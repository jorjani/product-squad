---
name: industrial
identity: dev tool, ops dashboard, agent OS
colors:
  primary: "#3b82f6"
  primary-hover: "#2563eb"
  primary-subtle: "rgba(59,130,246,0.12)"
  accent: "#f59e0b"
  canvas: "#0a0a0d"
  surface: "#15151b"
  surface-2: "#1c1c24"
  surface-3: "#252530"
  on-surface: "#e8e9ee"
  on-surface-2: "#9098a8"
  on-surface-3: "#5a6072"
  border: "#26262f"
  border-strong: "#3a3a47"
  success: "#22c55e"
  warning: "#f59e0b"
  danger: "#ef4444"
  identifier: "#7dd3fc"
typography:
  font-sans: '"IBM Plex Sans", -apple-system, BlinkMacSystemFont, sans-serif'
  font-mono: '"IBM Plex Mono", ui-monospace, "SF Mono", Menlo, monospace'
  body-size: 13px
  body-line-height: 1.5
  body-weight: 400
  heading-weight: 500
  numerals: tabular-nums
radii:
  sm: 2px
  md: 4px
  lg: 6px
  full: 9999px
spacing:
  base: 4px
  scale: [0, 2, 4, 8, 12, 16, 20, 24, 32, 48]
surface-treatment: flat-bordered-dark
shadows: none
---

# industrial

## Overview

Dev tool, ops dashboard, agent OS. Dense information without clutter. Dark canvas, sharp edges, monospace for any value that's an identifier or a literal. This is the *terminal-adjacent* school — it should feel like something that respects the user's screen-time and rewards reading carefully. No cosmetic flourishes; every pixel earns its keep.

## Colors

- **Canvas** (`#0a0a0d`): near-black with a slight blue cast. The page; the OS background. Never pure black.
- **Surface** (`#15151b`): panels, cards, primary content surfaces. Distinct from canvas.
- **Surface-2** (`#1c1c24`): nested surfaces, sidebars, table headers, modal backgrounds.
- **Surface-3** (`#252530`): row-hover, active selections, small interactive zones.
- **On-surface** (`#e8e9ee`): primary text. **Never pure white.**
- **On-surface-2** (`#9098a8`): secondary text — labels, metadata, captions.
- **On-surface-3** (`#5a6072`): tertiary text — disabled states, placeholders.
- **Primary** (`#3b82f6`): electric blue. CTAs, primary affordances, focus rings. Use for *one* action per view.
- **Accent** (`#f59e0b`): amber. Warnings, "in-progress" states, attention markers. Never for buttons.
- **Identifier** (`#7dd3fc`): light cyan, exclusively for monospace identifiers (file paths, IDs, hashes, env-var names). Communicates "this is a literal value." Never for body text.
- **Borders**: `#26262f` default — barely-there. `#3a3a47` for tables and emphasized dividers.

## Typography

- **Body**: IBM Plex Sans, 13px base, 1.5 line-height. Smaller than other flavors deliberately — density is the point.
- **Headings**: IBM Plex Sans 500 weight. Reserved; never above 24px in normal UI contexts.
- **Mono**: IBM Plex Mono for ALL identifiers, file paths, IDs, hashes, env-vars, code snippets, monetary values, durations, percentages. Same size as body (13px); same line-height.
- **Numerals**: always tabular. Right-align numeric columns by default.
- **Capitalization**: section headers may use small-caps letterspacing (UPPERCASE 11px, +0.05em letter-spacing). Buttons stay sentence case.

## Components

- **Buttons**: 4px radius. Primary fills electric blue. Secondary is ghost — transparent fill, 1px `border-strong`, on-surface text. Padding 6-12. Always include keyboard hint when an action has a shortcut (`Save · ⌘S`). Never gradient; never shadow.
- **Inputs**: 1px `border-strong`, surface-2 background, 4px radius. Focus uses primary-color 2px ring as outline. Mono font when the input is for an identifier.
- **Cards**: surface, 6px radius, 1px border (`#26262f`). No shadow ever. Hover may shift to surface-2.
- **Tabs**: text + 2px primary underline on active. Inactive in on-surface-2. Always show counts adjacent: `Tab name (24)`.
- **Tables**: hairline horizontal rules in `border-strong`, no vertical rules, no zebra-striping. Headers small-caps + on-surface-2. Identifier columns in mono + identifier color.
- **Status badges**: 2px radius, 11px text, 4-8 padding. Success/warning/danger use the semantic color at 18% alpha background + full color text + 1px matching border.
- **Page header**: small-caps eyebrow label, 24px sans title, action cluster right. No tagline; if a tagline exists it lives in on-surface-2 below.

## Do's and Don'ts

- **Do** use monospace for ANY value the user might copy, type, or refer back to. Identifier-styled mono communicates "this is exact."
- **Do** keep one primary CTA per view. Electric blue is loud against the dark canvas.
- **Do** show keyboard shortcuts inline for actions that have them. This flavor's users expect keyboards.
- **Do** maintain WCAG AA contrast: 4.5:1 body, 3:1 large. The dark canvas makes this easier; check on-surface-3.
- **Don't** introduce drop shadows or gradients. The surface model is **flat with borders.**
- **Don't** use radii larger than 6px. Pillier reads as consumer; we're a tool.
- **Don't** use the amber accent as a button color. It's a state indicator.
- **Don't** pair primary blue and accent amber in the same component — they're different registers.
- **Don't** mix multiple type sizes within a card. Two sizes max per surface; rely on weight for hierarchy.
- **Don't** use pure white text. `#e8e9ee` is the brightest the eye should encounter.
