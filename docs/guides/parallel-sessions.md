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

When the host offers native isolation, select its worktree option before starting the session.
The host creates the checkout outside the agent sandbox. Forge then adopts that fresh checkout
before workflow activation. Anthropic documents Desktop's per-session Git worktrees and the CLI
`--worktree` equivalent in its [Claude Code Desktop guide](https://code.claude.com/docs/en/desktop).

```bash
.forge/hooks/lib/worktree-lifecycle.sh adopt \
  --kind feat --name auth --base main --worktree "$PWD"
```

Adoption verifies that the linked worktree is clean, unpublished, and still at the exact requested
base. It seeds local Forge state and changes a host-generated branch such as `claude/auth-123` or
`codex/auth-123` to `feat/auth` (use `--kind fix` for `fix/auth`). It refuses to rename protected,
dirty, shared, or published work. This is the current safe equivalent of Forge V5 creating the
worktree itself.

```bash
# Terminal 1
cd /project && claude
> /new-feature auth

# Terminal 2
cd /project && codex
# invoke the installed new-feature skill for api
```

Review and verification receipts are bound to both candidate identity and worktree identity.
Copying clean evidence to another worktree does not satisfy its gates.

## Switch Hosts Mid-Feature

Open either host in the repository and select the linked worktree as the tool working directory
for local edits, reviews, verification, approval recording and normal receipt-validating promotion.
Continue in the current session by default; switch only if the developer chooses to.

For example, a session that starts in the primary checkout can select the worktree for its tools:

```bash
cd /project
codex
> Get into /project/.worktrees/auth and continue from .forge/local/state.md.
```

The new host reads `.forge/local/state.md`, continues at the next incomplete checkpoint, and keeps
still-valid artifact-bound evidence. It does not repeat planning merely because the host changed.
The current host is main for the next action; reviewer selection is recomputed for that action.
Opening the client directly at the linked worktree remains optional. Before direct commit, push
or PR creation, follow the installed
[Shipping from the current session](../../rules/workflow.md#shipping-from-the-current-session)
procedure. It requires verified task state and identity, matching process and input cwd, and a
successful exact-command local gate preflight. Keep native hooks and human authorization; report
native context mismatches and stop on real denials. Local verification does not certify a native
event or grant shipping authority. Revalidate the candidate, HEAD and approval before execution;
a still-current approval needs no new workspace-choice question.

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

- In Claude Desktop, turn on **worktree** before the first new-feature or bug-fix prompt. In other
  supported hosts, start from the primary checkout and use native isolation or let the portable
  helper create the worktree.
- A current or later Codex or Claude Code session may continue task work by setting tool cwd to
  that worktree; no copied identity or per-worktree trust step is needed. For direct shipping, use
  the [canonical preflight](../../rules/workflow.md#shipping-from-the-current-session).
- Do not create nested worktrees.
- Use paths relative to the active worktree.
- `quick-fix` uses the current branch and does not create a worktree.
- State and volatile evidence are per worktree; ADRs, changelog, and committed memory remain shared.
- Run `/finish-branch` only after the PR has merged. It records the finished work under the
  worktree's `### Done`, folds the narrative into the primary `.forge/local/state.md`, and removes
  the worktree only after the fold reports `FOLD_OK`.

## Finishing Parallel Worktrees

Each worktree's narrative folds back independently, in any order. The first fold after a quiet main
replaces main's narrative (`mode=replace`). When main changed after a worktree was seeded, because a
sibling folded first, a quick fix landed, or someone edited main's state, the fold merges instead
(`mode=merge`): it applies only the lines that worktree added or removed since its seed and keeps
everything else on main. Rerunning a fold is safe: it applies only worktree edits made since the
previous fold, so an unedited rerun changes nothing.

The fold stops with `FOLD_SAFE_STOP` while the worktree's `### Now` still lists work, so nothing is
silently dropped: move finished items to `### Done`, unfinished ones to `### Next` or
`### Deferred`, and rerun it.

Manual cleanup remains standard Git, after folding the worktree's state:

```bash
.forge/hooks/lib/worktree-lifecycle.sh fold --worktree "$PWD/.worktrees/auth"
git worktree remove .worktrees/auth
git worktree prune
git branch -d feat/auth
```

`git worktree remove` deletes the worktree's ignored `.forge/local/state.md`; skip it if the fold
did not report `FOLD_OK`.
