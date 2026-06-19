---
name: a11y
description: Audit an HTML file or component for WCAG AA color-contrast compliance — find every foreground/background pair, compute contrast ratios with Python, flag failures, and apply same-hue fixes. Use when checking or fixing contrast specifically. Distinct from /crap (visual hierarchy), /brand-audit (token consistency), and /ux-design (states + responsiveness); this one is purely about contrast math.
---

# /a11y — WCAG AA Color Contrast Audit

**Usage:** `/a11y [file path or screenshot]`

Audit a file for WCAG AA color contrast. Find every meaningful color pair, compute ratios, flag failures, fix them. Part of the audit family with /crap, /brand-audit, and /ux-design; reach for the visual ladder (/mockup, /prototype) when fixes turn into a redesign.

## Step 1 — Identify colors

Read the file and extract every pair where text or meaningful non-text UI appears:
1. **Text on backgrounds** — each CSS rule that sets `color` with its effective `background`.
2. **Non-text UI** — borders, icons, form controls, focus indicators against adjacent color.
3. **Nested contexts** — trace to the nearest ancestor background actually rendered.

Build a table: FG hex, BG hex, where it appears (selector), font size + weight.

## Step 2 — Compute ratios

Use Python (never eyeball):

```python
def relative_luminance(r, g, b):
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)

ratio = (lighter + 0.05) / (darker + 0.05)
```

**AA thresholds:** normal text 4.5:1; large text (>=18px, or >=14px bold/weight>=700) 3:1; non-text UI 3:1.

## Step 3 — Report

Table of ALL pairs, failures first:

```
| Element            | FG      | BG      | Ratio | Req   | Status |
|--------------------|---------|---------|-------|-------|--------|
| .label on .surface | #6B6B78 | #1C1C24 | 3.2:1 | 4.5:1 | FAIL   |
```

For each failure propose a replacement that passes, stays close to the original hue, and fits the palette.

## Step 4 — Fix

Apply fixes. Change only the failing property; leave passing colors alone. Re-compute the ratio after each change, then re-run the full audit to confirm zero failures.

## Output Summary

```
A11Y AUDIT — [filename]
Pairs checked: N   Failures found: N   Failures fixed: N
Status: ALL PASS (WCAG AA)
```

## Rules

- Always use Python for the math — never approximate.
- Trace nested backgrounds to the real rendered color.
- Decorative-only elements with no information value are exempt — state why when exempting.
- Fix contrast by adjusting lightness/saturation of the same hue, not by changing the design.
- Re-verify after all fixes.

$ARGUMENTS
