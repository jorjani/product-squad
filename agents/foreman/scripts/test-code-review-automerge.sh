#!/bin/bash
# Smoke test for lib/repos.sh::repo_code_review_automerge_enabled (foreman#210).
# Pure shell, no test framework. Stubs REPOS_INDEX_JSON with fixture files.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/repos.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d -t foreman-cr-automerge-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/index.json" <<'JSON'
{
  "projects": {
    "optin":   {"repos": ["org/optin"],   "board": {"code_review_automerge": true}},
    "optout":  {"repos": ["org/optout"],  "board": {"code_review_automerge": false}},
    "nofield": {"repos": ["org/nofield"], "board": {"project_number": 5}},
    "noboard": {"repos": ["org/noboard"]},
    "archived":{"repos": ["org/archived"], "status": "archived", "board": {"code_review_automerge": true}}
  }
}
JSON
REPOS_INDEX_JSON="$TMP/index.json"

# Test 1: explicit opt-in -> true
[ "$(repo_code_review_automerge_enabled org/optin)" = "true" ] \
  && pass "board.code_review_automerge: true -> true" \
  || fail "opt-in repo should be true"

# Test 2: explicit opt-out -> false
[ "$(repo_code_review_automerge_enabled org/optout)" = "false" ] \
  && pass "board.code_review_automerge: false -> false" \
  || fail "opt-out repo should be false"

# Test 3: board present but flag missing -> false (fail-closed)
[ "$(repo_code_review_automerge_enabled org/nofield)" = "false" ] \
  && pass "board without code_review_automerge -> false" \
  || fail "missing flag should fail closed to false"

# Test 4: no board object at all -> false
[ "$(repo_code_review_automerge_enabled org/noboard)" = "false" ] \
  && pass "no board object -> false" \
  || fail "no board should fail closed to false"

# Test 5: archived project overrides explicit opt-in -> false
[ "$(repo_code_review_automerge_enabled org/archived)" = "false" ] \
  && pass "archived status overrides opt-in -> false" \
  || fail "archived project should be false even with opt-in"

# Test 6: unknown repo -> false (fail-closed)
[ "$(repo_code_review_automerge_enabled org/unknown)" = "false" ] \
  && pass "unknown repo -> false" \
  || fail "unknown repo should fail closed to false"

# Test 7: getqatalyst/foreman is the built-in opt-in exception -> true
[ "$(repo_code_review_automerge_enabled getqatalyst/foreman)" = "true" ] \
  && pass "getqatalyst/foreman special-cased -> true" \
  || fail "getqatalyst/foreman should be true"

# Test 8: foreman exception holds even when the index is missing
REPOS_INDEX_JSON="$TMP/does-not-exist.json"
[ "$(repo_code_review_automerge_enabled getqatalyst/foreman)" = "true" ] \
  && pass "foreman exception holds with missing index" \
  || fail "foreman should be true even with missing index"
# ...and a missing index fails closed for any other repo
[ "$(repo_code_review_automerge_enabled org/optin)" = "false" ] \
  && pass "missing index -> false for non-foreman repos" \
  || fail "missing index should fail closed to false"

echo ""
echo "Results: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
