# QUICKSTART

5 minutes from clone to first rendered HTML in your browser.

## Prereqs (one-time)

1. **Install Claude Code** — [https://claude.com/claude-code](https://claude.com/claude-code)
2. **Sign in via subscription** — run `claude /login` once. Saves OAuth to `~/.claude/.credentials.json`.
3. **Auto-open in browser:** `draw` uses `open` on macOS (built-in) to auto-launch HTML. On Linux it falls back to printing the file path — open manually, or alias `open=xdg-open` first.

### ⚠️ ANTHROPIC_API_KEY gotcha

If `ANTHROPIC_API_KEY` is set in your shell environment, it **shadows** Claude Code subscription auth (precedence #3 vs #6 in [Claude Code auth docs](https://code.claude.com/docs/en/authentication)) and may fail with org-mismatch errors.

If you see `authentication_error`:
```bash
unset ANTHROPIC_API_KEY
```

## Get the bundle

Two paths. Pick one.

**A. Plugin install** (works today — the public repo is its own marketplace)

```bash
# Inside Claude Code:
/plugin marketplace add jorjani/product-squad
/plugin install product-squad@product-squad
```

Surfaces the bundle's skills as `/product-squad:<name>` in Claude Code's slash-command list — start with `/product-squad:getting-started`. No clone needed.

**B. Clone and run** (the cold-start path; what the rest of this doc assumes — works today)

```bash
git clone https://github.com/jorjani/product-squad.git
cd product-squad
```

When CWD is the bundle, Claude Code auto-discovers `/visualize`, `/scope`, `/onboard` from `.claude/skills/`. These three are clone-only; the plugin install does not include them.

## Demo 1 — Visual fidelity ladder (PRIMARY)

```bash
./draw "users configure notification preferences across email, push, and in-app channels"
```

What happens:

1. **T0 sketch** — ASCII layout printed to your terminal (~5 sec, ~$0.02)
2. **T1 wireframe** — multi-state HTML written to `/tmp/product-squad-demo-<ts>/wireframe.html`. Auto-opens in browser. (~30 sec, ~$0.08)
3. **T3 mockup** — hi-fi HTML with brand tokens written to `mockup.html`. Auto-opens. (~45 sec, ~$0.12)
4. **T4 prototype** — interactive HTML with state transitions written to `prototype.html`. Auto-opens. (~60 sec, ~$0.20)

*(T2 `/schematic` — annotation overlay — is documented as optional in the visual ladder and not included in V0.5. The numbering jump from T1 to T3 is intentional.)*

Total: ~2 minutes, ~$0.30-0.50 in Claude Code subscription usage.

### Try your own idea

```bash
./draw "dark mode toggle for the dashboard sidebar"
./draw "scheduling form for booking 30-minute coffee chats"
./draw "feed of recent commits across all repos a user follows"
```

See [`examples/idea-fixture.md`](examples/idea-fixture.md) for phrasing guidance (who + what + where + why pattern).

### Switch the brand flavor

The visual ladder ships with 4 aesthetic vocabularies. Each is a complete brand opinion — tokens + Do/Don'ts that stop the model from defaulting to vanilla Tailwind output.

```bash
FLAVOR=linear  ./draw "your idea"   # default; dark, agent-OS, Inter, monospace identifiers
FLAVOR=apple   ./draw "your idea"   # premium consumer marketing, white, near-monochrome, generous whitespace
FLAVOR=airbnb  ./draw "your idea"   # marketplace, white, coral primary, Plus Jakarta Sans, soft-shadow cards
FLAVOR=uber    ./draw "your idea"   # operational console, pure black on white, heavy display type
```

Open [`examples/flavor-comparison.html`](examples/flavor-comparison.html) in your browser to see all four rendered on the same UI side-by-side.

Running the same idea through two flavors back-to-back is the fastest way to feel how design tokens shape output. See [`design-system/design.md`](design-system/design.md) for the full flavor catalog + how to author your own.

### Override the demo brand string

By default the visual ladder uses a placeholder brand (`AcmeU 101 · ReviewLab`) instead of inventing real-world identifiers in chrome (page titles, breadcrumbs, course codes). To pin a specific brand:

```bash
BRAND="Acme Talent" FLAVOR=linear ./draw "candidates submit applications for review"
```

## Demo 2 — Commander's intent + scoping (SECONDARY)

```bash
./scope "users configure notification preferences across email, push, and in-app channels"
```

What happens:

1. 7 pre-filled prompt files written to `/tmp/product-squad-scope-<ts>/`:
   - `1-why.md` — frame the outcome (job-to-be-done)
   - `2-vet.md` — does this serve the mission? (cheap kill — STOP if Off-mission)
   - `3-shape.md` — decide what to build (options + capability delta + cuts)
   - `4-experience.md` — articulate user delta
   - `5-owit.md` — map scenarios (On/When/If/Then) + choices
   - `6-elon.md` — ruthless cut (question, delete, simplify)
   - `7-spec.md` — consolidate the conversation into one authoritative spec

   *(Run `/mission` once first to set the product vision `/vet` checks against.)*
2. You copy each file into Claude Code in sequence. Each stage's output informs the next.

```bash
# macOS:
cat /tmp/product-squad-scope-<ts>/1-why.md | pbcopy
# Linux (X11):
cat /tmp/product-squad-scope-<ts>/1-why.md | xclip -selection clipboard
# Linux (Wayland):
cat /tmp/product-squad-scope-<ts>/1-why.md | wl-copy

# Paste into Claude Code, read the response, then repeat for stages 2-7
# with the same copy command (substituting the stage file name).
```

Total: ~15-30 min of paste-and-think. Cost: ~$0.40-0.70 if you go deep on all 7 stages.

## What you'll have at the end

- **From `draw`**: 1 ASCII sketch (in terminal) + 3 rendered HTML files showing your feature at progressively higher fidelity
- **From `scope`**: 7 markdown documents capturing the product reasoning behind your feature
- **A pattern you can re-apply** to any future feature idea

## Troubleshooting

| Symptom | Fix |
|---|---|
| `claude: command not found` | Install Claude Code |
| `authentication_error` | `unset ANTHROPIC_API_KEY`, then `claude /login` |
| HTML didn't open in browser (Linux) | Output paths printed; open manually |
| Visual output looks generic | Idea was too vague; rephrase as "who does what where" |
| Scope stages 3, 5, 6 (/shape, /owit, /elon) ask interactive questions | Expected — paste, respond, read response. /vet (stage 2) is a one-shot gate: Off-mission means stop. |

## Next steps

Try these in order — each builds on the last:

1. **Re-run with a different flavor on your own idea** — `FLAVOR=apple ./draw "your idea"`. Same ladder, different aesthetic. The four flavors aren't cosmetic; each teaches a distinct theory of taste (see [`design-system/brand-flavors/`](design-system/brand-flavors/)).
2. **Run `scope` on the same idea** — `./scope "your idea"`. The visual ladder shows *what*; the scoping cluster shows *why* and *what to build first*.
3. **Then read the system docs** — [`AGENTS.md`](AGENTS.md) for the mental model, [`skills/shape/SKILL.md`](skills/shape/SKILL.md) for the options-menu + capability-delta pattern, [`manifest.yaml`](manifest.yaml) for the V1 roadmap (Foreman + Inspector runtime, Codex adapter, Railway one-click deploy).
