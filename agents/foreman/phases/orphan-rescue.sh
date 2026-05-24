#!/bin/bash
# Phase: Orphan Rescue — publish auto/ builds stranded after commit, pre-push.
# Runs once per daily pipeline invocation (post-loop, after ghost-sweep and
# BEFORE stranded-sweep). foreman#240.
#
# When build-ticket.sh's wall-clock killer (lib/bounded.sh) SIGKILLs the whole
# process group after claude has already committed + written .pr-body.md, the
# post-claude push (build-ticket.sh) and PR-create never run. The worktree at
# /tmp/foreman-build-<RepoShort>-<N> carries a real commit and a .pr-body.md
# but has no remote branch. stranded-sweep.sh would requeue this to Ready and
# redo the work; orphan-rescue instead publishes it — claude already finished,
# and .pr-body.md is the "verification passed" signal (foreman#238). Order
# matters: orphan-rescue first, then stranded-sweep requeues anything left.
#
# Detection signature (all six required, mirrors stranded-sweep.sh):
#   1. path matches foreman-build-<Repo>-<N>[-<PID>]
#   2. worktree idle (no file modified within STRANDED_AGE_MIN minutes)
#   3. HEAD branch is auto/issue-<N>-*
#   4. commits ahead of origin/main
#   5. no remote branch for HEAD (an existing #238 marker also trips this —
#      intentional: orphan-rescue must defer to the verification gate)
#   6. .pr-body.md present in worktree root  <- orphan-after-commit + #238 gate
#
# On push/PR-create failure -> mark_orphan (lib/orphan.sh) routes the commit
# through needs-verification/<branch> per foreman#238. After 3 consecutive
# rescue failures on the same orphan, the issue is labelled `blocked`.
#
# Self-test: ./orchestrator.sh test-orphan-rescue <repo> <issue> synthesizes an
# orphan worktree and dispatches one rescue iteration.
#
# POSTS: "PR opened: <url>" (issue comment), DECISION-NEEDED (via mark_orphan)
# READS: /tmp/foreman-build-* worktrees, origin remote branches
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
DATE=$(date +%Y-%m-%d)
LOG="$RESULTS_DIR/$DATE.log"

mkdir -p "$RESULTS_DIR"

source "$SCRIPT_DIR/config/board-ids.sh"
source "$SCRIPT_DIR/lib/comments.sh"
source "$SCRIPT_DIR/lib/repos.sh"
source "$SCRIPT_DIR/lib/orphan.sh"
source "$SCRIPT_DIR/lib/pr-body.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/questions.sh"

# --- Self-test mode ---------------------------------------------------------
# `orphan-rescue.sh --self-test <repo> <issue>` synthesizes the orphan
# condition then runs one scan with STRANDED_AGE_MIN=0. Mirrors the foreman
# CLAUDE.md "lazy-init telemetry needs a manual trigger" lesson — orphans
# fire too rarely to verify by observation alone.
SELF_TEST=0
TEST_REPO=""
TEST_ISSUE=""
if [ "${1:-}" = "--self-test" ]; then
  SELF_TEST=1
  TEST_REPO="${2:-}"
  TEST_ISSUE="${3:-}"
  if [ -z "$TEST_REPO" ] || [ -z "$TEST_ISSUE" ]; then
    echo "Usage: orphan-rescue.sh --self-test <owner/repo> <issue_number>" >&2
    exit 1
  fi
fi

# STRANDED_AGE_MIN matches stranded-sweep.sh so an actively-running build is
# never rescued mid-flight. Self-test uses 0 (the synthesized worktree is
# brand new — worktree_is_active treats <=0 as "always idle").
if [ "$SELF_TEST" -eq 1 ]; then
  STRANDED_AGE_MIN=0
else
  STRANDED_AGE_MIN="${STRANDED_AGE_MIN:-30}"
fi

# Idempotency sentinel (skipped in self-test so the test always runs).
SENTINEL="$RESULTS_DIR/.orphan-rescue-ran-$DATE"
if [ "$SELF_TEST" -eq 0 ] && [ -f "$SENTINEL" ]; then
  echo "ORPHAN-RESCUE: Already ran today" >> "$LOG"
  echo "rescued=0"
  exit 0
fi

# Short-name -> owner/repo map (worktree paths encode ${REPO##*/}).
SHORT_MAP=""
for _repo in $(eligible_repos); do
  SHORT_MAP="${SHORT_MAP}${_repo##*/}	${_repo}
"
done
short_to_repo() {
  printf '%s' "$SHORT_MAP" | awk -F'\t' -v s="$1" '$1==s {print $2; exit}'
}

# Idle detection — any file modified within STRANDED_AGE_MIN minutes means the
# build is still running. Exit 0 = active, 1 = idle. <=0 = always idle (test).
worktree_is_active() {
  local worktree="$1"
  [ "${STRANDED_AGE_MIN:-30}" -le 0 ] && return 1
  if find "$worktree" -maxdepth 3 -mmin -"$STRANDED_AGE_MIN" -type f -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi
  return 1
}

# Per-orphan consecutive-failure counter. comment_dedup_or_escalate hides its
# dup count and orphan DECISION-NEEDED comments dedup to <=1 on the issue, so
# a small results/ counter file is the reliable way to cap retries at 3.
fail_slug() { echo "$1" | tr '/' '_'; }
fail_count() {
  local f
  f="$RESULTS_DIR/.orphan-rescue-fails-$(fail_slug "$1")"
  [ -f "$f" ] && cat "$f" 2>/dev/null || echo 0
}
fail_bump() {
  local f n
  f="$RESULTS_DIR/.orphan-rescue-fails-$(fail_slug "$1")"
  n=$(fail_count "$1")
  n=$((n + 1))
  echo "$n" > "$f"
  echo "$n"
}
fail_clear() {
  rm -f "$RESULTS_DIR/.orphan-rescue-fails-$(fail_slug "$1")" 2>/dev/null || true
}

# After a rescue falls through to mark_orphan, bump the counter. On the 3rd
# consecutive failure, label the issue `blocked` and escalate once.
handle_rescue_failure() {
  local repo="$1" num="$2" branch="$3" count
  count=$(fail_bump "$branch")
  if [ "$count" -ge 3 ]; then
    gh issue edit "$num" --repo "$repo" --add-label "blocked" >/dev/null 2>&1 || true
    comment_dedup_or_escalate "$repo" "$num" "DECISION-NEEDED: orphan-rescue failed 3 cycles in a row

Foreman detected an orphaned build worktree for \`$branch\` and tried to publish it on 3 consecutive cycles; each attempt failed (push or PR creation). Where reachable, the commit was routed to the verification gate (#238).

Labelled \`blocked\`. Please resolve manually — check git auth/network, then either open the PR by hand or return this issue to Ready." "orphan-rescue-failed" >> "$LOG" 2>&1 || true
    # Source-reframe (D4): the work was done but Foreman couldn't
    # publish it. David picks the recovery path.
    local _title
    _title=$(gh issue view "$num" --repo "$repo" --json title -q '.title' 2>/dev/null || echo "")
    questions_register "orphan-rescue-failed" "$repo" "$num" \
      "Orphan branch $branch — push or PR-create failed 3 cycles in a row." \
      "Foreman finished building \"${_title:-#$num}\" but couldn't ship the PR — want me to retry, or do it by hand?" \
      "The work is committed locally and routed to the verification gate. Three publish attempts failed (likely a git auth or remote issue)." \
      '["Retry next cycle — git should be back","I will open the PR by hand","Drop the work — back to Ready"]' \
      "" || true
    echo "ORPHAN-RESCUE: $repo#$num blocked after $count failed rescues" >> "$LOG"
  fi
}

# Synthesize an orphan worktree for --self-test: a fresh worktree off
# origin/main with one dummy commit + a .pr-body.md, never pushed.
synthesize_orphan() {
  local repo="$1" issue="$2" short project_dir worktree branch
  short="${repo##*/}"
  project_dir="$(repo_to_path "$repo")"
  if [ -z "$project_dir" ] || [ ! -d "$project_dir" ]; then
    echo "test-orphan-rescue: no local checkout for $repo" >&2
    exit 1
  fi
  worktree="/tmp/foreman-build-${short}-${issue}"
  branch="auto/issue-${issue}-orphan-rescue-smoke-test"

  git -C "$project_dir" worktree remove "$worktree" --force 2>/dev/null || true
  rm -rf "$worktree" 2>/dev/null || true
  git -C "$project_dir" branch -D "$branch" 2>/dev/null || true
  git -C "$project_dir" push origin --delete "$branch" 2>/dev/null || true
  git -C "$project_dir" fetch origin main --quiet 2>/dev/null || true
  if ! git -C "$project_dir" worktree add -b "$branch" "$worktree" origin/main >/dev/null 2>&1; then
    echo "test-orphan-rescue: could not create worktree at $worktree" >&2
    exit 1
  fi

  printf 'orphan-rescue smoke test %s\n' "$(date)" > "$worktree/.orphan-rescue-smoke-test"
  git -C "$worktree" add .orphan-rescue-smoke-test
  git -C "$worktree" -c user.name="foreman" -c user.email="foreman@local" \
    commit -q -m "test: orphan-rescue smoke test (synthetic — close this PR)"
  cat > "$worktree/.pr-body.md" <<'EOF'
## Changes
- Synthetic orphan-rescue smoke test. This PR is generated by
  `./orchestrator.sh test-orphan-rescue` — safe to close.

## Testing
- Verifies phases/orphan-rescue.sh detects + publishes an orphaned worktree.
EOF
  echo "test-orphan-rescue: synthesized orphan at $worktree (branch $branch)"
}

# Rescue one detected orphan. Runs from inside the worktree. Returns 0 on
# publish, 1 on mark_orphan fall-through.
rescue_worktree() {
  local repo="$1" num="$2" worktree="$3" branch="$4"
  local head_sha title pr_body_file pr_url
  local push_err push_rc err_tail pr_err pr_rc pr_err_line

  head_sha=$(git -C "$worktree" rev-parse --short HEAD 2>/dev/null || echo unknown)
  cd "$worktree"

  # Step 1: push the orphaned branch.
  push_err=$(mktemp)
  push_rc=0
  git push -u origin "$branch" >"$push_err" 2>&1 || push_rc=$?
  if [ "$push_rc" -ne 0 ]; then
    err_tail=$(tail -5 "$push_err" 2>/dev/null | head -c 500 || true)
    rm -f "$push_err"
    echo "ORPHAN-RESCUE: $repo#$num push-failed → mark_orphan ($err_tail)" >> "$LOG"
    WORKTREE_DIR="$worktree"
    mark_orphan "$repo" "$num" "$branch" "orphan-rescue-push-failed" "$err_tail" >> "$LOG" 2>&1 || true
    handle_rescue_failure "$repo" "$num" "$branch"
    return 1
  fi
  rm -f "$push_err"

  # Step 2: open the PR. Body via lib/pr-body.sh — no build_cmd (the local
  # build check never ran; claude's .pr-body.md already carries Testing notes).
  title=$(gh issue view "$num" --repo "$repo" --json title -q '.title' 2>/dev/null || echo "$branch")
  pr_body_file=$(mktemp)
  build_pr_body "$worktree" "$num" "" > "$pr_body_file"
  pr_err=$(mktemp)
  pr_rc=0
  gh pr create --repo "$repo" --base main --title "$title" \
    --body-file "$pr_body_file" >/dev/null 2>"$pr_err" || pr_rc=$?
  rm -f "$pr_body_file"
  if [ "$pr_rc" -ne 0 ]; then
    pr_err_line=$(head -1 "$pr_err" 2>/dev/null | head -c 500 || true)
    rm -f "$pr_err"
    echo "ORPHAN-RESCUE: $repo#$num pr-create-failed → mark_orphan ($pr_err_line)" >> "$LOG"
    WORKTREE_DIR="$worktree"
    mark_orphan "$repo" "$num" "$branch" "orphan-rescue-pr-create-failed" "$pr_err_line" >> "$LOG" 2>&1 || true
    handle_rescue_failure "$repo" "$num" "$branch"
    return 1
  fi
  rm -f "$pr_err"

  # Step 3: resolve PR url, comment on the issue, move to In Review.
  pr_url=$(gh pr list --repo "$repo" --head "$branch" --json url -q '.[0].url' 2>/dev/null || true)
  gh issue comment "$num" --repo "$repo" \
    --body "PR opened: ${pr_url:-(branch $branch)}" >/dev/null 2>&1 || true
  move_to_in_review "$repo" "$num" >> "$LOG" 2>&1 || true

  fail_clear "$branch"
  echo "ORPHAN-RESCUE: $repo#$num published ${pr_url:-$branch} (head=$head_sha)" >> "$LOG"
  return 0
}

SCANNED=0
RESCUED=0
MARK_ORPHANED=0

if [ "$SELF_TEST" -eq 1 ]; then
  synthesize_orphan "$TEST_REPO" "$TEST_ISSUE"
fi

shopt -s nullglob
for worktree in /tmp/foreman-build-*; do
  [ -d "$worktree" ] || continue

  base="$(basename "$worktree")"
  # Worktree dirs are foreman-build-<Repo>-<N>-<PID> (PID-suffixed since the
  # worktree-race fix); fall back to the legacy no-PID form. The PID form's
  # two trailing numeric segments disambiguate the greedy <Repo> capture —
  # without the PID-first branch, ([0-9]+) binds the PID, not the issue
  # number. Mirrors stranded-sweep.sh so both phases agree on every worktree.
  if [[ "$base" =~ ^foreman-build-(.+)-([0-9]+)-([0-9]+)$ ]]; then
    SHORT="${BASH_REMATCH[1]}"
    NUM="${BASH_REMATCH[2]}"
  elif [[ "$base" =~ ^foreman-build-(.+)-([0-9]+)$ ]]; then
    SHORT="${BASH_REMATCH[1]}"
    NUM="${BASH_REMATCH[2]}"
  else
    continue
  fi

  # Self-test stays isolated to the synthesized worktree.
  if [ "$SELF_TEST" -eq 1 ] && [ "$base" != "foreman-build-${TEST_REPO##*/}-${TEST_ISSUE}" ]; then
    continue
  fi

  REPO="$(short_to_repo "$SHORT")"
  if [ -z "$REPO" ]; then
    echo "ORPHAN-RESCUE: $base no matching eligible repo for short '$SHORT' — skipping" >> "$LOG"
    continue
  fi

  SCANNED=$((SCANNED + 1))

  # Signature 2: idle.
  if worktree_is_active "$worktree"; then
    echo "ORPHAN-RESCUE: $REPO#$NUM worktree active within ${STRANDED_AGE_MIN}m — skipping" >> "$LOG"
    continue
  fi

  # Signature 3: HEAD is auto/issue-<N>-*.
  BRANCH=$(git -C "$worktree" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$BRANCH" != auto/issue-${NUM}-* ]]; then
    echo "ORPHAN-RESCUE: $REPO#$NUM worktree branch '$BRANCH' not auto/issue-$NUM-* — skipping" >> "$LOG"
    continue
  fi

  # Signature 4: commits ahead of origin/main.
  COMMITS_AHEAD=$(git -C "$worktree" rev-list --count origin/main..HEAD 2>/dev/null || echo 0)
  if [ "${COMMITS_AHEAD:-0}" -eq 0 ]; then
    echo "ORPHAN-RESCUE: $REPO#$NUM no commits ahead of origin/main — skipping" >> "$LOG"
    continue
  fi

  # Signature 5: no remote branch (a #238 marker also matches — defer to it).
  if [ -n "$(git -C "$worktree" ls-remote --heads origin "$BRANCH" 2>/dev/null)" ]; then
    echo "ORPHAN-RESCUE: $REPO#$NUM remote $BRANCH exists — not an orphan" >> "$LOG"
    continue
  fi

  # Signature 6: .pr-body.md present — the orphan-after-commit discriminator
  # AND the foreman#238 verification-passed signal. Without it, not a publish
  # target: leave for stranded-sweep.sh to requeue.
  if [ ! -f "$worktree/.pr-body.md" ]; then
    echo "ORPHAN-RESCUE: $REPO#$NUM no .pr-body.md — leaving for stranded-sweep" >> "$LOG"
    continue
  fi

  # 3-strike cap: stop attempting a doomed orphan.
  if [ "$(fail_count "$BRANCH")" -ge 3 ]; then
    echo "ORPHAN-RESCUE: $REPO#$NUM blocked after 3 failed rescues — skipping" >> "$LOG"
    continue
  fi

  # Defense-in-depth: a closed issue should not get a fresh PR.
  ISSUE_STATE=$(gh issue view "$NUM" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "OPEN")
  if [ "$ISSUE_STATE" = "CLOSED" ]; then
    echo "ORPHAN-RESCUE: $REPO#$NUM issue closed — skipping" >> "$LOG"
    continue
  fi

  if rescue_worktree "$REPO" "$NUM" "$worktree" "$BRANCH"; then
    cd "$SCRIPT_DIR"
    RESCUED=$((RESCUED + 1))
    # Remove the published worktree (cwd must be outside it).
    PROJECT_DIR="$(repo_to_path "$REPO")"
    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
      git -C "$PROJECT_DIR" worktree remove "$worktree" --force >> "$LOG" 2>&1 || true
    fi
    rm -rf "$worktree" 2>/dev/null || true
  else
    cd "$SCRIPT_DIR"
    MARK_ORPHANED=$((MARK_ORPHANED + 1))
  fi
done
shopt -u nullglob

[ "$SELF_TEST" -eq 0 ] && touch "$SENTINEL"
echo "ORPHAN-RESCUE PHASE: scanned=$SCANNED rescued=$RESCUED mark_orphaned=$MARK_ORPHANED" >> "$LOG"
echo "rescued=$RESCUED"
