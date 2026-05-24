# Product Squad

An opinionated agentic operating system for one-person dev teams.

> 🚧 **V0.5 — first playable cut.** Private during validation. Public at V1 (3-4 weeks).

## The 30-second demo

```bash
git clone git@github.com:jorjani/product-squad.git
cd product-squad
./bin/scope "I want users to save articles for later"
# → prints /shape brief + /owit scenarios + /elon ruthless cut
```

Requires Claude Code installed + `ANTHROPIC_API_KEY` set. Full setup in [`QUICKSTART.md`](QUICKSTART.md).

## What this is

A named crew of AI agents that owns the software dev pipeline — scope, build, review, verify — while you set direction. The repo is **agent-first**: an LLM agent can clone this, read [`AGENTS.md`](AGENTS.md) + [`manifest.yaml`](manifest.yaml), and orient in 60 seconds.

## The crew

| Agent | Role | V0.5 status |
|---|---|---|
| **Foreman** | Orchestrator | snapshot only — readable, not runnable |
| **Sarge** | PM scoping (idea → brief) | scoping prompts runnable via `bin/scope`; full runtime in V1 |
| **Inspector** | Verifier (Verify → Done gate) | snapshot only — lives inside Foreman |
| **Code-Reviewer** | PR review with severity-ranked findings | runnable as a Claude Code subagent |
| **Build-Fixer** | Minimal-diff repair for failing builds | runnable as a Claude Code subagent |

V1 (3-4 weeks): full runtime for all five, agent abstraction (Claude default + Codex tested), Railway one-click deploy, memory pattern, public launch.

## Quick orientation

| Audience | Start here |
|---|---|
| 🤖 LLM agent | [`AGENTS.md`](AGENTS.md) → [`manifest.yaml`](manifest.yaml) |
| 👤 Human | [`QUICKSTART.md`](QUICKSTART.md) → run the demo |
| 🛠 Forker | Read [`commands/shape.md`](commands/), [`commands/owit.md`](commands/), [`commands/elon.md`](commands/) |

## Layout

```
bin/scope      # V0.5 scoping-ladder demo
commands/      # /shape, /owit, /elon prompts (the scoping ladder)
examples/      # fixture idea for the demo
agents/        # snapshots: foreman, sarge, code-reviewer, build-fixer
docs/          # MIGRATION.md + roadmap
```

See [`manifest.yaml`](manifest.yaml) → `v1_roadmap` for what lands in V1.

## License

[MIT](LICENSE)
