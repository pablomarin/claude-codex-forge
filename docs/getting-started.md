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

Also required: Git 2.23+ and one authenticated host. On macOS/Linux, Python 3 (`python3` on PATH)
is required before first setup or any upgrade, including ordinary configuration merging and
validation. Windows uses PowerShell 5.1+ and needs Python 3 for authoritative full refresh;
WSL2 remains the recommended Codex environment.

`MATERIALIZED` means files were installed. `RUNTIME_READY` means that host's discovery, trust, and
required runtime capabilities were actually qualified. Never treat the first status as the second.

## 1. Clone Forge

The Forge clone supplies the installer; your project is a **different directory**. The commands
below assume this clone location. If you already have the clone, do not clone over it: update it
with `git -C ~/claude-codex-forge pull --ff-only` (PowerShell:
`git -C $HOME\claude-codex-forge pull --ff-only`). Stop if Git reports an error.

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
| First installation in a new or existing app with no agent harness | [4A: First installation](#4a-install-forge-for-the-first-time) |
| Existing Forge v6 | [4B: Routine update](#4b-update-an-existing-forge-v6-project); full reconciliation is not required |
| Forge v5, Claude-only, Codex-only, mixed, or another/custom harness | `setup.sh -f --dry-run` or `setup.ps1 -Force -DryRun` |
| Unknown | Run the same full-refresh preview; it is read-only |

Never use normal fresh setup to layer v6 over an existing harness. A full-refresh preview inventories
ownership, root instructions, state, settings, and hooks. Resolve its blockers and execute the same
command without the dry-run flag only after `UPGRADE: READY`.

“No agent harness” means no existing agent instruction/configuration surfaces such as `CLAUDE.md`,
`AGENTS.md`, `.claude/`, `.codex/`, or custom agent workflows. An established application can still
be a first installation. If you cannot classify the setup, or managed Forge files were customized,
choose [4C](#4c-migrate-older-custom-or-unknown-harnesses). A `.forge/version` value of `6` identifies
the v6 layout family, not the exact installed release or proof that a mixed setup is safe.

For all project paths: work from the target project's Git root, save existing changes in a commit
or backup, use a dedicated setup/update branch, and stop other sessions editing those files.
Do not run project setup in the Forge clone. Run each command separately and stop on an error.

## 3. Install the global harness

Global setup changes your home-directory agent configuration, not your project. The commands below
are for the first global installation with no existing harness. If global agent configuration
already exists or you are unsure, use the separate
[global preview and reconciliation](guides/upgrading.md#project-and-global-scopes) first; do not
silently replace it. A confirmed global v6 install can use `--global --upgrade` / `-Global -Upgrade`.

```bash
~/claude-codex-forge/setup.sh --global
```

```powershell
& $HOME\claude-codex-forge\setup.ps1 -Global
```

Global and project scopes are separate. Installing global first is the clearest path, but a project
install may come first; a later `--global` / `-Global` recognizes the advisory machine stamp and
materializes the global harness normally. A project refresh never rewrites global policy.

## 4A. Install Forge for the first time

Use this only for a project with **no agent harness**, whether the app is new or established.
Create the project folder first if needed; if it is not yet a Git repository, run `git init` there.

```bash
cd /path/to/your/project
~/claude-codex-forge/setup.sh -p "My Project"
```

```powershell
Set-Location C:\path\to\your-project
& $HOME\claude-codex-forge\setup.ps1 -Project "My Project"
```

Both adapters are installed even when only one CLI is available. Continue to step 5; do not run
4B or 4C as extra installation steps.

## 4B. Update an existing Forge v6 project

Use this for the second and later installs into a confirmed v6 project. First update the **Forge
clone**, then update the **project**:

```bash
git -C ~/claude-codex-forge pull --ff-only
cd /path/to/your/project
~/claude-codex-forge/setup.sh --upgrade
```

```powershell
git -C $HOME\claude-codex-forge pull --ff-only
Set-Location C:\path\to\your-project
& $HOME\claude-codex-forge\setup.ps1 -Upgrade
```

Pulling the clone alone does not update the project. `--upgrade` refreshes managed files while
preserving project-owned configuration; keep shared project knowledge outside managed Forge files.
Do not add `--dry-run` to `--upgrade`: dry-run is supported only with full reconciliation (`-f`).
If setup blocks or the project is mixed/customized, stop and use the preview in 4C. Otherwise
continue to step 5.

## 4C. Migrate older, custom, or unknown harnesses

This path covers Forge v5, a repository with only `.claude/` or `CLAUDE.md`, a repository with only
Codex/`AGENTS.md` surfaces, a mixture of both, and independently developed agent harnesses:

```bash
cd /path/to/your/project
~/claude-codex-forge/setup.sh -f --dry-run
# Resolve every named blocker. When the preview says UPGRADE: READY:
~/claude-codex-forge/setup.sh -f
```

```powershell
Set-Location C:\path\to\your-project
& $HOME\claude-codex-forge\setup.ps1 -Force -DryRun
# Resolve every named blocker. When the preview says UPGRADE: READY:
& $HOME\claude-codex-forge\setup.ps1 -Force
```

The preview writes nothing. The migration proves ownership before replacing or deleting legacy
files, preserves unknown project content, and blocks rather than guessing when instructions or
state are ambiguous. See [Upgrading](guides/upgrading.md) for report meanings and reconciliation.

**If blocked, stop here.** Preserve the report. Review each proposed reconciliation before changing
anything; back up custom instructions, hooks, skills, and state. Choose whether to retain the
custom harness or adopt Forge—never delete files just to make the preview green. Rerun the preview
after approved changes. `-f` is the transaction mode, not permission to bypass a blocker.

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

Successful discovery exits zero and reports `duplicate_rule_count=0`; it checks filesystem
discovery, not authentication, live hook execution, or reviewer access. Follow the installer's
`RUNTIME_QUALIFICATION` guidance for those checks; see
[runtime qualification](qualification/agent-mode-selection.md).

Then open each host you intend to use and accept its normal project-trust prompt. Codex hook registration
belongs to the primary checkout; a linked worktree prints the exact primary-checkout setup command
instead of mutating shared Git metadata from the side. Until authenticated discovery and the hook
sentinel are observed, setup truthfully reports `RUNTIME_READY: BLOCKED`.

### Finish checklist

- Setup exited successfully. For a full reconciliation, execution—not just preview—reported
  `UPGRADE: READY` and `ACTIVE_FORGE: v6`.
- Review `git status` and `git diff`: intended harness changes only; custom project content retained.
- Resolve every `CONFIG_READINESS: BLOCKED` or `CODEX_CONFIG_READINESS: BLOCKED` diagnostic.
  These mean configuration is incomplete even if setup exited zero or printed `MATERIALIZED`;
  fix the named prerequisite/merge issue, rerun the appropriate command, and check again.
- `INSTALLATION: MATERIALIZED` means installed files, not a certified live host. Resolve any
  `RUNTIME_READY: BLOCKED` diagnostic before claiming that host works; do not reinstall blindly.
- Commit the reviewed project harness changes on the setup/update branch. Never commit
  `.forge/local/`, credentials, or unrelated files. Teams use one upgrader and review the change as
  a dedicated PR; other developers pull it.
- Project setup does not refresh global configuration or sibling worktrees. For linked worktrees,
  follow [the worktree instructions](guides/setup-scenarios.md#linked-worktree).

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
