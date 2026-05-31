---
name: prototype
description: Single-file interactive HTML with vanilla JS state transitions. Use for the highest-fidelity tier; covers 6-10 states with click-through walkthrough. Initial landing state must be EMPTY/FIRST-USE, not the populated dashboard.
---

# /prototype — Tier 4 interactive HTML prototype

**Usage:** `/prototype [issue-number] [repo]` or `/prototype [feature name or paste spec/owit output]`

## Fidelity ladder position

```
/sketch → /wireframe → /schematic (opt) → /mockup → /prototype → production
  T0          T1               T2              T3          T4         T5
ASCII     Moqups HTML       annotation      styled HTML  +interactive
                            overlay
```

| Inherits from | Adds | Defers to next | Output URL pattern |
|---|---|---|---|
| `/mockup` (T3) — aesthetics applied on top of `/wireframe` (T1) structure | Interactivity, motion, microinteraction, clickable state navigation | Production code, real APIs, full accessibility, performance work | `https://<project>.<domain>/specs/<num>-prototype.html` |

## Purpose

Tier 4 of the design ladder. The **interaction contract**: how the styled UI behaves when the user clicks, hovers, navigates between states. Hi-fi interactive HTML — production aesthetics + state transitions + animation timing + microinteractions. Self-contained single file (vanilla JS or Tailwind CDN; no build step).

**Use when** the feel of the interaction matters before committing to build — micro-interactions, animation, multi-step flows, state transitions worth pre-validating. **Skip** if a mockup plus the wireframe's state coverage are enough for the builder to ship correctly.

## What this tier OWNS (locks at scope time)

- **Motion** — animation timing, easing, duration, choreography
- **Microinteraction** — hover feedback, click affordances, drag/scroll feel
- **Interactive state transitions** — clickable navigation between the states defined in the wireframe
- **Loading / skeleton patterns** — perceived performance
- **Form behavior** — validation feel, error recovery flow

## What this tier DEFERS

- All structural decisions → `/wireframe` already locked them
- Aesthetic decisions → `/mockup` already locked them
- Real backend APIs, persistence, auth → production
- Full accessibility (keyboard nav, ARIA, screen reader) → the builder at implementation
- Cross-browser polish → the builder at implementation

## Visual properties

- **Aesthetic:** inherits `/mockup`'s palette + typography + spacing + iconography
- **State coverage:** inherits `/wireframe`'s multi-state model — all states clickable
- **Interaction:** real clickable state transitions, real form behavior, real motion
- **Data:** plausible mock content (not Lorem ipsum); realistic names, dates, copy
- **Production-realistic:** could plausibly be a screen-recording of the built UI

## Workflow

### 1. Read predecessors

Required. Read `<repo>/specs/<num>-wireframe.html` (structure + states) and `<num>-mockup.html` if it exists (aesthetics). If only a wireframe exists, pull design tokens from `<repo>/design-system/design.md` and apply them in the prototype directly.

### 2. Read design tokens + primitive catalog

- `<repo>/design-system/design.md` — palette, typography, spacing (if absent, fall back to the generic template at the repo root)
- `<repo>/design-system/components.md` — primitive APIs (reuse, don't reinvent)
- Tailwind/CSS variable config if applicable

### 3. Produce

Write `<repo>/specs/<num>-prototype.html` — single self-contained file:

**Structure:**
- Vanilla HTML + CSS + JS, OR Tailwind CDN (no build step required)
- Inline brand tokens at top
- Real clickable navigation between states
- Real form validation, real hover/click feedback

**Include:**
- All states from the wireframe, clickable
- Real motion (CSS transitions, simple JS animations)
- Plausible mock data — no "Lorem ipsum"
- Hover, click, focus states

**Don't include:**
- API calls or real backend connections
- Complex state management (vanilla JS only)
- Animation libraries (use CSS transitions + simple JS)
- Production-grade accessibility (the builder applies at implementation)

### 4. Render to PNG (optional)

For inline embedding in a GitHub issue body, run `/html-to-png <path>` to produce `<num>-prototype.png` showing a representative state (usually the canonical happy state). Same embed pattern as `/wireframe`: PNG inline + HTML link for click-through interactivity.

### 5. Commit

Specs go directly to main per `Projects/CLAUDE.md` "Spec File Commits". One commit: `specs(<num>): prototype`.

## Output checklist

- [ ] All states from the wireframe are reachable via real clicks (state navigation works)
- [ ] Aesthetics match the mockup (or apply tokens directly if no mockup exists)
- [ ] Motion / transitions feel real (CSS transitions ≥ 150ms; easing curves applied)
- [ ] Forms validate, modals open / close, dropdowns toggle
- [ ] Plausible mock data — no Lorem ipsum
- [ ] Single self-contained file — opens with double-click in any browser

## When to step back

- → `/mockup` if pixel decisions are wrong and a static aesthetic re-validation is needed
- → `/wireframe` if state coverage or layout is wrong (rare — usually caught at T1)

## Related

- `/sketch` — Tier 0 (ASCII, one state, IA-only)
- `/wireframe` — Tier 1 (Moqups HTML, multi-state architecture contract)
- `/schematic` — Tier 2 optional (annotation overlay)
- `/mockup` — Tier 3 predecessor (hi-fi static HTML with aesthetics)
- `/html-to-png` — render to PNG for inline GitHub embedding
- `<repo>/design-system/design.md` — token source of truth
- `<repo>/design-system/components.md` — primitive catalog

## Anti-patterns

- **Don't redesign structure or aesthetics.** Wireframe + Mockup locked those. Prototype adds interaction only.
- **Don't connect to real APIs.** Prototypes are conversation artifacts, not code. `setTimeout` + mock data only.
- **Don't ship prototype HTML to production.** Throwaway by design; delete after the real implementation ships.
- **Don't skip the wireframe.** Prototype-without-wireframe forces structure + aesthetics + interaction decisions simultaneously — the "design three times" trap.
