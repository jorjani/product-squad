#!/bin/bash
# Phase: Sarge-Review — daily proactive recon of Scope items.
#
# Iterates project board #5 Scope items whose repo has agents.sarge includes
# "scope" in ~/Projects/.index.json. For each eligible item, invokes the
# existing Sarge prompt (prompts/sarge-review.md) and dispatches the JSON
# response: enrich/ready promote to Backlog, decision_needed leaves at Scope
# with a DECISION-NEEDED comment.
#
# Items that already have a spec doc on disk (specs/<num>-*.md) are promoted
# straight to Backlog — a committed spec doc means scoping is done. Items with
# a SPEC-UPDATED bot comment within the last 24h are skipped — Sarge does not
# redo recent work.
#
# Cap: SARGE_REVIEW_CAP (3) Claude-recon items per run; items beyond cap roll
# forward and are named in the per-run summary. Spec-doc promotes (a single
# cheap board call, no Claude invocation) are exempt from the cap and counted
# separately as spec_promoted.
#
# POSTS: SPEC-UPDATED:, DECISION-NEEDED:, ESCALATE-DEDUP (via comments.sh helper)
# READS: SPEC-UPDATED: (recent)
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

SARGE_REVIEW_CAP=3

ELIGIBLE_REPOS="$(sarge_eligible_repos)"
if [ -z "$ELIGIBLE_REPOS" ]; then
  echo "SARGE-REVIEW PHASE: No repos with agents.sarge includes 'scope'" >> "$LOG"
  echo "scoped=0 spec_promoted=0 skipped=0 deferred=0"
  exit 0
fi

# Pull Scope items, filter to eligible repos
SCOPE_ITEMS=$(fetch_board_items | python3 -c "
import json, sys
eligible = set('$ELIGIBLE_REPOS'.split())
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('status', '') != 'Scope':
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

if [ -z "$SCOPE_ITEMS" ]; then
  echo "SARGE-REVIEW PHASE: No Scope items on board (eligible repos: $ELIGIBLE_REPOS)" >> "$LOG"
  echo "scoped=0 spec_promoted=0 skipped=0 deferred=0"
  exit 0
fi

SCOPED=0
SPEC_PROMOTED=0
SKIPPED=0
DEFERRED=0
DEFERRED_LIST=""

while IFS='|' read -r REPO ISSUE_NUM ITEM_ID TITLE; do
  [ -z "$REPO" ] && continue

  PROJECT_DIR="$(repo_to_path "$REPO")"

  # Spec doc already committed → scoping is done. Promote to Backlog so triage
  # evaluates it. This branch previously skipped (continue without promoting),
  # which permanently stranded fully-scoped tickets: sarge-review won't re-recon
  # an item that already has a spec doc, and triage.sh only reads the Backlog
  # column. See getqatalyst/foreman#292 (foreman #209/#210/#233/#240/#272 sat
  # in Scope for days with committed spec docs and zero pipeline activity).
  #
  # Exempt from the cap gate below and counted in its own SPEC_PROMOTED tally:
  # this is one cheap board API call, no Claude invocation. SARGE_REVIEW_CAP
  # throttles expensive recon — counting cheap promotes against it strands the
  # Claude-recon path behind already-scoped tickets. See getqatalyst/foreman#298.
  if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR/specs" ]; then
    if compgen -G "$PROJECT_DIR/specs/${ISSUE_NUM}-*.md" >/dev/null 2>&1; then
      gh project item-edit \
        --project-id "$PROJECT_ID" --id "$ITEM_ID" \
        --field-id "$STATUS_FIELD_ID" \
        --single-select-option-id "$BACKLOG_OPTION_ID" \
        2>>"$LOG" || echo "  WARN: board promote to Backlog failed" >> "$LOG"
      echo "SARGE-REVIEW: $REPO#$ISSUE_NUM SPEC-DOC -> Backlog (scoping complete)" >> "$LOG"
      SPEC_PROMOTED=$((SPEC_PROMOTED + 1))
      continue
    fi
  fi

  # Cap gate: throttles expensive Claude recon. Spec-doc promotes above run no
  # Claude call and are intentionally exempt — they continue out before here.
  if [ "$SCOPED" -ge "$SARGE_REVIEW_CAP" ]; then
    DEFERRED=$((DEFERRED + 1))
    DEFERRED_LIST="${DEFERRED_LIST} ${REPO}#${ISSUE_NUM}"
    continue
  fi

  # Skip: recent SPEC-UPDATED bot comment (< 24h). Prevents re-running Sarge
  # on an item that auto-enrich or a prior Sarge pass just touched.
  RECENT_SU=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json comments -q '
    [.comments[] | select(.body | startswith("SPEC-UPDATED:"))] | last | .createdAt // ""
  ' 2>/dev/null || echo "")
  if [ -n "$RECENT_SU" ] && [ "$RECENT_SU" != "null" ]; then
    AGE_HRS=$(python3 -c "
from datetime import datetime, timezone
ts = '$RECENT_SU'.replace('Z', '+00:00')
delta = datetime.now(timezone.utc) - datetime.fromisoformat(ts)
print(int(delta.total_seconds() // 3600))
" 2>/dev/null || echo "999")
    if [ "$AGE_HRS" -lt 24 ]; then
      echo "SARGE-REVIEW: $REPO#$ISSUE_NUM SKIP (SPEC-UPDATED ${AGE_HRS}h ago)" >> "$LOG"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
  fi

  # Fetch fresh issue body
  ISSUE_DATA=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json title,body 2>/dev/null) || {
    echo "SARGE-REVIEW: $REPO#$ISSUE_NUM FAIL (could not fetch issue)" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    continue
  }
  ISSUE_TITLE=$(echo "$ISSUE_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('title',''))" 2>/dev/null)
  ISSUE_BODY=$(echo "$ISSUE_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('body',''))" 2>/dev/null)

  # Lightweight codebase context (project README + studio docs). The Sarge
  # subagent reads this verbatim — it does not have file-system tools in
  # headless mode.
  CODEBASE_CONTEXT=""
  if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
    for f in "design-system/project.json" "design-system/context.md" "design-system/features.yaml" "CLAUDE.md" ".claude/CLAUDE.md" "design-system/SCHEMA.md"; do
      if [ -f "$PROJECT_DIR/$f" ]; then
        CODEBASE_CONTEXT="${CODEBASE_CONTEXT}### $f"$'\n\n'"$(cat "$PROJECT_DIR/$f")"$'\n\n'
      fi
    done
  fi

  echo "SARGE-REVIEW: $REPO#$ISSUE_NUM - $TITLE" >> "$LOG"

  TMPFILE=$(mktemp)
  sed \
    -e "s|{REPO}|$REPO|g" \
    -e "s|{ISSUE_NUMBER}|$ISSUE_NUM|g" \
    "$SCRIPT_DIR/prompts/sarge-review.md" > "$TMPFILE"

  export ISSUE_BODY ISSUE_TITLE CODEBASE_CONTEXT
  python3 -c "
import os, sys
with open(sys.argv[1]) as f:
    c = f.read()
c = c.replace('{ISSUE_TITLE}', os.environ.get('ISSUE_TITLE', ''))
c = c.replace('{ISSUE_BODY}', os.environ.get('ISSUE_BODY', ''))
# Proactive run — no triage feedback yet.
c = c.replace('{FEEDBACK}', '_(none — proactive Sarge run, no triage feedback)_')
c = c.replace('{CODEBASE_CONTEXT}', os.environ.get('CODEBASE_CONTEXT', ''))
with open(sys.argv[1], 'w') as f:
    f.write(c)
" "$TMPFILE"

  RESULT_FILE="$RESULTS_DIR/$DATE-sarge-review-$ISSUE_NUM.log"
  SARGE_RESULT=$(claude -p "$(cat "$TMPFILE")" \
    --model "$SARGE_REVIEW_MODEL" \
    --max-budget-usd "$SARGE_REVIEW_BUDGET" \
    --dangerously-skip-permissions \
    < /dev/null 2>"$RESULT_FILE") || {
    echo "  SKIP: Claude invocation failed (see $RESULT_FILE)" >> "$LOG"
    SKIPPED=$((SKIPPED + 1))
    rm -f "$TMPFILE"
    continue
  }
  # Persist captured stdout alongside stderr; otherwise success-path log is empty.
  # Guard against empty SARGE_RESULT so the file stays 0 bytes (signal "phase ran clean")
  # rather than 1 byte of whitespace (which downstream grep would treat as non-empty).
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
    comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "DECISION-NEEDED: Foreman sarge-review could not parse Sarge's JSON response. @jorjani please review the spec manually. Diagnostic log: \`$RESULT_FILE\`" "sarge-review-parse-fail" || true
    # No structured product framing to lean on — translate from raw signal.
    questions_register "sarge-review-parse-fail" "$REPO" "$ISSUE_NUM" \
      "Sarge scoping run failed to produce a usable response for this ticket. Diagnostic log: $RESULT_FILE" \
      "" "" "[]" "" || true
    SKIPPED=$((SKIPPED + 1))
    continue
  }

  ACTION=$(echo "$SARGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('action',''))" 2>/dev/null)

  case "$ACTION" in
    enrich)
      UPDATED_BODY=$(echo "$SARGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('updated_body',''))" 2>/dev/null)
      CHANGES=$(echo "$SARGE_JSON" | python3 -c "
import json, sys
items = json.load(sys.stdin).get('changes_made', ['Enriched spec based on codebase recon'])
for c in items:
    print(f'- {c}')
" 2>/dev/null || echo "- Enriched spec based on codebase recon")
      if [ -z "$UPDATED_BODY" ]; then
        echo "  SKIP: enrich response missing updated_body (see $RESULT_FILE)" >> "$LOG"
        SKIPPED=$((SKIPPED + 1))
        continue
      fi
      if ! gh issue edit "$ISSUE_NUM" --repo "$REPO" --body "$UPDATED_BODY" 2>>"$LOG"; then
        echo "  FAIL: could not update issue body" >> "$LOG"
        SKIPPED=$((SKIPPED + 1))
        continue
      fi
      comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "SPEC-UPDATED: Sarge recon — spec enriched.

**Changes:**
$CHANGES

_Promoted to Backlog for triage._" "sarge-review-enriched" || true
      gh project item-edit \
        --project-id "$PROJECT_ID" --id "$ITEM_ID" \
        --field-id "$STATUS_FIELD_ID" \
        --single-select-option-id "$BACKLOG_OPTION_ID" \
        2>>"$LOG" || echo "  WARN: board promote to Backlog failed" >> "$LOG"
      echo "  ENRICHED -> Backlog" >> "$LOG"
      SCOPED=$((SCOPED + 1))
      ;;
    ready)
      SUMMARY=$(echo "$SARGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('summary','Spec already complete.'))" 2>/dev/null)
      comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "SPEC-UPDATED: Sarge recon — $SUMMARY

_Promoted to Backlog for triage._" "sarge-review-ready" || true
      gh project item-edit \
        --project-id "$PROJECT_ID" --id "$ITEM_ID" \
        --field-id "$STATUS_FIELD_ID" \
        --single-select-option-id "$BACKLOG_OPTION_ID" \
        2>>"$LOG" || echo "  WARN: board promote to Backlog failed" >> "$LOG"
      echo "  READY -> Backlog" >> "$LOG"
      SCOPED=$((SCOPED + 1))
      ;;
    decision_needed)
      SUMMARY=$(echo "$SARGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('summary','Sarge needs a product decision.'))" 2>/dev/null)
      DECISIONS=$(echo "$SARGE_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
lines = []
for q in d.get('decisions', []):
    lines.append(f\"**Q:** {q.get('question','')}\")
    rec = q.get('recommendation')
    if rec:
        lines.append(f'Sarge recommends: {rec}')
    for o in q.get('options', []):
        lines.append(f'- {o}')
    lines.append('')
print('\n'.join(lines))
" 2>/dev/null || echo "")
      comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "DECISION-NEEDED: $SUMMARY

$DECISIONS
@jorjani please resolve so Sarge can proceed on the next cycle." "sarge-review-decision" || true
      # Source-reframe (D4): Sarge already produces a product-framed
      # summary + first question / options. Pass them directly so no
      # LLM translate is needed at post-time.
      Q_FIRST=$(echo "$SARGE_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
decisions = d.get('decisions', []) or []
if not decisions:
    print('')
else:
    q = decisions[0]
    print(q.get('question', '').strip())
" 2>/dev/null)
      Q_OPTS=$(echo "$SARGE_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
decisions = d.get('decisions', []) or []
if not decisions:
    print('[]')
else:
    q = decisions[0]
    opts = list(q.get('options', []) or [])
    rec = (q.get('recommendation') or '').strip()
    if rec and rec not in opts:
        opts.insert(0, f'(Sarge recommends) {rec}')
    print(json.dumps(opts[:3]))
" 2>/dev/null)
      QUESTION_TEXT="${Q_FIRST:-$SUMMARY}"
      questions_register "sarge-review-decision" "$REPO" "$ISSUE_NUM" \
        "$SUMMARY"$'\n\n'"$DECISIONS" \
        "$QUESTION_TEXT" "$SUMMARY" "${Q_OPTS:-[]}" "" || true
      echo "  DECISION-NEEDED (left at Scope)" >> "$LOG"
      SCOPED=$((SCOPED + 1))
      ;;
    *)
      echo "  SKIP: unknown action='$ACTION' (see $RESULT_FILE)" >> "$LOG"
      SKIPPED=$((SKIPPED + 1))
      ;;
  esac

done <<< "$SCOPE_ITEMS"

if [ "$DEFERRED" -gt 0 ]; then
  echo "SARGE-REVIEW: deferred $DEFERRED items beyond cap=$SARGE_REVIEW_CAP:${DEFERRED_LIST}" >> "$LOG"
fi

echo "SARGE-REVIEW PHASE: scoped=$SCOPED spec_promoted=$SPEC_PROMOTED skipped=$SKIPPED deferred=$DEFERRED" >> "$LOG"
echo "scoped=$SCOPED spec_promoted=$SPEC_PROMOTED skipped=$SKIPPED deferred=$DEFERRED"
