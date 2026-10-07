# Automatic worktree setup: CLI journeys

## Surface coverage decision

- CLI: Covered through the real Bash and PowerShell installers and installed commands.
- UI/API: N/A — this installer and command harness exposes no browser or HTTP interface.
- Deterministic transport fixtures verify routing; they do not certify authentication or native Windows.

## UC1 — Install once and retain active work

Actor: Repository operator working in Claude or Codex with several Git worktrees.
Scenario: A primary checkout and two linked checkouts need the same Forge release while feature work is active.
Intent: Install and upgrade the repository with one command while keeping existing work.
Interface: CLI.
Setup: Use Git to create a disposable primary and two links, including spaces/Unicode paths; add ordinary project edits and instructions.
Steps:
1. Run setup from a link with project, tech and Playwright options; inspect every reported checkout.
2. Activate a workflow with the installed helper, customize user settings/scaffolds and make a managed hook stale; run normal setup and then upgrade from a link.
3. Reinvoke installed discovery and workflow-state show; inspect the project diff and Git branch/HEAD identities.
Verification: stdout shows primary-first results and every checkout's exact release. Installed managed files match that release; project instructions, customized scaffolds/settings, workflow state, application edits and branch/HEAD identities survive.
Persistence: Repeat setup/upgrade and invoke discovery and workflow-state show again.

## UC2 — Preview, narrow scope and understand partial failure

Actor: Repository operator performing maintenance while sibling branches remain active.
Scenario: The operator needs a read-only preview or one-checkout update, then encounters an unsupported sibling.
Intent: Control maintenance scope and see which checkouts succeeded or stayed blocked.
Interface: CLI.
Setup: Use an installed disposable repository with three checkouts and ordinary user-owned files.
Steps:
1. Run force preview from a link and compare checkout/Git metadata snapshots.
2. Run the checkout-only option while a sibling has a stale managed hook; inspect the untouched sibling.
3. Add a custom/legacy harness to a sibling, run repository setup and inspect successful and blocked results.
4. Invoke setup from a project subdirectory and inspect its refusal.
Verification: stdout shows preview results with no changed bytes, or identifies each materialized/blocked checkout. A blocked sibling stays untouched and the overall exit fails; stderr explains subdirectory refusal before sibling writes.
Persistence: Repeat preview/refusal and compare snapshots again.

## UC3 — Continue collaboration with either main engine

Actor: Repository operator handing installed work between Claude and Codex.
Scenario: Setup has updated the checkouts; the operator needs reviewers, opinions and council to retain their existing routing.
Intent: Continue cross-engine collaboration after installation.
Interface: CLI.
Setup: Use a fresh installed disposable checkout and existing deterministic transport fixtures; activate workflow state through the installed helper.
Steps:
1. Launch review/opinion with each main host and inspect the selected other engine.
2. Fail the preferred engine and observe visible fresh same-engine fallback in each direction.
3. Execute installed council with each main host; inspect mixed seat/chair routing and exact fixture-session continuation.
Verification: stdout/stderr and receipts show the correct main, reviewer, fallback, mixed council engines and session continuity. Fixture routing is explicitly distinguished from authenticated host readiness.
Persistence: Repeat healthy routing and inspect receipt/state consistency.

Executable specs: `tests/template/test-setup-worktrees.sh` and its PowerShell twin cover installation, preservation, scope and failure cases. Existing dual-engine/council seams cover unchanged collaboration contracts.
