# memory/

Agent-agnostic persistent memory pattern. The system any operator (and any agent) can use to remember user preferences, project facts, behavioral corrections, and references to external systems across sessions.

## 🚨 PRIVACY WARNING (read first)

**Your memories contain personal feedback, corrections, and project facts. Never commit them.**

The `.gitignore` in this directory excludes all `.md` files by default except:
- `README.md` (this file)
- `MEMORY.md.example` (the index format template)
- `template/` (fictional example memories)
- `adapters/` (per-agent setup snippets)
- `bin/` (the CLI helper)

**Verify the gitignore is in effect before saving anything sensitive:**
```bash
git check-ignore memory/my-actual-memory.md
# Should print: memory/my-actual-memory.md
```

If you accidentally stage real memories, do NOT commit. Run `git restore --staged memory/<file>.md` and add to your local-only `.git/info/exclude` if you need a non-gitignored path.

## The four memory types

| Type | What it stores | Example |
|---|---|---|
| `user` | Identity, role, preferences | "User is a senior backend eng new to React" |
| `feedback` | Behavioral corrections | "User prefers terse responses; skip trailing summaries" |
| `project` | Project facts that survive `/clear` | "Repo uses Bun, not Node; use `bun` commands" |
| `reference` | External-system bookmarks | "Linear project 'INGEST' tracks data pipeline bugs" |

## How loading works per agent

- **Claude Code:** Auto-loads everything in `memory/` into session context (set up via `additionalDirectories`)
- **Codex / Aider / Cursor / OpenCode:** Add the snippet from `adapters/<agent>.md` to your system prompt — tells the agent to read `memory/MEMORY.md` at session start and follow links
- **Any agent with shell:** `bin/memory get <name>`, `bin/memory grep <query>`, `bin/memory save <type> "<content>"`

## Status

Empty in v0.1.0-pre except this README + the privacy guardrails. Templates + CLI + adapter docs populate in M6 (memory + hooks + MCP milestone).
