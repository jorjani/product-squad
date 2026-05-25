#!/bin/bash
# Per-ticket executor: creates branch, runs Claude, ships PR
# Called by build.sh with: build-ticket.sh <repo> <issue_num> <title>
# POSTS: Automated build failed (attempt N), BUILD-FAILED: local build check
#
# Retry logic: if a remote branch exists from a prior failed attempt AND
# new non-bot comments have appeared on the issue, deletes old branch and
# retries with the full comment thread as context. Max 3 total attempts.
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

REPO="$1"
ISSUE_NUM="$2"
TITLE="$3"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
DATE=$(date +%Y-%m-%d)
LOG="$RESULTS_DIR/$DATE.log"

source "$SCRIPT_DIR/lib/comments.sh"
source "$SCRIPT_DIR/lib/bounded.sh"
# Slack-questions registration (lib/questions.sh) — silent no-op when
# SLACK_BOT_TOKEN unset, so the DARK posture survives without an explicit guard.
source "$SCRIPT_DIR/lib/questions.sh"
# mark_orphan (#238 verification gate) — shared with phases/orphan-rescue.sh.
source "$SCRIPT_DIR/lib/orphan.sh"
# build_pr_body — shared auto/ PR-body template, also used by orphan-rescue.sh.
source "$SCRIPT_DIR/lib/pr-body.sh"
# Threshold constants (WIP_LIMIT, MAX_BUILD_ATTEMPTS)
source "$SCRIPT_DIR/config/thresholds.sh"
# Centralized repo lookups (repo_to_path) — derives from ~/Projects/.index.json
source "$SCRIPT_DIR/lib/repos.sh"

# Repo -> local directory mapping is derived from ~/Projects/.index.json via
# lib/repos.sh::repo_to_path (centralized; survives renames without per-file drift).
PROJECT_DIR="$(repo_to_path "$REPO")"
if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  echo "FAIL: Unknown or missing project dir for $REPO"
  exit 1
fi

# Worktree cleanup on any exit (WORKTREE_DIR set later, before worktree creation)
cleanup_worktree() {
  if [ -n "${WORKTREE_DIR:-}" ] && [ -d "$WORKTREE_DIR" ]; then
    cd "$PROJECT_DIR" 2>/dev/null || true
    git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
    rm -rf "$WORKTREE_DIR" 2>/dev/null || true
  fi
  rm -f "${TMPFILE:-}" 2>/dev/null || true
}
trap cleanup_worktree EXIT

# Skip if issue is already closed (defense-in-depth -- build.sh also checks)
ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "OPEN")
if [ "$ISSUE_STATE" = "CLOSED" ]; then
  echo "SKIP: #$ISSUE_NUM is already closed"
  exit 0
fi

# Fetch issue body
ISSUE_BODY=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json body -q '.body' 2>/dev/null) || {
  echo "FAIL: Could not fetch issue #$ISSUE_NUM from $REPO"
  exit 1
}

# Create branch name (slugify title, max 40 chars)
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | head -c 40)
BASE_BRANCH="auto/issue-${ISSUE_NUM}-${SLUG}"
BRANCH="$BASE_BRANCH"

# Create isolated worktree for this build (project dir is never modified)
cd "$PROJECT_DIR"
git fetch origin main --prune 2>/dev/null || true
git checkout main 2>/dev/null || true
git reset --hard origin/main 2>/dev/null || true
# PID-suffixed so concurrent build-ticket.sh runs for the same issue never
# share a path. Without the -$$ suffix a sibling build's startup rm / cleanup
# trap could delete this build's live worktree mid-run — the Sage#168 failure
# class seen 2026-05-14 and 2026-05-20 ("Working directory was deleted").
WORKTREE_DIR="/tmp/foreman-build-${REPO##*/}-${ISSUE_NUM}-$$"
# Clean up any prior worktree at this exact path (defensive: PID reuse).
git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
rm -rf "$WORKTREE_DIR" 2>/dev/null || true
git worktree add "$WORKTREE_DIR" origin/main 2>/dev/null || {
  echo "FAIL: Could not create worktree for $REPO#$ISSUE_NUM"
  exit 1
}

# --- Retry logic: detect existing branches from previous attempts ---
BOT_USER=$(gh api user -q '.login' 2>/dev/null || echo "")
EXISTING_BRANCH=""
CURRENT_ATTEMPT=1
ISSUE_COMMENTS_SECTION=""

# Verification gate (#238): if an orphan marker exists for this issue, no
# automation may open a PR. Skip the build entirely until David resolves it.
NV_EXISTING=$(git branch -r --list "origin/needs-verification/auto/issue-${ISSUE_NUM}-*" 2>/dev/null \
  | sed 's|origin/||' | tr -d ' ' | head -1 || true)
if [ -n "$NV_EXISTING" ]; then
  echo "SKIP: $REPO#$ISSUE_NUM has orphan marker $NV_EXISTING (verification gate)"
  exit 0
fi

# Find existing remote branches for this issue (pick highest attempt)
for remote_ref in $(git branch -r --list "origin/auto/issue-${ISSUE_NUM}-*" 2>/dev/null | sed 's|origin/||' | tr -d ' '); do
  ref_attempt=1
  if [[ "$remote_ref" =~ -attempt-([0-9]+)$ ]]; then
    ref_attempt="${BASH_REMATCH[1]}"
  fi
  if [ "$ref_attempt" -ge "$CURRENT_ATTEMPT" ]; then
    EXISTING_BRANCH="$remote_ref"
    CURRENT_ATTEMPT="$ref_attempt"
  fi
done

if [ -n "$EXISTING_BRANCH" ]; then
  # Check if a PR already exists (prior build succeeded)
  EXISTING_PR=$(gh pr list --repo "$REPO" --head "$EXISTING_BRANCH" --json url -q '.[0].url' 2>/dev/null || true)
  if [ -n "$EXISTING_PR" ]; then
    echo "SKIP: PR already exists for $EXISTING_BRANCH: $EXISTING_PR"
    exit 0
  fi

  # Max attempts — silently skip (give-up comment was posted on the final failure)
  if [ "$CURRENT_ATTEMPT" -ge "$MAX_BUILD_ATTEMPTS" ]; then
    echo "GIVE-UP: $REPO#$ISSUE_NUM already failed $CURRENT_ATTEMPT attempts, not retrying"
    exit 0
  fi

  # Get timestamp of the tip commit on the existing branch
  BRANCH_DATE=$(git log -1 --format=%cI "origin/$EXISTING_BRANCH" 2>/dev/null || echo "")

  if [ -z "$BRANCH_DATE" ]; then
    echo "SKIP: Branch $EXISTING_BRANCH exists but couldn't determine timestamp"
    exit 0
  fi

  # Count new non-bot comments since the branch was created
  NEW_COMMENT_COUNT=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json comments \
    --jq "[.comments[] | select(.author.login != \"$BOT_USER\") | select(.createdAt > \"$BRANCH_DATE\")] | length" 2>/dev/null || echo "0")

  # Check if main has advanced since the branch (e.g., CI fix merged)
  BRANCH_MAIN_SHA=$(git merge-base origin/main "origin/$EXISTING_BRANCH" 2>/dev/null || echo "")
  CURRENT_MAIN_SHA=$(git rev-parse origin/main 2>/dev/null || echo "")
  MAIN_ADVANCED=false
  if [ -n "$BRANCH_MAIN_SHA" ] && [ "$BRANCH_MAIN_SHA" != "$CURRENT_MAIN_SHA" ]; then
    EXISTING_PR_URL=$(gh pr list --repo "$REPO" --head "$EXISTING_BRANCH" --json url -q '.[0].url' 2>/dev/null || true)
    if [ -z "$EXISTING_PR_URL" ]; then
      MAIN_ADVANCED=true
    fi
  fi

  # B3: Age check - stale branches (>3 days, no PR) get deleted and rebuilt
  BRANCH_AGE_SECS=$(( $(date +%s) - $(git log -1 --format=%ct "origin/$EXISTING_BRANCH" 2>/dev/null || echo "0") ))
  BRANCH_AGE_DAYS=$(( BRANCH_AGE_SECS / 86400 ))
  if [ "$BRANCH_AGE_DAYS" -gt 3 ]; then
    echo "STALE: Branch $EXISTING_BRANCH is ${BRANCH_AGE_DAYS}d old with no PR, deleting and rebuilding fresh"
    git push origin --delete "$EXISTING_BRANCH" 2>/dev/null || true
    git branch -D "$EXISTING_BRANCH" 2>/dev/null || true
    EXISTING_BRANCH=""
  elif [ "$NEW_COMMENT_COUNT" -eq 0 ] 2>/dev/null && [ "$MAIN_ADVANCED" = "false" ]; then
    echo "SKIP: Branch $EXISTING_BRANCH exists, no new comments and main unchanged"
    exit 0
  fi

  if [ "$MAIN_ADVANCED" = "true" ] && [ "$NEW_COMMENT_COUNT" -eq 0 ] 2>/dev/null; then
    echo "RETRY: main advanced since $EXISTING_BRANCH (likely CI fix), retrying"
  fi

  # New human comments found — prepare retry
  NEXT_ATTEMPT=$((CURRENT_ATTEMPT + 1))
  CURRENT_ATTEMPT="$NEXT_ATTEMPT"
  echo "RETRY: $NEW_COMMENT_COUNT new comment(s) on $REPO#$ISSUE_NUM, retrying (attempt $CURRENT_ATTEMPT)"

  # Fetch full comment thread for context
  ISSUE_COMMENTS=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json comments \
    --jq '.comments[] | "**\(.author.login)** (\(.createdAt)):\n\(.body)\n---"' 2>/dev/null || echo "")

  if [ -n "$ISSUE_COMMENTS" ]; then
    ISSUE_COMMENTS_SECTION="## Previous Attempts and Clarifications

The following comment thread from the GitHub issue contains context from previous build attempts and user clarifications:

$ISSUE_COMMENTS"
  fi

  # Delete old branch (remote + local)
  git push origin --delete "$EXISTING_BRANCH" 2>/dev/null || true
  git branch -D "$EXISTING_BRANCH" 2>/dev/null || true

  # Set retry branch name
  BRANCH="${BASE_BRANCH}-attempt-${CURRENT_ATTEMPT}"
fi

# Switch to worktree for the build
cd "$WORKTREE_DIR"
# Reuse existing branch if present (preserves prior partial work), otherwise create fresh
if git rev-parse --verify "$BRANCH" &>/dev/null || git rev-parse --verify "origin/$BRANCH" &>/dev/null; then
  echo "Reusing existing branch $BRANCH, rebasing on main..."
  git fetch origin main
  git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH"
  git rebase origin/main || {
    echo "Rebase conflicted — resetting to main (prior work too diverged)"
    git rebase --abort
    git reset --hard origin/main
  }
else
  git checkout -b "$BRANCH"
fi

# Log base commit for future replay capability
echo "BASE_COMMIT=$(git rev-parse HEAD)" >> "$RESULTS_DIR/$DATE-issue-$ISSUE_NUM.meta"

# Render prompt using temp file (safe for multiline issue bodies)
TMPFILE=$(mktemp)

sed \
  -e "s|{PROJECT_DIR}|$WORKTREE_DIR|g" \
  -e "s|{ISSUE_NUMBER}|$ISSUE_NUM|g" \
  -e "s|{BRANCH_NAME}|$BRANCH|g" \
  -e "s|{REPO}|$REPO|g" \
  "$SCRIPT_DIR/prompts/build.md" > "$TMPFILE"

# Replace title, body, and comments section (large values via env vars to avoid ARG_MAX)
export ISSUE_COMMENTS_SECTION
python3 -c "
import sys, os
body = sys.stdin.read()
with open(sys.argv[1], 'r') as f:
    content = f.read()
content = content.replace('{ISSUE_TITLE}', sys.argv[2])
content = content.replace('{ISSUE_BODY}', body)
content = content.replace('{ISSUE_COMMENTS_SECTION}', os.environ.get('ISSUE_COMMENTS_SECTION', ''))
with open(sys.argv[1], 'w') as f:
    f.write(content)
" "$TMPFILE" "$TITLE" <<< "$ISSUE_BODY"

# Pre-flight: measure the assembled prompt size for diagnostics. This replaces
# the prior body-only `wc -c` proxy (issue #118), which gated on a value
# unrelated to what Claude actually receives. The assembled prompt is the
# rendered template (already includes ISSUE_BODY + ISSUE_COMMENTS_SECTION via
# the sed/python pass above) plus every CLAUDE.md the SDK auto-loads from the
# worktree CWD walking upward, plus the user's global ~/.claude/CLAUDE.md.
# Logged only — no hard threshold yet; tune in a follow-up after data lands.
ASSEMBLED_PROMPT_BYTES=$(wc -c < "$TMPFILE" | tr -d ' ')
walk_dir="$WORKTREE_DIR"
while [ -n "$walk_dir" ] && [ "$walk_dir" != "/" ]; do
  for md in "$walk_dir/CLAUDE.md" "$walk_dir/.claude/CLAUDE.md"; do
    if [ -f "$md" ]; then
      md_bytes=$(wc -c < "$md" | tr -d ' ')
      ASSEMBLED_PROMPT_BYTES=$((ASSEMBLED_PROMPT_BYTES + md_bytes))
    fi
  done
  walk_dir="$(dirname "$walk_dir")"
done
if [ -f "$HOME/.claude/CLAUDE.md" ]; then
  md_bytes=$(wc -c < "$HOME/.claude/CLAUDE.md" | tr -d ' ')
  ASSEMBLED_PROMPT_BYTES=$((ASSEMBLED_PROMPT_BYTES + md_bytes))
fi
echo "ASSEMBLED_PROMPT_BYTES=$ASSEMBLED_PROMPT_BYTES (repo=$REPO issue=$ISSUE_NUM)"

# Move issue to In Progress before Claude starts
source "$SCRIPT_DIR/config/board-ids.sh"
source "$SCRIPT_DIR/config/model-routing.sh"
move_to_in_progress "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true

# Post CLAIMED marker so ghost-sweep can recognize this item as actively held
# by the build phase (consumed in phases/ghost-sweep.sh). Use comment_dedup so
# re-runs against the same issue don't spam — duplicates are the normal case.
comment_dedup "$REPO" "$ISSUE_NUM" "CLAIMED: foreman:build" >> "$LOG" 2>&1 || true

# Run Claude under run_bounded_to_file — wall-clock bound on the last
# unbounded SDK surface (closes the silent-outage class from 2026-05-08).
# 1800s = 30 min; builds normally land in 5-15 min per CLAUDE.md. The helper
# streams output directly to the issue log instead of buffering in a bash
# variable, so 30 min of verbose claude output (potentially 10-100 MB) does
# not blow up $PROBE_OUT.
echo "Building: $REPO#$ISSUE_NUM - $TITLE (attempt $CURRENT_ATTEMPT of 3)"
BUILD_TIMEOUT=1800  # 30 minutes
# Stall guard: if the issue log stops growing for this long, the build is
# wedged (e.g. claude hung on a dead API stream — R1) and run_bounded_to_file
# kills it early instead of waiting out the full BUILD_TIMEOUT. Env-tunable.
export BOUNDED_STALL_SECS="${BOUNDED_STALL_SECS:-600}"
ISSUE_LOG="$RESULTS_DIR/$DATE-issue-$ISSUE_NUM.log"

# B4: Progress watcher - log line count every 60s so orchestrator log shows
# activity. Runs until killed; we kill it after run_bounded_to_file returns.
( while true; do sleep 60; LC=$(wc -l < "$ISSUE_LOG" 2>/dev/null || echo 0); echo "  PROGRESS: $LC lines in issue-$ISSUE_NUM.log" >> "$LOG"; done ) &
PROGRESS_PID=$!

BUILD_STARTED=$(date +%s)
run_bounded_to_file "$BUILD_TIMEOUT" "$ISSUE_LOG" \
  claude -p "$(cat "$TMPFILE")" \
  --model "$BUILD_MODEL" \
  --effort high \
  --max-budget-usd "$BUILD_BUDGET" \
  --dangerously-skip-permissions
CLAUDE_EXIT="$PROBE_EXIT"

kill "$PROGRESS_PID" 2>/dev/null || true
wait "$PROGRESS_PID" 2>/dev/null || true

# Timeout failure path: claude exceeded the wall-clock bound. Treat as a
# build failure, post BUILD-FAILED (or DECISION-NEEDED on attempt 3) via
# the same dedup helper used elsewhere, then exit. Branch stays as the
# retry signal for the next cycle; the existing 3-attempt tracker handles
# the rest.
if [ "$CLAUDE_EXIT" -eq 124 ]; then
  # Distinguish a stall-kill (wedged, killed early by the BOUNDED_STALL_SECS
  # watchdog) from a genuine wall-clock timeout, so the failure comment is true.
  BUILD_ELAPSED=$(( $(date +%s) - BUILD_STARTED ))
  # 120s buffer: elapsed well under the wall-clock bound => killed early by the
  # stall watchdog, not a build that genuinely ran the full BUILD_TIMEOUT.
  if [ "$BUILD_ELAPSED" -lt $((BUILD_TIMEOUT - 120)) ]; then
    FAIL_DESC="build stalled — no output for ~${BOUNDED_STALL_SECS}s (likely a dead API stream, R1)"
  else
    FAIL_DESC="claude wall-clock timeout (${BUILD_TIMEOUT}s)"
  fi
  echo "TIMEOUT: $FAIL_DESC — killed at ${BUILD_ELAPSED}s on attempt $CURRENT_ATTEMPT of 3" >> "$ISSUE_LOG"
  LAST_LINES=$(tail -20 "$ISSUE_LOG" 2>/dev/null | head -500 || echo "No output captured")
  REMAINING=$((3 - CURRENT_ATTEMPT))

  if [ "$REMAINING" -le 0 ]; then
    comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "DECISION-NEEDED: build failed 3x (last attempt: ${FAIL_DESC})

**Branch:** \`$BRANCH\`
**Last output:**
\`\`\`
$LAST_LINES
\`\`\`

Staying in Ready. Please review and either close, update the spec, or comment to trigger a retry." "build-decision-needed" || true
    # Source-reframe (D4): Foreman couldn't ship this ticket after 3
    # tries. David doesn't want the build log; he wants to decide what
    # to do with the work.
    questions_register "build-failed-3x" "$REPO" "$ISSUE_NUM" \
      "Build failed 3 times. Last attempt: $FAIL_DESC. Branch: $BRANCH." \
      "Foreman couldn't ship \"$TITLE\" after 3 tries — what do you want to do?" \
      "The ticket is stuck in Ready and labelled blocked. Each attempt failed the same way (last: $FAIL_DESC)." \
      '["Retry as-is (just say retry)","Update the spec — I will add what to change","Close it — not worth pursuing"]' \
      "" || true
    gh issue edit "$ISSUE_NUM" --repo "$REPO" --remove-label "build-failed" --add-label "blocked" 2>/dev/null || true
  else
    comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "BUILD-FAILED: ${FAIL_DESC} on attempt $CURRENT_ATTEMPT of 3

**Branch:** \`$BRANCH\`
**Last output:**
\`\`\`
$LAST_LINES
\`\`\`

Returning to Ready for retry on next cycle. ($REMAINING attempt(s) remaining)" "build-timeout" || true
    gh issue edit "$ISSUE_NUM" --repo "$REPO" --add-label "build-failed" 2>/dev/null || true
  fi
  move_to_ready "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true
  echo "TIMEOUT: $REPO#$ISSUE_NUM — $FAIL_DESC (attempt $CURRENT_ATTEMPT)"
  exit 1
fi

# --- Local build check + push + PR creation ---
# Claude commits but does not push. We run a build check here, then push + create PR.
cd "$WORKTREE_DIR"

# Decline-cleanly path: Claude wrote `.decline-reason.md` to signal that no PR
# is warranted (bug already fixed, ticket obsolete, etc). Move to Verify for
# human/Inspector confirmation; do NOT increment the failure counter. The exit-0
# return value lets build.sh treat this as a successful build (clears tracker).
# Spec: specs/181-digest-classify-flow.md (decision 3A locks `.decline-reason.md`).
if [ -f ".decline-reason.md" ]; then
  DECLINE_REASON=$(head -50 .decline-reason.md 2>/dev/null || echo "(no reason provided)")
  echo "DECLINE: $REPO#$ISSUE_NUM declined cleanly"
  comment_dedup "$REPO" "$ISSUE_NUM" "DECLINED: build phase declined to ship a PR for this issue.

**Reason:**
\`\`\`
$DECLINE_REASON
\`\`\`

Moved to Verify so a human (or Inspector when foreman#106 ships) can confirm the issue is obsolete or otherwise resolved. Counter not incremented." >> "$LOG" 2>&1 || true
  move_to_verify "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true
  echo "OK: declined cleanly ($REPO#$ISSUE_NUM)"
  exit 0
fi

# Capture rev-list stderr instead of swallowing it. When COMMIT_COUNT lands at 0
# we still want to know *why* — rev-list error vs. honest no-op — so the daily
# log gets a distinct cause line and the no-PR comment can name the failure.
REV_LIST_ERR_FILE=$(mktemp)
COMMIT_COUNT=$(git rev-list origin/main..HEAD --count 2>"$REV_LIST_ERR_FILE") || COMMIT_COUNT=""
REV_LIST_ERR=$(head -1 "$REV_LIST_ERR_FILE" 2>/dev/null || true)
rm -f "$REV_LIST_ERR_FILE"
[ -z "$COMMIT_COUNT" ] && COMMIT_COUNT=0

# Diagnostic cause line — populated by post-Claude failure modes (SKIP-PUSH,
# BRANCH-MISSING, PR-CREATE-FAILED) so the no-PR branch names which fired.
FAIL_CAUSE=""
FAIL_CAUSE_TAG=""
FAIL_CAUSE_DETAIL=""

if [ "$COMMIT_COUNT" -eq 0 ]; then
  if [ -n "$REV_LIST_ERR" ]; then
    FAIL_CAUSE="SKIP-PUSH: $REPO#$ISSUE_NUM rev-list error: $REV_LIST_ERR"
  else
    FAIL_CAUSE="SKIP-PUSH: $REPO#$ISSUE_NUM rev-list returned 0"
  fi
  FAIL_CAUSE_TAG="build-skip-push"

  # If Claude wrote a PR body referencing a branch that ls-remote can't see,
  # that's a distinct failure class — Claude believed it pushed but didn't.
  if [ -f ".pr-body.md" ]; then
    CLAIMED_BRANCH=$(grep -oE 'auto/issue-[0-9]+[a-zA-Z0-9_-]*' ".pr-body.md" 2>/dev/null | head -1 || true)
    if [ -n "$CLAIMED_BRANCH" ] && [ -z "$(git ls-remote --heads origin "$CLAIMED_BRANCH" 2>/dev/null)" ]; then
      FAIL_CAUSE="BRANCH-MISSING: $REPO#$ISSUE_NUM $CLAIMED_BRANCH"
      FAIL_CAUSE_TAG="build-branch-missing"
    fi
  fi
  echo "$FAIL_CAUSE"
fi

if [ "$COMMIT_COUNT" -gt 0 ]; then
  # Detect build command from package.json
  BUILD_CMD=""
  if [ -f "package.json" ]; then
    BUILD_SCRIPT=""
    if jq -e '.scripts["build:frontend"]' package.json >/dev/null 2>&1; then
      BUILD_SCRIPT="build:frontend"
    elif jq -e '.scripts.build' package.json >/dev/null 2>&1; then
      BUILD_SCRIPT="build"
    fi
    if [ -n "$BUILD_SCRIPT" ]; then
      # Detect package manager from lock files
      if [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
        BUILD_CMD="bun run $BUILD_SCRIPT"
      elif [ -f "yarn.lock" ]; then
        BUILD_CMD="yarn run $BUILD_SCRIPT"
      else
        BUILD_CMD="npm run $BUILD_SCRIPT"
      fi
    fi
  fi

  # Run local build check if a command was detected
  if [ -n "$BUILD_CMD" ]; then
    # Worktree starts without node_modules — install deps before the build check.
    # Without this, tickets that touch package.json (new deps, prisma generate)
    # fail attempt 1 with "command not found" and have to be retried.
    INSTALL_CMD=""
    if [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
      INSTALL_CMD="bun install"
    elif [ -f "yarn.lock" ]; then
      INSTALL_CMD="yarn install"
    elif [ -f "package-lock.json" ]; then
      INSTALL_CMD="npm install"
    fi
    if [ -n "$INSTALL_CMD" ]; then
      echo "Installing deps in worktree: $INSTALL_CMD"
      INSTALL_LOG_FILE=$(mktemp)
      $INSTALL_CMD > "$INSTALL_LOG_FILE" 2>&1 && INSTALL_EXIT=0 || INSTALL_EXIT=$?
      if [ "$INSTALL_EXIT" -ne 0 ]; then
        INSTALL_TAIL=$(tail -20 "$INSTALL_LOG_FILE" | head -500)
        rm -f "$INSTALL_LOG_FILE"
        echo "FAIL: Dep install failed in worktree"

        REMAINING=$((3 - CURRENT_ATTEMPT))
        gh issue comment "$ISSUE_NUM" --repo "$REPO" --body "BUILD-FAILED: dep install failed in worktree (attempt $CURRENT_ATTEMPT of 3)

**Command:** \`$INSTALL_CMD\`
**Output:**
\`\`\`
$INSTALL_TAIL
\`\`\`

Returning to Ready. ($REMAINING attempt(s) remaining)" 2>/dev/null || true
        gh issue edit "$ISSUE_NUM" --repo "$REPO" --add-label "build-failed" 2>/dev/null || true
        move_to_ready "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true
        exit 1
      fi
      rm -f "$INSTALL_LOG_FILE"
    fi

    echo "Running local build check: $BUILD_CMD"
    BUILD_LOG_FILE=$(mktemp)
    $BUILD_CMD > "$BUILD_LOG_FILE" 2>&1 && BUILD_EXIT=0 || BUILD_EXIT=$?

    if [ "$BUILD_EXIT" -ne 0 ]; then
      BUILD_TAIL=$(tail -30 "$BUILD_LOG_FILE" | head -500)
      rm -f "$BUILD_LOG_FILE"
      echo "FAIL: Local build check failed"

      REMAINING=$((3 - CURRENT_ATTEMPT))
      comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "BUILD-FAILED: local build check caught failure before push (attempt $CURRENT_ATTEMPT of 3)

**Command:** \`$BUILD_CMD\`
**Output:**
\`\`\`
$BUILD_TAIL
\`\`\`

Build failed in worktree. PR was not created. ($REMAINING attempt(s) remaining)" "build-failed" || true

      if [ "$REMAINING" -le 0 ]; then
        gh issue edit "$ISSUE_NUM" --repo "$REPO" --remove-label "build-failed" --add-label "blocked" 2>/dev/null || true
        move_to_ready "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true
      else
        gh issue edit "$ISSUE_NUM" --repo "$REPO" --add-label "build-failed" 2>/dev/null || true
        move_to_ready "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true
      fi

      echo "FAIL: Local build check failed for $REPO#$ISSUE_NUM (attempt $CURRENT_ATTEMPT)"
      exit 1
    fi
    rm -f "$BUILD_LOG_FILE"
    echo "Local build check passed: $BUILD_CMD"
  else
    echo "No build command detected, skipping local build check"
  fi

  # Push branch to remote
  PUSH_ERR_FILE=$(mktemp)
  PUSH_RC=0
  git push -u origin "$BRANCH" >"$PUSH_ERR_FILE" 2>&1 || PUSH_RC=$?
  if [ "$PUSH_RC" -ne 0 ]; then
    PUSH_ERR_TAIL=$(tail -5 "$PUSH_ERR_FILE" 2>/dev/null | head -500 || true)
    rm -f "$PUSH_ERR_FILE"
    echo "FAIL: Could not push branch $BRANCH"
    # Verification gate (#238): commits exist but push to original ref failed.
    # Mark as orphan so the commit isn't lost with the worktree, and surface
    # DECISION-NEEDED. No auto-PR opens.
    mark_orphan "$REPO" "$ISSUE_NUM" "$BRANCH" "push-failed" "${PUSH_ERR_TAIL:-}" || true
    move_to_ready "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true
    exit 1
  fi
  rm -f "$PUSH_ERR_FILE"

  # Create PR — body assembled by lib/pr-body.sh (shared with orphan-rescue.sh,
  # foreman#240). Single source of truth for the Refs-not-Closes header (#233).
  PR_BODY_FILE=$(mktemp)
  build_pr_body "$WORKTREE_DIR" "$ISSUE_NUM" "$BUILD_CMD" > "$PR_BODY_FILE"

  # Capture pr-create stderr — failures (auth, rate limit, validation) used to
  # be swallowed and surface only as the generic "did not produce a PR" message.
  PR_CREATE_ERR_FILE=$(mktemp)
  PR_CREATE_RC=0
  gh pr create --repo "$REPO" --base main \
    --title "$TITLE" \
    --body-file "$PR_BODY_FILE" 2>"$PR_CREATE_ERR_FILE" || PR_CREATE_RC=$?
  if [ "$PR_CREATE_RC" -ne 0 ]; then
    PR_CREATE_FIRST_LINE=$(head -1 "$PR_CREATE_ERR_FILE" 2>/dev/null || true)
    PR_CREATE_FULL=$(cat "$PR_CREATE_ERR_FILE" 2>/dev/null || true)
    FAIL_CAUSE="PR-CREATE-FAILED: $REPO#$ISSUE_NUM ${PR_CREATE_FIRST_LINE:-unknown error}"
    FAIL_CAUSE_TAG="build-pr-create-failed"
    FAIL_CAUSE_DETAIL="$PR_CREATE_FULL"
    echo "$FAIL_CAUSE"
    rm -f "$PR_CREATE_ERR_FILE"
    rm -f "$PR_BODY_FILE"
    # Verification gate (#238): commit is pushed, but PR creation failed.
    # Without this mark, the next cycle's retry logic would graft new work on
    # top of an unverified commit. Mark as orphan and exit early.
    mark_orphan "$REPO" "$ISSUE_NUM" "$BRANCH" "pr-create-failed" "${PR_CREATE_FIRST_LINE:-unknown error}" || true
    move_to_ready "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true
    exit 1
  fi
  rm -f "$PR_CREATE_ERR_FILE"
  rm -f "$PR_BODY_FILE"
fi

# Check if PR was created
PR_URL=$(gh pr list --repo "$REPO" --head "$BRANCH" --json url -q '.[0].url' 2>/dev/null || true)

if [ -n "$PR_URL" ]; then
  # Comment on the issue with the PR link
  gh issue comment "$ISSUE_NUM" --repo "$REPO" \
    --body "PR opened: $PR_URL" 2>/dev/null || true

  # Move issue to In Review on project board
  move_to_in_review "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true

  # Worktree cleanup handled by EXIT trap
  echo "OK: $PR_URL"
  exit 0
else
  # Comment on issue about failure (Claude didn't produce commits)
  LAST_LINES=$(tail -20 "$RESULTS_DIR/$DATE-issue-$ISSUE_NUM.log" 2>/dev/null | head -500 || echo "No output captured")
  REMAINING=$((3 - CURRENT_ATTEMPT))

  if [ "$REMAINING" -le 0 ]; then
    # 3rd failure — stay in Ready, add blocked label, ask David what to do
    comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "DECISION-NEEDED: build failed 3x

Automated build failed (attempt $CURRENT_ATTEMPT of 3). Foreman has exhausted all retries.

**Branch:** \`$BRANCH\`
**Last output:**
\`\`\`
$LAST_LINES
\`\`\`

Staying in Ready. Please review and either close, update the spec, or comment to trigger a retry." "build-decision-needed" || true
    # Source-reframe (D4): no PR produced after 3 attempts. Same shape
    # as the timeout-3x case above — different upstream cause, same
    # decision shape for David.
    questions_register "build-failed-3x" "$REPO" "$ISSUE_NUM" \
      "Build ran but produced no PR for 3 attempts. Branch: $BRANCH." \
      "Foreman couldn't ship \"$TITLE\" after 3 tries — what do you want to do?" \
      "The ticket is stuck in Ready and labelled blocked. The build kept running but never opened a PR (last 3 attempts)." \
      '["Retry as-is (just say retry)","Update the spec — I will add what to change","Close it — not worth pursuing"]' \
      "" || true
    gh issue edit "$ISSUE_NUM" --repo "$REPO" --remove-label "build-failed" --add-label "blocked" 2>/dev/null || true
    move_to_ready "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true
  else
    # 1st or 2nd failure — back to Ready with label for retry. Surface the
    # cause line and any captured stderr so reviewers know which of SKIP-PUSH /
    # BRANCH-MISSING / PR-CREATE-FAILED fired instead of the generic message.
    NO_PR_CAUSE_BLOCK=""
    if [ -n "${FAIL_CAUSE:-}" ]; then
      NO_PR_CAUSE_BLOCK="**Cause:** $FAIL_CAUSE
"
    fi
    NO_PR_DETAIL_BLOCK=""
    if [ -n "${FAIL_CAUSE_DETAIL:-}" ]; then
      NO_PR_DETAIL_BLOCK="**Captured stderr:**
\`\`\`
$FAIL_CAUSE_DETAIL
\`\`\`
"
    fi
    NO_PR_TAG="${FAIL_CAUSE_TAG:-build-no-pr}"
    comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "Automated build attempted but did not produce a PR (attempt $CURRENT_ATTEMPT of 3).
${NO_PR_CAUSE_BLOCK}
**Branch:** \`$BRANCH\`
${NO_PR_DETAIL_BLOCK}**Last output:**
\`\`\`
$LAST_LINES
\`\`\`

Returning to Ready for retry on next cycle. ($REMAINING attempt(s) remaining)" "$NO_PR_TAG" || true
    gh issue edit "$ISSUE_NUM" --repo "$REPO" --add-label "build-failed" 2>/dev/null || true
    move_to_ready "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true
  fi

  # Worktree cleanup handled by EXIT trap (remote branch stays as retry signal)
  echo "FAIL: No PR created for $REPO#$ISSUE_NUM (attempt $CURRENT_ATTEMPT)"
  exit 1
fi
