#!/bin/bash
# Phase: Inspect — Verify -> Done gate (Inspector v1: deterministic classes +
# LLM-judge + aged-promote gate). foreman#209.
#
# Per Verify-column item, in order:
#
#   2C. refactor-allowlist  — closing PR merged AND diff confined to
#       (config|lib|prompts|specs|docs|design-system)/  -> PASS, instant Done.
#   2D. lazy-init           — issue body describes an event-driven producer
#       AND a grep-able anchor for it exists in the merged code
#                                                  -> PASS, instant Done.
#   Split-verify (v0)       — file-extension UI/non-UI classifier on the PR.
#       Pure non-UI + merged -> behavior PASS (-> aged gate).
#       Mixed/pure-UI        -> SKIP (-> LLM path).
#       Non-UI verify failed -> FAIL.
#   LLM path                — where the deterministic path SKIPs: a Haiku
#       classifier routes the AC tier; for T2 a Sonnet judge reads captured
#       HTTP + two-log-stream evidence. T3 (browser) and T4 (mocked state)
#       are SKIPped. PASS verdicts route through the aged gate.
#   2B. aged-promote gate   — a behavior PASS soaks INSPECT_HOLD_DAYS in
#       Verify (measured from the closing PR's mergedAt) before reaching
#       Done. Under the hold: INSPECTOR: HOLDING (Nd/Hd), once per day.
#
# Kill switch: INSPECT_DISABLE_LLM=1 skips the LLM path entirely — the
# deterministic classes (2C/2D/split-verify/aged gate) still run, no LLM API
# calls are made. Budget: the LLM path stops after INSPECT_BUDGET worth of
# classify+judge spend and SKIPs the remaining items.
#
# POSTS: INSPECTOR:
# READS: results/*.log + results/inspector.log (two-log-stream evidence, 2E)
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
DATE=$(date +%Y-%m-%d)
LOG="$RESULTS_DIR/$DATE.log"
INSPECTOR_LOG="$RESULTS_DIR/inspector.log"

# Authorization signal for move_to_done() in config/board-ids.sh — Inspector is
# the only programmatic caller; Foreman build phases must not promote to Done.
export INSPECTOR_RUN_ID="$DATE-$$"

mkdir -p "$RESULTS_DIR"

# Daily-once guard (same pattern as cleanup.sh)
SENTINEL="$RESULTS_DIR/.inspect-ran-$DATE"
if [ -f "$SENTINEL" ]; then
  echo "INSPECT: Already ran today" >> "$LOG"
  echo "INSPECT PHASE: passed=0 failed=0 skipped=0 held=0 (already-ran)" >> "$LOG"
  echo "passed=0 failed=0 skipped=0 held=0"
  exit 0
fi

# shellcheck disable=SC1091
. "$SCRIPT_DIR/config/board-ids.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/config/model-routing.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/config/thresholds.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/comments.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/inspect.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/repos.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/bounded.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/questions.sh"

# run_bounded globals — init so `set -u` is satisfied before the first call.
PROBE_OUT=""
PROBE_EXIT=0

# Kill switch (foreman#209 spec §2A): INSPECT_DISABLE_LLM=1 -> no LLM calls.
if [ "${INSPECT_DISABLE_LLM:-}" = "1" ]; then
  LLM_ENABLED=0
  echo "INSPECT: LLM path disabled (INSPECT_DISABLE_LLM=1)" >> "$LOG"
else
  LLM_ENABLED=1
fi

# Budget cap: the LLM path stops once classify+judge spend would exceed
# INSPECT_BUDGET. Conservative — every LLM-path item is charged the full
# classify+judge cap even when only the classifier runs. Budget values pass
# via env (not interpolated into the Python source); a calc error surfaces
# on stderr and disables the LLM path (fail closed, 0 — never silently 3).
INSPECT_MAX_LLM_ITEMS=$(INSPECT_BUDGET="${INSPECT_BUDGET:-5}" \
  INSPECT_CLASSIFY_BUDGET="${INSPECT_CLASSIFY_BUDGET:-0.5}" \
  INSPECT_JUDGE_BUDGET="${INSPECT_JUDGE_BUDGET:-1}" python3 -c "
import os
b = float(os.environ['INSPECT_BUDGET'])
per = float(os.environ['INSPECT_CLASSIFY_BUDGET']) + float(os.environ['INSPECT_JUDGE_BUDGET'])
print(max(1, int(b / per)) if per > 0 else 0)
" || echo 0)
LLM_ITEMS_USED=0

# Repo -> local directory mapping is derived from ~/Projects/.index.json via
# lib/repos.sh::repo_to_path (already sourced above; centralized to survive renames).

# Reads newline-separated file paths from stdin. Prints the subset whose
# extension is UI (.tsx/.jsx/.css/.scss/.html/.svg/.vue). Empty output = no UI.
classify_pr_has_ui() {
  grep -E '\.(tsx|jsx|css|scss|html|svg|vue)$' || true
}

# Args: repo pr_num
# Returns: exit 0 (PASS) or 1 (FAIL). Prints one-line reason to stdout.
# Logic: PR merged = PASS. We deliberately do NOT separately check CI — if the
# team (or Foreman's auto-merge) merged the PR, they accepted whatever CI state
# it was in. The merge action itself is the verdict.
verify_nonui() {
  local repo="$1" pr_num="$2"
  local pr_state
  pr_state=$(gh pr view "$pr_num" --repo "$repo" --json state --jq '.state' 2>/dev/null || echo "")
  if [ "$pr_state" != "MERGED" ]; then
    echo "PR #$pr_num state=$pr_state (expected MERGED)"
    return 1
  fi
  echo "PR #$pr_num merged"
  return 0
}

# emit_inspector_jsonl VERDICT KLASS AGE MODEL REASON
# Appends one JSONL record to results/inspector.log. Reads loop-locals REPO,
# ISSUE_NUM, PR_NUM, START_MS for the remaining fields.
emit_inspector_jsonl() {
  local verdict="$1" klass="$2" age="$3" model="$4" reason="$5"
  local ts reason_json end_ms latency
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  end_ms=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo 0)
  latency=$((end_ms - START_MS))
  reason_json=$(printf '%s' "$reason" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '"<encode-error>"')
  printf '{"ts":"%s","repo":"%s","issue":%s,"pr":%s,"verdict":"%s","class":"%s","age_days":%s,"model":"%s","latency_ms":%s,"reason":%s}\n' \
    "$ts" "$REPO" "$ISSUE_NUM" "${PR_NUM:-null}" "$verdict" "$klass" "${age:--1}" "$model" "$latency" "$reason_json" \
    >> "$INSPECTOR_LOG"
}

# apply_verdict REPO ISSUE LABEL REASON CTX
# Posts the INSPECTOR comment (deduped) and moves the board per the verdict.
# LABEL's leading word decides the action: PASS -> Done, FAIL -> Scope,
# anything else (HOLDING/SKIP) -> comment only, leave in Verify.
# Returns 1 only when a PASS board mutation failed (caller skips the count).
apply_verdict() {
  local repo="$1" issue="$2" label="$3" reason="$4" ctx="$5"
  local body word move_out
  body=$(inspector_comment_body "$label" "$reason")
  word="${label%% *}"
  case "$word" in
    PASS)
      move_out=$(move_to_done "$repo" "$issue" 2>&1) || true
      echo "$move_out" >> "$LOG"
      if printf '%s' "$move_out" | grep -q "Failed to move"; then
        echo "WARN INSPECT: $repo#$issue PASS but board mutation failed" >> "$LOG"
        return 1
      fi
      comment_dedup_or_escalate "$repo" "$issue" "$body" "$ctx" >/dev/null 2>&1 || true
      echo "INSPECT: $repo#$issue $label — $reason" >> "$LOG"
      ;;
    FAIL)
      move_to_scope "$repo" "$issue" >> "$LOG" 2>&1 || true
      comment_dedup_or_escalate "$repo" "$issue" "$body" "$ctx" >/dev/null 2>&1 || true
      echo "INSPECT: $repo#$issue FAIL — $reason" >> "$LOG"
      ;;
    *)
      comment_dedup_or_escalate "$repo" "$issue" "$body" "$ctx" >/dev/null 2>&1 || true
      echo "INSPECT: $repo#$issue $label — $reason" >> "$LOG"
      # SKIP verdicts are explicit "David please review" signals (T3 UI,
      # AC-UNCHECKED, low-confidence classifier, etc). Surface as a
      # question so David sees them in Slack rather than only on the issue.
      # HOLDING entries are transient (Inspector is waiting out a Verify
      # soak — re-checking next day); never escalate them.
      if [ "$word" = "SKIP" ]; then
        local _it
        _it=$(gh issue view "$issue" --repo "$repo" --json title -q '.title' 2>/dev/null || echo "")
        questions_register "inspector-skip" "$repo" "$issue" \
          "Inspector skipped on $repo#$issue. Reason: $reason" \
          "Inspector can't auto-verify \"${_it:-#$issue}\" — does the shipped change look right?" \
          "The work is merged but auto-verification didn't apply (reason: $reason). Sitting in Verify until you confirm or kick it back." \
          '["Looks good — move it to Done","Send it back to Scope — work isn'\''t right"]' \
          "" || true
      fi
      ;;
  esac
  return 0
}

# aged_gate_label MERGED_AT BASE_REASON
# 2B aged-promote gate. Echoes "<label>|<reason>":
#   age >= INSPECT_HOLD_DAYS -> "PASS|..."        (soak cleared, promote)
#   0 <= age < hold          -> "HOLDING (Nd/Hd)|..." (still soaking)
#   age unknown (-1)         -> "SKIP|..."         (cannot age; leave for human)
aged_gate_label() {
  local merged_at="$1" base="$2" age hold pdate
  hold="${INSPECT_HOLD_DAYS:-7}"
  age=$(inspect_age_days "$merged_at")
  if [ "$age" -lt 0 ]; then
    printf 'SKIP|%s but verify-age could not be determined; David please review' "$base"
  elif [ "$age" -ge "$hold" ]; then
    printf 'PASS|%s; cleared %dd Verify soak' "$base" "$hold"
  else
    pdate=$(inspect_promote_date "$merged_at" "$hold")
    printf 'HOLDING (%dd/%dd)|%s; promotes on %s' "$age" "$hold" "$base" "$pdate"
  fi
}

# collect_log_evidence REPO ISSUE_NUM PR_NUM
# 2E two-log-stream awareness: greps BOTH foreman log streams for this item.
# results/*.log carry per-phase summary lines; results/inspector.log carries
# per-item JSONL. Inspector reads both so a verdict never misses evidence that
# lives in only one stream.
collect_log_evidence() {
  local repo="$1" num="$2" pr="$3" short
  short="${repo##*/}"
  {
    grep -hE "(#${num}([^0-9]|\$)|${short}[#/]${num}([^0-9]|\$))" \
      "$RESULTS_DIR"/20??-??-??*.log 2>/dev/null | head -30 || true
    if [ -n "$pr" ] && [ "$pr" != "null" ]; then
      grep -hE "\"pr\":${pr}([^0-9]|\$)" "$INSPECTOR_LOG" 2>/dev/null | tail -10 || true
    fi
  } 2>/dev/null | head -40
}

# capture_http URL — fetches URL, echoes "HTTP <code> for <url>" + body head.
capture_http() {
  local url="$1" tmp code
  if [ -z "$url" ] || [ "$url" = "none" ]; then
    echo "(no deploy URL configured for this repo)"
    return
  fi
  tmp=$(mktemp)
  code=$(curl -s -o "$tmp" -w '%{http_code}' --max-time 20 -L "$url" 2>/dev/null || echo "000")
  printf 'HTTP %s for %s\n\n%s\n' "$code" "$url" "$(head -c 4000 "$tmp" 2>/dev/null || true)"
  rm -f "$tmp"
}

# llm_classify REPO ISSUE TITLE BODY
# Haiku AC-tier classifier. Echoes "<tier>|<confidence>|<reason>". On any
# failure echoes "T4|0|..." so the caller SKIPs.
llm_classify() {
  local repo="$1" issue="$2" title="$3" body="$4" prompt_file
  prompt_file=$(mktemp)
  {
    cat "$SCRIPT_DIR/prompts/inspect-classify.md"
    printf '\n\n## Issue\n\n%s#%s: %s\n\n%s\n' "$repo" "$issue" "$title" "$body"
  } > "$prompt_file"
  run_bounded 120 claude -p "$(cat "$prompt_file")" \
    --model "$INSPECT_CLASSIFY_MODEL" \
    --max-budget-usd "$INSPECT_CLASSIFY_BUDGET" \
    --dangerously-skip-permissions
  rm -f "$prompt_file"
  if [ "$PROBE_EXIT" -ne 0 ]; then
    echo "T4|0|classifier call failed (exit=$PROBE_EXIT)"
    return
  fi
  printf '%s' "$PROBE_OUT" | python3 -c '
import json, re, sys
text = sys.stdin.read()
m = re.search(r"\{[^{}]*\"tier\"[^{}]*\}", text, re.DOTALL)
try:
    d = json.loads(m.group(0)) if m else json.loads(text.strip())
    tier = str(d.get("tier", "T4")).strip().upper()
    conf = float(d.get("confidence", 0) or 0)
    reason = str(d.get("reason", "")).strip().replace("|", "/")[:120]
    if tier not in ("T1", "T2", "T3", "T4"):
        tier = "T4"
    print(f"{tier}|{conf}|{reason}")
except Exception:
    print("T4|0|classifier output unparseable")
' 2>/dev/null || echo "T4|0|classifier output unparseable"
}

# llm_judge REPO ISSUE TITLE BODY EVIDENCE
# Sonnet QA judge against captured evidence. Echoes "<verdict>|<reason>".
# On any failure or unclear output echoes "SKIP|...".
llm_judge() {
  local repo="$1" issue="$2" title="$3" body="$4" evidence="$5" prompt_file
  prompt_file=$(mktemp)
  {
    cat "$SCRIPT_DIR/prompts/inspect-judge.md"
    printf '\n\n## Issue\n\n%s#%s: %s\n\n%s\n' "$repo" "$issue" "$title" "$body"
    printf '\n## Captured evidence\n\n%s\n' "$evidence"
  } > "$prompt_file"
  run_bounded 240 claude -p "$(cat "$prompt_file")" \
    --model "$INSPECT_JUDGE_MODEL" \
    --max-budget-usd "$INSPECT_JUDGE_BUDGET" \
    --dangerously-skip-permissions
  rm -f "$prompt_file"
  if [ "$PROBE_EXIT" -ne 0 ]; then
    echo "SKIP|judge call failed (exit=$PROBE_EXIT)"
    return
  fi
  printf '%s' "$PROBE_OUT" | python3 -c '
import json, re, sys
text = sys.stdin.read()
m = re.search(r"\{[^{}]*\"verdict\"[^{}]*\}", text, re.DOTALL)
try:
    d = json.loads(m.group(0)) if m else json.loads(text.strip())
    v = str(d.get("verdict", "SKIP")).strip().upper()
    reason = str(d.get("reason", "")).strip().replace("|", "/")[:140]
    if v not in ("PASS", "FAIL"):
        print(f"SKIP|{reason or 'judge returned no clear verdict'}")
    else:
        print(f"{v}|{reason}")
except Exception:
    print("SKIP|judge output unparseable")
' 2>/dev/null || echo "SKIP|judge output unparseable"
}

PASSED=0
FAILED=0
SKIPPED=0
HELD=0

# count_outcome LABEL — bump the right counter from a verdict label.
count_outcome() {
  case "${1%% *}" in
    PASS)    PASSED=$((PASSED + 1)) ;;
    FAIL)    FAILED=$((FAILED + 1)) ;;
    HOLDING) HELD=$((HELD + 1)) ;;
    *)       SKIPPED=$((SKIPPED + 1)) ;;
  esac
}

VERIFY_ITEMS=$(fetch_board_items | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('status') == 'Verify':
        c = item.get('content', {})
        repo = c.get('repository', '')
        num = c.get('number', '')
        if repo and num:
            print(f'{repo}|{num}')
" 2>/dev/null || true)

if [ -z "$VERIFY_ITEMS" ]; then
  touch "$SENTINEL"
  echo "INSPECT PHASE: passed=0 failed=0 skipped=0 held=0" >> "$LOG"
  echo "passed=0 failed=0 skipped=0 held=0"
  exit 0
fi

while IFS='|' read -r REPO ISSUE_NUM; do
  if [ -z "$REPO" ] || [ -z "$ISSUE_NUM" ]; then continue; fi

  START_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo 0)

  # --- Issue title/body (needed by 2D and the LLM path) ---
  ISSUE_JSON=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json title,body 2>/dev/null || echo '{}')
  ISSUE_TITLE=$(printf '%s' "$ISSUE_JSON" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("title",""))
except: print("")' 2>/dev/null || echo "")
  ISSUE_BODY=$(printf '%s' "$ISSUE_JSON" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("body","") or "")
except: print("")' 2>/dev/null || echo "")

  PROJECT_DIR="$(repo_to_path "$REPO")"

  # --- Resolve the closing PR (GraphQL — closedByPullRequestsReferences is
  #     not exposed by `gh issue view --json`) ---
  REPO_OWNER="${REPO%%/*}"
  REPO_NAME="${REPO##*/}"
  PR_NUM=$(gh api graphql \
    -f query='query($owner: String!, $name: String!, $num: Int!) {
      repository(owner: $owner, name: $name) {
        issue(number: $num) {
          closedByPullRequestsReferences(first: 1, includeClosedPrs: true) {
            nodes { number }
          }
        }
      }
    }' \
    -F owner="$REPO_OWNER" -F name="$REPO_NAME" -F num="$ISSUE_NUM" \
    --jq '.data.repository.issue.closedByPullRequestsReferences.nodes[0].number' \
    2>/dev/null || echo "")
  [ "$PR_NUM" = "null" ] && PR_NUM=""

  PR_FILES=""
  PR_STATE=""
  PR_MERGED_AT=""
  PR_RETURNED=0
  UI_FILES=""
  UI_COUNT=0
  NONUI_COUNT=0
  DET_REASON=""

  if [ -n "$PR_NUM" ]; then
    # gh pr view --json files caps at 100 files (no pagination). Guard by
    # comparing returned count vs changedFiles totalCount; SKIP if truncated.
    PR_INFO=$(gh pr view "$PR_NUM" --repo "$REPO" --json files,changedFiles,mergedAt,state 2>/dev/null || echo "")
    PR_FILES=$(printf '%s' "$PR_INFO" | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    for f in d.get("files", []) or []:
        print(f.get("path", ""))
except: pass
' 2>/dev/null || echo "")
    PR_TOTAL_CHANGED=$(printf '%s' "$PR_INFO" | python3 -c 'import json,sys
try: print(int(json.load(sys.stdin).get("changedFiles", 0)))
except: print(0)' 2>/dev/null || echo 0)
    PR_STATE=$(printf '%s' "$PR_INFO" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("state","") or "")
except: print("")' 2>/dev/null || echo "")
    PR_MERGED_AT=$(printf '%s' "$PR_INFO" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("mergedAt","") or "")
except: print("")' 2>/dev/null || echo "")
    PR_RETURNED=$([ -z "$PR_FILES" ] && echo 0 || printf '%s\n' "$PR_FILES" | wc -l | tr -d ' ')

    if [ "$PR_TOTAL_CHANGED" -gt 0 ] && [ "$PR_RETURNED" -lt "$PR_TOTAL_CHANGED" ]; then
      LABEL="SKIP"
      REASON="PR #$PR_NUM has $PR_TOTAL_CHANGED changed files but gh capped at $PR_RETURNED; classifier unreliable. David please review."
      emit_inspector_jsonl "SKIP" "truncated" "-1" "" "$REASON"
      apply_verdict "$REPO" "$ISSUE_NUM" "$LABEL" "$REASON" "inspector-skip"
      count_outcome "$LABEL"
      continue
    fi

    if [ -n "$PR_FILES" ]; then
      UI_FILES=$(printf '%s\n' "$PR_FILES" | classify_pr_has_ui)
      if [ -n "$UI_FILES" ]; then
        UI_COUNT=$(printf '%s\n' "$UI_FILES" | wc -l | tr -d ' ')
      fi
      TOTAL_COUNT=$(printf '%s\n' "$PR_FILES" | wc -l | tr -d ' ')
      NONUI_COUNT=$((TOTAL_COUNT - UI_COUNT))
    fi
  fi

  # ─── 2C: refactor-allowlist auto-promote (instant, no soak) ───────────
  # Closing PR merged AND every changed file inside the refactor allowlist.
  # Note: the spec doc says "issue CLOSED" — but Foreman's PRs use `Refs #N`
  # (foreman#233), so a Verify-column issue is still OPEN. The merged closing
  # PR is the equivalent signal, matching verify_nonui's "merge IS the verdict".
  if [ -n "$PR_NUM" ] && [ "$PR_STATE" = "MERGED" ] && [ -n "$PR_FILES" ]; then
    if printf '%s\n' "$PR_FILES" | classify_diff_refactor_only; then
      LABEL="PASS (refactor-allowlist)"
      REASON="diff scoped to refactor allowlist (config|lib|prompts|specs|docs|design-system); $PR_RETURNED file(s) in PR #$PR_NUM"
      emit_inspector_jsonl "PASS" "refactor-allowlist" "-1" "" "$REASON"
      if apply_verdict "$REPO" "$ISSUE_NUM" "$LABEL" "$REASON" "inspector-pass"; then
        count_outcome "$LABEL"
      fi
      continue
    fi
  fi

  # ─── 2D: lazy-init telemetry positive-evidence promote (instant) ──────
  # Issue body describes an event-driven producer AND a grep-able anchor for
  # it exists in the merged code. Gated on a merged closing PR (same as 2C —
  # "wired in merged code" is unverifiable without one; PR_STATE falls back to
  # "" on a gh failure, so this also fails closed) and no UI files so a UI
  # ticket can never instant-promote here.
  if [ -n "$PR_NUM" ] && [ "$PR_STATE" = "MERGED" ] && [ -n "$PR_FILES" ] \
     && [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] && [ "$UI_COUNT" -eq 0 ] \
     && lazy_init_shape "$ISSUE_BODY"; then
    ANCHOR_HIT=""
    while IFS= read -r CAND; do
      [ -z "$CAND" ] && continue
      HIT=$(find_anchor_in_repo "$CAND" "$PROJECT_DIR") && {
        ANCHOR_HIT="\`$CAND\` at $HIT"
        break
      }
    done <<< "$(lazy_init_anchors "$ISSUE_BODY")"
    if [ -n "$ANCHOR_HIT" ]; then
      LABEL="PASS (lazy-init)"
      REASON="producer wired — $ANCHOR_HIT; event-driven telemetry, awaiting upstream trigger"
      emit_inspector_jsonl "PASS" "lazy-init" "-1" "" "$REASON"
      if apply_verdict "$REPO" "$ISSUE_NUM" "$LABEL" "$REASON" "inspector-pass"; then
        count_outcome "$LABEL"
      fi
      continue
    fi
  fi

  # ─── Split-verify (v0): file-extension UI/non-UI classifier ───────────
  DET_VERDICT=""
  DET_REASON=""
  if [ -n "$PR_NUM" ] && [ -n "$PR_FILES" ]; then
    UI_FILES_CSV=$(printf '%s' "$UI_FILES" | tr '\n' ',' | sed 's/,$//; s/,/, /g')

    NONUI_TMP=$(mktemp)
    if verify_nonui "$REPO" "$PR_NUM" > "$NONUI_TMP" 2>&1; then
      NONUI_PASS=true
    else
      NONUI_PASS=false
    fi
    NONUI_REASON=$(cat "$NONUI_TMP" 2>/dev/null || echo "")
    rm -f "$NONUI_TMP"

    if [ "$NONUI_COUNT" -eq 0 ]; then
      DET_VERDICT="SKIP"
      DET_REASON="UI-only PR #$PR_NUM. David to review: $UI_FILES_CSV"
    elif [ "$UI_COUNT" -gt 0 ] && [ "$NONUI_PASS" = "true" ]; then
      DET_VERDICT="SKIP"
      DET_REASON="Non-UI verified ($NONUI_REASON). UI requires human review: $UI_FILES_CSV"
    elif [ "$UI_COUNT" -gt 0 ] && [ "$NONUI_PASS" = "false" ]; then
      DET_VERDICT="FAIL"
      DET_REASON="Non-UI verification failed: $NONUI_REASON. (PR also has UI changes: $UI_FILES_CSV)"
    elif [ "$NONUI_PASS" = "true" ]; then
      DET_VERDICT="PASS"
      DET_REASON="$NONUI_REASON"
    else
      DET_VERDICT="FAIL"
      DET_REASON="$NONUI_REASON"
    fi

    if [ "$DET_VERDICT" = "FAIL" ]; then
      emit_inspector_jsonl "FAIL" "split-verify" "-1" "" "$DET_REASON"
      apply_verdict "$REPO" "$ISSUE_NUM" "FAIL" "$DET_REASON" "inspector-fail"
      count_outcome "FAIL"
      continue
    fi

    if [ "$DET_VERDICT" = "PASS" ]; then
      # Behavior PASS — route through the aged-promote gate (2B).
      GATE=$(aged_gate_label "$PR_MERGED_AT" "$DET_REASON")
      LABEL="${GATE%%|*}"
      REASON="${GATE#*|}"
      AGE=$(inspect_age_days "$PR_MERGED_AT")
      emit_inspector_jsonl "${LABEL%% *}" "aged-gate" "$AGE" "" "$REASON"
      if apply_verdict "$REPO" "$ISSUE_NUM" "$LABEL" "$REASON" "inspector-aged"; then
        count_outcome "$LABEL"
      fi
      continue
    fi
    # DET_VERDICT=SKIP — fall through to the LLM path below.
  fi

  # ─── No linked PR: v0 evaluate_ac fallback (source-tree T1 checks) ────
  if [ -z "$PR_NUM" ] || [ -z "$PR_FILES" ]; then
    if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
      REASON="no linked PR + no local checkout for $REPO"
      emit_inspector_jsonl "SKIP" "no-checkout" "-1" "" "$REASON"
      apply_verdict "$REPO" "$ISSUE_NUM" "SKIP" "$REASON" "inspector-skip"
      count_outcome "SKIP"
      continue
    fi
    if [ -z "$ISSUE_BODY" ]; then
      REASON="issue body fetch failed"
      emit_inspector_jsonl "SKIP" "fetch-failed" "-1" "" "$REASON"
      apply_verdict "$REPO" "$ISSUE_NUM" "SKIP" "$REASON" "inspector-skip"
      count_outcome "SKIP"
      continue
    fi
    AC_RESULT=$(evaluate_ac "$ISSUE_BODY" "$PROJECT_DIR" 2>/dev/null || echo "SKIP|evaluate_ac crashed|0|0|0|0|0|0")
    IFS='|' read -r AC_VERDICT AC_REASON _T _T1 _NT _P _F _C <<< "$AC_RESULT"
    if [ "$AC_VERDICT" = "PASS" ]; then
      # Source-tree checks — verified state, no deployed-behavior soak needed.
      emit_inspector_jsonl "PASS" "ac-bullet" "-1" "" "$AC_REASON"
      if apply_verdict "$REPO" "$ISSUE_NUM" "PASS" "$AC_REASON" "inspector-pass"; then
        count_outcome "PASS"
      fi
      continue
    fi
    if [ "$AC_VERDICT" = "FAIL" ]; then
      emit_inspector_jsonl "FAIL" "ac-bullet" "-1" "" "$AC_REASON"
      apply_verdict "$REPO" "$ISSUE_NUM" "FAIL" "$AC_REASON" "inspector-fail"
      count_outcome "FAIL"
      continue
    fi
    DET_REASON="$AC_REASON"
  fi

  # ─── LLM path: classify (Haiku) + judge (Sonnet) ─────────────────────
  # Reached only where the deterministic path SKIPped. Kill switch and budget
  # cap both fall back to a plain SKIP (= v0 behavior for these items).
  SKIP_FALLBACK="${DET_REASON:-no deterministic verdict}"

  if [ "$LLM_ENABLED" -ne 1 ]; then
    REASON="$SKIP_FALLBACK (LLM path disabled)"
    emit_inspector_jsonl "SKIP" "llm-disabled" "-1" "" "$REASON"
    apply_verdict "$REPO" "$ISSUE_NUM" "SKIP" "$REASON" "inspector-skip"
    count_outcome "SKIP"
    continue
  fi

  if [ "$LLM_ITEMS_USED" -ge "$INSPECT_MAX_LLM_ITEMS" ]; then
    REASON="$SKIP_FALLBACK (Inspector LLM budget cap reached — \$$INSPECT_BUDGET; retried next cycle)"
    emit_inspector_jsonl "SKIP" "budget-cap" "-1" "" "$REASON"
    apply_verdict "$REPO" "$ISSUE_NUM" "SKIP" "$REASON" "inspector-skip"
    count_outcome "SKIP"
    continue
  fi
  LLM_ITEMS_USED=$((LLM_ITEMS_USED + 1))

  CLS=$(llm_classify "$REPO" "$ISSUE_NUM" "$ISSUE_TITLE" "$ISSUE_BODY")
  IFS='|' read -r TIER CONF CLS_REASON <<< "$CLS"
  CONF_OK=$(python3 -c "print(1 if float('${CONF:-0}' or 0) >= 0.6 else 0)" 2>/dev/null || echo 0)

  if [ "$CONF_OK" -ne 1 ]; then
    REASON="classifier low confidence ($TIER conf=$CONF: $CLS_REASON); David please review"
    emit_inspector_jsonl "SKIP" "llm-lowconf" "-1" "haiku" "$REASON"
    apply_verdict "$REPO" "$ISSUE_NUM" "SKIP" "$REASON" "inspector-skip"
    count_outcome "SKIP"
    continue
  fi

  case "$TIER" in
    T2)
      DEPLOY_URL="$(repo_to_url "$REPO")"
      EVIDENCE=$(printf '%s\n\n--- captured HTTP ---\n%s\n' \
        "$(collect_log_evidence "$REPO" "$ISSUE_NUM" "$PR_NUM")" \
        "$(capture_http "$DEPLOY_URL")")
      JDG=$(llm_judge "$REPO" "$ISSUE_NUM" "$ISSUE_TITLE" "$ISSUE_BODY" "$EVIDENCE")
      IFS='|' read -r J_VERDICT J_REASON <<< "$JDG"
      if [ "$J_VERDICT" = "PASS" ]; then
        GATE=$(aged_gate_label "$PR_MERGED_AT" "judge: $J_REASON")
        LABEL="${GATE%%|*}"
        REASON="${GATE#*|}"
        AGE=$(inspect_age_days "$PR_MERGED_AT")
        emit_inspector_jsonl "${LABEL%% *}" "llm-judge" "$AGE" "haiku+sonnet" "$REASON"
        if apply_verdict "$REPO" "$ISSUE_NUM" "$LABEL" "$REASON" "inspector-aged"; then
          count_outcome "$LABEL"
        fi
      elif [ "$J_VERDICT" = "FAIL" ]; then
        REASON="judge: $J_REASON"
        emit_inspector_jsonl "FAIL" "llm-judge" "-1" "haiku+sonnet" "$REASON"
        apply_verdict "$REPO" "$ISSUE_NUM" "FAIL" "$REASON" "inspector-fail"
        count_outcome "FAIL"
      else
        REASON="T2 judge inconclusive — $J_REASON; David please review"
        emit_inspector_jsonl "SKIP" "llm-judge" "-1" "haiku+sonnet" "$REASON"
        apply_verdict "$REPO" "$ISSUE_NUM" "SKIP" "$REASON" "inspector-skip"
        count_outcome "SKIP"
      fi
      ;;
    T3)
      REASON="T3 (browser/UI) — Playwright capture deferred (foreman#209 spec §5: launchd wiring is an open eng-deep-dive); David please review. ($CLS_REASON)"
      emit_inspector_jsonl "SKIP" "t3-deferred" "-1" "haiku" "$REASON"
      apply_verdict "$REPO" "$ISSUE_NUM" "SKIP" "$REASON" "inspector-skip"
      count_outcome "SKIP"
      ;;
    T4)
      REASON="T4 (mocked/seeded state) — out of Inspector scope; repo integration tests own this. ($CLS_REASON)"
      emit_inspector_jsonl "SKIP" "t4-oos" "-1" "haiku" "$REASON"
      apply_verdict "$REPO" "$ISSUE_NUM" "SKIP" "$REASON" "inspector-skip"
      count_outcome "SKIP"
      ;;
    *)
      # T1 — the deterministic path already had its chance and SKIPped; the
      # classifier adds nothing here. Leave for a human.
      REASON="$SKIP_FALLBACK (classified T1; deterministic checks were inconclusive)"
      emit_inspector_jsonl "SKIP" "llm-t1" "-1" "haiku" "$REASON"
      apply_verdict "$REPO" "$ISSUE_NUM" "SKIP" "$REASON" "inspector-skip"
      count_outcome "SKIP"
      ;;
  esac
done <<< "$VERIFY_ITEMS"

touch "$SENTINEL"
echo "INSPECT PHASE: passed=$PASSED failed=$FAILED skipped=$SKIPPED held=$HELD" >> "$LOG"
echo "passed=$PASSED failed=$FAILED skipped=$SKIPPED held=$HELD"
