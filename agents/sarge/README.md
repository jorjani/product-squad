# agents/sarge/

Snapshot of **Sarge** — the PM agent that scopes ideas into buildable specs. Interviews the operator, recons the codebase, writes commander's intent briefs, advances the board.

**V0.5 status: readable + partially runnable.**

- ✅ **Runnable via `bin/scope`** — the scoping ladder (why → shape → experience → owit → elon) ships as `commands/` in the bundle root. Paste each prompt into Claude Code; get a brief.
- ❌ **Full Sarge runtime is V1** — the interactive C0–C5 phase flow (with `/decompose` skill, `/gh-issue` skill, GitHub Project board mutations, `.index.json` project lookup, foreman/config/board-ids.sh sourcing) is tightly coupled to David's setup. V1 ships a `headless` one-shot variant for any agent CLI.

## How Sarge thinks

The three-layer model (see [`agent-team-spec.md`](agent-team-spec.md)):

- **David (the operator)** — sets direction, picks options, makes decisions. Mobile-first.
- **Sarge (this agent)** — interviews + recons + writes briefs + curates the board. Never builds.
- **Foreman** — picks up Sarge's Ready briefs, builds PRs, reviews, verifies, ships.

Sarge's job: turn a vague idea into a buildable scope that passes Foreman's contract gates (Goal, AC, Context, Out-of-Scope).

## How to read this snapshot

| File | What it tells you |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Sarge's full operating model — board flow, C0-C5 phases, escalation, body-size pre-checks, user-experience-language pre-checks |
| [`agent-team-spec.md`](agent-team-spec.md) | The three-layer mental model (operator + Sarge + Foreman) + roles + comms protocol |
| [`BUILD-BRIEF.md`](BUILD-BRIEF.md) | The original Sarge build brief — Sarge scoping itself (recursive). Note: personal business-priority disclosure block was scrubbed in V0.5 per audit findings; pointer to `.index.json` priority field replaces it. |
| [`pipeline-workflow.md`](pipeline-workflow.md) | The Pitch → Scope → Backlog → Ready board flow Sarge manages |
| [`sarge-subagent.md`](sarge-subagent.md) | The Claude Code subagent definition (drop into your `~/.claude/agents/`; note V0.5 hardcodes David's `~/Projects` — V1 generalizes via the escape-hatch pattern from code-reviewer.md) |

## The scoping ladder (what's runnable today)

Sarge's prompt corpus ships as 5 standalone slash commands in the bundle root's `commands/` directory. Run them via `bin/scope`:

| Command | What it teaches |
|---|---|
| [`commands/why.md`](../../commands/why.md) | Outcome framing (job-to-be-done) |
| [`commands/shape.md`](../../commands/shape.md) | Decide what to build (Shape Up: options menu + capability delta + cuts) |
| [`commands/experience.md`](../../commands/experience.md) | Articulate the user delta in observable terms |
| [`commands/owit.md`](../../commands/owit.md) | Scenario specification (On/When/If/Then) + Choices |
| [`commands/elon.md`](../../commands/elon.md) | The Algorithm: question, delete, simplify, accelerate, automate |

```bash
./bin/scope "your feature idea in one sentence"
```

Writes 5 pre-filled prompt files to `/tmp/product-squad-scope-<ts>/`. Paste each into Claude Code in sequence.

## What's NOT in V0.5

The interactive full-flow Sarge subagent (C0 prioritize → C1 interview → C2 recon → C3 brief → C4 curate → C5 status) requires:

- Claude Code with subagent support (`subagent_type: "sarge"` dispatch)
- A GitHub Project board configured the way David's is (`getqatalyst` org, project #5, specific Status/Priority/Size field IDs)
- A populated `~/Projects/.index.json` with project aliases + codes + priority field
- `~/Projects/foreman/config/board-ids.sh` sourced for board mutation helpers
- The `/decompose`, `/gh-issue`, `/shape`, `/wireframe`, `/flow` skill ecosystem in `~/.claude/commands/`
- A `tools/minions/overlap-check.ts` Minion for deterministic data fetching

V1 ships a `CONTRACT_HEADLESS.md` and a one-shot `sarge-headless` prompt that takes `(idea, repo, board-context)` and emits `{title, body, board_status, decision_needed?, questions?}` JSON — runnable from any agent CLI without the full ecosystem.

## What to take away even without running it

Read [`CLAUDE.md`](CLAUDE.md)'s sections:

- **Your Process** (C0–C5) — the interview → recon → brief → curate loop
- **Body Size Pre-check** — the < 4,800 char limit + spec-doc extraction pattern
- **User-experience language pre-check** — never use engineering identifiers in Scenarios/UI sections (`Looking at X, I see Y` framing, not `the .userTable component`)
- **Board Flow** — the Pitch/Scope/Backlog/Ready/In Progress/In Review/Verify/Done columns

These are transferable patterns even if you're not running the full pipeline.

## V1 promises

- Sarge `headless` mode: non-interactive one-shot variant for any agent CLI
- Board mutation generalized via env-var-driven board IDs (no more `getqatalyst` hardcoding)
- `.index.json` schema documented as an adopter contract
- Escape-hatch pattern in `sarge-subagent.md` (matching code-reviewer.md's `or the target repo's path` line)

Track in top-level `manifest.yaml` → `v1_roadmap.sarge_headless`.
