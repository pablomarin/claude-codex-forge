# Upgrading to Forge 6

Forge 6 changes harness ownership. Upgrade an installed repository with an authoritative full
refresh, not a sequence of force copies:

```bash
git -C ~/claude-codex-forge pull
cd /path/to/project
~/claude-codex-forge/setup.sh -F
```

```powershell
git -C $HOME\claude-codex-forge pull
Set-Location C:\path\to\project
& $HOME\claude-codex-forge\setup.ps1 -FullRefresh # -R is the short alias
```

The command must run at the canonical repository root. Unix full refresh requires Python 3.

## What the Transaction Does

The checked-in manifests identify canonical v6 files, generated adapters, protected paths, and
version-specific v5 ownership evidence. The transaction stages the entire result, validates it,
backs up replaced bytes under `.forge/local/migration-backups/`, commits by bounded renames, and
writes `.forge/version` last. A failed transaction rolls back instead of leaving mixed discovery
trees.

It creates one canonical `.forge/` harness and thin native adapters under `.claude/`, `.codex/`, and
`.agents/`. Active v5 state is translated to `.forge/local/state.md`; legacy review, goal, and
authorization evidence is invalidated because it cannot certify the new contract.

## Protected Content

Full refresh preserves:

- user text outside Forge marker blocks in root/global instruction files;
- `.forge/local/state.md`, local memory, and project-owned `.forge/memory/`;
- unknown/custom settings and MCP entries unless they collide with required Forge behavior;
- custom native goal content, reported as a host readiness collision rather than overwritten;
- legacy files whose ownership cannot be proved.

Only entries proven Forge-owned by a generated marker, released fingerprint, or versioned mixed-file
region may be rewritten or removed. An ambiguity blocks before the first live v6 write.

## Read the Report

Every action is classified:

| Category | Meaning |
| -------- | ------- |
| `CREATED` | New canonical or adapter file |
| `REWRITTEN` | Proven Forge-owned content replaced or translated |
| `DELETED` | Proven obsolete managed file removed after backup |
| `PRESERVED` | Protected developer/project content retained |
| `PRESERVED_COMPAT` | Unknown or historical content retained without duplicating its behavior |
| `PRESERVED_COMPAT_BLOCKED` | Retained content overlaps Forge behavior; the named host stays not ready pending qualification or developer resolution |
| `BLOCKED` | Transaction could not prove a safe result; follow the printed recovery guidance |

`INSTALLATION: MATERIALIZED` confirms filesystem installation only. Per-host `RUNTIME_READY`
diagnostics cover binary availability, capabilities, discovery, authenticated trust, goal
collisions, and Codex hook registration.

## Project and Global Scopes

A project refresh never changes home-directory configuration. Refresh the global harness
separately when setup reports it stale:

```bash
~/claude-codex-forge/setup.sh --global -F
```

```powershell
& $HOME\claude-codex-forge\setup.ps1 -Global -FullRefresh # or -Global -R
```

Do not combine full refresh with force, incremental upgrade, continuity migration, or Playwright
scaffolding flags.

## Recover a Blocked Full Refresh

Most failures roll back automatically and print `ROLLED_BACK`; fix the cause and rerun full refresh.
If the report names a `recovery_required` journal, do not delete the journal or either preserved
version. Resolve any concurrent edit, then run the exact journal path reported:

```bash
~/claude-codex-forge/scripts/recover-full-refresh.sh \
  --journal /absolute/project/.forge/local/migration-journals/<transaction>.json \
  --target /absolute/project
```

```powershell
& $HOME\claude-codex-forge\scripts\recover-full-refresh.ps1 `
  -Journal C:\absolute\project\.forge\local\migration-journals\<transaction>.json `
  -Target C:\absolute\project
```

Recovery validates the journal, transaction root, repository identity, and recorded hashes before
changing anything. After recovery, rerun full refresh and then repeat host trust/readiness checks.

## Legacy `CONTINUITY.md`

Full refresh preserves the original file. The versioned migration recognizes supported v5 state and
root-instruction regions; if it cannot prove where custom legacy content belongs, it reports
`BLOCKED` for manual reconciliation rather than deleting or guessing.
