#!/bin/bash
# Foreman product-decision questions: post to Slack, read replies, act.
#
# This is the public API surface for the "push product-framed decision
# questions to David in Slack and feed his replies back to the pipeline"
# feature. State lives in foreman/state/questions.json (durable across
# fires, gitignored). Every public function is a silent no-op when
# SLACK_BOT_TOKEN / SLACK_QUESTIONS_CHANNEL_ID are unset — see DARK note in
# the README and the gate in lib/slack-bot.sh.
#
# Lifecycle per question:
#   1. An emitter calls questions_register with whatever it knows.
#   2. End-of-fire calls questions_post_new — for each pending entry it
#      translates the engineering signal into a product question (if the
#      emitter didn't already do so at source) and posts to Slack. The
#      returned thread ts is stored so we can re-find the thread later.
#   3. Start-of-fire (next run, or any run after) calls
#      questions_poll_replies — for each posted-not-resolved entry it reads
#      new thread replies, interprets each via LLM, posts a comment to the
#      GitHub issue, confirms in-thread, and marks the question resolved.
#   4. fire_exit_trap calls questions_waiting_line for the heartbeat ("N
#      still waiting, oldest Xd").
#
# Dedup model (D3 — post once):
#   The state key is `<source>:<repo>:<num>` — unique per logical signal
#   per issue. If a question for that key already exists in `pending` or
#   `posted` state, re-registering is a silent no-op (the original
#   question persists; nothing re-posts). If the prior question for that
#   key was `resolved`, a fresh register replaces it — David has answered
#   the old one, a new fire of the same signal is a new question.
#
# Bash 3.2 compatible (macOS default). No associative arrays, no
# process-substitution-only patterns. All state mutation goes through a
# python3 helper so JSON edits are atomic-ish (tmp + mv) and concurrent
# fires never half-write the file. The orchestrator lock already serialises
# fires; this is belt-and-suspenders.

# Callers must source these first (parallel to other lib/* files).
QUESTIONS_SCRIPT_DIR="${QUESTIONS_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
QUESTIONS_STATE_FILE="${QUESTIONS_STATE_FILE:-$QUESTIONS_SCRIPT_DIR/state/questions.json}"
QUESTIONS_PROMPTS_DIR="${QUESTIONS_PROMPTS_DIR:-$QUESTIONS_SCRIPT_DIR/prompts}"
QUESTIONS_RESULTS_DIR="${QUESTIONS_RESULTS_DIR:-$QUESTIONS_SCRIPT_DIR/results}"

# Notify mode (D1): controls *when* questions_post_new actually posts.
#   per-fire  (default): post on every fire that has new pending questions.
#   2x-daily: post at most twice per day, gated by a sentinel file. Cadence
#             can switch with a single env / config edit, no code change.
QUESTIONS_NOTIFY_MODE="${QUESTION_NOTIFY_MODE:-per-fire}"

# Translate prompt budgets — small caps because the prompt is short and we
# call once per pending-without-source-reframe question. Sonnet is overkill;
# Haiku is fine here. Same with reply interpretation.
QUESTIONS_TRANSLATE_MODEL="${QUESTIONS_TRANSLATE_MODEL:-haiku}"
QUESTIONS_TRANSLATE_BUDGET="${QUESTIONS_TRANSLATE_BUDGET:-0.25}"
QUESTIONS_INTERPRET_MODEL="${QUESTIONS_INTERPRET_MODEL:-haiku}"
QUESTIONS_INTERPRET_BUDGET="${QUESTIONS_INTERPRET_BUDGET:-0.25}"

# Per-call wall-clock bound on the LLM steps. lib/bounded.sh's run_bounded
# pattern (post-2026-05 unbounded-claude fixes) — every claude invocation
# must be bounded or a wedged stream can stall the orchestrator.
QUESTIONS_LLM_TIMEOUT="${QUESTIONS_LLM_TIMEOUT:-120}"

# _questions_ensure_state_file — create state/ + empty JSON if absent.
# Idempotent. Returns non-zero only on mkdir/write failure.
_questions_ensure_state_file() {
  local dir
  dir="$(dirname "$QUESTIONS_STATE_FILE")"
  mkdir -p "$dir" || return 1
  if [ ! -f "$QUESTIONS_STATE_FILE" ]; then
    printf '{"questions":{},"last_poll_at":null}\n' > "$QUESTIONS_STATE_FILE" || return 1
  fi
  return 0
}

# _questions_mutate_state PY_FRAGMENT
#   Loads the state JSON into a Python dict named `state`, runs the supplied
#   Python fragment (which may mutate `state`), then writes back atomically
#   via tmp + rename. The fragment can read env vars to receive arguments.
#   Echoes whatever the fragment prints (so callers can capture e.g. the
#   thread_ts of a freshly posted question).
_questions_mutate_state() {
  local fragment="$1"
  _questions_ensure_state_file || return 1

  STATE_FILE="$QUESTIONS_STATE_FILE" FRAGMENT="$fragment" python3 <<'PY'
import json, os, sys, tempfile

path = os.environ['STATE_FILE']
fragment = os.environ['FRAGMENT']

try:
    with open(path) as f:
        state = json.load(f)
except Exception:
    state = {'questions': {}, 'last_poll_at': None}

# Normalise schema in case the file was hand-edited.
state.setdefault('questions', {})
state.setdefault('last_poll_at', None)

# Execute the caller's fragment with `state` in scope. Output captured via
# print() in the fragment propagates back through this subprocess's stdout.
exec(fragment, {'state': state, 'os': os, 'json': json, 'sys': sys})

# Atomic write: tmp file in the same dir, fsync, rename.
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or '.', prefix='.questions.', suffix='.json')
try:
    with os.fdopen(fd, 'w') as f:
        json.dump(state, f, indent=2, sort_keys=True)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
except Exception:
    try:
        os.unlink(tmp)
    except Exception:
        pass
    raise
PY
}

# _questions_read_state — echoes the raw state JSON.
_questions_read_state() {
  _questions_ensure_state_file || return 1
  cat "$QUESTIONS_STATE_FILE"
}

# questions_register SOURCE REPO ISSUE_NUM RAW_SIGNAL [QUESTION] [CONTEXT] [OPTIONS_JSON] [PR_NUM]
#
# Upsert a pending question.
#
#   SOURCE        — emitter id (e.g. "build-failed-3x", "sarge-review-decision",
#                   "code-review-ac-mismatch"). Used in the dedup key.
#   REPO          — getqatalyst/<repo>
#   ISSUE_NUM     — GitHub issue number
#   RAW_SIGNAL    — engineering text Foreman would otherwise post on GitHub.
#                   Kept verbatim in state so a later translate call has
#                   the full signal to work with.
#   QUESTION      — optional product-framed one-line question. If non-empty,
#                   the LLM translate step is skipped (D4 source-reframe).
#   CONTEXT       — optional 2-3 lines of why/what's at stake (used with QUESTION).
#   OPTIONS_JSON  — optional JSON array of option strings (used with QUESTION).
#   PR_NUM        — optional related PR number (rendered as a link in the
#                   Slack message). Pass "" to omit.
#
# DARK skip: if SLACK_BOT_TOKEN/SLACK_QUESTIONS_CHANNEL_ID are unset, the
# call returns 0 without touching state. We don't want a half-built state
# file accumulating questions that will never be posted, and the post-once
# guarantee depends on the file reflecting what got posted, not what would
# have been.
questions_register() {
  # shellcheck disable=SC1091
  . "$QUESTIONS_SCRIPT_DIR/lib/slack-bot.sh"
  [ "$(slack_bot_enabled)" -eq 1 ] || return 0

  local source="$1"
  local repo="$2"
  local issue_num="$3"
  local raw_signal="$4"
  local question="${5:-}"
  local context="${6:-}"
  local options_json="${7:-[]}"
  local pr_num="${8:-}"

  [ -z "$source" ] || [ -z "$repo" ] || [ -z "$issue_num" ] && return 0

  Q_SOURCE="$source" Q_REPO="$repo" Q_NUM="$issue_num" Q_PR="$pr_num" \
  Q_RAW="$raw_signal" Q_QUESTION="$question" Q_CONTEXT="$context" \
  Q_OPTIONS="$options_json" \
  _questions_mutate_state "
import datetime
key = f'{os.environ[\"Q_SOURCE\"]}:{os.environ[\"Q_REPO\"]}:{os.environ[\"Q_NUM\"]}'
existing = state['questions'].get(key)
# Dedup: if a question for this key is already pending or posted (i.e. not
# yet resolved), the same emitter firing again is the *same* logical signal.
# Drop the new registration; the original entry persists so the same
# thread keeps accumulating context.
if existing and existing.get('status') in ('pending', 'posted'):
    sys.exit(0)
try:
    opts = json.loads(os.environ.get('Q_OPTIONS') or '[]')
    if not isinstance(opts, list):
        opts = []
except Exception:
    opts = []
state['questions'][key] = {
    'id': key,
    'source': os.environ['Q_SOURCE'],
    'repo': os.environ['Q_REPO'],
    'issue_num': int(os.environ['Q_NUM']),
    'pr_num': int(os.environ['Q_PR']) if os.environ.get('Q_PR') else None,
    'raw_signal': os.environ.get('Q_RAW', ''),
    'question': os.environ.get('Q_QUESTION', ''),
    'context': os.environ.get('Q_CONTEXT', ''),
    'options': opts,
    'created_at': datetime.datetime.utcnow().isoformat() + 'Z',
    'posted_at': None,
    'thread_ts': None,
    'last_reply_ts': None,
    'status': 'pending',
    'resolved_at': None,
    'resolution': None,
}
"
}

# _questions_translate_one KEY — runs the question-translate prompt for one
# pending entry that has no source-reframed question yet. Echoes a JSON
# object {question, context, options} on success, empty string on failure.
# Uses run_bounded so a wedged claude can't stall the post phase.
_questions_translate_one() {
  local key="$1"
  # shellcheck disable=SC1091
  . "$QUESTIONS_SCRIPT_DIR/lib/bounded.sh"

  local entry source repo num title body_excerpt raw prompt_file
  entry=$(_questions_read_state | KEY="$key" python3 -c '
import json, os, sys
state = json.load(sys.stdin)
print(json.dumps(state["questions"].get(os.environ["KEY"], {})))
' 2>/dev/null)
  [ -z "$entry" ] || [ "$entry" = "{}" ] && { echo ""; return 0; }

  source=$(printf '%s' "$entry" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("source",""))')
  repo=$(printf '%s' "$entry" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("repo",""))')
  num=$(printf '%s' "$entry" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("issue_num",""))')
  raw=$(printf '%s' "$entry" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("raw_signal",""))')

  # Issue context. Fetch fresh — the body may have been enriched since the
  # emitter fired. Trim to 1500 chars so the prompt stays compact.
  title=$(gh issue view "$num" --repo "$repo" --json title -q '.title' 2>/dev/null || echo "")
  body_excerpt=$(gh issue view "$num" --repo "$repo" --json body -q '.body' 2>/dev/null \
    | head -c 1500 || echo "")

  prompt_file=$(mktemp)
  {
    cat "$QUESTIONS_PROMPTS_DIR/question-translate.md"
    printf '\n\n## Input\n\n```json\n'
    Q_SOURCE="$source" Q_REPO="$repo" Q_NUM="$num" Q_TITLE="$title" \
    Q_BODY="$body_excerpt" Q_RAW="$raw" python3 -c '
import json, os
print(json.dumps({
    "signal_source": os.environ["Q_SOURCE"],
    "repo": os.environ["Q_REPO"],
    "issue_num": int(os.environ["Q_NUM"]),
    "issue_title": os.environ["Q_TITLE"],
    "issue_body_excerpt": os.environ["Q_BODY"],
    "raw_signal": os.environ["Q_RAW"],
}, indent=2))
'
    printf '\n```\n'
  } > "$prompt_file"

  run_bounded "$QUESTIONS_LLM_TIMEOUT" claude -p "$(cat "$prompt_file")" \
    --model "$QUESTIONS_TRANSLATE_MODEL" \
    --max-budget-usd "$QUESTIONS_TRANSLATE_BUDGET" \
    --dangerously-skip-permissions
  rm -f "$prompt_file"

  if [ "${PROBE_EXIT:-1}" -ne 0 ]; then
    echo ""
    return 0
  fi

  # Extract first balanced JSON object containing a "question" key. The
  # prompt forbids fences and prose; this is the belt-and-suspenders parse.
  printf '%s' "$PROBE_OUT" | python3 -c '
import json, re, sys
text = sys.stdin.read()
m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
if m:
    text = m.group(1)
candidates = []
depth = 0
start = -1
for i, ch in enumerate(text):
    if ch == "{":
        if depth == 0:
            start = i
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0 and start >= 0:
            candidates.append(text[start:i+1])
            start = -1
for c in reversed(candidates):
    if "\"question\"" in c:
        try:
            d = json.loads(c)
            print(json.dumps({
                "question": str(d.get("question", "")).strip(),
                "context": str(d.get("context", "")).strip(),
                "options": d.get("options") if isinstance(d.get("options"), list) else [],
            }))
            sys.exit(0)
        except Exception:
            continue
print("")
' 2>/dev/null || echo ""
}

# _questions_render_message KEY — echoes the formatted Slack text for a
# pending or just-translated entry. Reads state directly so the caller
# doesn't have to thread the entry through.
_questions_render_message() {
  local key="$1"
  _questions_read_state | KEY="$key" python3 -c '
import json, os, sys
state = json.load(sys.stdin)
e = state["questions"].get(os.environ["KEY"])
if not e:
    sys.exit(0)
repo = e.get("repo", "")
num = e.get("issue_num", "")
pr = e.get("pr_num")
issue_url = f"https://github.com/{repo}/issues/{num}"
question = (e.get("question") or "").strip() or "(question pending translation)"
context = (e.get("context") or "").strip()
options = e.get("options") or []

lines = [f"*{question}*"]
if context:
    lines.append(context)
lines.append("")
# Direct links — issue always, PR when present.
lines.append(f"<{issue_url}|{repo}#{num}>")
if pr:
    lines.append(f"<https://github.com/{repo}/pull/{pr}|PR #{pr}>")
if options:
    lines.append("")
    lines.append("_Options:_")
    for opt in options[:3]:
        lines.append(f"• {opt}")
lines.append("")
lines.append("_Reply in this thread — Foreman will read your answer next fire._")
print("\n".join(lines))
'
}

# _questions_should_post_now — gate for D1 (cadence). Echoes 1 (post) or 0 (skip).
# per-fire: always 1.
# 2x-daily: 1 at most twice per UTC day, recorded via a state-resident counter.
_questions_should_post_now() {
  case "$QUESTIONS_NOTIFY_MODE" in
    per-fire) echo 1 ;;
    2x-daily)
      _questions_read_state | python3 -c '
import datetime, json, os, sys
state = json.load(sys.stdin)
today = datetime.datetime.utcnow().strftime("%Y-%m-%d")
day = state.get("notify_day", "")
count = int(state.get("notify_count_today", 0)) if day == today else 0
print(1 if count < 2 else 0)
' 2>/dev/null || echo 1
      ;;
    *)
      echo 1
      ;;
  esac
}

# _questions_record_post — increment the 2x-daily counter after a successful
# post. No-op for per-fire mode (no counter to keep).
_questions_record_post() {
  [ "$QUESTIONS_NOTIFY_MODE" = "2x-daily" ] || return 0
  _questions_mutate_state '
import datetime
today = datetime.datetime.utcnow().strftime("%Y-%m-%d")
if state.get("notify_day") != today:
    state["notify_day"] = today
    state["notify_count_today"] = 0
state["notify_count_today"] = int(state.get("notify_count_today", 0)) + 1
'
}

# questions_post_new — DARK no-op when unconfigured. Iterates pending
# entries, translates the ones without a source-reframed question, posts
# each as its own Slack message, records the returned thread ts.
questions_post_new() {
  # shellcheck disable=SC1091
  . "$QUESTIONS_SCRIPT_DIR/lib/slack-bot.sh"
  [ "$(slack_bot_enabled)" -eq 1 ] || return 0

  local should_post
  should_post=$(_questions_should_post_now)
  [ "$should_post" = "1" ] || return 0

  _questions_ensure_state_file || return 0

  local pending_keys key entry has_question text ts
  pending_keys=$(_questions_read_state | python3 -c '
import json, sys
state = json.load(sys.stdin)
for k, v in state.get("questions", {}).items():
    if v.get("status") == "pending":
        print(k)
' 2>/dev/null || true)

  [ -z "$pending_keys" ] && return 0

  local posted=0
  while IFS= read -r key; do
    [ -z "$key" ] && continue

    has_question=$(_questions_read_state | KEY="$key" python3 -c '
import json, os, sys
state = json.load(sys.stdin)
e = state["questions"].get(os.environ["KEY"], {})
print("1" if (e.get("question") or "").strip() else "0")
' 2>/dev/null)

    if [ "$has_question" != "1" ]; then
      local translated
      translated=$(_questions_translate_one "$key")
      if [ -n "$translated" ]; then
        KEY="$key" TRANS="$translated" _questions_mutate_state '
import json, os
e = state["questions"].get(os.environ["KEY"])
if e:
    t = json.loads(os.environ["TRANS"])
    e["question"] = t.get("question", "")
    e["context"] = t.get("context", "")
    if isinstance(t.get("options"), list):
        e["options"] = t["options"]
'
      else
        # Translation failed and we have no source-framed question.
        # Skip this round; the entry stays pending and we try again next fire.
        echo "[questions] translate failed for $key — leaving pending" >&2
        continue
      fi
    fi

    text=$(_questions_render_message "$key")
    [ -z "$text" ] && continue

    ts=$(slack_bot_post_message "$text")
    if [ -z "$ts" ]; then
      echo "[questions] post failed for $key — leaving pending" >&2
      continue
    fi

    KEY="$key" TS="$ts" _questions_mutate_state '
import datetime
e = state["questions"].get(os.environ["KEY"])
if e:
    e["status"] = "posted"
    e["thread_ts"] = os.environ["TS"]
    e["posted_at"] = datetime.datetime.utcnow().isoformat() + "Z"
'
    _questions_record_post
    posted=$((posted + 1))
  done <<< "$pending_keys"

  echo "[questions] posted=$posted"
}

# _questions_interpret_one KEY REPLY_TEXT — runs the reply-interpret prompt
# for a single reply. Echoes JSON {action_summary, github_comment, confidence}
# on success, empty string on failure.
_questions_interpret_one() {
  local key="$1" reply_text="$2"
  # shellcheck disable=SC1091
  . "$QUESTIONS_SCRIPT_DIR/lib/bounded.sh"

  local entry prompt_file
  entry=$(_questions_read_state | KEY="$key" python3 -c '
import json, os, sys
state = json.load(sys.stdin)
print(json.dumps(state["questions"].get(os.environ["KEY"], {})))
' 2>/dev/null)
  [ -z "$entry" ] || [ "$entry" = "{}" ] && { echo ""; return 0; }

  prompt_file=$(mktemp)
  {
    cat "$QUESTIONS_PROMPTS_DIR/reply-interpret.md"
    printf '\n\n## Input\n\n```json\n'
    ENTRY="$entry" REPLY="$reply_text" python3 -c '
import json, os
e = json.loads(os.environ["ENTRY"])
print(json.dumps({
    "question": e.get("question", ""),
    "context": e.get("context", ""),
    "options": e.get("options", []) or [],
    "repo": e.get("repo", ""),
    "issue_num": e.get("issue_num", ""),
    "reply_text": os.environ["REPLY"],
}, indent=2))
'
    printf '\n```\n'
  } > "$prompt_file"

  run_bounded "$QUESTIONS_LLM_TIMEOUT" claude -p "$(cat "$prompt_file")" \
    --model "$QUESTIONS_INTERPRET_MODEL" \
    --max-budget-usd "$QUESTIONS_INTERPRET_BUDGET" \
    --dangerously-skip-permissions
  rm -f "$prompt_file"

  if [ "${PROBE_EXIT:-1}" -ne 0 ]; then
    echo ""
    return 0
  fi

  printf '%s' "$PROBE_OUT" | python3 -c '
import json, re, sys
text = sys.stdin.read()
m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
if m:
    text = m.group(1)
candidates = []
depth = 0
start = -1
for i, ch in enumerate(text):
    if ch == "{":
        if depth == 0:
            start = i
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0 and start >= 0:
            candidates.append(text[start:i+1])
            start = -1
for c in reversed(candidates):
    if "\"github_comment\"" in c:
        try:
            d = json.loads(c)
            print(json.dumps({
                "action_summary": str(d.get("action_summary", "")).strip()[:200],
                "github_comment": str(d.get("github_comment", "")).strip()[:1500],
                "confidence": str(d.get("confidence", "medium")).strip().lower(),
            }))
            sys.exit(0)
        except Exception:
            continue
print("")
' 2>/dev/null || echo ""
}

# questions_poll_replies — DARK no-op when unconfigured. For every posted
# entry whose thread has new replies since `last_reply_ts`, interpret the
# newest reply, post a comment to the GitHub issue, confirm in the thread,
# and mark the question resolved.
#
# We process the *newest* reply only, even if multiple unseen ones exist.
# Rationale: if David said "no wait, actually do X instead" after his first
# message, the latter is the binding decision. The earlier messages still
# remain in the thread for human re-read.
questions_poll_replies() {
  # shellcheck disable=SC1091
  . "$QUESTIONS_SCRIPT_DIR/lib/slack-bot.sh"
  [ "$(slack_bot_enabled)" -eq 1 ] || return 0

  _questions_ensure_state_file || return 0

  local posted_keys key ts last_seen replies new_reply reply_text reply_ts interp
  posted_keys=$(_questions_read_state | python3 -c '
import json, sys
state = json.load(sys.stdin)
for k, v in state.get("questions", {}).items():
    if v.get("status") == "posted" and v.get("thread_ts"):
        print(k)
' 2>/dev/null || true)

  [ -z "$posted_keys" ] && {
    _questions_mutate_state '
import datetime
state["last_poll_at"] = datetime.datetime.utcnow().isoformat() + "Z"
'
    return 0
  }

  local resolved=0
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    ts=$(_questions_read_state | KEY="$key" python3 -c '
import json, os, sys
state = json.load(sys.stdin)
print(state["questions"].get(os.environ["KEY"], {}).get("thread_ts", ""))
' 2>/dev/null)
    last_seen=$(_questions_read_state | KEY="$key" python3 -c '
import json, os, sys
state = json.load(sys.stdin)
print(state["questions"].get(os.environ["KEY"], {}).get("last_reply_ts") or "")
' 2>/dev/null)
    [ -z "$ts" ] && continue

    replies=$(slack_bot_get_thread_replies "$ts")
    new_reply=$(LAST="$last_seen" python3 -c '
import json, os, sys
replies = json.loads(sys.stdin.read() or "[]")
last = os.environ.get("LAST", "") or ""
# Take the latest reply newer than last_seen.
newer = [r for r in replies if (r.get("ts") or "") > last]
if not newer:
    sys.exit(0)
newer.sort(key=lambda r: r.get("ts") or "")
chosen = newer[-1]
print(json.dumps(chosen))
' <<< "$replies" 2>/dev/null)

    [ -z "$new_reply" ] && continue

    reply_text=$(printf '%s' "$new_reply" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("text",""))')
    reply_ts=$(printf '%s' "$new_reply" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("ts",""))')

    interp=$(_questions_interpret_one "$key" "$reply_text")
    if [ -z "$interp" ]; then
      echo "[questions] interpret failed for $key — leaving open, advancing cursor" >&2
      # Advance cursor so we don't re-attempt the same reply every fire.
      # The interpretation failure is logged; David can re-reply if needed.
      KEY="$key" REPLY_TS="$reply_ts" _questions_mutate_state '
e = state["questions"].get(os.environ["KEY"])
if e:
    e["last_reply_ts"] = os.environ["REPLY_TS"]
'
      continue
    fi

    local gh_comment action_summary confidence repo num
    gh_comment=$(printf '%s' "$interp" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("github_comment",""))')
    action_summary=$(printf '%s' "$interp" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("action_summary",""))')
    confidence=$(printf '%s' "$interp" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("confidence","medium"))')
    repo=$(_questions_read_state | KEY="$key" python3 -c '
import json, os, sys
state = json.load(sys.stdin)
print(state["questions"].get(os.environ["KEY"], {}).get("repo", ""))
')
    num=$(_questions_read_state | KEY="$key" python3 -c '
import json, os, sys
state = json.load(sys.stdin)
print(state["questions"].get(os.environ["KEY"], {}).get("issue_num", ""))
')

    if [ -n "$gh_comment" ] && [ -n "$repo" ] && [ -n "$num" ]; then
      # Post a banner so the GitHub thread shows where the decision came from.
      local full_body
      full_body="$gh_comment

_Decision relayed from Slack reply by @jorjani (confidence: $confidence)._"
      gh issue comment "$num" --repo "$repo" --body "$full_body" >/dev/null 2>&1 || \
        echo "[questions] gh issue comment failed for $repo#$num" >&2
    fi

    # Confirmation in-thread so David knows it landed AND can catch a misread.
    if [ -n "$action_summary" ]; then
      slack_bot_post_message "✅ Got it — $action_summary. Posted to $repo#$num. (confidence: $confidence)" "$ts" >/dev/null
    fi

    KEY="$key" REPLY_TS="$reply_ts" ACTION="$action_summary" CONF="$confidence" \
    _questions_mutate_state '
import datetime
e = state["questions"].get(os.environ["KEY"])
if e:
    e["status"] = "resolved"
    e["resolved_at"] = datetime.datetime.utcnow().isoformat() + "Z"
    e["last_reply_ts"] = os.environ["REPLY_TS"]
    e["resolution"] = {
        "action_summary": os.environ["ACTION"],
        "confidence": os.environ["CONF"],
    }
'
    resolved=$((resolved + 1))
  done <<< "$posted_keys"

  _questions_mutate_state '
import datetime
state["last_poll_at"] = datetime.datetime.utcnow().isoformat() + "Z"
'
  echo "[questions] resolved=$resolved"
}

# questions_waiting_line — echoes "N still waiting (oldest Xd)" or empty.
# Used by the fire heartbeat (D3 single low-noise line). Counts entries in
# status=posted (i.e. on Slack, unanswered). DARK no-op echoes empty.
questions_waiting_line() {
  # shellcheck disable=SC1091
  . "$QUESTIONS_SCRIPT_DIR/lib/slack-bot.sh"
  [ "$(slack_bot_enabled)" -eq 1 ] || { echo ""; return 0; }
  [ ! -f "$QUESTIONS_STATE_FILE" ] && { echo ""; return 0; }
  python3 -c '
import datetime, json, sys
try:
    state = json.load(open("'"$QUESTIONS_STATE_FILE"'"))
except Exception:
    sys.exit(0)
posted = [v for v in state.get("questions", {}).values() if v.get("status") == "posted"]
if not posted:
    sys.exit(0)
now = datetime.datetime.utcnow()
def age_days(v):
    ts = v.get("posted_at") or v.get("created_at") or ""
    try:
        d = datetime.datetime.fromisoformat(ts.replace("Z", ""))
        return max(0, (now - d).days)
    except Exception:
        return 0
oldest = max(age_days(v) for v in posted)
print(f"{len(posted)} still waiting (oldest {oldest}d)")
' 2>/dev/null || echo ""
}
