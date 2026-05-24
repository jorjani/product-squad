# foreman#168 — Slack push truth table

Tightener: `/flow` (T1d)
Issue: https://github.com/getqatalyst/foreman/issues/168

## Decision flow (ASCII)

```
escalation event fires at call site
        |
        v
  comment_dedup_or_escalate(repo, num, body, context)
        |
        +--> comment_dedup() returns rc:
        |       rc=0 (new posted)   -> Slack push (additive, alongside comment)
        |       rc=1 (duplicate)    -> NO Slack at outer site
        |       rc=2 (post failed)  -> NO Slack (comments.sh:146 errors out, returns 2)
        |
        +--> rc=1 path enters lib/comments.sh:140 (recursive comment_dedup with
              ESCALATE-DEDUP body, same repo+issue):
                  inner rc=0 -> Slack push ONCE (this is where loops surface)
                  inner rc=1 -> NO Slack (escalation already shown previously)
                  inner rc=2 -> NO Slack (post failed; informational only)

SLACK_CI_WEBHOOK_URL unset at any point: silent skip (mirrors stall.sh:187).
```

## Per-site behavior

| file:line | prefix | Slack@rc=0 | Slack@rc=1 | Notes |
|---|---|---|---|---|
| `phases/build-ticket.sh:430` | DECISION-NEEDED | YES | NO | Owner of 3rd-build-fail Slack |
| `phases/build.sh:147` | "Build failed 3..." | NO | NO | Suppressed; co-fires with `:430` |
| `phases/auto-enrich.sh:171` | ESCALATION | YES | NO | 3 round-trips |
| `phases/auto-enrich.sh:280` | DECISION-NEEDED | YES | NO | Parse failure |
| `lib/comments.sh:140` | ESCALATE-DEDUP | YES | NO | Fires inside helper; rc=0 of inner `comment_dedup` is the trigger |

## Co-firing collapse

`build-ticket.sh:430` and `build.sh:147` both trigger on the same 3rd-attempt-no-PR event. **build-ticket.sh:430 owns the Slack push; build.sh:147 stays silent on Slack** (still posts its existing comment for the durable trail). Mechanism: per-cycle marker file `${TMPDIR:-/tmp}/foreman-slack-fired-${repo}-${issue}-${cycle_id}` written by `:430` just before its Slack push and unlinked at end-of-cycle. `:147` checks-and-skips if the marker exists for the (repo, issue). File-based because `:430` and `:147` run in different shell invocations under `build-ticket → build`.

## Edge table

| From-state | Event | Guard | Side effects | To-state |
|---|---|---|---|---|
| no recent bot comment | site fires (ticket:430) | `SLACK_CI_WEBHOOK_URL` set | comment posted (rc=0); Slack POST | comment+slack sent |
| no recent bot comment | site fires (ticket:430) | webhook unset | comment posted (rc=0); Slack skipped silently | comment-only sent |
| recent dup exists | site fires (any of 5) | — | outer rc=1; NO outer Slack; enter ESC-DEDUP path | escalation pending |
| recent dup, first time | ESCALATE-DEDUP body posts | inner rc=0, webhook set | escalation comment + Slack POST (named context) | esc+slack sent |
| recent dup, Nth cycle | ESCALATE-DEDUP body re-posts | inner rc=1 (esc itself dup) | NO comment, NO Slack — loop contained | quiet (loop bounded) |
| 3rd build fail event | ticket:430 + build:147 fire | marker written by :430 | one comment per site; ONE Slack (owner :430) | single slack sent |
| gh post failure | site fires | comment_dedup rc=2 | error logged; NO Slack; outer returns 2 | error surfaced |

## Decisions locked (2026-05-07)

- **2A = a** — Per-cycle marker file at `${TMPDIR}/foreman-slack-fired-…`. Survives subshell boundaries; build.sh and build-ticket.sh run as separate shell invocations.
- **2B = a** — Slack body for ESCALATE-DEDUP carries context-only label (e.g., `build-oversized`, `propose-miss`). No suppressed-prefix duplication.
- **2C = a** — `rc=2` (gh post failed) silent on Slack. Comment-is-the-record; gh-stays-broken is a different loop class and shouldn't compound.

## Hardest unknowns

None — see this file. Ready for `/spec`.
