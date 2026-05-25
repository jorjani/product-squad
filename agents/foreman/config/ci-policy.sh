#!/bin/bash
# CI policy: which checks are advisory (recommendations) vs gates.
# Source this file: source "$SCRIPT_DIR/config/ci-policy.sh"
#
# Two layers of advisory classification:
#   1. Static ADVISORY_CHECKS — globally always-informational (e.g. SonarCloud).
#   2. Per-repo branch protection — checks NOT in the target branch's
#      required_status_checks.contexts[] are informational for that repo.
#
# Layer 2 is consulted by review.sh for auto-merge gating (foreman#182):
# if Sage main has no required checks, SonarCloud-style failures shouldn't
# stall the auto/ PR queue. Layer 1 remains as a defense-in-depth list for
# call-sites (ci-alert, digest) that don't fetch protection state.
ADVISORY_CHECKS=("SonarCloud Code Analysis")

# JSON-encoded form for hand-off to inline Python in phase scripts.
# Using JSON avoids delimiter collisions in check names that may contain
# spaces, pipes, or other shell-meaningful characters.
ADVISORY_CHECKS_JSON=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1:]))' "${ADVISORY_CHECKS[@]}")
export ADVISORY_CHECKS_JSON

# Fetch the required-status-checks list for a repo's default merge target
# (main). Returns a JSON array of check context names; empty `[]` when the
# branch has no protection (HTTP 404) or no required checks configured.
#
# Cached per-process: review.sh's outer loop processes the same repo many
# times, and protection state doesn't change inside one run.
#
# Usage: required_checks_for_repo "getqatalyst/Sage"  # prints JSON array
required_checks_for_repo() {
  local repo="$1"
  local cache_var
  cache_var="_REQ_CHECKS_$(printf '%s' "$repo" | tr -c 'A-Za-z0-9' '_')"
  # Bash 3.2-safe indirection: read named var, return if already set.
  local cached
  eval "cached=\${$cache_var-}"
  if [ -n "${cached:-}" ]; then
    printf '%s' "$cached"
    return 0
  fi

  local raw
  raw=$(gh api "repos/$repo/branches/main/protection" 2>/dev/null || true)
  local result
  result=$(printf '%s' "$raw" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read() or '{}')
except Exception:
    data = {}
rsc = data.get('required_status_checks') or {}
contexts = rsc.get('contexts') or []
print(json.dumps(contexts))
" 2>/dev/null || echo '[]')

  eval "$cache_var=\$result"
  printf '%s' "$result"
}
