# mcp/

MCP (Model Context Protocol) scoping conventions.

## V1 ships (M6)

- `scopes.md` — when to enable per-project vs globally; how to scope permissions; how to wrap third-party servers behind call limits + structured workflows

## Why simplified

V1 ships the scoping convention doc only — no wrapped Slack/Notion example servers. Reference implementations are deferred to V2 if demand surfaces.

## Why this matters

MCP servers extend an agent's tool surface. Naive setup creates two failure modes:
1. **Over-scoped:** an MCP enabled globally fires on every session, eating context tokens
2. **Under-defended:** a third-party MCP server makes uncontrolled API calls, leaks data, or accepts injected instructions

`scopes.md` codifies the pattern: enable per-project, wrap third-party with call limits, document when MCPs are worth the cost.

## Status

Empty in v0.1.0-pre. Populated in M6.
