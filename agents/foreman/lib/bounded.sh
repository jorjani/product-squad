#!/bin/bash
# Wall-clock timeout helper. macOS lacks GNU `timeout`.
#
# Two variants:
#   run_bounded SECS CMD ARGS...
#     Captures combined stdout+stderr into PROBE_OUT (via mktemp). PROBE_EXIT
#     is 124 on timeout. Suitable for short probes (auth checks, curl, claude
#     -p one-liners) where output is small enough to land in a bash variable.
#
#   run_bounded_to_file SECS OUTFILE CMD ARGS...
#     Streams output directly to OUTFILE (truncating). PROBE_EXIT is 124 on
#     timeout. PROBE_OUT is set to empty — caller manages the file. Use for
#     long-running calls whose output can exceed a safe bash variable size
#     (e.g. claude builds, where 30 min of verbose output may be 10-100 MB).
#
# Both variants use python3's `os.setsid()` to promote the bounded child to a
# new session/PGID leader, then escalate SIGTERM -> 3s grace -> SIGKILL on the
# child's process group. This is the POSIX-guaranteed primitive — bash's
# `set -m` is unreliable when the bounded command is a shell script.
#
# Provenance: introduced by issue #219 to wrap the build phase's claude call;
# the inline definition previously lived in orchestrator.sh (post-#218
# hardening with SIGTERM->SIGKILL escalation on the process group). Now
# sourced from both callers so the build phase shares the same hardened
# primitive as the preflight probes.

# Env var BOUNDED_STALL_SECS (optional, integer seconds): when >0, the bound
# ALSO fires if OUTFILE stops growing for that long — an output-stall watchdog
# for wedged streaming commands (R1: claude hung on a dead API stream). Unset
# or 0 = plain wall-clock bound only (preflight probes leave it unset).

# Internal: bounded process-group runner. Caller supplies the output path.
_run_bounded_pg() {
  local secs="$1"; shift
  local outfile="$1"; shift
  # python3 setsid wrapper: child becomes its own session/PGID leader,
  # then execs the requested command (which inherits the new PGID).
  # `exec` so the backgrounded subshell IS python3: $! is then the real
  # PID and (after os.setsid) the PGID leader. Without exec, bash may keep
  # the subshell as a shell process, so $! is not the group leader and the
  # kills below target the wrong group — a hung child then orphans.
  ( exec python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@" < /dev/null > "$outfile" 2>&1 ) &
  local cpid=$!
  # Killer subshell. With BOUNDED_STALL_SECS>0 (set by the build path), also
  # kill early when $outfile stops growing for that long — catches a wedged
  # command without waiting out the full wall-clock bound. Unset = plain
  # wall-clock bound, byte-for-byte the original (preflight probes).
  if [ "${BOUNDED_STALL_SECS:-0}" -gt 0 ]; then
    (
      waited=0; stall=0; last_size=-1
      while [ "$waited" -lt "$secs" ]; do
        sleep 5 2>/dev/null || break
        waited=$((waited + 5))
        cur_size=$(wc -c < "$outfile" 2>/dev/null | tr -d ' ' || echo 0)
        if [ "$cur_size" = "$last_size" ]; then
          stall=$((stall + 5))
          if [ "$stall" -ge "$BOUNDED_STALL_SECS" ]; then
            echo "BOUNDED-STALL: $outfile unchanged ${stall}s (>= ${BOUNDED_STALL_SECS}s) — killing wedged command" >&2
            break
          fi
        else
          stall=0; last_size="$cur_size"
        fi
      done
      # Reached on a stall OR on the wall-clock bound (waited >= secs). The
      # 5s poll granularity means a no-stall wall-clock kill lands up to ~5s
      # late vs the exact else-branch sleep "$secs" — immaterial on a 1800s
      # bound, and build-ticket.sh's stall-vs-timeout split has a 120s buffer.
      kill -TERM -- "-$cpid" 2>/dev/null || true
      sleep 3 2>/dev/null && kill -KILL -- "-$cpid" 2>/dev/null || true
    ) &
  else
    (
      sleep "$secs" 2>/dev/null && kill -TERM -- "-$cpid" 2>/dev/null
      sleep 3 2>/dev/null && kill -KILL -- "-$cpid" 2>/dev/null
    ) &
  fi
  local wpid=$!
  wait "$cpid" 2>/dev/null && PROBE_EXIT=0 || PROBE_EXIT=$?
  # Defensive reap: a bounded call must leave nothing alive behind it. If
  # this KILL actually signals a process, the wait/kill path above let one
  # escape (e.g. the bounded command exited but spawned a lingering child) —
  # reap it and log BOUNDED-STRAGGLER as evidence of the orphaned-build class.
  if kill -KILL -- "-$cpid" 2>/dev/null; then
    echo "BOUNDED-STRAGGLER: reaped survivor(s) in process group $cpid after bound (secs=$secs)" >&2
  fi
  # Both `kill` and `wait` need explicit `|| true` under `set -euo pipefail`.
  # When the bound is hit, the killer subshell may have already exited by the
  # time we get here — `kill` then returns non-zero and aborts the orchestrator
  # silently (exit 1, no log). The race is invisible in the no-timeout case
  # (the killer is still in `sleep $secs`) but always-fires when the bound
  # actually triggers.
  kill "$wpid" 2>/dev/null || true
  wait "$wpid" 2>/dev/null || true
  if [ "$PROBE_EXIT" -ge 128 ]; then PROBE_EXIT=124; fi
}

run_bounded() {
  local secs="$1"; shift
  local tmp; tmp=$(mktemp)
  _run_bounded_pg "$secs" "$tmp" "$@"
  PROBE_OUT=$(cat "$tmp")
  rm -f "$tmp"
}

run_bounded_to_file() {
  local secs="$1"; shift
  local outfile="$1"; shift
  _run_bounded_pg "$secs" "$outfile" "$@"
  PROBE_OUT=""
}
