# foreman#203 — normalize .index.json codes + worktree naming rule

Issue: https://github.com/getqatalyst/foreman/issues/203

## Convention

- **Project code** = first 4 letters of the project key, uppercased, hyphens stripped.
- **Worktree name** = `<code-lowercase><issue>-<slug>` (lead issue for multi-repo work; `<code>-<slug>` for exploratory).

## Changes applied

In `~/Projects/.index.json` (canonical registry):

| project       | old   | new   |
|---------------|-------|-------|
| sarge         | SRGE  | SARG  |
| foreman       | FRMN  | FORE  |
| sourcerer     | SRCR  | SOUR  |
| grant-finder  | GRNT  | GRAN  |

Other board-eligible codes (SAGE, JOBB, COAC, PROD, MAST) already matched the rule, no change.

Worktree-naming sentence appended to `~/Projects/CLAUDE.md` Rule 3.

## Out of scope

- Non-board-eligible codes (CNTN, IMMG, METR, PULS, ATHN, etc.) — followup if full uniformity is wanted.
- Renaming existing live worktrees — new format applies to new worktrees only.
- Create-time enforcement (linter/hook) — behavioral rule first.

## Foreman impact

Foreman scripts read `.index.json` for `board.project_number` / `agents` fields. The `code` field is not consumed by any foreman phase (verified via `grep -rn "code" phases/`). Foreman's own build worktrees (`/tmp/foreman-build-<repo>-<issue>`) are unaffected; the new convention targets human-created worktrees only.

Status-line topic files (`/tmp/claude-topic-*`) read `code` and will refresh on next status-line update — one stale read per active session, acceptable churn.
