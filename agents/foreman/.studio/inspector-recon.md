# Inspector v0 — Sarge Recon

**Status:** SHIPPED as v0 via #201 / PR #202 (merged 2026-05-08). Option B selected. Open questions at the bottom were resolved by the v0 build. Kept as a historical artifact and reference for the [v1 plan](inspector-v1-plan.md).
**Driving issue:** getqatalyst/foreman#106
**Adjacent ticket:** getqatalyst/foreman#200 (verify-FAIL classifier)
**Wedge file:** `phases/verify.sh:219-220` ("Verify->Done is the Inspector agent's job (unbuilt as of 2026-04-23); David promotes manually until it ships.")

---

## Why this exists

Foreman currently builds, ships, and verifies its own PRs. That's a **process violation** at the Verify→Done step: the builder cannot also be the closer. Today the Verify column drains only when David promotes manually, and items pile up. Inspector is the third agent — independent of Foreman's build chain — whose only job is to either promote a Verify item to Done or kick it back to Scope.

#106 already exists with a thoughtful body, but it's over-scoped for v0: it bundles Inspector + a separate code-reviewer phase + a four-tier classifier (T1 source-grep, T2 public-fetch, T3 DOM walks, T4 mocked state) + an LLM classifier prompt. That's a Large. The brief asks for a v0 cut.

---

## What Inspector is NOT

- Not Foreman with a different prefix. Inspector must run as a separate phase, with its own prompt and budget, posting under its own comment namespace (`INSPECTOR:`).
- Not the deploy-lag fix (#200). #200 makes verify.sh's PASS/FAIL more accurate; Inspector consumes verify.sh's signal and decides Verify→Done independently.
- Not a code reviewer. The code-reviewer subagent already exists at `Projects/.claude/agents/code-reviewer.md`. The "second pair of eyes" half of #106 is a separate phase and should split out.

---

## Three v0 options (lightest → heaviest)

### Option A — Mechanical aging promoter

**What it does:** Walks Verify-column items. For each, checks (1) `Automated verification: PASS` comment exists from verify.sh, (2) no `INSPECTOR: FAIL` since merge, (3) item has been in Verify for ≥24h. If all three hold, moves item to Done with `INSPECTOR: AUTO-PROMOTED — verify PASS, no failures, stable Nh`.

**What it doesn't:** No independent assertion. No re-check of AC. Trusts verify.sh's PASS. No LLM cost.

**Trigger:** New `phases/inspect.sh`, runs once per orchestrator cycle after `verify.sh`. Same launchd schedule (5×/day).

**Gate logic:** `verify.sh PASS && no FAIL since merge && Verify-age ≥ 24h → move_to_done + INSPECTOR: AUTO-PROMOTED comment via comment_dedup_or_escalate`.

**Failure modes:**
- If verify.sh's PASS was wrong (deploy-lag, false positive), Inspector silently auto-promotes broken work. Mitigation: depends on #200 landing first.
- Aging window is arbitrary; too short = false promotes, too long = column still piles up.

**Effort:** S (≤1 day). New phase script (~80 LOC), comment helper, board mover.

**Dependencies:** #200 (hard — without classifier, verify.sh's PASS is unreliable enough that auto-promote is risky).

---

### Option B — Heuristic T1 static-checker (RECOMMENDED)

**What it does:** Walks Verify-column items. Pulls AC bullets from the linked issue. Heuristic-classifies each bullet as T1 (regex-matchable to `grep`/`git ls-files`/`file exists` shape) or non-T1 (skip-whole-ticket). Compiles T1 bullets to bash, runs against the merge SHA, posts `INSPECTOR: PASS|FAIL|SKIP — N source checks, M skipped`.

**What it doesn't:** No T2 fetch (curl) checks — punted to v1. No LLM classifier — purely regex. No DOM walks, no mocked state. High SKIP rate on Sage tickets (which lean on HTTP behavior); that's expected and acceptable for v0.

**Trigger:** New `phases/inspect.sh`, runs once per cycle after `verify.sh`. Same launchd schedule.

**Gate logic:**
- `all T1 bullets PASS → move_to_done + INSPECTOR: PASS`
- `any T1 bullet FAIL → move_to_scope + INSPECTOR: FAIL — bullet "..." failed: <why>`
- `any non-T1 bullet OR compile error → leave in Verify + INSPECTOR: SKIP — <reason>` (David still owns)

**Failure modes:**
- Regex classifier misclassifies a bullet as T1, runs nonsense, FAILs incorrectly → ticket bounces to Scope. Recoverable; Sarge picks up.
- Heuristic over-skips. High SKIP rate makes Inspector look ineffective. Mitigation: log SKIP reasons; v1 promotes high-frequency SKIP shapes to LLM classification.
- Doesn't catch behavioral regressions, only file/grep-shape AC. Acceptable: that's what verify.sh and humans are for.

**Effort:** M (2-3 days). Heuristic classifier (~40 LOC of regex), bash compiler/runner, phase script, dedup-protected comment, board mover, ≥3 fixture tests in `scripts/test-inspect.sh`.

**Dependencies:** None hard. `move_to_done` already exists in `config/board-ids.sh` per #106. `comment_dedup_or_escalate` exists at `lib/comments.sh:121`. Plays well with #200 but doesn't block on it.

---

### Option C — Full LLM classifier (the current #106 spec)

**What it does:** Exactly what #106's body describes: LLM reads each AC bullet, classifies T1/T2/T3/T4, compiles to bash/curl, runs, posts INSPECTOR: PASS/FAIL/SKIP. Includes the classifier prompt at `prompts/inspect-classify.md` opening with "assume the builder cheated."

**Trigger:** Same as A and B.

**Gate logic:** Identical to B but with broader coverage (T1 + T2). T3/T4 still SKIP.

**Failure modes:**
- LLM mis-classifies → mis-compiles → FAIL or SKIP. Cost of mistake is higher because LLM cost makes loops expensive.
- Budget overrun: a Verify column with 15 items × LLM-per-bullet × 5×/day adds real $/month. Needs hard `--max-budget-usd` (#106 says 5).
- More moving parts than v0 should ship at once.

**Effort:** L (4-5 days). Heuristic classifier + LLM classifier + bash/curl compiler + budget guard + phase + tests.

**Dependencies:** Same as B, plus: classifier prompt design, budget routing, `[FOREMAN]` JSON mode in classifier output. Code-reviewer split should land first or alongside.

---

## Sarge recommendation: **Option B (heuristic T1 static-checker).**

**Why B over A:**
A is too cheap. Aging-only Inspector inherits all of verify.sh's mistakes silently. Until #200 lands, that's a real risk: false-positive verify PASSes auto-promote broken work to Done and we lose the audit trail. B does a small, independent re-check of AC against the merge SHA — that's the *minimum* posture for "third agent" to mean anything. Without independent assertion, Inspector is just a timer.

**Why B over C:**
C is the right v1, not v0. The LLM classifier is the highest-risk component (cost, mis-classification, prompt drift). Shipping it inside v0 means we can't isolate Inspector's bugs from classifier bugs. B proves the seams (phase wiring, board mutation, comment namespace, dedup) with mechanical machinery first. Once B is live and the SKIP shapes are logged, v1 can promote the highest-frequency SKIP shapes to LLM classification one at a time.

**Why now:**
verify.sh:219-220 is a process-violation TODO sitting in production. Foreman is auto-closing things it shouldn't and David's redline made that explicit. B is the smallest cut that retires that TODO without introducing new risk surface.

**Sequence:** Land #200 in parallel (independent track, fixes verify.sh's signal). Land B as Inspector v0. Re-evaluate C and code-reviewer split after two weeks of B-in-prod metrics.

---

## Acceptance criteria for Inspector v0 (Option B)

1. **New `phases/inspect.sh` runs after `verify.sh` in `orchestrator.sh`'s daily loop.** Has its own daily-once guard. Logs to `results/$DATE.log` with `INSPECT PHASE: passed=N failed=N skipped=N`. Does not run if `verify.sh` was skipped this cycle.
2. **Walks Verify-column items via `fetch_board_items` from `config/board-ids.sh`** (not `gh project item-list`, which silently truncates and drops Status). For each item, fetches the linked issue's AC checklist, regex-classifies each bullet as T1 or non-T1, compiles T1 bullets to bash (`grep -E`, `git ls-files | grep`, `test -f`).
3. **PASS path: all T1 bullets pass** → `move_to_done "$REPO" "$ISSUE_NUM"` (canonical helper, board-ids.sh) + `comment_dedup_or_escalate "$REPO" "$ISSUE_NUM" "INSPECTOR: PASS — N source checks passed" "inspector-pass"`. **FAIL path: any T1 bullet fails** → `move_to_scope` + `INSPECTOR: FAIL — bullet "<text>" failed: <why>`. **SKIP path: any non-T1 bullet, compile error, or no AC** → leave in Verify + `INSPECTOR: SKIP — <reason>`. All three paths use `comment_dedup_or_escalate` to prevent loops (sage#215 lesson).
4. **`scripts/test-inspect.sh` covers at least:** (a) all-T1 PASS, (b) one T1 FAIL → move_to_scope, (c) mixed T1+non-T1 → SKIP, (d) classifier regex never crashes on malformed bullets (fail-closed to SKIP), (e) dedup suppresses identical INSPECTOR: comments within 5-comment scan window. Tests run from fixtures, not live `gh`.
5. **No LLM invocation in v0.** No `claude -p` call inside `phases/inspect.sh`. No `--model`, no `--max-budget-usd`. Classifier is pure bash + regex. The cost ceiling for Inspector v0 is `$0/run`. (LLM classifier graduates in v1 once SKIP-shape data justifies it.)

---

## Open questions for David before scoping the build

(All resolved during the v0 split on 2026-05-08; preserved here for the audit trail.)

1. **Aging window for Option A** is moot if we go with B, but if you'd rather ship A first as a safety valve — what's the minimum hold time? 24h? 48h? A full week? → **Resolved: Option B was selected. Aging-window question reopened in [v1 plan](inspector-v1-plan.md) — David later asked for a ≥ 1-week minimum hold in Verify.**
2. **Inspector repo location.** #106 says "Lives in foreman" not standalone. Confirmed? → **Resolved: lives in foreman.**
3. **Code-reviewer split.** #106 bundles Inspector + code-reviewer phase. Splitting it out as a separate ticket is implied by the v0 cut. OK to file that as a follow-up? → **Resolved: split confirmed; code-reviewer is a separate ticket, not part of v1.**
4. **Budget for v1 LLM classifier.** #106 says `max-budget-usd=5` shared. Still right after we see B's SKIP rate? → **Carried into [v1 plan](inspector-v1-plan.md) Open Question #2.**
