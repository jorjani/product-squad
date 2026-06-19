---
name: pr-review
description: Open-PR review queue for one or more repos — fetch the open PRs, categorize (needs your review / yours approved / yours waiting), present a dashboard, then deep-review each via subagents on a two-pass checklist (hygiene + structural bugs that pass CI). Presents findings and waits — never submits a review or merges without explicit instruction. Use for a morning PR sweep. Distinct from /eng-review (which challenges an impl plan before code) — this one reviews shipped diffs.
---

# /pr-review — Open-PR Review Queue

Scan open PRs across one or more repos, categorize them, run a standard checklist on each PR needing review, and present a unified dashboard. You do NOT submit reviews or make decisions — you present, the user acts.

**Usage:** `/pr-review` (current repo) or `/pr-review owner/repo [owner/repo ...]` (explicit list).

---

## Step 0: Resolve Repos & Owner

- **Repos:** if `$ARGUMENTS` names one or more `owner/repo`, use those. Otherwise default to the current repo (`gh repo view --json nameWithOwner`).
- **Owner login:** the login whose PRs are "yours" vs. "others'." Default to the authenticated user (`gh api user --jq .login`); override if the user names a different owner.
- **Optional self-review exclude:** the user may name repos whose own-authored PRs should appear on the dashboard but NOT be auto-dispatched to a reviewer subagent (e.g. repos already covered by another review process). Default: empty — review everything.

Build a flat list of `{repo}` targets.

---

## Step 1: Fetch PR Queue (parallel)

For EACH repo, run in parallel:

```bash
gh pr list --repo {owner/repo} --json number,title,author,body,reviewDecision,createdAt,headRefName,isDraft,reviews,labels --limit 30
```

**Filter out:** draft PRs (`isDraft: true`), and bot PRs (`author.login` is `app/dependabot`, `dependabot[bot]`, or `renovate[bot]`).

**Categorize into three buckets** (let `OWNER` = the login from Step 0):

1. **Needs my review** — PRs by others (not `OWNER`) where `OWNER` has NOT already submitted a review.
2. **My PRs — approved** — PRs by `OWNER` with `reviewDecision: APPROVED` (ready to merge).
3. **My PRs — waiting** — PRs by `OWNER` without approval yet.

If all repos return zero PRs after filtering, say "No open PRs. Clean slate." and stop.

---

## Step 2: Present the Dashboard

One unified view, grouped by bucket, sorted by age (oldest first):

```
## PR Dashboard

### Needs My Review ({count})
| Repo | PR | Author | Title | Age | Flags |

### My PRs — Ready to Merge ({count})
| Repo | PR | Title | Approver | Age |

### My PRs — Waiting for Review ({count})
| Repo | PR | Title | Age | Flags |
```

**Flags:** `✗ No desc` (empty body) · `✗ No issue` (no `#nnn` in title or body) · `⚠ Stale` (age > 7 days).

Compute the **auto-review set**: all PRs in *Needs my review*, plus *Waiting-for-review* self-PRs whose repo is not in the optional exclude list. State: "**{N} PRs to review** ({M} from others, {K} self-PRs for second eyes)." If empty, skip to Step 4.

---

## Step 3: Per-PR Deep Review (subagents)

For each PR in the auto-review set, launch a subagent (Task tool, `subagent_type: general-purpose`). **Cap at 3 parallel**; batch in groups of 3 if more.

For a self-authored PR, prepend: `NOTE: authored by the repo owner, who wants a second pair of eyes before merge. Skip checks 1-2 (issue link / description) if both are already present.`

### Subagent Prompt Template

```
Review this pull request. Fetch the diff, run the checklist, return structured findings.

REPO: {owner/repo}
PR NUMBER: {number}
PR TITLE: {title}
PR AUTHOR: {author}
PR BODY: {body or "(empty)"}

## Fetch
gh pr diff {number} --repo {owner/repo}
gh pr view {number} --repo {owner/repo} --json commits --jq '.commits[].messageHeadline'
# Prior formal reviews (exclude the owner's own):
gh pr view {number} --repo {owner/repo} --json reviews \
  --jq '.reviews[] | select(.author.login != "OWNER") | {author: .author.login, state: .state, body: .body}'
# Inline line-level comments (where bots like Copilot leave feedback):
gh api repos/{owner/repo}/pulls/{number}/comments \
  --jq '.[] | {author: .user.login, path: .path, line: .line, body: .body}'

## Pass 0: Prior Reviewer Context
For each prior comment: validate against the actual diff. If a real bug, include it in Findings and credit the source ("Copilot flagged: ..."). If a false positive or already addressed, note it briefly so the human sees you considered it. A prior reviewer is a hint, not a verdict — your structural pass is the source of truth. Don't re-flag what a prior reviewer already caught — cite it.

## Pass 1: Hygiene Checklist
| # | Check | Look for |
|---|-------|----------|
| 1 | Linked to issue | #nnn in title or body |
| 2 | Description non-empty | body not blank |
| 3 | No debug artifacts | console.log, debugger, <<<, >>>, TODO, FIXME in added lines |
| 4 | No commented-out code | blocks of // or /* */ wrapping real code in added lines |
| 5 | No lint disables | eslint-disable, @ts-ignore in added lines |
| 6 | No dead code | unused imports, unreachable code in added lines |
| 7 | No secrets | API keys, tokens, passwords, .env values in added lines |
| 8 | Commit messages meaningful | not just "commit", "fix", "wip", "update" |

## Pass 2: Structural Review (bugs that pass CI)
Read the full diff. For each NEW codepath:
| #  | Check | Look for |
|----|-------|----------|
| 9  | Error handling | caught errors silently swallowed? empty catch? catch(e){} with no logging? |
| 10 | Trust boundaries | user input into DB queries, shell commands, or HTML without validation/escaping? |
| 11 | N+1 queries | new DB calls inside loops? missing includes/preloads? |
| 12 | Race conditions | shared mutable state? read-then-write without locking? |
| 13 | Missing null checks | new .property access on values that could be null/undefined? |
| 14 | Silent failures | async ops with no error path? promises without catch? fire-and-forget that should confirm? |
Only flag issues you can point to in the diff. No speculative concerns.

## Fix-First Heuristic
Classify each finding: AUTO-FIX (dead console.log, unused imports, stale comments, formatting) vs ASK (architecture, ambiguous error handling, possibly-intentional races, anything that changes behavior).

## Return Format (use EXACTLY this)
### {REPO_SHORT} #{number} — {title} ({author})
**Issue:** ✓ #{issue} / ✗ None | **Files:** {count} | **+{add}/-{del}**
**Hygiene:** [x]/[ ] for checks 1-8, brief detail on failures
**Structural:** [x]/[ ] for checks 9-14 (or "Clean — no structural issues")
**Prior reviewer context:** [N items: M valid kept / K dismissed — reason] (or "none")
**Findings:** numbered, one line each — blocker / nit [source] (or "Clean")
**Auto-fixable:** one line each — what to fix (or "None")
**Context:** 1-2 sentences on what this PR does

## RULES
- Findings ONE LINE each. Blockers first, then nits.
- Only flag at >80% confidence. No speculative or stylistic concerns.
- Same pattern in N files = one finding with a count, not N findings.
- Do NOT recommend approve/request-changes. Do NOT submit any review. Do NOT edit files.
```

Collect all reports and present sequentially, grouped by repo.

---

## Step 4: Summary + Actions

```
## Review Summary
| Repo | PR | Checklist | Blockers | Nits | Action needed? |

## Ready to Merge
| Repo | PR | Title |

## Actions — tell me what to do:
- "approve {repo} #{n}"                  → submit approval
- "approve {repo} #{n} with comment: ..." → approve with comment
- "request changes {repo} #{n} — ..."     → request changes
- "comment {repo} #{n} — ..."             → post comment only
- "merge {repo} #{n}"                     → squash merge + delete branch
- "autofix {repo} #{n}"                   → apply auto-fixable findings and commit
- "skip"                                  → done for now
```

Wait for instruction before taking ANY action on GitHub.

**Executing actions:**
- approve: `gh pr review {n} --repo {owner/repo} --approve --body "{comment}"`
- request changes: `gh pr review {n} --repo {owner/repo} --request-changes --body "{feedback}"`
- comment: `gh pr comment {n} --repo {owner/repo} --body "{note}"`
- merge: `gh pr merge {n} --repo {owner/repo} --squash --delete-branch`

After each action, confirm and offer the next.

---

## What This Does NOT Do

- Submit reviews without explicit instruction.
- Recommend approve vs. request-changes.
- Auto-merge anything.
- Review dependabot/renovate PRs.

$ARGUMENTS
