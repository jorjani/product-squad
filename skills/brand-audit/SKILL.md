---
name: brand-audit
description: Audit brand consistency — verify a design-system / brand-tokens doc exists and is complete, or compare its tokens against the code with file:line precision. Use to check visual identity (colors, fonts, radii, effects) against the source of truth. Distinct from /a11y (contrast math), /crap (visual hierarchy), and /ux-design (states); this one is token fidelity. Audits visual identity only, never copy.
---

# /brand-audit — Brand Consistency Audit

**Usage:** `/brand-audit [mode]`  — modes: `generate` | `guidelines` | `implementation` | (auto-detect)

Part of the audit family with /a11y, /crap, and /ux-design. Reports only; produces no code changes. References the visual ladder (/mockup, /prototype) when generating a new design system.

## Auto-detection
1. Look for the canonical token source — your design-system / brand-tokens doc (e.g. a `design.md` in your project's design-system folder), falling back to legacy `brand-guidelines.md`, `brand/*.md`, `docs/brand*.md`.
2. No token source → **Mode 1 (Generate)**. Token source + codebase (`src/`, `tailwind.config.*`, `*.css`) → **Mode 3 (Implementation)**. Token source, no codebase → **Mode 2 (Audit doc)**.

Report which mode ran, which file is canonical, and why.

## Mode 1 — Generate design system
No token doc found, or `generate`. Output is YAML frontmatter (palette, typography, radii) plus a markdown body (intent per token, do's and don'ts). If a codebase exists, scan for signals first: `:root` CSS vars, Tailwind colors, Google Fonts imports, recurring hex values. Then present a Decision Guide (Color Direction, Typography Pairing, Audience Signal), pre-fill what the scan found, and walk the user through the rest. Do not guess values, generate logos, or write the doc without user decisions.

## Mode 2 — Audit the doc
Token source but no codebase, or `guidelines`. Read the design-system doc (and any companion recipes), validate the frontmatter schema, and check internal consistency between frontmatter, body prose, and companion recipes.

```
## Frontmatter Completeness   (name, colors.*, typography.*, radii — ✓/△/✗)
## Body Completeness          (overview, color intent, type scale, components, do/don't)
## Internal Consistency       (valid hex; prose names match tokens; recipes ref tokens by name not hex)
## Gaps & Recommendations     (numbered, actionable)
```

## Mode 3 — Audit implementation
Token source + codebase, or `implementation`. Read the design-system doc frontmatter (palette/type/radii) and body (usage rules). Read infrastructure (CSS, Tailwind config, tokens), then scan components. Report violations by severity:

- **Critical** — CSS custom props / Tailwind config / framework theme vars don't match the palette.
- **High** — hardcoded hex not in palette (grep `#[0-9A-Fa-f]{6}`); `text-white`/`bg-black` when brand uses off-tones; pure `#FFFFFF`/`#000000` when brand specifies alternatives.
- **Medium** — gradients when prohibited; off-scale font weights/families; missing font imports; radius inconsistencies.
- **Low** — accent overused; hardcoded colors vs. token refs; inconsistent hover colors.

```
## Infrastructure Status   (CSS vars, Tailwind, tokens, fonts — ✓/△/✗)
## Violations              (Critical/High/Medium/Low — table: File | Line | Issue | Expected | Actual)
## Summary                 (counts by severity; overall compliance)
## Recommended Fixes        (prioritized)
```

## Key Principles
1. **Read before judging** — extract brand values from the doc; don't assume.
2. **File:line references** — every violation actionable, e.g. `Header.tsx:88 — hardcoded bg-[#12121A] instead of bg-secondary`.
3. **Severity matters** — token mismatch breaks the system; a stray `text-white` is fixable; an extra hover is a nit.
4. **Infrastructure first** — fix tokens/config before component-level noise.
5. **No copy auditing** — visual identity only, not tone or content.

## Does NOT
Write or modify code, audit copywriting, generate logos, make brand decisions without input, or replace human design review.

$ARGUMENTS
