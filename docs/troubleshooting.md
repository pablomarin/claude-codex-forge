# Troubleshooting

Common issues and their solutions.

## Setup script says files already exist

This is expected when Forge finds protected user content or existing host adapters. Use the
authoritative preview first:

```bash
~/claude-codex-forge/setup.sh -F --dry-run
```

```powershell
& $HOME\claude-codex-forge\setup.ps1 -FullRefresh -DryRun
```

Resolve every named blocker, then rerun without the dry-run flag. Full refresh reconciles only
ownership-proven Forge content and preserves user text outside managed blocks.

## Full-refresh preview says `UPGRADE: BLOCKED`

This is a safety result, not a partial installation. Preview writes no target files and prints all
known blockers together. Common groups are:

- `ROOT_POLICY_AMBIGUOUS`: remove only obsolete project-owned v5 references; keep neutral project
  context.
- `CUSTOM_HARNESS_COLLISION`: explicitly keep the independently developed harness, or archive it
  and remove its active registrations before adopting Forge v6.
- `MULTIPLE_STATE_SOURCES`: compare the reported hashes/timestamps, choose one state, and archive
  the non-selected copy.
- `LEGACY_FILE_MODIFIED` / `LEGACY_ALIAS_AMBIGUOUS`: restore exact released bytes or archive and
  remove that active legacy surface; Forge will not guess ownership.

Rerun preview until it says `UPGRADE: READY`; execution should finish with `ACTIVE_FORGE: v6`.
`MATERIALIZED` can still coexist with a per-host `RUNTIME_READY: BLOCKED` diagnostic—for example,
an overlapping enabled plugin or missing host authentication. Resolve that host diagnostic without
manually duplicating policy between `CLAUDE.md` and `AGENTS.md`.

## Memory not persisting?

1. Confirm the canonical project layers exist:

   ```bash
   ls .forge/local/memory/   # volatile, per-developer/worktree
   ls .forge/memory/         # durable, project-owned
   ```

2. Keep current progress in `.forge/local/state.md`, not either memory layer.

3. Remember that Claude Code and Codex native private memories are optional and are not
   synchronized. Promote a vetted cross-host learning through a reviewed change in `.forge/memory/`.

## Hooks not running?

### macOS / Linux

1. **Check script is executable:**

   ```bash
   ls -la .forge/hooks/
   # Should show -rwxr-xr-x for all .sh files
   ```

2. **Check settings.json is valid:**

   ```bash
   cat .claude/settings.json | jq .
   # Should parse without errors
   ```

   For Codex, also validate `.codex/hooks.json` with `jq .`.

   If setup reports `CODEX_HOOKS: BLOCKED`, resolve the printed trust or registration reason and
   rerun the authoritative full refresh; do not hand-edit the managed registration.

3. **Check jq is installed (recommended):**

   ```bash
   which jq
   # Should output path like /usr/bin/jq
   # Note: hooks will work without jq but some features are reduced
   ```

4. **Restart the affected host** — hooks snapshot at session start

### Windows

1. **Check PowerShell execution policy:**

   ```powershell
   Get-ExecutionPolicy
   # If "Restricted", run:
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

2. **Check hook scripts exist:**

   ```powershell
   Test-Path .forge\hooks\session-start.ps1
   Test-Path .forge\hooks\check-state-updated.ps1
   Test-Path .forge\hooks\post-tool-format.ps1
   Test-Path .forge\hooks\pre-compact-memory.ps1
   # All should return True
   ```

3. **Test hook script manually:**

   ```powershell
   echo '{"stop_hook_active": false}' | powershell -File .forge\hooks\check-state-updated.ps1
   # Should run without errors
   ```

4. **Check settings.json is valid:**

   ```powershell
   Get-Content .claude\settings.json | ConvertFrom-Json
   # Should parse without errors
   ```

5. **Restart the affected host** — hooks snapshot at session start

## Drift detection messages — what they mean

The SessionStart hook and `/new-feature` / `/fix-bug` Pre-Flight surface a few advisory messages tied to default-branch detection. None of them block (with one exception noted below); they're diagnostic hints.

### `default-branch helper bailed; assuming 'main'`

The helper at `.forge/hooks/lib/default-branch.{sh,ps1}` couldn't detect the default branch from cached refs. This is a fallback to `main` — wrong on `master`-default repos. Causes:

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

## Legacy v5 migration history and the current state file

The 5.14 → 5.15 [CONTINUITY split](guides/upgrading.md#migrating-from-continuitymd-514--515)
originally used `.claude/local/state.md`; that path is legacy history. Forge v6 owns current volatile
state at `.forge/local/state.md`.

### `ℹ check-state-updated: state.md not found` breadcrumb

You ran a host turn or tried to `git commit` and saw a friendly stderr breadcrumb pointing at the
migration path. Current hooks read **only** `.forge/local/state.md`; they never treat legacy
`CONTINUITY.md` or `.claude/local/state.md` as current certifying state. The breadcrumb fires when:

1. The repo has a legacy `CONTINUITY.md` at the root and `.forge/local/state.md` is missing.
2. `.forge/local/` was wiped (for example by an aggressive `git clean -fdx`).

**Fix:**

```bash
# Option A — run the migration assistant (preferred if you have legacy content):
~/claude-codex-forge/setup.sh --migrate

# Option B — authoritative v6 refresh (if there's nothing to migrate):
~/claude-codex-forge/setup.sh -F --dry-run
~/claude-codex-forge/setup.sh -F
```

Both options preserve existing `.forge/local/state.md` content.

### Dangling `@CONTINUITY.md` import in `CLAUDE.md`

If your `CLAUDE.md` still has a `@CONTINUITY.md` line at the top (the pre-5.15 default), Claude Code will silently fail to find the target — `@`-imports do not error on missing files. The migration assistant **detects but does not auto-edit** this; it prints a warning telling you the line is dangling.

**Fix:** delete the line yourself.

```diff
-@CONTINUITY.md
-
 # CLAUDE.md - my-project
```

You don't need to replace it with anything. The v5 `.claude/local/state.md` path was intentionally
not imported; v6 preserves that design at `.forge/local/state.md`, which hooks read on demand (see
[`docs/adr/0001-volatile-state-not-auto-loaded.md`](adr/0001-volatile-state-not-auto-loaded.md)).

### `setup.sh --migrate` says "nothing to migrate" but I have a `CONTINUITY.md`

The migration assistant uses sentinel markers in each destination to detect already-migrated content, so re-runs are no-ops. If you've already run `--migrate` once, subsequent invocations will skip every section and report nothing to do — that's correct behavior, not a bug. Verify by reading the destinations:

```bash
grep -A1 "^### Goal" CLAUDE.md
ls docs/adr/
cat .forge/local/state.md
```

If those look right, the migration succeeded. Re-running is safe.

### I want to start migration over

The original `CONTINUITY.md` is preserved byte-for-byte and never modified by `--migrate`, so you can roll forward at any time. To re-do migration from a clean slate:

```bash
# Remove the migrated outputs (KEEP CONTINUITY.md — it's the source)
rm -i .forge/local/state.md
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
       "superpowers@claude-plugins-official": true,
       "pr-review-toolkit@claude-plugins-official": true,
       "frontend-design@claude-plugins-official": true
     }
   }
   ```

3. **Restart Claude Code** after enabling plugins

4. **Try reinstalling:**
   ```
   /plugin uninstall superpowers@claude-plugins-official
   /plugin install superpowers@claude-plugins-official
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

> **If the other engine is unavailable**, reviewer launch visibly falls back to a fresh same-engine
> reviewer. Council starts one all-main attempt, including a fresh chairman.

## A Codex-backed opinion or `/council` returns empty output

This is [openai/codex#19945](https://github.com/openai/codex/issues/19945) — a `codex exec` regression on 0.124.0+ where it silently exits with empty stdout when stdio is detached from a TTY AND the prompt is non-trivial. Both conditions fire whenever Claude Code's Bash tool spawns codex. The bug is intermittent (~30% rate on 0.125.0), so a single working call doesn't prove anything.

The Forge ships a PTY shim (since v5.22) that works around this. If you're hitting the symptom anyway:

1. **Confirm the shim is installed:**

   ```bash
   ls .forge/hooks/lib/codex-pty.sh        # Unix
   ls .forge/hooks/lib/codex-pty.ps1       # Windows
   ls .forge/hooks/lib/codex-pty-helper.py # required on Unix
   ```

   If any are missing, preview with `setup.sh -F --dry-run` (or
   `setup.ps1 -FullRefresh -DryRun`) from your local Forge checkout. Execute the same full-refresh
   command without the dry-run flag only after `UPGRADE: READY`; it reconciles ownership-proven
   canonical files and generated adapters.

2. **Confirm the runtime dependency:**

   ```bash
   python3 --version   # Unix — required for the helper
   winpty --help       # Windows Git Bash — recommended
   ```

3. **Confirm the templates were migrated** (they should reference the shim, not bare `codex exec`):

   ```bash
   grep "codex-pty.sh" .forge/hooks/lib/agent-dispatch.sh       # Should match
   grep "codex-pty.sh exec" .forge/skills/council/references/peer-review-protocol.md  # Should match
   ```

4. **Diagnose with the bypass env var:** if you suspect upstream has fixed the bug or want to compare behavior:

   ```bash
   export CLAUDE_FORGE_CODEX_PTY_BYPASS=1
   # Then run Claude /opinion or Codex $opinion, matching the active host.
   ```

   - If this now WORKS reliably across multiple runs, upstream has fixed it for your codex version. Mention this on issue #19945 and watch for the Forge's retirement canary (scheduled to run periodically and open a Stage 1 retirement PR when the bug is empirically clean).
   - If this STILL hangs/exits-empty, the shim is required — leave the env var unset.

5. **Cancellation note:** Ctrl-C should terminate a Codex-backed opinion or `/council` call cleanly.
   If Codex processes linger, check `ps -axo pid,command | grep codex-pty-helper` and report the
   version + reproducer.

> **Don't "rephrase the prompt"** to work around this. Prompt length is one of the bug's two triggers, not the trigger; rephrasing changes timing, not cause. Trust the shim.

## /simplify not working?

`/simplify` is a built-in Claude Code command (v2.1.63+). If unavailable, update Claude Code or use the `code-simplifier` agent from `pr-review-toolkit` as a fallback.
