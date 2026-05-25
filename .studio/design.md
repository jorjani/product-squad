---
name: design.md
description: Generic design tokens for product-squad bundle (system fonts + grayscale + sensible defaults)
type: design-system
last_updated: 2026-05-24
---

# Design tokens

Generic, system-default design tokens. Override with your own `.studio/design.md` when you have a real brand. These are good enough for wireframes, mockups, and prototypes that need to feel "intentional" without looking like Bootstrap.

## Palette

| Token | Value | Use |
|---|---|---|
| `surface` | `#ffffff` | Main background |
| `surface-2` | `#f8fafc` | Subtle card / sidebar background |
| `surface-3` | `#f1f5f9` | Stronger card / hover state |
| `on-surface` | `#0f172a` | Body text |
| `on-surface-2` | `#475569` | Secondary text |
| `on-surface-3` | `#94a3b8` | Tertiary / placeholder text |
| `border` | `#e2e8f0` | Default border |
| `border-strong` | `#cbd5e1` | Emphasized border |
| `primary` | `#2563eb` | Primary action (CTA button, links) |
| `primary-hover` | `#1d4ed8` | Primary action hover |
| `primary-text` | `#ffffff` | Text on primary |
| `success` | `#16a34a` | Positive feedback |
| `warning` | `#eab308` | Caution feedback |
| `danger` | `#dc2626` | Destructive / error |

## Typography

| Token | Value |
|---|---|
| `font-sans` | `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif` |
| `font-mono` | `ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace` |
| `text-xs` | `0.75rem` (12px) |
| `text-sm` | `0.875rem` (14px) |
| `text-base` | `1rem` (16px) |
| `text-lg` | `1.125rem` (18px) |
| `text-xl` | `1.25rem` (20px) |
| `text-2xl` | `1.5rem` (24px) |
| `text-3xl` | `1.875rem` (30px) |
| `text-4xl` | `2.25rem` (36px) |

Default body text: `text-base` `font-sans` `on-surface`, line-height 1.5.

## Spacing scale

| Token | Value |
|---|---|
| `space-1` | `0.25rem` (4px) |
| `space-2` | `0.5rem` (8px) |
| `space-3` | `0.75rem` (12px) |
| `space-4` | `1rem` (16px) |
| `space-6` | `1.5rem` (24px) |
| `space-8` | `2rem` (32px) |
| `space-12` | `3rem` (48px) |
| `space-16` | `4rem` (64px) |

## Borders + radii

| Token | Value |
|---|---|
| `radius-sm` | `0.25rem` (4px) |
| `radius-md` | `0.5rem` (8px) |
| `radius-lg` | `0.75rem` (12px) |
| `radius-full` | `9999px` |
| `border-width` | `1px` |

## Shadows

| Token | Value |
|---|---|
| `shadow-sm` | `0 1px 2px 0 rgba(0, 0, 0, 0.05)` |
| `shadow-md` | `0 4px 6px -1px rgba(0, 0, 0, 0.1)` |
| `shadow-lg` | `0 10px 15px -3px rgba(0, 0, 0, 0.1)` |

## Notes

- Token names follow `[role]-[modifier]` (e.g., `surface-2`, `text-xs`).
- Override any single token in a project-specific `.studio/design.md` by re-declaring it; the bundled template is the fallback.
- System fonts deliberately — looks at-home on macOS, Windows, Linux without web font loading.
- Blue primary (`#2563eb`) is neutral enough to read as "any product"; replace with your brand color for real projects.
- All shadows use rgba black — they layer over any background.
