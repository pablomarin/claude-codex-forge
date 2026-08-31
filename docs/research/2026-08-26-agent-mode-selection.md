# Research: Agent Mode Selection / Dual-Engine Forge Workflows

**Date:** 2026-08-26
**Feature:** One Forge workflow harness usable from Claude Code or Codex, with
cross-engine review, fresh same-engine fallback, council, investigation, goal, and
cross-host resume.
**Researcher:** research-first agent
**Access date for external sources:** 2026-08-26
**Scope:** Research only. This brief records current host primitives and constraints;
the architecture decision belongs to the design phase.
**PRD:** `docs/prds/agent-mode-selection.md`

## Research Scope and Baseline

No dependency manifest or lockfile exists. Forge intentionally ships Bash,
Windows PowerShell, Markdown, JSON, and configuration templates without a packaged
runtime dependency. Observed research-host versions are diagnostic, not project pins:
Claude Code `2.1.237`, Codex CLI `0.144.1`, Bash `3.2.57`, Git `2.50.0`; PowerShell
and Grok Build are not installed on the research host.

## Libraries Touched

| Library / surface | Our version | Latest stable | Breaking changes relevant here | Source |
| --- | --- | --- | --- | --- |
| Claude Code CLI and harness | Not pinned; host `2.1.237` | `2.1.246` | No incompatible change identified; later patches changed `/goal` resume and background-loop behavior | [Releases](https://github.com/anthropics/claude-code/releases/latest) (2026-08-26) |
| OpenAI Codex CLI and harness | Not pinned; host `0.144.1` | `0.149.1` | No consolidated incompatible delta verified; `--full-auto` is deprecated and custom-agent format is evolving | [Releases](https://github.com/openai/codex/releases/latest) (2026-08-26) |
| Agent Skills | Not pinned | Unversioned living specification | `allowed-tools` remains experimental and client behavior varies | [Specification](https://agentskills.io/specification) (2026-08-26) |
| Git symlink behavior | Not pinned; host `2.50.0` | `2.55.0` | No relevant semantic change identified | [git-config](https://git-scm.com/docs/git-config) (2026-08-26) |
| GNU Bash | Not pinned; host `3.2.57` | `5.3` plus patches | Bash 4/5-only syntax is incompatible with the macOS Bash 3.2 baseline | [Bash 5.3 announcement](https://lists.gnu.org/archive/html/bug-bash/2025-07/msg00005.html) (2026-08-26) |
| PowerShell | Windows PowerShell `5.1` policy baseline; not installed locally | `7.6.5` | PowerShell 7 uses `pwsh`, has invocation differences, and removed Windows PowerShell cmdlets | [Releases](https://github.com/PowerShell/PowerShell/releases/latest) (2026-08-26) |
| Grok Build compatibility probe | Not installed or pinned | No stable tag verified; early beta | Claude compatibility is partial; documented Codex compatibility cells are mostly inert | [Announcement](https://x.ai/news/grok-build-cli) (2026-08-26) |

## Executive Summary

Claude Code and Codex can participate in one Forge workflow, but their compatible
content formats do not make their runtimes identical. Both understand repository
instructions, Agent Skills, MCP, hooks, fresh headless invocations, subagents, and a
native `/goal`; however, discovery roots, configuration schemas, permission systems,
hook payloads, subagent definitions, and goal lifecycle mechanics differ. The safe
implementation boundary is therefore one host-neutral Forge policy and state layer plus
small generated adapters for each host.

The installed project should not rely on tracked filesystem symlinks. Git can check
symlinks out as ordinary text files when `core.symlinks=false`, and Windows symlink
creation can depend on Developer Mode or elevated privileges. Materialized wrappers
are more portable, reviewable, and testable.

Fresh same-engine review is feasible: Claude can run a non-persistent print-mode
session and Codex can run an ephemeral `exec` session. Independence must be evidenced
by a fresh invocation identity and bounded context, not by requiring the reviewer
engine to differ from the active host. The MCPGateway prototype proves the shared-state
and reciprocal-launch shape, but its current opposite-engine-only evidence rule,
read-only Claude reviewer, and Node 24 runtime requirement cannot become the Forge
contract unchanged.

## Per-Library Analysis

### Claude Code

**Versions:** ours=not pinned, research host `2.1.237`; latest=`2.1.246`.
**Breaking changes since ours:** No incompatible change identified. `/goal` resume and
idle background-loop behavior changed in later patches.
**Deprecations:** `.claude/commands` remains supported, but skills are preferred for new
reusable workflows; agent hooks remain experimental.
**Recommended pattern:** use `CLAUDE.md`/imports plus Claude-native thin settings,
hooks, skills, agents, permissions, headless invocation, and goal composition.

#### Current primitives

- `CLAUDE.md` is Claude Code's repository instruction surface. Claude also supports
  importing another instruction file with `@path`; Anthropic specifically documents
  importing `AGENTS.md` from `CLAUDE.md` for projects shared with other agents.
- Project skills use `SKILL.md`; `.claude/commands` remains supported for legacy custom
  commands, while skills are the recommended reusable surface.
- Hooks are configured in Claude settings and have Claude-specific events, matchers,
  input payloads, exit-code behavior, and JSON response contracts.
- Subagents start with separate context and can have their own model, prompt, tools,
  permission mode, hooks, and persistent memory.
- `claude -p` provides a headless fresh reviewer path. `--no-session-persistence`, tool
  selection, permission mode, model, effort, budget, and structured output can bound a
  review run.
- Claude's native `/goal` is session-scoped and uses a fresh evaluator on Stop. It is
  not a portable state store and must be composed over Forge's durable checkpoint and
  evidence.

#### Sources

1. [Claude Code memory and instruction files](https://code.claude.com/docs/en/memory)
   — repository `CLAUDE.md`, imports, and the documented `@AGENTS.md` sharing pattern.
2. [Claude Code skills and slash commands](https://code.claude.com/docs/en/slash-commands)
   — `SKILL.md` and legacy `.claude/commands` discovery.
3. [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) — event,
   matcher, input, output, and blocking contracts.
4. [Claude Code subagents](https://code.claude.com/docs/en/sub-agents) — isolated
   context, tools, permissions, and memory.
5. [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference) — print
   mode, session persistence, model, effort, tools, and permission flags.
6. [Claude Code goals](https://code.claude.com/docs/en/goal) — native `/goal` scope and
   evaluator behavior.

#### Design impact

- Preserve a Claude-native instruction/command/settings surface, but keep it thin.
- Use a fresh `claude -p` process for same-engine review when the other engine is
  unavailable or explicitly not selected.
- Do not treat Claude's session goal or automatic memory as canonical cross-host state.
- A generated `CLAUDE.md` import is preferable on a clean install. Existing protected
  project instructions need bounded marker-based reconciliation or a hook-injected
  pointer rather than replacement.

#### Test implications

- Assert generated Claude wrappers point to the same canonical workflow revision as
  Codex wrappers.
- Fake the `claude` executable to test present, missing, authentication-failure,
  launch-failure, timeout, and clean-result paths without network access.
- Contract-test Claude hook payload fixtures and fresh-review launch flags.
- Verify `/goal` instructions use Forge nonce/evidence and do not claim that the native
  Claude session transfers to Codex.

### OpenAI Codex

**Versions:** ours=not pinned, research host `0.144.1`; latest=`0.149.1`.
**Breaking changes since ours:** No consolidated incompatible delta could be verified;
capability probing remains necessary.
**Deprecations:** `--full-auto` is a compatibility flag; explicit
`--sandbox workspace-write` is recommended. Custom-agent TOML is current but evolving.
**Recommended pattern:** install real `AGENTS.md`, `.agents`, and `.codex` adapters;
use `codex exec --ephemeral` for fresh review and explicit capability profiles.

#### Current primitives

- Codex discovers layered `AGENTS.md` instructions and uses `.agents/skills` for
  repository Agent Skills.
- Codex can import Claude Code instructions, settings, skills, plugins, hooks,
  commands, and subagents. Import is a migration/synchronization operation, not a
  guarantee that both hosts continue reading one physical file or that semantics are
  identical.
- Codex project configuration is TOML and its hook configuration can live in
  `.codex/hooks.json`; hook trust and merge behavior are Codex-specific.
- Codex subagents use TOML role definitions and fresh thread contexts.
- `codex exec --ephemeral` supplies a fresh same-engine or opposite-engine reviewer
  path. Sandbox and approval options differ materially from Claude permission rules.
- Codex has a stable native `/goal`, but its durable chat-attached goal mechanics are
  different from Claude's Stop evaluator. Forge must define the shared objective and
  completion evidence above both.
- The installed CLI on the research machine is `codex-cli 0.144.1`; `goals`, `hooks`,
  `multi_agent`, and `plugins` report stable, while `memories` reports experimental.

#### Sources

1. [Import settings from other coding agents](https://learn.chatgpt.com/docs/import)
   — Claude-to-Codex mapping and semantic caveats.
2. [Codex customization overview](https://learn.chatgpt.com/docs/customization/overview)
   — `AGENTS.md`, configuration, skills, MCP, hooks, and subagents.
3. [Codex hooks](https://learn.chatgpt.com/docs/hooks) — project hook configuration,
   merge, trust, and event contracts.
4. [Build Agent Skills](https://learn.chatgpt.com/docs/build-skills) — repository skill
   discovery and `SKILL.md` structure.
5. [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode)
   — `codex exec`, ephemeral runs, output capture, and sandbox controls.
6. [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents) —
   TOML role definitions and fresh contexts.
7. [Codex developer commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli#set-or-view-a-task-goal-with-goal)
   and [Follow goals](https://learn.chatgpt.com/use-cases/follow-goals) — current native
   `/goal` lifecycle.

#### Design impact

- Install a real Codex surface rather than telling every user to run a one-time Claude
  import.
- Use `.agents/skills`, `.codex/config.toml`, `.codex/hooks.json`, and Codex subagent
  TOML only as adapters to shared Forge policy.
- Use `codex exec --ephemeral` for fresh Codex review and capture the final response
  separately from diagnostic output.
- Translate capabilities intentionally; do not mechanically copy Claude permission
  strings into Codex sandbox configuration.
- Keep Forge memory and state in the repository-local host-neutral area because native
  Codex memory is experimental and is not Claude memory.

#### Test implications

- Assert Codex skills and subagent TOML parse and reference existing canonical files.
- Fake `codex` to test availability and fallback behavior deterministically.
- Cover Codex hook payloads, trust/install messaging, and concurrent-event-safe Stop
  orchestration.
- Run an optional real-CLI smoke against the installed stable Codex, while keeping the
  normal suite offline and deterministic.

### Agent Skills Portability

**Versions:** ours=not pinned; latest=unversioned living specification.
**Breaking changes since ours:** Not applicable; there is no pinned semantic version.
**Deprecations:** None identified; `allowed-tools` is experimental and not portable.
**Recommended pattern:** author the portable `SKILL.md` body once, while keeping
discovery roots, tools, permissions, collisions, and host metadata in adapters.

#### Findings

The Agent Skills specification standardizes a directory containing `SKILL.md` with
frontmatter and supporting files. It is an appropriate common authoring format, but it
does not standardize host discovery roots, permissions, hooks, subagent configuration,
native commands, or goal behavior. One canonical skill can therefore be referenced by
both adapters, but the adapters remain necessary.

#### Sources

1. [Agent Skills overview](https://agentskills.io/home) — purpose and multi-product
   portability model.
2. [Agent Skills specification](https://agentskills.io/specification) — directory,
   frontmatter, progressive disclosure, and resource requirements.

#### Design impact

- Author shared workflow and skill bodies once in a canonical Forge directory.
- Generate small host-discovery wrappers instead of keeping two independently edited
  full skill trees.
- Give canonical references stable relative paths so copied installs and worktrees work.

#### Test implications

- Validate frontmatter and referenced resources for every generated skill.
- Compare canonical revision/fingerprint fields across Claude and Codex wrappers.
- Include a stale-wrapper mutation test that parity verification must reject.

### Git and Filesystem-Link Portability

**Versions:** ours=not pinned, research host Git `2.50.0`; latest Git=`2.55.0`.
**Breaking changes since ours:** None relevant to symlink checkout identified.
**Deprecations:** None relevant.
**Recommended pattern:** use materialized generated files or documented textual imports;
do not require tracked symlinks, junctions, Developer Mode, or elevation.

#### Findings

Tracked symlinks are not a reliable installation contract. Git documents that with
`core.symlinks=false`, symbolic links are checked out as small ordinary files containing
the link text. Windows unprivileged symlink creation depends on flags and Developer
Mode; otherwise privilege may be required. Junctions and directory links also differ
from Unix links. Generated wrapper files avoid these failure modes and produce ordinary
diffs developers can review.

Claude's official sharing recommendation also uses an instruction import rather than a
required Windows symlink.

#### Sources

1. [Git `core.symlinks`](https://git-scm.com/docs/git-config#Documentation/git-config.txt-coresymlinks)
   — checkout behavior when symlink support is unavailable.
2. [Microsoft `CreateSymbolicLinkW`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createsymboliclinkw)
   — privilege and Developer Mode conditions.
3. [Claude Code memory and instruction files](https://code.claude.com/docs/en/memory)
   — documented `@AGENTS.md` sharing approach.

#### Design impact

- Do not require symlinks or junctions.
- Materialize deterministic, visibly generated wrappers and record them in an ownership
  manifest.
- A user may choose local symlinks independently, but setup and verification must not
  depend on them.

#### Test implications

- Assert all installed managed paths are regular files in clean and migrated fixtures.
- Test with Git `core.symlinks=false`.
- Exercise paths containing spaces and Windows separators in static parity fixtures.

### GNU Bash and PowerShell

**Versions:** Bash ours=not pinned/host `3.2.57`, latest=`5.3`; PowerShell supported
baseline=`5.1`, not installed locally, latest=`7.6.5`.
**Breaking changes since ours:** Bash 4/5-only syntax is unavailable on the macOS 3.2
baseline; PowerShell 7 uses `pwsh` and differs from Windows PowerShell 5.1.
**Deprecations:** No Bash deprecation relevant; Windows PowerShell 5.1 remains the
built-in compatibility baseline while current development is PowerShell 7.x.
**Recommended pattern:** keep behaviorally equivalent Bash 3.2-compatible and Windows
PowerShell 5.1-compatible twins; detect newer runtimes without requiring them.

#### Findings

Forge's no-build/no-package-runtime model can remain intact if runtime behavior stays in
the existing Bash and Windows PowerShell twins. Shell selection, quoting, process exit
status, signal/timeout behavior, and JSON I/O differ. A host-neutral policy does not
remove the need for platform adapters; it removes Claude-vs-Codex duplication inside
each platform.

#### Sources

1. [Bash invocation](https://www.gnu.org/software/bash/manual/html_node/Invoking-Bash.html)
   and [Bash exit status](https://www.gnu.org/software/bash/manual/html_node/Exit-Status.html)
   — startup, argument, and status semantics.
2. [about_PowerShell_exe](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe)
   and [about_Execution_Policies](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)
   — Windows invocation and policy behavior.

#### Design impact

- Preserve `.sh`/`.ps1` parity for every runtime hook, dispatcher, and migration step.
- Keep host adapters data-driven where possible so Bash and PowerShell do not each
  embed separate copies of workflow policy.
- Do not adopt the MCPGateway prototype's Node 24 runtime as a Forge requirement.

#### Test implications

- Add cross-platform source-contract assertions for every new twin.
- Run behavioral Bash tests locally and PowerShell tests in Windows CI.
- Test quoting, paths with spaces, nonzero exits, timeout, missing executable, and
  malformed JSON/result handling on both platforms.

### Goal and Memory Semantics

#### Findings

Both hosts expose `/goal`, but neither native goal is the other host's transferable
session. Cross-host resume must therefore use Forge's worktree state, plan, evidence,
and artifact hashes. A developer can stop one host and resume with the other; Forge
does not promise to move the native chat/session itself.

Native memory is also not a shared contract: Claude project memory and Codex memories
have different locations, lifecycle, and maturity. Forge memories intended to survive a
host switch must live in a Forge-owned project-local location and be pointed to by both
instruction surfaces.

#### Sources

1. [Claude Code goals](https://code.claude.com/docs/en/goal) and
   [Claude Code memory](https://code.claude.com/docs/en/memory).
2. [Codex developer commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli#set-or-view-a-task-goal-with-goal)
   and [Codex customization](https://learn.chatgpt.com/docs/customization/overview).

#### Design impact

- Store a host-neutral goal nonce and action/evidence receipts in shared local state.
- Compose host-specific goal prompts from the same canonical objective and completion
  predicate.
- Store Forge memory under the shared local directory; native host memory may augment
  it but cannot be required for continuity.

#### Test implications

- Resume every persisted phase in both directions without repeating completed work.
- Reject old-nonce, stale-plan, stale-HEAD, or mismatched-artifact evidence.
- Verify native goal prompt text differs only where host mechanics require it.

### Grok Build Extensibility (Future, Not V1 Scope)

**Versions:** ours=not installed or pinned; latest=no stable release tag verified,
officially early beta.
**Breaking changes since ours:** Not applicable without a stable baseline.
**Deprecations:** None verified.
**Recommended pattern:** reserve a capability-based adapter boundary, but make no v1
support claim until Grok has its own version policy and acceptance matrix.

#### Findings

Grok Build is compatible enough to justify a capability-based host registry. It reads
`AGENTS.md` and `CLAUDE.md`, discovers skills from `.grok`, `.agents`, and `.claude`,
and documents Claude-compatible hooks, plugins, MCP, subagents, headless mode, and
worktrees. That breadth also creates double-discovery risk if Forge installs multiple
full copies. Grok's settings, hook payloads, agents, and goal/workflow mechanics still
need a thin `.grok` adapter; Claude/Codex files alone are not a verified complete Grok
implementation.

#### Sources

1. [Grok Build launch and compatibility statement](https://x.ai/news/grok-build-cli)
   and [Grok Build overview](https://docs.x.ai/build/overview).
2. [Grok Build open-source repository](https://github.com/xai-org/grok-build),
   especially its configuration, skills, hooks, plugins, subagents, and headless-mode
   user guides.
3. [Grok Build modes and commands](https://docs.x.ai/build/modes-and-commands) and
   [CLI reference](https://docs.x.ai/build/cli/reference).

#### Design impact

- Model hosts by capabilities such as instructions, workflows, hooks, fresh headless
  execution, sandbox profiles, subagents, and native goal integration.
- Keep Claude and Codex as the only v1 registered hosts.
- Prevent adapters from causing the same canonical workflow to be discovered twice.

#### Test implications

- Unit-test unknown/future host capability records independently from Claude/Codex.
- Reserve adapter-version and capability-profile fields in dispatch evidence.
- Do not claim Grok support until `.grok` behavior has its own acceptance matrix.

## Local Empirical Evidence: MCPGateway Prototype

### Verified local evidence

- `.agent-workflows/local/state.md` and `.agent-workflows/review-policy.md` demonstrate a
  host-neutral checkpoint and policy.
- `.agents/skills/*`, `.claude/*`, and `.codex/*` demonstrate thin host entry surfaces.
- `.agent-workflows/runtime/external-review.mjs` demonstrates a bounded fresh
  `claude -p` reviewer from Codex.
- `.agent-workflows/runtime/workflow.mjs` currently accepts review evidence only when
  `engine !== state.primaryHost`; that rejects the approved same-engine fresh-review
  modes.
- The runtime requires Node.js 24 and the normal reviewer deliberately disables tools;
  those choices conflict respectively with Forge's no-runtime contract and the
  capability-expanded investigative mode.

### Sources

1. Local prototype runtime and policy under
   `/Users/pablomarin/Code/mcpgateway/.agent-workflows/` (inspected 2026-08-26).
2. Local Claude/Codex adapters under `/Users/pablomarin/Code/mcpgateway/.claude/`,
   `/Users/pablomarin/Code/mcpgateway/.agents/`, and
   `/Users/pablomarin/Code/mcpgateway/.codex/` (inspected 2026-08-26).

### Design impact

- Reuse the conceptual boundaries, not the Node implementation wholesale.
- Replace `engine != primaryHost` with an independence receipt: fresh invocation ID,
  requested and actual engines, reviewer role, capability profile, fallback reason,
  and artifact identity.
- Make investigative capability orthogonal to engine selection.

### Test implications

- Port the prototype's state/fallback failure cases into Forge fixtures.
- Add all four main/reviewer combinations plus preflight and in-flight failure fallback.
- Prove an investigative same-engine reviewer can write a worktree artifact without
  being accepted as the main implementation run.

## 9. Consolidated Design Constraints

1. One canonical Forge policy/state/memory/evidence layer; no independently authored
   Claude and Codex workflow bodies.
2. Deterministic regular-file adapters; no required symlinks.
3. Current invocation selects the active host; no permanent main preference.
4. Runtime availability is reevaluated on each dispatch.
5. Independent review is a fresh-run/context property, not an engine-inequality rule.
6. Normal review and investigation are separate capability profiles.
7. External mutation remains a human-authorized operation even in investigation.
8. Native goals compose over Forge state; they are not cross-host session transport.
9. A managed-file ownership manifest is needed for safe authoritative migration.
10. Bash and PowerShell remain equal supported runtime implementations.
11. Claude/Codex v1 should expose a host-capability registry extensible to Grok later.

## Not Researched (with justification)

- **Node.js 24:** used by the MCPGateway prototype but not a Forge dependency or an
  approved requirement. If design adopts Node, it needs a separate distribution and
  compatibility decision.
- **MCP protocol internals:** both hosts support MCP, but this feature does not implement
  or change an MCP server.
- **Playwright:** present only in optional templates and unrelated to engine dispatch.
- **Direct Anthropic/OpenAI model APIs:** this integration targets installed coding-agent
  CLIs, not direct API orchestration.
- **Concurrent-edit locking frameworks:** explicitly excluded by the approved PRD.

## Open Risks and Required Validation

| Risk | Current confidence | Required validation before completion |
| --- | --- | --- |
| Existing protected `CLAUDE.md`/`AGENTS.md` cannot be replaced | High | Test marker-bounded merge/import behavior and no-byte-change preservation outside the block |
| Codex hook event/payload details drift across CLI releases | Medium | Fixture tests plus an optional real `codex 0.144+` smoke |
| Claude fresh subprocess inherits unwanted project/session context | Medium | Assert `--no-session-persistence`, bounded prompt, explicit cwd, tools, and output capture |
| Same-engine fallback could be mistaken for self-review | Medium | Evidence schema must require fresh invocation ID and reviewed-artifact hash/HEAD |
| Authentication failure detection can be ambiguous | Medium | Treat any unusable/empty/timeout preflight as visible fallback; never fabricate clean evidence |
| Full-refresh deletes customized legacy managed files | Medium | Delete only manifest-owned or positively identified legacy paths; preserve and report ambiguous paths |
| Two hosts edit simultaneously | Accepted non-goal | Document ordinary Git/filesystem risk; add no lock or lease |
| Windows behavior differs without local PowerShell | Medium | Require Windows CI for setup, hooks, dispatch, migration, paths, and fallback matrix |
| Grok double-discovers wrapper trees | Future risk | Keep Grok out of v1 claims; capability adapter must define exactly one discovery route |

## Research Gate Result

**PASS.** Every external platform or portability surface has at least two primary or
official sources, an access date, an explicit design impact, test implications, and
open risks. No unresolved research item prevents approach comparison. Host-specific
runtime behavior still requiring empirical proof is explicitly assigned to tests or a
bounded implementation spike rather than assumed.
