# /new-feature — Host-Neutral Feature Workflow

Build a substantial feature from requirements through an open PR. The active Claude Code or Codex
host is the main agent for this session; there is no permanent main engine.

## 0. Resume or Start

1. Read `.forge/instructions.md`, `.forge/rules/`, and `.forge/local/state.md`. Initialize state from
   `.forge/state.template.md` only when it is absent; never overwrite developer state. Use the
   host's file read/write capabilities for state, not shell commands.
2. Resolve the active host through its installed adapter and record `Last active host`. If the host
   changed, resume the exact next unchecked durable step. Warn that simultaneous editing can
   overwrite work, but do not create a lock or lease.
3. From the primary checkout, create the isolated worktree with
   `.forge/hooks/lib/worktree-lifecycle.sh create --kind feat --name <slug> --base <ref-or-sha>`
   (PowerShell: `worktree-lifecycle.ps1 -Action Create -Kind feat -Name <slug> -Base <ref-or-sha>`).
   Only in the Forge source checkout, when the installed path is absent, use the tracked
   `hooks/lib/worktree-lifecycle.sh` or `.ps1` instead. This creates exactly `feat/<slug>` under
   `.worktrees/<slug>` and copies missing private/ignored installed harness files without
   overwriting anything.
4. Continue from a native Claude Code or Codex session rooted in the new worktree so its normal
   SessionStart hook creates the protected host receipt. If that receipt is absent, stop and reopen
   the host in the worktree; never synthesize a receipt or bind an older task/session ID manually.
5. The helper seeds only `## State` (with `### Now` cleared), `## Open Questions`, and `## Blockers`
   from the primary checkout and writes the exact baseline to
   `.forge/local/.state-seed-snapshot.md`. It never seeds workflow, goal, authorization, receipts,
   evidence, or local memory. For an adopted worktree, run the helper's `seed` action once; if a
   state or snapshot already exists, reconcile it explicitly rather than guessing.
6. Before the first feature change, persist the intended base ref and resolved base SHA. The SHA is
   immutable for the workflow and is passed to every candidate, dispatcher invocation, receipt,
   isolated repository, and review prompt. An adopted worktree reuses its recorded base; if ancestry
   is ambiguous and no base was recorded, require an explicit base rather than recomputing it.
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

## 1. Requirements

Run `/prd:discuss <feature>` and `/prd:create <feature>`. Do not design implementation details in
the PRD. Continue only after explicit PRD approval and record the approved PRD path/version.

If autonomous execution would help, offer the active host's native `/goal`. Forge state remains the
authority for objective, nonce, persistent turn ceiling/count, checklist, evidence, authorization,
and terminal status. Native counters may reset; the Forge record never does.

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
`VERDICT: PARTIAL`, and `VERDICT: PASS` explicitly. Resolve
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
7. Against that exact candidate, read-only and without mutation:
   - dispatch distinct fresh `code-spec` and `code-quality` reviews and verify the pair;
   - run `verify-app`, persist its report with leading `VERDICT:`, and write its receipt;
   - run the complete feature/regression E2E matrix, persist its report with leading `VERDICT:`, and
     write its receipt.
8. Promote the exact tree through the candidate promotion helper, then commit.

Before each final code-review iteration: use one broad review, one repair pass, and one closure
review. Closure checks only named findings and direct regressions; do not start a second broad scan.
One still-open reachable P0/P1 may receive one surgical repair plus surgical verification, then
surface the blocker to the developer. P3, cosmetic, speculative, purely theoretical, and
unchanged-candidate concerns do not keep the loop open; a concrete material P2 still prevents
certification. Run focused owning checks during repair and one complete aggregate after final bytes
freeze.

Human-readable reports and receipts remain local under `.forge/local/`; they are not post-verification
source commits. A mutation invalidates only evidence whose boundary it can affect; any mutation in
the exact-candidate boundary returns to step 5 and requires fresh candidate-bound final receipts.
Do not restart unrelated focused verification mechanically. Intermediate reviews never satisfy the
ship gate.

For a Developer Demo PR body, every claimed-current diagram edge must have a `file:line` Evidence
row. An unsupported claimed-current edge is P1; clearly labeled planned/inferred briefing edges are
not current-behavior claims.

## 7. State, Memory, and PR

Update `.forge/local/state.md` and project memory with verified learnings only. Show the exact PR
title/body/base/head and pause for human authorization. The developer creates the authorization
record bound to the active objective nonce and candidate. Only then push and run `gh pr create`.

If E2E truly does not apply, use the canonical checklist form
`- [x] E2E verified — N/A: <concrete supported reason>`.

PR creation is a new external mutation and never council-authorized. Ordinary reviewer fallback is
automatic. Stop after the PR is open; do not merge.
