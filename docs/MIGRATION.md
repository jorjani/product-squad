# Migration

This bundle is a forked snapshot of David's running pipeline. **It is NOT a live mirror.**

## Source SHAs (V0.5 cut)

Frozen on 2026-05-24:

| Repo | Source | SHA |
|---|---|---|
| `agents/foreman/` | `getqatalyst/foreman` | `d4738a47ea633586f1780087ea60ebea6c795a55` |
| `agents/sarge/` | `getqatalyst/sarge` | `6ad9a83876b988550740b9a3c1b00f70e41d8fa1` |
| `agents/code-reviewer.md` | `~/.claude/agents/code-reviewer.md` | (same date) |
| `agents/build-fixer.md` | `~/.claude/agents/build-fixer.md` | (same date) |
| `agents/sarge/sarge-subagent.md` | `~/.claude/agents/sarge.md` | (same date) |

## Excluded via rsync (not in bundle)

`rsync -a --exclude=.git --exclude=metrics --exclude=results --exclude=node_modules --exclude=.claude/worktrees`:

- `.git/` — bundle gets fresh history
- `metrics/` — operational telemetry with private project names + PR numbers
- `results/` — debug logs with private content (full Claude transcripts of past builds)
- `node_modules/` — dependency installs
- `.claude/worktrees/` — local-only work-in-progress

## Scrubbed in V0.5 (full inventory)

These removals happened AFTER the initial rsync, in response to the V0.5 code-review audit (jorjani/product-squad#2 reviewer findings):

1. **`agents/sarge/BUILD-BRIEF.md:101-107`** — replaced personal business-priority stack (immigration > thought leadership > products; named a client) with a pointer to `.index.json`'s `priority` field.

2. **`agents/sarge/plans/`** (entire directory removed, 6 files) — these were Sarge's operational planning artifacts for David's specific client engagements:
   - `jobber-actions.md` — **contained a live Sentry auth token + DSN** (rotated separately; bundle redacted before merge)
   - `jobber-northstar-referral-network.md` — Jobber product strategy, revenue model, owner disclosure
   - `jobber-pipeline-consolidation-scope.md` — operational scope tracker
   - `m1-m2-verification.md` — verification checklist with private branch names + issue numbers
   - `pipeline-automation-improvements.md` — internal pipeline notes
   - `council-implementation.md` — design notes (removed for consistency; can re-add later if pedagogically useful)

   None of these are pedagogical content for a bundle adopter — they're operational artifacts that belong in David's private workspace, not in a shared bundle.

3. **`agents/sarge/sarge-subagent.md`** (working-directory escape hatch) — added "(or the target repo's path if specified in the prompt)" to the working-directory line, matching the pattern from `agents/code-reviewer.md`. Also changed "David" → "the operator" in the same paragraph. Other Qatalyst/jorjani references remain (full scrub is V1).

## NOT scrubbed in V0.5 (bundled as-is)

Visible-but-acceptable for V0.5; full scrub lands in V1:
- `getqatalyst` GitHub org references throughout (~173 hits)
- `jorjani` GitHub username references (~9 hits)
- `/Users/jorjani/...` hardcoded paths
- `MacBook-Pro-2.local` hostname references
- David's specific Project Board #5 IDs
- Slack channel naming conventions tied to David's workspaces
- References to David by name in foreman/sarge agent context (beyond sarge-subagent.md which IS scrubbed)

**Honest framing:** read `agents/foreman/` and `agents/sarge/` as **documentation of an opinionated system that runs on David's box**, not as portable code you can `./orchestrator.sh` against your own GitHub org. The V0.5 demo path (`bin/scope` + `commands/` + `examples/`, shipping in PR #3) IS scrubbed and IS runnable.

V1 (3-4 weeks) does the full scrub. See top-level `manifest.yaml` → `v1_roadmap`.

## Rebase protocol (when upstream evolves)

When `getqatalyst/foreman` or `getqatalyst/sarge` advances and the bundle needs to catch up:

```bash
# Re-rsync with the same excludes (overwrites with latest)
rsync -a --exclude=.git --exclude=metrics --exclude=results \
  --exclude=node_modules --exclude=.claude/worktrees \
  /path/to/foreman/ ./agents/foreman/

# Update this file's SHA table with the new HEAD
git -C /path/to/foreman rev-parse HEAD

# CRITICAL: Re-scan for secrets and operational content
# The V0.5 audit found a live Sentry token in sarge/plans/ that the
# rsync excludes didn't catch. Run this before committing the rebase:
grep -rE 'sntryu_|sk_live_|ghp_|ghs_|github_pat_|xoxb-(?!test)|xoxp-(?!test)' agents/

# Re-apply demo-path scrubs (commands/, bin/scope, examples/)
# These don't auto-flow from upstream; they're V0.5-specific layers.

# Re-apply scrubs from the inventory above (BUILD-BRIEF.md, plans/,
# sarge-subagent.md escape hatch). After V1's full scrub, fewer scrubs
# will be needed per-rebase.
```

After V1's full scrub, rebases get easier (fewer ongoing manual scrubs needed).

## Why fork-snapshot vs symlink bridge?

Considered: a symlink bridge keeping `~/Projects/foreman` and `agents/foreman/` in sync. Rejected for V0.5 because:

1. **Two masters problem** — David's live cron needs `getqatalyst`-coupled code; the bundle needs scrubbed code. A live symlink can't serve both.
2. **Outsider experience** — a symlink-bridged bundle would need "if you're the original author, also do X" caveats in QUICKSTART. Forked snapshot keeps the outsider experience clean.
3. **Reversibility** — if V1 plans change, the snapshot is independent. The bridge would entangle the two.
4. **Security** — a live symlink means any secret accidentally written to David's foreman/ would auto-propagate to the bundle. The snapshot model + the scrub inventory above gives a clear audit boundary.

Bridge may return in V1 if the divergence between upstream and bundle becomes painful.
