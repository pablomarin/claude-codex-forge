# Automatic repository worktree setup

User approval: install and upgrade must include the repository's Git worktrees by default. Keep the
community flow simple and preserve project files, branches, uncommitted work and workflow state.
Immutable workflow base: quick-fix/setup-docs at bac5a39d5012bd07b53e0120bb98393c40b5c183.
The earlier unreleased documentation commit is included; this change retains pending release6.4.8.

## Reproduction and cause

Both setup entrypoints target only their process cwd. A fresh Git repo with primary plus linked
checkout gets Forge in just the invoked checkout. Existing full-refresh and marker materialization
already preserve ownership/state and shared Codex hook registration is deliberately primary-owned.

## Minimal implementation

1. Add `--this-checkout-only` and PowerShell `-ThisCheckoutOnly` with equivalent help. Default setup,
   upgrade, force and force preview discover the physical Git root and actual Git worktree list.
   Help, invalid options, legacy global retirement stay non-mutating/single-purpose. Reject a
   subdirectory before any sibling action; a non-Git directory retains existing initialization.
2. If multiple worktrees exist, run the existing entrypoint once per discovered checkout with the
   opt-out switch to prevent recursion. Git's primary-first order supplies shared hook registration
   even when the user starts in a linked worktree. Pass original installer options literally and
   never promote default setup to upgrade: canonical materialization already refreshes adapters,
   while changing FORCE would overwrite user Playwright scaffolds. Skip bare metadata entries,
   which are not checkouts; unavailable actual checkout entries remain failures. Use the
   same installer revision and release throughout. Do not create/switch branches or activate Goal.
3. Before each write in automatic multiple-worktree scope, reuse the existing read-only full-refresh
   planner (`--force --dry-run` / `-Force -DryRun`, checkout-only), preserving its output. Do not
   introduce a second ownership/state checker or bypass a BLOCKED plan. Python remains required
   for this authoritative preflight on Windows as well as Unix. Explicit preview never invokes a
   writing mode. A regular upgrade does not automatically convert a legacy sibling: report its
   unsupported mode and leave it untouched; the agent can guide the existing previewed migration.
4. Report each checkout's path, release and preview/materialized/blocked outcome. Continue independent
   checkouts after one failure, but return nonzero if any fails or is missing. No cross-checkout
   atomic transaction or rollback is claimed; existing per-checkout transaction semantics apply.
   Files materialized do not certify vendor authentication, hook trust or runtime readiness.
5. Preserve current single-checkout behavior through opt-out and for repositories with one checkout.
   Do not mutate unrelated Git repos or home configuration. No new manifest-owned runtime files.

Preliminary installed council E2E exposed one existing portable PowerShell separator mismatch:
`candidate-fingerprint.ps1` recognizes excluded Git/local directories only with backslashes, so
PS7 on Unix traverses live private session stores while parallel peers remove them. Normalize
the relative path separators in the existing exclusion predicate (one line); Windows semantics
and Bash's existing pruning stay unchanged. First prove RED with an unreadable excluded private
directory through the actual identity CLI, then GREEN and fresh installed council in both mains.
No new ownership checks, session state or routing machinery.

## TDD and acceptance

Focused installed CLI test twins (Bash and native PowerShell5.1-compatible): start from a linked
checkout and install primary + two links, including spaces/Unicode paths. Confirm exact versions,
canonical managed hashes/discovery, branch/HEAD and user config/app/local state preservation. Commit
installed fixture, dirty application work, make one installed canonical hook stale on disk without
changing source snapshot, upgrade from a link, verify source equivalence on all checkouts.
Exercise opt-out (siblings unchanged), read-only force preview (all filesystem bytes unchanged),
blocked legacy/custom checkout (no writes there, overall failure and truthful partial report),
nonexistent/prunable worktree, bare metadata entries and subdirectory safe-stop. Verify default
Playwright setup preserves customized sibling scaffolds (the requested mode is unchanged).
No silent fallback to one checkout when Git listing fails. Readiness remains separately reported.

Exercise Claude-main/Codex-reviewer and Codex-main/Claude-reviewer installed routing in both Bash and
PowerShell fixtures, with real installed CLI commands and honest synthetic transport labels. Reuse
existing installed dual-engine seams for unchanged reviewer/opinion/council/fallback assertions.
Do not invent native runtime IDs or call portable PS7 native Windows qualification.

Run focused setup/worktree tests, owning setup flags/layout checks, doc contracts and run-fast once
final bytes settle; no exhaustive local run-all. Native Windows5.1 qualification remains CI-owned.

## Documentation

README and setup guide now state automatic worktree scope and opt-out, removing the extra include
phrase. Update Getting Started, setup scenarios and upgrading where checkout-only guidance would
contradict the new default. Keep agent-first prompts and direct CLI paths on the same installers.
Record behavior in pending6.4.8 changelog; don't publish an extra release for the earlier local commit.

## Finalization

One broad configured plan review, one bounded repair and closure if needed. After GREEN and focused
verification freeze a single staged-clean candidate, obtain distinct configured spec/quality reviews
and candidate-bound app/E2E receipts. Native host producer type is not exposed by this Codex tool
surface; use available bounded agent with its actual runtime ID, following the producer contract,
and report that limitation without claiming a registered native producer invocation. Final review
and verifiers use canonical helpers. No push/PR/merge without current human authorization.

## Native Windows CI completion repair

The approved installer and stacked guidance PRs must both reach main after successful CI. Actual
Windows5.1 runs37561525413 and37570838820 exhausted the 30-minute job budget before all17
sequential suites completed. The second run passed all306 dispatcher assertions, including the
earlier two reproduction failures; preserve those failures as intermittent observations rather
than claiming an established runtime cause. Both runs stopped emitting output after the setup
worktree suite's first fixture began; its child installer output is redirected to a temporary
log, so current CI cannot distinguish slow progress from a stalled child.

Keep installer/runtime behavior and every assertion unchanged. Bound the diagnostic repair to
the CI/test harness: allow90 minutes for the broad native qualification job, print suite start,
finish and elapsed time, and tee each focused worktree installer invocation's output into its
existing log while keeping it visible. No suite is omitted; nonzero status still blocks Windows
attestation and merge. Windows completion remains unverified until fresh native CI actually passes.

Before changing the runner, reproduce missing suite boundaries with tiny disposable success and
failure fixtures through the real PowerShell runner; verify all discovered fixtures still run
after failure and the aggregate result remains nonzero. Cover setup log/exit preservation with
the owning focused worktree suite on portable PS7; it does not certify Windows5.1. Run run-fast
after final bytes settle. Obtain fresh exact-candidate paired reviews and app/E2E receipts before
normal promotion. Include this same bounded CI repair in the stacked guidance candidate and
revalidate its final receipts, keeping6.4.8 and6.4.9 release boundaries and monotonic counters.
