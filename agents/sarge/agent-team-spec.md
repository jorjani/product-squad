# Agent Team Architecture

## The Hill

David manages a product team of AI agents. He sets direction and makes decisions. Agents collaborate through GitHub issues without David as the messenger. Work flows from idea to shipped code through layered delegation, where each layer adds specificity from its own recon rather than upstream guesses.

## Roles

### David (Owner)
- Sets the hill, approves scope, makes decisions
- Works from phone; interacts via short messages
- Escalation target, not the router

### Sarge (PM Agent)
- Interviews David to clarify intent
- Runs codebase recon (files, schemas, patterns)
- Writes structured scope briefs as GitHub issues
- Manages board: Pitch → Scope → Backlog
- Does NOT specify implementation; defines the goal and constraints

### Foreman (Construction Foreman)
- Oversees execution, does not build directly
- Triages: evaluates issues against readiness criteria
- Dispatches builds to project agents (Sage, Jobber, Coaches)
- Reviews PR quality and correctness
- Verifies post-merge in production
- Escalates to Sarge (via issue comment) when spec is unclear

### Project Agents (Sage, Jobber, Coaches)
- Own their repo; know the codebase intimately
- Receive a goal + AC from Foreman, do their own recon
- Make all implementation decisions (files, patterns, approach)
- Build, test, ship PR

## The Issue Contract

The GitHub issue is the handoff artifact. Every issue that reaches Ready must have at least these sections. This is the minimum contract.

For the full issue format (adds Current State, UI Flow): see root `CLAUDE.md`. For step-by-step issue creation with grounding: run `/gh-issue`.

```markdown
## Goal
{1-2 sentences. What changes and why. The "done" state.}

## Acceptance Criteria
- [ ] {Testable outcome, not implementation step}
- [ ] {Testable outcome}
- [ ] {Testable outcome}

## Context
{What exists today that's relevant. Schema refs, existing patterns,
related features. Pointers, not prescriptions.}

## Out of Scope
{What this deliberately does NOT include. Prevents scope creep.}
```

Size (XS / S / M / L / XL) is set on the GitHub Project's Size field, not in the issue body.

### What goes IN the issue body:
- The goal (what the user/system should be able to do after)
- Testable acceptance criteria (observable outcomes)
- Relevant context (existing code, schemas, constraints)
- What's excluded (boundaries)

Size (XS / S / M / L / XL) goes on the GitHub Project Size field, not in the body.

### What stays OUT of the issue:
- Implementation steps ("modify file X, add function Y")
- Architecture decisions the builder can make
- Hallucinated details not grounded in codebase recon
- Speculative approaches ("could use X or Y")

### Body Size Constraint

Foreman's pre-build validator rejects bodies over 3,000 chars. Sarge targets **≤ 2,800 chars** before moving an issue to Backlog, leaving headroom for triage comments on the way to Ready.

When a brief would exceed the budget, extract to a spec doc at `<repo>/specs/<issue-number>-<slug>.md` and link it from the Context section as `Spec: specs/<issue-number>-<slug>.md`. Keep only Goal, Acceptance Criteria, short Context pointer, and Out of Scope in the issue body. Move SQL blocks, query results, migration steps, ASCII mockups, decision tables, and long code excerpts to the spec doc.

Once Foreman's validator loop-breaker PR lands, a same-body re-pickup after the first BUILD-OVERSIZED rejection will escalate to Blocked, which requires Sarge to revise before the ticket returns to Ready.

**Principle:** Each layer adds specificity from its own investigation. Sarge defines the goal. Foreman validates readiness. The project agent decides how to build it.

## Communication Protocol

All agent-to-agent communication happens via **GitHub issue comments**. No local files, no side channels.

### Sarge → Foreman
- Writes issue body with the contract format above
- Moves to Scope or Backlog on the board
- Tags with repo label (sage, jobber, coaches)

### Foreman → Sarge (feedback loop)
- Comments on issue: "NEEDS-SPEC: {what's missing}"
- Sarge reads comment, runs additional recon, updates issue body
- Foreman re-triages on next run

### Foreman → Project Agent
- Passes: issue title, body, comments, repo path
- Project agent does its own codebase recon before building
- Project agent has full autonomy on implementation

### Project Agent → Foreman (via PR)
- Ships PR linked to issue
- Foreman reviews against AC (not implementation opinions)
- CLEAN → merge. ISSUES → comment with specifics.

### Any Agent → David (escalation)
- Comment on issue: "DECISION-NEEDED: {options with recommendation}"
- Only when: unresolvable ambiguity, conflicting constraints, or 2 round-trips without resolution

## Board Flow (Simplified)

```
Parking ──→ Pitch ──→ Scope ──→ Backlog ──→ Ready ──→ Done
           (Sarge)   (Sarge)   (Sarge)    (Foreman)  (Foreman)
```

### Column ownership:
- **Parking:** David drops raw ideas
- **Pitch → Scope → Backlog:** Sarge's territory. Interview, recon, write brief.
- **Ready → Done:** Foreman's territory. Triage, dispatch, review, verify.

### Gateway criteria:
- **→ Pitch:** David says "look into this"
- **→ Scope:** Has goal and initial AC from Sarge's interview
- **→ Backlog:** Passes Sarge's self-check (contract format complete, recon done)
- **→ Ready:** Passes Foreman's 6 triage criteria (clear AC, bounded scope, no TBDs, no blocked deps, sufficient context, not blocked)
- **→ Done:** PR merged + verified in production

## Delegation Model

```
David: "Sage should recommend what to work on next"
  │
  ▼
Sarge: interviews David, recon Sage codebase
  │  writes issue: Goal + AC + Context + Out of Scope
  │  posts to board → Scope
  │  self-checks → moves to Backlog
  │
  ▼
Foreman: triage evaluates against 6 criteria
  │  if pass → Ready
  │  if fail → comments "NEEDS-SPEC: missing X" → Sarge picks up
  │
  ▼ (Ready)
Foreman: dispatches to Sage project agent
  │  passes: issue body + repo path
  │  Sage agent does its own recon, decides approach, builds
  │
  ▼
Sage Agent: ships PR linked to issue
  │
  ▼
Foreman: reviews PR against AC
  │  CLEAN → merge → verify → Done
  │  ISSUES → comments → Sage agent fixes
```

## What Changes from Today

| Today | Target |
|-------|--------|
| David writes issues | Sarge writes issues from David's direction |
| Freeform issue format | Standard contract (Goal/AC/Context/OOS) |
| Foreman builds code directly | Foreman dispatches to project agents |
| Board columns unused (In Progress, In Review, Done) | Simplify to match actual flow |
| Priority/Size/Estimate fields empty | Delete or start using |
| 30 items rotting in Parking | Sarge triages Parking proactively |
| Sarge is conceptual | Sarge is an active agent writing issues |

## Implementation Phases

### Phase 1: The Contract (now)
- Standardize issue format across existing Ready tickets
- Update Foreman's triage prompt to enforce the contract
- Sarge starts writing issues for Sprint 1 tickets

### Phase 2: The Feedback Loop
- Foreman comments "NEEDS-SPEC" on issues that fail triage
- Sarge monitors and responds (manual trigger for now)
- Board columns cleaned up to match actual flow

### Phase 3: Foreman Dispatches
- Foreman stops building directly
- Foreman spawns project-specific Claude sessions with repo context
- Each project agent gets: issue body + their CLAUDE.md + their design-system/

### Phase 4: Autonomous Loop
- Sarge proactively triages Parking
- Full cycle runs without David except for escalations
- David reviews shipped work, not in-progress specs
