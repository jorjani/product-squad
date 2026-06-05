# Idea fixtures for V0.5 demos

Realistic feature ideas to try with `draw` (V0.5 PRIMARY wedge — visual fidelity ladder) and `scope` (V0.5 SECONDARY wedge — commander's intent + scoping).

## Quick run — Visual ladder

`draw "idea"` runs sketch → wireframe → mockup → prototype, auto-opens each rendered HTML in your browser (macOS); on Linux the file paths are printed instead. ~60-120 sec, ~$0.30-0.50 in Claude Code subscription usage.

```bash
./draw "users configure notification preferences across email, push, and in-app channels"
./draw "dark mode toggle for the dashboard sidebar"
./draw "scheduling form for booking 30-minute coffee chats with a mentor"
./draw "feed of recent commits across all repos a user follows"
./draw "comment thread with reply, like, and report actions on each post"
./draw "table view of pending invoices with filter by status and overdue badge"
```

## Quick run — Product cluster

`scope "idea"` writes 7 pre-filled prompts (why → vet → shape → experience → owit → elon → spec) to `/tmp/product-squad-scope-<ts>/`. You paste each into Claude Code in sequence — each stage's output feeds the next.

```bash
./scope "users configure notification preferences across email, push, and in-app channels"
```

The 7 stages teach a transferable product-craft pattern:
1. **/why** — frame the outcome (job-to-be-done)
2. **/vet** — does this serve the mission? (cheap kill — STOP if Off-mission)
3. **/shape** — decide what to build (options menu + capability delta + cuts)
4. **/experience** — articulate the felt user delta
5. **/owit** — map scenarios (On/When/If/Then) + product choices
6. **/elon** — ruthless cut (question, delete, simplify)
7. **/spec** — consolidate the conversation into one authoritative spec

Precursor (run once per product): **/mission** writes `design-system/mission.md` — the vision /vet judges each feature against.

## How to phrase ideas (the meta-skill)

Both demos produce sharper output when the idea is:

- **One sentence** — not three paragraphs of context
- **About a specific UI surface or product motion** — "a form," "a page," "a button," "a feed," "a table," "a workflow"
- **About a specific user** — "students," "candidates," "admins," "viewers," "subscribers"
- **About a specific action** — "upload," "schedule," "filter," "review," "configure"

### Too vague (returns shallow output)

```bash
./draw "matchmaking"
./scope "ai assistant"
```

### Too detailed (tries to do too much; output confused)

```bash
./draw "A comprehensive resume review platform with peer matching, rubric-based scoring, anonymous feedback, gamification, badges, and integration with Canvas LMS for grading..."
```

### Just right

```bash
./scope "Students upload a resume to a course project page so peers can review it before the deadline"
```

The "Just right" shape: **who** does **what** **where** **why** — in one sentence.

## What you'll see per tier

### `draw` output (in `/tmp/product-squad-demo-<ts>/`)

| Tier | File | Content |
|---|---|---|
| T0 sketch | (terminal) | ASCII layout — napkin-level IA |
| T1 wireframe | `wireframe.html` | Multi-state HTML — spatial layout locked, microcopy direction set, all edge cases |
| T3 mockup | `mockup.html` | Single-state hi-fi HTML — brand colors, typography, polished |
| T4 prototype | `prototype.html` | Interactive single-file HTML — state transitions, form behavior |

*(T2 `/schematic` — annotation overlay tier — is documented in the ladder as optional and not included in V0.5; that's why the numbering jumps from T1 to T3.)*

Each HTML auto-opens in your default browser as it's generated (macOS); on Linux the file paths are printed for manual open.

### `scope` output (in `/tmp/product-squad-scope-<ts>/`)

| Stage | File | Content |
|---|---|---|
| 1 | `1-why.md` | /why prompt pre-filled with your idea |
| 2 | `2-vet.md` | /vet prompt pre-filled (mission-fit gate) |
| 3 | `3-shape.md` | /shape prompt pre-filled |
| 4 | `4-experience.md` | /experience prompt pre-filled |
| 5 | `5-owit.md` | /owit prompt pre-filled |
| 6 | `6-elon.md` | /elon prompt pre-filled |
| 7 | `7-spec.md` | /spec prompt pre-filled |

Each file has a header explaining what to copy. `cat <file> | pbcopy` on macOS copies it to clipboard ready to paste into Claude Code.

## From scope to visuals (the bridge)

A `/spec` is richer than a sharp visual wants. `/decompose` splits it into single-surface "who does what where why" phrasings — exactly the shape `draw` reads best — each with a ready `./draw` command:

```
./scope → … → /spec  →  /decompose  →  ./draw "<one phrasing>"
```

The phrasings are already in `draw`'s input format, so the hand-off is copy-and-run. Visualize the surface `/decompose` recommends first; draw the rest only if they earn it.

## After the demo

The pattern transfers. Each skill file (`skills/sketch/SKILL.md`, `skills/wireframe/SKILL.md`, etc.) is a reusable scoping artifact you can adopt in your own projects — they're written as Claude Code skills with auto-trigger descriptions, but the prompts work in any agent that takes stdin and emits text.

For the commands NOT bundled in V0.5 (e.g., `/flow`, `/api`, `/migrate`, `@eng-deep-dive`), see `manifest.yaml` → `v1_roadmap` — they're planned for V1 (3-4 weeks).
