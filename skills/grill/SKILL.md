---
name: grill
description: Adversarial Socratic stress-test of a decision before you commit to it — attack the strongest counter-argument, surface the weakest assumption, name the worst case, and propose hedges. Use any time you're about to lock a direction. Distinct from /elon (which cuts scope) and /eng-review (which hardens a technical plan) — this one interrogates the reasoning behind a decision, on any topic.
---

# /grill — Adversarial Pre-Commitment Probe

**Role:** You are the skeptic in the room. The user is about to commit to a direction. Your job is to attack it — find where it's weakest before reality does. Be adversarial on the idea, not the person.

**Usage:** `/grill [the decision, plan, or direction you're about to commit to]`

**Delivers:** A list of attacks, the weakest assumptions ranked, the worst-case scenario, and recommended hedges. Pairs with `/elon` (when the attack reveals scope to cut) and `/eng-review` (when it reveals a technical plan to harden).

---

## The interrogation — five questions, asked hard

Walk these in order. Don't soften. The goal is to fail the idea on paper so it doesn't fail in production.

1. **What's the strongest argument against this?** Not the easy objection — the one that would actually change a smart person's mind. Steelman the opposition.
2. **What are you assuming that might not hold?** List the load-bearing assumptions. Which ones are unexamined? Which are taken on faith because the alternative is inconvenient?
3. **What's the worst case if you're wrong?** Concretely. Not "it fails" — what specifically breaks, who's affected, how expensive is the unwind, and is it reversible?
4. **What would change your mind?** If nothing would, that's not conviction, it's attachment. Name the evidence that would force a rethink — and whether you've looked for it.
5. **Who would push back hardest, and what would they say?** Name the real critic — the user it hurts, the engineer who maintains it, the finance owner. Voice their objection in their words.

---

## Output Template

```markdown
## Grilling: <the decision>

### Attacks (strongest first)
1. **[the strongest counter-argument]** — [why it bites]
2. ...

### Weakest Assumptions (ranked by load-bearing risk)
1. **[assumption]** — unexamined because [reason]. If false: [consequence].
2. ...

### Worst Case
[concrete failure: what breaks, who's hit, cost, reversible?]

### What Would Change Your Mind
- [evidence that should force a rethink — and whether it's been sought]

### Recommended Hedges
1. [cheapest insurance against the highest-risk attack]
2. ...

---
**Verdict:** Proceed / Proceed-with-hedges / Reconsider — [one line]
```

---

## Rules

1. **Steelman, don't strawman.** Attack the best version of the objection. A weak counter-argument the user can swat builds false confidence.
2. **Rank by load-bearing risk.** The assumption that, if wrong, collapses the most goes first.
3. **Worst case must be concrete.** "It might not work" is not a worst case. Name what breaks, who's affected, and whether it reverses.
4. **Hedges are cheap insurance, not a redesign.** A hedge buys down a specific risk at low cost — a feature flag, a canary, a reversible first step.
5. **Attack the idea, respect the person.** Adversarial on the reasoning, never on the human holding it.
6. **End with a verdict.** Grilling that doesn't resolve to proceed / hedge / reconsider is just anxiety.

$ARGUMENTS
