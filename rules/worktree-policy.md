# Worktree Policy

**`/new-feature` and `/fix-bug` ALWAYS create a worktree** (unless already inside one). This ensures parallel sessions never mix work - even if you're on an unrelated feature branch.

**CRITICAL -- Always check if you are on a git worktree. If you are, never commit to the main folder ALWAYS TO THE WORKTREE**

**`/quick-fix` does NOT create worktrees** - it's for trivial changes only.

Planning and implementation continue in the workflow's existing isolated worktree.
Do not create another worktree for the same task when a native tool or optional integration
offers to do so. Forge owns these workflow phases; no Superpowers plugin is required.
