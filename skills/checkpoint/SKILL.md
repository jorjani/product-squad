---
name: checkpoint
description: Mid-session status snapshot — what got done, what's uncommitted right now, context usage, and the highest-ROI next actions. Use partway through a session to orient without ending it; distinct from /retro (post-session process review) and /pickup (resuming a prior session). Reports only — never commits.
---

# /checkpoint — Mid-Session Status Check

Quick orientation: what's done, what's dirty, where to go next. Review THIS session and produce a checkpoint report.

### 1. Done (what happened this session)

Summarize each meaningful deliverable in 2–3 lines: what was built, scoped, fixed, or decided; links to PRs/issues/commits; key design decisions and WHY. Detailed enough that someone (or a `/pickup`) can resume tomorrow without re-reading the conversation.

### 2. Dirty (uncommitted work)

Run `git status` and `git diff --stat` for the active repo. Report modified-but-uncommitted files and new untracked files. If clean, say "Clean — nothing to commit."

**Snapshot of current state, not history.** Don't list files that were already committed and pushed earlier in the session — those are done, not dirty. Do NOT commit anything; just report.

### 3. Context

Estimate context usage from conversation length and tool calls:
- **< 40%:** "Plenty of room. Keep going."
- **40–70%:** "Moderate use. Good for a few more tasks."
- **70–85%:** "Getting full. Consider wrapping up or starting fresh for complex work."
- **> 85%:** "Near limit. Wrap up and start a new session."

### 4. Next Steps (80/20)

List 2–4 highest-impact next actions, sorted by ROI. For each: **What** (one line), **Why it matters** (impact / what it unblocks), **Effort** (quick/medium/deep). Consider what unblocks other work, what's quick vs. needs a new session, and what has external dependencies.

### 5. Handoff Note (optional)

Anything non-obvious the next session needs — a gotcha, a deferred decision, a file in a weird state. Otherwise skip.

## Output Format

```
## Checkpoint — {project or "Cross-project"}

### Done
- [deliverable with context]

### Dirty
[git status output or "Clean"]

### Context: ~X% used (low/moderate/high)
[one-line recommendation]

### Next (80/20)
1. **[action]** — [why] _(effort)_
2. **[action]** — [why] _(effort)_

### Handoff (if applicable)
[non-obvious context for next session]
```

## Rules

- **Don't start new work** — status only.
- **Don't auto-commit** — just report dirty state.
- **Be honest about context** — if running low, say so.
- **Keep it scannable** — 10 seconds to read, not 2 minutes.

$ARGUMENTS
