# Product Squad

An opinionated agentic operating system for one-person dev teams.

> 🚧 **V1 in development.** Public launch planned. This repo is currently private during scaffolding.

## What this is

A named crew of AI agents that owns the full software dev pipeline — scope, build, review, verify — while you set direction. Runs on your laptop or in the cloud. Works with Claude Code (default) or Codex CLI (tested adapter). Apache-2.0... wait, MIT. The repo design is **agent-first**: an LLM agent can clone this, read `AGENTS.md` + `manifest.yaml`, and know how to contribute in seconds.

## The crew

- **Foreman** — orchestrator: builds, reviews, verifies, triages, cleans up
- **Sarge** — PM agent: turns vague ideas into buildable specs (Claude Code only in V1)
- **Inspector** — verifier: gates Verify → Done with deterministic classes + LLM judge
- **Code-Reviewer** — PR review with severity-ranked findings
- **Build-Fixer** — minimal-diff repair for failing builds and tests

## Quick orientation

| Audience | Start here |
|---|---|
| 🤖 You're an LLM agent | [`AGENTS.md`](AGENTS.md) → [`manifest.yaml`](manifest.yaml) |
| 👤 You're a human evaluating | This README → [`docs/tool-choices.md`](docs/) (coming in M5) |
| 🛠 You want to deploy | [`QUICKSTART.md`](QUICKSTART.md) (coming in M5: Railway smooth path + laptop hacker path) |

## Layout

```
agents/        # The crew (Foreman, Sarge, Inspector, Code-Reviewer, Build-Fixer)
commands/      # Curated dev-workflow slash commands
cloud/         # Deploy paths (Railway smooth + laptop hacker)
guardrails/    # Opinionated rules + audit playbook
memory/        # Agent-agnostic persistent memory pattern
config/        # Hooks, settings, env-var bootstrap
mcp/           # MCP scoping conventions
lib/           # Shared utilities (agent abstraction layer)
docs/          # Tool choices, customization, glossary
```

## Status

V1 milestone plan tracked in `~/.claude/plans/what-would-it-take-golden-rivest.md` (private during scaffolding). Each milestone ships via the worktree + branch + PR pattern.

## License

[MIT](LICENSE)
