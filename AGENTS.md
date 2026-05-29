# AGENTS.md

You are an LLM agent encountering Product Squad. Read this file first.

## What this repo is (V0.5)

Product Squad is an opinionated agentic dev OS. **V0.5 ships two wedges:**

- **Primary — visual fidelity ladder** (sketch → wireframe → mockup → prototype) via `./draw`
- **Secondary — product/scoping cluster** (why → shape → experience → owit → elon) via `./scope`

**How the two clusters connect.** The product cluster decides *what* to build and *for whom*; the visual cluster decides *how it looks*. They meet twice: `/shape`'s selected option is the idea you hand to `./draw`; `/owit`'s scenarios become the state coverage `/prototype` exhausts. Each command in the product cluster names what it Consumes from the prior stage and what it Delivers to the next — the chain is explicit, not inferred.

Five named agents exist in snapshot form under `agents/`, but full runtime + Foreman portability lands in V1.

## How to orient in 60 seconds

1. **Parse [`manifest.yaml`](manifest.yaml).** Machine-readable index of every agent, command, demo, and roadmap item. Status per-agent: `runnable_v0_5: true | false | partial`.
2. **Read this file.** You're already here. Mental model + contribution rules.
3. **Try the demos:**
   - `./draw "your feature idea"` — renders 4-tier visual ladder; opens HTML in browser on macOS, prints file paths on Linux. Set `FLAVOR=linear|apple|airbnb|uber` to switch the aesthetic vocabulary (default `linear`). Set `BRAND="YourProduct"` to override the brand placeholder used in chrome (default `AcmeU 101 · ReviewLab`). See [`.studio/design.md`](.studio/design.md) and [`examples/flavor-comparison.html`](examples/flavor-comparison.html).
   - `./scope "your feature idea"` — writes 5 scoping prompts for sequential paste into Claude Code
4. **Open `agents/<name>/README.md`** for the agent you're acting as (snapshot context — full `CONTRACT.md` per-agent arrives V1).

## The crew (V0.5 status)

| Agent | Role | V0.5 runnable | Where it lives |
|---|---|---|---|
| **Foreman** | Orchestrator | ❌ snapshot | `agents/foreman/` |
| **Sarge** | PM scoping (idea → brief) | ✅ partial (via `scope`) | `agents/sarge/` + `commands/{why,shape,experience,owit,elon}.md` |
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

V0.5 is a **forked snapshot** of David's running pipeline plus the visual ladder + scoping cluster wedges. Don't expect every script in `agents/foreman/` to run unchanged — many reference `~/Projects/.index.json` and the `getqatalyst` GitHub org. The V1 roadmap in `manifest.yaml` covers the portability fixes (`stat -f %m` → Linux-portable, `FOREMAN_HOST` default removal, board-id validation abort-on-failure, `.index.json` existence check, etc.).

## Agent compatibility

- **V0.5 default:** Claude Code only. Both demos use `claude -p` with subscription auth (**no API key required**).
- **V1 default:** Claude Code, with Codex CLI as a tested adapter (`AGENT=codex`). Abstraction layer in `lib/agent.sh`.
- **Community-welcome (V1+):** Aider, OpenCode, Cursor, Gemini CLI.

⚠️ **Gotcha:** If `ANTHROPIC_API_KEY` is set in your env, it *shadows* Claude Code subscription auth (precedence #3 vs #6 in the Claude Code auth docs). Unset it if you hit org-mismatch errors: `unset ANTHROPIC_API_KEY`

## What NOT to do

- Don't commit anything in `memory/*.md` except templates (privacy guardrail — see `memory/README.md` when V1 lands)
- Don't bypass the pre-commit hook with `--no-verify`
- Don't push directly to `main`
- Don't invent new comment prefixes or board column names without grepping for siblings first

## Where to ask

Open an issue on the repo. In V0.5, David (the operator) is the only respondent. In V1, Code-Reviewer and Sarge subagents will read issue comments and route accordingly.
