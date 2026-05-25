#!/bin/bash
# Phase: Ghost Sweep — demote In Progress items that have no CLAIMED comment.
# Runs once per daily pipeline invocation (post-loop, after cleanup).
#
# Pickup logic in build-ticket.sh moves an item to In Progress before the
# build runs. If the build aborts (oversized check, claim conflict, malformed
# spec) before any builder posts a CLAIMED comment, the item is stranded
# — no rollback to Ready exists. This phase closes that loop autonomously:
# any In Progress item with no CLAIMED comment from any builder and no
# open auto/issue-N-* PR is demoted to Ready after N hours.
#
# Default age threshold: 4 hours. Per-repo override via
# GHOST_SWEEP_HOURS_<SHORT_UPPER> env var (e.g. GHOST_SWEEP_HOURS_SAGE=8).
# Hyphens in repo names are translated to underscores for env-var validity
# (e.g. product-studio -> GHOST_SWEEP_HOURS_PRODUCT_STUDIO).
# Global override via GHOST_SWEEP_HOURS.
#
# POSTS: none (board move only — see _shared/agent-team.md state machine)
# READS: CLAIMED:* comments on In Progress issues
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
DATE=$(date +%Y-%m-%d)
LOG="$RESULTS_DIR/$DATE.log"

mkdir -p "$RESULTS_DIR"

SENTINEL="$RESULTS_DIR/.ghost-sweep-ran-$DATE"
if [ -f "$SENTINEL" ]; then
  echo "GHOST-SWEEP: Already ran today" >> "$LOG"
  echo "demoted=0"
  exit 0
fi

source "$SCRIPT_DIR/config/board-ids.sh"
source "$SCRIPT_DIR/lib/repos.sh"

# Same eligible set Foreman builds for. Project #5 contains items from repos
# outside foreman's scope; skipping non-eligible repos prevents cross-team
# disruption from ghost-sweep moves.
ELIGIBLE_REPOS="$(eligible_repos)"
if [ -z "$ELIGIBLE_REPOS" ]; then
  echo "ghost-sweep.sh: eligible_repos returned empty — agents.foreman map missing from ~/Projects/.index.json?" >&2
  exit 1
fi

DEFAULT_GHOST_HOURS="${GHOST_SWEEP_HOURS:-4}"

# Per-repo minimum age before a CLAIMED-less In Progress item is swept.
# Override for tests/tuning via env var GHOST_SWEEP_HOURS_<SHORT_UPPER>
# (e.g. GHOST_SWEEP_HOURS_FOREMAN=2). Falls back to DEFAULT_GHOST_HOURS.
ghost_hours_for_repo() {
  local short_upper="$1"
  local env_var="GHOST_SWEEP_HOURS_${short_upper}"
  if [ -n "${!env_var:-}" ]; then
    echo "${!env_var}"
    return
  fi
  echo "$DEFAULT_GHOST_HOURS"
}

# Fetch open In Progress items with ProjectV2Item.updatedAt as entry-time
# proxy. updatedAt bumps when Status is set; on parked items it equals the
# move time. Closed issues are ignored — they shouldn't be In Progress
# anyway, and demoting a closed issue would reopen the gap.
fetch_in_progress_items() {
  PROJECT_ORG="$PROJECT_ORG" PROJECT_NUMBER="$PROJECT_NUMBER" python3 - <<'PY' 2>/dev/null
import json, os, subprocess, sys
org = os.environ['PROJECT_ORG']
number = os.environ['PROJECT_NUMBER']
items = []
cursor = None
while True:
    after = f', after: "{cursor}"' if cursor else ''
    query = f'''
    {{
      organization(login: "{org}") {{
        projectV2(number: {number}) {{
          items(first: 100{after}) {{
            pageInfo {{ hasNextPage endCursor }}
            nodes {{
              id
              updatedAt
              fieldValueByName(name: "Status") {{
                ... on ProjectV2ItemFieldSingleSelectValue {{ name }}
              }}
              content {{
                ... on Issue {{
                  number
                  state
                  repository {{ nameWithOwner }}
                }}
              }}
            }}
          }}
        }}
      }}
    }}'''
    r = subprocess.run(['gh', 'api', 'graphql', '-f', f'query={query}'],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(f'fetch_in_progress_items: {r.stderr}', file=sys.stderr)
        sys.exit(1)
    data = json.loads(r.stdout)
    page = data['data']['organization']['projectV2']['items']
    for n in page['nodes']:
        c = n.get('content') or {}
        if not c.get('number'):
            continue
        if c.get('state') != 'OPEN':
            continue
        sv = n.get('fieldValueByName')
        if not sv or sv.get('name') != 'In Progress':
            continue
        items.append({
            'updated_at': n['updatedAt'],
            'repo': c['repository']['nameWithOwner'],
            'number': c['number'],
        })
    if not page['pageInfo']['hasNextPage']:
        break
    cursor = page['pageInfo']['endCursor']
print(json.dumps(items))
PY
}

# Count CLAIMED comments on this issue (any author, any builder subject).
# Returns 2 on gh API failure so the caller can skip rather than treat a
# transient rate-limit / network blip as "no CLAIMED found" (false demote).
has_claimed_comment() {
  local repo="$1" num="$2"
  local result
  result=$(gh issue view "$num" --repo "$repo" --json comments \
    --jq '[.comments[] | select(.body | test("(^|\n)CLAIMED:"))] | length' \
    2>/dev/null) || return 2
  echo "$result"
}

# Any open PR whose head branch matches auto/issue-<num>-* in this repo?
# Treated as builder-in-transit signal (In Progress -> In Review window).
# gh's --search head: is exact-match, so we list and prefix-filter instead.
# Returns 2 on gh API failure so the caller can skip (see has_claimed_comment).
has_open_builder_pr() {
  local repo="$1" num="$2"
  local result
  result=$(gh pr list --repo "$repo" --state open --limit 100 \
    --json headRefName \
    --jq "[.[] | select(.headRefName | startswith(\"auto/issue-${num}-\"))] | length" \
    2>/dev/null) || return 2
  echo "$result"
}

# Hours since ISO-8601 timestamp.
hours_since() {
  python3 -c "
import sys, datetime
ts = sys.argv[1]
dt = datetime.datetime.fromisoformat(ts.replace('Z','+00:00'))
now = datetime.datetime.now(datetime.timezone.utc)
print(int((now - dt).total_seconds() // 3600))
" "$1" 2>/dev/null || echo 0
}

ITEMS_JSON=$(fetch_in_progress_items)
if [ -z "$ITEMS_JSON" ]; then
  echo "GHOST-SWEEP: fetch returned empty (skipping)" >> "$LOG"
  touch "$SENTINEL"
  echo "demoted=0"
  exit 0
fi

# Stream items via process substitution so DEMOTED stays in this shell
# (bash subshells from `... | while` would lose the counter).
DEMOTED=0
SCANNED=0
while IFS=$'\t' read -r REPO NUM UPDATED_AT; do
  [ -z "$REPO" ] || [ -z "$NUM" ] && continue
  if ! echo " $ELIGIBLE_REPOS " | grep -q " $REPO "; then
    continue
  fi
  SCANNED=$((SCANNED + 1))

  SHORT_UPPER=$(echo "${REPO#*/}" | tr '[:lower:]-' '[:upper:]_')
  HOURS_MIN=$(ghost_hours_for_repo "$SHORT_UPPER")
  AGE=$(hours_since "$UPDATED_AT")

  if [ "${AGE:-0}" -lt "${HOURS_MIN:-4}" ]; then
    continue
  fi

  if ! CLAIMED_COUNT=$(has_claimed_comment "$REPO" "$NUM"); then
    echo "GHOST-SWEEP: ${REPO}#${NUM} gh API error reading comments — skipping" >> "$LOG"
    continue
  fi
  if [ "${CLAIMED_COUNT:-0}" -gt 0 ]; then
    continue
  fi

  if ! PR_COUNT=$(has_open_builder_pr "$REPO" "$NUM"); then
    echo "GHOST-SWEEP: ${REPO}#${NUM} gh API error listing PRs — skipping" >> "$LOG"
    continue
  fi
  if [ "${PR_COUNT:-0}" -gt 0 ]; then
    echo "GHOST-SWEEP: ${REPO}#${NUM} no CLAIMED but open auto/ PR — skipping" >> "$LOG"
    continue
  fi

  if move_to_ready "$REPO" "$NUM" >> "$LOG" 2>&1; then
    echo "GHOST-DEMOTE: ${REPO}#${NUM} (no CLAIMED for ${AGE} hours)" >> "$LOG"
    DEMOTED=$((DEMOTED + 1))
  else
    echo "GHOST-SWEEP: ${REPO}#${NUM} demote failed (board move error)" >> "$LOG"
  fi
done < <(echo "$ITEMS_JSON" | python3 -c "
import json, sys
for it in json.load(sys.stdin):
    print(f\"{it['repo']}\t{it['number']}\t{it['updated_at']}\")
" 2>/dev/null)

touch "$SENTINEL"
echo "GHOST-SWEEP PHASE: scanned=$SCANNED demoted=$DEMOTED" >> "$LOG"
echo "demoted=$DEMOTED"
