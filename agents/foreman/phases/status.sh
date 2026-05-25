#!/bin/bash
# Status: show board state, blockers, and what needs attention
# Usage: ./orchestrator.sh status
# READS: NEEDS-SPEC:, SPEC-UPDATED:, Automated triage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/config/board-ids.sh"
source "$SCRIPT_DIR/lib/repos.sh"
ELIGIBLE_REPOS="$(eligible_repos)"
if [ -z "$ELIGIBLE_REPOS" ]; then
  echo "status.sh: eligible_repos returned empty — agents.foreman map missing from ~/Projects/.index.json?" >&2
  exit 1
fi

echo ""
echo "=== PIPELINE STATUS ==="
echo ""

fetch_board_items | python3 -c "
import json, sys
eligible = set('$ELIGIBLE_REPOS'.split())
data = json.load(sys.stdin)
by_status = {}
for item in data.get('items', []):
    s = item.get('status', 'Unknown')
    c = item.get('content', {})
    repo = c.get('repository', '?')
    num = c.get('number', '?')
    title = item.get('title', '?')[:55]
    by_status.setdefault(s, []).append((repo, num, title))

for col in ['Ready', 'Scope', 'Pitch', 'Parking', 'Done']:
    items = by_status.get(col, [])
    eligible_items = [i for i in items if i[0] in eligible]
    other = len(items) - len(eligible_items)
    suffix = f' (+{other} other)' if other else ''
    print(f'{col} ({len(eligible_items)}{suffix})')
    for repo, num, title in eligible_items:
        print(f'  {repo.split(\"/\")[-1]}#{num}: {title}')
    print()
" 2>/dev/null

echo "=== NEEDS ATTENTION ==="
echo ""

echo "NEEDS-SPEC (waiting for enrichment):"
NEEDS_OUTPUT=""
for REPO in $ELIGIBLE_REPOS; do
  REPO_OUT=$(gh issue list --repo "$REPO" --state open --json number,title,comments --limit 50 2>/dev/null | python3 -c "
import json, sys
repo = '$REPO'.split('/')[-1]
for issue in json.load(sys.stdin):
    comments = issue.get('comments', [])
    relevant = [c for c in comments if c.get('body','').startswith(('NEEDS-SPEC:','SPEC-UPDATED:','Automated triage'))]
    if relevant and relevant[-1].get('body','').startswith('NEEDS-SPEC:'):
        print(f'  {repo}#{issue[\"number\"]}: {issue[\"title\"][:50]}')
" 2>/dev/null || true)
  [ -n "$REPO_OUT" ] && NEEDS_OUTPUT="${NEEDS_OUTPUT}${REPO_OUT}\n"
done
if [ -n "$NEEDS_OUTPUT" ]; then
  echo -e "$NEEDS_OUTPUT"
else
  echo "  None"
fi
echo ""

echo "Open PRs:"
for REPO in $ELIGIBLE_REPOS; do
  gh pr list --repo "$REPO" --state open --json number,title,statusCheckRollup --jq '.[] | "\(.number)|\(.title)|\(if (.statusCheckRollup // [] | length) == 0 then "none" elif any(.statusCheckRollup[]; .conclusion == "FAILURE") then "FAIL" elif all(.statusCheckRollup[]; .conclusion == "SUCCESS" or .conclusion == "SKIPPED" or .conclusion == null) then "pass" else "pending" end)"' 2>/dev/null | while IFS='|' read -r num title ci; do
    marker=" "
    [ "$ci" = "FAIL" ] && marker="x"
    [ "$ci" = "pending" ] && marker="~"
    short=$(echo "$REPO" | sed 's|.*/||')
    echo "  [$marker] ${short}#${num}: ${title:0:50} (CI: $ci)"
  done
done
echo ""

LATEST=$(ls -t "$SCRIPT_DIR/metrics/$(date +%Y)-"*.json 2>/dev/null | head -1)
if [ -n "$LATEST" ]; then
  echo "Last metrics ($(basename "$LATEST" .json)):"
  python3 -c "
import json
with open('$LATEST') as f:
    d = json.load(f)
b = d.get('build', {})
r = d.get('review', {})
t = d.get('triage', {})
bsr = d.get('rates', {}).get('build_success', 0)
print(f'  Build: {b.get(\"built\",0)} ok / {b.get(\"failed\",0)} fail | Review: {r.get(\"merged\",0)} merged | Triage: {t.get(\"promoted\",0)} promoted | Rate: {bsr:.0%}')
" 2>/dev/null
fi
echo ""
