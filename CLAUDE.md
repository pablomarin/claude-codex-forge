<!-- forge:migrated 2026-04-28 -->

# CLAUDE.md - claude-codex-forge

## Project Overview

### What Is This?

A production-grade template toolkit that transforms Claude Code from a simple coding assistant into an autonomous, memory-aware software engineering system. It provides enforced workflows, persistent memory, coding standards, and quality gates — all installed via a single `setup.sh` script.

### Tech Stack

- **Scripts:** Bash (setup.sh) + PowerShell (setup.ps1) — cross-platform installers
- **Config:** JSON (settings, MCP) + Markdown (commands, rules, templates)
- **Hooks:** Bash (.sh) + PowerShell (.ps1) — auto-run quality gates
- **No runtime dependencies** — pure config/scripts, no build step

### File Structure

```
claude-codex-forge/
├── setup.sh                    # Unix installer (main entry point)
├── setup.ps1                   # Windows installer (PowerShell)
├── README.md                   # Documentation for the community
│
├── CLAUDE.template.md          # Template → project CLAUDE.md
├── state.template.md           # Template → .claude/state.template.md (always-refresh) and .claude/local/state.md (gitignored, never overwritten)
├── GLOBAL-CLAUDE.template.md   # Template → ~/.claude/CLAUDE.md
├── mcp.template.json           # Template → project .mcp.json
│
├── commands/                   # Workflow commands (copied to .claude/commands/)
│   ├── new-feature.md          # Full feature lifecycle
│   ├── fix-bug.md              # Systematic debugging workflow
│   ├── quick-fix.md            # Trivial changes (< 3 files)
│   ├── finish-branch.md        # Merge PR + cleanup worktree
│   ├── codex.md                # Second opinion from Codex CLI
│   ├── review-pr-comments.md   # Process PR review feedback
│   └── prd/                    # PRD subcommands
│       ├── discuss.md          # Interactive requirements refinement
│       └── create.md           # Generate structured PRD
│
├── rules/                      # Coding standards (copied to .claude/rules/)
│   ├── principles.md           # Core philosophy (KISS, DRY, composition)
│   ├── workflow.md             # Decision matrix for command choice
│   ├── critical-rules.md       # Non-negotiable rules
│   ├── worktree-policy.md      # Git worktree isolation
│   ├── memory.md               # Persistent memory usage
│   ├── security.md             # Auth, secrets, SQL injection
│   ├── testing.md              # AAA pattern, fixtures, E2E
│   ├── api-design.md           # REST conventions, error format
│   ├── python-style.md         # Python-specific conventions
│   ├── typescript-style.md     # TypeScript-specific conventions
│   ├── database.md             # SQLAlchemy patterns, naming
│   ├── frontend-design.md      # UI/UX standards
│   └── skill-audit.md          # Third-party skill security checklist
│
├── hooks/                      # Hook scripts (copied to .claude/hooks/)
│   ├── lib/                         # Shared helpers sourced/called by other hooks
│   │   ├── default-branch.sh/.ps1   # Detect repo's default branch (origin/HEAD → main → master)
│   │   ├── codex-pty.sh/.ps1        # PTY shim for `codex exec` — works around openai/codex#19945 (silent empty exit when stdio detached from TTY)
│   │   └── codex-pty-helper.py      # Python helper: pty.fork + waitpid loop (avoids 3.9 pty.spawn macOS hang)
│   ├── session-start.sh/.ps1        # SessionStart: silent context injection (branch + drift warning)
│   ├── check-state-updated.sh/.ps1  # Stop: advisory state reminder + CHANGELOG threshold gate
│   ├── check-bash-safety.sh/.ps1    # PreToolUse: audit log + block dangerous patterns
│   ├── check-workflow-gates.sh/.ps1 # PreToolUse: block commit/push/PR if quality gates incomplete
│   ├── auto-approve-local-writes.sh/.ps1  # PermissionRequest: auto-approve Write/Edit on .claude/local/** (workaround for CC v2.1.80+ regression)
│   ├── post-tool-format.sh/.ps1     # PostToolUse: auto-format on save
│   ├── pre-compact-memory.sh/.ps1   # PreCompact: save learnings before compression
│   └── check-config-change.sh/.ps1  # ConfigChange: log config modifications
│
├── skills/                     # Skill templates (copied to .claude/skills/)
│   ├── SKILL.template.md      # Template for creating custom skills
│   ├── ui-design/             # UI Design skill (three-mode router, auto-triggers)
│   │   ├── SKILL.template.md  # Core: mode selection + design rules per mode
│   │   └── references/        # 10 reference guides (loaded on demand)
│   │       ├── 21st-dev-components.md
│   │       ├── animation-techniques.md
│   │       ├── industry-design-guide.md
│   │       ├── landing-patterns.md
│   │       ├── media-assets.md
│   │       ├── polish-checklist.md
│   │       ├── product-ui-patterns.md
│   │       ├── trust-first-patterns.md
│   │       ├── typography-and-color.md
│   │       └── ux-antipatterns.md
│   ├── generate-image/        # Image generation via Gemini API (checks docs first)
│   │   └── SKILL.template.md  # Script-based generation, no MCP dependency
│   ├── release/               # Release PR creator (dev→test, test→prod)
│   │   └── SKILL.template.md  # Environment promotion with categorized changelogs
│   └── council/               # Engineering Council (multi-perspective decisions)
│       ├── SKILL.template.md  # Orchestrator: dispatch, gate, synthesis
│       └── references/        # 3 reference guides (loaded on demand)
│           ├── advisors.md              # 5 advisor profiles with engine assignments
│           ├── output-schema.md         # Structured output for advisors + chairman
│           └── peer-review-protocol.md  # Dispatch, escalation, minority report rules
│
├── agents/                     # Subagent definitions (copied to .claude/agents/)
│   ├── verify-app.md           # Full verification: tests + lint + types
│   ├── verify-e2e.md           # E2E user-journey testing: API + UI + CLI
│   ├── research-first.md       # Pre-design library/API research
│   └── council-advisor.md      # Generic council advisor (persona via prompt)
│
├── settings/                   # Settings templates
│   ├── settings.template.json          # Project-level (plugins, permissions, hooks)
│   ├── global-settings.template.json   # Global-level (hooks only, merged)
│   └── settings-windows.template.json  # Windows variant
│
├── docs/adr/                   # Architecture Decision Records (seed set ships with harness)
│   ├── template.md                     # Canonical 5-section ADR template
│   ├── README.md                       # Index + authoring conventions
│   ├── 0001-volatile-state-not-auto-loaded.md
│   ├── 0002-bash-and-powershell-dual-platform.md
│   ├── 0003-template-distributed-no-build-step.md
│   ├── 0004-diataxis-docs-structure.md
│   └── 0005-hard-platform-parity-rule.md
│
├── scripts/                    # Forge-internal helpers (NOT shipped to downstream installs)
│   ├── migrate-continuity.sh           # `setup.sh --migrate` — legacy CONTINUITY.md → state.md + ADRs
│   └── migrate-continuity.ps1          # PowerShell mirror
│
└── templates/
    ├── playwright/
    │   ├── playwright.config.template.ts    # Playwright framework config
    │   ├── auth.fixture.template.ts         # Auth bypass pattern
    │   ├── example.spec.template.ts         # Reference spec scaffold (Phase 6.2c)
    │   └── README.md
    └── ci-workflows/
        ├── e2e.yml                          # GitHub Actions workflow (reference, not auto-activated)
        └── README.md
```

### Key Commands

```bash
# Testing changes to the template
./setup.sh -p "Test" -t fullstack      # Test full setup in current dir
./setup.sh -p "Test" -t python         # Test Python-only setup
./setup.sh -p "Test" -f                # Test force-overwrite mode
./setup.sh --global                    # Test global setup

# Workflows (MANDATORY - hooks enforce these)
/new-feature <name>     # Full feature workflow
/fix-bug <name>         # Bug fix with systematic debugging
/quick-fix <name>       # Trivial changes only (< 3 files)
/finish-branch          # Merge PR + cleanup worktree
```

---

## Critical Conventions

### Template → Generated File Mapping

Templates in the root are **source of truth**. `setup.sh` copies them to target projects:

| Template (edit this)                      | Generated file (never edit directly)                                                                                        |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `CLAUDE.template.md`                      | `CLAUDE.md` in target project                                                                                               |
| `state.template.md`                       | `.claude/state.template.md` in target project (always-refresh) AND `.claude/local/state.md` (gitignored, never overwritten) |
| `GLOBAL-CLAUDE.template.md`               | `~/.claude/CLAUDE.md`                                                                                                       |
| `mcp.template.json`                       | `.mcp.json` in target project                                                                                               |
| `settings/settings.template.json`         | `.claude/settings.json` in target project                                                                                   |
| `commands/*.md`                           | `.claude/commands/*.md` in target project                                                                                   |
| `rules/*.md`                              | `.claude/rules/*.md` in target project                                                                                      |
| `hooks/*`                                 | `.claude/hooks/*` in target project                                                                                         |
| `hooks/lib/default-branch.sh`             | `.claude/hooks/lib/default-branch.sh` in target project                                                                     |
| `hooks/lib/default-branch.ps1`            | `.claude/hooks/lib/default-branch.ps1` in target project                                                                    |
| `hooks/lib/codex-pty.sh`                  | `.claude/hooks/lib/codex-pty.sh` in target project                                                                          |
| `hooks/lib/codex-pty.ps1`                 | `.claude/hooks/lib/codex-pty.ps1` in target project                                                                         |
| `hooks/lib/codex-pty-helper.py`           | `.claude/hooks/lib/codex-pty-helper.py` in target project                                                                   |
| `skills/ui-design/SKILL.template.md`      | `.claude/skills/ui-design/SKILL.md` in target                                                                               |
| `skills/ui-design/references/*.md`        | `.claude/skills/ui-design/references/*.md`                                                                                  |
| `skills/generate-image/SKILL.template.md` | `.claude/skills/generate-image/SKILL.md`                                                                                    |
| `skills/release/SKILL.template.md`        | `.claude/skills/release/SKILL.md` in target                                                                                 |
| `skills/council/SKILL.template.md`        | `.claude/skills/council/SKILL.md` in target                                                                                 |
| `skills/council/references/*.md`          | `.claude/skills/council/references/*.md`                                                                                    |
| `agents/verify-app.md`                    | `.claude/agents/verify-app.md` in target project                                                                            |
| `agents/verify-e2e.md`                    | `.claude/agents/verify-e2e.md` in target project                                                                            |
| `agents/research-first.md`                | `.claude/agents/research-first.md` in target project                                                                        |
| `agents/council-advisor.md`               | `.claude/agents/council-advisor.md` in target                                                                               |
| `templates/playwright/*.ts`               | `playwright.config.ts`, `tests/e2e/fixtures/auth.ts` (only with `--with-playwright`)                                        |
| `templates/ci-workflows/*`                | `docs/ci-templates/*` (only with `--with-playwright` — NOT auto-activated to `.github/workflows/`)                          |

### Platform Parity

Every hook has both `.sh` (Unix) and `.ps1` (Windows) versions. **Always update both** when changing hook logic. Same for `setup.sh` / `setup.ps1`.

### setup.sh Behavior

- `copy_file()` skips existing files unless `-f` (force) is passed
- `CLAUDE.md` and `.claude/local/state.md` (gitignored) are **never overwritten** even with `-f` — they're user content
- A legacy `CONTINUITY.md` (from pre-PR-#2 installs) is also never overwritten; setup prompts the user to run `--migrate` to move its content into `CLAUDE.md` (durable) + `docs/adr/` (decisions) + `.claude/local/state.md` (volatile)
- `.claude/state.template.md` is **always refreshed** (it's the canonical template, not user content)
- Rules, commands, hooks, and settings CAN be safely refreshed with `-f`
- `-t python|typescript|fullstack` controls which language-specific rules are copied

### Hook Design

- **SessionStart hooks** (`session-start.sh`): Output JSON with `hookSpecificOutput.additionalContext` for silent context injection. Source-gated: drift-detection fetch fires only on `startup`/`resume` subtypes, not `clear`/`compact`. Cannot block (exit 2 is advisory) — drift surfaces as a warning string in additionalContext only.
- **Stop hooks** (`check-state-updated.sh`): Use `exit 2` + stderr message to block
- **PreToolUse hooks** (`check-bash-safety.sh`): Audit log + `exit 2` to block dangerous Bash patterns
- **PermissionRequest hooks** (`auto-approve-local-writes.sh`): Output `hookSpecificOutput.decision.behavior=allow` to skip prompt; fires only when CC is about to show a permission dialog. Used to work around CC v2.1.80+ regression on path-scoped allow rules. Fail-open: print nothing on parse error or path-validation failure. Opt-out via `CLAUDE_FORGE_AUTO_APPROVE_LOCAL_WRITES=0`.
- **PostToolUse hooks**: Match file extensions, run formatters, `exit 0` always
- **PreCompact hooks**: Use `exit 0` (non-blocking) — just reminders
- **ConfigChange hooks** (`check-config-change.sh`): Log config changes, optional `exit 2` strict mode
- Prompt-type hooks must return `{"ok": true}` or `{"ok": false, "reason": "..."}`

---

## Detailed Rules

All coding standards, workflow rules, and policies are in `.claude/rules/`.
These files are auto-loaded by Claude Code with the same priority as this file.

**What's in `.claude/rules/`:**

- `principles.md` — Top-level principles and design philosophy
- `workflow.md` — Decision matrix for choosing the right command
- `worktree-policy.md` — Git worktree isolation rules
- `critical-rules.md` — Non-negotiable rules (branch safety, TDD, etc.)
- `memory.md` — How to use persistent memory and save learnings
- `security.md`, `testing.md`, `api-design.md` — Coding standards
- Language-specific: `python-style.md`, `typescript-style.md`, `database.md`, `frontend-design.md`
