---
name: usage-audit
description: Diagnose token burn — summarize the active usage block, find the hottest sessions in a recent time window, and drill into the top one to identify what's consuming tokens (tool mix, fan-out, noisy watchers). Use when a session is burning tokens fast and you want the cause. Distinct from /context-diet (always-loaded budget) and /harness-audit (config health); this one diagnoses live burn.
---

# /usage-audit — Diagnose Token Burn

Find what's consuming tokens in the current usage block and drill into the hot session.

**Usage:** `/usage-audit [minutes]` (default 17)

For always-loaded context budget use /context-diet; for config health use /harness-audit.

Run three checks in order. Report concisely. Skip sessions under 100K tokens in the window.

## 1. Active block summary
```bash
npx ccusage@latest blocks --active 2>&1 | head -30
```
Note block start time, tokens so far, burn rate.

## 2. Per-session tokens in the window
Default window 17 min; if an argument is a number, use that. Point `PROJECT_DIR` at your Claude Code transcript directory for this project (`~/.claude/projects/<project-dir>`).

```bash
MIN="${1:-17}"
CUTOFF=$(date -u -v-${MIN}M +%Y-%m-%dT%H:%M:%SZ)
cd "$PROJECT_DIR"
for f in *.jsonl; do
  tokens=$(jq -r --arg c "$CUTOFF" 'select(.timestamp >= $c) | select(.message.usage) | (.message.usage.input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0) + (.message.usage.cache_read_input_tokens // 0) + (.message.usage.output_tokens // 0)' "$f" 2>/dev/null | awk '{s+=$1} END {print s+0}')
  if [ "${tokens:-0}" -gt 100000 ]; then
    mtime=$(stat -f "%Sm" -t "%H:%M" "$f")
    echo "$mtime  tokens=$tokens  $f"
  fi
done | sort -k2 -t= -n -r | head -5
```

## 3. Drill into the top session
For the #1 file from step 2:
```bash
F={top_file}; CUTOFF={same_cutoff}
echo "=== first user message ==="
jq -r 'select(.type=="user" and (.message.content | type=="string")) | .message.content' "$F" | head -20
echo "=== message types in window ==="
jq -r --arg c "$CUTOFF" 'select(.timestamp >= $c) | .type' "$F" | sort | uniq -c | sort -rn
echo "=== tool calls in window ==="
jq -r --arg c "$CUTOFF" 'select(.timestamp >= $c and .type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name' "$F" | sort | uniq -c | sort -rn
echo "=== top 5 assistant turns by tokens ==="
jq -r --arg c "$CUTOFF" 'select(.timestamp >= $c and .type=="assistant" and .message.usage) | "\(.timestamp)\t\((.message.usage.input_tokens // 0) + (.message.usage.cache_read_input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0) + (.message.usage.output_tokens // 0))"' "$F" | sort -k2 -rn | head -5
```

## Output

```
## Usage audit (last {N} min)
Block: started {time}, {tokens} tokens, ${cost}, burn rate {x}/min
Top session: {file} ({tokens} in window)
Started: "{first user message snippet}"
Tool mix: {Bash: N, Read: N, ...}
Event drivers: {notification: N, pr-link: N, ...}

Likely cause: {one line — e.g. "watcher firing on noisy pattern" or "subagent fan-out"}
Recommended action: {exit session / kill watched process / narrow regex / etc.}
```

$ARGUMENTS
