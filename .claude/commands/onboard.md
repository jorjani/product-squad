# /onboard — Set up product-squad with your product's context

Runs `./onboard "$ARGUMENTS"` from the product-squad bundle's repo root. Writes a single intake prompt to `/tmp/product-squad-intake-<timestamp>/intake.md` that asks the operator 5 questions about their product (name, audience, surface, primary action, default flavor, brand string). Claude conducts the interview, then writes `.studio/project.json` with the answers. Subsequent `/visualize` and `/scope` runs honor those defaults.

**Optional.** Operators can skip `/onboard` entirely and use the default fixture (`AcmeU 101 · ReviewLab` brand placeholder, `linear` flavor) — the bundle works without project context. `/onboard` is the path for operators who want the bundle to render IN THEIR brand instead of the demo placeholder.

**What to do when invoked:**

1. Verify CWD is a product-squad bundle (look for `manifest.yaml` with `name: product-squad` at repo root).
2. Use the Bash tool to run: `./onboard "$ARGUMENTS"`
3. The script writes the intake file and prints its path.
4. Tell the operator: "Open a fresh Claude Code conversation in this directory and paste the contents of `<intake-file-path>`. Claude will interview you (5 questions) and write `.studio/project.json` when done."
5. After the operator confirms `.studio/project.json` was written, suggest: `/visualize "<a specific feature idea>"` to render their first artifact with their brand defaults.

**$ARGUMENTS shape:**
- `/onboard "my product idea in one sentence"` — seeds the interview with a sentence
- `/onboard` (no arg) — interview starts by asking the operator to describe their product

$ARGUMENTS
