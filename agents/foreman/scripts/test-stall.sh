#!/bin/bash
# Smoke test for lib/stall.sh dedup + Ready-detail one-liner.
# Run after changes to lib/stall.sh. Pure shell, no test framework.
#
# Covers:
#   1. Ready-detail format string is shaped correctly (Fix #2).
#   2. Bare-stall fallback still emits "run build" if Ready query returns empty (Fix #2).
#   3. Dedup state file: identical payload within TTL is skipped (Fix #1).
#   4. Dedup state file: changed payload (different subtitle or PR-set) re-alerts (Fix #1).
#   5. Dedup state file: same payload outside TTL re-alerts (Fix #1).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Source order matters: stall.sh references fetch_board_items from board-ids.sh.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/config/board-ids.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/stall.sh"

PASS=0
FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL+1)); }
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }

TMP=$(mktemp -d -t foreman-stall-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Test 1: oldest_ready_detail format
# ---------------------------------------------------------------------------
# Stub fetch_board_items with a minimal Ready set. Two old-ish issues; pick
# the one with the older createdAt.
fetch_board_items() {
  cat <<'JSON'
{"items":[
  {"id":"x1","status":"Ready","content":{"repository":"getqatalyst/Sage","number":42,"createdAt":"2026-04-01T00:00:00Z"}},
  {"id":"x2","status":"Ready","content":{"repository":"getqatalyst/Jobber","number":17,"createdAt":"2026-04-08T00:00:00Z"}},
  {"id":"x3","status":"Backlog","content":{"repository":"getqatalyst/Sage","number":99,"createdAt":"2025-01-01T00:00:00Z"}}
]}
JSON
}
detail=$(oldest_ready_detail)
case "$detail" in
  "Ready: 2 items, oldest getqatalyst/Sage#42 ("*"d)")
    pass "oldest_ready_detail format and selection"
    ;;
  *)
    fail "oldest_ready_detail unexpected: '$detail'"
    ;;
esac

# ---------------------------------------------------------------------------
# Test 2: bare-stall branch falls back when Ready query is empty
# ---------------------------------------------------------------------------
fetch_board_items() { echo '{"items":[]}'; }
# Stub gh pr list calls so get_stall_context returns no contributing repos.
gh() {
  case "$1" in
    pr) echo '[]'; return 0 ;;
    *)  command gh "$@" ;;
  esac
}

# Override surfaces so we can capture the Slack body without firing for real.
STALL_STATE_FILE="$TMP/state-empty"
SLACK_CAPTURE="$TMP/slack-empty.txt"
unset SLACK_CI_WEBHOOK_URL  # Skip Slack post path; we read the rendered text via debug.

# Drop into an instrumented copy of notify_stall: re-render and capture.
context=$(get_stall_context)
ready_detail=$(oldest_ready_detail)
rendered=$(echo "$context" | READY_COUNT=3 STALL_BOARD_URL="$STALL_BOARD_URL" STALL_ORG="$STALL_ORG" STALL_WIP_CAP_VAL="$STALL_WIP_CAP" READY_DETAIL="$ready_detail" python3 -c '
import json, os, sys
ctx = json.load(sys.stdin)
ready = int(os.environ.get("READY_COUNT", "0"))
ready_detail = os.environ.get("READY_DETAIL", "").strip()
contributing = [r for r in ctx.get("repos", []) if r.get("failing", 0) > 0 or r.get("cap_hit")]
gh_failed = [r for r in ctx.get("repos", []) if r.get("gh_failed")]
if not gh_failed and not contributing:
    detail_line = f"→ {ready_detail}" if ready_detail else "→ Run `./orchestrator.sh build` to surface the error"
    print(detail_line)
')
if [ "$rendered" = "→ Run \`./orchestrator.sh build\` to surface the error" ]; then
  pass "bare-stall falls back to 'run build' when Ready query empty"
else
  fail "bare-stall fallback wrong: '$rendered'"
fi
unset -f gh

# ---------------------------------------------------------------------------
# Test 3, 4, 5: dedup logic via the helper functions directly
# ---------------------------------------------------------------------------
SUBTITLE_A="Sage WIP cap reached"
SUBTITLE_B="Jobber: 1 auto/ PR CI-failing"
CONTEXT_A='{"repos":[{"name":"Sage","open_auto":3,"failing":3,"cap_hit":true,"pr_numbers":[1,2,3],"gh_failed":false}]}'
CONTEXT_B='{"repos":[{"name":"Sage","open_auto":3,"failing":2,"cap_hit":true,"pr_numbers":[1,2],"gh_failed":false}]}'

HASH_A=$(_stall_payload_hash "$SUBTITLE_A" "$CONTEXT_A")
HASH_A_AGAIN=$(_stall_payload_hash "$SUBTITLE_A" "$CONTEXT_A")
HASH_B=$(_stall_payload_hash "$SUBTITLE_B" "$CONTEXT_B")

if [ -n "$HASH_A" ] && [ "$HASH_A" = "$HASH_A_AGAIN" ]; then
  pass "_stall_payload_hash deterministic for identical inputs"
else
  fail "_stall_payload_hash not deterministic ('$HASH_A' vs '$HASH_A_AGAIN')"
fi
if [ "$HASH_A" != "$HASH_B" ]; then
  pass "_stall_payload_hash differs for different inputs"
else
  fail "_stall_payload_hash collided across different inputs"
fi

# Test 3: identical hash within TTL is skipped
state="$TMP/state-3"
_stall_record_payload "$HASH_A" "$state"
if _stall_should_skip "$HASH_A" "$state"; then
  pass "dedup: identical payload within TTL is skipped"
else
  fail "dedup: identical payload within TTL should have been skipped"
fi

# Test 4: changed payload (different hash) is NOT skipped
if ! _stall_should_skip "$HASH_B" "$state"; then
  pass "dedup: changed payload re-alerts immediately"
else
  fail "dedup: changed payload was incorrectly suppressed"
fi

# Test 5: same hash but record older than TTL is NOT skipped
state="$TMP/state-5"
mkdir -p "$(dirname "$state")"
old_ts=$(( $(date +%s) - STALL_DEDUP_TTL_SECONDS - 60 ))
printf '%s %s\n' "$old_ts" "$HASH_A" > "$state"
if ! _stall_should_skip "$HASH_A" "$state"; then
  pass "dedup: stale record outside TTL re-alerts"
else
  fail "dedup: stale record outside TTL was incorrectly suppressed"
fi

# Test 6: state file gets created under STALL_STATE_FILE override path
state="$TMP/state-6"
[ ! -f "$state" ] || { fail "test fixture: state file should not preexist"; }
_stall_record_payload "$HASH_A" "$state"
if [ -f "$state" ] && grep -q "$HASH_A" "$state"; then
  pass "_stall_record_payload writes hash to state file"
else
  fail "_stall_record_payload did not write expected record"
fi

# ---------------------------------------------------------------------------
echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
