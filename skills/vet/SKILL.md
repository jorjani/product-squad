---
name: vet
description: Judge whether a feature serves the product mission — and kill it if it doesn't. Reads design-system/mission.md and returns Serves / Tangential / Off-mission. Use right after /why as a cheap kill before scoping effort, and optionally again on the finished /spec. Distinct from /elon — /elon kills for internal bloat; /vet kills for strategic misfit against the mission.
---

# /vet — Does This Feature Belong?

You can scope and ship any feature. The question `/vet` answers is different: *should this one exist at all, given what the product is for?* It judges a feature against the **mission**, not against its own internal leanness (that's `/elon`).

**Consumes:** `design-system/mission.md` (mission + non-goals) AND a feature — a raw idea, `/why`'s outcome, or `/spec`'s finished spec.

**Delivers:** A fit verdict — **Serves / Tangential / Off-mission** — anchored to the mission and its non-goals. The gate: Serves → proceed to `/shape`; Tangential → defer or rethink; Off-mission → stop, before you spend effort scoping a feature that doesn't belong.

---

## Step 0 — Load the yardstick

Read `design-system/mission.md`. If it's **missing**, say so and recommend `/mission` first — you can't judge fit without a mission. Offer a *provisional* vet against `design-system/project.json` (`audience` + `primary_action` as a weak proxy), clearly labeled provisional. A real vet needs a real mission.

## Step 1 — State what's being judged

One line: the feature. One line: the mission, restated from `mission.md`. Put them side by side so the comparison is visible.

## Step 2 — Test fit

Three questions, in order:
1. **Does it advance the north-star?** If yes, how directly? A feature that moves the north-star Serves almost by definition.
2. **Does it hit a declared non-goal?** If the feature falls under something `mission.md` says the product will NOT do, that's a near-automatic **Off-mission** — unless the operator wants to change the mission itself (flag that as the real decision, bigger than this feature).
3. **What's the opportunity cost?** Even an on-mission-adjacent feature competes for attention with the core. Name what mission-work it displaces.

## Step 3 — Verdict

Deliver the verdict in the format below. Don't soften it — a gate that hedges isn't a gate.

---

## Output Format

```
## Vet — <feature> vs the <product> mission

**Mission:**      <one line, from mission.md>
**This feature:** <one line>

**Fit:**
- Advances the north-star? <yes/no — how>
- Hits a non-goal? <which one, or none>
- Opportunity cost: <what core work this competes with>

---

**Verdict: Serves / Tangential / Off-mission**
<2-3 sentences — the reason, anchored to the mission>

<one of:>
→ Serves — proceed to /shape.
→ Tangential — defer. What would make it Serve: <the change, or "nothing — it's a different product">.
→ Off-mission — stop here. <why it doesn't belong>. Do instead: <the mission-work that matters more>.
```

---

## Rules

- **The mission is the only yardstick.** Not bloat (that's `/elon`), not feasibility (that's `/shape`). Fit, and only fit.
- **A declared non-goal kills.** If the feature is something the mission says the product won't do, the verdict is Off-mission — and surface that the only way to "save" it is to rewrite the mission, which is a bigger decision than this feature.
- **Be willing to kill.** A gate that never returns Off-mission is theater. If everything Serves, the mission has no edges — send the operator back to `/mission` to add non-goals.
- **On a kill, point somewhere.** Never just "no." Name the mission-work worth doing instead.
- **Cheap and early.** This is a verdict, not a document. Run it before scoping, when killing costs nothing. Keep it short.

$ARGUMENTS
