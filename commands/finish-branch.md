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
authorization. Council, reviewer, native `/goal`, and prior PR-creation authority cannot authorize
merge.

After authorization, run the selected `gh pr merge` command once. Do not combine it with branch
deletion. Re-read PR state after any local checkout error: if the server says `MERGED`, continue;
if it remains `OPEN`, report the failure and stop rather than retrying or force-merging.

## 3. Preserve Continuity Before Removing the Worktree

Developer-local continuity lives in `.forge/local/state.md`; project-owned durable knowledge lives
in `.forge/memory/`. Never move gate receipts, `/goal` authorization, or candidate evidence between
worktrees.

When running inside an isolated worktree:

1. Run `.forge/hooks/lib/worktree-lifecycle.sh fold --worktree <absolute-worktree-path>`
   (PowerShell: `worktree-lifecycle.ps1 -Action Fold -Worktree <absolute-worktree-path>`) before
   navigating away. Only in the Forge source checkout, when the installed path is absent, use the
   tracked `hooks/lib/worktree-lifecycle.sh` or `.ps1` instead.
2. The helper compares the primary foldable narrative with the exact seed snapshot. Missing or
   malformed inputs emit `FOLD_SAFE_STOP`; primary divergence emits `FOLD_DIVERGED`. Both preserve
   every state file for manual reconciliation—no engine guesses a merge.
3. On an exact seed match, the helper atomically replaces only `## State` (Done/Next/Deferred, with
   `### Now` cleared), `## Open Questions`, and `## Blockers` in primary state. It never touches
   `## Workflow`, `## /goal session`, `## PR authorization`, receipts, objective nonce, or
   persistent Forge turn records.
4. Fold verified durable learnings separately into `.forge/memory/`; never copy local receipts or
   volatile session history there.

When not in a worktree, record `FOLD_SKIP` and continue.

## 4. Cleanup

From the primary checkout, derive the physical worktree path and branch from Git rather than path
name assumptions. Then:

1. Remove the merged worktree.
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
