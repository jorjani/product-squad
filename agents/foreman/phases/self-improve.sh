#!/bin/bash
# Phase 6: Self-Improve — analyze pipeline metrics, propose prompt changes
# POSTS: (auto/ PRs, not comment protocols)
# Modes:
#   A: No active experiment → analyze + propose change → ship auto/ PR
#   B: Experiment PR still open → skip (let review pipeline handle it)
#   C: Experiment PR merged → evaluate before/after → keep or revert → then Mode A
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/config/model-routing.sh"
source "$SCRIPT_DIR/lib/comments.sh"
METRICS_DIR="$SCRIPT_DIR/metrics"
PROMPTS_DIR="$SCRIPT_DIR/prompts"
DATE=$(date +%Y-%m-%d)
REPO="getqatalyst/foreman"

# Pinned tracking issue for PROPOSE outcomes. All PROPOSE-* comments post here
# (per specs/154-propose-misses-flow.md §4B) so `comment_dedup_or_escalate`'s
# in-issue dedup scan can detect identical misses across cadences.
TRACKING_TITLE="self-improve telemetry — PROPOSE outcomes"
TRACKING_ISSUE_CACHE=""
PROPOSE_OUTCOME=""

ensure_tracking_issue() {
  if [ -n "$TRACKING_ISSUE_CACHE" ]; then
    printf '%s\n' "$TRACKING_ISSUE_CACHE"
    return 0
  fi
  local num
  num=$(gh issue list --repo "$REPO" --state all --limit 100 \
        --search "in:title \"$TRACKING_TITLE\"" \
        --json number,title 2>/dev/null | \
        TT="$TRACKING_TITLE" python3 -c "
import json, os, sys
target = os.environ.get('TT', '')
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for item in data:
    if item.get('title') == target:
        print(item.get('number', ''))
        break
" 2>/dev/null || true)
  if [ -z "$num" ]; then
    local body url
    body="Long-lived tracking issue for self-improve PROPOSE outcomes.

This issue collects automated comments emitted by the self-improve phase when its
PROPOSE step encounters non-success outcomes:

- \`PROPOSE-MISS\` — replace target string not found (slot refunded; next cadence retries)
- \`PROPOSE-TARGET-MISSING\` — proposed prompt file does not exist (slot unaffected)
- \`PROPOSE-MISS-SOFT\` — anchor not found; content appended at end-of-file (slot consumed)
- \`PROPOSE-EVAL-PARSE\` — could not parse PROPOSE response (slot unaffected)
- \`PROPOSE-CRASH\` — uncaught error in the phase (slot unaffected)

See \`specs/154-propose-misses-flow.md\` for the full truth table."
    url=$(gh issue create --repo "$REPO" --title "$TRACKING_TITLE" --body "$body" 2>/dev/null) || {
      echo "SELF-IMPROVE: WARNING: could not find or create tracking issue" >&2
      return 1
    }
    num=$(printf '%s' "$url" | grep -oE '[0-9]+$' || true)
  fi
  if [ -z "$num" ]; then
    return 1
  fi
  TRACKING_ISSUE_CACHE="$num"
  printf '%s\n' "$num"
}

post_propose_event() {
  local prefix="$1"
  local context="$2"
  local body="$3"
  local issue
  issue=$(ensure_tracking_issue) || {
    echo "SELF-IMPROVE: WARNING: tracking issue unavailable, dropping $prefix event" >&2
    return 1
  }
  comment_dedup_or_escalate "$REPO" "$issue" "$prefix: $body" "$context" || true
}

on_exit() {
  local rc=$?
  trap - EXIT
  if [ $rc -ne 0 ] && [ -z "$PROPOSE_OUTCOME" ]; then
    local body="Self-improve phase exited unexpectedly (rc=$rc) on cadence $DATE.

Slot unaffected; next every-other-day cadence will retry from scratch. Investigate the daily orchestrator log and \`metrics/self-improve-$DATE-stderr.log\` if present."
    post_propose_event "PROPOSE-CRASH" "propose-crash" "$body" || true
  fi
  exit $rc
}
trap on_exit EXIT
# Per-machine daemon state, not synced via git (gitignored). The daemon
# rewrites this file on every run; committing it caused drift between
# fresh clones and the running M5 daemon. See foreman#187.
EXPERIMENTS_FILE="$METRICS_DIR/experiments.json"

mkdir -p "$METRICS_DIR"

# Initialize experiments file if missing
if [ ! -f "$EXPERIMENTS_FILE" ]; then
  echo '{"active": null, "history": []}' > "$EXPERIMENTS_FILE"
fi

# --- Helpers ---

get_active_experiment() {
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
active = data.get('active')
if active:
    print(json.dumps(active))
else:
    print('null')
" "$EXPERIMENTS_FILE"
}

count_metrics_files() {
  local since="${1:-}"
  if [ -n "$since" ]; then
    python3 -c "
import os, sys
d = sys.argv[1]
since = sys.argv[2]
count = sum(1 for f in os.listdir(d) if f.endswith('.json') and f[:10] >= since and f not in ('experiments.json', 'failure-tracker.json'))
print(count)
" "$METRICS_DIR" "$since"
  else
    python3 -c "
import os, sys
d = sys.argv[1]
count = sum(1 for f in os.listdir(d) if f.endswith('.json') and f not in ('experiments.json', 'failure-tracker.json'))
print(count)
" "$METRICS_DIR"
  fi
}

aggregate_metrics() {
  local since="${1:-}"
  python3 -c "
import os, json, sys, glob

metrics_dir = sys.argv[1]
since = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else ''

files = sorted(glob.glob(os.path.join(metrics_dir, '*.json')))
files = [f for f in files if os.path.basename(f) not in ('experiments.json', 'failure-tracker.json')]
if since:
    files = [f for f in files if os.path.basename(f)[:10] >= since]

if not files:
    print(json.dumps({'days': 0, 'summary': 'No metrics data available'}))
    sys.exit(0)

totals = {'builds': {}, 'reviews': {}, 'triage': {}, 'verify': {}}
all_failures = []
days = len(files)

for fpath in files:
    with open(fpath) as f:
        day = json.load(f)
    for phase in totals:
        phase_data = day.get(phase, day.get(phase.rstrip('s'), {}))
        for k, v in phase_data.items():
            if isinstance(v, (int, float)):
                totals[phase][k] = totals[phase].get(k, 0) + v
    all_failures.extend(day.get('failures', []))

# Compute rates
b = totals.get('builds', totals.get('build', {}))
built = b.get('built', 0)
failed = b.get('failed', 0)
total_builds = built + failed
rates = {}
if total_builds > 0:
    rates['build_success'] = round(built / total_builds, 2)
    retried = b.get('retried', 0)
    rates['first_attempt'] = round((built - retried) / total_builds, 2)

r = totals.get('reviews', totals.get('review', {}))
reviewed = r.get('reviewed', 0)
merged = r.get('merged', 0)
if reviewed > 0:
    rates['review_merge'] = round(merged / reviewed, 2)

result = {
    'days': days,
    'date_range': [os.path.basename(files[0])[:10], os.path.basename(files[-1])[:10]],
    'totals': totals,
    'rates': rates,
    'failure_count': len(all_failures),
    'failures': all_failures[:20]
}
print(json.dumps(result, indent=2))
" "$METRICS_DIR" "$since"
}

# --- Mode Detection ---

ACTIVE=$(get_active_experiment)

if [ "$ACTIVE" != "null" ]; then
  # Check if the experiment's PR is still open or has been merged
  PR_NUM=$(echo "$ACTIVE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('pr_number',''))")

  if [ -z "$PR_NUM" ]; then
    echo "ERROR: Active experiment has no PR number, resetting"
    python3 -c "
import json, sys
with open(sys.argv[1], 'r+') as f:
    data = json.load(f)
    if data['active']:
        data['active']['verdict'] = 'error'
        data['history'].append(data['active'])
    data['active'] = None
    f.seek(0); json.dump(data, f, indent=2); f.truncate()
" "$EXPERIMENTS_FILE"
    ACTIVE="null"
  else
    PR_STATE=$(gh pr view "$PR_NUM" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "UNKNOWN")

    if [ "$PR_STATE" = "OPEN" ]; then
      # Mode B: experiment PR still open, skip
      echo "SELF-IMPROVE: Mode B — experiment PR #$PR_NUM still open, waiting for review"
      exit 0

    elif [ "$PR_STATE" = "MERGED" ]; then
      # Mode C: evaluate the experiment
      echo "SELF-IMPROVE: Mode C — evaluating experiment (PR #$PR_NUM merged)"

      MERGE_DATE=$(gh pr view "$PR_NUM" --repo "$REPO" --json mergedAt -q '.mergedAt' 2>/dev/null | cut -c1-10)
      DAYS_SINCE=$(count_metrics_files "$MERGE_DATE")

      if [ "$DAYS_SINCE" -lt 2 ]; then
        echo "SELF-IMPROVE: Only $DAYS_SINCE day(s) of data since merge, need at least 2. Waiting."
        exit 0
      fi

      # Compare baseline vs post-merge metrics
      BASELINE=$(echo "$ACTIVE" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('baseline',{})))")
      TARGET_METRIC=$(echo "$ACTIVE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('target_metric',''))")
      POST_METRICS=$(aggregate_metrics "$MERGE_DATE")

      VERDICT=$(python3 -c "
import json, sys

baseline = json.loads(sys.argv[1])
post = json.loads(sys.argv[2])
target = sys.argv[3]

post_rates = post.get('rates', {})
base_rates = baseline.get('rates', {})

# Backstop: build_success and first_attempt must not regress more than 0.15.
build_ok = post_rates.get('build_success', 0) >= base_rates.get('build_success', 0) - 0.15
first_ok = post_rates.get('first_attempt', 0) >= base_rates.get('first_attempt', 0) - 0.15

# Targeted gate: if the experiment named a target_metric, it must not regress
# beyond a small noise tolerance. 0.02 covers day-to-day fluctuation without
# reopening the exp-004 gap (which was a 0.10 regression).
target_ok = True
if target:
    target_ok = post_rates.get(target, 0) >= base_rates.get(target, 0) - 0.02

if build_ok and first_ok and target_ok:
    print('kept')
else:
    print('reverted')
" "$BASELINE" "$POST_METRICS" "$TARGET_METRIC")

      echo "SELF-IMPROVE: Verdict for experiment: $VERDICT"

      if [ "$VERDICT" = "reverted" ]; then
        # Create revert PR
        cd "$SCRIPT_DIR"
        git checkout main 2>/dev/null
        git pull origin main 2>/dev/null

        REVERT_BRANCH="auto/revert-self-improve-$DATE"
        git checkout -b "$REVERT_BRANCH"

        # Get the original change details and revert
        PROMPT_FILE=$(echo "$ACTIVE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('prompt_file',''))")
        CHANGE_TYPE=$(echo "$ACTIVE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('change',{}).get('type',''))")

        if [ "$CHANGE_TYPE" = "insert_after" ]; then
          CONTENT=$(echo "$ACTIVE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('change',{}).get('content',''))")
          # Remove the inserted content
          python3 -c "
import sys
content = sys.argv[2]
path = sys.argv[1]
with open(path) as f:
    text = f.read()
text = text.replace(content + '\n', '')
text = text.replace(content, '')
with open(path, 'w') as f:
    f.write(text)
" "$PROMPTS_DIR/$PROMPT_FILE" "$CONTENT"
        elif [ "$CHANGE_TYPE" = "replace" ]; then
          OLD=$(echo "$ACTIVE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('change',{}).get('new',''))")
          NEW=$(echo "$ACTIVE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('change',{}).get('old',''))")
          python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    text = f.read()
text = text.replace(old, new)
with open(path, 'w') as f:
    f.write(text)
" "$PROMPTS_DIR/$PROMPT_FILE" "$OLD" "$NEW"
        fi

        git add "prompts/$PROMPT_FILE"
        git commit -m "chore: revert self-improve experiment (metrics degraded)

Reverting prompt change from PR #$PR_NUM.
Experiment verdict: reverted (post-merge metrics declined).

Co-Authored-By: Foreman Self-Improve <noreply@getqatalyst.com>"
        git push -u origin "$REVERT_BRANCH" 2>/dev/null

        REVERT_PR_URL=$(gh pr create --repo "$REPO" --base main \
          --title "Revert: self-improve experiment (metrics degraded)" \
          --body "Reverting prompt change from PR #$PR_NUM.

Post-merge metrics showed degradation compared to baseline. Auto-reverting.

Closes the self-improve experiment cycle." 2>/dev/null || true)

        echo "SELF-IMPROVE: Revert PR created: $REVERT_PR_URL"
        git checkout main 2>/dev/null
      fi

      # Update experiment record
      python3 -c "
import json, sys

verdict = sys.argv[1]
post_metrics_raw = sys.argv[2]
post_metrics = json.loads(post_metrics_raw)

with open(sys.argv[3], 'r+') as f:
    data = json.load(f)
    exp = data['active']
    exp['verdict'] = verdict
    exp['result'] = post_metrics.get('rates', {})
    exp['evaluated'] = sys.argv[4]
    data['history'].append(exp)
    data['active'] = None
    f.seek(0)
    json.dump(data, f, indent=2)
    f.truncate()
" "$VERDICT" "$POST_METRICS" "$EXPERIMENTS_FILE" "$DATE"

      ACTIVE="null"
      echo "SELF-IMPROVE: Experiment archived. Proceeding to Mode A."
    else
      # PR was closed without merge (rejected)
      echo "SELF-IMPROVE: Experiment PR #$PR_NUM was closed without merge. Archiving."
      python3 -c "
import json, sys
with open(sys.argv[1], 'r+') as f:
    data = json.load(f)
    exp = data['active']
    exp['verdict'] = 'rejected'
    exp['evaluated'] = sys.argv[2]
    data['history'].append(exp)
    data['active'] = None
    f.seek(0); json.dump(data, f, indent=2); f.truncate()
" "$EXPERIMENTS_FILE" "$DATE"
      ACTIVE="null"
    fi
  fi
fi

# --- Mode A: Propose a new experiment ---

if [ "$ACTIVE" = "null" ]; then
  echo "SELF-IMPROVE: Mode A — analyzing metrics and proposing change"

  # Need at least 2 days of metrics to analyze
  TOTAL_DAYS=$(count_metrics_files)
  if [ "$TOTAL_DAYS" -lt 2 ]; then
    echo "SELF-IMPROVE: Only $TOTAL_DAYS day(s) of metrics. Need at least 2 before proposing changes."
    exit 0
  fi

  # Aggregate all available metrics as baseline
  METRICS_SUMMARY=$(aggregate_metrics)

  # Collect failure details
  FAILURE_DETAILS=$(python3 -c "
import json, sys
metrics = json.loads(sys.argv[1])
failures = metrics.get('failures', [])
if not failures:
    print('No specific failures recorded in recent metrics.')
else:
    for f in failures:
        if 'issue' in f:
            print(f\"- Build failure: {f['repo']}#{f['issue']} -- {f.get('reason', 'unknown')}\")
        elif 'pr' in f:
            print(f\"- Review flag: {f['repo']} PR #{f['pr']} -- {f.get('reason', 'unknown')}\")
" "$METRICS_SUMMARY")

  # Collect experiment history
  EXPERIMENT_HISTORY=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
history = data.get('history', [])
if not history:
    print('No previous experiments.')
else:
    for exp in history:
        print(f\"- {exp.get('date','?')}: {exp.get('prompt_file','?')} -- {exp.get('change_summary','?')} -- verdict: {exp.get('verdict','?')}\")
" "$EXPERIMENTS_FILE")

  # Read current prompts
  BUILD_PROMPT=$(cat "$PROMPTS_DIR/build.md")
  REVIEW_PROMPT=$(cat "$PROMPTS_DIR/review.md")
  TRIAGE_PROMPT=$(cat "$PROMPTS_DIR/triage.md")
  VERIFY_PROMPT=$(cat "$PROMPTS_DIR/verify.md" 2>/dev/null || echo "(not found)")
  REPAIR_PROMPT=$(cat "$PROMPTS_DIR/repair.md" 2>/dev/null || echo "(not found)")

  # Collect narrative history (last 7 days that have a narrative field).
  # Provides categorical signal that the metrics counters cannot carry on their own.
  NARRATIVE_HISTORY=$(python3 -c "
import os, json, sys, glob
files = sorted(glob.glob(os.path.join(sys.argv[1], '*.json')))
files = [f for f in files if os.path.basename(f) not in ('experiments.json', 'failure-tracker.json')][-7:]
out = []
for fpath in files:
    try:
        with open(fpath) as f:
            day = json.load(f)
        narrative = (day.get('narrative') or '').strip()
        if narrative:
            out.append(f\"- {os.path.basename(fpath)[:10]}: {narrative}\")
    except Exception:
        pass
print('\n'.join(out) if out else 'No narratives recorded yet.')
" "$METRICS_DIR")

  # Render the self-improve prompt
  TMPFILE=$(mktemp)
  trap 'rm -f "$TMPFILE"' EXIT

  cp "$PROMPTS_DIR/self-improve.md" "$TMPFILE"

  export BUILD_PROMPT REVIEW_PROMPT TRIAGE_PROMPT VERIFY_PROMPT REPAIR_PROMPT
  export METRICS_SUMMARY FAILURE_DETAILS EXPERIMENT_HISTORY NARRATIVE_HISTORY

  python3 -c "
import sys, os

with open(sys.argv[1]) as f:
    content = f.read()

replacements = {
    '{BUILD_PROMPT}': os.environ.get('BUILD_PROMPT', ''),
    '{REVIEW_PROMPT}': os.environ.get('REVIEW_PROMPT', ''),
    '{TRIAGE_PROMPT}': os.environ.get('TRIAGE_PROMPT', ''),
    '{VERIFY_PROMPT}': os.environ.get('VERIFY_PROMPT', ''),
    '{REPAIR_PROMPT}': os.environ.get('REPAIR_PROMPT', ''),
    '{METRICS_SUMMARY}': os.environ.get('METRICS_SUMMARY', ''),
    '{FAILURE_DETAILS}': os.environ.get('FAILURE_DETAILS', ''),
    '{EXPERIMENT_HISTORY}': os.environ.get('EXPERIMENT_HISTORY', ''),
    '{NARRATIVE_HISTORY}': os.environ.get('NARRATIVE_HISTORY', ''),
}

for k, v in replacements.items():
    content = content.replace(k, v)

with open(sys.argv[1], 'w') as f:
    f.write(content)
" "$TMPFILE"

  # Run Claude to analyze and propose
  STDERR_LOG="$METRICS_DIR/self-improve-$DATE-stderr.log"

  RESULT=$(claude -p "$(cat "$TMPFILE")" \
    --model "$SELF_IMPROVE_MODEL" \
    --max-budget-usd "$SELF_IMPROVE_BUDGET" \
    --dangerously-skip-permissions \
    < /dev/null 2>"$STDERR_LOG") || {
    echo "SELF-IMPROVE: Claude analysis failed. stderr:"
    cat "$STDERR_LOG"
    echo "$RESULT" > "$METRICS_DIR/self-improve-$DATE-raw.txt"
    exit 1
  }

  # Parse the response — extract JSON from potentially mixed text
  ACTION=$(echo "$RESULT" | python3 -c "
import json, sys, re
text = sys.stdin.read().strip()
# Try direct parse first
try:
    result = json.loads(text)
    print(result.get('action', 'error'))
    sys.exit(0)
except Exception: pass
# Try stripping markdown fences
m = re.search(r'\`\`\`(?:json)?\s*\n(.*?)\n\`\`\`', text, re.DOTALL)
if m:
    try:
        result = json.loads(m.group(1))
        print(result.get('action', 'error'))
        sys.exit(0)
    except Exception: pass
# Try finding JSON object in mixed text
m = re.search(r'\{[^{}]*\"action\"[^{}]*\}', text, re.DOTALL)
if m:
    try:
        result = json.loads(m.group(0))
        print(result.get('action', 'error'))
        sys.exit(0)
    except Exception: pass
print('error')
")

  if [ "$ACTION" = "no_change" ]; then
    echo "SELF-IMPROVE: No change proposed. Metrics are healthy."
    exit 0
  fi

  if [ "$ACTION" != "change" ]; then
    echo "SELF-IMPROVE: Could not parse Claude response. Raw output saved."
    echo "$RESULT" > "$METRICS_DIR/self-improve-$DATE-raw.txt"
    RAW_PREVIEW=$(printf '%s' "$RESULT" | head -c 400)
    post_propose_event "PROPOSE-EVAL-PARSE" "propose-eval-parse" \
"Could not parse the PROPOSE response as JSON. Raw output (first 400 chars):

\`\`\`
$RAW_PREVIEW
\`\`\`

Full raw output saved to \`metrics/self-improve-$DATE-raw.txt\`. Slot unaffected; next cadence will retry."
    PROPOSE_OUTCOME="parse-failure"
    exit 0
  fi

  # Extract change details — find JSON object in mixed text
  CHANGE_JSON=$(echo "$RESULT" | python3 -c "
import json, sys, re
text = sys.stdin.read().strip()
# Try direct parse
try:
    json.loads(text)
    print(text)
    sys.exit(0)
except Exception: pass
# Try markdown fence
m = re.search(r'\`\`\`(?:json)?\s*\n(.*?)\n\`\`\`', text, re.DOTALL)
if m:
    try:
        json.loads(m.group(1))
        print(m.group(1))
        sys.exit(0)
    except Exception: pass
# Find the largest JSON object containing 'action'
for m in re.finditer(r'\{', text):
    depth = 0
    start = m.start()
    for i in range(start, len(text)):
        if text[i] == '{': depth += 1
        elif text[i] == '}': depth -= 1
        if depth == 0:
            candidate = text[start:i+1]
            try:
                obj = json.loads(candidate)
                if 'action' in obj:
                    print(candidate)
                    sys.exit(0)
            except Exception: pass
            break
print('{}')
")

  PROMPT_FILE=$(echo "$CHANGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['prompt_file'])")
  HYPOTHESIS=$(echo "$CHANGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['hypothesis'])")
  CHANGE_TYPE=$(echo "$CHANGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['change']['type'])")
  EXPECTED=$(echo "$CHANGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('expected_impact',''))")

  # Validate the prompt file exists
  if [ ! -f "$PROMPTS_DIR/$PROMPT_FILE" ]; then
    echo "SELF-IMPROVE: Proposed change targets non-existent file: $PROMPT_FILE"
    post_propose_event "PROPOSE-TARGET-MISSING" "propose-target-missing" \
"PROPOSE targeted a prompt file that does not exist: \`prompts/$PROMPT_FILE\`.

Hypothesis: $HYPOTHESIS

Slot unaffected (environmental skip). Next cadence will re-analyze metrics from scratch."
    PROPOSE_OUTCOME="file-missing"
    exit 0
  fi

  # Apply the change
  cd "$SCRIPT_DIR"
  git checkout main 2>/dev/null
  git pull origin main 2>/dev/null

  BRANCH="auto/self-improve-$DATE"
  git checkout -b "$BRANCH"

  if [ "$CHANGE_TYPE" = "insert_after" ]; then
    ANCHOR=$(echo "$CHANGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['change']['anchor'])")
    CONTENT=$(echo "$CHANGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['change']['content'])")

    # Exit 0 = anchor matched, 2 = anchor missed (content appended at EOF).
    # The file is written either way (CONSUME semantics for both branches).
    set +e
    python3 -c "
import sys
anchor = sys.argv[2]
content = sys.argv[3]
path = sys.argv[1]
with open(path) as f:
    text = f.read()
anchor_missed = anchor not in text
if anchor_missed:
    print(f'WARNING: anchor not found in {path}, appending to end')
    text = text.rstrip() + '\n' + content + '\n'
else:
    lines = text.split('\n')
    new_lines = []
    for line in lines:
        new_lines.append(line)
        if anchor in line:
            new_lines.append(content)
    text = '\n'.join(new_lines)
with open(path, 'w') as f:
    f.write(text)
sys.exit(2 if anchor_missed else 0)
" "$PROMPTS_DIR/$PROMPT_FILE" "$ANCHOR" "$CONTENT"
    ANCHOR_RC=$?
    set -e

    if [ $ANCHOR_RC -eq 2 ]; then
      ANCHOR_PREVIEW=$(printf '%s' "$ANCHOR" | head -c 200)
      CONTENT_PREVIEW=$(printf '%s' "$CONTENT" | head -c 400)
      post_propose_event "PROPOSE-MISS-SOFT" "propose-miss-soft" \
"PROPOSE \`insert_after\` anchor not found in \`prompts/$PROMPT_FILE\`; content was appended at end-of-file (silent fallback now surfaced).

Anchor (first 200 chars):
\`\`\`
$ANCHOR_PREVIEW
\`\`\`

Content (first 400 chars):
\`\`\`
$CONTENT_PREVIEW
\`\`\`

Slot consumed; experiment proceeds. Repeated soft-misses on the same prompt suggest prompt drift."
    elif [ $ANCHOR_RC -ne 0 ]; then
      PROPOSE_OUTCOME="insert-failure"
      echo "SELF-IMPROVE: insert_after step failed (rc=$ANCHOR_RC)"
      git checkout main 2>/dev/null
      git branch -D "$BRANCH" 2>/dev/null || true
      exit $ANCHOR_RC
    fi

  elif [ "$CHANGE_TYPE" = "replace" ]; then
    OLD=$(echo "$CHANGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['change']['old'])")
    NEW=$(echo "$CHANGE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['change']['new'])")

    set +e
    python3 -c "
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    text = f.read()
if old not in text:
    print(f'WARNING: old text not found in {path}, skipping replace')
    sys.exit(1)
text = text.replace(old, new, 1)
with open(path, 'w') as f:
    f.write(text)
" "$PROMPTS_DIR/$PROMPT_FILE" "$OLD" "$NEW"
    REPLACE_RC=$?
    set -e

    if [ $REPLACE_RC -ne 0 ]; then
      echo "SELF-IMPROVE: Replace failed, old text not found"
      OLD_PREVIEW=$(printf '%s' "$OLD" | head -c 400)
      NEW_PREVIEW=$(printf '%s' "$NEW" | head -c 400)
      post_propose_event "PROPOSE-MISS" "propose-miss" \
"PROPOSE \`replace\` target string not found in \`prompts/$PROMPT_FILE\`.

Old (first 400 chars):
\`\`\`
$OLD_PREVIEW
\`\`\`

New (first 400 chars):
\`\`\`
$NEW_PREVIEW
\`\`\`

Hypothesis: $HYPOTHESIS

Slot refunded; next cadence will re-propose (regen may produce a matching \`old\`)."
      git checkout main 2>/dev/null
      git branch -D "$BRANCH" 2>/dev/null || true
      PROPOSE_OUTCOME="replace-miss"
      exit 0
    fi
  else
    echo "SELF-IMPROVE: Unknown change type: $CHANGE_TYPE"
    git checkout main 2>/dev/null
    git branch -D "$BRANCH" 2>/dev/null || true
    exit 1
  fi

  # Create a summary of the change for the commit and experiment record
  CHANGE_SUMMARY=$(python3 -c "
import json, sys
data = json.loads(sys.argv[1])
ct = data['change']['type']
if ct == 'insert_after':
    print(f\"Added to {data['prompt_file']}: {data['change']['content'][:80]}\")
else:
    print(f\"Changed in {data['prompt_file']}: {data['change'].get('old','')[:40]} -> {data['change'].get('new','')[:40]}\")
" "$CHANGE_JSON")

  # Commit and push
  git add "prompts/$PROMPT_FILE"

  # Check if there are actually changes to commit
  if git diff --cached --quiet; then
    echo "SELF-IMPROVE: No actual changes to commit (change may have been a no-op)"
    git checkout main 2>/dev/null
    git branch -D "$BRANCH" 2>/dev/null || true
    exit 0
  fi

  git commit -m "$(cat <<EOF
chore: self-improve $PROMPT_FILE

Hypothesis: $HYPOTHESIS
Expected: $EXPECTED

Co-Authored-By: Foreman Self-Improve <noreply@getqatalyst.com>
EOF
)"
  git push -u origin "$BRANCH" 2>/dev/null

  PR_URL=$(gh pr create --repo "$REPO" --base main \
    --title "Self-improve: $PROMPT_FILE" \
    --body "$(cat <<EOF
## Self-Improvement Experiment

**Hypothesis:** $HYPOTHESIS

**Expected Impact:** $EXPECTED

**Change:** $CHANGE_SUMMARY

**Prompt File:** prompts/$PROMPT_FILE

This PR was generated by the Foreman self-improve phase (Phase 5).
It will be evaluated automatically after 2+ days of pipeline data.
If metrics degrade, a revert PR will be created automatically.
EOF
)" 2>/dev/null || true)

  PR_NUM=$(echo "$PR_URL" | grep -oE '[0-9]+$' || true)

  echo "SELF-IMPROVE: PR created: $PR_URL"

  git checkout main 2>/dev/null

  # Record the experiment
  BASELINE_RATES=$(echo "$METRICS_SUMMARY" | python3 -c "import json,sys; print(json.dumps(json.loads(sys.stdin.read()).get('rates',{})))")

  python3 - "$DATE" "$PROMPT_FILE" "$CHANGE_SUMMARY" "$HYPOTHESIS" "$PR_NUM" "$EXPERIMENTS_FILE" "$BASELINE_RATES" "$CHANGE_JSON" <<'PYEOF'
import json, sys

change_payload = json.loads(sys.argv[8])
exp = {
    'id': f'exp-{len(json.load(open(sys.argv[6])).get("history", [])) + 1:03d}',
    'date': sys.argv[1],
    'prompt_file': sys.argv[2],
    'change_summary': sys.argv[3],
    'hypothesis': sys.argv[4],
    'target_metric': change_payload.get('target_metric', ''),
    'pr_number': int(sys.argv[5]) if sys.argv[5] else 0,
    'baseline': json.loads(sys.argv[7]),
    'change': change_payload
}

with open(sys.argv[6], 'r+') as f:
    data = json.load(f)
    data['active'] = exp
    f.seek(0)
    json.dump(data, f, indent=2)
    f.truncate()

print(f'Experiment {exp["id"]} recorded')
PYEOF

  echo "SELF-IMPROVE PHASE: proposed change to $PROMPT_FILE"
fi
