# Forge V6 Strict Receipt Workflow Design

## Problem

Forge V6 converted `new-feature`, `fix-bug`, and `quick-fix` to the canonical dual-engine
workflow, but the shipping hook still contains the transitional receipt-v2 activation rule: final
receipt validation runs only after `Candidate receipt` contains a non-placeholder path. An active
V6 workflow can therefore leave the receipt table untouched and continue through legacy checklist
evaluation. That contradicts the V6 cutover plan, which required strict receipt-only operation once
all development workflow producers were converted.

The resulting failure is procedural, not merely cosmetic. A main agent can narrate completed
reviews, leave structured receipt linkage absent or stale, lose the final review iteration, and
reach a shipping action without entering the candidate-bound evidence path. The compact V6
workflows also removed explicit state-transition instructions that previously kept Claude on the
required phase order.

## Goals

1. Make candidate-bound receipt validation mandatory for every shipping action in an active,
   canonical V6 workflow.
2. Keep the no-code checkpoint carve-out for a direct documentation-only commit, while requiring
   receipts for every push and PR creation.
3. Make the receipt and review-iteration state transitions explicit enough for Claude or Codex to
   execute without reconstructing the protocol from helper implementations.
4. Preserve one canonical engine-neutral policy with thin host adapters.
5. Preserve cross-host continuation in the same branch and linked worktree without a host lease,
   copied session, or regenerated evidence when the candidate bytes are unchanged.
6. Keep genuine V5 migration diagnostics without allowing V5 evidence or V6 placeholders to
   certify a V6 shipping action.

## Non-Goals

- Recreate the V5 command files or their full verbosity.
- Transfer Claude or Codex native conversation history between hosts.
- Add a workflow lock or permanent main-engine setting.
- Make checklist prose a substitute for candidate-bound executable evidence.
- Change reviewer transport authorization, model routing, or automatic reviewer fallback.
- Expand the hook into a general shell parser or gate non-shipping commands.

## Considered Approaches

### A. Canonical V6 hard cutover (selected)

Treat an active canonical V6 state as sufficient to require the complete receipt set. Placeholder,
missing, malformed, mixed-candidate, stale, or non-clean receipt linkage blocks shipping. Retain
legacy parsing only outside the canonical V6 certification path.

This directly repairs the incomplete Task 9 cutover, has no new agent-controlled mode switch, and
keeps receipt evidence authoritative.

### B. Add an `Evidence mode` state field

An explicit `legacy` or `receipt-v2` field would make activation visible, but it would introduce
another editable value that an agent could omit, preserve accidentally, or set incorrectly. It
would reproduce the same optional-activation weakness in a new form.

### C. Strengthen prompts only

Longer workflow prose could reduce mistakes but would leave the shipping bypass intact. It would
also depend on model attention for the boundary that Forge already has enough information to
enforce mechanically.

## Design

### Mandatory V6 receipt boundary

`check-workflow-gates.sh` and `check-workflow-gates.ps1` will classify state exactly as they do now:
the canonical `.forge/local/state.md` path is V6 state, and a non-empty `Command` inside its
`## Workflow` block means a workflow is active.

For every active V6 shipping action, the hook will invoke the platform-native
`verification-receipt` checker unconditionally. It will no longer inspect `Candidate receipt` to
decide whether receipt-v2 is active. The Stop-hook evidence builder and convergence breaker will
use the same schema-based classification: active canonical V6 state never consults legacy clean
rows, even before receipt paths are populated. Failure to resolve the helper or validate any
required state field or receipt blocks with a remediation that tells the operator to initialize
receipt paths, freeze a staged-clean candidate, set the review iteration before dispatch, and
rerun both review lenses and both verifiers.

The existing direct documentation-only `git commit` carve-out remains before final receipt
validation. It permits a checkpoint commit without mutating workflow state. `git push` and
`gh pr create` never use that carve-out and therefore always require current receipts.

The old checklist evidence reader remains code only for genuine compatibility inputs, but it is
unreachable as certification after an active canonical V6 state has been selected. A V6 state with
placeholders cannot fall through to it.

### One final code-review contract

All three development workflows require distinct fresh `code-spec` and `code-quality` receipts for
the same candidate and review iteration. `quick-fix` retains its smaller planning and implementation
ceremony but not a weaker final code-certification boundary. The two review invocations may run
concurrently when the host supports it, so this does not require serially doubling review latency.

`verify-app` and E2E remain separate candidate-bound receipts. The E2E report and receipt schemas
will gain an explicit `N/A` result for a concretely justified non-user-facing change. The report
must begin with `VERDICT: N/A`, and the receipt must bind that report, justification, and current
candidate. A checked prose box alone is not certification. `verify-app` remains PASS-only for a
successful ship decision.

### Executable state-transition protocol

The canonical workflow rule and the three development commands will state the following sequence
directly:

1. When activating the workflow, replace the workflow checklist, allocate one task-local evidence
   directory, populate every receipt path immediately, and set final `Review iteration` to `0`.
2. Complete planning and obtain clean plan-review evidence before starting production
   implementation. Plan-review iteration evidence remains distinct from final code-review
   iteration state.
3. Complete RED, GREEN, and the preliminary feature E2E phase before solution material,
   simplification, staging, or final freeze.
4. Stage the intended candidate and freeze it to the already-linked candidate receipt path.
5. Increment `Review iteration` before dispatching either final code reviewer. Both resulting
   receipts must record that value and the same candidate identity.
6. Write verifier reports first, then write candidate-bound `verify-app` and E2E receipts, and run
   the receipt checker before promotion.
7. Any in-boundary mutation makes the final set stale. Restage, refreeze, increment the iteration,
   and replace the state linkage with the new review and verification receipts. Never relabel old
   evidence.
8. Promotion consumes the exact validated candidate; no tracked artifact may be reset, moved, or
   edited after certification to change the promoted tree.

The protocol remains in canonical `.forge` sources. Claude and Codex adapters continue only to
translate native discovery and invocation syntax.

### Cross-host continuation

The state and receipts remain worktree-local and engine-neutral. `Last active host` records who
advanced the workflow but does not own or lock it. A switch from Codex to Claude, or Claude to
Codex, follows these rules:

- Open or target the same linked worktree and read its canonical state.
- Update only `Last active host` and resume the exact `Next step`; retain workflow base ref/SHA and
  review iteration.
- Existing receipts remain valid when the candidate identity and receipt freshness still validate.
  Reviewer `main_host`, requested engine, and actual engine fields are audit/routing metadata, not
  a lease.
- Any candidate mutation on the new host invalidates the affected final set and triggers the normal
  refreeze and iteration transition.
- Reviewer transport authorization is re-established when required by the resumed native session;
  it does not alter candidate identity or workflow ownership.

No native chat transcript is transferred or claimed to transfer. Durable state is the continuation
contract.

## Error Handling

The strict gate fails closed and distinguishes these operator actions in its message:

- Missing or placeholder linkage: initialize the task-local receipt paths and final review
  iteration.
- Missing candidate: stage and freeze the intended candidate.
- Missing or mismatched reviews: dispatch both final lenses at the current iteration.
- Missing or failed verifier receipt: persist a canonical report and write its receipt. E2E may be
  a candidate-bound `N/A`; `verify-app` may not.
- Stale candidate: return to staging/freeze and regenerate the complete affected set.
- Legacy state: run the authoritative full-refresh preview and resolve migration blockers; legacy
  prose cannot certify V6 shipping.

The hook never edits state or deletes evidence on the operator's behalf.

## Compatibility and Rollout

This is a deliberate V6 enforcement correction suitable for Forge 6.2. Existing V6 work in
progress remains resumable, but its next non-documentation shipping action blocks until the receipt
table is populated and the final candidate is certified. Existing complete, current receipt sets
continue to validate without regeneration.

Forge 6.1 reviewer-consent and linked-worktree configuration corrections remain prerequisites in
the release history. Upgrading a V6.0 downstream project to the release containing this design must
use the ordinary V6 upgrade path; V5, mixed, custom, or unknown trees still use the read-only full
refresh preview before any reconciliation.

## Test Strategy

Tests will be written before implementation and will cover both Bash and PowerShell source parity.

1. An active canonical V6 workflow with placeholder receipt paths and fully checked legacy rows
   must fail a push.
2. An active canonical V6 workflow with a missing receipt table must fail a push with initialization
   guidance.
3. A complete current V6 receipt set must pass unchanged.
4. A direct documentation-only commit must retain its existing carve-out, while push remains
   blocked without receipts.
5. A genuine legacy state input must not certify a V6 shipping action.
6. `quick-fix`, `fix-bug`, and `new-feature` must all declare the same paired final review contract
   and explicit receipt initialization/iteration transitions.
7. A candidate-bound E2E `N/A` report and receipt with a concrete reason must satisfy the E2E
   component, while a prose-only N/A, empty reason, or `verify-app` N/A must fail.
8. A Codex-originated state and candidate must continue in Claude with the same base SHA,
   iteration, next step, and candidate identity when bytes are unchanged.
9. A mutation after that host switch must invalidate the old receipts.
10. Static Bash/PowerShell contract checks must pin equivalent strict activation and remediation
   language. PowerShell runtime behavior remains CI-owned when `pwsh` is unavailable locally.
11. The focused hook/evidence suites, fast suite, aggregate suite, and `git diff --check` must pass
    against the final bytes before release claims.

## Expected Files

- `hooks/check-workflow-gates.sh` and `.ps1`: remove optional V6 receipt activation and enforce the
  current receipt set after the documentation-only carve-out.
- `hooks/build-evidence.sh` and `.ps1`, plus `hooks/lib/review-breaker.sh` and `.ps1`: derive V6
  receipt mode from canonical state rather than candidate-path population, so Stop evidence and
  convergence accounting cannot revive legacy clean rows.
- `rules/workflow.md`: own the exact final-evidence state-transition protocol.
- `commands/new-feature.md`, `commands/fix-bug.md`, and `commands/quick-fix.md`: invoke the protocol
  at explicit phase boundaries; make quick-fix final review parity explicit.
- `state.template.md`: initialize and explain receipt paths, iteration zero, invalidation, and
  cross-host continuation without suggesting optional activation.
- `FORGE.template.md`: state that active V6 shipping always requires current structured receipts.
- `hooks/lib/verification-receipt.sh` and `.ps1`, `agents/verify-e2e.md`, and `rules/testing.md`:
  represent a justified E2E N/A as structured candidate-bound evidence instead of a prose bypass.
- `tests/template/test-build-evidence.sh`, `tests/template/test-hooks.sh`,
  `tests/template/test-workflow-parity.sh`, and focused parity contracts: prove strict activation,
  continuation, mutation invalidation, and platform equivalence.
- Release documentation and synchronized version surfaces: describe the enforcement correction and
  V6.0/V6.1 upgrade consequence.

## Acceptance Criteria

- No active canonical V6 workflow can reach legacy checklist certification because receipt paths
  are absent or placeholders.
- All development workflows expose one paired final review and verifier contract.
- The same unchanged worktree can move between Claude and Codex without resetting base, iteration,
  candidate, or evidence.
- Candidate mutation on either host invalidates stale receipts before shipping.
- The docs-only checkpoint carve-out remains narrow and cannot authorize push or PR creation.
- Canonical policy remains single-sourced and host adapters remain thin.
- Bash and PowerShell implementations remain statically equivalent, with all available executable
  suites green and unavailable Windows execution reported honestly.
