---
name: playful
identity: consumer SaaS, onboarding, friendly tool
colors:
  primary: "#ec5b4f"
  primary-hover: "#d44a3f"
  primary-subtle: "#fef0ee"
  accent: "#2dd4bf"
  accent-subtle: "#ecfdf7"
  canvas: "#fffaf6"
  surface: "#ffffff"
  surface-2: "#fff5ef"
  surface-3: "#ffe9dc"
  on-surface: "#2a1f1e"
  on-surface-2: "#6b5e5c"
  on-surface-3: "#a89993"
  border: "#f4e5dc"
  border-strong: "#e8d4c5"
  success: "#10b981"
  warning: "#f59e0b"
  danger: "#ef4444"
typography:
  font-sans: 'Manrope, "Nunito Sans", -apple-system, BlinkMacSystemFont, sans-serif'
  font-mono: '"DM Mono", ui-monospace, monospace'
  body-size: 15px
  body-line-height: 1.65
  body-weight: 500
  heading-weight: 700
  numerals: lining-nums
radii:
  sm: 10px
  md: 14px
  lg: 20px
  full: 9999px
spacing:
  base: 4px
  scale: [0, 4, 8, 12, 16, 20, 24, 32, 40, 56, 72]
surface-treatment: rounded-soft-shadow
shadows:
  rest: "0 1px 2px rgba(43, 31, 30, 0.04)"
  hover: "0 8px 24px -8px rgba(236, 91, 79, 0.18)"
  modal: "0 24px 48px -16px rgba(43, 31, 30, 0.18)"
---

# playful

## Overview

Consumer SaaS, onboarding moments, friendly tools that people choose to use. Warm, soft, approachable — the opposite of compliance software. Surfaces are rounded; shadows are subtle but real; the coral primary feels human rather than corporate. This is the *people are scared of software* school — make it look like a friend, not a system.

## Colors

- **Canvas** (`#fffaf6`): warm cream. The page background. Never pure white.
- **Surface** (`#ffffff`): cards, modals, content panels.
- **Surface-2** (`#fff5ef`): nested surfaces, soft section backgrounds.
- **Surface-3** (`#ffe9dc`): selected rows, gentle emphasis.
- **On-surface** (`#2a1f1e`): primary text. Warm near-black, never cool.
- **On-surface-2** (`#6b5e5c`): secondary text — descriptions, metadata.
- **On-surface-3** (`#a89993`): tertiary text — placeholders, disabled states.
- **Primary** (`#ec5b4f`): warm coral. CTAs, key affordances. **One primary action per view, but use it confidently — it's the warmth of the brand.**
- **Primary subtle** (`#fef0ee`): selected-row tint, button-hover backdrop.
- **Accent** (`#2dd4bf`): cool teal. Secondary affordances, "in progress" / "live" indicators, success-adjacent state. Pairs intentionally with coral as warm/cool counterpoint.
- **Borders**: `#f4e5dc` default, `#e8d4c5` for emphasis.

## Typography

- **Body**: Manrope, 15px base, 1.65 line-height. Slightly larger than other flavors — generous reading on warm canvas.
- **Body weight**: 500 baseline (not 400). The slightly heavier baseline reads as confident and warm.
- **Headings**: Manrope 700. Headings should feel *spoken*; avoid corporate sterility.
- **Mono**: DM Mono for code, identifiers, monetary values. Slightly smaller (14px when body is 15px).
- **Numerals**: lining (proportional), NOT tabular by default. Tabular only for data tables.
- **Sentence case** for all UI labels and buttons. Never UPPERCASE.

## Components

- **Buttons**: 14px radius (almost pill at small sizes, gently rounded at large). Primary fills coral with white text. Secondary is white surface with 1px border + coral text. Tertiary is text-only coral with underline on hover. Padding 12-20 — buttons feel substantial. Subtle hover shadow (`0 8px 24px -8px coral18`).
- **Inputs**: 1px border, white surface, 14px radius. Generous padding (12-16). Focus ring uses coral at 25% alpha + 1px coral border. Placeholder text in on-surface-3.
- **Cards**: white surface, 20px radius, 1px border + the `rest` shadow always-on. Hover adds the `hover` shadow. **Cards visibly float** — this is the one flavor where shadows are essential, not optional.
- **Modals**: 20px radius, full `modal` shadow, no border. Backdrop blur if available (`backdrop-filter: blur(8px) brightness(0.7)`).
- **Tabs**: pill-style — `full` radius, sentence-case text, active tab fills primary-subtle with coral text. Inactive tab is text-only in on-surface-2.
- **Tables**: less prominent — gentle horizontal rules in `border`, no vertical rules. Headers use sentence-case, on-surface-2, 13px.
- **Progress / status**: rounded bars (full radius), coral primary or teal accent fill. Animated when in-progress.
- **Empty states**: should include warm illustration or large emoji + sentence-case helper text in on-surface-2.

## Do's and Don'ts

- **Do** use generous padding and large radii — softness IS the brand. Compressed UIs read as anxious in this flavor.
- **Do** keep shadows subtle but always present on cards. Removing them collapses the friendliness.
- **Do** pair coral and teal intentionally as warm/cool counterpoint when you need two semantic states (active/in-progress, today/scheduled, you/others).
- **Do** use sentence case throughout. Headings, buttons, labels.
- **Do** maintain WCAG AA contrast: 4.5:1 body, 3:1 large. The warm canvas can reduce contrast on lighter text colors — test on-surface-3 carefully.
- **Don't** use radii smaller than 10px. Sharp corners read as cold; this flavor cannot be cold.
- **Don't** use the dense small-text (13px or below) typical of dashboards. 15px is the floor.
- **Don't** use UPPERCASE labels or letterspaced eyebrow text. Friendly tone is incompatible with shouting.
- **Don't** use cool/neutral grays for backgrounds — warm tints (`#fffaf6`, `#fff5ef`) carry the brand. Cool grays make the flavor look broken.
- **Don't** pair coral with red (`danger`) in the same view if avoidable — the warm hues fight. Keep destructive UI quarantined to confirmation modals.
