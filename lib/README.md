# lib/

Shared utilities. The agent abstraction layer lives here.

## V1 files

| File | Purpose | Milestone |
|---|---|---|
| `agent.sh` | The agent-agnostic abstraction (sourced by every phase script) | M3 |

## `lib/agent.sh` shape (M3)

```bash
agent_run() {
  # Args: --prompt FILE --model TIER --budget USD --profile NAME [--cwd DIR]
  # Reads $AGENT env var, dispatches to _agent_claude / _agent_codex / etc.
  case "$AGENT" in
    claude) _agent_claude "$@" ;;
    codex)  _agent_codex  "$@" ;;
    *)      echo "agent.sh: unknown AGENT=$AGENT" >&2; return 2 ;;
  esac
}
```

Phase scripts call `agent_run` instead of `claude -p` directly. Swap `$AGENT` to change the backend.

## Profiles

The `--profile` arg routes per-agent flag translation:
- `build` — needs filesystem edit + commit
- `review` — text-in / JSON-out
- `triage` — one-shot text classification
- `inspect` — classify + judge

## Tested adapters in V1

- **claude** (default) — pass-through to `claude -p`
- **codex** — Codex CLI (`codex exec --full-auto`)

## Status

Empty in v0.1.0-pre. Populated in M3 (agent-agnostic abstraction milestone).
