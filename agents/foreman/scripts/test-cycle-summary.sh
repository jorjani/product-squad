#!/bin/bash
# Smoke test for lib/cycle-summary.sh#_cs_render.
#
# _cs_render is a pure function: JSON fixture in, formatted Slack text out.
# These tests bypass gh/Slack entirely and assert on the rendered text.
#
# Cases:
#   (a) all-quiet cycle  -> 2 lines (header + status)
#   (b) populated cycle  -> all sections render
#   (c) empty sections drop independently
#   (d) numbers in input flow through unchanged

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/cycle-summary.sh"

PASS=0
FAIL=0
FAIL_DETAIL=""

# Assert that $haystack contains $needle (literal substring).
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

# Assert that $haystack does NOT contain $needle.
assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL  $label"
    echo "        unexpected substring: $needle"
    echo "        got:"
    printf '%s\n' "$haystack" | sed 's/^/          /'
    FAIL_DETAIL="${FAIL_DETAIL}\n  $label"
  else
    PASS=$((PASS + 1))
    echo "  PASS  $label"
  fi
}

# Assert that line count matches expected.
assert_line_count() {
  local label="$1" haystack="$2" expected="$3"
  local actual
  actual=$(printf '%s' "$haystack" | wc -l | tr -d ' ')
  # printf no trailing newline -> wc -l reports inner newlines.
  # _cs_render's print() adds a final newline, so wc -l counts every line.
  # Pass actual via printf %s\n to normalise.
  actual=$(printf '%s\n' "$haystack" | grep -c .)
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1))
    echo "  PASS  $label ($actual lines)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $label (expected $expected lines, got $actual)"
    printf '%s\n' "$haystack" | sed 's/^/          /'
    FAIL_DETAIL="${FAIL_DETAIL}\n  $label"
  fi
}

# ── Case (a): all-quiet cycle ────────────────────────────────────────
echo "Case (a): all-quiet cycle (2 lines)"

QUIET_FIXTURE='{
  "time_str": "14:23",
  "day_str": "Fri May 8",
  "sage": {"shipped": 0, "refs": [], "ci": "green"},
  "foreman": {"landed": 0, "open": 0},
  "decide": [],
  "validate": {"count": 0},
  "watch": [],
  "board_url": "https://example.com/board"
}'

QUIET_OUT=$(echo "$QUIET_FIXTURE" | _cs_render)
assert_line_count "quiet renders exactly 2 lines"      "$QUIET_OUT" 2
assert_contains   "quiet has header (time)"            "$QUIET_OUT" "*14:23 · Fri May 8*"
assert_contains   "quiet has status line"              "$QUIET_OUT" "🟢 Sage: shipped 0"
assert_contains   "quiet has Foreman in status"        "$QUIET_OUT" "🤖 Foreman: 0 PRs landed"
assert_not_contains "quiet drops Decide"               "$QUIET_OUT" "*Decide*"
assert_not_contains "quiet drops Validate"             "$QUIET_OUT" "*Validate*"
assert_not_contains "quiet drops Watch"                "$QUIET_OUT" "*Watch:*"
assert_not_contains "quiet drops Board link"           "$QUIET_OUT" "[Board]"
assert_not_contains "quiet drops 'open' detail"        "$QUIET_OUT" "open"

# ── Case (b): populated cycle ────────────────────────────────────────
echo ""
echo "Case (b): populated cycle (all sections)"

BUSY_FIXTURE='{
  "time_str": "09:45",
  "day_str": "Mon May 5",
  "sage": {"shipped": 2, "refs": [410, 411], "ci": "green"},
  "foreman": {"landed": 3, "open": 1},
  "decide": [
    {"repo": "Sage", "num": 175},
    {"repo": "coaches", "num": 88},
    {"repo": "foreman", "num": 211}
  ],
  "validate": {"count": 2, "oldest_repo": "coaches", "oldest_num": 188, "oldest_days": 4},
  "watch": ["PR Sage#205 CI failing", "foreman bug+urgent: #220"],
  "board_url": "https://github.com/orgs/getqatalyst/projects/5"
}'

BUSY_OUT=$(echo "$BUSY_FIXTURE" | _cs_render)
assert_contains "busy has header"               "$BUSY_OUT" "*09:45 · Mon May 5*"
assert_contains "busy shows Sage shipped count" "$BUSY_OUT" "shipped 2 (#410, #411)"
assert_contains "busy shows CI green"           "$BUSY_OUT" "CI green"
assert_contains "busy shows Foreman landed"     "$BUSY_OUT" "🤖 Foreman: 3 PRs landed, 1 open"
assert_contains "busy shows Decide count"       "$BUSY_OUT" "*Decide* (3):"
assert_contains "busy shows Decide refs"        "$BUSY_OUT" "Sage#175, coaches#88, foreman#211"
assert_contains "busy shows Validate"           "$BUSY_OUT" "*Validate* (2 in Verify, oldest coaches#188 4d)"
assert_contains "busy shows Watch line 1"       "$BUSY_OUT" "*Watch:* PR Sage#205 CI failing"
assert_contains "busy shows Watch line 2"       "$BUSY_OUT" "*Watch:* foreman bug+urgent: #220"
assert_contains "busy shows Board link"         "$BUSY_OUT" "[Board](https://github.com/orgs/getqatalyst/projects/5)"

# ── Case (c): independent section drop ──────────────────────────────
echo ""
echo "Case (c): sections drop independently"

# Decide present, Validate empty, Watch present.
PARTIAL_FIXTURE='{
  "time_str": "11:00",
  "day_str": "Tue May 6",
  "sage": {"shipped": 1, "refs": [42], "ci": "red"},
  "foreman": {"landed": 0, "open": 2},
  "decide": [{"repo": "Sage", "num": 99}],
  "validate": {"count": 0},
  "watch": ["PR coaches#150 CI failing"],
  "board_url": "https://example.com/board"
}'

PARTIAL_OUT=$(echo "$PARTIAL_FIXTURE" | _cs_render)
assert_contains   "partial has Decide"          "$PARTIAL_OUT" "*Decide* (1): Sage#99"
assert_not_contains "partial drops Validate"    "$PARTIAL_OUT" "*Validate*"
assert_contains   "partial has Watch"           "$PARTIAL_OUT" "*Watch:* PR coaches#150 CI failing"
assert_contains   "partial has Board (any actionable -> link)" "$PARTIAL_OUT" "[Board]"
assert_contains   "partial shows CI red"        "$PARTIAL_OUT" "CI red"
assert_contains   "partial shows shipped 1"     "$PARTIAL_OUT" "shipped 1 (#42)"
assert_contains   "partial shows 'open' even when landed=0" "$PARTIAL_OUT" "0 PRs landed, 2 open"

# Validate-only (no Decide, no Watch).
VONLY_FIXTURE='{
  "time_str": "16:00",
  "day_str": "Wed May 7",
  "sage": {"shipped": 0, "refs": [], "ci": "green"},
  "foreman": {"landed": 0, "open": 0},
  "decide": [],
  "validate": {"count": 1, "oldest_repo": "Sage", "oldest_num": 50, "oldest_days": 2},
  "watch": [],
  "board_url": "https://example.com/board"
}'
VONLY_OUT=$(echo "$VONLY_FIXTURE" | _cs_render)
assert_not_contains "v-only drops Decide"       "$VONLY_OUT" "*Decide*"
assert_contains     "v-only has Validate"       "$VONLY_OUT" "*Validate* (1 in Verify, oldest Sage#50 2d)"
assert_not_contains "v-only drops Watch"        "$VONLY_OUT" "*Watch:*"
assert_contains     "v-only has Board link"     "$VONLY_OUT" "[Board]"

# ── Case (d): numbers flow through ──────────────────────────────────
echo ""
echo "Case (d): numbers match input fixtures"

NUM_FIXTURE='{
  "time_str": "01:01",
  "day_str": "Thu May 1",
  "sage": {"shipped": 7, "refs": [1, 2, 3], "ci": "green"},
  "foreman": {"landed": 12, "open": 5},
  "decide": [
    {"repo": "a", "num": 1}, {"repo": "b", "num": 2}, {"repo": "c", "num": 3},
    {"repo": "d", "num": 4}, {"repo": "e", "num": 5}
  ],
  "validate": {"count": 9, "oldest_repo": "x", "oldest_num": 999, "oldest_days": 17},
  "watch": ["one", "two"],
  "board_url": "https://example.com/board"
}'
NUM_OUT=$(echo "$NUM_FIXTURE" | _cs_render)
assert_contains "(d) shipped 7 (#1, #2, #3)"   "$NUM_OUT" "shipped 7 (#1, #2, #3)"
assert_contains "(d) 12 PRs landed, 5 open"    "$NUM_OUT" "12 PRs landed, 5 open"
assert_contains "(d) Decide count 5"           "$NUM_OUT" "*Decide* (5):"
assert_contains "(d) all 5 decide refs"        "$NUM_OUT" "a#1, b#2, c#3, d#4, e#5"
assert_contains "(d) Validate 9 oldest x#999 17d" "$NUM_OUT" "*Validate* (9 in Verify, oldest x#999 17d)"

# Refs cap test: >3 refs -> only first 3 render.
CAP_FIXTURE='{
  "time_str": "02:02",
  "day_str": "Fri May 2",
  "sage": {"shipped": 5, "refs": [10, 20, 30, 40, 50], "ci": "green"},
  "foreman": {"landed": 0, "open": 0},
  "decide": [],
  "validate": {"count": 0},
  "watch": [],
  "board_url": "https://example.com/board"
}'
CAP_OUT=$(echo "$CAP_FIXTURE" | _cs_render)
assert_contains     "(d) refs cap shows first 3" "$CAP_OUT" "shipped 5 (#10, #20, #30)"
assert_not_contains "(d) refs cap excludes #40"  "$CAP_OUT" "#40"
assert_not_contains "(d) refs cap excludes #50"  "$CAP_OUT" "#50"

# Watch cap test: >2 entries -> only first 2 render.
WATCH_CAP_FIXTURE='{
  "time_str": "03:03",
  "day_str": "Sat May 3",
  "sage": {"shipped": 0, "refs": [], "ci": "green"},
  "foreman": {"landed": 0, "open": 0},
  "decide": [],
  "validate": {"count": 0},
  "watch": ["alpha", "beta", "gamma"],
  "board_url": "https://example.com/board"
}'
WATCH_CAP_OUT=$(echo "$WATCH_CAP_FIXTURE" | _cs_render)
assert_contains     "(d) watch cap renders alpha" "$WATCH_CAP_OUT" "*Watch:* alpha"
assert_contains     "(d) watch cap renders beta"  "$WATCH_CAP_OUT" "*Watch:* beta"
assert_not_contains "(d) watch cap excludes gamma" "$WATCH_CAP_OUT" "gamma"

echo ""
echo "============================="
echo "Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '%b\n' "Failures:$FAIL_DETAIL"
  exit 1
fi
echo "OK"
exit 0
