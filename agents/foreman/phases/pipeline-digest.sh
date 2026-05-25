#!/bin/bash
# Pipeline Digest: daily actionable digest with auto-actions
# AUTO: close stale digests
# REPORT: Verify items (Foreman handles actual verification)
# POSTS: pipeline-digest GitHub issue (getqatalyst/foreman)
# Note: PM-layer scoping is owned by Sarge (getqatalyst/sarge)
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
DATE=$(date +%Y-%m-%d)
LOG="$RESULTS_DIR/$DATE.log"

mkdir -p "$RESULTS_DIR"
source "$SCRIPT_DIR/config/board-ids.sh"
# CI classification: required-set is fetched per repo from branch-protection
# (see BLOCKER_REPOS loop below). FAILURE on a required check → Blocker;
# FAILURE on an unrequired check → Advisory. 404 → empty required-set → all
# advisory. See specs/181-digest-classify-flow.md.

# Run once per day
SENTINEL="$RESULTS_DIR/.pipeline-digest-ran-$DATE"
if [ -f "$SENTINEL" ]; then
  echo "PIPELINE-DIGEST: Already ran today" >> "$LOG"
  echo "skipped=1"
  exit 0
fi

echo "PIPELINE-DIGEST: Starting" >> "$LOG"

# Fetch all board items once — reused throughout
ALL_ITEMS=$(fetch_board_items)

AUTO_LOG=""
AUTO_COUNT=0

# ── REPORT: Items in Verify (Foreman handles actual verification) ─────────
VERIFY_ITEMS=$(echo "$ALL_ITEMS" | python3 -c "
import json, sys
items = []
for item in json.load(sys.stdin).get('items', []):
    if item.get('status') != 'Verify': continue
    c = item.get('content', {})
    r, n = c.get('repository',''), c.get('number','')
    title = item.get('title','')
    if r and n: items.append((r, str(n), title))
for r, n, title in items:
    short = r.replace('getqatalyst/', '')
    print(f'{r}|{n}|{title}|{short}')
" 2>/dev/null || true)
VERIFY_COUNT=0
VERIFY_LOG=""
AUTO_DECLINED_COUNT=0
AUTO_DECLINED_LOG=""
while IFS='|' read -r REPO ISSUE_NUM TITLE SHORT; do
  [ -z "$REPO" ] && continue
  # Auto-declined items carry a DECLINED: bot comment (posted by build-ticket.sh
  # when Claude wrote `.decline-reason.md`). Surface them in their own section
  # so they don't get conflated with verification work.
  DECLINED_HITS=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json comments \
    -q '[.comments[] | select(.body | startswith("DECLINED:"))] | length' 2>/dev/null || echo 0)
  if [ "${DECLINED_HITS:-0}" -gt 0 ]; then
    AUTO_DECLINED_COUNT=$((AUTO_DECLINED_COUNT + 1))
    AUTO_DECLINED_LOG="${AUTO_DECLINED_LOG}\n- [${SHORT} #${ISSUE_NUM}](https://github.com/${REPO}/issues/${ISSUE_NUM}) ${TITLE}"
  else
    VERIFY_COUNT=$((VERIFY_COUNT + 1))
    VERIFY_LOG="${VERIFY_LOG}\n- [${SHORT} #${ISSUE_NUM}](https://github.com/${REPO}/issues/${ISSUE_NUM}) ${TITLE}"
  fi
done <<< "$VERIFY_ITEMS"

# ── AUTO 2: Close pipeline-digest issues older than 2 days ───────────────────
CUTOFF=$(python3 -c "from datetime import datetime,timedelta; print((datetime.utcnow()-timedelta(days=2)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
gh issue list --repo getqatalyst/foreman --label pipeline-digest --state open --json number,createdAt 2>/dev/null \
  | python3 -c "
import json,sys
cutoff='$CUTOFF'
for i in json.load(sys.stdin):
    if i['createdAt'] < cutoff: print(i['number'])
" 2>/dev/null | while read -r OLD_NUM; do
  [ -z "$OLD_NUM" ] && continue
  gh issue close "$OLD_NUM" --repo getqatalyst/foreman --comment "Superseded by today's digest." 2>/dev/null || true
  echo "PIPELINE-DIGEST: Closed old digest #$OLD_NUM" >> "$LOG"
done

# ── AUTO: Clean Ready of already-shipped items ────────────────────────────
READY_CLEANUP=$(echo "$ALL_ITEMS" | python3 -c "
import json, sys
for item in json.load(sys.stdin).get('items', []):
    if item.get('status') != 'Ready': continue
    c = item.get('content', {})
    r, n = c.get('repository',''), c.get('number','')
    if r and n: print(f'{r}|{n}')
" 2>/dev/null || true)
while IFS='|' read -r REPO ISSUE_NUM; do
  [ -z "$REPO" ] && continue
  STATE=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "OPEN")
  if [ "$STATE" = "CLOSED" ]; then
    move_to_verify "$REPO" "$ISSUE_NUM" >> "$LOG" 2>&1 || true
    SHORT="${REPO#getqatalyst/}"
    AUTO_LOG="${AUTO_LOG}\n- Ready->Verify: [${SHORT} #${ISSUE_NUM}](https://github.com/${REPO}/issues/${ISSUE_NUM}) (already shipped, awaits Inspector)"
    AUTO_COUNT=$((AUTO_COUNT + 1))
  fi
done <<< "$READY_CLEANUP"

# ── BLOCKERS: CI-failing PRs, build failures, WIP limits ───────────────────
BLOCKER_REPOS=("getqatalyst/Sage" "getqatalyst/coaches" "getqatalyst/Jobber" "getqatalyst/product-studio")
BLOCKER_LINES=""
BLOCKER_COUNT=0
ADVISORY_LINES=""
ADVISORY_COUNT=0
GH_FAILED_REPOS=""
GH_FAILED_COUNT=0

for B_REPO in "${BLOCKER_REPOS[@]}"; do
  B_SHORT="${B_REPO#getqatalyst/}"

  # Required-set lookup: one `gh api` call per repo, parsed into a JSON list.
  # 404 (no branch protection) → empty list → every failing check classifies
  # as Advisory. See specs/181-digest-classify-flow.md.
  REQUIRED_SET_JSON=$(gh api "repos/$B_REPO/branches/main/protection" 2>/dev/null \
    | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(json.dumps(data.get('required_status_checks', {}).get('contexts', []) or []))
except Exception:
    print('[]')
" 2>/dev/null)
  [ -z "$REQUIRED_SET_JSON" ] && REQUIRED_SET_JSON='[]'
  export REQUIRED_SET_JSON

  # Single gh call per repo: drives both CI-failure and WIP-limit checks.
  # If gh fails (auth, rate limit, network), record it so the digest can
  # name the upstream failure rather than silently posting "Blockers: 0".
  if PR_DATA=$(gh pr list --repo "$B_REPO" --state open \
      --json number,title,headRefName,statusCheckRollup 2>/dev/null); then
    # Each PR is classified once as blocker OR advisory. A PR with any
    # required-check failure routes to Blockers; a PR with only unrequired
    # failures routes to Advisories with neutral framing.
    while IFS='|' read -r KIND PR_NUM PR_TITLE CI_REASON; do
      [ -z "$KIND" ] && continue
      if [ "$KIND" = "blocker" ]; then
        BLOCKER_COUNT=$((BLOCKER_COUNT + 1))
        BLOCKER_LINES="${BLOCKER_LINES}\n- :red_circle: ${B_SHORT} blocked — PR #${PR_NUM} ${CI_REASON} failing"
      else
        ADVISORY_COUNT=$((ADVISORY_COUNT + 1))
        ADVISORY_LINES="${ADVISORY_LINES}\n- :warning: ${B_SHORT} — PR #${PR_NUM} ${CI_REASON} failing (not required by branch protection)"
      fi
    done < <(echo "$PR_DATA" | python3 -c "
import json, os, sys
required = set(json.loads(os.environ.get('REQUIRED_SET_JSON', '[]')))
for pr in json.load(sys.stdin):
    checks = pr.get('statusCheckRollup') or []
    failures = [c for c in checks if c.get('conclusion') == 'FAILURE' or c.get('state') == 'FAILURE']
    if not failures: continue
    blocking = [c for c in failures if (c.get('name') or '') in required]
    advisory_fails = [c for c in failures if (c.get('name') or '') not in required]
    if blocking:
        reason = blocking[0].get('name', 'unknown check')
        print(f'blocker|{pr[\"number\"]}|{pr[\"title\"]}|{reason}')
    elif advisory_fails:
        reason = advisory_fails[0].get('name', 'unknown check')
        print(f'advisory|{pr[\"number\"]}|{pr[\"title\"]}|{reason}')
" 2>/dev/null)

    # WIP limit: repo has 3+ open auto/ PRs
    OPEN_AUTO=$(echo "$PR_DATA" | python3 -c "
import json, sys
prs = json.load(sys.stdin)
print(sum(1 for p in prs if p.get('headRefName','').startswith('auto/')))
" 2>/dev/null || echo 0)
    if [ "$OPEN_AUTO" -ge 3 ]; then
      BLOCKER_COUNT=$((BLOCKER_COUNT + 1))
      BLOCKER_LINES="${BLOCKER_LINES}\n- :red_circle: ${B_SHORT} — WIP limit reached (${OPEN_AUTO} open auto/ PRs)"
    fi
  else
    GH_FAILED_COUNT=$((GH_FAILED_COUNT + 1))
    GH_FAILED_REPOS="${GH_FAILED_REPOS}${GH_FAILED_REPOS:+, }${B_SHORT}"
  fi
done

# Build failures from failure tracker. Self-heals: if the issue is now closed,
# the digest skips the line and prunes the tracker entry so the next run is clean.
FAILURE_TRACKER="$SCRIPT_DIR/metrics/failure-tracker.json"
if [ -f "$FAILURE_TRACKER" ]; then
  STALE_KEYS=()
  while IFS='|' read -r ISSUE_KEY FAILURES; do
    [ -z "$ISSUE_KEY" ] && continue
    F_REPO="${ISSUE_KEY%#*}"
    F_NUM="${ISSUE_KEY##*#}"
    F_STATE=$(gh issue view "$F_NUM" --repo "$F_REPO" --json state -q '.state' 2>/dev/null || echo "OPEN")
    if [ "$F_STATE" = "CLOSED" ]; then
      STALE_KEYS+=("$ISSUE_KEY")
      continue
    fi
    BLOCKER_COUNT=$((BLOCKER_COUNT + 1))
    BLOCKER_LINES="${BLOCKER_LINES}\n- :red_circle: Build blocked: ${ISSUE_KEY} (${FAILURES}x consecutive failures)"
  done < <(python3 -c "
import json
data = json.load(open('$FAILURE_TRACKER'))
for key, val in data.items():
    if val.get('blocked'):
        print(f'{key}|{val[\"failures\"]}')
" 2>/dev/null || true)

  if [ ${#STALE_KEYS[@]} -gt 0 ]; then
    jq --args 'reduce $ARGS.positional[] as $k (.; del(.[$k]))' \
      "$FAILURE_TRACKER" "${STALE_KEYS[@]}" > "${FAILURE_TRACKER}.tmp" \
      && mv "${FAILURE_TRACKER}.tmp" "$FAILURE_TRACKER"
  fi
fi

# ── BUILD DIGEST ───────────────────────────────────────────────────────────

# Top 5 Pitch+Scope items, oldest first
STUCK=$(echo "$ALL_ITEMS" | python3 -c "
import json, sys
items = []
for item in json.load(sys.stdin).get('items', []):
    status = item.get('status','')
    if status not in ('Pitch','Scope'): continue
    c = item.get('content', {})
    r, n, title = c.get('repository',''), c.get('number',''), item.get('title','')
    created = c.get('createdAt','')
    if r and n: items.append((created, r, str(n), title, status))
items.sort()  # oldest first
for created, r, n, title, status in items[:5]:
    print(f'{created}|{r}|{n}|{title}|{status}')
" 2>/dev/null || true)

DECISIONS=""
while IFS='|' read -r CREATED_AT REPO ISSUE_NUM TITLE STATUS; do
  [ -z "$REPO" ] && continue
  ACTUAL_CREATED=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json createdAt -q '.createdAt' 2>/dev/null || echo "")
  DAYS=$(python3 -c "from datetime import datetime, timezone; d=datetime.fromisoformat('$ACTUAL_CREATED'.replace('Z','+00:00')); print((datetime.now(timezone.utc)-d).days)" 2>/dev/null || echo "?")

  SHORT="${REPO#getqatalyst/}"
  DECISIONS="${DECISIONS}**[${SHORT} #${ISSUE_NUM}](https://github.com/${REPO}/issues/${ISSUE_NUM}) — ${TITLE}** (${DAYS} days in ${STATUS})\n\n"
done <<< "$STUCK"

[ -z "$DECISIONS" ] && DECISIONS="_No items in Pitch or Scope._\n"

READY_FEED=$(echo "$ALL_ITEMS" | python3 -c "
import json, sys
items = []
for item in json.load(sys.stdin).get('items', []):
    if item.get('status') != 'Ready': continue
    c = item.get('content', {})
    r, n, title = c.get('repository',''), c.get('number',''), item.get('title','')
    if r and n:
        items.append(f'- [{r.replace(\"getqatalyst/\",\"\")} #{n}](https://github.com/{r}/issues/{n}) {title}')
print('\n'.join(items) if items else '_No items in Ready._')
" 2>/dev/null || echo "_No items in Ready._")

READY_COUNT=$(echo "$READY_FEED" | grep -c "^-" 2>/dev/null || echo 0)
AUTO_SECTION="${AUTO_LOG:-_None this run._}"

VERIFY_SECTION=$([ "$VERIFY_COUNT" -eq 0 ] && echo "_None in Verify._" || printf '%b' "$VERIFY_LOG")

BLOCKER_SECTION=""
if [ "$GH_FAILED_COUNT" -gt 0 ]; then
  # Without this, a failing `gh pr list` collapses every repo to zero
  # blockers and the digest looks indistinguishable from a clean day.
  BLOCKER_SECTION="## Blockers: ${BLOCKER_COUNT} (scan unreliable)
:warning: **Blocker scan unreliable** — \`gh pr list\` failed for ${GH_FAILED_REPOS}. Run \`gh auth status\` and check rate limit, then rerun pipeline-digest.
$(printf '%b' "$BLOCKER_LINES")

"
elif [ "$BLOCKER_COUNT" -gt 0 ]; then
  BLOCKER_SECTION="## Blockers: ${BLOCKER_COUNT}
$(printf '%b' "$BLOCKER_LINES")

"
else
  BLOCKER_SECTION="## Blockers: 0

"
fi

ADVISORY_SECTION=""
if [ "$ADVISORY_COUNT" -gt 0 ]; then
  ADVISORY_SECTION="## Advisories: ${ADVISORY_COUNT}
$(printf '%b' "$ADVISORY_LINES")

"
fi

# Auto-declined: items Foreman cleanly declined to build (wrote `.decline-reason.md`).
# Surfaced separately so they aren't conflated with verification work. Zero-suppressed.
AUTO_DECLINED_SECTION=""
if [ "$AUTO_DECLINED_COUNT" -gt 0 ]; then
  AUTO_DECLINED_SECTION="## Auto-declined: ${AUTO_DECLINED_COUNT}
$(printf '%b' "$AUTO_DECLINED_LOG")

"
fi

DIGEST="${BLOCKER_SECTION}${ADVISORY_SECTION}${AUTO_DECLINED_SECTION}## Decisions Needed (top 5 stuck items)

$(printf '%b' "$DECISIONS")
## Awaiting Verification: ${VERIFY_COUNT}
${VERIFY_SECTION}

## Auto-completed this run
$(printf '%b' "$AUTO_SECTION")

## Foreman Feed: ${READY_COUNT} items in Ready
$READY_FEED"

# Ensure label exists
gh label create pipeline-digest --repo getqatalyst/foreman --color "#5319e7" \
  --description "Daily Sarge digest" 2>/dev/null || true

ISSUE_URL=$(gh issue create \
  --repo getqatalyst/foreman \
  --title "Pipeline Digest — $DATE" \
  --label pipeline-digest \
  --body "$DIGEST" 2>&1) || { echo "PIPELINE-DIGEST: Failed to create issue" >> "$LOG"; ISSUE_URL=""; }
echo "$ISSUE_URL" >> "$LOG"

# ── SLACK NOTIFICATION ──────────────────────────────────────────────────
if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
  # Count stuck items in Pitch >7 days
  STUCK_COUNT=$(echo "$ALL_ITEMS" | python3 -c "
from datetime import datetime, timezone, timedelta
import json, sys
count = 0
cutoff = datetime.now(timezone.utc) - timedelta(days=7)
for item in json.load(sys.stdin).get('items', []):
    if item.get('status') != 'Pitch': continue
    created = item.get('content', {}).get('createdAt', '')
    if not created: continue
    try:
        d = datetime.fromisoformat(created.replace('Z', '+00:00'))
        if d < cutoff: count += 1
    except: pass
print(count)
" 2>/dev/null || echo "0")

  # Build Slack message lines
  SLACK_LINES=""
  if [ "$GH_FAILED_COUNT" -gt 0 ]; then
    SLACK_LINES=":warning: Blocker scan unreliable — \`gh pr list\` failed for ${GH_FAILED_REPOS}. Run \`gh auth status\` / check rate limit.
"
  fi
  if [ "$BLOCKER_COUNT" -gt 0 ]; then
    SLACK_LINES="${SLACK_LINES}$(printf '%b' "$BLOCKER_LINES" | sed 's/^- //' | head -3)"
    if [ "$BLOCKER_COUNT" -gt 3 ]; then
      SLACK_LINES="${SLACK_LINES}
+$((BLOCKER_COUNT - 3)) more blockers"
    fi
    SLACK_LINES="${SLACK_LINES}
"
  fi
  if [ "$GH_FAILED_COUNT" -gt 0 ]; then
    SLACK_LINES="${SLACK_LINES}📋 Ready: ${READY_COUNT} items waiting | Blockers: scan failed"
  else
    SLACK_LINES="${SLACK_LINES}📋 Ready: ${READY_COUNT} items waiting | ⏳ Stuck: ${STUCK_COUNT} items in Pitch >7 days"
  fi
  if [ -n "$ISSUE_URL" ]; then
    SLACK_LINES="${SLACK_LINES}
🔗 Full digest: ${ISSUE_URL}"
  fi

  # Prepend provenance banner
  if [ -n "${FOREMAN_BANNER:-}" ]; then
    SLACK_LINES="${FOREMAN_BANNER} ${SLACK_LINES}"
  fi

  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/lib/slack.sh"
  slack_post SLACK_WEBHOOK_URL "$SLACK_LINES"
  echo "PIPELINE-DIGEST: Slack notification sent" >> "$LOG"
else
  echo "PIPELINE-DIGEST: SLACK_WEBHOOK_URL not set, skipping Slack notification" >> "$LOG"
fi

osascript -e "display notification \"${READY_COUNT} ready, ${BLOCKER_COUNT} blockers, ${AUTO_COUNT} auto-actions\" with title \"Foreman ${FOREMAN_BANNER:-}\" subtitle \"$DATE\" sound name \"Glass\"" 2>/dev/null || true

touch "$SENTINEL"
echo "PIPELINE-DIGEST: auto=$AUTO_COUNT ready=$READY_COUNT blockers=$BLOCKER_COUNT" >> "$LOG"
echo "digest_posted=1 auto=$AUTO_COUNT ready=$READY_COUNT blockers=$BLOCKER_COUNT"
