---
name: list-capabilities
description: Enumerate the skills and commands available in the current environment by scanning the live skill and command directories — no hardcoded list. Use when the user asks "what can you do here", "what skills are available", or wants a map of the installed bundle. Distinct from /sessions, which lists running Claude Code sessions rather than capabilities.
---

# /list-capabilities — What's Available Here

Discover and list the skills and commands installed in the current environment. **Discover dynamically — never recite a hardcoded list**, since installed bundles vary.

## Process

1. **Scan for skills.** List the skill directories in scope — typically `.claude/skills/*/SKILL.md` in the project and any active plugin's `skills/` folder. Each subfolder name is a skill.
2. **Scan for commands.** List `.claude/commands/*.md` in scope (project-level and user-level if present).
3. **Read the trigger line.** For each, pull the `description` from the SKILL.md frontmatter, or the first heading/tagline of a command file, so each entry has a one-line "what it does."
4. **Group and sort.** Group by source (this project / plugin / user-level), sort alphabetically within each group.

```bash
# Skills in scope
ls -d .claude/skills/*/ 2>/dev/null
# Commands in scope
ls .claude/commands/*.md 2>/dev/null
```

If the user names a filter, narrow to entries matching it.

## Output Format

```
## Capabilities — {scope}

### Skills
- /skillname — one-line description
- ...

### Commands
- /commandname — one-line description
- ...
```

## Rules

- **No manual maintenance** — if a capability exists as a file, it shows up; if a file is gone, it doesn't.
- Skills and commands are listed separately so the user can tell which mechanism each uses.
- Keep each description to one line — this is a menu, not docs.

$ARGUMENTS
