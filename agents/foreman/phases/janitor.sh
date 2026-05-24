#!/bin/bash
# Phase: Janitor — board hygiene sweep (two passes).
# Runs once per daily pipeline invocation (post-loop).
#
# Pass 1 (stranded-CLOSED -> Parking): when a GitHub issue closes but its board
# card never advanced to Done or Verify (e.g., closed manually as not_planned
# from Pitch/Backlog/Scope/Ready), the card strands in its source column. This
# pass finds CLOSED-issue cards in any column except {Done, Verify, Parking}
# and moves them to Parking.
#
# Pass 2 (open-in-Done -> close issue): after foreman#233 (Refs not Closes), a
# PR merge no longer auto-closes its linked issue — closed-state must track
# Done, not merge. Inspector closes the issue when it promotes Verify->Done;
# this pass is the safety net for cards dragged to Done manually, closing the
# still-open issue. No board move (the card is already in Done).
#
# Never moves to Done — Done is reserved for move_to_done in phases/inspect.sh
# after Foreman build + verify (separation of duties; see foreman#106).
# Never touches Verify (David's review queue) or Parking (already correct).
#
# POSTS: none
# READS: none
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
DATE=$(date +%Y-%m-%d)
LOG="$RESULTS_DIR/$DATE.log"

mkdir -p "$RESULTS_DIR"

SENTINEL="$RESULTS_DIR/.janitor-ran-$DATE"
if [ -f "$SENTINEL" ]; then
  echo "JANITOR: Already ran today" >> "$LOG"
  echo "swept=0 closed=0"
  exit 0
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/config/board-ids.sh"

# Fetch all Issue cards on board #5 with their issue state + board Status.
# Janitor filters in shell for two passes (stranded-CLOSED, open-in-Done) so the
# board is fetched once. PRs are skipped — the Issue fragment filters them out
# (a PR's content has no repository under the Issue inline-fragment match, so it
# yields no number).
fetch_board_state() {
  PROJECT_ORG="$PROJECT_ORG" PROJECT_NUMBER="$PROJECT_NUMBER" python3 - <<'PY' 2>>"$LOG"
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
        print(f'fetch_stranded_items: {r.stderr}', file=sys.stderr)
        sys.exit(1)
    data = json.loads(r.stdout)
    page = data['data']['organization']['projectV2']['items']
    for n in page['nodes']:
        c = n.get('content') or {}
        if not c.get('number'):
            continue
        sv = n.get('fieldValueByName')
        status = sv.get('name') if sv else None
        items.append({
            'repo': c['repository']['nameWithOwner'],
            'number': c['number'],
            'state': c.get('state'),
            'status': status,
        })
    if not page['pageInfo']['hasNextPage']:
        break
    cursor = page['pageInfo']['endCursor']
print(json.dumps(items))
PY
}

ITEMS_JSON=$(fetch_board_state)
if [ -z "$ITEMS_JSON" ]; then
  echo "JANITOR: fetch returned empty (skipping)" >> "$LOG"
  touch "$SENTINEL"
  echo "[janitor] swept 0 cards (board clean)" >> "$LOG"
  echo "swept=0 closed=0"
  exit 0
fi

# Pass 1: stranded CLOSED-issue cards (column not in {Done, Verify, Parking}) -> Parking.
SWEPT=0
SWEPT_NAMES=()
while IFS=$'\t' read -r REPO NUM STATUS; do
  [ -z "$REPO" ] || [ -z "$NUM" ] && continue
  if move_to_parking "$REPO" "$NUM" >> "$LOG" 2>&1; then
    SHORT="${REPO#*/}"
    SWEPT_NAMES+=("${SHORT}#${NUM} (${STATUS}→Parking)")
    SWEPT=$((SWEPT + 1))
  else
    echo "JANITOR: ${REPO}#${NUM} move failed (board move error)" >> "$LOG"
  fi
done < <(echo "$ITEMS_JSON" | python3 -c "
import json, sys
EXCLUDE = {'Done', 'Verify', 'Parking'}
for it in json.load(sys.stdin):
    if it.get('state') != 'CLOSED':
        continue
    st = it.get('status')
    if not st or st in EXCLUDE:
        continue
    print(f\"{it['repo']}\t{it['number']}\t{st}\")
" 2>>"$LOG")

# Pass 2: OPEN issues whose card already reached Done -> close the issue.
CLOSED_DONE=0
CLOSED_NAMES=()
while IFS=$'\t' read -r REPO NUM; do
  [ -z "$REPO" ] || [ -z "$NUM" ] && continue
  if gh issue close "$NUM" --repo "$REPO" --reason completed >> "$LOG" 2>&1; then
    SHORT="${REPO#*/}"
    CLOSED_NAMES+=("${SHORT}#${NUM}")
    CLOSED_DONE=$((CLOSED_DONE + 1))
  else
    echo "JANITOR: ${REPO}#${NUM} issue close failed" >> "$LOG"
  fi
done < <(echo "$ITEMS_JSON" | python3 -c "
import json, sys
for it in json.load(sys.stdin):
    if it.get('state') != 'OPEN':
        continue
    if it.get('status') != 'Done':
        continue
    print(f\"{it['repo']}\t{it['number']}\")
" 2>>"$LOG")

touch "$SENTINEL"
if [ "$SWEPT" -eq 0 ]; then
  echo "[janitor] swept 0 cards (board clean)" >> "$LOG"
else
  LIST=""
  for name in "${SWEPT_NAMES[@]}"; do
    if [ -z "$LIST" ]; then LIST="$name"; else LIST="$LIST, $name"; fi
  done
  echo "[janitor] swept $SWEPT: $LIST" >> "$LOG"
fi
if [ "$CLOSED_DONE" -gt 0 ]; then
  CLOSED_LIST=""
  for name in "${CLOSED_NAMES[@]}"; do
    if [ -z "$CLOSED_LIST" ]; then CLOSED_LIST="$name"; else CLOSED_LIST="$CLOSED_LIST, $name"; fi
  done
  echo "[janitor] closed $CLOSED_DONE open-in-Done: $CLOSED_LIST" >> "$LOG"
fi
echo "swept=$SWEPT closed=$CLOSED_DONE"
