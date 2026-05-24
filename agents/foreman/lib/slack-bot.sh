#!/bin/bash
# Slack bot API helpers (chat.postMessage + conversations.replies).
#
# Distinct from lib/slack.sh, which speaks the incoming-webhook protocol
# (fire-and-forget, no return value, no thread_ts capture). The questions
# pipeline needs the bot API so it can:
#   - read the returned ts from chat.postMessage (to anchor the question thread)
#   - poll conversations.replies (to read David's free-text replies)
#
# DARK-by-default: every function silently no-ops when SLACK_BOT_TOKEN is
# unset (the activation env var). The wider feature uses
# SLACK_QUESTIONS_CHANNEL_ID for the destination channel; that env var is
# checked here too so a half-configured token cannot post to a wrong channel.
#
# Failures (network, auth) are non-fatal — same posture as lib/slack.sh —
# so a Slack outage never blocks a Foreman fire.

# slack_bot_enabled — echoes 1 when both required envs are set, else 0.
# Callers should branch on this rather than testing the envs themselves;
# centralising the check keeps the "DARK until both envs exist" gate uniform.
slack_bot_enabled() {
  if [ -n "${SLACK_BOT_TOKEN:-}" ] && [ -n "${SLACK_QUESTIONS_CHANNEL_ID:-}" ]; then
    echo 1
  else
    echo 0
  fi
}

# slack_bot_post_message TEXT [THREAD_TS]
#   Posts TEXT to SLACK_QUESTIONS_CHANNEL_ID via chat.postMessage.
#   Echoes the message ts on success (caller captures for thread anchoring).
#   Echoes the empty string + logs to stderr on any failure or DARK skip.
#   THREAD_TS optional — when provided, the message is posted as a reply in
#   that thread (used to confirm "Got it — doing X" back to David).
slack_bot_post_message() {
  local text="$1"
  local thread_ts="${2:-}"

  [ "$(slack_bot_enabled)" -eq 1 ] || { echo ""; return 0; }
  [ -z "$text" ] && { echo ""; return 0; }

  SLACK_TEXT="$text" SLACK_THREAD_TS="$thread_ts" python3 -c "
import json, os, sys, urllib.request, urllib.error
token = os.environ['SLACK_BOT_TOKEN']
channel = os.environ['SLACK_QUESTIONS_CHANNEL_ID']
text = os.environ['SLACK_TEXT']
thread_ts = os.environ.get('SLACK_THREAD_TS') or ''
payload = {'channel': channel, 'text': text, 'unfurl_links': False, 'unfurl_media': False}
if thread_ts:
    payload['thread_ts'] = thread_ts
data = json.dumps(payload).encode()
req = urllib.request.Request(
    'https://slack.com/api/chat.postMessage',
    data=data,
    headers={
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': f'Bearer {token}',
    },
)
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = json.loads(resp.read().decode())
    if not body.get('ok'):
        print(f'slack_bot_post_message: api error: {body.get(\"error\",\"unknown\")}', file=sys.stderr)
        sys.exit(0)
    print(body.get('ts', ''))
except urllib.error.URLError as e:
    print(f'slack_bot_post_message: network error: {e}', file=sys.stderr)
except Exception as e:
    print(f'slack_bot_post_message: unexpected: {e}', file=sys.stderr)
" 2>/dev/null || echo ""
}

# slack_bot_get_thread_replies THREAD_TS
#   Echoes a JSON array of reply objects {user, ts, text} excluding the
#   parent message (i.e. the question itself). Empty array on DARK / no
#   replies / any failure. Caller is responsible for filtering to "new
#   since last seen" using the ts cursor stored in state.
slack_bot_get_thread_replies() {
  local thread_ts="$1"

  [ "$(slack_bot_enabled)" -eq 1 ] || { echo "[]"; return 0; }
  [ -z "$thread_ts" ] && { echo "[]"; return 0; }

  SLACK_THREAD_TS="$thread_ts" python3 -c "
import json, os, sys, urllib.request, urllib.error, urllib.parse
token = os.environ['SLACK_BOT_TOKEN']
channel = os.environ['SLACK_QUESTIONS_CHANNEL_ID']
ts = os.environ['SLACK_THREAD_TS']
qs = urllib.parse.urlencode({'channel': channel, 'ts': ts, 'limit': '50'})
req = urllib.request.Request(
    f'https://slack.com/api/conversations.replies?{qs}',
    headers={'Authorization': f'Bearer {token}'},
)
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = json.loads(resp.read().decode())
    if not body.get('ok'):
        print('[]')
        print(f'slack_bot_get_thread_replies: api error: {body.get(\"error\",\"unknown\")}', file=sys.stderr)
        sys.exit(0)
    messages = body.get('messages', []) or []
    # Drop the parent: conversations.replies returns the parent first, with
    # ts == thread_ts. The questions-bot never wants to interpret its own
    # question as a reply.
    out = []
    for m in messages:
        if m.get('ts') == ts:
            continue
        # Skip bot/automation messages — we only want David's free text.
        # The bot's own confirmation posts ('Got it — doing X') would otherwise
        # be reinterpreted as a fresh reply on the next poll.
        if m.get('bot_id') or m.get('subtype'):
            continue
        out.append({
            'user': m.get('user', ''),
            'ts': m.get('ts', ''),
            'text': m.get('text', ''),
        })
    print(json.dumps(out))
except urllib.error.URLError as e:
    print('[]')
    print(f'slack_bot_get_thread_replies: network error: {e}', file=sys.stderr)
except Exception as e:
    print('[]')
    print(f'slack_bot_get_thread_replies: unexpected: {e}', file=sys.stderr)
" 2>/dev/null || echo "[]"
}
