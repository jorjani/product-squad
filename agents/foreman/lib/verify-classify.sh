#!/bin/bash
# Foreman verify-FAIL classifier.
#
# When phases/verify.sh's assertion fails, the root cause matters: a Railway
# deploy that hasn't rolled yet (deploy-lag) and a real production bug
# (assertion-fail) both surface identically today, so Foreman files
# false-positive bug tickets that David then has to close (Sage#239/245/247/248).
#
# This module exposes a pure function classify_verify_fail() that returns one
# of three verdicts. Callers map the verdict to an action; the function itself
# has no side effects. Logging is a separate helper (log_verify_classify).
#
# Inputs:
#   pr_merged_at     ISO8601 (e.g. 2026-05-08T12:48:02Z) — from gh pr view
#   build_time       ISO8601 of deployed build (from /api/version or /health),
#                    or empty if neither endpoint exposes one.
#   fp_expected      Optional fingerprint we expected (e.g. main HEAD SHA).
#                    Empty in current usage; reserved for Inspector v0+.
#   fp_actual        Optional fingerprint of deployed build (e.g. version
#                    field from /api/version). Empty if not available.
#   error_string     Optional Claude/curl error text. Used only to flag
#                    transient/network failures as unknown rather than
#                    assertion-fail when the build is current.
#
# Verdicts:
#   deploy-lag       Prod hasn't caught up. Retry, no ticket, no FAIL comment.
#   assertion-fail   Real bug. File ticket as today, FAIL comment, board move.
#   unknown          Can't classify with confidence. File ticket BUT tag with
#                    verify-classifier-unsure so Inspector can second-look.
#
# Decision rules (first match wins):
#   1. build_time empty AND fp_actual empty                 -> unknown
#   2. build_time present AND build_time < pr_merged_at     -> deploy-lag
#   3. fp_expected != fp_actual (both non-empty)            -> deploy-lag
#   4. build_time present AND error_string is transient     -> unknown
#   5. otherwise (build current, no contradiction)          -> assertion-fail
#
# Fabro 6-class taxonomy — vocabulary target. v1 implements the first two; the
# remaining four are reserved for future verdict additions and must use these
# names rather than ad-hoc strings.
#
#   transient_infra    deploy-lag    deploy hasn't propagated; infrastructure race.
#   deterministic      assertion-fail real code/data bug; reproducible.
#   budget_exhausted   (reserved)    Claude budget cap hit before assertion ran.
#   compilation_loop   (reserved)    repeated build attempts on identical inputs.
#   canceled           (reserved)    PR closed, branch deleted, or run aborted mid-flight.
#   structural         (reserved)    upstream config/env break unrelated to the PR's diff.
#
# The verdict strings emitted today (deploy-lag, assertion-fail, unknown) stay
# as-is for v1 — log compatibility. `unknown` is the Fabro fallback for "can't
# classify with confidence" and routes to Inspector second-look.

# Lexicographic ISO8601 comparison is safe iff both strings are normalized to
# UTC with the same precision. gh's mergedAt is always `...Z`; the Sage
# /api/version buildTime is `2026-05-08T04:13:39Z`. We do not attempt to parse
# offsets like `+00:00` — if a future endpoint emits a non-Z timestamp, the
# caller must normalize before passing in (or accept the unknown verdict).
#
# Returns the verdict on stdout. Always exits 0 unless inputs are malformed.
classify_verify_fail() {
  local merged_at="${1:-}"
  local build_time="${2:-}"
  local fp_expected="${3:-}"
  local fp_actual="${4:-}"
  local error_string="${5:-}"

  # No build_time AND no fingerprint — no way to tell if deploy is current.
  if [ -z "$build_time" ] && [ -z "$fp_actual" ]; then
    echo "unknown"
    return 0
  fi

  # Build is older than the merge — deploy hasn't propagated.
  if [ -n "$build_time" ] && [ -n "$merged_at" ] && [[ "$build_time" < "$merged_at" ]]; then
    echo "deploy-lag"
    return 0
  fi

  # Fingerprints disagree — deploy is rolling, even if buildTime looks fresh.
  if [ -n "$fp_expected" ] && [ -n "$fp_actual" ] && [ "$fp_expected" != "$fp_actual" ]; then
    echo "deploy-lag"
    return 0
  fi

  # Build is current. If the failure looks transient (network/5xx/timeout),
  # surface as unknown rather than blame the code.
  if [ -n "$error_string" ] && _verify_classify_is_transient "$error_string"; then
    echo "unknown"
    return 0
  fi

  # Build is current, no fingerprint contradiction, no transient marker.
  # Either fingerprint matches, or we have buildTime>=mergedAt but no
  # fingerprint at all. Treat as a real failure.
  echo "assertion-fail"
}

# Pattern-match common transient/infrastructure failures. Intentionally
# narrow — we want to avoid swallowing genuine HTTP-400 / response-shape
# bugs by pattern-matching too aggressively. Add patterns only when a
# real false-classification incident motivates it.
_verify_classify_is_transient() {
  local err="$1"
  local lower
  lower=$(printf '%s' "$err" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *"timeout"*|*"timed out"*) return 0 ;;
    *"econnreset"*|*"econnrefused"*|*"connection reset"*|*"connection refused"*) return 0 ;;
    *" 502 "*|*" 503 "*|*" 504 "*|*"bad gateway"*|*"service unavailable"*|*"gateway timeout"*) return 0 ;;
    *"network error"*|*"could not resolve"*|*"name resolution"*) return 0 ;;
  esac
  return 1
}

# Append a single classification record to results/verify-classify.log.
# Schema: pipe-delimited, one line per classification. Inspector v0 reads
# this to second-look unknown verdicts and to learn drift in classifier
# accuracy over time.
#
# Usage:
#   log_verify_classify LOG_DIR REPO ISSUE PR MERGED BUILDTIME FP_EXP FP_ACT VERDICT ACTION
log_verify_classify() {
  local log_dir="$1"
  local repo="$2"
  local issue="$3"
  local pr="$4"
  local merged="$5"
  local buildtime="$6"
  local fp_exp="$7"
  local fp_act="$8"
  local verdict="$9"
  local action="${10}"

  mkdir -p "$log_dir"
  local log_file="$log_dir/verify-classify.log"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  printf '%s|repo=%s|issue=%s|pr=%s|merged=%s|build=%s|fp_exp=%s|fp_act=%s|verdict=%s|action=%s\n' \
    "$now" "$repo" "$issue" "$pr" "$merged" "$buildtime" "$fp_exp" "$fp_act" "$verdict" "$action" \
    >> "$log_file"
}

# Has this PR already been classified today? Used to dedupe re-runs of
# verify.sh on the same merged PR (e.g. during a manual rerun or a
# launchd retry). Returns 0 if a classification record exists for this
# repo+pr in the log, 1 otherwise.
already_classified() {
  local log_dir="$1"
  local repo="$2"
  local pr="$3"
  local log_file="$log_dir/verify-classify.log"
  [ -f "$log_file" ] || return 1
  grep -q "|repo=$repo|.*|pr=$pr|" "$log_file"
}
