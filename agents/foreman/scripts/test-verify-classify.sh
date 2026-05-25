#!/bin/bash
# Smoke tests for lib/verify-classify.sh.
#
# 5 fixtures (per foreman#200):
#   1. deploy-lag                          build < merge -> deploy-lag
#   2. real-assertion-fail                 build >= merge, no transient -> assertion-fail
#   3. unknown-no-buildtime                no buildTime, no fingerprint -> unknown
#   4. unknown-fingerprint-match-but-error transient error string -> unknown
#   5. dedup                               re-classify same PR twice; log keeps both
#                                          (we test already_classified detects it)
#
# Usage: ./scripts/test-verify-classify.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/lib/verify-classify.sh"

PASS=0
FAIL=0
FAILS=()

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    FAILS+=("$label: expected='$expected' got='$actual'")
    echo "  FAIL: $label  expected='$expected'  got='$actual'"
  fi
}

echo "=== fixture 1: deploy-lag ==="
# Sage#239-style: PR merged at 12:48Z, prod build is from 12:25Z (Railway propagating).
v=$(classify_verify_fail "2026-05-08T12:48:02Z" "2026-05-08T12:25:00Z" "" "railway-old" "")
assert_eq "deploy-lag verdict" "deploy-lag" "$v"

echo "=== fixture 2: real-assertion-fail ==="
# Build is newer than merge (deploy current), Claude reported a feature failure.
v=$(classify_verify_fail "2026-05-08T12:48:02Z" "2026-05-08T12:55:00Z" "" "railway-new" "AC1 failed: expected duplicate banner, got nothing")
assert_eq "assertion-fail verdict" "assertion-fail" "$v"

echo "=== fixture 3: unknown-no-buildtime ==="
# Endpoint exposes no buildTime AND no version field — classifier can't tell.
v=$(classify_verify_fail "2026-05-08T12:48:02Z" "" "" "" "")
assert_eq "unknown verdict" "unknown" "$v"

echo "=== fixture 4: unknown-fingerprint-match-but-error ==="
# Build is current AND fingerprint matches expected, but Claude got a 503.
# Conservatively unknown — could be a flake, not necessarily a real bug.
v=$(classify_verify_fail "2026-05-08T12:48:02Z" "2026-05-08T12:55:00Z" "railway-new" "railway-new" "got HTTP 503 Service Unavailable from /api/jobs")
assert_eq "transient -> unknown" "unknown" "$v"

echo "=== fixture 5: dedup (already_classified detection) ==="
# Use a temp log dir so we don't pollute results/.
TMP_LOG_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_LOG_DIR"' EXIT

# Before any log writes, already_classified should be false.
if already_classified "$TMP_LOG_DIR" "getqatalyst/Sage" "999"; then
  FAIL=$((FAIL + 1)); FAILS+=("dedup: already_classified should be false on empty log")
  echo "  FAIL: dedup empty-log check"
else
  PASS=$((PASS + 1))
  echo "  PASS: dedup empty-log returns 1"
fi

# Log a classification, then verify already_classified returns true.
log_verify_classify "$TMP_LOG_DIR" "getqatalyst/Sage" "239" "238" \
  "2026-05-08T12:48:02Z" "2026-05-08T12:25:00Z" "" "railway-old" "deploy-lag" "retry-no-ticket"

if already_classified "$TMP_LOG_DIR" "getqatalyst/Sage" "238"; then
  PASS=$((PASS + 1))
  echo "  PASS: dedup detected after log write"
else
  FAIL=$((FAIL + 1)); FAILS+=("dedup: already_classified should be true after log write")
  echo "  FAIL: dedup post-log check"
fi

# Log line shape sanity: should contain pipe-delimited fields and the verdict.
LOG_LINE=$(tail -1 "$TMP_LOG_DIR/verify-classify.log")
shape_ok=1
for needle in "|repo=getqatalyst/Sage|" "|pr=238|" "|verdict=deploy-lag|" "|action=retry-no-ticket"; do
  case "$LOG_LINE" in *"$needle"*) ;; *) shape_ok=0 ;; esac
done
if [ "$shape_ok" = "1" ]; then
  PASS=$((PASS + 1))
  echo "  PASS: log line shape ok"
else
  FAIL=$((FAIL + 1)); FAILS+=("dedup: log line shape unexpected: $LOG_LINE")
  echo "  FAIL: log line shape: $LOG_LINE"
fi

# Re-classifying with a different action should append (not overwrite).
log_verify_classify "$TMP_LOG_DIR" "getqatalyst/Sage" "239" "238" \
  "2026-05-08T12:48:02Z" "2026-05-08T12:55:00Z" "" "railway-new" "assertion-fail" "file-ticket"
LINE_COUNT=$(wc -l < "$TMP_LOG_DIR/verify-classify.log" | tr -d ' ')
assert_eq "log appends, doesn't overwrite" "2" "$LINE_COUNT"

echo
echo "=== summary ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ $FAIL -gt 0 ]; then
  echo
  echo "Failures:"
  for f in "${FAILS[@]}"; do
    echo "  - $f"
  done
  exit 1
fi
exit 0
