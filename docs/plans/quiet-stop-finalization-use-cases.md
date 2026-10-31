# Quiet Stop and release-history acceptance

Project type: CLI / host-hook integration.
UI QA: N/A — no rendered UI, styling, interaction or UI copy changes.
Surface coverage: public installers and registered Claude/Codex hook commands in disposable
fixtures. Authenticated native Desktop sessions and native Windows 5.1 remain UNVERIFIED.
These use cases qualify the fixture interfaces, not live model behavior or native event delivery.

## UC1: Continue an interactive editing conversation

Actor: developer iterating with Claude Code or Codex.
Scenario: a response answers a question or awaits feedback, leaving workflow state unchanged.
Intent: finish the response without an extra forced turn or a changelog demand.
Interface: registered Stop commands through the repository's disposable host-event test harness.
Setup: Bash, Git, Python and PowerShell are available. The sanctioned harness owns disposable
repository fixtures and creates their initial workflow state before exercising Stop events.
Steps:
1. Run `bash tests/template/test-stop-workflow.sh` (the platform twin is
   `pwsh -NoProfile -File tests/template/test-stop-workflow.ps1`).
2. Inspect stdout and stderr for the repeated active/completed Stop, multi-file, nested-history,
   linked-event routing and independent guard results for both host registrations.
Verification: stdout reports those assertions passing and zero failures, including allowed Stop
output and absence of WORKFLOW/changelog demands. Invalid state and unsupported shipping controls
must report successful rejection assertions; exit status alone is not sufficient evidence.
Persistence: Stop does not create a checkpoint-hash sidecar or change another worktree's state;
Goal accounting remains idempotent. Actual host model conversation remains unverified.

## UC2: Install and update Forge without an extra release history

Actor: developer installing Forge in an existing project.
Scenario: the project has no changelog, a nested application changelog, or multiple owned histories.
Intent: install or upgrade the harness without creating or rewriting customer release history.
Interface: public `setup.sh` and `setup.ps1` install, upgrade and full-refresh commands.
Setup: Bash and PowerShell runtimes are available; the sanctioned fixture harness owns disposable
customer projects with absent, nested-only and root-plus-nested histories before installation.
Steps:
1. Run `bash tests/template/test-changelog-ownership.sh` and
   `pwsh -NoProfile -File tests/template/test-changelog-ownership.ps1`; these exercise the public
   installer for install, upgrade and full refresh on each project layout.
2. Inspect stdout and stderr for each mode's installation and history-preservation assertions.
Verification: stdout reports successful installation/version metadata, no extra root history,
identical hashes for existing root/nested histories including CRLF/Unicode, and zero failures.
An exit code without those observable assertions does not pass this case.
Persistence: assertions recheck each existing customer history after every installer operation.

## UC3: Finalize the complete change set

Actor: main agent following canonical project instructions.
Scenario: implementation, preliminary checks and simplification are complete.
Intent: consolidate the appropriate history once before candidate freeze and merge.
Interface: canonical workflow/state templates and policy regression checks.
Setup: the final candidate and its canonical instruction documents are available for verification.
Steps:
1. Run `bash tests/template/test-contracts.sh`, or consume that exact command's current result
   from the independent final fast gate.
2. Inspect stdout for the named release-history finalization and source release-policy assertions;
   inspect the final review evidence for the single entry and matching version badge.
Verification: stdout reports all named assertions passing and zero failures; final review confirms
the entry/badge match. This is an instruction contract, not a runtime detector of agent compliance.
Persistence: no installer-generated or duplicate customer changelog is introduced.
