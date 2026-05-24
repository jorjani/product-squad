#!/bin/bash
# Repair: check out auto/ branch, fix review findings, push.
# Called by review.sh: repair.sh <pr_number> <repo>
# POSTS: Automated repair:, CLAIM-AUDIT:, DECISION-NEEDED: (claim-audit gap)
# Audit (foreman#241): after Claude repairs, a fresh-context Claude call
# compares the new HEAD commit's message claims against its diff. Gaps
# trigger one retry; persistent gaps suppress the success marker so
# review.sh:286-289 skips re-review and the PR waits for David.
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

PR_NUM="$1"
REPO="$2"

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config/model-routing.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/comments.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/repos.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/questions.sh"
DATE=$(date +%Y-%m-%d)
LOG_FILE="$SCRIPT_DIR/results/$DATE-repair-$PR_NUM.log"
MARKER_BODY="Automated repair: pushed fixes based on review findings. Re-reviewing now."

PROJECT_DIR="$(repo_to_path "$REPO")"
if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  echo "REPAIR FAIL: Unknown project dir for $REPO"
  exit 1
fi

# Get branch name from PR
BRANCH=$(gh pr view "$PR_NUM" --repo "$REPO" --json headRefName -q '.headRefName' 2>/dev/null) || {
  echo "REPAIR FAIL: Could not fetch PR #$PR_NUM branch"
  exit 1
}

# Safety: only repair auto/ branches
if [[ "$BRANCH" != auto/* ]]; then
  echo "REPAIR SKIP: Not an auto/ branch: $BRANCH"
  exit 1
fi

# Checkout the branch
cd "$PROJECT_DIR"
ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
git fetch origin 2>/dev/null
git checkout "$BRANCH" 2>/dev/null
git pull origin "$BRANCH" 2>/dev/null || true

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"; cd "$PROJECT_DIR" && git checkout "$ORIGINAL_BRANCH" 2>/dev/null || true' EXIT

# Render repair prompt
sed \
  -e "s|{REPO}|$REPO|g" \
  -e "s|{PR_NUMBER}|$PR_NUM|g" \
  -e "s|{BRANCH}|$BRANCH|g" \
  -e "s|{PROJECT_DIR}|$PROJECT_DIR|g" \
  "$SCRIPT_DIR/prompts/repair.md" > "$TMPFILE"

# Run Claude repair ($10 budget, same as review).
# Capture HEAD before/after so the audit only fires when a new commit was made.
HEAD_BEFORE=$(git rev-parse HEAD)

echo "REPAIR: Fixing PR #$PR_NUM on $BRANCH"
claude -p "$(cat "$TMPFILE")" \
  --model "$REPAIR_MODEL" \
  --effort high \
  --max-budget-usd "$REPAIR_BUDGET" \
  --dangerously-skip-permissions \
  < /dev/null > "$LOG_FILE" 2>&1 || {
  echo "REPAIR FAIL: Claude exited with error"
  gh pr comment "$PR_NUM" --repo "$REPO" --body "Automated repair: attempted but failed. Falling back to manual review." 2>/dev/null || true
  exit 1
}

HEAD_AFTER=$(git rev-parse HEAD)

post_marker() {
  gh pr comment "$PR_NUM" --repo "$REPO" --body "$MARKER_BODY" 2>/dev/null || true
}

# No new commit => nothing to audit; preserve prior behavior.
if [ "$HEAD_BEFORE" = "$HEAD_AFTER" ]; then
  post_marker
  echo "REPAIR OK: PR #$PR_NUM (no commit; audit skipped)"
  exit 0
fi

# Claim-to-diff audit (foreman#241). Runs in a fresh Claude session so the
# verifier has no prior context — breaks the same-agent confirmation bias.
run_claim_audit() {
  local msg_file diff_file prompt_file raw
  local rc=0
  msg_file=$(mktemp)
  diff_file=$(mktemp)
  prompt_file=$(mktemp)
  git log -1 --format=%B HEAD > "$msg_file"
  git show HEAD > "$diff_file"
  TEMPLATE="$SCRIPT_DIR/prompts/claim-audit.md" MSG_FILE="$msg_file" DIFF_FILE="$diff_file" \
    python3 -c "
import os, sys
tmpl = open(os.environ['TEMPLATE']).read()
msg = open(os.environ['MSG_FILE']).read()
diff = open(os.environ['DIFF_FILE']).read()
sys.stdout.write(tmpl.replace('{COMMIT_MESSAGE}', msg).replace('{COMMIT_DIFF}', diff))
" > "$prompt_file"

  # `|| rc=$?` exempts the assignment from set -e and lets us inspect failures.
  raw=$(claude -p "$(cat "$prompt_file")" \
    --model "$CLAIM_AUDIT_MODEL" \
    --max-budget-usd "$CLAIM_AUDIT_BUDGET" \
    --dangerously-skip-permissions \
    < /dev/null 2>>"$LOG_FILE") || rc=$?
  rm -f "$msg_file" "$diff_file" "$prompt_file"
  if [ "$rc" -ne 0 ]; then
    echo "ERROR"
    return 0
  fi

  printf '%s' "$raw" | python3 -c "
import json, sys, re
t = sys.stdin.read().strip()
m = re.search(r'\`\`\`(?:json)?\s*\n(.*?)\n\`\`\`', t, re.DOTALL)
if m:
    t = m.group(1).strip()
if not t.startswith('{'):
    m = re.search(r'(\{.*\})', t, re.DOTALL)
    if m:
        t = m.group(1)
try:
    parsed = json.loads(t)
    if not isinstance(parsed, dict) or 'gaps' not in parsed:
        raise ValueError('missing gaps')
    print(json.dumps(parsed))
except Exception:
    print('PARSE_ERROR')
" 2>/dev/null || echo "PARSE_ERROR"
}

extract_gap_claims() {
  printf '%s' "$1" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for g in d.get('gaps', []):
        if isinstance(g, dict):
            c = g.get('claim', '').strip()
            if c:
                print(c)
        elif isinstance(g, str) and g.strip():
            print(g.strip())
except Exception:
    pass
" 2>/dev/null
}

echo "REPAIR: Running claim-to-diff audit on HEAD ($HEAD_AFTER)"
AUDIT_RESULT=$(run_claim_audit)

if [ "$AUDIT_RESULT" = "ERROR" ] || [ "$AUDIT_RESULT" = "PARSE_ERROR" ]; then
  REASON="claude invocation failed"
  [ "$AUDIT_RESULT" = "PARSE_ERROR" ] && REASON="could not parse audit JSON"
  comment_dedup_or_escalate "$REPO" "$PR_NUM" \
    "CLAIM-AUDIT: skipped ($REASON). Re-review proceeding without claim verification." \
    "claim-audit-skipped" || true
  post_marker
  echo "REPAIR OK: PR #$PR_NUM (audit skipped: $REASON)"
  exit 0
fi

GAPS=$(extract_gap_claims "$AUDIT_RESULT")

if [ -z "$GAPS" ]; then
  post_marker
  echo "REPAIR OK: PR #$PR_NUM (audit clean)"
  exit 0
fi

# Gaps found — retry repair once with the gaps named.
echo "REPAIR: Audit found gap(s), retrying once"
{
  echo "AUDIT GAPS (pre-retry):"
  echo "$GAPS"
} >> "$LOG_FILE"

GAP_BULLETS=$(printf '%s\n' "$GAPS" | sed 's/^/- /')
RETRY_PROMPT="You are an autonomous code fixer. The previous repair commit on PR #$PR_NUM (branch $BRANCH) made claims in its commit message that a fresh-context audit could not find evidence for in the diff.

**Unsupported claim(s):**
$GAP_BULLETS

**Working directory:** $PROJECT_DIR
**Repository:** $REPO

## Process
1. Read the previous commit message and diff: \`git log -1 --format=%B HEAD\` and \`git show HEAD\`
2. For each unsupported claim above, identify the code change it implies
3. Read the relevant file(s) and implement the missing change
4. Stage specific files with \`git add\` (never \`-A\` or \`.\`)
5. Commit with conventional format: \`fix: implement claimed fix(es) from PR #$PR_NUM\`
6. Push: \`git push origin $BRANCH\`

## Rules
- Implement ONLY the missing claim(s) above. Do not refactor or fix unrelated issues.
- Do not amend the previous commit. Add a new commit.
- If a claim is too vague to act on, or does not correspond to any real code change, skip it.
- If no claims are actionable, commit nothing and exit."

claude -p "$RETRY_PROMPT" \
  --model "$REPAIR_MODEL" \
  --effort high \
  --max-budget-usd "$REPAIR_BUDGET" \
  --dangerously-skip-permissions \
  < /dev/null >> "$LOG_FILE" 2>&1 || {
  comment_dedup_or_escalate "$REPO" "$PR_NUM" \
    "DECISION-NEEDED: repair audit found unfixed claim(s):
$GAP_BULLETS

Retry repair attempt failed. @jorjani please review." \
    "claim-audit-retry-failed" || true
  # LLM-translate fallback: the gap bullets are too low-level to
  # safely product-frame at source. Let the translate prompt distill them.
  questions_register "claim-audit-retry-failed" "$REPO" "$PR_NUM" \
    "PR #$PR_NUM repair-retry crashed mid-way. Unfixed audit claims:"$'\n'"$GAP_BULLETS" \
    "" "" "[]" "$PR_NUM" || true
  echo "REPAIR FAIL: audit retry Claude exited with error"
  exit 1
}

HEAD_AFTER_RETRY=$(git rev-parse HEAD)
if [ "$HEAD_AFTER_RETRY" = "$HEAD_AFTER" ]; then
  comment_dedup_or_escalate "$REPO" "$PR_NUM" \
    "DECISION-NEEDED: repair audit found unfixed claim(s):
$GAP_BULLETS

Retry repair made no new commit. @jorjani please review." \
    "claim-audit-no-fix" || true
  questions_register "claim-audit-no-fix" "$REPO" "$PR_NUM" \
    "PR #$PR_NUM repair-retry produced no new commit. Unfixed claims:"$'\n'"$GAP_BULLETS" \
    "" "" "[]" "$PR_NUM" || true
  echo "REPAIR FAIL: audit gap unresolved (no retry commit)"
  exit 1
fi

echo "REPAIR: Re-running audit after retry ($HEAD_AFTER_RETRY)"
AUDIT_RESULT_2=$(run_claim_audit)

if [ "$AUDIT_RESULT_2" = "ERROR" ] || [ "$AUDIT_RESULT_2" = "PARSE_ERROR" ]; then
  REASON="claude invocation failed"
  [ "$AUDIT_RESULT_2" = "PARSE_ERROR" ] && REASON="could not parse audit JSON"
  comment_dedup_or_escalate "$REPO" "$PR_NUM" \
    "CLAIM-AUDIT: skipped ($REASON) on retry. Re-review proceeding without claim verification." \
    "claim-audit-skipped-retry" || true
  post_marker
  echo "REPAIR OK: PR #$PR_NUM (audit skipped on retry: $REASON)"
  exit 0
fi

GAPS_2=$(extract_gap_claims "$AUDIT_RESULT_2")
if [ -z "$GAPS_2" ]; then
  post_marker
  echo "REPAIR OK: PR #$PR_NUM (audit clean after retry)"
  exit 0
fi

GAP_BULLETS_2=$(printf '%s\n' "$GAPS_2" | sed 's/^/- /')
comment_dedup_or_escalate "$REPO" "$PR_NUM" \
  "DECISION-NEEDED: repair audit found unfixed claim(s) after 1 retry:
$GAP_BULLETS_2

@jorjani please review." \
  "claim-audit-still-gapped" || true
questions_register "claim-audit-still-gapped" "$REPO" "$PR_NUM" \
  "PR #$PR_NUM still has audit gaps after retry. Unfixed claims:"$'\n'"$GAP_BULLETS_2" \
  "" "" "[]" "$PR_NUM" || true
echo "REPAIR FAIL: audit gap still present after retry"
exit 1
