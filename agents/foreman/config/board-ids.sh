#!/bin/bash
# GitHub Project Board constants — PLACEHOLDERS.
# Run scripts/sync-board-ids.sh against your own org/project to populate real IDs.
# Source this file: source "$SCRIPT_DIR/config/board-ids.sh"
PROJECT_ID="PVT_YOUR_PROJECT_NODE_ID"
PROJECT_NUMBER=1
PROJECT_ORG="your-github-org"
STATUS_FIELD_ID="PVTSSF_YOUR_FIELD_ID"
PARKING_OPTION_ID="00000000"
PITCH_OPTION_ID="00000000"
SCOPE_OPTION_ID="00000000"
BACKLOG_OPTION_ID="00000000"
READY_OPTION_ID="00000000"
IN_PROGRESS_OPTION_ID="00000000"
IN_REVIEW_OPTION_ID="00000000"
DONE_OPTION_ID="00000000"
VERIFY_OPTION_ID="00000000"
BLOCKED_OPTION_ID="00000000"

# Priority field (single select)
PRIORITY_FIELD_ID="PVTSSF_YOUR_FIELD_ID"
P0_OPTION_ID="79628723"
P1_OPTION_ID="0a877460"
P2_OPTION_ID="da944a9c"

# Size field (single select)
SIZE_FIELD_ID="PVTSSF_YOUR_FIELD_ID"
SIZE_XS_OPTION_ID="00000000"
SIZE_S_OPTION_ID="00000000"
SIZE_M_OPTION_ID="00000000"
SIZE_L_OPTION_ID="00000000"
SIZE_XL_OPTION_ID="00000000"

# Fetch all board items with status via GraphQL API.
# gh project item-list does NOT return the Status field — this function does.
# Output: JSON matching the format scripts expect:
#   {"items": [{"id": "...", "title": "...", "status": "Ready", "content": {"repository": "owner/repo", "number": 123, "createdAt": "...", "updatedAt": "..."}}]}
fetch_board_items() {
  python3 -c "
import json, subprocess, sys

items = []
cursor = None
while True:
    after = f', after: \"{cursor}\"' if cursor else ''
    query = '''
    {
      organization(login: \"$PROJECT_ORG\") {
        projectV2(number: $PROJECT_NUMBER) {
          items(first: 100''' + after + ''') {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              fieldValueByName(name: \"Status\") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
              content {
                ... on Issue {
                  number
                  title
                  repository { nameWithOwner }
                  createdAt
                  updatedAt
                }
                ... on PullRequest {
                  number
                  title
                  repository { nameWithOwner }
                  createdAt
                  updatedAt
                }
              }
            }
          }
        }
      }
    }'''
    result = subprocess.run(
        ['gh', 'api', 'graphql', '-f', f'query={query}'],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        if not items:
            print(f'fetch_board_items: GraphQL query failed: {result.stderr}', file=sys.stderr)
            sys.exit(1)
        break  # return partial results from previous pages

    data = json.loads(result.stdout)
    items_data = data['data']['organization']['projectV2']['items']

    for node in items_data['nodes']:
        content = node.get('content')
        if not content or not content.get('number'):
            continue
        status_val = node.get('fieldValueByName')
        items.append({
            'id': node['id'],
            'title': content.get('title', ''),
            'status': status_val['name'] if status_val else '',
            'content': {
                'repository': content.get('repository', {}).get('nameWithOwner', ''),
                'number': content['number'],
                'createdAt': content.get('createdAt', ''),
                'updatedAt': content.get('updatedAt', ''),
            }
        })

    if not items_data['pageInfo']['hasNextPage']:
        break
    cursor = items_data['pageInfo']['endCursor']

print(json.dumps({'items': items}))
" 2>/dev/null || echo '{"items":[]}'
}

# Validate board IDs against the live project board
# Call during orchestrator preflight to catch drift early.
# Covers Status, Priority, and Size single-select fields.
validate_board_ids() {
  local live_ids
  live_ids=$(gh project field-list "$PROJECT_NUMBER" --owner "$PROJECT_ORG" --format json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for field in data.get('fields', []):
    fname = field.get('name')
    if fname in ('Status', 'Priority', 'Size'):
        for opt in field.get('options', []):
            print(f'{fname}|{opt[\"name\"]}={opt[\"id\"]}')
" 2>/dev/null) || { echo "BOARD-CHECK: Could not fetch live board IDs (skipping)"; return 0; }

  local mismatches=0
  while IFS='=' read -r key live_id; do
    # Key is "FieldName|OptionName". Map to the matching *_OPTION_ID constant.
    case "$key" in
      "Status|Parking")     config_val="$PARKING_OPTION_ID" ;;
      "Status|Pitch")       config_val="$PITCH_OPTION_ID" ;;
      "Status|Scope")       config_val="$SCOPE_OPTION_ID" ;;
      "Status|Backlog")     config_val="$BACKLOG_OPTION_ID" ;;
      "Status|Ready")       config_val="$READY_OPTION_ID" ;;
      "Status|In Progress") config_val="$IN_PROGRESS_OPTION_ID" ;;
      "Status|In Review")   config_val="$IN_REVIEW_OPTION_ID" ;;
      "Status|Done")        config_val="$DONE_OPTION_ID" ;;
      "Status|Verify")      config_val="$VERIFY_OPTION_ID" ;;
      "Status|Blocked")     config_val="$BLOCKED_OPTION_ID" ;;
      "Priority|P0")        config_val="$P0_OPTION_ID" ;;
      "Priority|P1")        config_val="$P1_OPTION_ID" ;;
      "Priority|P2")        config_val="$P2_OPTION_ID" ;;
      "Size|XS")            config_val="$SIZE_XS_OPTION_ID" ;;
      "Size|S")             config_val="$SIZE_S_OPTION_ID" ;;
      "Size|M")             config_val="$SIZE_M_OPTION_ID" ;;
      "Size|L")             config_val="$SIZE_L_OPTION_ID" ;;
      "Size|XL")            config_val="$SIZE_XL_OPTION_ID" ;;
      *) continue ;;
    esac
    if [ "$config_val" != "$live_id" ]; then
      echo "BOARD-CHECK DRIFT: $key config=$config_val live=$live_id"
      mismatches=$((mismatches + 1))
    fi
  done <<< "$live_ids"

  if [ "$mismatches" -gt 0 ]; then
    echo "BOARD-CHECK: $mismatches stale IDs detected. Update config/board-ids.sh"
    return 1
  fi
  echo "BOARD-CHECK: All IDs match live board"
  return 0
}

# Move a GitHub issue to a status on the project board
# Usage: move_board_item <repo> <issue_number> <option_id>
move_board_item() {
  local repo="$1" issue_num="$2" option_id="$3"

  local item_id
  item_id=$(fetch_board_items | python3 -c "
import json, sys
repo = sys.argv[1]
issue_num = int(sys.argv[2])
data = json.load(sys.stdin)
for item in data.get('items', []):
    content = item.get('content', {})
    if content.get('repository') == repo and content.get('number') == issue_num:
        print(item.get('id', ''))
        break
" "$repo" "$issue_num" 2>/dev/null || true)

  if [ -n "$item_id" ]; then
    gh project item-edit \
      --project-id "$PROJECT_ID" \
      --id "$item_id" \
      --field-id "$STATUS_FIELD_ID" \
      --single-select-option-id "$option_id" \
      2>/dev/null && return 0 || return 1
  else
    echo "BOARD: ${repo}#${issue_num} not found on board (skipped)"
    return 1
  fi
}

# Convenience wrappers
# Called by Inspector (phases/inspect.sh, exports INSPECTOR_RUN_ID) and manual David
# intervention only. Foreman build phases never move items to Done — separation of
# duties requires an independent verifier. Enforced at runtime: callers must set
# INSPECTOR_RUN_ID. Manual David sessions can prefix the call:
#   INSPECTOR_RUN_ID=manual move_to_done <repo> <num>
# TTY-based bypass was tried but is unreliable under launchd (cron stdin inheritance
# is not guaranteed non-TTY); positive env-var signal is the safe enforcement path.
# See getqatalyst/foreman#106 (Inspector v0) and #209 (Inspector v1).
move_to_done() {
  local repo="$1" issue_num="$2"
  if [ -z "${INSPECTOR_RUN_ID:-}" ]; then
    echo "BOARD: move_to_done REFUSED for ${repo}#${issue_num} — INSPECTOR_RUN_ID is required. Inspector (phases/inspect.sh) sets this automatically; manual callers should prefix with INSPECTOR_RUN_ID=manual." >&2
    return 1
  fi
  if move_board_item "$repo" "$issue_num" "$DONE_OPTION_ID"; then
    # Close-on-promote: PRs use `Refs #N` (foreman#233), so the issue stays
    # open through merge — Verify->Done is the close point. Idempotent: closing
    # an already-closed issue exits non-zero, absorbed by `|| true`.
    gh issue close "$issue_num" --repo "$repo" --reason completed 2>/dev/null || true
    echo "BOARD: Moved ${repo}#${issue_num} to Done (issue closed)"
  else
    echo "BOARD: Failed to move ${repo}#${issue_num} to Done"
  fi
}

move_to_verify() {
  local repo="$1" issue_num="$2"
  if move_board_item "$repo" "$issue_num" "$VERIFY_OPTION_ID"; then
    echo "BOARD: Moved ${repo}#${issue_num} to Verify"
  else
    echo "BOARD: Failed to move ${repo}#${issue_num} to Verify"
  fi
}

move_to_scope() {
  local repo="$1" issue_num="$2"
  if move_board_item "$repo" "$issue_num" "$SCOPE_OPTION_ID"; then
    echo "BOARD: Moved ${repo}#${issue_num} to Scope"
  else
    echo "BOARD: Failed to move ${repo}#${issue_num} to Scope"
  fi
}

move_to_in_progress() {
  local repo="$1" issue_num="$2"
  if move_board_item "$repo" "$issue_num" "$IN_PROGRESS_OPTION_ID"; then
    echo "BOARD: Moved ${repo}#${issue_num} to In Progress"
  else
    echo "BOARD: Failed to move ${repo}#${issue_num} to In Progress"
  fi
}

move_to_in_review() {
  local repo="$1" issue_num="$2"
  if move_board_item "$repo" "$issue_num" "$IN_REVIEW_OPTION_ID"; then
    echo "BOARD: Moved ${repo}#${issue_num} to In Review"
  else
    echo "BOARD: Failed to move ${repo}#${issue_num} to In Review"
  fi
}

move_to_ready() {
  local repo="$1" issue_num="$2"
  if move_board_item "$repo" "$issue_num" "$READY_OPTION_ID"; then
    echo "BOARD: Moved ${repo}#${issue_num} to Ready"
  else
    echo "BOARD: Failed to move ${repo}#${issue_num} to Ready"
    return 1
  fi
}

move_to_blocked() {
  local repo="$1" issue_num="$2"
  if move_board_item "$repo" "$issue_num" "$BLOCKED_OPTION_ID"; then
    echo "BOARD: Moved ${repo}#${issue_num} to Blocked"
  else
    echo "BOARD: Failed to move ${repo}#${issue_num} to Blocked"
  fi
}

move_to_parking() {
  local repo="$1" issue_num="$2"
  if move_board_item "$repo" "$issue_num" "$PARKING_OPTION_ID"; then
    echo "BOARD: Moved ${repo}#${issue_num} to Parking"
  else
    echo "BOARD: Failed to move ${repo}#${issue_num} to Parking"
    return 1
  fi
}
