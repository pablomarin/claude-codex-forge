# Connected development and bounded documentation certification

Approved scope: the developer approved the two-part solution in this conversation on 2026-10-22.
Work only in `fix/developer-feedback`, physical worktree `.worktrees/developer-feedback`.
Immutable base: `main`, `899e000139734ec56098ed2e6b3b944b5a218f6a`.
Do not edit the harness-choice worktree, merge the Windows PR, publish, or change global settings.

## Reproduction and cause

- Claude templates force an enabled, fail-closed main shell sandbox with unsandboxed retries disabled.
  Worktrees inherit project settings. Proxy networking cannot cover Docker or arbitrary integration
  scripts using native database drivers. Native Desktop additionally reads project configuration
  from the main checkout and may lack terminal-exported environment variables.
- Python merges only selected settings sections and ignores sandbox upgrades; PowerShell's generic
  merge overwrites owned scalars. A template-only change cannot safely repair installed projects.
- Final receipt validation binds all four receipts to complete candidate/head/tree identity.
  `state.template.md` explicitly requires all four again on every mutation.
- Stop validates final evidence during implementation, producing premature stale warnings.

## Minimal implementation

1. Remove main-shell sandbox defaults from both Claude settings templates. Preserve native host,
   user and organization policy and all existing permission/consequential-action guards. Keep the
   ordinary reviewer isolated and unchanged. Leave the working Codex configuration out of scope.
2. Add explicit `setup.sh --connected-development` and PowerShell `-ConnectedDevelopment` options.
   The selected option merges only `sandbox.enabled=false` into project-local Claude settings in
   the checkouts covered by existing installer fanout. Preserve every unrelated local setting.
   Normal upgrades preserve existing sandbox choices and explain a retained restriction. Do not
   claim identical boolean values prove Forge ownership; no automatic removal of ambiguous policy.
3. Make Stop's final-evidence advisory apply only in explicit finalization phases (review, verify,
   verification, finalization/finalize, promotion/promote, shipping/ship). Diagnosis, planning,
   implementation, repair and preliminary E2E preserve progress without final receipt warnings.
   Keep Goal accounting, state validation, continuation and actual ship enforcement unchanged.
4. Add `verification-receipt close-docs --state PATH --previous-candidate PATH` and the PS twin.
   The caller saves original certified candidate A, then freezes updated staged-clean candidate B
   at the active candidate path. Existing spec/quality/app/E2E receipts continue to name A.
   Validate the original complete passing receipt set against A, its age and immutable report
   hashes. Validate B's real current identity. Permit the same source HEAD, or A's already-proved
   exact Forge promotion; no arbitrary commits, upstream merges/rebases or base changes.
5. Compare A's frozen tree to B's. Require an unchanged tracked regular 100644 policy at
   `.forge/verification-scope.tsv`, header `# forge:non-runtime-prose v1`, exact `prose<TAB>path`
   declarations, no globs. Source dogfood may use `manifests/verification-scope.tsv` only when the
   canonical source markers exist and no installed policy exists. Initially enroll only this
   source repository's `docs/CHANGELOG.md`, guarding the machine-consumed release heading.
   Reject additions/deletions, binary, symlink, executable/mode, rename and unknown changes.
   Explicitly reject instruction/policy/plan/requirements/configuration paths and MDX even if
   enrolled. Negative fixtures mutate only the enrolled forbidden path, so a broken deny rule
   cannot pass accidentally because an unrelated, unlisted prose file also changed.
   Missing or modified scope policy blocks reuse; projects enroll paths before certification.
6. Run the focused docs check (`git diff --check` on the exact tree delta plus protected release
   metadata checks). Write `<active candidate path>.docs-closure` recording A/B identities,
   original receipt hashes, policy/delta hashes and fresh docs check result. Preserve A in a
   Forge-local regular file. Never relabel receipts, renew their timestamps, increment paired
   review iteration or reset first certification. A second correction recomputes original A to
   newest B, not a transitive chain. Preserve source promotion provenance before target promotion.
7. Extend the existing single validator used by Stop/build-evidence/ship/promotion to accept this
   explicit closure only after recomputation. It still requires exact B current/promoted identity,
   validates original evidence against A, and rejects stale/tampered/mixed evidence and dirty bytes.
   Partial publication fails closed. No generic dependency mapper or runtime-only fingerprint.
8. Update canonical workflow/state instructions and user guides with this exception and connected
   setup. Functional repairs still use fresh receipts and bounded delta/named-finding closure review.
   Prepare one patch release, 6.4.12, changelog, README badge and appropriate version contracts.

## Ownership

- Producer access: settings templates, setup twins, settings merger/materializers and focused tests.
- Producer receipts: verification-receipt twins, minimal classifier helpers if necessary, focused
  docs-closure suites and source scope policy.
- Producer Stop: Stop twins and owning Stop test expectations.
- Main agent: plan/review, policy/docs/release, integration and final verification.
Native registered producer type/UUID is not exposed by this host; preserve actual collaboration
task identities and self-review reports, never invent native task receipts. Configured paired
review and executable verification remain independent final requirements.

## RED/GREEN and acceptance

- First demonstrate old fresh settings enforce sandbox; connected opt-in is unsupported and
  existing local settings must be preserved. Then prove fresh/upgrade/fanout behavior in both twins.
- Registered Stop tests with both recorded mains: implementation does not warn; final review warns;
  missing receipts still block actual shipping and Goal/continuation behavior remains intact.
- Actual helper fixture: certify A once, alter enrolled changelog narrative, freeze B, close docs,
  check and promote B successfully with zero additional reviewer/app/E2E invocations. Cover a
  correction after original exact promotion and a second correction against original A.
- Negative controls: code/config/instruction Markdown, changed first release heading or scope,
  unknown path, rename/mode/symlink/binary, unstaged/untracked, source mismatch, stale/missing/tampered
  original receipts/report, other worktree, arbitrary HEAD/base movement. No renewed evidence age.
- Run focused owning Bash and portable PS7 suites, then ordinary `tests/template/run-fast.sh`.
  Register the new Bash docs-closure suite in fast and broad runners; Windows discovers its
  PS twin automatically. Update the existing native-discovery count contract to 19 suites.
  Do not run exhaustive local aggregates. Native Windows 5.1 remains CI-owned.
- Installed disposable journeys exercise both mains and visible fallback with engine fixtures;
  distinguish them from authenticated vendor evidence. Attempt available live host boundaries
  without claiming Desktop UI, Docker, database or Windows success unless actually exercised.

## Review and completion

Run one configured plan review before production implementation; the developer already approved
the proposed scope. Run distinct configured code-spec/code-quality reviews over the final frozen
candidate, focused fast verification and feature E2E; preserve truthful candidate receipts.
Shipping/publication requires exact-scope approval beyond this implementation approval. Leave a
reviewable local change and report remaining native/environment boundaries honestly.
