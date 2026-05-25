#!/bin/bash
# lib/ci-status.sh — classify a PR's CI rollup as pass / fail / pending / none.
#
#   pr_ci_status REPO PR_NUM  ->  prints exactly one of: pass | fail | pending | none | error
#
# Applies the same gating-vs-advisory split that phases/review.sh performs
# inline (review.sh:341-365): a check gates the verdict only when it is a
# required status check on the target branch. When the branch has no required
# checks, nothing gates and the verdict is `pass`. Statically-advisory checks
# (config/ci-policy.sh ADVISORY_CHECKS) never gate.
#
# `none` means the PR reported no checks at all — distinct from `pass`. Callers
# decide whether `none` is acceptable (e.g. getqatalyst/foreman has no CI, so
# phases/code-review.sh treats `none` as green for its own repo).
#
# `error` means the CI status could not be determined (the `gh` fetch failed —
# rate-limit / network / auth). It is NOT green: a merge gate must never read a
# failed fetch as "no checks". Fail closed — callers block on `error`.
#
# Depends on config/ci-policy.sh — source it before calling (provides
# required_checks_for_repo and ADVISORY_CHECKS_JSON). Extracted here as a lib so
# phases/code-review.sh (foreman#210) can reuse review.sh's classifier without
# calling a helper across phase boundaries.

pr_ci_status() {
  local repo="$1" pr_num="$2"
  local rollup required rc
  rollup=$(gh pr view "$pr_num" --repo "$repo" --json statusCheckRollup \
    --jq '.statusCheckRollup' 2>/dev/null)
  rc=$?
  # Fail closed: a failed fetch must NOT collapse to '[]' -> 'none', which merge
  # gates read as green. `error` means "couldn't determine" — callers block on it.
  if [ "$rc" -ne 0 ]; then
    echo 'error'
    return 0
  fi
  [ -z "$rollup" ] && rollup='[]'
  required=$(required_checks_for_repo "$repo" 2>/dev/null || echo '[]')

  ROLLUP_JSON="$rollup" REQUIRED_CHECKS_JSON="$required" \
  ADVISORY_CHECKS_JSON="${ADVISORY_CHECKS_JSON:-[]}" python3 -c "
import json, os
def load(name, default):
    try:
        return json.loads(os.environ.get(name, '') or default)
    except Exception:
        return json.loads(default)
advisory = set(load('ADVISORY_CHECKS_JSON', '[]'))
required = set(load('REQUIRED_CHECKS_JSON', '[]'))
checks = load('ROLLUP_JSON', '[]') or []
def is_gating(c):
    name = c.get('name') or ''
    if name in advisory:
        return False
    if not required:
        return False
    return name in required
gating = [c for c in checks if is_gating(c)]
if not checks:
    print('none')
elif not gating:
    print('pass')
elif any(c.get('conclusion') == 'FAILURE' or c.get('state') == 'FAILURE' for c in gating):
    print('fail')
elif all(c.get('conclusion') in ('SUCCESS', 'SKIPPED', 'NEUTRAL', None) or c.get('state') in ('SUCCESS', 'SKIPPED', 'NEUTRAL', None) for c in gating):
    print('pass')
else:
    print('pending')
" 2>/dev/null || echo 'error'
}
