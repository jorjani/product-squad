---
name: deploy-trigger
description: Run a pre-flight checklist before deploying, then trigger the deploy — verify the start command, health endpoint, env vars, local typecheck/build, and git state pass BEFORE the platform attempts a deploy, so failures surface on your laptop in seconds instead of in a remote build minutes later. Uses Railway as the worked example; the checklist transfers to Render, Fly, or any push-to-deploy platform. Use right before shipping a service. Pairs with /deploy-status (post-deploy diagnosis) and /ship (the full landing workflow).
---

# /deploy-trigger — Pre-Flight Checklist + Deploy

Generic purpose: catch the deploy failures you CAN catch locally (type errors, missing env vars, a health endpoint that doesn't exist, an unpushed commit) before the platform spends minutes on a build that was doomed at push time.

**This skill uses Railway as the worked example.** The phases are platform-agnostic — swap `railway up` / `railway variables` for your platform's deploy + env commands (`render deploy`, `flyctl deploy`, `vercel --prod`).

**Usage:** `/deploy-trigger` (check + deploy) · `/deploy-trigger check-only` (checklist, no deploy)

## Phase 1 — Pre-flight checklist (report pass/fail per item)

### 1. Project identity
- Platform config file exists? (`railway.json`, `render.yaml`, `fly.toml`)
- `package.json` start command — what is it?
- Dockerfile present? (if yes, that path overrides the buildpack)

### 2. Build config
- `startCommand` matches an actual script in `package.json`.
- `healthcheckPath` points to a **dedicated** health endpoint, not `/`.
- That endpoint exists in server code and returns 200.

### 3. Native deps (if an ORM with a native engine is used, e.g. Prisma)
- The generate step is in the build command.
- Required system packages are declared (e.g. `openssl` for Prisma).
- On a first deploy, remind to push the schema to the remote DB before traffic hits.

### 4. Environment variables
- Read `.env` / `.env.example` for required names.
- List the platform's vars and diff — flag any missing.
- DB URL uses a platform reference (`${{Postgres.DATABASE_URL}}`), not a hardcoded string.
- No secrets committed to tracked files.

### 5. TypeScript & build (the highest-ROI check)
- `tsc --noEmit` passes. **BLOCKING.** Most push-to-deploy platforms do NOT run type checks — a type error slips through the build and becomes a runtime 500. Catch it locally.
- `bun run build` (or `npm run build`) succeeds. Show build time + output size.

### 6. Git state
- Relevant changes committed.
- Pushed to remote (Git-integration deploys need the push).

## Phase 2 — Report

```
Pre-Flight Checklist: <project>
═══════════════════════════════════════
✓ platform config exists
✓ Start command valid: bun run start
✓ Healthcheck: /health (verified in code)
✓ Native deps OK
✗ Missing env var: MAILER_API_KEY
✓ tsc --noEmit clean
✓ Git clean, pushed
═══════════════════════════════════════
Result: 6/7 passed — 1 issue to fix
```

## Phase 3 — Deploy (unless `check-only`)

If all checks pass (or the user approves despite warnings):

1. Trigger the deploy (`railway up --detach`, or your platform's equivalent).
2. Wait ~30s, then query deployment status via the platform's API/CLI.
3. If FAILED, fetch runtime logs and surface the actual error.
4. Report success or failure with actionable detail — then hand off to [`deploy-status`](../deploy-status/SKILL.md) to confirm the new container is actually serving.

## Reference: Railway gotchas (example platform)

| Gotcha | Detection | Fix |
|--------|-----------|-----|
| Bun blocks postinstall | `prisma generate` missing from buildCommand | add `bunx prisma generate` to build |
| Missing OpenSSL | no `aptPkgs: ["openssl"]` with Prisma | add to `railway.json` |
| Wrong healthcheck | `healthcheckPath: "/"` | point to a JSON `/health` endpoint |
| TypeScript errors deployed | `tsc --noEmit` skipped | platform won't block on TS — check locally first |
| CLI context drift | `railway status` shows wrong project | `railway link -p <id> -s <service>` |

## Hard rules

- **Don't skip checklist steps.** Each maps to a real production failure mode.
- **Type-check locally — always.** The platform won't.
- **Health endpoint is dedicated, never `/`.** A root route that happens to 200 hides a dead app.
