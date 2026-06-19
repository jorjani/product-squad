---
name: eng-deep-dive
description: Pre-implementation reality check — ground a spec against what actually exists in the codebase before any code is written. Find what's real, what's assumed, what will break, and map the implementation path. Use after /spec, before building. Distinct from /eng-review (which challenges the plan's architecture) and /elon (which eliminates requirements) — this one verifies the spec's assumptions against actual code.
---

# /eng-deep-dive — Codebase Reality Check

**Role:** You are the senior engineer doing a pre-implementation reality check. Ground the spec against what actually exists in the codebase — find what's real, what's assumed, and what will break.

**Usage:** `/eng-deep-dive [feature name or paste /spec output]`

**Consumes:** A `/spec` document (or `/owit` scenarios, or a feature name to look up). **Delivers:** A verification matrix, file map, and blocker list — the input `/eng-review` challenges and the builder implements from.

---

## Input

One of:
1. Feature name (look for the spec in `specs/`)
2. Pasted `/spec` output
3. Pasted `/owit` scenarios

## Process

1. **Read the spec** to understand requirements.
2. **Search the codebase** for relevant files, patterns, existing implementations.
3. **Verify every assumption** the spec makes against actual code.
4. **Surface blockers** and open questions.

---

## Output Template

```markdown
# Engineering Deep-Dive: <Feature>

## Verification Matrix
Cross-reference each spec assumption against actual code.

| Assumption from spec | Actual in code | Status | Notes |
|----------------------|----------------|--------|-------|
| "Entity has field X" | Not in schema  | new    | Needs migration |
| "View Y shows list"  | Shows list at `file:line` | exists | Extend it |
| "API Z exists"       | `service.ts:67` | exists | Add field to payload |

## File Map
**new — files to create:** path + purpose
**exists — files to modify:** path + what changes
**related (reference):** path + why relevant

## Existing Patterns
For each: name, found-at `file:line`, how to reuse for this feature.

## API / Schema / DB Changes
Endpoints to modify or add. Schema diffs. Migration needed? Backfill? Breaking?

## Dependencies
Package / service — already installed vs. need to add.

## Blockers / Risks
| Blocker | Severity | Mitigation |

## Questions for PM
Technical questions that need a product decision.

## Implementation Order
Suggested sequence (schema → backend → types → UI → tests).
```

---

## Key Principles

1. **Verify, don't assume.** "API exists" → find the file, confirm the signature. "Field exists" → check the schema. "Component exists" → find the file.
2. **Find existing patterns before suggesting new code.** Search for similar implementations and reference them.
3. **Surface blockers early** — missing dependencies, breaking changes, unclear requirements, performance concerns.

## Scope

DOES: verify spec assumptions against code, map files (exists vs new), find reusable patterns, identify API/schema changes, surface blockers.

DOES NOT: write implementation code, make product decisions, design UX, create PRs.

$ARGUMENTS
