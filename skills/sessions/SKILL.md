---
name: sessions
description: List recent Claude Code sessions across projects with last-active time, context usage, message count, and a resume ID. Use when the user asks "what sessions are open", "where did I leave off", or wants to resume a specific session from the CLI. Distinct from /list-capabilities, which lists installed skills and commands rather than running sessions.
---

# /sessions — List Recent Claude Code Sessions

Show recent Claude Code sessions across projects with their status, so the user can see what's in flight and resume the right one.

## Process

Claude Code stores per-session transcripts as `.jsonl` files under `~/.claude/projects/<encoded-project-path>/<session-uuid>.jsonl`. Enumerate them and, for each, report:

- **Last Active** — file modified time.
- **Project** — decoded from the project directory name.
- **CTX** — approximate context-window usage (from the transcript size / token count).
- **Msgs** — number of user messages.
- **Last Message** — the most recent user message (truncated).
- **Session ID** — the short UUID, used to resume.

Sort by last-active, newest first. Present as a markdown table so it renders in the chat panel.

```bash
ls -t ~/.claude/projects/*/*.jsonl 2>/dev/null | head -40
```

If a project-local helper script exists for this, prefer it and present its raw markdown output without reformatting.

## After the table

Remind the user how to act on it:
- Resume a specific session: `claude -r <session-id>`
- Continue the most recent session in the current dir: `claude -c`

## Rules

- Newest first — the session they want is usually at the top.
- Truncate long last-messages so the table stays scannable.
- Read-only — never modify or delete session files.

$ARGUMENTS
