# /finish-branch — Host-Neutral Merge and Cleanup

Use after the PR is approved. This workflow merges only with explicit human authorization, preserves
developer continuity, and removes the feature worktree without choosing a permanent engine.

## 1. Inspect Without Mutation

1. Read `.forge/local/state.md` and resolve the active host through its adapter.
2. Resolve the current branch and inspect its PR state, URL, title, base, checks, and review status.
3. If no PR exists, stop. If it is already merged, skip to continuity/cleanup.
4. If checks, review, or conflicts still block merge, report the exact blocker and stop.

## 2. Authorize and Merge

Show the exact merge mutation, including PR URL and merge strategy. Pause for explicit human
authorization unless the human already approved this exact still-current merge. Council, reviewer, native `/goal`, and prior PR-creation authority cannot authorize
merge.

After authorization, the agent records the actual decision and runs the selected `gh pr merge` command once. Do not combine it with branch
deletion. Re-read PR state after any local checkout error: if the server says `MERGED`, continue;
if it remains `OPEN`, report the failure and stop rather than retrying or force-merging.

## 3. Preserve Continuity Before Removing the Worktree

Developer-local continuity lives in `.forge/local/state.md`; project-owned durable knowledge lives
in `.forge/memory/`. Never move gate receipts, `/goal` authorization, or candidate evidence between
worktrees.

When running inside an isolated worktree:

1. Record the finished status in the worktree narrative with native file tools: add the merged work
   (branch, PR URL, outcome) under `### Done`; move each remaining `### Now` item to `### Done` when
   finished or to `### Next` or `### Deferred` when not, leaving `### Now` empty; resolve
   `## Open Questions` and `## Blockers` that this work settled.
2. Run `.forge/hooks/lib/worktree-lifecycle.sh fold --worktree <absolute-worktree-path>`
   (PowerShell: `worktree-lifecycle.ps1 -Action Fold -Worktree <absolute-worktree-path>`) before
   navigating away. Only in the Forge source checkout, when the installed path is absent, use the
   tracked `hooks/lib/worktree-lifecycle.sh` or `.ps1` instead.
3. The helper atomically folds only `## State` (Done/Next/Deferred, with `### Now` cleared),
   `## Open Questions`, and `## Blockers` into primary state and reports `FOLD_OK` with a mode:
   - `mode=replace`: primary is unchanged since the seed snapshot, so it takes the worktree narrative.
   - `mode=merge`: primary changed after the seed (a sibling worktree folded first, a quick fix, or
     a hand edit). A deterministic three-way merge applies only the lines this worktree added or
     removed since the seed and keeps every other primary line.
   - `mode=unchanged`: primary already holds exactly this worktree narrative.
   Each fold becomes the base for the next one, so rerunning after a worktree edit applies only
   that edit, and an unedited rerun changes nothing.
   It never touches `## Workflow`, `## /goal session`, `## PR authorization`, receipts, objective
   nonce, or persistent Forge turn records.
4. `FOLD_SAFE_STOP` reports a missing or malformed input, or work still listed under the worktree
   `### Now`. It leaves every state file unchanged; fix the named cause and rerun the fold.
5. Read primary `.forge/local/state.md` with the host file-read tool and confirm the finished work
   appears under `### Done`.
6. Fold verified durable learnings separately into `.forge/memory/`; never copy local receipts or
   volatile session history there.

Only `FOLD_OK` permits removing the worktree: `git worktree remove` deletes its ignored
`.forge/local/state.md`, so stop cleanup after `FOLD_SAFE_STOP`. When not in a worktree, record
`FOLD_SKIP` and continue.

## 4. Cleanup

From the primary checkout, derive the physical worktree path and branch from Git rather than path
name assumptions. Then:

1. Remove the merged worktree only after its fold reported `FOLD_OK`.
2. Delete the merged local branch with safe deletion. A force deletion is a separate destructive
   action requiring new human authorization.
3. Check whether the remote branch exists. If it does, show the exact deletion and pause for new
   human authorization before running the bare remote-delete command.
4. Prune stale worktree/remote references and update the resolved default branch with a fast-forward
   only operation. Never hardcode `main`.
5. Clear the completed primary `## Workflow` block while preserving local narrative and the terminal
   Forge goal record. Record terminal status `complete` only after every authorized mutation and
   cleanup step actually succeeds.

Do not merge another PR, start new feature work, or delete unrelated worktrees as part of cleanup.
