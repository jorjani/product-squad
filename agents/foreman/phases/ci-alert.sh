#!/bin/bash
# CI pile-up alerting: detect when PRs are systematically blocked by CI failures
# Creates/updates a GitHub issue in foreman repo when >3 PRs are stuck
# POSTS: (GitHub issues, not comment protocols)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATE=$(date +%Y-%m-%d)
LOG="$SCRIPT_DIR/results/$DATE.log"

# CI policy: advisory failures (e.g., SonarCloud) don't count toward pile-up.
source "$SCRIPT_DIR/config/ci-policy.sh"

REPOS=("getqatalyst/Sage" "getqatalyst/coaches" "getqatalyst/Jobber" "getqatalyst/product-studio" "getqatalyst/foreman")
ALERT_REPO="getqatalyst/foreman"
ALERT_LABEL="ci-alert"
THRESHOLD=3

# Ensure label exists
gh label create "$ALERT_LABEL" --repo "$ALERT_REPO" --color "d93f0b" 2>/dev/null || true

NOW_EPOCH=$(date +%s)
CUTOFF_SECONDS=86400  # 24 hours

BLOCKED_PRS=""
BLOCKED_COUNT=0

for REPO in "${REPOS[@]}"; do
  PRS=$(gh pr list --repo "$REPO" --state open --json number,title,headRefName,statusCheckRollup,updatedAt 2>/dev/null || echo '[]')

  while IFS='|' read -r PR_NUM PR_TITLE CI_STATUS UPDATED_AT; do
    [ -z "$PR_NUM" ] && continue
    [ "$CI_STATUS" != "fail" ] && [ "$CI_STATUS" != "pending" ] && continue

    # Check age: updatedAt must be >24h ago
    UPDATED_EPOCH=$(python3 -c "from datetime import datetime; print(int(datetime.fromisoformat('$UPDATED_AT'.replace('Z','+00:00')).timestamp()))" 2>/dev/null || echo 0)
    AGE_SECONDS=$(( NOW_EPOCH - UPDATED_EPOCH ))
    [ "$AGE_SECONDS" -lt "$CUTOFF_SECONDS" ] && continue

    AGE_HOURS=$(( AGE_SECONDS / 3600 ))
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
    BLOCKED_PRS="${BLOCKED_PRS}| ${REPO}#${PR_NUM} | [${PR_TITLE}](https://github.com/${REPO}/pull/${PR_NUM}) | ${CI_STATUS} | ${AGE_HOURS}h |
"
  done < <(echo "$PRS" | python3 -c "
import json, os, sys
advisory = set(json.loads(os.environ.get('ADVISORY_CHECKS_JSON', '[]')))
prs = json.load(sys.stdin)
for pr in prs:
    if pr.get('isDraft', False):
        continue
    num = pr['number']
    title = pr['title']
    checks = pr.get('statusCheckRollup', []) or []
    updated = pr.get('updatedAt', '')
    # Advisory checks are recommendations — exclude from pile-up signal.
    gating = [c for c in checks if (c.get('name') or '') not in advisory]
    if not checks:
        ci = 'none'
    elif not gating:
        ci = 'pass'
    elif any(c.get('conclusion') == 'FAILURE' or c.get('state') == 'FAILURE' for c in gating):
        ci = 'fail'
    elif all(c.get('conclusion') in ('SUCCESS', 'SKIPPED', 'NEUTRAL', None) or c.get('state') in ('SUCCESS', 'SKIPPED', 'NEUTRAL', None) for c in gating):
        ci = 'pass'
    else:
        ci = 'pending'
    print(f'{num}|{title}|{ci}|{updated}')
" 2>/dev/null)
done

echo "CI-ALERT: $BLOCKED_COUNT PRs blocked (threshold: $THRESHOLD)" >> "$LOG"

# Check for existing open alert issue
EXISTING_ISSUE=$(gh issue list --repo "$ALERT_REPO" --label "$ALERT_LABEL" --state open --json number --jq '.[0].number' 2>/dev/null || true)

if [ "$BLOCKED_COUNT" -gt "$THRESHOLD" ]; then
  BODY="## CI pile-up detected

**${BLOCKED_COUNT} PRs** have been blocked by CI failures/pending for >24 hours.

| Repo | PR | CI Status | Age |
|------|-----|-----------|-----|
${BLOCKED_PRS}
*Last checked: ${DATE} $(date +%H:%M)*"

  if [ -n "$EXISTING_ISSUE" ]; then
    # Update existing issue
    gh issue edit "$EXISTING_ISSUE" --repo "$ALERT_REPO" \
      --title "CI pile-up: $BLOCKED_COUNT PRs blocked across repos" \
      --body "$BODY" 2>/dev/null || true
    echo "CI-ALERT: Updated issue #$EXISTING_ISSUE" >> "$LOG"
  else
    # Create new issue
    gh issue create --repo "$ALERT_REPO" \
      --title "CI pile-up: $BLOCKED_COUNT PRs blocked across repos" \
      --label "$ALERT_LABEL" \
      --body "$BODY" 2>/dev/null || true
    echo "CI-ALERT: Created new alert issue" >> "$LOG"
  fi
elif [ -n "$EXISTING_ISSUE" ]; then
  # Pile-up resolved: close the issue
  gh issue close "$EXISTING_ISSUE" --repo "$ALERT_REPO" \
    --comment "Resolved: $BLOCKED_COUNT PRs blocked (threshold: $THRESHOLD). Pile-up cleared." 2>/dev/null || true
  echo "CI-ALERT: Closed issue #$EXISTING_ISSUE (resolved)" >> "$LOG"
fi

echo "ci_blocked=$BLOCKED_COUNT"
