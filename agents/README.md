# agents/

The named crew lives here. Forked snapshots of David's running pipeline as of V0.5 — see [`../docs/MIGRATION.md`](../docs/MIGRATION.md) for source SHAs, what was excluded, what was scrubbed, and the rebase protocol.

## V0.5 layout

- **foreman/** — bash orchestrator + 18 phases + Inspector (lives inside as `phases/inspect.sh` + `prompts/inspect-*.md`). Snapshot only — readable, not runnable on a different machine in V0.5.
- **sarge/** — PM agent prompts + `agent-team-spec.md` + `BUILD-BRIEF.md` + `sarge-subagent.md`. Scoping prompts run via `bin/scope` at the repo root; full interactive Sarge arrives V1.
- **code-reviewer.md** — Claude Code subagent definition (single .md file). Drop into your `~/.claude/agents/` to use.
- **build-fixer.md** — Claude Code subagent definition (single .md file). Most portable in the bundle — zero couplings.

## Per-agent V0.5 status

| Agent | V0.5 runnable | Read this for context |
|---|---|---|
| Foreman | ❌ snapshot | `agents/foreman/CLAUDE.md` |
| Sarge | ✅ partial (via `bin/scope`) | `agents/sarge/CLAUDE.md` + `agents/sarge/BUILD-BRIEF.md` |
| Inspector | ❌ lives in Foreman | `agents/foreman/phases/inspect.sh` |
| Code-Reviewer | ✅ subagent | `agents/code-reviewer.md` |
| Build-Fixer | ✅ subagent | `agents/build-fixer.md` |

## Conventions

- Subagent `.md` files use YAML frontmatter compatible with Claude Code (and portable to other agent systems via simple translation in V1).
- Multi-file agents (`foreman/`, `sarge/`) have a `CLAUDE.md` orienting an LLM to the codebase. `CONTRACT.md` files (per-agent I/O schema) arrive in V1.

## Inspector — why it lives in foreman/

Inspector has no standalone runtime — it exists entirely as foreman phases + prompts + libs. Pulling it out would scatter the orchestrator. It's a Foreman phase with its own internal contract, not a separate dispatch surface.

## Honest framing

Read `agents/foreman/` and `agents/sarge/` as **documentation of an opinionated system that runs on the original author's box**, not as portable code you can `./orchestrator.sh` against your own GitHub org. The V0.5 demo path (`bin/scope` + `commands/` + `examples/`) IS scrubbed and IS runnable. V1 (3-4 weeks) ships the full portability fixes.
