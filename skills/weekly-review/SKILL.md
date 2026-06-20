---
name: weekly-review
description: Run a weekly review-and-reset ritual — review the week's work from your logs, produce a time-allocation breakdown, score what shipped vs. what merely moved forward, grade against stated goals, coach on the one highest-leverage move for next week, then propose next week's goals. Generic cadence pattern adaptable to whatever your work log looks like (session notes, git history, a TODO done-log). Use at the close of a work week. Pairs with /mochary (priority coaching), /retro (process retrospective), and /todo (the task backlog this reads from).
---

# /weekly-review — Weekly Review + Priority Reset

Generic purpose: turn a week of scattered activity into (1) an honest account of where time went, (2) a goals-vs-reality grade, (3) one high-leverage focus for next week, and (4) a committed goal set. A repeatable cadence ritual, not a one-off report.

**Usage:** `/weekly-review` (current week) · `/weekly-review last` · `/weekly-review W10`

**Adapt the data sources to what you have.** This skill assumes three inputs; substitute freely:

| Input | If you keep it as… | Fallback |
|---|---|---|
| Week's work | session log, daily notes | `git log --since` across your repos |
| Open tasks + goals | a root `TODO.md` | your issue tracker's "this sprint" |
| Long-term priorities | a `PRIORITIES.md` | ask the user for 3–5 priorities |

## Step 1 — Gather data

Determine the target week from the argument (blank = current ISO week; `last` = previous; `W##` = that week). Read the week's work log, the task/goals list, and the long-term priorities doc. Glob any per-project task files for open P0/P1 items.

## Step 2 — Week in review

**Time allocation.** Parse durations from the log (`~XX min`, `~X hr`). Deduplicate: same project + timestamps within 5 min = one session logged twice (count the longer). Produce a table sorted by hours descending with a **Total** row:

| Project | Hours | % |
|---------|-------|---|

**Per-project breakdown.** For each project with ≥15 min, list outcomes as numbered items with a stable prefix so the user can reference any one ("tell me more about S3"):

- **Shipped (S#)** — a user/customer can see it: merged to production, published, delivered to an external party.
- **Moved Forward (M#)** — internal progress: specs, plans, decisions, infra, reviews.

Number sequentially across the whole review (S1, S2…; M1, M2…). Each item must stand alone — describe the **outcome or why it matters**, not the mechanics. "Fixed the job checker that had silently failed for two weeks" — not "switched cron." Skip pure housekeeping unless it had visible impact.

## Step 3 — Goals vs reality

For each stated goal, grade Hit / Partial / Missed with one sentence of evidence (G# prefix). No goals set → say so and flag it as a gap.

## Step 4 — Big-picture check

For each long-term priority, assess whether this week advanced / maintained / ignored / put it at risk (P# prefix, one sentence each). No priorities doc → ask the user for their 3–5 and offer to create one.

## Step 5 — Priority coaching (the most important section, no line limit)

Apply a big-picture coaching lens — see [`mochary`](../mochary/SKILL.md) for the full frame:

1. **Energy audit** — where did time *actually* go vs. goals and priorities? Name patterns: avoidance, over-indexing on tooling, reactive vs. intentional, spread too thin.
2. **The one thing** — single highest-leverage move for next week. Not urgent, not fun — what unblocks the most? "If you could do only ONE thing next week, what makes the week a success?" **Bold it.**
3. **Fear check** — if the goals-vs-reality gap reveals something being avoided, name it directly. Skip if nothing is.
4. **Commitment** — ask for one concrete commitment: what, by when, how you'll know it's done. **Bold the question.**

Name the priority and ask for commitment — don't solve the problem here.

## Step 6 — Next-week proposal

From open P0/P1 items, this week's momentum, and the coaching above: propose **5–7 goals** (N# prefix, one line of context each), then flag items to **cut or defer** (D# prefix, with why). Max 7 — force prioritization. Ask the user to confirm/edit before writing anything.

## Step 7 — Write updates (only after approval)

1. Archive completed items first (while the current week's header still names the week being closed).
2. Update the task/goals doc: roll the week header forward; replace goals with the approved set.
3. Write a weekly log capturing Priorities / Context / Completed / Did-not-happen / Shifted / Decisions / Coach-assessment. Skip any empty section. Brief > comprehensive.

## Rules

- **Number everything** — S#/M#/G#/P#/N#/D#, sequential, so any item is addressable.
- **Bullets, not paragraphs. Plain English** — no PR/issue numbers, no code references; describe what it *is*.
- **Shipped = user-visible.** Docs, specs, internal tools = Moved Forward.
- **Coaching section has no line limit.** Be direct, bold, ask hard questions.
- **Never auto-write.** Always propose first; write only after explicit approval.
