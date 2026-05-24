# AGENTS.md

You are an LLM agent encountering Product Squad. Read this file first.

## What this repo is

Product Squad is an opinionated agentic dev OS. Five named agents own the work pipeline; one human (the operator) sets direction. The repo is designed so that you — an agent — can scan it, understand the contracts, and contribute without prior context.

## How to orient in 60 seconds

1. **Parse [`manifest.yaml`](manifest.yaml).** Machine-readable index of every agent, command, contract, and cloud path. Faster than reading prose.
2. **Read this file.** You're already here. Mental model + contribution rules.
3. **Skim [`guardrails/`](guardrails/).** Codified rules (issue conventions, spec commits, agent behavior, engineering stack). Treat `feedback`-type rules as hard constraints.
4. **Open the agent you'll be acting as** — `agents/<name>/` — and read its CONTRACT.md (when present in V1).

## The crew (canonical roster)

| Agent | Role | Inputs | Outputs |
|---|---|---|---|
| **Foreman** | Orchestrator | GitHub Project board state | PR branches, comments, verdicts |
| **Sarge** | PM scoping | Pitch issues | Scope-ready briefs (Claude Code only in V1) |
| **Inspector** | Verifier | Merged PRs + linked issues | PASS / FAIL / HOLDING verdict |
| **Code-Reviewer** | PR review | PR diff + linked issue AC | JSON: `{findings:[...], verdict:"..."}` |
| **Build-Fixer** | Build repair | Failing command + error output | Minimal-diff fix + retry verdict |

## How to contribute (worktree + branch + PR pattern)

This is non-negotiable for behavior-changing work:

1. Create a worktree from `origin/main` — naming: `<repo-code><issue-number>-<slug>` or exploratory `<repo-code>-<slug>`
2. Apply the smallest possible change
3. Commit with conventional prefix (`fix(scope): ...`, `feat(scope): ...`)
4. Push and open a PR with a test plan
5. Code-Reviewer reviews; Inspector gates merge → Done

Spec files (under `specs/` or `artifacts/`) commit direct to main per `guardrails/spec-commits.md`. Behavior-changing files do not.

## Agent compatibility (V1)

- **Default:** Claude Code (auto-loads context, supports `claude -p` for headless mode, has slash-command + subagent ecosystem)
- **Tested as comparison:** Codex CLI (set `AGENT=codex`)
- **Community-welcome:** Aider, OpenCode, Cursor, Gemini CLI — adapters in `lib/agent.sh` are designed to be portable

If you're not Claude Code, see `agents/<name>/CONTRACT.md` for the JSON I/O contract you need to satisfy.

## What NOT to do

- Don't commit anything in `memory/*.md` except templates (privacy guardrail — see `memory/README.md`)
- Don't bypass the pre-commit hook with `--no-verify`
- Don't push directly to `main` in any agent repo
- Don't invent new comment prefixes or board column names without grepping for siblings first (see `guardrails/agent.md`)

## V1 status

Pre-release. Bundle in development. Milestones M1 (foundation) → M7 (launch). Public launch will flip this repo from private to public. Until then, the structure is real but contents are scaffolding.

## Where to ask

Open an issue on the repo. Code-Reviewer and Sarge subagents read issue comments — surface questions there. The operator (human) is the escalation path; agents resolve among themselves first.
