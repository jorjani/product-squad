#!/bin/bash
# Shared runtime environment for Foreman.
#
# Sourced by orchestrator.sh; all phase scripts inherit via process env.
# This is the single source of truth for runtime PATH. launchd, SSH, and
# interactive contexts all route through here.
#
# launchd does not source shell profiles (.zshrc, .zprofile). Every PATH
# addition for a non-standard runtime (bun, nvm-managed node, etc.) must be
# declared explicitly here.
#
# To add a new runtime: append a guarded block below, no other files change.

# Base PATH: homebrew, user-local, claude CLI, system
export PATH="$HOME/.claude/local:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Bun (single-location install at ~/.bun/bin)
if [ -d "$HOME/.bun/bin" ]; then
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
fi

# Node via nvm (handles node, npm, pnpm, yarn, corepack)
# Sourcing nvm.sh is required: it sets up shims for the default node version.
# A plain PATH entry would break the next time the default node version changes.
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Slack webhook for ops alerts (stall detection, pipeline digest).
# Sources from cross-project connections so launchd inherits it without a
# separate plist edit. See ~/Projects/connections/slack/.env.example.
# Aliases SLACK_WEBHOOK_URL = SLACK_CI_WEBHOOK_URL so phases/pipeline-digest.sh
# (which checks the legacy name) starts firing too.
if [ -f "$HOME/Projects/connections/slack/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$HOME/Projects/connections/slack/.env"
  set +a
  export SLACK_WEBHOOK_URL="${SLACK_CI_WEBHOOK_URL:-${SLACK_WEBHOOK_URL:-}}"
fi

# Canonical foreman runtime host. orchestrator.sh pre-flight aborts when
# `hostname` does not match. Prevents accidental dual-machine fires when a
# stale plist remains loaded on a retired host. Migration: edit this, install
# the symlinked plist on the new host, launchctl unload on the old host.
export FOREMAN_HOST="${FOREMAN_HOST:-MacBook-Pro-2.local}"
