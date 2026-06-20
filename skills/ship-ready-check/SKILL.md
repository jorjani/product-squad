---
name: ship-ready-check
description: Quality gate that decides whether a work item (GitHub issue, ticket, spec) is ready to hand to an autonomous coding agent to build without follow-up questions. Runs four ordered gates — Value, Clarity, Grounding (against the actual codebase), Scenarios — stopping at the first failure so cheap checks run before expensive ones. Posts a verdict, advances the item on pass, returns blocking questions + suggested fixes on fail. Uses an autonomous build agent + GitHub issues as the worked example; the gate framework transfers to any builder + tracker. Pairs with /pm, /eng-deep-dive, /gh-issue.
---

# /ship-ready-check — Readiness Gate Before an Autonomous Build

Generic purpose: before a work item is handed to an autonomous coding agent (or a junior dev) to build unattended, prove it's **worth doing, grounded in reality, and specified clearly enough that two builders produce the same result.** A bounced ticket is cheap; a broken autonomous build is not.

**This skill uses an autonomous build agent reading GitHub issues as the worked example.** The four-gate framework transfers to any builder + tracker — replace `gh issue view` and the board-move mutation with your tracker's API.

**Usage:** `/ship-ready-check [issue-url]` · `/ship-ready-check sweep` (batch non-ready items)

## How it works

1. Fetch the item.
2. Identify which project/repo it belongs to.
3. Load that project's codebase context.
4. Run 4 gates **in order. Stop at the first failure** — don't run expensive gates on items that fail cheap ones.
5. Post the verdict.
6. All pass → advance the item to the builder's queue. Any fail → leave it, comment with blocking questions + suggested fixes.

## The 4 gates

### Gate 1 — Value (text only, cheapest)

Tests the **problem**, not the solution.
- **Who and when?** A specific user in a specific scenario, not "users" generically.
- **What changes for them?** A meaningful before/after the user would notice. Look at the actual product — if the current experience is already fine, the problem isn't real.
- **Delivered vs. listed value.** Does *this* item deliver the benefit, or list aspirational future benefits while shipping a subset?

**PASS:** specific user + scenario + real, current pain. **FAIL:** no concrete user/scenario, or value justified entirely by systems that don't exist yet. A real problem with a heavy approach still passes here — flag the approach for Gate 3.

### Gate 2 — Clarity (text only)

**PASS:** no TBD/open questions; concrete testable acceptance criteria; single bounded deliverable; files to touch listed; two builders would produce the same result. **FAIL:** unresolved design decisions, vague requirements ("make it better"), multiple plausible interpretations, missing criteria. On fail, state the ambiguity and the competing interpretations.

### Gate 3 — Grounding (reads the codebase — expensive; launch a subagent)

The subagent must return **evidence** (what it found, where), not just verdicts. Verify:
- **Root cause match** — read the code the item changes; understand why the current behavior is broken before judging the fix. A complex fix for a simple bug is caught here.
- **File / function / model references exist** and do what the item claims.
- **Behavioral & data-model claims** match the actual code/schema.
- **Existing implementations** — does something similar already exist that the item ignores?
- **Dependencies** referenced are actually shipped.
- **Stale details** — model IDs, package versions, endpoints that drifted.
- **Approach proportionality** — if Gate 1 flagged a simpler path, does the codebase support it, or does it justify the heavier one? State which.

Line numbers drift; flag inaccurate ones but don't fail on minor drift if the file + function are right. On fail, state claim-vs-found and **suggest the fix** ("Replace `claude-3-haiku-20240307` with `claude-haiku-4-5`, used in `src/lib/extraction/claude.ts`").

### Gate 4 — Scenarios (text + grounding context)

**PASS:** happy path fully described; top 3–5 failure/edge cases covered (error, empty, duplicate, timeout, bad input) with specified behavior. **FAIL:** only the happy path; vague error handling ("handle gracefully" without saying how). On fail, list missing scenarios as concrete questions.

## Gate ordering — cheap first

```
Gate 1 Value      — text only  ─┐ fail → stop, comment
Gate 2 Clarity    — text only  ─┤ fail → stop, comment
Gate 3 Grounding  — subagent reads codebase (expensive) ─┤ fail → stop
Gate 4 Scenarios  — text + grounding context ─┘ all pass → advance
```

A vague or low-value item never triggers the expensive grounding read.

## Verdict comment

```
**Ready Check: PASS**
| Gate | Verdict | Notes |
|------|---------|-------|
| Value     | PASS | … |
| Clarity   | PASS | … |
| Grounding | PASS | … |
| Scenarios | PASS | … |
Advanced to the build queue.
```

On fail, mark the failing gate, leave later gates `--` (not evaluated), and add a **What to fix** list. Each item: references a specific gap (not "needs more detail"), suggests a fix or names the simpler alternative, and is never answerable with just yes/no.

## Override

If an item fails the gate but should be built anyway, add a `force-build` label — the builder picks it up regardless; the gate comment stays as documentation of known gaps.

## Rules

1. **Value first.** If the work isn't worth doing, nothing else matters.
2. **Stop at first failure.** Don't run expensive gates on items that fail cheap ones.
3. **Suggest fixes, not just questions.** You have the codebase context — "Did you mean `X`?" beats "seems wrong."
4. **Evidence over judgment.** Grounding verdicts cite file + line + content.
5. **Conservative default.** When in doubt, fail — a bounce is cheaper than a broken build.
6. **One comment per run.** Edit/replace the prior Ready Check comment; don't spam.

## Neighbors

- [`pm`](../pm/SKILL.md) — interrogate the idea before it's even a ticket (upstream of this gate).
- [`eng-deep-dive`](../eng-deep-dive/SKILL.md) — the codebase reality check Gate 3 performs, run standalone.
- [`gh-issue`](../gh-issue/SKILL.md) — write the issue in commander's-intent form so it passes Clarity on the first try.
