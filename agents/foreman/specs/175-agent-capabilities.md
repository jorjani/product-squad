---
issue: 175
status: shipped
---

# foreman#175 — Per-project agent capability schema

Issue: https://github.com/getqatalyst/foreman/issues/175

## Action vocabulary

Canonical verbs for `agents.<agent>` arrays in `~/Projects/.index.json`. One verb per distinct phase-shaped action that selects a project list. Verbs that operate on a fixed/cross-cutting list (cleanup, alert, metrics, self-improve) are intentionally OUT of v1 — they are not gated per-repo today.

| Verb | Definition | Phase / surface | First consumer |
|---|---|---|---|
| `scope` | Pitch → Scope grounding (interview, recon, brief) | `sarge` agent | Sarge `C0` filter |
| `build` | Pick up Ready, branch + ship PR | `foreman/phases/build.sh` (Ready loop), `build-ticket.sh` | build.sh (this ticket) |
| `review` | Read open PRs, run checklist, decide merge/repair | `foreman/phases/review.sh` | review.sh |
| `merge` | Auto-merge clean `auto/` PRs after review | `foreman/phases/review.sh` (post-review action) | review.sh |
| `triage` | Scope → Ready promotion via 6 criteria | `foreman/phases/triage.sh` | triage.sh |
| `digest` | Daily Foreman Feed listing Ready items per repo | `foreman/phases/pipeline-digest.sh` | digest's Ready-feed query |
| `verify` | Confirm merged PR works in deployed environment | `foreman/phases/verify.sh` | verify.sh |
| `enrich` | Mechanically fill `NEEDS-SPEC:` gaps on Scope items | `foreman/phases/auto-enrich.sh` | auto-enrich.sh |
| `intake` | Interactive raw-idea → spec'd issue | `foreman/phases/intake.sh` | intake.sh |
| `repair` | Fix review findings on an existing auto/ PR | `foreman/phases/repair.sh` | repair.sh |

Out of v1 (operate on cross-cutting fixed lists, not per-repo capability gates):

- `cleanup` — `phases/cleanup.sh` runs branch pruning across 9 repos including `mastra-server`, `athena`, `profilepulse` (broader than board-eligible).
- `alert` — `phases/ci-alert.sh` + `lib/stall.sh` operate on a hardcoded `STALL_REPOS` set; alerting is global, not gated.
- `metrics` — `phases/collect-metrics.sh` parses today's log; not per-repo.
- `self-improve` — `phases/self-improve.sh` is `getqatalyst/foreman` only; trivially gated by single-repo identity.

If a future need arises (e.g., suppressing CI alerts for a repo where Foreman doesn't merge), promote `alert` from cross-cutting to per-repo at that point. KISS; do not pre-add unused verbs.

## Per-project canonical values

Audit derived from current ground-truth: `foreman/phases/build.sh:11` (`ELIGIBLE_REPOS`), `phases/triage.sh:13`, `phases/auto-enrich.sh:17`, `phases/verify.sh:15`, `phases/review.sh:30`, `phases/intake.sh:22-26`, `phases/pipeline-digest.sh:91` (BLOCKER_REPOS), `phases/ci-alert.sh:11`. Eight projects today have a `board.project_number` entry in `.index.json`.

| Project | repo | `agents.sarge` | `agents.foreman` | Notes |
|---|---|---|---|---|
| sage | `getqatalyst/Sage` | `["scope"]` | `["build", "review", "merge", "triage", "digest", "verify", "enrich", "intake", "repair"]` | Full set today |
| coaches | `getqatalyst/coaches` | `["scope"]` | `["build", "review", "merge", "triage", "digest", "verify", "enrich", "repair"]` | Full set today; no `intake` (not in `intake.sh` switch) |
| jobber | `getqatalyst/Jobber` | `["scope"]` | `["build", "review", "merge", "triage", "digest", "verify", "enrich", "intake", "repair"]` | Full set today; future: drop `build`, `merge`, `intake` when separate dev arrives |
| product-studio | `getqatalyst/product-studio` | `["scope"]` | `["build", "review", "merge", "triage", "digest", "verify", "enrich", "intake", "repair"]` | Full set today |
| mastra-server | `getqatalyst/mastra-server` | `["scope"]` | `[]` | Board entry exists but absent from every phase eligibility list. Mastra ships through manual ops today. |
| reap | `getqatalyst/reap` | `["scope"]` | `["build", "review", "merge", "triage", "digest", "verify", "enrich", "intake", "repair"]` | Full set today |
| sourcerer | `getqatalyst/sourcerer` | `["scope"]` | `["review", "triage", "digest", "verify", "enrich"]` | **No `build`, no `merge`, no `intake`, no `repair`.** Separate developer owns shipping. Today's symptom: Ready tickets surface STALL noise. |
| foreman | `getqatalyst/foreman` | `["scope"]` | `["build", "review", "merge", "triage", "digest", "verify", "enrich", "intake", "repair"]` | Self-improve. Already in build's eligibility today. |

`mastra-server` discovery: it has a `board.project_number` in `.index.json` but is absent from `build.sh`, `triage.sh`, `auto-enrich.sh`, `verify.sh`, `intake.sh`, `pipeline-digest.sh`. Effective state today is "board-visible, agent-untouched". `agents.foreman: []` captures this honestly. If someone later wants Foreman to act on mastra-server, they flip values; no shell edit needed. Sarge's `["scope"]` reflects that Sarge can scope mastra-server tickets when they show up.

## Next 2 consumers to migrate (followups, not bundled)

1. **`foreman/phases/triage.sh:13`** — same `ELIGIBLE_REPOS` shape as build.sh, gates Scope → Ready promotion. Skipping triage on a repo means tickets sit in Scope forever; Sarge already handles sourcerer's Scope manually, so capability `triage` controls whether Foreman's automated triage runs. Highest-leverage second consumer because the migration pattern from build.sh transfers verbatim.

2. **`foreman/lib/stall.sh:15`** (`STALL_REPOS`) and **`foreman/phases/build.sh:45`** (the `BUILD PHASE: No Ready tickets found` log line that triggers `notify_stall` upstream). Today's exact symptom — sourcerer Ready tickets producing `STALL: N in Ready, no progress` Slack alerts — disappears when stall counts only Ready items in repos whose `agents.foreman` contains `build`. Either filter the build.sh ticket query upstream of the stall denominator, or have `count_ready_items` accept a capability filter. Same pattern; second highest leverage.

Out of scope here, file as separate tickets when each is next touched:

- `phases/auto-enrich.sh:17` (eligible enrichment list)
- `phases/verify.sh:15` (eligible verify list)
- `phases/intake.sh:22-26` (intake repo switch)
- `phases/pipeline-digest.sh:91` (`BLOCKER_REPOS` for CI scan)
- `phases/ci-alert.sh:11` (`REPOS` for pile-up scan)
- `phases/cleanup.sh:46` (broader than board; `cleanup` verb intentionally not in v1 vocab)

## Reading the schema (build.sh consumer pattern)

After migration, `build.sh` reads from `.index.json` instead of the hardcoded string. The hardcoded `ELIGIBLE_REPOS=...` line at `build.sh:11` is replaced with a Python lookup against `~/Projects/.index.json` that selects projects whose `agents.foreman` array contains `"build"`. Same shell location, different source.

## Shipped state

- `phases/build.sh:14-24` derives `ELIGIBLE_REPOS` from `~/Projects/.index.json` (`agents.foreman` contains `"build"`).
- `~/Projects/.index.json`: all 8 board-eligible projects carry an `agents` map matching the audit table above. Projects without a board entry intentionally have `agents: {}`.
- `~/Projects/_shared/agent-team.md` § Action Vocabulary canonicalizes the verb list and points consumers at this spec.
