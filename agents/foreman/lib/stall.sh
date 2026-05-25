#!/bin/bash
# Stall detection helpers.
#
# A stall = orchestrator cycle finished with zero work but the Ready board
# column still has items. Without a signal, David finds out 24-48h later
# (incident 2026-04-28: 10 cycles produced zero output, Sage WIP cap held
# by 4 CI-failing PRs).
#
# Surfaces:
#   1. macOS notification (osascript) — transient banner, persists in NC
#   2. Slack webhook to dev-alert — durable, multi-surface (mobile/email/desktop)
#
# Callers must source config/board-ids.sh first (provides fetch_board_items).

STALL_REPOS=("getqatalyst/Sage" "getqatalyst/coaches" "getqatalyst/Jobber" "getqatalyst/product-studio")
STALL_WIP_CAP=3
STALL_ORG="getqatalyst"
STALL_BOARD_URL="https://github.com/orgs/getqatalyst/projects/5"

# Slack/macOS dedup. Sibling pattern to lib/comments.sh:121 (issue-comment dedup),
# adapted because the stall channel has no remote audit trail to scan — state lives
# in a local file alongside the daily logs in results/. 12h window matches the
# orchestrator cadence (5x/day): a payload that re-fires within 12h is the same
# pile-up, so suppress it; a fresh payload (different subtitle or PR-set) re-alerts
# immediately because the hash differs.
STALL_DEDUP_TTL_SECONDS=43200  # 12h

# Echo the count of items currently in the Ready column.
count_ready_items() {
  fetch_board_items 2>/dev/null | python3 -c "
import json, sys
try:
    items = json.load(sys.stdin).get('items', [])
    print(sum(1 for i in items if i.get('status') == 'Ready'))
except Exception:
    print(0)
" 2>/dev/null || echo 0
}

# Echo a JSON document describing per-repo auto/ PR state.
# Shape:
#   {"repos": [{"name", "open_auto", "failing", "cap_hit", "pr_numbers": [...], "gh_failed": bool}, ...]}
# gh_failed=true means `gh pr list` exited non-zero (auth, rate limit, network).
# Without that flag, every failing repo collapses to {open_auto:0, failing:0, cap_hit:false}
# and the alert renders as "no progress" instead of "blocker analysis unreliable".
get_stall_context() {
  local repos_json="["
  local first=1
  local repo short pr_json repo_data
  for repo in "${STALL_REPOS[@]}"; do
    short="${repo#getqatalyst/}"
    if pr_json=$(gh pr list --repo "$repo" --state open \
        --json number,headRefName,statusCheckRollup 2>/dev/null); then
      repo_data=$(echo "$pr_json" | STALL_REPO_NAME="$short" STALL_WIP_CAP_VAL="$STALL_WIP_CAP" python3 -c "
import json, os, sys
try:
    prs = json.load(sys.stdin)
except Exception:
    prs = []
auto_prs = [p for p in prs if p.get('headRefName', '').startswith('auto/')]
failing_pr_numbers = []
for p in auto_prs:
    checks = p.get('statusCheckRollup') or []
    if any(c.get('conclusion') == 'FAILURE' or c.get('state') == 'FAILURE' for c in checks):
        failing_pr_numbers.append(p['number'])
cap = int(os.environ['STALL_WIP_CAP_VAL'])
print(json.dumps({
    'name': os.environ['STALL_REPO_NAME'],
    'open_auto': len(auto_prs),
    'failing': len(failing_pr_numbers),
    'cap_hit': len(auto_prs) >= cap,
    'pr_numbers': failing_pr_numbers,
    'gh_failed': False,
}))
" 2>/dev/null || echo "{\"name\":\"${short}\",\"open_auto\":0,\"failing\":0,\"cap_hit\":false,\"pr_numbers\":[],\"gh_failed\":true}")
    else
      repo_data="{\"name\":\"${short}\",\"open_auto\":0,\"failing\":0,\"cap_hit\":false,\"pr_numbers\":[],\"gh_failed\":true}"
    fi
    if [ "$first" -eq 1 ]; then first=0; else repos_json="${repos_json},"; fi
    repos_json="${repos_json}${repo_data}"
  done
  repos_json="${repos_json}]"
  echo "{\"repos\": ${repos_json}}"
}

# Compute the one-liner Ready-column detail: total count + oldest issue ref.
# Uses createdAt (the only "age" field plumbed through fetch_board_items today;
# updatedAt and column-entry time are not currently fetched). Echoes the empty
# string on any failure so callers can fall back to the bare "run build" line.
# Format: "Ready: N items, oldest owner/repo#NUM (Nd)".
oldest_ready_detail() {
  fetch_board_items 2>/dev/null | python3 -c "
import json, sys
from datetime import datetime, timezone
try:
    items = json.load(sys.stdin).get('items', [])
except Exception:
    sys.exit(0)
ready = [i for i in items if i.get('status') == 'Ready']
if not ready:
    sys.exit(0)
def created_at(i):
    return i.get('content', {}).get('createdAt', '') or '9999-12-31T00:00:00Z'
oldest = min(ready, key=created_at)
content = oldest.get('content', {})
repo = content.get('repository', '')
num = content.get('number')
ts = content.get('createdAt', '')
if not (repo and num and ts):
    sys.exit(0)
try:
    created = datetime.fromisoformat(ts.replace('Z', '+00:00'))
    days = max(0, (datetime.now(timezone.utc) - created).days)
except Exception:
    sys.exit(0)
print(f'Ready: {len(ready)} items, oldest {repo}#{num} ({days}d)')
" 2>/dev/null || true
}

# Hash the alert payload (subtitle + sorted PR-set) so identical pile-ups dedup
# but new failures always alert. Echoes the hash, or empty on failure.
_stall_payload_hash() {
  local subtitle="$1"
  local context="$2"
  local pr_set
  pr_set=$(echo "$context" | python3 -c "
import json, sys
try:
    ctx = json.load(sys.stdin)
except Exception:
    sys.exit(0)
parts = []
for r in ctx.get('repos', []):
    name = r.get('name', '')
    for n in r.get('pr_numbers', []) or []:
        parts.append(f'{name}#{n}')
print(','.join(sorted(parts)))
" 2>/dev/null || echo "")
  printf '%s|%s' "$subtitle" "$pr_set" | shasum 2>/dev/null | awk '{print $1}'
}

# Resolve the dedup state file. Defaults to results/.stall-state under the
# foreman repo; tests can override via STALL_STATE_FILE.
_stall_state_file() {
  if [ -n "${STALL_STATE_FILE:-}" ]; then
    echo "$STALL_STATE_FILE"
    return
  fi
  local self_dir
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  echo "${self_dir}/results/.stall-state"
}

# Return 0 if a matching hash was alerted within STALL_DEDUP_TTL_SECONDS.
# State file format: one record per line, "EPOCH HASH". We only need the most
# recent record per hash, so we read the whole file (small) and check.
_stall_should_skip() {
  local hash="$1"
  local state_file="$2"
  [ -z "$hash" ] && return 1
  [ -f "$state_file" ] || return 1
  local now last_ts
  now=$(date +%s)
  last_ts=$(awk -v h="$hash" '$2==h {ts=$1} END {print ts+0}' "$state_file")
  [ "$last_ts" -eq 0 ] && return 1
  local age=$((now - last_ts))
  [ "$age" -lt "$STALL_DEDUP_TTL_SECONDS" ]
}

# Append a (timestamp, hash) record. Trims the file to the last 50 lines so it
# stays bounded across long uptimes.
_stall_record_payload() {
  local hash="$1"
  local state_file="$2"
  [ -z "$hash" ] && return 0
  mkdir -p "$(dirname "$state_file")" 2>/dev/null || true
  printf '%s %s\n' "$(date +%s)" "$hash" >> "$state_file"
  if [ "$(wc -l < "$state_file" 2>/dev/null || echo 0)" -gt 50 ]; then
    tail -n 50 "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
  fi
}

# Fire the stall alert: macOS banner + Slack post (if webhook configured).
#
# Legacy fallback path. lib/cycle-summary.sh#notify_cycle_summary now posts a
# summary at the end of every orchestrator cycle (Decide / Validate / Watch),
# making the Slack channel a log feed instead of a stall-only alarm. This
# function is kept as a dedup-protected backstop: if cycle-summary errors,
# the orchestrator's zero-work-with-Ready-items branch still fires this so
# the worst-case alarm path stays alive.
#
# Args:
#   $1 — ready_count (integer)
# Reads env:
#   SLACK_CI_WEBHOOK_URL — webhook for dev-alert (silent skip if unset)
notify_stall() {
  local ready_count="${1:-0}"
  local context rendered ready_detail
  context=$(get_stall_context)
  ready_detail=$(oldest_ready_detail)
  rendered=$(echo "$context" | READY_COUNT="$ready_count" STALL_BOARD_URL="$STALL_BOARD_URL" STALL_ORG="$STALL_ORG" STALL_WIP_CAP_VAL="$STALL_WIP_CAP" READY_DETAIL="$ready_detail" python3 -c '
import json, os, sys
ctx = json.load(sys.stdin)
ready = int(os.environ.get("READY_COUNT", "0"))
board = os.environ["STALL_BOARD_URL"]
org = os.environ["STALL_ORG"]
cap = os.environ["STALL_WIP_CAP_VAL"]
ready_detail = os.environ.get("READY_DETAIL", "").strip()
repos = ctx.get("repos", [])
gh_failed = [r for r in repos if r.get("gh_failed")]
contributing = [r for r in repos if r.get("failing", 0) > 0 or r.get("cap_hit")]

def queue_url(name):
    return f"https://github.com/{org}/{name}/pulls?q=is%3Aopen+head%3Aauto%2F"
def pr_url(name, n):
    return f"https://github.com/{org}/{name}/pull/{n}"
def pr_word(n):
    return "PR" if n == 1 else "PRs"
def action_for(repo):
    if repo["cap_hit"] and repo["failing"] > 0:
        return f"→ Close 1 stale {repo['name']} auto/ PR or raise the cap ({cap} in `lib/stall.sh`)"
    if repo["failing"] > 0:
        return f"→ Triage failing {repo['name']} PRs or run `./orchestrator.sh repair`"
    if repo["cap_hit"]:
        return f"→ Wait on review, close stale, or raise the {repo['name']} cap"
    return f"→ {ready_detail}" if ready_detail else "→ Run `./orchestrator.sh build` to surface the error"

if gh_failed:
    # Upstream tool failure: blocker analysis is unreliable, do not pretend the
    # repos are healthy. One failed `gh pr list` (rate limit, expired auth,
    # network) collapses every repo to zeros, so we surface it explicitly
    # rather than render the misleading "no progress" line.
    failed_names = ", ".join(r["name"] for r in gh_failed)
    head = f"blocker analysis unreliable — `gh pr list` failed for {failed_names}"
    slack = (
        f":warning: *Foreman stalled* — {head}\n"
        f"→ Check `gh auth status` and rate limit, then rerun once gh works\n"
        f"<{board}|Board>"
    )
    subtitle = "blocker scan unreliable (gh failed)"
elif not contributing:
    head = f"{ready} in Ready, no progress this cycle"
    # Prefer Ready-column detail (oldest pending issue) over the bare "run build"
    # copy — gives David a concrete pointer instead of a generic command. Falls
    # back to "run build" if the Ready query failed (oldest_ready_detail empty).
    detail_line = f"→ {ready_detail}" if ready_detail else "→ Run `./orchestrator.sh build` to surface the error"
    slack = (
        f":warning: *Foreman stalled* — {head}\n"
        f"{detail_line}\n"
        f"<{board}|Board>"
    )
    subtitle = head
elif len(contributing) == 1:
    r = contributing[0]
    if r["cap_hit"] and r["failing"] > 0:
        head = f"{r['name']} WIP cap reached ({r['failing']}/{cap} auto/ {pr_word(r['failing'])} CI-failing)"
    elif r["failing"] > 0:
        head = f"{r['name']}: {r['failing']} auto/ {pr_word(r['failing'])} CI-failing"
    else:
        head = f"{r['name']} WIP cap reached ({r['open_auto']} open auto/ {pr_word(r['open_auto'])})"
    lines = [f":warning: *Foreman stalled* — {head}"]
    if r["pr_numbers"]:
        pr_links = " · ".join(
            f"<{pr_url(r['name'], n)}|{r['name']}#{n}>" for n in r["pr_numbers"]
        )
        lines.append(f"PRs: {pr_links}")
    lines.append(action_for(r))
    lines.append(f"<{board}|Board> · <{queue_url(r['name'])}|{r['name']} auto/ queue>")
    slack = "\n".join(lines)
    subtitle = head
else:
    lines = [":warning: *Foreman stalled* — multiple repos blocked"]
    for r in contributing:
        if r["cap_hit"] and r["failing"] > 0:
            label = f"{r['failing']}/{cap} {pr_word(r['failing'])} CI-failing"
        elif r["failing"] > 0:
            label = f"{r['failing']} {pr_word(r['failing'])} CI-failing"
        else:
            label = f"{r['open_auto']} open auto/ {pr_word(r['open_auto'])} (cap)"
        line = f"*{r['name']}:* {label}"
        if r["pr_numbers"]:
            pr_links = " ".join(f"<{pr_url(r['name'], n)}|#{n}>" for n in r["pr_numbers"])
            line += f" — {pr_links}"
        lines.append(line)
    lines.append("→ Triage failing PRs across repos, or run `./orchestrator.sh repair`")
    queues = " · ".join(f"<{queue_url(r['name'])}|{r['name']}>" for r in contributing)
    lines.append(f"<{board}|Board> · {queues}")
    slack = "\n".join(lines)
    subtitle = ", ".join(f"{r['name']} {r['failing']}" for r in contributing) + " CI-failing"

print(json.dumps({"slack": slack, "subtitle": subtitle}))
' 2>/dev/null || echo '{}')

  local subtitle slack_text
  subtitle=$(echo "$rendered" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('subtitle',''))
except Exception: print('')" 2>/dev/null || echo "stalled")
  slack_text=$(echo "$rendered" | python3 -c "import json,sys
try: print(json.load(sys.stdin).get('slack',''))
except Exception: print('')" 2>/dev/null || echo "")

  # Dedup guard: byte-identical pile-ups within STALL_DEDUP_TTL_SECONDS get
  # suppressed (mirrors comment_dedup_or_escalate from lib/comments.sh:121).
  # A changed subtitle or PR-set produces a different hash and re-alerts.
  local payload_hash state_file
  payload_hash=$(_stall_payload_hash "$subtitle" "$context")
  state_file=$(_stall_state_file)
  if _stall_should_skip "$payload_hash" "$state_file"; then
    return 0
  fi
  _stall_record_payload "$payload_hash" "$state_file"

  # Prepend provenance banner to Slack text
  if [ -n "${FOREMAN_BANNER:-}" ] && [ -n "$slack_text" ]; then
    slack_text="${FOREMAN_BANNER} ${slack_text}"
  fi

  # Surface 1: macOS notification (existing behaviour)
  osascript -e "display notification \"${ready_count} in Ready, no progress\" with title \"Foreman ${FOREMAN_BANNER:-} stalled\" subtitle \"${subtitle}\"" 2>/dev/null || true

  # Surface 2: Slack webhook (new in foreman#139 v2)
  # shellcheck disable=SC1091
  . "$(dirname "${BASH_SOURCE[0]}")/slack.sh"
  slack_post SLACK_CI_WEBHOOK_URL "$slack_text"
}
