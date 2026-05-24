# AGENTS.md

You are an LLM agent encountering Product Squad. Read this file first.

## What this repo is (V0.5)

Product Squad is an opinionated agentic dev OS. **V0.5 ships the scoping wedge** — the prompts that codify how to turn a vague idea into a buildable ticket. Five named agents exist in snapshot form under `agents/`, but full runtime + Foreman portability lands in V1.

## How to orient in 60 seconds

1. **Parse [`manifest.yaml`](manifest.yaml).** Machine-readable index of every agent, command, and roadmap item. Status per-agent: `runnable_v0_5: true | false | partial`.
2. **Read this file.** You're already here. Mental model + contribution rules.
3. **Try the demo:** `./bin/scope "your feature idea"` — outputs /shape + /spec + /owit. Source prompts in `commands/`.
4. **Open `agents/<name>/README.md`** for the agent you're acting as (snapshot context — full `CONTRACT.md` per-agent arrives V1).

## The crew (V0.5 status)

| Agent | Role | V0.5 runnable | Where it lives |
|---|---|---|---|
| **Foreman** | Orchestrator | ❌ snapshot | `agents/foreman/` |
| **Sarge** | PM scoping (idea → brief) | ✅ partial (via `bin/scope`) | `agents/sarge/` + `commands/{shape,owit,elon}.md` |
| **Inspector** | Verifier (Verify → Done gate) | ❌ lives in Foreman | `agents/foreman/phases/inspect.sh` |
| **Code-Reviewer** | PR review (severity-ranked) | ✅ Claude Code subagent | `agents/code-reviewer.md` |
| **Build-Fixer** | Minimal-diff build repair | ✅ Claude Code subagent | `agents/build-fixer.md` |

## How to contribute (worktree + branch + PR pattern)

Non-negotiable for behavior-changing work:

1. Create a worktree from `origin/main` — naming: `psq<issue>-<slug>` or exploratory `psq-<slug>`
2. Apply the smallest possible change
3. Commit with conventional prefix (`fix(scope): ...`, `feat(scope): ...`)
4. Push, open a PR with a test plan
5. Code-Reviewer subagent reviews; in V1, Inspector gates merge → Done

Docs at root + files under `specs/` and `artifacts/` commit direct to main. Behavior-changing files do not.

## V0.5 ≠ V1 (set expectations)

V0.5 is a **forked snapshot** of David's running pipeline plus the scoping wedge. Don't expect every script in `agents/foreman/` to run unchanged — many reference `~/Projects/.index.json` and the `getqatalyst` GitHub org. The V1 roadmap in `manifest.yaml` covers the portability fixes (`stat -f %m` → Linux-portable, `FOREMAN_HOST` default removal, board-id validation abort-on-failure, `.index.json` existence check, etc.).

## Agent compatibility

- **V0.5 default:** Claude Code (only). The demo uses `claude -p` directly.
- **V1 default:** Claude Code, with Codex CLI as a tested adapter (`AGENT=codex`). Abstraction layer in `lib/agent.sh`.
- **Community-welcome (V1+):** Aider, OpenCode, Cursor, Gemini CLI.

## What NOT to do

- Don't commit anything in `memory/*.md` except templates (privacy guardrail — see `memory/README.md` when V1 lands)
- Don't bypass the pre-commit hook with `--no-verify`
- Don't push directly to `main`
- Don't invent new comment prefixes or board column names without grepping for siblings first

## Where to ask

Open an issue on the repo. In V0.5, David (the operator) is the only respondent. In V1, Code-Reviewer and Sarge subagents will read issue comments and route accordingly.
