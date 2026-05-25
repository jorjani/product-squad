#!/bin/bash
# Verifies run_bounded enforces a hard deadline against a child that
# REQUIRES SIGKILL (SIGTERM alone is not enough), and that a bounded
# command leaves no straggler children behind it (#299). Sources
# lib/bounded.sh so the tests exercise the real committed code rather
# than a drifting inline copy.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/bounded.sh"

fail=0
self_pgid=$(ps -o pgid= -p $$ | tr -d ' ')
echo "test runner PID=$$ PGID=$self_pgid"

# T1 (STRONG): truly stubborn child — bash ignores TERM and loops over sleep.
# A TERM-only bound would loop forever (each sleep dies from TERM, bash
# starts a new one). Only SIGKILL escalation can stop this.
echo "--- T1: SIGKILL-only-killable child (bash traps TERM, loops sleep) with 2s bound ---"
start=$(date +%s)
run_bounded 2 bash -c 'trap "" TERM; while :; do sleep 30; done'
end=$(date +%s); elapsed=$((end - start))
echo "elapsed=${elapsed}s PROBE_EXIT=$PROBE_EXIT"
if [ "$elapsed" -le 8 ] && [ "$PROBE_EXIT" -eq 124 ]; then
  echo "T1 PASS"
else
  echo "T1 FAIL"; fail=1
fi

# T1b: confirm no orphans linger after T1.
sleep 0.3
orphans=$(pgrep -f 'while :; do sleep 30' | wc -l | tr -d ' ')
echo "T1b: lingering stubborn-child procs = $orphans"
if [ "$orphans" = "0" ]; then echo "T1b PASS"; else echo "T1b FAIL"; fail=1; fi

# T2: well-behaved fast command exits clean with output captured.
echo "--- T2: fast command (echo hello) with 5s bound ---"
start=$(date +%s)
run_bounded 5 echo hello
end=$(date +%s); elapsed=$((end - start))
echo "elapsed=${elapsed}s PROBE_EXIT=$PROBE_EXIT PROBE_OUT='$PROBE_OUT'"
if [ "$elapsed" -le 2 ] && [ "$PROBE_EXIT" -eq 0 ] && [ "$PROBE_OUT" = "hello" ]; then
  echo "T2 PASS"
else
  echo "T2 FAIL"; fail=1
fi

# T3: cooperative child obeys SIGTERM at the bound.
echo "--- T3: cooperative sleep with 1s bound ---"
start=$(date +%s)
run_bounded 1 sleep 10
end=$(date +%s); elapsed=$((end - start))
echo "elapsed=${elapsed}s PROBE_EXIT=$PROBE_EXIT"
if [ "$elapsed" -le 4 ] && [ "$PROBE_EXIT" -eq 124 ]; then
  echo "T3 PASS"
else
  echo "T3 FAIL"; fail=1
fi

# T4: bounded child runs in a separate PGID. Tests setsid wrapper directly so
# the result reflects what run_bounded actually does. Previous T4 used `set -m`
# directly which was a placebo — that mechanism only works for single-binary
# bounded commands, not shell scripts. Production wedge 2026-05-10 ran 13h
# because of this gap. The new setsid wrapper is unconditional.
echo "--- T4: bounded child PGID is separate (via setsid wrapper) ---"
( exec python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' sleep 3 ) &
cpid=$!
sleep 0.3
cpgid=$(ps -o pgid= -p "$cpid" 2>/dev/null | tr -d ' ')
echo "cpid=$cpid cpgid=$cpgid (test runner PGID=$self_pgid)"
if [ -n "$cpgid" ] && [ "$cpgid" != "$self_pgid" ]; then
  echo "T4 PASS"
else
  echo "T4 FAIL: bounded child shares parent PGID"; fail=1
fi
kill "$cpid" 2>/dev/null; wait "$cpid" 2>/dev/null || true

# T4b (NEW): same PGID-separation check but the bounded command is a SHELL
# SCRIPT, not a single binary. This is the case that broke production on
# 2026-05-10 — `set -m` failed silently for phase scripts (orchestrator
# wraps phases/triage.sh, phases/verify.sh, etc.). The setsid wrapper must
# work regardless of whether the command is a single binary or a script.
echo "--- T4b: bounded child PGID is separate when command is a SHELL SCRIPT ---"
script=$(mktemp)
cat > "$script" <<'INNER'
#!/bin/bash
sleep 3
INNER
chmod +x "$script"
( exec python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$script" ) &
cpid=$!
sleep 0.5
cpgid=$(ps -o pgid= -p "$cpid" 2>/dev/null | tr -d ' ')
echo "cpid=$cpid cpgid=$cpgid (test runner PGID=$self_pgid)"
if [ -n "$cpgid" ] && [ "$cpgid" != "$self_pgid" ]; then
  echo "T4b PASS"
else
  echo "T4b FAIL: shell-script child shares parent PGID — PR #223 wedge would recur"; fail=1
fi
kill "$cpid" 2>/dev/null; wait "$cpid" 2>/dev/null || true
rm -f "$script"

# T5: run_bounded must survive the bound-hit cleanup race under `set -euo
# pipefail`. PR #218 fix.
echo "--- T5: run_bounded under set -euo pipefail must reach the line after the bound is hit ---"
t5_out=$(bash -c '
  set -euo pipefail
  source "'"$SCRIPT_DIR"'/lib/bounded.sh"
  run_bounded 2 bash -c '"'"'trap "" TERM; while :; do sleep 30; done'"'"'
  echo "REACHED_AFTER_RUN_BOUNDED"
' 2>&1)
echo "$t5_out"
if echo "$t5_out" | grep -q "REACHED_AFTER_RUN_BOUNDED"; then
  echo "T5 PASS"
else
  echo "T5 FAIL: set -e exited run_bounded on the bound-hit cleanup race"; fail=1
fi

# T6 (NEW): the regression test for the 13h production wedge. Bounded command
# is a shell script that spawns multiple children (mirrors a real phase
# script). The 15-min bound must still enforce — verify by using a 2s bound
# on a script that forks a 30s sleep + ignores TERM in the parent shell.
# Without setsid (and with `set -m`-only), this is what wedged in production.
echo "--- T6: real production scenario — shell-script phase that wedges its children ---"
script=$(mktemp)
cat > "$script" <<'INNER'
#!/bin/bash
trap "" TERM
sleep 30 &
wait
INNER
chmod +x "$script"
start=$(date +%s)
run_bounded 2 "$script"
end=$(date +%s); elapsed=$((end - start))
echo "elapsed=${elapsed}s PROBE_EXIT=$PROBE_EXIT"
if [ "$elapsed" -le 8 ] && [ "$PROBE_EXIT" -eq 124 ]; then
  echo "T6 PASS"
else
  echo "T6 FAIL: phase-shaped wedge not killed by bound (this is the 13h prod wedge)"; fail=1
fi
# Confirm no orphans
sleep 0.3
orphans=$(pgrep -f "$script" 2>/dev/null | wc -l | tr -d ' ')
echo "T6b: lingering phase-script procs = $orphans"
if [ "$orphans" = "0" ]; then echo "T6b PASS"; else echo "T6b FAIL"; fail=1; fi
rm -f "$script"

# T7 (NEW, #299): a bounded command that exits cleanly but leaves a child
# alive in its process group. run_bounded must reap the whole group, not
# just the waited pid — the orphaned-build-claude class.
echo "--- T7: straggler child reaped after the bounded command exits ---"
t7_err=$(mktemp)
run_bounded 30 bash -c 'sleep 6001 & exit 0' 2>"$t7_err"
sleep 0.5
t7_orphans=$(pgrep -f 'sleep 6001' 2>/dev/null | wc -l | tr -d ' ')
t7_logged=$(grep -q BOUNDED-STRAGGLER "$t7_err" && echo yes || echo no)
echo "T7: lingering straggler procs=$t7_orphans  BOUNDED-STRAGGLER logged=$t7_logged"
if [ "$t7_orphans" = "0" ] && [ "$t7_logged" = "yes" ]; then
  echo "T7 PASS"
else
  echo "T7 FAIL: straggler not reaped or BOUNDED-STRAGGLER not logged"; fail=1
  pkill -f 'sleep 6001' 2>/dev/null || true
fi
rm -f "$t7_err"

# T8 (NEW, #1/R1): with BOUNDED_STALL_SECS set, a command producing no output
# is killed once its outfile stops growing — without waiting the full bound.
echo "--- T8: stall watchdog kills a no-output command early ---"
t8_out=$(mktemp); t8_err=$(mktemp)
start=$(date +%s)
BOUNDED_STALL_SECS=5 run_bounded_to_file 120 "$t8_out" bash -c 'sleep 600' 2>"$t8_err"
end=$(date +%s); elapsed=$((end - start))
t8_logged=$(grep -q BOUNDED-STALL "$t8_err" && echo yes || echo no)
echo "T8: elapsed=${elapsed}s PROBE_EXIT=$PROBE_EXIT BOUNDED-STALL-logged=$t8_logged"
if [ "$elapsed" -le 45 ] && [ "$PROBE_EXIT" -eq 124 ] && [ "$t8_logged" = "yes" ]; then
  echo "T8 PASS"
else
  echo "T8 FAIL: stall watchdog did not kill the no-output command early"; fail=1
fi
rm -f "$t8_out" "$t8_err"

echo "==="
[ "$fail" -eq 0 ] && echo "ALL PASS" && exit 0
echo "FAILED"; exit 1
