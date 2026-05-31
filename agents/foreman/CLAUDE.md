# Foreman

Autonomous daily orchestrator. Reviews open PRs and merges clean ones, then picks up Ready tickets from the GitHub project board and builds new PRs.

## Setup (one-time per clone)

```bash
git config core.hooksPath .githooks
```

Activates the versioned pre-commit policy under `.githooks/` (blocks direct commits to main except `specs/` and `artifacts/`, per `Projects/CLAUDE.md § Spec File Commits`). Without this, each clone runs whatever stale hook lives in `.git/hooks/` — drifts silently between machines (M2 vs M5). Or run `bash scripts/setup.sh`.

## How It Works

0. **Intake phase** (interactive): Takes a raw idea + target repo, reads project `design-system/` context, produces a spec'd GitHub issue, and adds it to project board #5 in Pitch status.
1. **Verify phase** (daily): Confirms merged PRs work in deployed environments. Closes linked issues on success, creates bug tickets on failure.
1b. **Inspect + Code-Review phases** (daily, parallel siblings after Verify, before Review): Inspect (Inspector v1, foreman#209) gates Verify→Done. Per item: a refactor-allowlist diff (`config|lib|prompts|specs|docs|.studio`) or a wired lazy-init producer auto-promotes instantly with no LLM; otherwise the file-extension split-verify classifier and an LLM fallback (Haiku tier classifier + Sonnet judge over captured HTTP/log evidence) render PASS/FAIL/SKIP. A behavior PASS soaks `INSPECT_HOLD_DAYS` (7) in Verify — `INSPECTOR: HOLDING (Nd/7d)` once a day — before promoting to Done. `INSPECT_DISABLE_LLM=1` drops the LLM path (deterministic classes still run); the LLM path stops after `INSPECT_BUDGET` spend. Posts `INSPECTOR:`. Code-Review dispatches the `code-reviewer` subagent against open PRs missing a `REVIEWER:` comment, posts findings (or `REVIEWER: LGTM`), then (foreman#210) runs the auto-merge gate on non-`auto/*` PRs: a clean verdict + allowlisted author (`CODE_REVIEW_MERGE_ALLOWLIST`, default `jorjani`) + repo opt-in (`board.code_review_automerge`, foreman itself defaults on) + green CI + an LLM `AC-MATCH` verdict squash-merges the PR and moves the linked issue to Verify; `AC-MISMATCH` posts `DECISION-NEEDED:` on the issue and leaves the PR open. `auto/*` PRs are untouched — `phases/review.sh` still owns that path. Kill switch: `CODE_REVIEW_DISABLE_AUTOMERGE=1`. The autonomous review phase (next) may consume `REVIEWER:` comments when deciding.
2. **Review phase** (daily): Fetches open PRs across eligible repos. Runs Claude review (14-point checklist). Auto-merges clean `auto/` PRs. Human PRs get review only. CI pile-up alerting runs after review.
3. **Build phase** (daily): Fetches "Ready" tickets from project board #5. Creates branch in isolated worktree, implements, tests, ships PR. After opening a PR: comments on the issue with the PR link, moves the issue to "In Review" on the project board. If stuck, comments on the issue. Pre-claim filters (counted, not stalls): skip when the repo has `board.foreman_build=false` in `~/Projects/.index.json`, and skip when the repo already has `WIP_LIMIT` (3) open `auto/` PRs.
4. **Triage phase** (daily): Fetches "Scope" tickets from project board #5. Checks cross-issue dependencies first (skips if blocked by open deps). Enforces issue contract format (Goal/AC/Context/OOS). Promotes buildable tickets to "Ready", comments `NEEDS-SPEC:` on incomplete ones.
4b. **Sarge-Review phase** (daily, post-loop): Proactive recon on Scope items. Fetches Scope tickets whose repo has `agents.sarge` includes `"scope"` in `~/Projects/.index.json`, invokes the existing Sarge prompt (`prompts/sarge-review.md`), and dispatches the JSON response (`enrich`/`ready` → promote to Backlog, `decision_needed` → DECISION-NEEDED comment, leave at Scope). Promotes items with an existing `specs/<num>-*.md` doc straight to Backlog (a committed spec doc means scoping is done); skips items with a SPEC-UPDATED bot comment within the last 24h. Caps at 3 items per run; deferred items roll to the next run and are named in the per-run log. Also available as `./orchestrator.sh sarge-review`
4c. **Sarge-Pitch phase** (daily, post-loop): First-pass Sarge recon on Pitch items. Fetches Pitch tickets whose repo has `agents.sarge` includes `"scope"` (pitch reuses the scope flag — pitch is upstream of scope), invokes `prompts/sarge-pitch.md`, and posts a single `SARGE-DRAFT:` comment with questions for David, an ASCII wireframe for UI tickets, and a draft brief. Never moves the card off Pitch — David promotes to Scope manually. Re-fires whenever the issue body or comment thread changes (dedup-on-identical-body via `comment_dedup_or_escalate`). Caps at 3 items per run; deferred items roll forward and are named in the per-run log. Also available as `./orchestrator.sh sarge-pitch`
5. **Auto-enrich phase** (daily, post-loop): Scans for `NEEDS-SPEC:` comments, mechanically fills spec gaps (file paths, schema refs, size estimates). Escalates to David after 3 failed round-trips (disagreement loop) or on the first malformed Claude response (parse failure, posts DECISION-NEEDED with dedup). Full PM scoping lives in Sarge (getqatalyst/sarge). Also available as `./orchestrator.sh auto-enrich`
6. **Cleanup phase** (daily, post-loop): Prunes stale local branches across all eligible repos. Tier 1: deletes branches merged into main. Tier 2: deletes branches whose GitHub PR is merged or closed. Tier 3: flags orphaned branches >14 days, auto-deletes at 30+. Also available as `./orchestrator.sh cleanup`
7. **Ghost-sweep phase** (daily, post-loop): Demotes In Progress items that have no `CLAIMED` comment from any builder. Default threshold: 4 hours idle in In Progress; per-repo override via `GHOST_SWEEP_HOURS_<SHORT_UPPER>` env var (global via `GHOST_SWEEP_HOURS`). Items with an open `auto/issue-<N>-*` PR are skipped (mid-handoff to In Review). Log line per demotion: `GHOST-DEMOTE: <repo>#<num> (no CLAIMED for <X> hours)`. Also available as `./orchestrator.sh ghost-sweep`
7a1. **Orphan-rescue phase** (daily, post-loop, before stranded-sweep): Publishes `auto/` builds stranded after commit but before push. When the wall-clock killer (`lib/bounded.sh`) SIGKILLs the build process group after `claude` already committed + wrote `.pr-body.md`, the post-claude push/PR-create never runs. Orphan-rescue scans `/tmp/foreman-build-<Repo>-<N>` worktrees for the six-point signature (idle, `auto/issue-N-*` branch, commits ahead, no remote branch, **`.pr-body.md` present**) and pushes + opens the PR + moves the issue to In Review. The `.pr-body.md`-presence check is both the orphan-after-commit discriminator and the foreman#238 verification-passed signal — without it the worktree is left for stranded-sweep to requeue. On push/PR-create failure it falls through to `mark_orphan` (`needs-verification/<branch>` per #238); after 3 consecutive failures on the same orphan the issue is labelled `blocked`. Also available as `./orchestrator.sh orphan-rescue`; synthesize + test via `./orchestrator.sh test-orphan-rescue <repo> <issue>`.
7a2. **Stranded-sweep phase** (daily, post-loop): Detects orphaned `auto/issue-N-*` worktrees at `/tmp/foreman-build-<Repo>-<N>` whose build process died after `CLAIMED:` but before push (local commits present, no remote branch, idle for ≥ `STRANDED_AGE_MIN` minutes, default 30). Posts `STALLED:` with the worktree path + branch, moves the issue back to Ready, removes the worktree so the next build cycle re-picks the ticket. Concrete incident motivating this phase: Sage#394 stalled silently for ~4.8h on 2026-05-16. Complements ghost-sweep (which skips items that already have CLAIMED) and cleanup.sh (which skips unmerged branches). Also available as `./orchestrator.sh stranded-sweep`
7b. **Janitor phase** (daily, post-loop): Sweeps stranded CLOSED-issue cards to Parking. Any card whose issue is closed but whose board column is not in `{Done, Verify, Parking}` is moved to Parking. Never moves to Done (reserved for Inspector — see `phases/inspect.sh`). Never touches Verify (David's review queue). Per-fire log line: `[janitor] swept N: <repo>#<num> (<col>→Parking), ...` (or `[janitor] swept 0 cards (board clean)`). Also available as `./orchestrator.sh janitor`
8. **Self-improve phase** (every other day): Analyzes pipeline metrics, identifies failure patterns, proposes prompt changes as auto/ PRs. Evaluates previous experiments (keep if metrics improved, revert if degraded). One experiment at a time.

**Daily loop:** Verify → [Inspect ‖ Code-Review] → Review (+CI alert) → Build → Triage (loop) → Sarge-Review → Sarge-Pitch → Auto-Enrich → Cleanup → Ghost-Sweep → Orphan-Rescue → Stranded-Sweep → Janitor → Metrics → Self-Improve (odd days)
**Manual triggers:** Intake
**Full pipeline:** Idea → Pitch → Scope (Sarge recon, getqatalyst/sarge) → Triage (dep gate + spec check) → Ready → Build → PR → Review → Merge → Verify → Done

GitHub is the interface. PRs, reviews, issue comments. Result files in `results/` are debug logs only.

**Board operations:** Use `gh project item-edit` with an explicit `--project-id "$PROJECT_ID"` (the `PVT_…` node ID), plus `--id`, `--field-id`, and `--single-select-option-id` — the form `move_board_item` in `config/board-ids.sh` uses, and the standard across `phases/triage.sh`, `phases/sarge-review.sh`, and `phases/verify.sh`. Passing the user-facing project *number* (`5`) instead of the `PVT_…` node ID makes `item-edit` fail silently — always pass `$PROJECT_ID`. All Project #5 field and option IDs are canonical in `config/board-ids.sh`. Source that file to get exported shell constants; add any new fields there. `~/Projects/.index.json` only marks board eligibility per project (`board.project_number` + `board.org`); it no longer duplicates IDs, which previously drifted silently. Run `validate_board_ids` from the script on preflight to detect upstream drift on Status, Priority, and Size. Board columns:
- **Parking** -- David's holding pen
- **Pitch** -- New issues, not yet scoped
- **Scope** -- Being scoped by Sarge
- **Backlog** -- Scoped, not yet prioritized
- **Ready** -- Passes triage, ready for Foreman to build
- **In Progress / In Review / Verify** -- Foreman's build cycle
- **Done** -- Shipped and verified

**Comment protocols:** Each phase header lists its `POSTS:` and `READS:`. Before changing a prefix: `grep -rn 'PREFIX' phases/`. Update all hits in one PR, handle backward compat. See `metrics/incidents.md` for what has actually broken.

## Structure

```
foreman/
  orchestrator.sh             # Entry point, runs phases in order
  phases/
    intake.sh                 # Phase 0: idea -> spec'd GitHub issue (interactive)
    verify.sh                 # Phase 1: verify merged PRs in deployments
    inspect.sh                # Phase 1b (parallel): Verify -> Done gate (Inspector)
    code-review.sh            # Phase 1b (parallel): dispatch code-reviewer subagent on open PRs
    review.sh                 # Phase 2: review + merge open PRs
    build.sh                  # Phase 3: pick up Ready tickets
    build-ticket.sh           # Per-ticket build executor (uses worktrees)
    triage.sh                 # Phase 4: triage Scope tickets (dep gate + spec check)
    sarge-review.sh           # Phase 4b: proactive Sarge recon on Scope items (cap 3/run)
    sarge-pitch.sh            # Phase 4c: first-pass Sarge draft on Pitch items (cap 3/run, no board move)
    auto-enrich.sh            # Phase 5: mechanically fill NEEDS-SPEC gaps (full PM scoping: getqatalyst/sarge)
    cleanup.sh                # Phase 6: prune stale local branches across repos
    ghost-sweep.sh            # Phase 6b: demote In Progress items lacking CLAIMED
    orphan-rescue.sh          # Phase 6b1: publish auto/ builds stranded after commit
    stranded-sweep.sh         # Phase 6b2: requeue orphaned auto/issue-N-* worktrees
    janitor.sh                # Phase 6c: sweep stranded CLOSED cards to Parking
    ci-alert.sh               # Post-review: detect CI pile-ups across repos
    collect-metrics.sh        # Parse daily logs into metrics/YYYY-MM-DD.json
    self-improve.sh           # Phase 7: autoresearch loop for prompt optimization
  prompts/
    intake.md                 # Idea-to-issue spec prompt (reads design-system/ context)
    build.md                  # Autonomous build prompt
    review.md                 # Autonomous PR review prompt
    triage.md                 # Triage evaluation prompt (enforces issue contract)
    auto-enrich.md            # Auto-enrich prompt (fills spec gaps mechanically)
    sarge-pitch.md            # First-pass Sarge prompt for Pitch items (questions + wireframe + brief)
    self-improve.md           # Meta-prompt: analyze metrics, propose prompt changes
  metrics/                    # Structured JSON metrics + experiment tracker
  config/
    schedule.plist             # launchd schedule (5x/day; cadence canonical here)
  scripts/
    start-remote.sh           # iPhone SSH trigger
  results/                    # Debug logs
```

## Running

```bash
# Full daily run (review + build + triage)
./orchestrator.sh

# Single phase
./orchestrator.sh review
./orchestrator.sh build
./orchestrator.sh triage
./orchestrator.sh self-improve
./orchestrator.sh auto-enrich

# Intake: idea -> spec'd issue
./orchestrator.sh intake getqatalyst/Jobber "add duplicate detection before importing jobs"
./orchestrator.sh intake getqatalyst/product-studio "show token usage per conversation in the UI"

# From iPhone via SSH
./scripts/start-remote.sh
```

## Managing

```bash
# Check if loaded
launchctl list | grep foreman

# Reload after editing plist
launchctl unload ~/Library/LaunchAgents/com.jorjani.foreman.plist
launchctl load ~/Library/LaunchAgents/com.jorjani.foreman.plist

# Manual trigger
launchctl start com.jorjani.foreman
```

## Agent Team Process
Foreman partners with Sarge (PM) and Inspector (verification). Inspector v1 ships as `phases/inspect.sh` (foreman#209) — gates Verify→Done via deterministic auto-promote classes, an LLM classify+judge fallback, and a 7-day soak on behavior PASSes. Browser/Playwright (T3) capture is deferred; UI-only cases still SKIP to David. Canonical roster in `~/Projects/_shared/agent-team.md`. Agents coordinate via GitHub issues before surfacing to David.

**Internal review flow:**
1. Sarge writes scope brief on issue → tags READY/NEEDS-INPUT/BLOCKED
2. Foreman reads brief, runs pre-build assessment, comments if concerns
3. Foreman builds → self-reviews PR → merges clean auto/ PRs
4. Post-merge: Foreman moves the issue to Verify. Inspector v1 (`phases/inspect.sh`) auto-promotes refactor-allowlist and lazy-init cases instantly and other behavior PASSes after a 7-day Verify soak; UI-only (T3) cases SKIP to David.

**Escalation to David only when:**
- Decision required (Sarge presents recon with recommendation)
- 2 round-trips between Foreman and Sarge without resolution
- 3 consecutive build failures or appetite exceeded
- Weekly digest (Mon/Thu)

**Stale PR policy:**
- Merge conflicts >3 days → close, issue returns to Scope
- No activity >7 days → close, issue returns to Ready for rebuild

## Safety

- Never pushes to main (always `auto/` branches)
- Per-phase model and budget caps live in `config/model-routing.sh` (single source of truth). Phase scripts source it; do not hardcode `--model` or `--max-budget-usd` values inline.
- Builds run in isolated worktrees (`/tmp/foreman-build-*`), never modify project directories
- Auto-merge only for `auto/` branches (agent's own PRs)
- CI must pass before merge
- Failed builds comment on the GitHub issue and clean up
- Idempotent (skips if already ran today)

## Lessons

- `gh project item-list --format json` returns Status but NOT custom fields like Priority.
  It also silently truncates at `--limit N` (we use 200). When you need pagination,
  Priority, or other custom fields, use `fetch_board_items` from `config/board-ids.sh`
  (GraphQL with cursor-based pagination).

- **Bash 3.2 (macOS default) does not support `declare -A`** (associative arrays). All
  foreman scripts run under `#!/bin/bash` which resolves to `/bin/bash` (locked at 3.2 by
  Apple). Use plain shell variables for shared config (e.g. `BUILD_MODEL=opus`, not
  `PHASE_MODEL[build]=opus`). The failure is silent under `bash -n` and surfaces only at
  runtime when the config is sourced.

- **Any new automated-comment prefix MUST go through `comment_dedup_or_escalate`**
  from `lib/comments.sh`. Detection without dedupe creates noise loops — sage#215
  collected 11 byte-identical BUILD-OVERSIZED comments across 3 days; sage#187
  fired duplicate SPEC-UPDATED + duplicate NEEDS-SPEC pairs within minutes. The
  helper scans the last 5 bot comments and skips identical bodies; on dedupe,
  surfaces a single ESCALATE-DEDUP mention to David and stays quiet.

- **Filtering repos by agent capability uses `lib/repos.sh` helpers.** Never
  inline JSON parsing of `agents.<agent>` in a phase script. Today: `eligible_repos`
  (agents.foreman ⊇ "build") and `sarge_eligible_repos` (agents.sarge ⊇ "scope").
  New (agent, verb) pair? Add a sibling function in `lib/repos.sh` named
  `<agent>_eligible_repos` (or `<verb>_eligible_repos` when the agent is foreman)
  following the same shape. Reason: #175 shipped `eligible_repos`, but `build.sh`
  kept its own inline copy until #N — five other phases used the helper while
  one outlier silently drifted. Inline parsers also bypass `REPOS_INDEX_JSON`
  override and break smoke tests like `scripts/test-sarge-eligible.sh`.

- **Shell-side JSON parsing in foreman uses `python3 -c`**, not `jq`. All 16+
  existing call sites (triage.sh, pipeline-digest.sh, sarge-review.sh, lib/repos.sh)
  follow this convention. Stay consistent unless the operation is non-trivial enough
  to warrant extracting a `.py` helper. Don't introduce a third parser.

- **Batch "centralize the constant" tickets into one PR.** Three tickets shipped
  on 2026-05-16 with the same shape — #244 (`lib/repos.sh`), #247 (`config/thresholds.sh`),
  #203 (`.index.json` codes) — each "extract a literal that drifted in N places to
  a single source." Per-ticket Foreman dispatch added overhead disproportionate to
  the change. When you spot two or more candidates of this class, file one umbrella
  ticket listing the literals + their target files, not one per literal. Inspector v1
  (scoped at foreman#209) will also auto-promote pure refactors via the
  `config|lib|prompts` allowlist, so batching clears the Verify queue in one pass.

- **`X=$(cmd 2>FILE)` gives you stderr-only on disk; stdout disappears into the
  variable.** If the diagnostic log file is expected to capture the full response,
  also `printf '%s\n' "$X" >> "$FILE"` after the call. sarge-review.sh shipped this
  bug — per-issue logs were 0 bytes for two weeks while the real response lived
  only in memory. Audit any `=$(.* 2>"$FILE")` site where FILE is referenced
  downstream for "diagnostic context."

- **Project status is the strongest build-eligibility signal.** `repo_foreman_build_enabled`
  in `lib/repos.sh` treats `status: archived|parked|inactive` in `.index.json` as
  a hard disable, overriding any explicit `board.foreman_build`. If you mark a
  project archived but leave a Ready ticket in its repo, Foreman will refuse to
  build it. Reason: the status flag is set when the project goes dormant; explicit
  `foreman_build` may have been set months earlier under different assumptions.

- **Foreman writes two log streams — grep both when reading evidence.**
  - `results/YYYY-MM-DD.log` — daily orchestrator narrative. Carries one-line
    per-phase summaries (`INSPECT: ... PASS`, `SARGE-REVIEW PHASE: scoped=3`,
    `CODE-REVIEW PHASE: reviewed=2 lgtm=0 findings=2`). Start here when
    investigating "did phase X run, what did it do."
  - `results/YYYY-MM-DD-<phase>-<n>.log` — per-record diagnostic file (one per
    item processed). Carries the raw claude transcript, parser errors, full
    response bodies. Drop in when the daily-log summary says SKIP/FAIL/PARSE
    and you need the why.
  - `results/inspector.log` — append-only JSONL across all Inspector runs (not
    date-keyed). The longest-running per-item record stream; query it when
    asking "what has Inspector seen across this column over weeks."
  - An empty per-record file means "phase ran clean" (post-#268).

- **Lazy-init telemetry needs a manual trigger if natural events fire rarely.**
  When a feature posts a signal only when an upstream condition occurs — #154
  (PROPOSE-MISS tracking issue, fires on self-improve misses), #238 (`mark_orphan`,
  fires on push-fail) — natural-event verification can take weeks or never happen.
  Two options: accept negative evidence (no fires = no failures = working, but
  unprovable positively), or ship a `./orchestrator.sh test-<feature>` companion
  that synthesizes the upstream condition. Rule of thumb: if natural triggers
  fire ≥1×/week, observation suffices; <1×/week, ship the test command alongside
  the feature. Inspector v1 (foreman#209) will accept code-presence + grep-able
  anchor as positive evidence so this isn't load-bearing for verification — but
  it's still faster and more convincing than waiting for the universe.

## Eligible Projects

Read `~/Projects/.index.json` for the full project registry. Projects with a `board` field are eligible for board work.

Priority order is defined by the `priority` field in `.index.json` (lower = higher priority). Foreman itself is self-improve only.

## Design System Awareness

UI tickets reference tokens by name (`primary`, `surface`, `on-surface`), not by hex value. Each project's canonical token source is `{project}/design-system/design.md` (YAML frontmatter). Reference projects: sage, jobber, coaches, reap.

When building a UI ticket, read the project's `design-system/design.md` frontmatter for tokens before generating CSS or component code. Don't invent palette values; if the file is missing or incomplete, the ticket should specify what to add. Long-form recipes (per-page component specs) live in companion `brand-guidelines.md` files when present.
