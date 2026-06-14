# Forge Harness

Forge is a Claude Code workflow harness that coordinates planning, implementation, review, verification, and handoff artifacts for downstream software projects.

## Language

**Runtime context efficiency**:
Reducing main-thread context growth during active Forge workflows while preserving mandatory review gates and durable rationale.
_Avoid_: token efficiency, run proper token efficiency, saving tokens

**Main thread**:
The primary Claude conversation that orchestrates the workflow, reviews summaries, and makes phase decisions; subagents and Codex side work are not the main thread.
_Avoid_: active chat, main session when contrasted ambiguously with worktrees

**Durable rationale**:
The preserved “why” for decisions, trade-offs, rejected alternatives, and accepted risks, stored in artifacts that survive compaction or fresh-session seams.
_Avoid_: notes, context dump

**Phase-boundary seam**:
A deliberate workflow transition where Forge can summarize, persist, compact, or restart from artifacts without losing decision continuity. The Phase 3 → Phase 4 seam is the transition from approved plan to implementation.
_Avoid_: checkpoint when the meaning is context-management rather than gate status

**Fresh implementation session**:
A new Claude session or autonomous handoff that starts implementation from durable artifacts and selected files, not from the full planning transcript.
_Avoid_: restart when it implies losing the plan or rationale

**Same-session compaction**:
A context-management move where the main thread remains responsible for the workflow but compresses prior discussion after durable rationale has been written.
_Avoid_: clear, reset

**Implementation Handoff**:
A durable plan-file section that lets implementation start after compaction or in a fresh implementation session without rereading the full planning transcript. It carries outcome, decision ledger, non-goals, invariants, task contract, and review expectations.
_Avoid_: summary when it omits rationale or constraints

**Task Contract**:
The implementation-facing contract inside the Implementation Handoff. For full plans it includes the dispatch table with task IDs, dependencies, and concrete write paths; for trivial plans it may be a short ordered task list.
_Avoid_: dispatch plan when used as a separate drifting artifact

**Fresh-session trigger**:
A heuristic signal that the next phase should start from durable artifacts rather than the full prior transcript. Early triggers are large task count, multiple plan-review iterations, material council/spike changes, heavy Phase 3 churn, or metrics showing Phase 3 dominates context growth.
_Avoid_: hard token cutoff until measured thresholds exist

**Goal evidence**:
The structured progress signal used by Forge's autonomous goal loop to decide whether PR-ready conditions are satisfied or blocked. Outside an active goal loop, goal evidence is not part of normal workflow tracking.
_Avoid_: workflow reminder, quality gate enforcement

## Example dialogue

Dev: “Should we optimize total tokens or main-thread context first?”
Domain expert: “For Forge, target runtime context efficiency first: keep the main thread lean, but do not hide missing rationale. Move durable rationale into plans, handoffs, or ADRs before trimming conversation context.”
