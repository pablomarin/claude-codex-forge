# Setup Scenarios

Forge always installs one `.forge/` harness and both native adapter surfaces. You choose the main
agent simply by opening Claude Code or Codex for the current task.

## Fresh Project, One Engine Installed

```bash
cd /path/to/project
git init
~/claude-codex-forge/setup.sh -p "My Project"
claude # or codex
```

The missing engine's adapter is still materialized for later. Review continues with a fresh
same-engine process and prints a fallback reason; council runs all seats and its chairman on the
installed engine. Installing and authenticating the other CLI later requires no project redesign.

## Fresh Project, Both Engines Installed

Run the same setup command. Start either host:

```bash
claude
# later, from the same worktree after the Claude session stops
codex
```

The current host is main for that action. Review prefers the other engine, while state, receipts,
memory pointers, plans, and checkpoints stay under `.forge/` for cross-host resume.

## Existing v5 Project

Do not layer v6 beside the old managed harness. Pull Forge and run the authoritative transaction:

```bash
git -C ~/claude-codex-forge pull
cd /path/to/project
~/claude-codex-forge/setup.sh -F
```

Windows PowerShell:

```powershell
git -C $HOME\claude-codex-forge pull
Set-Location C:\path\to\project
& $HOME\claude-codex-forge\setup.ps1 -FullRefresh # or -R
```

The transaction preserves user-owned content, migrates active state, removes only proven
Forge-owned legacy files, and stops on ambiguous ownership. Read [Upgrading](upgrading.md) before
resolving a blocked report.

## Global Refresh

Global files have their own transaction and are never changed by project setup:

```bash
~/claude-codex-forge/setup.sh --global -F
```

```powershell
& $HOME\claude-codex-forge\setup.ps1 -Global -FullRefresh # or -Global -R
```

## Linked Worktree

Project files may be refreshed from the canonical repository root. Codex's hook registry is shared
through the Git common directory and must be registered from the primary checkout. When setup sees
a linked worktree it leaves that registry alone and prints:

```text
CODEX_HOOKS: BLOCKED linked worktree cannot mutate primary registration
Run: cd '<primary-checkout>' && '<forge-clone>/setup.sh'
```

Run that exact command, complete Codex's trust ceremony in the primary checkout, then reopen the
linked worktree. Each hook event is still routed back to the event worktree's own `.forge/` state.

## Playwright Scaffold

For a fresh TypeScript/full-stack install, add `--with-playwright` (PowerShell:
`-WithPlaywright`). Full refresh is intentionally separate; do not combine those flags.
