---
name: design.md
description: Flavor selector for product-squad visual ladder — points at one of the brand-flavors files
type: design-system
---

# Design

This file is the **flavor selector** for the visual ladder. The actual design tokens, type ramps, component opinions, and Do/Don't rules live in `.studio/brand-flavors/<name>.md`.

## Available flavors

The bundle ships four **brand-archetype** flavors. Each is a visual lineage — inspiration drawn from a recognizable product family, NOT an endorsement or impersonation. Substitute fonts where the original is proprietary; the tokens preserve the optical register.

| Flavor | Identity | Signature |
|---|---|---|
| [`linear`](brand-flavors/linear.md) | Agent OS, issue tracker, keyboard-native dev tool (default) | Dark canvas, indigo primary, Inter, hairline borders, monospace identifiers |
| [`apple`](brand-flavors/apple.md) | Premium consumer marketing, hero product pages | White canvas, near-monochrome, single product blue, large display type, generous whitespace |
| [`airbnb`](brand-flavors/airbnb.md) | Marketplace, photography-forward catalog | White canvas, coral primary, Plus Jakarta Sans, soft-shadow rounded cards |
| [`uber`](brand-flavors/uber.md) | Mobility platform, operational console | Pure black on white, heavy display type, sharp utility radii, semantic-only color |

See [`examples/flavor-comparison.html`](../examples/flavor-comparison.html) to view all four rendered side-by-side on the same UI.

## How to select

`draw` reads two environment variables: `FLAVOR` (aesthetic vocabulary) and `BRAND` (brand chrome placeholder used in titles, breadcrumbs, course codes, etc).

```bash
./draw "your idea"                                # FLAVOR=linear (default), BRAND=AcmeU 101 · ReviewLab
FLAVOR=apple ./draw "your idea"                   # switch flavor only
BRAND="YourProduct" ./draw "your idea"            # set brand chrome only
FLAVOR=airbnb BRAND="StayCo" ./draw "your idea"
```

Unknown flavor names fall back to `linear` with a warning. `BRAND` has no validation — whatever you provide gets pasted into chrome verbatim.

**Why `BRAND` exists:** without it, the model invents specific real-world identifiers from the idea text (e.g., `CSC301` for an EDU-themed idea). Operator-supplied brand strings stop the fabrication and let the demo feel like a real product context.

## Why flavors

Tokens alone (just a color palette and font names) produce vanilla output — the model reads neutral tokens and produces neutral-looking HTML. Each flavor pairs tokens with a **theory of taste** (Overview paragraph) and **negative constraints** (Do/Don't section). The negative constraints stop the model from silently defaulting to its training-data-popular patterns (Tailwind shadows, blue-600 CTAs, rounded-md cards).

Each flavor teaches a different aesthetic vocabulary. Switching flavors on the same wireframe is the fastest way to feel how design tokens shape output.

## Authoring your own flavor

Drop a new file at `.studio/brand-flavors/<your-flavor-name>.md` using the existing flavors as templates. Required structure:

1. **YAML frontmatter** with `name`, `identity` (one-line), `teaches` (one-sentence — what does the flavor teach a designer?), `colors`, `typography`, `radii`, `spacing`, `surface-treatment`, `shadows`.
2. **Overview paragraph** — the theory of the aesthetic. What does this flavor *teach*?
3. **Colors section** — every hex value annotated with what it's for and what it's NOT for.
4. **Typography section** — fonts, sizes, weights, numeral style, capitalization rules.
5. **Components section** — opinions on buttons, inputs, cards, tabs, tables, status badges. Specific.
6. **Do's and Don'ts** — at least 5 of each. Negative constraints carry as much weight as positive ones.

The Do/Don't section is the differentiator. Tokens are necessary but not sufficient.

## Replacing a flavor for your own project

When you fork this bundle for a real product, replace one flavor with your brand:

```bash
# Option 1: overwrite the file
cp my-brand-tokens.md .studio/brand-flavors/linear.md

# Option 2: add your brand as a new flavor and set it as default
echo 'export FLAVOR=mybrand' >> ~/.zshrc
```
