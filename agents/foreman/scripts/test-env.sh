#!/bin/bash
# Smoke test: simulate launchd's minimal env and verify every runtime Foreman
# needs resolves via config/env.sh. Run after any change to PATH/env.
#
# Why: launchd does NOT source ~/.zshrc or ~/.zprofile, so any PATH entry
# missing from config/env.sh causes "command not found" in production.
# Running this under `env -i` reproduces that stripped environment locally.
#
# Usage:
#   ./scripts/test-env.sh
#
# Exit: 0 if all required binaries resolve, 1 with a list of missing ones.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/config/env.sh"
PLIST_FILE="$SCRIPT_DIR/config/schedule.plist"

REQUIRED_BINS=(bun node npm pnpm yarn claude gh git jq python3)

if [ ! -f "$ENV_FILE" ]; then
  echo "FAIL: $ENV_FILE not found" >&2
  exit 1
fi

if [ ! -f "$PLIST_FILE" ]; then
  echo "FAIL: $PLIST_FILE not found" >&2
  exit 1
fi

# Parse bootstrap PATH from the launchd plist so the test stays locked to it.
# If the plist PATH ever changes, this test picks up the new value automatically.
PLIST_PATH=$(plutil -extract EnvironmentVariables.PATH raw "$PLIST_FILE") || {
  echo "FAIL: could not extract EnvironmentVariables.PATH from $PLIST_FILE" >&2
  exit 1
}

# Seed only what launchd itself provides, so the env mirrors production.
# launchd sets HOME, USER, LOGNAME, SHELL, TMPDIR plus anything in EnvironmentVariables.
output=$(env -i \
  HOME="$HOME" \
  USER="$USER" \
  LOGNAME="$LOGNAME" \
  SHELL="$SHELL" \
  TMPDIR="$TMPDIR" \
  PATH="$PLIST_PATH" \
  bash -c "
  set +u
  . '$ENV_FILE'
  for bin in ${REQUIRED_BINS[*]}; do
    if path=\$(command -v \"\$bin\" 2>/dev/null); then
      printf 'OK    %-10s %s\n' \"\$bin\" \"\$path\"
    else
      printf 'MISS  %-10s (not on PATH)\n' \"\$bin\"
    fi
  done
")

echo "$output"

if echo "$output" | grep -q '^MISS'; then
  echo
  echo "FAIL: one or more required binaries do not resolve under launchd-simulated env." >&2
  echo "Fix: add the missing runtime to $ENV_FILE." >&2
  exit 1
fi

echo
echo "PASS: all required binaries resolve."
