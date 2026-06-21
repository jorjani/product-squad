---
name: release
description: Cut a versioned release — detect the last tag, bump semver from commit conventions, generate grouped release notes, then tag, push, and draft a GitHub Release. Conservative: shows a full dry-run preview and waits for confirmation before any tag, push, or release. Use to cut a release from merged work. Pairs with /ship (per-PR) and /changelog.
---

# /release — Cut a Release

`/ship` lands one PR. `/release` packages many merged PRs into a single versioned, tagged, announced release. The whole flow is **preview-then-confirm**: nothing is tagged, pushed, or published until you approve the plan.

**Usage:**
- `/release` — auto-detect the bump from commits, preview, confirm
- `/release minor` (or `major` / `patch`) — force the bump level
- `/release v1.4.0` — set the exact version explicitly

**Delivers:** A semver tag pushed to origin + a GitHub Release with grouped notes. Optionally updates `CHANGELOG.md`.

---

## Step 1 — Find the last release

```
git fetch --tags
git describe --tags --abbrev=0    # most recent tag, e.g. v1.3.2
```

If there are **no tags**, this is the first release. Default the previous version to `v0.0.0` and the range to the full history (`git log` with no range). Tell the user it's the first release so they can confirm a sensible starting version.

## Step 2 — Read the commits since that tag

```
git log <last-tag>..HEAD --pretty=format:'%s|%h'
```

This commit list is the **single source of truth** for both the bump and the notes. If it's empty, stop: "No commits since `<last-tag>` — nothing to release."

## Step 3 — Decide the bump (semver)

This skill assumes **Conventional Commits** prefixes (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, etc.). Derive the bump:

| Signal in the commit range | Bump |
|---|---|
| Any `BREAKING CHANGE:` footer or `!` after type (`feat!:`) | **major** |
| Any `feat:` | **minor** |
| Only `fix:` / `chore:` / `docs:` / others | **patch** |

If the user passed an explicit level or version, honor it verbatim — skip the derivation.

**If the commits are NOT conventional** (no recognizable prefixes), say so plainly and ask for the bump level rather than guessing. Don't infer major/minor from commit prose.

State the chosen bump and the one reason for it: "Minor (`v1.3.2` → `v1.4.0`) — 3 `feat:` commits, no breaking changes."

## Step 4 — Generate release notes

Group the commits by type, highest-impact first. Drop the prefix from each line and keep the human-readable summary. Omit empty groups and noise (`chore: bump deps` is fine to fold or cut).

```
## What's new

### Features
- <feat summaries>

### Fixes
- <fix summaries>

### Other
- <refactor / docs / chore worth mentioning>

**Full changelog:** <last-tag>...<new-tag>
```

If a `/changelog` artifact or `CHANGELOG.md` convention exists in the repo, match its format instead of inventing one.

## Step 5 — DRY RUN (mandatory — stop here)

Show the complete plan and **wait for explicit confirmation**. Nothing has touched git yet.

```
RELEASE PREVIEW
  Previous:  v1.3.2
  New:       v1.4.0   (minor — 3 feat, 2 fix)
  Tag:       v1.4.0 on <current-branch> @ <short-sha>
  Push:      origin v1.4.0
  Release:   gh release create v1.4.0 (draft notes below)
  CHANGELOG: <will update | not touched>

<the generated notes>
```

Pre-flight checks before showing the preview — surface any as warnings:
- On the default branch? Releasing from a feature branch is usually a mistake.
- Working tree clean? Uncommitted changes won't be in the tag.
- Local branch up to date with origin? Behind = the tag may miss commits.
- Tag name already exists? Abort rather than clobber.

**Do not proceed past this step without a yes.**

## Step 6 — Tag, push, release (after confirmation)

```
# annotated tag on the confirmed commit
git tag -a v1.4.0 -m "Release v1.4.0"
git push origin v1.4.0

# draft the GitHub Release from the generated notes
gh release create v1.4.0 \
  --title "v1.4.0" \
  --notes-file <notes-path> \
  --verify-tag
```

Use `--draft` if the user wants to eyeball the Release page before it goes public; otherwise publish directly. Use `--latest` to mark it the latest release when appropriate.

## Step 7 — Optional: update CHANGELOG.md

If the repo keeps a `CHANGELOG.md`, prepend a new section (newest on top), following [Keep a Changelog](https://keepachangelog.com) order if that's the existing style:

```
## [1.4.0] — (unreleased date intentionally omitted unless asked)

### Added / Changed / Fixed
<grouped entries>
```

Commit it separately: `docs(changelog): v1.4.0`. Only do this if a `CHANGELOG.md` already exists or the user asks — don't introduce the convention unprompted.

---

## Rules

- **Preview before every side effect.** Tag, push, and `gh release create` are outward-facing and hard to reverse. Show the full plan, get a yes, then act. Never tag-and-push in one unconfirmed motion.
- **Commits are the source of truth.** The bump and the notes both derive from `git log <last-tag>..HEAD`. Don't invent entries that aren't backed by a commit.
- **Don't guess a bump from prose.** Conventional prefixes drive the bump. If they're absent, ask — a wrong major/minor call ships a misleading version.
- **Never clobber a tag.** If the target tag exists, abort and surface it. Re-releasing over a tag rewrites history people may have pulled.
- **First release is explicit.** No prior tag → confirm the starting version with the user rather than defaulting silently.
- **One release = one tag.** `/release` is the batch primitive; `/ship` remains the per-PR primitive. Don't fold per-PR work into here.

$ARGUMENTS
