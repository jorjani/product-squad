#!/bin/bash
# Phase: Sarge-Pitch — daily first-pass recon of Pitch items.
#
# Iterates project board #5 Pitch items whose repo has agents.sarge includes
# "scope" in ~/Projects/.index.json (pitch is upstream of scope — same flag).
# For each eligible item lacking a current SARGE-DRAFT: comment, invokes the
# Sarge prompt (prompts/sarge-pitch.md) and posts a single SARGE-DRAFT: comment
# containing questions for David, an ASCII wireframe (UI tickets only), and a
# draft brief.
#
# Never mutates the board column — David promotes Pitch → Scope manually.
#
# Re-fire trigger: byte-identical body dedup via comment_dedup_or_escalate.
# When David replies in-thread or edits the issue body, Sarge's response text
# changes, so the helper posts a fresh draft.
#
# Cap: SARGE_PITCH_CAP (3) items per run; items beyond cap roll forward and
# are named in the per-run summary.
#
# POSTS: SARGE-DRAFT:, ESCALATE-DEDUP (via comments.sh helper)
# READS: SARGE-DRAFT: (recent), full issue body, full comment thread
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
DATE=$(date +%Y-%m-%d)
LOG="$RESULTS_DIR/$DATE.log"

mkdir -p "$RESULTS_DIR"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config/board-ids.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config/model-routing.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/comments.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/repos.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/questions.sh"

SARGE_PITCH_CAP=3

ELIGIBLE_REPOS="$(sarge_eligible_repos)"
if [ -z "$ELIGIBLE_REPOS" ]; then
  echo "SARGE-PITCH PHASE: No repos with agents.sarge includes 'scope'" >> "$LOG"
  echo "drafted=0 skipped=0 deferred=0"
  exit 0
fi

PITCH_ITEMS=$(fetch_board_items | python3 -c "
import json, sys
eligible = set('$ELIGIBLE_REPOS'.split())
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('status', '') != 'Pitch':
        continue
    c = item.get('content', {})
    repo = c.get('repository', '')
    if repo not in eligible:
        continue
    num = c.get('number', '')
    title = item.get('title', '')
    iid = item.get('id', '')
    if num and iid:
        print(f'{repo}|{num}|{iid}|{title}')
" 2>/dev/null || true)

if [ -z "$PITCH_ITEMS" ]; then
  echo "SARGE-PITCH PHASE: No Pitch items on board (eligible repos: $ELIGIBLE_REPOS)" >> "$LOG"
  echo "drafted=0 skipped=0 deferred=0"
  exit 0
fi

DRAFTED=0
SKIPPED=0
DEFERRED=0
DEFERRED_LIST=""

while IFS='|' read -r REPO ISSUE_NUM ITEM_ID TITLE; do
  [ -z "$REPO" ] && continue

  if [ "$DRAFTED" -ge "$SARGE_PITCH_CAP" ]; then
    DEFERRED=$((DEFERRED + 1))
    DEFERRED_LIST="${DEFERRED_LIST} ${REPO}#${ISSUE_NUM}"
    continue
  fi

  PROJECT_DIR="$(repo_to_path "$REPO")"

  ISSUE_DATA=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json title,body,comments 2>/dev/null) || {
    echo "SARGE-PITCH: $REPO#$ISSUE_NUM FAIL (could not fetch issue)" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  }
  ISSUE_TITLE=$(echo "$ISSUE_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('title',''))" 2>/dev/null)
  ISSUE_BODY=$(echo "$ISSUE_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('body',''))" 2>/dev/null)
  COMMENT_THREAD=$(echo "$ISSUE_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
lines = []
for c in data.get('comments', []):
    author = (c.get('author') or {}).get('login', 'unknown')
    body = c.get('body', '').strip()
    if body:
        lines.append(f'### @{author}')
        lines.append(body)
        lines.append('')
print('\n'.join(lines) if lines else '_(no comments yet)_')
" 2>/dev/null || echo "_(no comments yet)_")

  CODEBASE_CONTEXT=""
  if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
    for f in ".studio/project.json" ".studio/context.md" ".studio/features.yaml" ".studio/design.md" "CLAUDE.md" ".claude/CLAUDE.md" ".studio/SCHEMA.md"; do
      if [ -f "$PROJECT_DIR/$f" ]; then
        CODEBASE_CONTEXT="${CODEBASE_CONTEXT}### $f"$'\n\n'"$(cat "$PROJECT_DIR/$f")"$'\n\n'
      fi
    done
  fi

  echo "SARGE-PITCH: $REPO#$ISSUE_NUM - $TITLE" >> "$LOG"

  TMPFILE=$(mktemp)
  sed \
    -e "s|{REPO}|$REPO|g" \
    -e "s|{ISSUE_NUMBER}|$ISSUE_NUM|g" \
    "$SCRIPT_DIR/prompts/sarge-pitch.md" > "$TMPFILE"

  export ISSUE_BODY ISSUE_TITLE CODEBASE_CONTEXT COMMENT_THREAD
  python3 -c "
import os, sys
with open(sys.argv[1]) as f:
    c = f.read()
c = c.replace('{ISSUE_TITLE}', os.environ.get('ISSUE_TITLE', ''))
c = c.replace('{ISSUE_BODY}', os.environ.get('ISSUE_BODY', ''))
c = c.replace('{CODEBASE_CONTEXT}', os.environ.get('CODEBASE_CONTEXT', ''))
c = c.replace('{COMMENT_THREAD}', os.environ.get('COMMENT_THREAD', ''))
with open(sys.argv[1], 'w') as f:
    f.write(c)
" "$TMPFILE"

  RESULT_FILE="$RESULTS_DIR/$DATE-sarge-pitch-$ISSUE_NUM.log"
  SARGE_RESULT=$(claude -p "$(cat "$TMPFILE")" \
    --model "$SARGE_PITCH_MODEL" \
    --max-budget-usd "$SARGE_PITCH_BUDGET" \
    --dangerously-skip-permissions \
    < /dev/null 2>"$RESULT_FILE") || {
    echo "  SKIP: Claude invocation failed (see $RESULT_FILE)" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    rm -f "$TMPFILE"
    continue
  }
  # Persist captured stdout alongside stderr; otherwise success-path log is empty.
  # Guard against empty SARGE_RESULT so the file stays 0 bytes (signal "phase ran clean")
  # rather than 1 byte of whitespace.
  [ -n "$SARGE_RESULT" ] && printf '%s\n' "$SARGE_RESULT" >> "$RESULT_FILE"
  rm -f "$TMPFILE"

  SARGE_JSON=$(echo "$SARGE_RESULT" | python3 -c "
import json, sys, re
t = sys.stdin.read().strip()
m = re.search(r'\`\`\`(?:json)?\s*\n(.*?)\n\`\`\`', t, re.DOTALL)
if m:
    t = m.group(1).strip()
if not t.startswith('{'):
    m = re.search(r'(\{.*\})', t, re.DOTALL)
    if m:
        t = m.group(1)
try:
    print(json.dumps(json.loads(t)))
except Exception as e:
    print(f'PARSE_ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>>"$RESULT_FILE") || {
    echo "  PARSE FAIL: Sarge response was malformed (see $RESULT_FILE)" >> "$LOG"
    comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "DECISION-NEEDED: Foreman sarge-pitch could not parse Sarge's JSON response. @jorjani please review the pitch manually. Diagnostic log: \`$RESULT_FILE\`" "sarge-pitch-parse-fail" || true
    questions_register "sarge-pitch-parse-fail" "$REPO" "$ISSUE_NUM" \
      "Sarge first-pass pitch run failed to produce a usable response. Diagnostic log: $RESULT_FILE" \
      "" "" "[]" "" || true
    SKIPPED=$((SKIPPED + 1))
    continue
  }

  ACTION=$(echo "$SARGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('action',''))" 2>/dev/null)

  case "$ACTION" in
    draft)
      COMMENT_BODY=$(echo "$SARGE_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
questions = d.get('questions', []) or []
wireframe = d.get('wireframe', '') or ''
brief = d.get('brief', '') or ''
lines = ['SARGE-DRAFT: First-pass recon on this pitch.', '']
if questions:
    lines.append('**Questions for @jorjani:**')
    for q in questions:
        lines.append(f'- {q}')
    lines.append('')
if wireframe.strip():
    lines.append('**Wireframe:**')
    lines.append('\`\`\`')
    lines.append(wireframe.rstrip())
    lines.append('\`\`\`')
    lines.append('')
if brief.strip():
    lines.append('**Draft brief:**')
    lines.append(brief.strip())
    lines.append('')
lines.append('_Pitch column unchanged — promote to Scope when ready._')
print('\n'.join(lines))
" 2>/dev/null) || {
        echo "  SKIP: could not assemble comment body (see $RESULT_FILE)" >> "$LOG"
        SKIPPED=$((SKIPPED + 1))
        continue
      }
      if [ -z "$COMMENT_BODY" ]; then
        echo "  SKIP: empty comment body" >> "$LOG"
        SKIPPED=$((SKIPPED + 1))
        continue
      fi
      if comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "$COMMENT_BODY" "sarge-pitch-draft"; then
        echo "  DRAFTED" >> "$LOG"
        DRAFTED=$((DRAFTED + 1))
      else
        echo "  FAIL: comment post failed" >> "$LOG"
        SKIPPED=$((SKIPPED + 1))
      fi
      ;;
    skip)
      REASON=$(echo "$SARGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('reason','no reason given'))" 2>/dev/null)
      echo "  SKIP (Sarge): $REASON" >> "$LOG"
      SKIPPED=$((SKIPPED + 1))
      ;;
    *)
      echo "  SKIP: unknown action='$ACTION' (see $RESULT_FILE)" >> "$LOG"
      SKIPPED=$((SKIPPED + 1))
      ;;
  esac

done <<< "$PITCH_ITEMS"

if [ "$DEFERRED" -gt 0 ]; then
  echo "SARGE-PITCH: deferred $DEFERRED items beyond cap=$SARGE_PITCH_CAP:${DEFERRED_LIST}" >> "$LOG"
fi

echo "SARGE-PITCH PHASE: drafted=$DRAFTED skipped=$SKIPPED deferred=$DEFERRED" >> "$LOG"
echo "drafted=$DRAFTED skipped=$SKIPPED deferred=$DEFERRED"
