#!/bin/bash
# lib/pr-body.sh — shared auto/ PR-body template.
#
# Single source of truth for the PR description format used by both the
# in-process build path (phases/build-ticket.sh) and the orphan-rescue path
# (phases/orphan-rescue.sh, foreman#240). Factored out so the two callers
# cannot drift — and so foreman#233's `Closes` -> `Refs` change lands in one
# place.
#
# foreman#233: a merged auto/ PR must NOT auto-close its issue. Issue state
# tracks verification and closes on the Verify->Done promotion, so the body
# header is always `Refs #N`, never `Closes #N`.

# build_pr_body <worktree_dir> <issue_num> <build_cmd_or_empty>
#
# Emits the full PR body to stdout:
#   - `Refs #N` header
#   - body content: $worktree_dir/.pr-body.md when Claude wrote one, else a
#     commit-log summary of origin/main..HEAD
#   - an optional "## Build Check" section when build_cmd is non-empty
build_pr_body() {
  local worktree_dir="$1" issue_num="$2" build_cmd="${3:-}"
  local body_content

  if [ -f "$worktree_dir/.pr-body.md" ]; then
    body_content=$(cat "$worktree_dir/.pr-body.md")
  else
    body_content="## Changes
$(git -C "$worktree_dir" log origin/main..HEAD --pretty=format:'- %s' 2>/dev/null)"
  fi

  if [ -n "$build_cmd" ]; then
    body_content="$body_content

## Build Check
Local build passed: \`$build_cmd\`"
  fi

  printf 'Refs #%s\n\n%s\n' "$issue_num" "$body_content"
}
