---
name: flow
description: UI state-transition contract producer — turn a UI ticket's goal, scenarios, and acceptance criteria into per-state ASCII blocks plus an edge table where each row is one verifiable assertion (from state, trigger, target state, visible cue or side effect, how to verify). Use to lock UI behavior into a build-and-test-ready spec before coding. Pairs with /api (backend contract for full-stack tickets) and runs after /decompose (which locks atomic scope).
---

# /flow — UI State-Transition Contract

**Usage:** `/flow [issue-number] [repo]` or `/flow` with pasted issue text.

## Purpose

Turn a UI ticket into a precise, testable contract. Read the ticket's goal, scenarios, and acceptance criteria; output per-state ASCII blocks plus a Markdown edge table where each row is one assertion a tester (human or automated) can check.

Each row answers: from which state, on what trigger, to what target state, with what visible cue or side effect, and how to verify it.

## Workflow

### 1. Read

Fetch the issue body (`gh issue view <num> --repo <repo> --json title,body,comments`) or read the pasted text. Identify three signal types:

- **States** — from scenario sections, per-state ASCII blocks, or "On the X surface, ..." prose.
- **Triggers** — from criteria phrased "click X → Y", "on action A, system does B", "user types/hovers/scrolls".
- **Side effects** — from `POST /api/...`, table names, clipboard mentions, navigation references.

### 2. Produce

Write per-state ASCII blocks (one per named state), then the edge table. Cells the ticket cannot ground stay `(not stated)` — do not invent.

The **Verify** column says how each row is checked:
- `walk` — a browser-driven check (e.g. a Playwright session). All `walk` rows in one ticket compile to ONE session, not one per row. Bias to `walk` when unsure.
- `source` — a static assertion against source (a file exports X, a constant equals Y) — no browser needed.

Tiny example (one transition + one entry-cue + one global static-fact):

```
| # | From    | Trigger        | Target | Cue or side-effect                          | Verify |
|---|---------|----------------|--------|---------------------------------------------|--------|
| 1 | Editor  | click Publish  | POSTED | opacity 0.55, posted_content row written    | walk   |
| 2 | POSTED  | (entry)        | POSTED | green check overlay top-right               | walk   |
| 3 | (any)   | (none)         | (any)  | postActions.ts exports renderScheduleWidget | source |
```

### 3. Place

- **Small ticket:** print the blocks + table inline for paste-in.
- **Larger ticket:** write `<repo>/specs/<num>-flow.md` with frontmatter (`issue: <num>`, `status: draft`); print a compact body-side summary (Trigger + Target columns only). Whoever verifies reads the spec when present, falls back to the body.

## Output checklist

- [ ] Per-state ASCII blocks for every named state.
- [ ] Edge table covers transitions, entry-cues, and global static-facts.
- [ ] Verify column populated for every row.
- [ ] `(not stated)` flagged on cells the ticket did not ground.

## Related

- `/decompose` — runs before `/flow` to lock atomic scope.
- `/api` — sibling for the backend contract; pair them on full-stack tickets (`/flow` covers UI state, `/api` covers endpoints).
