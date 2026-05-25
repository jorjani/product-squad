#!/bin/bash
# Collect structured metrics from today's orchestrator logs into JSON
# Handles multiple log files per day (format: YYYY-MM-DD-HHMM.log)
# Output: metrics/YYYY-MM-DD.json
# READS: (log markers: FLAGGED:, GIVE-UP: — from result logs, not GitHub comments)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATE="${1:-$(date +%Y-%m-%d)}"
RESULTS_DIR="$SCRIPT_DIR/results"
METRICS_DIR="$SCRIPT_DIR/metrics"
OUTPUT="$METRICS_DIR/$DATE.json"

mkdir -p "$METRICS_DIR"

# Find all log files for this date (both old YYYY-MM-DD.log and new YYYY-MM-DD-HHMM.log)
LOG_FILES=$(find "$RESULTS_DIR" -maxdepth 1 -name "${DATE}*.log" ! -name "*-issue-*" ! -name "*-review-*" ! -name "*-verify-*" ! -name "launchd-*" 2>/dev/null | sort)

if [ -z "$LOG_FILES" ]; then
  echo "No logs for $DATE"
  exit 0
fi

# Concatenate all daily logs for parsing
COMBINED=$(mktemp)
trap 'rm -f "$COMBINED"' EXIT
cat $LOG_FILES > "$COMBINED"

# Parse phase summary lines (format: "PHASE_NAME PHASE: key=val key=val ...")
# Also handles CYCLE SUMMARY lines from looping orchestrator
parse_summary() {
  local phase="$1"
  python3 -c "
import sys, json, re

with open(sys.argv[1]) as f:
    text = f.read()

phase = sys.argv[2]
totals = {}

# Match both 'PHASE PHASE: k=v' and 'CYCLE N SUMMARY: ...k=v...' patterns
for line in text.split('\n'):
    pairs = []
    if f'{phase} PHASE:' in line:
        pairs = re.findall(r'(\w+)=(\d+)', line)
    totals_update = {k: int(v) for k, v in pairs}
    for k, v in totals_update.items():
        totals[k] = totals.get(k, 0) + v

print(json.dumps(totals))
" "$COMBINED" "$phase"
}

# Extract individual failures with reasons
extract_failures() {
  python3 -c "
import sys, json, re

failures = []
with open(sys.argv[1]) as f:
    lines = f.readlines()

# Track current context (repo/PR/issue) across multi-line log entries
current_repo = ''
current_pr = ''
current_issue = ''

for line in lines:
    stripped = line.strip()

    # Track repo/PR context: '[getqatalyst/Jobber] PR #104: ...'
    repo_pr = re.match(r'\[(\S+)\]\s+PR #(\d+)', stripped)
    if repo_pr:
        current_repo = repo_pr.group(1)
        current_pr = repo_pr.group(2)
        continue

    # Track repo/issue context: 'BUILD: repo#num - title'
    build_ctx = re.match(r'BUILD:\s+(\S+)#(\d+)', stripped)
    if build_ctx:
        current_repo = build_ctx.group(1)
        current_issue = build_ctx.group(2)
        continue

    # FLAGGED line (follows a repo/PR context line)
    if stripped.startswith('FLAGGED:') and current_repo and current_pr:
        reason = stripped.replace('FLAGGED: ', '')
        failures.append({
            'repo': current_repo,
            'pr': int(current_pr),
            'reason': reason
        })
        continue

    # Build failures
    if stripped.startswith('FAIL:') or stripped.startswith('GIVE-UP:'):
        match = re.search(r'(\S+/\S+)#(\d+)', stripped)
        if match:
            failures.append({
                'repo': match.group(1),
                'issue': int(match.group(2)),
                'reason': stripped
            })
        elif current_repo and current_issue:
            failures.append({
                'repo': current_repo,
                'issue': int(current_issue),
                'reason': stripped
            })
        continue

print(json.dumps(failures))
" "$COMBINED"
}

REVIEW=$(parse_summary "REVIEW")
BUILD=$(parse_summary "BUILD")
TRIAGE=$(parse_summary "TRIAGE")
VERIFY=$(parse_summary "VERIFY")
FAILURES=$(extract_failures)

python3 -c "
import json, sys

metrics = {
    'date': sys.argv[1],
    'review': json.loads(sys.argv[2]),
    'build': json.loads(sys.argv[3]),
    'triage': json.loads(sys.argv[4]),
    'verify': json.loads(sys.argv[5]),
    'failures': json.loads(sys.argv[6])
}

# Nest verify-classifier verdicts under verify.classified so day-over-day
# diffs and self-improve read the verdict slice without colliding with the
# top-level counters. pop() ensures keys do not appear in both places.
verify = metrics['verify']
classified = {
    'deploy_lag': verify.pop('deploy_lag', 0),
    'assertion_fail': verify.pop('assertion_fail', 0),
    'unknown': verify.pop('unknown', 0),
    'deferred': verify.pop('deferred', 0),
}
verify['classified'] = classified

# Compute derived rates
b = metrics['build']
built = b.get('built', 0)
failed = b.get('failed', 0)
total = built + failed
if total > 0:
    retried = b.get('retried', 0)
    metrics['rates'] = {
        'build_success': round(built / total, 2),
        'first_attempt': round(max(0, built - retried) / total, 2)
    }

r = metrics['review']
reviewed = r.get('reviewed', 0)
merged = r.get('merged', 0)
if reviewed > 0:
    metrics['rates'] = metrics.get('rates', {})
    metrics['rates']['review_merge'] = round(merged / reviewed, 2)

with open(sys.argv[7], 'w') as f:
    json.dump(metrics, f, indent=2)

print(f'Metrics written: {sys.argv[7]}')
" "$DATE" "$REVIEW" "$BUILD" "$TRIAGE" "$VERIFY" "$FAILURES" "$OUTPUT"

# Generate prose narrative for the day, append to metrics JSON.
# Borrowed from Fabro's auto-retro pattern. Feeds self-improve.sh with
# qualitative signal that counters and one-line failure strings can't carry.
NARRATIVE_PROMPT="$SCRIPT_DIR/prompts/daily-narrative.md"
NARRATIVE_LOG="$METRICS_DIR/narrative-$DATE-stderr.log"

if [ -f "$NARRATIVE_PROMPT" ] && [ -s "$COMBINED" ] && [ -f "$SCRIPT_DIR/config/model-routing.sh" ]; then
  source "$SCRIPT_DIR/config/model-routing.sh"
  RESULT_LOGS=$(find "$RESULTS_DIR" -maxdepth 1 -name "${DATE}-*.log" -type f 2>/dev/null | head -10)

  CONTEXT=$(mktemp)
  cat "$NARRATIVE_PROMPT" > "$CONTEXT"
  printf '\n\n## Today structured metrics\n\n' >> "$CONTEXT"
  cat "$OUTPUT" >> "$CONTEXT"
  printf '\n\n## Today result logs (truncated to last 100 lines each)\n\n' >> "$CONTEXT"
  for log in $RESULT_LOGS; do
    printf '### %s\n' "$(basename "$log")" >> "$CONTEXT"
    tail -100 "$log" >> "$CONTEXT" 2>/dev/null || true
    printf '\n' >> "$CONTEXT"
  done

  NARRATIVE=$(claude -p "$(cat "$CONTEXT")" \
    --model "$NARRATIVE_MODEL" \
    --max-budget-usd "$NARRATIVE_BUDGET" \
    --dangerously-skip-permissions \
    < /dev/null 2>"$NARRATIVE_LOG" | head -c 4000) || NARRATIVE=""

  rm -f "$CONTEXT"

  if [ -n "$NARRATIVE" ]; then
    python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    metrics = json.load(f)
metrics['narrative'] = sys.argv[2]
with open(sys.argv[1], 'w') as f:
    json.dump(metrics, f, indent=2)
" "$OUTPUT" "$NARRATIVE"
    echo "Narrative appended to $OUTPUT"
  else
    echo "Narrative generation produced no output; metrics file unchanged. See $NARRATIVE_LOG."
  fi
fi
