# /quick-fix — Host-Neutral Small-Change Workflow

Use only for a clearly understood, low-risk change that touches at most three files, needs no
architecture decision, and has an obvious verification path. Otherwise use `/fix-bug` or
`/new-feature`.

## Steps

1. Resolve the active host and run `.forge/hooks/lib/workflow-state.sh show` (PowerShell: the `.ps1`
   twin). If the matching workflow is active, use `workflow-state.sh checkpoint` with the displayed
   phase and exact next step to record `Last active host`, then resume it. If inactive, continue only
   through the deterministic branch/base preflight. Forge provides no edit lock: concurrent sessions are allowed,
   including simultaneous editing. Coordinate overlapping writes; if any session mutates the candidate, candidate-bound evidence becomes stale.
2. Confirm the branch is not protected and resolve the intended base ref. Then invoke
   `.forge/hooks/lib/workflow-state.sh activate --host <claude|codex> --workflow quick-fix --task
   <slug> --base-ref <ref-or-sha> --phase diagnosis --next-step 'state acceptance check'` before any discretionary investigation or tracked mutation.
   Activation freezes the resolved base SHA and base identity, creates
   task-local evidence directories, populates receipt paths, and initializes review iteration zero.
3. State the acceptance check and affected files before production implementation. If behavior changes, write and observe a failing
   test first; documentation-only corrections use a direct rendered/static check instead.
4. Make the smallest change and run the owning focused check.
5. Update applicable solution/changelog material. Run the Forge-owned simplification phase only
   when code changed.
6. Force-stage only explicitly approved ignored artifacts, then `git add -A`; freeze the staged-clean
   candidate.
7. At finalization, invoke `.forge/hooks/lib/workflow-state.sh checkpoint --host <claude|codex>
   --phase review --next-step 'dispatch final paired reviews' --begin-review` before reviewer
   dispatch. Run distinct fresh `code-spec` and
   `code-quality` reviews concurrently when useful, then `verify-app` and applicable E2E read-only
   against that same candidate. Both review receipts must name the same candidate and iteration.
   User-facing changes require the feature/regression journey matrix; non-user-facing
   changes may record E2E N/A with a concrete supported reason.
8. Any candidate mutation invalidates final review and verifier receipts. Restage, refreeze,
   increment the iteration before review, and rerun the affected final gates.
9. Promote the exact candidate and commit. Use `workflow-state.sh checkpoint` for workflow control,
   update checklist/narrative content and verified memory, then finish with `workflow-state.sh
   checkpoint --host <claude|codex> --phase complete --next-step none`.
10. Show any push/PR mutation and pause for explicit human authorization. Stop after the requested
    external action; do not merge unless separately authorized.

Reviewer `auto` uses the other installed engine and falls back automatically to a fresh same-engine
reviewer on launch/capability failure. A finding is not fallback. Reports and receipts remain under
`.forge/local/` and do not become post-verification source changes.

Use one broad review, one repair pass, and one closure review limited to named findings plus direct
regressions; never start a second broad scan for the same candidate revision. If a reachable P0/P1
remains, allow one surgical repair and verification, then surface it to the developer. P3, cosmetic,
speculative, and unchanged-candidate concerns do not keep the closure review open.
