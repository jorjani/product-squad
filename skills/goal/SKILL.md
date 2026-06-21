---
name: goal
description: Force a measurable target and an explicit falsifier before building — catches "ship X by Y" (activity dressed as outcome), "improve onboarding" (no measure), and "users will love it" (unfalsifiable). Use when the destination is fuzzy.
---

# /goal — Pin the Destination, Not the Activity

## What this catches

- **Activity masquerading as outcome** — "ship the new dashboard by Q3" names work, not the change in the world it's supposed to produce.
- **No measure** — "improve onboarding" with nothing that moves. You can't tell success from motion.
- **Unfalsifiable wins** — "users will love it" can't be proven wrong, so it can't be proven right either.

## When to use

Right after you can state what you want to do, but before you scope or build. The trigger: you can describe the *work* in a sentence but can't say what *number* tells you it worked. Pair early — a fuzzy goal contaminates every downstream decision.

## Methodology

The outcome-vs-activity distinction (Christensen's jobs framing; OKR thinking, light touch). Activity is what you do; outcome is what changes because you did it. A real goal names the outcome, attaches a measure, sets a threshold, and — critically — declares what would prove it *failed*. If nothing could prove failure, it isn't a goal, it's a wish.

## The questions

1. **In one sentence, what's the work?** The thing you're about to do. Just the activity — name it plainly.
2. **What changes in the world if it succeeds?** Not what you ship — what's different for the user, the business, the system afterward.
3. **How will you know — what number moves, by how much, by when?** A specific metric, a threshold, a date. "Activation rate from 40% to 60% by end of Q3," not "better activation."
4. **What would prove it didn't work?** The falsifier. The observation that forces you to admit it failed. If you can't name one, the goal is unfalsifiable — go back to question 3.

## Output format

```
Work:      [the activity, one line]
Outcome:   [what changes in the world]
Measure:   [the metric that moves]
Threshold: [from X to Y, by when]
Falsifier: [the observation that would prove it failed]
```

## When to skip

The goal is already a measured, dated, falsifiable outcome — don't ceremonially re-derive it. Also skip for pure exploration where the point is to learn what to measure; force a goal there and you'll invent a fake one.

## Sister skills

- [[why]] — surfaces the motivation one level up; run it first to find the root, then `/goal` pins the target that serves it.
- [[bet]] — once the goal is measurable, frame the wager (cost vs. expected payoff). *(future rung — Bound band)*
- [[grill]] — stress-test the measure and threshold adversarially before you commit to them.
