# 0009 — Review certification: scoped evidence + convergence breaker

## Status

Accepted (2026-06-05)

## Context

The code-review loop's head-rebind rule had freshness but no scope model: ANY HEAD movement invalidated the head-bound clean evidence and demanded "re-run reviewers at the new HEAD," dispatched in practice as full-branch reviews. Stochastic reviewers ~always find something in a big diff, so the exit condition ("both engines clean on the same pass") degenerated into a coincidence condition — and fix rounds minted new findings. In the field (msai-v2 PR #89, 2026-06), a branch that had been certified clean by both engines and authorized for merge hit a docs/CHANGELOG-only merge conflict; the conflict-resolution commit moved HEAD, the loop re-opened at full scope, and review spiraled from iteration 15 to 25 without converging — half a day of cost for a docs rebind, with no stopping rule. A 5-advisor council (Codex chairman) ruled the fix must be a machine-visible evidence contract, not prose guidance.

## Considered Options

- **Prose-only scope guidance:** tell the agent to scope re-reviews in command prose — **overruled by the council chairman**: agent-asserted scope is a trust gap; nothing stops a full-scope spiral or a fabricated "scoped" claim.
- **Gates validate format only, agent computes scope:** evidence grammar without recomputation — rejected: a `scope=mechanical` claim the gate cannot verify is self-certification.
- **Shared helper, recompute-don't-trust (chosen):** a read-only `hooks/lib/review-scope.{sh,ps1}` is the single source of truth for scope classification; the gates and `/goal` readiness RECOMPUTE every chain-dependent claim instead of trusting the recorded line.
- **Infinite full rebinds on high-impact surfaces:** keep full-scope re-reviews forever for risky code — overruled in favor of ONE deliberate **deep pass** at certification (default ON; repos may narrow via `CLAUDE.md ## Review Configuration`).

## Decision

A clean evidence line changes meaning: from "clean at HEAD" to **"review debt since the last clean evidence is discharged at HEAD."** The first pass where both engines are clean at `scope=full` on the same head is **certification**; after it, re-reviews are scoped to the effective **PR-owned delta** (whole-diff + per-file `git patch-id --stable` identity against the merge-base, `--no-renames`) plus the upstream interaction surface (merged-in AND still-pending default-branch movement). A docs-only/empty rebind is a recorded **mechanical re-stamp** — valid only when the gate's own recomputation agrees. Evidence is a coherent pair grammar (`scope=full|delta — base=… — head=…`, both engines, same scope/base/head; single-line mechanical/deep-pass/adjudication forms), parsed and enforced by `check-workflow-gates.{sh,ps1}` AND `build-evidence.{sh,ps1}` — chain construction re-validates every historical row (a fabricated mechanical-over-code or stale-base delta never becomes the trusted prior clean head; rebases fail closed to full). A hook-enforced **convergence breaker** (`POST_CERT_REVIEW_ROUND_LIMIT=3`, canonical in the helper) blocks ship after >3 post-certification rounds until a HUMAN records the head-bound adjudication line; in `/goal` the breaker halts for the human — council is never the risk-acceptor. The oscillation trigger (new-P0/P1-in-own-delta) is prose-mandated agent discipline with the round-limit as the machine backstop — finding severity is not recomputable from `state.md`, so a hook-enforced version would be self-reported theater (PRD US-003 amended to match). `SCOPE_REQUIRED` binds re-review dispatch and claim validation (rebind events) — an unchanged certified head is NOT ship-blocked by later default-branch drift (pre-existing behavior, deliberately unchanged). FIX-3 (P2-on-certified-code severity policy) stays deferred per the v5.50 precedent.

## Consequences

- ✅ A docs-only merge conflict after certification costs minutes (one mechanical re-stamp validated by recomputation), not a half-day full-review spiral.
- ✅ Non-convergence has a stopping rule with a named human authority: the breaker trips at a recomputable round count (the loop-counter line makes finding-rounds visible), and only the human adjudication line — never the agent, never council — unblocks ship.
- ✅ Scope is machine-visible and auditable in the evidence grammar; both platforms enforce identical semantics (parity pinned by contracts; the PS helper is dual-mode so hooks can consume it without spawning `pwsh`).
- ⚠️ Less variance resampling post-certification — intentional: repeated full-scope passes were re-rolling stochastic dice on certified code, which is exactly the incident shape. The deliberate deep pass at certification (default ON) is the compensating control for high-stakes surfaces.
- ⚠️ Scope freshness depends on the locally-known `origin/<default>`: dispatch-time `git fetch` (with mechanical lockout on fetch failure) is the freshness mechanism; the gates deliberately stay offline.
- 🔮 Betting that certification + scoped deltas preserve defect-catch rates at far lower cost. Future forks if data disagrees: plan-loop symmetry (apply the same model to plan review), the deferred FIX-3 severity policy, and recording the assessed default-ref tip (`default_head=`) if upstream-drift auditing proves necessary.
