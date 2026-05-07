# Troubleshooting

Common issues and their solutions.

## Setup script says files already exist

This is expected if you already have Claude Code set up. See [Upgrading](guides/upgrading.md) for options.

## Memory not persisting?

1. **Check auto memory is enabled** (it's on by default):

   ```bash
   # Inside Claude Code, run:
   /memory    # Should show auto-memory toggle
   ```

2. **Check global setup was run:**

   ```bash
   ls ~/.claude/CLAUDE.md
   ls ~/.claude/settings.json
   # Both should exist
   ```

3. **Check auto memory directory exists:**

   ```bash
   ls ~/.claude/projects/
   # Should show project directories
   ```

4. **View memory in Claude Code:**

   ```
   /memory
   # Should show MEMORY.md and CLAUDE.md files
   ```

5. **Tell Claude explicitly:**
   ```
   "Remember that we use pnpm for this project"
   "Save to memory that the database migrations use Alembic"
   ```

## Hooks not running?

### macOS / Linux

1. **Check script is executable:**

   ```bash
   ls -la .claude/hooks/
   # Should show -rwxr-xr-x for all .sh files
   ```

2. **Check settings.json is valid:**

   ```bash
   cat .claude/settings.json | jq .
   # Should parse without errors
   ```

3. **Check jq is installed (recommended):**

   ```bash
   which jq
   # Should output path like /usr/bin/jq
   # Note: hooks will work without jq but some features are reduced
   ```

4. **Restart Claude Code** — Hooks snapshot at session start

### Windows

1. **Check PowerShell execution policy:**

   ```powershell
   Get-ExecutionPolicy
   # If "Restricted", run:
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

2. **Check hook scripts exist:**

   ```powershell
   Test-Path .claude\hooks\session-start.ps1
   Test-Path .claude\hooks\check-state-updated.ps1
   Test-Path .claude\hooks\post-tool-format.ps1
   Test-Path .claude\hooks\pre-compact-memory.ps1
   # All should return True
   ```

3. **Test hook script manually:**

   ```powershell
   echo '{"stop_hook_active": false}' | powershell -File .claude\hooks\check-state-updated.ps1
   # Should run without errors
   ```

4. **Check settings.json is valid:**

   ```powershell
   Get-Content .claude\settings.json | ConvertFrom-Json
   # Should parse without errors
   ```

5. **Restart Claude Code** — Hooks snapshot at session start

## Drift detection messages — what they mean

The SessionStart hook and `/new-feature` / `/fix-bug` Pre-Flight surface a few advisory messages tied to default-branch detection. None of them block (with one exception noted below); they're diagnostic hints.

### `default-branch helper bailed; assuming 'main'`

The helper at `.claude/hooks/lib/default-branch.{sh,ps1}` couldn't detect the default branch from cached refs. This is a fallback to `main` — wrong on `master`-default repos. Causes:

- The repo has no `origin` remote AND neither `main` nor `master` exists locally.
- The repo was cloned with `--no-checkout` and no branches have been created yet.

**Fix:** ensure your repo has a real default branch checked out. If you just cloned, run `git checkout main` (or `master`).

### `Parent '<branch>' is N commits behind origin`

Drift warning — your local default branch is behind the remote. Run `git pull` to update it. New worktrees are still based from `origin/<default>` automatically; this warning just nudges you to catch up your main checkout when you next switch back.

### `Could not resolve any default-branch ref; basing worktree on HEAD`

Last-resort fallback inside `/new-feature` / `/fix-bug`. The new worktree was based on whatever you currently have checked out — possibly a feature branch, a tag, or a detached HEAD. Verify this is what you wanted; if not, delete the worktree (`git worktree remove .worktrees/<name>`) and re-run with the right base checked out.

### Drift warnings show the wrong default branch (e.g., `master` after a remote rename)

Detection uses the locally cached `origin/HEAD` symbolic ref, which is set at clone time and **not refreshed by `git fetch`** even after the upstream renames its default branch. Symptom: helper returns `master` after the remote was renamed `master → main`, and drift checks compare against the retired branch.

**Fix:**

```bash
git remote set-head origin --auto
git fetch --prune
```

This refreshes `refs/remotes/origin/HEAD` to the current upstream default and prunes the dead remote-tracking branch. After running, the helper returns the correct name on next invocation.

## Migration and the volatile state file

Issues specific to the 5.14 → 5.15 [CONTINUITY split](guides/upgrading.md#migrating-from-continuitymd-514--515) and the new `.claude/local/state.md`.

### `ℹ check-state-updated: state.md not found` breadcrumb

You ran a Claude Code turn or tried to `git commit` and saw a friendly stderr breadcrumb pointing at `setup.sh --migrate`. The PreToolUse and Stop hooks read **only** `.claude/local/state.md` — they never fall back to a legacy `CONTINUITY.md`. The breadcrumb fires when:

1. The repo has a legacy `CONTINUITY.md` at the root **and** `.claude/local/state.md` is missing — the hooks suspect you upgraded to 5.15 but haven't migrated yet.
2. `.claude/local/` was wiped (e.g., by an aggressive `git clean -fdx`, or because the `.gitignore` pattern wasn't picked up before a stash/restore).

**Fix:**

```bash
# Option A — run the migration assistant (preferred if you have legacy content):
~/claude-codex-forge/setup.sh --migrate

# Option B — re-install the starter state file (if there's nothing to migrate):
~/claude-codex-forge/setup.sh -f
```

Both options preserve any existing `.claude/local/state.md` content — they're idempotent.

### Dangling `@CONTINUITY.md` import in `CLAUDE.md`

If your `CLAUDE.md` still has a `@CONTINUITY.md` line at the top (the pre-5.15 default), Claude Code will silently fail to find the target — `@`-imports do not error on missing files. The migration assistant **detects but does not auto-edit** this; it prints a warning telling you the line is dangling.

**Fix:** delete the line yourself.

```diff
-@CONTINUITY.md
-
 # CLAUDE.md - my-project
```

You don't need to replace it with anything — `.claude/local/state.md` is intentionally NOT imported, so hooks read it on demand instead of Claude auto-loading it. That's the design (see [`docs/adr/0001-volatile-state-not-auto-loaded.md`](adr/0001-volatile-state-not-auto-loaded.md)).

### `setup.sh --migrate` says "nothing to migrate" but I have a `CONTINUITY.md`

The migration assistant uses sentinel markers in each destination to detect already-migrated content, so re-runs are no-ops. If you've already run `--migrate` once, subsequent invocations will skip every section and report nothing to do — that's correct behavior, not a bug. Verify by reading the destinations:

```bash
grep -A1 "^### Goal" CLAUDE.md
ls docs/adr/
cat .claude/local/state.md
```

If those look right, the migration succeeded. Re-running is safe.

### I want to start migration over

The original `CONTINUITY.md` is preserved byte-for-byte and never modified by `--migrate`, so you can roll forward at any time. To re-do migration from a clean slate:

```bash
# Remove the migrated outputs (KEEP CONTINUITY.md — it's the source)
rm -i .claude/local/state.md
# Optionally remove auto-numbered ADRs added by the previous --migrate run
# (review docs/adr/ first; seed ADRs 0001-0005 are NOT from --migrate)

# Re-run
~/claude-codex-forge/setup.sh --migrate
```

The Goal block in `CLAUDE.md` is overwritten only if you delete the `### Goal` subsection first; otherwise the assistant respects existing content.

## Permissions still prompting?

1. **Verify settings.json syntax:**

   ```bash
   cat .claude/settings.json | jq '.permissions'
   ```

2. **Check permission patterns:**
   - `Bash(uv:*)` matches `uv run pytest`
   - `Bash(uv run pytest)` only matches exact command
   - Use `:*` suffix for wildcards

3. **Restart Claude Code** after changing settings

## MCP servers not showing up in /mcp?

**`mcpServers` in `.claude/settings.json` is silently ignored.** This is a [known issue](https://github.com/anthropics/claude-code/issues/24477) — no error, no warning, they just don't load.

MCP servers must be in one of these files:

| File                       | Scope    | Shareable via git? |
| -------------------------- | -------- | ------------------ |
| `.mcp.json` (project root) | Project  | Yes                |
| `~/.claude.json`           | Personal | No                 |

The setup script creates `.mcp.json` at the project root. If you don't see servers:

1. **Check `.mcp.json` exists at project root** (not inside `.claude/`):

   ```bash
   cat .mcp.json
   ```

2. **If missing, re-run setup or create it manually:**

   ```json
   {
     "mcpServers": {
       "playwright": {
         "type": "stdio",
         "command": "npx",
         "args": ["-y", "@playwright/mcp@latest"],
         "env": {}
       },
       "context7": {
         "type": "http",
         "url": "https://mcp.context7.com/mcp"
       }
     }
   }
   ```

3. **Or use the CLI:**

   ```bash
   claude mcp add --transport stdio --scope project playwright -- npx -y @playwright/mcp@latest
   claude mcp add --transport http --scope project context7 https://mcp.context7.com/mcp
   ```

4. **Restart Claude Code** — MCP servers are loaded at session start.

## MCP servers still prompting for permission?

MCP permissions **do not support wildcards**. The pattern `mcp__*` does nothing.

Permissions go in `.claude/settings.json` (separate from MCP server definitions):

```json
// Wrong - wildcards don't work
"mcp__*"
"mcp__context7__*"

// Correct - use server name without wildcard
"mcp__context7"
"mcp__playwright"
```

The server name (without `__*`) approves ALL tools from that MCP server.

See: [GitHub Issue #3107](https://github.com/anthropics/claude-code/issues/3107)

## Plugins not showing in /help?

1. **Verify plugin installed:**

   ```
   /plugin list
   ```

2. **Verify plugin is ENABLED** in `~/.claude/settings.json`:

   ```json
   {
     "enabledPlugins": {
       "superpowers@superpowers-marketplace": true,
       "pr-review-toolkit@claude-plugins-official": true,
       "frontend-design@claude-plugins-official": true
     }
   }
   ```

3. **Restart Claude Code** after enabling plugins

4. **Try reinstalling:**
   ```
   /plugin uninstall superpowers@superpowers-marketplace
   /plugin install superpowers@superpowers-marketplace
   ```

## Codex CLI not working?

1. **Check it's installed:**

   ```bash
   codex --version
   # Should show 0.101.0 or higher
   ```

2. **Check authentication:**

   ```bash
   codex    # Should not prompt for login
   ```

3. **"command not found" on macOS:**

   ```bash
   # If installed via npm, check Node.js version
   node --version   # Must be 22+

   # If installed via Homebrew
   brew reinstall --cask codex
   ```

4. **Windows — "command not found" in WSL:**

   ```bash
   # Make sure you installed inside WSL, not Windows
   npm install -g @openai/codex
   ```

5. **Authentication from headless/remote environments:**

   ```bash
   codex login --device-auth
   # Gives a URL + code to enter on any browser
   ```

6. **Don't have a ChatGPT Plus/Pro/Business plan?**
   Use an API key instead:
   ```bash
   codex login --with-api-key
   ```

> **If Codex is unavailable**, the workflow still works — Claude will present designs to you for manual review. But Codex is faster and provides an independent perspective.

## /codex or /council returns empty output, hangs for ~17 min, or exits 0 with nothing

This is [openai/codex#19945](https://github.com/openai/codex/issues/19945) — a `codex exec` regression on 0.124.0+ where it silently exits with empty stdout when stdio is detached from a TTY AND the prompt is non-trivial. Both conditions fire whenever Claude Code's Bash tool spawns codex. The bug is intermittent (~30% rate on 0.125.0), so a single working call doesn't prove anything.

The Forge ships a PTY shim (since v5.22) that works around this. If you're hitting the symptom anyway:

1. **Confirm the shim is installed:**

   ```bash
   ls .claude/hooks/lib/codex-pty.sh        # Unix
   ls .claude/hooks/lib/codex-pty.ps1       # Windows
   ls .claude/hooks/lib/codex-pty-helper.py # required on Unix
   ```

   If any are missing: re-run `setup.sh --upgrade` (or `setup.ps1 -Upgrade`) from your local Forge checkout to install them. `--upgrade` preserves your existing settings.json + .mcp.json customizations while merging in new entries; `-f` would overwrite them.

2. **Confirm the runtime dependency:**

   ```bash
   python3 --version   # Unix — required for the helper
   winpty --help       # Windows Git Bash — recommended
   ```

3. **Confirm the templates were migrated** (they should reference the shim, not bare `codex exec`):

   ```bash
   grep "codex-pty.sh exec" .claude/commands/codex.md           # Should match
   grep "codex-pty.sh exec" .claude/skills/council/references/peer-review-protocol.md  # Should match
   ```

4. **Diagnose with the bypass env var:** if you suspect upstream has fixed the bug or want to compare behavior:

   ```bash
   CLAUDE_FORGE_CODEX_PTY_BYPASS=1 /codex review
   ```

   - If this now WORKS reliably across multiple runs, upstream has fixed it for your codex version. Mention this on issue #19945 and watch for the Forge's retirement canary (scheduled to run periodically and open a Stage 1 retirement PR when the bug is empirically clean).
   - If this STILL hangs/exits-empty, the shim is required — leave the env var unset.

5. **Cancellation note:** Ctrl-C should terminate `/codex` or `/council` cleanly within ~1 second (no orphan processes). If you see codex processes lingering after a cancel, check `ps -axo pid,command | grep codex-pty-helper` and report the version + reproducer. The shim's signal-handling path is regression-tested but cancellation under unusual stdio configurations could surface new edge cases.

> **Don't "rephrase the prompt"** to work around this. Prompt length is one of the bug's two triggers, not the trigger; rephrasing changes timing, not cause. Trust the shim.

## /simplify not working?

`/simplify` is a built-in Claude Code command (v2.1.63+). If unavailable, update Claude Code or use the `code-simplifier` agent from `pr-review-toolkit` as a fallback.
