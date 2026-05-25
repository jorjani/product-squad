---
name: components.md
description: Generic component primitives for product-squad bundle (reusable building blocks for wireframes, mockups, prototypes)
type: component-catalog
last_updated: 2026-05-24
---

# Components

Generic primitive catalog. Override with your own `.studio/components.md` when you have a real component library. These are good-enough primitives that wireframe/mockup/prototype commands can reference without inventing fresh shapes per ticket.

All references use tokens from `.studio/design.md` — no hex codes inline.

## Button

States: `default`, `hover`, `active`, `disabled`, `loading`

Variants:
- **Primary** — solid `primary` background, `primary-text` text. Main action on a screen.
- **Secondary** — `border-strong` outline, `on-surface` text, transparent background. Non-primary actions.
- **Ghost** — `on-surface` text, no border, no background. Toolbars, lists, dense UI.
- **Destructive** — solid `danger` background, white text. Reserve for delete/remove.

Sizes: `sm` (height 32px), `md` (default, height 40px), `lg` (height 48px). Padding follows `space-3`/`space-4`/`space-6` scale.

```html
<button class="btn btn--primary btn--md">Save</button>
<button class="btn btn--secondary btn--md">Cancel</button>
<button class="btn btn--ghost btn--sm">Edit</button>
```

## Input

States: `default`, `focus`, `disabled`, `invalid`

Variants:
- **Text** — single-line input. Height matches button `md`.
- **Textarea** — multi-line. Min height `space-16` (64px).
- **Select** — dropdown (use native `<select>` for prototypes; style chevron with inline SVG or CSS background).

Always paired with a `<label>` (visible or sr-only). Errors shown below the input in `text-sm` `danger` color.

```html
<label for="title">Title</label>
<input id="title" type="text" class="input">

<label for="bio">Bio</label>
<textarea id="bio" class="input"></textarea>
```

## Card

A `surface-2` background block with `radius-md` corners, `space-4` padding, optional `shadow-sm`. Container for grouping related content.

```html
<div class="card">
  <h3>Card title</h3>
  <p>Card body...</p>
</div>
```

## Modal / Dialog

Centered overlay with `surface` background, `radius-lg`, `shadow-lg`, max-width 500px. Backdrop is `rgba(0,0,0,0.5)`. Always has a close button (top-right or in `.modal-actions`).

```html
<div class="modal-backdrop">
  <div class="modal" role="dialog" aria-labelledby="modal-title">
    <h2 id="modal-title">Confirm action</h2>
    <p>Are you sure?</p>
    <div class="modal-actions">
      <button class="btn btn--secondary">Cancel</button>
      <button class="btn btn--primary">Confirm</button>
    </div>
  </div>
</div>
```

## Nav

Variants:
- **Topbar** — horizontal nav, `surface` background, `border` bottom. Height 64px. Logo left, actions right.
- **Sidebar** — vertical nav, `surface-2` background, `border` right. Width 240px. Items styled as `btn--ghost` full-width.
- **Tabs** — horizontal section nav, underlined active state in `primary`. Items `space-4` apart.

## Table

`surface` background, `border` between rows, `space-3` padding per cell. Header in `surface-3` background, `text-sm` `font-semibold`. Rows hover to `surface-3`.

```html
<table class="table">
  <thead>
    <tr><th>Column 1</th><th>Column 2</th></tr>
  </thead>
  <tbody>
    <tr><td>Cell</td><td>Cell</td></tr>
  </tbody>
</table>
```

## Badge

Small inline label. `surface-3` background, `radius-full`, `text-xs`, `space-1` `space-3` padding.

```html
<span class="badge">Status</span>
<span class="badge badge--success">Done</span>
```

## Empty state

When there's nothing to show: centered block with an icon (or large emoji), heading, body text, and a single CTA button.

```html
<div class="empty-state">
  <div class="empty-state__icon">📭</div>
  <h3>No items yet</h3>
  <p>Create your first item to get started.</p>
  <button class="btn btn--primary">Create item</button>
</div>
```

## Notes

- Primitives are deliberately minimal. Add your own (avatars, tooltips, popovers, dropdowns, breadcrumbs) by extending this file in your `.studio/components.md`.
- For prototypes, prefer vanilla HTML + CSS over JS frameworks. Use small `<script>` blocks for interactivity (form validation, modal toggle, tab switching).
- Tailwind CDN is fine for prototypes; production code should use scoped CSS / CSS modules.
