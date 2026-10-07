# Standalone Forge installation journeys

Project type: CLI. Execute the same journeys with Bash and portable PowerShell, recording
both Claude and Codex as the active main through the installed state CLI. Discovery/file
checks certify materialization, not authenticated agent behavior or native Windows.

## UC1: Fresh setup and preserved workflow across updates

Actor: Repository operator equipping a project for Claude Code and Codex.
Scenario: A fresh Git repository has no agent harness. The operator wants Forge's canonical
engineering practices without enabling an overlapping plugin, and needs updates to retain work.
Interface: CLI.
Intent: Install one Forge workflow owner and keep explicit project choices through updates.
Setup: Disposable Git repository and isolated home, created through Git; no injected harness.
Steps:
1. Run the real setup command. Observe its banner and run installed discovery.
2. Choose disabled overlap entries plus an unrelated plugin and preference in project settings;
   activate a task using the installed canonical workflow-state CLI.
3. Run routine upgrade twice, full-refresh preview and full refresh. Reinvoke discovery/state.
Verification: Stdout describes canonical Forge capabilities, discovery reports the expected
release and zero duplicate rules, and project settings contain no automatically enabled overlap.
Updates preserve the operator's explicit plugin choices and preference; state output retains
the task, main host, immutable base and next step. Both root adapters find canonical instructions.
Persistence: Repeat upgrade/discovery and compare retained settings and state after reconciliation.

## UC2: Retained enabled overlap is explained rather than deleted

Actor: Repository operator who deliberately retains an external frontend plugin.
Scenario: The operator enables frontend-design in the installed project's settings and
requests reconciliation, expecting Forge to preserve the choice and explain its readiness effect.
Interface: CLI.
Intent: Keep a chosen integration while understanding whether the host is ready.
Setup: UC1's installed disposable project and operator-owned settings; no fabricated receipts.
Steps:
1. Enable the plugin in project settings and run the real full-refresh command.
2. Read the readiness report, then reinvoke discovery and inspect retained settings/state.
Verification: Stdout reports PRESERVED_COMPAT_BLOCKED and Claude RUNTIME_READY: BLOCKED;
the explicit enabled choice, unrelated plugin/preference and workflow state remain intact.
Persistence: A subsequent discovery invocation still finds one canonical rule set and
retained settings still record the explicit enabled choice. Discovery is not readiness proof.

## Surface coverage decision

CLI: Both journeys exercise the real installers and installed CLIs.
UI/API: N/A — this change exposes installer/configuration commands, not a browser or HTTP service.
Native agent pressure behavior: Unverified unless an authenticated operator-supplied runner
executes the separate scenarios in the research report; schema fixtures are insufficient.
