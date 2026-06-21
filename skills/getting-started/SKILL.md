---
name: getting-started
description: First-run orientation for anyone who just installed a Claude Code plugin — detect what's actually installed (skills, commands, agents), surface 3-5 starter commands grouped by cluster, and show one concrete "build something in 5 minutes" path. Use when a user is new to a plugin and asks "what can this do" or "how do I start." Meta — works for any plugin, not just this one. Distinct from /list-capabilities (a flat enumeration) — this one curates a guided on-ramp.
---

# /getting-started — First-Run Orientation

**Role:** You are the welcome guide. A user just installed a plugin and doesn't know where to begin. Detect what's present, point them at the highest-value starting commands, and walk them through one end-to-end win.

**Usage:** `/getting-started`

**Delivers:** A short orientation — what's installed, 3-5 starter commands by cluster, one 5-minute build path, and where to read more. Curated, not exhaustive (that's `/list-capabilities`).

---

## Process

### 1. Detect what's installed
Scan the live directories — don't assume from memory:
- **Skills** — `skills/*/SKILL.md` (and `.claude/skills/`). Read each frontmatter `name` + `description`.
- **Commands** — `.claude/commands/*.md` if present.
- **Agents** — `.claude/agents/*.md` or an `agents/` directory.
- **Manifest** — `manifest.yaml` / `.claude-plugin/plugin.json` for the bundle's own grouping and intent.

Report the counts plainly: "12 skills, 3 agents, 0 standalone commands."

### 2. Surface starters by cluster
Pick **3-5** commands a new user should run first. Group them by the bundle's own clusters (read them from the manifest — don't invent groupings). For each starter: the command, one line on what it does, and when to reach for it. Lead with the single most representative command of the bundle.

### 3. Show a "build something in 5 minutes" path
One concrete end-to-end sequence the user can run right now to see the bundle work. Chain real commands with arrows and say what each produces. Example shape (adapt to what's installed):

```
/sketch "<idea>"   → ASCII layout in terminal
/wireframe         → mid-fi HTML, multi-state
/mockup            → brand-styled HTML
/handoff           → one openable showcase
```

Pick the shortest path that produces something the user can see or open. If the bundle has a single headline demo, use that.

### 4. Point to deeper docs
Name where to learn more — `README.md`, `QUICKSTART.md`, `manifest.yaml`, `/list-capabilities` for the full catalog. One line each, not a tour.

---

## Output Template

```markdown
## Welcome — <bundle name>

**Installed:** N skills · N agents · N commands

### Start here
1. `/<command>` — [what it does]. Run when [trigger].
2. ...

### Build something in 5 minutes
`/<a>` → `/<b>` → `/<c>`
[one line: what you'll have at the end]

### Learn more
- `README.md` — [what's there]
- `/list-capabilities` — full command catalog
```

---

## Rules

1. **Detect, don't recite.** Scan the actual directories. A plugin the user customized won't match any baked-in list.
2. **Curate to 3-5 starters.** The full list is `/list-capabilities`. This skill's value is *choosing* the first few.
3. **One runnable path.** The 5-minute sequence must be real commands that chain into a visible result — not a feature tour.
4. **Bundle-agnostic.** Read groupings from the manifest. Don't hardcode this bundle's clusters — the skill should orient a user inside any plugin.
5. **Short.** A new user is deciding whether this is worth their time. One screen, lead with the single best entry point.

$ARGUMENTS
