# /fix-bug — Host-Neutral Systematic Bug-Fix Workflow

Diagnose and fix a reproducible defect through an open PR. The active Claude Code or Codex host is
the main agent for this session; there is no permanent main engine.

## 0. Resume or Start

1. Read `.forge/instructions.md`, `.forge/rules/`, and `.forge/local/state.md`. Initialize state from
   `.forge/state.template.md` only when absent. Use the host's file read/write capabilities for
   state, not shell commands.
2. Record `Last active host`. On a host switch, resume the exact next unchecked durable step. Warn
   about simultaneous editing; do not create a lock or lease.
3. Work outside the protected default branch in one isolated worktree. From the primary checkout,
   create it with `.forge/hooks/lib/worktree-lifecycle.sh create --kind fix --name <slug> --base
   <ref-or-sha>` (PowerShell: `worktree-lifecycle.ps1 -Action Create -Kind fix -Name <slug> -Base
   <ref-or-sha>`). Only in the Forge source checkout, when the installed path is absent, use the
   tracked `hooks/lib/worktree-lifecycle.sh` or `.ps1` instead. This creates exactly `fix/<slug>`
   under `.worktrees/<slug>` and copies missing private/ignored installed harness files without
   overwriting anything.
4. Continue from a native Claude Code or Codex session rooted in the new worktree. Its normal
   SessionStart hook creates and UserPromptSubmit refreshes the protected host receipt. If the host
   adapter was absent when the session opened, install or seed it and reopen the host in the
   worktree; never synthesize a receipt or bind an older task/session ID manually.
5. The helper seeds only `## State` (with `### Now` cleared), `## Open Questions`, and `## Blockers`
   from the primary checkout and writes the exact baseline to
   `.forge/local/.state-seed-snapshot.md`. It never seeds workflow, goal, authorization, receipts,
   evidence, or local memory. For an adopted worktree, run the helper's `seed` action once; if a
   state or snapshot already exists, reconcile it explicitly rather than guessing.
6. Before the first fix change, persist the intended base ref and resolved base SHA. Reuse an
   already-recorded base for an adopted worktree; when ancestry is ambiguous, require an explicit
   base. Never recompute from a later-moving default branch.
7. Replace the active workflow checklist with:

   ```markdown
   - [ ] Symptom reproduced
   - [ ] Root cause proven
   - [ ] Existing solution/research checked
   - [ ] Fix plan approved
   - [ ] Plan review receipts clean
   - [ ] Regression test RED
   - [ ] Minimal fix GREEN
   - [ ] Preliminary feature E2E complete
   - [ ] Solution and changelog material complete
   - [ ] Simplification complete
   - [ ] Candidate frozen
   - [ ] Final code review receipts clean
   - [ ] Verify-app receipt PASS
   - [ ] E2E verified
   - [ ] Candidate promoted and committed
   - [ ] State and memory updated
   - [ ] PR creation authorized
   - [ ] PR open
   ```

## 1. Systematic Diagnosis

Follow four phases without editing production code early:

1. Reproduce the exact symptom with a minimal, repeatable check.
2. Trace data/control flow to the first incorrect decision or state transition.
3. Compare a working control and the failing case; test one hypothesis at a time.
4. State the proven root cause and the production change that a regression test must catch.

If reproduction is impossible, record `BLOCKED` with the missing environment/input rather than
guessing. When investigation needs network or write access, invoke the Forge opinion workflow's
investigate profile (`/opinion investigate` in Claude Code; `$opinion investigate` in Codex) and
require an independent `investigation-repro` receipt before treating the hypothesis as actionable.

## 2. Existing Solutions and Research

Search repository history, issues, plans, memory, and current official documentation for the
affected libraries/APIs. Dispatch `research-first` when current external behavior matters. Reuse a
proven local pattern where it fits; do not copy a superficially similar fix without checking its
invariants.

If autonomous execution would help, offer the active host's native `/goal`. Persistent Forge state,
not resettable native counters, remains authoritative for the objective, nonce, budget, checklist,
evidence, authorization, and terminal status.

## 3. Plan the Minimal Fix

Write `docs/plans/<bug>.md` with reproduction, root cause, immutable base ref/SHA, changed paths,
regression test, minimal production change, acceptance criteria, and user-journey coverage.
Use `/council` only for a consequential design fork.

Freeze the plan hash and dispatch a fresh `plan` reviewer with `--engine auto`. Automatic
same-engine fallback handles an unavailable/failed other engine without stopping. Findings are not
fallback.

The plan remains at `docs/plans/<bug>.md` inside the candidate. Dispatch the plan review with
`--artifact git:working-tree` so the immutable snapshot contains the plan, current code, and tests.
Before capture, run `git add -N -f -- docs/plans/<bug>.md`; this intent-to-add marker makes an
ignored plan visible to the snapshot without staging its contents or committing it.
Do not move or copy the plan into `.forge/local` or a hand-built review-context directory, and do
not use a file-only artifact for a review that depends on repository context.

Before each plan-review iteration: use one broad review, one repair pass, and one closure review.
Closure checks only named findings and direct regressions; do not start a second broad scan. One
still-open reachable P0/P1 may receive one surgical repair plus surgical verification, then surface
the blocker to the developer. P3, cosmetic, speculative, purely theoretical, and unchanged-candidate
concerns do not keep the loop open; a concrete material P2 still prevents certification.

Review iterations remain subject to the canonical `POST_CERT_REVIEW_ROUND_LIMIT`
convergence-breaker in `.forge/rules/workflow.md`; only a human may adjudicate a tripped breaker.

Plan-stage spec-loss is P1 when it could produce the wrong fix; this does **not** relax the exit.

## 4. TDD Fix

1. Write the smallest regression test that fails for the proven root cause; observe the RED.
2. Implement the smallest production change that makes it GREEN.
3. Run the owning tests and a direct control proving unrelated supported behavior remains intact.
4. Refactor only after green.

Invoke the active host's exact `forge-v6-producer` agent type for each bounded implementation task.
Supply its acceptance criteria, immutable base SHA, and host runtime agent/task ID; the producer
must emit the required structured spec and quality task receipts.

## 5. Preliminary E2E

For user-facing behavior, design Actor/Scenario/Intent/Interface/Setup/Steps/Verification/Persistence
use cases and a Surface coverage decision. Run `verify-e2e` in feature mode while fixes are allowed.
Parse its `VERDICT:` and `SUGGESTED_PATH:` headers, create the suggested local evidence directory,
and persist the unchanged leading header with the report. Handle `VERDICT: FAIL`, `VERDICT: PARTIAL`,
`VERDICT: PASS`, `SURFACE_COVERAGE_WARNING`,
`FAIL_BUG`, `FAIL_INFRA`, `FAIL_INVALID_USE_CASE`, and `FAIL_STALE` explicitly.

## 6. Finalize One Exact Candidate

1. Finish implementation/TDD and update solution/changelog material.
2. After preliminary E2E, graduate committed use cases and generate/run tracked specs.
3. Run the Forge-owned simplification phase and apply justified changes.
4. Force-stage only explicitly approved ignored artifacts, then `git add -A`.
5. Freeze the staged-clean candidate.
6. Read-only against that exact candidate: run distinct fresh `code-spec` and `code-quality`
   reviews, `verify-app`, and the complete feature/regression E2E matrix. Persist reports with their
   leading `VERDICT:` lines and write candidate-bound receipts under `.forge/local/`.
7. Promote the exact tree through candidate promotion, then commit.

Before each final code-review iteration: use one broad review, one repair pass, and one closure
review. Closure checks only named findings and direct regressions; do not start a second broad scan.
One still-open reachable P0/P1 may receive one surgical repair plus surgical verification, then
surface the blocker to the developer. P3, cosmetic, speculative, purely theoretical, and
unchanged-candidate concerns do not keep the loop open; a concrete material P2 still prevents
certification. Run focused owning checks during repair and one complete aggregate after final bytes
freeze.

A mutation invalidates only evidence whose boundary it can affect; any mutation in the exact-
candidate boundary requires a new freeze and fresh candidate-bound final receipts. Do not restart
unrelated focused verification mechanically. Intermediate reviews never satisfy the ship gate.
Human-readable reports and receipts remain local evidence, not tracked post-verification source.

For a Developer Demo, every claimed-current diagram edge needs a `file:line` Evidence row; an
unsupported claimed-current edge is P1.

## 7. State, Memory, and PR

Update `.forge/local/state.md`, changelog, and project memory with verified facts. Show the exact PR
mutation and pause. Only a human-created authorization record bound to the active nonce/candidate
permits push and `gh pr create`. Reviewer engine fallback is automatic; PR creation is not.

If E2E truly does not apply, use the canonical checklist form
`- [x] E2E verified — N/A: <concrete supported reason>`.

Stop after the PR is open. Do not merge.
