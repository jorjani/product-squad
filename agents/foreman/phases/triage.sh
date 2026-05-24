#!/bin/bash
# Phase 3: Triage Backlog tickets — promote buildable ones to Ready
# Also handles dependency gating: if "Depends on #N" refs exist and are open, skip (not a spec problem)
# POSTS: NEEDS-SPEC:, Automated triage: promoted
# READS: NEEDS-SPEC:, SPEC-UPDATED:, Automated triage
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATE=$(date +%Y-%m-%d)
LOG="$SCRIPT_DIR/results/$DATE.log"

# Board constants + board move helpers
source "$SCRIPT_DIR/config/board-ids.sh"
source "$SCRIPT_DIR/config/model-routing.sh"
source "$SCRIPT_DIR/lib/comments.sh"
source "$SCRIPT_DIR/lib/repos.sh"

ELIGIBLE_REPOS="$(eligible_repos)"

PROMOTED=0
COMMENTED=0
SKIPPED=0

# Fetch Backlog tickets from project board #5
TICKETS=$(fetch_board_items | python3 -c "
import json, sys
eligible = set('$ELIGIBLE_REPOS'.split())
data = json.load(sys.stdin)
for item in data.get('items', []):
    status = item.get('status', '')
    if status not in ('Backlog',):
        continue
    content = item.get('content', {})
    repo = content.get('repository', '')
    if repo not in eligible:
        continue
    num = content.get('number', '')
    title = item.get('title', '')
    item_id = item.get('id', '')
    if num and title and item_id:
        print(f'{repo}|{num}|{item_id}|{title}')
" 2>/dev/null || true)

if [ -z "$TICKETS" ]; then
  echo "TRIAGE PHASE: No Backlog tickets found" >> "$LOG"
  echo "No Backlog tickets"
  exit 0
fi

while IFS='|' read -r REPO ISSUE_NUM ITEM_ID TITLE; do
  [ -z "$REPO" ] && continue

  echo "TRIAGE: $REPO#$ISSUE_NUM - $TITLE" >> "$LOG"

  # Skip if issue is already closed (board stale)
  ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "OPEN")
  if [ "$ISSUE_STATE" = "CLOSED" ]; then
    echo "  SKIP: Issue is closed (board stale), moving to Verify for Inspector" >> "$LOG"
    move_to_verify "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Decide whether to (re)triage. This phase only ever fetches Backlog items
  # (status filter above), so a last marker of "Automated triage: promoted"
  # means the item was promoted to Ready, then regressed back to Backlog (a
  # manual drag, a Blocked->Backlog move, a build-failure sweep). The promotion
  # is void -- re-evaluate it. Only "waiting" (NEEDS-SPEC posted, no SPEC-UPDATED
  # response yet) is skipped, to avoid re-spamming the author.
  TRIAGE_STATUS=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json comments --jq '
    [.comments[] | select(.body | startswith("Automated triage") or startswith("NEEDS-SPEC:") or startswith("SPEC-UPDATED:"))]
    | if length == 0 then "new"
      elif (last.body | startswith("SPEC-UPDATED:")) then "re-triage"
      elif (last.body | startswith("Automated triage: promoted")) then "stale-promote"
      else "waiting"
      end
  ' 2>/dev/null || echo "new")
  if [ "$TRIAGE_STATUS" = "waiting" ]; then
    echo "  SKIP: Awaiting SPEC-UPDATED response to prior NEEDS-SPEC" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  if [ "$TRIAGE_STATUS" = "re-triage" ]; then
    echo "  RE-TRIAGE: Spec was updated since last NEEDS-SPEC" >> "$LOG"
  elif [ "$TRIAGE_STATUS" = "stale-promote" ]; then
    echo "  RE-TRIAGE: stale 'promoted' marker, item is back in Backlog (regressed)" >> "$LOG"
  fi

  # Fetch issue body
  ISSUE_BODY=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json body -q '.body' 2>/dev/null) || {
    echo "  SKIP: Could not fetch issue body" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  }

  # Dependency gate: if "Depends on #N" exists and any dep is open, skip (not a spec problem)
  OPEN_DEPS=$(echo "$ISSUE_BODY" | python3 -c "
import sys, re
text = sys.stdin.read()
nums = [m[0] or m[1] for m in re.findall(r'[Dd]epends\s+on\s+(?:[\w/.-]+#(\d+)|#(\d+))', text)]
print(','.join(nums))
" 2>/dev/null || echo "")

  if [ -n "$OPEN_DEPS" ]; then
    ALL_DEPS_CLOSED="true"
    BLOCKING_DEPS=""
    for DEP_NUM in $(echo "$OPEN_DEPS" | tr ',' ' '); do
      DEP_STATE=$(gh issue view "$DEP_NUM" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "OPEN")
      if [ "$DEP_STATE" != "CLOSED" ]; then
        ALL_DEPS_CLOSED="false"
        BLOCKING_DEPS="${BLOCKING_DEPS} #${DEP_NUM}"
      fi
    done

    if [ "$ALL_DEPS_CLOSED" = "false" ]; then
      echo "  SKIP: Blocked by open dependencies:${BLOCKING_DEPS}" >> "$LOG"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    # All deps closed — proceed with normal evaluation
    echo "  DEPS: All dependencies resolved, evaluating" >> "$LOG"
  fi

  # Render triage prompt
  TMPFILE=$(mktemp)
  trap 'rm -f "$TMPFILE"' EXIT

  sed \
    -e "s|{REPO}|$REPO|g" \
    -e "s|{ISSUE_NUMBER}|$ISSUE_NUM|g" \
    "$SCRIPT_DIR/prompts/triage.md" > "$TMPFILE"

  READY_CHECKLIST=$(cat "$SCRIPT_DIR/config/ready-templates.md" 2>/dev/null || echo "")
  export READY_CHECKLIST
  python3 -c "
import sys, os
body = sys.stdin.read()
with open(sys.argv[1], 'r') as f:
    content = f.read()
content = content.replace('{ISSUE_TITLE}', sys.argv[2])
content = content.replace('{ISSUE_BODY}', body)
content = content.replace('{READY_CHECKLIST}', os.environ.get('READY_CHECKLIST', ''))
with open(sys.argv[1], 'w') as f:
    f.write(content)
" "$TMPFILE" "$TITLE" <<< "$ISSUE_BODY"

  # Run Claude evaluation (Sonnet — lighter model for triage)
  EVAL_RESULT=$(claude -p "$(cat "$TMPFILE")" \
    --model "$TRIAGE_MODEL" \
    --max-budget-usd "$TRIAGE_BUDGET" \
    --dangerously-skip-permissions \
    < /dev/null 2>/dev/null) || {
    echo "  SKIP: Claude evaluation failed" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    rm -f "$TMPFILE"
    continue
  }

  rm -f "$TMPFILE"

  # Parse structured JSON response
  BUILDABLE=$(echo "$EVAL_RESULT" | python3 -c "
import json, sys
text = sys.stdin.read().strip()
# Handle potential markdown fences
if text.startswith('\`\`\`'):
    lines = text.split('\n')
    text = '\n'.join(lines[1:-1])
try:
    result = json.loads(text)
    print('true' if result.get('buildable') else 'false')
except:
    print('error')
" 2>/dev/null || echo "error")

  if [ "$BUILDABLE" = "true" ]; then
    # Promote to Ready
    gh project item-edit \
      --project-id "$PROJECT_ID" \
      --id "$ITEM_ID" \
      --field-id "$STATUS_FIELD_ID" \
      --single-select-option-id "$READY_OPTION_ID" \
      2>/dev/null || {
      echo "  FAIL: Could not promote item" >> "$LOG"
      SKIPPED=$((SKIPPED + 1))
      continue
    }

    gh issue comment "$ISSUE_NUM" --repo "$REPO" --body "Automated triage: promoted to **Ready**. This ticket has sufficient specification for autonomous build." 2>/dev/null || true

    echo "  PROMOTED to Ready" >> "$LOG"
    PROMOTED=$((PROMOTED + 1))

  elif [ "$BUILDABLE" = "false" ]; then
    # Parse missing items
    MISSING=$(echo "$EVAL_RESULT" | python3 -c "
import json, sys
text = sys.stdin.read().strip()
if text.startswith('\`\`\`'):
    lines = text.split('\n')
    text = '\n'.join(lines[1:-1])
try:
    result = json.loads(text)
    items = result.get('missing', [])
    for item in items:
        print(f'- {item}')
except:
    print('- Could not parse evaluation details')
" 2>/dev/null || echo "- Could not parse evaluation details")

    comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "NEEDS-SPEC: This ticket is missing required specification.

**Missing:**
$MISSING

_Sarge or the ticket author should update the issue. It will be re-evaluated on the next triage run._" "needs-spec" || true

    echo "  COMMENTED: needs spec" >> "$LOG"
    COMMENTED=$((COMMENTED + 1))

  else
    echo "  SKIP: Could not parse evaluation result" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
  fi

done <<< "$TICKETS"

echo "TRIAGE PHASE: promoted=$PROMOTED commented=$COMMENTED skipped=$SKIPPED" >> "$LOG"
echo "promoted=$PROMOTED commented=$COMMENTED skipped=$SKIPPED"
