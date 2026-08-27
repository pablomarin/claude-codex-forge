# Commands Reference

All slash commands and subagents available after setup.

## Workflow Commands (ENFORCED — Start Here)

| Command               | Purpose               | Notes                                                                            |
| --------------------- | --------------------- | -------------------------------------------------------------------------------- |
| `/new-feature <name>` | Full feature workflow | PRD → Research → Design (iterative) → Execute → Review (iterative) → PR → Finish |
| `/fix-bug <name>`     | Bug fix workflow      | Search solutions → Systematic debugging → Fix → Review → Compound                |
| `/quick-fix <name>`   | Trivial changes only  | < 3 files, no arch impact, still requires verify                                 |
| `/finish-branch`      | Merge + cleanup       | Merge PR to main → Delete remote/local branch + worktree → Restart servers       |

**Workflow commands guide the process.** `.forge/local/state.md` is the host-neutral durable
checkpoint; hooks validate its current candidate evidence before commit/push/PR.

### Autonomous loop (`/goal`)

`/goal` remains each host's native command; Forge never installs a command or skill with that name.
The root adapter composes native autonomy over `.forge/workflows/goal.md`, including persistent
budget, exact resume, evidence, and human-authorization boundaries.

## Decision Analysis

| Command                           | Purpose                    | Notes |
| --------------------------------- | -------------------------- | ----- |
| `/council <question>`             | Multi-perspective analysis | Uses both engines when available; otherwise reruns the whole topology on the main engine. |
| `/opinion <request>`              | Fresh independent opinion  | Chooses Claude Code or Codex with automatic visible same-engine fallback. |
| `/opinion investigate <request>`  | Bounded investigation      | Disposable candidate, declared read-only query channel, and independent reproduction. |

### `/opinion` profiles

Forge deliberately uses `/opinion` because `/review` is reserved by both supported hosts. Ordinary
requests are hermetic and read-only. Investigation is explicit: use `/opinion investigate` when the
task needs network, execution, or a declared live-data query channel.

| Profile           | Boundary | Use for |
| ----------------- | -------- | ------- |
| General/plan/code | Hermetic, read-only, no network | Independent analysis and candidate-bound review |
| `investigate`     | Disposable workspace plus explicitly declared capabilities | Reproduction or live-state fact finding; replay is bounded and findings require an independent control |

## PRD Commands (Requirements)

| Command                  | Purpose                           | Output                              |
| ------------------------ | --------------------------------- | ----------------------------------- |
| `/prd:discuss {feature}` | Interactive user story refinement | `docs/prds/{feature}-discussion.md` |
| `/prd:create {feature}`  | Generate structured PRD           | `docs/prds/{feature}.md`            |

## Quality Gates (Pre-PR — in this order)

| Command / Agent    | Purpose |
| ------------------ | ------- |
| `/opinion`         | Distinct fresh code-spec and code-quality receipts over one frozen candidate |
| Simplification phase | Forge-owned cleanup before final candidate freeze |
| `verify-app` agent | Unit tests, migration check, lint, and types |
| `verify-e2e` agent | User-journey E2E plus regression replay |

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
