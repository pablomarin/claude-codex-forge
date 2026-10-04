# 0011 — Fold a diverged continuity narrative by deterministic three-way merge

## Status

Accepted (2026-10-04). Amends [ADR 0008](0008-state-continuity-round-trip.md): divergence now merges
instead of stopping.

## Context

ADR 0008 folds a finished worktree's narrative into the primary `state.md` by exact replace when the
primary is unchanged since seed, and stops with `FOLD_DIVERGED` otherwise. It assumed one feature at
a time. Forge now documents one worktree per active feature, and in that supported flow the second
worktree to finish always diverged, because its sibling's fold had changed the primary. A quick fix
or hand edit on the primary had the same effect, and a retried fold diverged against its own earlier
result. Nothing then stopped `/finish-branch` cleanup, and `git worktree remove` deletes the ignored
worktree `state.md`, so the finished status never reached the primary.

The fold also cleared the worktree's `### Now` without a trace, although the template's own update
rule moves the next queued item from `### Next` into `### Now`.

## Considered Options

- **Option A (chosen):** deterministic line-level three-way merge per narrative section, using the
  seed snapshot as base, in both the Bash and PowerShell helpers.
- **Option B:** keep the safe-stop and document manual reconciliation — leaves the supported
  parallel flow broken.
- **Option C:** `git merge-file --union` — deterministic, but when two worktrees each delete a
  different adjacent line (the usual parallel case: each removes its own `### Next` item), union
  resolution restores both deleted lines.
- **Option D:** agent LLM merge, deferred by ADR 0008 — non-deterministic and not testable.

## Decision

When the primary is unchanged since seed, fold keeps ADR 0008's exact replace (`mode=replace`). When
the primary equals the worktree narrative, the fold has already happened (`mode=unchanged`).
Otherwise it merges each foldable section (`mode=merge`): lines the worktree removed since seed leave
the primary; lines it added are inserted after their nearest preceding worktree line that the
primary still has, or at the section top; every other primary line is kept. Blank and `---` divider
lines are layout, not merged content. Bash and PowerShell produce byte-identical results.

The fold refuses with `FOLD_SAFE_STOP` while the worktree `### Now` still lists work.
`/finish-branch` records the finished work under `### Done` first, confirms it reached the primary,
and removes the worktree only after `FOLD_OK`.

## Consequences

- ✅ Parallel worktrees, quick fixes on the primary, and retries fold without manual
  reconciliation. Only lines the worktree itself removed since seed leave the primary.
- ✅ The merge is deterministic, idempotent, and covered by executable Bash and PowerShell tests.
- ⚠️ A line both sides edited differently survives in both versions for the developer to tidy.
- ⚠️ Lines two worktrees insert at the same spot are ordered by fold order.
- 🔮 Unchanged from ADR 0008: gate sections never travel, the primary `### Now` is emptied on fold,
  and a worktree removed without `/finish-branch` still loses its narrative.
