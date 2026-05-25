#!/bin/bash
# Smoke test for lib/questions.sh.
#
# Mirrors scripts/test-cycle-summary.sh's structure: each case prints
# PASS / FAIL lines and the script exits non-zero on any failure.
#
# The tests bypass Slack entirely. They cover three things:
#   (a) DARK no-op: with SLACK_BOT_TOKEN unset, every public function
#       returns 0 and writes nothing to state.
#   (b) state file: questions_register populates state/questions.json
#       with the documented schema, and re-registering the same key
#       (still pending) is a silent no-op.
#   (c) heartbeat line: with no posted entries, questions_waiting_line
#       echoes empty; with one posted entry, it echoes the expected text.
#
# Slack and LLM calls are NOT exercised here — they require a token and
# would post live to the channel. Those paths are validated by hand the
# first time SLACK_BOT_TOKEN is set.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Isolated state file per run so concurrent test invocations don't race
# and so a leftover file from a previous attempt doesn't poison results.
TEST_STATE_DIR=$(mktemp -d)
export QUESTIONS_STATE_FILE="$TEST_STATE_DIR/questions.json"
export QUESTIONS_SCRIPT_DIR="$SCRIPT_DIR"
trap 'rm -rf "$TEST_STATE_DIR"' EXIT

# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/questions.sh"

PASS=0
FAIL=0
FAIL_DETAIL=""

assert_eq() {
  local label="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1))
    echo "  PASS  $label"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $label"
    echo "        want: $want"
    echo "        got:  $got"
    FAIL_DETAIL="${FAIL_DETAIL}\n  $label"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1))
    echo "  PASS  $label"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $label"
    echo "        expected substring: $needle"
    echo "        got:"
    printf '%s\n' "$haystack" | sed 's/^/          /'
    FAIL_DETAIL="${FAIL_DETAIL}\n  $label"
  fi
}

# ── Case (a): DARK no-op with SLACK_BOT_TOKEN unset ────────────────────
echo "Case (a): DARK no-op"
unset SLACK_BOT_TOKEN SLACK_QUESTIONS_CHANNEL_ID

# Try to register — should silently no-op.
questions_register "build-failed-3x" "getqatalyst/Sage" "999" \
  "Build failed 3 times. Branch auto/issue-999-foo." \
  "Foreman couldn't ship widget after 3 tries — what do you want to do?" \
  "Ticket stuck in Ready, labelled blocked." \
  '["Retry","Update spec","Close"]' \
  ""
DARK_FILE_EXISTS=0
[ -f "$QUESTIONS_STATE_FILE" ] && DARK_FILE_EXISTS=1
assert_eq "DARK: register does not touch state file" "$DARK_FILE_EXISTS" 0

# Heartbeat line should be empty.
DARK_HEARTBEAT=$(questions_waiting_line)
assert_eq "DARK: waiting line is empty" "$DARK_HEARTBEAT" ""

# Post-new should silently no-op.
DARK_POST=$(questions_post_new)
assert_eq "DARK: post-new echoes nothing" "$DARK_POST" ""

# Poll-replies should silently no-op.
DARK_POLL=$(questions_poll_replies)
assert_eq "DARK: poll-replies echoes nothing" "$DARK_POLL" ""

# ── Case (b): state file schema with bot enabled ───────────────────────
echo ""
echo "Case (b): state file with bot enabled"

# Activate the DARK gate by setting both envs to placeholder values.
# We won't actually call Slack (we only call questions_register, which
# just writes to state — no network call).
export SLACK_BOT_TOKEN="xoxb-test-not-real"
export SLACK_QUESTIONS_CHANNEL_ID="C0TESTCHAN"

questions_register "build-failed-3x" "getqatalyst/Sage" "999" \
  "Build failed 3 times. Branch auto/issue-999-foo." \
  "Foreman couldn't ship widget after 3 tries — what do you want to do?" \
  "Ticket stuck in Ready, labelled blocked." \
  '["Retry","Update spec","Close"]' \
  ""

# Now state file should exist with one entry.
[ -f "$QUESTIONS_STATE_FILE" ]
assert_eq "state file created on register" "$?" 0

ENTRY_COUNT=$(python3 -c "import json; print(len(json.load(open('$QUESTIONS_STATE_FILE'))['questions']))")
assert_eq "state contains 1 entry" "$ENTRY_COUNT" 1

KEY=$(python3 -c "import json; print(list(json.load(open('$QUESTIONS_STATE_FILE'))['questions'].keys())[0])")
assert_eq "key is <source>:<repo>:<num>" "$KEY" "build-failed-3x:getqatalyst/Sage:999"

STATUS=$(python3 -c "import json; print(json.load(open('$QUESTIONS_STATE_FILE'))['questions']['$KEY']['status'])")
assert_eq "new entry status is pending" "$STATUS" "pending"

QUESTION_TEXT=$(python3 -c "import json; print(json.load(open('$QUESTIONS_STATE_FILE'))['questions']['$KEY']['question'])")
assert_contains "question text persisted" "$QUESTION_TEXT" "couldn't ship widget"

OPTIONS_LEN=$(python3 -c "import json; print(len(json.load(open('$QUESTIONS_STATE_FILE'))['questions']['$KEY']['options']))")
assert_eq "options array has 3 entries" "$OPTIONS_LEN" 3

# Re-register same key while still pending — must be a no-op (no duplicate,
# original question text preserved).
questions_register "build-failed-3x" "getqatalyst/Sage" "999" \
  "DIFFERENT raw signal" \
  "DIFFERENT question text" \
  "DIFFERENT context" \
  '["A","B"]' \
  ""

ENTRY_COUNT_2=$(python3 -c "import json; print(len(json.load(open('$QUESTIONS_STATE_FILE'))['questions']))")
assert_eq "re-register pending = same count" "$ENTRY_COUNT_2" 1

QUESTION_TEXT_2=$(python3 -c "import json; print(json.load(open('$QUESTIONS_STATE_FILE'))['questions']['$KEY']['question'])")
assert_contains "re-register did NOT overwrite question" "$QUESTION_TEXT_2" "couldn't ship widget"

# After marking the entry resolved, a new register WILL replace it
# (different signal cycle → new decision needed).
python3 -c "
import json
p = '$QUESTIONS_STATE_FILE'
d = json.load(open(p))
d['questions']['$KEY']['status'] = 'resolved'
json.dump(d, open(p, 'w'), indent=2)
"

questions_register "build-failed-3x" "getqatalyst/Sage" "999" \
  "FRESH raw signal" \
  "Fresh question text after resolution" \
  "Fresh context" \
  '["X"]' \
  ""

QUESTION_TEXT_3=$(python3 -c "import json; print(json.load(open('$QUESTIONS_STATE_FILE'))['questions']['$KEY']['question'])")
assert_contains "re-register after resolved DOES replace" "$QUESTION_TEXT_3" "Fresh question text"

# ── Case (c): heartbeat line behavior ──────────────────────────────────
echo ""
echo "Case (c): waiting line"

# Currently the single entry is pending again (we re-registered above).
# Waiting line only counts status=posted. So with no posted entries,
# the line should still be empty.
WAITING=$(questions_waiting_line)
assert_eq "no posted entries -> empty waiting line" "$WAITING" ""

# Mark the entry as posted with a fake thread_ts and posted_at 2 days ago.
python3 -c "
import datetime, json
p = '$QUESTIONS_STATE_FILE'
d = json.load(open(p))
two_days_ago = (datetime.datetime.utcnow() - datetime.timedelta(days=2)).isoformat() + 'Z'
e = d['questions']['$KEY']
e['status'] = 'posted'
e['thread_ts'] = '1700000000.000100'
e['posted_at'] = two_days_ago
json.dump(d, open(p, 'w'), indent=2)
"

WAITING_2=$(questions_waiting_line)
assert_contains "1 posted entry, 2d old -> shows count" "$WAITING_2" "1 still waiting"
assert_contains "1 posted entry, 2d old -> shows age" "$WAITING_2" "(oldest 2d)"

echo ""
echo "============================="
echo "Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '%b\n' "Failures:$FAIL_DETAIL"
  exit 1
fi
echo "OK"
exit 0
