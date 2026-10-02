# /quick-fix — Host-Neutral Small-Change Workflow

Use only for a clearly understood, low-risk, non-user-facing change with an obvious focused check.
The change may touch at most three implementation paths; exact release metadata paths `README.md`
and `docs/CHANGELOG.md` do not consume that budget. If diagnosis is uncertain, architecture or
product judgment is needed, the behavior is user-facing, the change is high-risk, or the path limit
would be exceeded, stop and use `/fix-bug` or `/new-feature`.

Apply the shared [Startup boundary](../rules/workflow.md#startup-boundary) before the first workflow
step. It is the canonical activation, resume, isolation, and setup-failure contract.

## Steps

1. Resolve the active host and run `.forge/hooks/lib/workflow-state.sh show` (PowerShell: the `.ps1`
   twin). Resume only the exact matching active workflow. A new quick fix must start from a clean
   `quick-fix/<slug>` branch whose `HEAD` equals a distinct named base branch; activate it with
   `workflow-state.sh activate --host <claude|codex> --workflow quick-fix --task <slug> --base-ref
   <named-base-branch> --phase diagnosis --next-step '<exact next step>'` (or the `.ps1` twin)
   before investigation or tracked mutation. `HEAD`, a raw commit SHA, or the quick-fix branch itself
   is not a valid activation base.
2. State the acceptance check and affected paths. If behavior changes, write and observe a focused
   failing test first; documentation-only corrections use a direct rendered or static check.
3. Make the smallest change. If the work stops satisfying the quick-fix eligibility rules, checkpoint
   the state and restart it as `/fix-bug` or `/new-feature`; do not stretch the quick-fix boundary.
4. Run the focused check directly in the main session. Quick-fix dispatches no `code-spec`,
   `code-quality`, `verify-app`, or `verify-e2e` role and creates no candidate-bound final receipt set.
5. Apply this repository's release policy. In the Forge source repository, every merged change set
   bumps exact `MAJOR.MINOR.PATCH`, records every change in `docs/CHANGELOG.md`, and adds README
   release prose only for material changes. Downstream repositories follow their own policy; never
   invent or rewrite a downstream `.forge/version` as part of application work.
6. Check the complete diff from the recorded base. It must contain no more than three implementation
   paths, plus optional exact `README.md` and `docs/CHANGELOG.md` release metadata. Record the direct
   check result in the workflow checklist and run `workflow-state.sh checkpoint` (or the `.ps1`
   twin) to record the phase as complete.
7. Commit normally after the ship hook accepts the validated base and scope. Show any push, PR, or
   merge mutation and pause for the required human authorization; authorization for one external
   mutation does not imply another.

Forge provides no edit lock. Concurrent sessions are allowed, but overlapping writes must be
coordinated. Any unexpected mutation or base drift invalidates the direct scope check and requires a
fresh inspection before shipping.
