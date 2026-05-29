---
name: airbnb
identity: marketplace, travel, consumer trust, photography-forward catalog
teaches: Warmth through softness and whitespace; let photography be the hero and let the UI step back.
colors:
  primary: "#FF5A5F"
  primary-hover: "#E5484D"
  primary-subtle: "#FFF1F1"
  accent: "#00A699"
  canvas: "#FFFFFF"
  surface: "#FFFFFF"
  surface-2: "#F7F7F7"
  surface-3: "#EBEBEB"
  on-surface: "#222222"
  on-surface-2: "#717171"
  on-surface-3: "#B0B0B0"
  border: "#DDDDDD"
  border-strong: "#B0B0B0"
  success: "#008A05"
  warning: "#FC642D"
  danger: "#C13515"
typography:
  font-sans: '"Plus Jakarta Sans", "Inter", -apple-system, BlinkMacSystemFont, sans-serif'
  font-mono: '"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace'
  body-size: 16px
  body-line-height: 1.5
  body-weight: 400
  heading-weight: 600
  numerals: lining-nums
radii:
  sm: 8px
  md: 12px
  lg: 16px
  full: 9999px
spacing:
  base: 4px
  scale: [0, 4, 8, 12, 16, 24, 32, 48, 64, 96]
surface-treatment: rounded-soft-shadow
shadows:
  rest: "0 0 0 1px rgba(0,0,0,0.02), 0 2px 6px rgba(0,0,0,0.04)"
  hover: "0 0 0 1px rgba(0,0,0,0.02), 0 4px 8px rgba(0,0,0,0.10)"
  modal: "0 8px 28px rgba(0,0,0,0.28)"
---

# airbnb

## Overview

Marketplace, travel, consumer trust, photography-forward catalog. The page is white and quiet; the product is the photo. UI chrome is rounded, low-contrast, and gets out of the way so listings, profiles, and imagery carry the surface. This is the *let the inventory breathe* school — a single coral CTA, a single shadow tier, and generous whitespace do the work that gradients and color do in lesser flavors.

Font substitution: **Plus Jakarta Sans substitutes for the proprietary Cereal typeface** — closest free geometric-humanist match with warm corner softening and generous x-height. DM Sans is an acceptable fallback.

## Colors

- **Canvas** (`#FFFFFF`): pure white page. The marketplace assumes warmth comes from photography, not from a tinted background. Don't introduce a cream cast.
- **Surface** (`#FFFFFF`): cards, modals, listing tiles. Same value as canvas — separation comes from the shadow and the radius, not a fill contrast.
- **Surface-2** (`#F7F7F7`): neutral warm gray. Section dividers, sidebar fills, skeleton loaders. Never for cards.
- **Surface-3** (`#EBEBEB`): hovered rows, selected filter chips, image placeholder fallback.
- **On-surface** (`#222222`): primary text. Near-black, warm-neutral. Never pure black; never pure white.
- **On-surface-2** (`#717171`): secondary text — prices, ratings, dates, listing metadata. Reads as "supporting fact."
- **On-surface-3** (`#B0B0B0`): tertiary — disabled labels, placeholder text. Below this is illegible on white.
- **Primary** (`#FF5A5F`): coral. The brand. Use for the *one* primary action per view — search, reserve, continue. Never as a background block; coral is too loud to sit under text.
- **Primary-hover** (`#E5484D`): pressed/hover for coral fills. ~6% darker.
- **Primary-subtle** (`#FFF1F1`): coral hover backdrop on ghost buttons, subtle selected-tile tint. Not a chip fill.
- **Accent** (`#00A699`): teal. Reserved for secondary affordances — trust badges, profile verification, in-progress markers. Never a CTA color; pairs with coral as warm/cool counterpoint.
- **Borders**: `#DDDDDD` is the universal hairline — inputs, dividers, table rules. `#B0B0B0` only for focused or emphasized state.
- **Success** (`#008A05`): availability confirmed, payment cleared. Distinct from teal accent — accent is brand, success is system.
- **Warning** (`#FC642D`): the Arches orange. Soft-launch / promotional / "almost gone" tone. Never a danger replacement.
- **Danger** (`#C13515`): destructive — cancellations, errors. Deeper red than coral on purpose; the warm hues must not collide.

## Typography

- **Body**: Plus Jakarta Sans, 16px base, 1.5 line-height. Larger than utility flavors — the marketplace reads as editorial.
- **Body weight**: 400 baseline. Plus Jakarta Sans has enough optical weight at 400 that 500 reads as emphasis.
- **Headings**: Plus Jakarta Sans 600. Section titles 22px, page titles 26-32px. Headings stay restrained; the photography does the loud talking.
- **Mono**: JetBrains Mono only for code samples, booking confirmation numbers, and API-adjacent UIs. Not for prices — prices are sans.
- **Numerals**: lining (proportional) by default. Tabular only inside multi-row data tables (admin/host dashboards).
- **Sentence case** for all UI — buttons, labels, navigation, headings. Never UPPERCASE; never letterspaced eyebrows.

## Components

- **Buttons**: 8px radius. Primary fills coral with white text, 14-24 padding, 600 weight. Secondary is white surface with 1px `border` + on-surface text. Tertiary is text-only with underline on hover. No gradient; no glow. Hover lifts to `hover` shadow on primary, swaps to surface-2 on secondary.
- **Inputs**: 1px `border`, white surface, 8px radius, 14-16 padding. The hero search bar is a `full`-radius pill divided by vertical hairlines into segments — that pattern is reserved for primary search, not generic forms. Focus uses a 1px `border-strong` ring with no glow.
- **Cards (listing-card idiom)**: white surface, 12px radius, NO border, `rest` shadow always-on. Photo at the top with 12px radius clipping the corners to match the card. Heart icon top-right, optional trust-badge pill top-left (`full` radius, white surface, 11px 600). 4-5 lines of meta beneath the photo in 16px on-surface + 14px on-surface-2 + price-with-weight-emphasis. Hover swaps to `hover` shadow. **Cards visibly float, but only one elevation tier exists** — there is no "more elevated" card.
- **Modals**: 16px radius, `modal` shadow, no border. Backdrop is `rgba(0,0,0,0.45)`, no blur. Close button is text "Close" top-left or an X top-right — never both.
- **Tabs**: text + 2px on-surface underline on active; inactive in on-surface-2. Underline sits 8px below the label baseline. Pill-style tabs (`full` radius, primary-subtle fill, on-surface text) for filter chips only.
- **Tables**: rare in this flavor — when used, hairline horizontal rules in `border`, no vertical rules, no zebra. Headers in on-surface-2, sentence case, 14px. Numeric columns tabular-nums and right-aligned.
- **Badges**: `full` radius pills, 11-12px text, 600 weight, 4-10 padding. White-fill-with-shadow when sitting on a photo; on-surface-2 1px border when sitting on white. Coral fill only for "new" or "rare" markers, never for status.
- **Page header**: large sentence-case title (26-32px, 600), one-line on-surface-2 subtitle if needed, action cluster right-aligned. No eyebrow label.

## Do's and Don'ts

- **Do** treat photography as a UI primitive. Reserve the largest cards and most of the visual budget for images; let the chrome shrink around them.
- **Do** use the single shadow tier consistently — `rest` everywhere on cards, `hover` on interaction. Don't invent a third tier.
- **Do** keep coral scarce. One primary CTA per view; the rest is white, gray, and photography. Coral loses meaning if it tiles.
- **Do** use sentence case everywhere. The marketplace tone is conversational; UPPERCASE shouts and breaks register.
- **Do** maintain WCAG AA contrast: 4.5:1 body, 3:1 large. On-surface-3 (`#B0B0B0`) only meets large-text contrast — never use it for body copy.
- **Do** pair coral and teal intentionally when you need two semantic registers (brand action / trust marker). They are warm/cool counterparts, not interchangeable.
- **Don't** introduce gradients, glows, or multi-shadow layered "Material" elevation. One shadow tier; flat fills.
- **Don't** use radii under 8px. Sharp corners read as utility software; the marketplace must feel hospitable.
- **Don't** tint the canvas. Cream and warm-white backgrounds belong to other flavors — here the brand warmth comes from photography on top of white, not warmth underneath.
- **Don't** use coral as a background block under body text. Coral is for the click target, not the container.
- **Don't** mix the orange warning and coral primary in the same view if avoidable — the warm hues collide. Quarantine warning to inline alerts.
- **Don't** style prices in mono or color them. Price emphasis comes from weight (600) in sans, in on-surface — not from a treatment.
