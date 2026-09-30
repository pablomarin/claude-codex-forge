# /new-feature — Host-Neutral Feature Workflow

Build a substantial feature from requirements through an open PR. The active Claude Code or Codex
host is the main agent for this session; there is no permanent main engine.

Apply the shared [Startup boundary](../rules/workflow.md#startup-boundary) before the first workflow
step. It is the canonical activation, resume, isolation, and setup-failure contract.

## 0. Resume or Start

1. Read `.forge/instructions.md` and `.forge/rules/`, resolve the active host through its installed
   adapter, then run `.forge/hooks/lib/workflow-state.sh show` (PowerShell: the `.ps1` twin). If the
   canonical state is absent or invalid, stop and use the setup/migration path; never reconstruct it
   ad hoc.
2. If this worktree already has the matching workflow active, use `workflow-state.sh checkpoint`
   with the displayed phase and exact next step to record `Last active host`, then resume that step.
   If it is inactive, continue only through the deterministic worktree/base preflight below. There
   is no Forge edit lock; concurrent sessions are allowed, including simultaneous editing, so coordinate overlapping writes.
   If any session mutates the candidate, candidate-bound evidence becomes stale and must be
   regenerated before certification.
3. Reuse an existing isolated physical worktree, including a prepared native worktree. If none
   exists, create one with the portable helper where allowed:
   `.forge/hooks/lib/worktree-lifecycle.sh create --kind feat --name <slug> --base <ref-or-sha>`
   (PowerShell: `worktree-lifecycle.ps1 -Action Create -Kind feat -Name <slug> -Base <ref-or-sha>`).
   In a fresh host-native worktree, normalize and seed it before activation with
   `.forge/hooks/lib/worktree-lifecycle.sh adopt --kind feat --name <slug> --base <ref-or-sha>
   --worktree "$PWD"` (PowerShell: `worktree-lifecycle.ps1 -Action Adopt -Kind feat -Name <slug>
   -Base <ref-or-sha> -Worktree $PWD.Path`). This safely replaces a clean, unpublished
   host-generated branch name with `feat/<slug>`; it never renames protected, dirty, shared, or
   published work.
   Only in the Forge source checkout, when the installed path is absent, use the tracked
   `hooks/lib/worktree-lifecycle.sh` or `.ps1`. Native creation or adoption is optional only under
   the shared startup boundary; never create a second worktree for the same-directory handoff.
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
   new-feature --task <slug> --base-ref <ref-or-sha> --phase requirements --next-step 'complete
   approved PRD'` before any discretionary investigation or tracked mutation. On Windows, use the
   `.ps1` twin. The helper resolves and freezes the base SHA, which is immutable for this workflow
   and is passed to every candidate, dispatcher invocation, receipt, isolated repository, and review
   prompt. An adopted active worktree reuses its recorded base; if ancestry is ambiguous and no base
   was recorded, require an explicit base before activation rather than guessing or recomputing it.
7. Replace the active `## Workflow` block and create this checklist:

   ```markdown
   - [ ] PRD approved
   - [ ] Research complete
   - [ ] Approach and plan approved
   - [ ] Plan review receipts clean
   - [ ] Implementation and TDD complete
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

## 1. Requirements

Run `/prd:discuss <feature>` and `/prd:create <feature>`. Do not design implementation details in
the PRD. Continue only after explicit PRD approval and record the approved PRD path/version.

If autonomous execution would help, offer the active host's native `/goal`. Populate `## /goal
session` only after the developer invokes `/goal` or explicitly requests native Goal autonomy, then
publish the activation with `.forge/hooks/lib/goal-ledger.sh activate` (or the PowerShell twin).
That human action is activation authority; Forge state and the Git-common ledger provide persistent
objective, nonce, activation/count/ceiling, checklist, evidence, and terminal status. Native counters
may reset; the repository ledger never does. External mutations retain their separate authorization
boundaries.

## 2. Research

Dispatch the canonical `research-first` role through the active host adapter. Its report identifies
current versions, official sources, breaking changes, design impact, test implications, and honest
unknowns. If fresh dispatch is unavailable, the current host may do the same bounded research and
must label that fallback. Do not turn missing research access into a verified result.

## 3. Design and Plan

1. Produce at least two viable approaches when genuine alternatives exist. Compare complexity,
   blast radius, reversibility, time to validate, and user/correctness risk.
2. Use `/council` for a consequential fork or a contrarian check. The council owns whole-topology
   engine fallback; a missing other engine automatically becomes an all-main-engine council.
3. Write `docs/plans/<feature>.md` with goal, architecture, tech stack, immutable base ref/SHA,
   acceptance criteria, exact files, TDD steps, and E2E use cases.
4. E2E use cases use Actor, Scenario, Intent, Interface, Setup, Steps, Verification, and Persistence.
   Include a Surface coverage decision and the `SURFACE_COVERAGE_WARNING` handling contract.
5. Freeze the plan content hash and dispatch a fresh `plan` review with `--engine auto`. The
   dispatcher automatically retries once with a fresh same-engine reviewer on launch/capability
   failure. Findings are not fallback.

The plan remains at `docs/plans/<feature>.md` inside the candidate. Dispatch the plan review with
`--artifact git:working-tree` so the immutable snapshot contains the plan, approved project inputs,
current code, and tests. Before capture, run `git add -N -f -- docs/plans/<feature>.md`; this
intent-to-add marker makes an ignored plan visible to the snapshot without staging its contents or
committing it. Do not move or copy the plan into `.forge/local` or a hand-built
review-context directory, and do not use a file-only artifact for a review that depends on
repository context.

Before each plan-review iteration: use one broad review, one repair pass, and one closure review.
Closure checks only named findings and direct regressions; do not start a second broad scan. One
still-open reachable P0/P1 may receive one surgical repair plus surgical verification, then surface
the blocker to the developer. P3, cosmetic, speculative, purely theoretical, and unchanged-candidate
concerns do not keep the loop open; a concrete material P2 still prevents certification.

Review iterations remain subject to the canonical `POST_CERT_REVIEW_ROUND_LIMIT`
convergence-breaker in `.forge/rules/workflow.md`; only a human may adjudicate a tripped breaker.

Plan-stage spec-loss is P1 when it could cause the wrong feature to be built; this does **not** relax
the exit requirement of no P0/P1/P2 for the approved plan revision.

## 4. Implement with TDD

Do not begin this phase before production implementation is authorized by clean plan evidence for
the current plan candidate.

Execute plan tasks in dependency order by invoking the active host's exact `forge-v6-producer`
agent type. Supply the bounded acceptance criteria, immutable workflow base SHA, and host runtime
agent/task ID in every handoff. Every task follows RED → GREEN → refactor and produces the
structured spec/quality task receipts required by the SubagentStop gate.

When a test fails unexpectedly, use the workflow's systematic-debugging phase: reproduce, identify
root cause, add a failing regression test, make the smallest fix, and rerun the owning suite.

Do not pause merely because the other engine is unavailable; automatic reviewer fallback is normal.
Stop only for a broken invariant, destructive/security-sensitive action, explicit user input, or an
external mutation requiring new human authority.

## 5. Preliminary User-Journey Validation

Design or refine feature E2E cases and run `verify-e2e` in feature mode while fixes are still
allowed. Parse its `VERDICT:` and `SUGGESTED_PATH:` headers, create the suggested local evidence
directory, and persist the unchanged leading header with the report. Handle `VERDICT: FAIL`,
`VERDICT: PARTIAL`, `VERDICT: PASS`, and `VERDICT: N/A` explicitly. Resolve
`FAIL_BUG`, `FAIL_INFRA`, `FAIL_INVALID_USE_CASE`, and `FAIL_STALE` before final freeze. A sanctioned
setup path that is broken is a product/infrastructure failure, not permission to seed through a DB
or undocumented interface.

## 6. Finalize One Exact Candidate

Run this order exactly:

1. Finish implementation and TDD.
2. Create/update solution documentation and `docs/CHANGELOG.md` when applicable.
3. After the preliminary feature E2E pass, graduate the committed use cases and generate/run any
   tracked specs.
4. Run the Forge-owned simplification phase and apply justified changes.
5. Force-stage only the workflow's explicit approved ignored artifacts, then run `git add -A`.
6. Freeze a staged-clean candidate with `candidate-fingerprint`; record its receipt under
   `.forge/local/evidence/<task-id>/`.
7. At finalization, invoke `.forge/hooks/lib/workflow-state.sh checkpoint --host <claude|codex>
   --phase review --next-step 'dispatch final paired reviews' --begin-review` before any reviewer
   dispatch. Against that exact candidate,
   read-only and without mutation:
   - dispatch distinct fresh `code-spec` and `code-quality` reviews and verify the pair;
   - run `verify-app`, persist its report with leading `VERDICT:`, and write its receipt;
   - run the complete feature/regression E2E matrix, persist its report with leading `VERDICT:`, and
     write its receipt.
   Both review receipts must name the same candidate and the incremented iteration.
8. Promote the exact tree through the candidate promotion helper, then commit.

Before each final code-review iteration: use one broad review, one repair pass, and one closure
review. Before production repairs, follow the shared [Final-review repair](../rules/workflow.md#final-review-repair) transition.
Closure checks only named findings and direct regressions; do not start a second broad scan.
One still-open reachable P0/P1 may receive one surgical repair plus surgical verification, then
surface the blocker to the developer. P3, cosmetic, speculative, purely theoretical, and
unchanged-candidate concerns do not keep the loop open; a concrete material P2 still prevents
certification. Run focused owning checks during repair and one complete aggregate after final bytes
freeze.

Human-readable reports and receipts remain local under `.forge/local/`; they are not post-verification
source commits. Any candidate mutation invalidates final review and verifier receipts. A mutation in
the exact-candidate boundary returns to step 5 and requires fresh candidate-bound final receipts.
Do not restart unrelated focused verification mechanically. Intermediate reviews never satisfy the
ship gate.

For a Developer Demo PR body, every claimed-current diagram edge must have a `file:line` Evidence
row. An unsupported claimed-current edge is P1; clearly labeled planned/inferred briefing edges are
not current-behavior claims.

## 7. State, Memory, and PR

Use `workflow-state.sh checkpoint` for workflow control, update checklist/narrative content and
project memory with verified learnings only, and finish with `workflow-state.sh checkpoint --host
<claude|codex> --phase complete --next-step none`. Show the exact PR
title/body/base/head and pause for human authorization. The developer creates the authorization
record bound to the active objective nonce and candidate. Only then push and run `gh pr create`.

If E2E truly does not apply, use the canonical checklist form
`- [x] E2E verified — N/A: <concrete supported reason>` and persist the matching
candidate-bound `VERDICT: N/A` report and E2E receipt. A prose N/A alone cannot certify V6.

PR creation is a new external mutation and never council-authorized. Ordinary reviewer fallback is
automatic. Stop after the PR is open; do not merge.
