# Finish Branch Workflow

> **Use this command after the PR is reviewed and approved.**
> This command handles merging the PR and cleaning up the worktree/branch.

---

## When to Use

- After all PR review comments have been addressed (via `/review-pr-comments`)
- After the PR is approved by reviewers
- When you're ready to merge to main and clean up

**Note:** This command does NOT commit, push, or create PRs. Those steps happen before this command. This command only merges and cleans up.

---

## Phase 1: Merge PR

### 1.1 Find the PR

```bash
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
gh pr view "$BRANCH_NAME" --json state,url,title
```

**If no PR exists:** Tell the user they need to create a PR first. STOP.

### 1.2 Check if already merged

```bash
gh pr view "$BRANCH_NAME" --json state --jq '.state'
```

If state is `MERGED`, skip to Phase 2 (cleanup).

### 1.3 Ask user for merge confirmation

**Ask the user:**

> "PR is ready: [URL]. Shall I merge it to main and clean up?"

**STOP and wait.** Do NOT proceed until the user explicitly says yes.

If the user says no or wants to wait — STOP HERE. They can run `/finish-branch` again later.

### 1.4 Merge the PR (only after user confirms)

```bash
gh pr merge "$BRANCH_NAME" --squash
```

> **Why squash?** Keeps main history clean. Use `--merge` or `--rebase` if the user prefers.
>
> **Why NOT `--delete-branch`?** `-d/--delete-branch` deletes the _local_ branch after
> merging, which forces `gh` to switch this checkout off the head branch onto the base
> branch. When you're in a worktree and the base branch (e.g. `main`) is checked out in
> the primary worktree, that switch fails with `fatal: '<base>' is already used by
worktree at <path>` — even though **the server-side merge already succeeded**. Phase 2
> below already removes the worktree, deletes the local branch, AND deletes the remote
> branch, so `--delete-branch` is redundant here. Dropping it makes the merge
> worktree-safe.

**If `gh pr merge` prints a local git error** (e.g. `fatal: '<base>' is already used by
worktree …`): the API merge almost certainly still landed. Do **not** retry the merge —
verify and continue:

```bash
gh pr view "$BRANCH_NAME" --json state --jq '.state'
```

If it prints `MERGED`, proceed to Phase 2 (cleanup). Only treat it as a real failure if
the state is still `OPEN`.

**If merge fails for a real reason** (merge conflicts, required checks pending — state
stays `OPEN`):

- Tell the user what failed
- STOP and let them resolve it
- Do NOT force merge

---

## Phase 2: Cleanup (After Merge)

### 2.1 Detect current context

```bash
# Check if we're in a worktree
if [[ "$(pwd)" == *".worktrees/"* ]]; then
  echo "STATE: IN_WORKTREE"
  # Extract worktree name from path
  WORKTREE_NAME=$(basename "$(pwd)")
  echo "WORKTREE_NAME: $WORKTREE_NAME"
else
  echo "STATE: NOT_IN_WORKTREE"
fi
```

### 2.2 Get branch name

```bash
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
echo "BRANCH_NAME: $BRANCH_NAME"
```

### 2.2b Fold continuity narrative into main (BEFORE navigating away / worktree removal)

> **Why here:** step 2.4 force-removes the worktree's working tree, including the gitignored `.claude/local/state.md` and its seed snapshot. The fold MUST read them while they still exist — and this step runs while we are still **inside** the worktree, so all worktree paths are cwd-relative and no cross-block variable is needed.

**Skip this entire step if NOT in a worktree** (`[[ "$(pwd)" != *".worktrees/"* ]]`) — there is no separate worktree narrative to fold.

Run the divergence check (self-contained — defines its own helpers):

```bash
if [[ "$(pwd)" != *".worktrees/"* ]]; then
  echo "FOLD_SKIP: not in a worktree — nothing to fold"
else
  MAIN_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
  MAIN_STATE="$MAIN_ROOT/.claude/local/state.md"
  WT_STATE=".claude/local/state.md"                       # cwd = worktree
  WT_SNAP=".claude/local/.state-seed-snapshot.md"

  # EXTRACT-FOLDABLE-BEGIN (byte-identical, indent-normalized, across new-feature.md, fix-bug.md, finish-branch.md — enforced by test-contracts.sh)
  # extract_foldable <state.md path> — prints foldable narrative with Now body blanked
  extract_foldable() {
    awk '
      /^## State$/        { f=1 }
      /^## Update Rules$/ { f=0 }
      f {
        if ($0 ~ /^### Now$/)            { now=1; print; next }
        if (now && $0 ~ /^### /)         { now=0 }
        if (now && $0 ~ /^---[[:space:]]*$/) { now=0 }
        if (now) next
        print
      }
    ' "$1"
  }
  # EXTRACT-FOLDABLE-END
  foldable_is_valid() {  # structural guard: refuse empty/malformed extraction
    printf '%s\n' "$1" | grep -q '^## State$' \
      && printf '%s\n' "$1" | grep -q '^## Open Questions$' \
      && printf '%s\n' "$1" | grep -q '^## Blockers$'
  }

  if [ ! -f "$WT_STATE" ]; then
    echo "FOLD_ABORT: worktree state.md absent ($WT_STATE) — NOT replacing main (loud safe-stop)"
  elif [ ! -f "$WT_SNAP" ]; then
    echo "FOLD_SAFE_STOP: seed snapshot missing ($WT_SNAP) — cannot verify divergence; NOT replacing main"
  elif [ ! -f "$MAIN_STATE" ]; then
    echo "FOLD_SAFE_STOP: main state.md missing — nothing to guard; NOT replacing (manual reconcile)"
  else
    MAIN_FOLD="$(extract_foldable "$MAIN_STATE")"
    WT_FOLD="$(extract_foldable "$WT_STATE")"
    SNAP_FOLD="$(cat "$WT_SNAP")"
    # Normalize BOTH sides through printf '%s\n' so a trailing-newline difference
    # (snapshot written via the Write tool vs awk stdout) can't cause false divergence.
    MAIN_TMP="$(mktemp)"; SNAP_TMP="$(mktemp)"
    printf '%s\n' "$MAIN_FOLD" > "$MAIN_TMP"
    printf '%s\n' "$SNAP_FOLD" > "$SNAP_TMP"
    if ! foldable_is_valid "$MAIN_FOLD" || ! foldable_is_valid "$WT_FOLD" || ! foldable_is_valid "$SNAP_FOLD"; then
      echo "FOLD_SAFE_STOP: main, worktree, or snapshot narrative is structurally incomplete (missing ## State/## Open Questions/## Blockers) — NOT replacing"
    elif diff "$MAIN_TMP" "$SNAP_TMP" >/dev/null 2>&1; then
      echo "FOLD_OK: main narrative unchanged since seed — safe to replace"
      echo "FOLD_MAIN_STATE:$MAIN_STATE"        # absolute; consumed by the FOLD_OK action below
      echo "FOLD_WT_STATE:$(pwd)/$WT_STATE"     # absolute worktree path (vars don't survive to the next block)
    else
      echo "FOLD_DIVERGED: main narrative changed since this worktree was seeded — NOT replacing (loud safe-stop)"
      echo "  ⚠ Review $MAIN_STATE and $WT_STATE and reconcile by hand. The worktree is left intact." >&2
    fi
    rm -f "$MAIN_TMP" "$SNAP_TMP"
  fi
fi
```

**Act on the sentinel:**

- **`FOLD_OK`** → replace main's foldable narrative with the worktree's. Use the absolute paths printed on the OK path: read the worktree state.md at the `FOLD_WT_STATE:` path, and using the **Edit** tool on main's state.md at the `FOLD_MAIN_STATE:` path, replace the `## State` (Done/Next/Deferred), `## Open Questions`, and `## Blockers` sections with the worktree's versions, then set `### Now` back to its empty placeholder. **Do NOT touch** `## Workflow`, `## /goal session`, `## PR authorization` on main (gate sections never travel; 2.8 clears main's `## Workflow` separately). Then continue cleanup (2.3 →).
- **`FOLD_SKIP`** → not in a worktree; continue cleanup normally.
- **`FOLD_DIVERGED` / `FOLD_SAFE_STOP` / `FOLD_ABORT`** → **STOP cleanup.** Do NOT replace main's narrative, and do NOT proceed to 2.3/2.4 — removing the worktree now would discard the un-folded narrative. Surface the printed warning, tell the user to reconcile `$MAIN_STATE` vs the worktree's state.md by hand, then re-run `/finish-branch`. (No LLM merge — divergence is a deliberate safe-stop in this version.)

### 2.3 Navigate to main repository

```bash
# Go back to main repo root (works from inside worktree)
cd "$(git rev-parse --git-common-dir)/.."
echo "Now in: $(pwd)"
```

### 2.4 Remove the worktree

```bash
git worktree remove ".worktrees/$WORKTREE_NAME" --force
echo "✓ Removed worktree: .worktrees/$WORKTREE_NAME"
```

### 2.5 Delete local branch

```bash
git branch -d "$BRANCH_NAME"
echo "✓ Deleted local branch: $BRANCH_NAME"
```

**If branch not fully merged (force delete with user confirmation):**

```bash
git branch -D "$BRANCH_NAME"
```

### 2.6 Delete remote branch

Since 1.4 no longer passes `--delete-branch`, the remote branch is still there — delete
it here. **Run each line as its own command — do NOT chain with `&&`/`||`/`;`/`|`.** The
Forge's `check-workflow-gates` hook blocks any compound command containing a `git push`
(it can't validate evidence against a chained push), so a one-liner like
`git push … || echo …` gets rejected at runtime.

First check whether the remote branch still exists:

```bash
git ls-remote --heads origin "$BRANCH_NAME"
```

If that printed a ref line, delete it with a **bare** push (nothing before or after it):

```bash
git push origin --delete "$BRANCH_NAME"
```

If it printed nothing, the remote branch is already gone — skip the push.

### 2.7 Prune stale references

```bash
git worktree prune
git fetch --prune
echo "✓ Pruned stale references"
```

### 2.8 Clear Workflow Tracking

If .claude/local/state.md has a `## Workflow` section with an active workflow, either:

- Set Command to `none` and clear the Checklist, OR
- Delete the entire `## Workflow` section

This marks the workflow as complete so the Stop hook stops reminding and the PreToolUse gate stops checking.

### 2.9 Switch to main and pull

```bash
git checkout main
git pull
echo "✓ Updated main branch"
```

> **Note on E2E use cases:** Any use cases graduated to `tests/e2e/use-cases/` during Phase 6.2b of `/new-feature` or `/fix-bug` are now on main and will be tested in regression mode by future features. No cleanup needed — they persist as permanent regression tests.

---

### 2.10 Restart development servers from main

> ⚠️ **Servers may still be running from the deleted worktree directory, or not running at all.**

Restart the development servers from the main directory so the user is back to a working state. Use the project's start commands from CLAUDE.md.

```bash
# Example (replace with actual project commands from CLAUDE.md):
# npm run dev
# uv run uvicorn main:app --reload
```

---

## Cleanup Summary

After successful cleanup, report to user:

```
✓ All done:
  - PR merged to main (squash)
  - Removed worktree: .worktrees/[name]
  - Deleted local branch: [branch]
  - Deleted remote branch: [branch]
  - Pruned stale references
  - On main branch (up to date)
  - Development servers restarted from main
```

---

## If NOT in a Worktree

If the user is not in a worktree (e.g., working directly on a feature branch):

1. **Skip the narrative fold-back (2.2b)** — there is no separate worktree state.md to fold (the 2.2b block self-skips via its `*".worktrees/"*` guard).
2. **Skip worktree removal** (steps 2.3, 2.4)
3. **Still delete branches** (steps 2.5, 2.6)
4. **Still prune and update main** (steps 2.7, 2.8)

---

## Error Handling

### PR not found

- Check if a PR exists for this branch: `gh pr list --head "$BRANCH_NAME"`
- The user may need to create the PR first

### Merge fails

- Check for merge conflicts or required checks
- Tell the user what failed and STOP

### Worktree removal fails

- Check if worktree has uncommitted changes
- Use `--force` flag if changes are already in the merged PR

### Branch deletion fails

- If "not fully merged": The PR might not be merged yet. Confirm with user.
- If "remote ref does not exist": GitHub may have auto-deleted on merge. This is fine.

---

## Checklist Summary

- [ ] PR merged to main (with user confirmation)
- [ ] Worktree removed (if applicable)
- [ ] Local branch deleted
- [ ] Remote branch deleted
- [ ] Stale references pruned
- [ ] On main branch (up to date)
- [ ] Development servers restarted from main
