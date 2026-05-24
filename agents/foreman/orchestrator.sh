#!/bin/bash
# Foreman Orchestrator
# Runs phases in a loop until no phase produces work, then stops.
# Phases: Verify → Review → Build → Triage (loop) → Sarge-Review → Auto-Enrich
#
# Usage:
#   ./orchestrator.sh           # Full run (loop until idle)
#   ./orchestrator.sh verify    # Single phase only
#   ./orchestrator.sh inspect   # Single phase only (Inspector v0 — Verify -> Done gate)
#   ./orchestrator.sh code-review  # Single phase only (independent code-reviewer dispatch on open PRs)
#   ./orchestrator.sh review    # Single phase only
#   ./orchestrator.sh build     # Single phase only
#   ./orchestrator.sh triage    # Single phase only
#   ./orchestrator.sh sarge-review            # Proactive Sarge recon on Scope items
#   ./orchestrator.sh sarge-pitch             # First-pass Sarge draft on Pitch items
#   ./orchestrator.sh intake <repo> "<idea>"  # Turn idea into spec'd issue
#   ./orchestrator.sh self-improve            # Force self-improve phase
#   ./orchestrator.sh pipeline-digest         # Daily digest + auto-promotions
#   ./orchestrator.sh auto-enrich             # Scan NEEDS-SPEC comments, enrich specs (mechanical only — see getqatalyst/sarge for full PM scoping)
#   ./orchestrator.sh cleanup                 # Prune stale local branches across repos
#   ./orchestrator.sh ghost-sweep             # Demote In Progress items lacking CLAIMED
#   ./orchestrator.sh orphan-rescue           # Publish auto/ builds stranded after commit
#   ./orchestrator.sh test-orphan-rescue <repo> <issue>  # Self-test orphan-rescue
#   ./orchestrator.sh stranded-sweep          # Requeue orphaned auto/issue-N-* worktrees
#   ./orchestrator.sh janitor                 # Sweep stranded CLOSED cards to Parking
#   ./orchestrator.sh status                  # Show board state + blockers
set -euo pipefail
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load runtime env (PATH for launchd/SSH, bun, nvm). See config/env.sh.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/config/env.sh"
RESULTS_DIR="$SCRIPT_DIR/results"
DATE=$(date +%Y-%m-%d)
RUN_ID="$DATE-$(date +%H%M)"
LOG="$RESULTS_DIR/$RUN_ID.log"

# Provenance banner: [F:<host>:<HHMM>:<pid>] — stamped on every artifact.
# Must source after RUN_ID is set so the HHMM component matches the log filename.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/provenance.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/slack.sh"
# Slack-questions feature (lib/questions.sh). DARK by default — every
# function is a silent no-op when SLACK_BOT_TOKEN / SLACK_QUESTIONS_CHANNEL_ID
# are unset, so this changes nothing about Foreman's behavior until the
# bot is installed and those env vars are populated.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/questions.sh"
PHASE="${1:-all}"
MAX_CYCLES=3
MAX_DAILY_BUILDS=10

mkdir -p "$RESULTS_DIR"

# --- Helper: extract count from phase output (macOS compatible, no grep -P) ---
extract_count() {
  local key="$1"
  local text="$2"
  echo "$text" | sed -n "s/.*${key}=\([0-9]*\).*/\1/p" | tail -1
}

# --- Wall-clock timeout primitive ---
# Provides run_bounded (PROBE_OUT capture) and run_bounded_to_file (streams
# to caller-supplied path, used by phases/build-ticket.sh for the long-running
# claude build call). See lib/bounded.sh for the SIGTERM->SIGKILL/PGID
# semantics — same primitive used by preflight probes and the build phase.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/bounded.sh"

# --- Concurrent run lock ---
# Steal a held lock only when the holder process is genuinely dead — never on
# a timer. The prior 4-hour age heuristic stole the lock from still-alive long
# runs (a full daily loop can legitimately exceed 4h), letting two
# orchestrators run concurrently and race the shared build worktree paths.
LOCK_DIR="$RESULTS_DIR/.orchestrator.lock"
LOCK_PID_FILE="$LOCK_DIR/pid"
acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    local holder LOCK_AGE
    holder=$(cat "$LOCK_PID_FILE" 2>/dev/null || echo "")
    # Holder alive AND still an orchestrator: genuinely running, stand down.
    if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null \
       && ps -p "$holder" -o command= 2>/dev/null | grep -q "orchestrator.sh"; then
      FIRE_ABORT_REASON=lock-busy
      echo "Another orchestrator is running (pid $holder). Exiting."
      exit 0
    fi
    # Pidless + fresh = the sub-second window between a peer's mkdir and its
    # pid write. Refuse rather than race the peer that is mid-acquire.
    if [ -z "$holder" ]; then
      # stat fails if the lock dir vanished mid-check (holder released it):
      # || echo 0 makes LOCK_AGE huge -> falls through to reclaim the now-free
      # lock, and keeps stat's failure from aborting the run under set -e.
      LOCK_AGE=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0) ))
      if [ "$LOCK_AGE" -lt 300 ]; then
        FIRE_ABORT_REASON=lock-busy
        echo "Lock just acquired by a peer (pidless, ${LOCK_AGE}s old). Exiting."
        exit 0
      fi
    fi
    echo "Stale lock detected (holder pid '${holder:-none}' not a live orchestrator). Reclaiming." >> "$LOG"
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR" 2>/dev/null || { FIRE_ABORT_REASON=lock-busy; echo "Could not acquire lock. Exiting."; exit 0; }
  fi
  echo "$$" > "$LOCK_PID_FILE"
  LOCK_ACQUIRED=1
}
LOCK_ACQUIRED=0
# Per-fire heartbeat state. Trap posts FIRE END (success) or FIRE ABORT
# (preflight) to #foreman-heartbeat so a missing pair signals a wedged
# fire within ~3h. FIRE_HEARTBEAT_POSTED guards against double-post if
# trap fires twice (e.g. EXIT after explicit exit).
FIRE_ABORT_REASON=""
FIRE_HEARTBEAT_POSTED=0
release_lock() {
  # rm -rf, not rmdir: the lock dir now holds a pid file.
  [ "$LOCK_ACQUIRED" -eq 1 ] && rm -rf "$LOCK_DIR" 2>/dev/null || true
}
fire_exit_trap() {
  if [ "$FIRE_HEARTBEAT_POSTED" -ne 1 ]; then
    FIRE_HEARTBEAT_POSTED=1
    if [ -n "$FIRE_ABORT_REASON" ]; then
      fire_heartbeat "FIRE ABORT | reason=$FIRE_ABORT_REASON"
    elif [ "$LOCK_ACQUIRED" -eq 1 ]; then
      # D3: a single low-noise line for unanswered questions instead of
      # re-posting each fire. questions_waiting_line is DARK-empty when
      # the bot isn't configured, so the heartbeat shape is unchanged.
      local _q_line
      _q_line=$(questions_waiting_line)
      if [ -n "$_q_line" ]; then
        fire_heartbeat "FIRE END | cycles=${CYCLE:-0} built=${BUILD_WORK:-0} reviewed=${REVIEWED_WORK:-0} merged=${REVIEW_WORK:-0} | questions: $_q_line"
      else
        fire_heartbeat "FIRE END | cycles=${CYCLE:-0} built=${BUILD_WORK:-0} reviewed=${REVIEWED_WORK:-0} merged=${REVIEW_WORK:-0}"
      fi
    fi
  fi
  release_lock
}
trap 'fire_exit_trap' EXIT

# --- Log cleanup: delete logs older than 7 days ---
find "$RESULTS_DIR" -name "*.log" -mtime +7 -delete 2>/dev/null || true

# Intake is interactive (not part of daily run), handle separately
if [ "$PHASE" = "intake" ]; then
  INTAKE_REPO="${2:-}"
  INTAKE_IDEA="${3:-}"
  if [ -z "$INTAKE_REPO" ] || [ -z "$INTAKE_IDEA" ]; then
    echo "Usage: ./orchestrator.sh intake <repo> \"<idea>\""
    echo "Repos: getqatalyst/Sage, getqatalyst/coaches, getqatalyst/Jobber, getqatalyst/product-studio, getqatalyst/foreman"
    exit 1
  fi
  "$SCRIPT_DIR/phases/intake.sh" "$INTAKE_REPO" "$INTAKE_IDEA"
  exit $?
fi

# Status command: show board state + blockers (no lock needed)
if [ "$PHASE" = "status" ]; then
  "$SCRIPT_DIR/phases/status.sh"
  exit $?
fi

# test-orphan-rescue: synthesize an orphan worktree and run one rescue
# iteration (foreman#240). Manual smoke test — no lock needed.
if [ "$PHASE" = "test-orphan-rescue" ]; then
  TEST_REPO="${2:-}"
  TEST_ISSUE="${3:-}"
  if [ -z "$TEST_REPO" ] || [ -z "$TEST_ISSUE" ]; then
    echo "Usage: ./orchestrator.sh test-orphan-rescue <repo> <issue>"
    exit 1
  fi
  "$SCRIPT_DIR/phases/orphan-rescue.sh" --self-test "$TEST_REPO" "$TEST_ISSUE"
  exit $?
fi

# Acquire lock (after intake check, since intake is interactive)
acquire_lock

# Heartbeat: FIRE START. Existence of this post is the signal — a START
# without a matching END/ABORT inside ~3h means the fire is wedged.
fire_heartbeat "FIRE START"

# Pre-flight
echo "=== ORCHESTRATOR START: $RUN_ID $FOREMAN_BANNER ===" >> "$LOG"

# Canonical-host check. Set FOREMAN_HOST in config/env.sh to the machine that
# should run foreman; pre-flight aborts on mismatch. Prevents accidental dual-
# machine fires when a stale plist remains loaded on a retired host.
if [ -n "${FOREMAN_HOST:-}" ] && [ "$(hostname)" != "$FOREMAN_HOST" ]; then
  FIRE_ABORT_REASON=wrong-host
  echo "ABORT: canonical foreman host is $FOREMAN_HOST; running on $(hostname). Unload plist here." >> "$LOG"
  osascript -e "display notification \"Foreman fired on $(hostname); canonical is $FOREMAN_HOST.\" with title \"Foreman $FOREMAN_BANNER\" subtitle \"WRONG HOST\"" 2>/dev/null || true
  exit 0
fi

run_bounded 30 gh auth status
if [ "$PROBE_EXIT" -ne 0 ]; then
  FIRE_ABORT_REASON=gh-auth
  echo "ABORT: gh auth check failed (exit=$PROBE_EXIT): $PROBE_OUT" >> "$LOG"
  osascript -e "display notification \"GitHub auth expired or hung. Run: gh auth login\" with title \"Foreman $FOREMAN_BANNER\" subtitle \"FAILED\"" 2>/dev/null || true
  exit 1
fi

run_bounded 10 curl -sf --max-time 5 https://api.github.com
if [ "$PROBE_EXIT" -ne 0 ]; then
  FIRE_ABORT_REASON=api-down
  echo "ABORT: api.github.com unreachable (exit=$PROBE_EXIT)" >> "$LOG"
  exit 1
fi

# Claude token expiration display (best-effort, no probe yet)
CREDS_FILE="$HOME/.claude/.credentials.json"
if [ -f "$CREDS_FILE" ]; then
  EXPIRES_AT=$(python3 -c "import json; print(json.load(open('$CREDS_FILE')).get('claudeAiOauth',{}).get('expiresAt',0))" 2>/dev/null || echo "0")
  NOW_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null)
  REMAINING_H=$(python3 -c "print(round(($EXPIRES_AT - $NOW_MS) / 3600000, 1))" 2>/dev/null || echo "0")
  echo "Claude token expires in ${REMAINING_H}h" >> "$LOG"
fi
# Probe: lightweight call that forces SDK to refresh token if expired.
# Bounded so a hung claude (auth or network) cannot block all subsequent fires.
# Run from $HOME so claude does NOT pick up the *project-local* `.mcp.json`
# in $PWD (~/Projects/.mcp.json defines playwright, whose `npx -y
# @playwright/mcp@latest` bootstrap exceeds the 60s probe bound). Global
# MCP config (~/.claude/mcp.json) is cwd-independent and still loads — if
# you ever add a slow MCP to global config, the probe will hang again.
# Phases that legitimately want MCP keep their own cwd.
if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
  FIRE_ABORT_REASON=no-home
  echo "ABORT: HOME unset or not a directory; cannot probe Claude" >> "$LOG"
  exit 1
fi
run_bounded 60 bash -c 'cd "$HOME" && exec claude -p "reply OK" --model haiku --max-budget-usd 1'
if [ "$PROBE_EXIT" -eq 124 ]; then
  FIRE_ABORT_REASON=claude-timeout
  echo "ABORT: Claude probe timed out (60s)" >> "$LOG"
  osascript -e "display notification \"Claude probe timed out (auth or network)\" with title \"Foreman $FOREMAN_BANNER\" subtitle \"PROBE TIMEOUT\"" 2>/dev/null || true
  exit 1
fi
if echo "$PROBE_OUT" | grep -q "authentication_error\|401"; then
  FIRE_ABORT_REASON=claude-auth
  echo "ABORT: Claude auth failed. Token expired and refresh failed." >> "$LOG"
  echo "Probe output: $PROBE_OUT" >> "$LOG"
  osascript -e "display notification \"Claude token expired. Run: claude auth login\" with title \"Foreman $FOREMAN_BANNER\" subtitle \"AUTH FAILED\"" 2>/dev/null || true
  exit 1
fi
echo "Claude auth OK" >> "$LOG"

# Self-update: pull foreman and meta repo to current main before phases.
# Soft-fail (warn + continue with local HEAD): a transient network blip should
# not block the run, and the next fire will retry. --ff-only refuses to
# clobber local commits or merges, surfacing divergence as a warning.
echo "--- self-update ---" >> "$LOG"
for repo_path in "$SCRIPT_DIR" "$HOME/Projects"; do
  run_bounded 30 git -C "$repo_path" pull --ff-only origin main
  echo "self-update $repo_path: $PROBE_OUT" >> "$LOG"
  if [ "$PROBE_EXIT" -ne 0 ]; then
    echo "WARNING: pull failed for $repo_path (exit=$PROBE_EXIT), continuing with local HEAD" >> "$LOG"
  fi
done

# Board ID drift check
source "$SCRIPT_DIR/config/board-ids.sh"
if ! validate_board_ids >> "$LOG" 2>&1; then
  echo "WARNING: Board IDs are stale — board moves will fail. See log." >> "$LOG"
  osascript -e "display notification \"Board IDs are stale! Update config/board-ids.sh\" with title \"Foreman $FOREMAN_BANNER\" subtitle \"DRIFT DETECTED\"" 2>/dev/null || true
fi

echo "Pre-flight OK" >> "$LOG"

# Poll David's Slack replies to any prior open questions. Runs before
# any phase so a "retry" / "close" / "update spec" decision lands as a
# GitHub comment BEFORE the build phase re-scans for changes. DARK no-op
# when the bot isn't configured. Bounded so a hung LLM interpret call
# never wedges the fire.
echo "--- QUESTIONS-POLL ---" >> "$LOG"
run_bounded 300 bash -c '. "'"$SCRIPT_DIR"'/lib/questions.sh" && questions_poll_replies'
echo "$PROBE_OUT" >> "$LOG"
if [ "$PROBE_EXIT" -eq 124 ]; then
  echo "ABORT: QUESTIONS-POLL timed out (5m) — continuing fire" >> "$LOG"
fi

# Single phase mode: run once and exit
if [ "$PHASE" != "all" ]; then
  echo "" >> "$LOG"
  echo "=== PHASE: $(echo "$PHASE" | tr '[:lower:]' '[:upper:]') ===" >> "$LOG"
  # Collect metrics before self-improve (it needs them). Bounded same as
  # the full-run path — collect-metrics invokes claude under the hood.
  if [ "$PHASE" = "self-improve" ]; then
    run_bounded 900 "$SCRIPT_DIR/phases/collect-metrics.sh" "$DATE"
    if [ "$PROBE_EXIT" -eq 124 ]; then
      echo "ABORT: collect-metrics pre-step timed out (15m) — continuing to self-improve" >> "$LOG"
    fi
  fi
  # All phases get a 15-min bound with TERM->KILL escalation (issue #222).
  # run_bounded handles the PGID isolation + cleanup-race protection (PR #216, #218).
  run_bounded 900 "$SCRIPT_DIR/phases/$PHASE.sh"
  RESULT="$PROBE_OUT"
  if [ "$PROBE_EXIT" -eq 124 ]; then
    RESULT="${RESULT}"$'\n'"$(echo "$PHASE" | tr '[:lower:]' '[:upper:]') PHASE: TIMED OUT after 15 minutes"
  fi
  echo "$RESULT" >> "$LOG"
  echo "" >> "$LOG"
  echo "=== ORCHESTRATOR COMPLETE: $(date +%H:%M) ===" >> "$LOG"
  echo "Done. Log: $LOG"
  exit 0
fi

# Full run: loop phases until no work is done
CYCLE=0
TOTAL_BUILDS_TODAY=0

while [ "$CYCLE" -lt "$MAX_CYCLES" ]; do
  CYCLE=$((CYCLE + 1))
  TOTAL_WORK=0

  echo "" >> "$LOG"
  echo "=== CYCLE $CYCLE of $MAX_CYCLES ===" >> "$LOG"

  # Phase 0: Verify
  # Each phase is wrapped in run_bounded 900 (15 min) so a wedged claude/MCP
  # cannot hang the orchestrator indefinitely (issue #222). On timeout, log
  # the abort and continue the cycle — other phases still get to run.
  echo "--- VERIFY ---" >> "$LOG"
  run_bounded 900 "$SCRIPT_DIR/phases/verify.sh"
  VERIFY_OUT="$PROBE_OUT"
  echo "$VERIFY_OUT" >> "$LOG"
  if [ "$PROBE_EXIT" -eq 124 ]; then
    echo "ABORT: VERIFY phase timed out (15m) — continuing cycle" >> "$LOG"
    # Zero the work count on timeout so partial output doesn't suppress the
    # stall alert at the end of the cycle. See PR #223 reviewer feedback.
    VERIFY_WORK=0
  else
    VERIFY_WORK=$(extract_count "verified" "$VERIFY_OUT")
    VERIFY_WORK=${VERIFY_WORK:-0}
  fi
  TOTAL_WORK=$((TOTAL_WORK + VERIFY_WORK))

  # Phase 0b: Inspect (Verify -> Done gate) + Code-Review (open-PR second pair
  # of eyes) run as siblings, before phases/review.sh. Inspect is gated on
  # verify completing; code-review runs independently so it still surfaces
  # findings even if verify errored out. Both phases have daily-once
  # sentinels, so re-entry within the same orchestrator invocation is a no-op.
  #
  # Parallelism: fire both with `&`, wait for both, log per-phase output. The
  # 15-min per-phase bound is intentionally dropped here — both have
  # daily-once guards and per-call claude budgets, so a wedge can't sprawl.
  CR_OUT_FILE="$RESULTS_DIR/$RUN_ID-code-review.out"
  IN_OUT_FILE="$RESULTS_DIR/$RUN_ID-inspect.out"

  if echo "$VERIFY_OUT" | grep -q "verified="; then
    echo "--- INSPECT --- (parallel with CODE-REVIEW)" >> "$LOG"
    "$SCRIPT_DIR/phases/inspect.sh" > "$IN_OUT_FILE" 2>&1 &
    INSPECT_PID=$!
  else
    echo "--- INSPECT --- SKIPPED (verify did not complete this cycle)" >> "$LOG"
    INSPECT_PID=""
  fi

  echo "--- CODE-REVIEW ---" >> "$LOG"
  "$SCRIPT_DIR/phases/code-review.sh" > "$CR_OUT_FILE" 2>&1 &
  CODE_REVIEW_PID=$!

  if [ -n "$INSPECT_PID" ]; then
    wait "$INSPECT_PID" || true
    [ -f "$IN_OUT_FILE" ] && cat "$IN_OUT_FILE" >> "$LOG" && rm -f "$IN_OUT_FILE"
  fi
  wait "$CODE_REVIEW_PID" || true
  [ -f "$CR_OUT_FILE" ] && cat "$CR_OUT_FILE" >> "$LOG" && rm -f "$CR_OUT_FILE"

  # Phase 1: Review
  echo "--- REVIEW ---" >> "$LOG"
  run_bounded 900 "$SCRIPT_DIR/phases/review.sh"
  REVIEW_OUT="$PROBE_OUT"
  echo "$REVIEW_OUT" >> "$LOG"
  if [ "$PROBE_EXIT" -eq 124 ]; then
    echo "ABORT: REVIEW phase timed out (15m) — continuing cycle" >> "$LOG"
    REVIEW_WORK=0
    REVIEWED_WORK=0
  else
    REVIEW_WORK=$(extract_count "merged" "$REVIEW_OUT")
    REVIEW_WORK=${REVIEW_WORK:-0}
    REVIEWED_WORK=$(extract_count "reviewed" "$REVIEW_OUT")
    REVIEWED_WORK=${REVIEWED_WORK:-0}
  fi
  TOTAL_WORK=$((TOTAL_WORK + REVIEW_WORK))

  # CI pile-up detection
  "$SCRIPT_DIR/phases/ci-alert.sh" >> "$LOG" 2>&1 || true

  # Phase 2: Build (skip if daily build cap reached)
  if [ "$TOTAL_BUILDS_TODAY" -ge "$MAX_DAILY_BUILDS" ]; then
    echo "--- BUILD --- SKIPPED (daily cap: $MAX_DAILY_BUILDS builds reached)" >> "$LOG"
    BUILD_WORK=0
  else
    echo "--- BUILD ---" >> "$LOG"
    run_bounded 900 "$SCRIPT_DIR/phases/build.sh"
    BUILD_OUT="$PROBE_OUT"
    echo "$BUILD_OUT" >> "$LOG"
    if [ "$PROBE_EXIT" -eq 124 ]; then
      echo "ABORT: BUILD phase timed out (15m) — continuing cycle" >> "$LOG"
      BUILD_WORK=0
    else
      BUILD_WORK=$(extract_count "built" "$BUILD_OUT")
      BUILD_WORK=${BUILD_WORK:-0}
      # Intentional skips (per-repo WIP cap, foreman_build=false) count as
      # cycle activity so stall detection does not flag a deliberate hold.
      # Per foreman#177: skip-due-to-cap / skip-due-to-flag are NOT stalls.
      BUILD_SKIPPED_WIP=$(extract_count "skipped_wip_cap" "$BUILD_OUT")
      BUILD_SKIPPED_NOT_ELIGIBLE=$(extract_count "skipped_not_eligible" "$BUILD_OUT")
      BUILD_INTENTIONAL_SKIPS=$(( ${BUILD_SKIPPED_WIP:-0} + ${BUILD_SKIPPED_NOT_ELIGIBLE:-0} ))
    fi
    TOTAL_BUILDS_TODAY=$((TOTAL_BUILDS_TODAY + BUILD_WORK))
    TOTAL_WORK=$((TOTAL_WORK + BUILD_WORK + ${BUILD_INTENTIONAL_SKIPS:-0}))
  fi

  # Phase 3: Triage
  echo "--- TRIAGE ---" >> "$LOG"
  run_bounded 900 "$SCRIPT_DIR/phases/triage.sh"
  TRIAGE_OUT="$PROBE_OUT"
  echo "$TRIAGE_OUT" >> "$LOG"
  if [ "$PROBE_EXIT" -eq 124 ]; then
    echo "ABORT: TRIAGE phase timed out (15m) — continuing cycle" >> "$LOG"
    TRIAGE_WORK=0
  else
    TRIAGE_WORK=$(extract_count "promoted" "$TRIAGE_OUT")
    TRIAGE_WORK=${TRIAGE_WORK:-0}
  fi
  TOTAL_WORK=$((TOTAL_WORK + TRIAGE_WORK))

  echo "CYCLE $CYCLE: verified=$VERIFY_WORK merged=$REVIEW_WORK built=$BUILD_WORK promoted=$TRIAGE_WORK total=$TOTAL_WORK" >> "$LOG"

  if [ "$TOTAL_WORK" -eq 0 ]; then
    echo "No work done this cycle. Stopping." >> "$LOG"
    # Stall alert: zero work + Ready not empty = something is jammed.
    # See getqatalyst/foreman#139 (v1: osascript, v2: Slack to dev-alert).
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/lib/stall.sh"
    READY_COUNT=$(count_ready_items)
    if [ "${READY_COUNT:-0}" -gt 0 ]; then
      echo "STALL: $READY_COUNT in Ready, no progress this cycle" >> "$LOG"
      notify_stall "$READY_COUNT"
    fi
    break
  fi

  echo "Work done ($TOTAL_WORK actions). Looping." >> "$LOG"
done

# Post-loop phases: upstream flow (run once per orchestrator invocation, not per cycle)

# Phase 4: Pipeline Digest (once per day -- actionable digest + auto-promotions)
echo "" >> "$LOG"
echo "--- PIPELINE-DIGEST ---" >> "$LOG"
run_bounded 900 "$SCRIPT_DIR/phases/pipeline-digest.sh"
DIGEST_OUT="$PROBE_OUT"
echo "$DIGEST_OUT" >> "$LOG"
if [ "$PROBE_EXIT" -eq 124 ]; then
  echo "ABORT: PIPELINE-DIGEST phase timed out (15m) — continuing" >> "$LOG"
fi

# Phase 4b: Sarge-Review — proactive recon of Scope items (foreman#192).
# Runs the existing Sarge prompt against Scope-status board items whose repo
# has agents.sarge includes "scope" in ~/Projects/.index.json. Caps at 3
# items per run; deferred items are named in the per-run log.
echo "" >> "$LOG"
echo "--- SARGE-REVIEW ---" >> "$LOG"
run_bounded 900 "$SCRIPT_DIR/phases/sarge-review.sh"
SARGE_OUT="$PROBE_OUT"
echo "$SARGE_OUT" >> "$LOG"
if [ "$PROBE_EXIT" -eq 124 ]; then
  echo "ABORT: SARGE-REVIEW phase timed out (15m) — continuing" >> "$LOG"
fi

# Phase 4c: Sarge-Pitch — first-pass recon on Pitch items (foreman#211).
# Posts SARGE-DRAFT: with questions + ASCII wireframe (UI tickets only) +
# draft brief. Never moves the card off Pitch — David promotes manually.
# Caps at 3 items per run; deferred items roll forward.
echo "" >> "$LOG"
echo "--- SARGE-PITCH ---" >> "$LOG"
run_bounded 900 "$SCRIPT_DIR/phases/sarge-pitch.sh"
SARGE_PITCH_OUT="$PROBE_OUT"
echo "$SARGE_PITCH_OUT" >> "$LOG"
if [ "$PROBE_EXIT" -eq 124 ]; then
  echo "ABORT: SARGE-PITCH phase timed out (15m) — continuing" >> "$LOG"
fi

# Phase 5: Auto-Enrich (break triage deadlock -- mechanically fill NEEDS-SPEC gaps)
# Full PM scoping lives in Sarge (getqatalyst/sarge). This phase is mechanical only.
echo "" >> "$LOG"
echo "--- AUTO-ENRICH ---" >> "$LOG"
run_bounded 900 "$SCRIPT_DIR/phases/auto-enrich.sh"
ENRICH_OUT="$PROBE_OUT"
echo "$ENRICH_OUT" >> "$LOG"
if [ "$PROBE_EXIT" -eq 124 ]; then
  echo "ABORT: AUTO-ENRICH phase timed out (15m) — continuing" >> "$LOG"
fi

# Phase 6: Cleanup — prune stale local branches across eligible repos
echo "" >> "$LOG"
echo "--- CLEANUP ---" >> "$LOG"
run_bounded 900 "$SCRIPT_DIR/phases/cleanup.sh"
CLEANUP_OUT="$PROBE_OUT"
echo "$CLEANUP_OUT" >> "$LOG"
if [ "$PROBE_EXIT" -eq 124 ]; then
  echo "ABORT: CLEANUP phase timed out (15m) — continuing" >> "$LOG"
fi

# Phase 6b: Ghost Sweep — demote In Progress items lacking a CLAIMED comment.
# Pickup logic in build-ticket.sh moves items to In Progress before the build
# runs; if the build aborts before a CLAIMED comment lands, the item strands.
# This phase rolls those back to Ready so the next cycle can re-pick them up.
echo "" >> "$LOG"
echo "--- GHOST-SWEEP ---" >> "$LOG"
run_bounded 900 "$SCRIPT_DIR/phases/ghost-sweep.sh"
GHOST_OUT="$PROBE_OUT"
echo "$GHOST_OUT" >> "$LOG"
if [ "$PROBE_EXIT" -eq 124 ]; then
  echo "ABORT: GHOST-SWEEP phase timed out (15m) — continuing" >> "$LOG"
fi

# Phase 6b1: Orphan Rescue — publish auto/ builds stranded after commit but
# before push (foreman#240). Runs BEFORE stranded-sweep on purpose: where
# claude finished (commit + .pr-body.md present), the work should be published,
# not requeued and redone. Anything orphan-rescue does not publish falls
# through to stranded-sweep below.
echo "" >> "$LOG"
echo "--- ORPHAN-RESCUE ---" >> "$LOG"
run_bounded 900 "$SCRIPT_DIR/phases/orphan-rescue.sh"
ORPHAN_RESCUE_OUT="$PROBE_OUT"
echo "$ORPHAN_RESCUE_OUT" >> "$LOG"
if [ "$PROBE_EXIT" -eq 124 ]; then
  echo "ABORT: ORPHAN-RESCUE phase timed out (15m) — continuing" >> "$LOG"
fi

# Phase 6b2: Stranded Sweep — requeue orphaned auto/issue-N-* worktrees
# whose build process died after CLAIMED but before push (foreman#270).
# Ghost-sweep can't catch these (CLAIMED comment exists); cleanup.sh skips
# them (branch unmerged). Without this phase the issue stalls silently in
# In Progress — Sage#394 took 4.8h to spot manually on 2026-05-16.
echo "" >> "$LOG"
echo "--- STRANDED-SWEEP ---" >> "$LOG"
run_bounded 900 "$SCRIPT_DIR/phases/stranded-sweep.sh"
STRANDED_OUT="$PROBE_OUT"
echo "$STRANDED_OUT" >> "$LOG"
if [ "$PROBE_EXIT" -eq 124 ]; then
  echo "ABORT: STRANDED-SWEEP phase timed out (15m) — continuing" >> "$LOG"
fi

# Phase 6c: Janitor — move stranded CLOSED cards to Parking (foreman#242).
# An issue closed manually (e.g., gh issue close --reason not_planned) leaves
# its board card behind in its source column. This phase finds those CLOSED
# cards (any column except Done, Verify, Parking) and sweeps them to Parking.
# Never moves to Done — that path is reserved for the Inspector phase.
echo "" >> "$LOG"
echo "--- JANITOR ---" >> "$LOG"
run_bounded 900 "$SCRIPT_DIR/phases/janitor.sh"
JANITOR_OUT="$PROBE_OUT"
echo "$JANITOR_OUT" >> "$LOG"
if [ "$PROBE_EXIT" -eq 124 ]; then
  echo "ABORT: JANITOR phase timed out (15m) — continuing" >> "$LOG"
fi

# Collect structured metrics (every full run). Wraps a claude call for
# narrative generation under the hood, so the 15-min bound applies — same
# wedge class as the other phases. Discovered when the 2026-05-11 16:00
# fire wedged here for 16h after the other phases correctly aborted.
echo "" >> "$LOG"
echo "--- COLLECT-METRICS ---" >> "$LOG"
run_bounded 900 "$SCRIPT_DIR/phases/collect-metrics.sh" "$DATE"
METRICS_OUT="$PROBE_OUT"
echo "$METRICS_OUT" >> "$LOG"
if [ "$PROBE_EXIT" -eq 124 ]; then
  echo "ABORT: COLLECT-METRICS phase timed out (15m) — continuing" >> "$LOG"
fi

# Phase 6: Self-Improve (every other day, after the work loop)
# %-d (no leading zero) avoids bash's octal trap on 08/09 — `08 % 2` errors out
# under set -e because "08" is invalid octal. Hit this on 2026-05-08.
DAY=$(date +%-d)
if [ $((DAY % 2)) -eq 1 ]; then
  echo "" >> "$LOG"
  echo "=== PHASE 6: SELF-IMPROVE ===" >> "$LOG"
  run_bounded 900 "$SCRIPT_DIR/phases/self-improve.sh"
  IMPROVE_RESULT="$PROBE_OUT"
  echo "$IMPROVE_RESULT" >> "$LOG"
  if [ "$PROBE_EXIT" -eq 124 ]; then
    echo "ABORT: SELF-IMPROVE phase timed out (15m) — continuing" >> "$LOG"
  fi
fi

# Cycle summary: post a Slack log entry every run (replaces stall-only alert).
# See lib/cycle-summary.sh and getqatalyst/foreman#198 for the dedup state file
# behaviour preserved in the legacy notify_stall path.
echo "" >> "$LOG"
echo "--- CYCLE-SUMMARY ---" >> "$LOG"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/cycle-summary.sh"
notify_cycle_summary >> "$LOG" 2>&1 || true

# Post any decision questions registered during this fire to Slack.
# Runs LAST so emitters from every phase have already contributed
# pending entries to the state file. DARK no-op when the bot isn't
# configured. Bounded — translate-LLM hangs cannot wedge the fire.
echo "" >> "$LOG"
echo "--- QUESTIONS-POST ---" >> "$LOG"
run_bounded 600 bash -c '. "'"$SCRIPT_DIR"'/lib/questions.sh" && questions_post_new'
echo "$PROBE_OUT" >> "$LOG"
if [ "$PROBE_EXIT" -eq 124 ]; then
  echo "ABORT: QUESTIONS-POST timed out (10m) — leftover entries roll to next fire" >> "$LOG"
fi

echo "" >> "$LOG"
echo "=== ORCHESTRATOR COMPLETE: $(date +%H:%M) ($CYCLE cycles, $TOTAL_BUILDS_TODAY builds today) ===" >> "$LOG"

SUMMARY="Foreman: $CYCLE cycles. V=$VERIFY_WORK R=$REVIEW_WORK B=$BUILD_WORK T=$TRIAGE_WORK"
osascript -e "display notification \"$SUMMARY\" with title \"Foreman $FOREMAN_BANNER\" subtitle \"$RUN_ID\"" 2>/dev/null || true

echo "Done. Log: $LOG"
