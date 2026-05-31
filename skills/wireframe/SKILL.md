---
name: wireframe
description: Produce multi-state HTML with state-toggle navigation, in moqups dashed-border aesthetic. Use when the user wants to lay out information architecture and edge states for a feature. State-count cap 3-5 (one happy + two most-instructive edges).
---

# /wireframe — Tier 1 mid-fi visual artifact (Moqups-style HTML)

**Usage:** `/wireframe [issue-number] [repo]` or `/wireframe` with pasted issue text.

## Fidelity ladder position

```
/sketch → /wireframe → /schematic (opt) → /mockup → /prototype → production
  T0          T1               T2              T3          T4         T5
ASCII     Moqups HTML       annotation      styled HTML  +interactive
                            overlay
```

| Inherits from | Adds | Defers to next | Output URL pattern |
|---|---|---|---|
| `/sketch` (T0 ASCII) | Spatial fidelity, multi-state coverage, primitive refs, microcopy direction, edge cases | Aesthetics (typography, color, spacing) → `/mockup`; motion/interactivity → `/prototype` | `https://<project>.<domain>/specs/<num>-wireframe.html` |

## Purpose

Tier 1 of the design ladder. The **architecture contract**: where things go, what hierarchy they sit in, what information each region carries, how states transition. Moqups-style HTML — grayscale, real spatial layout, mountain/box placeholders for images, generic chrome (no brand colors, no typography commitment, no aesthetics).

**Default rung for any UI ticket at Scope/Ready status.** Don't skip to mockup or prototype unless this tier has been validated.

## What this tier OWNS (locks at scope time)

- **Information architecture** — what data + components live where
- **Layout / spatial composition** — two-pane vs single, regions, hierarchy
- **State design** — all states (happy + edge + error + empty + loading)
- **Component primitive selection** — which existing primitives are reused (from project's `design-system/components.md`)
- **Microcopy direction** — actual button labels, headings, helper text
- **Edge-case states** — explicit, not implicit

## What this tier DEFERS (do not commit to here)

- Typography, color, spacing values, iconography, imagery → `/mockup`
- Motion, transitions, microinteraction → `/prototype`
- Per-component styling (px, radii, shadow, hover) → the builder applies at implementation
- Accessibility specifics → the builder applies; flag in wireframe annotations if critical
- Responsive behavior → the builder applies or `/mockup` if it materially affects layout

## Visual properties (the Moqups-style aesthetic)

- **Palette:** white background, light gray fills, medium gray borders, dark gray text. NO brand colors.
- **Borders:** dashed (visibly-a-sketch) for content regions, solid for chrome
- **Typography:** default sans-serif at one or two sizes; no font system commitment
- **Placeholder shapes:** mountain-and-sun motif for images, simple gray rectangles for unknown content blocks, generic pill/button chrome
- **Annotations:** yellow-bg callout boxes for primitive refs and design rationale; red-bg callout boxes for open questions
- **Multi-state:** all states stacked vertically with anchor links (top-of-doc TOC) for fast navigation

## Workflow

### 1. Read

Fetch the issue body or pasted text. Identify:

- **Surface(s)** — which UI region(s) change
- **States** — list every state including edge cases (empty, error, loading, cancel, retry)
- **Primitives reused** — grep `design-system/components.md` (or equivalent) for existing components

If states or primitives aren't named, ask before drawing.

### 2. Produce

Write `<repo>/specs/<num>-wireframe.html` with the visual properties above. Structure:

```
<doc-header>: title + tier chip
<nav-toc>: anchor links to every state
<section A: Happy path>: 4-6 states
<section B: Edge cases>: all remaining states (cancel, retry, error, empty, etc.)
<section C: Primitive references>: list of reused primitives with file refs
<section D: Open questions>: explicit list of decisions deferred to builder
```

Each state card:
- State number + name + entry transition
- Editor/page wireframe at compact scale
- Callout(s) with annotations and primitive refs

### 3. Make the wireframe viewable from the issue

The issue body must let a reader see the wireframe. The in-body **Tier 1 ASCII** (carried per `issue-conventions.md`) is the 10-second skim; the committed HTML is the full artifact. How a reader reaches the rendered HTML depends on the repo:

- **Repo has a live-render gateway** (serves `specs/*.html` as rendered HTML — e.g. Netlify, Cloudflare Pages, GitHub Pages, or any static-asset CDN pointing at the repo's `specs/` dir): **skip the PNG.** Link the live-render URL for full fidelity. The in-body ASCII covers the inline skim — nothing else is needed, no binary to commit or keep in sync.

  ```
  Wireframe: https://<project>.<domain>/specs/<num>-wireframe.html (live) | https://github.com/<org>/<repo>/blob/main/specs/<num>-wireframe.html (source)
  ```

- **Repo has no render gateway:** GitHub shows a committed `.html` as source code, not a rendered page. Render a PNG with `/html-to-png <path>`, commit it alongside the HTML, and embed it inline so the issue is viewable without a clone:

  ```
  ![Wireframe — N states](https://github.com/<org>/<repo>/blob/main/specs/<num>-wireframe.png?raw=1)
  ```

  Also link the committed HTML source, so the interactive multi-state artifact (anchor-nav between states) stays reachable from the issue:

  ```
  Wireframe source: https://github.com/<org>/<repo>/blob/main/specs/<num>-wireframe.html
  ```

  **Verify after posting.** Open the issue in a fresh tab and confirm the image renders. If it fails (viewer lacks repo access on a private repo), drag-and-drop the PNG into the GitHub UI for a stable `user-images.githubusercontent.com` URL.

**Default: skip the PNG.** Render one only for repos with no live-render gateway. A PNG is a 500KB+ binary that silently drifts the moment the HTML is edited — earn it, don't default to it.

### 4. Commit

Specs go directly to main per `Projects/CLAUDE.md` "Spec File Commits". One commit per ticket: `specs(<num>): wireframe` — append `+ screenshot` only when a PNG was generated.

## Output checklist

- [ ] All states (happy + edge) rendered as anchored sections
- [ ] Every reused primitive named with file path
- [ ] Open questions surfaced as red callouts, not silent assumptions
- [ ] No brand colors, no typography commitment, no spacing precision
- [ ] Issue body links the wireframe HTML — live-render URL where the repo has a gateway
- [ ] PNG generated only if the repo has no render gateway; skipped by default

## When to escalate

- → `/mockup` when the aesthetic direction is contested and needs visual decision before build
- → `/prototype` when interaction or motion needs to be felt before commit
- → `/schematic` (optional) when wireframe alone can't capture multi-screen flow or custom-component internals

## When to step back

- → `/sketch` when the wireframe is forcing premature commitment and the IA is still open

## Related

- `/sketch` — Tier 0 predecessor (ASCII, one state, IA-only)
- `/mockup` — Tier 3 successor (hi-fi static HTML with aesthetics)
- `/prototype` — Tier 4 successor (interactive HTML)
- `/html-to-png` — render the wireframe HTML to PNG; only for repos without a live-render gateway
- `/shape` — names "Visual" as the bottleneck that routes to `/wireframe`
- Trigger map (project guardrail) — designing or prototyping any UI surface → reads project's `design-system/components.md`. A generic template ships at the repo root (`design-system/components.md`) for projects without their own.
