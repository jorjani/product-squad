# foreman#210 — code-reviewer phase: AC check + auto-merge gate

Issue: https://github.com/getqatalyst/foreman/issues/210
Parent: #106 (orchestrator v0, shipped)
Sibling: #209 (Inspector v1 — owns Verify→Done; this issue owns In Review→Verify for non-`auto/*` PRs)
Related: #272 (central orchestration event log — auto-merge events should write there when shipped)

This doc carries WHY-was-decided-this-way and implementation detail. The issue body carries WHAT/WHY only.

---

## 1. Today's baseline (what already works)

`phases/code-review.sh` (235 LOC, last touched 2026-05-16 20:00) — runs daily across `eligible_repos() + getqatalyst/foreman`, dispatches the `code-reviewer` subagent (`Projects/.claude/agents/code-reviewer.md`) on each open non-draft PR that doesn't already have a `REVIEWER:` comment. Subagent returns `{"findings":[...], "verdict":"LGTM|LGTM with nits|Needs changes|Blocked"}` via the `[FOREMAN]` JSON contract (`foreman/prompts/code-review.md`). Phase parses, formats Blockers/Majors/Nits, posts `REVIEWER: <verdict>` comment. **No merge, close, label, or board mutation.**

Evidence the phase runs successfully in prod: foreman#265 and reap#48 both reviewed today (2026-05-16), findings posted, no errors.

`phases/review.sh` already auto-merges `auto/*` PRs via the embedded review-subagent flow (L264-269), then calls `move_to_verify` (L280) and `cleanup_merged_worktrees`. Non-`auto/*` PRs are reviewed (informational comment) but never merged by Foreman.

Orchestrator dispatch order (from `orchestrator.sh`): `inspect.sh` + `code-review.sh` run in parallel as siblings, the orchestrator **waits for both**, then runs `review.sh` (`run_bounded 900`). No race between this phase and `review.sh`.

---

## 2. What #210 adds

After `code-review.sh` posts the `REVIEWER:` comment, classify the PR against the linked issue's AC. If gates pass, merge.

### 2A. AC-match classifier

Inputs: PR diff, linked issue's body AC bullets.
Output: `ac_match: AC-MATCH | AC-MISMATCH | AC-UNCHECKED`, plus per-bullet rationale (≤140c each, capped at 5 bullets surfaced).

**Decision needed from David before build:** reuse Inspector v1's LLM-judge classifier (`prompts/inspect-judge.md`, see `specs/209-inspector-v1.md` §2A) or fork. Tradeoff:

- **Reuse.** Same Sonnet T=0 + structured schema. But Inspector judges **deployed state** (Playwright capture + grep evidence). #210 judges a **pre-merge diff**. Same prompt won't fit cleanly; would need a "mode" flag and an alternate evidence section. Couples two phases that today are independent.
- **Fork.** New `prompts/code-review-ac-judge.md`. Sonnet T=0, structured output, judges "does this diff satisfy this bullet." Cleaner separation; cheap. Schema can borrow Inspector's contract.

Recommend **fork** (separation of concerns; diff-vs-state is a meaningful split), but surface for David.

### 2B. Merge eligibility (the gate)

Merge the PR via `gh pr merge $PR_NUM --repo $REPO --squash --auto` if **all** are true:
1. `REVIEWER:` posted with `verdict ∈ {LGTM, LGTM with nits}` AND `findings[].severity` contains zero `blocker`.
2. `ac_match: AC-MATCH`.
3. CI status: `SUCCESS` (use the same gating-vs-advisory classifier in `phases/review.sh` L341-365 — extract to `lib/ci-status.sh` as a small refactor or duplicate inline).
4. Repo opt-in (see 2D).

Merge strategy: `--squash` by default; reading per-repo `.github` config is out of scope for v1 (most repos squash; explicit per-repo override deferred until a real exception appears).

On merge success: extract linked issue via `extract_linked_issue` (defined in `review.sh:50` — extract or duplicate; do NOT call the function across phase boundaries) and call `move_to_verify` (`config/board-ids.sh:208`). Also call `cleanup_merged_worktrees` to maintain parity with `review.sh`.

### 2C. Authorization model

**Decision needed from David before build.** Extending `gh pr merge` to non-`auto/*` PRs touches two new author classes:

- **David's manual PRs.** He hand-writes them. Should LGTM+AC-MATCH alone gate merge, or also require a manual approval flag (PR label `foreman-merge-ok`, body marker, etc.)?
- **External / human contributor PRs.** Same question, higher stakes.

Default proposal for first cut: merge **only** if PR author is in an allowlist. Allowlist v1 = `["jorjani"]` (hardcoded in `lib/repos.sh` or `config/automerge-allowlist.sh`). Foreman never auto-merges PRs from authors outside that list — comment posted instead, classified as `DECISION-NEEDED:` on the issue. Expand allowlist explicitly when David wants.

Alternative David might prefer: no allowlist; trust the gates (LGTM + AC-MATCH + CI green); explicit opt-out per repo (see 2D).

### 2D. Repo opt-out

Mirror the `board.foreman_build` flag pattern (already implemented at `lib/repos.sh:79-96`). New field: `board.code_review_automerge` in `Projects/.index.json`. Default: `false` (fail-closed — opt-in per repo). New helper `repo_code_review_automerge_enabled <owner/repo>` returns `"true"|"false"` from the index. `code-review.sh` skips the merge gate when `false`, still posts findings.

`getqatalyst/foreman` itself: opt-in **true** (Foreman self-merges its own AC-MATCH PRs).

### 2E. AC-MISMATCH path

If classifier returns `AC-MISMATCH`, do NOT merge. Post a `DECISION-NEEDED:` comment on the linked issue (via `comment_dedup_or_escalate`, `lib/comments.sh:126`, context label `code-review-ac-mismatch`) naming the failing bullets. PR stays open. David's call to either patch the PR or update the AC.

### 2F. Event log integration (deferred)

When #272 (central event log) ships, the auto-merge action emits an event: `{phase: "code-review", action: "auto-merged", repo, pr, issue, ac_match: "AC-MATCH", author}`. Until then: standard log line in `results/$DATE.log` (matches `phases/review.sh` conventions, e.g. `[$REPO] PR #$PR_NUM AUTO-MERGED (AC-MATCH, author=...)`).

---

## 3. T1d verification contract

Each AC row below maps to evidence Inspector v1 (when #209 ships) walks against #210's merged code.

| State / change | Trigger / observable | Pass evidence |
|---|---|---|
| AC-MATCH + LGTM + CI green on allowlisted author → merge fires | Open PR meeting all gates from allowlisted author | `gh pr merge --squash` exit 0; PR state MERGED; `move_to_verify` called; board column advances In Review→Verify |
| AC-MISMATCH → no merge | Open PR with diff that misses an AC bullet | `DECISION-NEEDED: code-review-ac-mismatch` on linked issue; PR remains OPEN; no merge mutation in log |
| Blocker finding → no merge | `REVIEWER:` comment has any `severity: blocker` finding | PR remains OPEN; no merge attempt logged |
| Non-allowlisted author → no merge | PR author not in `code_review_automerge` allowlist | Findings comment posts as today; no merge attempt; log entry `SKIP: author not in allowlist` |
| Repo opt-out → no merge | `board.code_review_automerge: false` (or missing) | Phase still posts findings; no merge attempt; no AC-classifier dispatch (cost saving) |
| AC-UNCHECKED (no linked issue or no AC bullets) → no merge | PR body lacks `Closes #N` or linked issue body has no AC | Findings posted; no merge; log entry `SKIP: AC-UNCHECKED` |
| Re-run safety | Same PR walked twice on consecutive ticks | Existing `REVIEWER:` comment dedups; no double-merge; idempotent (PR already MERGED on second pass) |
| Kill switch | `CODE_REVIEW_DISABLE_AUTOMERGE=1` env | Phase reverts to comment-only behavior (today's prod path); no merge regardless of gates |

---

## 4. Hardest unknowns (carried into Backlog gate)

1. **AC-classifier reuse vs fork (Inspector v1).** Decision in 2A. Defaults to **fork** in this spec; David confirms before build. Coupling cost vs duplication cost. → `@eng-deep-dive` if David wants reuse, otherwise default-fork is cheap.
2. **Authorization model for non-`auto/*` merges.** Decision in 2C. Defaults to **allowlist v1 = [jorjani]**. David's call. → DECISION-NEEDED on body before Backlog.
3. **Merge strategy per repo.** Squash assumed. If a repo standardizes on merge-commit or rebase-merge, the hardcoded `--squash` flag drops branch info. Probability low (no current eligible repo deviates); cost of fix later trivial (read `gh api repos/$REPO --jq .merge_commit_allowed`). → defer until first exception surfaces.

---

## 5. Out of scope

- Multi-pass review (security/perf/UX layers). Single severity-tier pass remains.
- Auto-fixing the PR. If AC-MISMATCH, post comment; do not edit code.
- Editing `phases/review.sh` to drop its `auto/*` auto-merge path. That path is shipping and unchanged.
- Cross-repo merge strategy detection (see §4-#3).
- AC-coverage *map* (per-line attribution). Per-bullet PASS/FAIL only.
- Re-trigger code-review on push (today: skipped if any `REVIEWER:` comment exists — `phases/code-review.sh:78-84`). v1 keeps that. If a builder pushes a fix after AC-MISMATCH, Inspector v1's `move_to_scope` flow re-opens the issue and code-review fires fresh on the next PR.
- Integration with `phases/repair.sh`. AC-MISMATCH does NOT trigger auto-repair; David's call to patch.

---

## 6. Helpers / files to reuse

- `comment_dedup_or_escalate` — `lib/comments.sh:126`. Use for `DECISION-NEEDED:` on AC-MISMATCH.
- `move_to_verify`, `move_to_scope` — `config/board-ids.sh:208,221`. Post-merge board mutation.
- `extract_linked_issue` — `phases/review.sh:50`. Duplicate to `code-review.sh` or extract to `lib/pr.sh` (small refactor, fine either way).
- `cleanup_merged_worktrees` — `phases/review.sh:163`. Same parity; duplicate or extract.
- CI status classifier — `phases/review.sh:341-365` (advisory-vs-gating split, ADVISORY_CHECKS_JSON). Definitely extract to `lib/ci-status.sh` since two phases now want it.
- `repo_foreman_build_enabled` — `lib/repos.sh:82-96`. Pattern template for new `repo_code_review_automerge_enabled`.
- Model routing — `config/model-routing.sh`. New env var `CODE_REVIEW_AC_MODEL` (default Sonnet, T=0).

---

## 7. Acceptance for ready-to-build (Foreman's triage gate)

Hardest unknowns 1 + 2 resolved (David picks one path each). Hardest unknown 3 deferred OK. Spec doc updated with David's picks before Foreman moves to Ready.
