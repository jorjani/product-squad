# docs/

Tool choices, customization, workflow conventions, glossary.

## V1 docs (populated across M5-M7)

| File | Purpose | Milestone |
|---|---|---|
| `tool-choices.md` | Opinionated guide: GitHub, Railway, Anthropic, Bun, Bash, env vars, Slack. Why each + alternatives. | M5 |
| `cloud-railway.md` | Railway deployment walkthrough (smooth path) | M5 |
| `cloud-fallback.md` | GitHub Actions cron alternative | M5 |
| `customization.md` | "How to fork and adapt" | M6 |
| `hooks.md` | When to use which Claude Code hook + debugging | M6 |
| `agents.md` | Per-adapter notes (Claude, Codex; community: Aider, OpenCode, etc.) | M3 |
| `project-specific-commands.md` | Pattern for writing your own commands (no worked examples in V1) | M6 |
| `glossary.md` | Foreman / Sarge / Inspector / Code-Reviewer / Build-Fixer defined | M7 |
| `workflow.md` | Board column model (Parking → Pitch → ... → Done) + commander's intent | M7 |
| `MIGRATION.md` | Source SHAs + before/after path map from monorepo consolidation | M2 |

## Style

- Optimize for **agent legibility first, human second** — short paragraphs, tables, clear headings, no narrative bloat
- Every doc has a frontmatter block declaring purpose + when_to_read

## Status

Empty in v0.1.0-pre. Populated incrementally across milestones.
