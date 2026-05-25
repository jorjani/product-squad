# foreman#285 — Verify-FAIL classifier: signal wiring + Fabro vocabulary

Issue: https://github.com/getqatalyst/foreman/issues/285
Supersedes: original body of foreman#197 (classifier logic shipped in PR #200, commit 20f7c73, 2026-05-16; #197 closed as completed).
Adjacent: foreman#233 (Refs not Closes), foreman#272 (event log), foreman#104 (pre-build loop-breaker — deferred).

The issue body carries WHAT/WHY. This doc carries the wiring details and the Fabro mapping. The classifier itself ships in `lib/verify-classify.sh` already.

---

## 1. State of the world (what's already shipped)

PR #200 (merged 2026-05-16) landed:

- `lib/verify-classify.sh` — pure `classify_verify_fail()`, three verdicts (`deploy-lag` / `assertion-fail` / `unknown`), transient-error matcher, `log_verify_classify()`, `already_classified()` dedup gate.
- `phases/verify.sh:147-244` — calls the classifier on the FAIL branch, probes `/api/version` then `/health` for `buildTime` + fingerprint (`version` / `sha` / `commit` fields), gracefully degrades to `unknown` when no probe data, retries once with 180s sleep on `deploy-lag`, tags filed bugs with `verify-classifier-unsure` on `unknown`.
- `scripts/test-verify-classify.sh` — 5-fixture smoke test (deploy-lag, real-assertion-fail, unknown-no-buildtime, transient-error, dedup). 8 assertions.
- Daily log lines: `DEPLOY-LAG: build=... < merge=... — sleep 180s + retry once, no ticket`, `FAIL (verdict=<v>)`, `DEFER (deploy-lag persists, no ticket filed)`, `SKIP: already classified on a prior run`.
- Pipe-delimited record in `results/verify-classify.log` per classification, schema documented at `lib/verify-classify.sh:100-127`.

Cluster that motivated the original body (Sage#239/245/247/248) — all CLOSED.

---

## 2. The actual gap

The signal exists but no consumer reads it. Today:

- `phases/collect-metrics.sh:120` extracts `VERIFY` summary via `parse_summary "VERIFY"`. That summary is the single `VERIFY PHASE: verified=N failed=N skipped=N` line (verify.sh:252); it does not break out verdict counts. `DEFER` lines are invisible. Per-verdict counts are not in `metrics/YYYY-MM-DD.json`.
- `prompts/self-improve.md` consumes the metrics JSON. Without verdict counts, it cannot ask "is classifier `unknown` rate rising?" or "are deploy-lag retries succeeding?".
- `results/verify-classify.log` is append-only, no rotation, no downstream reader.

Three small extensions close the loop.

---

## 3. Work items

### 3.1 Verify phase emits a structured summary line

`phases/verify.sh:252` today:

```bash
echo "VERIFY PHASE: verified=$VERIFIED failed=$FAILED skipped=$SKIPPED" >> "$LOG"
```

Add four counters tracked inside the FAIL branch (initialized to 0 at the top alongside `VERIFIED=0`):

- `CLASS_DEPLOY_LAG` — incremented on `deploy-lag` verdict (regardless of whether retry succeeded).
- `CLASS_ASSERTION_FAIL` — incremented on `assertion-fail` verdict.
- `CLASS_UNKNOWN` — incremented on `unknown` verdict.
- `CLASS_DEFERRED` — incremented on the `DEFER` branch (deploy-lag persisted past retry).

Append to the summary:

```bash
echo "VERIFY PHASE: verified=$VERIFIED failed=$FAILED skipped=$SKIPPED \
deploy_lag=$CLASS_DEPLOY_LAG assertion_fail=$CLASS_ASSERTION_FAIL \
unknown=$CLASS_UNKNOWN deferred=$CLASS_DEFERRED" >> "$LOG"
```

Single line — `collect-metrics.sh`'s `parse_summary` regex already consumes `key=value` pairs.

### 3.2 collect-metrics rolls up classifier verdicts

`phases/collect-metrics.sh:120` runs `parse_summary "VERIFY"`. After step 3.1, the parsed dict carries the four new keys automatically.

Add a nested rollup in the Python block (lines 123-158) so the JSON shape is:

```json
"verify": {
  "verified": 5,
  "failed": 2,
  "skipped": 3,
  "classified": {
    "deploy_lag": 1,
    "assertion_fail": 1,
    "unknown": 0,
    "deferred": 0
  }
}
```

Zero values are emitted (not omitted) so day-over-day diffs don't silently treat missing keys as "no fires".

### 3.3 self-improve sees the new shape

`prompts/self-improve.md` reads the daily metrics file. Add one paragraph to the prompt body (no logic change) instructing the model to inspect `verify.classified` when proposing experiments:

> When `verify.classified.unknown` exceeds 1 in a 7-day window, consider tightening the transient-error patterns in `lib/verify-classify.sh:_verify_classify_is_transient`. When `verify.classified.deferred` is non-zero, consider lengthening the retry sleep in `phases/verify.sh:189` or adding a second retry. Never propose changes that reduce visibility into real assertion failures.

### 3.4 Fabro 6-class vocabulary scaffold

Add a comment block at the top of `lib/verify-classify.sh` (after the existing usage docs) declaring the Fabro vocabulary as the larger target, with the v1 mapping:

```bash
# Fabro 6-class taxonomy — vocabulary target. v1 implements the first two; the
# remaining four are reserved for future verdict additions and must use these
# names rather than ad-hoc strings.
#
#   transient_infra    deploy-lag    deploy hasn't propagated; infrastructure race.
#   deterministic      assertion-fail real code/data bug; reproducible.
#   budget_exhausted   (reserved)    Claude budget cap hit before assertion ran.
#   compilation_loop   (reserved)    repeated build attempts on identical inputs.
#   canceled           (reserved)    PR closed, branch deleted, or run aborted mid-flight.
#   structural         (reserved)    upstream config/env break unrelated to the PR's diff.
#
# The verdict strings emitted today (deploy-lag, assertion-fail, unknown) stay
# as-is for v1 — log compatibility. `unknown` is the Fabro fallback for "can't
# classify with confidence" and routes to Inspector second-look.
```

No code change. The comment locks the vocabulary so when a sixth fire mode appears (e.g. compilation_loop from foreman#104 if/when it fires), the new verdict slot is `compilation_loop`, not `loop-breaker-tripped` or similar.

---

## 4. Coordination

### 4.1 foreman#233 (Refs not Closes) — `phases/verify.sh` overlap

#233 edits `phases/verify.sh:45` (Refs in linked-issue regex), `:145` (replace `ISSUE_STATE=CLOSED` check with PR-comment-presence check), `:152` (negation), `:212` (positive branch). Reference: `specs/233-refs-not-closes.md` §3.

This ticket adds four counters and edits the summary echo (`:252`) — no line overlap. Build whichever ships first; second one rebases trivially.

### 4.2 foreman#272 (event log) — explicit non-bundle

#272's wave-2 wires `edge.selected` emits across phases. Classifier outcomes are a natural emit point (`chosen=deploy-lag|...`), but #272 owns when emits land. This ticket writes only to `results/verify-classify.log` and the metrics JSON; it does NOT call `emit_event`. After #272 wave-2 lands, a follow-up adds the emit in one line at each `log_verify_classify` site.

### 4.3 foreman#104 (hash-based loop-breaker) — explicit non-bundle

#104's body defers itself until the trigger condition (validator firing more than once on the same unchanged body) is met. Not met today. Cross-reference only; when #104 ships, its verdict slot uses the Fabro name `compilation_loop`.

---

## 5. Open questions (deferred to evidence)

1. **Retry budget N=1 vs N=3** — PR #200 shipped with N=1 (180s sleep, single retry). Defer N=3 escalation until a deferred case appears in metrics.
2. **Per-repo `health_endpoint` config in `.index.json`** — defer until a second repo motivates it.
3. **`results/verify-classify.log` rotation** — defer; at current fire rate (~few entries/month) this is fine for years.

---

## 6. Files touched

- `phases/verify.sh` — 4 counter inits, 4 increments inside the case block (lines ~185-205), summary echo at line 252.
- `phases/collect-metrics.sh` — nested rollup in Python block (lines 123-158).
- `prompts/self-improve.md` — one paragraph.
- `lib/verify-classify.sh` — comment block at top (no behavior change).

No new files. No new lib. Size: XS.
