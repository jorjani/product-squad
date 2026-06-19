---
name: pickup
description: Resume work from a previous session given freeform end-of-session notes — parse what was done and what's pending, verify state against the codebase, and lead with commander's intent before recommending next steps. Use at the START of a session to re-orient; pairs with /checkpoint (mid-session status) and /retro (post-session review).
---

# /pickup — Resume from Previous Session

Pick up where a previous session left off. The user has pasted **freeform notes** from the end of a prior session — bullets, a table, prose, or raw conversation output.

## Process

### Step 0: Clean the input (silently)

User input is often raw agent output or a conversation dump. Before parsing:
- **Deduplicate** — if the same statement repeats, keep only the most complete version.
- **Strip preamble** — drop "Let me…", "I'll…", "I need to…" lines that state intent without content.
- **Find the payload** — structured output (tables, headers, bullet lists) is the real content. Ignore conversational filler.

Don't tell the user you're cleaning their input.

### Step 1: Parse

Extract: **what was done** (completed work, decisions, files changed), **what's pending** (unfinished work, next steps, open questions), and **key files** (touched, created, referenced). If the work is project-scoped, note which project.

### Step 2: Load context

Read the relevant project/context files and re-read the key files named in the notes to **verify current state** — don't trust the notes blindly.

### Step 3: Commander's Intent

Lead with the big picture (4–6 lines max):

> **Mission:** One sentence — what are we accomplishing and WHY?
>
> **Current state:** 1–2 lines — where the last session left off. Confirm what you verified in the codebase vs. what the notes merely claim.
>
> **Key constraints:** 2–4 non-obvious constraints that shape what "right" looks like.

The user already lived through the last session — they need you aligned on *intent*, not a replay.

### Step 4: Recommend next steps

Present a **numbered list, sorted by ROI**. What unblocks the most value? What's quick vs. deep? What has dependencies? Let the user pick — don't start working until they choose.

## Rules

- Accept any format — don't ask the user to restructure their notes.
- If the project/scope is ambiguous, ask once.
- Don't re-do completed work — verify state first.
- Lead with WHY, not WHAT.
- Keep commander's intent tight — 4–6 lines, not a wall of text.

$ARGUMENTS
