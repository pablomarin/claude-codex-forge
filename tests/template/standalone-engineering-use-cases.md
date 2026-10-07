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

## UC3: Early native suite result with complete qualification

Actor: Forge maintainer validating a PowerShell change before merging its pull request.
Scenario: A long serial native run previously hid an early failed suite until all other
suites finished. The maintainer needs an isolated result promptly and a final answer
which still requires every discovered suite.
Interface: CLI and GitHub Actions.
Intent: See which suite failed and retain evidence without accepting incomplete coverage.
Setup: Disposable Git checkout containing independently authored passing/failing suite
programs; the real runner and aggregate validator, with result directories outside it.
Steps:
1. Invoke run-all.ps1 -ListSuites, then invoke exact -SuiteName/-ResultPath selections
   in isolated checkouts of the same commit. Read each persisted result and suite log.
2. Invoke validate-windows-suite-results.ps1 with the discovery list and dependency
   status, then repeat validation against the retained files.
Verification: Stdout and persisted results identify the selected suite, actual exit,
 elapsed time and candidate before/after state. The failed suite's exit is retained;
 missing, duplicate, failed, wrong-candidate, nonnative or dirty results explain rejection.
 Native GitHub jobs run independently with fail-fast disabled, and the final native
 attestation is reached only after complete successful coverage of the exact checkout.
Persistence: Reinvoke validation against the same artifacts; a prior failure cannot become
 passing because another suite succeeded or its result disappeared.
Qualification limit: Local PS7 runs prove CLI contracts and rejection of portable results.
 Independently authored synthetic5.1 wire controls prove validator semantics; they never
 establish Windows execution. Native job scheduling and attestation require actual CI.

## Surface coverage decision

CLI: Both journeys exercise the real installers and installed CLIs.
UI/API: N/A — this change exposes installer/configuration commands, not a browser or HTTP service.
Native agent pressure behavior: Unverified unless an authenticated operator-supplied runner
executes the separate scenarios in the research report; schema fixtures are insufficient.
