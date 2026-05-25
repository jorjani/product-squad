# Sarge Build Brief

**Date:** 2026-04-03
**Author:** David + Claude (scoping session)
**Goal:** Build Sarge as a full PM agent that drives the Pitch-to-Scope pipeline, interviews David, runs codebase recon, and keeps Foreman fed with Ready work.

---

## Commander's Intent

**Done looks like:** David drops an idea — it goes to Pitch. Sarge interviews him (short codes, mobile-friendly), runs codebase recon, writes a scoped GitHub issue with commander's intent format, and moves it through Scope toward Ready. Foreman picks it up from there. David makes decisions, not specs. Parking is David's holding pen — Sarge never touches it.

**Who receives this:** Foreman (the builder agent), who triages Scoped issues into Ready and builds them autonomously.

**How we know it worked:** Parking stops growing. Scope items move to Ready within 1-2 days instead of stalling. David's interaction is approve/reject/redirect, not write-specs-manually.

---

## The System Today

### What Works (Don't Break These)

**Foreman** runs 5x/day via launchd. Fully operational:
- Verify → Review → Build → Triage → Sarge-Enrich → Self-Improve
- 15 items shipped in last 8 days
- Budget caps: $20/build, $10/review, $10/sarge-enrich, $5/triage
- Safety: isolated worktrees, auto/ branches only, CI must pass
- Config: `/Users/jorjani/Projects/foreman/config/schedule.plist`
- Board helpers: `/Users/jorjani/Projects/foreman/config/board-ids.sh`

**Board (Project #5):** Pitch → Scope → Ready → Done (Parking is graveyard, David only)
- Board config in `~/Projects/.index.json` under each project's `board` field
- Board helpers in `foreman/config/board-ids.sh`
- Comment protocol and issue contract format: see `sarge/agent-team-spec.md`

### What's Broken (Fix These)

1. **Sarge doesn't initiate.** It only reacts to Foreman's NEEDS-SPEC comments. Nobody drives Pitch → Scope proactively. The pipeline starves at the top.

2. **33 Parking items rotting.** No triage, no curation, no "this is dead, kill it" or "this matters, promote it." David is the bottleneck.

3. **9 Scope items stuck.** NEEDS-SPEC comments posted but items aren't progressing to Ready. The enrichment → re-triage loop may have a bug, or the enrichments aren't good enough to pass triage.

4. **Pitch-to-scope phase mothballed.** `foreman/phases/pitch-to-scope.sh` exists but was removed from the daily loop (caused deadlocks — Sarge wrote bad specs, Foreman rejected, loop stalled). Still callable manually via `./orchestrator.sh pitch-to-scope`.

5. **No way to invoke Sarge.** The agent definition (`.claude/agents/sarge.md`) exists but is passive. No command, no trigger, no scheduled run.

### What's Designed But Not Built

**Council Pattern** — `sarge/plans/council-implementation.md`
- 5 advisor personas (Questioner, Pruner, Simplifier, Builder, User Advocate)
- 3-stage deliberation: fan-out → peer review → chairman synthesis
- Session JSON artifacts for measurement
- Decision: build this as part of Sarge's scoping process, or start simpler?

---

## What Sarge Must Do (Capabilities)

### C1: Interview David
- Take a raw idea ("Sage should recommend what to work on next")
- Ask 2-3 targeted questions (why, for whom, what does done look like)
- Use short codes (A1, B2) for mobile-friendly replies
- Capture the hill before doing any recon

### C2: Codebase Recon
- Read target project's `.studio/` files (project.json, context.md, features.yaml, SCHEMA.md)
- Search codebase for relevant code (real paths, real functions, real columns)
- Check existing GitHub issues/PRs for related work
- Present findings with clear recommendation, not a data dump

### C3: Write Scope Brief
- Produce a GitHub issue in commander's intent format
- Every claim grounded in recon (verified file paths, real schema columns)
- No implementation details, no prescriptive logic
- Apply the Algorithm: question every requirement, delete what you can, simplify what remains

### C4: Board Management
- Create issues on the correct repo (`gh issue create --repo <repo>`)
- Move items between board columns (Parking → Pitch → Scope → Backlog)
- Comment on issues with protocol prefixes (SPEC-UPDATED, DECISION-NEEDED)
- Track round-trips (escalate after 2 failed cycles)

### C5: Pipeline Overview
- Show board state (items per column, per project)
- Identify blockers (stuck items, failing CI, stale PRs)
- Surface what needs David's attention vs what's flowing
- Weekly/sprint summary

### C6: Parking Policy
- **Parking is David's domain. Sarge does NOT touch Parking.**
- Parking is a holding pen. David moves items to Pitch when ready, or kills them.
- If David asks Sarge to look at a specific Parking item, investigate it. But never proactively sweep Parking.

---

## Eligible Projects

See `~/Projects/.index.json` for the full project registry. Projects with a `board` field are eligible.

Priority order is set in `~/Projects/.index.json` (per-project `priority` field). Do not hardcode here — read the registry.

<!-- V0.5 scrub: removed personal business-priority disclosure block. The operator's
     own ranking belongs in their own .index.json, not in the bundled docs. -->


---

## How David Works (Design Constraints)

- **Mobile-first.** Texts from phone. Short codes for replies.
- **Decision-maker, not executor.** Approve/reject/redirect.
- **PM thinking partner.** Wants someone to challenge assumptions, not just take orders.
- **Direct feedback.** No hedging, no gentle suggestions.
- **The Algorithm at every stage:** Question → Delete → Simplify → Accelerate → Automate last.
- **Commander's intent for all issues.** Goal and constraints go down; implementation decisions stay with the builder.

---

## Architecture Decision: Agent, Not Script

Sarge should be a **Claude Code agent** (`.claude/agents/sarge.md`), not a shell script. Why:

1. **Interactive.** Sarge needs to interview David, ask follow-ups, present options.
2. **Multi-tool.** Needs Glob, Grep, Read (recon), Bash (gh CLI, board management), Agent (spawn sub-agents for parallel recon).
3. **Contextual.** Needs to read project .studio/ files, understand the board state, reference previous decisions.
4. **Conversational.** David talks to Sarge like a PM, not a CLI.

The current agent definition at `.claude/agents/sarge.md` is a stub — 56 lines, issue-writer only. It needs to become the full PM agent.

The foreman enrichment phase (`sarge-enrich.sh`) stays as-is — it's the automated reactive loop. Sarge-the-agent is the proactive layer on top.

---

## Key Files to Read/Modify

### Sarge (rewrite)
- `/Users/jorjani/Projects/.claude/agents/sarge.md` — **REWRITE** as full PM agent
- `/Users/jorjani/Projects/sarge/CLAUDE.md` — Update to match new agent capabilities
- `/Users/jorjani/Projects/sarge/agent-team-spec.md` — Reference (don't modify)
- `/Users/jorjani/Projects/sarge/plans/council-implementation.md` — Reference for future council integration

### Foreman (read-only, understand how it works)
- `/Users/jorjani/Projects/foreman/CLAUDE.md` — Agent team process, safety, eligible projects
- `/Users/jorjani/Projects/foreman/config/board-ids.sh` — Board constants and helpers
- `/Users/jorjani/Projects/foreman/phases/triage.sh` — How Foreman triages (what Sarge feeds)
- `/Users/jorjani/Projects/foreman/phases/sarge-enrich.sh` — Reactive enrichment loop
- `/Users/jorjani/Projects/foreman/phases/pitch-to-scope.sh` — Mothballed, reference for what was tried
- `/Users/jorjani/Projects/foreman/prompts/triage.md` — What Foreman checks when triaging
- `/Users/jorjani/Projects/foreman/metrics/incidents.md` — What has broken

### Project context (Sarge reads these during recon)
- `{project}/.studio/project.json` — What is this project
- `{project}/.studio/context.md` — Architecture and patterns
- `{project}/.studio/features.yaml` — Feature → code mapping
- `{project}/.studio/SCHEMA.md` — Enum reference, DB constraints
- `{project}/CLAUDE.md` or `{project}/.claude/CLAUDE.md` — Project instructions

### Root config
- `/Users/jorjani/Projects/.index.json` — Project registry with aliases
- `/Users/jorjani/Projects/PRIORITIES.md` — David's priority stack
- `/Users/jorjani/Projects/CLAUDE.md` — Root instructions (issue format, worktree rules)

---

## Current Board State (Apr 3)

| Column | Count | Items |
|--------|-------|-------|
| Parking | 33 | Mostly product-studio (17) + scattered Jobber/Sage |
| Pitch | 1 | Jobber#6 (Unified Job Extraction) |
| Scope | 9 | Jobber#22, #56, #78, #111; Sage#84, #85, #92; + 2 new from today |
| Backlog | 2 | Jobber#21, Sage#72 |
| Ready | 3 | Sage#73, #83, #103 |
| Done | 15 | Shipped in last 8 days |

---

## Incident History (What Has Broken)

9 incidents in 8 days. Categories:
- **stall** (3): Board sync issues, triage deadlock. Both fixed.
- **infra** (3): First-run bugs, syntax errors, parse failures. All different.
- **runaway** (1): Build loop uncapped. Now capped at 10/day + 3-failure per ticket.
- **collision** (1): Two PRs conflicted on migrations. Speculative fix merged.
- **orphan** (1): Comment format changed, old issues invisible. Backward compat added.

**Key lesson:** Over-responded to one orphaned-comment incident with a 100-line registry + 7-step checklist. The actual fix was 2 lines. Process should be proportional to incident frequency. Check `metrics/incidents.md` before building safeguards.

---

## What Good Looks Like

### Week 1 (Build Sarge Agent)
- [ ] Rewrite `.claude/agents/sarge.md` with full capabilities (C1-C6)
- [ ] Test: David invokes Sarge, drops an idea, Sarge interviews, runs recon, creates scoped issue
- [ ] Test: Sarge shows pipeline overview with actionable recommendations
- [ ] Test: Sarge triages 5 Parking items, recommends promote/kill

### Week 2 (Fix the Pipeline)
- [ ] Diagnose Scope deadlock (why 9 items stuck with NEEDS-SPEC)
- [ ] Clear the backlog: either enrich stuck items or kill/park them
- [ ] Run Sarge on 3 real ideas end-to-end (Pitch → Scoped issue)
- [ ] Foreman builds from Sarge's specs without NEEDS-SPEC round-trips

### Week 3 (Cadence)
- [ ] Sarge runs Monday/Thursday: board review + David's priority sync
- [ ] Parking < 15 items (triaged the 33-item pile)
- [ ] Scope → Ready pipeline takes < 48h for well-understood items
- [ ] David's weekly interaction: 2 interview sessions + approve/reject decisions

### Stretch (Council Pattern)
- [ ] Implement council deliberation for complex scoping
- [ ] Session JSON artifacts committed for measurement
- [ ] Compare: council-scoped issues vs single-pass — do they pass triage faster?

---

## Open Questions for David

1. **Council now or later?** The 5-advisor pattern is designed. Build it into Sarge V1, or start with single-pass scoping and add council as an upgrade?

2. **Sarge cadence:** Interactive-only (David invokes when needed) or also scheduled (Monday/Thursday board review)?

3. ~~Parking triage authority~~ **RESOLVED:** Parking is David's domain. Sarge does not touch Parking. Ever.

4. **Priority override:** When project priorities conflict with what's stuck on the board, who wins? (e.g., Sage is P1 but Jobber has 4 stuck Scope items)
