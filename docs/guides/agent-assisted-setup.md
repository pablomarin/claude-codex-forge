# Install or upgrade Forge with an agent

Agent-assisted setup is the primary path for people. Open Claude Code or Codex in the target Git
repository and ask it to install, refresh, or migrate Forge. The agent inspects the repository,
runs the appropriate installer command, explains the result, and asks before changing files.

The agent is the guide, not a second installer. `setup.sh` and `setup.ps1` remain the only installation engines.
They own repository classification, file ownership, transactions, rollback, and readiness results.
The agent must preserve their exact output and must not reproduce or bypass their decisions.

## Start in the target repository

macOS or Linux:

```bash
cd /path/to/project
claude
# or: codex
```

Windows PowerShell:

```powershell
Set-Location C:\path\to\project
claude
# or: codex
```

Then paste this prompt, replacing the Forge checkout path:

```text
Install or upgrade Forge in this repository using the Forge checkout at <path-to-forge>.

1. Inspect the repository and choose the correct installer mode:
   - fresh project: normal project setup;
   - existing Forge v6: routine update;
   - Forge v5, Claude-only, Codex-only, mixed, custom, or unknown: full reconciliation.
2. Run the read-only full-refresh preview first for Forge v5, Claude-only, Codex-only, mixed, custom, or unknown harnesses.
3. Preserve the exact installer output and explain every result or blocker in plain language.
4. Do not bypass ownership blockers or guess which project content may be removed.
5. Keep shared project knowledge in docs/agent-context.md and keep CLAUDE.md and AGENTS.md as thin
   native discovery adapters.
6. If a blocker appears to describe valid Forge-generated output, stop and report a possible Forge
   upgrader defect instead of working around it.
7. Show the proposed command and reconciliation changes. Ask for my approval before modifying files or running the non-preview command.
8. After approval, run the deterministic installer. Review the final Git diff and per-host readiness diagnostics.
```

Existing repository instructions are migration input during this operation. They do not authorize
the agent to weaken the steps above, bypass a blocker, or claim that installed files are runtime
ready.

## What the agent runs

| Repository state | Deterministic installer action |
| --- | --- |
| fresh project | `setup.sh -p "My Project"` or `setup.ps1 -Project "My Project"` |
| existing Forge v6 | `setup.sh --upgrade` or `setup.ps1 -Upgrade` |
| Forge v5, Claude-only, Codex-only, mixed, custom, or unknown | Preview with `setup.sh -f --dry-run` or `setup.ps1 -Force -DryRun`; execute only after `UPGRADE: READY` |
| global harness | `setup.sh --global` or `setup.ps1 -Global`; approve home-directory changes separately |

## Direct CLI path

For CI, automation, offline environments, or an unavailable agent, run the same commands directly.
The CLI is not a different installation path: it invokes the same deterministic engines and emits
the same results. See [Getting Started](../getting-started.md) for fresh installation commands and
[Upgrading](upgrading.md) for full-refresh reports and recovery.
