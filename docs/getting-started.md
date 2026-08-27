# Getting Started

Install once, open either supported host, and work. Forge installs one canonical `.forge/` harness
plus native Claude Code and Codex adapters; it does not ask you to choose a permanent main agent.
The host you are using leads the current action.

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

## 2. Install the global harness

```bash
~/claude-codex-forge/setup.sh --global
```

```powershell
& $HOME\claude-codex-forge\setup.ps1 -Global
```

Global and project scopes are separate. A project refresh never rewrites the global harness.

## 3. Install a fresh project

From the Git repository root:

```bash
~/claude-codex-forge/setup.sh -p "My Project"
```

```powershell
& $HOME\claude-codex-forge\setup.ps1 -Project "My Project"
```

Both adapters are installed even when only one CLI is available. If this repository already has a
v5 harness, use the [authoritative full-refresh path](guides/upgrading.md) instead.

## 4. Open either host

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
Expanded network/query/write capability is explicit and confined to the disposable investigator.

## 5. Verify installation and trust

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

## Existing project

Pull the Forge clone and run the breaking v6 refresh:

```bash
git -C ~/claude-codex-forge pull
cd /path/to/project
~/claude-codex-forge/setup.sh -F
```

```powershell
git -C $HOME\claude-codex-forge pull
Set-Location C:\path\to\project
& $HOME\claude-codex-forge\setup.ps1 -FullRefresh # -R is equivalent
```

See [Upgrading](guides/upgrading.md) before resolving any `BLOCKED` report.

## Next

- [Setup scenarios](guides/setup-scenarios.md)
- [Parallel and cross-host sessions](guides/parallel-sessions.md)
- [Commands](reference/commands.md)
- [Troubleshooting](troubleshooting.md)
