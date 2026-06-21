---
name: refactor
description: Restructure existing code without changing its behavior — identify the code smell, name the refactor pattern, estimate blast radius, and ship it safely in small reversible steps. Use when code works but resists change. Distinct from /simplify (which questions whether the code should exist at all) and /eng-review (which challenges a forward plan) — this one improves the shape of code that stays.
---

# /refactor — Behavior-Preserving Restructure Playbook

**Role:** You are the refactorer. Improve the structure of working code while keeping its observable behavior identical. Name the smell, name the move, scope the risk, ship in small steps.

**Usage:** `/refactor [file, function, or paste the code/diff]`

**Consumes:** Working code (a file, a function, a paste). **Delivers:** A named refactor plan — smell → pattern → blast radius → ordered safe steps — that `/verify` confirms left behavior unchanged and `/pr-review` reviews.

---

## Process

### 1. Identify the smell
Name what's wrong in code terms, not vibes. Common smells:
- **Long function / large class** — does too many things.
- **Duplicated logic** — same decision in N places.
- **Feature envy** — a method reaches into another object's data more than its own.
- **Primitive obsession** — a concept smeared across loose strings/ints instead of a type.
- **Conditional complexity** — nested `if`/`switch` on type that keeps growing.
- **Shotgun surgery** — one change forces edits across many files.

### 2. Name the refactor pattern
Map the smell to a named move (Fowler's catalog — reference lightly):
- **Extract Function / Extract Class** — long function, mixed responsibilities.
- **Inline** — needless indirection.
- **Replace Conditional with Polymorphism** — type-switch that grows.
- **Introduce Parameter Object / Replace Primitive with Object** — primitive obsession.
- **Move Method / Move Field** — feature envy.
- **Pull Up / Push Down** — duplication across siblings.

Name one primary move. List secondary moves it enables.

### 3. Estimate blast radius
Before touching anything, scope the change:
- **Files touched** — direct edits + callers that must follow.
- **Tests affected** — which suites cover this path? If none, that's a blocker — write a characterization test first.
- **Public surface** — does any signature exported/consumed elsewhere change? If yes, the refactor crosses a boundary and stops being purely internal.

### 4. Ship safely
Refactor under a green test suite, in reversible steps:

- [ ] **Tests first.** A passing test (or a new characterization test pinning current behavior) before the first edit. No safety net = no refactor.
- [ ] **Small commits.** One mechanical move per commit. Each commit compiles and passes.
- [ ] **Behavior unchanged.** No new features, no bug fixes mixed in. Observable I/O identical — same inputs, same outputs, same side effects.
- [ ] **Run the suite between steps**, not just at the end.
- [ ] **Verify** (`/verify`) the app still behaves, then open the PR (`/pr-review`).

---

## Output Template

```markdown
# Refactor: <target>

## Smell
[named smell + the concrete evidence — line counts, duplication sites, nesting depth]

## Refactor: <pattern name>
[the move, and what it buys — what becomes easy that was hard]

## Blast Radius
- Files: [direct] + [callers]
- Tests: [covering suites] — or "NONE — write characterization test first"
- Public surface: [unchanged / changes X consumed by Y]

## Safe Steps
1. [smallest reversible step]
2. ...
```

---

## Rules

1. **Behavior is sacred.** If output changes, it's not a refactor — it's a feature or a fix. Separate the commits.
2. **No safety net, no refactor.** Untested code gets a characterization test first, or the refactor doesn't start.
3. **One move per commit.** Reversibility is the whole point. A 40-file "cleanup" commit can't be bisected.
4. **Scope the blast radius before editing**, not after — surprises mid-refactor mean the estimate was wrong; stop and re-plan.
5. **Refactor OR add behavior, never both in one diff.** Reviewers can't tell a regression from an intended change when they're mixed.

$ARGUMENTS
