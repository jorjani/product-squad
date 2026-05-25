---
name: editorial
identity: thoughtful, considered, content-first
colors:
  primary: "#3f6b4e"
  primary-hover: "#335a3f"
  primary-subtle: "#e6efe9"
  accent: "#c9742d"
  surface: "#ffffff"
  surface-2: "#f8f6f2"
  canvas: "#f5f2ec"
  on-surface: "#1c1c24"
  on-surface-2: "#525561"
  on-surface-3: "#9098a2"
  border: "#e4dfd6"
  border-strong: "#cfc8b9"
  success: "#0f8a5e"
  warning: "#c5862b"
  danger: "#b8362a"
typography:
  font-sans: 'Inter, "Inter Tight", -apple-system, BlinkMacSystemFont, sans-serif'
  font-mono: '"JetBrains Mono", ui-monospace, SFMono-Regular, monospace'
  body-size: 14px
  body-line-height: 1.6
  body-weight: 400
  heading-weight: 600
  numerals: tabular-nums
radii:
  sm: 6px
  md: 8px
  lg: 12px
  full: 9999px
spacing:
  base: 4px
  scale: [0, 4, 8, 12, 16, 20, 24, 32, 40, 56, 72]
surface-treatment: flat-bordered
shadows: none
---

# editorial

## Overview

Calm, focused, content-first. Long-form text deserves room to breathe. The interface gets out of the way; whatever the user is reading or composing should always be the visual gravity. Color is rationed; whitespace is generous; chrome is minimal. This is the *considered product* school — it should feel like a thing made on purpose, not a thing assembled from a kit.

## Colors

- **Primary** (`#3f6b4e`): a muted, slightly desaturated green. CTAs, active tabs, key affordances. Hover darkens to `#335a3f`. Use sparingly; **one primary action per view.**
- **Primary subtle** (`#e6efe9`): tinted backgrounds for selected rows, gentle emphasis, badges. Never for text.
- **Accent** (`#c9742d`): warm clay. Use for *secondary* emphasis only — annotation callouts, "new" indicators, the occasional pull-quote rule. Never for buttons; never alongside primary in the same affordance.
- **Canvas** (`#f5f2ec`): warm paper. The page background. Distinct from card surface.
- **Surface** (`#ffffff`): cards, modals, panels that elevate above canvas — by *border*, not shadow.
- **Surface-2** (`#f8f6f2`): subtle nested surface; sidebars, footers.
- **On-surface** (`#1c1c24`): primary text. Near-black with a slight cool cast. **Never pure black.**
- **Borders**: `#e4dfd6` default; `#cfc8b9` for emphasized dividers (table-of-contents rules, section separators).

## Typography

- **Body**: Inter, 14px base, 1.6 line-height. Inter Tight at heading sizes when available.
- **Headings**: Inter at 600/700 weight. No display face; hierarchy comes from size + weight + space, not contrasting fonts.
- **Numerals**: tabular wherever data aligns in columns. `font-variant-numeric: tabular-nums`.
- **Mono**: JetBrains Mono for code, identifiers, file paths, monetary amounts. Slightly smaller than body (13px when body is 14px).

## Components

- **Buttons**: 8px radius. Primary fills with on-primary text. Secondary is ghost (transparent fill, 1px border, on-surface text). Tertiary is text-only with primary color. Padding 8-16. Never gradient; never shadow.
- **Inputs**: 1px border, white surface, 8px radius. Focus ring uses primary at 30% alpha as outline (not a glow shadow).
- **Cards**: white surface, 12px radius, 1px border (`#e4dfd6`), no shadow at rest. Hover may add a 0.04-alpha shadow if interactive, never otherwise.
- **Tabs**: text + 2px underline accent in primary on active. Inactive uses on-surface-2.
- **Tables**: hairline horizontal rules in `border-strong`, no vertical rules, no zebra-striping. Headers use on-surface-2 + small uppercase letterspaced label.
- **Page header**: title 24px, optional subtitle in on-surface-2, action cluster on the right. Generous bottom margin (32-40).

## Do's and Don'ts

- **Do** keep one primary CTA per view. The green stops working when it competes with itself.
- **Do** rely on whitespace and weight for hierarchy before reaching for color.
- **Do** maintain WCAG AA contrast: 4.5:1 body text on canvas, 3:1 large text and UI components.
- **Don't** use the primary green for large area fills or page backgrounds. It is an accent, not a wash.
- **Don't** mix the accent clay (`#c9742d`) with primary green inside the same affordance. They are distinct registers.
- **Don't** introduce drop shadows or gradient effects. The surface model is **flat with borders**.
- **Don't** capitalize labels or buttons. Lowercase / sentence case throughout.
- **Don't** use radii larger than 12px. Anything pillier reads as consumer-app.
