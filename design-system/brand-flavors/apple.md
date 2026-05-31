---
name: apple
identity: premium consumer marketing, hero product pages, prestige register
teaches: Restraint as premium signal — whitespace, monochrome surfaces, and a single accent earn trust that ornament cannot.
colors:
  primary: "#0071E3"
  primary-hover: "#0077ED"
  primary-subtle: "rgba(0,113,227,0.08)"
  accent: "#0071E3"
  canvas: "#FFFFFF"
  surface: "#FFFFFF"
  surface-2: "#FBFBFD"
  surface-3: "#F5F5F7"
  on-surface: "#1D1D1F"
  on-surface-2: "#6E6E73"
  on-surface-3: "#86868B"
  border: "#D2D2D7"
  border-strong: "#86868B"
  success: "#29A745"
  warning: "#F56300"
  danger: "#E30000"
typography:
  font-sans: '"Inter Display", "Inter", -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif'
  font-mono: '"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace'
  body-size: 17px
  body-line-height: 1.47059
  body-weight: 400
  heading-weight: 600
  numerals: lining-nums
radii:
  sm: 8px
  md: 12px
  lg: 18px
  full: 9999px
spacing:
  base: 4px
  scale: [0, 4, 8, 12, 16, 24, 32, 48, 72, 96, 128]
surface-treatment: flat-with-blur-overlays
shadows:
  rest: none
  floating: "0 1px 0 rgba(0,0,0,0.04)"
  modal: "0 10px 40px -12px rgba(0,0,0,0.12)"
---

# apple

## Overview

Premium consumer marketing, hero product pages, prestige register. Near-monochrome surfaces, generous whitespace, large display type, a single saturated accent. This is the *restraint signals quality* school — the page must feel like the product photography could survive on it without competition. No decoration, no gradients on chrome, no shadows on resting elements. Whitespace is the design.

Font substitutions: **Inter Display substitutes for SF Pro Display; Inter substitutes for SF Pro Text; JetBrains Mono substitutes for SF Mono.** The proprietary originals are not redistributable; the substitutes preserve the optical register (neutral grotesque, tight display tracking, generous text x-height).

## Colors

- **Canvas** (`#FFFFFF`): pure white page background. The default. Sections may invert to pure black (`#000000`) for product hero blocks — that inversion is the only chromatic event allowed.
- **Surface** (`#FFFFFF`): cards, content panels. Same as canvas — surfaces are defined by spacing and hairlines, not fills.
- **Surface-2** (`#FBFBFD`): faintly cooler off-white for alternating sections, subtle zoning. Barely perceptible — that is the point.
- **Surface-3** (`#F5F5F7`): selected rows, quiet emphasis, segmented-control track. Never a card fill.
- **On-surface** (`#1D1D1F`): primary text. Near-black with a slight warm cast. **Never pure black for body copy.**
- **On-surface-2** (`#6E6E73`): secondary text — captions, metadata, legal small print, eyebrows.
- **On-surface-3** (`#86868B`): tertiary text — disabled, placeholder, footnote.
- **Primary** (`#0071E3`): saturated product blue. Links, primary CTAs, focus rings. **The only color event on a typical page.** One per view, used confidently.
- **Primary-hover** (`#0077ED`): one shade brighter on hover. Never a transform, never a shadow — the color shift is the entire affordance.
- **Accent** (`#0071E3`): intentionally identical to primary. This flavor has no second hue. If you need contrast, use weight and scale, not color.
- **Borders** (`#D2D2D7`): hairline dividers. 1px only; never thicker. `#86868B` for strong dividers in dense data contexts.
- **Semantic** (success `#29A745`, warning `#F56300`, danger `#E30000`): reserved for system feedback only. Never decorative.

## Typography

- **Body**: Inter, 17px base, 1.47 line-height, weight 400. The 17px floor is non-negotiable on marketing surfaces — smaller reads as utilitarian and breaks the register.
- **Display**: Inter Display, 56–96px for hero, weight 600. Tight tracking (`-0.025em` to `-0.04em` at display sizes). One hero per section, generous margins above and below.
- **Section headings**: Inter Display 600, 40–48px. Same tracking discipline.
- **Subheads**: Inter 400 or 500, 21–28px, on-surface-2.
- **Mono**: JetBrains Mono for code blocks and exact technical values only. 15px when body is 17px.
- **Numerals**: lining by default (marketing). Tabular only inside data tables and pricing comparisons.
- **Case**: sentence case everywhere. **Never UPPERCASE.** No letterspaced eyebrows.

## Components

- **Buttons**: `full` radius (pill) for primary marketing CTAs; `md` (12px) for utility buttons inside cards. Primary fills `#0071E3` with white text, weight 400, 17px. Secondary is text-link blue with no fill, no border — just the word and the chevron. Hover shifts color one step; **no shadow, no transform, no gradient.** Padding 12–28 horizontal.
- **Inputs**: 1px `border`, white surface, `md` radius. Focus ring is 4px `primary-subtle` halo + 1px `primary` border. Generous padding (12–16). Placeholder in on-surface-3.
- **Cards**: white surface, `lg` (18px) radius, 1px `border`. **No resting shadow.** Hover may shift the border to `border-strong` — that is the entire hover affordance.
- **Modals**: `lg` radius, `modal` shadow, no border. Backdrop uses backdrop-filter blur (`backdrop-filter: blur(20px) saturate(180%)`) over a semi-opaque white scrim.
- **Tabs**: segmented-control idiom — `surface-3` track, `full` radius, active pill is white with the `floating` shadow. Sentence case, 15–17px.
- **Tables**: hairline horizontal rules in `border`, no vertical rules, no zebra. Headers sentence case in on-surface-2, weight 600.
- **Badges**: `full` radius, 13px text, 4–10 padding. Semantic color at 10% alpha background + full color text. No border.
- **Page header / nav**: sticky, 48px tall, `backdrop-filter: blur(20px) saturate(180%)` over `rgba(255,255,255,0.72)`. This is the only place a blur overlay belongs.
- **Hero block**: 96–128px vertical padding top and bottom. Display heading, optional subhead in on-surface-2, optional pair of text-link CTAs. Edge-to-edge product photography below. Never a card, never a border.

## Do's and Don'ts

- **Do** treat whitespace as the primary design element. If a section feels too empty, it is probably correct. Double the vertical padding before adding ornament.
- **Do** keep the page near-monochrome. Color appears only on the single primary CTA and on product photography.
- **Do** use 17px body. Smaller breaks the prestige register and reads as a dashboard.
- **Do** use sentence case everywhere — headings, buttons, eyebrows, labels.
- **Do** let display type breathe with tight tracking and generous leading. Large type with default tracking reads as web-default, not premium.
- **Do** maintain WCAG AA contrast: `#1D1D1F` on white is 16.7:1; `#6E6E73` on white is 5.0:1 (passes body); `#86868B` on white is 3.5:1 (large text or non-essential only).
- **Don't** add drop shadows to resting elements. Cards do not float. Buttons do not float. Only modals and the floating nav have shadow.
- **Don't** introduce a second accent color. If two things need to stand apart, use weight, size, or spacing — never a new hue.
- **Don't** use UPPERCASE, letterspaced eyebrows, or all-caps labels. This flavor cannot shout.
- **Don't** compress vertical rhythm. Section padding of 72–128px is the floor, not the ceiling.
- **Don't** use gradients on chrome (buttons, cards, surfaces). Gradients belong to product photography only.
- **Don't** use pure black (`#000000`) for body text on white, or pure white (`#FFFFFF`) for body text on black hero inversions. `#1D1D1F` and `#F5F5F7` are the caps.
- **Don't** mix radii within a surface. Pill CTAs live in hero blocks; rounded-rectangle buttons live inside cards — don't combine them in one component.
