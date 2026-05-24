# commands/

Curated dev-workflow slash commands. Each command is a self-contained markdown prompt with YAML frontmatter.

## V1 set (~15-20, populated in M2)

See [`../manifest.yaml`](../manifest.yaml) `commands.planned` for the canonical list. Includes the design ladder (`/sketch → /wireframe → /mockup → /prototype`), the spec pipeline (`/shape → /spec → /owit → /decompose → /flow`), and execution helpers (`/verify`, `/is-ready`, `/elon`, `/simplify`, `/investigate`).

## Conventions

- One job per command (no kitchen-sink chains)
- Fail loudly when assumptions break
- Read existing context (`.studio/`, `manifest.yaml`) — never hardcode
- Idempotent (re-running is safe)
- Composable (pipe to other commands, not just to humans)

## What's NOT in V1

Project-specific commands (TrackRec board ops, Jobber pipeline, Coaches RLS, Amp brand voice, content/podcast workflows) — those are private to the operator's projects and don't belong in the OSS bundle. The *pattern* of writing your own is documented in `docs/project-specific-commands.md` (M6).

## Status

Empty in v0.1.0-pre. Populated in M2.
