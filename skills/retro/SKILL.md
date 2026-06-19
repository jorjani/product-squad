---
name: retro
description: Post-session retrospective focused on process, not code — what shipped, what cost time, and specific actionable improvements for future sessions. Use at the END of a session to capture lessons; distinct from /checkpoint (mid-session status) and /pickup (resuming a prior session). Brief by design — surface only what matters.
---

# /retro — Session Retrospective

Quick post-session analysis. Review this session, be brief, skip anything obvious or low-impact. The whole retro fits on one screen.

## Output Format

```markdown
## Retro — {project} — {date}

### What shipped
{Concrete outcomes: merged PRs, issues created, files synced, things deployed. Facts only.}

### Misses
{1–3 bullets. Only friction that actually cost time, caused rework, or left value on the table. Skip if clean.}

### Recommendations
{Process/tooling improvements for smoother future sessions. Each must be actionable — state what to change and where. Mark TODO (not done) or DONE (applied this session).}

**R{n}: {title}** _{XS/S/M}_ `{TODO|DONE}`
What: {one line — the specific change}
Where: {file path or process step}

{Max 3 items. If smooth, say "None."}
```

## Rules

- **Max 3 items per section.** 4+ means you aren't filtering hard enough.
- Skip a section entirely if nothing meaningful to say.
- Recommendations must be specific (file path or process step) and marked TODO or DONE so the user knows if action is needed.
- Don't repeat: if a miss has an obvious fix, put it in Recommendations and skip the miss.
- Focus on process, not the code.

$ARGUMENTS
