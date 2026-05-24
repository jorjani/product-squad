# cloud/

Deploy paths. Product Squad supports two tiers:

## Smooth path (V1 primary): Railway

- One-click "Deploy on Railway" button
- Pre-baked `Dockerfile` (bun + git + gh + claude CLI)
- Railway cron service (5x/day default schedule)
- Railway Volume mount at `/workspace` for persistent worktrees
- 30-min path from click to first autonomous PR (if you have 3 secrets ready)

Files: [`railway/`](railway/) (populated in M5)

## Hacker path: laptop

- macOS launchd plist (current Foreman setup)
- Linux cron / systemd notes
- Self-host Docker Compose

Files: [`laptop/`](laptop/) (populated in M5)

## Fallback (documented, not bundled)

- GitHub Actions cron (free for public repos; no persistent volume)
- Fly.io (alternative cloud; fine-grained process control)

## Required env vars

Per [`../manifest.yaml`](../manifest.yaml) `cloud.primary.required_env`:
- `GITHUB_TOKEN` — PAT classic with `repo`, `workflow`, `project`, `write:org` scopes
- `ANTHROPIC_API_KEY` — works with `claude -p` headlessly (no OAuth dance)
- `GITHUB_ORG` — your GitHub org slug
- `PROJECT_NUMBER` — your GitHub Project board number

Optional: `SLACK_WEBHOOK_URL`, `CODE_REVIEW_MERGE_ALLOWLIST`.

## Status

Empty in v0.1.0-pre. Populated in M5 (cloud setup milestone).
