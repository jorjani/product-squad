---
name: sync-repos
description: Fast-forward every git repo under a workspace folder in one sweep. For each repo, fetch origin and pull --ff-only when the branch is clean and behind; everything else (ahead, diverged, dirty, detached, fetch-failed) goes to a report for the human to decide. Never stashes, rebases, merges, or force-pushes. Set the workspace root via the WORKSPACE_ROOT env var or the first argument (defaults to ~/Projects). Use to consolidate state after several sessions or PR merges land. Pairs with /checkpoint (snapshot before sweeping) and /pickup (resume once synced).
---

# /sync-repos — Fast-Forward the Workspace

Sync the current branch with origin across every repo in a workspace folder. Fast-forwards where safe; surfaces anything that needs human judgment.

**Usage:** `/sync-repos` (uses `WORKSPACE_ROOT`, default `~/Projects`) or `/sync-repos /path/to/workspace`.

## What this does

For each repo under the workspace root that has its own `.git` (depth ≤ 4, excluding `node_modules`, worktrees, and any parked directories you configure):

1. Skip the repo if its working tree has uncommitted **tracked-file** changes (modified/added/deleted/renamed/unmerged). Untracked files (`??`) alone don't count as dirty — they can't conflict with a fast-forward, and treating local artifacts as in-flight work is over-cautious.
2. Skip if HEAD is detached or the branch has no upstream tracking.
3. Run `git fetch --quiet` against origin. If `gtimeout` or `timeout` is available (macOS needs `brew install coreutils` for `gtimeout`), wrap with a 15-second timeout so a flaky remote can't stall the whole sweep.
4. Compute ahead/behind counts vs upstream.
5. If clean+behind: fast-forward (`git pull --ff-only`).
6. If ahead/diverged/dirty/failed: report and leave alone.

## Discovery

```bash
WORKSPACE_ROOT="${1:-${WORKSPACE_ROOT:-$HOME/Projects}}"
repos=()

# Parent workspace repo (if it has its own .git)
[ -d "$WORKSPACE_ROOT/.git" ] && repos+=("$WORKSPACE_ROOT")

# Sibling and nested repos: any subfolder with its own .git, depth ≤ 4.
# Excludes: node_modules (transitive deps) and worktrees (siblings of the
# main checkout, would double-count). Add your own -not -path globs for any
# parked directories you don't want swept.
while IFS= read -r git_dir; do
  repos+=("$(dirname "$git_dir")")
done < <(find "$WORKSPACE_ROOT" -maxdepth 4 -type d -name ".git" \
  -not -path "*/node_modules/*" \
  -not -path "*/.claude/worktrees/*" \
  2>/dev/null | sort)

# Pick a timeout wrapper that exists; fall back to no-timeout if neither is
# installed (macOS default has neither — `brew install coreutils` provides
# gtimeout). Without this guard, `timeout` would resolve to "command not found"
# and `git fetch` would silently never run.
TIMEOUT_CMD=""
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout 15"
elif command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout 15"
fi
```

## Per-repo sweep

Run sequentially (parallelism would interleave output and a single slow fetch only delays one repo's report). Uses `git -C "$repo"` throughout so the caller's CWD is never modified:

```bash
synced=()
ahead=()
diverged=()
dirty=()
skipped=()
failed=()

for repo in "${repos[@]}"; do
  name=$(basename "$repo")

  # Dirty = tracked-file changes (M/A/D/R/C/U). Untracked-only working trees
  # (?? lines) can FF cleanly, so don't block on local artifacts/logs.
  if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null | grep -vE '^\?\? ')" ]; then
    dirty+=("$name")
    continue
  fi

  current_branch=$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$current_branch" ]; then
    skipped+=("$name (detached HEAD)")
    continue
  fi

  if ! git -C "$repo" rev-parse --abbrev-ref "${current_branch}@{upstream}" >/dev/null 2>&1; then
    skipped+=("$name on $current_branch (no upstream)")
    continue
  fi

  $TIMEOUT_CMD git -C "$repo" fetch --quiet 2>/dev/null
  fetch_exit=$?
  if [ "$fetch_exit" -eq 124 ]; then
    failed+=("$name on $current_branch (fetch timed out)")
    continue
  elif [ "$fetch_exit" -ne 0 ]; then
    failed+=("$name on $current_branch (fetch exited $fetch_exit)")
    continue
  fi

  counts=$(git -C "$repo" rev-list --left-right --count "HEAD...@{upstream}" 2>/dev/null) || {
    failed+=("$name on $current_branch (compare failed)")
    continue
  }
  read -r a b <<< "$counts"
  a=${a:-0}
  b=${b:-0}

  if [ "$a" -eq 0 ] && [ "$b" -eq 0 ]; then
    continue  # silent on clean repos
  elif [ "$a" -eq 0 ] && [ "$b" -gt 0 ]; then
    if git -C "$repo" pull --ff-only --quiet 2>/dev/null; then
      synced+=("$name on $current_branch (+$b)")
    else
      failed+=("$name on $current_branch (fast-forward unexpectedly failed)")
    fi
  elif [ "$a" -gt 0 ] && [ "$b" -eq 0 ]; then
    ahead+=("$name on $current_branch ($a unpushed)")
  else
    diverged+=("$name on $current_branch ($a ahead, $b behind)")
  fi
done
```

## Report

Print a single summary block. Order: actions taken first, then things needing human judgment, sorted by severity:

```
Synced (fast-forwarded):
  - <name on branch (+N)>

Ahead (unpushed commits):
  - <name on branch (N unpushed)>

Diverged (need rebase or merge):
  - <name on branch (A ahead, B behind)>

Failed (fetch or compare error; investigate manually):
  - <name on branch (reason)>

Dirty (uncommitted work; not touched):
  - <name>

Skipped (detached HEAD or no upstream):
  - <name>
```

If any category is empty, omit its block. If everything is clean, print: "All repos in sync."

## Rules

- **Never touch dirty working trees.** Don't stash, don't reset, don't `git add`. The user's in-flight work is sacred.
- **Only fast-forward.** No rebase, no merge, no force. Anything that isn't a clean fast-forward goes to the report and the user decides.
- **Never delete branches.** This command syncs; branch hygiene is a separate concern.
- **Run from anywhere.** Uses `git -C "$repo"` for every git invocation, so the caller's CWD is never modified.
- **Surface failures, never swallow them.** Fetch errors, compare errors, and unexpected fast-forward failures land in the `failed` bucket with a reason — they don't disappear into the silent-success category.

## When to use

- After multiple sessions or PR merges have landed across repos and you want to consolidate state.
- When you'd rather sweep the whole workspace than `cd` into each repo one at a time.
- Before starting a coordinated change that touches multiple repos.

This command's job is the deterministic part: clean fast-forwards. The divergent and dirty repos in the report are yours to resolve.

$ARGUMENTS
