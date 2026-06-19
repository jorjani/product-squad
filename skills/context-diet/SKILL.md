---
name: context-diet
description: Audit always-loaded context — measure consumption of every file loaded each session, classify sections HOT/WARM/COLD, and propose moves out of the hot path. Use when CLAUDE.md / memory files feel bloated and you want to reclaim context budget. Audit and propose only; makes no changes. Distinct from /harness-audit (config health) and /usage-audit (live token burn).
---

# /context-diet — Context Window Budget Audit

Audit always-loaded context: measure consumption, classify by layer, propose moves.

**Usage:** `/context-diet`

For config health use /harness-audit; for diagnosing live token burn use /usage-audit.

## Step 1 — Measure
Read and count lines for every always-loaded file:

**Global (always):** your global `CLAUDE.md`, your memory index (first 200 lines), any project-root `CLAUDE.md`, and any always-loaded index/manifest.

**Project-specific (when a project is identified):** your design-system / project context files (`project.json`, `context.md`, schema, config YAML) and the project's `CLAUDE.md` / `.claude/CLAUDE.md`.

**Active this session:** any skill/command definitions loaded.

Estimate tokens: `words × 1.3` (English + code heuristic).

## Step 2 — Classify
Read every section in each CLAUDE.md and memory file. Apply the three-layer model:
- **HOT** — every interaction, any project. Belongs in CLAUDE.md. Leave it.
- **WARM** — specific projects or workflows. Move to a path-scoped rule or command file.
- **COLD** — reference, examples, detailed instructions. Move to a project doc or delete.

## Step 3 — Report

```
## Context Diet — {date}

### Budget
| File | Lines | Est. Tokens | Status |
| Global CLAUDE.md | X | X | OK / OVER (target <100 lines) |
| Project CLAUDE.md | X | X | OK / OVER (target <150 lines) |
| Memory index | X | X | OK / OVER (target <200 lines) |
| design-system / context files | X | X | {N files} |
| **Total** | **X** | **X** | **~{X}% of window** |

### Findings
{WARM and COLD only; skip HOT. Format: "Lines X-Y: {section} ({N} lines) — WARM/COLD — {where it belongs}". Sort by line count descending.}

### Proposed Moves
- Source: {file}:{lines}
- Destination: {command file, path-scoped rules file, or project doc}
- Savings: {N} lines removed from hot path

### Summary
Current: {X} always-loaded lines (~{X} tokens). After moves: {Y} lines ({Z}% reduction).
```

## Rules
- Targets: global CLAUDE.md <100 lines, project CLAUDE.md <150, memory index <200.
- Audit and propose only — do NOT make changes.
- Skip sections under 5 lines.
- Skills are lazy-loaded — list separately; don't count against budget.
- Everything in budget and well-placed? "All clear. No action needed."

## Deletion Safety
When trimming a file (especially via subagent), diff the result and categorize every deletion:
- **Safe** — exact duplicates, dead file refs, content verbatim in another loaded file, generic advice already in global CLAUDE.md.
- **Needs review** — project-specific behavioral rules that look generic but aren't (e.g. "show ASCII mockup before building"), quickstart recipes, design philosophy gates.

Present both categories to the user before finalizing. Bulk rewrites silently drop behavioral rules that look like filler.

$ARGUMENTS
