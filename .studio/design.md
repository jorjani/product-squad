---
name: design.md
description: Flavor selector for product-squad visual ladder — points at one of the brand-flavors files
type: design-system
---

# Design

This file is the **flavor selector** for the visual ladder. The actual design tokens, type ramps, component opinions, and Do/Don't rules live in `.studio/brand-flavors/<name>.md`.

## Available flavors

| Flavor | Identity | Signature |
|---|---|---|
| [`editorial`](brand-flavors/editorial.md) | Thoughtful, considered, content-first | Warm canvas, muted green, Inter, flat surfaces |
| [`industrial`](brand-flavors/industrial.md) | Dev tool, ops dashboard, agent OS | Dark canvas, electric blue, IBM Plex Sans + Mono, sharp 4px radii |
| [`playful`](brand-flavors/playful.md) | Consumer SaaS, onboarding, friendly tool | Warm cream canvas, coral primary, Manrope, soft shadows, 14-20px radii |
| [`brutalist`](brand-flavors/brutalist.md) | Indie hacker, research tool, anti-design | Stark white, JetBrains Mono everywhere, 0 radius, 2px black borders, neon green accent |

## How to select

`bin/visual` reads the `FLAVOR` environment variable. Default is `editorial`.

```bash
./bin/visual "your idea"                       # uses editorial (default)
FLAVOR=industrial ./bin/visual "your idea"     # uses industrial
FLAVOR=playful    ./bin/visual "your idea"     # uses playful
FLAVOR=brutalist  ./bin/visual "your idea"     # uses brutalist
```

Unknown flavor names fall back to `editorial` with a warning.

## Why flavors

Tokens alone (just a color palette and font names) produce vanilla output — the model reads neutral tokens and produces neutral-looking HTML. Each flavor pairs tokens with a **theory of taste** (Overview paragraph) and **negative constraints** (Do/Don't section). The negative constraints stop the model from silently defaulting to its training-data-popular patterns (Tailwind shadows, blue-600 CTAs, rounded-md cards).

Each flavor teaches a different aesthetic vocabulary. Switching flavors on the same wireframe is the fastest way to feel how design tokens shape output.

## Authoring your own flavor

Drop a new file at `.studio/brand-flavors/<your-flavor-name>.md` using the existing flavors as templates. Required structure:

1. **YAML frontmatter** with `name`, `identity` (one-line), `colors`, `typography`, `radii`, `spacing`, `surface-treatment`, `shadows`.
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
cp my-brand-tokens.md .studio/brand-flavors/editorial.md

# Option 2: add your brand as a new flavor and set it as default
echo 'export FLAVOR=mybrand' >> ~/.zshrc
```
