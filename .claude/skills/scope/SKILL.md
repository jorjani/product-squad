---
name: scope
description: Walk the user through 5 progressive product-craft prompts (why → shape → experience → owit → elon) via ./scope. Use when the user is thinking through what to build before building it.
---

# /scope — Product cluster brief (why → shape → experience → owit → elon)

Runs `./scope "$ARGUMENTS"` from the product-squad bundle's repo root. Writes 5 pre-filled prompt files (one per stage of the product cluster) to `/tmp/product-squad-scope-<timestamp>/`. The operator pastes each into Claude Code in sequence; each stage's output feeds the next.

**What to do when invoked:**

1. Verify CWD is a product-squad bundle (look for `manifest.yaml` with `name: product-squad` at repo root).
2. Use the Bash tool to run: `./scope "$ARGUMENTS"`
3. Stream the output. The wrapper writes 5 files and prints the path.
4. After completion, point the operator at stage 1: `cat <output-dir>/1-why.md | pbcopy` (macOS) — they paste it into Claude Code, read the response, then proceed to stage 2.
5. The 5 stages chain explicitly — each command file names its **Consumes** (from the prior stage) and **Delivers** (to the next). Output flows: idea → outcome (/why) → brief (/shape) → felt change (/experience) → scenarios (/owit) → cut list (/elon).

**The visual-cluster bridge:** Stage 2's `/shape` output is the right input for `./draw "$ARGUMENTS"` once a feature is selected. Stage 4's `/owit` scenarios become the state coverage `/wireframe` maps.

$ARGUMENTS
