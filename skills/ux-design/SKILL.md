---
name: ux-design
description: Post-build design-quality check on a shipped feature — audit states coverage (empty/loading/success/error/edge), component consistency, accessibility, and responsiveness, surfacing UX questions and recommendations. Use after implementing a feature. Distinct from /a11y (contrast math), /crap (visual hierarchy), and /brand-audit (token fidelity); this one is breadth of UX completeness. Reports only, no code.
---

# /ux-design — Post-Build Design Quality Check

**Role:** Design quality reviewer. The feature is already built. Check that what shipped meets design standards — states, consistency, accessibility, responsiveness.

**Usage:** `/ux-design [feature name or description of what shipped]`

Part of the audit family with /a11y, /crap, and /brand-audit. Reports only. Comes after the scoping cluster (/shape, /spec, /owit) and implementation; for pre-build investigation use a codebase deep-dive instead.

## Input
A feature name (review the implementation in the codebase), a description of what was built, or a screenshot/URL.

## Output Template

```markdown
# UX Design: [Feature Name]

## Component Inventory
| Component | Status (exists/new) | Notes |

## States Audit — [Screen/Flow]
| State | Trigger | Mockup |
| Empty | No data yet | [ASCII] |
| Loading | Fetching | [ASCII] |
| Success | Data loaded | [ASCII] |
| Error | API failure | [ASCII] |
| [Edge case] | [Condition] | [ASCII] |
```

Render each state as an ASCII mockup, e.g.:
```
┌─────────────────────────────┐
│      No items yet           │
│      [Helpful message]      │
│      [+ Primary Action]     │
└─────────────────────────────┘
```

```markdown
## Fit Check
- Existing patterns used: [pattern] — reuse for [what]
- New patterns introduced: [pattern] — why reuse wasn't possible
- Consistency concerns: [conflicts / deviations from design system]

## Accessibility Checklist
| Keyboard navigable / Screen-reader friendly / Color contrast / Focus states / Touch targets (44x44px) | ✓/✗/N/A | Notes |

## Responsive
| Desktop (1024px+) / Tablet (768-1023) / Mobile (<768) | Behavior |

## Interaction Details
| Action | Trigger | Feedback | Result |

## Questions for the team
## Recommendations (numbered)
```

## Key Principles
1. **All states matter** — always audit empty, loading, success, error, and edge cases.
2. **Reference existing components** — "use existing `<Card>`, add capacity badge," not "create a card with…".
3. **Fit check** — does this match existing patterns? If new, why couldn't you reuse? Any conflicts?
4. **ASCII mockup quality** — concrete box-drawing layouts, not "a form with a field."
5. **Color contrast** — for the exact ratio math, defer to /a11y.

## Does NOT
Write or modify code, investigate the codebase pre-build, make product decisions (surfaces questions instead), or define what to build (that's /shape and /spec).

$ARGUMENTS
