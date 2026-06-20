---
name: deploy-status
description: Walk the full deploy chain for a commit SHA and report what's done, in flight, or stuck — CI → platform picked up the commit → build/migration → new container live → endpoint serving new code. Read-only; never triggers redeploys. Uses Railway as the example platform; the chain transfers to Render, Fly, or Vercel — swap the platform's status/log commands. Use when a push "should be live" but you can't tell whether it actually deployed. Pairs with /deploy-trigger (which fires the deploy) and /verify (prove-it-works gate).
---

# /deploy-status — Deploy Chain Status for a Commit

Generic purpose: answer "did commit X actually reach production, and if not, where did it stall?" by walking the deploy chain phase by phase instead of polling `uptime` as a deploy proxy — which wastes time and lies when the container is crash-looping.

**This skill uses Railway as the example platform.** The five-phase chain is platform-agnostic; replace `railway status` / `railway logs` with `render`, `flyctl status`, or `vercel inspect` for your platform.

**Usage:** `/deploy-status [sha]` (defaults to the current project's `origin/main` HEAD)

## Workflow — stop on the first FAIL and report the chain so far

### 1. Locate the project + its deploy service

Validate the SHA exists (`git rev-parse <sha>`; default to `git fetch origin main -q && git rev-parse origin/main`). If multiple services exist (web, worker), default to the user-facing one and note the others.

### 2. CI status

```bash
gh run list --repo <repo> --commit <sha> --json conclusion,status,name --limit 5
```

Report each check. `IN_PROGRESS` → "still running." Any `failure` → STOP, link the failing run.

### 3. Platform picked up the commit

```bash
railway status --json   # or: render services, flyctl status, vercel inspect <url>
```

Compare the platform's latest-deployment commit hash to your SHA. No match → the Git→platform webhook hasn't fired yet, or it's broken. Report and stop.

### 4. Build / migration phase

Query the deployment logs for the latest deployment. Look for error markers, failed DB migrations, container restart loops.

**The distrust-exit-code-zero nugget:** an entrypoint wrapper that prints "exit code: 0" can mask a failure in an *inner* script (a migration that rolled back, a seed that threw). When a migration looks suspicious, read the migration system's own log table (e.g. `_prisma_migrations`, `schema_migrations`) for the real error — don't trust the wrapper's summary line.

### 5. New container is live with new code

```bash
curl -sS -m 5 https://<project-domain>/api/health
```

Compare reported `uptime` to the deploy record's timestamp. Uptime exceeds the gap by minutes → new container is live. Uptime is hours → the OLD container is still serving and the new one never took over. No health endpoint → fall back to a known route + header, or note "no health probe."

### 6. Endpoint serving new code

Hit the routes the change touched; inspect the response for the new behavior. Optionally include a `git diff <prev-sha> <sha> -- <path>` snippet so the user can spot-check what *should* be visible.

## Output format

A 6-row table, one row per phase, status emoji + one-line note:

```
| Phase | Status | Note |
|-------|--------|------|
| 1. SHA exists        | ✅ | a891926 on main |
| 2. CI                | ✅ | 4/4 checks passed |
| 3. Platform picked up | ✅ | latest deployment commit matches |
| 4. Build / migration | ❌ | migrations log shows CHECK constraint violation |
| 5. New container live | — | (skipped — phase 4 failed) |
| 6. Endpoint serving  | — | (skipped) |
```

Then 1–2 sentences of recovery guidance for whatever failed.

## Hard rules

- **Read-only.** Never trigger redeploys, change env vars, or push. Diagnosis only — to fire a deploy use [`deploy-trigger`](../deploy-trigger/SKILL.md).
- **No long polling loops.** One-shot check. For polling, the user re-invokes (`/loop 1m /deploy-status <sha>`).
- **Be honest about blind spots.** If logs are paywalled or there's no public health endpoint, say so and report what you DID confirm.

## Skip conditions

If the project doesn't deploy to a supported platform (e.g. a Vercel-only project while you've only wired the Railway path), say so up front and note the missing adapter as a follow-up.
