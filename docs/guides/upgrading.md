# Upgrading to Forge 6

Forge 6 changes harness ownership. This path applies to Forge v5 and to repositories that already
contain any other agent harness: Claude-only files, Codex-only files, a mixture of both, or an
independently developed harness. Upgrade with one previewed, authoritative full refresh—not a fresh
install or a sequence of force copies.

For a person performing the upgrade, agent-assisted setup is the recommended human path; follow the
[canonical guide](agent-assisted-setup.md). Claude Code or Codex runs the preview, preserves its
exact output, explains each blocker, and asks before making reconciliation changes or executing the
migration. The agent never replaces the transaction below. Use the commands directly for CI,
automation, offline use, or troubleshooting:

```bash
git -C ~/claude-codex-forge pull
cd /path/to/project
~/claude-codex-forge/setup.sh -f --dry-run
# Resolve every named blocker. When the preview says UPGRADE: READY:
~/claude-codex-forge/setup.sh -f
```

```powershell
git -C $HOME\claude-codex-forge pull
Set-Location C:\path\to\project
& $HOME\claude-codex-forge\setup.ps1 -Force -DryRun
# Resolve every named blocker. When the preview says UPGRADE: READY:
& $HOME\claude-codex-forge\setup.ps1 -Force
```

The command must run at the canonical repository root. Unix full refresh requires Python 3. The
preview uses the same planner and staging validation as execution but creates no guard, backup,
report, stamp, or project/global file. Execution repeats discovery under the transaction guard, so
a stale preview never authorizes changed bytes.

`--upgrade` / `-Upgrade` updates an existing v6 installation while preserving project-owned
configuration. `-f` / `--force` / `-Force` previews or executes the transactional full
installation and reconciliation path from any state. The former `-F` / `--full-refresh` and
`-FullRefresh` / `-R` spellings remain deprecated compatibility aliases and are no longer needed.

If you do not know which harness or version is present, run the preview. It is the safe inventory
command and writes no project files.

## What the Transaction Does

The checked-in manifests identify canonical v6 files, generated adapters, protected paths, and
version-specific v5 ownership evidence. The transaction stages the entire result, validates it,
backs up replaced bytes under `.forge/local/migration-backups/`, commits by bounded renames, and
writes `.forge/version` last. A failed transaction rolls back instead of leaving mixed discovery
trees.

It creates one canonical `.forge/` harness and thin native adapters under `.claude/`, `.codex/`, and
`.agents/`. Active v5 state is translated to `.forge/local/state.md`; legacy review, goal, and
authorization evidence is invalidated because it cannot certify the new contract.

### Instruction ownership after migration

```text
.forge/                     Forge-owned engineering policy
docs/agent-context.md       Team-owned shared project knowledge
CLAUDE.md                   Thin Claude discovery adapter + shared-context pointer
AGENTS.md                   Thin Codex discovery adapter + shared-context pointer
```

Do not manually synchronize `CLAUDE.md` and `AGENTS.md`. Shared project instructions belong in the
neutral context file instead. Project-owned text stays outside their bounded Forge blocks, and both
blocks load the same `.forge/instructions.md` policy. Forge cannot infer repository architecture,
domain facts, or local commands; create `docs/agent-context.md` when the project needs shared
context and put this same pointer outside the managed block in both roots:

```markdown
Read `docs/agent-context.md` completely before acting.
```

Then maintain shared knowledge only in the neutral document. Keep only genuinely host-specific
instructions in the corresponding root file.

## Protected Content

Full refresh preserves:

- user text outside Forge marker blocks in root/global instruction files;
- `.forge/local/state.md`, local memory, and project-owned `.forge/memory/`;
- unknown/custom settings and MCP entries unless they collide with required Forge behavior;
- custom native goal content, reported as a host readiness collision rather than overwritten;
- legacy files whose ownership cannot be proved.

Only entries proven Forge-owned by a generated marker, released fingerprint, or versioned mixed-file
region may be rewritten or removed. An ambiguity blocks before the first live v6 write.

Full refresh distinguishes active harness policy from content Forge merely seeded as a starting
point. A modified rule, hook, workflow, setting, or native adapter still blocks because it can
compete with v6. Modified ADR indexes, CI references, and other non-runtime seeded content are
reported as `PRESERVED` and remain byte-identical. At a known cross-host alias path, an exact
released whole-file hash is sufficient for safe replacement even when the advisory v5 stamp is
older; any modified alias still blocks.

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

The final summary is the quick decision point:

| Summary | Meaning | Next step |
| ------- | ------- | --------- |
| `UPGRADE: READY` + `ACTIVE_FORGE: unchanged` | Read-only preview found a safe plan. | Run the same full-refresh command without the dry-run flag. |
| `UPGRADE: BLOCKED` | One or more ownership, root-policy, custom-harness, JSON, or state choices are unresolved. | Resolve every listed item; rerun preview. No migration was applied. |
| `UPGRADE: READY` + `ACTIVE_FORGE: v6` | Transaction committed one canonical v6 harness and thin host adapters. | Review preserved content and separately qualify each host. |
| `MATERIALIZED` + host `RUNTIME_READY: BLOCKED` | Filesystem migration succeeded, but that host is not yet safely runnable. | Follow the named host diagnostic; do not rerun filesystem migration blindly. |

An enabled plugin can cause the last outcome without being a second filesystem harness. Forge
preserves the plugin, completes a safe migration, and keeps only that host's runtime readiness
blocked until the overlap is disabled, reconciled, or qualified.

## Custom Harnesses and Competing State

An independently developed harness such as `.agent-workflows/` is project-owned. Forge will not
delete or silently merge it. A grouped `CUSTOM_HARNESS_COLLISION` report means the project owner
must choose one of two paths:

1. Keep the custom harness and stop the Forge migration; or
2. Adopt Forge v6: commit or back up the current project, archive the custom runtime under a
   non-discovered project location such as `docs/archive/legacy-agent-workflows/`, and remove only
   its reviewed root/settings/hook registrations.

`MULTIPLE_STATE_SOURCES` lists each plausible state path, hash, and modification time. Compare the
states, choose the authoritative one, archive the non-selected state, and put the chosen content at
the single source the report names before rerunning preview. Preserve custom skills, agents, hooks,
and documentation that do not collide with required Forge surfaces.

Root-policy findings are also manual by design. The report prints an `ACTION_REQUIRED` section with
file-specific edits, the shared-context location, the exact root pointer, and the preview command to
retry. Replace only obsolete project-owned references such as `@CONTINUITY.md`, the retired
Codex-only review command, or old `.claude/rules/` imports. Preserve useful project facts by moving
shared material to `docs/agent-context.md`; do not replace the whole root file or copy shared Forge
policy into both native files.

## Project and Global Scopes

A project refresh never changes home-directory configuration. Refresh the global harness
separately when setup reports it stale, previewing first:

```bash
~/claude-codex-forge/setup.sh --global -f --dry-run
~/claude-codex-forge/setup.sh --global -f
```

```powershell
& $HOME\claude-codex-forge\setup.ps1 -Global -Force -DryRun
& $HOME\claude-codex-forge\setup.ps1 -Global -Force
```

Do not combine full reconciliation with the routine update, retired continuity migration, or
Playwright scaffolding flags.

Full refresh changes only the current worktree. It does not edit sibling worktrees or guess which
sibling branch should receive the migration. Commit the successful harness migration, merge or
rebase it normally, then refresh another worktree only when that branch contains the migration.

## Recover a Blocked Full Refresh

Most failures roll back automatically and print `ROLLED_BACK`; fix the cause, rerun the read-only
preview, and execute only after it is ready.
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

The standalone continuity migration command is retired in Forge 6. Full refresh preserves the
original file and reports `LEGACY_CONTINUITY_UNRESOLVED` unless exact prior migration evidence
proves that its state already landed in the canonical v6 destination. Forge does not guess how a
mixed narrative file should be split.

Run `setup.sh -f --dry-run` or `setup.ps1 -Force -DryRun`. If blocked, move durable facts to
project instructions, architecture decisions to `docs/adr/`, and current local state to
`.forge/local/state.md`. Then archive or remove `CONTINUITY.md` and rerun preview. The retired
`--migrate` / `-Migrate` spelling changes nothing and exits nonzero with this same direction.
