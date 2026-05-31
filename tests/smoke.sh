#!/bin/bash
# smoke.sh — pre-push sanity checks for the product-squad bundle.
#
# Wraps three checks into one runnable script:
#   1. bash -n  on the wrapper scripts (draw, scope, onboard)
#   2. yaml.safe_load on manifest.yaml
#   3. claude plugin validate .  (skipped with a warning if claude is missing)
#
# Exits non-zero if any check fails. Runs all checks before exiting. Run from the repo root:
#   ./tests/smoke.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

FAIL=0

step() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf 'ok: %s\n' "$1"; }
bad()  { printf 'FAIL: %s\n' "$1"; FAIL=1; }

step "bash -n on wrapper scripts"
for script in draw scope onboard; do
  if [ ! -f "$script" ]; then
    bad "$script missing"
    continue
  fi
  if bash -n "$script"; then
    ok "$script"
  else
    bad "$script syntax error"
  fi
done

step "yaml.safe_load manifest.yaml"
if [ ! -f manifest.yaml ]; then
  bad "manifest.yaml missing"
elif python3 -c "import yaml,sys; yaml.safe_load(open('manifest.yaml'))"; then
  ok "manifest.yaml parses"
else
  bad "manifest.yaml does not parse"
fi

step "claude plugin validate ."
if ! command -v claude >/dev/null 2>&1; then
  printf 'skip: claude binary not on PATH\n'
elif claude plugin validate . >/dev/null 2>&1; then
  ok "plugin validates"
else
  bad "claude plugin validate . failed"
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  echo "smoke: PASS"
  exit 0
else
  echo "smoke: FAIL"
  exit 1
fi
