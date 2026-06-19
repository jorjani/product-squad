---
name: qa
description: Test a running web app like a real user with the Playwright MCP — discover the app, exercise pages and forms, catch layout/console bugs, fix the high-severity ones atomically, and verify. Use when you have a local dev server and want functional browser QA. Distinct from /verify (confirms one specific change) and the design audits (/crap, /ux-design, /a11y); this one hunts for and fixes bugs across the app.
---

# /qa — Browser QA Testing

Test a web application like a real user using the Playwright MCP. Find bugs, fix them, verify.

**Usage:**
- `/qa http://localhost:3000` — test this URL
- `/qa http://localhost:3000 billing page` — scope to a specific area

Use /verify when you only need to confirm a single change works.

## Step 1 — Setup
Navigate to the target URL with `mcp__playwright__browser_navigate`. Snapshot to confirm it loads. If the page needs auth, tell the user and stop.

## Step 2 — Discover
Snapshot the current page. Identify nav links, buttons, forms, interactive elements. If scope was given, focus there; otherwise pick the 3-5 most important pages/flows.

## Step 3 — Test each page
1. **Visual** — snapshot; look for broken/overlapping layout, missing images/icons, text overflow, responsive issues.
2. **Interactive** — click buttons, fill forms, toggle states; do they respond, validate, open/close, show loading?
3. **State** — empty (no data), error (invalid input), boundary (very long text, many items).
4. **Console** — `mcp__playwright__browser_console_messages` for JS errors.

Record each bug: page + element, what's wrong (with screenshot), severity (critical/high/medium/low).

## Step 4 — Fix
Highest severity first: find the source file and cause, make the minimal fix, commit atomically (`fix: [what]`), navigate back, and verify with a fresh snapshot. If a fix would touch >3 files, flag it instead — likely a deeper issue.

## Step 5 — Report

```
QA REPORT
URL:    [target]
Pages:  [N tested]
Bugs:   [N found] — [N fixed, N flagged]
FIXED:    [page] [desc] — [commit]
FLAGGED:  [page] [desc] — [reason]
CLEAN:    [pages with no issues]
Status: DONE | DONE_WITH_CONCERNS
```

## Rules
- Test what users do, not implementation details.
- Screenshots as evidence — before and after fixes.
- One bug = one atomic commit.
- Fix bugs, not styling preferences.
- Can't reproduce a visual issue? Note it and move on.
- Critical/high get fixed; medium if simple; low gets flagged.

$ARGUMENTS
