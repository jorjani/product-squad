---
name: handoff
description: Bundle the visual-ladder outputs into one openable showcase that shows what a feature looks like AND works like — the mockup (looks) + the prototype (works) + the spec's intent, framed on a single index page. Use after ./draw to hand a feature to a design discussion, a stakeholder, or an implementation session.
---

# /handoff — Show What It Looks Like and Works Like

The visual ladder produces a folder of artifacts (`sketch`, `wireframe`, `mockup`, `prototype`). `/handoff` assembles them into **one self-contained showcase** a person can open and grasp in a glance: the **mockup** shows what it *looks like*, the **prototype** shows what it *works like*, and a one-line frame says what it *is and why*.

**Consumes:** A `./draw` output dir (`/tmp/product-squad-demo-<ts>/` — `mockup.html` = looks like, `prototype.html` = works like) and, if available, the `/spec` (for the what/why frame).

**Delivers:** A handoff folder with a single `index.html` showcase that frames the feature and links the mockup and prototype. Open it, share the folder, or bring it into a design or implementation session. Surface-agnostic — it's just HTML.

---

## Process

1. **Locate the artifacts.** Find the most recent `./draw` output dir (or the one the operator names). Confirm which files exist — at minimum you want `mockup.html` (looks like) and `prototype.html` (works like). Note any missing tier rather than failing.
2. **Frame the feature.** One line of what + why — from `/spec` if present, else the idea the visuals were drawn from. The visuals carry the weight; don't re-narrate the spec.
3. **Build the showcase.** Write `index.html` into the handoff folder: a brief header (the frame), then two clearly-labeled sections — **"Looks like"** linking `mockup.html`, **"Works like"** linking `prototype.html` (the interactive one, so a viewer can click through states). Add `wireframe.html` as a secondary "how we got here" link if present, and the ASCII `sketch.txt` as plain text — not as an HTML surface. Self-contained, relative links, opens with no server.
4. **Hand it off.** Output the path and open `index.html`. State it's shareable as a folder or droppable into any design-iteration context.

## Output

A handoff folder (default `/tmp/product-squad-handoff-<slug>/`, or alongside the draw dir) containing `index.html` plus the linked artifacts. Confirm with one line:

> "Handoff ready: `<path>/index.html` — opens to the mockup (looks like) + prototype (works like). Open it, share the folder, or bring it into your next design pass."

---

## Rules

- **Looks like AND works like — both, or name the gap.** The mockup answers "looks"; the interactive prototype answers "works." If one is absent, build the showcase with what exists and label what's missing — don't fake it.
- **The visuals carry the weight.** Frame in a line or two; a viewer should reach the mockup in the first scroll.
- **Self-contained.** Opens with no server, no build. Relative links to sibling files; nothing that needs the bundle's repo.
- **"Works like" means clickable.** Link the prototype a viewer can click — not a screenshot. If only a static mockup exists, say "behavior not yet prototyped — run /prototype."
- **No new design decisions.** `/handoff` presents what the ladder produced; it doesn't restyle. To change the visuals, re-run the ladder.

$ARGUMENTS
