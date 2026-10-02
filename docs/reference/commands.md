# Commands and Skills Reference

The host-native entry points and shared agent roles available after setup.

## Workflow Commands (ENFORCED — Start Here)

| Purpose | Claude Code | Codex |
| --- | --- | --- |
| Full feature workflow | `/new-feature <name>` | `$new-feature <name>` |
| Bug-fix workflow | `/fix-bug <name>` | `$fix-bug <name>` |
| Trivial change | `/quick-fix <name>` | `$quick-fix <name>` |
| Merge and worktree cleanup | `/finish-branch` | `$finish-branch` |

**Workflow commands guide the process.** `.forge/local/state.md` is the host-neutral durable
checkpoint; hooks validate its current candidate evidence before commit/push/PR.

`/quick-fix` is the narrow exception: it is limited to a clean exact-base, low-risk,
non-user-facing change with no more than three implementation paths and one obvious focused check.
The main agent runs that check directly; quick-fix does not dispatch review or verification agents
and does not create a final candidate receipt set. Scope drift restarts as `/fix-bug` or
`/new-feature`.

### Upgrading from prefixed Codex names

Codex now uses `$fix-bug`, `$new-feature`, `$quick-fix`, `$finish-branch`,
`$prd-create`, `$prd-discuss`, and `$review-pr-comments`, without `workflow-`.
Claude's entry points and the shared `.forge/workflows/` procedures are unchanged.
Upgrade an existing V6 project with `setup.sh --upgrade` or `setup.ps1 -Upgrade`.
Setup removes old wrappers only when their recorded installation hash and generated
identity prove they are unchanged Forge files. Modified or unproven old wrappers
and sibling files remain, with a warning to reconcile the old name manually.

A custom or unproven skill at a new short name blocks replacement. Move that skill
directory aside outside the skill discovery folders, rerun setup, then reconcile
your custom content under a distinct name. Use the same recovery if an interrupted
install wrote a wrapper but not its installation receipt; do not delete custom work.
Transactional full-refresh preview and apply enforce the same ownership checks.
On Unix, reconciling existing renamed skills requires Python 3; PowerShell performs
these checks natively. Existing projects may need a fresh Codex session to discover
the updated skill inventory.

### Autonomous loop (`/goal`)

`/goal` remains each host's native command; Forge never installs a command or skill with that name.
The root adapter composes native autonomy over `.forge/workflows/goal.md`, including persistent
budget, exact resume, evidence, and human-authorization boundaries. The Forge objective, nonce, and
next step survive a host switch; the native Claude Code or Codex session does not transfer.
Each native Goal request authorizes one 20-turn tranche. Another request is needed after exhaustion.
Push, PR, merge, deployment, and other external mutations remain separately authorized.

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
| Interactive requirements | `/prd:discuss {feature}` | `$prd-discuss {feature}` | `docs/prds/{feature}-discussion.md` |
| Structured PRD | `/prd:create {feature}` | `$prd-create {feature}` | `docs/prds/{feature}.md` |

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
| Codex | `$review-pr-comments` | Address the same comments through the canonical workflow |

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
| `--retire-global`                  | Preview one-time removal of legacy machine-wide Forge-owned files; never required for project installation                                                                                                                                                                                                            |
| `--apply --confirm <digest>`       | Apply that retirement only when the current inventory exactly matches the preview digest                                                                                                                                                                                                                              |
| `--with-playwright`                | Scaffold Playwright config + auth fixture + reference CI workflow                                                                                                                                                                                                                                                     |
| `--playwright-dir <path>`          | Override autodetected scaffolding directory for monorepos                                                                                                                                                                                                                                                             |

PowerShell uses `-Upgrade`, `-Force`, `-DryRun`, `-RetireGlobal`, `-Apply`, and `-Confirm`. The former Bash `-F` / `--full-refresh` and
PowerShell `-FullRefresh` / `-R` spellings remain deprecated compatibility aliases. Project and
legacy-retirement operations are separate transactions, and preview does not certify host
`RUNTIME_READY` status. A project preview also blocks on an active user-owned `post-checkout` hook
that still references retired v5 state paths; the operator must migrate or retire that hook because
full refresh deliberately does not mutate `.git/hooks`.
The old `--migrate` / `-Migrate` spellings are retired, non-mutating diagnostics. Legacy
`CONTINUITY.md` is handled by the full-refresh inventory and manual reconciliation when needed.
