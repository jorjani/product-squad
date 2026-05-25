# foreman#125 — auto-extract oversized bodies: codebase fit & seam analysis

Tightener: `@eng-deep-dive`
Issue: https://github.com/getqatalyst/foreman/issues/125

## Char-limit correction (load-bearing)

The issue body currently states `> 3000 chars` as the trigger. The canonical limit is **5000 chars hard, 4800 target**. /spec must replace every `3000` with the correct value before the contract closes.

Sources of truth:

- `Projects/.studio/guardrails/issue-conventions.md:11` — "Foreman-buildable issues (size XS/S/M): body ≤ 5000 chars. Hard limit." Reaffirmed at line 388 in the Enforcement section: "rejects > 5000 chars with `BUILD-OVERSIZED:`".
- `foreman/phases/build-ticket.sh:228` — runtime gate: `if [ "$BODY_CHARS" -gt 5000 ]; then ... BUILD-OVERSIZED: issue body is ${BODY_CHARS} chars (limit 5000)`.
- `sarge/CLAUDE.md:25` — Sarge target: "keep it under **4,800 chars** to leave headroom for triage comments."

Per-size budgets (issue-conventions.md:13) are tighter still: XS ≤ 500, S ≤ 1500, M ≤ 2500. Auto-extract should aim for the M ceiling (2500c) when slimming, not just "below 5000c." Treat 4800c as the *escalation* threshold, not the *target*.

The gap that bit sage#215 was that the 5000c gate at `build-ticket.sh:228` posts `BUILD-OVERSIZED:` and parks the issue in Ready, but no automation extracts content; the issue sits until David intervenes. This ticket closes that loop.

## Sarge vs Foreman ownership boundary

Sarge already enforces body-size pre-Backlog (`sarge/CLAUDE.md:24-34`, "Body Size Pre-check"). It is interactive, prose-checklist, and runs at the **Pitch → Backlog** transition during scope-time editing. Foreman currently has the *runtime gate* at `build-ticket.sh:228` but no *remediation*.

This ticket adds the remediation arm at a different point in the pipeline:

| Owner | Phase | Trigger | Output |
|---|---|---|---|
| Sarge (existing) | Pitch → Backlog | Body about to exceed 2500-4800c at scope time | Inline scope-time slimming + spec doc |
| Foreman triage (existing) | Backlog → Ready | NEEDS-SPEC criterion #0 size check | `NEEDS-SPEC: extract-to-spec-doc` comment |
| Foreman build pre-flight (existing) | Ready → In Progress | `wc -c > 5000` at build-ticket.sh:228 | `BUILD-OVERSIZED:` + `oversized` label |
| Foreman auto-enrich (this ticket) | post-Triage / post-BUILD-OVERSIZED | `oversized` label OR `BUILD-OVERSIZED` comment present | Spec doc commit + body slim |

Why both Sarge and Foreman: bodies bloat **after** Backlog too. Comment-driven enrichment (auto-enrich's existing Scope-fill mode) can copy verbose NEEDS-SPEC feedback into the body. David edits live tickets from his phone and may inline a SQL block. The Sarge pre-check fires at one moment in the lifecycle; this ticket extends the same rule mechanically at a later moment.

Per `Projects/CLAUDE.md` no-cross-repo-duplication rule: Sarge owns the *rule text* (target ≤4800, what to extract — see issue-conventions.md "What DOES NOT belong" list at line 313). Foreman has the first *executable implementation* of that rule. No code duplication; both reference the same guardrail.

## auto-enrich.sh column-filter change

Currently at `phases/auto-enrich.sh:74`:

```python
if item.get('status', '') != 'Scope':
    continue
```

This filter rejects Ready items. The ticket's AC #1 says enter the loop also "when issue body chars > 3000 OR last NEEDS-SPEC body contains `BUILD-OVERSIZED` or `extract-verbose-content-to-spec-doc`."

Recommended seam: **two separate query passes**, not a collapsed filter.

```python
# Pass 1 (existing): Scope items with NEEDS-SPEC comments (fill-mode)
# Pass 2 (new):      Ready items with `oversized` label OR BUILD-OVERSIZED comment (extract-mode)
```

Risks of collapsing into one filter:

1. A misplaced `or` could skip every Scope item silently (the Python `continue` triggers for both arms if the condition is mis-parenthesized).
2. Conversely, if the body-char check fires on Scope items, auto-enrich would attempt extraction on tickets that haven't yet been spec'd — destroying enrichment work-in-progress.

Cleanest implementation: keep the existing Scope→fill loop (`SCOPE_ITEMS` block at lines 69-89), then below it add a parallel `OVERSIZED_ITEMS` block with its own status filter (`status == 'Ready'`) and its own enrichment branch. Each item runs through one mode only; the modes are mutually exclusive per AC #6.

**Loop budget:** AC says "smoke test on a real oversized issue." Today the steady-state count of Ready+oversized items is small (sage#215 was a single instance over 3 days). Cap at **3 extractions per cycle**. Each extraction is one Claude call (~$0.15-0.30 at the current AUTO_ENRICH_BUDGET) plus one git push. Three is enough for the realistic worst case (multi-issue spike) without blowing budget if the trigger condition fires falsely.

## Prompt schema change

Current prompt at `prompts/auto-enrich.md:54`:

```json
{"updated_body": "...", "changes_made": ["..."]}
```

Extract-mode needs:

```json
{"updated_body": "...", "spec_doc_filename": "<num>-<slug>.md", "spec_doc_content": "---\nissue: <num>\nstatus: approved\n---\n\n<markdown>", "changes_made": ["..."]}
```

**Recommendation: fork the prompt.** Create `prompts/auto-extract-oversized.md` rather than overload `auto-enrich.md`.

Justification:

1. The two paths have fundamentally different *inputs* (NEEDS-SPEC feedback vs `BUILD-OVERSIZED` body) and *outputs* (filled body vs slimmed body + new file). One prompt with conditional schema branches is brittle — Claude will skip the conditional half the time and return the wrong shape.
2. The instruction sets diverge: fill-mode references the Ready Checklist for what's missing; extract-mode references issue-conventions.md "What DOES NOT belong" for what to peel off. Mixing them dilutes both.
3. `auto-enrich.sh` already calls Claude once per item; selecting which prompt file to render is a single `if`-statement above the existing `sed` block (lines 215-218). Cheap to fork, expensive to merge.

The new prompt's instructions section must explicitly enumerate what gets extracted, sourced verbatim from `issue-conventions.md:313-323` ("What DOES NOT belong"): SQL > 10 lines, query results, decision matrices, sequence diagrams, ASCII > 30 lines (non-per-state), step-by-step rationales, verification runbooks. The prompt instructs Claude to *move* these out, replace with a one-line `Spec: <absolute URL>` reference, and verify the slimmed body fits under 4800c.

## Spec-doc commit step

Mechanic per `spec-commits.md` and `Projects/CLAUDE.md` "Spec File Commits":

1. Resolve `PROJECT_DIR` via existing `repo_to_dir` lookup (`auto-enrich.sh:25-34`).
2. Write `<PROJECT_DIR>/specs/<num>-<slug>.md` with frontmatter `issue: <num>, status: approved`.
3. `cd "$PROJECT_DIR" && git add specs/<num>-<slug>.md` (explicit path; never `-A` per `feedback_dont_remove_shared_fields` and Projects/CLAUDE.md rule "NEVER COMMIT -A").
4. `git commit -m "specs(<num>): <slug from title>"` per spec-commits.md:19 message format.
5. `git fetch origin main && git rebase origin/main` (defense against parallel commits during the cycle).
6. `git push origin main`.
7. `gh issue edit <num> --repo <repo> --body "<slimmed_body>"` where slimmed body includes `Spec: https://github.com/<org>/<repo>/blob/main/specs/<num>-<slug>.md` per the absolute-URL rule (issue-conventions.md:294-301).
8. Post-edit verification: re-fetch body, `wc -c` < 5000. If fail → `comment_dedup_or_escalate` with ESCALATE-DEDUP context `auto-extract-oversized`.
9. Per `feedback_no_ceremonial_comments`, **do NOT post a `SPEC-UPDATED` comment**. The body's new `Spec:` link is the contract. The git activity log + label removal carry the rationale. AC #5 of the current issue body says to post SPEC-UPDATED; /spec should drop that requirement.
10. `gh issue edit <num> --repo <repo> --remove-label "oversized"` so build-ticket's pre-flight stops re-firing on the next cycle.

**Worktree risk.** Foreman's *build* phase runs in worktrees (`build-ticket.sh:76` creates `/tmp/foreman-build-*`), but auto-enrich does NOT use worktrees — it operates against the project main checkouts directly (it never modifies code; only fetches issue body via `gh` and posts comments). So the spec-doc commit step in this ticket runs in the main checkout naturally. No workaround needed.

But: the existing `phases/auto-enrich.sh` does not currently `cd` into project dirs; it only reads context files. Adding `git add/commit/push` to `$PROJECT_DIR` is a new side-effect class. Document explicitly: this phase now mutates project repos. Affects `getqatalyst/Sage`, `getqatalyst/coaches`, `getqatalyst/Jobber`, `getqatalyst/product-studio`, `getqatalyst/reap` (per `ELIGIBLE_REPOS` at line 17).

**Recommendation: run extraction against the existing main checkouts** (the `repo_to_dir` mapping already points there), NOT in any worktree. Verified safe because main checkouts of these repos are auto-enrich's read targets today; promoting them to commit targets is additive.

## Slug generation + collision

Slug derivation: lowercase issue title, alnum-to-dash, max 40 chars. Same algorithm as `build-ticket.sh:67`:

```
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 40)
```

Reuse this exact pattern — don't reinvent.

Collision handling:

1. **File already exists at `<PROJECT_DIR>/specs/<num>-<slug>.md`.** Auto-extract should be idempotent on the same issue (see "Idempotency" below), so a same-issue rerun finding its own file is fine — overwrite with the new content. Detect via `git log --oneline -1 -- specs/<num>-<slug>.md`; if the last commit author is the foreman bot AND the issue number matches, overwrite.
2. **Different issue, same slug.** E.g., issue #200 "fix the login bug" and #312 "fix the login bug — round two." `<num>` prefix prevents collision because filenames are `200-fix-the-login-bug.md` vs `312-fix-the-login-bug.md`. Numeric prefix is the disambiguator.
3. **Pathological: unrelated issue, identical num+slug.** Vanishingly rare. Fall back to numeric-only filename `<num>.md` if `git status --short specs/<num>-<slug>.md` shows untracked-with-different-content. If still ambiguous, escalate via `ESCALATE-DEDUP` context `auto-extract-slug-collision` and skip this issue.

## Idempotency on re-run

Per the issue body's spirit (smoke test #7d says "second invocation is a no-op"):

Pre-check at the top of the extract branch — before the Claude call:

```bash
BODY_CHARS=$(printf '%s' "$ISSUE_BODY" | wc -c | tr -d ' ')
if [ "$BODY_CHARS" -le 4800 ]; then
  # Already slimmed; remove `oversized` label if still present and skip.
  gh issue edit "$ISSUE_NUM" --repo "$REPO" --remove-label "oversized" 2>/dev/null || true
  continue
fi
```

The 4800c threshold (not 5000) is the no-op cutoff: a body at 4900c would re-trigger build-ticket's 5000c gate, so we treat anything in the 4800-5000 band as "still oversized; rerun extraction."

Second guard: if the body already contains a `Spec:` line referencing a `specs/<num>-` file in the project repo, skip. The presence of the link IS the extraction marker.

## Failure modes + fallback

| Failure | Detection | Action |
|---|---|---|
| Claude returns slimmed body still > 5000c | `wc -c` after `gh issue edit` | `comment_dedup_or_escalate` context `auto-extract-still-oversized`. Don't loop. Don't `gh issue edit` to revert (the slim attempt may have improved it; leave it). |
| Claude returns spec_doc_content with no extractable signal | Empty `spec_doc_content` field in JSON | Skip this issue, log to `RESULT_FILE`, do NOT mutate body. |
| `git rebase origin/main` conflicts | Non-zero rc from rebase | `git rebase --abort`, retry once with fresh `git fetch`. If second attempt fails, `comment_dedup_or_escalate` context `auto-extract-rebase-conflict` and skip. Don't force-push. |
| `git push origin main` rejected | Non-zero rc | Treat same as rebase conflict (rare race; another agent pushed during the window). Retry once after rebase, then escalate. |
| `gh issue edit` fails after spec doc committed | Non-zero rc | LOG only. Do NOT retry (body may be partially mutated; retry could double-apply). The committed spec doc orphans temporarily but is harmless — it just isn't linked. Manual cleanup ticket. |
| Malformed Claude JSON | Existing parse-fail branch at `auto-enrich.sh:269-285` | Reuse existing `DECISION-NEEDED: Foreman auto-enrich could not parse...` comment with extra context that this was extract-mode. |

All escalations route through `comment_dedup_or_escalate` per `lib/comments.sh:121` — the existing `BUILD-OVERSIZED` and `NEEDS-SPEC` patterns are the precedent.

## Decisions locked (2026-05-07)

1. **Char limit is 5000 hard / 4800 target.** Replace all `3000` references in the issue body during /spec.
2. **Fork the prompt.** New file `prompts/auto-extract-oversized.md`; do not extend `auto-enrich.md`.
3. **Cap at 3 extractions per cycle** to bound budget exposure on a false-trigger spike.
4. **Run in main checkout, not in a worktree.** Auto-enrich already reads from main checkouts; promote the same paths to commit targets. Build phase's worktree pattern does not apply here.
5. **No `SPEC-UPDATED` comment after extraction.** Body's `Spec:` link + label removal + git history is the contract. Per `feedback_no_ceremonial_comments`. AC #5 in the current issue body must be revised to reflect this.
6. **Two-pass query, not collapsed filter.** Keep existing Scope→fill loop; add parallel Ready→extract loop below it. Modes mutually exclusive per AC #6.
7. **Reuse `build-ticket.sh:67` slug algorithm verbatim.** Don't re-derive.
8. **Idempotency cutoff at 4800c**, not 5000c. Anything in the 4800-5000c band re-runs extraction.
