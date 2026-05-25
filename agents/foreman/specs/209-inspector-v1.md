# foreman#209 — Inspector v1 internals

Issue: https://github.com/getqatalyst/foreman/issues/209
Parent: #106 (v0, shipped, closed 2026-05-16)
Sibling: #210 (code-reviewer phase; separate ticket)

This doc carries the implementation-side detail. The issue body carries WHAT/WHY only.

---

## 1. v0 baseline (today)

`phases/inspect.sh` (332 LOC) + `lib/inspect.sh` (190 LOC) — see `getqatalyst/foreman` `main`.

- Walks Verify-column items, fetches AC checklist, regex-classifies each bullet T1 vs non-T1.
- T1: `grep -E`, `git ls-files | grep`, `test -f`. Pure bash. No HTTP, no DOM, no LLM.
- Verdicts: PASS → `move_to_done`; FAIL → `move_to_scope`; SKIP → leave in Verify.
- Logs to `results/inspector.log` (JSONL per item).

v1 keeps the v0 path as a fallback under `INSPECT_DISABLE_LLM=1`.

---

## 2. v1 adds (three classes)

### 2A. LLM-judge with structured output (Tier 2 + 3)

- AC classifier (Haiku, T=0) routes each bullet: T1 bash | T2 HTTP/API | T3 UI/Playwright | T4 mocked → SKIP.
- LLM-judge (Sonnet, T=0) reads the captured state + bullet, emits `{verdict: PASS|FAIL, reason: <≤140c>}`. Structured-output schema enforces shape.
- Determinism contract: same Playwright capture + same bullet → same verdict across re-runs. T=0 alone is not enough; pin schema + prompt versions.
- Prompt: `prompts/inspect-judge.md` opens "you are a strict QA engineer; the builder may have cut corners."
- Kill switch: `INSPECT_DISABLE_LLM=1` falls through to v0's regex path.

### 2B. Aged-promote gate

- PASS verdicts hold ≥ 7 days in Verify before `move_to_done`.
- Aging source: `move_to_verify` board mutation timestamp on item history. Comment-grep fallback (`grep "Foreman: moved to Verify" PR_body OR issue comments`) if the mutation log is unavailable.
- Daily holding comment: `INSPECTOR: HOLDING (Nd/7d) -- N checks passed; will promote on <date>`. Dedup-suppressed to one per day per item.

### 2C. Refactor-allowlist auto-promote (NEW from 2026-05-16 evidence)

Heuristic: if a merged PR's diff touches ONLY paths matching:

```
^(config|lib|prompts|specs|docs|\.studio)/.*$
```

AND the linked issue is CLOSED → promote to Done with `INSPECTOR: PASS (refactor-allowlist) -- diff scoped to <paths>`. No LLM-judge, no Playwright. Verify via:

```bash
gh pr diff "$pr_url" --name-only | awk '
  $1 !~ /^(config|lib|prompts|specs|docs|\.studio)\// { fail=1; exit }
  END { exit fail }
'
```

If the AC bullets call out a specific structural intent ("extracted constants to config/thresholds.sh"), assert the new file exists at the named path AND ≥1 grep anchor inside it matches the bullet's claim. Covers 5/13 from the 2026-05-16 manual run.

### 2D. Lazy-init telemetry: positive-evidence acceptance (NEW from 2026-05-16 evidence)

For event-driven producer/handler tickets where AC says "posts X on Y event" or "creates issue Z when condition C":

- Inspector resolves the producer function/handler in the merged code (`grep -n`-able anchor).
- If found AND the issue body documents the path as event-driven AND the upstream event has not fired since merge → PASS with `INSPECTOR: PASS (lazy-init) -- producer wired at <file:line>; awaiting upstream <event>`.
- Optional: `./orchestrator.sh inspect --force-fire foreman#<N>` triggers the producer once for a smoke test. Out of scope for v1 unless trivial; revisit after first month.

Covers 2/13 from the 2026-05-16 manual run (#154 PROPOSE-MISS producer; #238 `mark_orphan()`).

### 2E. Two-log-stream awareness (NEW from 2026-05-16 evidence)

Foreman writes evidence in two places. Inspector v1 reads both:

```
results/
├── 2026-05-16-0100.log               ← daily orchestrator log (per launchd tick)
│                                        carries <PHASE>: summary lines:
│                                          INSPECT: ... PASS
│                                          SARGE-REVIEW PHASE: scoped=3
│                                          CODE-REVIEW PHASE: reviewed=2
│                                          REPAIR: Running claim-to-diff audit on HEAD ...
│                                          ASSEMBLED_PROMPT_BYTES=<N>
├── 2026-05-16-0600.log
├── ... (one per launchd tick, 5x/day)
├── inspector.log                      ← per-issue JSONL (cross-day, append-only)
└── 2026-05-16-code-review-foreman-265.out  ← per-issue phase output
```

Inspector v1 greps both:
- For phase-summary signals: `grep -E "<PHASE>:" results/2026-05-16-*.log`.
- For per-record/JSONL evidence: `results/inspector.log` and `results/YYYY-MM-DD-<phase>-<repo>-<num>.out`.

Many per-issue stub files are empty today (separate bug, being fixed in parallel). v1 treats absence-of-empty-stub as no-signal, NOT as fail.

---

## 3. Today's evidence (2026-05-16 manual-verify session)

| Issue | Class | Method | v1 class | v0 verdict |
|---|---|---|---|---|
| #203 | code-shape refactor | file-read | 2C refactor-allowlist | SKIP |
| #244 | code-shape refactor | file-read | 2C refactor-allowlist | SKIP |
| #245 | code-shape refactor | file-read | 2C refactor-allowlist | SKIP |
| #247 | code-shape refactor | file-read | 2C refactor-allowlist | SKIP |
| #258 | code-shape refactor | file-read | 2C refactor-allowlist | SKIP |
| #106 | phase wiring | daily-log grep | 2E two-log-stream | (would need T2/T3) |
| #192 | phase wiring | daily-log grep | 2E two-log-stream | SKIP |
| #241 | phase wiring | daily-log grep | 2E two-log-stream | SKIP |
| #118 | phase wiring | daily-log grep | 2E two-log-stream | SKIP |
| #154 | lazy-init producer | negative evidence | 2D lazy-init | SKIP |
| #238 | lazy-init handler | negative evidence | 2D lazy-init | SKIP |
| #177 | conditional branch | shell stub | 2D lazy-init + bash | SKIP |
| #246 | prompt change | phase output | 2E two-log-stream | SKIP |

Total: 13/13 currently SKIPped by v0. After v1: 5/13 auto-promote via 2C, 2/13 via 2D, 6/13 via 2E or T2/T3. Target ≥ 80% auto-promote on the same input set.

---

## 4. T1d verification contract (Inspector v1 verifies itself)

Each AC bullet in the body has a corresponding row here. Inspector v1 runs against #209 after merge and these are the edges it walks.

| State / change | Trigger / observable | Pass evidence |
|---|---|---|
| Refactor-allowlist promote fires | Merged PR with diff ⊂ allowlist paths + linked CLOSED issue | `INSPECTOR: PASS (refactor-allowlist)` on the issue + Verify→Done within one orchestrator tick |
| Refactor-allowlist correctly skips | Merged PR with at least one out-of-allowlist file | No `(refactor-allowlist)` verdict; falls through to LLM-judge/aged-promote |
| Lazy-init promote fires | Issue body says "posts X on Y event"; grep-able anchor exists in merged code; event hasn't fired | `INSPECTOR: PASS (lazy-init) -- producer wired at <file:line>` |
| LLM-judge PASS holds 7 days | AC bullets classify T2 or T3; checks pass; verify-age < 7d | `INSPECTOR: HOLDING (Nd/7d)` once per day; no Done promote until day 7 |
| LLM-judge PASS at day ≥ 7 | Same item, age = 7d | `INSPECTOR: PASS -- N checks passed over 7d hold` + Verify→Done |
| LLM-judge FAIL | Any check fails | `INSPECTOR: FAIL -- bullet "<text>" failed: <reason>` + Verify→Scope; no hold |
| Two-log-stream evidence | Inspector run against an issue whose only signal lives in a per-tick log | Inspector reads `results/YYYY-MM-DD-*.log` AND `results/inspector.log`; correct verdict regardless of which stream carried it |
| Kill switch | `INSPECT_DISABLE_LLM=1` set | v0 regex path runs; no LLM API calls in `results/inspector.log` (zero `model=` lines for the run) |

---

## 5. Hardest unknowns (carried from Pitch)

1. **Playwright runtime wiring** in launchd context. Browser warm-up cost vs spawn-per-call; route through Playwright MCP or spawn Node? → `@eng-deep-dive` before build.
2. **LLM-judge determinism.** Same capture + same bullet → same verdict. T=0 + structured schema + frozen prompt-version. Re-run + majority-vote only if first design drifts in dogfood. → `@eng-deep-dive`.
3. **Aging-window storage.** Inspector needs "entered Verify" timestamp per item. Three candidates: GraphQL field history (preferred if available), comment grep (`grep "Foreman: moved to Verify"`), new board field (avoid; cross-cuts board contract). → `/api` tightener.

These survive into Backlog. Foreman's triage will gate on them being closed before Ready.

---

## 6. Out of scope (carried from Pitch; not changes from there)

- T4 mocked/seeded-state (integration tests own this).
- Code-reviewer phase (#210).
- Standalone `getqatalyst/inspector` repo. Lives in foreman.
- Independent cron schedule. Shares 5x/day orchestrator.
- Modifying `phases/review.sh` autonomous merge.
- Building Playwright MCP itself (runtime dep only).
- `--force-fire` for lazy-init (2D extension; deferred unless trivial).

---

## 7. Helpers / files to reuse

- `fetch_board_items`, `move_to_done`, `move_to_scope` — `config/board-ids.sh`.
- `comment_dedup_or_escalate` — `lib/comments.sh:121`.
- Model routing — `config/model-routing.sh`. Defaults: Haiku for AC classifier; Sonnet for LLM-judge.
- v0 fallback path — `phases/inspect.sh` + `lib/inspect.sh` (unchanged; v1 wraps).

