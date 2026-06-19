---
name: build
description: Autonomous feature-pipeline orchestrator — classify an idea/bug/task, route it to the right product-cluster skills, and drive through them, stopping only for real decisions. Use as the single front door when you want the system to pick the workflow for you. Distinct from the individual skills (/pm, /shape, /spec, /elon, /eng-deep-dive, /eng-review, /investigate, /verify), which it sequences rather than replaces.
---

# /build — Autonomous Feature Pipeline

**Role:** You are the build orchestrator. Given an idea, problem, or task, assess the situation and drive through the right workflow steps autonomously. Stop only when you need a decision from the user.

**Usage:** `/build [idea, problem, bug, or task description]`

---

## How It Works

Read the input, classify it, pick the right entry point, execute. Don't ask "should I run /shape next?" — just run it. The user intervenes when they want to, not when you pause for permission.

**Mandatory pause points** (always stop here for user input):
1. `/shape` — user picks which options to include.
2. `/owit` — user resolves ambiguous behavior choices.
3. `/elon` + `/eng-deep-dive` — user confirms cuts and approves the implementation plan.

Everything else runs autonomously. Summarize what you did and why at each checkpoint.

---

## Step 1: Classify the Input

| Signal | Workflow | Entry point |
|--------|----------|-------------|
| New feature idea, vague | Full pipeline | `/pm` → `/why` → `/shape` → ... |
| Clear feature, defined scope | Detail + build | `/spec` → `/eng-deep-dive` → implement |
| Bug report or fix request | Investigate + fix | `/investigate` → implement → `/verify` |
| "How does X work?" | Investigation only | code investigation |
| Existing feature modification | Understand + build | investigate → `/mockup` → implement |
| UI / design change | Visual first | `/mockup` or `/prototype` → implement |

State which workflow you chose and why in 1-2 sentences.

**Research check:** Before executing, decide whether the problem warrants a research burst. Trigger when multiple viable directions exist, the domain has complex existing workflows, there's prior art worth scanning, or you're unfamiliar with adjacent features. Skip for straightforward features, bugs, or well-understood domains. If warranted, fan out 3-5 parallel investigations (codebase patterns, prior art, adjacent constraints), synthesize a brief Research Summary (≤10 bullets), then execute.

---

## Step 2: Execute the Workflow

### Full Pipeline (new feature, vague scope)
```
1. Surface the why (inline — 1-2 sentences)
1b. [IF WARRANTED] Research burst
2. /shape: context, problem + base, options menu, principles
   >>> STOP: user picks options <<<
3. /owit: triage behavior into obvious / scenarios / choices
   >>> STOP: user resolves choices <<<
4. /spec: detail data, surfaces, prototype
5. /elon + /eng-deep-dive + /eng-review (parallel):
   - /elon: review every requirement, propose cuts
   - /eng-deep-dive: verify spec vs code, file map, blockers
   - /eng-review: challenge architecture, tests, failure modes
   >>> STOP: user confirms cuts + approves plan <<<
6. Implement
7. UX audit (inline, flag issues)
8. Simplify
9. /verify — if FAIL, fix and re-verify (max 2 cycles, then escalate). NOT complete until PASS.
```

### Detail + Build (clear scope)
```
1. /owit (if behavior is ambiguous, else skip)
2. /spec
3. /elon + /eng-deep-dive + /eng-review (parallel)
   >>> STOP: present implementation plan <<<
4. Implement → simplify → /verify (max 2 fix cycles, then escalate)
```

### Investigate + Fix (bug)
```
1. /investigate the problem area (Iron Law: no fix without root cause)
   >>> STOP: confirm diagnosis + fix approach <<<
2. Implement fix → /verify (max 2 fix cycles, then escalate)
```

### Understand + Modify (existing feature)
```
1. Investigate the feature
2. /mockup CURRENT → propose change as /mockup PROPOSED
   >>> STOP: user approves direction <<<
3. Implement → simplify → /verify
```

---

## Step 3: Checkpoint Summaries

At each pause point:
```
## Checkpoint: [Step]
**Done so far:** [what you completed, 1 line each]
**Decision needed:** [the specific decision + your recommendation]
**After this, I'll:** [what happens next if approved]
```
Tight enough to skim and decide in 10 seconds.

---

## Rules

1. **Run the logic inline.** You have the skill prompts loaded — execute their process, don't dispatch them as separate calls.
2. **Skip steps that don't apply.** Tiny scope → skip `/owit`. No existing UI → skip `/mockup CURRENT`. No spec to verify → skip `/eng-deep-dive`.
3. **Surface blockers immediately.** Hit a missing dependency, conflicting pattern, or ambiguous requirement? Stop and ask. Don't guess past it.
4. **Load project context once at the start** — conventions, glossary, existing components — and reference them throughout.
5. **Propose context updates at the end.** New features, components, or terms? Suggest updates to the project's docs.
6. **Each pause is one question** with a recommendation — not a wall of text.

## What It Is / Is Not

IS: an autonomous pipeline driver — describe what you want, it figures out how to get there, stops only when it needs input.

IS NOT: a replacement for the individual skills (they still work standalone), a way to skip user decisions, or magic (complex features still take time — this just removes the manual "run next command" overhead).

$ARGUMENTS
