# config/

Hooks + settings + env-var bootstrap.

## V1 files

| File | Purpose | Milestone |
|---|---|---|
| `agent.sh` | `$AGENT` + model + budget defaults (Claude Code default, Codex tested adapter) | M3 |
| `env.sh` | `PRODUCT_SQUAD_*` env var bootstrap (paths, repos, escalation user, etc.) | M2 |
| `settings.template.json` | 5-10 documented Claude Code hook examples | M6 |

## Hook examples planned (M6)

- `PreToolUse` — warn before destructive Bash commands
- `SessionStart` — surface most-recently-changed files
- `UserPromptSubmit` — inject project-context reminder
- `OnError` — capture stack traces for later review
- Permission patterns showing how to allow common safe Bash commands

## Conventions

- Templates are safe-by-default: no destructive defaults, no auto-network
- All hooks are documented in `docs/hooks.md` (M6) with when-to-use + debugging notes
- Settings.json is Claude Code-specific; other agents use their own equivalents (Cursor `.cursorrules`, Aider `.aider.conf.yml`)

## Status

Empty in v0.1.0-pre. Populated across M2 (env.sh), M3 (agent.sh), M6 (settings + hooks).
