# agents/foreman/

Snapshot of the **Foreman** orchestrator — the autonomous daily pipeline that ships PRs, reviews them, verifies merged code, and triages incoming work.

**V0.5 status: readable, not runnable.** This snapshot exists for context (so you can read the system, learn from it, and adopt patterns). Full runtime portability ships in V1.

## What Foreman does

Foreman is a bash-orchestrated 18-phase daily pipeline. Each cron tick (5×/day):

1. **Verify** — check merged PRs actually deployed
2. **Inspect + Code-Review** (parallel) — gate Verify→Done; review open PRs
3. **Review** — auto-merge clean `auto/*` PRs; queue human PRs for code review
4. **Build** — pick up Ready issues, create worktree, run Claude, ship PR
5. **Triage** — promote Scope items to Ready if they pass contract gates
6. **Sarge-Review + Sarge-Pitch** — dispatch Sarge subagent on Scope + Pitch items
7. **Auto-enrich** — mechanically fill `NEEDS-SPEC` gaps
8. **Cleanup + Ghost-sweep + Orphan-rescue + Stranded-sweep + Janitor** — repo hygiene
9. **Self-improve** (alternate days) — analyze metrics, propose prompt changes

Each phase has a dedicated script in `phases/`. Shared utilities in `lib/`. Prompts in `prompts/`. Schedule in `config/schedule.plist` (macOS launchd; V1 ships Linux cron + Railway).

## How to read this snapshot

| File | What it tells you |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Foreman's full operational model (board flow, phases, escalation, design system awareness, lessons) |
| [`orchestrator.sh`](orchestrator.sh) | Entry point — the loop that runs phases in order with bounded execution |
| [`phases/build-ticket.sh`](phases/build-ticket.sh) | Per-ticket build executor — worktree creation, Claude dispatch, PR creation, retry logic |
| [`phases/inspect.sh`](phases/inspect.sh) | Inspector v1 — Verify→Done gate via refactor-allowlist + LLM classify+judge |
| [`phases/code-review.sh`](phases/code-review.sh) | Code-reviewer dispatch + auto-merge gate |
| [`prompts/build.md`](prompts/build.md) | The autonomous build prompt |
| [`config/board-ids.sh`](config/board-ids.sh) | GitHub Project board IDs (currently hardcoded to `getqatalyst` board #5; V1 parameterizes) |

## V0.5 ≠ V1 (what won't run for you)

Reading the bundle as documentation is the right V0.5 framing. Trying to run `./orchestrator.sh` will hit:

- Hardcoded `FOREMAN_HOST=MacBook-Pro-2.local` in `config/env.sh:47` (V1 removes default)
- `~/Projects/.index.json` lookup at `lib/repos.sh:16` (V1 makes optional + adds existence check)
- `PROJECT_ORG=getqatalyst` + `PROJECT_NUMBER=5` in `config/board-ids.sh` (V1 parameterizes via env)
- `stat -f %m` macOS-only call at `orchestrator.sh:97` (V1 adds Linux portability)
- `date +%-d` BSD-only at `orchestrator.sh:582` (V1 fixes)
- Personal user references (`jorjani` in code-review allowlist; V1 strips ~173 `getqatalyst` refs + ~9 `jorjani` refs)

The V1 hidden-coupling fix list lives in top-level `manifest.yaml` → `v1_roadmap.portability_fixes`.

## Inspector lives inside

There's no `agents/inspector/` — Inspector is a Foreman *phase*, not a freestanding agent. The implementation is split across:

- [`phases/inspect.sh`](phases/inspect.sh) — the phase script (deterministic auto-promote allowlist + LLM fallback)
- [`lib/inspect.sh`](lib/inspect.sh) — shared helpers
- [`prompts/inspect-classify.md`](prompts/inspect-classify.md) — Haiku-tier file-extension classifier
- [`prompts/inspect-judge.md`](prompts/inspect-judge.md) — Sonnet-tier evidence judge

Promoting Inspector to a freestanding agent in `agents/inspector/` was considered + rejected — Inspector has zero standalone runtime and is tightly coupled to Foreman's column model + log streams. Documented in [`../README.md`](../README.md).

## What to take away even without running it

Read [`CLAUDE.md`](CLAUDE.md)'s "Lessons" section. It captures hard-won operational discoveries:
- Bash 3.2 (macOS default) doesn't support `declare -A`
- Foreman writes two log streams; grep both when investigating
- Comment-prefix dedup via `comment_dedup_or_escalate` prevents noise loops
- `repo_to_path` derived from `.index.json` beats per-file case-statement drift
- Project status (`archived|parked|inactive`) is the strongest build-eligibility signal
- `gh project item-list --format json` silently truncates at `--limit N`

These are transferable lessons even if you build your own orchestrator in a different language.

## V1 promises

- Linux portability (drop launchd → cron/systemd/Railway)
- `lib/agent.sh` abstraction so `$AGENT=codex` swaps the backend
- Full scrub of personal identifiers + private project refs
- Railway one-click Deploy button + Dockerfile
- Sarge `headless` one-shot mode for non-Claude-Code agents
- Memory pattern adapters per agent

Track in top-level `manifest.yaml` → `v1_roadmap`.
