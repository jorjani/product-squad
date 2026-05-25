#!/bin/bash
# Start Foreman in tmux (called from iPhone via SSH)
export PATH="/Users/jorjani/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export HOME="/Users/jorjani"
LOG="/Users/jorjani/Projects/foreman/results/remote-start.log"

echo "$(date): Starting Foreman..." >> "$LOG"

# Kill any existing session
/opt/homebrew/bin/tmux kill-session -t foreman 2>/dev/null

# Start new session
/opt/homebrew/bin/tmux new-session -d -s foreman \
  "/Users/jorjani/Projects/foreman/orchestrator.sh 2>&1 | tee -a $LOG"

sleep 2

if /opt/homebrew/bin/tmux has-session -t foreman 2>/dev/null; then
  echo "$(date): Session started successfully" >> "$LOG"
  echo "OK"
else
  echo "$(date): Session failed to start" >> "$LOG"
  echo "FAILED - check $LOG"
fi
