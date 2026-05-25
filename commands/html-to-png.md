---
description: Convert an HTML file to a PNG screenshot via Playwright. Auto-detects viewport from body CSS.
---

# /html-to-png

Render an HTML file as a PNG image using Playwright.

## Usage

```
/html-to-png path/to/file.html
```

Optional viewport override (skips auto-detect):
```
/html-to-png path/to/file.html 1080 1350
```

## Steps

1. **Read the HTML.** Grep for `body { width: ... }` and `body { height: ... }` to detect the intended viewport. If absent, ask the user. Default to 1080×1350 for LinkedIn portrait, or 1200×630 for header/OG.
2. **Load Playwright tools** via `ToolSearch` if not already loaded:
   - `mcp__playwright__browser_navigate`
   - `mcp__playwright__browser_resize`
   - `mcp__playwright__browser_take_screenshot`
   - `mcp__playwright__browser_close`
3. **Navigate** to `file://{absolute_path}` of the HTML.
4. **Resize** viewport to the detected dimensions.
5. **Re-navigate** if the page URL drops to `about:blank` after resize (known Playwright MCP quirk on viewport changes).
6. **Screenshot** with `type: png`, `filename: {basename}.png`.
7. **Move** the PNG from the workspace root (Playwright's default save location) into the source HTML's directory.
8. **Close** the browser.

## Common viewports

| Use | Dimensions |
|---|---|
| LinkedIn portrait (4:5) | 1080×1350 |
| LinkedIn square | 1080×1080 |
| Substack / OG header | 1200×630 |
| Twitter card | 1200×628 |

## Known quirks

- **Save path defaults to workspace root.** Playwright MCP saves screenshots to the working directory regardless of the `filename` you pass. Always `mv` the file to the source HTML's directory after capture.
- **Viewport drop after resize.** Sometimes the page URL becomes `about:blank` after `browser_resize`. Re-navigate before screenshotting.
- **Emoji glyphs use the OS font.** Renders Apple Color Emoji on macOS. For cross-platform consistency in shipped visuals, swap to inline SVGs or a hosted icon font before rendering.

## After rendering

Always show the result inline in the chat (Playwright returns the screenshot in the tool result) so the user can verify before shipping. Don't claim success without the user seeing it.
