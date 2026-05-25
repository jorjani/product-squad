# /mockup — Tier 3 hi-fi static HTML with brand aesthetics

**Usage:** `/mockup [issue-number] [repo]` or `/mockup` with pasted issue text.

## Fidelity ladder position

```
/sketch → /wireframe → /schematic (opt) → /mockup → /prototype → production
  T0          T1               T2              T3          T4         T5
ASCII     Moqups HTML       annotation      styled HTML  +interactive
                            overlay
```

| Inherits from | Adds | Defers to next | Output URL pattern |
|---|---|---|---|
| `/wireframe` (T1) — IA, layout, state coverage, primitives | Typography, color, spacing, iconography, imagery, responsive behavior | Motion, microinteraction, full interactivity → `/prototype` | `https://<project>.<domain>/specs/<num>-mockup.html` |

## Purpose

Tier 3 of the design ladder. The **aesthetic contract**: how the wireframe-validated structure actually looks in brand-aligned form. Hi-fi static HTML with real design tokens from the project's `.studio/design.md` (or equivalent). Single best state — not multi-state coverage (that's wireframe's job).

**Use when** aesthetic direction is contested and needs visual decision before the builder applies it. **Skip when** the builder can apply tokens deterministically from a wireframe + design.md.

## What this tier OWNS (locks at scope time)

- **Typography** — font family, scale, weights, line-heights
- **Color** — palette applied; brand accents in correct positions; semantic colors (success/warn/error/info)
- **Spacing & rhythm** — real px values for padding, margins, gaps
- **Iconography** — actual icons in correct positions, not placeholder mountains
- **Imagery** — real images or representative photos, not gray boxes
- **Responsive behavior** (if material to layout) — breakpoint adaptations
- **Visual hierarchy** — what stands out, what recedes

## What this tier DEFERS

- Multi-state coverage → already locked by `/wireframe`
- Motion, transitions, microinteraction → `/prototype`
- Interactive behavior (clickable, navigable) → `/prototype`
- Per-instance pixel polishing → the builder applies at implementation

## Visual properties

- **Palette:** real brand colors from `.studio/design.md` (or project equivalent)
- **Typography:** real font stack from design tokens
- **Spacing:** real px values, real grid
- **Static:** single best state per page — usually the canonical happy state; or before/after diff if modifying existing UI
- **Production-realistic:** could plausibly be a screenshot of the built UI

## Workflow

### 1. Read predecessor wireframe

Required. The wireframe (`<repo>/specs/<num>-wireframe.html`) is the IA/layout/state contract. The mockup applies aesthetics on top — never re-decides structure. If no wireframe exists, run `/wireframe` first.

### 2. Read design tokens

Pull from the project's design system:
- `<repo>/.studio/design.md` — palette, typography, spacing tokens (canonical source). If absent, fall back to the generic template bundled at the repo root.
- `<repo>/public/css/base.css` or equivalent — runtime truth
- Tailwind config if applicable

If tokens conflict between files, the `.studio/design.md` doc is canonical; CSS mirrors.

### 3. Produce

Write `<repo>/specs/<num>-mockup.html`. Single state (the canonical happy state from the wireframe — usually State 1 Idle or the highest-decision-weight state). Apply tokens. Use real component primitives from `.studio/components.md`.

For before/after comparisons on existing UI, use a toggle or side-by-side layout within the mockup.

### 4. Render to PNG (optional)

If the mockup will be embedded in a GitHub issue body, run `/html-to-png <path>` to produce `<num>-mockup.png`. Same pattern as wireframe: embed PNG inline + link the HTML for click-through.

### 5. Commit

Specs go directly to main per `Projects/CLAUDE.md` "Spec File Commits". One commit: `specs(<num>): mockup`.

## Output checklist

- [ ] All brand tokens applied (color, typography, spacing) — no generic placeholders
- [ ] Real component primitives used (per `.studio/components.md`); no aesthetic reinvention
- [ ] Single canonical state — not multi-state (wireframe's job)
- [ ] If modifying existing UI: before/after toggle for review
- [ ] Inline image embed pattern matches `/wireframe`'s convention if going into an issue body

## When to escalate

- → `/prototype` when interaction or motion needs to be felt before commit

## When to step back

- → `/wireframe` when aesthetic work is exposing IA/state-coverage holes
- → `/sketch` when the entire approach is wrong and aesthetics are premature

## Related

- `/sketch` — Tier 0 (ASCII, one state, IA-only)
- `/wireframe` — Tier 1 predecessor (Moqups HTML, multi-state, architecture contract)
- `/schematic` — Tier 2 optional (annotation overlay)
- `/prototype` — Tier 4 successor (interactive HTML with motion)
- `/html-to-png` — render to PNG for inline GitHub embedding
- `<repo>/.studio/design.md` — token source of truth
- `<repo>/.studio/components.md` — primitive catalog

## Anti-patterns

- **Don't redesign structure.** Wireframe locked that. Mockup applies aesthetics only.
- **Don't show multiple states.** Wireframe owns multi-state coverage. Mockup is single-state.
- **Don't invent design tokens.** Read from `.studio/design.md`. If a needed token doesn't exist, add it there before using it.
- **Don't skip the wireframe.** Mockup-without-wireframe forces architecture and aesthetic decisions simultaneously — same trap as starting at `/prototype` for a Scope ticket.
