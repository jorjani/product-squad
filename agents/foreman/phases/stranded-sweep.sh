#!/bin/bash
# Phase: Stranded Sweep — detect orphaned auto/issue-N-* worktrees and requeue.
# Runs once per daily pipeline invocation (post-loop, after ghost-sweep).
#
# When the orchestrator dies between commit and push, the worktree at
# /tmp/foreman-build-<RepoShort>-<N>-<PID> survives with local commits but no
# remote branch — the issue stays In Progress (CLAIMED was posted, so
# ghost-sweep skips it) and nothing else picks it up. Concrete incident:
# Sage#394 stalled silently for ~4.8h on 2026-05-16.
#
# Resolution: post STALLED: comment, move issue back to Ready, and remove
# the worktree so the next build cycle re-picks the ticket cleanly. The
# canonical build path already runs typecheck/build before push; rerunning
# it is safer than salvage-pushing an unverified branch from sweep.
#
# Default idle threshold: 30 minutes (matches BUILD_TIMEOUT in build-ticket.sh
# so an actively-running claude build is never swept). Override via
# STRANDED_AGE_MIN env var.
#
# POSTS: STALLED:
# READS: /tmp/foreman-build-* worktrees, origin remote branches
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
DATE=$(date +%Y-%m-%d)
LOG="$RESULTS_DIR/$DATE.log"

mkdir -p "$RESULTS_DIR"

SENTINEL="$RESULTS_DIR/.stranded-sweep-ran-$DATE"
if [ -f "$SENTINEL" ]; then
  echo "STRANDED-SWEEP: Already ran today" >> "$LOG"
  echo "stranded=0"
  exit 0
fi

source "$SCRIPT_DIR/config/board-ids.sh"
source "$SCRIPT_DIR/lib/comments.sh"
source "$SCRIPT_DIR/lib/repos.sh"

STRANDED_AGE_MIN="${STRANDED_AGE_MIN:-30}"

# Build a short-name -> owner/repo map from eligible_repos. Worktree paths
# encode `${REPO##*/}` (e.g. "Sage" for getqatalyst/Sage), so we need the
# reverse mapping to look up the canonical repo for board moves / comments.
SHORT_MAP=""
for _repo in $(eligible_repos); do
  SHORT_MAP="${SHORT_MAP}${_repo##*/}	${_repo}
"
done

short_to_repo() {
  printf '%s' "$SHORT_MAP" | awk -F'\t' -v s="$1" '$1==s {print $2; exit}'
}

# Detect activity by looking for any file modified within STRANDED_AGE_MIN
# minutes. mtime on the worktree directory itself only updates when entries
# are added/removed, so we walk a few levels deep instead. Exit code 0 means
# "active" (at least one recent file), 1 means "idle".
worktree_is_active() {
  local worktree="$1"
  if find "$worktree" -maxdepth 3 -mmin -"$STRANDED_AGE_MIN" -type f -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi
  return 1
}

SCANNED=0
STRANDED=0

shopt -s nullglob
for worktree in /tmp/foreman-build-*; do
  [ -d "$worktree" ] || continue
  SCANNED=$((SCANNED + 1))

  base="$(basename "$worktree")"
  # Worktree dirs are foreman-build-<Repo>-<N>-<PID> (PID-suffixed since the
  # worktree-race fix). Try the PID form first: its two trailing numeric
  # segments disambiguate the greedy <Repo> capture. Fall back to the legacy
  # no-PID form for worktrees created before the fix deployed.
  if [[ "$base" =~ ^foreman-build-(.+)-([0-9]+)-([0-9]+)$ ]]; then
    SHORT="${BASH_REMATCH[1]}"
    NUM="${BASH_REMATCH[2]}"
    # BASH_REMATCH[3] is the PID suffix — not needed; SHORT+NUM are sufficient.
  elif [[ "$base" =~ ^foreman-build-(.+)-([0-9]+)$ ]]; then
    SHORT="${BASH_REMATCH[1]}"
    NUM="${BASH_REMATCH[2]}"
  else
    echo "STRANDED-SWEEP: $base does not match foreman-build-<Repo>-<N>[-<PID>] — skipping" >> "$LOG"
    continue
  fi

  REPO="$(short_to_repo "$SHORT")"
  if [ -z "$REPO" ]; then
    echo "STRANDED-SWEEP: $base no matching eligible repo for short '$SHORT' — skipping" >> "$LOG"
    continue
  fi

  if worktree_is_active "$worktree"; then
    echo "STRANDED-SWEEP: $REPO#$NUM worktree active within ${STRANDED_AGE_MIN}m — skipping" >> "$LOG"
    continue
  fi

  BRANCH=$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$BRANCH" != auto/issue-${NUM}-* ]]; then
    echo "STRANDED-SWEEP: $REPO#$NUM worktree branch '$BRANCH' not auto/issue-$NUM-* — skipping" >> "$LOG"
    continue
  fi

  COMMITS_AHEAD=$(git -C "$worktree" rev-list --count "origin/main..HEAD" 2>/dev/null || echo 0)
  if [ "${COMMITS_AHEAD:-0}" -eq 0 ]; then
    echo "STRANDED-SWEEP: $REPO#$NUM worktree has no commits ahead of origin/main — skipping" >> "$LOG"
    continue
  fi

  # If the remote branch exists, the build already pushed (idempotency: a
  # prior sweep cycle may have left the worktree, or a human ran the rescue
  # path like Sage#394 on 2026-05-17). Not stranded.
  REMOTE_LINE=$(git -C "$worktree" ls-remote --heads origin "$BRANCH" 2>/dev/null || true)
  if [ -n "$REMOTE_LINE" ]; then
    echo "STRANDED-SWEEP: $REPO#$NUM remote $BRANCH exists — not stranded" >> "$LOG"
    continue
  fi

  HEAD_SHA=$(git -C "$worktree" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  LAST_MSG=$(git -C "$worktree" log -1 --format=%s HEAD 2>/dev/null | head -c 200 || echo "")

  comment_dedup_or_escalate "$REPO" "$NUM" "STALLED: stranded auto/ branch (build process died mid-pipeline)

**Worktree:** \`$worktree\`
**Branch:** \`$BRANCH\` (local-only, $COMMITS_AHEAD commit(s) ahead of main)
**HEAD:** \`$HEAD_SHA\` — $LAST_MSG
**Idle:** >${STRANDED_AGE_MIN} min

Returning to Ready so the build phase can re-pick this ticket on the next cycle. Worktree removed." \
    "stranded-sweep" >> "$LOG" 2>&1 || true

  move_to_ready "$REPO" "$NUM" >> "$LOG" 2>&1 || true

  PROJECT_DIR="$(repo_to_path "$REPO")"
  if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
    git -C "$PROJECT_DIR" worktree remove "$worktree" --force >> "$LOG" 2>&1 || true
  fi
  rm -rf "$worktree" 2>/dev/null || true

  echo "STRANDED-SWEEP: $REPO#$NUM requeued (branch=$BRANCH, head=$HEAD_SHA, ${COMMITS_AHEAD} ahead)" >> "$LOG"
  STRANDED=$((STRANDED + 1))
done
shopt -u nullglob

touch "$SENTINEL"
echo "STRANDED-SWEEP PHASE: scanned=$SCANNED stranded=$STRANDED" >> "$LOG"
echo "stranded=$STRANDED"
