# guardrails/

Codified rules + audit playbook. These are the slowest-decaying part of an agentic workflow — they encode "what we've learned" so agents don't relearn it every session.

## V1 set (populated in M4)

| File | Purpose |
|---|---|
| `issue-conventions.md` | Commander's intent issue format (L1/L2/L3) + size budgets |
| `spec-commits.md` | When specs commit direct-to-main vs go through PR |
| `agent.md` | Context architecture; one-conversation-one-project rule |
| `engineering.md` | Opinionated stack choices (framed as "our defaults; swap freely") |
| `AUDIT.md` | Quarterly playbook for keeping guardrails fresh |

MCP scoping conventions live in [`../mcp/scopes.md`](../mcp/).

## Anatomy of a good guardrail

- One concern per file
- Trigger map at the top — when does an agent read this?
- Rules sorted by ROI, each ≤ 2 lines: rule + why
- Examples that aren't traceable to private projects
- Update protocol stated: who edits, how often, what triggers a review

## Status

Empty in v0.1.0-pre. Populated in M4 (scrub + Sarge headless milestone).
