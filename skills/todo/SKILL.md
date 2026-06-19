---
name: todo
description: Per-project task parking lot backed by a plain TODO.md — list, add, complete, and pick up tasks, each linking to one detail source (a task file or a GitHub issue). Use to capture work without losing it, or to resume a parked task with full context. Pairs with /pickup (resume a whole session) and /checkpoint (mid-session snapshot); /mochary zooms out from the list to the one thing that matters.
---

# /todo — Project Task Parking Lot

A lightweight, file-backed task list. One `TODO.md` per project is the single source — no duplication into other systems.

**Usage:**
- `/todo` — show all open todos for the current project
- `/todo [project]` — show todos for a specific project
- `/todo add [description]` — add a new todo
- `/todo done [name]` — mark a todo done

## How It Works

1. **Identify the project** from the argument, the current directory, or by asking.
2. **Read `{project}/TODO.md`** — the persistent task file for that project.
3. **Display the list** with status, context, and linked files. Number each item so the user can say "pick up 3".
4. If the user says "do X" or "pick up X", **read the linked detail file** and load the project's context before starting.

## TODO.md Format

```markdown
# [Project] — Active Tasks

## Active

- [ ] **Task name** — one-line description
  - Context: [why this matters, who asked for it]
  - Detail: `path/to/task-file.md` or GitHub issue URL
  - Priority: P1/P2/P3

## Done

- [x] **Task name** — Completed YYYY-MM-DD
```

## Behavior

**Showing the list:**
- Read the project's `TODO.md`, display it cleanly — name, one-line context, priority.
- Number each item so the user can reference it by number.

**"do X" / "pick up X":**
- Find the matching todo by name or number.
- Read the linked detail file (task markdown, GitHub issue, etc.).
- Load the project's context, summarize what needs to happen, and ask how to proceed before working.

**Adding a todo:**
- Append to the Active section of `TODO.md`.
- If a detail file exists, link it. If a GitHub issue exists, link that instead.

**Marking done:**
- Move the item from Active to Done with the completion date.

## Rules

- `TODO.md` is the single source — don't duplicate into other systems.
- Each todo links to ONE detail source (task file OR GitHub issue, not both).
- If a task file was converted to a GitHub issue, update the link.
- Don't auto-create `TODO.md` — ask the user first if it doesn't exist.

$ARGUMENTS
