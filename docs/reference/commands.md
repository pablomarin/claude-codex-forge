# Commands Reference

All slash commands and subagents available after setup.

## Workflow Commands (ENFORCED — Start Here)

| Command               | Purpose               | Notes                                                                            |
| --------------------- | --------------------- | -------------------------------------------------------------------------------- |
| `/new-feature <name>` | Full feature workflow | PRD → Research → Design (iterative) → Execute → Review (iterative) → PR → Finish |
| `/fix-bug <name>`     | Bug fix workflow      | Search solutions → Systematic debugging → Fix → Review → Compound                |
| `/quick-fix <name>`   | Trivial changes only  | < 3 files, no arch impact, still requires verify                                 |
| `/finish-branch`      | Merge + cleanup       | Merge PR to main → Delete remote/local branch + worktree → Restart servers       |

**Workflow commands guide the process.** `.claude/local/state.md` is read on demand by hooks (not auto-loaded), and the Stop hook reminds you to keep it current; `check-workflow-gates.sh` validates completion before commit/push/PR.

### Autonomous loop (`/goal`)

`/goal` is not a Forge command you install — it's Claude Code's built-in, invoked with a Forge-composed instruction. After the PRD is approved in `/new-feature` (or the plan in `/fix-bug`), the workflow **offers** you a ready-to-paste `/goal …` command. Paste it and the agent drives the rest of the lifecycle — plan → review → implement → review → verify → E2E → PR — autonomously, routing hard decisions to `/council` and stopping only at the PR-creation gate. It's **optional and PRD-gated**; declining keeps you in manual phase-by-phase mode. In either mode you watch and steer by typing in the prompt. Full behavior: [Autonomous Goal Mode](../explanation/autonomous-goal.md); the agent's autonomous-run rules live in `rules/workflow.md` ("Council During `/forge-goal` Autonomous Run").

## Decision Analysis

| Command                | Purpose                       | Notes                                                                                                                                                                             |
| ---------------------- | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/council <question>`  | Multi-perspective analysis    | 5 advisors (3 Claude + 2 Codex) + Codex chairman. See [The Engineering Council](../explanation/engineering-council.md) for personas, when it fires, and the minority-report rule. |
| `/codex <instruction>` | Second opinion from Codex CLI | Four modes: Code Review, Design Review, General (all hermetic — read-only, no network), and **Investigate** (live-system access — see below).                                     |

### `/codex` modes

**You don't pick the mode — Claude does, from your request.** Codex itself has no concept of modes; it just receives a prompt + sandbox flags. The three hermetic modes are **keyword/context-routed** (e.g. "review", "review the plan", or a general question). **Investigate is capability-routed**, not keyword-triggered: Claude enters it only when the task genuinely needs project credentials, network, an external system (DB/cloud/API), live data, or to execute something — so a plain "review this" never silently escalates to live access. Describe the work in plain language; Claude maps it to the right mode and only grants Codex live access when the task demands it.

| Mode            | Sandbox / network                                                                 | Use for                                                                                                                                                                                                                                                                                                                                                    |
| --------------- | --------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Code Review     | `exec review`, hermetic (read-only, no network)                                   | Reviewing committed/uncommitted diffs                                                                                                                                                                                                                                                                                                                      |
| Design Review   | `--sandbox read-only`, no network                                                 | Reviewing a plan/design before implementation                                                                                                                                                                                                                                                                                                              |
| General         | `--sandbox read-only`, no network                                                 | A second opinion / analysis question                                                                                                                                                                                                                                                                                                                       |
| **Investigate** | `--sandbox workspace-write` + network, repo-confined (never `danger-full-access`) | Debugging / reverse-engineering / data-spelunking against **live systems** — Codex runs queries, reaches DBs/APIs, executes. Read-only / non-mutating; Claude provisions it from the project's own connection surface; findings cross-verified. Works inside an autonomous `/goal` run. See [Codex Investigate Mode](../explanation/codex-investigate.md). |

## PRD Commands (Requirements)

| Command                  | Purpose                           | Output                              |
| ------------------------ | --------------------------------- | ----------------------------------- |
| `/prd:discuss {feature}` | Interactive user story refinement | `docs/prds/{feature}-discussion.md` |
| `/prd:create {feature}`  | Generate structured PRD           | `docs/prds/{feature}.md`            |

## Superpowers Commands (Design → Execute → Debug)

| Command                                       | Purpose                                                    | Notes                                    |
| --------------------------------------------- | ---------------------------------------------------------- | ---------------------------------------- |
| `/superpowers:brainstorming`                  | Interactive design refinement                              | Uses PRD context                         |
| `/superpowers:writing-plans`                  | Create detailed implementation plan                        | TDD tasks                                |
| `/superpowers:subagent-driven-development`    | Execute plan via dispatched subagents (default in Phase 4) | TDD enforced, parallel via Dispatch Plan |
| `/superpowers:executing-plans`                | Execute plan in a separate session                         | Headless / walk-away mode                |
| `/superpowers:systematic-debugging`           | 4-phase root cause analysis                                | Before ANY bug fix                       |
| `/superpowers:verification-before-completion` | Evidence-based completion check                            | Catches "should work" claims             |

## Quality Gates (Pre-PR — in this order)

| Command / Agent                | Purpose                                                        | Notes                                       |
| ------------------------------ | -------------------------------------------------------------- | ------------------------------------------- |
| `/codex review`                | First review after implementation — independent second opinion | Codex CLI (uncommitted/base/commit options) |
| `/codex {instruction}`         | General second opinion                                         | Runs `codex exec` in read-only sandbox      |
| `/pr-review-toolkit:review-pr` | Deep multi-analyzer review (6 agents)                          | Silent failures, test coverage, type design |
| `/simplify`                    | Clean up modified files                                        | Built-in command, no plugin needed          |
| `verify-app` agent             | Unit tests, migration check, lint, types                       | "Use the verify-app agent"                  |
| `verify-e2e` agent             | User-journey E2E (API / UI / CLI) + regression suite replay    | "Use the verify-e2e agent"                  |

## Research Enforcement (Pre-Design — Phase 2)

Your AI assistant's knowledge has a cutoff. Libraries ship breaking changes weekly. The `research-first` agent runs in Phase 2 of `/new-feature` — before any design begins — querying Context7, official docs, and changelogs for each dependency your feature touches. It produces a structured brief in `docs/research/` that the design phase reads. No more building on stale docs.

For bug fixes, targeted research runs after root-cause isolation (Phase 2.5 of `/fix-bug`).

## PR Review Comments (Post-PR)

| Command               | Purpose                              | Notes                                                           |
| --------------------- | ------------------------------------ | --------------------------------------------------------------- |
| `/review-pr-comments` | Address automated PR review comments | Requires GitHub Copilot, Codex, or Claude PR reviews configured |

## Built-in Commands

| Command        | Purpose                                             |
| -------------- | --------------------------------------------------- |
| `/clear`       | Clear context (triggers SessionStart hook)          |
| `/compact`     | Compact context manually (triggers PreCompact hook) |
| `/memory`      | View/edit memory files (auto memory + CLAUDE.md)    |
| `/cost`        | Show session costs                                  |
| `/hooks`       | View configured hooks                               |
| `/permissions` | View/modify permissions                             |
| `/help`        | List all commands                                   |
| `Shift+Tab`    | Toggle auto-accept mode (mid-session)               |

---

## Subagents

Custom subagents available via the Task tool.

| Agent             | Purpose                                                                                           | Invocation                                            |
| ----------------- | ------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `verify-app`      | Unit tests + lint + type checks + migrations                                                      | "Use the verify-app agent"                            |
| `verify-e2e`      | User-journey E2E through API / UI / CLI; produces markdown report at `tests/e2e/reports/`         | "Use the verify-e2e agent"                            |
| `research-first`  | Pre-design library/API research via Context7 + official docs; writes `docs/research/<feature>.md` | Phase 2 of `/new-feature`, Phase 2.5 of `/fix-bug`    |
| `council-advisor` | Engineering Council advisor (persona via prompt)                                                  | Dispatched by `/council` skill — not invoked directly |

---

## `setup.sh` Flags

Run from a fresh `claude-codex-forge` clone.

| Flag                               | Purpose                                                                                                                                                                                                                                                                                                               |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-p "Project Name"`                | Project name (required for fresh installs)                                                                                                                                                                                                                                                                            |
| `-t python\|typescript\|fullstack` | Pick the language profile (controls which `rules/*.md` get installed)                                                                                                                                                                                                                                                 |
| `-f`                               | Force-overwrite refreshable templates (rules, commands, hooks, settings)                                                                                                                                                                                                                                              |
| `--upgrade`                        | Same as `-f` plus a template-drift summary at the end                                                                                                                                                                                                                                                                 |
| `--global`                         | Install global files into `~/.claude/`                                                                                                                                                                                                                                                                                |
| `--with-playwright`                | Scaffold Playwright config + auth fixture + reference CI workflow                                                                                                                                                                                                                                                     |
| `--playwright-dir <path>`          | Override autodetected scaffolding directory for monorepos                                                                                                                                                                                                                                                             |
| `--migrate`                        | Run the legacy-state-file migration assistant: extracts Goal into `CLAUDE.md`, decisions into `docs/adr/`, and Done/Now/Next into `.claude/local/state.md`. Idempotent; original file preserved byte-for-byte. Flags any dangling `@`-import in `CLAUDE.md`. See `docs/guides/upgrading.md` for the full walkthrough. |
