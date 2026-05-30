# /owit — Scenario Specification (On, When, If, Then)

**Purpose:** Define the user experience flow for a feature using On/When/If/Then scenarios. Focus on what the user sees, does, and experiences -- not how it's built. Decisions about implementation belong in eng-deep-dive, not here.

**Usage:** `/owit [feature description or paste /shape output]`

---

## Flow

```
/shape (decide what to build)
  → /owit (THIS — map behavior before detailing)
    → /spec (detail data + surfaces, informed by scenarios)  [V1 — not bundled in V0.5]
      → /elon + @eng-deep-dive (parallel: cut + ground vs codebase)  [@eng-deep-dive is V1]
        → Implement
```

**Consumes:** A feature description, a `/shape` output, OR a `/shape` + `/experience` pair. When given `/shape` output, use the selected options, capability delta, and principles as the foundation -- don't re-explore intent. When given `/experience`, lift the Audience line as the scenario actor and the Delta as the success condition the scenarios test.

**Delivers:** Flow diagram + numbered scenarios + numbered Choices (C1, C2…) + a collapsed "Obvious" list. Feeds `/elon` (scenarios + Choices to cut against) and downstream `/spec` (V1) or implementation directly.

---

## Output Structure

The output has three sections. **The user reviews the flow diagram first, then the choices.**

### Section 1: Flow Diagram

A mermaid flowchart showing the dominant user journey. Each node maps to a scenario ID. Branch points show where choices diverge. This is the bird's-eye view the user scans first.

Rules:
- Nodes are user-visible states or actions, not technical steps
- Branch labels are conditions the user experiences ("key works" / "key rejected"), not system internals
- Keep it to one diagram. If the feature has multiple entry points, show them converging into the main flow.

### Section 2: The Scenarios

Full On/When/If/Then scenarios organized by flow stage. Each scenario describes what the user sees and does. Grouped by stage with letter prefixes matching the diagram.

Rules:
- **No technical language.** No variable names, no endpoint paths, no database tables, no SDK references. Write from the user's perspective.
- **No implementation.** Don't say "the system encrypts the key." Say "the key is stored securely." How it's stored is an engineering decision, not a product one.
- Sorted by frequency/importance within each group
- If a scenario has an "or" in it -- two reasonable paths -- it's probably a Choice. Extract it to Section 3.
- Group related behaviors as sub-items under one scenario rather than separate scenarios

### Section 3: The Choices

Where the user experience could go multiple ways. Each choice is a numbered decision with options. These are product decisions, not engineering ones -- they're about what the user sees and experiences, not how the backend handles it.

Choices use IDs like C1, C2, C3 so the user can respond quickly ("C1: A, C2: B").

Format per choice:
```
### C1: [Question being answered -- what should happen when X?]

[1-2 sentence setup: the situation the user is in and why the answer isn't obvious]

| # | Option | Effort | Trade-off |
|---|--------|--------|-----------|
| A | [simplest option] | [gut estimate] | [what the user gains/loses] |
| B | [next option] | [estimate] | [what the user gains/loses] |

**Lean:** [which option and why, in one sentence]
```

Rules for choices:
- Always number C1, C2, C3 -- the user references these by ID in their response
- Always list simplest/cheapest option first
- Effort is gut-level (30 min / 2 hrs / half day)
- Trade-offs describe user impact, not system impact
- If there are only 2 options and one is clearly better, it's not a real choice -- move it to Section 2

### The Obvious (collapsed)

At the end, a compact list of mechanical behaviors that don't need review. Standard CRUD, migrations, form validation, etc. Listed so the user knows you've thought about them, but not worth their attention.

---

## Scenario Structure

Each scenario follows this pattern (include only the parts that add clarity):

- **On** [where in the app] -- what screen, tab, or surface the user is looking at
- **When** [what the user does or what happens] -- trigger
- **If** [optional condition] -- only when needed to distinguish paths
- **Then** [what the user sees or experiences] -- outcome

Not every scenario needs all four parts. Omit **On** if it's obvious from the group. Omit **If** when there's no conditional branching.

**Language test:** If a scenario mentions a file path, function name, database column, or API endpoint, rewrite it. The user should be able to read every scenario without knowing the codebase.

---

## Process

### Step 1: Map the User Journey

Think about the feature from the user's chair:
- What screen do they start on?
- What do they click/type/see at each step?
- Where do they end up?
- What can go wrong that they'd notice?

### Step 2: Draw the Flow Diagram

Create a mermaid flowchart of the dominant path. Add branches only where the user's experience diverges. Label nodes with scenario IDs.

### Step 3: Triage into Scenarios vs Choices

- **Is the user experience clear?** -> Scenario (Section 2)
- **Could two reasonable people design this differently?** -> Choice (Section 3)
- **Is it mechanical/standard?** -> Obvious (collapsed at bottom)

### Step 4: Present for Review

Tell the user: "Check the diagram for the overall flow. **The Choices need your call.**" Direct attention to decisions, not descriptions.

---

## Anti-Patterns

- **Technical language in scenarios.** "The system resolves the API key" -- rewrite as "the user's saved key is used." The user doesn't care about resolution logic.
- **Implementation choices disguised as product choices.** "Should we cache the client or create per-request?" is an engineering decision. "Should the user see an error or get silently switched to the default?" is a product decision.
- **Too many scenarios.** If you have 15+ scenarios, you're over-specifying. Group related behaviors. Move mechanical ones to Obvious.
- **Too many choices.** More than 3-4 choices means the feature isn't shaped well. Resolve ambiguity upstream in `/shape` or `/spec`.
- **Flow diagrams with system internals.** Nodes should be user states ("Sees error message"), not system states ("API returns 401").

---

## Example Output

```
## Flag a Job -- Scenarios

### 1. Flow Diagram

(mermaid flowchart showing: User sees job -> Clicks flag -> Picks reason -> Submits -> Sees confirmation)

### 2. The Scenarios

**O: Opening the Flag**

- **O1.** When a user clicks the flag icon on any job, then a dialog opens asking for a reason.
- **O2.** The dialog shows four reasons as radio buttons. Submit is disabled until one is picked.

**S: Submitting**

- **S1.** When the user picks a reason and submits, then a confirmation message appears and the dialog closes.
- **S2.** If the user has already flagged this job, then the dialog shows "You've already reported this" instead of the form.

### 3. The Choices

#### C1: What should happen when multiple people flag the same job for different reasons?

Two different users flag the same job, but one says "spam" and the other says "inaccurate." Should the job still get auto-removed?

| # | Option | Effort | Trade-off |
|---|--------|--------|-----------|
| A | 2 flags from anyone = job removed, regardless of reason | 30 min | Simple, but unrelated complaints could remove a valid job |
| B | 2 flags with the same reason = removed; mixed reasons = stays up for review | 1 hr | Safer, but some flagged jobs linger until an admin checks |

**Lean:** B. Prevents false removals. "Review" just means an admin looks at a list -- no new UI needed yet.

### The Obvious (collapsed)

- Flag data includes the job, the reason, optional details, and who flagged it
- Logged-in users are identified by account; anonymous users by session
- Standard form validation (can't submit empty, double-submit prevention)
```

---

## What This Command DOES

- Define the user experience as a reviewable flow
- Surface product decisions that need the user's input
- Produce numbered, referenceable scenarios the user can approve, modify, or hand off

## What This Command DOES NOT

- Make engineering decisions (that's `@eng-deep-dive`)
- Write implementation code
- Reference file paths, function names, or database schemas
- Design UI layouts or mockups (that's `/prototype`)

$ARGUMENTS
