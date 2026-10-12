---
name: visualize
description: Render a feature idea as wireframe + mockup + prototype HTML by running the visual fidelity ladder via the bundle's draw script. Use when the user is describing a UI feature they want to see laid out — early ideation, stakeholder review, "what would this even look like."
---

# /visualize — 4-tier visual fidelity ladder for an idea

Plugin-install twin of `.claude/skills/visualize/` (the clone-and-run version). Runs the bundle's `draw` script from the installed plugin. Generates sketch → wireframe → mockup → prototype, writes HTMLs to `/tmp/product-squad-demo-<timestamp>/`, opens each in the browser (macOS). Total: ~60-120 sec, ~$0.30-0.50 in Claude Code subscription usage.

**What to do when invoked:**

1. Use the Bash tool to run: `"${CLAUDE_PLUGIN_ROOT}/draw" "$ARGUMENTS"`
2. Stream the output. Each tier announces itself; HTMLs auto-open.
3. After completion, suggest one of: `/product-squad:scope "$ARGUMENTS"` to produce a product brief, OR a different flavor (`FLAVOR=apple "${CLAUDE_PLUGIN_ROOT}/draw" "..."` — also airbnb, uber, or default linear), OR `/product-squad:onboard` if `design-system/project.json` doesn't exist in the current directory yet (so future runs use the operator's brand defaults).

**Env vars** the user may prefix to override:
- `FLAVOR=<linear|apple|airbnb|uber>` — aesthetic vocabulary (default reads from `design-system/project.json` if present, otherwise `linear`)
- `BRAND="<your-product>"` — chrome placeholder (default reads from `design-system/project.json` if present, otherwise `AcmeU 101 · ReviewLab`)

$ARGUMENTS
