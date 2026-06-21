---
name: scope-item
description: Turn an accepted pitch into an acceptance-criteria-ready backlog item — explicit ACs, decision points, files likely touched, and a success test. Use after a pitch is approved and before a builder picks it up. Pairs with /pitch-draft upstream and /decompose downstream.
---

# /scope-item — Pitch → AC-Ready Backlog Item

A pitch decides *whether*. Scoping decides *what done means* — precisely enough that a builder can pick the item up without a follow-up conversation, and you can tell when it's finished. This is the stage where ambiguity either gets resolved or gets surfaced as an explicit decision for the product owner.

**Consumes:** An accepted pitch (from `/pitch-draft`, `/shape`, or a one-paragraph brief). Read the codebase if one is present — scoping is grounded in real code, not abstractions.

**Delivers:** A scoped item with four parts: **acceptance criteria**, **decision points**, **files likely touched**, and a **success test** — plus a verdict (ready / needs a decision).

---

## Step 1 — Assess against the format

Compare the pitch to the target shape:

```
## Goal
<1-2 sentences — what changes for the user>

## Acceptance criteria
- [ ] <observable outcome, not an implementation step>

## Context
<real file paths, functions, data models — no abstractions>

## Out of scope
<explicit boundaries>
```

Decide which of three states the item is in:

- **Ready** — already meets the format. Pass it through with a one-line note.
- **Enrichable** — you can fill every gap from the codebase (missing paths, schema details, ungrounded ACs). Do it; the item becomes build-ready.
- **Needs a decision** — the gap is a product question only the owner can answer (ambiguous goal, multiple valid approaches with different UX, unclear in/out scope). Surface it; do not guess.

## Step 2 — Write acceptance criteria

Each criterion is an **observable outcome**, not a task. "User sees a confirmation toast after saving," not "add a toast component." A reader should be able to check each one by using the product, with no knowledge of the code. If a criterion can only be verified by reading the diff, it's an implementation step — rewrite it.

## Step 3 — Surface decision points

For anything you can't resolve from the codebase, write an explicit decision — never a silent assumption:

```
**Decision:** <the question, specifically>
Recommend: <your pick and why>
- <option A — and its user-facing consequence>
- <option B — and its user-facing consequence>
```

**The spec-boundary test** — what the item must decide vs. what the builder decides:

- **INCLUDE** decisions that change the product: where logic runs, the data model, data flow, which surfaces change, API routes.
- **EXCLUDE** code-level implementation: function names, internal abstractions, test structure.
- **The test:** if two approaches produce a *different user experience*, the item must choose. If the UX is identical, the builder chooses.

## Step 4 — Files likely touched

From your codebase recon, list the concrete files and functions the work probably lands in — `path/to/file.ts:functionName` form. Verify each one exists; don't guess paths. This is grounding, not prescription — it tells the builder where to start looking, not what to write. Omit only if no codebase is available.

## Step 5 — Success test

One concrete, runnable check that proves the item is done: a user action and its observable result, or a command and its expected output. "Place an order with a saved address → no address fields shown, order completes." This is the single assertion that closes the loop between scope and verification.

---

## Output Format

```
## Scoped — <title>   ·   Verdict: <ready | needs decision>

## Goal
<what changes for the user>

## Acceptance criteria
- [ ] <observable>
- [ ] <observable>

## Decision points
<explicit decisions per Step 3 — or "None — fully grounded">

## Files likely touched
- path/to/file.ext:symbol — <why>

## Success test
<one runnable check: action → observable result>

## Out of scope
<explicit boundaries carried from the pitch>
```

---

## Rules

- **Observable ACs only.** If verifying a criterion requires reading code, it's a task, not an acceptance criterion. Rewrite it as something a user can see.
- **No silent assumptions.** Every gap is either filled from the codebase or surfaced as a decision point. A scoped item that hides its unknowns wastes the builder's first hour.
- **Decide product, leave code.** Use the spec-boundary test on every choice. Over-specifying the *how* steals the builder's judgment; under-specifying the *what* sends the work back.
- **Ground every reference.** File paths and functions must exist. Verify before you write them.
- **One success test.** Not a runbook — the single check that means "done." If you can't name one, the scope isn't clear yet.
- **Hand off to `/decompose`.** Once scoped, split the item into single-surface units, each ready for a builder or the visual ladder.

$ARGUMENTS
