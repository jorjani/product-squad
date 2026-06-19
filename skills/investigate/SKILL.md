---
name: investigate
description: Systematic root-cause debugging — no fix until the root cause is found and proven, to stop symptom-patching whack-a-mole. Use when asked to debug, fix a bug, investigate an error, or run a root-cause analysis. Drives hypothesis → evidence → minimal fix → regression test, and calls /verify to prove the fix before reporting done.
---

# /investigate — Systematic Debugging

Systematic root-cause debugging. Use when asked to debug, fix a bug, investigate an error, or root-cause an analysis.

**Usage:** `/investigate [symptom, error, or failing behavior]`

## Iron Law

NO FIXES WITHOUT ROOT-CAUSE INVESTIGATION FIRST. Fixing symptoms creates whack-a-mole. Find the root cause, then fix it.

## Phase 1: Root-Cause Investigation

1. Collect symptoms: error messages, stack traces, reproduction steps. Insufficient context? Ask ONE question at a time.
2. Read the code: trace the path from symptom back to potential causes. Grep for references, Read for logic.
3. Check recent changes: `git log --oneline -20 -- <affected-files>`. Was this working before? What changed?
4. Reproduce: can you trigger it deterministically? If not, gather more evidence first.

Output: "Root cause hypothesis: ..." — a specific, testable claim.

## Phase 2: Scope Lock

After forming the hypothesis, identify the narrowest directory containing the affected files. Announce: "Restricting edits to `<dir>/` for this debug session." Only edit outside it if the root cause genuinely spans broader scope.

## Phase 3: Pattern Analysis

| Pattern | Signature | Where to look |
|---------|-----------|---------------|
| Race condition | Intermittent, timing-dependent | Concurrent access to shared state |
| Nil/null propagation | TypeError, undefined | Missing guards on optional values |
| State corruption | Inconsistent data, partial updates | Transactions, callbacks, hooks |
| Integration failure | Timeout, unexpected response | External API calls, service boundaries |
| Configuration drift | Works locally, fails in staging/prod | Env vars, feature flags, DB state |
| Stale cache | Shows old data, fixes on clear | Redis, CDN, browser cache |

Also check git log for prior fixes in the same area — recurring bugs in the same files are an architectural smell.

## Phase 4: Hypothesis Testing

Before writing ANY fix, verify the hypothesis.

1. Add a temporary log/assertion at the suspected root cause. Run reproduction. Does evidence match?
2. Hypothesis wrong? Return to Phase 1. Gather more evidence. Do not guess.
3. **3-strike rule:** 3 failed hypotheses → STOP. Ask the user:
   - A) Continue — new hypothesis: [describe]
   - B) Escalate — needs someone who knows the system
   - C) Add logging and catch it next time

Red flags — slow down if you see:
- "Quick fix for now" — there is no "for now." Fix it right or escalate.
- Proposing a fix before tracing data flow — you're guessing.
- Each fix reveals a new problem elsewhere — wrong layer, not wrong code.

## Phase 5: Implementation

1. Fix the root cause, not the symptom. Smallest change that eliminates the actual problem.
2. Minimal diff: fewest files, fewest lines. Resist refactoring adjacent code.
3. Write a regression test that fails without the fix, passes with it.
4. Run the full test suite. Paste the output. No regressions.
5. Fix touches >5 files? Flag the blast radius before proceeding.

## Phase 6: Verification & Report

Reproduce the original bug and confirm it's fixed — run `/verify`, not optional.

```
DEBUG REPORT
════════════════════════════════════════
Symptom:         [what the user observed]
Root cause:      [what was actually wrong]
Fix:             [what changed, with file:line]
Evidence:        [test output showing the fix works]
Regression test: [file:line of the new test]
Status:          DONE | DONE_WITH_CONCERNS | BLOCKED
════════════════════════════════════════
```

## Rules

- 3+ failed fix attempts → STOP and question the architecture.
- Never apply a fix you cannot verify. Never say "this should fix it" — prove it via `/verify`.
- Fix touches >5 files → flag blast radius first.
- DONE = root cause found + fix applied + regression test + all tests pass.
- DONE_WITH_CONCERNS = fixed but cannot fully verify (intermittent, needs staging).
- BLOCKED = root cause unclear after investigation, escalated.

$ARGUMENTS
