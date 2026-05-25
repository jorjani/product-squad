# 240 — Orphan rescue after build-ticket.sh dies post-claude

## Proximate cause (confirmed)

`lib/bounded.sh:33` runs claude under `python3 ... os.setsid(); os.execvp(...)`,
making claude a new session/PGID leader. The killer subshell at `:36-38` sends
`kill -TERM -- "-$cpid"` then `kill -KILL -- "-$cpid"` to the *process group*.
When the wall-clock bound (`BUILD_TIMEOUT=1800` in `phases/build-ticket.sh:323`)
fires after claude has already exited successfully, the SIGKILL still targets
the PG and reaps build-ticket.sh's post-claude code path (push at `:541`,
PR-create at `:582`).

Result: commit + `.pr-body.md` survive in `$WORKTREE_DIR`, no remote branch,
EXIT trap (`:99 → :91`) runs and removes the worktree, taking the commit with it.

## Architecture

New phase: `phases/orphan-rescue.sh`. Runs once per daily orchestrator cycle,
**before** stranded-sweep (`phases/stranded-sweep.sh`). Stranded-sweep treats
the same worktree pattern as "requeue and let next build redo the work" —
orphan-rescue handles the subset where claude *did* succeed and we should
publish, not redo. Order: orphan-rescue first; anything orphan-rescue doesn't
publish, stranded-sweep then requeues.

**Daily loop position:**
... Cleanup → Ghost-Sweep → **Orphan-Rescue (new)** → Stranded-Sweep → Janitor ...

## Detection signature (minimum-diff)

For each `/tmp/foreman-build-<Repo>-<N>/` worktree, in order:

1. Path matches `^foreman-build-(.+)-([0-9]+)$` (reuse stranded-sweep.sh:79).
2. Worktree is *idle* (`find -mmin -STRANDED_AGE_MIN -type f` returns nothing,
   reuse `worktree_is_active` from stranded-sweep.sh:62).
3. `git rev-parse --abbrev-ref HEAD` returns `auto/issue-N-*`.
4. `git rev-list --count origin/main..HEAD > 0` (commits present).
5. `git ls-remote --heads origin <branch>` returns empty (no upstream).
6. **`.pr-body.md` exists in worktree root.** This is the orphan-after-commit
   discriminator AND the verification-passed signal (claude only writes this
   after completing its work). It honors foreman#238's gate — without this
   file present, the orphan is NOT a publish target.

All six → orphan-rescue target. Any failure → leave to stranded-sweep.

## Rescue action

For each detected orphan:

1. `cd <worktree>`
2. `git push -u origin <branch>` (capture stderr; on failure → fall-through to
   `mark_orphan` per #238).
3. Construct PR body via the shared helper `lib/pr-body.sh::build_pr_body`
   (see "PR-body factoring" below). On #233 landing, the template emits
   `Refs #N`, not `Closes #N`.
4. `gh pr create --repo <repo> --base main --title <title> --body-file ...`
   (capture stderr; on failure → fall-through to `mark_orphan`).
5. `gh issue comment <N> --repo <repo> --body "PR opened: <url>"`.
6. `move_to_in_review <repo> <N>` (use existing helper).
7. `git worktree remove <worktree> --force` from `repo_to_path <repo>`.
8. Post one log line: `ORPHAN-RESCUE: <repo>#<N> published <pr-url> (head=<sha>)`.

## PR-body factoring (orthogonal cleanup)

Extract `phases/build-ticket.sh:556-576` to `lib/pr-body.sh::build_pr_body`:

```bash
build_pr_body() { # $1=worktree_dir, $2=issue_num, $3=build_cmd_or_empty
  local body_content
  if [ -f "$1/.pr-body.md" ]; then
    body_content=$(cat "$1/.pr-body.md")
  else
    body_content="## Changes
$(git -C "$1" log origin/main..HEAD --pretty=format:'- %s')"
  fi
  [ -n "$3" ] && body_content="$body_content

## Build Check
Local build passed: \`$3\`"
  # Refs after #233 lands; Closes today. Single source of truth.
  printf 'Closes #%s\n\n%s\n' "$2" "$body_content"
}
```

Both `build-ticket.sh` and `orphan-rescue.sh` source it. #233 changes the
`Closes` → `Refs` in one place. No template drift.

## Failure handling

- **Single-orphan rescue fails (push or PR-create).** Fall through to
  `mark_orphan <repo> <issue> <branch> "orphan-rescue-<cause>" "<stderr>"`
  (already exists in `build-ticket.sh:31`). This respects #238: pushes the
  commit under `needs-verification/<branch>`, persists `.pr-body.md` to
  `results/orphan-bodies/`, posts DECISION-NEEDED. **Do not auto-PR on this
  path** — #238 explicitly gates that.
- **Multiple orphans same cycle.** Process serially. Per-orphan error is
  captured + logged; continue to the next. No early bail.
- **Same orphan fails 3 cycles in a row.** Count via existing
  `comment_dedup_or_escalate` dedup signal on tag `orphan-rescue-failed`.
  On 3rd dedup-suppression, add `blocked` label and stop attempting.

## Worktree retention contract

**Before this ticket:** `phases/cleanup.sh:65` runs `git worktree prune` against
each project dir on every cycle. `:73-85` (Tier 0) removes worktrees whose
branch is *merged* — irrelevant for orphans (orphan branch is not merged, has
no remote). The EXIT trap in `build-ticket.sh:91-99` removes the worktree on
process exit — **but** the proximate cause (SIGKILL of the PG) means the trap
doesn't always run. The worktree often survives long enough to be rescued.

**After this ticket:** No change to cleanup.sh. The worktree survives until
either (a) orphan-rescue publishes and removes it, (b) stranded-sweep requeues
and removes it, or (c) a subsequent SIGKILL escapes the trap. Acceptable —
worst case the orphan slips one cycle and is caught on the next.

**Do not** modify cleanup.sh's Tier 0 to skip "has unpushed commits"; the
orphan-rescue phase running before cleanup makes this redundant.

## State signal (FIRE coordination, future)

`orchestrator.sh:134` posts `FIRE START`, `:100` posts `FIRE END`, `:98` posts
`FIRE ABORT`. The orphan signature today is *implicit* — derived from
worktree-state alone. We do **not** wire orphan-rescue to consume FIRE events
in this ticket; the worktree pattern is sufficient and self-contained.

Once foreman#272's event log wave-2 lands, orphan-rescue.sh becomes a producer:
`stage.orphan.detect`, `stage.orphan.publish`, `stage.orphan.fail`. Out of
scope here.

## Logging contract

- `ORPHAN-RESCUE: <repo>#<N> published <pr-url>` — happy path.
- `ORPHAN-RESCUE: <repo>#<N> push-failed → mark_orphan (<err>)` — push fail.
- `ORPHAN-RESCUE: <repo>#<N> pr-create-failed → mark_orphan (<err>)` — PR fail.
- `ORPHAN-RESCUE PHASE: scanned=<N> rescued=<M> mark_orphaned=<K>` — summary.

Sentinel: `results/.orphan-rescue-ran-<DATE>` (idempotent same-day reruns,
matching stranded-sweep pattern).

## CLAUDE.md update

Add to "Daily loop" line in `foreman/CLAUDE.md`:

> ... Cleanup → Ghost-Sweep → **Orphan-Rescue** → Stranded-Sweep → Janitor ...

Add phase to "How It Works" list at position 7a1 (between ghost-sweep at 7
and stranded-sweep at 7a2).

## Test command

`./orchestrator.sh test-orphan-rescue <repo> <issue>` — synthesizes the orphan
condition (creates worktree, adds dummy commit + `.pr-body.md`, does not
push), then dispatches one orphan-rescue iteration. Mirrors the "lazy-init
telemetry needs a manual trigger" lesson in foreman/CLAUDE.md.

## Coordination with sibling tickets

- **foreman#238** — verification gate. Orphan-rescue honors it via the
  `.pr-body.md`-as-signal discriminator (no `.pr-body.md` → not a publish
  target). On rescue-push or PR-create failure, fall through to `mark_orphan`
  which routes through `needs-verification/<branch>` per #238.
- **foreman#233** — Refs not Closes. `lib/pr-body.sh::build_pr_body` is the
  single template both build-ticket.sh and orphan-rescue.sh use. #233 changes
  `Closes` → `Refs` in one place.
- **foreman#272** — event log. Orphan-rescue becomes a producer in #272's
  wave-2; this ticket does not wire emits.

## Policy decision (David's call, 2026-05-17)

The `.pr-body.md`-presence discriminator was the chosen resolution to the
#238 policy collision. Evidence basis: the 4 orphans in 2026-05-14/15 were
all manually rescued; 3/4 merged cleanly (Sage#368, foreman#235, Sage#369),
1/4 closed for unrelated reasons (Sage#370). 4/4 rescue attempts produced
legitimate publishable PRs. `.pr-body.md` is a reliable "claude completed"
signal in practice.
