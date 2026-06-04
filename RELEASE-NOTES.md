# Release Notes

Format: [Keep a Changelog](https://keepachangelog.com/) · Versioning: [SemVer](https://semver.org/)

## [Unreleased]

Three unreleased PRs are merged to `main` but not yet tagged: PR #10 (V0.6 polish), PR #17 (plugin manifest), PR #19 (skills migration). `manifest.yaml` + `.claude-plugin/plugin.json` declare `version: 0.7.0-dev`.

> **Tag decision pending.** Three candidates, pick one before cutting the next tag:
> - `v0.5.2` — frame this as a patch line on top of v0.5.1. Understates the surface change.
> - `v0.6.0` — minor bump. Matches the `0.6.0-dev` manifest string and the "V0.6 polish" naming used in PR #10.
> - `v0.7.0` — minor bump that signals the plugin-shape pivot (marketplace.json, `commands/` → `skills/`) is the headline, not the polish. Honest about how much changed for a user installing fresh.

### Added
- **`./onboard`** — third entry point. Optional 5-question intake interview that writes `.studio/project.json`.
- **`./draw` and `./scope` read `.studio/project.json`** for `FLAVOR` and `BRAND` defaults. Precedence: env var > project.json > hardcoded. (#10)
- **`/visualize`, `/scope`, `/onboard`** — slash commands auto-discovered when the bundle is the CWD.
- **Plugin manifest** at `.claude-plugin/plugin.json` and a first-party marketplace manifest at `.claude-plugin/marketplace.json`. `claude plugin validate .` passes. Once the repo is public, `/plugin marketplace add jorjani/product-squad` works. (#17)
- **Auto-triggering skills.** Every prompt file moved to `skills/<name>/SKILL.md` with `name:` + `description:` frontmatter. Claude Code matches the description against in-conversation context and offers the skill without an explicit slash command. (#19)
- **Install section** in `README.md` + `QUICKSTART.md` showing the `/plugin install` path alongside clone-and-run. (#17)
- **`CODE_OF_CONDUCT.md`** — Contributor Covenant v2.1, David named as report contact. (#17)
- **`examples/flavor-comparison.html`** — 4-pane visual catalog of the brand flavors.
- **Chain contracts** on all 5 product-cluster commands: each opens with explicit `Consumes:` and `Delivers:` lines.
- **Cross-cluster bridge paragraph** in `AGENTS.md` connecting the product cluster to the visual cluster.
- **`teaches:` frontmatter field** on each flavor — one-sentence summary of the aesthetic vocabulary.
- **Product-vision altitude** — `/mission` writes `design-system/mission.md` (mission + value prop + north-star + non-goals); `/vet` gates feature fit against it (Serves / Tangential / Off-mission) as a cheap kill *before* scoping.
- **`/spec`** — consolidates the cluster outputs (`why → … → elon`) into one authoritative contract. Graduated from the V1 roadmap.
- **`/decompose`** — bridges the scoping cluster to the visual ladder: splits a spec into single-surface "who/what/where/why" phrasings, each ready for `./draw`.
- **`/gh-issue`** — packages a spec as a board-agnostic GitHub issue in commander's-intent form (goal + constraints down; how stays with the builder).
- **`/handoff`** — bundles the visual-ladder outputs into one openable showcase: mockup (looks like) + prototype (works like) + the spec's frame.

### Changed
- **Brand flavors rebranded** `editorial / industrial / playful / brutalist` → `linear / apple / airbnb / uber`. Aesthetic-vocabulary names became brand-archetype emulations. Visual lineage, not endorsement.
- **Default flavor** `editorial` → `linear`.
- **Entry points moved to repo root and renamed**: `bin/visual` → `./draw`, `bin/scope` → `./scope`.
- **Demo fixture swapped** from EDU-specific (`students upload resume to course project for peer review`) to universal (`users configure notification preferences across email, push, and in-app channels`).
- **`AGENTS.md` rewritten** as a 51-line user-mediation brief (down from 70). Agent operator framing, not a tool-navigation guide. (#19)
- **`manifest.yaml`** top-level key `commands:` → `skills:` and all 10 paths updated. (#19)
- **`./scope` is now a 7-stage sequencer** — `why → vet → shape → experience → owit → elon → spec` (was 5). README, QUICKSTART, `examples/idea-fixture.md`, and the `.claude/skills/scope` wrapper synced to match.

### Removed
- **`bin/`** directory. Both binaries live at repo root now. (#10)
- **`commands/*.md`** — replaced by `skills/<name>/SKILL.md` directories. Same applies to `.claude/commands/*.md` → `.claude/skills/<name>/SKILL.md`. (#19)
- **Stale `commands/README.md`** — no longer applies after the skills migration. (#19)
- **Stale README copy** — the "Private during validation. Public at V1 (3-4 weeks)" line. (#17)

### Fixed
- **`REPO_ROOT` resolution after the `bin/` flatten** — scripts at repo root needed `SCRIPT_DIR` (not `SCRIPT_DIR/..`). Caught by smoke test, would have been a runtime failure if shipped. (#10)

## [0.5.1] — 2026-05-25

Mopup release before Gabriel onboarding. Discoverability + reliability fixes to the primary V0.5 wedge.

### Added
- **T0 sketch persistence** to `$OUT_DIR/sketch.txt`. Sketch now chains into the T1 wireframe as a predecessor, closing the T0 → T1 continuity gap. (#8)
- **Closing message** lists `T0 → T1 → T3 → T4` and prompts to try other flavors + the secondary `bin/scope` wedge. Fixes the silent end-of-run that buried flavor switching and the scoping cluster. (#8)

### Changed
- **QUICKSTART "Next steps"** rewritten from three doc-reading hand-offs to three command-try invitations that build momentum after the demos. (#9)

### Fixed
- **Rate-limit false-negative** in `bin/visual` — detects `hit your limit` / `You've hit your limit` / `[Uu]sage limit` in the claude log and treats the run as success if the file landed on disk before the quota fired. (#8)
- **Per-tier predecessor guards** at the call site — `|| true` was swallowing `run_tier`'s `return 1`, so downstream tiers inherited dead paths. (#8)
- **Shell-safe `IDEA` quoting** in closing-message example lines — now goes through `printf '%q'` for paste-ready output. (#8)

## [0.5.0] — 2026-05-25

First playable cut. Two demo wedges, both single-command, no API key required.

### Added
- **Visual fidelity ladder** (PRIMARY): `bin/visual` runs `sketch → wireframe → mockup → prototype`. Each tier auto-opens in browser (macOS) or prints file path (Linux). (#3)
- **Product cluster** (SECONDARY): `bin/scope` writes 5 pre-filled prompts (`why → shape → experience → owit → elon`) for sequential paste into Claude Code. (#4)
- **Four swappable brand flavors** (`editorial / industrial / playful / brutalist`) with `FLAVOR` and `BRAND` env vars. Each flavor pairs YAML token frontmatter with theory-of-taste + explicit Do/Don't negative constraints — the differentiator that stops the model from defaulting to training-data-popular Tailwind patterns. (#7)
- **Per-tier state-count caps** (wireframe 3-5, mockup 1, prototype 6-10) to fix the dogfood complaint that wireframes were stacking 8-10 states vertically. (#7)
- **`BRAND` env var** (default `AcmeU 101 · ReviewLab`) to stop fabrication of real-world identifiers like `CSC301`. (#7)
- **Five named agents** in snapshot form (Foreman, Sarge, Inspector, Code-Reviewer, Build-Fixer). Code-Reviewer + Build-Fixer runnable as Claude Code subagents. (#2)
- **README + QUICKSTART + per-agent context READMEs.** (#5)

### Fixed
- **Headless `claude -p` permission grant** — unblocked the visual demo on a cold-start clone. (#6)
- **`bin/visual` prompt composition** — switched from `prompt=$(cat <<EOF ... EOF)` to a temp-file + stdin pipe. Old form tripped bash's `$()` parser on heredoc bodies with quote-pair patterns. (#7)
- **`editorial.md` missing `surface-3` token** — the default flavor's row-hover/badge backgrounds were broken; the other 3 flavors already had it. (#7)
- **Do's and Don'ts heading mismatch** in `bin/visual` prompt — referred to "Dos and Donts" (a leftover workaround for the heredoc bug). The mismatch reduced the chance the model located the negative constraints. (#7)

### Notes
- Requires Claude Code installed and signed in via subscription. No Anthropic API key required.
- Tested only on macOS (Linux falls back gracefully). Windows untested.
