# foreman#181 — outcome and CI classification

Tightener: `/flow` (T1d)
Issue: https://github.com/getqatalyst/foreman/issues/181

## A. Build outcome state machine (ASCII)

```
                          build-ticket.sh:in-progress
                                     |
       +------------+----------------+--------------+--------------+
       v            v                v              v              v
  pr-opened    declined-cleanly  declined-cleanly  generic-fail  infra-crash
  (PR_URL set) (.decline-reason) (exit-code 2)    (exit !=0,2)  (timeout/OOM)
       |            |                |              |              |
       v            v                v              v              v
   In Review     Verify           [N/A]          Ready          Ready
   (label:       (label: none,    (NOT USED      (label:        (label:
    none)         comment:         per 3A)        build-failed,  build-failed,
                  DECLINED)                       counter++)     counter++)
       |            |                              |              |
       v            v                              v              v
   counter=0    counter=0                       counter++       counter++
```

Decision 3A locks the contract on `.decline-reason.md` only; exit-code 2 is not used.

PR opened: `build-ticket.sh:412-422` (PR_URL set → `move_to_in_review`).
Generic failure: `build-ticket.sh:424-456` (`build-failed` + `move_to_ready`); failure tracker bumped at `build.sh:129-154`; 3rd strike → Blocked at `build.sh:133-147`.

## A. Edge table (build outcome)

| Outcome signal | Board target | Label | Counter increment | Digest section |
|---|---|---|---|---|
| PR opened (PR_URL non-empty, `build-ticket.sh:410`) | In Review | none | reset to 0 (`build.sh:120-124`) | silent |
| Decline-cleanly via `.decline-reason.md` (NEW) | Verify | none | no | "Auto-declined" (informational) |
| Generic non-zero exit (`build-ticket.sh:424-456`) | Ready (or Blocked at 3rd strike) | `build-failed` | yes | Blockers (real) |
| Infra crash: timeout / OOM / dep-install fail (`build-ticket.sh:320-333`) | Ready | `build-failed` | yes | Blockers (real) |

## B. CI classification flow (ASCII)

```
   per repo in BLOCKER_REPOS (pipeline-digest.sh:97)
              |
              v
  REQUIRED = gh api repos/<r>/branches/main/protection
              |             \
       200 OK |              \ 404 (no protection)
              v               v
       parse required_      REQUIRED = {} (empty set)
       _status_checks.
       contexts[]            |
              \              /
               v            v
        for each PR, iterate statusCheckRollup[]
              |
       +------+-------+----------+
       v              v          v
   conclusion=     conclusion=  PENDING
   FAILURE         SUCCESS      / NEUTRAL
       |              |          |
       v              v          v
   name in        silent      silent
   REQUIRED?
   yes / no
       |
   +---+---+
   v       v
 Blocker  Advisory
 bucket   bucket
```

Today: `pipeline-digest.sh:113` treats ANY `conclusion == 'FAILURE'` as a blocker — no required-set lookup, no 404 handling. That is the bug. Per decision 3B, **a separate "Advisories" digest section** carries advisory failures (zero-suppressed when the count is 0).

Required-set source: `gh api repos/<owner>/<repo>/branches/<default>/protection` → `.required_status_checks.contexts[]`. 404 → empty set → all checks advisory. Cache per-digest-run (one `gh api` call per repo, inside the `pipeline-digest.sh:97` loop).

## B. Edge table (CI)

| Check name | In required set? | conclusion | Digest bucket |
|---|---|---|---|
| SonarCloud | no (404 on Sage main) | FAILURE | Advisory (warning, not blocker) |
| SonarCloud | no | SUCCESS | silent |
| SonarCloud | yes | FAILURE | Blocker |
| CodeQL | yes | FAILURE | Blocker |
| Tests | yes | SUCCESS | silent |
| Tests | yes | PENDING | silent |
| Tests | yes | FAILURE | Blocker |
| Tests | no | FAILURE | Advisory |
| any | any | NEUTRAL / SKIPPED | silent |

## Decisions locked (2026-05-07)

- **3A = a** — Decline-cleanly contract via `.decline-reason.md` file marker. Greppable, dedup-friendly, survives wrappers. Exit-code 2 is **not** supported (pick one, not both).
- **3B = a** — Board target for clean declines = Verify. Treats clean decline as a verification claim ("bug obsolete; check that PR #X covers it"). Routes to Inspector when foreman#106 ships, to David in the interim. Done is wrong (skips the human check); a new "Auto-Declined" column is overhead for a low-volume signal.
- **3C = a** — Advisory failures land in a separate "Advisories" digest section with a count. Zero is silent. Preserves SonarCloud-drift visibility without crying wolf.

## Hardest unknowns

None — see this file. Ready for `/spec`.
