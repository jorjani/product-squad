#!/bin/bash
# Smoke test for lib/repos.sh::sarge_eligible_repos (foreman#192).
# Pure shell, no test framework. Stubs REPOS_INDEX_JSON with fixture files.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/repos.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1" >&2; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d -t foreman-sarge-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Test 1: agents.sarge with "scope" is included; without "scope" excluded
# ---------------------------------------------------------------------------
cat > "$TMP/index1.json" <<'JSON'
{
  "projects": {
    "alpha": {"repos": ["org/alpha"], "agents": {"sarge": ["scope"]}},
    "beta":  {"repos": ["org/beta"],  "agents": {"sarge": []}},
    "gamma": {"repos": ["org/gamma"], "agents": {}},
    "delta": {"repos": ["org/delta"], "agents": {"sarge": ["scope", "review"]}}
  }
}
JSON

REPOS_INDEX_JSON="$TMP/index1.json"
result=$(sarge_eligible_repos)
# Order is dict-iteration order (insertion in py3.7+), so alpha then delta.
expected="org/alpha org/delta"
if [ "$result" = "$expected" ]; then
  pass "filters in only repos whose agents.sarge contains 'scope'"
else
  fail "expected '$expected', got '$result'"
fi

# ---------------------------------------------------------------------------
# Test 2: project with multiple repos emits each repo
# ---------------------------------------------------------------------------
cat > "$TMP/index2.json" <<'JSON'
{
  "projects": {
    "multi": {"repos": ["org/r1", "org/r2"], "agents": {"sarge": ["scope"]}}
  }
}
JSON

REPOS_INDEX_JSON="$TMP/index2.json"
result=$(sarge_eligible_repos)
if [ "$result" = "org/r1 org/r2" ]; then
  pass "expands a project's repos array"
else
  fail "expected 'org/r1 org/r2', got '$result'"
fi

# ---------------------------------------------------------------------------
# Test 3: empty index -> empty string (no crash)
# ---------------------------------------------------------------------------
cat > "$TMP/index3.json" <<'JSON'
{"projects": {}}
JSON

REPOS_INDEX_JSON="$TMP/index3.json"
result=$(sarge_eligible_repos)
if [ -z "$result" ]; then
  pass "empty projects -> empty output"
else
  fail "expected empty, got '$result'"
fi

# ---------------------------------------------------------------------------
# Test 4: missing agents key -> excluded (no crash on missing key)
# ---------------------------------------------------------------------------
cat > "$TMP/index4.json" <<'JSON'
{
  "projects": {
    "noagents": {"repos": ["org/noagents"]}
  }
}
JSON

REPOS_INDEX_JSON="$TMP/index4.json"
result=$(sarge_eligible_repos)
if [ -z "$result" ]; then
  pass "missing agents key -> excluded (no crash)"
else
  fail "expected empty, got '$result'"
fi

echo ""
echo "Results: $PASS pass, $FAIL fail"
[ "$FAIL" -eq 0 ] || exit 1
