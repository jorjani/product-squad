# agents/

The named crew lives here. Each agent has its own subdirectory (or single .md file for subagents) with prompts, contracts, and supporting code.

## Layout (after M2 consolidation)

- **foreman/** — bash orchestrator + 18 phases + Inspector (lives inside as `phases/inspect.sh` + `prompts/inspect-*.md`)
- **sarge/** — PM agent prompts + `agent-team-spec.md` + headless mode contract
- **code-reviewer.md** — subagent definition (single .md file)
- **build-fixer.md** — subagent definition (single .md file)

## Conventions

- Each agent dir has a `CONTRACT.md` describing inputs, outputs, and any I/O schema
- Multi-file agents have a `README.md` orienting an LLM to the codebase
- Subagent .md files use YAML frontmatter compatible with Claude Code (and portable to other agent systems via simple translation)

## Inspector — why it lives in foreman/

Inspector is not a freestanding agent — it has zero standalone runtime, exists entirely as foreman phases + prompts + libs, and pulling it out would scatter the orchestrator. It's a phase of Foreman with its own contract.

## Status

Empty in v0.1.0-pre. Populated in M2 (consolidation milestone).
