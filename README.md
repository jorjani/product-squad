# Product Squad

An opinionated agentic operating system for one-person dev teams.

> **v0.10.0 — 66 skills.** See [RELEASE-NOTES.md](RELEASE-NOTES.md) for what shipped.

## Install

Two paths.

**Claude Code marketplace**

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

When CWD is the bundle directory, Claude Code auto-discovers `/visualize`, `/scope`, `/onboard` from `.claude/skills/` — no install step.

## Use with your agent (no install)

Point any coding agent at this repo and let it pick skills that match your current work:

```
Read https://github.com/jorjani/product-squad/blob/main/llms.txt and pick the
3 skills most relevant to what I'm working on right now. Fetch each skill's
SKILL.md and apply it.
```

[`llms.txt`](llms.txt) is a one-line-per-skill catalog generated from each skill's frontmatter. Every skill is a standalone markdown file — no runtime, no dependencies — so any agent that can read a URL can use them. [`AGENTS.md`](AGENTS.md) is the operator brief if the agent needs the mental model behind the bundle.

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
# See design-system/design.md for the full set + how to author your own.
```

### 🧠 Product cluster (SECONDARY)

```bash
./scope "users configure notification preferences across email, push, and in-app channels"
# → writes 7 pre-filled prompts to /tmp/product-squad-scope-<ts>/
# → paste each into Claude Code in sequence (why → vet → shape → experience → owit → elon → spec)
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
| 🛠 Forker | Visual ladder: [`sketch`](skills/sketch/SKILL.md) → [`wireframe`](skills/wireframe/SKILL.md) → [`mockup`](skills/mockup/SKILL.md) → [`prototype`](skills/prototype/SKILL.md) · Product cluster: [`why`](skills/why/SKILL.md) → [`shape`](skills/shape/SKILL.md) → [`experience`](skills/experience/SKILL.md) → [`owit`](skills/owit/SKILL.md) → [`elon`](skills/elon/SKILL.md) |

## Command skills

Beyond the scoping cluster and visual ladder, 40 single-purpose skills — each `skills/<name>/SKILL.md`, auto-discovered by Claude Code. Grouped by what they touch:

**UI & design audits** — judge or fix a built surface.
- [`a11y`](skills/a11y/SKILL.md) — WCAG AA color-contrast audit (Python math, flag + fix)
- [`crap`](skills/crap/SKILL.md) — visual-hierarchy audit (Contrast/Repetition/Alignment/Proximity)
- [`brand-audit`](skills/brand-audit/SKILL.md) — brand-token consistency, doc vs. code
- [`ux-design`](skills/ux-design/SKILL.md) — post-build UX completeness (states, a11y, responsive)
- [`qa`](skills/qa/SKILL.md) — browser QA of a running app via Playwright MCP
- [`imagine`](skills/imagine/SKILL.md) — text-to-image via fal.ai (needs `FAL_KEY`)

**Harness & context audits** — keep the environment lean.
- [`harness-audit`](skills/harness-audit/SKILL.md) — config health (hooks, permissions, commands, agents, memory)
- [`context-diet`](skills/context-diet/SKILL.md) — always-loaded context budget (HOT/WARM/COLD)
- [`usage-audit`](skills/usage-audit/SKILL.md) — live token-burn diagnosis

**Eng tighteners** — scope, verify, and build with discipline.
- [`pm`](skills/pm/SKILL.md) — PM scoping interview — find the underlying job
- [`architecture`](skills/architecture/SKILL.md) — system design before tickets (pattern, boundaries, deps, alternatives) — sits between `/spec` and `/decompose`
- [`build`](skills/build/SKILL.md) — autonomous feature-pipeline orchestrator
- [`eng-deep-dive`](skills/eng-deep-dive/SKILL.md) — pre-implementation reality check vs. code
- [`eng-review`](skills/eng-review/SKILL.md) — adversarial architecture review of a plan
- [`investigate`](skills/investigate/SKILL.md) — systematic root-cause debugging
- [`refactor`](skills/refactor/SKILL.md) — behavior-preserving restructure (smell → pattern → blast radius → safe steps)
- [`verify`](skills/verify/SKILL.md) — terminal "prove it ran" gate
- [`ship`](skills/ship/SKILL.md) — sync base → test → review → commit → push → PR, one pass
- [`release`](skills/release/SKILL.md) — cut a versioned release: last tag → semver bump from commit conventions → grouped notes → tag/push/GitHub Release, behind a dry-run preview (batch primitive to `/ship`'s per-PR one)
- [`pr-review`](skills/pr-review/SKILL.md) — open-PR dashboard + two-pass subagent review (present-only)

**Spec contracts** — turn a spec into a build-and-test-ready interface.
- [`flow`](skills/flow/SKILL.md) — UI state-transition contract (per-state ASCII + edge table)
- [`api`](skills/api/SKILL.md) — backend API contract (endpoints, auth, shapes, error codes, idempotency)

**Brand & naming** — name it, then claim the domain.
- [`namer`](skills/namer/SKILL.md) — startup naming agent (Placek sound-symbolism + Igor 9-category rubric)
- [`domain-check`](skills/domain-check/SKILL.md) — domain availability across TLD tiers (whois + DNS dig)

**Product** — shape the idea, scope it, cut it, stress-test the call.
- [`pitch-draft`](skills/pitch-draft/SKILL.md) — raw idea → Shape Up pitch (problem · appetite · solution sketch · rabbit holes · no-gos); feeds `/shape` + `/spec`
- [`scope-item`](skills/scope-item/SKILL.md) — accepted pitch → AC-ready backlog item (observable ACs · decision points · files likely touched · success test); pairs with `/pitch-draft` upstream, `/decompose` downstream
- [`mochary`](skills/mochary/SKILL.md) — big-picture priority coach (Mochary frame): the one thing that matters
- [`simplify`](skills/simplify/SKILL.md) — Tesla's 5-step Algorithm on something that feels finished (scope-cut family with `/elon`)
- [`grill`](skills/grill/SKILL.md) — adversarial Socratic stress-test before commitment (third hardener with `/elon` + `/eng-review`)

**Thinking Primitives** — forcing functions before you build, organized in bands (rungs):

```
Frame: /why /goal /who
Kill:  /grill /elon /vet
Bound: (Rung 3, coming)
```

_Frame band (Rung 1) and Kill band (Rung 2) shipped; Bound band lands in a later wave. Kill-band skills are cross-listed from their original clusters._

- [`why`](skills/why/SKILL.md) — frame the outcome / job one level above the stated task
- [`goal`](skills/goal/SKILL.md) — pin the measurable target + falsifier (catches activity-as-outcome, no-measure, unfalsifiable wins)
- [`who`](skills/who/SKILL.md) — name the specific user in a specific scenario (guards against generic-audience drift)
- [`grill`](skills/grill/SKILL.md) — adversarial pre-commitment probe: strongest counter-argument, weakest assumption, worst case, hedges
- [`elon`](skills/elon/SKILL.md) — ruthless cut (the Algorithm): Build / Rethink / Kill
- [`vet`](skills/vet/SKILL.md) — mission-fit kill: Serves / Tangential / Off-mission

**Agentic patterns** — building blocks for autonomous agents.
- [`agent-question`](skills/agent-question/SKILL.md) — route an agent's decision to a human: experience-altitude framing, numbered options, real-time vs. batched routing, confidence gate, state tracking

**Safety** — guardrails against destructive commands.
- [`guard`](skills/guard/SKILL.md) — session safety mode: destructive-command denylist confirmation + an Edit/Write boundary

**Session hygiene** — start, orient, and close out a working session.
- [`getting-started`](skills/getting-started/SKILL.md) — first-run plugin orientation: what's installed, starter commands, a 5-minute build path
- [`pickup`](skills/pickup/SKILL.md) — resume from prior-session notes
- [`checkpoint`](skills/checkpoint/SKILL.md) — mid-session status snapshot
- [`retro`](skills/retro/SKILL.md) — post-session process retrospective
- [`debrief`](skills/debrief/SKILL.md) — meeting/notes → decisions + actions
- [`sessions`](skills/sessions/SKILL.md) — list recent Claude Code sessions
- [`sync-repos`](skills/sync-repos/SKILL.md) — fast-forward every repo in a workspace folder; report what needs judgment
- [`list-capabilities`](skills/list-capabilities/SKILL.md) — enumerate installed skills + commands
- [`todo`](skills/todo/SKILL.md) — per-project task parking lot (TODO.md-backed)

## Example skills (sample integrations)

Provider/stack-specific skills that demonstrate a transferable pattern using one concrete provider as the worked example. Marked **optional** in [`manifest.yaml`](manifest.yaml) under `optional_skills` — a distinct tier from the command skills above, not loaded as defaults. Install on demand and swap the provider for your own stack.

- [`notification-setup`](skills/notification-setup/SKILL.md) — verify a transactional email sending domain (DKIM/SPF/DMARC) for **AWS SES**. Pattern transfers — swap the provider (Resend, Postmark, SendGrid).
- [`dns-setup`](skills/dns-setup/SKILL.md) — manage DNS records (list/add/delete) via **Cloudflare** scripts. Pattern transfers — swap the provider (Route 53, Porkbun).
- [`deploy-status`](skills/deploy-status/SKILL.md) — walk the deploy chain for a commit on **Railway** (read-only). Pattern transfers — swap the platform (Render, Fly, Vercel).
- [`deploy-trigger`](skills/deploy-trigger/SKILL.md) — pre-flight checklist + deploy on **Railway**. Pattern transfers — swap the platform.
- [`analytics-setup`](skills/analytics-setup/SKILL.md) — wire client-side product analytics with **PostHog** (init → identify → signout → events). Pattern transfers — swap the SDK (Amplitude, Mixpanel).
- [`weekly-review`](skills/weekly-review/SKILL.md) — weekly review-and-reset ritual (generic cadence). Adapt the data sources to your own logs.
- [`worktree-cleanup`](skills/worktree-cleanup/SKILL.md) — prune provably-merged **git worktrees** with ordered safety gates. Pattern transfers — skip the agent-owned check if you don't run one.
- [`ship-ready-check`](skills/ship-ready-check/SKILL.md) — 4-gate readiness check before an autonomous build, using **GitHub issues** as the example. Pattern transfers — swap the tracker + builder.

## Layout

```
bin/
  visual         # PRIMARY demo — visual fidelity ladder
  scope          # SECONDARY demo — commander's intent + scoping
skills/          # scoping cluster + visual ladder + 21 command skills, each <name>/SKILL.md
design-system/   # Bundled generic design tokens + component primitives
examples/        # Idea fixtures + phrasing guidance
agents/          # Snapshots: foreman, sarge, code-reviewer, build-fixer
docs/            # MIGRATION.md (source SHAs + scrub log) + roadmap
```

See [`manifest.yaml`](manifest.yaml) → `v1_roadmap` for what lands in V1.

## Author

Built by [David Jorjani](https://www.linkedin.com/in/jorjani/) — Lead, Product and Tech at Harvard Business School Foundry; teaches software engineering and applied computing in the Department of Computer Science at the University of Toronto. Prior experience leading product and tech teams at 7 startups.

## License

[MIT](LICENSE)
