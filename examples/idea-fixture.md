# Idea fixtures for the V0.5 visual demo

A handful of realistic feature ideas for `bin/visual`. Each one is phrased to give the visual ladder enough specificity to produce non-shallow output.

## Quick run

Pick an idea, paste it in:

```bash
./bin/visual "students upload resume to course project for peer review"
```

Or use one of these:

```bash
./bin/visual "dark mode toggle for the dashboard sidebar"

./bin/visual "scheduling form for booking 30-minute coffee chats with a mentor"

./bin/visual "feed of recent commits across all repos a user follows"

./bin/visual "settings page where users can configure notification preferences per channel"

./bin/visual "table view of pending invoices with filter by status and overdue badge"
```

## How to phrase ideas (the meta-skill)

The visual ladder produces sharper output when the idea is:

- **One sentence** — not three paragraphs of context
- **About a specific UI surface** — "a form," "a page," "a button," "a feed," "a table"
- **About a specific user** — "students," "candidates," "admins," "viewers," "subscribers"
- **About a specific action** — "upload," "schedule," "filter," "review," "configure"

### Too vague (returns shallow output)

```bash
./bin/visual "matchmaking"
./bin/visual "ai assistant"
./bin/visual "make it better"
```

### Too detailed (tries to do too much, often confused)

```bash
./bin/visual "A comprehensive resume review platform with peer matching, rubric-based scoring, anonymous feedback, gamification, badges, and integration with Canvas LMS for grading..."
```

### Just right

```bash
./bin/visual "Students upload a resume to a course project page so peers can review it before the deadline"
```

The "Just right" shape: **who** does **what** **where** **why**.

## What you'll see per tier

Each tier writes to `/tmp/product-squad-demo-<timestamp>/`:

| Tier | File | Content |
|---|---|---|
| T0 sketch | (terminal) | ASCII layout — napkin-level IA |
| T1 wireframe | `wireframe.html` | Multi-state HTML — spatial layout locked, microcopy direction set, all edge cases |
| T3 mockup | `mockup.html` | Single-state hi-fi HTML — brand colors, typography, polished |
| T4 prototype | `prototype.html` | Interactive single-file HTML — state transitions, form behavior |

Each HTML file auto-opens in your default browser as it's generated. Total run: ~60-120 seconds + ~$0.30-0.50 in Claude Code subscription usage.

## After the demo

The pattern transfers. Each command (`commands/sketch.md`, `commands/wireframe.md`, `commands/mockup.md`, `commands/prototype.md`) is a reusable scoping artifact you can adopt in your own projects — they're written as Claude Code slash commands, but the prompts work in any agent that takes stdin and emits text.

For the secondary cluster (commander's intent + scoping), see the product cluster in `commands/{why,shape,experience,owit,elon}.md`.
