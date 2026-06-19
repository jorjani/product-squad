---
name: crap
description: Audit a UI against the four CRAP design principles — Contrast, Repetition, Alignment, Proximity — grounding every finding in actual component code and design tokens. Use for visual-hierarchy and scanning polish on a built page. Distinct from /a11y (contrast math only), /brand-audit (token consistency), and /ux-design (states + responsiveness); this one judges layout legibility.
---

# /crap — Visual Design Audit (CRAP Principles)

**Usage:** `/crap [screenshot or page description]`

Audit a UI page against Contrast, Repetition, Alignment, Proximity (Robin Williams, *The Non-Designer's Design Book*). Produces ranked, code-grounded fixes. Part of the audit family with /a11y, /brand-audit, and /ux-design; when a fix becomes a redesign, move to /mockup or /prototype.

User typically shares a screenshot. If they name a route, navigate to the component code.

## Step 1 — Identify the UI
Screenshot: analyze layout, cards, typography, spacing, color, hierarchy. Route name: find the component tree. Always read the project's theme/design-system files (CSS variables, Tailwind config, brand tokens) to learn what tokens exist vs. what's used.

## Step 2 — Read the code
Before any judgment, read: the page/layout component, key child components in view, global theme/tokens, component-specific CSS. You need exact class names, spacing, font sizes, and color tokens. Never critique from the screenshot alone — code tells you intentional vs. accidental.

## Step 3 — Audit each principle
For each, give **what's working** (1 sentence) and **what's not** (findings with code references).

- **Contrast** — *"If two elements are not the same, make them very different."* Hierarchy, weight/size differentiation, primary vs. secondary vs. noise, active/inactive states, signal data vs. filler.
- **Repetition** — *"Repeat visual elements for consistency."* Consistent card treatment, predictable placement of recurring elements, badge/tag/icon consistency, do all cards end the same way.
- **Alignment** — *"Every element has a visual connection to another."* Grid alignment across a row, vertical alignment of comparable data, clean internal edges, text-alignment consistency, ragged rows from uneven heights.
- **Proximity** — *"Related items grouped together."* Related data visually separated, unrelated data fused, metadata grouped by meaning, whitespace signaling groups, dense compound lines.

## Step 4 — Rank by ROI
Score each finding: Impact (H/M/L) and Effort (Trivial <5 / Small 5-20 / Medium 20-50 lines). Sort highest impact, lowest effort first.

## Step 5 — Output

```
## CRAP Audit: [Page Name]
**Components:** [files read, with line refs]

### Contrast / Repetition / Alignment / Proximity
**Working:** [1 sentence]
**Findings:** 1. [finding + code ref] — Impact: [H/M/L], Effort: [T/S/M]

### High-ROI Changes (Top 5)
| # | Fix | Principle | Impact | Effort | Files |
|---|-----|-----------|--------|--------|-------|

### Implementation Notes
[1-2 sentences per top-5 fix — exact classes/utilities/structure]
```

## Key Principles
1. **Code-grounded, not screenshot-only** — reference specific classes and values.
2. **Scanning > reading** — card grids and dashboards are scanned; judge every finding by "does this help scanning?"
3. **Surgical over sweeping** — smallest change, biggest improvement.
4. **Respect the design system** — work within existing tokens; don't invent colors or spacing.
5. **One principle can mask another** — name the root principle that resolves the most symptoms.

## Does NOT
Redesign pages, evaluate UX flows or interaction design (that's /ux-design), create mockups, or make subjective aesthetic calls.

$ARGUMENTS
