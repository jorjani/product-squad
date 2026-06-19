---
name: harness-audit
description: Audit your Claude Code harness configuration — hooks, permissions, commands, agents, memory, plugins — and suggest concrete improvements. Use to find stale, broken, or redundant config. Report only; auto-applies nothing. Distinct from /context-diet (measures always-loaded token budget) and /usage-audit (diagnoses live token burn); this one audits config health, not tokens.
---

# /harness-audit — Claude Code Configuration Audit

**Usage:** `/harness-audit`

Audit the Claude Code harness (hooks, permissions, commands, agents, memory, plugins) and suggest improvements. Report only. For token-budget concerns use /context-diet; for live burn use /usage-audit.

## Process

### 1. Read configuration
Collect facts from your global and project config:
- Global `settings.json` (hooks, permissions, plugins, statusLine).
- Project `.claude/settings.json` (permissions, hooks).
- Project and global `CLAUDE.md` (instructions).

### 2. Inventory commands + agents
Scan your `.claude/commands/` and `.claude/agents/`:
- Count total commands and agents.
- Flag any referencing tools, files, or patterns that no longer exist.
- Flag commands with overlapping purpose (compare first line + usage).
- Flag commands not referenced by any other command or workflow.

### 3. Check memory health
Scan your memory directory:
- Read the memory index; count entries.
- Flag memory files not in the index.
- Flag index entries pointing to missing files.
- Spot-check 3 random entries for content that contradicts current codebase state.

### 4. Hooks review
For each hook: does the referenced script/path still exist? Is it doing something a built-in feature now handles? Are common patterns missing (e.g. format-on-save for uncovered file types)?

### 5. Permissions review
- Flag overly broad patterns (e.g. `Bash(rm:*)`).
- Flag stale one-off permissions that look session-specific.
- Count total entries; flag if >100 (permission bloat).

## Output

```
## Harness Audit — {date}

### Summary
| Category | Count | Issues |
| Commands / Agents / Hooks / Memory files / Permissions / Plugins | {n} | {issues} |

### Findings (sorted by impact)
1. **[category]:** [finding] — [suggested fix]

### Stale Items (safe to remove)
- [item]: [why it's stale]

### Missing (worth adding)
- [suggestion]: [why]
```

## Rules
- Report only. Do not edit settings, commands, or memory.
- Sort findings by impact — what would improve daily usage most.
- Be specific: "command X references file Y which doesn't exist," not "some commands may be stale."
- Skip cosmetic issues (formatting, naming). Focus on functional problems.

$ARGUMENTS
