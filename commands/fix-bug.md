# /fix-bug — Host-Neutral Systematic Bug-Fix Workflow

Diagnose and fix a reproducible defect through an open PR. The active Claude Code or Codex host is
the main agent for this session; there is no permanent main engine.

Apply the shared [Startup boundary](../rules/workflow.md#startup-boundary) before the first workflow
step. It is the canonical activation, resume, isolation, and setup-failure contract.

## 0. Resume or Start

1. Read `.forge/instructions.md` and `.forge/rules/`, resolve the active host, then run
   `.forge/hooks/lib/workflow-state.sh show` (PowerShell: the `.ps1` twin). If canonical state is
   absent or invalid, stop and use the setup/migration path; never reconstruct it ad hoc.
2. If this worktree already has the matching workflow active, use `workflow-state.sh checkpoint`
   with the displayed phase and exact next step to record `Last active host`, then resume that exact
   next unchecked durable step. If it is inactive, continue only through the deterministic
   worktree/base preflight below. Forge provides no edit lock: concurrent sessions are allowed, including simultaneous editing;
   coordinate overlapping writes.
   If any session mutates the candidate, candidate-bound evidence becomes stale and must be
   regenerated before certification.
3. Work outside the protected default branch in one isolated physical worktree, reusing an existing
   prepared native worktree when present. If none exists, use the portable helper where allowed:
   `.forge/hooks/lib/worktree-lifecycle.sh create --kind fix --name <slug> --base
   <ref-or-sha>` (PowerShell: `worktree-lifecycle.ps1 -Action Create -Kind fix -Name <slug> -Base
   <ref-or-sha>`).
   In a fresh host-native worktree, normalize and seed it before activation with
   `.forge/hooks/lib/worktree-lifecycle.sh adopt --kind fix --name <slug> --base <ref-or-sha>
   --worktree "$PWD"` (PowerShell: `worktree-lifecycle.ps1 -Action Adopt -Kind fix -Name <slug>
   -Base <ref-or-sha> -Worktree $PWD.Path`). This safely replaces a clean, unpublished
   host-generated branch name with `fix/<slug>`; it never renames protected, dirty, shared, or
   published work.
   Only in the Forge source checkout, when the installed path is absent, use the tracked
   `hooks/lib/worktree-lifecycle.sh` or `.ps1`. Native creation or adoption is optional only
   under the shared startup boundary; never create a second worktree for the same-directory handoff.
4. Continue work in the linked worktree from the current or a later Claude Code or Codex session.
   A session opened in the primary checkout may continue the linked worktree by using it as the
   working directory; opening the client at the worktree path remains optional. The installed
   adapter declares the current host for reviewer routing. No per-worktree Forge receipt, copied
   session identity, hook-trust bypass, or task-root reopening is required.
5. The helper seeds only `## State` (with `### Now` cleared), `## Open Questions`, and `## Blockers`
   from the primary checkout and writes the exact baseline to
   `.forge/local/.state-seed-snapshot.md`. It never seeds workflow, goal, authorization, receipts,
   evidence, or local memory. The `create` and `adopt` actions both seed state. If an inactive
   native worktree already has both state and its snapshot, `adopt` preserves them; if only one
   exists or a workflow is active, stop rather than guessing or overwriting it.
6. In the target worktree, run `workflow-state.sh show` and resolve the intended base ref. If state
   is inactive, invoke `.forge/hooks/lib/workflow-state.sh activate --host <claude|codex> --workflow
   fix-bug --task <slug> --base-ref <ref-or-sha> --phase diagnosis --next-step 'reproduce the
   symptom'` before any discretionary investigation or tracked mutation. On Windows, use the `.ps1`
   twin. The helper resolves and freezes the base SHA. Reuse an already-recorded base for an adopted
   active worktree; when ancestry is ambiguous, require an explicit base before activation. Never
   recompute from a later-moving default branch.
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

8. The activation helper creates the task-local evidence directories, populates every receipt path,
   freezes the base ref/SHA, and initializes review iteration zero. At each later durable boundary,
   invoke `.forge/hooks/lib/workflow-state.sh checkpoint --host <claude|codex> --phase <phase>
   --next-step '<exact next step>'`; do not directly edit workflow control rows.

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

If autonomous execution would help, offer the active host's native `/goal`. Populate `## /goal
session` only after the developer invokes `/goal` or explicitly requests native Goal autonomy, then
publish the activation with `.forge/hooks/lib/goal-ledger.sh activate` (or the PowerShell twin).
That human action is activation authority; persistent Forge state and the Git-common ledger provide
the objective, nonce, activation/count/ceiling, checklist, evidence, and terminal status. External
mutations retain their separate authorization boundaries.

## 3. Plan the Minimal Fix

Write `docs/plans/<bug>.md` with reproduction, root cause, immutable base ref/SHA, changed paths,
regression test, minimal production change, acceptance criteria, and user-journey coverage.
Do not invoke /council as a routine planning or contrarian step. The fresh plan reviewer is the
default independent challenge. Invoke council only when the developer explicitly requests it or a
concrete high-impact architectural fork remains unresolved after the cheapest safe falsifying
check.

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
An ordinary review finding is not a council trigger; keep plan findings in this bounded repair and
closure loop.

Review iterations remain subject to the canonical `POST_CERT_REVIEW_ROUND_LIMIT`
convergence-breaker in `.forge/rules/workflow.md`; only a human may adjudicate a tripped breaker.

Plan-stage spec-loss is P1 when it could produce the wrong fix; this does **not** relax the exit.

## 4. TDD Fix

Do not begin this phase before production implementation is authorized by clean plan evidence for
the current plan candidate.

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
`VERDICT: PASS`, `VERDICT: N/A`, `SURFACE_COVERAGE_WARNING`,
`FAIL_BUG`, `FAIL_INFRA`, `FAIL_INVALID_USE_CASE`, and `FAIL_STALE` explicitly.

## 6. Finalize One Exact Candidate

1. Finish implementation/TDD and update solution/changelog material.
2. After preliminary E2E, graduate committed use cases and generate/run tracked specs.
3. Run the Forge-owned simplification phase and apply justified changes.
4. Force-stage only explicitly approved ignored artifacts, then `git add -A`.
5. Freeze the staged-clean candidate.
6. At finalization, invoke `.forge/hooks/lib/workflow-state.sh checkpoint --host <claude|codex>
   --phase review --next-step 'dispatch final paired reviews' --begin-review` before any reviewer
   dispatch. Read-only against that exact candidate: run distinct fresh `code-spec` and `code-quality`
   reviews, `verify-app`, and the complete feature/regression E2E matrix. Persist reports with their
   leading `VERDICT:` lines and write candidate-bound receipts under `.forge/local/`.
   Both review receipts must name the same candidate and the incremented iteration.
7. Promote the exact tree through candidate promotion, then commit.

Before each final code-review iteration: use one broad review, one repair pass, and one closure
review. Before production repairs, follow the shared [Final-review repair](../rules/workflow.md#final-review-repair) transition.
Closure checks only named findings and direct regressions; do not start a second broad scan.
One still-open reachable P0/P1 may receive one surgical repair plus surgical verification, then
surface the blocker to the developer. P3, cosmetic, speculative, purely theoretical, and
unchanged-candidate concerns do not keep the loop open; a concrete material P2 still prevents
certification. Run focused owning checks during repair and one complete aggregate after final bytes
freeze.
A code-review finding is not a council trigger; keep findings in this bounded repair and closure
loop, then surface a remaining blocker to the developer.

A mutation invalidates only evidence whose boundary it can affect. Any candidate mutation
invalidates final review and verifier receipts; any mutation in the exact-
candidate boundary requires a new freeze and fresh candidate-bound final receipts. Do not restart
unrelated focused verification mechanically. Intermediate reviews never satisfy the ship gate.
Human-readable reports and receipts remain local evidence, not tracked post-verification source.

For a Developer Demo, every claimed-current diagram edge needs a `file:line` Evidence row; an
unsupported claimed-current edge is P1.

## 7. State, Memory, and PR

Use `workflow-state.sh checkpoint` for workflow control, update checklist/narrative content,
changelog, and project memory with verified facts, and finish with `workflow-state.sh checkpoint
--host <claude|codex> --phase complete --next-step none`. Show the exact PR
mutation and pause. Only fresh human authorization bound to the active nonce/candidate permits push
and `gh pr create`. Native Goal activation does not grant it. Reviewer engine fallback is automatic;
PR creation is not.

If E2E truly does not apply, use the canonical checklist form
`- [x] E2E verified — N/A: <concrete supported reason>` and persist the matching
candidate-bound `VERDICT: N/A` report and E2E receipt. A prose N/A alone cannot certify V6.

Stop after the PR is open. Do not merge.
