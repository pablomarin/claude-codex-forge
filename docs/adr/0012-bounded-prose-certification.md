# 0012 — Retain certification for declared prose corrections

## Status

Accepted (2026-10-22). Amends only the accepted documentation-revalidation cost in ADR 0009.

## Context

A second developer reports that small changelog corrections invalidate the complete review,
verify-app and E2E set. The convergence breaker bounds repeated rounds but does not avoid them.
The final candidate must remain exact, and Forge's own Markdown can be executable agent policy.

## Considered Options

- Rebuild the deferred general scoped-certification engine: too much machinery for this case.
- Ignore all Markdown or docs-directory changes: unsafe for instruction, build and runtime inputs.
- Keep blanket invalidation: preserves integrity but repeats unrelated expensive work.
- Require an unchanged explicit prose scope and recomputed original-to-final proof: chosen.

## Decision

Keep the original full certification unchanged. A documentation closure validates fresh original
receipts, an unchanged tracked exact-path scope, the final staged-clean candidate and its complete
delta from the original tree. It runs the bounded prose check, protects release headings, and
rejects mixed functional or special-file changes. The shared shipping validator rechecks the proof.
Allow the same parent or the original candidate's proven exact Forge promotion. Preserve original
promotion evidence, receipt ages, review iteration and convergence anchor. Compare each further
correction to the original certification rather than chaining inherited receipts. Projects declare
non-runtime paths before certification; the source repository initially enrolls changelog narrative.

## Consequences

- Eligible prose corrections avoid new reviewers and application/E2E executions without claiming
  those executions tested different bytes.
- Functional changes and ambiguous inputs retain normal certification; no dependency mapper or
  arbitrary merge/rebase equivalence is introduced.
- The scope declaration is a project contract, not proof that prose has no runtime consumers.
  Generated documentation or changed external environments need relevant verification.
- The ADR 0009 convergence breaker remains unchanged and still applies to actual review rounds.
