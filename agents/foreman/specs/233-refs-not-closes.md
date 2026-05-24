# 233 — Refs not Closes: stop auto-closing issues on PR merge

Spec for foreman#233. Body carries Goal/Visual/Scenarios; this doc carries
the file:line map and the deploy-verify signal swap.

## File:line targets (verified 2026-05-17)

### 1. PR body template

`phases/build-ticket.sh:573` — change:

```
Closes #$ISSUE_NUM
```

to:

```
Refs #$ISSUE_NUM
```

### 2. Inspector non-UI verify gate

`phases/inspect.sh:81-99` (`verify_nonui()`). Today:

- PR state == MERGED (keep)
- issue state == CLOSED (drop)

After: PASS = PR merged. Remove the issue-state check entirely. Update the
docstring at line 74 ("PR merged + linked issue closed = PASS" → "PR merged = PASS").

### 3. Close-on-promote (helper change)

`config/board-ids.sh:208-219` (`move_to_done`). Chain `gh issue close` on
successful board move:

```bash
move_to_done() {
  local repo="$1" issue_num="$2"
  if [ -z "${INSPECTOR_RUN_ID:-}" ]; then
    echo "BOARD: move_to_done REFUSED ..." >&2
    return 1
  fi
  if move_board_item "$repo" "$issue_num" "$DONE_OPTION_ID"; then
    gh issue close "$issue_num" --repo "$repo" --reason completed 2>/dev/null || true
    echo "BOARD: Moved ${repo}#${issue_num} to Done (issue closed)"
  else
    echo "BOARD: Failed to move ${repo}#${issue_num} to Done"
  fi
}
```

Idempotent — `gh issue close` on an already-closed issue is a no-op + non-zero,
absorbed by `|| true`.

### 4. Verify-subagent signal swap

This is the load-bearing finding that the original body didn't surface.

**Today:**
- `prompts/verify.md:60-63` instructs the subagent to `gh issue close` on PASS.
- `phases/verify.sh:152, 212` read `ISSUE_STATE == CLOSED` as "deploy verified" → move to Verify column.

**Problem:** If the PR body says `Refs #N`, GitHub doesn't auto-close on merge —
but the verify subagent still closes on PASS, which would mean the issue closes
**before** Done. Defeats the whole change.

**Fix:**

In `prompts/verify.md:55-63` (the PASS section), replace step 2 (`gh issue close`)
with: post the `Automated verification: PASS` comment on the linked issue. Step 3
(comment on PR) stays. So both surfaces get the same proof body; neither closes
the issue.

In `phases/verify.sh:145`, replace:

```bash
ISSUE_STATE=$(gh issue view "$LINKED_ISSUE" --repo "$REPO" --json state -q '.state' ...)
```

with a PR-comment presence check:

```bash
VERIFY_VERDICT=$(gh pr view "$PR_NUM" --repo "$REPO" --json comments \
  --jq '[.comments[] | select(.body | startswith("Automated verification: PASS"))] | length' \
  2>/dev/null || echo 0)
```

Then `if [ "$VERIFY_VERDICT" -gt 0 ]` replaces `if [ "$ISSUE_STATE" = "CLOSED" ]`
at lines 152 and 212. The negation at 152 becomes `if [ "$VERIFY_VERDICT" -eq 0 ]`.

`phases/verify.sh:59` already greps for `Automated verification` to dedupe; the
signal source is the same comment.

### 5. Janitor extension (Done sweep)

`phases/janitor.sh` already sweeps CLOSED-stranded cards to Parking via
`fetch_stranded_items` (filters `c.get('state') == 'CLOSED'`).

Add a second pass — same fetch loop, inverted filter:

- `c.get('state') == 'OPEN'`
- `status == 'Done'`

For each match: `gh issue close <num> --repo <repo> --reason completed`. No
board move (already in Done). Log line: `[janitor] closed N open-in-Done: ...`.

Both passes share the existing GraphQL loop; lift to a single fetch that
returns all items + their state + status, then filter in shell. Keeps GraphQL
calls at one per janitor run.

### 6. Issue-link regex (consumers)

Both currently match `Closes|Fixes|Resolves` and need `Refs` added:

- `phases/verify.sh:45` — regex parsing PR body for linked issue.
- `prompts/review.md:14` — instruction to look for "Closes #N"; expand to "Closes/Refs/Fixes/Resolves #N".

Other repo references (grep `'Closes #'`) hit code-comments only — none parse PR
bodies for link extraction.

## Test plan

- Smoke: `bash scripts/test-inspect.sh` (existing) — exercises `verify_nonui`. Update
  the test fixture to drop the "issue closed" precondition.
- Manual: synthesize a merged-but-open PR locally, run `./orchestrator.sh verify`,
  confirm the comment-presence path moves the item to Verify.
- Manual: run `./orchestrator.sh inspect` against a Verify-column item with an
  open linked issue; confirm `move_to_done` closes it.
- Manual: run `./orchestrator.sh janitor` after manually setting a Done card's
  issue to OPEN; confirm the second pass closes it.

## Coordination

- foreman#209 (Inspector v1): consumes the new `move_to_done` contract for free —
  spec already references `move_to_done`; no edit needed.
- foreman#210 (code-reviewer auto-merge): doesn't call `move_to_done`. No coupling.
- foreman#272 (event log): the new `move_to_done` is a natural `stage.exit`
  emit site for the Verify→Done edge. Defer the emission to #272's producer wave;
  do not bundle.

## Supersedes

- `feedback_awaiting_verification_is_review_queue.md` — the "closed items in
  Awaiting Verification is a feature" memory is a workaround that exists because
  closed != Done today. After this lands, closed == Done is restored; sweep
  Awaiting Verification by closed-state freely. Memory file can be archived.
