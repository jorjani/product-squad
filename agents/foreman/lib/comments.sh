#!/bin/bash
# Foreman automated-comment helpers.
#
# All phase scripts should use comment_dedup_or_escalate before posting any
# automated comment with a known prefix (BUILD-OVERSIZED, NEEDS-SPEC,
# SPEC-UPDATED, BUILD-FAILED, DECISION-NEEDED, etc).
#
# Why: previous failure modes generated identical noisy comments —
# sage#215 (11x BUILD-OVERSIZED across 3 days) and sage#187 (duplicate
# SPEC-UPDATED + duplicate NEEDS-SPEC pairs fired within minutes of
# each other). Dedup converts a mechanical-loop failure into a single
# human escalation, then stays quiet.

# Cached bot user login for the current script run. Populated lazily by
# comment_dedup on first successful `gh api user` call to avoid hitting
# the API on every comment attempt.
FOREMAN_BOT_USER_CACHE=""

# Post a comment, but skip if a recent bot comment is byte-identical.
#
# Usage:
#   comment_dedup REPO ISSUE_NUM BODY [SCAN_DEPTH]
#
# Returns:
#   0 — comment posted (new)
#   1 — skipped (duplicate detected)
#   2 — post failed (gh issue comment returned non-zero)
#
# SCAN_DEPTH: how many recent bot comments to compare against (default 5).
comment_dedup() {
  local repo="$1"
  local issue_num="$2"
  local body="$3"
  local scan_depth="${4:-5}"

  local bot_user="$FOREMAN_BOT_USER_CACHE"
  if [ -z "$bot_user" ]; then
    local gh_user_err
    gh_user_err=$(mktemp)
    bot_user=$(gh api user -q '.login' 2>"$gh_user_err")
    local gh_user_rc=$?
    if [ $gh_user_rc -ne 0 ] || [ -z "$bot_user" ]; then
      echo "[comment_dedup] WARNING: gh api user failed; dedup disabled for this call" >&2
      if [ -s "$gh_user_err" ]; then
        sed 's/^/[comment_dedup]   gh: /' "$gh_user_err" >&2
      fi
      rm -f "$gh_user_err"
      # Skip dedup, post comment directly. Return 0 on success, 2 on failure.
      local post_err
      post_err=$(mktemp)
      gh issue comment "$issue_num" --repo "$repo" --body "$body" 2>"$post_err"
      local post_rc=$?
      if [ $post_rc -ne 0 ]; then
        echo "[comment_dedup] ERROR: gh issue comment failed (rc=$post_rc)" >&2
        if [ -s "$post_err" ]; then
          sed 's/^/[comment_dedup]   gh: /' "$post_err" >&2
        fi
        rm -f "$post_err"
        return 2
      fi
      rm -f "$post_err"
      return 0
    fi
    rm -f "$gh_user_err"
    FOREMAN_BOT_USER_CACHE="$bot_user"
  fi

  local body_file
  body_file=$(mktemp)
  printf '%s' "$body" > "$body_file"

  local result
  result=$(gh issue view "$issue_num" --repo "$repo" --json comments 2>/dev/null | \
    BOT_USER="$bot_user" SCAN_DEPTH="$scan_depth" BODY_FILE="$body_file" python3 -c "
import json, os, re, sys
target = open(os.environ['BODY_FILE']).read()
data = json.load(sys.stdin)
bot = os.environ['BOT_USER']
depth = int(os.environ['SCAN_DEPTH'])
# Strip provenance banner '[F:host:HHMM:pid] ' from both sides before comparing.
# Otherwise per-run PID/HHMM differences make every comment 'new', defeating
# the cross-run loop protection that motivated this helper (sage#215, sage#187).
banner_re = re.compile(r'^\[F:[^:\s]+:[^:\s]+:[^\]\s]+\] ')
def strip_banner(s): return banner_re.sub('', s, count=1)
recent_bot = [strip_banner(c.get('body','')) for c in data.get('comments', []) if c.get('author', {}).get('login') == bot][-depth:]
print('dup' if strip_banner(target) in recent_bot else 'new')
" 2>/dev/null || echo "new")

  rm -f "$body_file"

  if [ "$result" = "dup" ]; then
    return 1
  fi

  local post_err
  post_err=$(mktemp)
  gh issue comment "$issue_num" --repo "$repo" --body "$body" 2>"$post_err"
  local post_rc=$?
  if [ $post_rc -ne 0 ]; then
    echo "[comment_dedup] ERROR: gh issue comment failed (rc=$post_rc)" >&2
    if [ -s "$post_err" ]; then
      sed 's/^/[comment_dedup]   gh: /' "$post_err" >&2
    fi
    rm -f "$post_err"
    return 2
  fi
  rm -f "$post_err"
  return 0
}

# Post a comment. If it would be byte-identical to a recent bot comment,
# emit a single ESCALATE-DEDUP message tagging David and stay quiet
# afterward. The ESCALATE-DEDUP comment itself is deduped, so a stuck
# loop produces one human escalation, not many.
#
# Usage:
#   comment_dedup_or_escalate REPO ISSUE_NUM BODY [CONTEXT_LABEL]
#
# CONTEXT_LABEL: short human label of which automation tried to post
# (e.g., "build-oversized", "build-failed", "needs-spec"). Surfaces in
# the escalation so David knows what's looping.
#
# Returns:
#   0 — comment posted, or duplicate handled (escalation posted/suppressed)
#   non-zero — underlying gh post failed; caller should treat as error
comment_dedup_or_escalate() {
  local repo="$1"
  local issue_num="$2"
  local body="$3"
  local context="${4:-automated-loop}"

  # Prepend provenance banner if available. The banner contains the PID, so
  # same-run duplicates are caught by dedup while different runs (different
  # PID) produce distinct bodies — loop protection wins.
  if [ -n "${FOREMAN_BANNER:-}" ]; then
    body="${FOREMAN_BANNER} ${body}"
  fi

  comment_dedup "$repo" "$issue_num" "$body"
  local rc=$?

  case $rc in
    0)
      return 0
      ;;
    1)
      local escalation
      escalation="ESCALATE-DEDUP: Foreman would have posted a comment byte-identical to a recent bot comment on this issue (context: \`$context\`). Suppressing to prevent a loop.

@jorjani the underlying problem isn't being resolved by automation. Either fix the issue manually, change its status, or update the spec so the next cycle produces a different outcome."

      comment_dedup "$repo" "$issue_num" "$escalation"
      # Escalation post status is informational; original was a duplicate, so
      # the loop is contained either way. Return 0 to signal handled.
      return 0
      ;;
    2)
      echo "[comment_dedup_or_escalate] ERROR: comment post failed (context: $context); not escalating" >&2
      return 2
      ;;
    *)
      echo "[comment_dedup_or_escalate] ERROR: comment_dedup returned unexpected rc=$rc" >&2
      return $rc
      ;;
  esac
}
