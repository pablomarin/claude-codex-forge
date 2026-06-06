# 0009 — Convergence breaker for the code-review loop (scoped-certification engine built, then deliberately deferred)

## Status

Accepted (2026-06-06)

## Context

The code-review loop's head-rebind rule had freshness but no stopping rule: ANY HEAD movement invalidated the head-bound clean evidence and demanded "re-run reviewers at the new HEAD." Stochastic reviewers ~always find something in a big diff, so the exit condition ("both engines clean on the same pass") degenerated into a coincidence condition — and fix rounds minted new findings. In the field (msai-v2 PR #89, 2026-06), a branch certified clean by both engines and authorized for merge hit a docs/CHANGELOG-only merge conflict; the resolution commit moved HEAD, the loop re-opened at full scope, and review spiraled from iteration 15 to 25 without converging — half a day of cost with no stopping rule and no named human authority.

A first 5-advisor council ruled the fix must be machine-visible, not prose. A full **scoped-certification engine** was then built and certified (15 plan-review iterations, dual-engine code review, 1,081 assertions): scoped evidence grammar (`scope=full|delta|mechanical — base — head` coherent pairs), a `git patch-id`-based PR-owned-delta classifier, recompute-don't-trust gate validation, mechanical re-stamps for docs-only rebinds, and a default-ON deep pass. Before merge, the maintainer convened a **second council on community value** ("does this make the Forge better for the whole community?"). Chairman verdict: **NO as-is** — Simplifier and Scalability Hawk OBJECTed (sustained): the full engine ships an unmeasured O(changed-files) git fan-out into every downstream commit path, a runtime-unverified 450-line PowerShell twin, a deep-pass tax on every feature, and a wall-of-text operating model — all justified by ONE incident, when the breaker alone captures most of the value at a fraction of the surface. The maintainer ruled: **ship only the circuit breaker**.

## Considered Options

- **Full scoped-certification engine:** built, reviewed clean, live-E2E'd — and **deferred**. Preserved in branch history at commit `ece4eae` (recoverable wholesale). Deferred because community-distribution risks (PS runtime proof, hot-path latency bounds, observability/opt-out, doc learnability) outweigh the marginal benefit over the breaker for users who have never hit the incident class. Revisit if a second, different downstream user hits a spiral the breaker handles badly.
- **Prose-only guidance:** overruled by the first council — agent-asserted convergence discipline is the trust gap that produced the incident.
- **Convergence breaker only (chosen):** a small, recomputable stopping rule with a named human authority — no new evidence grammar, no diff machinery, no per-feature review tax.

## Decision

Ship the **convergence breaker**: a small read-only helper, `hooks/lib/review-breaker.sh` + dual-mode `review-breaker.ps1` (`Invoke-ReviewBreaker`), computes from `state.md` alone (only git call: `rev-parse HEAD`): **certification** = the first iteration where both engines recorded clean evidence at the same head (today's legacy evidence format — no new grammar); **rounds past certification** = the `Code review loop (N iterations)` counter (authoritative — finding-rounds bump it without writing clean rows), backstopped by counting post-cert evidence rows; **trip** at more than `POST_CERT_REVIEW_ROUND_LIMIT = 3` (canonical in the helper). When tripped and unadjudicated, `check-workflow-gates.{sh,ps1}` blocks every gated ship action — the check runs BEFORE the docs-only commit carve-out and outside the PASS-evidence branch, so neither an N/A escape nor a docs-only commit bypasses it; a count-less `Code review loop — N/A:` line after certification reads as counter erasure and trips fail-closed. Release is HUMAN-only: a head-bound `Post-certification tail adjudicated by human — <decision> — head=… — ts=…` checklist line that the agent never writes on its own initiative; in `/goal` runs the breaker halts for the human — `/council` is explicitly carved out as a substitute. `build-evidence.{sh,ps1}` expose `post_cert_rounds`/`breaker` (fail-open on helper absence — visibility only) and suppress `pr_ready` while tripped+unadjudicated, so an autonomous run halts visibly.

## Consequences

- ✅ Non-convergence now has a hard stop with a named human authority: the PR #89 shape costs at most 3 extra rounds, then pages the human with the open tail — instead of grinding to iteration 25.
- ✅ Tiny community footprint: ~100-line helper, no git diffing on the hot path, no new evidence grammar to hand-write, nothing for an uncertified or converging repo to notice (an untripped breaker is inert), and a PowerShell twin small enough to review line-by-line.
- ⚠️ Docs-only rebinds after certification still trigger full re-review rounds — bounded at 3, not eliminated. The scoped engine that would make them free is deliberately deferred; that residual cost is accepted.
- ⚠️ "Human-only adjudication" is procedural — the hook cannot prove a human typed the line. The head-binding and the explicit prose prohibition are the enforcement; the human reviews the audit trail at PR time.
- 🔮 Betting that the bound alone (not scope optimization) removes the incident pain. Falsifier: repeated breaker trips on legitimately-converging docs rebinds → revisit the deferred engine at `ece4eae`, starting from the second council's five conditions (PS runtime CI, latency ceiling + observability + opt-out, deep pass opt-in, decision-table docs, rollback path).
