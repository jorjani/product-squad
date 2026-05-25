# foreman#154 — PROPOSE outcome and slot truth table

Tightener: `/flow` (T1d)
Issue: https://github.com/getqatalyst/foreman/issues/154

## Outcome flow (ASCII)

```
                       PROPOSE-running
                              |
   +-------+----------+--------+-----------+----------------+----------+
   |       |          |        |           |                |          |
   v       v          v        v           v                v          v
success  replace-   file-   anchor-     anchor-miss-    parse-      crash
         miss      missing  match-ok    inserted-      failure   (uncaught)
         (L552-563)(L502-506)(L532-540) at-end          (L488-494)(set -e)
                                        (L527-529)
   |       |          |        |           |                |          |
slot:    slot:      slot:    slot:       slot:           slot:      slot:
CONSUME  REFUND     SKIP     CONSUME     CONSUME         SKIP       SKIP
                                         (today silent)
   |       |          |        |           |                |          |
   v       v          v        v           v                v          v
PR opens; PROPOSE-   PROPOSE- (no         PROPOSE-MISS-   PROPOSE-   PROPOSE-
EVALUATE  MISS       TARGET-  comment)    SOFT (per 4C)   EVAL-     CRASH
next      comment    MISSING                              PARSE
cadence   on track   comment                              comment
          issue      on track                             on track
                     issue                                issue
```

Slot semantics:
- **CONSUME** = today's experiment is spent; no retry until next cadence (every other day per `foreman/CLAUDE.md`).
- **REFUND** = next cadence retries the same hypothesis (LLM regen may produce an `old` string that matches).
- **SKIP** = slot unaffected; failure is environmental (missing file, parse error, crash), not a real attempt.

## Slot policy truth table

| Outcome | Slot accounting | Comment? | Comment prefix | Comment destination |
|---|---|---|---|---|
| success | CONSUME | no | (PR body carries it) | PR on `getqatalyst/foreman` |
| replace-miss (L552-563) | REFUND | yes | PROPOSE-MISS | foreman tracking issue [*] |
| file-missing (L502-506) | SKIP | yes | PROPOSE-TARGET-MISSING | foreman tracking issue [*] |
| anchor-miss-inserted-at-end (L527-529) | CONSUME | yes | PROPOSE-MISS-SOFT | foreman tracking issue [*] |
| parse-failure (L488-494) | SKIP | yes | PROPOSE-EVAL-PARSE | foreman tracking issue [*] |
| crash (uncaught) | SKIP | yes | PROPOSE-CRASH | foreman tracking issue [*] |

`[*]` Single long-lived **foreman tracking issue** — created as Step 0 of the build. Title: `self-improve telemetry — PROPOSE outcomes`. Pinned. All five PROPOSE-* prefixes post there. Per-miss issues defeat `comment_dedup_or_escalate` (dedup scans within an issue, not across).

## Surfacing dedup behavior

`lib/comments.sh:121` `comment_dedup_or_escalate REPO ISSUE_NUM BODY CONTEXT_LABEL` is the choke point.

```
cadence N:   PROPOSE-MISS body contains prompt_file=repair.md, old="X", new="Y"
             → comment posted (rc=0)
cadence N+2: same prompt_file/old/new generated again
             → byte-identical to prior bot comment in last 5
             → comment_dedup returns 1
             → ESCALATE-DEDUP fires ONCE tagging @jorjani (lib/comments.sh:135-143)
             → quiet thereafter (escalation itself is deduped)
cadence N+4: PROPOSE generates a different `old` or `new`
             → not byte-identical
             → fresh PROPOSE-MISS posts; counter resets
```

CONTEXT_LABEL per outcome: `propose-miss`, `propose-target-missing`, `propose-miss-soft`, `propose-eval-parse`, `propose-crash`. These appear in the ESCALATE-DEDUP message so David knows which surface is looping.

## Decisions locked (2026-05-07)

- **4A = a** — REFUND on `replace-miss` only (LLM regen may match next cadence). SKIP on environmental failures (file-missing, parse, crash). CONSUME on success and `anchor-miss-inserted-at-end`.
- **4B = a** — Create one pinned `getqatalyst/foreman` tracking issue at build time titled "self-improve telemetry — PROPOSE outcomes". All five PROPOSE-* prefixes post there.
- **4C = a** — Surface `anchor-miss-inserted-at-end` as `PROPOSE-MISS-SOFT` (low-urgency, deduped). Today the silent fallback masks prompt rot — making it visible costs ~5 LOC. **YAGNI flag (2026-05-07):** revisit if it becomes noise; the simpler default is to leave the silent fallback alone until a real anchor-drift bug fires. Build it, but treat `PROPOSE-MISS-SOFT` as removable if it adds zero signal in the first month.

## Hardest unknowns

None — see this file. Ready for `/spec`.
