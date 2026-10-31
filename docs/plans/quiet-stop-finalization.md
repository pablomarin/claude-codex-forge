# Quiet conversation stops and finalization-only changelogs

## Scope and diagnosis

Base: `main` at `16e01749f0a2902b7a137de3c731614a42fd991d`.
User approved fixing repeated hook feedback and per-message changelog work. Forge has one
canonical release history in its source repository, `docs/CHANGELOG.md`. Customer histories
are customer-owned; installation must not invent a second history or delete an existing one.

The Stop hook compares the current state hash to the previous Stop and exits 2 when unchanged.
A question or a pause for user feedback therefore causes another model turn. Its independent
four-file changelog threshold also runs on every Stop and checks uncommitted changes only at
root `docs/CHANGELOG.md`. Ocean Properties PM edits its nested application changelog, so that
update cannot satisfy the check. Existing tests assert these unwanted behaviors.
Both public setup scripts also create root changelog scaffolding independently of customer layout.

## Minimal change

1. Remove unchanged-state continuation and changelog threshold logic from both Stop hook twins.
   Retain canonical-state validation, Goal accounting/budgets/stuck diagnostics, evidence
   publication, legacy migration advisory and finalization-only evidence advisories. Shipping
   evidence and human authorization remain enforced independently.
2. Put changelog responsibility in canonical finalization policy: consolidate one entry per
   change set after implementation/preliminary checks/simplification and before final candidate
   freeze and merge. Do not write or mention changelogs for questions or intermediate replies.
   Respect the customer's chosen existing history and policy; never require root history or
   duplicate Forge release notes downstream. Keep local progress in state at durable boundaries.
3. Stop installers from creating a customer changelog. Preserve existing changelogs byte-for-byte
   on fresh install, upgrade and refresh. Installed Forge version metadata remains unchanged.
4. Update relevant regression tests, hook documentation and workflow wording, including the
   installed `state.template.md` Update Rules and `rules/critical-rules.md`. Remove instructions
   to add changelog entries per task, move Done progress into root release history, or expect
   Stop reminders. Local progress remains local; release history is finalization-only.
   Register the new Bash changelog-ownership suite in `tests/template/run-all.sh` so CI runs it;
   the PowerShell suite is discovered automatically. Update the pinned suite count in
   `tests/support/check-windows-ci-feedback.py` from 22 to 23 and run its owning check.
   No new configuration,
   changelog detector or merge of customer documents. Existing waiver scope spellings remain
   readable for compatibility, but no obsolete Stop gate should need a waiver.

## Ownership

Runtime producer: `hooks/check-state-updated.{sh,ps1}`, associated Stop/hook/waiver tests.
Installer producer: `setup.{sh,ps1}`, associated setup/worktree tests.
Main: canonical policy/workflows (including `state.template.md` and `rules/critical-rules.md`),
`tests/template/run-all.sh` suite registration, `tests/support/check-windows-ci-feedback.py`
native-discovery count, hook reference, this plan, solution documentation, and final
source release metadata. No changes to Ocean Properties PM in this source fix.

## Acceptance and verification

- RED before implementation: repeated unchanged active workflow Stops must return allow with no
  WORKFLOW reminder in both hosts; four or more changed files without any changelog must not
  interrupt a reply, including a nested app changelog fixture.
- Exercise both host registrations and linked event cwd routing. Canonical invalid state and
  shipping without valid evidence must still block. Native Goal turn accounting stays idempotent.
- Bash and PowerShell tests mirror behavior. Portable PS7 checks do not certify native Windows.
- Fresh setup with no customer changelog creates none; existing root and nested histories survive
  install/upgrade/refresh unchanged. Verify official installer behavior in disposable projects.
- Run focused Stop/hook/setup checks and `tests/template/run-fast.sh`; broad release suites stay CI-owned.
- Independent plan review, producer task reviews, final spec/quality review and app/E2E evidence
  use the canonical dispatcher/receipts. No browser visual audit applies to this shell/policy fix.
- Source native alignment is UNVERIFIED (no installed hooks); physical process/common directory
  check matches the isolated worktree. No native Desktop or Windows runtime claims.

Existing quick-fix path-budget limits remain: a nested customer changelog counts toward the
three implementation paths. The exact root release-metadata exception is unchanged; document
that limit rather than adding a changelog detector in this fix (plan-review P3 advisory).

## User journeys

Actor: developer using Claude or Codex. Scenario: ask for subtitle options, wait, choose text,
then give another small change. Interface: registered Stop hook. Verify every ordinary reply can
finish without changing workflow state or release history merely to silence a hook.
Scenario: finish the batch. Interface: canonical finalization workflow. Verify the chosen project
changelog is consolidated once before freeze/merge and no extra root changelog is introduced.
Scenario: invalid state, active Goal budget, or uncertified shipping. Verify independent guards
retain their existing behavior. Fixtures exercise actual registered commands, not authenticated
native application sessions.
