# 0010 — Runtime context efficiency via handoff seams

Status: Accepted (2026-06-14)

Forge will optimize runtime context efficiency first at phase-boundary seams, especially Phase 3 → Phase 4, rather than weakening review gates or forcing universal fresh sessions. Approved plans will carry an `Implementation Handoff` with durable rationale, non-goals, invariants, a `Task Contract`, and review expectations so the main thread can compact by default and recommend a fresh implementation session only when fresh-session triggers suggest planning context has become a liability.

## Considered Options

- **Same-session only:** lowest operational complexity, but leaves long brainstorm/plan-review transcripts in the main thread during implementation.
- **Always fresh implementation session:** maximizes context leanness, but risks losing implicit decision continuity for tightly coupled work.
- **Handoff seam policy (chosen):** preserve the “why” in durable artifacts, recommend same-session compaction by default, and recommend fresh implementation sessions for large/churn-heavy work.

## Consequences

- Mandatory Claude × Codex plan/code review gates remain intact.
- `Task Contract` becomes the canonical implementation contract; Phase 4 dispatch planning should verify/update it instead of creating a drifting duplicate artifact.
- Goal evidence remains required for active `/goal` loops, but can be suppressed outside active goal sessions because normal workflow tracking and ship gates do not depend on it.
- Model/effort budgeting and Phase 3.3 plan-review offloading are documented as future measured experiments, not first-step automation.
