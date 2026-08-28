# 0001 — Volatile workflow state lives at `.claude/local/state.md`, not auto-loaded

## Status

Amended by [ADR 0010](0010-dual-engine-canonical-harness.md) (2026-08-27). The non-auto-loaded,
gitignored state boundary remains; its canonical v6 path is `.forge/local/state.md`.

## Context

Forge transformed `CONTINUITY.md` from a single tracked file holding both durable team-shared facts and volatile per-developer working state into three artifacts (PR #2): durable content folded into `CLAUDE.md`, architecture decisions promoted to per-file ADRs in `docs/adr/`, and volatile per-developer state moved to a new file. The open question was where the volatile state file should live and whether Claude Code should auto-load it.

PR #1 (drift-hygiene) shipped 2026-04-28 to address a multi-developer staleness failure mode in which local `main` ran 97 commits behind origin while Claude was reading a tracked `CONTINUITY.md` as authoritative project state — confidently citing already-merged PRs as open. PR #1 patched the symptom via SessionStart `git fetch` + warning. PR #2 had to address the root cause: where does volatile per-developer state live, and how does it interact with Claude's auto-loaded context?

A 5-advisor council with a Codex chairman deliberated for one round. Three options were on the table:

- **A:** `.claude/local/state.md` — gitignored, NOT auto-loaded by Claude Code; the workflow rule routes Claude to read it on demand; hooks read it via shell. Novel Forge-only path.
- **B:** `CLAUDE.local.md` at project root — gitignored, AUTO-LOADED via Claude Code's directory walk; Anthropic's first-class documented mechanism (`code.claude.com/docs/en/memory` — "Local instructions" scope); `/init --personal` can auto-gitignore. Zero new convention.
- **C:** `.claude/state.md` — same shell-read behavior as A, no `/local/` subdir, less invented taxonomy. Surfaced during deliberation as a fallback if root auto-load was rejected.

## Considered Options

- **Option A (chosen):** `.claude/local/state.md`, gitignored, NOT auto-loaded. Hard-cut: hooks read only this file; if missing they emit a friendly stderr breadcrumb and don't gate.
- **Option B:** `CLAUDE.local.md` at project root, AUTO-LOADED via Claude Code directory walk. Reuses Anthropic's documented mechanism. Pros: zero new convention; `/init --personal` automation; first-class platform behavior. Cons: re-introduces auto-loading of volatile per-developer state — the same transport mechanism PR #1 patched. Token amplification on every session-start across N developers and M sessions; secrets pasted into "Now" by mistake auto-transmit on every session.
- **Option C:** `.claude/state.md` (no `/local/` subdir). Same shell-read behavior as A. Less invented taxonomy. Did not clearly outperform A once root auto-load was rejected.

## Decision

Forge ships volatile per-developer workflow state at `.claude/local/state.md`, gitignored, NOT auto-loaded by Claude Code. Hooks (`check-state-updated.{sh,ps1}` and `check-workflow-gates.{sh,ps1}`) parse it via shell. Claude reads it on demand when the workflow rule (`.claude/rules/workflow.md`) tells it to. The migration from legacy `CONTINUITY.md` is hard-cut: there is no fallback in hooks to the old file path.

## Consequences

- **Pro:** Volatile state stays out of auto-loaded context. Token cost is paid on demand, not on every session-start. Secrets pasted into the file by mistake do not auto-transmit on every session.
- **Pro:** Hook code is self-explanatory: `read .claude/local/state.md` clearly reads operational state, not preferences or instructions.
- **Pro:** Cross-developer contamination is solved (gitignore boundary).
- **Trade-off:** Forge introduces a repo-specific convention (`.claude/local/`) instead of using Anthropic's documented `CLAUDE.local.md`. The Simplifier's minority report flagged this as path-cost; weighed against the design correctness and overruled.
- **Trade-off:** A future Anthropic feature could claim the `.claude/local/` directory namespace. Mitigation: a 2-byte path change in setup.sh + the workflow rule. Low probability, easy reversibility.
- **Trade-off:** Discoverability is slightly worse than `CLAUDE.local.md` would be (nested vs root). Acceptable tax.
- **Future:** If field testing produces evidence that auto-loading a structured state file does NOT cause measurable model bias or token amplification, Option B may be revisited via a new ADR superseding this one.
- **Future:** If field testing produces evidence that the secret-leak risk is unfounded, that single Hawk objection weakens — but the Pragmatist's correctness argument (PR #1 root cause) and the Maintainer's data-vs-instructions argument both remain independent.

## Council deliberation

5 advisors (Simplifier-Claude, Pragmatist-Claude, Scalability-Hawk-Claude, Contrarian-Codex, Maintainer-Codex) + Codex chairman with high reasoning depth. Phase 1 Contrarian Gate returned OBJECT (auto-load alone does not falsify CLAUDE.local.md; PR #1's bug was shared stale state, not auto-load semantics per se). Per protocol, escalated to full council on high-impact-surface ground.

Final tally: Pragmatist APPROVE A · Hawk APPROVE A (OBJECT to B) · Maintainer CONDITIONAL on A · Simplifier OBJECT to A (wants B) · Contrarian CONDITIONAL leaning B with schema discipline (also surfaced Option C).

Chairman key reasoning: "PR #1 proved that stale state in model context is harmful; shared tracking was the trigger, but auto-load was the transport. Fixing only the sharing problem and keeping root auto-load would be a partial fix on a high-impact default."

Five blocking conditions captured into the implementation plan: see `docs/plans/2026-04-28-continuity-split.md` Acceptance Criteria AC-1 through AC-5.
