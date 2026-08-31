# Design: Forge 6 Upgrade Hardening

**Date:** 2026-08-31
**Status:** Draft for developer review

## Problem

Forge 6 has the right target architecture—one canonical `.forge/` harness with thin Claude Code and
Codex adapters—but its public upgrade path is not yet safe and clear for ordinary repositories with
older Forge installations. A force refresh (`-f`) correctly refuses v5, while authoritative full
refresh (`-F`) can stop at the first modified legacy file and can preserve old root-policy bodies in
a way that leaves two active instruction systems. Users need one predictable upgrade command, a
complete preview, and a simple guarantee: after a successful migration there is exactly one active
Forge, with project-owned content and state preserved.

Audits of two existing downstream repositories exposed the common shapes this design must handle:

- a mostly exact v5 install with a project-owned rules file and ADR index;
- a tracked v5 install mixed with pre-existing Codex adapters, modified hook/CI files, and a large
  project instruction body;
- root files beginning with a historical `forge:migrated` sentinel before the old Forge region;
- enabled legacy plugins that may overlap the v6 harness.

A second audit added two more supported profiles:

- an exact v5.60 core with a historical project `AGENTS.md`, content-identical untracked Codex skill
  copies, a custom project agent, and one legacy state store;
- a v5.61 stamp followed by a deliberately developed cross-host runtime, custom `.agents` skills,
  modified legacy workflows, and two divergent local state stores.

The upgrade must handle those shapes explicitly. It must not silently delete uncertain content or
attempt a semantic LLM merge.

## Goals

1. Make the v5/mixed-to-v6 upgrade understandable before it changes files.
2. Guarantee exactly one active Forge after a successful full refresh.
3. Preserve project-owned instructions, settings, ADRs, state, memory, and unknown extensions.
4. Replace or retire legacy behavior only when Forge ownership is proven.
5. Report every blocking ambiguity in one run with concrete remediation.
6. Keep Unix and Windows behavior equivalent and dependency-light.

## Non-goals

- Inferring ownership from prose meaning or asking an agent to merge arbitrary Markdown.
- Deleting every unknown file under `.claude/`, `.codex/`, or `.agents/`.
- Making `-f` guess how to migrate v5.
- Certifying Claude Code/Codex authentication or runtime readiness as part of filesystem migration.
- Supporting unversioned historical layouts for which Forge has no ownership evidence.

## Public CLI Contract

| Intent | Unix | Windows | Behavior |
| --- | --- | --- | --- |
| Refresh an existing v6 install | `setup.sh -f` | `setup.ps1 -Force` | Refreshes managed v6 content; still refuses v5 or mixed legacy ownership. |
| Preview a v5/mixed migration | `setup.sh -F --dry-run` | `setup.ps1 -FullRefresh -DryRun` | Performs full discovery, classification, staging validation, and reporting without changing project or global files. |
| Execute a v5/mixed migration | `setup.sh -F` | `setup.ps1 -FullRefresh` | Runs the same analysis, then applies the validated transaction. |

`-R` remains the Windows short alias for `-FullRefresh`. Full refresh remains incompatible with
force, incremental upgrade, continuity migration, and Playwright-scaffolding flags. Project and
global scopes remain separate transactions.

Dry-run and execution must use the same planner. A dry-run report is advisory, not an authorization
token: execution repeats discovery and refuses to apply if any input changed.

## Success Invariant: One Active Forge

A successful full refresh may write the v6 stamp only after proving all of the following:

- `.forge/` contains the canonical managed harness;
- `CLAUDE.md` and `AGENTS.md` contain at most one bounded Forge adapter each;
- `.claude/`, `.codex/`, and `.agents/` expose only the intended thin v6 adapters and qualified
  custom content;
- no active legacy Forge rule, command, hook, prompt hook, settings entry, or retired `/codex`
  surface remains discoverable;
- preserved custom native content does not collide with a required Forge command, skill, hook, or
  policy surface;
- developer state and project-owned durable memory are preserved or translated;
- all planned replacements/deletions are backed up and the transaction can roll back.

Historical bytes may remain under `.forge/local/migration-backups/`; backups are not active host
discovery surfaces. If the planner cannot prove the invariant, it writes no v6 stamp and changes no
live files. Independently installed plugins are not a second filesystem harness; a plugin overlap
may allow materialization while keeping the affected host `RUNTIME_READY: BLOCKED` until qualified
or resolved.

## Ownership Classification

Every relevant path or managed entry receives exactly one classification before mutation:

| Classification | Evidence | Action |
| --- | --- | --- |
| `MANAGED_EXACT` | Released fingerprint, generated marker, or exact versioned managed region | Replace, translate, or delete according to the v6 manifest. |
| `PROJECT_OWNED` | Outside a bounded Forge region or explicitly protected by the ownership contract | Preserve byte-for-byte except for inserting/replacing a bounded adapter marker. |
| `CUSTOM_INERT` | Unknown content with no active collision | Preserve and report. |
| `AMBIGUOUS_ACTIVE` | Modified Forge-like content, malformed managed data, or custom content colliding with required v6 behavior | Preserve, report all conflicts, and block the transaction. |

The planner must collect all `AMBIGUOUS_ACTIVE` findings before returning `BLOCKED`; users should
not have to rerun the installer repeatedly to discover one conflict at a time. A finding includes
scope, path or entry, detected ownership evidence, collision type, and a direct resolution.

## Root Instruction Reconciliation

Root `CLAUDE.md` and `AGENTS.md` are project-owned containers, not wholesale Forge files. The
reconciler operates only on explicit, versioned structures:

1. Ignore any recognized leading `forge:migrated` or `forge:reconciled` sentinel when locating a
   historical Forge region.
2. Identify known v5 Forge regions using versioned boundaries/fingerprints, not approximate prose.
3. Remove only the proven v5 Forge region.
4. Preserve all project-owned text in its original order and bytes where possible.
5. Insert or refresh exactly one v6 native adapter marker.
6. Scan preserved active text for obsolete Forge references such as retired commands or legacy
   managed paths. A proven reference inside a known Forge region is removed with that region; an
   ambiguous reference in project text is reported and blocks migration rather than being rewritten.

Per-file behavior:

- missing native root file: create the thin v6 adapter;
- project-owned root file: preserve it and add the bounded adapter;
- historical Forge-filled file: remove proven Forge regions, preserve any project content, add the
  adapter;
- ambiguous mixed file: preserve it unchanged and block with reconciliation instructions.

Users never maintain `CLAUDE.md` and `AGENTS.md` as duplicate policy documents. Both remain thin
native discovery surfaces over the same canonical `.forge/instructions.md`; teams keep shared
project context once, outside Forge-managed regions.

## Native Trees, Settings, and Plugins

- Proven generated v5 `.claude/`, `.codex/`, or `.agents/` files are replaced or removed according
  to the versioned ownership and tombstone manifests.
- Historical cross-host copies may be treated as managed only when their bytes match a versioned
  alias fingerprint for the stamped release. A familiar name or similar prose is not provenance.
- Unknown native files are preserved. If their names, hooks, commands, skills, or matchers overlap a
  required v6 surface, the migration is `BLOCKED` with the exact collision.
- Settings merges preserve unrelated user entries. Proven v5 Forge entries are removed before v6
  entries are installed so a hook cannot run twice.
- Enabled legacy plugins are classified by actual overlap. Inert plugins are preserved and
  reported; plugins that can provide competing Forge behavior are preserved and allow filesystem
  migration, but keep that host `RUNTIME_READY: BLOCKED` until the user disables, reconciles, or
  qualifies them.
- Existing custom native goals remain protected and continue to use the existing runtime-readiness
  collision rules.

An independently developed active harness—such as a custom runtime referenced by root instructions,
Claude hooks, Codex hooks, and native skills—is not a legacy file collection. The report groups its
paths and registrations as one `AMBIGUOUS_ACTIVE` system and gives two choices: keep it and do not
migrate, or explicitly retire/archive it before rerunning full refresh. Forge never silently deletes
that project-owned runtime, even when its responsibilities overlap v6.

## State, Backups, and Transaction Flow

The existing full-refresh transaction remains the foundation:

1. Resolve the canonical project or global root. Execution acquires the existing bounded guard;
   dry-run records a read-only input snapshot without creating a persistent guard.
2. Discover the installed stamp, native surfaces, settings entries, root regions, state, and
   versioned ownership evidence.
3. Build the complete classification and action plan.
4. Materialize the proposed result in staging and validate the one-active-Forge invariant.
5. Emit the report. Dry-run stops here and removes staging without writing guards, backups, stamps,
   reports, or project files.
6. Execution repeats discovery under the guard, revalidates source hashes, creates raw backups for
   every replaced/deleted destination, and records the journal.
7. Commit with the existing no-clobber/rollback behavior, translate the single supported active
   legacy state to `.forge/local/state.md`, invalidate legacy evidence, and write the v6 stamp last.

If discovery finds multiple plausible active state stores, it preserves all of them and blocks with
their paths, hashes, and modification times. It does not guess which objective is current. The user
selects or reconciles the authoritative state, then reruns preview.

The report uses the existing action categories (`CREATED`, `REWRITTEN`, `DELETED`, `PRESERVED`,
`PRESERVED_COMPAT`, `PRESERVED_COMPAT_BLOCKED`, `BLOCKED`) plus a final summary:

```text
UPGRADE: READY | BLOCKED
ACTIVE_FORGE: v6 | unchanged
CHANGES: created=<n> rewritten=<n> deleted=<n> preserved=<n>
BLOCKERS: <n>
NEXT_STEP: <one exact command or reconciliation instruction>
```

## User Experience

The upgrade guide leads with preview, not mutation:

```bash
~/claude-codex-forge/setup.sh -F --dry-run
~/claude-codex-forge/setup.sh -F
```

Users read one complete report, resolve only named blockers, rerun preview, then execute. Successful
output explicitly says that one active v6 harness is installed, names preserved custom content and
backup location, and separately reports each host's materialization/runtime-readiness status.

`setup.sh -f` continues to produce a short message directing legacy users to the preview command,
so users do not need to know the internal difference before they begin.

## Acceptance Matrix

The owning Bash and PowerShell behavioral suites cover these supported upgrade shapes:

1. exact released v5 install → clean preview and successful migration;
2. v5 plus project-owned `AGENTS.md` → project text preserved, thin adapter added;
3. legacy `.claude`-only install → canonical v6 plus both host adapters, no active v5;
4. mixed `.claude`/`.codex`/`.agents` install → exact generated artifacts retired, custom inert files
   preserved, collisions reported;
5. root instruction file with a leading migration sentinel → known v5 region removed without
   duplicating or losing project text;
6. modified Forge-owned active file → all ambiguities reported and no live write/stamp;
7. custom project agent, rule, setting, and enabled plugin → inert content preserved; active overlap
   blocks with remediation;
8. existing v6 install → `-f` remains idempotent and `-F --dry-run` reports no migration needed;
9. dry-run for every case → byte-identical Git worktree, local state, global state, and stamps;
10. injected transaction failure → rollback restores exact pre-upgrade bytes.

Additional integration assertions cover:

- an exact v5 core plus historical project `AGENTS.md`, content-identical untracked skill aliases,
  and a custom project agent: exact aliases are replaced, custom content is preserved, and any
  obsolete active root reference is reported in one pass;
- a stamped v5 repository with an independently developed active cross-host runtime and two local
  state stores: preview groups the runtime collision, reports both states, performs no writes, and
  refuses to claim a clean migration until the project owner chooses which harness/state to keep.

Four sanitized integration fixtures model the audited downstream repository shapes without copying
private project content. They complement, rather than duplicate, the version-by-version fingerprint
matrix.

Full refresh operates on the current canonical worktree only. It never edits sibling linked
worktrees. After the migration commit is merged, other branches receive the tracked v6 layout through
normal merge/rebase; each worktree retains and translates its own gitignored local state when setup
is run there.

## Documentation and Release Boundary

Update the README, getting-started/setup scenarios, upgrade guide, command reference, and
troubleshooting guide together. Documentation must distinguish:

- `-f` v6 refresh from `-F` legacy migration;
- preview/readiness from mutation;
- filesystem `MATERIALIZED` from authenticated `RUNTIME_READY`;
- preserved project content from blocked active collisions;
- automatic rollback from explicit recovery-required cases.

The change is complete when the acceptance matrix passes on Unix, the PowerShell suite passes in
Windows CI, the final aggregate passes once on the frozen candidate, and the public documentation
matches the executable CLI.
