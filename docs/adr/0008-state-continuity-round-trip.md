# 0008 — Per-developer continuity narrative round-trips through main (seed + guarded deterministic fold-back)

## Status

Accepted (2026-06-02)

## Context

ADR 0001 moved volatile per-developer workflow state to `.claude/local/state.md` — gitignored, not auto-loaded — to kill the cross-developer staleness bug a tracked `CONTINUITY.md` had caused. That split was correct, but it left a regression that only surfaced in the field (msai-v2, 2026-06): the per-developer **continuity narrative** (the `## State` Done/Now/Next/Deferred story, plus `## Open Questions` and `## Blockers`) became **worktree-local and ephemeral**.

Concretely: `/new-feature` and `/fix-bug` initialize a _blank_ worktree `state.md` from the template (`new-feature.md` STATE-INIT, `git rev-parse --show-toplevel` = the worktree), and `/finish-branch` runs `git worktree remove --force`, which deletes the worktree's working tree — including the gitignored `state.md`. Step 2.8 only cleared main's `## Workflow` section; it never carried the narrative back. So a developer's confirmed operational facts ("the writable-KV apply + spike is done — don't re-propose it") died at every merge, and main's `state.md` was perpetually stale. This regressed the cross-session continuity the legacy `CONTINUITY.md` used to provide for a single developer.

The developer works **one feature at a time** (parallel worktrees are rare). That fact is the hinge: it collapses the concurrency concerns that would otherwise force a heavier design.

## Considered Options

- **Mechanism 1 — common-dir singleton:** split the file; move the narrative to a per-clone file in the git common dir, read+appended by all worktrees, with locking + provenance + a corruption detector. Correct for true parallel use, but heavy (new file, new lifecycle, lock portability across Bash/PowerShell) — unjustified for one-feature-at-a-time.
- **Mechanism 2 — share main's `state.md` from worktrees:** rejected unanimously by council — it re-couples the gate machinery (`## Workflow`, `/goal` nonce, PR-auth head-SHA) across worktrees and is a lost-update / gate-corruption generator.
- **Mechanism 3+ / agent LLM merge (A):** seed the worktree from main, and at finish let Claude semantically merge (keep/update/delete-if-resolved) with preservation bias. Matches the user's literal "smart merge" ask, but non-deterministic, not unit-gradeable, and its failure mode (a dropped/hallucinated item) is undetectable because the worktree `state.md` is destroyed moments later.
- **Guarded B (chosen):** deterministic narrative-section **replace**, guarded by a seed-time **snapshot**, with a **loud safe-stop** on divergence.

## Decision

The continuity narrative **round-trips through main**, gitignored throughout (ADR 0001's tracked-state prohibition is preserved — nothing is committed):

1. **Seed-on-create** (`/new-feature`, `/fix-bug`): a fresh worktree's foldable narrative is copied verbatim from main's `state.md` with `### Now` cleared, and a narrative-only **seed snapshot** is written to `.claude/local/.state-seed-snapshot.md` (gitignored, worktree-local).
2. **Guarded fold-back** (`/finish-branch`, step 2.2b, **before** `git worktree remove`): compare main's current foldable narrative to the seed snapshot. **Match** → deterministically replace main's foldable sections (`### Done`/`### Next`/`### Deferred`, `## Open Questions`, `## Blockers`) with the worktree's, `### Now` emptied, gate sections untouched. **Diverged / snapshot missing / structurally incomplete / worktree state absent** → loud safe-stop, no overwrite, files left intact for manual reconciliation.

The deterministic replace is correct because, under sequential use, the worktree narrative is the seed-forward successor of main's — so a replace already encodes every leave/update/delete the developer made. The snapshot guard handles the one case where that premise breaks (main changed since seed — a hand-edit, a quick-fix, a hook, or a rare parallel sibling): rather than silently erase, it stops loudly. The full LLM merge (A) is **deferred**; divergence is a safe-stop, not an automatic merge.

Decided via the Phase 3.1c Contrarian Gate (OBJECT → escalated) and a 5-advisor council; chairman verdict = guarded B. This refines the user's literal "smart merge" preference (intent preserved, mechanism made deterministic + safe); the delta is flagged in the PR body for the user's final call at review.

## Consequences

- **Pro:** Cross-session + cross-worktree continuity is restored for the single developer; main's `state.md` is current after every finish. Deterministic and unit-testable (contract tests pin the scaffold, ordering, section-scoping, divergence guard, and the byte-identical (indent-normalized) `EXTRACT-FOLDABLE` block across the three command files). No silent data loss — divergence fails loud (honoring Forge's detect-and-surface posture).
- **Pro:** ADR 0001 stands — `state.md` and the snapshot are both gitignored; nothing is re-tracked into main.
- **Trade-off:** A worktree **abandoned** without ever running `/finish-branch` still loses its narrative (no merge fires) — a documented known gap, deferred.
- **Trade-off:** A rare divergence (parallel sibling, hand-edit) does not auto-merge — the developer reconciles by hand. Acceptable given the frequency and the cost of the non-deterministic alternative.
- **Trade-off:** The `EXTRACT-FOLDABLE` extractor is pasted in three places (kept byte-identical, indent-normalized, by contract) rather than shared — command docs cannot share a function across files.
- **Future:** If parallel-worktree continuity becomes common, or if the divergence safe-stop proves annoying, an opt-in LLM-merge fallback (A) or a common-dir singleton (mechanism 1) can be introduced via a superseding ADR. This ADR **complements**, and does not supersede, ADR 0001.
