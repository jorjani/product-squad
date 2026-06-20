---
name: worktree-cleanup
description: Prune merged git worktrees across every repo in a workspace, safely. Runs ordered gates per worktree (fresh <15m / empty / merged / unmerged / lock-alive / real-WIP) and removes ONLY worktrees whose branch is provably merged into main, never live, locked, dirty, or just-created ones. Distinguishes squash-merges (patch-id + PR-state checks) from fast-forwards. Uses an autonomous build agent's /tmp worktrees as the example of owned worktrees that get reported but never touched. Use to reclaim disk after PRs land. Pairs with /sync-repos and /guard.
---

# /worktree-cleanup — Prune Merged Worktrees Safely

Generic purpose: remove the git worktrees whose work has already landed in main, while never touching one that's live, locked by a running process, holding uncommitted work, too new to judge, or owned by another agent. Safe to run anytime — the only cost of a badly-timed run is churned results.

**This skill uses "an autonomous build agent" as the worked example** of a process that continuously creates and prunes its own `/tmp/<agent>-build-*` worktrees. If you run such an agent, those worktrees are **agent-owned**: report them, never remove them. If you don't, skip Step 0 entirely.

## Step 0 — Is an automated worktree-creator running?

An agent that spins worktrees up and down during a loop makes any sweep launched mid-loop see stale-on-arrival state:

```bash
agent_active=$(find /tmp -maxdepth 1 -type d -name '<agent>-build-*' -mmin -10 2>/dev/null | head -1)
```

Non-empty → tell the user the agent appears mid-loop, results will churn, recommend re-running when idle, proceed only if they confirm. Either way, `/tmp/<agent>-build-*` worktrees are agent-owned: evaluate and report, **never remove**.

## Per-repo sweep

For each repo under your workspace root:

1. `git -C <repo> fetch origin main -q`
2. `git -C <repo> worktree prune` (drop stale pointers)
3. `git -C <repo> worktree list`
4. For each non-main worktree, run the gates **in order**. Each sets `class` to `fresh` / `empty` / `merged` / `unmerged`; the first gate that resolves to KEEP short-circuits. Only `class=merged` reaches removal.

### Gate 0 — Freshly created? (KEEP if so)

A worktree created in the last 15 minutes is almost certainly live or just-spawned — even if it currently looks merged and clean, because a brand-new branch is trivially an ancestor of main and its tree is clean for the seconds between `git worktree add` and the first edit.

```bash
fresh=$(find "<wt_path>" -maxdepth 0 -mmin -15 2>/dev/null)
```

Non-empty → `class=fresh`, KEEP, reason `fresh (<15m old)`, skip the rest.

### Gate A — Merged, or empty?

"Merged" means *the work in this worktree is now in main*. A branch with no commits of its own has nothing to merge — it's `empty`, always kept. Count the branch's own commits first:

```bash
ahead=$(git rev-list --count origin/main..<branch> 2>/dev/null)
```

`git rev-list` errors if `origin/main` is missing (failed fetch, or default branch is `master`) or HEAD is detached. Empty `ahead` (non-zero exit) → inconclusive → treat as `unmerged` and KEEP.

- **`ahead == 0`** — no commits beyond main: EITHER merged OR fresh/empty, and the commit graph can't tell them apart. Run **only the PR-state check** below: merged PR → `class=merged`; none → `class=empty`, KEEP (reason `empty (no commits, no merged PR)`). **Never** treat a bare `git merge-base --is-ancestor` as merged — a fresh branch satisfies it identically. That false positive is the bug this gate exists to prevent.

- **`ahead > 0`** — branch has its own commits. `class=merged` if either check passes, else `unmerged`; cheap local check first:
  - **Patch-id** (single-commit squash — branch commit's patch equals the squash commit's):
    ```bash
    unique=$(git cherry origin/main <branch> | grep -c '^+')
    total=$(git cherry origin/main <branch> | wc -l)
    # merged if total > 0 AND unique == 0
    ```
  - **PR-state** (multi-commit squash folds N diffs into ONE main commit, so no patch-id matches; also the only check for `ahead == 0`):
    ```bash
    repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
    merged_at=$(gh pr list --repo "$repo" --state merged --base main --head <branch> --json mergedAt --jq '.[0].mergedAt // empty' 2>/dev/null)
    # merged if merged_at is non-empty
    ```
    `gh` unauthenticated / API fails → inconclusive: `ahead>0` falls to `unmerged`, `ahead==0` falls to `empty` (no positive signal → keep).

### Gate B — Lock alive? (KEEP if so)

A `locked` file alone isn't a reason to keep — verify the holder is alive; dead-pid locks are stale.

```bash
lock_file="<repo>/.git/worktrees/<wt_name>/locked"
if [ -f "$lock_file" ]; then
  pid=$(grep -oE 'pid [0-9]+' "$lock_file" | grep -oE '[0-9]+' | head -1)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then lock_state="alive"; else lock_state="stale"; fi
else lock_state="none"; fi
```

`alive` → KEEP, reason `lock-alive (pid {n})`.

### Gate C — Real WIP? (KEEP if so)

Don't conflate gitignored build artifacts with user work. (Use `wt_status`, not `status` — `$status` is read-only in zsh.)

```bash
cd <wt_path>; wt_status=$(git status --porcelain); has_wip="no"
# Tracked changes (any line NOT starting with ??) = real WIP.
if [ -n "$wt_status" ] && echo "$wt_status" | grep -vq '^??'; then has_wip="yes"; fi
# Untracked (?? lines) count only if NOT gitignored. Check the worktree's own .gitignore;
# if class=merged + lock not alive, also cross-check main's .gitignore (artifact from an
# older branch whose .gitignore predates a tightening commit → OK to drop).
```

## Decision

- **`class=merged` AND not an agent-owned `/tmp` worktree AND `lock_state` in (none, stale) AND `has_wip=no`** → remove. Unlock a stale lock first (`--force` alone won't override a `locked` file):
  ```bash
  [ "$lock_state" = "stale" ] && git worktree unlock <path>
  git worktree remove <path> --force && git branch -D <branch>
  ```
- **otherwise** → keep, reporting one reason (priority order): `fresh (<15m old)` · `empty (no commits, no merged PR)` · `unmerged` · `lock-alive (pid {n})` · `uncommitted (<reason>)` · `agent-owned`.

## Report

How many removed, how many kept (branch + specific reason). Flag stale-lock auto-cleanups separately — recurring orphan locks are worth noticing.

## Never delete

Unmerged work · worktrees with real WIP · worktrees <15 min old · empty worktrees (no commits of their own) · agent-owned `/tmp` worktrees. Stale locks (dead pid) and gitignored artifacts do **not** count as reasons to keep.

## Neighbors

- [`sync-repos`](../sync-repos/SKILL.md) — fast-forward every repo before pruning, so merge detection sees fresh `origin/main`.
- [`guard`](../guard/SKILL.md) — destructive-command confirmation; pairs with the never-delete rules above when running in a sensitive workspace.
