#!/bin/bash
# Phase 2: Pick up Ready tickets from project board, build and ship PRs
# POSTS: Build failed 3 times (failure cap comment)
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATE=$(date +%Y-%m-%d)
LOG="$SCRIPT_DIR/results/$DATE.log"

# Threshold constants (WIP_LIMIT, MAX_BUILD_ATTEMPTS)
source "$SCRIPT_DIR/config/thresholds.sh"

# Board constants + board move helpers
source "$SCRIPT_DIR/config/board-ids.sh"

# Per-repo helpers (eligible_repos, repo_foreman_build_enabled)
source "$SCRIPT_DIR/lib/repos.sh"

ELIGIBLE_REPOS="$(eligible_repos)"
if [ -z "$ELIGIBLE_REPOS" ]; then
  echo "build.sh: eligible_repos returned empty — agents.foreman map missing from ~/Projects/.index.json?" >&2
  exit 1
fi

BUILT=0
FAILED=0
BLOCKED=0
SKIPPED_NOT_ELIGIBLE=0
SKIPPED_WIP_CAP=0

FAILURE_TRACKER="$SCRIPT_DIR/metrics/failure-tracker.json"
# Per-machine state, intentionally gitignored; do not sync across machines.
# Initialize tracker file if missing
[ -f "$FAILURE_TRACKER" ] || echo '{}' > "$FAILURE_TRACKER"

# Fetch Ready tickets from project board #5
TICKETS=$(fetch_board_items | python3 -c "
import json, sys
eligible = set('$ELIGIBLE_REPOS'.split())
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('status') != 'Ready':
        continue
    content = item.get('content', {})
    repo = content.get('repository', '')
    if repo not in eligible:
        continue
    num = content.get('number', '')
    title = item.get('title', '')
    if num and title:
        print(f'{repo}|{num}|{title}')
" 2>/dev/null || true)

if [ -z "$TICKETS" ]; then
  echo "BUILD PHASE: No Ready tickets found" >> "$LOG"
  echo "No Ready tickets"
  exit 0
fi

while IFS='|' read -r REPO ISSUE_NUM TITLE; do
  [ -z "$REPO" ] && continue

  ISSUE_KEY="${REPO}#${ISSUE_NUM}"

  # Per-repo build flag: board.foreman_build=false in ~/Projects/.index.json
  # opts a repo out of auto-build while keeping it on the project board for
  # visibility. Default true when absent. Build slot is NOT consumed.
  FOREMAN_BUILD_FLAG=$(repo_foreman_build_enabled "$REPO")
  if [ "$FOREMAN_BUILD_FLAG" = "false" ]; then
    echo "BUILD: $REPO#$ISSUE_NUM - $TITLE" >> "$LOG"
    echo "  SKIP: $REPO has board.foreman_build=false — not eligible for auto-build" >> "$LOG"
    SKIPPED_NOT_ELIGIBLE=$((SKIPPED_NOT_ELIGIBLE + 1))
    continue
  fi

  # WIP limit: if repo has >= WIP_LIMIT open PRs, review oldest first before building
  OPEN_PR_COUNT=$(gh pr list --repo "$REPO" --state open --json number | jq length 2>/dev/null || echo "0")
  if [ "$OPEN_PR_COUNT" -ge "$WIP_LIMIT" ]; then
    echo "BUILD: $REPO#$ISSUE_NUM - $TITLE" >> "$LOG"
    echo "  WIP limit reached for $REPO ($OPEN_PR_COUNT open PRs), reviewing oldest first" >> "$LOG"
    OLDEST_PR=$(gh pr list --repo "$REPO" --state open --json number,createdAt \
      --jq 'sort_by(.createdAt) | .[0].number' 2>/dev/null || true)
    if [ -n "$OLDEST_PR" ]; then
      if "$SCRIPT_DIR/phases/review.sh" >> "$LOG" 2>&1; then
        # If review resulted in a merge, recheck the count and possibly continue
        OPEN_PR_COUNT=$(gh pr list --repo "$REPO" --state open --json number | jq length 2>/dev/null || echo "$WIP_LIMIT")
        if [ "$OPEN_PR_COUNT" -ge "$WIP_LIMIT" ]; then
          echo "  WIP: review did not free a slot for $REPO, skipping build" >> "$LOG"
          continue
        fi
        echo "  WIP: review freed a slot for $REPO, proceeding with build" >> "$LOG"
      else
        echo "  WIP: review phase flagged issues for PR #$OLDEST_PR, skipping build" >> "$LOG"
        continue
      fi
    else
      echo "  WIP: could not determine oldest PR for $REPO, skipping build" >> "$LOG"
      continue
    fi
  fi

  # Right-to-left: skip if repo already has WIP_LIMIT+ open auto/ PRs
  OPEN_AUTO_PR_COUNT=$(gh pr list --repo "$REPO" --state open --json headRefName -q ".[].headRefName" 2>/dev/null | grep -c "^auto/" || true)
  if [ "$OPEN_AUTO_PR_COUNT" -ge "$WIP_LIMIT" ]; then
    echo "BUILD: $REPO#$ISSUE_NUM - $TITLE" >> "$LOG"
    echo "  SKIP: $REPO has $OPEN_AUTO_PR_COUNT open auto/ PRs (WIP limit: $WIP_LIMIT) — finish existing work first" >> "$LOG"
    SKIPPED_WIP_CAP=$((SKIPPED_WIP_CAP + 1))
    continue
  fi

  # Skip if issue is already closed (board status may be stale)
  ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "OPEN")
  if [ "$ISSUE_STATE" = "CLOSED" ]; then
    echo "BUILD: $REPO#$ISSUE_NUM - $TITLE" >> "$LOG"
    echo "  SKIP: Issue is closed (board stale), moving to Verify for Inspector" >> "$LOG"
    move_to_verify "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true
    # Clear any stale tracker entry: the issue is done, will not iterate this loop again.
    if jq -e --arg key "$ISSUE_KEY" '.[$key]' "$FAILURE_TRACKER" >/dev/null 2>&1; then
      jq --arg key "$ISSUE_KEY" 'del(.[$key])' "$FAILURE_TRACKER" > "${FAILURE_TRACKER}.tmp" \
        && mv "${FAILURE_TRACKER}.tmp" "$FAILURE_TRACKER"
    fi
    continue
  fi

  # --- Failure cap: check if this issue is blocked ---
  IS_BLOCKED=$(jq -r --arg key "$ISSUE_KEY" '.[$key].blocked // false' "$FAILURE_TRACKER" 2>/dev/null || echo "false")
  if [ "$IS_BLOCKED" = "true" ]; then
    # Reset condition: human moved it back to Ready (it's in this list, so it IS Ready)
    # The fact that we're iterating it means it's currently "Ready" on the board.
    # Reset the tracker and allow the build.
    jq --arg key "$ISSUE_KEY" \
      '.[$key] = {"failures": 0, "last_failed": .[$key].last_failed, "blocked": false, "reset_date": (now | strftime("%Y-%m-%d"))}' \
      "$FAILURE_TRACKER" > "${FAILURE_TRACKER}.tmp" && mv "${FAILURE_TRACKER}.tmp" "$FAILURE_TRACKER"
    echo "RESET: $ISSUE_KEY was blocked but is back in Ready — resetting failure count" >> "$LOG"
  fi

  echo "BUILD: $REPO#$ISSUE_NUM - $TITLE" >> "$LOG"

  if "$SCRIPT_DIR/phases/build-ticket.sh" "$REPO" "$ISSUE_NUM" "$TITLE" >> "$LOG" 2>&1; then
    BUILT=$((BUILT + 1))
    echo "  OK" >> "$LOG"
    # Clear failure count on success
    if jq -e --arg key "$ISSUE_KEY" '.[$key]' "$FAILURE_TRACKER" >/dev/null 2>&1; then
      jq --arg key "$ISSUE_KEY" 'del(.[$key])' "$FAILURE_TRACKER" > "${FAILURE_TRACKER}.tmp" \
        && mv "${FAILURE_TRACKER}.tmp" "$FAILURE_TRACKER"
    fi
  else
    FAILED=$((FAILED + 1))
    echo "  FAIL" >> "$LOG"

    # --- Failure cap: record failure ---
    PREV_FAILURES=$(jq -r --arg key "$ISSUE_KEY" '.[$key].failures // 0' "$FAILURE_TRACKER" 2>/dev/null || echo "0")
    NEW_FAILURES=$((PREV_FAILURES + 1))

    if [ "$NEW_FAILURES" -ge 3 ]; then
      # Block the issue and move to Scope
      jq --arg key "$ISSUE_KEY" --arg date "$DATE" --argjson count "$NEW_FAILURES" \
        '.[$key] = {"failures": $count, "last_failed": $date, "blocked": true}' \
        "$FAILURE_TRACKER" > "${FAILURE_TRACKER}.tmp" && mv "${FAILURE_TRACKER}.tmp" "$FAILURE_TRACKER"

      BLOCKED=$((BLOCKED + 1))
      echo "  BLOCKED: $ISSUE_KEY has failed $NEW_FAILURES times, blocking" >> "$LOG"

      # Move issue to Blocked on the project board so Foreman will not re-pick it.
      # Scope is Sarge's active work surface; Blocked is the graveyard for stuck tickets.
      move_to_blocked "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true

      # Comment on the issue about blocking
      gh issue comment "$ISSUE_NUM" --repo "$REPO" --body "Build failed 3 times. Moving to Blocked. Last failure: $DATE. This issue will not be retried until it is moved back to Ready." 2>/dev/null || true

    else
      # Record failure but don't block yet
      jq --arg key "$ISSUE_KEY" --arg date "$DATE" --argjson count "$NEW_FAILURES" \
        '.[$key] = {"failures": $count, "last_failed": $date, "blocked": false}' \
        "$FAILURE_TRACKER" > "${FAILURE_TRACKER}.tmp" && mv "${FAILURE_TRACKER}.tmp" "$FAILURE_TRACKER"
    fi
  fi
done <<< "$TICKETS"

echo "BUILD PHASE: built=$BUILT failed=$FAILED blocked=$BLOCKED skipped_wip_cap=$SKIPPED_WIP_CAP skipped_not_eligible=$SKIPPED_NOT_ELIGIBLE" >> "$LOG"

# Emit BUILD-SKIPPED when the cycle produced no work solely because every
# candidate was filtered by the eligibility flag or the WIP cap. This is
# intentional behavior, not a stall — stall alerts should not fire.
if [ "$BUILT" -eq 0 ] && [ "$FAILED" -eq 0 ] && [ "$BLOCKED" -eq 0 ] \
   && [ $((SKIPPED_WIP_CAP + SKIPPED_NOT_ELIGIBLE)) -gt 0 ]; then
  echo "BUILD-SKIPPED: wip_cap=$SKIPPED_WIP_CAP not_eligible=$SKIPPED_NOT_ELIGIBLE" >> "$LOG"
fi

echo "built=$BUILT failed=$FAILED blocked=$BLOCKED skipped_wip_cap=$SKIPPED_WIP_CAP skipped_not_eligible=$SKIPPED_NOT_ELIGIBLE"
