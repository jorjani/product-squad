---
name: debrief
description: Turn a meeting transcript, voice dump, or raw notes into structured decisions, action items (yours vs. theirs), insights, and blockers — then suggest where to route each. Use after any meeting or call to capture outcomes; accepts any messy input format. Distinct from /checkpoint and /retro, which review a working session rather than a meeting.
---

# /debrief — Meeting → Decisions + Actions + Updates

Process a meeting into structured outputs and suggest where they go.

## Step 1: Identify context

From the notes, extract **who** was involved, the **project** (if any — not every meeting is project-scoped), and the **type** (client sync, prospect call, networking, teaching, internal). If a project is identified, load its context.

## Step 2: Extract

| Category | What to capture |
|----------|----------------|
| **Decisions** | What was agreed. State who decided. |
| **Action Items** | WHO does WHAT by WHEN. Separate yours from theirs. |
| **Insights** | Non-obvious things learned — about the person, their business, the problem. |
| **Blockers** | What's stuck and why. |
| **Content Seeds** | Anything that could become a post or article (optional). |

## Step 3: Output

```
## Debrief — [who] / [topic]
**Date:** YYYY-MM-DD | **Type:** [client/prospect/networking/teaching/internal]
**Project:** [name or "none"]

### Decisions
- [decision] — decided by [who]

### My Actions
- [ ] [action] — [deadline if mentioned]

### Their Actions
- [ ] [person]: [action]

### Insights
- [insight]

### Content Seeds
- [idea that could become a post]
```

## Step 4: Route (suggest, don't auto-execute)

Based on what was extracted, offer numbered next steps and let the user pick:
- Action items for a project → add to the project's task list or create an issue (`/gh-issue`).
- Content seed → develop it into a post.
- Project decision → record it in the project's notes/inbox.
- New person not yet tracked → add them to your contacts/people file.

Skip routing if there's nothing to route.

## Rules

- Accept any format — transcript, bullets, voice-to-text mess, stream of consciousness.
- Don't clean up the user's words in Decisions — preserve their language.
- "My Actions" = what you committed to. "Their Actions" = what the other party will do.
- Content Seeds and Route suggestions are optional — include only if something genuinely stood out.
- Keep the output tight — a working doc, not full meeting minutes.

$ARGUMENTS
