#!/bin/bash
# Smoke test for lib/inspect.sh.
#
# Pure-function tests against fixture files in a tmp dir — no gh, no board.
# Cases:
#   (a) all-T1 PASS  — every bullet is a source-tree check that passes
#   (b) one T1 FAIL  — bullet asserts content that is not in the file
#   (c) mixed T1+non-T1 SKIP — any non-T1 bullet shorts the whole AC to SKIP
#   (d) malformed bullets — empty / no-backticks / weird shape never crash, fail-closed to SKIP
#   (e) dedup property — inspector_comment_body is deterministic so
#       comment_dedup_or_escalate's recent-comment scan can suppress repeats

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/inspect.sh"

PASS=0
FAIL=0
FAIL_DETAIL=""

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    echo "  PASS  $label"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $label"
    echo "        expected: $expected"
    echo "        got:      $actual"
    FAIL_DETAIL="${FAIL_DETAIL}\n  $label"
  fi
}

assert_starts_with() {
  local label="$1" actual="$2" prefix="$3"
  case "$actual" in
    "$prefix"*) PASS=$((PASS + 1)); echo "  PASS  $label" ;;
    *)
      FAIL=$((FAIL + 1))
      echo "  FAIL  $label"
      echo "        expected prefix: $prefix"
      echo "        got:             $actual"
      FAIL_DETAIL="${FAIL_DETAIL}\n  $label"
      ;;
  esac
}

# ── Fixture tree ─────────────────────────────────────────────────────
TMP=$(mktemp -d -t foreman-inspect-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/phases" "$TMP/lib" "$TMP/src"
cat > "$TMP/phases/inspect.sh" <<'EOF'
#!/bin/bash
echo "INSPECT PHASE: passed=0 failed=0 skipped=0"
EOF
cat > "$TMP/lib/inspect.sh" <<'EOF'
classify_bullet() { echo "T1"; }
EOF
cat > "$TMP/src/example.ts" <<'EOF'
export const foo = 42;
EOF

# ── Case (a): all-T1 PASS ────────────────────────────────────────────
echo "Case (a): all-T1 PASS"
BODY_PASS='## Acceptance criteria

- [ ] `phases/inspect.sh` exists and contains `INSPECT PHASE`
- [ ] `lib/inspect.sh` defines `classify_bullet`
- [ ] `src/example.ts` contains `foo`'

R=$(evaluate_ac "$BODY_PASS" "$TMP")
IFS='|' read -r V REASON TOTAL T1 NONT1 P F C <<< "$R"
assert_eq "(a) verdict is PASS" "$V" "PASS"
assert_eq "(a) total bullets"   "$TOTAL" "3"
assert_eq "(a) all classified T1" "$T1" "3"
assert_eq "(a) all passed"      "$P" "3"
assert_eq "(a) zero failures"   "$F" "0"

# ── Case (b): one T1 FAIL ────────────────────────────────────────────
echo ""
echo "Case (b): one T1 FAIL"
BODY_FAIL='- [ ] `phases/inspect.sh` exists and contains `INSPECT PHASE`
- [ ] `phases/inspect.sh` contains `definitely-not-in-this-file-zzz`'

R=$(evaluate_ac "$BODY_FAIL" "$TMP")
IFS='|' read -r V REASON TOTAL T1 NONT1 P F C <<< "$R"
assert_eq "(b) verdict is FAIL" "$V" "FAIL"
assert_eq "(b) one passed"      "$P" "1"
assert_eq "(b) one failed"      "$F" "1"

# ── Case (c): mixed T1+non-T1 → SKIP ─────────────────────────────────
echo ""
echo "Case (c): mixed T1+non-T1 → SKIP"
BODY_MIXED='- [ ] `phases/inspect.sh` exists
- [ ] User can click the deploy button on https://example.com and the page renders'

R=$(evaluate_ac "$BODY_MIXED" "$TMP")
IFS='|' read -r V REASON TOTAL T1 NONT1 P F C <<< "$R"
assert_eq "(c) verdict is SKIP"      "$V" "SKIP"
assert_eq "(c) one T1, one non-T1"   "${T1}/${NONT1}" "1/1"

# ── Case (d): malformed bullets → SKIP, no crash ─────────────────────
echo ""
echo "Case (d): malformed bullets → SKIP, no crash"
BODY_MALFORMED='- [ ]
- [ ] ``
- [ ] random text without any backticks at all
- [ ] `unsafe/../path.ts` exists
- [ ] `/etc/passwd` exists'

# Must not crash regardless of input shape.
R=$(evaluate_ac "$BODY_MALFORMED" "$TMP" 2>/dev/null || echo "CRASH|crash|0|0|0|0|0|0")
IFS='|' read -r V REASON TOTAL T1 NONT1 P F C <<< "$R"
case "$V" in
  SKIP) PASS=$((PASS + 1)); echo "  PASS  (d) malformed input → SKIP (verdict=$V)" ;;
  *)    FAIL=$((FAIL + 1)); echo "  FAIL  (d) expected SKIP, got $V"; FAIL_DETAIL="${FAIL_DETAIL}\n  (d)" ;;
esac

# Empty body should also SKIP cleanly.
R=$(evaluate_ac "" "$TMP" 2>/dev/null || echo "CRASH")
assert_starts_with "(d) empty body → SKIP" "$R" "SKIP|"

# Path-traversal bullet must not produce a file read attempt outside repo_dir.
# compile_t1_bullet rejects ".." and absolute paths; verify directly.
if compile_t1_bullet '- [ ] `unsafe/../path.ts` exists' "$TMP" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  FAIL  (d) compile_t1_bullet should reject path traversal"
  FAIL_DETAIL="${FAIL_DETAIL}\n  (d) traversal"
else
  PASS=$((PASS + 1))
  echo "  PASS  (d) compile_t1_bullet rejects path traversal"
fi

if compile_t1_bullet '- [ ] `/etc/passwd` exists' "$TMP" 2>/dev/null; then
  FAIL=$((FAIL + 1))
  echo "  FAIL  (d) compile_t1_bullet should reject absolute path"
  FAIL_DETAIL="${FAIL_DETAIL}\n  (d) absolute"
else
  PASS=$((PASS + 1))
  echo "  PASS  (d) compile_t1_bullet rejects absolute path"
fi

# ── Case (e): dedup property — body is deterministic ─────────────────
echo ""
echo "Case (e): dedup property"
B1=$(inspector_comment_body "PASS" "3 source check(s) passed")
B2=$(inspector_comment_body "PASS" "3 source check(s) passed")
assert_eq "(e) same input → byte-identical body" "$B1" "$B2"
assert_eq "(e) body matches expected prefix" "$B1" "INSPECTOR: PASS — 3 source check(s) passed"

# Different reason → different body (so a real change still surfaces).
B3=$(inspector_comment_body "PASS" "4 source check(s) passed")
if [ "$B1" != "$B3" ]; then
  PASS=$((PASS + 1))
  echo "  PASS  (e) different reason → different body"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL  (e) different reason should yield different body"
  FAIL_DETAIL="${FAIL_DETAIL}\n  (e) reason differs"
fi

# v1 verdict suffix bodies are deterministic too (route through dedup).
B4=$(inspector_comment_body "PASS (refactor-allowlist)" "diff scoped to config/")
B5=$(inspector_comment_body "PASS (refactor-allowlist)" "diff scoped to config/")
assert_eq "(e) refactor-allowlist body deterministic" "$B4" "$B5"
assert_starts_with "(e) refactor-allowlist body prefix" "$B4" "INSPECTOR: PASS (refactor-allowlist) —"

# ── Case (f): 2C refactor-allowlist diff classifier ──────────────────
echo ""
echo "Case (f): classify_diff_refactor_only"
if printf 'config/board-ids.sh\nlib/inspect.sh\nprompts/triage.md\n' | classify_diff_refactor_only; then
  PASS=$((PASS + 1)); echo "  PASS  (f) all-allowlist diff → refactor"
else
  FAIL=$((FAIL + 1)); echo "  FAIL  (f) all-allowlist diff should classify as refactor"
  FAIL_DETAIL="${FAIL_DETAIL}\n  (f) all-allowlist"
fi
if printf 'lib/inspect.sh\nphases/build.sh\n' | classify_diff_refactor_only; then
  FAIL=$((FAIL + 1)); echo "  FAIL  (f) diff touching phases/ should NOT be refactor"
  FAIL_DETAIL="${FAIL_DETAIL}\n  (f) out-of-allowlist"
else
  PASS=$((PASS + 1)); echo "  PASS  (f) diff touching phases/ → not refactor"
fi
if printf '' | classify_diff_refactor_only; then
  FAIL=$((FAIL + 1)); echo "  FAIL  (f) empty diff should fail closed"
  FAIL_DETAIL="${FAIL_DETAIL}\n  (f) empty"
else
  PASS=$((PASS + 1)); echo "  PASS  (f) empty diff → not refactor (fail closed)"
fi

# ── Case (g): 2D lazy-init shape detector ────────────────────────────
echo ""
echo "Case (g): lazy_init_shape"
if lazy_init_shape 'The producer posts a PROPOSE-MISS comment on a self-improve miss event.'; then
  PASS=$((PASS + 1)); echo "  PASS  (g) 'posts X on Y event' → lazy-init shape"
else
  FAIL=$((FAIL + 1)); echo "  FAIL  (g) 'posts X on Y event' should match"
  FAIL_DETAIL="${FAIL_DETAIL}\n  (g) posts-on-event"
fi
if lazy_init_shape 'mark_orphan() fires on a push-fail.'; then
  PASS=$((PASS + 1)); echo "  PASS  (g) 'fires on ...' → lazy-init shape"
else
  FAIL=$((FAIL + 1)); echo "  FAIL  (g) 'fires on ...' should match"
  FAIL_DETAIL="${FAIL_DETAIL}\n  (g) fires-on"
fi
if lazy_init_shape 'Refactor the build phase to extract a helper function.'; then
  FAIL=$((FAIL + 1)); echo "  FAIL  (g) plain refactor should NOT match lazy-init"
  FAIL_DETAIL="${FAIL_DETAIL}\n  (g) false-positive"
else
  PASS=$((PASS + 1)); echo "  PASS  (g) plain refactor → not lazy-init shape"
fi

# ── Case (h): 2D anchor extraction + repo grep ───────────────────────
echo ""
echo "Case (h): lazy_init_anchors + find_anchor_in_repo"
cat > "$TMP/src/producer.sh" <<'EOF'
mark_orphan() {
  echo "orphan marked"
}
EOF
ANCHORS=$(lazy_init_anchors 'The handler `mark_orphan()` fires; see also `noise`.')
case "$ANCHORS" in
  *mark_orphan*) PASS=$((PASS + 1)); echo "  PASS  (h) extracts backticked identifier anchor" ;;
  *) FAIL=$((FAIL + 1)); echo "  FAIL  (h) expected mark_orphan in anchors, got: $ANCHORS"
     FAIL_DETAIL="${FAIL_DETAIL}\n  (h) anchors" ;;
esac
HIT=$(find_anchor_in_repo "mark_orphan" "$TMP" 2>/dev/null)
case "$HIT" in
  src/producer.sh:*) PASS=$((PASS + 1)); echo "  PASS  (h) find_anchor_in_repo locates producer ($HIT)" ;;
  *) FAIL=$((FAIL + 1)); echo "  FAIL  (h) expected src/producer.sh:N, got: $HIT"
     FAIL_DETAIL="${FAIL_DETAIL}\n  (h) anchor-hit" ;;
esac
if find_anchor_in_repo "definitely_not_a_symbol_zzz" "$TMP" >/dev/null 2>&1; then
  FAIL=$((FAIL + 1)); echo "  FAIL  (h) find_anchor_in_repo should miss an absent symbol"
  FAIL_DETAIL="${FAIL_DETAIL}\n  (h) anchor-miss"
else
  PASS=$((PASS + 1)); echo "  PASS  (h) find_anchor_in_repo misses an absent symbol"
fi

# ── Case (i): 2B aging-window helpers ────────────────────────────────
echo ""
echo "Case (i): inspect_age_days + inspect_promote_date"
assert_eq "(i) empty timestamp → -1 (unknown)" "$(inspect_age_days '')" "-1"
assert_eq "(i) garbage timestamp → -1 (unknown)" "$(inspect_age_days 'not-a-date')" "-1"
OLD_AGE=$(inspect_age_days '2020-01-01T00:00:00Z')
if [ "$OLD_AGE" -ge 7 ]; then
  PASS=$((PASS + 1)); echo "  PASS  (i) far-past timestamp ages past the 7d hold ($OLD_AGE d)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL  (i) far-past timestamp should age >= 7d, got $OLD_AGE"
  FAIL_DETAIL="${FAIL_DETAIL}\n  (i) old-age"
fi
assert_eq "(i) promote date = merge + 7d" "$(inspect_promote_date '2026-05-01T00:00:00Z' 7)" "2026-05-08"
assert_eq "(i) promote date empty on parse failure" "$(inspect_promote_date 'bad' 7)" ""

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────"
echo "  $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf "Failures:%b\n" "$FAIL_DETAIL"
  exit 1
fi
exit 0
