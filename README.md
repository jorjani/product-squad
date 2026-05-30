# Product Squad

An opinionated agentic operating system for one-person dev teams.

> 🚧 **V0.5 — first playable cut.** Public for validation; pre-1.0 surface, expect change.

## Install

Two paths. Use the first when it's available; fall back to the second.

**Claude Code marketplace** *(submission pending — see [#11](https://github.com/jorjani/product-squad/issues/11))*

```bash
/plugin marketplace add jorjani/product-squad
/plugin install product-squad@product-squad
```

Surfaces `/product-squad:visualize`, `/product-squad:scope`, `/product-squad:onboard` in Claude Code without you cloning anything.

**Clone and run**

```bash
git clone https://github.com/jorjani/product-squad.git
cd product-squad
./draw "your feature idea"
```

When CWD is the bundle directory, Claude Code auto-discovers `/visualize`, `/scope`, `/onboard` from `.claude/commands/` — no install step.

## The 30-second demos

Two wedges, both single-command. Pick either or run both.

### 🎨 Visual ladder (PRIMARY)

```bash
git clone git@github.com:jorjani/product-squad.git
cd product-squad
./draw "users configure notification preferences across email, push, and in-app channels"
# → sketch (ASCII in terminal) + wireframe.html + mockup.html + prototype.html
# → each HTML auto-opens in your browser (macOS); Linux prints the file path
```

Time: ~60-120 seconds. Cost: ~$0.30-0.50 in Claude Code subscription usage.

**Switch brand flavor** to see the same idea rendered in a different aesthetic vocabulary:

```bash
FLAVOR=apple ./draw "users configure notification preferences across email, push, and in-app channels"
# Other flavors: linear (default) · airbnb · uber
# See .studio/design.md for the full set + how to author your own.
```

### 🧠 Product cluster (SECONDARY)

```bash
./scope "users configure notification preferences across email, push, and in-app channels"
# → writes 5 pre-filled prompts to /tmp/product-squad-scope-<ts>/
# → paste each into Claude Code in sequence (why → shape → experience → owit → elon)
```

Each stage teaches a transferable product-craft pattern. Time: ~15-30 min of paste-and-think.

### Requirements

- **Claude Code installed** and signed in (`claude /login` once with your subscription account)
- **No API key required** — uses subscription OAuth
- ⚠️ If `ANTHROPIC_API_KEY` is set in your env, it *shadows* subscription auth and may fail with org-mismatch errors. Run `unset ANTHROPIC_API_KEY` first.

Full setup in [`QUICKSTART.md`](QUICKSTART.md).

## What this is

A named crew of AI agents that owns the software dev pipeline — scope, build, review, verify — while you set direction. The repo is **agent-first**: an LLM agent can clone this, read [`AGENTS.md`](AGENTS.md) + [`manifest.yaml`](manifest.yaml), and orient in 60 seconds.

## The crew

| Agent | Role | V0.5 status |
|---|---|---|
| **Foreman** | Orchestrator | snapshot only — readable, not runnable |
| **Sarge** | PM scoping (idea → brief) | scoping prompts runnable via `scope`; full runtime in V1 |
| **Inspector** | Verifier (Verify → Done gate) | snapshot only — lives inside Foreman |
| **Code-Reviewer** | PR review with severity-ranked findings | runnable as a Claude Code subagent |
| **Build-Fixer** | Minimal-diff repair for failing builds | runnable as a Claude Code subagent |

V1 (3-4 weeks): full runtime for all five, agent abstraction (Claude default + Codex tested), Railway one-click deploy, memory pattern, public launch.

## Quick orientation

| Audience | Start here |
|---|---|
| 🤖 LLM agent | [`AGENTS.md`](AGENTS.md) → [`manifest.yaml`](manifest.yaml) |
| 👤 Human | [`QUICKSTART.md`](QUICKSTART.md) → run a demo |
| 🛠 Forker | Visual ladder: [`sketch`](commands/sketch.md) → [`wireframe`](commands/wireframe.md) → [`mockup`](commands/mockup.md) → [`prototype`](commands/prototype.md) · Product cluster: [`why`](commands/why.md) → [`shape`](commands/shape.md) → [`experience`](commands/experience.md) → [`owit`](commands/owit.md) → [`elon`](commands/elon.md) |

## Layout

```
bin/
  visual         # PRIMARY demo — visual fidelity ladder
  scope          # SECONDARY demo — commander's intent + scoping
commands/        # 10 prompts (5 visual + 5 product)
.studio/         # Bundled generic design tokens + component primitives
examples/        # Idea fixtures + phrasing guidance
agents/          # Snapshots: foreman, sarge, code-reviewer, build-fixer
docs/            # MIGRATION.md (source SHAs + scrub log) + roadmap
```

See [`manifest.yaml`](manifest.yaml) → `v1_roadmap` for what lands in V1.

## License

[MIT](LICENSE)
