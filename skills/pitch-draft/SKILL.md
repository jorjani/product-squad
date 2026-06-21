---
name: pitch-draft
description: Turn a raw, unstructured idea into a Shape Up-style pitch — problem, appetite, solution sketch, rabbit holes, no-gos. Use at the very front of the funnel when you have a one-liner or a rough thought and need a decision-ready brief before anyone scopes or builds. Feeds /shape (option menu) and /spec (the contract).
---

# /pitch-draft — Raw Idea → Pitch

A pitch is the artifact that lets someone decide **whether** to spend time on an idea — not how to build it. Following Basecamp's Shape Up, a pitch states the problem, the appetite (how much time it's worth), a rough solution sketch, and the boundaries: the rabbit holes to avoid and the no-gos to declare out of scope.

**Consumes:** An unstructured idea — a sentence, a Slack message, a complaint, a "wouldn't it be nice if…".

**Delivers:** A pitch with five sections + the smallest set of questions that, once answered, unblock scoping. Decision-ready: the reader can promote it, park it, or kill it.

---

## Step 0 — Read the raw idea

Take whatever the user gives you. If it's a single line, that's fine — the whole point is to shape the fuzz into a decision-ready brief. Skim the codebase if one is present: an idea that's already half-built or redundant should be flagged, not pitched.

## Step 1 — Apply The Algorithm to the idea itself

Before writing, interrogate the idea:

1. **Question the requirement.** Does this need to exist? Who actually feels the pain?
2. **Delete.** Is this redundant with something already shipped? If so, say so in the pitch and stop.
3. **Simplify.** What's the smallest version that still solves the real problem?

A pitch that survives this is worth writing. One that doesn't gets a one-line "already covered by X" instead.

## Step 2 — Write the pitch (five sections)

**Problem** — One or two sentences. The specific pain, stated as observable fact, not a feature request. "Users re-enter the same address on every order" beats "we should add saved addresses." If you can't name who hurts and how, you don't have a problem yet — ask.

**Appetite** — How much time is this worth? A fixed budget, not an estimate. Shape Up uses "small batch" (a few days) vs. "big batch" (a couple of weeks). The appetite caps the scope: if the solution can't fit, the scope gets cut, not the time.

**Solution sketch** — The rough shape of the approach, at the altitude of "what the user experiences," not "which functions to write." Prose, a bullet flow, or — if the idea is UI-shaped (a screen, a component, a flow, a layout) — a small ASCII wireframe. Deliberately under-specified: enough to picture it, loose enough that the builder still decides the how.

**Rabbit holes** — The places where effort could unexpectedly explode. Risk multipliers, not blockers. "If this needs to work offline, the sync layer is a rewrite." Naming them now is how you protect the appetite later.

**No-gos** — What you're explicitly declaring out of scope. The adjacent things people will assume are included. Stating them keeps the pitch honest and the scope bounded. "Bulk edit is a no-go for this pitch" prevents a reviewer from quietly expanding it.

## Step 3 — Open questions

List only the questions whose answers change the shape — the smallest set that unblocks the next stage. Skip anything obvious from the codebase or already answered in the idea. Don't paper over unknowns with assumptions; carry them forward.

---

## Output Format

```
## Pitch — <short title>

**Problem**
<who hurts, how — observable fact>

**Appetite**
<small batch (~days) | big batch (~weeks)> — <one line on why that budget>

**Solution sketch**
<rough shape — prose, flow, or small ASCII wireframe if UI-shaped>

**Rabbit holes**
- <where effort could explode>

**No-gos**
- <explicitly out of scope for this pitch>

**Open questions**
- <only what changes the shape — else omit>
```

---

## Rules

- **Decide-whether, not decide-how.** A pitch exists to make a go/no-go call cheap. The moment you're prescribing implementation, you've left the pitch and entered the spec.
- **Appetite caps scope.** Fixed time, variable scope. If the sketch can't fit the appetite, cut the sketch — don't pad the time.
- **Name the boundaries.** Rabbit holes and no-gos are what separate a pitch from a wish. A pitch with no boundaries hasn't been shaped.
- **Smallest unblocking question set.** Every open question should be one a reader *must* answer before scoping. If they could scope without it, drop it.
- **Kill redundant pitches early.** If The Algorithm finds the idea already exists or shouldn't, the deliverable is one honest line, not a polished pitch.
- **Hand off cleanly.** When the pitch is accepted, `/shape` turns it into an options menu and capability delta; `/spec` later commits the contract.

$ARGUMENTS
