#!/bin/bash
# One-time setup for a fresh Foreman clone.
# Run: ./setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Point git hooks at the committed hooks/ directory
git config core.hooksPath "$SCRIPT_DIR/hooks"
echo "Git hooks configured: $(git config core.hooksPath)"

echo "Setup complete."
