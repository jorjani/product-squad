#!/bin/bash
# Per-cycle Slack summary post.
#
# Replaces the stall-only alert (lib/stall.sh) with a log feed: every
# orchestrator cycle posts a short summary, regardless of whether work
# happened. Quiet cycles stay short (header + status), busy cycles add
# Decide / Validate / Watch sections only when populated.
#
# Format (M1+M2 hybrid, telegraph):
#   *<HH:MM> · <DayName MMM D>*
#   🟢 Sage: shipped <N>[ (refs)] · CI <green|red>   |   🤖 Foreman: <N> PRs landed[, <N> open]
#   *Decide* (<N>): repo#<id>[, repo#<id>...]
#   *Validate* (<N> in Verify, oldest repo#<id> <N>d)
#   *Watch:* <one-line risk>
#   [Board](<url>)
#
# Design: _cs_render is a pure function (JSON in → text out) so the
# format is testable without hitting gh/Slack. notify_cycle_summary is
# the thin wrapper that gathers, renders, and posts.
#
# Callers must source config/board-ids.sh first (provides fetch_board_items).

CS_BOARD_URL="https://github.com/orgs/getqatalyst/projects/5"
CS_REPOS=("getqatalyst/Sage" "getqatalyst/coaches" "getqatalyst/Jobber" "getqatalyst/product-studio" "getqatalyst/foreman")
CS_SAGE_REPO="getqatalyst/Sage"
CS_FOREMAN_REPO="getqatalyst/foreman"
CS_SCOPE_STALE_DAYS=5

# Pure render: read fixture JSON on stdin, print formatted Slack text on stdout.
# Fixture shape:
#   {
#     "time_str": "14:23",
#     "day_str": "Fri May 8",
#     "sage": {"shipped": N, "refs": [num,...], "ci": "green|red|unknown"},
#     "foreman": {"landed": N, "open": N},
#     "decide": [{"repo": "Sage", "num": 175}, ...],
#     "validate": {"count": N, "oldest_repo": "coaches", "oldest_num": 188, "oldest_days": 4},
#     "watch": ["risk line 1", "risk line 2"],
#     "board_url": "https://..."
#   }
# Any section may be empty/missing — render drops it.
_cs_render() {
  python3 -c '
import json, sys

try:
    data = json.load(sys.stdin)
except Exception as e:
    print(f"_cs_render: bad JSON input: {e}", file=sys.stderr)
    sys.exit(1)

time_str = data.get("time_str", "")
day_str = data.get("day_str", "")
sage = data.get("sage") or {}
foreman = data.get("foreman") or {}
decide = data.get("decide") or []
validate = data.get("validate") or {}
watch = data.get("watch") or []
board_url = data.get("board_url", "")

lines = []

# Header — always renders.
lines.append(f"*{time_str} · {day_str}*")

# Status line — always renders.
sage_n = int(sage.get("shipped", 0) or 0)
sage_refs = sage.get("refs") or []
sage_ci = sage.get("ci", "unknown")
sage_part = f"🟢 Sage: shipped {sage_n}"
if sage_n > 0 and sage_refs:
    sage_part += " (" + ", ".join(f"#{r}" for r in sage_refs[:3]) + ")"
sage_part += f" · CI {sage_ci}"

f_landed = int(foreman.get("landed", 0) or 0)
f_open = int(foreman.get("open", 0) or 0)
foreman_part = f"🤖 Foreman: {f_landed} PRs landed"
if f_open > 0:
    foreman_part += f", {f_open} open"

lines.append(f"{sage_part}   |   {foreman_part}")

# Decide — only if populated.
if decide:
    parts = []
    for d in decide:
        repo = d.get("repo", "?")
        num = d.get("num", "?")
        parts.append(f"{repo}#{num}")
    refs = ", ".join(parts)
    lines.append(f"*Decide* ({len(decide)}): {refs}")

# Validate — only if populated (count > 0).
v_count = int(validate.get("count", 0) or 0)
if v_count > 0:
    o_repo = validate.get("oldest_repo", "?")
    o_num = validate.get("oldest_num", "?")
    o_days = int(validate.get("oldest_days", 0) or 0)
    lines.append(f"*Validate* ({v_count} in Verify, oldest {o_repo}#{o_num} {o_days}d)")

# Watch — only if populated. Cap at 2 lines.
for risk in watch[:2]:
    if risk:
        lines.append(f"*Watch:* {risk}")

# Board link only when there is something to act on.
if (decide or v_count > 0 or watch) and board_url:
    lines.append(f"[Board]({board_url})")

print("\n".join(lines))
'
}

# Strip "getqatalyst/" prefix; echo the short repo name.
_cs_short_repo() {
  local repo="$1"
  echo "${repo#getqatalyst/}"
}

# Echo the count of human PRs merged to a repo's main today (UTC).
# Excludes auto/* (Foreman-built) so the Foreman bucket is disjoint — reader
# does no math. Conservative: if the gh call fails, echo 0.
_cs_count_shipped_today() {
  local repo="$1"
  local since
  since=$(date -u +%Y-%m-%dT00:00:00Z)
  gh pr list --repo "$repo" --state merged --base main \
    --search "merged:>=${since} -head:auto/" --json number \
    -L 50 2>/dev/null \
    | python3 -c "
import json, sys
try:
    print(len(json.load(sys.stdin)))
except Exception:
    print(0)
" 2>/dev/null || echo 0
}

# Echo a JSON list of human PR numbers merged to a repo's main today (UTC),
# oldest first. Excludes auto/* to match _cs_count_shipped_today.
# Capped at 3 entries; the renderer trims further if needed.
_cs_shipped_refs() {
  local repo="$1"
  local since
  since=$(date -u +%Y-%m-%dT00:00:00Z)
  gh pr list --repo "$repo" --state merged --base main \
    --search "merged:>=${since} -head:auto/" --json number,mergedAt \
    -L 10 2>/dev/null \
    | python3 -c "
import json, sys
try:
    prs = json.load(sys.stdin)
    prs.sort(key=lambda p: p.get('mergedAt', ''))
    print(json.dumps([p['number'] for p in prs[:3]]))
except Exception:
    print('[]')
" 2>/dev/null || echo "[]"
}

# Echo the CI status of a repo's main BRANCH: green | red | unknown.
#
# Uses actions/runs?branch=main&event=push, which returns only workflows
# that ran on the main branch ref from push events. The previous implementation
# read check-runs on the main HEAD commit, which also surfaced PR-bound
# advisory gates (e.g. Sonar) attributed to the merged SHA — causing "CI red"
# reports while main was actually green. The event=push filter then dropped
# the Claude Code issue_comment workflow (always conclusion=skipped) that
# fires on every PR comment and was burying real push CI in recency-sorted
# results — causing "CI unknown" while main was actually green.
_cs_main_ci() {
  local repo="$1"
  local conclusion
  conclusion=$(gh api "repos/${repo}/actions/runs?branch=main&event=push&per_page=1" \
    --jq '.workflow_runs[0].conclusion // ""' 2>/dev/null || echo "")
  case "$conclusion" in
    success)                     echo "green" ;;
    failure|timed_out|cancelled) echo "red" ;;
    *)                           echo "unknown" ;;
  esac
}

# Echo "landed|open" — auto/ PRs merged today and currently open across CS_REPOS.
_cs_foreman_pr_stats() {
  local landed=0 open=0
  local since
  since=$(date -u +%Y-%m-%dT00:00:00Z)
  local repo merged_n open_n
  for repo in "${CS_REPOS[@]}"; do
    merged_n=$(gh pr list --repo "$repo" --state merged --base main \
      --search "merged:>=${since} head:auto/" --json number -L 50 2>/dev/null \
      | python3 -c "
import json, sys
try: print(len(json.load(sys.stdin)))
except: print(0)" 2>/dev/null || echo 0)
    open_n=$(gh pr list --repo "$repo" --state open \
      --json headRefName -L 50 2>/dev/null \
      | python3 -c "
import json, sys
try:
    prs = json.load(sys.stdin)
    print(sum(1 for p in prs if p.get('headRefName','').startswith('auto/')))
except: print(0)" 2>/dev/null || echo 0)
    landed=$((landed + merged_n))
    open=$((open + open_n))
  done
  echo "${landed}|${open}"
}

# Echo a JSON list of "decide" items: Pitch labeled needs-decision OR Scope >5d.
# Each entry: {"repo": "Sage", "num": 175}. Capped at 6.
_cs_decide_items() {
  local board_json
  board_json=$(fetch_board_items 2>/dev/null || echo '{"items":[]}')
  echo "$board_json" | CS_STALE="$CS_SCOPE_STALE_DAYS" python3 -c '
import json, os, sys
from datetime import datetime, timezone, timedelta

stale_days = int(os.environ.get("CS_STALE", "5"))
cutoff = datetime.now(timezone.utc) - timedelta(days=stale_days)

try:
    items = json.load(sys.stdin).get("items", [])
except Exception:
    items = []

out = []
for it in items:
    status = it.get("status", "")
    content = it.get("content", {}) or {}
    repo = content.get("repository", "")
    num = content.get("number")
    if not (repo and num):
        continue
    short = repo.replace("getqatalyst/", "")
    if status == "Scope":
        # updatedAt approximates "last status update" — better than createdAt,
        # which flagged freshly-moved items as stale by their original birthday.
        ts = content.get("updatedAt") or content.get("createdAt", "")
        if not ts:
            continue
        try:
            d = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except Exception:
            continue
        if d < cutoff:
            out.append({"repo": short, "num": num})
out_capped = out[:6]
print(json.dumps(out_capped))
'
}

# Fetch issues labeled needs-decision in any board repo.
# Echo JSON list of {"repo", "num"}.
_cs_needs_decision_items() {
  local out="["
  local first=1 repo short result
  for repo in "${CS_REPOS[@]}"; do
    short=$(_cs_short_repo "$repo")
    result=$(gh issue list --repo "$repo" --label needs-decision --state open \
      --json number -L 20 2>/dev/null | python3 -c "
import json, sys
try:
    nums = [i['number'] for i in json.load(sys.stdin)]
    print(json.dumps(nums))
except: print('[]')" 2>/dev/null || echo "[]")
    while IFS= read -r num; do
      [ -z "$num" ] && continue
      [ "$first" -eq 1 ] && first=0 || out="${out},"
      out="${out}{\"repo\":\"${short}\",\"num\":${num}}"
    done < <(echo "$result" | python3 -c "
import json, sys
try:
    for n in json.load(sys.stdin): print(n)
except: pass" 2>/dev/null)
  done
  out="${out}]"
  echo "$out"
}

# Echo JSON: {"count": N, "oldest_repo": "...", "oldest_num": N, "oldest_days": N}
_cs_validate_summary() {
  fetch_board_items 2>/dev/null | python3 -c '
import json, sys
from datetime import datetime, timezone

try:
    items = json.load(sys.stdin).get("items", [])
except Exception:
    items = []

verify = []
for it in items:
    if it.get("status") != "Verify":
        continue
    c = it.get("content", {}) or {}
    repo = c.get("repository", "")
    num = c.get("number")
    # updatedAt approximates "last moved into / activity in Verify". Falls
    # back to createdAt if the field is missing. createdAt-as-staleness flagged
    # newly-moved items by their original birthday.
    ts = c.get("updatedAt") or c.get("createdAt", "")
    if not (repo and num and ts):
        continue
    verify.append((ts, repo.replace("getqatalyst/", ""), num))

if not verify:
    print(json.dumps({"count": 0}))
    sys.exit(0)

verify.sort()
oldest_ts, oldest_repo, oldest_num = verify[0]
try:
    d = datetime.fromisoformat(oldest_ts.replace("Z", "+00:00"))
    days = max(0, (datetime.now(timezone.utc) - d).days)
except Exception:
    days = 0

print(json.dumps({
    "count": len(verify),
    "oldest_repo": oldest_repo,
    "oldest_num": oldest_num,
    "oldest_days": days,
}))
' 2>/dev/null || echo '{"count":0}'
}

# Echo JSON list of watch lines (≤2).
# Sources: failing PR CI on board repos, foreman issues labeled bug+urgent.
_cs_watch_lines() {
  local lines="["
  local first=1 repo short pr_data
  # Failing PRs first.
  for repo in "${CS_REPOS[@]}"; do
    short=$(_cs_short_repo "$repo")
    pr_data=$(gh pr list --repo "$repo" --state open \
      --json number,headRefName,statusCheckRollup -L 50 2>/dev/null \
      | REPO_SHORT="$short" python3 -c "
import json, os, sys
short = os.environ['REPO_SHORT']
try:
    prs = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for p in prs:
    checks = p.get('statusCheckRollup') or []
    if any((c.get('conclusion') == 'FAILURE' or c.get('state') == 'FAILURE') for c in checks):
        print(f'PR {short}#{p[\"number\"]} CI failing')
        break  # one line per repo at most
" 2>/dev/null || true)
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      [ "$first" -eq 1 ] && first=0 || lines="${lines},"
      lines="${lines}$(printf '%s' "$line" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')"
    done <<< "$pr_data"
  done
  # foreman bug+urgent.
  local bug_urgent
  bug_urgent=$(gh issue list --repo "$CS_FOREMAN_REPO" --label bug --label urgent \
    --state open --json number -L 5 2>/dev/null \
    | python3 -c "
import json, sys
try:
    nums = [i['number'] for i in json.load(sys.stdin)]
    if nums:
        print('foreman bug+urgent: ' + ', '.join(f'#{n}' for n in nums[:3]))
except: pass" 2>/dev/null || true)
  if [ -n "$bug_urgent" ]; then
    [ "$first" -eq 1 ] && first=0 || lines="${lines},"
    lines="${lines}$(printf '%s' "$bug_urgent" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip()))')"
  fi
  lines="${lines}]"
  # Cap at 2.
  echo "$lines" | python3 -c "
import json, sys
try:
    arr = json.load(sys.stdin)
    print(json.dumps(arr[:2]))
except:
    print('[]')" 2>/dev/null || echo "[]"
}

# Build the full fixture JSON for _cs_render.
_cs_collect_data() {
  local time_str day_str
  time_str=$(date "+%H:%M")
  day_str=$(date "+%a %b %-d")

  local sage_n sage_refs sage_ci
  sage_n=$(_cs_count_shipped_today "$CS_SAGE_REPO")
  sage_refs=$(_cs_shipped_refs "$CS_SAGE_REPO")
  sage_ci=$(_cs_main_ci "$CS_SAGE_REPO")

  local f_stats f_landed f_open
  f_stats=$(_cs_foreman_pr_stats)
  f_landed="${f_stats%%|*}"
  f_open="${f_stats##*|}"

  local stale_decide nd_decide decide_combined
  stale_decide=$(_cs_decide_items)
  nd_decide=$(_cs_needs_decision_items)
  decide_combined=$(STALE_JSON="$stale_decide" ND_JSON="$nd_decide" python3 -c '
import json, os
stale = json.loads(os.environ["STALE_JSON"]) if os.environ.get("STALE_JSON") else []
nd = json.loads(os.environ["ND_JSON"]) if os.environ.get("ND_JSON") else []
seen = set()
out = []
for d in stale + nd:
    key = (d.get("repo"), d.get("num"))
    if key in seen:
        continue
    seen.add(key)
    out.append(d)
print(json.dumps(out[:6]))
' 2>/dev/null || echo "[]")

  local validate watch
  validate=$(_cs_validate_summary)
  watch=$(_cs_watch_lines)

  TIME_STR="$time_str" DAY_STR="$day_str" \
  SAGE_N="$sage_n" SAGE_REFS="$sage_refs" SAGE_CI="$sage_ci" \
  F_LANDED="$f_landed" F_OPEN="$f_open" \
  DECIDE_JSON="$decide_combined" VALIDATE_JSON="$validate" WATCH_JSON="$watch" \
  BOARD_URL="$CS_BOARD_URL" python3 -c '
import json, os
print(json.dumps({
    "time_str": os.environ["TIME_STR"],
    "day_str": os.environ["DAY_STR"],
    "sage": {
        "shipped": int(os.environ.get("SAGE_N", "0") or 0),
        "refs": json.loads(os.environ.get("SAGE_REFS", "[]") or "[]"),
        "ci": os.environ.get("SAGE_CI", "unknown"),
    },
    "foreman": {
        "landed": int(os.environ.get("F_LANDED", "0") or 0),
        "open": int(os.environ.get("F_OPEN", "0") or 0),
    },
    "decide": json.loads(os.environ.get("DECIDE_JSON", "[]") or "[]"),
    "validate": json.loads(os.environ.get("VALIDATE_JSON", "{}") or "{}"),
    "watch": json.loads(os.environ.get("WATCH_JSON", "[]") or "[]"),
    "board_url": os.environ.get("BOARD_URL", ""),
}))
'
}

# Top-level: gather, render, post. Failures are non-fatal — orchestrator
# continues. This is intentionally noisier on success and silent on failure.
notify_cycle_summary() {
  local fixture text
  fixture=$(_cs_collect_data 2>/dev/null) || {
    echo "[cycle-summary] data collection failed; skipping post" >&2
    return 0
  }
  text=$(echo "$fixture" | _cs_render 2>/dev/null) || {
    echo "[cycle-summary] render failed; skipping post" >&2
    return 0
  }

  # Prepend provenance banner to Slack text
  if [ -n "${FOREMAN_BANNER:-}" ] && [ -n "$text" ]; then
    text="${FOREMAN_BANNER} ${text}"
  fi

  # shellcheck disable=SC1091
  . "$(dirname "${BASH_SOURCE[0]}")/slack.sh"
  slack_post SLACK_CI_WEBHOOK_URL "$text"
}
