# /experience — Articulate what changes for the user

**Purpose:** Print a brief, specific description of what happens after the work ships, written in the actual user's vocabulary. Useful mid-conversation when technical detail has drifted from human impact, or when drafting an issue body's "Why" section.

**Usage:** `/experience [feature description or work-in-progress]`

---

## What this command produces

```
Experience: [specific feature name]
Audience:   [who exactly, what they're doing, where in the product]

[Lens, named after the actual user]:
  [Observable description of what the user encounters after the work
   ships. Specific surfaces, dimensions, and example values. No
   adjectives without observables behind them.]

Delta: [The felt change in one sentence.]

Risks:                  ← optional, only if there are real trade-offs
- [1-2 bullets describing what might trip the user or trade off]
```

---

## Rules

### One lens only

The user's lens, written in the user's vocabulary. The user might be a candidate, a founder, a developer, an oncall engineer — whoever they actually are. There is no separate "DX block" alongside "UX block." If the actual user is a developer, the lens speaks developer. If the actual user is a candidate, the lens speaks candidate. Pick the one true audience and write everything in their terms.

### Be specific — every noun answers "which one?"

| Vague | Specific |
|---|---|
| "preferences" | "job-matching preferences in the candidate's profile" |
| "the form" | "the salary min/max input pair in the profile's job-matching section" |
| "the user" | "authenticated candidate on JobBoard" |
| "the list" | "the For You feed" |
| "the slider" | "the salary range slider in the job-matching preferences" |

If a noun could refer to two things, name it.

### Lead with the After, not the Today

Skip the "today X is broken" preamble. Lead with what the user encounters when the work is done. The reader already knows the current state; what they're trying to articulate is the new one.

### Concrete preview values, not "various examples"

Pick representative numbers and show the verdict each one gets.
- ✗ "scores low for junior candidates"
- ✓ "a 1-yr role → skip · too junior; a 7-yr role → 20/20 · in sweet spot"

### Delta is one sentence

The felt change, not a recap. If you need two sentences, the body block is doing the wrong job.

---

## Anti-patterns

| Don't | Do |
|---|---|
| Generic nouns ("preferences", "the form") | Name the specific surface and what's on it |
| Adjectives without observables ("easier", "cleaner", "more intuitive") | Describe the observable change that produced the feeling |
| Parallel DX block on a UX feature | Drop it; if the user isn't a developer, DX isn't a separate audience |
| Multi-paragraph Delta | One sentence — the felt change |
| Implementation references in any block | Surface, dimension, and verb only — no file paths, function names, or schema fields |
| Speculative emotional language ("delighted users") | Observable outcomes only — what they see, do, or stop seeing |

---

## Worked example — JobBoard range picker

```
Experience: Visual range picker for JobBoard job-matching preferences
Audience:   Authenticated candidate on JobBoard, editing job-matching
            preferences (salary, years of experience, seniority,
            company size) in their profile

UX:
  In the profile's job-matching preferences section, the candidate
  sees one range slider per ranged dimension — replacing the current
  salary min/max input pair and the seniority pill multiselect, and
  used for new dimensions like years of experience and company size.

  Two red handles set the hard skip range for each dimension. For
  example, on years of experience: "skip jobs requiring less than
  2 yrs or more than 15 yrs." A green band between the handles
  shows the auto-derived sweet spot — the range where matching
  jobs score full points.

  A live preview panel below the slider scores five sample jobs
  against the current settings: a 1-yr role → "skip · too junior";
  a 7-yr role → "20/20 · in sweet spot"; an 18-yr role → "skip ·
  too senior."

  If the auto sweet spot is wrong, "+ Tune sweet spot" reveals two
  green inner handles to narrow or widen the full-score range.

Delta: The candidate sees the shape of their preference instead of
       two opaque numbers — and roles outside both edges (too junior
       AND too senior, underpaying AND overpaying) stop appearing in
       the For You feed by default.

Risks:
- Touch: outer handles can clip when set close — need ≥44px hit areas.
- Hidden mode: "+ Tune sweet spot" may be missed on first use —
  first-render pulse or onboarding hint helps.
- Tier-snapping for seniority: Junior/Mid/Senior/Staff/Principal are
  discrete; the picker needs to snap rather than interpolate.
```

---

## When to invoke

- Mid-conversation, after technical drift, to surface "what does this actually change for the person on the other side?"
- Before writing an issue body's "Why" section
- When comparing two designs to see whose delta is bigger
- In a retro, to describe what shipped
- Whenever a non-technical reader needs to understand what the work does

## When NOT to invoke

- For multi-scenario mapping with branches → use `/owit`
- For deciding whether to build at all → use `/shape`
- For one-level-up goal restatement → use `/why`
- For visual decisions or layout → use `/mockup` or `/wireframe`
- For engineering plans → use `@eng-deep-dive`

## Neighbors

```
   /why         (one level up — outcome)
     ↓
   /shape       (decide what to build)
     ↓
   /experience  ←  THIS (articulate the human delta)
     ↓
   /owit        (map the full scenario)
     ↓
   /spec        (detail data + surfaces) [V1 — not bundled in V0.5]
```

It's also fine to fire `/experience` after building, before writing the issue body or retro.

$ARGUMENTS
