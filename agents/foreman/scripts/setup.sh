#!/bin/bash
# One-time per-clone setup for foreman.
# Activates the versioned hook policy under .githooks/.
set -euo pipefail

cd "$(dirname "$0")/.."

git config core.hooksPath .githooks
echo "Configured core.hooksPath=.githooks (versioned pre-commit hook active)."
