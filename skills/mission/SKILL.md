---
name: mission
description: Capture the product's mission, value proposition, north-star, and explicit non-goals — the altitude above any single feature. Use once when starting a product, or to revisit the vision, before scoping features. Distinct from /why, which frames one feature's outcome; /mission frames the whole product. /vet reads its output to judge whether a feature belongs.
---

# /mission — Define What the Product Is For

The scoping cluster (`/why → /shape → /experience → /owit → /elon`) all operates at the **feature** level. `/mission` operates one level up: the **product**. Run it once at the start — and revisit it when the vision shifts — and every feature gets judged against it by `/vet`.

**Consumes:** `design-system/project.json` if present (for `audience` / `surface` context, so you don't re-ask) OR the operator's description of the product.

**Delivers:** `design-system/mission.md` — mission, value proposition, north-star, and **non-goals**. `/vet` consumes this to decide whether a feature Serves the mission or should be killed.

---

## Before you start

If `design-system/mission.md` already exists, **read it back to the operator first** and ask whether they're refining it or starting over. Never silently overwrite a mission.

If `design-system/project.json` exists, read it — reuse `audience`, `surface`, `primary_action` instead of re-asking.

---

## The interview

Ask these **one at a time** with AskUserQuestion. Propose a sensible default from what you already know, lead with your recommendation, let the operator confirm or override. This is a conversation about the *product*, not a form.

1. **Mission — one sentence.** "What change does this product make for its user?" Not the features — the *change*. Push back on feature-lists: a mission is an outcome, not a capability.
   - Good: "Solo builders ship a spec a developer can build from without a single follow-up question."
   - Bad: "A tool with scoping commands and a visual ladder." (that's features, not a mission)

2. **Value proposition.** "Why would someone choose this over the status quo or the obvious alternative?" The core promise or unfair advantage. One or two sentences.

3. **North-star.** "What does *winning* look like — the one observable outcome that means the product is working?" Prefer something countable or clearly observable.
   - "An idea goes from one sentence to a shippable spec in under 30 minutes."

4. **Non-goals — 2 to 4.** "What will this product deliberately NOT do?" These are the boundaries `/vet` enforces. Force at least two. If the operator can't name non-goals, the mission is too vague — push until they can.
   - "Not a project-management tool — no boards, sprints, or assignees."
   - "Not for teams — single-operator only."

---

## Output

Write `design-system/mission.md` with this shape, then show it to the operator:

```
# Mission — <product>

**Mission:** <one sentence — the change for the user>

**Value proposition:** <why this over the alternative>

**North-star:** <what winning looks like — observable>

**Who it's for:** <audience — from project.json if available>

**Non-goals (what we will NOT build):**
- <non-goal 1>
- <non-goal 2>

---
_Used by `/vet` to judge whether a feature serves the mission. Revisit with `/mission` when the vision shifts._
```

Confirm with one line: "design-system/mission.md saved. Run `/vet <feature>` to test any feature against it."

---

## Rules

- **Mission is a change, not a feature set.** If the answer lists capabilities, reframe it as the outcome those capabilities produce.
- **Non-goals are mandatory.** A mission with no boundaries can't kill anything — and a gate that can't kill is theater. Force at least two.
- **Don't fabricate.** If the operator is unsure, capture "TBD" rather than inventing a mission for them.
- **Prose, not JSON.** This is the human-readable vision doc; `project.json` stays the machine config.
- **Run once, revisit rarely.** This is not a per-feature command. If you find yourself running it every feature, you want `/why`.

$ARGUMENTS
