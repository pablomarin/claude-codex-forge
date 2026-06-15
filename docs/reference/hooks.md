# Hooks Reference

Hooks run automatically without manual intervention. Seven hook events configured across global and project scopes.

## Hooks (Run Automatically)

| Hook             | Trigger                                   | What Happens                                                                                                                                                                                                                                                                  | Scope            |
| ---------------- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| `SessionStart`   | New session, resume, `/clear`, compaction | Silently injects branch + drift status via `additionalContext` (source-gated: `git fetch` + behind-warning runs only on `startup`/`resume`, not on `clear`/`compact`; cannot block — exit 2 is advisory)                                                                      | Project          |
| `Stop` (global)  | Claude finishes responding                | No-op pass-through (`exit 0`) — memory saving handled by PreCompact                                                                                                                                                                                                           | Global           |
| `Stop` (project) | Claude finishes responding                | Advisory: extracts active workflow Command/Phase/Next from `.claude/local/state.md` and prints a reminder. During active `/goal` sessions, emits `FORGE_GOAL_EVIDENCE`; outside `/goal`, evidence output is suppressed to keep context lean. Also gates `docs/CHANGELOG.md` updates when 4+ files have changed (blocks via exit 2). | Project          |
| `PreToolUse`     | Before every Bash command                 | Logs commands to audit log, blocks dangerous patterns (pipe-to-shell, etc.). `check-workflow-gates.sh` reads only `.claude/local/state.md`; if missing, prints a friendly stderr breadcrumb pointing at `setup.sh --migrate` and exits 0 (no fallback to legacy state files). | Project          |
| `PostToolUse`    | After Edit/Write on code files            | Auto-formats with ruff (Python) / prettier (JS/TS/JSON/Markdown)                                                                                                                                                                                                              | Project          |
| `PreCompact`     | Before context compression                | Reminds Claude to save learnings before context compression (blocks until done)                                                                                                                                                                                               | Global + Project |
| `SubagentStop`   | Subagent finishes                         | Validates subagent output quality                                                                                                                                                                                                                                             | Project          |
| `ConfigChange`   | Config file modified mid-session          | Logs changes to audit log; optional strict mode blocks deny-rule removals                                                                                                                                                                                                     | Project          |

## How Global and Project Hooks Interact

Global hooks (`~/.claude/settings.json`) and project hooks (`.claude/settings.json`) **both run**. They don't conflict — they complement each other:

- **Global Stop hook**: No-op (`exit 0`) — memory saving handled by PreCompact and CLAUDE.md rules
- **Project Stop hook**: Advisory reminder — extracts the active workflow row from `.claude/local/state.md` and nudges Claude to keep state current. `build-evidence` emits goal evidence only when `.claude/local/state.md` has an active UUID-shaped `/goal` nonce. Still gates `docs/CHANGELOG.md` when 4+ tracked files have changed without a CHANGELOG update (exit 2). State-update gating moved entirely to PreToolUse so a gitignored state file no longer breaks the porcelain check.
- **Global PreCompact hook**: Command that blocks with memory save reminder (`exit 2` + stderr)
- **Project PreCompact hook**: Command reminder + project-specific context script

## Workflow Gates

Beyond the hooks above, `check-workflow-gates.sh` blocks **commit/push/PR** until the workflow checklist in `.claude/local/state.md` contains the required markers (`Code review loop`, `Simplified`, `Verified`). The hook reads only `.claude/local/state.md` — if the file is missing, it prints a friendly stderr breadcrumb pointing at `setup.sh --migrate` and exits 0 (it never falls back to legacy state files). This is the real "discipline enforcement" hook — it refuses to let you ship until the quality loop has run.
