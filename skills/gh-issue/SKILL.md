---
name: gh-issue
description: Turn a /spec into a GitHub issue in commander's-intent form — goal and constraints down, implementation decisions left to the builder. Use after /spec to hand a contract to a builder or board. Board-agnostic — emits the issue plus the gh create command; project/column placement is your tooling's job.
---

# /gh-issue — Spec → Issue (Commander's Intent)

A `/spec` is the contract. `/gh-issue` packages it as a GitHub issue a builder can pick up without a follow-up conversation — stating the **goal and constraints**, and deliberately *not* stating how to build it.

**Consumes:** A `/spec` document (this session's, or `specs/<slug>.md`).

**Delivers:** A GitHub issue — outcome-oriented title + commander's-intent body — plus the ready `gh issue create` command. Implementation decisions stay with the builder.

---

## Step 0 — Find the spec

Use this session's `/spec` output, or read `specs/<slug>.md`. If there's no spec, stop: "Run `/spec` first — `/gh-issue` packages a contract, it doesn't author one."

## Step 1 — Respect the repo's template

If the target repo has `.github/ISSUE_TEMPLATE/feature.yml`, map the spec into its fields. Otherwise use the default body below.

## Step 2 — Ground the references

Before writing, verify any file paths, functions, or data models the spec names actually exist — search the codebase directly or send a subagent. An issue that points a builder at a path that moved or a function that was renamed wastes their first hour. Collect verified references in `file.ext:symbol` form; these belong in the issue's constraints/context, not invented from memory. If the spec references nothing concrete (pure greenfield), skip this step.

## Step 3 — Write the issue (commander's intent)

Translating a spec into an issue is a **demotion of detail**: keep the goal, the why, the constraints, and the acceptance; drop the how. The builder decides mechanism.

- **Title** — outcome-oriented, imperative. "Let candidates filter jobs by visa sponsorship," not "Add visa filter dropdown component."
- **Body** — Goal, What changes for the user, Constraints & principles (what must hold — not how), Acceptance (observable), Open questions (carried from the spec, not papered over).
- **No implementation detail** — no file paths, no prescriptive logic, no "do X by doing Y." If you're tempted to write a step, you're writing the builder's job.
- **Body budget ≤ ~3000 chars.** If the spec is richer, link `specs/<slug>.md` and keep the issue body to the intent. Don't inline a wall of scenarios.

**When to extract a spec doc:** if the body is approaching ~2000 chars, or you're about to paste a code block longer than ~10 lines, an ASCII mockup over ~40 lines, a decision matrix, or a step-by-step runbook — stop and put it in `specs/<slug>.md` instead, then link it from the body. Give the spec doc minimal frontmatter so it's traceable:

```yaml
---
issue: <number, once created>
status: draft
---
```

## Step 4 — Create it (confirm first)

Creating an issue is an outward-facing action. Show the body, then: if `gh` is available and you're in the target repo, offer to run the create on confirmation. Otherwise emit the command for the operator to run.

## Step 5 — Board placement (optional, your tooling)

This skill is board-agnostic — it produces the issue and the create command, and stops. If your workflow *also* drops new issues onto a project board, that's your tooling's job, but the generic shape is:

1. Resolve the issue's node ID: `gh api repos/<org>/<repo>/issues/<n> --jq '.node_id'`.
2. Add it to your board: `addProjectV2ItemById` with your project's ID.
3. Set the starting column / priority / size: `updateProjectV2ItemFieldValue` against your status field, choosing the option that matches the issue's shape (a fuzzy idea-with-options → an early "pitch/triage" column; a clean grounded spec → a "ready/backlog" column).

Keep your project, field, and option IDs in your own config — they're environment-specific, not part of this skill. State the chosen column and one-line reason before mutating, so the operator can override.

---

## Output Format

```
## Issue — <title>

**Title:** <outcome-oriented, imperative>

**Body** (commander's intent, ≤ 3000 chars):
---
## Goal
<the outcome and why it matters — from /spec>

## What changes for the user
<capability delta — observable>

## Constraints & principles
<non-negotiables — what must hold, not how>

## Acceptance
<observable conditions that mean it's done>

## Open questions
<carried from /spec, if any — else omit>

<link to specs/<slug>.md if the body was trimmed>
---

Create it:
gh issue create --title "<title>" --body-file <path-to-body>

(Adding the issue to a project board / setting a column is environment-specific — your tooling.)
```

---

## Rules

- **Goal and constraints down; how stays with the builder.** That's the whole contract. The moment you prescribe mechanism, you've broken commander's intent.
- **Outcome title, observable acceptance.** "User can X and sees Y," never "feature works" or "component added."
- **Respect the budget.** ≤ 3000 chars; extract overflow to `specs/<slug>.md` and link it.
- **Don't fabricate or resolve open questions.** Carry the spec's unresolved items into the issue verbatim. An issue that hides its unknowns wastes the builder's first hour.
- **Board-agnostic.** Produce the issue + command. Project/column placement is the operator's tooling, not this skill's job.
- **Confirm before creating.** Outward-facing side effect — show the body, get a yes, then run `gh`.

$ARGUMENTS
