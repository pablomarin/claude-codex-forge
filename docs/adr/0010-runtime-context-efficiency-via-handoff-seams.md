# 0010 — Optimize runtime context efficiency at handoff seams

## Status

Accepted (2026-06-14)

## Context

Forge workflows intentionally preserve high-leverage judgment through mandatory Claude × Codex plan/code review, council escalation, and durable artifacts. Runtime context still grows during PRD discussion, brainstorming, plan writing, plan review, implementation orchestration, and review churn; naive compaction or fresh sessions can reduce context rot but lose the implicit “why” behind decisions.

## Considered Options

- **Option A (chosen): Handoff seam policy** — preserve rationale in durable plan sections, compact by default, and recommend fresh implementation sessions only when churn/size triggers apply.
- **Option B: Same-session only** — lowest operational complexity, but leaves long brainstorm/plan-review transcripts in the main thread during implementation.
- **Option C: Always fresh implementation session** — maximizes context leanness, but risks losing implicit decision continuity for tightly coupled work.

## Decision

Forge will optimize runtime context efficiency first at phase-boundary seams, especially Phase 3 → Phase 4, rather than weakening review gates or forcing universal fresh sessions. Approved plans will carry an `Implementation Handoff` with durable rationale, non-goals, invariants, a `Task Contract`, and review expectations so the main thread can compact by default and recommend a fresh implementation session only when fresh-session triggers suggest planning context has become a liability. Goal evidence remains required for active `/goal` loops, but is suppressed outside active goal sessions because normal workflow tracking and ship gates do not depend on it.

## Consequences

- ✅ Mandatory Claude × Codex plan/code review gates remain intact.
- ✅ `Task Contract` becomes the canonical implementation contract; Phase 4 dispatch planning verifies/updates it instead of creating a drifting duplicate artifact.
- ✅ Non-`/goal` Stop events no longer emit low-value `FORGE_GOAL_EVIDENCE` JSON into the transcript.
- ⚠️ Plans gain one more section for full workflows; this is accepted to preserve rationale before compaction/fresh-session seams.
- 🔮 Model/effort budgeting and Phase 3.3 plan-review offloading remain future measured experiments, not first-step automation.
