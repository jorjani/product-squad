#!/bin/bash
# Provenance banner helper.
#
# Generates a short provenance ID stamped on every Foreman artifact:
#   [F:<host>:<HHMM>:<pid>]
#
# Example: [F:m2:2118:46845]
#
# - F       — Foreman agent prefix
# - host    — short hostname nickname (mapped from `hostname` via case below)
# - HHMM   — run-id hour+minute (from RUN_ID or current time)
# - pid     — orchestrator PID for direct `ps -p` / `kill`
#
# Usage:
#   source lib/provenance.sh   # after RUN_ID is set
#   echo "$FOREMAN_BANNER"     # [F:m2:2118:46845]
#
# Single source of truth. All surfaces (log, Slack, GitHub, osascript)
# reference FOREMAN_BANNER; none build the string themselves.

# Host nickname: short, human-friendly label for the machine.
# Map known hostnames to nicknames; unknown hosts get the first segment
# of their hostname (e.g., "DJ-Mac-Air.local" -> "DJ-Mac-Air").
_provenance_host_nick() {
  local full_host
  full_host=$(hostname)
  case "$full_host" in
    DJ-Mac-Air*)       echo "m2" ;;
    MacBook-Pro-2*)    echo "m5" ;;
    *)                 echo "${full_host%%.*}" ;;
  esac
}

# Extract HHMM from RUN_ID (format: YYYY-MM-DD-HHMM) or fall back to now.
_provenance_hhmm() {
  if [ -n "${RUN_ID:-}" ]; then
    # Last 4 chars of RUN_ID are HHMM. Pure parameter expansion (strip all
    # but the last 4) avoids any ambiguity with ${var:-default} syntax.
    echo "${RUN_ID#${RUN_ID%????}}"
  else
    date +%H%M
  fi
}

# Build and export the banner. Idempotent — safe to source multiple times.
if [ -z "${FOREMAN_BANNER:-}" ]; then
  _PROV_NICK=$(_provenance_host_nick)
  _PROV_HHMM=$(_provenance_hhmm)
  _PROV_PID=$$
  export FOREMAN_BANNER="[F:${_PROV_NICK}:${_PROV_HHMM}:${_PROV_PID}]"
  unset _PROV_NICK _PROV_HHMM _PROV_PID
fi
