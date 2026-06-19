---
name: api
description: Backend API contract producer — turn a spec or feature description into a Markdown contract: endpoint list, per-endpoint auth model, request shape, success response, error-code table, and idempotency rules. Grounds each endpoint against existing routes in the repo so the contract matches conventions in place. Use when the backend interface is the unknown to lock before building. Pairs with /flow (UI state contract for full-stack tickets); run after /eng-deep-dive has mapped the codebase.
---

# /api — Backend API Contract

**Usage:** `/api [issue-number] [repo]` or `/api` with a pasted spec or feature description.

## Purpose

Produce the API contract when the backend interface is the thing to nail down before coding. Read the spec, identify the endpoints involved (extending existing ones or net-new), and output a Markdown contract: endpoint list, request and response shapes, error codes, auth model.

Pairs with `/flow` on full-stack tickets — `/flow` covers UI state, `/api` covers the backend contract.

## Workflow

### 1. Read

Fetch the issue body or read the pasted text. Identify:

- **Endpoints** — from the feature description or capability list ("delete a posted-link mark", "expose current-user permissions").
- **Auth context** — from the surface: admin endpoint, user-scoped, or public.
- **Existing analogues** — grep the repo for sibling routes; the contract should match the conventions already in place, not introduce new ones.

### 2. Produce

Write a Markdown doc with these sections (skip any that don't apply; do not invent rows):

```
# API contract — <feature name>

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| DELETE | /api/ideas/:id/posted/link?platform=<p> | un-publish a single platform mark |

## DELETE /api/ideas/:id/posted/link

**Auth:** session-scoped (existing requireUser middleware).

**Request:**
- Path: `id` (idea UUID)
- Query: `platform` (one of: linkedin, twitter, substack)
- Body: none

**Response (success):** 204 No Content.

**Response (errors):**
| Status | Code                | When                                       |
|--------|---------------------|--------------------------------------------|
| 401    | unauthenticated     | no session cookie                          |
| 404    | idea_not_found      | id does not match an idea owned by user    |
| 404    | platform_not_marked | no posted_content row for (idea, platform) |

**Idempotency:** repeated DELETE on an already-deleted platform returns 404 platform_not_marked, not 204. Caller distinguishes.

## Data shape (only when introducing or changing one)

Reference existing tables and columns. Keep this to the request/response *shape* — if the schema migration itself is the open question, that's a separate piece of work; flag it, don't design it here.
```

Cells the spec cannot ground stay `(not stated)` or omit the row. Do not invent endpoints, params, or error codes.

### 3. Place

- **Small ticket:** print the contract inline.
- **Larger ticket:** write `<repo>/specs/<num>-<slug>/api.md` with frontmatter (`issue: <num>`, `status: draft`); link it from the ticket body by URL rather than pasting the whole thing in.

## Output checklist

- [ ] Endpoint list complete — method + path + purpose for each.
- [ ] Per-endpoint: auth, request shape, success response, error table.
- [ ] Idempotency / side-effect rules called out when non-obvious.
- [ ] No invented codes; `(not stated)` flagged where the spec did not ground a cell.

## Related

- `/flow` — sibling UI state contract; pair on full-stack tickets.
- `/eng-deep-dive` — run first to map existing routes and patterns the contract should match.
- `/spec` — the upstream document `/api` reads its requirements from.
