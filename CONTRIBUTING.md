# Contributing

Bundle conventions. Read before opening a PR.

## Workflow

1. Open an issue first. Scope lives in the issue body; PRs reference it via `Closes #N`.
2. Create a worktree from `origin/main` under `.claude/worktrees/`:

   ```bash
   git fetch
   git worktree add -b psq<n>-<slug> .claude/worktrees/psq<n>-<slug> origin/main
   cd .claude/worktrees/psq<n>-<slug>
   git branch --unset-upstream
   ```

   Worktree placement under `.claude/worktrees/` keeps them out of root globbing. The `--unset-upstream` step is required — the branch tracks `origin/main` on create and will fast-forward `main` on push otherwise.

3. Commit on the branch. One commit per PR is the norm. Message format: `<type>(<scope>): <subject>` (see `git log` for precedent).
4. Push and open a PR. Use the template — Summary + Test plan are required sections.
5. Run the `code-reviewer` subagent against the diff before requesting human review. It returns severity-ranked findings (Blocker / Major / Nit) and is the merge gate. Fix Blockers before merging.
6. Merge via the REST API from the worktree (the local-checkout warning from `gh pr merge` is benign):

   ```bash
   gh api repos/jorjani/product-squad/pulls/<N>/merge -X PUT -f merge_method=squash
   ```

## Smoke test

Run `./tests/smoke.sh` from the repo root before pushing. It wraps `bash -n` on the wrapper scripts, validates `manifest.yaml`, and runs `claude plugin validate .`. Non-zero exit = don't push.

## Adding a new flavor

Flavors live in `.studio/brand-flavors/<name>.md`. Each file overlays styling opinions (canvas, primary color, type, radii) on top of the semantic primitives in `.studio/components.md`. To add one:

1. Copy an existing flavor (`linear.md` is the leanest baseline) to `<name>.md`. Edit the canvas, palette, typography, and radii sections.
2. Register the new flavor under `v0_5.assets` in `manifest.yaml` with a one-line purpose.
3. Verify `draw "test idea"` with `FLAVOR=<name>` produces the expected look on T3 mockup and T4 prototype.
4. Open a PR titled `feat(flavor): add <name>` with a screenshot of the mockup tier in the body.

Unknown flavor names fall back to `linear` with a warning — confirm the fallback is gone once your flavor is registered.

## What doesn't go in a PR

- Generated output under `/tmp/product-squad-*` — these are ephemeral demo dirs.
- Secrets. The bundle uses subscription auth; no API keys live in this repo.
- `--no-verify`, force-pushes to `main`, or amending merged commits.
