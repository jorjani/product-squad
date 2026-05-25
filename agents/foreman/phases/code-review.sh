#!/bin/bash
# Phase: Code Review — independent second-pair-of-eyes on open PRs, plus the
# foreman#210 auto-merge gate for non-auto/* PRs.
#
# Dispatches the code-reviewer subagent (Projects/.claude/agents/code-reviewer.md)
# on open PRs across eligible repos that don't already have a REVIEWER:
# comment, then posts findings (or LGTM) as a REVIEWER: comment.
#
# For non-auto/* PRs it then runs the merge gate: when the verdict is clean
# (LGTM, no Blocker finding), the author is allowlisted, the repo is opted in,
# CI is green, and an LLM judge rules the diff AC-MATCH against the linked
# issue, the PR is squash-merged and the linked issue moves to Verify. auto/*
# PRs are untouched — phases/review.sh still owns that path. On AC-MISMATCH a
# DECISION-NEEDED: comment is posted on the linked issue and the PR stays open.
# Kill switch: CODE_REVIEW_DISABLE_AUTOMERGE=1 reverts to comment-only.
#
# POSTS: REVIEWER:, DECISION-NEEDED:
# READS: REVIEWER:
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/config/env.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/config/model-routing.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/repos.sh"
# foreman#210 merge gate: board moves, CI classification, deduped comments.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/config/board-ids.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/config/ci-policy.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/ci-status.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/comments.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/questions.sh"

DATE=$(date +%Y-%m-%d)
RESULTS_DIR="$SCRIPT_DIR/results"
LOG="$RESULTS_DIR/$DATE.log"
mkdir -p "$RESULTS_DIR"

# Daily-once guard (same pattern as inspect.sh / cleanup.sh)
SENTINEL="$RESULTS_DIR/.code-review-ran-$DATE"
if [ -f "$SENTINEL" ]; then
  echo "CODE-REVIEW: Already ran today" >> "$LOG"
  echo "CODE-REVIEW PHASE: reviewed=0 lgtm=0 findings=0 merged=0 (already-ran)" >> "$LOG"
  echo "reviewed=0 lgtm=0 findings=0 merged=0"
  exit 0
fi

REVIEWED=0
LGTM=0
WITH_FINDINGS=0
SKIPPED=0
MERGED=0

# ── foreman#210: merge gate config ───────────────────────────────────────────
# Kill switch: CODE_REVIEW_DISABLE_AUTOMERGE=1 reverts to today's comment-only
# behavior — findings still post, no merge regardless of gates.
if [ "${CODE_REVIEW_DISABLE_AUTOMERGE:-}" = "1" ]; then
  AUTOMERGE_ENABLED=0
  echo "[code-review] auto-merge disabled (CODE_REVIEW_DISABLE_AUTOMERGE=1)" >> "$LOG"
else
  AUTOMERGE_ENABLED=1
fi
# Author allowlist (space-separated): only PRs whose author is listed are
# merge-eligible. v1 is David alone; expand by editing the default below or
# exporting CODE_REVIEW_MERGE_ALLOWLIST.
CODE_REVIEW_MERGE_ALLOWLIST="${CODE_REVIEW_MERGE_ALLOWLIST:-jorjani}"

# Extract the linked issue number from a PR body (Closes/Fixes/Resolves/Refs #N).
# Duplicated from phases/review.sh:50 deliberately — helpers are not shared
# across phase boundaries (specs/210 §6). Takes the body as an argument since
# the merge gate has already fetched it.
extract_linked_issue_from_body() {
  printf '%s' "$1" | python3 -c "
import re, sys
m = re.search(r'(?:Closes|Fixes|Resolves|Refs)\s+#(\d+)', sys.stdin.read(), re.IGNORECASE)
print(m.group(1) if m else '')
" 2>/dev/null || true
}

# cleanup_merged_branch REPO BRANCH
# Remove the local worktree + branch for a just-merged PR head branch, if any.
# Non-auto/* PRs rarely carry a Foreman worktree, but this mirrors review.sh's
# post-merge cleanup so a merge never strands a stale local branch.
cleanup_merged_branch() {
  local repo="$1" branch="$2" repo_dir wt_path
  [ -z "$branch" ] && return 0
  repo_dir="$(repo_to_path "$repo")"
  [ -n "$repo_dir" ] && [ -d "$repo_dir" ] || return 0
  wt_path=$(git -C "$repo_dir" worktree list --porcelain 2>/dev/null \
    | awk -v t="$branch" '/^worktree /{p=$2} $1=="branch" && $2=="refs/heads/" t {print p}' || true)
  if [ -n "$wt_path" ] && [ -d "$wt_path" ]; then
    git -C "$repo_dir" worktree remove "$wt_path" --force 2>/dev/null || true
    echo "[code-review] $repo CLEANUP: removed worktree $wt_path ($branch)" >> "$LOG"
  fi
  git -C "$repo_dir" branch -D "$branch" 2>/dev/null || true
}

# classify_ac REPO PR_NUM ISSUE_NUM ISSUE_TITLE ISSUE_BODY
# Dispatches the AC-judge LLM (prompts/code-review-ac-judge.md) against the PR
# diff + linked issue. Echoes "<verdict>|<detail>" where verdict is one of
# AC-MATCH | AC-MISMATCH | AC-UNCHECKED | SKIP and detail is a human summary
# (for AC-MISMATCH, a markdown list of the failing AC bullets). SKIP on any
# parse/dispatch failure so the caller leaves the PR open.
classify_ac() {
  local repo="$1" pr_num="$2" issue_num="$3" issue_title="$4" issue_body="$5"
  local diff prompt_file ac_out

  diff=$(gh pr diff "$pr_num" --repo "$repo" 2>/dev/null | head -c 80000 || true)
  if [ -z "$diff" ]; then
    echo "SKIP|PR diff empty or unavailable"
    return 0
  fi

  prompt_file=$(mktemp)
  {
    cat "$SCRIPT_DIR/prompts/code-review-ac-judge.md"
    printf '\n\n## Issue\n\n%s#%s: %s\n\n%s\n' "$repo" "$issue_num" "$issue_title" "$issue_body"
    printf '\n## PR Diff\n\n%s\n' "$diff"
  } > "$prompt_file"

  ac_out="$RESULTS_DIR/$DATE-code-review-ac-${repo##*/}-$pr_num.out"
  claude -p "$(cat "$prompt_file")" \
    --model "$CODE_REVIEW_AC_MODEL" \
    --max-budget-usd "$CODE_REVIEW_AC_BUDGET" \
    --dangerously-skip-permissions \
    < /dev/null > "$ac_out" 2>&1 || true
  rm -f "$prompt_file"

  AC_OUT="$ac_out" python3 <<'PY' || true
import json, os, re, sys

def emit(verdict, detail):
    print(f'{verdict}|{detail}')
    sys.exit(0)

try:
    text = open(os.environ['AC_OUT']).read()
except Exception:
    emit('SKIP', 'AC-judge output unreadable')

parsed = None
fence = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', text, flags=re.DOTALL)
if fence:
    try: parsed = json.loads(fence.group(1))
    except Exception: parsed = None
if parsed is None:
    try: parsed = json.loads(text.strip())
    except Exception: parsed = None
if parsed is None:
    for s in reversed([m.start() for m in re.finditer(r'\{', text)]):
        depth = 0
        for i in range(s, len(text)):
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
                if depth == 0:
                    chunk = text[s:i+1]
                    if '"ac_match"' in chunk:
                        try: parsed = json.loads(chunk)
                        except Exception: parsed = None
                    break
        if parsed is not None:
            break

if not isinstance(parsed, dict):
    emit('SKIP', 'could not parse AC-judge JSON output')

verdict = str(parsed.get('ac_match', '')).strip().upper()
if verdict not in ('AC-MATCH', 'AC-MISMATCH', 'AC-UNCHECKED'):
    emit('SKIP', 'AC-judge returned no clear verdict')

bullets = parsed.get('bullets')
if not isinstance(bullets, list):
    bullets = []
fails = [b for b in bullets
         if isinstance(b, dict) and str(b.get('status', '')).strip().upper() == 'FAIL']

if verdict == 'AC-MISMATCH':
    lines = []
    for b in fails[:5]:
        ac = str(b.get('ac', '')).strip()[:80]
        note = str(b.get('note', '')).strip()[:140]
        if ac:
            lines.append(f'- **{ac}** -- {note}' if note else f'- **{ac}**')
    emit('AC-MISMATCH', '\n'.join(lines) if lines
         else 'one or more acceptance criteria are not met')
elif verdict == 'AC-MATCH':
    emit('AC-MATCH', f'{len(bullets)} acceptance criteria checked')
else:
    emit('AC-UNCHECKED', 'linked issue states no checkable acceptance criteria')
PY
}

# attempt_automerge REPO PR_NUM KIND COMMENT_BODY
# foreman#210 merge gate — runs after a REVIEWER: comment is posted on an open
# PR. Squash-merges the PR and moves the linked issue to Verify when every gate
# passes; otherwise logs the first failed gate and returns without merging.
# auto/* PRs are always skipped (phases/review.sh owns that path). The paid LLM
# AC classifier runs last, after every cheap gate. Bumps the global MERGED.
attempt_automerge() {
  local repo="$1" pr_num="$2" kind="$3" comment_body="$4"
  local tag="[code-review] $repo#$pr_num"

  # PR metadata: author login, head branch, body (for the linked issue).
  local pr_json author branch body
  pr_json=$(gh pr view "$pr_num" --repo "$repo" --json author,headRefName,body 2>/dev/null || echo '{}')
  author=$(printf '%s' "$pr_json" | python3 -c 'import json,sys
try: print((json.load(sys.stdin).get("author") or {}).get("login","") or "")
except Exception: print("")' 2>/dev/null || echo "")
  branch=$(printf '%s' "$pr_json" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("headRefName","") or "")
except Exception: print("")' 2>/dev/null || echo "")
  body=$(printf '%s' "$pr_json" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("body","") or "")
except Exception: print("")' 2>/dev/null || echo "")

  # auto/* PRs: phases/review.sh owns the auto-merge path. Leave untouched.
  case "$branch" in
    auto/*)
      echo "$tag MERGE-SKIP: auto/* branch (review.sh owns)" >> "$LOG"
      return 0 ;;
  esac

  # Repo opt-in (fail-closed). Bailing here also skips the paid AC classifier.
  local repo_optin
  repo_optin=$(repo_code_review_automerge_enabled "$repo" 2>/dev/null || echo "false")
  if [ "$repo_optin" != "true" ]; then
    echo "$tag MERGE-SKIP: repo not opted in (board.code_review_automerge)" >> "$LOG"
    return 0
  fi

  # Author allowlist.
  if [ -z "$author" ] || ! printf ' %s ' "$CODE_REVIEW_MERGE_ALLOWLIST" | grep -qF " $author "; then
    echo "$tag MERGE-SKIP: author not in allowlist (${author:-unknown})" >> "$LOG"
    return 0
  fi

  # Reviewer verdict gate: only LGTM / LGTM with nits, and no Blocker finding.
  # KIND is "lgtm" for both LGTM and "LGTM with nits"; the Blocker check is a
  # belt-and-suspenders guard against an inconsistent subagent response.
  if [ "$kind" != "lgtm" ]; then
    echo "$tag MERGE-SKIP: verdict not mergeable (kind=$kind)" >> "$LOG"
    return 0
  fi
  if printf '%s\n' "$comment_body" | grep -q '^### Blockers'; then
    echo "$tag MERGE-SKIP: blocker finding present" >> "$LOG"
    return 0
  fi

  # Linked issue.
  local issue_num
  issue_num=$(extract_linked_issue_from_body "$body")
  if [ -z "$issue_num" ]; then
    echo "$tag MERGE-SKIP: AC-UNCHECKED (no Closes/Refs #N in PR body)" >> "$LOG"
    return 0
  fi

  # CI status: block on failing/pending/error; pass and none (no checks) are
  # green. `error` (CI status undeterminable) fails closed — never auto-merge a
  # PR whose CI we could not read.
  local ci
  ci=$(pr_ci_status "$repo" "$pr_num" 2>/dev/null || echo "error")
  if [ "$ci" = "fail" ] || [ "$ci" = "pending" ] || [ "$ci" = "error" ]; then
    echo "$tag MERGE-SKIP: CI $ci" >> "$LOG"
    return 0
  fi

  # Linked-issue title/body for the AC classifier.
  local issue_json issue_title issue_body
  issue_json=$(gh issue view "$issue_num" --repo "$repo" --json title,body 2>/dev/null || echo '{}')
  issue_title=$(printf '%s' "$issue_json" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("title","") or "")
except Exception: print("")' 2>/dev/null || echo "")
  issue_body=$(printf '%s' "$issue_json" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("body","") or "")
except Exception: print("")' 2>/dev/null || echo "")
  if [ -z "$issue_body" ]; then
    echo "$tag MERGE-SKIP: AC-UNCHECKED (issue #$issue_num body unavailable)" >> "$LOG"
    return 0
  fi

  # AC classifier — the one paid LLM call, last after every cheap gate.
  local ac_result ac_verdict ac_detail
  ac_result=$(classify_ac "$repo" "$pr_num" "$issue_num" "$issue_title" "$issue_body")
  ac_verdict="${ac_result%%|*}"
  ac_detail="${ac_result#*|}"

  case "$ac_verdict" in
    AC-MATCH) ;;
    AC-MISMATCH)
      local dn_body
      dn_body="DECISION-NEEDED: code-review-ac-mismatch

PR #$pr_num passed code review but its diff does not satisfy the acceptance criteria of issue #$issue_num:

$ac_detail

The PR is left open. Patch it to cover the missing criteria, or update the issue's acceptance criteria if the scope changed."
      if comment_dedup_or_escalate "$repo" "$issue_num" "$dn_body" "code-review-ac-mismatch" >/dev/null 2>&1; then
        echo "$tag MERGE-SKIP: AC-MISMATCH — DECISION-NEEDED posted on #$issue_num" >> "$LOG"
      else
        echo "$tag MERGE-SKIP: AC-MISMATCH — DECISION-NEEDED post FAILED on #$issue_num" >> "$LOG"
      fi
      # Source-reframe (D4): the AC judge already named which acceptance
      # criteria failed. Surface that as a product question — David picks
      # whether to update the work or the spec.
      local q_title q_short
      q_title="${issue_title:-issue #$issue_num}"
      q_short=$(printf '%s' "$ac_detail" | head -3)
      questions_register "code-review-ac-mismatch" "$repo" "$issue_num" \
        "PR #$pr_num diff does not satisfy AC of #$issue_num: $ac_detail" \
        "PR for \"$q_title\" looks clean but misses what we asked for — patch the PR, or update the spec?" \
        "Code review says the implementation passes review on its own merits, but the acceptance criteria from the issue aren't met:"$'\n\n'"$q_short" \
        '["Patch the PR — I will describe what is missing","Update the AC — the scope changed","Merge it anyway — close enough"]' \
        "$pr_num" || true
      return 0 ;;
    AC-UNCHECKED)
      echo "$tag MERGE-SKIP: AC-UNCHECKED — $ac_detail" >> "$LOG"
      return 0 ;;
    *)
      echo "$tag MERGE-SKIP: AC classifier inconclusive — $ac_detail" >> "$LOG"
      return 0 ;;
  esac

  # All gates passed — squash-merge. Synchronous merge (no --auto): CI is
  # already gated green above, so --auto would only add a failure mode on repos
  # without auto-merge enabled, and a synchronous merge keeps the immediate
  # move_to_verify reliable (mirrors phases/review.sh's post-merge flow).
  if gh pr merge "$pr_num" --repo "$repo" --squash >> "$LOG" 2>&1; then
    echo "$tag AUTO-MERGED (AC-MATCH, author=$author, ci=$ci)" >> "$LOG"
    move_to_verify "$repo" "$issue_num" >> "$LOG" 2>&1 || true
    cleanup_merged_branch "$repo" "$branch"
    MERGED=$((MERGED + 1))
  else
    echo "$tag MERGE-SKIP: gh pr merge failed (left open for review.sh / human)" >> "$LOG"
  fi
  return 0
}

# Eligible repos: same set as phases/review.sh — board-eligible + foreman itself.
REPOS_LIST="$(eligible_repos) getqatalyst/foreman"

for REPO in $REPOS_LIST; do
  [ -z "$REPO" ] && continue
  PROJECT_DIR="$(repo_to_path "$REPO")"
  if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
    echo "[code-review] $REPO SKIP: no local checkout" >> "$LOG"
    continue
  fi

  PR_LIST_JSON=$(gh pr list --repo "$REPO" --state open --json number,isDraft 2>&1)
  PR_LIST_RC=$?
  if [ $PR_LIST_RC -ne 0 ]; then
    echo "[code-review] $REPO SKIP: gh pr list failed (rc=$PR_LIST_RC)" >> "$LOG"
    continue
  fi
  PRS=$(printf '%s' "$PR_LIST_JSON" | python3 -c "
import json, sys
try:
    for p in json.load(sys.stdin):
        if not p.get('isDraft'):
            print(p.get('number',''))
except Exception:
    pass
" 2>/dev/null || true)

  for PR_NUM in $PRS; do
    [ -z "$PR_NUM" ] && continue

    # Structural dedup: skip PRs that already have any REVIEWER: comment.
    # Once-per-PR is stronger than once-per-day-byte-identical; we never want
    # the second-pair-of-eyes phase to post twice on the same PR. Use `contains`
    # (not `startswith`) so banner-prefixed bodies (`[F:host:HHMM:pid] REVIEWER: ...`)
    # are matched — `lib/provenance.sh` auto-prepends FOREMAN_BANNER, and a
    # startswith check would miss our own past comments and repost every fire.
    HAS_REVIEWER=$(gh pr view "$PR_NUM" --repo "$REPO" --json comments \
      --jq '[.comments[] | select(.body | contains("REVIEWER:"))] | length' \
      2>/dev/null || echo 0)
    if [ "${HAS_REVIEWER:-0}" -gt 0 ]; then
      echo "[code-review] $REPO#$PR_NUM SKIP (existing REVIEWER: comment)" >> "$LOG"
      continue
    fi

    echo "[code-review] $REPO#$PR_NUM dispatching code-reviewer subagent" >> "$LOG"

    PROMPT_FILE=$(mktemp)
    sed -e "s|{REPO}|$REPO|g" -e "s|{PR_NUMBER}|$PR_NUM|g" \
      "$SCRIPT_DIR/prompts/code-review.md" > "$PROMPT_FILE"

    cd "$PROJECT_DIR"
    git fetch origin 2>/dev/null || true

    SUBAGENT_OUT="$RESULTS_DIR/$DATE-code-review-${REPO##*/}-$PR_NUM.out"
    claude -p "$(cat "$PROMPT_FILE")" \
      --model "$CODE_REVIEW_MODEL" \
      --max-budget-usd "$CODE_REVIEW_BUDGET" \
      --dangerously-skip-permissions \
      < /dev/null > "$SUBAGENT_OUT" 2>&1 || true

    rm -f "$PROMPT_FILE"
    REVIEWED=$((REVIEWED + 1))

    # Parse subagent output. The agent's [FOREMAN] mode returns a single JSON
    # object {"findings":[...], "verdict":"..."}. Claude may wrap it in
    # surrounding text or a fence — extract the last balanced JSON containing
    # a "verdict" key.
    COMMENT_BODY=$(SUB="$SUBAGENT_OUT" python3 <<'PY'
import json, os, re, sys

try:
    text = open(os.environ['SUB']).read()
except Exception:
    print('REVIEWER: SKIP -- subagent output unreadable')
    sys.exit(0)

# Strip ```json ... ``` fences if present.
fence = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', text, flags=re.DOTALL)
candidate = fence.group(1) if fence else None

parsed = None
if candidate:
    try:
        parsed = json.loads(candidate)
    except Exception:
        parsed = None

if parsed is None:
    # Try whole output.
    try:
        parsed = json.loads(text.strip())
    except Exception:
        # Try the largest brace-balanced span containing "verdict".
        starts = [m.start() for m in re.finditer(r'\{', text)]
        for s in reversed(starts):
            depth = 0
            for i in range(s, len(text)):
                if text[i] == '{':
                    depth += 1
                elif text[i] == '}':
                    depth -= 1
                    if depth == 0:
                        chunk = text[s:i+1]
                        if '"verdict"' in chunk:
                            try:
                                parsed = json.loads(chunk)
                            except Exception:
                                parsed = None
                        break
            if parsed is not None:
                break

if parsed is None:
    print('REVIEWER: SKIP -- could not parse subagent JSON output')
    sys.exit(0)

verdict = (parsed.get('verdict') or 'Unknown').strip()
findings = parsed.get('findings') or []

if verdict.lower() == 'skip' or parsed.get('error'):
    reason = parsed.get('error') or 'subagent reported no reviewable diff'
    print(f'REVIEWER: SKIP -- {reason}')
    sys.exit(0)

if not findings:
    print('REVIEWER: LGTM -- no blocker / major / nit findings.')
    sys.exit(0)

buckets = {'blocker': [], 'major': [], 'nit': []}
for f in findings:
    sev = str(f.get('severity', 'nit')).strip().lower()
    if sev not in buckets:
        sev = 'nit'
    buckets[sev].append(f)

lines = [f'REVIEWER: {verdict}', '']
for label, key in (('Blockers', 'blocker'), ('Majors', 'major'), ('Nits', 'nit')):
    items = buckets[key]
    if not items:
        continue
    lines.append(f'### {label}')
    for it in items[:10]:
        file_ = str(it.get('file') or '?').strip()
        line_ = str(it.get('line') or '?').strip()
        rule  = str(it.get('rule') or '').strip()
        why   = str(it.get('why')  or '').strip()
        fix   = str(it.get('fix')  or '').strip()
        head = f'- **{file_}:{line_}**'
        if rule:
            head += f' -- {rule}'
        lines.append(head)
        if why:
            lines.append(f'  - Why: {why}')
        if fix:
            lines.append(f'  - Fix: {fix}')
    lines.append('')

# Trim trailing blank line.
while lines and lines[-1] == '':
    lines.pop()

print('\n'.join(lines))
PY
)

    # Prepend provenance banner so cross-run instances are distinguishable in logs.
    if [ -n "${FOREMAN_BANNER:-}" ]; then
      COMMENT_BODY="${FOREMAN_BANNER} ${COMMENT_BODY}"
    fi

    if printf '%s' "$COMMENT_BODY" | grep -q '^.*REVIEWER: LGTM'; then
      LGTM=$((LGTM + 1))
      KIND="lgtm"
    elif printf '%s' "$COMMENT_BODY" | grep -q '^.*REVIEWER: SKIP'; then
      SKIPPED=$((SKIPPED + 1))
      KIND="skip"
    else
      WITH_FINDINGS=$((WITH_FINDINGS + 1))
      KIND="findings"
    fi

    gh pr comment "$PR_NUM" --repo "$REPO" --body "$COMMENT_BODY" >/dev/null 2>&1 || \
      echo "[code-review] $REPO#$PR_NUM WARN: gh pr comment failed" >> "$LOG"

    echo "[code-review] $REPO#$PR_NUM posted: $KIND" >> "$LOG"

    # foreman#210: merge gate — squash-merge non-auto/* PRs that clear every
    # gate (verdict, repo opt-in, allowlist, CI, AC-MATCH). No-op for auto/*.
    if [ "$AUTOMERGE_ENABLED" -eq 1 ]; then
      attempt_automerge "$REPO" "$PR_NUM" "$KIND" "$COMMENT_BODY"
    fi
  done
done

touch "$SENTINEL"
echo "CODE-REVIEW PHASE: reviewed=$REVIEWED lgtm=$LGTM findings=$WITH_FINDINGS skipped=$SKIPPED merged=$MERGED" >> "$LOG"
echo "reviewed=$REVIEWED lgtm=$LGTM findings=$WITH_FINDINGS skipped=$SKIPPED merged=$MERGED"
