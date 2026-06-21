---
name: simplify
description: Run Tesla's 5-step Algorithm on something that feels finished — question the requirement, delete what's not needed, simplify what remains, accelerate, automate last. Use when a feature works but feels heavy, over-built, or "complete." Distinct from /refactor (which improves code structure without changing behavior) and /elon (the interactive build-time cut with per-requirement STOP gates) — this one is a fast review pass over things that already exist.
---

# /simplify — The Algorithm

**Role:** You are the simplifier. Apply Elon's 5-step Algorithm — the one from Tesla's production line — to something already built or fully specced. Find what shouldn't exist, then make what's left smaller and faster.

**Usage:** `/simplify [feature, code, process, or system that feels complete]`

**Consumes:** Anything that feels done — a shipped feature, a finished spec, a working module, a process. **Delivers:** A cut list — questioned requirements, deletions, simplifications, accelerations, automations — in strict order. Pairs with `/refactor` (to execute structural cuts) and `/eng-review` (to harden what survives).

---

## The 5 Steps — strict order, never skip ahead

The order is the method. Most people simplify before deleting, and automate before questioning. That's backwards and it's why systems bloat.

### 1. Question the requirement
Every requirement is wrong — or at least suspect — until proven otherwise. For each: **Who asked for this? What concrete thing breaks if it's gone?** A requirement from a person you can name survives scrutiny; one from "best practice," "we might need it," or "to be safe" does not. **Make requirements less dumb before optimizing them** — the most common error is optimizing something that should not exist.

### 2. Delete the part or process
Now remove. If you're not adding back at least 10% of what you delete, you didn't delete enough. The bias is toward keeping things "just in case" — invert it. **Delete first, add back only when something concretely breaks.** Deletions cite the requirement (from Step 1) they're allowed by.

### 3. Simplify what remains
Only what survived Steps 1-2. Merge components. Replace custom with off-the-shelf. Collapse options into a sensible default. Strip premature abstraction. **Don't simplify something that should have been deleted** — that's why this comes third.

### 4. Accelerate cycle time
Speed up what's left — but only after it's correct and lean. Faster builds, fewer round-trips, shorter feedback loops. **Never accelerate a step you haven't first tried to delete** — speeding up waste just makes faster waste.

### 5. Automate — last
Automation comes at the very end. Automate a process only after it's been questioned, trimmed, simplified, and sped up. **Automating a bad process locks the bad process in.** Most teams reach for automation in Step 1 and pay for it forever.

---

## Output Template

```markdown
## The Algorithm — <target>

### 1. Question
- **Q1:** "[requirement]" — asked by [who/unknown]. Breaks if gone: [concrete thing / nothing] → **Keep / Cut**

### 2. Delete
- **D1:** Remove [part] (allowed by Q#). Add back only if [concrete trigger].

### 3. Simplify
- **S1:** [survivor]: [before] → [after]

### 4. Accelerate
- **A1:** [step]: [current cycle] → [faster path]

### 5. Automate
- [only if a process survived all four steps — otherwise "nothing earns automation yet"]

---
**Net:** [what got cut, what got smaller, what got faster — one line]
```

---

## Rules

1. **Order is law.** Never simplify before deleting, never automate before accelerating. Out-of-order = bloat re-introduced.
2. **Strongest on "complete" things.** The Algorithm bites hardest where everyone agrees the work is done — that's where the unquestioned requirements hide.
3. **Name who asked.** A requirement with no owner is a deletion candidate by default.
4. **Delete until it hurts, then add back.** If nothing got added back, the cut was too timid.
5. **Concrete, not advisory.** "Cut the retry wrapper around the in-memory cache" — not "consider simplifying."

$ARGUMENTS
