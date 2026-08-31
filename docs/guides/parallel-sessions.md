# Parallel and Cross-Host Sessions

Use one worktree per active feature. Claude Code and Codex can each lead different worktrees, and a
developer may resume one worktree in the other host after stopping the first session.

## Isolated Features

`/new-feature` and `/fix-bug` create `.worktrees/<name>/` when started from the primary branch. Each
worktree has its own branch, candidate, `.forge/local/state.md`, and local evidence.

```bash
# Terminal 1
cd /project && claude
> /new-feature auth

# Terminal 2
cd /project && codex
# invoke the installed workflow-new-feature skill for api
```

Receipts are bound to both candidate identity and worktree identity. Copying a clean receipt to
another worktree does not satisfy its gates.

## Switch Hosts Mid-Feature

Stop the current host, then open the same worktree in the other host:

```bash
cd /project/.worktrees/auth
codex # after the Claude Code session has stopped
```

The new host reads `.forge/local/state.md`, continues at the next incomplete checkpoint, and keeps
still-valid artifact-bound evidence. It does not repeat planning merely because the host changed.
The current host is main for the next action; reviewer selection is recomputed for that action.

> **Warning:** Do not edit the same worktree from both hosts simultaneously. Forge intentionally
> adds no locks or ownership daemon. Concurrent writes can invalidate the frozen candidate and all
> review/verification receipts; ordinary Git recovery remains the escape hatch.

## Codex Hooks in Linked Worktrees

Claude project hooks live in each adapter surface. Codex uses one protected registry/router in the
primary checkout because linked worktrees share the Git common directory. Initial setup from a
linked worktree therefore prints the exact command to run in the primary checkout and does not
mutate its sibling.

After primary registration and project trust, the stable router validates the common directory and
dispatches each event to the event worktree's own `.forge/hooks/` and `.forge/local/state.md`. A
missing/stale registration or wrong-common-directory event keeps Codex `RUNTIME_READY: BLOCKED`.

## Practical Rules

- Start a new feature from the primary checkout; the workflow moves into its worktree.
- Do not create nested worktrees.
- Use paths relative to the active worktree.
- `quick-fix` uses the current branch and does not create a worktree.
- State and volatile evidence are per worktree; ADRs, changelog, and committed memory remain shared.
- Run `/finish-branch` only after the PR has merged; it folds eligible state back and cleans up.

Manual cleanup remains standard Git:

```bash
git worktree remove .worktrees/auth
git worktree prune
git branch -d feat/auth
```
