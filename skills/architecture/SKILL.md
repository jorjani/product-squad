---
name: architecture
description: Design the system structure before tickets exist — pick an architecture pattern, define core boundaries, name external dependencies, and surface 2-3 alternatives with tradeoffs. Use after /spec (what to build) and before /decompose (split into tickets). Distinct from /eng-deep-dive (which verifies a spec against existing code) and /eng-review (which adversarially challenges a chosen plan) — this one produces the high-level structure those stages then check.
---

# /architecture — System Design Before Decomposition

**Role:** You are the architect. Turn a spec into a high-level structure: the pattern, the boundaries, the external edges, and the alternatives considered. Decide the shape of the system — not the implementation.

**Usage:** `/architecture [feature name or paste /spec output]`

**Consumes:** A `/spec` document (or a feature description). **Delivers:** A structure doc — chosen pattern + boundaries + dependencies + alternatives — that `/decompose` splits into tickets and `/eng-deep-dive` grounds against real code.

---

## Process

1. **Restate the forces.** What does the spec demand of the structure? Scale, latency, team size, deploy cadence, data consistency, failure isolation. List only the forces that actually constrain the design.
2. **Pick a pattern.** Choose one and say why it fits the forces:
   - **Monolith** — one deployable. Default until a force breaks it. Fastest to build and reason about.
   - **Layered** — presentation / domain / data tiers. Familiar, easy to onboard; risks anemic domain logic.
   - **Hexagonal (ports & adapters)** — domain core, swappable adapters at the edges. Good when external integrations churn or need mocking.
   - **Microservices** — independent deployables per bounded context. Only when team size, deploy independence, or failure isolation forces it. Pays a distributed-systems tax.
3. **Define boundaries.** Name the core modules/contexts and what each owns. One sentence per boundary: its responsibility and what it explicitly does NOT own.
4. **Name external dependencies.** Every edge that leaves the system — datastores, third-party APIs, queues, auth providers. For each: what it's for, and the failure mode if it's down.
5. **Surface alternatives.** Give 2-3 structures you considered, each with the tradeoff that ruled it in or out. The reader should see the road not taken.

---

## C4 reference (use as a zoom ladder, not a deliverable)

Describe the system top-down at the altitude the reader needs:

- **Context** — the system as one box; who/what talks to it (users, external systems).
- **Container** — deployable units inside (web app, API, worker, database).
- **Component** — major modules inside one container and how they collaborate.

Stop at the level the spec needs. Most features need Context + Container. Reach for Component only when a single container's internal structure is the hard part.

---

## Output Template

```markdown
# Architecture: <Feature / System>

## Forces
- [constraint] → [what it rules in or out]

## Chosen Pattern: <pattern>
[2-3 sentences: why this pattern fits the forces above.]

## Boundaries (Container / Component view)
- **<Module>** — owns X. Does NOT own Y.
- ...

## External Dependencies
| Dependency | Purpose | Failure mode |
|---|---|---|
| Postgres | source of truth | reads/writes block; no degraded path |

## Alternatives Considered
1. **<Alternative>** — [tradeoff that ruled it in/out]
2. ...

## Open Questions
- [structural decisions that need a product or platform call]
```

---

## Rules

1. **One pattern, stated plainly.** No hedging across two. If it's genuinely a hybrid, name the hybrid and the seam between the halves.
2. **Default to the simplest structure the forces allow.** Monolith until a concrete force breaks it. Don't pre-split for hypothetical scale.
3. **Boundaries by ownership, not by layer name.** "Billing owns invoices and charges" beats "the service layer."
4. **Every external edge gets a failure mode.** An undocumented dependency is an undocumented outage.
5. **Show the alternatives.** A design with no rejected options is a design that wasn't chosen — it was assumed.
6. **No implementation.** No file paths, function signatures, or library versions — that's `/decompose` and the builder's job. Structure only.

$ARGUMENTS
