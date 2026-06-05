---
name: shape
description: Decide what to build via options-menu + capability-delta + cuts (Shape Up methodology). Use when the user has a why but multiple paths forward and needs to commit to one shape before going deeper.
---

# /shape — Shape Up: Decide What to Build

**Purpose:** Before detailing anything, decide what's worth building and what's not. Present the problem, show what exists, lay out options with effort and value, and let the user configure the scope. Inspired by Basecamp's Shape Up methodology.

**Usage:** `/shape [idea or problem]`

**Consumes:** A raw idea OR `/why`'s outcome statement. When given the latter, use it as the "Why it matters" in Step 2 — don't re-derive intent.

**Delivers:** Selected option(s) + capability delta + named bottlenecks + principles + audience hint. Feeds `/experience` (audience hint + selected option become the lens + surface) and `/owit` (the brief to scenario-spec against).

---

## Flow

```
/shape (THIS — decide what to build, name 1-3 bottlenecks)
  │
  ├── Small scope, no bottlenecks → /spec directly
  │
  └── Bottlenecks named → run tightener(s) from Loose-end taxonomy
                            │  /wireframe, /mockup, /ui-diff (alias), /prototype
                            │  /flow, /api, /migrate, @eng-deep-dive
                            │
                            └── /spec (aggregate artifacts; rewrite body to Scope-form;
                                       advance column Pitch → Scope)
                                  │
                                  └── Foreman triage → Ready → Build
                                        │
                                        └── /eng-review (pre-merge) → Merge → /verify
```

> **V0.5 bundled commands:** `/why`, `/vet`, `/shape`, `/experience`, `/owit`, `/elon`, `/spec`, `/wireframe`, `/mockup`, `/prototype`. **Planned for V1 (not in V0.5):** `/flow`, `/api`, `/migrate`, `@eng-deep-dive`, `/eng-review`, `/verify`, `Foreman` (the orchestrator). For V0.5, manual review takes the place of Foreman/`/verify`.

---

## Step 1: Context Check

If the project has `design-system/` files, skim first:
1. `features.yaml` -- does this already partially exist?
2. `rules.yaml` -- any constraints?

If overlap or conflict, flag it before going further.

---

## Step 2: Problem + Base + Why

**Problem:** One sentence. What's broken, missing, or possible?

**Why it matters:** One sentence -- what outcome does this enable one level up? If `/why` was already run this session, reference that. If not, surface it yourself. The user needs to see you understand the goal, not just the task.

**Base model:** What exists today? What's the starting point? This grounds the conversation in reality, not greenfield assumptions. Read the codebase if needed.

---

## Step 3: Options Menu

This is the core of the command. Present options like a car configurator -- each one is an independent (or dependent) add-on the user can include or exclude.

| # | Option | Effort | Value | Needs |
|---|--------|--------|-------|-------|
| 1 | [thing] | [gut-level: 30 min / 2 hrs / 1 day / 1 week] | [what changes if this ships] | -- |
| 2 | [thing] | [effort] | [value] | #1 |
| 3 | [thing] | [effort] | [value] | -- |

**Rules:**
1. 3-8 options. Fewer means the scope is obvious (just build it). More means you haven't shaped enough.
2. **Effort is gut-level, not an estimate.** "~2 hours" not "2 hours 15 minutes." Relative sizing: is this a 30-min thing or a multi-day thing?
3. **Value is what changes for the user**, not what gets built. "Eliminates manual scoring" not "adds API integration."
4. **Dependencies noted.** If option 3 needs option 1, say so. This prevents picking incompatible combos.
5. **Include at least one option you'd cut.** If everything is essential, you haven't shaped -- you've just listed requirements.

---

## Step 4: What Changes for the User (Capability Delta)

The options menu says what gets built. This section says what the user can actually *do* afterward that they couldn't before — and what still won't work. **This is the most important part of the shape output.** (The term "capability delta" comes from product engineering; if it's new to you, just read it as "what changes for the user.")

**Format: one block per option (or group of options), with a hard "still can't" list.**

```
**After [option]:**
[Concrete action the user can now take, in plain language. Specific > vague.]
- [Exact thing they can do #1]
- [Exact thing they can do #2]

**What it still can't do:**
- [Thing people assume is included but isn't]
- [Adjacent capability that requires separate work]

**The real unlock:** [One sentence on the meaningful change in behavior or workflow.]
```

**Rules:**
1. **Specific, not category.** "You can push a content idea from Claude Code directly into your your product's dashboard" not "enables programmatic access."
2. **Name what's excluded.** If LinkedIn posting still requires a browser OAuth flow after this ships, say so. Don't let vague value language imply it's included.
3. **One real unlock per option group.** If you can't name one concrete workflow that changes, the option may not be worth building.
4. **Keep it honest.** "You stop getting logged out on mobile. That's it. One setting, one outcome." is better than inflated value language.

**Example (from dual-auth feature):**

> **After Clerk session extension:**
> You stop getting logged out on mobile after inactivity. That's it. One setting, one outcome.
>
> **After CLI key middleware + Railway wiring:**
> Claude Code, running in terminal, can call these endpoints with a header:
> - `POST /api/ideas` — push a content idea into your pipeline (Express Mode runs, it appears in your dashboard)
> - `GET /api/dashboard` — read your existing ideas
> - `POST /api/ideas/:id/optimize` — trigger platform optimization on an idea
>
> **What it still can't do:**
> - Post to LinkedIn — that still needs your OAuth token from the browser session
> - Access admin endpoints — separate check, not covered by this key
> - Run automatically — needs something to call it (Claude Code session, a cron job, etc.)
>
> **The real unlock:** You're in a Claude Code session working on content, you generate an idea, and you push it directly to your your product's dashboard with one call — instead of copy-pasting it manually into the browser.

---

## Step 5: Principles, Constraints & Rabbit Holes

Three categories, ordered by agency:

**Principles** -- non-negotiable design commitments. These are choices you make about how this should work, not external limitations. They apply regardless of which options the user picks. State 2-4.
- "Zero config -- the user should never have to set anything up"
- "No data loss on any error path"
- "Works the same whether there's 1 record or 10,000"
- "The user should never need to context-switch to complete this task"

If you can't articulate any principles, the problem isn't understood well enough. If an option from Step 3 conflicts with a principle, flag the tension explicitly.

Principles flow downstream: `/spec` inherits them as design constraints, `/elon` checks if anything violates them, implementation respects them.

**Constraints** -- hard external blockers that limit solution space. Facts, not choices.
- Technical: "API rate limit is 300 req/month on free tier"
- Architectural: "Must work with existing auth middleware"
- Business: "Can't change the public API contract"

**Rabbit holes** -- risk multipliers where effort could unexpectedly expand. Warnings, not blockers.
- "If we need to support mobile, the table component won't work -- that's a redesign"
- "The enrichment pipeline assumes single-source; multi-source would be a rewrite"

Max 4 principles, 3 constraints, 3 rabbit holes. More of any means the idea needs more shaping.

---

## Step 6: User Picks Options

Ask the user which options they want. Their selection IS the scope.

---

## Step 7: Bottleneck callout

Walk the loose-end taxonomy — 5 categories of hardest unknowns that can block a build:

1. **Visual fidelity** — UI/UX details unclear → tighten with `/wireframe`, `/mockup`, `/prototype`
2. **State machine** — transitions / edge cases unclear → tighten with `/flow` (not bundled in V0.5; see V1 roadmap)
3. **API contract** — request/response shapes unclear → tighten with `/api` (V1)
4. **DB schema** — data model unclear → tighten with `/migrate` (V1)
5. **Codebase fit** — how the change plugs into existing code → tighten with `@eng-deep-dive` (V1)

For each category, judge whether it triggers given THIS ticket's picked options. Name 1-3 hardest unknowns. Default: none.

The callout goes in the Pitch body as its own section:

```
## Hardest unknowns (2)

1. Visual — inline-edit chip needs an interaction model (click-to-toggle vs hover-pencil). Recommend /ui-diff.
2. API — DELETE endpoint shape and idempotency unclear. Recommend /api.
```

Or:

```
## Hardest unknowns

None — existing pattern; skip to /spec.
```

Rules:

1. Typically 1; 2 when full-stack; 3 only when truly multi-axis. More than 3 means the picks are too ambitious — re-shape.
2. State the unknown in one line. Cite the taxonomy category by name (`Visual`, `State machine`, `API`, `DB schema`, `Codebase fit`) so a reader can check the rule.
3. Recommend the default tightener from the taxonomy. The user can pick a different rung within the same category (e.g., `/wireframe` instead of `/ui-diff` if lo-fi is enough).
4. `/spec`'s Step 0 verifies each named tightener produced its artifact before rewriting the body.

For non-trivial scope (3+ options selected or multi-day effort): after the user picks options and confirms bottlenecks, show brief delivery milestones — what's usable after each phase, not just a task list. Skip for small scope:

```
Phase 1 (~2 hrs): Options 1+2 ship. User can [do X].
Phase 2 (~1 day): Option 4 ships. User can [do Y].
```

If the selected scope needs detail, hand off to `/owit` to map behavior and resolve choices, then `/spec` to commit the contract.

---

## Principles

1. **Appetite over estimation.** Don't ask "how long will this take?" Ask "how much is this worth?" The user's time budget determines scope, not the other way around.
2. **Decide before detailing.** No wireframes, no data models, no prototypes at this stage. Those come in `/spec` after the user picks their scope.
3. **Options, not proposals.** Don't present one solution and ask for approval. Present a menu and let the user configure.
4. **Cut something.** If you can't identify an option to exclude, you're not shaping -- you're listing requirements. Shape Up's core insight: fixed time, variable scope.
5. **Self-sufficient.** This command should make sense even if the user didn't run `/why` or `@deep-dive` first. Surface the "why" and check the codebase yourself.

---

## Anti-Patterns

- **Presenting one solution:** "Here's what I'd build" -- that's a proposal, not shaping. Show options.
- **Everything is essential:** If all options are must-haves, you haven't shaped. Find the boundary.
- **Effort without value:** A column of "2 hrs, 4 hrs, 1 day" means nothing without "why you'd want this."
- **Rabbit holes as blockers:** If a rabbit hole blocks the entire idea, it's not a rabbit hole -- it's an unresolved problem. Resolve it first.
- **YAML/structured output:** This is a conversation, not a document. Tables and bullets, not schemas.
- **Missing the why:** Jumping straight to options without stating why this matters. Always lead with the outcome.
- **Vague capability claims:** "Enables programmatic access", "unlocks automation", "improves workflow" -- these are not capability deltas. Name the specific action the user can take. If you can't, you don't understand the value yet.
- **Skipping "still can't":** Omitting what doesn't change implies it does. Users will assume LinkedIn posting is included if you don't say it isn't. Name the exclusions.

$ARGUMENTS
