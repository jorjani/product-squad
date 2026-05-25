# Inspector v1 — Plan & Sequencing

**Status:** plan, no code yet. v1 is the next Inspector build (no waiting on calibration gates).
**Driving epic:** getqatalyst/foreman#106
**v0 ticket (shipped):** getqatalyst/foreman#201 (PR #202, merged 2026-05-08)
**Recon:** [`inspector-recon.md`](inspector-recon.md) (option matrix)

---

## Purpose

This doc answers three questions:

1. **What is Foreman's boundary?** (and why everything past it belongs to Inspector)
2. **What does v1 do that v0 doesn't?** (scope delta from B → C)
3. **What does v0's run log tell us about how v1 is built?** (calibration shapes priorities, not go/no-go)

Sarge reads this before filing the v1 issue. David reads this to confirm the boundary and pick the open questions.

---

## Foreman's boundary

**Current state (today):** Foreman runs Phases 0-7 per `foreman/CLAUDE.md`, including Phase 1 `verify.sh` which smoke-tests merged PRs in deployed environments. v0 shipped Inspector as a separate phase that runs *after* verify.sh and decides Verify → Done; verify.sh stays in Foreman's loop. Inspector consumes its signal but does not yet own the smoke test.

**Target state (post-v1):** Foreman's loop ends at review/merge. Everything past merge is Inspector's territory (or David's, when Inspector punts with SKIP).

- ✓ Foreman owns: Pitch → Scope (via Sarge handoff) → Ready → In Progress → In Review → merge.
- ✗ Foreman does NOT own: post-merge smoke testing, the Verify column, or Verify → Done.

The current state is a process violation (named in `phases/verify.sh:219-220` as a TODO): the agent that built and shipped a PR cannot also be the agent that decides whether the deploy worked. v0 fixed half of it (Verify → Done is now Inspector's call). v1 fixes the other half (the smoke test itself moves out of Foreman).

**Implication for v1 scope:** Inspector v1 isn't just "v0 + LLM." It's "v0 + LLM + post-merge smoke testing." `phases/verify.sh` either migrates inline to Inspector v1 or gets retired when Inspector runs its own equivalent (see Open Question #1).

---

## What v0 covers (recap)

Per #201, shipped in `phases/inspect.sh` + `lib/inspect.sh`:

- **Walks Verify-column items**, fetches AC checklist, regex-classifies each bullet T1 vs non-T1.
- **T1 only:** `grep -E`, `git ls-files | grep`, `test -f`. Pure bash. No HTTP, no DOM, no LLM.
- **Three verdicts:** PASS → `move_to_done`. FAIL → `move_to_scope`. SKIP → leave in Verify (David owns).
- **Cost ceiling:** $0/run.
- **Logs** to `results/inspector.log` (one JSON line per item: `ts`, `repo`, `issue`, `verdict`, `total/t1/non_t1/passed/failed/compile_err`, `latency_ms`, `reason`).

The log format is what tells v1's scope which T2 patterns to prioritize first. Without it, v1 ships blind and has to guess at compiler templates.

---

## What v1 adds (Option C from recon + boundary cleanup)

| Capability | v0 | v1 |
|---|---|---|
| AC bullet classification | regex (T1 only) | LLM-classified (T1 / T2 / T3 / T4) |
| Compiled checks | bash file/grep | bash file/grep + `curl` HTTP/body checks |
| Post-merge smoke testing | (Foreman's `phases/verify.sh`) | **Inspector takes ownership.** Inspector either calls into the existing verify logic from `phases/inspect.sh`, or `phases/verify.sh` gets retired and its checks migrate inline. Either way, Foreman's loop ends at review/merge. |
| DOM walks (T3) | SKIP | SKIP (deferred to v2) |
| Mocked state (T4) | SKIP | SKIP (out of scope) |
| Classifier prompt | n/a | `prompts/inspect-classify.md`, opens "assume the builder cheated" |
| Output mode | n/a | `[FOREMAN]` JSON for structured verdicts |
| Cost ceiling | $0/run | `--max-budget-usd=5` shared across the run (from #106) |
| Kill switch | restart Foreman without phase | env flag `INSPECT_DISABLE_LLM=1` falls back to v0's regex path |

**Not in v1:**

- Playwright MCP T3 walks (deferred to v2 follow-up; original carve-out in #106's Out of Scope).
- T4 mocked / seeded-state (repo-level integration tests own this).
- Standalone `getqatalyst/inspector` repo (lives in foreman).
- Independent cron schedule (shares the existing 5×/day orchestrator run).
- Auto-merge / PR-block from any code-reviewer findings (separate phase, separate ticket — see "Sibling: code-reviewer split" below).

---

## What v0 logs tell us about v1's shape

v1 is happening regardless. The log signals below shape *which T2 patterns v1 prioritizes* and *what the SKIP-shape backlog looks like* — not whether v1 ships.

| # | Signal | Where it comes from | What it shapes |
|---|---|---|---|
| 1 | **SKIP rate** | `inspector.log`: count of `verdict=skip` / total items evaluated | High SKIP rate = v1's LLM/T2 coverage is the unlock. Low SKIP rate = v1's calibration matters less; ship it lean. |
| 2 | **MTTM (mean time to move)** | Difference between item-enters-Verify and item-leaves-Verify (PASS or FAIL), aggregated weekly | If MTTM is high but SKIP rate is low, the bottleneck isn't classification — it's something else (cycle gap, dedup loop). v1 may not fix it; flag for separate ticket. |
| 3 | **Top-3 SKIP shapes** | `inspector.log`: SKIP reasons clustered by recurring patterns (e.g., "deployed URL returns 200", "field exists in response") | Picks v1's first T2 compiler templates. ≥ 2 of top-3 in HTTP shape → v1 covers most of them. Top-3 in DOM/state shape → flag for v2 (Playwright). |

**Use as scope-shaping inputs, not gates.** File the v1 ticket as soon as we have ~1 week of logs to anchor the top-3 SKIP shapes. If David wants to file sooner with explicit "scope to be tightened post-week-1," that's fine too.

**Code-reviewer split** is a separate decision and a separate ticket, not part of v1. See "Sibling: code-reviewer split" below.

---

## What v0 must log to inform v1's scope

Already in #201 AC #6 — listed here so v1 scoping confirms the dependency holds:

- `ts` — when Inspector evaluated the item
- `repo` — which repo the issue belongs to
- `issue` — issue number
- `verdict` — `pass` / `fail` / `skip`
- `total` / `t1` / `non_t1` / `passed` / `failed` / `compile_err` — bullet counts
- `latency_ms` — wall time for the item evaluation
- `reason` — SKIP reason string (free-form for now; v1 will categorize)

If anything in this list is missing from `results/inspector.log` after a week of runs, v1's compiler template selection has to be guessed instead of calibrated. That's a v0 follow-up bug to fix before v1 scoping, not a blocker.

---

## Cost model (v1)

- **Cap:** `--max-budget-usd=5` shared across the entire run, per #106 line on the original spec. With a Verify column averaging ~5 items × ~3 bullets each × ~1 LLM call per bullet at Haiku rates, this is comfortable. Opus calls inflate it 10×; default to Haiku unless calibration proves wrong.
- **Failure mode if cap exceeded:** Inspector exits early with `INSPECTOR: SKIP — budget exceeded`. Logs the items it didn't reach. v0's regex path remains valid for the unreached items on the next cycle.
- **Kill switch:** `INSPECT_DISABLE_LLM=1` env var causes `phases/inspect.sh` to skip the LLM classifier and fall through to v0's regex path. Reversible to v0 in one env-var flip; do not need a code revert.

Per-phase model and budget actually live in `config/model-routing.sh` (see `foreman/CLAUDE.md § Safety`). v1's wiring **must** add Inspector there, not hardcode `--model` / `--max-budget-usd` in the phase script.

---

## Sibling: code-reviewer split

The original #106 spec bundled v1 (LLM classifier) with a separate **code-reviewer phase**: `phases/code-review.sh` dispatches the existing `code-reviewer` subagent against open PRs missing a `REVIEWER:` tag and posts findings.

These are **different work**:

- Inspector consumes Verify-column items and decides Verify → Done. It runs *after* a PR is merged.
- Code-reviewer phase consumes open PRs and posts findings *before* merge. It informs `phases/review.sh`'s autonomous reviewer; it doesn't merge or block.

Decision: **code-reviewer split is a separate ticket, separate decision, separate sequence.** It doesn't depend on v1; it can land before, alongside, or after. File it when David greenlights — not gated by this plan.

---

## Open questions for David before scoping the v1 build

1. **`phases/verify.sh` disposition.** v1 means Inspector owns the post-merge surface. Two paths:
   - (a) **Migrate inline.** Inspector v1 calls into verify.sh's smoke-test logic from `phases/inspect.sh`. verify.sh stays as a library, not a phase. One agent runs it; one agent owns the verdict.
   - (b) **Retire and rebuild.** verify.sh comes out of the orchestrator entirely. Inspector v1 runs its own deploy-fetch checks (compiled from T2 AC bullets via the LLM classifier). Cleaner boundary, more code to write.
   - Lean: (a) for v1, then re-evaluate (b) once T2 coverage is healthy. Pick before scoping.
2. **Budget split.** Is `$5/run` shared across all Foreman/Inspector phases, or does Inspector v1 get its own $5? #106's original wording is ambiguous.
3. **Model default.** Haiku for cost, Sonnet for accuracy, Opus for hardest-case classification. Default is Haiku unless you pick otherwise.
4. **Kill-switch shape.** Env var (`INSPECT_DISABLE_LLM=1`) or board-side toggle (an `inspector-disabled` label on the issue)? Env var is simpler; label is more inspectable.
5. **File timing.** File the v1 ticket now (Sarge writes spec with explicit "tighten T2 templates after week-1 SKIP-shape data") or wait ~1 week for v0 logs to land first?

Once #1 lands, the rest are scoping details. Sarge files the v1 ticket immediately after.
