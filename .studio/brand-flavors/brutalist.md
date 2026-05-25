---
name: brutalist
identity: indie hacker, research tool, anti-design honesty
colors:
  primary: "#000000"
  primary-hover: "#000000"
  primary-subtle: "#f4f4f4"
  accent: "#39ff14"
  accent-2: "#ff00aa"
  canvas: "#fefefe"
  surface: "#ffffff"
  surface-2: "#f4f4f4"
  surface-3: "#e4e4e4"
  on-surface: "#000000"
  on-surface-2: "#444444"
  on-surface-3: "#777777"
  border: "#000000"
  border-strong: "#000000"
  success: "#000000"
  warning: "#000000"
  danger: "#000000"
typography:
  font-sans: '"JetBrains Mono", "IBM Plex Mono", ui-monospace, monospace'
  font-mono: '"JetBrains Mono", "IBM Plex Mono", ui-monospace, monospace'
  body-size: 14px
  body-line-height: 1.5
  body-weight: 400
  heading-weight: 700
  numerals: tabular-nums
radii:
  sm: 0px
  md: 0px
  lg: 0px
  full: 0px
spacing:
  base: 4px
  scale: [0, 4, 8, 12, 16, 24, 32, 48, 64]
surface-treatment: stark-thick-border
shadows: none
border-width: 2px
---

# brutalist

## Overview

Indie hacker, research tool, anti-design honesty. The interface refuses to charm; it presents information and gets out of the way. Everything is monospace; everything has hard edges; everything has thick black borders. Color is reserved for the *one* thing that demands attention — and the chosen accent is intentionally loud against the otherwise stark layout. This is the *honest-information-display* school: it should look like a paper printout from 1989, in the best possible way.

## Colors

- **Canvas** (`#fefefe`): off-white. Pure white reads as sterile; this is slightly warmer.
- **Surface** (`#ffffff`): card / content surfaces, distinct from canvas by 1 shade.
- **Surface-2** (`#f4f4f4`): nested surfaces, table headers, code blocks.
- **Surface-3** (`#e4e4e4`): hover states, active selections.
- **On-surface** (`#000000`): primary text. **Yes, pure black.** This flavor wants maximum contrast.
- **On-surface-2** (`#444444`): secondary text — descriptions, captions.
- **On-surface-3** (`#777777`): tertiary text — disabled, placeholders.
- **Primary** (`#000000`): the page itself is the brand. CTAs use black fill with white text.
- **Accent** (`#39ff14`): neon green. Used SPARINGLY for the *one* thing that demands attention — an active row's left-border, a status badge, the cursor on a focused input.
- **Accent-2** (`#ff00aa`): hot pink. Reserved for destructive confirmations and "this is irreversible" warnings. Never decorative.
- **Semantic states** (`success` / `warning` / `danger`): all resolve to `#000000`. This flavor does not use color to encode state — that's the design choice, not a bug. Use the `accent` neon green to mark active/live items, `accent-2` hot pink for destructive/irreversible. Status badges differentiate via UPPERCASE text labels and border treatment, not fill color. A "warning" badge looks identical to a "success" badge except for its label and an `accent` border if it requires attention.
- **Borders**: `#000000` everywhere. 2px is the default border-width — thicker than other flavors deliberately.

## Typography

- **Body**: JetBrains Mono, 14px base, 1.5 line-height. **Monospace everywhere** — no sans-serif anywhere in the UI.
- **Body weight**: 400 baseline.
- **Headings**: JetBrains Mono 700. Size hierarchy comes from size jumps (14 / 18 / 24 / 32), not weight contrast.
- **UPPERCASE LABELS**: section headers and small labels use UPPERCASE with `letter-spacing: 0.08em`. Reserved for navigation, status badges, eyebrow text. Body content stays sentence case.
- **Numerals**: always tabular. Right-align by default.

## Components

- **Buttons**: ZERO radius. Black fill + white text for primary. Secondary is white surface + 2px black border + black text. Hover inverts colors (black bg ↔ white bg). No transition; instant. Padding 8-16. Sometimes include a `[ ]` or `>` glyph as part of the label to signal "this is interactive."
- **Inputs**: 2px black border, white surface, 0 radius. Focus state: border stays, accent green underline appears below the input as a 2px bar. Placeholder in on-surface-3.
- **Cards**: white surface, 2px black border, 0 radius. NO shadow ever. Hover may shift to surface-2 fill (no other change).
- **Tabs**: not pill or underline — `[Tab Name]` with brackets typed as literal text, active tab fills black with white text.
- **Tables**: 2px black border around the whole table; 1px black between rows. Headers use UPPERCASE letterspaced labels in surface-2 background. Cell padding tight (6-10).
- **Status badges**: rectangular, 2px black border, fill in surface OR accent green for "active/live" state. Text UPPERCASE.
- **Page header**: large 32px title, optional `> subtitle in mono` below. Action cluster right with bracketed `[ button ]` styling.
- **Lists**: every item separated by a hairline rule (`1px solid #000`); checkbox / radio uses `[ ]` / `( )` literal characters typed as text or styled as 2px-bordered squares/circles.

## Do's and Don'ts

- **Do** use UPPERCASE letterspaced labels for nav, badges, eyebrow text. They're a signature of the flavor.
- **Do** keep the accent green for ONE element per view. Its purpose is to redirect attention — overusing kills it.
- **Do** use 2px borders everywhere borders appear — thinner reads as accidental.
- **Do** use monospace for body text. This is not a "we tried to be clever" choice; it's the entire flavor.
- **Do** maintain WCAG AAA contrast where possible — black-on-white starts at 21:1; reserve lower contrast only for genuinely tertiary text.
- **Don't** introduce ANY radii. Sharp corners are non-negotiable.
- **Don't** introduce ANY drop shadows. Borders carry separation.
- **Don't** use sans-serif anywhere. The whole flavor is "the printout aesthetic."
- **Don't** add gradients, animations, or hover-fade transitions. Hover is instant or nothing.
- **Don't** soften the accent green by tinting it. `#39ff14` at full saturation or it doesn't work.
- **Don't** apologize for the look in marketing copy. The flavor's honesty IS its tone.
