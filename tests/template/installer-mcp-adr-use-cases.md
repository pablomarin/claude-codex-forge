# Installer MCP reuse and ADR preservation journeys

Project type: CLI. Run on disposable projects via Bash and portable PS7, with both
Claude and Codex recorded as main through the installed workflow-state CLI. Editing
project configuration and ADR files is the documented operator interface. File checks
observe the installer outputs; they do not certify MCP startup, authentication or Windows5.1.

## UC1: Keep chosen MCP integrations through setup and repeated upgrade

Actor: Repository maintainer who already configured Context7 and Playwright for Codex.
Scenario: The maintainer installs or upgrades Forge and wants existing hosted Context7
and customized Playwright choices retained without launching redundant registrations.
Interface: CLI and project configuration files.
Intent: Keep one registration for each chosen integration while updating Forge.
Setup: Disposable Git repository and isolated home, with existing operator-authored
Codex entries, application file and later a project preference; no generated outcomes.
Steps:
1. Run the real setup installer; inspect generated configuration and displayed release.
2. Activate a task with the installed workflow-state CLI and retain a preference in settings.
3. Arrange the previously released duplicate managed block, run upgrade twice, full-refresh
   preview, full refresh, then upgrade again. Reinvoke the workflow-state CLI.
Verification: Stdout reports upgrade readiness; output configuration preserves exact outside
choices, hosted URL/token-variable name and Playwright arguments. It contains no Forge
fallback registration for either known server. Application, preference and task remain.
Persistence: Repeated upgrade/full refresh retains the same normalized configuration and
workflow bytes; preview leaves the configuration unchanged.

## UC2: Retain a reusable ADR template during migration

Actor: Repository maintainer upgrading a v5 project with an ADR index and reusable template.
Scenario: The maintainer needs current Forge while keeping project decision documents
usable; the project index references the reusable template.
Interface: CLI and project documentation files.
Intent: Upgrade the harness without losing the template used for future project decisions.
Setup: Disposable recognized5.61 project with byte-exact historical template or an
operator-customized template, a customized index and an exact old internal numbered ADR.
Steps:
1. Run real full-refresh preview and inspect its migration report and existing files.
2. Apply full refresh, then routine upgrade and a second full refresh.
Verification: Stdout distinguishes preservation from retirement. The template and customized
index retain their bytes and the index link resolves, while the exact obsolete internal ADR
is retired. The maintainer can still use the template for the next project decision.
Persistence: A subsequent installer invocation retains the same template/index bytes and
does not restore the obsolete internal ADR.

## Surface coverage decision

CLI/configuration/document files: Covered by both journeys on Bash and portable PS7,
with both recorded mains. UI/API: N/A — this capability reconciles local repository files
through installation commands, and provides no browser or HTTP product surface.
Native Windows5.1 and live MCP connectivity/authentication: Not certified by portable runs;
future native CI and actual host startup are distinct evidence boundaries.

Owning deterministic regressions: test-merge-settings.sh/check-codex-mcp-reuse.py and
test-full-refresh.sh/test-full-refresh.ps1 exercise the production renderers and refresh
entrypoints. Installed journey execution records are kept as local evidence.
