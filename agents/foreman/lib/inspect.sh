#!/bin/bash
# Inspector v0: heuristic AC-bullet classifier and compiler.
# Pure functions — no gh, no board calls. Imported by phases/inspect.sh
# and exercised directly by scripts/test-inspect.sh.
#
# Tier definitions (option B from design-system/inspector-recon.md):
#   T1 — bullet asserts source-tree state (file exists, file contains string,
#        symbol defined in path). Compilable to grep/test against a checkout.
#   T2/T3/T4 — runtime / DOM / mocked-state assertions. v0 SKIPs them.
#
# Output convention for evaluate_ac:
#   "VERDICT|REASON|total|t1|non_t1|passed|failed|compile_err"
#   pipe-delimited so callers can parse without jq.

# classify_bullet TEXT
# Echoes "T1" or "NON_T1". Fail-closed: anything ambiguous is NON_T1.
classify_bullet() {
  local text="$1"
  text=$(printf '%s' "$text" | sed -E 's/^[[:space:]]*-[[:space:]]*\[[ xX]\][[:space:]]*//')

  local lower
  lower=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$lower" | grep -qE '(deployed|production|https?://|endpoint|displays?|renders?|user can|click|redirect|browser|dom |(^|[^[:alnum:]_])ui([^[:alnum:]_]|$)|api responds|status code|http response|fetches?|loads in|server starts|runs the|when called|once a day|cron|schedule|webhook|notification|slack|email)'; then
    echo "NON_T1"
    return
  fi

  if ! printf '%s' "$text" | grep -qE '`[^`]+`'; then
    echo "NON_T1"
    return
  fi

  if printf '%s' "$lower" | grep -qE '(exists|contains|added|imports?|defines?|defined|declares?|declared|matches|references?|wires?|sources?|appended|present|mentions?)'; then
    echo "T1"
    return
  fi

  echo "NON_T1"
}

# compile_t1_bullet TEXT REPO_DIR
# Stdout: a bash command (single line) that exits 0 on pass, non-zero on fail.
# Stderr: a short reason on compile failure.
# Return code: 0 compiled, 1 compile failed.
compile_t1_bullet() {
  local text="$1"
  local repo_dir="$2"

  local backticks
  backticks=$(printf '%s\n' "$text" | grep -oE '`[^`]+`' | sed 's/^`//; s/`$//' || true)
  if [ -z "$backticks" ]; then
    echo "no backticked tokens" >&2
    return 1
  fi

  # First token that looks like a path (has slash or known extension)
  local file=""
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    if printf '%s' "$tok" | grep -qE '(/|\.(sh|md|ts|tsx|js|jsx|py|json|yaml|yml|html|css|plist|txt))$'; then
      file="$tok"
      break
    fi
  done <<< "$backticks"

  if [ -z "$file" ]; then
    echo "no file-path token" >&2
    return 1
  fi

  # Reject ".." or absolute paths to keep the shell-out bounded to repo_dir
  case "$file" in
    /*|*..*) echo "unsafe path: $file" >&2; return 1 ;;
  esac

  local target="$repo_dir/$file"

  # Second backticked token that is NOT the file path → grep needle
  local needle=""
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    if [ "$tok" != "$file" ]; then
      needle="$tok"
      break
    fi
  done <<< "$backticks"

  if [ -n "$needle" ]; then
    printf 'test -f %q && grep -F -q -- %q %q' "$target" "$needle" "$target"
  else
    printf 'test -f %q' "$target"
  fi
  return 0
}

# evaluate_ac BODY REPO_DIR
# Reads issue body markdown, walks every "- [ ]" / "- [x]" line,
# classifies, compiles, and runs T1 checks. Echoes a single
# "VERDICT|REASON|total|t1|non_t1|passed|failed|compile_err" line.
evaluate_ac() {
  local body="$1"
  local repo_dir="$2"

  # Scope to the Acceptance Criteria section (between its heading and the next heading)
  local ac_section
  ac_section=$(printf '%s\n' "$body" | sed -n '/^##[[:space:]]*[Aa]cceptance [Cc]riteria/,/^##[[:space:]]/{/^##[[:space:]]*[Aa]cceptance [Cc]riteria/d;/^##[[:space:]]/d;p;}' || true)
  # Fall back to full body if no AC heading found
  if [ -z "$ac_section" ]; then
    ac_section="$body"
  fi

  local bullets
  bullets=$(printf '%s\n' "$ac_section" | grep -E '^[[:space:]]*-[[:space:]]*\[[ xX]\]' || true)

  if [ -z "$bullets" ]; then
    echo "SKIP|no AC checklist found|0|0|0|0|0|0"
    return
  fi

  local total=0 t1=0 non_t1=0 passed=0 failed=0 compile_err=0
  local first_fail="" first_compile_err=""

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    total=$((total + 1))

    local cls
    cls=$(classify_bullet "$line" 2>/dev/null || echo "NON_T1")

    if [ "$cls" = "NON_T1" ]; then
      non_t1=$((non_t1 + 1))
      continue
    fi

    t1=$((t1 + 1))
    local cmd
    cmd=$(compile_t1_bullet "$line" "$repo_dir" 2>/dev/null) || cmd=""
    if [ -z "$cmd" ]; then
      compile_err=$((compile_err + 1))
      [ -z "$first_compile_err" ] && first_compile_err=$(_inspect_short "$line")
      continue
    fi

    # Trust boundary: $cmd is built by compile_t1_bullet using printf %q,
    # which guarantees single-token quoting regardless of issue-body content.
    if eval "$cmd" >/dev/null 2>&1; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
      [ -z "$first_fail" ] && first_fail=$(_inspect_short "$line")
    fi
  done <<< "$bullets"

  if [ "$non_t1" -gt 0 ]; then
    echo "SKIP|${non_t1}/${total} bullet(s) non-T1 (runtime/UI); v0 only checks T1|$total|$t1|$non_t1|$passed|$failed|$compile_err"
    return
  fi
  if [ "$compile_err" -gt 0 ]; then
    echo "SKIP|compile error on bullet \"${first_compile_err}\"|$total|$t1|$non_t1|$passed|$failed|$compile_err"
    return
  fi
  if [ "$failed" -gt 0 ]; then
    echo "FAIL|bullet \"${first_fail}\" failed: source check returned non-zero|$total|$t1|$non_t1|$passed|$failed|$compile_err"
    return
  fi
  if [ "$t1" -gt 0 ] && [ "$passed" -eq "$t1" ]; then
    echo "PASS|${passed} source check(s) passed|$total|$t1|$non_t1|$passed|$failed|$compile_err"
    return
  fi
  echo "SKIP|no checkable bullets|$total|$t1|$non_t1|$passed|$failed|$compile_err"
}

# inspector_comment_body VERDICT REASON
# Deterministic per (verdict, reason). Used by the phase script and asserted
# in the dedup smoke test — same inputs must produce byte-identical bodies
# so comment_dedup_or_escalate's recent-comment scan can suppress repeats.
inspector_comment_body() {
  local verdict="$1"
  local reason="$2"
  printf 'INSPECTOR: %s — %s' "$verdict" "$reason"
}

# Trim a line to a short single-line snippet for embedding in reasons/comments.
_inspect_short() {
  printf '%s' "$1" \
    | sed -E 's/^[[:space:]]*-[[:space:]]*\[[ xX]\][[:space:]]*//' \
    | tr '\n|' ' /' \
    | cut -c1-120
}

# ─── Inspector v1 (foreman#209) ──────────────────────────────────────────────
# Pure helpers for the three deterministic auto-promote classes (2C, 2D) and
# the aged-promote gate (2B). No gh, no board, no LLM — exercised directly by
# scripts/test-inspect.sh.

# REFACTOR_ALLOWLIST_RE — top-level dirs a pure structural refactor may touch.
# A diff confined to these is the 2C fast-lane: instant promote, no 7-day soak.
REFACTOR_ALLOWLIST_RE='^(config|lib|prompts|specs|docs|\.studio)/'

# classify_diff_refactor_only
# Reads newline-separated changed-file paths from stdin. Exit 0 iff the diff is
# non-empty AND every path is inside REFACTOR_ALLOWLIST_RE; exit 1 otherwise.
# Empty input fails closed (exit 1) — an empty diff is not a refactor.
classify_diff_refactor_only() {
  local seen=0 path
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    seen=1
    if ! printf '%s\n' "$path" | grep -qE "$REFACTOR_ALLOWLIST_RE"; then
      return 1
    fi
  done
  [ "$seen" -eq 1 ]
}

# lazy_init_shape BODY
# Exit 0 iff the issue body describes an event-driven producer/handler whose
# telemetry only fires when an upstream event occurs (2D). Strict on purpose:
# a false positive instant-promotes unverified work; a false negative just
# falls through to the ordinary 7-day soak.
lazy_init_shape() {
  local lower
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  printf '%s' "$lower" | grep -qE 'lazy-init|fires? (only )?(on|when|upon)|posts? [^.]*(on|when|upon) [^.]*(event|fail|miss|trigger)|creates? [^.]*(issue|ticket|comment|tracking) [^.]*when'
}

# lazy_init_anchors BODY
# Echoes candidate producer symbols — backticked identifier-shaped tokens from
# the issue body (function names, snake_case handlers), one per line, deduped.
lazy_init_anchors() {
  printf '%s\n' "$1" \
    | grep -oE '`[A-Za-z_][A-Za-z0-9_]*(\(\))?`' \
    | sed 's/^`//; s/`$//; s/()$//' \
    | sort -u
}

# find_anchor_in_repo ANCHOR REPO_DIR
# Greps REPO_DIR for a use of ANCHOR as a whole identifier. On the first hit,
# echoes "<relpath>:<line>" and exits 0; exits 1 if not found. Prefers `git
# grep` (skips .git / untracked) and falls back to `grep -rn` so the function
# is exercisable against a plain fixture dir.
find_anchor_in_repo() {
  local anchor="$1" repo_dir="$2" hit pat
  [ -z "$anchor" ] && return 1
  [ -d "$repo_dir" ] || return 1
  pat="(^|[^A-Za-z0-9_])${anchor}([^A-Za-z0-9_]|\$)"
  if git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
    hit=$(git -C "$repo_dir" grep -nE "$pat" -- . 2>/dev/null | head -1)
    [ -n "$hit" ] && { printf '%s' "$hit" | cut -d: -f1-2; return 0; }
  else
    hit=$(grep -rnE --exclude-dir=node_modules --exclude-dir=.git "$pat" "$repo_dir" 2>/dev/null | head -1)
    if [ -n "$hit" ]; then
      hit=${hit#"$repo_dir"/}
      printf '%s' "$hit" | cut -d: -f1-2
      return 0
    fi
  fi
  return 1
}

# inspect_age_days ISO8601
# Echoes whole days elapsed since the given UTC timestamp (e.g. a closing PR's
# mergedAt — Foreman's proxy for "entered Verify"). Echoes -1 when the input is
# empty or unparseable so callers can distinguish "unknown" from "0 days old".
inspect_age_days() {
  TS="$1" python3 -c "
import os, sys
from datetime import datetime, timezone
ts = os.environ.get('TS', '').strip()
if not ts:
    print(-1); sys.exit(0)
try:
    t = datetime.fromisoformat(ts.replace('Z', '+00:00'))
    print(int((datetime.now(timezone.utc) - t).total_seconds() // 86400))
except Exception:
    print(-1)
" 2>/dev/null || echo -1
}

# inspect_promote_date ISO8601 HOLD_DAYS
# Echoes the YYYY-MM-DD on which an item merged at ISO8601 clears its HOLD_DAYS
# soak. Empty string on parse failure.
inspect_promote_date() {
  TS="$1" HOLD="$2" python3 -c "
import os, sys
from datetime import datetime, timedelta
ts = os.environ.get('TS', '').strip()
try:
    t = datetime.fromisoformat(ts.replace('Z', '+00:00'))
    print((t + timedelta(days=int(os.environ['HOLD']))).strftime('%Y-%m-%d'))
except Exception:
    print('')
" 2>/dev/null || echo ""
}
