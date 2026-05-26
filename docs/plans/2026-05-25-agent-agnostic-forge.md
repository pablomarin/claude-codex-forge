# Agent-agnostic forge: PR-by-PR transformation plan (v2)

**Date:** 2026-05-25
**Status:** v2 — post-Codex review (revised per concrete primitive findings)
**Branch (when work starts):** TBD — separate worktrees per PR

> **v1 → v2 changes:** Codex review identified 7 technical errors + 4 structural problems in v1. Notable corrections: Codex has no project-level custom slash commands (workflow must be reshaped as skills); Codex's `/goal` already exists (no need to invent); Codex skills install to `.agents/skills/` not `.codex/skills/`; Stop hook ordering can race under Codex's concurrent dispatch; `PostToolUse` shape differs (`apply_patch` with `tool_input.command` vs Claude's `Edit/Write` with `tool_input.file_path`); memory model migration was missing; permission/sandbox model was missing. Revised estimate: **6–10 weeks**, 13 PRs (added 2, reshaped 3).

---

## Strategic framing

**The goal:** the forge becomes a platform-neutral coding-agent harness. A developer picks Claude Code OR Codex as the driver; the forge's workflow, skills, hooks, council, and `/forge-goal` work identically on either. The forge owns all the skills it depends on.

**Research findings (2026-05-25, validated by Codex review):**

| Primitive | Claude Code | Codex CLI 0.125.0 | Status |
| --- | --- | --- | --- |
| **Hook events** | `Stop`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `PreCompact`, `SubagentStop`, `SessionStart`, `UserPromptSubmit`, `ConfigChange` | `Stop`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `PreCompact`, `PostCompact`, `UserPromptSubmit`, `SubagentStop`, `SubagentStart`, `SessionStart` | ✓ Confirmed |
| **Hook execution order** | Sequential within a matcher | **CONCURRENT** within an event (no ordering guarantee) | ⚠ Forge's Stop ordering (build-evidence → check-state-updated) breaks |
| **Hook handler type** | `command` and others | **`command` only** (prompt and agent handlers parsed but skipped) | ⚠ Forge's SubagentStop prompt hook must be re-typed |
| **Hook stdout for Stop** | Free-form, exit-code controls flow | **Must be valid JSON or empty for exit 0** | ⚠ Forge's stderr-only Stop hooks need empty JSON stdout |
| **Hook trust** | Free execution | Hash-trust per hook via `/hooks` slash command | ⚠ First-install requires trust ceremony |
| **Edit tool name** | `Edit`, `Write` with `tool_input.file_path` | `apply_patch` with `tool_input.command` (Edit/Write are matcher aliases) | ⚠ post-tool-format.sh assumes file_path |
| **Skills path** | `.claude/skills/` | **`.agents/skills/`** (walks CWD up to repo root) | ⚠ Plan v1 had wrong path |
| **Custom project slash commands** | `.claude/commands/*.md` | **NOT SUPPORTED** — only built-in `/goal`, `/skills`, `/hooks`, `/plugins`, etc. | ⚠ FATAL: PR-B3 v1 cannot ship as written |
| **Project instructions** | `CLAUDE.md` | `AGENTS.md` (layered discovery + `AGENTS.override.md` + 32 KiB cap) | ✓ Acceptable for first pass |
| **Autonomous loop** | `/goal` native | **`/goal` native** (CLI + app + IDE) | ✓ Already exists — integrate, don't invent |
| **Memory** | `~/.claude/projects/.../memory/` (always-on, file-based) | `~/.codex/memories` (experimental, off by default, Chronicle research preview) | ⚠ Migration needed |
| **Permissions/sandbox** | `settings.json` permissions object | Permission profiles + workspace roots + network policy + OS sandboxing (default: no network, workspace-limited writes) | ⚠ Cannot mechanically translate |
| **MCP servers** | `.mcp.json` | `codex mcp` config | ✓ Same MCP protocol |
| **Subagents** | Task tool | `multi_agent` stable | ✓ Parallel |
| **Plugins** | Plugin marketplace + `enabledPlugins` | `codex plugin marketplace` + `[plugins."name@source"]` in config.toml. **Marketplace/TUI-oriented; no `codex plugin install <local>` CLI** | ⚠ Plugin packaging path is marketplace, not local-install |

**Working assumptions (revised):**
- Hook scripts are NOT trivially portable. Five concrete divergences need code changes (ordering race, handler type, stdout JSON, apply_patch shape, trust ceremony).
- Skill content IS portable (markdown + frontmatter) but install path differs (`.agents/skills/`).
- Memory and permissions need their own PRs.
- `/goal` integration replaces "invent autonomous loop".

**Three phases, 13 PRs:**

- **Phase A** (4 PRs) — Skill ownership (Superpowers divorce). Pre-req for everything else.
- **Phase B** (6 PRs) — Dual-platform install + portability fixes + skills-as-workflow + permissions + memory.
- **Phase C** (2 PRs) — Native `/goal` integration + council inversion.
- **Phase E** (1 PR, optional) — Codex plugin marketplace presence.

---

## Phase A: Skill ownership (Superpowers divorce)

### PR-A1: Fork `forge:writing-plans` — preceded by contract-inspection discovery

**Risk reassessment:** Codex flagged this as not "low" — current commands depend on writing-plans' exact header shape and then mutate the output (`new-feature.md` Phase 3.2, `fix-bug.md` Phase 3.2). Must inspect first.

**Scope (with discovery step):**

1. **Discovery (inline, not separate PR):** read current `/superpowers:writing-plans` SKILL.md. Document the contract the forge depends on: required header (`# <Name>` H1 + `**Goal:**` / `**Architecture:**` / `**Tech Stack:**`), the position of the Approach Comparison block insertion, how the spec → plan handoff currently works.
2. Create `skills/writing-plans/SKILL.template.md` matching the documented contract exactly.
3. Replace path default `docs/superpowers/plans/YYYY-MM-DD-<feature>.md` → `docs/plans/<feature>.md`.
4. Update `setup.sh` + `setup.ps1` to copy to `.claude/skills/writing-plans/SKILL.md`.
5. Update workflow command references in `commands/new-feature.md` Phase 3.2 + `commands/fix-bug.md` Phase 3.2.
6. Contract test: assert no `superpowers:writing-plans` references in workflow commands; assert the header shape contract is documented in the new SKILL.md.

**Exit criteria:**
- Discovery doc landed (can be inline in the SKILL.md or separate `docs/explanation/`)
- Dogfood `/new-feature test-feature` in `../mcpgateway` reaches Phase 3.2 and writes the plan to `docs/plans/test-feature.md` with the same header shape v1 expected.
- All four hot-path suites pass.

**Risk:** medium (was "low" in v1). Contract inspection is the unknown.

---

### PR-A2: Fork `forge:brainstorming`

**Scope:**
- Create `skills/brainstorming/SKILL.template.md` (copy from Superpowers 5.1.0, ~250 lines).
- Replace path `docs/superpowers/specs/...` — **decision required**: fold spec into the plan file OR skip the separate spec-write. Recommend fold; the forge's plan file already carries design rationale.
- Integrate Approach Comparison + Contrarian Gate as native skill steps (currently the workflow command handles these around the brainstorming invocation; folding them in is cleaner).
- Update workflow commands.

**Exit criteria:**
- No `docs/superpowers/` directories created during a dogfood run.
- `/new-feature` reaches Phase 3 brainstorming, produces Approach Comparison + design rationale in `docs/plans/<feature>.md`.

**Risk:** medium. Could split into two sub-PRs if integration is complex.

---

### PR-A3: Fork `forge:subagent-driven-development`

**Scope:**
- Create `skills/subagent-driven-development/SKILL.template.md` (~400 lines).
- Adjust path references (plan file = `docs/plans/`).
- Update workflow commands Phase 4.

**Exit criteria:**
- Dogfood `/new-feature` Phase 4 dispatches subagents per task end-to-end.
- The two-stage review (spec + quality) still fires per task.

**Risk:** medium. Execution engine — bugs block feature work.

---

### PR-A4: Fork `forge:systematic-debugging` + drop superpowers from settings

**Scope:**
- Fork `superpowers:systematic-debugging`.
- **Decision:** drop `executing-plans` (the rarely-used Phase 4 inline executor alternative)? Recommend drop.
- Remove `enabledPlugins["superpowers@..."]` entirely from `settings.template.json`.
- Contract test: no `superpowers:` references anywhere in workflow commands or settings.

**Exit criteria:**
- Zero `superpowers:` references in shipped templates.
- `/fix-bug` works end-to-end with `forge:systematic-debugging`.

**Risk:** low (mechanical).

---

## Phase B: Dual-platform install + portability fixes

### PR-B0 (NEW): Codex primitive validation spike

**Why:** Codex review pointed out PR-B1+ assumes specific behaviors (skill discovery, hook ordering, stdout JSON, etc.) without direct verification. Spike first.

**Scope (research, no production code):**
- Install Codex CLI in a clean test repo.
- Verify:
  - `.agents/skills/<name>/SKILL.md` is discovered correctly (walking from CWD up).
  - Stop hook ordering: are concurrent hooks REALLY simultaneous, or is there an ordering primitive we can use?
  - Stop hook stdout requirement: empty string vs `{}` vs nothing — what's accepted?
  - `apply_patch` PostToolUse: what's the JSON shape, can we extract file paths from `tool_input.command`?
  - `/goal` integration: can it consume FORGE_GOAL_EVIDENCE-format JSON from Stop hooks across turns?
  - AGENTS.md layered discovery + override semantics.
  - Trust ceremony UX: what does the user actually do?
- Document findings in `docs/explanation/codex-primitives.md`.

**Exit criteria:** every assumption in PR-B1 onwards is empirically validated against actual Codex CLI behavior, not docs alone.

**Risk:** medium. Spike might surface MORE divergences. Better to find them now than mid-PR.

---

### PR-B1 (RESHAPED): Hook portability fixes for Codex

**v1 had:** assumed hooks were already portable thanks to v5.32 `cwd`-from-stdin. **Codex review found five concrete blockers:**

**Scope:**
1. **Stop hook ordering race fix.** Currently `build-evidence.sh` writes a fingerprint side-channel that `check-state-updated.sh` reads. Under Codex's concurrent dispatch, `check-state-updated` might run BEFORE `build-evidence`. Fix:
   - Make `check-state-updated.sh` self-sufficient: if the fingerprint side-channel is missing OR older than current invocation, re-invoke `build-evidence.sh` inline. Idempotent.
   - OR merge the two hooks into one ordered script.
   - OR write fingerprint to a stable hash of the state (no side-channel file needed).
2. **Empty JSON on Stop stdout.** Forge's Stop hooks currently emit stderr-only + exit 0. Codex requires valid JSON or empty on stdout. Add `printf '{}\n'` to all Stop hooks before `exit 0`.
3. **`apply_patch` PostToolUse.** `post-tool-format.sh` currently expects `tool_input.file_path`. Codex's `apply_patch` uses `tool_input.command` (the patch text). Parse the patch to find affected files. Same logic in `.ps1` version.
4. **Remove prompt-type hooks.** `settings.template.json` has a `SubagentStop` prompt hook (Sonnet evaluates subagent output). Codex only runs `command` hooks. Either remove this hook OR rewrite as a command hook that invokes a model via API.
5. **Trust ceremony UX.** Document in `docs/guides/upgrading.md`: "first install on Codex requires `/hooks` review and trust" — include exact steps.

**Exit criteria:**
- All forge hooks work under Codex (validated by PR-B2 smoke tests).
- Stop hook concurrency-safe (test with deliberately racing hooks).
- `apply_patch` PostToolUse correctly identifies modified files.

**Risk:** high. This is the dense divergence area. May surface more issues during implementation.

---

### PR-B2 (RESHAPED): setup.sh `--target claude|codex|both` + correct skill paths

**v1 had:** `.codex/skills/`. **v2:** `.agents/skills/` per Codex's actual spec.

**Scope:**
- `setup.sh` + `setup.ps1` gain `--target {claude|codex|both}` flag (default: `claude`).
- For `--target claude`: unchanged.
- For `--target codex`:
  - Hooks: `.codex/hooks.json` (or `[hooks]` in `.codex/config.toml`)
  - Skills: **`.agents/skills/<name>/SKILL.md`** (NOT `.codex/skills/`)
  - Commands: skip — Codex has no custom slash commands; workflow lives elsewhere (see PR-B3).
  - Generate `AGENTS.md` alongside `CLAUDE.md` (identical content; document the override-file convention but don't ship one).
- For `--target both`: write both `.claude/` and `.codex/`; share `.agents/skills/` between them (Codex reads here, Claude can too via the same path).
- Migration: existing installs unaffected when `--target` is omitted.
- New helper script: `scripts/translate-settings.py` — converts `.claude/settings.json` (JSON) to `.codex/config.toml` `[hooks]` table.

**Exit criteria:**
- `./setup.sh -p Test -t fullstack --target codex` writes a working `.codex/` + `.agents/skills/` + `AGENTS.md`.
- `cd <project> && codex` loads the agent with AGENTS.md visible.
- Existing claude-only installs unaffected.

**Risk:** medium. Schema translation is the tricky part.

---

### PR-B3 (RESHAPED): Workflow-as-skills for Codex (NOT slash commands)

**v1 had:** `.codex/commands/*.md`. **v2:** Codex has no custom slash commands. Workflow must be reshaped as skills the user invokes by name.

**Scope:**
- Each workflow command (`/new-feature`, `/fix-bug`, `/quick-fix`, `/finish-branch`, `/codex` → `/second-opinion`, `/council`, `/forge-goal`) gets a Codex-shaped skill at `.agents/skills/<name>/SKILL.md`.
- The skill content IS the prompt the user types: `"Run the new-feature workflow for <name>"` invokes the skill, which loads the same prose the slash-command version had.
- Document in `AGENTS.md` how to invoke each skill from Codex.
- For Claude Code: continue using `.claude/commands/<name>.md` as before. Same content, two install paths.
- Update workflow commands to be skill-format-compatible (frontmatter + clear invocation prose).

**Exit criteria:**
- Codex user can run `Run /new-feature <name>` (or equivalent skill invocation) and get the same workflow.
- Skill content is shared between Claude and Codex install paths.
- No regression on Claude-side slash-command invocation.

**Risk:** medium-high. Skill invocation UX in Codex may be more verbose than Claude's `/command`. Acceptable tradeoff.

---

### PR-B4 (NEW): Permissions/sandbox model translation

**Why this PR exists:** Codex has explicit permission profiles, workspace roots, network policy, and OS sandboxing — none of which `settings.json`'s `permissions.allow/deny/ask` arrays translate to mechanically. The autonomous loop, `gh pr create`, package managers, and MCP all depend on permission semantics.

**Scope:**
- Audit `settings.template.json`'s `permissions` for items that need Codex equivalents.
- Define a mapping: `Bash(...)` patterns → Codex permission profile entries; `Read(*)`/`Write(*)` → workspace root config; network access → Codex network policy.
- Write `scripts/translate-permissions.py` invoked by `setup.sh --target codex`.
- Document the differences in `docs/reference/permissions.md` — what works the same, what's different.
- Decision: for `--target both`, do we ship a unified permissions vocabulary? Recommend NO — keep them platform-native, with the forge documenting what each enables.

**Exit criteria:**
- Codex install has equivalent permission posture to Claude install (deny dangerous commands, allow safe ones).
- `gh pr create` works in codex sessions if permissions allow it.
- Forge's autonomous loop's network/git calls all work under Codex sandbox.

**Risk:** medium. Codex permission model is well-documented but new to the forge.

---

### PR-B5 (NEW): Memory model — forge-owned, platform-independent

**Why this PR exists:** the forge writes to `~/.claude/projects/<dir>/memory/` everywhere (`setup.sh` global memory + `commands/new-feature.md` finish steps tell agents to save to Claude auto-memory). Codex's `~/.codex/memories` is experimental, off by default, and has different shape. Cannot mechanically translate.

**Scope:**
- Move forge's memory convention from `~/.claude/projects/<dir>/memory/` to `.forge/local/memory/` in the project (or `~/.forge/memory/<project>/` globally if cross-project memory is desired).
- Memory is platform-independent — both Claude and Codex sessions write to the same location.
- Update `commands/new-feature.md` "Compound learnings" step + global `~/.claude/CLAUDE.md` memory instructions to point at the new location.
- Document in `docs/explanation/memory-architecture.md`: forge owns memory, NOT the agent platform.
- Migration: existing memory in `~/.claude/projects/.../memory/` stays where it is — the forge reads from BOTH locations during transition, only writes to the new one.

**Exit criteria:**
- Forge's memory survives switching between Claude and Codex drivers.
- Existing memory data preserved; no data loss on upgrade.
- Documentation explains the new location.

**Risk:** medium. Memory is load-bearing; migration must not lose data.

---

## Phase C: Native `/goal` integration + council inversion

### PR-C1 (RESHAPED): Integrate native Codex `/goal` into the forge workflow

**v1 had:** "Research whether Codex has /goal". **v2:** Codex `/goal` exists; this PR INTEGRATES it.

**Scope:**
- Verify (in spike sub-step): can Codex `/goal` consume FORGE_GOAL_EVIDENCE JSON from Stop hooks? Does it persist nonce across turns? Does it pause for `AskUserQuestion`-style PR-create gates?
- Update `commands/new-feature.md` PRD-Complete Checkpoint and `commands/fix-bug.md` Plan-Approved Checkpoint: print Codex-flavored `/goal` command when running under Codex (detected via `FORGE_DRIVER` env var or marker file).
- Codex Stop hook behavior: ensure evidence is emitted correctly across `/goal` turns.
- PR-create authorization: design the Codex equivalent of `AskUserQuestion` modal. If Codex has it natively, use it; if not, document a prose-prompt fallback.
- Stale-evidence prevention by nonce — same logic as Claude side.

**Exit criteria:**
- Codex-driven autonomous run from PRD-Complete → PR-Open works end-to-end.
- PR-create authorization fires correctly.
- Evidence schema works for both platforms with the same nonce-anchoring.

**Risk:** medium (smaller than v1's high). `/goal` exists; integration is the work.

---

### PR-C2 (RESHAPED): Council inversion + driver detection

**v1 had:** "chairman by driver" as PR-D1. **v2:** combined with explicit driver detection mechanism, since C1 needs it too.

**Scope:**
- Define `FORGE_DRIVER` detection mechanism: env var (set by setup.sh), or marker file (`.forge/local/driver`), or auto-detect via presence of `.claude/` vs `.codex/`.
- `skills/council/SKILL.template.md` — chairman selection becomes `FORGE_DRIVER`-aware.
- `skills/council/references/advisors.md` — persona engine assignments reversible (each persona has claude-engine and codex-engine variants).
- Default: chairman = OTHER agent from the driver.
- Tests: contract assertion that both chairman flavors are supported and driver detection works.

**Exit criteria:**
- `/council` from Claude session uses Codex chairman + 3 Claude personas + 2 Codex personas.
- `/council` from Codex session uses Claude chairman + 3 Codex personas + 2 Claude personas.
- Driver detection is reliable (env var + marker file + fallback).

**Risk:** medium (was low). Driver detection is the new wrinkle.

---

## Phase E: Optional — marketplace presence

### PR-E1: Forge as a Codex plugin

**Scope:**
- Restructure forge templates into a Codex plugin manifest per Codex marketplace specs.
- Codex plugin install path is marketplace-oriented (`codex plugin marketplace` + per-project enable in `config.toml`). NOT a `codex plugin install <local>` CLI.
- Either: submit to Codex public marketplace OR maintain as a self-hosted source the user adds via `codex plugin marketplace add`.
- Same artifact, alternate install method.

**Exit criteria:** users can install the forge from a Codex marketplace source as an alternative to `setup.sh --target codex`.

**Risk:** low — additive.

---

## Cross-cutting concerns

| Concern | Approach |
| --- | --- |
| **Backward compat** | Existing `.claude/`-only installs keep working through Phase A + B. Phase C may introduce optional codex paths but never breaks claude-default. |
| **Test discipline** | Every PR adds contract assertions for its new vocabulary. Hot-path suites stay at 0 failed. |
| **Codex smoke tests** | Once PR-B0 lands, every Phase B+ PR runs both claude smoke + codex smoke. |
| **Doc parity** | Each PR updates `README.md` + `docs/explanation/workflow.md` + relevant guides to reflect the dual-platform reality. |
| **CHANGELOG** | Each PR bumps version (v5.39, v5.40, …). |

## Revised estimate

- Phase A (4 PRs): 1.5–2 weeks. Largely unchanged.
- Phase B (6 PRs): 3–5 weeks. Doubled from v1 because:
  - PR-B0 (spike) added (was missing)
  - PR-B1 reshaped from "test portability" to "fix 5 concrete blockers"
  - PR-B3 reshaped from "ship slash commands" to "reshape workflow as skills"
  - PR-B4 (permissions) added
  - PR-B5 (memory) added
- Phase C (2 PRs): 1–2 weeks. Down from v1 because `/goal` exists.
- Phase E (1 PR, optional): 2–4 days.

**Total: 6–10 weeks calendar, 13 PRs.** Matches Codex's revised estimate.

## Decision points along the way

1. **After PR-A2**: should brainstorming write a separate spec file or fold into the plan file? (Recommendation: fold.)
2. **After PR-A4**: drop `executing-plans` entirely or fork it? (Recommendation: drop.)
3. **After PR-B0**: if spike surfaces blockers we can't fix, do we scope Phase B down to "Claude-only with skill ownership" and defer Codex? (Recommendation: yes — Phase A still has value standalone.)
4. **After PR-B3**: do we accept that Codex users invoke workflow via skill names (slightly more verbose than `/command`) or do we petition Codex for custom slash command support? (Recommendation: accept the trade-off.)
5. **After PR-B4**: unified permission vocabulary or platform-native? (Recommendation: platform-native.)
6. **After PR-C1**: if Codex `/goal` doesn't pause for PR-auth, do we accept a prose-prompt fallback? (Recommendation: yes, document the difference.)
