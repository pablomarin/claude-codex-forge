<p align="center">
  <img src="docs/images/hero.png" alt="Claude and Codex — two AI coding agents shaping the work through a 7-phase workflow (PRD → Research → Design → Review → Build → Verify → Ship) held together by an engineering harness" width="720">
</p>

<h1 align="center">Claude Codex Forge</h1>

<p align="center">
  <strong>An engineering harness for disciplined software building — powered by two coding agents.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green?style=flat-square"></a>
  <a href="#version-history"><img alt="Version" src="https://img.shields.io/badge/version-5.22-blue?style=flat-square"></a>
  <a href="docs/getting-started.md"><img alt="Platform" src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey?style=flat-square"></a>
  <a href="https://code.claude.com"><img alt="Claude Code" src="https://img.shields.io/badge/Claude_Code-enabled-purple?style=flat-square"></a>
  <a href="https://developers.openai.com/codex/"><img alt="Codex CLI" src="https://img.shields.io/badge/Codex_CLI-required-orange?style=flat-square"></a>
</p>

<p align="center">
  <a href="docs/getting-started.md">Quick Start</a>
  ·
  <a href="docs/reference/commands.md">Commands</a>
  ·
  <a href="docs/explanation/workflow.md">Workflow</a>
  ·
  <a href="docs/explanation/harness-philosophy.md">Philosophy</a>
  ·
  <a href="docs/troubleshooting.md">Troubleshooting</a>
  ·
  <a href="docs/CHANGELOG.md">Changelog</a>
</p>

---

Claude Codex Forge combines **Claude Code** and **OpenAI's Codex** into a single workflow. Two agents beat one: Claude designs, Codex independently reviews, and the Engineering Council adjudicates when they disagree. What started as a set of workflow templates has grown — through continuous iteration — into a full engineering harness.

## What you get

- **Dual-agent review** — `/codex review` (independent second opinion) + `/council` (5-advisor panel with Codex chairman) catch issues one agent alone would miss. Two separately-trained models flag different concerns — disagreement is the signal.
- **Discipline by construction** — workflow commands bake in TDD, research-before-design, and E2E testing. Hooks block dangerous Bash, enforce state updates, and gate commit/push/PR on explicit quality markers.
- **Continuous memory** — auto-memory persists locally across sessions and compaction (rescued by the `PreCompact` hook); `docs/adr/`, `docs/CHANGELOG.md`, and `docs/solutions/` travel with the repo so every architecture decision, root cause, and pattern compounds across weeks and teammates via git. Per-developer Workflow / Done / Now / Next state lives in gitignored `.claude/local/state.md` — read by hooks on demand, kept out of Claude's auto-loaded context.
- **Team-scale by default** — one GitHub repo becomes the hub. Multiple developers run parallel Claude sessions via auto-created git worktrees, each isolated but with full project context.

## Quick start

**Prerequisites:** [Claude Code](https://code.claude.com/docs) · [Node.js 22+](https://nodejs.org) · Git 2.23+ · a [ChatGPT Plus/Pro/Business plan or OpenAI API key](https://developers.openai.com/codex/) for Codex CLI.

```bash
# 1. Clone this harness repo (once per machine)
git clone https://github.com/pablomarin/claude-codex-forge.git ~/claude-codex-forge
chmod +x ~/claude-codex-forge/setup.sh

# 2. Global setup once per machine (installs the memory system)
~/claude-codex-forge/setup.sh --global

# 3. Install Codex CLI + authenticate (required for dual-agent review)
npm install -g @openai/codex   # or: brew install --cask codex
codex login

# 4. Per-project setup
cd /path/to/your/project
~/claude-codex-forge/setup.sh -p "My Project"

# 5. Start Claude Code, install the Superpowers plugin, restart
claude
> /plugin marketplace add obra/superpowers-marketplace
> /plugin install superpowers@superpowers-marketplace

# 6. Restart Claude Code, then kick off your first workflow
> /new-feature my-feature
```

Full walkthrough with platform-specific (Windows/macOS/Linux) instructions, the "no Codex" fallback, and troubleshooting: **[Getting Started →](docs/getting-started.md)**

Windows users: [PowerShell instructions](docs/getting-started.md#windows).

### Running setup later

`setup.sh` is safe to re-run. Three modes:

| Command                         | Use case                                                                                                                                                                                                                                                                           |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `setup.sh -p "Name"` (no flags) | **First install** on a new project. Also safe to re-run later to fill in missing template files without disturbing anything that already exists.                                                                                                                                   |
| `setup.sh --upgrade`            | **Routine template updates** on an existing project. Refreshes hooks, commands, rules, and agents. **Merges** `.claude/settings.json` and `.mcp.json` so your customizations (permissions, plugins, extra MCP servers) are preserved. Creates a timestamped `.bak` before merging. |
| `setup.sh -f`                   | **Reset to template verbatim.** Overwrites `.claude/settings.json` and `.mcp.json` — wipes your customizations. No backup. Use only if your setup is corrupted or you've never customized anything.                                                                                |

`CLAUDE.md`, `.claude/local/state.md`, and `docs/CHANGELOG.md` are always preserved — the template initializes them on first install and never touches them afterward, regardless of flags. If you upgrade from a pre-5.15 install, your legacy state file is preserved too; run `setup.sh --migrate` when ready to split it into the three new artifacts.

Full flag reference: **[Upgrading guide →](docs/guides/upgrading.md)**

### Upgrading from a pre-5.15 install?

```bash
./setup.sh --upgrade   # picks up new files; preserves your existing CONTINUITY.md byte-for-byte
./setup.sh --migrate   # splits CONTINUITY.md into CLAUDE.md durable + docs/adr/ decisions + .claude/local/state.md volatile
```

See [`docs/guides/upgrading.md`](docs/guides/upgrading.md) for the full walkthrough including verifying the migration and removing the legacy `@CONTINUITY.md` import.

## How it works

One feature goes from idea to merged PR across 14 enforced phases — from PRD through research, dual-reviewer design loops, TDD execution, parallel code review, simplify + verify + E2E, compound learnings, and PR reviewer handling.

See **[the full workflow diagram](docs/explanation/workflow.md)** for the complete view, or jump straight to:

- **[Why a harness, not a template](docs/explanation/harness-philosophy.md)** — the two-agent design, discipline by construction, continuous memory
- **[Commands reference](docs/reference/commands.md)** — every slash command and subagent
- **[Hooks reference](docs/reference/hooks.md)** — seven hook events that keep discipline structural

## Documentation

| Topic                                                              | What's inside                                                               |
| ------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| **[Getting Started](docs/getting-started.md)**                     | Prerequisites, 6-step install, verify setup                                 |
| **[Setup Scenarios](docs/guides/setup-scenarios.md)**              | New project · existing project · upgrade                                    |
| **[Customize Your Project](docs/guides/customize-project.md)**     | CLAUDE.md · `.claude/local/state.md` · optional MCPs · automated PR reviews |
| **[Upgrading](docs/guides/upgrading.md)**                          | `--upgrade` mode, merge behavior, fresh-install alternative                 |
| **[Parallel Development](docs/guides/parallel-sessions.md)**       | Multiple sessions via git worktrees                                         |
| **[Playwright CI Bridge](docs/guides/playwright-ci-bridge.md)**    | `--with-playwright` scaffold for deterministic E2E in CI                    |
| **[Commands Reference](docs/reference/commands.md)**               | All slash commands and subagents                                            |
| **[Hooks Reference](docs/reference/hooks.md)**                     | Seven hook events + how they interact                                       |
| **[Permissions & Security](docs/reference/permissions.md)**        | Deny / ask / skip rules                                                     |
| **[File Structure](docs/reference/file-structure.md)**             | What setup creates and where                                                |
| **[Creating Skills](docs/reference/creating-skills.md)**           | Author your own slash commands                                              |
| **[Cheatsheet](docs/reference/cheatsheet.md)**                     | Copy-paste daily-workflow card                                              |
| **[Workflow (full)](docs/explanation/workflow.md)**                | 14-phase diagram with rationale                                             |
| **[Harness Philosophy](docs/explanation/harness-philosophy.md)**   | Why dual-agent, why discipline, why continuous memory                       |
| **[Memory Architecture](docs/explanation/memory-architecture.md)** | Global + project + auto-memory layers                                       |
| **[Troubleshooting](docs/troubleshooting.md)**                     | Memory · hooks · permissions · MCP · plugins · Codex                        |

## Concrete guarantees

The pillars above cash out in specific, repo-verifiable behavior:

- **Compaction rescue** — `PreCompact` hook flushes session learnings to auto-memory _before_ context compression, so nothing is dropped silently
- **Review ordering enforced** — `/codex review` runs _first_ as an independent pass, then `/pr-review-toolkit:review-pr` (6 deep agents), then `/simplify`, then post-PR `/review-pr-comments`. Commits are blocked until quality markers are present.
- **Worktree isolation** — `/new-feature` and `/fix-bug` auto-create git worktrees so parallel Claude sessions never share filesystem state
- **E2E for user-facing changes** — `verify-e2e` subagent replays `tests/e2e/use-cases/*.md` as a growing regression suite; optional `--with-playwright` scaffolds deterministic `.spec.ts` for contributor PRs in CI

## Version history

Recent releases:

| Version | Date       | Highlights                                                                                                                                                                                                                                 |
| ------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 5.22    | 2026-05-01 | Codex PTY shim — `.claude/hooks/lib/codex-pty.{sh,ps1}` works around [openai/codex#19945](https://github.com/openai/codex/issues/19945) (silent empty exit when `codex exec` runs without a TTY); migrated `/codex` + `/council` callsites |
| 5.21    | 2026-04-30 | PermissionRequest hook auto-approves writes to `.claude/local/**` (workaround for CC v2.1.80+ regression on path-scoped rules)                                                                                                             |
| 5.20    | 2026-04-29 | Bump Codex CLI model `gpt-5.4` → `gpt-5.5` in `/codex` and `/council` (OpenAI released GPT-5.5 on 2026-04-23)                                                                                                                              |
| 5.19    | 2026-04-29 | Allow `Write`/`Edit` on `.claude/local/**` without prompting (workaround for Claude Code v2.1.80+ bare-tool regression)                                                                                                                    |
| 5.18    | 2026-04-28 | Tighten reconcile prompt — enumerate all CONTINUITY reference types (tree diagrams, prose pointers, labels)                                                                                                                                |
| 5.17    | 2026-04-28 | Drop per-file template-drift cry-wolf hint; soft "ask Claude to reconcile" tip                                                                                                                                                             |
| 5.16    | 2026-04-28 | Migration UX — consolidated "ask Claude" reconcile message; dropped cry-wolf drift hint                                                                                                                                                    |
| 5.15    | 2026-04-28 | CONTINUITY split — durable facts to CLAUDE.md, decisions to `docs/adr/`, volatile state to gitignored `.claude/local/state.md`                                                                                                             |
| 5.14    | 2026-04-27 | Drift hygiene — SessionStart `git fetch` warning + worktree from `origin/<default>`                                                                                                                                                        |
| 5.13    | 2026-04-21 | Phase 4 task-DAG dispatch with file-conflict constraints                                                                                                                                                                                   |
| 5.12    | 2026-04-21 | Template-drift notice on `setup.sh -f` / `--upgrade`                                                                                                                                                                                       |
| 5.11    | 2026-04-20 | ARRANGE rule — close the E2E actor-boundary gap via text layer                                                                                                                                                                             |
| 5.10    | 2026-04-18 | Evidence-based E2E gate — checkbox claims bound to `tests/e2e/reports/` artifact                                                                                                                                                           |
| 5.9     | 2026-04-18 | `E2E verified` gate — close the silent-skip loophole                                                                                                                                                                                       |
| 5.8     | 2026-04-18 | Multi-project interpreter preflight + isolation guide                                                                                                                                                                                      |
| 5.7     | 2026-04-18 | Template self-test suite (4 bash suites, ~5s)                                                                                                                                                                                              |
| 5.6     | 2026-04-17 | Template monorepo support + Playwright security fixes                                                                                                                                                                                      |
| 5.5     | 2026-04-17 | `verify-e2e` agent (#449) · Playwright CI bridge (#450) · `research-first` (#472) · repo rename                                                                                                                                            |
| 5.4     | 2026-03-31 | Engineering Council — 5 advisors with Codex chairman                                                                                                                                                                                       |
| 5.3     | 2026-03-01 | Silent SessionStart context injection via JSON `hookSpecificOutput`                                                                                                                                                                        |
| 5.2     | 2026-02-20 | Frontend design plugin + `rules/frontend-design.md`                                                                                                                                                                                        |
| 5.1     | 2026-02-19 | CLAUDE.md split — slim file + auto-loaded `.claude/rules/`                                                                                                                                                                                 |
| 5.0     | 2026-02-19 | Removed Compound Engineering, replaced with built-in quality gates                                                                                                                                                                         |

Full history: **[docs/CHANGELOG.md](docs/CHANGELOG.md)**

## Credits

Started from [Boris Cherny's workflow](https://www.anthropic.com/engineering/claude-code-best-practices) (Claude Code's creator), Anthropic's official best practices, and [OpenClaw's pre-compaction memory patterns](https://github.com/openclaw/openclaw/discussions/6038) — evolved into a dual-agent harness through ongoing iteration.

## Getting help

- [Claude Code Docs](https://code.claude.com/docs)
- [Memory Management](https://code.claude.com/docs/en/memory)
- [Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Skills & Commands](https://code.claude.com/docs/en/skills)
- [Anthropic Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Subagents Guide](https://code.claude.com/docs/en/sub-agents)

## License

See [LICENSE](LICENSE).
