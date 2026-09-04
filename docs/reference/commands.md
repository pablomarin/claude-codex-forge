# Commands and Skills Reference

The host-native entry points and shared agent roles available after setup.

## Workflow Commands (ENFORCED — Start Here)

| Purpose | Claude Code | Codex |
| --- | --- | --- |
| Full feature workflow | `/new-feature <name>` | `$workflow-new-feature <name>` |
| Bug-fix workflow | `/fix-bug <name>` | `$workflow-fix-bug <name>` |
| Trivial change | `/quick-fix <name>` | `$workflow-quick-fix <name>` |
| Merge and worktree cleanup | `/finish-branch` | `$workflow-finish-branch` |

**Workflow commands guide the process.** `.forge/local/state.md` is the host-neutral durable
checkpoint; hooks validate its current candidate evidence before commit/push/PR.

### Autonomous loop (`/goal`)

`/goal` remains each host's native command; Forge never installs a command or skill with that name.
The root adapter composes native autonomy over `.forge/workflows/goal.md`, including persistent
budget, exact resume, evidence, and human-authorization boundaries. The Forge objective, nonce, and
next step survive a host switch; the native Claude Code or Codex session does not transfer.

## Decision Analysis

- Claude Code: `/opinion investigate` followed by the request
- Codex: `$opinion investigate` followed by the request

| Host | Invocation | Purpose |
| ---- | ---------- | ------- |
| Claude Code | `/opinion <request>` | Fresh independent opinion |
| Codex | `$opinion <request>` | Fresh independent opinion |
| Claude Code | `/opinion investigate <request>` | Fresh full-agent investigation in the real worktree |
| Codex | `$opinion investigate <request>` | Fresh full-agent investigation in the real worktree |

### Opinion profiles

Forge deliberately uses the name `opinion` because `review` is reserved by both supported hosts.
Use `/opinion` in Claude Code and `$opinion` in Codex. Ordinary requests are hermetic and read-only;
add `investigate` when the task needs normal project tools, writes, network, databases, APIs, or MCP.
The current host remains main; automatic selection prefers the other engine and visibly falls back
to a fresh same-engine reviewer on launch or capability failure.

| Profile           | Boundary | Use for |
| ----------------- | -------- | ------- |
| General/plan/code | Hermetic, read-only, no network | Independent analysis and candidate-bound review |
| `investigate`     | Fresh full agent, real worktree, normal host config/tools/MCP/network | Operational research and live-state fact finding; findings require an independent control |

## PRD Commands (Requirements)

| Purpose | Claude Code | Codex | Output |
| --- | --- | --- | --- |
| Interactive requirements | `/prd:discuss {feature}` | `$workflow-prd-discuss {feature}` | `docs/prds/{feature}-discussion.md` |
| Structured PRD | `/prd:create {feature}` | `$workflow-prd-create {feature}` | `docs/prds/{feature}.md` |

## Quality Gates (Pre-PR — in this order)

| Command / Agent    | Purpose |
| ------------------ | ------- |
| Simplification phase | Forge-owned cleanup before final candidate freeze |
| Claude `/opinion` / Codex `$opinion` | Distinct fresh code-spec and code-quality receipts over the frozen candidate |
| `verify-app` agent | Unit tests, migration check, lint, and types |
| `verify-e2e` agent | User-journey E2E plus regression replay |

Review uses one broad pass, one repair pass, and one closure pass limited to named findings and
direct regressions. P3, cosmetic, and speculative concerns do not keep the loop open; reachable
P0/P1 security, correctness, or data-integrity failures still block.

## Research Enforcement (Pre-Design — Phase 2)

Your AI assistant's knowledge has a cutoff. Libraries ship breaking changes weekly. The `research-first` agent runs in Phase 2 of `/new-feature` — before any design begins — querying Context7, official docs, and changelogs for each dependency your feature touches. It produces a structured brief in `docs/research/` that the design phase reads. No more building on stale docs.

For bug fixes, targeted research runs after root-cause isolation (Phase 2.5 of `/fix-bug`).

## PR Review Comments (Post-PR)

| Host | Invocation | Purpose |
| --- | --- | --- |
| Claude Code | `/review-pr-comments` | Address automated PR review comments |
| Codex | `$workflow-review-pr-comments` | Address the same comments through the canonical workflow |

## Claude Code Built-in Commands

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

Canonical roles are materialized for each host and invoked through that host's native agent
mechanism. Workflows call them automatically; the plain-language invocation below also works when
you need a role directly.

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
| `-t python\|typescript\|fullstack` | Record the project profile and determine Playwright eligibility; v6 does not prune the canonical v6 rules or skills by profile                                                                                                                                                                                      |
| `-u`, `--upgrade`                  | Update an existing v6 installation while preserving project-owned settings, MCP entries, and content                                                                                                                                                                                                                 |
| `-f`, `--force`                    | Authoritative full installation/reconciliation from any state, with ownership checks and transactional rollback                                                                                                                                                                                                       |
| `--dry-run`                        | With `-f` / `--force`, run complete discovery and staging validation without writing target files; rerun without this flag only after `UPGRADE: READY`                                                                                                                                                                  |
| `--global`                         | Install canonical global policy under `~/.forge/` plus bounded Claude Code and Codex adapters                                                                                                                                                                                                                         |
| `--with-playwright`                | Scaffold Playwright config + auth fixture + reference CI workflow                                                                                                                                                                                                                                                     |
| `--playwright-dir <path>`          | Override autodetected scaffolding directory for monorepos                                                                                                                                                                                                                                                             |

PowerShell uses `-Upgrade`, `-Force`, and `-DryRun`. The former Bash `-F` / `--full-refresh` and
PowerShell `-FullRefresh` / `-R` spellings remain deprecated compatibility aliases. Project and
global full reconciliations are separate transactions, and preview does not certify host
`RUNTIME_READY` status. A project preview also blocks on an active user-owned `post-checkout` hook
that still references retired v5 state paths; the operator must migrate or retire that hook because
full refresh deliberately does not mutate `.git/hooks`.
The old `--migrate` / `-Migrate` spellings are retired, non-mutating diagnostics. Legacy
`CONTINUITY.md` is handled by the full-refresh inventory and manual reconciliation when needed.
