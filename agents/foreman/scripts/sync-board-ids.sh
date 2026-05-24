#!/bin/bash
# Sync foreman/config/board-ids.sh with live GitHub Project V2 board state.
# Manual trigger. Writes changes in place; caller reviews and commits explicitly.
#
# Usage: ./scripts/sync-board-ids.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOARD_IDS_FILE="$SCRIPT_DIR/config/board-ids.sh"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

[ -f "$BOARD_IDS_FILE" ] || { echo "Missing $BOARD_IDS_FILE" >&2; exit 1; }

LIVE_JSON=$(gh project field-list 5 --owner getqatalyst --format json 2>/dev/null)
[ -n "$LIVE_JSON" ] || { echo "Could not fetch live field list from GitHub" >&2; exit 1; }

UPDATES=$(python3 - "$LIVE_JSON" "$BOARD_IDS_FILE" "$DRY_RUN" <<'PY'
import json, re, sys
from pathlib import Path

live = json.loads(sys.argv[1])
path = Path(sys.argv[2])
dry_run = sys.argv[3] == "1"
content = path.read_text()

pairs = {
    ('Status', 'Parking'):     'PARKING_OPTION_ID',
    ('Status', 'Pitch'):       'PITCH_OPTION_ID',
    ('Status', 'Scope'):       'SCOPE_OPTION_ID',
    ('Status', 'Backlog'):     'BACKLOG_OPTION_ID',
    ('Status', 'Ready'):       'READY_OPTION_ID',
    ('Status', 'In Progress'): 'IN_PROGRESS_OPTION_ID',
    ('Status', 'In Review'):   'IN_REVIEW_OPTION_ID',
    ('Status', 'Done'):        'DONE_OPTION_ID',
    ('Status', 'Verify'):      'VERIFY_OPTION_ID',
    ('Status', 'Blocked'):     'BLOCKED_OPTION_ID',
    ('Priority', 'P0'):        'P0_OPTION_ID',
    ('Priority', 'P1'):        'P1_OPTION_ID',
    ('Priority', 'P2'):        'P2_OPTION_ID',
    ('Size', 'XS'):            'SIZE_XS_OPTION_ID',
    ('Size', 'S'):             'SIZE_S_OPTION_ID',
    ('Size', 'M'):             'SIZE_M_OPTION_ID',
    ('Size', 'L'):             'SIZE_L_OPTION_ID',
    ('Size', 'XL'):            'SIZE_XL_OPTION_ID',
}

changes = []
for field in live.get('fields', []):
    fname = field.get('name')
    for opt in field.get('options', []):
        key = (fname, opt.get('name'))
        if key not in pairs:
            continue
        var = pairs[key]
        live_id = opt['id']
        m = re.search(rf'^{var}="([^"]*)"', content, re.MULTILINE)
        if not m:
            continue
        old = m.group(1)
        if old == live_id:
            continue
        content = re.sub(rf'^{var}="[^"]*"', f'{var}="{live_id}"', content, count=1, flags=re.MULTILINE)
        changes.append(f'{var}: {old} -> {live_id}')

if changes and not dry_run:
    path.write_text(content)

if not changes:
    print('__NONE__')
else:
    for line in changes:
        print(line)
PY
)

if [ "$UPDATES" = "__NONE__" ]; then
  echo "board-ids.sh already matches live board."
  exit 0
fi

COUNT=$(echo "$UPDATES" | wc -l | tr -d ' ')
if [ "$DRY_RUN" = "1" ]; then
  echo "Dry run: $COUNT change(s) would be applied:"
else
  echo "Updated board-ids.sh with $COUNT change(s):"
fi
echo "$UPDATES" | sed 's/^/  /'
[ "$DRY_RUN" = "0" ] && echo "" && echo "Review: git diff config/board-ids.sh"
