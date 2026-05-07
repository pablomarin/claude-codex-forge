# Getting Started

> **Two setup steps:** global (once per machine) and project (once per project). Global setup MUST come first — it installs the memory system all projects share.

## Prerequisites

### macOS / Linux

- **Claude Code** installed and working (`claude --version`)
- **Node.js 22+** (for Codex CLI, npx commands, and Playwright MCP)
- **Git 2.23+** initialized in your project
- **jq** (recommended, not required): `brew install jq` (macOS) or `apt install jq` (Linux). Used for JSON merging during global setup (falls back to Python if unavailable). Hooks work without it.
- **Codex CLI** (**required** for the full workflow): `npm i -g @openai/codex` or `brew install --cask codex` (macOS). Powers the first-pass code review (`/codex review`), design review, and 3 of the 5 Engineering Council roles (chairman + 2 advisors). Without it, those steps degrade to manual user review. See [Step 5](#step-5-install-codex-cli-required) for full instructions.
- **Python 3.12+** with `uv` (if Python project)
- **pnpm** or **npm** (if JavaScript/TypeScript project)

### Windows

- **Claude Code** installed and working (`claude --version`)
- **WSL2** (recommended for Codex CLI): `wsl --install` from elevated PowerShell
- **PowerShell 5.1+** (included with Windows 10/11)
- **Node.js 22+** (for Codex CLI, npx commands, and Playwright MCP)
- **Git 2.23+** initialized in your project
- **Codex CLI** (**required** for the full workflow): `npm i -g @openai/codex` inside WSL. Powers the first-pass code review, design review, and 3 of the 5 Engineering Council roles. Without it, those steps degrade to manual user review. See [Step 5](#step-5-install-codex-cli-required) for full instructions.
- **Python 3.12+** with `uv` (if Python project)
- **pnpm** or **npm** (if JavaScript/TypeScript project)

> **Note:** Windows does NOT require `jq` — PowerShell has native JSON support via `ConvertFrom-Json`.
>
> **Note:** Codex CLI works best via WSL2 on Windows. Native Windows support is experimental. See [OpenAI's Windows guide](https://developers.openai.com/codex/windows/).

---

## Step 1: Clone this repo (once per machine)

**macOS / Linux:**

```bash
git clone https://github.com/pablomarin/claude-codex-forge.git ~/claude-codex-forge
chmod +x ~/claude-codex-forge/setup.sh
```

**Windows (PowerShell):**

```powershell
git clone https://github.com/pablomarin/claude-codex-forge.git $HOME\claude-codex-forge
```

## Step 2: Global setup (once per machine)

This installs Claude's memory system so it remembers things across ALL your projects.

**macOS / Linux:**

```bash
~/claude-codex-forge/setup.sh --global
```

**Windows (PowerShell):**

```powershell
& $HOME\claude-codex-forge\setup.ps1 -Global
```

## Step 3: Project setup (once per project)

```bash
cd /path/to/your/project
~/claude-codex-forge/setup.sh -p "My Project"
```

For tech-specific scenarios (new project, existing project with/without Claude Code, upgrading) see [Setup Scenarios](guides/setup-scenarios.md).

## Step 4: Install the Superpowers plugin (once per machine)

Start Claude Code and install Superpowers from Anthropic's official marketplace:

```bash
claude
```

Then inside Claude Code:

```
/plugin install superpowers@claude-plugins-official
```

Restart Claude Code.

> **Note:** `pr-review-toolkit` and `frontend-design` are built-in Claude Code plugins pre-enabled in `.claude/settings.json`. `/simplify` is a built-in Claude Code command (no plugin needed). `superpowers` requires a separate install (step above).
>
> **Why the official marketplace?** Same plugin, but `superpowers@claude-plugins-official` (Anthropic-curated since 2026-01-15) installs in one step with no `marketplace add` prerequisite. The community `superpowers@superpowers-marketplace` works too, but [obra/superpowers-marketplace#11](https://github.com/obra/superpowers-marketplace/issues/11) documents an upstream Claude Code plugin-name-conflict bug that surfaces when both identities exist on the same machine.

## Step 5: Install Codex CLI (required)

Codex CLI is **required for the full workflow**. It powers three core phases:

- **Design review** — independent validation of your plan before any code is written
- **First-pass code review** (`/codex review`) — runs before the deep `/pr-review-toolkit:review-pr` pass
- **Engineering Council** — Codex is the chairman plus 2 of the 5 advisor roles (3 total)

Without Codex, those phases degrade to manual user review. The workflow still runs, but you lose the independent second opinion that catches issues Claude missed.

**macOS / Linux:**

```bash
# Option A: npm (requires Node.js 22+)
npm install -g @openai/codex

# Option B: Homebrew (macOS only — no Node.js dependency)
brew install --cask codex
```

**Windows (via WSL2 — recommended):**

```bash
# Inside WSL:
npm install -g @openai/codex
```

> **Windows note:** Native Windows support is experimental. OpenAI recommends WSL2 for the best experience. See [Codex Windows guide](https://developers.openai.com/codex/windows/) for details.

**Authenticate (all platforms):**

```bash
codex          # Opens browser to sign in (requires ChatGPT Plus/Pro/Business/Enterprise)
```

Or with an API key:

```bash
codex login --with-api-key
```

**Verify:**

```bash
codex --version   # Should show version 0.101.0+
```

> **No Codex available?** The workflow still runs — Claude presents design plans to you for manual review, and the `/codex review` and Engineering Council steps fall back to user-led review. You lose the independent second opinion but nothing is blocked.

## Step 6: Verify setup

Inside Claude Code, run:

```
/hooks       → Should show: SessionStart, Stop, PreToolUse, PostToolUse, PreCompact, SubagentStop, ConfigChange
/help        → Should show: /superpowers:*, /new-feature, /fix-bug, /prd:*
/memory      → Should show your auto memory directory
```

**Done!** Now use `/new-feature my-feature` to start your first guided workflow. See [Workflow Overview](explanation/workflow.md) for the full process and [Commands Reference](reference/commands.md) for all available commands.

---

## Upgrading (existing projects)

Already have the templates installed? Pull the latest and upgrade:

```bash
cd ~/claude-codex-forge && git pull
cd /path/to/your/project
~/claude-codex-forge/setup.sh --upgrade
```

This updates all hooks, commands, and rules while safely merging new settings into your existing `settings.json` and `.mcp.json`. Your customizations are preserved. See [Upgrading](guides/upgrading.md) for details.

---

## Next

- [Setup scenarios](guides/setup-scenarios.md) — New project, existing project, or upgrading
- [Customize your project](guides/customize-project.md) — CLAUDE.md, `.claude/local/state.md`, optional MCP add-ons
- [Parallel development](guides/parallel-sessions.md) — Multiple sessions via git worktrees
- [Multi-project isolation](guides/multi-project-isolation.md) — How `uv` / `pnpm` / worktrees keep projects separate, and why `setup.sh` does a warn-only interpreter preflight
- [Troubleshooting](troubleshooting.md) — If something's not working
