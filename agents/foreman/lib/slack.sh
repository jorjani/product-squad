#!/bin/bash
# Slack POST helper.
#
# Single source of truth for the python3 + urllib.request mechanics that
# every Foreman Slack post used to inline (cycle-summary, stall,
# pipeline-digest, heartbeat). Adding a 4th copy would be wrong.
#
# slack_post <webhook-var-name> <text>
#   - Reads the webhook URL from the env var named <webhook-var-name>.
#     Pass the NAME, not the value (e.g. `slack_post SLACK_CI_WEBHOOK_URL "$text"`),
#     so we no-op cleanly when the var is unset rather than POSTing to an
#     empty URL.
#   - Silently no-ops if the var is unset/empty or text is empty.
#   - Failures never block — Slack outages must not propagate into the orchestrator.
#   - Bash 3.2 compatible (uses ${!var} indirect expansion, no associative arrays).
#
# fire_heartbeat <message>
#   - Posts to SLACK_HEARTBEAT_WEBHOOK_URL, prefixed with FOREMAN_BANNER.
#   - Used by orchestrator.sh for FIRE START / FIRE END / FIRE ABORT posts
#     so a wedged or aborted fire is visible as a missing-pair gap in Slack
#     within ~3h instead of >24h.

slack_post() {
  local var_name="$1"
  local text="$2"
  local url="${!var_name:-}"
  [ -z "$url" ] && return 0
  [ -z "$text" ] && return 0
  echo "$text" | SLACK_URL="$url" python3 -c "
import json, os, sys, urllib.request
text = sys.stdin.read()
url = os.environ['SLACK_URL']
payload = json.dumps({'text': text}).encode()
req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'})
try:
    urllib.request.urlopen(req, timeout=10)
except Exception as e:
    print(f'slack post failed: {e}', file=sys.stderr)
" 2>/dev/null || true
}

fire_heartbeat() {
  local message="$1"
  local text="${FOREMAN_BANNER:-} $message"
  slack_post SLACK_HEARTBEAT_WEBHOOK_URL "$text"
}
