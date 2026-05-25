# Foreman Pipeline

The autonomous development pipeline for Qatalyst projects.

## How It Works

Three layers:
- **David** — sets direction, approves scope, makes decisions
- **Sarge** — PM layer. Shapes work from Pitch → Ready. Runs daily digest at 10am via Cowork.
- **Foreman** — Builder layer. Ships work from Ready → Done. Runs 5x/day via launchd.

---

## The Board

Shape Up flow on GitHub Projects board #5:

```
Parking → Pitch → Scope → Ready → In Progress → In Review → Verify → Done
```

| Column | Owner | What happens here |
|--------|-------|-------------------|
| Parking | David | Graveyard. Nothing moves out without David requesting it. |
| Pitch | Sarge + David | Raw idea captured. Just goal + why. |
| Scope | Sarge | Recon done, acceptance criteria written, "done" defined. |
| Ready | Triage → Foreman | Foreman's inbox. Triage checks deps + spec, promotes when clear. |
| In Progress | Foreman | Foreman is building (auto/ branch, Claude Code). |
| In Review | Foreman | PR open, CI running, code review. |
| Verify | Foreman | Post-merge verification against acceptance criteria. |
| Done | Foreman | Shipped and verified. |

---

## Gateway Checks

Nothing moves right without meeting its gate.

**G1 Parking → Pitch:** Problem statement exists, not duplicate, aligns with priorities.

**G2 Pitch → Scope:** Interview done, recon report with findings and options. Algorithm pass: what was questioned, deleted, simplified.

**G3 Scope → Ready:** Triage checks two gates: (1) Dependency gate -- if "Depends on #N" exists and any dep is still open, the issue stays in Scope (not a spec problem, just waiting). (2) Spec gate -- issue contract complete (Goal/AC/Context/OOS/Size), AC testable, size estimated. Ready checklist passes (see `config/ready-templates.md`).

**G4 Ready → In Progress:** Foreman posts plan before coding. Appetite set (XS=1hr, S=1day, M=3days, L=5days).

**G5 In Progress → In Review:** PR exists. CI passes. Diff within scope bounds.

**G6 In Review → Verify:** Merged to main. Deployed (if applicable).

**G7 Verify → Done:** Verified against AC. If failed → issue reopened, moved back to Scope.

---

## Ready Checklist

Full checklist in `config/ready-templates.md`. Summary:

**Base (every item):**
- [ ] Goal is one sentence
- [ ] Acceptance criteria numbered and testable
- [ ] "Done" defined — what does a human verify?
- [ ] Size estimated (XS/S/M/L)
- [ ] Files affected listed

**Add for UI changes:** Current screenshot or description of what exists. Expected behavior described.

**Add for Data Model:** Schema change, migration strategy, existing data impact.

**Add for Integration:** External API docs, auth identified, failure mode described.

---

## Sarge (PM Layer)

Sarge lives in `getqatalyst/sarge`. It owns all PM work: interviewing David, codebase recon, writing scope briefs, curating the board from Pitch → Ready.

**Foreman's role in the PM flow** is limited to two mechanical phases:
- `phases/auto-enrich.sh` — fills spec gaps (file paths, schema refs, size) when Triage posts `NEEDS-SPEC:`. No product judgment. Escalates to David after 2 failed round-trips.
- `phases/pipeline-digest.sh` — daily board digest: stuck items, Ready feed, auto-actions (close stale, promote shipped). Posts as GitHub issue (label: `pipeline-digest`).

---

## Foreman (Builder Layer)

**Runs via launchd** 5x/day at 00:15, 05:00, 10:00, 14:45, 19:30.

**Phase order per run (loops until no work, max 3 cycles):**
1. Verify — check merged PRs against AC
2. Review — review open PRs, merge clean auto/ branches
3. CI-Alert — flag CI failures
4. Build — pick up Ready tickets, create worktrees, run Claude Code
5. Triage — check Scope items, promote to Ready if checklist passes

**Post-loop (once per run):**
6. Auto-Enrich — mechanically fill NEEDS-SPEC gaps with codebase context (15 min timeout)
7. Collect-Metrics
8. Self-Improve (odd days only)

**Circuit breakers:**
- 3 consecutive build failures → back to Scope with log
- Scope gap detected → back to Scope immediately
- 2 round-trips between Foreman and Sarge → escalate to David
- Daily build cap: 10 builds max per full run

### Running

```bash
# Full daily run
./orchestrator.sh

# Single phase
./orchestrator.sh verify
./orchestrator.sh review
./orchestrator.sh build
./orchestrator.sh triage
./orchestrator.sh auto-enrich
./orchestrator.sh self-improve

# Intake: idea -> spec'd issue
./orchestrator.sh intake getqatalyst/Jobber "add duplicate detection before importing jobs"
./orchestrator.sh intake getqatalyst/Sage "show token usage per conversation in the UI"

# Board snapshot
./orchestrator.sh status
```

### Managing launchd

```bash
# Check if loaded
launchctl list | grep foreman

# Reload after editing plist
launchctl unload ~/Library/LaunchAgents/com.jorjani.foreman.plist
launchctl load ~/Library/LaunchAgents/com.jorjani.foreman.plist

# Manual trigger
launchctl start com.jorjani.foreman
```

---

## Comment Prefix Bus

Phases communicate via GitHub issue comments with these prefixes.

| Prefix | Posted by | Read by |
|--------|-----------|---------|
| `NEEDS-SPEC:` | triage | triage, auto-enrich |
| `SPEC-UPDATED:` | auto-enrich | triage, auto-enrich |
| `ESCALATION:` | auto-enrich | auto-enrich |
| `Automated triage:` | triage | triage |
| `Automated review:` | review | review |
| `Automated repair:` | repair | review |
| `Automated verification:` | verify | verify |

> Before changing a prefix: `grep -rn 'PREFIX' phases/` and update all hits in one PR. See `metrics/incidents.md` for what has broken in the past.

---

## The Algorithm

Applied at every scoping stage:
1. Question every requirement — why does this need to exist?
2. Delete anything you can — if you're not adding things back, you're not deleting enough
3. Simplify what remains
4. Accelerate cycle time
5. Automate last — never automate a broken process

---

## Agent Task Sizing

Tasks follow a phased model: **Recon → Plan → Execute → Verify**. Each phase is its own task.

| Size | Turns | Scope |
|------|-------|-------|
| XS | 1-5 | One command, one file read |
| S | 5-20 | One file under 1,000 lines |
| M | 20-50 | Multi-file, under 1,000 lines total |
| L | Phase it | Break into Recon → Plan → Execute → Verify |

Hard rule: never send a single file over 2,000 lines to one task.

---

## Board Column IDs

Defined in `config/board-ids.sh`. These IDs change whenever the board schema is modified — always update all downstream consumers (this config, Sarge task prompt, memory files) after any field change.

---

## Repos

| Repo | Priority | Description |
|------|----------|-------------|
| getqatalyst/Sage | P1 | LinkedIn content tool |
| getqatalyst/coaches | P2 | Coaching platform |
| getqatalyst/Jobber | P3 | Curated job board |
| getqatalyst/product-studio | P4 | Product Studio |
| getqatalyst/foreman | — | This repo (pipeline orchestrator) |

---

## Structure

```
foreman/
  orchestrator.sh             # Entry point
  phases/
    intake.sh                 # Phase 0: idea -> spec'd issue (interactive)
    verify.sh                 # Phase 1: verify merged PRs against AC
    review.sh                 # Phase 2: review + merge open PRs
    build.sh                  # Phase 3: pick up Ready tickets
    build-ticket.sh           # Per-ticket build executor (uses worktrees)
    triage.sh                 # Phase 4: triage Scope tickets (dep gate + spec check)
    auto-enrich.sh            # Phase 5: mechanically fill NEEDS-SPEC gaps (see getqatalyst/sarge for full PM scoping)
    ci-alert.sh               # Post-review: detect CI pile-ups
    collect-metrics.sh        # Parse daily logs into metrics/YYYY-MM-DD.json
    self-improve.sh           # Phase 6: analyze metrics, propose prompt changes
    status.sh                 # Board snapshot
  prompts/
    intake.md
    build.md
    review.md
    triage.md
    auto-enrich.md
    self-improve.md
  config/
    board-ids.sh              # GitHub project board constants
    ready-templates.md        # Ready checklist by item type
    schedule.plist            # launchd schedule
  metrics/                    # Structured JSON metrics + experiment tracker
  results/                    # Debug logs (7-day retention)
```
