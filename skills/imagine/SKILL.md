---
name: imagine
description: Generate images from text prompts using fal.ai's model library via a local script. Use when the user wants to create an image, illustration, or visual asset from a description. Distinct from the visual ladder (/sketch, /wireframe, /mockup, /prototype), which lay out UI in HTML; this produces raster images. Requires a FAL_KEY env var.
---

# /imagine — Generate Images with fal.ai

Generate images from text prompts using fal.ai's model library.

**Usage:**
```
/imagine <prompt>
/imagine --model schnell <prompt>
```

For laying out UI rather than generating pictures, use the visual ladder (/sketch → /wireframe → /mockup → /prototype).

## Prerequisites
- A `fal.ai` CLI/script in your project that wraps the fal.ai API (e.g. `imagine.ts`).
- A `FAL_KEY` environment variable. If missing, tell the user to get one at https://fal.ai/dashboard/keys.
- If the script's `node_modules/` is absent, install deps first (e.g. `bun install`).

## 1. Parse arguments
Extract from the prompt:
- **Prompt** (required) — the text description.
- **--model** (optional) — `dev` (default, quality), `schnell` (fast+cheap), `recraft` (stylized), `nanobanana`, or any full fal.ai endpoint ID.
- **--size** (optional) — `WxH` (default 1024x1024).
- **--no-open** (optional) — skip auto-opening the result.

If no arguments, ask what to generate.

## 2. Generate
Run the project's fal.ai script with the parsed flags and prompt, e.g.:
```bash
bun imagine.ts $FLAGS "$PROMPT"
```
It calls fal.ai, saves the image to the script's output dir, and (on macOS) opens it.

## 3. Report
Tell the user the saved file path and which model was used. Offer to regenerate with a different model/prompt for tweaks.

## Model shorthands
| Shorthand | Endpoint | Notes |
|-----------|----------|-------|
| `dev` | fal-ai/flux/dev | Default, good quality |
| `schnell` | fal-ai/flux/schnell | Fast + cheap |
| `recraft` | fal-ai/recraft-v3 | Stylized / illustration |
| `nanobanana` | fal-ai/nanobanana | Gemini image model |

Any full fal.ai endpoint ID also works as `--model`.

$ARGUMENTS
