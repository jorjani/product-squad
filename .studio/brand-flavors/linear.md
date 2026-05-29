---
name: linear
identity: agent OS, issue tracker, keyboard-native dev tool
teaches: density without clutter, monospace as a trust signal, and the operator-respect register that comes from showing keyboard hints inline
colors:
  primary: "#5e6ad2"
  primary-hover: "#6e7ae0"
  primary-subtle: "rgba(94,106,210,0.14)"
  accent: "#a78bfa"
  canvas: "#08090a"
  surface: "#101113"
  surface-2: "#161719"
  surface-3: "#1f2023"
  on-surface: "#f7f8f8"
  on-surface-2: "#8a8f98"
  on-surface-3: "#62666d"
  border: "#23252a"
  border-strong: "#34373c"
  success: "#4cb782"
  warning: "#f2994a"
  danger: "#eb5757"
  identifier: "#7dd3fc"
typography:
  font-sans: 'Inter, "Inter Display", -apple-system, BlinkMacSystemFont, sans-serif'
  font-mono: '"JetBrains Mono", "IBM Plex Mono", ui-monospace, "SF Mono", Menlo, monospace'
  body-size: 13px
  body-line-height: 1.5
  body-weight: 400
  heading-weight: 510
  numerals: tabular-nums
radii:
  sm: 4px
  md: 6px
  lg: 8px
  full: 9999px
spacing:
  base: 4px
  scale: [0, 2, 4, 6, 8, 12, 16, 20, 24, 32, 40]
surface-treatment: flat-bordered-dark
shadows: none
---

# linear

## Overview

Agent OS, issue tracker, keyboard-native dev tool. The user lives on the keyboard and resents waste. Dark canvas with a faint violet cast, hairline borders instead of dividers, monospace for anything copyable. This is the *we measured every pixel* school — surfaces are flat, type hierarchy is weight not size, and every primary action shows its shortcut. Looks like something an engineer would choose, not something procurement bought.

## Colors

- **Canvas** (`#08090a`): near-black with a slight cool cast. The app shell. **Never pure black** — pure black flattens depth and reads as cheap.
- **Surface** (`#101113`): the main content pane. Distinct from canvas by ~3% luminance.
- **Surface-2** (`#161719`): sidebars, modal bodies, table headers, sticky toolbars.
- **Surface-3** (`#1f2023`): row-hover, command-menu active item, selected list cell.
- **On-surface** (`#f7f8f8`): primary text. **Never pure white** — pure white burns at this contrast.
- **On-surface-2** (`#8a8f98`): metadata, labels, captions, inactive tab text.
- **On-surface-3** (`#62666d`): placeholders, disabled, the `kbd` outline color.
- **Primary** (`#5e6ad2`): signature indigo-violet. CTAs, focus rings, active nav item, link color. **One primary action per view.** This color carries the brand; don't dilute it.
- **Primary-subtle** (`rgba(94,106,210,0.14)`): selected-row tint, ghost-button hover, active-tab pill background.
- **Accent** (`#a78bfa`): lighter violet, used for "in-progress" markers, AI/agent affordances, secondary highlights. Never for buttons.
- **Identifier** (`#7dd3fc`): light cyan, exclusively for monospace literals — issue IDs (`ENG-1421`), file paths, env-var names, hashes. Communicates "this is exact." Never for body text.
- **Borders**: `#23252a` for default hairlines. `#34373c` for tables and emphasized dividers. Borders are the only separators — no shadows, no fills.
- **Semantic**: `success` muted green, `warning` amber, `danger` desaturated red. All used as outlines + 14% alpha fills, never as button backgrounds.

## Typography

- **Body**: Inter, 13px base, 1.5 line-height. Density is the point — readers are scanning a queue, not reading prose.
- **Headings**: Inter Display at 510 weight (close to 500 but optically heavier in Inter). Reserved; never above 22px in chrome, 28px in marketing.
- **Mono**: JetBrains Mono for ALL identifiers, IDs, hashes, file paths, env-vars, code snippets, durations, percentages. Same size as body (13px); same line-height.
- **Numerals**: tabular by default. Right-align numeric columns.
- **Capitalization**: section eyebrows may use small-caps (11px UPPERCASE, +0.04em letter-spacing). Buttons and menu items stay sentence case. Status badges may use lowercase.

## Components

- **Buttons**: 6px radius. Primary fills `#5e6ad2` with white text; hover lightens to `#6e7ae0`. Secondary is ghost — transparent fill, 1px `border-strong`, on-surface text, hover fills surface-2. Tertiary is text-only in on-surface-2. Padding 4-10 vertical / 8-14 horizontal. **Always include the keyboard shortcut inline** when an action has one (`Create issue ⌘N`, `Save ⌘S`). The shortcut sits in `on-surface-3` with a hairline-bordered `kbd` glyph. Never gradient. Never shadow.
- **Inputs**: 1px `border` default, 6px radius, surface-2 background. Focus replaces the border with primary + a 1px primary-subtle outer ring (no glow). Mono font when the input is for an identifier or URL. Placeholders sit in `on-surface-3`.
- **Cards**: surface, 8px radius, 1px `border`. **No shadow ever.** Hover shifts background to surface-2 — not a transform, not a glow. The whole hover state is a 1-frame background swap.
- **Modals**: 8px radius, surface-2 fill, 1px `border-strong`. Backdrop is `rgba(8,9,10,0.6)`. No backdrop blur — clarity over effect. Close affordance is `Esc` shown bottom-right.
- **Tabs**: text + 2px primary underline on active. Inactive in on-surface-2. Counts adjacent in `on-surface-3`: `Active 12  Backlog 47`. Optionally a pill variant for command-menu filters: full radius, primary-subtle fill on active.
- **Tables**: hairline horizontal rules in `border` (quieter than industrial). No vertical rules. No zebra. Row height 32px. Headers in small-caps, on-surface-2, 11px. Identifier column in mono + identifier color. Hover fills surface-2 across the full row.
- **Badges**: 4px radius, 11px text, 2-6 padding. Status uses semantic color at 14% alpha background + full color text + 1px matching border. Identifier badges use mono + identifier color, no fill.
- **Page header**: small-caps eyebrow (`PROJECT`, `INBOX`), 20px title in Inter Display 510, breadcrumb left, action cluster right. Primary action in the cluster carries its keyboard hint. No tagline.
- **Command menu (signature)**: centered modal, 8px radius, surface-2, 1px `border-strong`. Input row top, results below, each row showing icon + label + shortcut `kbd`. Active row fills surface-3. This pattern is the flavor's emblem — if a build needs a "what can I do here" surface, default to the command-menu shape.
- **`kbd` glyph**: 4px radius, 1px `border` outline, surface-2 fill, on-surface-2 text, 11px mono, 2-4 padding. Used everywhere shortcuts appear inline.

## Do's and Don'ts

- **Do** show keyboard shortcuts inline on every action that has one. This flavor's users live on keyboards; hiding the shortcut breaks the contract.
- **Do** use monospace + identifier color for anything copyable — IDs, paths, env vars, hashes. The cyan says "this is the literal value."
- **Do** keep one primary indigo action per view. The violet is loud against the dark canvas; two primaries cancel each other.
- **Do** build a command-menu (`⌘K`) for any surface with more than five distinct actions. It's the canonical "everything" interface.
- **Do** use weight, not size, for type hierarchy. 13/510 vs 13/400 reads cleaner than 16 vs 13.
- **Do** maintain WCAG AA: 4.5:1 body, 3:1 large. Dark canvas helps; check `on-surface-3` against surface-2.
- **Don't** introduce drop shadows, glows, or gradients. The surface model is **flat with hairline borders.** A shadow on a card here reads as a different product entirely.
- **Don't** use radii larger than 8px. Pillier shapes read as consumer; this flavor is a tool.
- **Don't** use the accent violet as a button color. Primary is the only button violet.
- **Don't** pair primary `#5e6ad2` with the `success`/`warning`/`danger` colors at full saturation in the same component. Semantic colors live at 14% alpha or as 1px outlines.
- **Don't** use pure white or pure black anywhere. `#f7f8f8` is the brightest; `#08090a` is the darkest.
- **Don't** mix more than two type sizes per surface. Hierarchy via weight; size shifts are a last resort.
- **Don't** zebra-stripe tables or add vertical rules. Hairline horizontals only; the eye is supposed to glide.
