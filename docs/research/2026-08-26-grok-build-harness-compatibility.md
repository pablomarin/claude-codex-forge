# Grok Build Harness Compatibility Probe

**Date:** 2026-08-26
**Status:** Preliminary scope research; not the mandatory post-PRD `research-first` brief
**Question:** Does xAI Grok Build use the same project files and workflow methods as
Claude Code and Codex closely enough to consume a Forge canonical harness?

## Executive Finding

**Mostly yes at the policy/workflow layer; no at the complete host-runtime layer.** Grok
Build deliberately supports `AGENTS.md`, Claude Code instruction files, Agent Skills,
Claude-style commands and hooks, plugins, MCP servers, independent subagents, headless
runs, and worktrees. It can consume a large part of a host-neutral Forge harness directly.

It is not a zero-wrapper third host. Native settings, hook envelopes, agent definitions,
session/memory stores, permissions, and autonomous-loop controls differ. Current official
documentation exposes workflows and Stop hooks but no native `/goal` command equivalent
to the Claude Code and Codex commands. Grok support would therefore need a thin Grok host
adapter and explicit parity tests, not merely adding `grok` to an engine enum.

## Compatibility Matrix

| Surface | Grok Build support | Forge implication |
| --- | --- | --- |
| Project instructions | Native `AGENTS.md`; also reads `CLAUDE.md` for compatibility | A canonical `AGENTS.md`-family policy is directly reusable, but Grok must not load the same policy twice through both families |
| Skills | Standard `SKILL.md`; scans `.grok/skills`, `.agents/skills`, and Claude skill paths | Canonical Agent Skills can be shared directly; host-specific tool names may still need a wrapper or variant |
| Custom commands | Flat Markdown commands under `.grok/commands`, `.agents/commands`, and Claude command paths become slash commands | Many Forge command entrypoints are portable as skills/commands |
| Hooks | Native `.grok/hooks/*.json`; scans Claude `settings.json` hooks by default | Hook logic can share a canonical core, but a Grok adapter is required for event/payload differences |
| Hook semantics | Supports lifecycle gates including `PreToolUse`, `Stop`, and `SubagentStop`; Claude output vocabulary is substantially compatible | Enforcement model is compatible, but not byte-for-byte: Grok uses camelCase input where Claude uses snake_case and lacks some events/fields |
| Settings | `.grok/config.toml` plus project `.grok/config.toml` | Cannot reuse `.claude/settings.json` or `.codex/config.toml` as the only settings source |
| Permissions/sandbox | Native permission rules, approval modes, sandbox profiles, and project trust | Same safety outcomes are possible through a Grok-specific adapter |
| MCP | Native Grok TOML registration plus compatibility/plugin `.mcp.json` support | MCP definitions may be shareable, but precedence, trust, and schema need contract tests |
| Plugins | Bundles skills, commands, agents, hooks, MCP, and LSP; accepts Grok and Claude plugin layouts | A Forge plugin package could target Grok with a thin manifest, but installation/trust differs from Codex and Claude |
| Subagents | Fresh independent child context; configurable toolsets; `.grok/agents/*.md`; personas | Same-engine fresh reviewers and council seats are feasible |
| Headless reviewer | `grok -p`, JSON/streaming JSON, fresh session by default, resume support | Suitable for bounded reviewer dispatch and auditable run identity |
| Worktrees | Native worktree support and worktree-aware sessions | Compatible with Forge's per-feature isolation model |
| Memory | Grok-native experimental memory under `~/.grok/memory` | Not automatically shared with Claude/Codex; Forge durable state/memory needs a canonical project contract |
| Foreign sessions | Official CLI imports Claude sessions; Codex compatibility cells for most project surfaces are currently inert | Native transcript/session continuity is not a three-way shared store |
| Autonomous goal | Workflows and Stop hooks are documented; no native `/goal` is listed in the current official command reference | A Grok goal-equivalent would need a Forge adapter around Stop hooks/workflows or remain out of scope initially |

## Important Compatibility Details

### 1. Grok is closest to a bridge between Claude and Codex conventions

xAI explicitly says existing `AGENTS.md`, plugins, hooks, skills, and MCP servers work out
of the box. Grok's own documentation confirms:

- `AGENTS.md` is a native project-instruction file.
- `CLAUDE.md` files are read for compatibility.
- `.agents/skills` and `.agents/commands` are scanned alongside `.grok` paths.
- `.claude/skills`, `.claude/commands`, and Claude hook/settings sources are scanned by
  default unless compatibility is disabled.

This makes the planned canonical-harness/thin-wrapper architecture more extensible than
a Claude-specific source tree. It also introduces a duplication hazard: a Grok session
can discover both the canonical `AGENTS.md` surface and a Claude wrapper. Forge would need
an explicit single-load rule and a discovery test using `grok inspect --json`.

### 2. Grok does not currently discover Codex's whole `.codex` surface

The official configuration guide says the Codex compatibility cells for skills, rules,
agents, MCP, and hooks are reserved and currently inert; only staged session support is
listed. Grok's apparent Codex compatibility instead comes from native `AGENTS.md` and
shared `.agents/skills` conventions. Forge should not assume `.codex/config.toml`,
`.codex/hooks.json`, or `.codex/agents/*.toml` will load in Grok.

### 3. Claude hook compatibility is close, not identical

Grok can scan Claude hook configuration and supports blocking pre-tool and stop gates.
However, the official hook guide documents differences including camelCase input keys
where Claude uses snake_case, Grok-specific event values, and a different permission
notification surface. Existing Forge shell/PowerShell hook cores can be reused only if a
thin host adapter normalizes the input/output contract.

### 4. Fresh review and council execution are feasible

Grok subagents have independent context windows and configurable toolsets. Headless mode
starts a fresh session by default and emits a session ID in structured output. Therefore
Grok can satisfy the Forge definition of reviewer independence: fresh run, bounded
context, capability profile, and artifact-bound evidence. Read-only and investigative
profiles are both feasible through Grok permissions, sandbox, web, shell, and MCP tools.

### 5. Grok does not yet drop into the proposed `/goal` contract unchanged

Claude Code and Codex both document native `/goal` commands. Grok's current official
command reference documents plan mode, persistent sessions, background workflows, custom
Rhai workflows, Stop hooks, and headless resume, but no `/goal`. Forge could reproduce
the observable autonomous-loop behavior with a Grok Stop-hook/workflow adapter, but that
is a third host implementation and needs separate research and acceptance testing.

## Recommendation for the Current Feature

Keep the approved PRD scoped to Claude Code and Codex unless the user explicitly expands
it. Design the canonical harness so Grok can be added later without another rewrite:

1. Keep workflow policy and evidence host-neutral.
2. Prefer portable Agent Skills and shared `.agents` sources where all selected hosts
   genuinely load them.
3. Treat settings, hooks, permissions, agents, goal drivers, and plugin manifests as thin
   host adapters with parity tests.
4. Record host capabilities rather than hard-coding a two-value engine enum throughout
   the canonical runtime.
5. Add a later Grok qualification matrix before advertising it as a supported third host.

## Primary Sources

- [Introducing Grok Build](https://x.ai/news/grok-build-cli)
- [Grok Build overview](https://docs.x.ai/build/overview)
- [Official Grok Build source and user guide](https://github.com/xai-org/grok-build)
- [Configuration and harness compatibility](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/05-configuration.md)
- [Project rules](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/12-project-rules.md)
- [Skills and command discovery](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/08-skills.md)
- [Hooks and Claude compatibility](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/10-hooks.md)
- [Plugins and marketplaces](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/09-plugins.md)
- [Subagents and personas](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/16-subagents.md)
- [Headless mode and sessions](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/14-headless-mode.md)
- [Modes, commands, and workflows](https://docs.x.ai/build/modes-and-commands)
- [CLI reference](https://docs.x.ai/build/cli/reference)
