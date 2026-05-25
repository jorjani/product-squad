# foreman#272 — Central orchestration event log internals

Issue: https://github.com/getqatalyst/foreman/issues/272
Consumer (sibling): foreman#209 §2D (Inspector v1, lazy-init class)
Adjacent (not blocking): foreman#274 (PROPOSE tracker), foreman#22 (spend)

This doc carries the implementation-side detail. The issue body carries WHAT/WHY only.

Decisions on storage shape, write API, read API, and schema discipline were locked in David's Fabro-pattern research session, 2026-05-17. Do not re-litigate; if a constraint surfaces during build, escalate to Sarge for a Pitch on the change rather than drifting silently.

---

## 1. Storage

- **Path:** `_shared/events/YYYY-MM-DD.jsonl` (one file per calendar day, host-local clock).
- **Shape:** newline-delimited JSON. One event per line. Strict UTF-8. No trailing comma drama.
- **Posture:** append-only; never edit or truncate in-place. Mirrors `results/inspector.log` precedent.
- **Retention:** keep everything. Revisit only if `du -sh _shared/events/` becomes meaningful (out of scope for v1).
- **Creation:** the helper auto-creates the date file with `0644` perms on first write of the day. Parent dir created with `0755` if missing.

---

## 2. Envelope schema (required for every event)

```json
{
  "id":               "<ULID or UUIDv4>",
  "ts":               "<ISO8601 UTC, ms-precision: 2026-05-17T14:23:01.123Z>",
  "run_id":           "<orchestrator $RUN_ID; e.g. 2026-05-17-1423>",
  "event":            "<from event-name enum, §3>",
  "session_id":       "<phase or call-scope id; e.g. foreman.build.1423>",
  "parent_session_id":"<enclosing scope id; null for top-level>",
  "node_id":          "<machine-readable producer id; e.g. 'build', 'review.merge'>",
  "node_label":       "<human-readable producer label; e.g. 'Phase 3: Build'>",
  "properties":       { /* event-specific payload, see §3 */ }
}
```

All nine envelope fields are required; absent → emitter sets to `null` rather than omitting. Reason: jq selectors fail less surprisingly when keys exist.

`run_id` source: reuse `orchestrator.sh:34` (`RUN_ID="$DATE-$(date +%H%M)"`). For sub-calls spawned outside the orchestrator (e.g. one-off `./orchestrator.sh build`), the same line fires, so the same shape applies. No new id-generator needed.

`session_id` convention: `<system>.<phase>.<HHMM>` for the orchestrator's phase scope; sub-spawns nest as `<system>.<phase>.<HHMM>.<n>` where `n` is a monotonic per-spawn counter held by the parent session.

---

## 3. Event-name enum + payload contracts

| event             | properties (required keys)                                                                                       |
|-------------------|------------------------------------------------------------------------------------------------------------------|
| `run.start`       | `{argv, host, foreman_banner}`                                                                                   |
| `run.exit`        | `{cycles, built, reviewed, merged, exit_code}`                                                                   |
| `run.fail`        | `{reason, exit_code, abort_phase}`                                                                               |
| `stage.enter`     | `{phase}`                                                                                                        |
| `stage.exit`      | `{phase, work_count, summary_kv}` (summary_kv mirrors the phase's `PHASE: k=v ...` summary)                      |
| `stage.fail`      | `{phase, exit_code, reason}`                                                                                     |
| `agent.usage`     | `{model, tokens: {input, output, cache_read, cache_write}, cost_usd, duration_ms, caller_phase}` (wave 2)        |
| `edge.selected`   | `{edge_name, choices, chosen, rationale_excerpt_140c}` (self-improve PROPOSE outcomes route here)                |
| `loop.restart`    | `{cycle_n, reason}` (orchestrator's outer-loop iteration)                                                        |
| `agent.sub.spawned` | `{parent_session_id, child_session_id, kind, target}` (kind: claude\|gh\|jq\|other; target: prompt path or cmd) |

Allowlist enforced at the helper layer (§4). Unknown event names rejected with non-zero exit + stderr message; emitter dies hard rather than corrupting the log.

---

## 4. Write API: `_shared/lib/event.sh`

Shell library. Phase scripts source it once near the top, after `config/env.sh`.

```bash
# _shared/lib/event.sh — sourced by phase scripts
emit_event <event_name> [properties_json]
```

Behavior:

- Validates `event_name` against the §3 allowlist; non-match → `return 2` + stderr.
- Generates `id` (ULID preferred; fall back to `uuidgen | tr 'A-Z' 'a-z'`).
- Stamps `ts` (UTC, ms-precision; `python3 -c` per the foreman shell-parser convention).
- Reads `RUN_ID`, `SESSION_ID`, `PARENT_SESSION_ID`, `NODE_ID`, `NODE_LABEL` from env (set by orchestrator + each phase header; documented in §5).
- Merges caller-supplied `properties_json` (default `{}`).
- Atomically appends a single line to `_shared/events/$DATE.jsonl` (flock-based; never partial-write).
- Returns 0 on success; non-zero on validation/write failure. Callers must NOT exit on a failed emit — log to stderr and continue. Event log is observability infra, not load-bearing.

Helper does not retry on write failure (no queue, no buffer). The cost of a missed event line < the cost of a hung phase. If write rates ever justify a buffer, that's a follow-up.

Naming: `emit_event` (verb-first; matches `comment_dedup_or_escalate`'s shape in `lib/comments.sh`).

---

## 5. Producer wiring (day 1, Foreman-only)

Each phase script gets a small header block, modelled on how `provenance.sh` is sourced today:

```bash
# At top of phase script, after config sourcing:
source "$SCRIPT_DIR/../_shared/lib/event.sh"
export SESSION_ID="foreman.build.${RUN_ID##*-}"
export PARENT_SESSION_ID="foreman.orchestrator.${RUN_ID##*-}"
export NODE_ID="build"
export NODE_LABEL="Phase 3: Build"

emit_event "stage.enter" '{"phase":"build"}'
# ... phase body ...
emit_event "stage.exit" "$(jq -n --argjson kv "$SUMMARY_JSON" '{phase:"build",work_count:'$BUILT',summary_kv:$kv}')"
```

**Day-1 producer set (minimal viable v1):**

| Producer file        | Events fired                                                                  |
|----------------------|-------------------------------------------------------------------------------|
| `orchestrator.sh`    | `run.start`, `run.exit`, `run.fail`, `loop.restart`                           |
| `phases/build.sh`    | `stage.enter`, `stage.exit`, `stage.fail`, `agent.sub.spawned` (claude build) |
| `phases/review.sh`   | `stage.enter`, `stage.exit`, `stage.fail`, `agent.sub.spawned` (claude review)|
| `phases/self-improve.sh` | `stage.enter`, `stage.exit`, `edge.selected` (PROPOSE outcome routing)    |

**Wave 2 (separate ticket, do not bundle):**

- All other phases (verify, inspect, code-review, triage, sarge-review, auto-enrich, cleanup, ghost-sweep, stranded-sweep, janitor, collect-metrics).
- `agent.usage` from every claude call (requires hooking the bounded.sh / claude-CLI wrapper to capture token + cost; non-trivial).
- Sage and mastra-server producers (different runtime — TypeScript; needs a sibling `_shared/lib/event.ts` emitter).

Rationale for the day-1 cut: build/review/self-improve are the three phases Inspector v1 §2D was designed against (#154, #238 producer/handler cases). Other phases are useful but not blocking #209.

---

## 6. Read API: `_shared/lib/event-query.sh`

Thin jq wrapper. Single purpose: abstract the storage choice so storage can swap (JSONL → SQLite → external) without breaking consumers.

Surface:

```bash
event_query <jq_filter> [--since YYYY-MM-DD] [--until YYYY-MM-DD]
```

Implementation v1: concatenates the requested daily JSONL files and pipes through `jq -c "<filter>"`. Returns matched events one-per-line.

Default window: today only. `--since`/`--until` widen.

Inspector v1 §2D consumer-side usage (illustrative, not prescriptive — the consumer ticket is #209):

```bash
# "Has the propose-miss producer fired since merge timestamp X?"
event_query 'select(.event=="edge.selected" and .node_id=="self-improve" and .properties.chosen=="propose-miss" and .ts > "2026-05-12T00:00:00Z")' --since 2026-05-12
```

---

## 7. Sample emission lines (for reviewer ground truth)

```jsonl
{"id":"01J9X...","ts":"2026-05-17T14:23:00.001Z","run_id":"2026-05-17-1423","event":"run.start","session_id":"foreman.orchestrator.1423","parent_session_id":null,"node_id":"orchestrator","node_label":"Foreman orchestrator","properties":{"argv":["all"],"host":"M5","foreman_banner":"F:M5:1423:54321"}}
{"id":"01J9X...","ts":"2026-05-17T14:23:00.412Z","run_id":"2026-05-17-1423","event":"stage.enter","session_id":"foreman.build.1423","parent_session_id":"foreman.orchestrator.1423","node_id":"build","node_label":"Phase 3: Build","properties":{"phase":"build"}}
{"id":"01J9X...","ts":"2026-05-17T14:24:11.998Z","run_id":"2026-05-17-1423","event":"agent.sub.spawned","session_id":"foreman.build.1423.1","parent_session_id":"foreman.build.1423","node_id":"build.claude","node_label":"claude build for Sage#402","properties":{"kind":"claude","target":"prompts/build.md","repo":"getqatalyst/Sage","issue":402}}
{"id":"01J9X...","ts":"2026-05-17T14:31:02.555Z","run_id":"2026-05-17-1423","event":"stage.exit","session_id":"foreman.build.1423","parent_session_id":"foreman.orchestrator.1423","node_id":"build","node_label":"Phase 3: Build","properties":{"phase":"build","work_count":3,"summary_kv":{"built":3,"failed":0,"blocked":0}}}
{"id":"01J9X...","ts":"2026-05-17T14:55:00.001Z","run_id":"2026-05-17-1423","event":"run.exit","session_id":"foreman.orchestrator.1423","parent_session_id":null,"node_id":"orchestrator","node_label":"Foreman orchestrator","properties":{"cycles":2,"built":3,"reviewed":12,"merged":9,"exit_code":0}}
```

---

## 8. Boundaries & non-goals

- **Not a replacement for `results/*.log`.** Daily log stays as the narrative trace for humans; event log is the queryable surface for tools. Both fed in parallel during this ticket.
- **Not a replacement for `metrics/YYYY-MM-DD.json`.** `collect-metrics.sh` continues to parse `results/*.log`. A follow-up may re-source from JSONL but is not in this ticket.
- **Not a replacement for `results/inspector.log`.** Inspector keeps its own per-item JSONL until v1 lands and re-sources from the central log.
- **Not a replacement for #274's tracking issue.** PROPOSE-* comments still post to that issue (human notice surface). `edge.selected` events mirror the same outcomes for tool queries.
- **Not load-bearing.** A failed `emit_event` MUST NOT take down a phase. Log to stderr, continue.

---

## 9. Hardest unknowns

1. **ULID vs UUID for `id`.** ULIDs are sortable (good for jq `select(.id > ...)` paging) but need a generator binary; UUIDs ship in macOS base. Default: try `ulid` if present, fall back to `uuidgen`. Builder decides.
2. **flock semantics on macOS.** macOS `flock` is GNU-compat via Homebrew but not in base. Default: use `python3 -c` with `fcntl.flock` (per the existing shell-parser convention). Cross-platform, no extra dep.
3. **`agent.usage` token/cost capture.** Requires hooking `claude` CLI output for the `--cost-usd` line (or whatever the CLI surfaces). Non-trivial; deferred to wave 2. Day-1 producers do not emit `agent.usage`.
