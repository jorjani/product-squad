---
name: why
description: Frame the outcome / job-to-be-done one level above the user's stated task. Use when the user is unclear why they're building what they're building, or when restating their request as an outcome would clarify priority.
---

# /why -- What's the Job and Why Does It Matter?

Before diving in, go one level up. The user said what they want to do. Your job is to articulate **why it matters** -- what does this enable one level above?

**Consumes:** A raw feature idea or one-line ask.

**Delivers:** A 1-2 sentence outcome statement — what this enables one level up. Feeds `/shape`'s "Why it matters" in Step 2.

## Process

1. **Restate the task** in one line (what the user asked for)
2. **State the job one level up** -- what outcome does this enable? Not the implementation, the capability it unlocks.
   - "Add Sentry" → "Detect production failures before users report them. Cut response time to errors from hours to minutes."
   - "Add visa sponsorship filter" → "Candidates with visa needs stop wasting time on jobs that won't sponsor. Reduces noise, increases trust in the board."
   - "Normalize company names" → "Prevent duplicate company entries that fragment job listings and confuse employer analytics."
3. **Check alignment** -- ask the user: "Is this the right why? If not, what's the actual goal?"

## Output Format

```
Task: [what they asked for]
Why:  [what it enables one level up -- 1-2 sentences max]
```

Then ask: "Is this the right why?"

## Rules

- Keep it to 2-3 sentences max. This is a lens, not a document.
- Don't list steps, don't plan, don't scope. Just the job and the why.
- If the why reveals a simpler path to the same outcome, say so. ("If the goal is catching production errors, have you considered just adding a health check endpoint first?")
- If the user's request is already clearly outcome-oriented, say so and move on. Don't force this when it's obvious.
