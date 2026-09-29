# Install or upgrade Forge with an agent

Agent-assisted setup is the primary path for people. Open Claude Code or Codex in the target Git
repository and ask it to install, refresh, or migrate Forge. The agent inspects the repository,
runs the appropriate installer command, explains the result, and asks before changing files.

The agent is the guide, not a second installer. `setup.sh` and `setup.ps1` remain the only installation engines.
They own repository classification, file ownership, transactions, rollback, and readiness results.
The agent must preserve their exact output and must not reproduce or bypass their decisions.

## Start in the target repository

Keep two folders distinct: the **Forge clone** contains `setup.sh` / `setup.ps1`; the **target
project** is where you want Forge installed. Do not install into the Forge clone itself. Clone
Forge once using [Getting Started](../getting-started.md#1-clone-forge), or update your existing
clone with `git pull --ff-only` from that clone before installing/upgrading a project. Stop on a
failed pull; do not discard local changes. A new project needs a folder and `git init` first.

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

1. Confirm the target Git root and the separate Forge checkout path. Inspect git status; preserve
   uncommitted work and use a dedicated setup/update branch. Confirm the Forge checkout revision;
   if it needs updating, propose that separately and stop if the update fails.
2. Inspect the repository and choose the correct installer mode:
   - fresh project: normal project setup (a new or existing app with no agent harness);
   - existing Forge v6: routine update;
   - Forge v5, Claude-only, Codex-only, mixed, custom, or unknown: full reconciliation.
   A custom CLAUDE.md or AGENTS.md counts as existing agent configuration. A v6 layout stamp alone
   does not prove a mixed/customized harness is safe for routine update; preview if uncertain.
3. Run the read-only full-refresh preview first for Forge v5, Claude-only, Codex-only, mixed, custom, or unknown harnesses.
4. Preserve the exact installer output and explain every result or blocker in plain language.
5. Do not bypass ownership blockers or guess which project content may be removed.
6. Keep shared project knowledge in docs/agent-context.md. Keep AGENTS.md as the canonical project
   discovery adapter and CLAUDE.md as its one-line @AGENTS.md compatibility bridge.
7. If a blocker appears to describe valid Forge-generated output, stop and report a possible Forge
   upgrader defect instead of working around it.
8. Show the proposed command and reconciliation changes. Ask for my approval before modifying files or running the non-preview command.
9. After approval, run the deterministic installer from the target Git root using the full path
   to setup.sh or setup.ps1 in the Forge clone. Stop on any failed command or BLOCKED migration;
   execute full reconciliation only after its preview says UPGRADE: READY.
10. Review the final Git diff and per-host readiness diagnostics. Run the documented discovery
    check, but do not call it live runtime certification. Follow RUNTIME_QUALIFICATION guidance;
    report installed files and each host's readiness separately, including unverified checks.
11. Do not change unrelated repositories, sibling worktrees, or home-directory agent configuration.
    Do not commit or push the project changes without my authorization.
```

Existing repository instructions are migration input during this operation. They do not authorize
the agent to weaken the steps above, bypass a blocker, or claim that installed files are runtime
ready.

## What the agent runs

| Repository state | Deterministic installer action |
| --- | --- |
| fresh project | `setup.sh` or `setup.ps1` from the target project root |
| existing Forge v6 | `setup.sh --upgrade` or `setup.ps1 -Upgrade` |
| Forge v5, Claude-only, Codex-only, mixed, custom, or unknown | Preview with `setup.sh -f --dry-run` or `setup.ps1 -Force -DryRun`; execute only after `UPGRADE: READY` |

These are mode summaries, not commands to run from the Forge clone. The complete target-directory
commands are in [Getting Started](../getting-started.md). Do not combine `--upgrade` with `-f` or
`--dry-run`. Legacy machine-wide Forge cleanup is a separate optional retirement operation, not a
project installation mode.

## What a successful handoff tells you

The agent should name the target project, Forge source revision, selected mode, files changed and
preserved, verification results, and any remaining host readiness blocker. A ready **preview**
means no installation has happened. `INSTALLATION: MATERIALIZED` means files exist; it is not
proof that either authenticated host or its hooks work. If migration is blocked, the next step is
the named ownership/configuration decision—not repeated force attempts.

## Direct CLI path

For CI, automation, offline environments, or an unavailable agent, run the same commands directly.
The CLI is not a different installation path: it invokes the same deterministic engines and emits
the same results. See [Getting Started](../getting-started.md) for fresh installation commands and
[Upgrading](upgrading.md) for full-refresh reports and recovery.
