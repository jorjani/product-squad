#!/bin/bash
# Foreman magic-number thresholds
# Source this file: source "$SCRIPT_DIR/config/thresholds.sh"
WIP_LIMIT=3            # max open auto/* PRs per repo before build.sh skips
MAX_BUILD_ATTEMPTS=3   # max retry attempts in build-ticket.sh before giving up
INSPECT_HOLD_DAYS=7    # days a behavior PASS soaks in Verify before Inspector promotes to Done (foreman#209)
