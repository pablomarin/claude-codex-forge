# Parallel and Cross-Host Sessions

Use one worktree per active feature. Claude Code and Codex can each lead different worktrees, resume
the same worktree in later sessions, or coordinate concurrent work in one worktree. Forge supplies
artifact-bound evidence, not an edit lock.

## Isolated Features

`/new-feature` and `/fix-bug` use the installed `worktree-lifecycle` helper when started from the
primary checkout. It creates `.worktrees/<name>/` on exactly `feat/<name>` or `fix/<name>`, copies
missing ignored/private installed harness files plus `.claude/settings.json`, `.codex/config.toml`,
and the `.codex/hooks.json` validation mirror without overwriting existing content, then seeds the
worktree-local state and its guarded fold baseline. Codex hook execution still routes through the
primary checkout. The helper never copies local memory, receipts, goal authorization, or evidence.
Each worktree therefore has its own candidate, `.forge/local/state.md`, and local evidence even when
the harness is intentionally uncommitted.

```bash
# Terminal 1
cd /project && claude
> /new-feature auth

# Terminal 2
cd /project && codex
# invoke the installed workflow-new-feature skill for api
```

Review and verification receipts are bound to both candidate identity and worktree identity.
Copying clean evidence to another worktree does not satisfy its gates.

## Switch Hosts Mid-Feature

Open either host in the repository -> say "get into this worktree and continue" -> work there -> close or switch hosts -> repeat without reopening at the worktree path.

For example, a session that starts in the primary checkout can select the worktree for its tools:

```bash
cd /project
codex
> Get into /project/.worktrees/auth and continue from .forge/local/state.md.
```

The new host reads `.forge/local/state.md`, continues at the next incomplete checkpoint, and keeps
still-valid artifact-bound evidence. It does not repeat planning merely because the host changed.
The current host is main for the next action; reviewer selection is recomputed for that action.
Opening the client directly at the linked worktree remains optional.

Forge creates no edit lock: concurrent sessions are allowed. Forge intentionally adds no ownership daemon, so the
developer still coordinates overlapping edits. When any session changes the candidate,
candidate-bound evidence becomes stale automatically; rerun the affected review and verification
against the new candidate before certification. Ordinary Git recovery remains the escape hatch for
an actual edit conflict.

## Codex Hooks in Linked Worktrees

Claude project hooks live in each adapter surface. Codex uses one stable registry/router in the
primary checkout because linked worktrees share the Git common directory. Initial setup from a
linked worktree therefore prints the exact command to run in the primary checkout and does not
mutate its sibling.

Repository hook setup and trust happen once unless the native host reports a genuinely new or
changed hook definition. They are not repeated per worktree. After primary registration and project trust, the stable router validates the common directory and
dispatches each event to the event worktree's own `.forge/hooks/` and `.forge/local/state.md`. A
missing/stale registration or wrong-common-directory event keeps Codex `RUNTIME_READY: BLOCKED`.

## Practical Rules

- Start a new feature from the primary checkout; the workflow moves into its worktree.
- A current or later Codex or Claude Code session may continue it by setting tool cwd to that
  worktree; no task-root reopen, copied identity, or per-worktree trust step is needed.
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
