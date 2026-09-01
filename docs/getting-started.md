# Getting Started

Install once, open either supported host, and work. Forge installs one canonical `.forge/` harness
plus native Claude Code and Codex adapters; it does not ask you to choose a permanent main agent.
The host you are using leads the current action.

For people, the recommended path is [agent-assisted setup](guides/agent-assisted-setup.md): open
Claude Code or Codex in the target repository and paste the canonical setup prompt. The agent
chooses the correct command, but `setup.sh` or `setup.ps1` performs every installation and remains
the source of truth. The commands below remain the direct path for CI, automation, offline use, and
troubleshooting.

## Compatibility

Forge probes capabilities, not just version strings. These are the v6 tested baselines; newer
versions remain usable when they expose the required capabilities.

| Host | Tested baseline | Required v1 capabilities | If present but unsupported |
| ---- | --------------- | ------------------------ | -------------------------- |
| Claude Code | `2.1.237` | Project instructions/rules, commands, hooks, fresh non-persistent CLI runs, workspace sandbox, native `/goal` | Adapters are `MATERIALIZED`, but the affected role is not `RUNTIME_READY`; Forge prints the missing capability and uses a fresh Codex or Claude fallback when possible. |
| Codex CLI | `0.144.1` | Project instructions/rules, skills, hooks, `exec --ephemeral`, sandbox and output capture, native `/goal` | Adapters are `MATERIALIZED`, but the affected role is not `RUNTIME_READY`; Forge prints the missing flag/trust requirement and falls back without stopping when another qualified path exists. |

Also required: Git 2.23+ and one authenticated host. Python 3 is required for authoritative full
refresh. Windows uses PowerShell 5.1+; WSL2 remains the recommended Codex environment.

`MATERIALIZED` means files were installed. `RUNTIME_READY` means that host's discovery, trust, and
required runtime capabilities were actually qualified. Never treat the first status as the second.

## 1. Clone Forge

macOS / Linux:

```bash
git clone https://github.com/pablomarin/claude-codex-forge.git ~/claude-codex-forge
chmod +x ~/claude-codex-forge/setup.sh
```

Windows PowerShell:

```powershell
git clone https://github.com/pablomarin/claude-codex-forge.git $HOME\claude-codex-forge
```

## 2. Choose the project installation path

The project command depends on what is already in the repository:

| Repository state | Next command |
| --- | --- |
| Fresh repository with no agent harness | Continue to the normal project installation below |
| Existing Forge v6 | Use the managed-refresh command in the [README setup table](../README.md#setup-refresh-and-team-upgrades); full refresh is not required |
| Forge v5, Claude-only, Codex-only, mixed, or another/custom harness | `setup.sh -F --dry-run` or `setup.ps1 -FullRefresh -DryRun` |
| Unknown | Run the same full-refresh preview; it is read-only |

Never use normal fresh setup to layer v6 over an existing harness. A full-refresh preview inventories
ownership, root instructions, state, settings, and hooks. Resolve its blockers and execute the same
command without the dry-run flag only after `UPGRADE: READY`.

## 3. Install the global harness

```bash
~/claude-codex-forge/setup.sh --global
```

```powershell
& $HOME\claude-codex-forge\setup.ps1 -Global
```

Global and project scopes are separate. Installing global first is the clearest path, but a project
install may come first; a later `--global` / `-Global` recognizes the advisory machine stamp and
materializes the global harness normally. A project refresh never rewrites global policy.

## 4A. Install a fresh project

From the Git repository root:

```bash
~/claude-codex-forge/setup.sh -p "My Project"
```

```powershell
& $HOME\claude-codex-forge\setup.ps1 -Project "My Project"
```

Both adapters are installed even when only one CLI is available. If this repository already has any
agent harness, use the [authoritative full-refresh path](guides/upgrading.md) instead.

## 4B. Upgrade a repository with any existing harness

This path covers Forge v5, a repository with only `.claude/` or `CLAUDE.md`, a repository with only
Codex/`AGENTS.md` surfaces, a mixture of both, and independently developed agent harnesses:

```bash
~/claude-codex-forge/setup.sh -F --dry-run
# Resolve every named blocker. When the preview says UPGRADE: READY:
~/claude-codex-forge/setup.sh -F
```

```powershell
& $HOME\claude-codex-forge\setup.ps1 -FullRefresh -DryRun
# Resolve every named blocker. When the preview says UPGRADE: READY:
& $HOME\claude-codex-forge\setup.ps1 -FullRefresh
```

The preview writes nothing. The migration proves ownership before replacing or deleting legacy
files, preserves unknown project content, and blocks rather than guessing when instructions or
state are ambiguous. See [Upgrading](guides/upgrading.md) for report meanings and reconciliation.

## 5. Open either host

```bash
claude
# or
codex
```

Claude Code uses `/opinion`; Codex uses `$opinion`. With both engines ready, review defaults to the
other engine. If it is absent, unauthenticated, too old, or missing a role capability, Forge reports
the reason and tries a fresh same-engine reviewer. Council fallback reruns the whole topology on the
current host so a discarded mixed attempt is never certified.

For investigation, Claude Code uses `/opinion investigate`; Codex uses `$opinion investigate`.
Forge starts a fresh full agent in the real worktree with the selected host's normal configuration,
state, memory, tools, MCP, network, database/API access, and write capability. Investigation adds no
special Forge sandbox or allowlist; destructive and protected external mutations still use the
same host prompts and explicit human authority as ordinary engineering work.

## 6. Verify installation and trust

Run the deterministic discovery check from the project root:

```bash
~/claude-codex-forge/scripts/verify-runtime.sh discovery --project-root "$(pwd -P)"
```

```powershell
& $HOME\claude-codex-forge\scripts\verify-runtime.ps1 discovery -ProjectRoot (Get-Location).Path
```

Then open each installed host and accept its normal project-trust prompt. Codex hook registration
belongs to the primary checkout; a linked worktree prints the exact primary-checkout setup command
instead of mutating shared Git metadata from the side. Until authenticated discovery and the hook
sentinel are observed, setup truthfully reports `RUNTIME_READY: BLOCKED`.

## Shared project instructions after setup

Forge policy belongs to `.forge/`. Team-owned project context belongs in one neutral file such as
`docs/agent-context.md`. When that context is needed, create the file and put this same line outside
the Forge-managed block in both `CLAUDE.md` and `AGENTS.md`:

```markdown
Read `docs/agent-context.md` completely before acting.
```

Forge does not generate your architecture or domain knowledge. Maintain it once in
`docs/agent-context.md`; do not synchronize duplicate copies between the native root files.

## Next

- [Setup scenarios](guides/setup-scenarios.md)
- [Parallel and cross-host sessions](guides/parallel-sessions.md)
- [Commands](reference/commands.md)
- [Troubleshooting](troubleshooting.md)
