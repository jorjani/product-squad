---
name: decompose
description: Break a spec or shaped feature into sharp single-surface idea-phrasings — each a "who does what where why" one-liner ready for the visual ladder. Use when a feature is too broad for one visual and needs splitting into distinct UI surfaces before /sketch, /wireframe, or ./draw. The bridge from the scoping cluster to the visual ladder.
---

# /decompose — Spec → Draw-Ready Idea Phrasings

A `/spec` is a contract — rich, multi-surface, more context than a sharp visual wants. The visual ladder (`./draw`, `/sketch`, `/wireframe`, `/mockup`, `/prototype`) does its best work from **one surface, one sentence**. `/decompose` is the adapter: it splits a feature into the distinct UI surfaces it actually contains, each phrased the way the ladder reads it.

**Consumes:** A `/spec` document, a `/shape` output, or a raw feature description.

**Delivers:** N idea-phrasings — each one UI surface, in the "who does what where why" one-sentence shape — plus the exact `./draw` command to visualize each. Feeds the visual ladder directly.

---

## The target shape

Every phrasing is a single sentence naming **who** does **what**, **where**, and **why** — the "just right" shape the ladder is tuned for (see `examples/idea-fixture.md`):

> "Students upload a resume to a course project page so peers can review it before the deadline."

One surface. One motion. One sentence. Not "the whole feature."

## Process

1. **Inventory the surfaces.** Read the spec and list every distinct UI surface or motion it implies — a form, a table, an empty state, a confirmation, a settings panel, a detail view. A rich feature usually has 3-6.
2. **Phrase each as who/what/where/why.** One sentence each: concrete user, concrete action, concrete surface, concrete reason. Strip implementation detail — the ladder reads intent, not architecture.
3. **Drop the un-visualizable.** Some spec items are logic, not surfaces (a cron job, a validation rule, a rate limit). Name them as "no surface" rather than forcing a phrasing.
4. **Recommend a starting surface.** Name the ONE phrasing that, drawn first, teaches the most about the feature — usually the primary happy-path surface. The operator visualizes that, then decides whether the rest earn a ladder run.

## Output Format

```
## Decompose — <feature>

Surfaces worth visualizing (<n>):

1. **<surface name>** — "<who does what where why, one sentence>"
   ./draw "<the same phrasing>"

2. **<surface name>** — "<phrasing>"
   ./draw "<phrasing>"

No surface (skip the ladder):
- <logic-only item> — <why it has no UI>

**Draw this first:** #<n> — <one line on why it's the most instructive surface>.
```

---

## Rules

- **One surface per phrasing.** If a phrasing needs an "and," it's two surfaces — split it.
- **Who/what/where/why, every time.** A phrasing missing the user or the reason produces shallow visuals. Match the idea-fixture shape exactly.
- **Don't force UI onto logic.** Validation, jobs, and rules have no surface — name them and move on. Padding the list with fake surfaces wastes ladder runs.
- **Recommend, don't dump.** Always name the one to draw first. A list of six with no priority is the same problem the spec had.
- **No implementation detail.** A phrasing is intent for a designer, not a ticket for an engineer.

$ARGUMENTS
