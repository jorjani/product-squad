---
name: who
description: Force a specific user in a specific scenario, not "users" — catches generic-audience drift ("for teams", "for anyone who X"). Use when the subject of the work is a category instead of a person.
---

# /who — Name the Person, Not the Audience

## What this catches

- **Generic-audience drift** — "for users", "for teams", "for anyone who X". A category can't have a pain, a workflow, or a moment of need. A person can.
- **The everyone trap** — when the subject is broad enough to include everyone, it's sharp enough to serve no one. Breadth feels safe; it's actually unfalsifiable positioning.
- **Absent alternative** — naming a user without naming what they do *today* instead. No alternative means no wedge.

## When to use

The moment you describe who something is for and the answer is a plural noun ("users", "developers", "customers"). Run it before `/shape` or any design work — a generic subject produces a generic surface that fits no real workflow.

## Methodology

Sharp ICP (ideal customer profile): name, role, scenario, current behavior. The test is concreteness — if you can picture a single real person doing a single real thing at a single real moment, the subject is sharp. If you're describing a demographic, it's still a category. Name a real person you know if you can; the specificity transfers even when you later generalize.

## The questions

1. **Who specifically?** Name a real person if you can — an actual human you could message. If not, the sharpest single persona, not the segment.
2. **What role / context?** Their job, their team size, the system they live in. The context that shapes the need.
3. **What are they doing right now instead?** The current behavior — the spreadsheet, the manual step, the competitor, the workaround. No alternative named = you don't understand the user yet.
4. **What's their pain in that moment?** The specific friction at the specific point in their workflow. Not "it's slow" — *what* is slow, *when*, *how much does it cost them*.
5. **Why YOU and not the alternative they have?** The wedge. What you do that their current behavior doesn't — the reason they'd switch.

## Output format

```
Name:             [a real person, or the single sharpest persona]
Role:             [job / context / system they live in]
Current behavior: [what they do today instead]
Pain moment:      [the specific friction, at the specific point]
Wedge:            [why you, not their current alternative]
```

## When to skip

The subject is already a named person in a named scenario — don't dilute it back into a survey. Also skip for genuine infrastructure / platform work where the "user" is another system, not a human; force a persona there and you'll fabricate one.

## Sister skills

- [[why]] — frames the outcome; `/who` names the subject that outcome is *for*.
- [[goal]] — pins the measurable target; a sharp `/who` makes the measure concrete (whose behavior moves).
- [[jobs]] — the job-to-be-done that person is hiring you for. *(related — defer building)*
