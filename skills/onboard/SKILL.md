---
name: onboard
description: Ask the user 5 intake questions (name, audience, surface, default_flavor, brand) and save defaults to design-system/project.json in the current project. Use when the user is setting up the bundle for a specific product they own.
---

# /onboard — Set up product-squad with your product's context

Plugin-install twin of `.claude/skills/onboard/` (the clone-and-run version). Runs the bundle's `onboard` script from the installed plugin. Writes a single intake prompt to `/tmp/product-squad-intake-<timestamp>/intake.md` that asks the operator 5 questions about their product (name, audience, surface, primary action, default flavor, brand string). Claude conducts the interview, then writes `design-system/project.json` in the operator's project directory. Subsequent `/product-squad:visualize` runs from that directory honor those defaults.

**Optional.** Operators can skip onboarding entirely and use the default fixture (`AcmeU 101 · ReviewLab` brand placeholder, `linear` flavor) — the bundle works without project context. Onboarding is the path for operators who want the bundle to render IN THEIR brand instead of the demo placeholder.

**What to do when invoked:**

1. Use the Bash tool to run: `"${CLAUDE_PLUGIN_ROOT}/onboard" "$ARGUMENTS"`
2. The script writes the intake file and prints its path.
3. Tell the operator: "Open a fresh Claude Code conversation in your project directory and paste the contents of `<intake-file-path>`. Claude will interview you (5 questions) and write `design-system/project.json` when done."
4. After the operator confirms `design-system/project.json` was written, suggest: `/product-squad:visualize "<a specific feature idea>"` to render their first artifact with their brand defaults.

**$ARGUMENTS shape:**
- `/product-squad:onboard "my product idea in one sentence"` — seeds the interview with a sentence
- `/product-squad:onboard` (no arg) — interview starts by asking the operator to describe their product

$ARGUMENTS
