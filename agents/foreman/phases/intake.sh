#!/bin/bash
# Phase 0: Intake — turn a raw idea into a spec'd GitHub issue
# Usage: intake.sh <repo> "<idea>"
# Example: intake.sh getqatalyst/Jobber "add a duplicate detection check before importing jobs"
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

REPO="$1"
IDEA="$2"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
DATE=$(date +%Y-%m-%d)
LOG="$RESULTS_DIR/$DATE.log"

mkdir -p "$RESULTS_DIR"
source "$SCRIPT_DIR/config/model-routing.sh"
source "$SCRIPT_DIR/lib/repos.sh"

PROJECT_DIR="$(repo_to_path "$REPO")"
if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  echo "FAIL: Unknown or missing project dir for $REPO"
  exit 1
fi

echo "INTAKE: $REPO — $IDEA" >> "$LOG"

# Render prompt
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

sed \
  -e "s|{PROJECT_DIR}|$PROJECT_DIR|g" \
  -e "s|{REPO}|$REPO|g" \
  "$SCRIPT_DIR/prompts/intake.md" > "$TMPFILE"

# Replace idea (can be multiline, use python for safety)
python3 -c "
import sys
idea = sys.argv[2]
with open(sys.argv[1], 'r') as f:
    content = f.read()
content = content.replace('{IDEA}', idea)
with open(sys.argv[1], 'w') as f:
    f.write(content)
" "$TMPFILE" "$IDEA"

# Run Claude (Opus for quality spec generation, needs codebase access)
RESULT_FILE="$RESULTS_DIR/$DATE-intake.log"
RESULT=$(claude -p "$(cat "$TMPFILE")" \
  --model "$INTAKE_MODEL" \
  --effort high \
  --max-budget-usd "$INTAKE_BUDGET" \
  --dangerously-skip-permissions \
  < /dev/null 2>"$RESULT_FILE") || {
  echo "  FAIL: Claude evaluation failed" >> "$LOG"
  echo "FAIL: Claude returned an error. See $RESULT_FILE"
  exit 1
}

# Parse JSON response
PARSED=$(echo "$RESULT" | python3 -c "
import json, sys

text = sys.stdin.read().strip()
# Strip markdown fences if present
if text.startswith('\`\`\`'):
    lines = text.split('\n')
    text = '\n'.join(lines[1:-1])

try:
    data = json.loads(text)
    title = data['title']
    body = data['body']
    labels = data.get('labels', ['enhancement'])
    # Output as tab-separated: title\tbody\tlabels
    print(title)
    print('---SPLIT---')
    print(body)
    print('---SPLIT---')
    print(','.join(labels))
except Exception as e:
    print(f'PARSE_ERROR: {e}', file=sys.stderr)
    print(text, file=sys.stderr)
    sys.exit(1)
" 2>>"$RESULT_FILE") || {
  echo "  FAIL: Could not parse Claude response" >> "$LOG"
  echo "FAIL: Could not parse response. See $RESULT_FILE"
  exit 1
}

TITLE=$(echo "$PARSED" | awk '/---SPLIT---/{n++; next} n==0' | head -1)
BODY=$(echo "$PARSED" | awk '/---SPLIT---/{n++; next} n==1')
LABELS=$(echo "$PARSED" | awk '/---SPLIT---/{n++; next} n==2' | head -1)

if [ -z "$TITLE" ] || [ -z "$BODY" ]; then
  echo "  FAIL: Empty title or body" >> "$LOG"
  echo "FAIL: Parsed but got empty title or body"
  exit 1
fi

# Create GitHub issue
LABEL_ARGS=""
IFS=',' read -ra LABEL_ARRAY <<< "$LABELS"
for label in "${LABEL_ARRAY[@]}"; do
  label=$(echo "$label" | xargs)  # trim whitespace
  LABEL_ARGS="$LABEL_ARGS --label $label"
done

ISSUE_URL=$(gh issue create --repo "$REPO" \
  --title "$TITLE" \
  --body "$BODY" \
  $LABEL_ARGS \
  2>/dev/null) || {
  echo "  FAIL: Could not create issue" >> "$LOG"
  echo "FAIL: gh issue create failed"
  exit 1
}

# Extract issue number from URL
ISSUE_NUM=$(echo "$ISSUE_URL" | grep -o '[0-9]*$')

# Add to project board #5 in Define status
gh project item-add 5 --owner getqatalyst --url "$ISSUE_URL" 2>/dev/null || true

echo "  CREATED: $ISSUE_URL" >> "$LOG"
echo "OK: $ISSUE_URL"
