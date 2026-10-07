# Setup Scenarios

Forge installs one `.forge/` harness and both native adapter surfaces in each checkout.
Installation and upgrade include the repository's Git worktrees automatically; unrelated
repositories remain untouched. You choose the main
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
~/claude-codex-forge/setup.sh -f --dry-run
# After UPGRADE: READY
~/claude-codex-forge/setup.sh -f
```

Windows PowerShell:

```powershell
git -C $HOME\claude-codex-forge pull
Set-Location C:\path\to\project
& $HOME\claude-codex-forge\setup.ps1 -Force -DryRun
# After UPGRADE: READY
& $HOME\claude-codex-forge\setup.ps1 -Force
```

Preview is read-only. The transaction preserves user-owned content, migrates active state, removes
only proven Forge-owned legacy files, and reports all ambiguous ownership together. Read
[Upgrading](upgrading.md) before resolving an `UPGRADE: BLOCKED` report.

## Independent Projects

Forge is complete inside each repository. Installing or upgrading one project never changes
another project, and each committed `.forge/version` records that repository's exact release.
If an older Forge release left machine-wide files, use the optional
[one-time retirement procedure](upgrading.md#one-time-legacy-global-retirement); it is not an
installation step.

## Linked Worktree

Run the normal setup or upgrade command from any checkout's Git root. Setup discovers the
repository's worktrees and processes the primary checkout first, then the linked checkouts. Each
checkout keeps its branch, project configuration and local workflow state. The same release is
installed throughout, with a result for every checkout. Missing or blocked targets make the
overall command fail; other checkouts may already have completed.

Codex's hook registry is shared through the Git common directory and remains primary-owned.
Complete normal host authentication/trust after installation; materialization is not runtime
certification. Each hook event routes to the event worktree's own `.forge/` state.

To deliberately update only the current checkout, use `--this-checkout-only` (PowerShell:
`-ThisCheckoutOnly`). A linked checkout in this mode cannot register the primary's shared hooks
and prints the existing primary setup command. Run that command in the primary checkout (add the
checkout-only flag if you want to keep the operation narrow), then complete Codex trust and reopen
the linked worktree.

## Playwright Scaffold

For a fresh TypeScript/full-stack install, add `--with-playwright` (PowerShell:
`-WithPlaywright`). Full refresh is intentionally separate; do not combine those flags.
