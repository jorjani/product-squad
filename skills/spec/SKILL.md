---
name: spec
description: Aggregate the scoping cluster's outputs (why, shape, experience, owit, elon) into one authoritative spec — the contract a builder works from. Use at the end of a scoping session to consolidate the conversation into a single document. Distinct from the individual cluster skills, which each produce one slice; /spec is the join.
---

# /spec — Commit the Contract

The cluster produces five slices in conversation: an outcome (`/why`), a chosen shape (`/shape`), a felt delta (`/experience`), behavior (`/owit`), and a cut list (`/elon`). They scatter across the session. `/spec` collapses them into **one authoritative document** — the contract everything downstream consumes.

**Consumes:** This session's `/why`, `/shape`, `/experience`, `/owit`, `/elon` outputs (or the files in a `scope` session dir). Plus any tightener artifacts named as bottlenecks (`/wireframe`, `/api`, etc.).

**Delivers:** One spec document. Feeds `/gh-issue` (→ issue in contract format), the visual ladder (→ extract one idea-phrasing for `./draw`), and `/vet` (→ a final fit check on the fully-scoped feature).

---

## Step 0 — Gather and verify

Pull each cluster stage's output from the conversation (or the `scope` session dir). For each that's **missing**, say so explicitly — do not fabricate it. If `/shape` named bottlenecks (Hardest unknowns) and a tightener artifact for one is missing, flag it: the spec is incomplete until that loose end is tightened.

## Step 1 — Assemble

Write the spec in the structure below. Carry forward the numbered IDs from `/elon` (R#/D#/S#) so the cut list stays traceable. Keep it a **contract: WHAT and WHY, never HOW** — no code, no file paths, no implementation steps. The builder decides how.

## Step 2 — Surface gaps

List open questions and unresolved choices explicitly. An honest "5 open questions" beats a smooth doc that papered over them.

## Step 3 — Save

Offer to write it to `specs/<slug>.md`. (Advancing a board column Pitch → Scope is environment-specific — hand that to the operator's own tooling, e.g. via `/gh-issue`.)

---

## Output Format

```
# Spec — <feature name>

## Problem
<one sentence — from /shape>

## Why it matters
<the outcome — from /why>

## Scope
<the options the operator selected — from /shape Step 6>

## What changes for the user
<capability delta — from /shape Step 4 + /experience>

## Behavior
<OWIT scenarios + resolved Choices — from /owit>

## Principles & constraints
<from /shape Step 5 — principles survive into implementation>

## Cut list
<surviving spec + deletions (D#) + simplifications (S#) — from /elon's verdict>

## Open questions
<unresolved — do NOT fabricate answers>

## Acceptance
<observable conditions that mean this is done>
```

---

## Rules

- **Don't fabricate.** A missing stage gets named as missing, not invented. (If `/elon` never ran, write "no cut list — /elon not run" rather than inventing one.)
- **Contract, not plan.** WHAT and WHY only. The moment you write a file path or a function name, you've left the spec's altitude.
- **Preserve traceability.** Keep `/elon`'s R#/D#/S# IDs so a reader can trace every cut back to its reason.
- **Acceptance is observable.** "User can X and sees Y," not "feature works."
- **One source of truth.** After `/spec`, the spec doc is authoritative — later changes edit the spec, they don't re-litigate the conversation.

$ARGUMENTS
