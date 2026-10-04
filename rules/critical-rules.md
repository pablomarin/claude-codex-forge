# Critical Rules

- **CHECK BRANCH** — Never implement on the protected default branch.
- **USE CANONICAL WORKFLOWS** — Use `/new-feature`, `/fix-bug`, or `/quick-fix` as appropriate.
- **TDD** — Write and observe a failing behavior test before production changes.
- **RESEARCH FIRST** — Verify current library/API/provider behavior before design.
- **INDEPENDENT DESIGN REVIEW** — A fresh plan reviewer must challenge the plan before implementation. Council is exceptional, not a substitute for routine plan review.
- **STRUCTURED REVIEW** — Final code review requires separate clean spec and quality receipts over one frozen candidate.
- **E2E USER JOURNEYS** — Use `verify-e2e` for user-facing behavior. Arrange and verify only through sanctioned user interfaces; see `.forge/rules/testing.md`.
- **UPDATE STATE** — Keep `.forge/local/state.md` and applicable changelog material current.
- **NO SILENT DEFERRAL** — Fix known reachable correctness, security, evidence, or configuration defects in active scope before shipping.
- **KISS AND YAGNI** — Build the smallest correct solution required by current evidence and acceptance criteria. Do not add speculative abstractions, compatibility layers, hardening, or edge-case machinery without a concrete supported need.
- **RESOURCE DISCIPLINE** — Use the smallest correct solution and the one-broad/one-repair/one-closure budget. Do not chase perfection or speculative rare cases; never waive reachable security, data loss, supported correctness, or explicit acceptance criteria.
- **GROUND YOUR CLAIMS** — Distinguish verified facts, inferences, unverified results, and blockers. Confident guessing is a defect. Bind every certification to the exact candidate.
- **HUMAN AUTHORITY** — PR creation and other consequential external mutations require explicit human approval. The agent records the actual decision and executes through normal host controls; no manual command or authorization-file edit is required. Configured reviews and investigations launch under standing approval.
- **HOST FREEDOM** — Either host may resume at the next durable step. Forge creates no edit lock: concurrent sessions are allowed. Coordinate overlapping writes; if any session mutates the candidate, candidate-bound evidence becomes stale.
