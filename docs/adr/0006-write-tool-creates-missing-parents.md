# 0006 — Trust the Write tool to create missing parent directories

## Status

Accepted (2026-05-09)

## Context

Branch `fix/state-migration-via-write-tool` (v5.24) was originally written assuming the Write tool does **not** reliably create parent directories. That assumption drove a defensive `mkdir -p .claude/local` retained inside the STATE-INIT bash block (gated to fresh-worktree first-init only) — necessary because `.claude/local/` is gitignored and missing in worktrees.

The `mkdir` retention created three downstream problems that the Engineering Council flagged:

1. **Internal contradictions in the workflow text** — Step 2a was labeled "read-only" but ran `mkdir`; Step 2b said Write "creates parent dirs implicitly" while shell comments said it "does NOT reliably create parent dirs."
2. **A residual permission prompt** — Anthropic's docs are explicit that writes under `.claude/` are never auto-approved by baseline modes/rules except `bypassPermissions`. The retained `mkdir` therefore prompts on first invocation in every fresh worktree.
3. **AC-2d** — a contract test that explicitly whitelisted `mkdir` under `.claude/`, locking in the workaround as the supported behavior.

Per the council's Minority Report (Contrarian + Hawk + Maintainer), the underlying assumption was unproven. We ran the spike the Hawk requested (~2 minutes) before merging.

## Considered Options

- **Option A (chosen):** Capture the empirical Write parent-dir behavior in this ADR, drop `mkdir` from the workflow, simplify contract tests, and reframe the CHANGELOG honestly as "zero prompts on the state-init path."
- **Option B:** Keep `mkdir` as defense-in-depth in case some Claude Code version regresses on Write parent-dir creation. Rejected: defensive code without a captured failure case becomes folklore (Maintainer's exact concern).
- **Option C:** Try Write first, fall back to `mkdir` + retry on failure. Rejected: agent fallback logic in prose is fragile, and we have no captured failure to motivate it.

## Decision

The Write tool creates missing parent directories on the supported Claude Code surface. The `fix/state-migration-via-write-tool` branch drops the retained `mkdir`, AC-2d, and the contradictory comments. Step 2a becomes truly read-only.

### Captured evidence (the spike the council asked for)

| Variable                 | Value                                                                                                          |
| ------------------------ | -------------------------------------------------------------------------------------------------------------- |
| Date                     | 2026-05-09                                                                                                     |
| OS                       | macOS 26.2 (build 25C56)                                                                                       |
| Claude Code              | 2.1.138                                                                                                        |
| Test path                | `/tmp/forge-write-spike.MirUrQ/.claude/local/state.md` (absolute, parent missing)                              |
| Pre-state                | Scratch dir empty — `.claude/`, `.claude/local/` did not exist                                                 |
| Tool invocation          | `Write(file_path=<above>, content=<single line>)`                                                              |
| Result                   | "File created successfully" — both `.claude/`, `.claude/local/`, and `state.md` materialized in one Write call |
| Permission prompt fired? | No                                                                                                             |

This invalidates the prior "Write doesn't reliably create parent dirs" comment in the workflow. The Forge ships the result-of-this-spike, not the assumption.

## Consequences

- ✅ True zero-prompt state-init on fresh worktrees. No `mkdir` prompt, no `cp` prompt.
- ✅ STATE-INIT block becomes truly read-only — Step 2a/2b/2c labels are now consistent with what the code does.
- ✅ Contract tests can ban **all** Bash writes under `.claude/` (no `mkdir` exception). AC-2d is removed; AC-2b is tightened.
- ✅ CHANGELOG can honestly say "zero prompts" instead of "at most one prompt on the idempotent mkdir."
- ⚠️ We're betting on Write parent-dir behavior remaining stable across future Claude Code versions. Codex review iter-2 surfaced the codex-pty-helper saga (v5.22) as evidence that CC behavior can shift between minor releases. If Write regresses on parent-dir creation, the symptom will be a clear "no such file or directory" error from Write — loud, not silent — and the fix is to re-add `mkdir` (one-line revert from this ADR's commit).
- ⚠️ Windows / WSL behavior is untested. If a Windows user reports Write failing with ENOENT on missing parent, this ADR gets revisited. The `setup.sh`/`setup.ps1` parity rule (ADR 0005) would normally force testing both, but the Write tool itself is implemented by Claude Code (not the Forge), so the platform behavior question is upstream.
- 🔮 Invalidating signal: any in-the-wild report of `/new-feature` or `/fix-bug` failing at state init with ENOENT on `.claude/local/state.md`. If that happens on a CC version newer than 2.1.138, we reopen this ADR and reintroduce `mkdir` (or a Bash-PreToolUse hook scoped to `mkdir -p .claude/local`).
