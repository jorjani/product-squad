#!/bin/bash
# Phase 0: Verify — confirm merged PRs work in deployed environment
# Pass: move linked issue to Verify column. Fail: create bug ticket in Ready.
# Verify->Done is Inspector v0's job (phases/inspect.sh). v1 (getqatalyst/foreman#209)
# is in Pitch and extends to UI/mixed cases; David promotes manually until v1 ships.
# POSTS: Automated verification:
# READS: Automated verification:
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/config/model-routing.sh"
source "$SCRIPT_DIR/lib/repos.sh"
DATE=$(date +%Y-%m-%d)
LOG="$SCRIPT_DIR/results/$DATE.log"

# shellcheck disable=SC2207  # word-splitting on space-separated repos is intentional
REPOS=($(eligible_repos))

# Board constants + board move helpers
source "$SCRIPT_DIR/config/board-ids.sh"
# Verify-FAIL classifier (deploy-lag vs assertion-fail vs unknown).
source "$SCRIPT_DIR/lib/verify-classify.sh"
# Wall-clock + stall watchdog for the claude calls below. Without this, a hung
# claude stream (transient SDK/API issue) blocks the entire VERIFY phase until
# the orchestrator's outer 15-min phase bound fires — and the inner PGID,
# created under setsid, then survives as an orphan. See lib/bounded.sh.
# Concrete incident: 2026-05-20 11:00 cycle 3 — Sage#429 deploy-lag retry
# wedged at 0 bytes in `results/2026-05-20-verify-429-retry.log`, killed by
# the outer phase bound.
source "$SCRIPT_DIR/lib/bounded.sh"
VERIFY_CLAUDE_TIMEOUT=600                    # wall-clock per claude call
export BOUNDED_STALL_SECS="${BOUNDED_STALL_SECS:-180}"  # kill earlier if no output

VERIFIED=0
FAILED=0
SKIPPED=0
CLASS_DEPLOY_LAG=0
CLASS_ASSERTION_FAIL=0
CLASS_UNKNOWN=0
CLASS_DEFERRED=0

for REPO in "${REPOS[@]}"; do
  DEPLOY_URL="$(repo_to_url "$REPO")"
  PROJECT_DIR="$(repo_to_path "$REPO")"

  # Find PRs merged today
  MERGED_PRS=$(gh pr list --repo "$REPO" --state merged --json number,title,mergedAt,body --limit 50 2>/dev/null | python3 -c "
import json, sys, re
date = '$DATE'
prs = json.load(sys.stdin)
for pr in prs:
    merged_at = pr.get('mergedAt', '')
    if not merged_at.startswith(date):
        continue
    num = pr['number']
    title = pr['title']
    body = pr.get('body') or ''
    match = re.search(r'(?:Closes|Fixes|Resolves|Refs)\s+#(\d+)', body, re.IGNORECASE)
    linked = match.group(1) if match else ''
    print(f'{num}|{title}|{linked}')
" 2>/dev/null || true)

  [ -z "$MERGED_PRS" ] && continue

  while IFS='|' read -r PR_NUM PR_TITLE LINKED_ISSUE; do
    [ -z "$PR_NUM" ] && continue

    echo "VERIFY: $REPO PR #$PR_NUM: $PR_TITLE" >> "$LOG"
    VERDICT=""  # reset per PR; classifier sets only on FAIL path

    # Max 1 verification attempt per merged PR
    ALREADY=$(gh pr view "$PR_NUM" --repo "$REPO" --json comments --jq ".comments[] | select(.body | startswith(\"Automated verification\"))" 2>/dev/null || true)
    if [ -n "$ALREADY" ]; then
      echo "  SKIP: Already verified" >> "$LOG"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    # Foreman special case: orchestrator running = verified
    if [ "$REPO" = "getqatalyst/foreman" ]; then
      FOREMAN_PROOF="Automated verification: PASS. Foreman orchestrator is running — self-verified.

✅ Verified by Foreman: PR merged into main, orchestrator launchd job is loaded and running on schedule.
👀 Your check (sanity): glance at the next scheduled run in \`results/$DATE.log\` (or tomorrow's) to confirm the change behaves as expected end-to-end."
      gh pr comment "$PR_NUM" --repo "$REPO" --body "$FOREMAN_PROOF" 2>/dev/null || true

      if [ -n "$LINKED_ISSUE" ]; then
        gh issue comment "$LINKED_ISSUE" --repo "$REPO" --body "$FOREMAN_PROOF" 2>/dev/null || true
        move_to_verify "$REPO" "$LINKED_ISSUE" >> "$LOG" 2>&1 || true
        echo "  PASS (self-verified, #$LINKED_ISSUE -> Verify)" >> "$LOG"
      else
        echo "  PASS (self-verified, no linked issue)" >> "$LOG"
      fi
      VERIFIED=$((VERIFIED + 1))
      continue
    fi

    # CLI/no-deployment repos: verify via CI pass on merge
    if [ "$DEPLOY_URL" = "none" ]; then
      CLI_PROOF="Automated verification: PASS. No deployment URL — verified via CI pass on merge.

✅ Verified by Foreman: PR merged into main with CI green; no deployed environment to hit.
👀 Your check (sanity): pull the latest main and run the affected CLI command from this PR locally to confirm behavior."
      gh pr comment "$PR_NUM" --repo "$REPO" --body "$CLI_PROOF" 2>/dev/null || true

      if [ -n "$LINKED_ISSUE" ]; then
        gh issue comment "$LINKED_ISSUE" --repo "$REPO" --body "$CLI_PROOF" 2>/dev/null || true
        move_to_verify "$REPO" "$LINKED_ISSUE" >> "$LOG" 2>&1 || true
        echo "  PASS (no deployment, #$LINKED_ISSUE -> Verify)" >> "$LOG"
      else
        echo "  PASS (no deployment, no linked issue)" >> "$LOG"
      fi
      VERIFIED=$((VERIFIED + 1))
      continue
    fi

    # No linked issue — skip (nothing to close/track)
    if [ -z "$LINKED_ISSUE" ]; then
      echo "  SKIP: No linked issue found" >> "$LOG"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    # Reachability pre-check: skip Claude if deployment is unreachable (saves $5 budget)
    if ! curl -sf --max-time 10 "$DEPLOY_URL" >/dev/null 2>&1; then
      echo "  SKIP: Deployment unreachable ($DEPLOY_URL)" >> "$LOG"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    # Render verify prompt
    TMPFILE=$(mktemp)
    sed \
      -e "s|{REPO}|$REPO|g" \
      -e "s|{PR_NUMBER}|$PR_NUM|g" \
      -e "s|{DEPLOY_URL}|$DEPLOY_URL|g" \
      -e "s|{LINKED_ISSUE}|$LINKED_ISSUE|g" \
      "$SCRIPT_DIR/prompts/verify.md" > "$TMPFILE"

    python3 -c "
import sys
with open(sys.argv[1], 'r') as f:
    content = f.read()
content = content.replace('{PR_TITLE}', sys.argv[2])
with open(sys.argv[1], 'w') as f:
    f.write(content)
" "$TMPFILE" "$PR_TITLE"

    # Run Claude verification (Sonnet — $5 budget). Bounded so a hung stream
    # cannot run out the outer phase bound (see header comment for incident).
    cd "$PROJECT_DIR"
    run_bounded_to_file "$VERIFY_CLAUDE_TIMEOUT" "$SCRIPT_DIR/results/$DATE-verify-$PR_NUM.log" \
      claude -p "$(cat "$TMPFILE")" \
        --model "$VERIFY_MODEL" \
        --max-budget-usd "$VERIFY_BUDGET" \
        --dangerously-skip-permissions
    if [ "$PROBE_EXIT" -eq 124 ]; then
      echo "  VERIFY-TIMEOUT: claude hung on PR #$PR_NUM (killed after ${VERIFY_CLAUDE_TIMEOUT}s or ${BOUNDED_STALL_SECS}s stall)" >> "$LOG"
    fi

    # Check outcome: did the verifier post an "Automated verification: PASS"
    # comment? Issue state no longer signals success — PRs use `Refs #N`
    # (foreman#233), so a passing merged issue stays OPEN. The PASS comment on
    # the PR is the signal (same body is also posted on the issue).
    VERIFY_VERDICT=$(gh pr view "$PR_NUM" --repo "$REPO" --json comments \
      --jq '[.comments[] | select(.body | startswith("Automated verification: PASS"))] | length' \
      2>/dev/null || echo 0)

    # FAIL path: classify before acting. Three verdicts map to three actions:
    #   deploy-lag       sleep + retry once, no ticket, no FAIL comment
    #   assertion-fail   file ticket on board, comment FAIL on issue (existing flow)
    #   unknown          file ticket as today BUT tag with verify-classifier-unsure
    #                    so Inspector (foreman#106) second-looks
    if [ "$VERIFY_VERDICT" -eq 0 ]; then
      # Dedup gate: skip if this PR was already classified on a prior run.
      # Without this, a persistent deploy-lag (Railway down for hours) would
      # re-fire the 180s sleep + Claude retry on every scheduled launchd run.
      if already_classified "$SCRIPT_DIR/results" "$REPO" "$PR_NUM"; then
        echo "  SKIP: $REPO #$PR_NUM already classified on a prior run — defer to next verify cycle" >> "$LOG"
        VERDICT="already-classified"
      else
      PR_MERGED_AT=$(gh pr view "$PR_NUM" --repo "$REPO" --json mergedAt -q '.mergedAt' 2>/dev/null || echo "")
      DEPLOY_VERSION_JSON=$(curl -sf --max-time 10 "$DEPLOY_URL/api/version" 2>/dev/null || echo "")
      if [ -z "$DEPLOY_VERSION_JSON" ]; then
        DEPLOY_VERSION_JSON=$(curl -sf --max-time 10 "$DEPLOY_URL/health" 2>/dev/null || echo "")
      fi
      DEPLOY_BUILD_TIME=$(printf '%s' "$DEPLOY_VERSION_JSON" \
        | python3 -c "import json,sys
try:
  d=json.load(sys.stdin); print((d.get('buildTime') or d.get('data',{}).get('buildTime') or ''))
except Exception: pass" 2>/dev/null || echo "")
      DEPLOY_FINGERPRINT=$(printf '%s' "$DEPLOY_VERSION_JSON" \
        | python3 -c "import json,sys
try:
  d=json.load(sys.stdin); print((d.get('version') or d.get('sha') or d.get('commit') or d.get('data',{}).get('version') or ''))
except Exception: pass" 2>/dev/null || echo "")

      # Capture recent Claude/curl output so the classifier can detect transient
      # errors (timeout, 5xx, ECONNREFUSED) and route to `unknown` instead of
      # blaming the code. Bounded to 200 lines + 2000 chars so the pattern match
      # stays cheap.
      ERROR_TAIL=$(tail -200 "$SCRIPT_DIR/results/$DATE-verify-$PR_NUM.log" 2>/dev/null | tr '\n' ' ' | head -c 2000)

      VERDICT=$(classify_verify_fail "$PR_MERGED_AT" "$DEPLOY_BUILD_TIME" "" "$DEPLOY_FINGERPRINT" "$ERROR_TAIL")

      case "$VERDICT" in
        deploy-lag)
          echo "  DEPLOY-LAG: build=$DEPLOY_BUILD_TIME < merge=$PR_MERGED_AT — sleep 180s + retry once, no ticket" >> "$LOG"
          log_verify_classify "$SCRIPT_DIR/results" "$REPO" "$LINKED_ISSUE" "$PR_NUM" \
            "$PR_MERGED_AT" "$DEPLOY_BUILD_TIME" "" "$DEPLOY_FINGERPRINT" "deploy-lag" "retry-no-ticket"
          CLASS_DEPLOY_LAG=$((CLASS_DEPLOY_LAG + 1))
          sleep 180
          cd "$PROJECT_DIR"
          run_bounded_to_file "$VERIFY_CLAUDE_TIMEOUT" "$SCRIPT_DIR/results/$DATE-verify-$PR_NUM-retry.log" \
            claude -p "$(cat "$TMPFILE")" \
              --model "$VERIFY_MODEL" \
              --max-budget-usd "$VERIFY_BUDGET" \
              --dangerously-skip-permissions
          if [ "$PROBE_EXIT" -eq 124 ]; then
            echo "  VERIFY-TIMEOUT: deploy-lag retry hung on PR #$PR_NUM" >> "$LOG"
          fi
          VERIFY_VERDICT=$(gh pr view "$PR_NUM" --repo "$REPO" --json comments \
            --jq '[.comments[] | select(.body | startswith("Automated verification: PASS"))] | length' \
            2>/dev/null || echo 0)
          ;;
        assertion-fail)
          log_verify_classify "$SCRIPT_DIR/results" "$REPO" "$LINKED_ISSUE" "$PR_NUM" \
            "$PR_MERGED_AT" "$DEPLOY_BUILD_TIME" "" "$DEPLOY_FINGERPRINT" "assertion-fail" "file-ticket"
          CLASS_ASSERTION_FAIL=$((CLASS_ASSERTION_FAIL + 1))
          ;;
        unknown)
          log_verify_classify "$SCRIPT_DIR/results" "$REPO" "$LINKED_ISSUE" "$PR_NUM" \
            "$PR_MERGED_AT" "$DEPLOY_BUILD_TIME" "" "$DEPLOY_FINGERPRINT" "unknown" "file-ticket-flagged"
          CLASS_UNKNOWN=$((CLASS_UNKNOWN + 1))
          ;;
      esac
      fi  # end already_classified gate
    fi

    rm -f "$TMPFILE"

    if [ "$VERIFY_VERDICT" -gt 0 ]; then
      move_to_verify "$REPO" "$LINKED_ISSUE" >> "$LOG" 2>&1 || true
      VERIFIED=$((VERIFIED + 1))
      echo "  PASS (#$LINKED_ISSUE -> Verify)" >> "$LOG"
    elif [ "${VERDICT:-}" = "deploy-lag" ]; then
      # Retry already done above. Closed -> falls through to PASS branch above
      # (won't reach here). Still open -> deploy is genuinely lagging beyond
      # 180s; do not file a ticket, defer to next verify run.
      SKIPPED=$((SKIPPED + 1))
      CLASS_DEFERRED=$((CLASS_DEFERRED + 1))
      echo "  DEFER (deploy-lag persists, no ticket filed)" >> "$LOG"
    else
      # Claude should have created a bug issue — find it and add to board in Ready
      BUG_URL=$(gh issue list --repo "$REPO" --state open --search "Bug: verification failed for PR #$PR_NUM" --json url -q '.[0].url' 2>/dev/null || true)
      if [ -n "$BUG_URL" ]; then
        ITEM_ID=$(gh project item-add 5 --owner getqatalyst --url "$BUG_URL" --format json --jq '.id' 2>/dev/null || true)
        if [ -n "$ITEM_ID" ]; then
          gh project item-edit \
            --project-id "$PROJECT_ID" \
            --id "$ITEM_ID" \
            --field-id "$STATUS_FIELD_ID" \
            --single-select-option-id "$READY_OPTION_ID" \
            2>/dev/null || true
        fi
        # Tag unknown verdicts so Inspector (foreman#106) knows to second-look.
        if [ "${VERDICT:-}" = "unknown" ]; then
          BUG_NUM=$(printf '%s' "$BUG_URL" | sed -E 's|.*/([0-9]+)$|\1|')
          if [ -n "$BUG_NUM" ]; then
            gh issue edit "$BUG_NUM" --repo "$REPO" --add-label "verify-classifier-unsure" 2>/dev/null || true
          fi
        fi
      fi
      FAILED=$((FAILED + 1))
      echo "  FAIL (verdict=${VERDICT:-assertion-fail})" >> "$LOG"
    fi

  done <<< "$MERGED_PRS"
done

# Items stay in Verify. Inspector v0 (phases/inspect.sh) handles the Verify->Done
# gate for deterministic cases; David promotes manually for UI/mixed. v1: foreman#209.
echo "VERIFY PHASE: verified=$VERIFIED failed=$FAILED skipped=$SKIPPED deploy_lag=$CLASS_DEPLOY_LAG assertion_fail=$CLASS_ASSERTION_FAIL unknown=$CLASS_UNKNOWN deferred=$CLASS_DEFERRED" >> "$LOG"
echo "verified=$VERIFIED failed=$FAILED skipped=$SKIPPED deploy_lag=$CLASS_DEPLOY_LAG assertion_fail=$CLASS_ASSERTION_FAIL unknown=$CLASS_UNKNOWN deferred=$CLASS_DEFERRED"
