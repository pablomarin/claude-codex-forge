# Worktree Policy

**`/new-feature` and `/fix-bug` ALWAYS create a worktree** (unless already inside one). This ensures parallel sessions never mix work - even if you're on an unrelated feature branch.

**Before creating a worktree, Forge-managed upgrade files must be committed and pushed.** If `.claude/`, `.mcp.json`, `docs/reference/`, `docs/adr/`, `tests/e2e/`, or `docs/ci-templates/` are changed/untracked in the parent checkout, STOP and commit/discard them first. If local `<default>` has Forge-managed commits ahead of `origin/<default>`, push them before using `/new-feature` or `/fix-bug`. New worktrees normally base from `origin/<default>` and will not inherit uncommitted or unpushed Forge machinery.

**CRITICAL -- Always check if you are on a git worktree. If you are, never commit to the main folder ALWAYS TO THE WORKTREE**

**`/quick-fix` does NOT create worktrees** - it's for trivial changes only.

When running Superpowers skills (`brainstorming`, `writing-plans`, `executing-plans`), these skills may attempt to create worktrees. **SKIP worktree creation** in these skills - you're already isolated.
