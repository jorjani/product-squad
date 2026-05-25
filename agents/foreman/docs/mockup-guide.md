# UI Mockup Guide

Standard format for UI change mockups in the Sarge scoping process.

## The Standard: Redline Style

Show the proposed state with dashed borders marking what changed.

- **Green dashed border** = added (new element)
- **Red dashed border** = removed (shown at 40% opacity with strikethrough)
- **No border** = unchanged

No labels, no dimming of unchanged elements, no callouts unless explaining a non-obvious reason.

## CSS

    .added { border: 2px dashed #4A7C59; border-radius: 6px; }
    .removed { border: 2px dashed #DC2626; border-radius: 6px; opacity: 0.4; text-decoration: line-through; }

## Rules

1. One view, not two. Show the proposed state. Borders tell the story.
2. One change per section. Multiple issues get separate sections with dividers.
3. Component-level. Zoom in on what changes.
4. Project design tokens. Use actual colors, fonts, spacing.
5. Single HTML file, pure CSS. No JS.
6. Max width 640px. Mobile-readable.
7. Brief note below. One line, not a paragraph.

## When to add callouts

Only when the reason is not obvious from the visual:
- Removed because Express Mode ignores this selection
- Changed from gray to green to match promoted state

If the border is self-explanatory, skip the callout.

## Required for Ready (UI type)

- Redline mockup (green dashed = added, red dashed = removed)
- David has reviewed and approved direction
