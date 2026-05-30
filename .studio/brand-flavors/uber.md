---
name: uber
identity: mobility platform, operational console, marketplace surface
teaches: Clarity through contrast; function before feeling.
colors:
  primary: "#000000"
  primary-hover: "#1a1a1a"
  primary-subtle: "#F6F6F6"
  accent: "#06C167"
  canvas: "#FFFFFF"
  surface: "#FFFFFF"
  surface-2: "#F6F6F6"
  surface-3: "#EEEEEE"
  on-surface: "#000000"
  on-surface-2: "#545454"
  on-surface-3: "#AFAFAF"
  border: "#EEEEEE"
  border-strong: "#CBCBCB"
  success: "#06C167"
  warning: "#FFC043"
  danger: "#E11900"
typography:
  font-sans: '"Inter Display", "Inter", system-ui, -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif'
  font-mono: '"JetBrains Mono", ui-monospace, "SF Mono", Menlo, monospace'
  body-size: 16px
  body-line-height: 1.5
  body-weight: 400
  heading-weight: 700
  numerals: tabular-nums
radii:
  sm: 4px
  md: 8px
  lg: 8px   # intentionally equal to md — this flavor doesn't soften at larger scales
  full: 9999px
spacing:
  base: 4px
  scale: [0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64]
surface-treatment: flat-bordered
shadows: none
---

# uber

## Overview

Mobility platform, operational console, marketplace surface. The lineage is utilitarian: pure black on white, heavy bold display type, large primary actions, and almost no decoration. Hierarchy comes from type weight and scale, not color. Color is reserved for semantics — green for confirmed/success, red for destructive, amber for caution — never for decoration. This is the *operations-grade* school: the interface looks calm because every choice carries weight, and the user is presumed to be in motion.

Font substitutions: **Inter Display substitutes for Uber Move; Inter substitutes for Uber Move Text; JetBrains Mono substitutes for Uber Move Mono.** The proprietary originals are not redistributable; the substitutes preserve the heavy display register and the utilitarian body register.

## Colors

- **Canvas** (`#FFFFFF`): pure white. The page. **Not** for accent surfaces.
- **Surface** (`#FFFFFF`): cards, sheets, primary content surfaces. Distinguished from canvas by border, not fill.
- **Surface-2** (`#F6F6F6`): nested surfaces, table headers, input backgrounds, subtle zones. **Not** for cards on canvas (no contrast).
- **Surface-3** (`#EEEEEE`): hover and selected row backgrounds. **Not** a resting state.
- **On-surface** (`#000000`): primary text and primary fills. Pure black is the brand. **Not** decorative.
- **On-surface-2** (`#545454`): secondary text — captions, metadata, labels. **Not** for primary CTAs or headings.
- **On-surface-3** (`#AFAFAF`): tertiary text — placeholders, disabled states, timestamps. **Not** for body content.
- **Primary** (`#000000`): primary CTA fill, page title color. **Not** for borders or backgrounds at scale.
- **Primary-hover** (`#1a1a1a`): primary button hover. **Not** visible at rest.
- **Primary-subtle** (`#F6F6F6`): pressed-state background for ghost buttons, selected list rows. **Not** for badges.
- **Accent** (`#06C167`): semantic green — success confirmations, "on trip" / "arrived" states, marketplace positive signal. **Not** for primary CTAs.
- **Success** (`#06C167`): same green; use for success badges, confirmation toasts, completed states.
- **Warning** (`#FFC043`): amber — schedule conflicts, surge indicators, cautionary states. **Not** for buttons; **not** as a body text color.
- **Danger** (`#E11900`): red — destructive actions, cancellation, errors. **Not** decorative; reserved for irreversible or error states.
- **Borders**: `#EEEEEE` for hairlines and dividers; `#CBCBCB` for input borders, table separators, and emphasized rules.

## Typography

- **Display**: Inter Display (substitutes for Uber Move). Used for headlines and page titles. Heavy: 700.
- **Body**: Inter (substitutes for Uber Move Text). 16px base, 1.5 line-height, 400 weight.
- **Mono**: JetBrains Mono (substitutes for Uber Move Mono if used at all). Reserved for codes, identifiers, fare receipts, license/vehicle plates.
- **Hierarchy is weight-driven**: heavy display headlines over regular body create the contrast — never undersized headings styled as bold. Title sizes step 32 / 28 / 24 / 20 / 18 / 16; titles always 700.
- **Numerals**: tabular by default — fares, ETAs, dates, counts, durations all align in columns. Switch to lining only inside marketing-style hero blocks.
- **Capitalization**: sentence case for headings, body, buttons, and badges. No ALL-CAPS labels; small-caps is foreign to this lineage.

## Components

- **Buttons**: 8px radius (4px for mini/inline). Primary is solid black fill, white text, 700 weight, generous touch target (min 48px height on mobile, 40px on desktop). Often full-width on mobile, prominent on web. Secondary is white surface, 1px `border-strong` border, black text. Tertiary is text-only black with `primary-subtle` hover background. No gradient; no shadow at rest.
- **Inputs**: 8px radius, 1px `border-strong`, surface-2 fill at rest, white on focus. Focus state: 2px black border, no glow. Labels sit above the input in 14px on-surface-2; placeholders in on-surface-3. Min height 48px — generous touch target.
- **Cards**: white surface, 1px `border` hairline, **0px radius** (Base Web's surface radius is sharp). No shadow at rest. Hover may shift fill to surface-2 with no other change. Use cards to group, not to decorate.
- **Modals / Sheets**: full-bleed bottom sheets on mobile, centered on desktop. Sharp corners (0px) for full-screen / bottom sheets; 8px for centered desktop dialogs. One subtle shadow allowed *only* for floating bottom sheets: `0px -4px 16px rgba(0,0,0,0.12)`. Cards stay flat.
- **Tabs**: text + 2px black underline on active. Inactive tab text uses on-surface-2. Counts adjacent in parentheses: `Trips (24)`.
- **Tables**: hairline horizontal rules in `border-strong`, no vertical rules, no zebra. Header row in surface-2 with 700 weight on-surface labels. Identifier columns (trip IDs, plates) in mono. Right-align numeric columns.
- **Badges**: 4px radius, 12px text, 4-8 padding. Semantic states render as colored text + matching 1px border + ~10% alpha fill (`success` green, `warning` amber, `danger` red). Neutral badges use on-surface-2 text + `border` outline + transparent fill.
- **Page header**: 32px title (700, on-surface), optional 16px subtitle in on-surface-2 directly below. Action cluster right-aligned with one primary button. No eyebrow label, no tagline, no decorative rule.

## Do's and Don'ts

- **Do** make the primary CTA loud and large. Black on white at scale is the signature — undersized buttons read as unfinished.
- **Do** drive hierarchy with weight contrast: 700 display over 400 body. Reach for size only after weight is exhausted.
- **Do** use sentence case everywhere — buttons, headings, badges, nav. The lineage is conversational, not shouty.
- **Do** keep semantic color semantic: green means confirmed, red means destructive, amber means caution. One job each.
- **Do** keep touch targets generous (≥44px). The lineage assumes a user in motion on a phone.
- **Do** use tabular numerals for any fare, ETA, count, or duration. They scan in columns.
- **Don't** introduce drop shadows on cards or buttons. Surfaces separate via border. One shadow exception: floating bottom sheet.
- **Don't** use color decoratively. If a color isn't carrying meaning, remove it.
- **Don't** mix font weights mid-paragraph or stack 3+ sizes in one card. Two sizes max per surface; weight does the lifting.
- **Don't** use radii larger than 8px. Pill shapes are reserved for `full` (avatars, status dots, segmented controls).
- **Don't** use ALL-CAPS letterspaced labels. That belongs to other lineages; here it reads foreign.
- **Don't** soften pure black with a tint. `#000000` is the brand — `#222` reads as a mistake.
- **Don't** layer the accent green and danger red in the same view unless one is a state and the other an action. They compete.
