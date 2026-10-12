---
name: scope
description: Walk the user through 7 progressive product-craft prompts (why → vet → shape → experience → owit → elon → spec) via the bundle's scope script. Use when the user is thinking through what to build before building it.
---

# /scope — Product cluster brief (why → vet → shape → experience → owit → elon → spec)

Plugin-install twin of `.claude/skills/scope/` (the clone-and-run version). Runs the bundle's `scope` script from the installed plugin. Writes 7 pre-filled prompt files (one per stage of the product cluster) to `/tmp/product-squad-scope-<timestamp>/`. The operator pastes each into Claude Code in sequence; each stage's output feeds the next.

**What to do when invoked:**

1. Use the Bash tool to run: `"${CLAUDE_PLUGIN_ROOT}/scope" "$ARGUMENTS"`
2. Stream the output. The wrapper writes 7 files and prints the path.
3. After completion, point the operator at stage 1: `cat <output-dir>/1-why.md | pbcopy` (macOS) — they paste it into Claude Code, read the response, then proceed to stage 2.
4. The 7 stages chain explicitly — each command file names its **Consumes** (from the prior stage) and **Delivers** (to the next). Output flows: idea → outcome (/why) → fit check (/vet) → brief (/shape) → felt change (/experience) → scenarios (/owit) → cut list (/elon) → contract (/spec).

**Precursor:** `/product-squad:mission` writes `design-system/mission.md` (run once per product) — the vision `/vet` (stage 2) judges each feature against.

**The visual-cluster bridge:** run `/product-squad:decompose` on the final `/spec` to split the feature into single-surface "who/what/where/why" phrasings, each ready for `/product-squad:visualize`. `/owit`'s scenarios become the state coverage `/wireframe` maps.

$ARGUMENTS
