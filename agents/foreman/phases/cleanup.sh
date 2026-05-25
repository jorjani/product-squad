#!/bin/bash
# Phase: Cleanup — prune stale local branches across eligible repos
# Runs once per daily pipeline invocation (post-loop, before metrics)
#
# Tier 1: Delete branches merged into main (git-only, no API)
# Tier 2: Delete branches whose GitHub PR is merged or closed (one API call per branch)
# Tier 3: Flag branches with no remote + >14 days stale; auto-delete at 30+ days
# Never delete: main, master, staging, current branch, branches with open PRs
#
# POSTS: none
# READS: none
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
DATE=$(date +%Y-%m-%d)
LOG="$RESULTS_DIR/$DATE.log"

mkdir -p "$RESULTS_DIR"

source "$SCRIPT_DIR/lib/comments.sh"
source "$SCRIPT_DIR/lib/repos.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/questions.sh"

# Run once per day
SENTINEL="$RESULTS_DIR/.cleanup-ran-$DATE"
if [ -f "$SENTINEL" ]; then
  echo "CLEANUP: Already ran today" >> "$LOG"
  echo "skipped=1"
  exit 0
fi

# shellcheck disable=SC2207  # word-splitting on space-separated repos is intentional
REPOS=($(eligible_repos))
PROTECTED_BRANCHES="main|master|staging"

# Helper: branch is "merged" if either git history shows it merged into main
# (regular merge), OR GitHub PR state is MERGED/CLOSED (squash merges leave
# no hash trail in main's history but the PR record is the source of truth).
# Reads $REPO and $PROJECT_DIR from the per-repo loop scope (bash dynamic).
branch_is_merged() {
  local branch="$1"
  git -C "$PROJECT_DIR" branch --merged main --no-color 2>/dev/null \
    | sed 's/^[ *+]*//' | grep -qx "$branch" && return 0
  local pr_state
  pr_state=$(gh pr list --repo "$REPO" --head "$branch" --state all --json state -q '.[0].state' 2>/dev/null || echo "")
  case "$pr_state" in MERGED|CLOSED) return 0 ;; esac
  return 1
}

TOTAL_DELETED=0
TOTAL_FLAGGED=0
TOTAL_ORPHANS=0

for REPO in "${REPOS[@]}"; do
  PROJECT_DIR="$(repo_to_path "$REPO")"
  [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ] && continue

  SHORT="${REPO#getqatalyst/}"
  CURRENT_BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "main")
  DELETED=0
  FLAGGED=0

  # Pre-cleanup: prune worktrees and stale remote-tracking refs
  git -C "$PROJECT_DIR" worktree prune 2>/dev/null || true
  git -C "$PROJECT_DIR" fetch --prune 2>/dev/null || true

  # Tier 0: remove worktrees whose branch is merged + no uncommitted changes.
  # Without this, Tier 1/2's `git branch -d` silently fails on worktree-held
  # branches (git refuses to delete a branch that is checked out somewhere).
  # Untracked files are OK: they're session noise (.claude/, build output) and
  # not real modifications — `--force` discards them along with the worktree.
  git -C "$PROJECT_DIR" worktree list 2>/dev/null | while IFS= read -r WT_LINE; do
    WT_PATH=$(echo "$WT_LINE" | awk '{print $1}')
    WT_BRANCH=$(echo "$WT_LINE" | sed -n 's/.*\[\(.*\)\]$/\1/p')
    [ -z "$WT_BRANCH" ] && continue
    [ "$WT_PATH" = "$PROJECT_DIR" ] && continue
    branch_is_merged "$WT_BRANCH" || continue
    # --untracked-files=no: only block on real modifications, not session noise
    if [ -n "$(git -C "$WT_PATH" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
      echo "CLEANUP: [$SHORT] worktree '$WT_PATH' branch '$WT_BRANCH' has uncommitted changes, skipped" >> "$LOG"
      continue
    fi
    git -C "$PROJECT_DIR" worktree remove --force "$WT_PATH" 2>/dev/null && \
      echo "CLEANUP: [$SHORT] removed worktree '$WT_PATH' (merged, untracked discarded)" >> "$LOG" || true
  done

  # If the main checkout's current branch is itself merged + no uncommitted
  # changes, switch to main so Tier 1/2 below can delete it. Without this,
  # merged feature branches left checked out stay forever (e.g. after a
  # recovery, agent commit, or interrupted session).
  if [ "$CURRENT_BRANCH" != "main" ] && \
     [ -z "$(git -C "$PROJECT_DIR" status --porcelain --untracked-files=no 2>/dev/null)" ] && \
     branch_is_merged "$CURRENT_BRANCH"; then
    git -C "$PROJECT_DIR" switch main 2>/dev/null && {
      echo "CLEANUP: [$SHORT] switched current from merged '$CURRENT_BRANCH' to main" >> "$LOG"
      CURRENT_BRANCH="main"
    } || true
  fi

  # Collect all local branches except protected + current
  BRANCHES=$(git -C "$PROJECT_DIR" branch --no-color 2>/dev/null \
    | grep -v "^\*" \
    | sed 's/^ *//' \
    | grep -vE "^($PROTECTED_BRANCHES)$" \
    | grep -v "^${CURRENT_BRANCH}$" \
    || true)

  [ -z "$BRANCHES" ] && continue

  # Tier 1: branches merged into main
  MERGED=$(git -C "$PROJECT_DIR" branch --merged main --no-color 2>/dev/null \
    | grep -v "^\*" \
    | sed 's/^ *//' \
    | grep -vE "^($PROTECTED_BRANCHES)$" \
    | grep -v "^${CURRENT_BRANCH}$" \
    || true)

  for BRANCH in $MERGED; do
    git -C "$PROJECT_DIR" branch -d "$BRANCH" 2>/dev/null && {
      echo "CLEANUP: [$SHORT] deleted '$BRANCH' (merged into main)" >> "$LOG"
      DELETED=$((DELETED + 1))
    } || true
  done

  # Remaining branches after Tier 1
  REMAINING=$(git -C "$PROJECT_DIR" branch --no-color 2>/dev/null \
    | grep -v "^\*" \
    | sed 's/^ *//' \
    | grep -vE "^($PROTECTED_BRANCHES)$" \
    | grep -v "^${CURRENT_BRANCH}$" \
    || true)

  [ -z "$REMAINING" ] && {
    TOTAL_DELETED=$((TOTAL_DELETED + DELETED))
    continue
  }

  for BRANCH in $REMAINING; do
    # Branch age in days
    COMMIT_DATE=$(git -C "$PROJECT_DIR" log -1 --format='%ct' "$BRANCH" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    AGE_DAYS=$(( (NOW - COMMIT_DATE) / 86400 ))

    # Check if branch is in a worktree (skip if so)
    WT_CHECK=$(git -C "$PROJECT_DIR" worktree list 2>/dev/null | grep "\[$BRANCH\]" || true)
    if [ -n "$WT_CHECK" ]; then
      continue
    fi

    # Has remote?
    HAS_REMOTE=$(git -C "$PROJECT_DIR" ls-remote --heads origin "$BRANCH" 2>/dev/null | wc -l | tr -d ' ')

    # Tier 2: check GitHub PR status
    PR_STATE=$(gh pr list --repo "$REPO" --head "$BRANCH" --state all --json state -q '.[0].state' 2>/dev/null || echo "")

    if [ "$PR_STATE" = "MERGED" ]; then
      git -C "$PROJECT_DIR" branch -D "$BRANCH" 2>/dev/null && {
        echo "CLEANUP: [$SHORT] deleted '$BRANCH' (PR merged on GitHub)" >> "$LOG"
        DELETED=$((DELETED + 1))
      } || true
      continue
    fi

    if [ "$PR_STATE" = "CLOSED" ]; then
      git -C "$PROJECT_DIR" branch -D "$BRANCH" 2>/dev/null && {
        echo "CLEANUP: [$SHORT] deleted '$BRANCH' (PR closed on GitHub)" >> "$LOG"
        DELETED=$((DELETED + 1))
      } || true
      continue
    fi

    if [ "$PR_STATE" = "OPEN" ]; then
      # Active work, never touch
      continue
    fi

    # Tier 3: no remote, no PR — flag or auto-delete based on age
    if [ "$HAS_REMOTE" -eq 0 ] && [ -z "$PR_STATE" ]; then
      if [ "$AGE_DAYS" -ge 30 ]; then
        git -C "$PROJECT_DIR" branch -D "$BRANCH" 2>/dev/null && {
          echo "CLEANUP: [$SHORT] deleted '$BRANCH' (orphaned, ${AGE_DAYS} days stale)" >> "$LOG"
          DELETED=$((DELETED + 1))
        } || true
      elif [ "$AGE_DAYS" -ge 14 ]; then
        echo "CLEANUP: [$SHORT] STALE '$BRANCH' (no remote, no PR, ${AGE_DAYS} days) — review manually" >> "$LOG"
        FLAGGED=$((FLAGGED + 1))
      fi
      continue
    fi

    # Tier 3 extension: has remote, no PR — flag if old enough
    if [ "$HAS_REMOTE" -gt 0 ] && [ -z "$PR_STATE" ] && [ "$AGE_DAYS" -ge 14 ]; then
      echo "CLEANUP: [$SHORT] STALE '$BRANCH' (pushed, no PR, ${AGE_DAYS} days) — review manually" >> "$LOG"
      FLAGGED=$((FLAGGED + 1))
    fi

  done

  # Verification gate (#238): scan remote orphan markers and surface each as
  # DECISION-NEEDED on the parent issue. Dedup handles cross-run repetition so
  # a marker that sits for days produces one comment, not one per cleanup run.
  ORPHANS=0
  NV_REMOTES=$(git -C "$PROJECT_DIR" branch -r --list "origin/needs-verification/auto/issue-*" 2>/dev/null \
    | sed 's|origin/||' | tr -d ' ' || true)
  for nv_ref in $NV_REMOTES; do
    if [[ "$nv_ref" =~ ^needs-verification/auto/issue-([0-9]+) ]]; then
      issue_num="${BASH_REMATCH[1]}"
      orphan_branch="${nv_ref#needs-verification/}"
      sha=$(git -C "$PROJECT_DIR" rev-parse "origin/$nv_ref" 2>/dev/null || echo "")
      [ -z "$sha" ] && continue

      body_section=""
      body_persist="$SCRIPT_DIR/results/orphan-bodies/$(echo "$orphan_branch" | tr '/' '_').md"
      [ -f "$body_persist" ] && body_section="
**Saved PR body:** \`$body_persist\`"

      comment_dedup_or_escalate "$REPO" "$issue_num" "DECISION-NEEDED: orphan build branch on remote (\`$nv_ref\`)

An auto-build produced commits but the PR was not auto-opened (verification gate, #238).

**Orphan commit:** \`$sha\`
**Marker branch:** \`$nv_ref\`${body_section}

Re-run verification (typecheck + local build) on the marker branch before opening a PR. If verification fails, delete the marker branch and return the issue to Ready." "orphan-needs-verification" || true
      # Source-reframe (D4): same shape as the lib/orphan.sh emitter at
      # mark-time. Re-registration is deduped at the state-key level —
      # this only fires when the state file has no entry for this issue
      # (typically: marker survived from before the questions feature
      # shipped, or state file rebuilt).
      _ot=$(gh issue view "$issue_num" --repo "$REPO" --json title -q '.title' 2>/dev/null || echo "")
      questions_register "orphan-needs-verification" "$REPO" "$issue_num" \
        "Orphan commit $sha on $nv_ref still on remote." \
        "Foreman built \"${_ot:-#$issue_num}\" but the verification gate blocked auto-publish — want me to retry, or take the work?" \
        "An orphan marker branch is sitting on remote; the original auto-publish never landed." \
        '["Retry the publish next cycle","I will verify + open the PR by hand","Drop the work — back to Ready"]' \
        "" || true

      echo "CLEANUP: [$SHORT] ORPHAN-NEEDS-VERIFICATION '$nv_ref' (issue #$issue_num)" >> "$LOG"
      ORPHANS=$((ORPHANS + 1))
    fi
  done

  TOTAL_DELETED=$((TOTAL_DELETED + DELETED))
  TOTAL_FLAGGED=$((TOTAL_FLAGGED + FLAGGED))
  TOTAL_ORPHANS=$((TOTAL_ORPHANS + ORPHANS))

  if [ "$DELETED" -gt 0 ] || [ "$FLAGGED" -gt 0 ] || [ "$ORPHANS" -gt 0 ]; then
    echo "CLEANUP: [$SHORT] deleted=$DELETED flagged=$FLAGGED orphans=$ORPHANS" >> "$LOG"
  fi
done

touch "$SENTINEL"
echo "CLEANUP PHASE: deleted=$TOTAL_DELETED flagged=$TOTAL_FLAGGED orphans=$TOTAL_ORPHANS" >> "$LOG"
echo "deleted=$TOTAL_DELETED flagged=$TOTAL_FLAGGED orphans=$TOTAL_ORPHANS"
