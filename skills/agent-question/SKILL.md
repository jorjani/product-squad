---
name: agent-question
description: Route a decision from an autonomous agent to a human cleanly — frame it at experience-altitude with numbered options, classify it as real-time vs. batched, gate auto-action on confidence, and track it in a state file. Use when building agents that must occasionally ask a human and act on the reply. Pattern skill — encodes the emitter → register → post → parse → action → resolve flow, provider-agnostic.
---

# /agent-question — Routing Agent Decisions to Humans

**Role:** You are designing (or generating) the question-routing layer for an autonomous agent. When the agent hits a fork it shouldn't decide alone, this is how it asks a human and acts on the answer without losing state.

**Usage:** `/agent-question [the decision the agent needs a human to make]`

**Delivers:** A framed question (experience-altitude, numbered options), a routing classification (real-time vs. batched), a confidence gate, and a state-file record — ready to post and resume.

---

## 1. Altitude — ask at experience level, never spec level

A human answering an agent's question should never need to read code to answer it.

- **Experience-altitude (correct):** the behavior, its implications, and numbered options. "The importer found 3 records with no email. Skip them, guess from name, or stop and ask per-record? (1/2/3)"
- **Spec-altitude (wrong):** `parseRow()` at `import.ts:88` throws on null `email`; should we `continue` or `throw`?

Frame what changes for the user and what each option costs. Hide the implementation. (Pairs with `/experience` for the altitude discipline and `/spec` for where the detail belongs instead.)

## 2. Format — numbered options

Always present choices as a numbered list (1, 2, 3) so the human replies with a single digit. A free-text question invites a free-text answer the agent then has to parse and often re-ask. Default the safest option to #1 and say it's the default.

## 3. Routing taxonomy — real-time vs. batched

Classify every question by urgency. Only direction-shapers interrupt a human in real time.

| Class | Examples (generic) | Channel | Cadence |
|---|---|---|---|
| **Real-time** (direction-shapers) | scoping-agent pitch decisions, repeated-build-failure escalations, generic "decision-needed" forks that block progress | push (chat/Slack/notification) | posted immediately |
| **Batched** (low-urgency) | verifier confirmations, reviewer findings, informational "clear" signals | stays on a board / queue | weekly nudge, no interrupt |

A misrouted question is expensive both ways: a batched question pushed in real time trains the human to ignore the channel; a real-time question left on a board blocks the agent.

## 4. Confidence gate — only high-confidence replies auto-commit

When the agent parses a human reply, it scores its own confidence in the interpretation:

- **High** → auto-commit the action.
- **Medium / low** → do NOT act. Post a clarifying re-ask ("I read that as option 2 — confirm?"). Acting on a misread reply is worse than asking twice.

## 5. State tracking — every question registered

Each question gets a record in a state file (JSON/SQLite/etc.) before it's posted, so the agent can resume after a restart and never double-asks:

```json
{
  "key": "import-2026-06-21-null-emails",
  "status": "open | answered | resolved",
  "thread_ts": "<message id from the channel, if posted>",
  "resolution": "<chosen option + parsed value, once resolved>"
}
```

`key` is deterministic (derive it from the decision, not a timestamp) so the same fork doesn't register twice.

## 6. Pre-fetch context — don't ask blank

For design or codebase questions, gather what already exists and show it in the question. "Here's the current handler / the existing design token / the 3 similar records — which way?" beats an empty prompt. The human decides faster when the agent has already done the lookup.

---

## Reference architecture flow

```
emitter   → agent detects a fork it shouldn't decide alone
register  → write a state record (key, status=open) BEFORE posting
post      → only if real-time: push to chat with numbered options + pre-fetched context
            (batched: leave on the board)
reply     → human answers (ideally a single number)
parse     → interpret + score confidence
action    → high confidence: commit · medium/low: clarifying re-ask
confirm   → echo what was done back to the human
resolve   → state record → resolved, with the resolution recorded
```

---

## Rules

1. **Experience-altitude or don't ask.** If answering needs a file:line, you're asking the wrong human or the wrong question.
2. **Numbered options always.** One digit to answer beats a paragraph to parse.
3. **Real-time is rare.** Default to batched. Reserve push for things that block the agent or shape direction.
4. **Never act on low confidence.** Re-ask. A wrong auto-commit costs more than a second question.
5. **Register before posting.** State first, message second — so a crash mid-post doesn't lose the question or duplicate it.
6. **Deterministic keys.** Same fork → same key → asked once.

$ARGUMENTS
