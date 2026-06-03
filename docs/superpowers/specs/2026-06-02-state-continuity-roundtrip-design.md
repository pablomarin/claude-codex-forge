# Design: State Continuity Round-Trip

**Date:** 2026-06-02
**Topic:** Make the per-developer continuity narrative in `.claude/local/state.md` survive worktree teardown by round-tripping it through main.
**Status:** Validated — Phase 3.1c Contrarian Gate escalated to full council; chairman verdict = **guarded B** (deterministic replace + seed snapshot + loud safe-stop on divergence). Supersedes the earlier agent-driven-smart-merge default.
**PRD:** `docs/prds/state-continuity-roundtrip.md`
**Research:** `docs/research/2026-06-02-state-continuity-roundtrip.md`
**Prior decisions:** (1) 5-advisor council → mechanism 3+ (round-trip), deciding fact = one feature at a time. (2) Phase 3.1c council → **guarded B** mechanism for the fold-back (this session).

## Problem (one paragraph)

`/new-feature` and `/fix-bug` initialize a **blank** worktree-local `state.md` (`new-feature.md:211/223`), and `/finish-branch` deletes the worktree (and its gitignored `state.md`) while only clearing main's `## Workflow` section. The per-developer continuity narrative (Done / Now / Next / Deferred + Open Questions + Blockers) therefore dies at every merge, and main's `state.md` is perpetually stale. We want the narrative to round-trip through main — without re-tracking it into git (ADR 0001) and without new files/locking beyond a small per-worktree snapshot.

## Mechanism (council-decided: guarded B)

The fold-back is a **deterministic narrative-section replace**, guarded by a seed-time snapshot so it never _silently_ erases main-side changes:

- **Seed-on-create** copies main's narrative into the worktree (Now cleared) AND writes a **narrative-only seed snapshot** capturing exactly the foldable sections as they were at seed time.
- **Fold-back-on-finish** (before `git worktree remove`): compare main's _current_ foldable narrative to the seed snapshot.
  - **Unchanged** → deterministically replace main's foldable sections with the worktree's. (Correct: the worktree narrative is the seed-forward successor of main's.)
  - **Changed / snapshot missing / malformed / worktree state.md absent** → **fail loud**: emit a visible warning, do NOT replace, leave the worktree and both state files intact for manual reconciliation.

The smart/agent LLM merge (option A) is explicitly **NOT** built in this PR — the divergence path is a safe-stop, not an LLM merge. This honors the user's _intent_ (main reflects reality; leave/replace/delete are encoded by editing the worktree narrative forward) while being deterministic, unit-testable, and free of silent data loss. The deterministic-vs-LLM delta is flagged in the PR body for the user's final call at review.

## Foldable sections (explicit)

- **Foldable** (snapshotted + replaced on fold-back): `### Done`, `### Next`, `### Deferred` (under `## State`), plus `## Open Questions` and `## Blockers`.
- **`### Now`** is special: cleared on seed; on fold-back main's `Now` is **set empty** (finished work has moved to `### Done`). `Now` is NOT carried from the worktree and is NOT part of the divergence snapshot (it is always reset, so it cannot signal divergence).
- **Gate sections** — `## Workflow`, `## /goal session`, `## PR authorization` — are NEVER snapshotted, NEVER seeded, NEVER folded. They stay worktree-local with today's REPLACE/singleton semantics.

## Architecture

### Unit 1 — Seed-on-create + snapshot (`commands/new-feature.md` + `commands/fix-bug.md`)

The shared `STATE-INIT` bash block (byte-identical across both files, enforced by `test-contracts.sh`) already computes `PARENT_ROOT` = main's working tree. Extend it:

- Emit `SEED_FROM_MAIN:<path-to-main-state.md>` when (a) in a worktree (`PARENT_ROOT != ROOT`), (b) `$PARENT_ROOT/.claude/local/state.md` exists, (c) it has real content. Existing sentinels unchanged. Short-circuit on `STATE_EXISTS` (never re-seed a resumed worktree).
- Step 2b gains one branch: on `SEED_FROM_MAIN`, the agent reads the template (skeleton + empty gate sections) and main's `state.md` (narrative), then writes the worktree `state.md` = fresh gate sections + verbatim foldable sections + `### Now` cleared.
- Step 2b ALSO writes the **seed snapshot** to `.claude/local/.state-seed-snapshot.md` in the worktree, containing ONLY the foldable sections copied from main. This file lives in the gitignored `.claude/local/` (never committed), is worktree-local (dies with the worktree — fine, only needed during its life), and is read once at finish.

**Why here:** `PARENT_ROOT` already computed; no new path resolution; preserves the one-block contract.

### Unit 2 — Guarded fold-back (`commands/finish-branch.md`)

A new step inserted **before** `git worktree remove` (P0 sequencing — the gitignored worktree `state.md` + snapshot are destroyed by remove). The step:

1. **Mechanical scaffold (bash):** resolve worktree paths (worktree `state.md` + `.state-seed-snapshot.md`, captured while still in/pointing at the worktree) and main's `state.md` (`$(git rev-parse --git-common-dir)/../.claude/local/state.md`).
   - If the worktree `state.md` is absent → **abort loud** (do not proceed to a silent empty replace).
   - If the seed snapshot is absent/malformed → **fail loud + safe-stop** (no replace).
2. **Divergence check (deterministic):** extract main's current foldable sections; compare (normalized byte/section compare) to the seed snapshot.
   - **Match** → replace main's foldable sections with the worktree's foldable sections; set main's `### Now` empty; preserve main's gate sections untouched.
   - **Mismatch** → **fail loud**: print a visible warning (mirroring the `session-start.sh` drift-warning pattern) naming the divergence, do NOT replace, leave worktree + both files intact; instruct the user to reconcile manually.
3. Existing Step 2.8 (clear main's `## Workflow`) is preserved, after the fold.

### Unit 3 — Docs (`state.template.md`)

Extend `## Update Rules`: document the round-trip — seed-on-create (verbatim foldable + Now cleared + snapshot), guarded fold-back (deterministic replace iff snapshot matches; else loud safe-stop), foldable-section list, and that gate sections never travel.

### Unit 4 — ADR 0008

Short ADR: decision (narrative round-trips via seed + guarded deterministic replace), alternatives (mechanism 1 common-dir singleton; mechanism 2 shared file — rejected; agent smart-merge A — deferred to divergence-only follow-up; pure unguarded B — rejected as silent-loss), deciding facts (sequential usage; "descendant ≠ main-unchanged"), deferred edges (abandoned worktree, retroactive migration, live parallel sharing, full smart-merge fallback). Complements, does not supersede, ADR 0001.

### Unit 5 — Tests (`tests/template/test-contracts.sh`)

- STATE-INIT byte-identity across `new-feature.md` + `fix-bug.md` (existing — still passes).
- `SEED_FROM_MAIN` sentinel present in both command files' STATE-INIT block.
- Seed branch writes the snapshot + clears Now (assert prose names `.state-seed-snapshot.md` and "Now cleared/empty" + foldable-verbatim).
- Fold-back step present in `finish-branch.md` AND appears **before** the `git worktree remove` line (ordering assertion — research flagged ordering as the failure mode).
- Fold-back is section-scoped: names the foldable sections AND explicitly excludes the three gate sections.
- Fold-back has the divergence guard: asserts the "compare to snapshot" + "fail loud / no silent replace on mismatch" + "abort if worktree state.md absent" prose is present.

### Unit 6 — Release hygiene

`docs/CHANGELOG.md` new `## 5.52` entry; `README.md` version badge + version-history row (per repo rule).

## Data flow

```
seed (/new-feature):  main state.md ──foldable verbatim──▶ worktree state.md  (Now cleared)
                       main foldable  ──snapshot──▶ worktree .claude/local/.state-seed-snapshot.md
   ...dev edits worktree narrative forward (adds Done, resolves Blockers, answers Qs)...
finish (/finish-branch, BEFORE worktree remove):
   compare main foldable  vs  seed snapshot
     match    → worktree foldable ──replace──▶ main state.md (Now emptied; gate sections preserved)
     mismatch → LOUD warning, NO replace, worktree + files left intact for manual reconcile
```

## Error handling / edge cases

- Main `state.md` missing on seed → fall back to template init (no seed, no snapshot). On fold-back with no snapshot → safe-stop loud.
- Main `Now` stale/non-empty on seed → seed still clears worktree Now; fold-back empties main Now.
- Worktree `state.md` absent on finish → abort loud (no silent empty replace).
- Snapshot missing/malformed on finish → safe-stop loud (no replace).
- Main foldable diverged since seed (hand-edit / quick-fix / hook / parallel sibling) → safe-stop loud (no replace).
- Not in a worktree (`PARENT_ROOT == ROOT`) → no seed/snapshot; fold-back no-ops.
- Downstream repo gitignores all `.claude/` → existing guard fires unchanged.

## Testing strategy

- **Deterministic (test-contracts.sh):** scaffold presence + ordering + section-scoping + snapshot/guard prose + byte-identity. These are the gate.
- **Manual scenario (E2E-style, Phase 5.4):** (1) common path — seed a fact in a worktree → `/finish-branch` (fact merged into main, Now empty, gates preserved) → `/new-feature` (fact seeded into new worktree, Now empty). (2) divergence path — seed, then edit main's narrative out-of-band, then `/finish-branch` → assert LOUD warning + main NOT overwritten + worktree intact.

## Decisions

- Fold-back = **guarded deterministic replace** (council Phase 3.1c). NOT agent LLM merge (deferred to a divergence-only follow-up if ever needed).
- Seed snapshot stored at `.claude/local/.state-seed-snapshot.md` (gitignored, worktree-local, non-foldable).
- Seed-on-create and fold-back ship in the SAME PR (B is unsafe without seed).
- Divergence / missing-snapshot / missing-worktree-state → loud safe-stop, never silent replace.
- Ship ADR 0008.
- Platform parity: command `.md` files are platform-agnostic prose; the bash scaffold is Unix (consistent with existing command docs — no `.ps1` command mirrors exist in the repo).
- PR body flags the deterministic-replace-vs-LLM-merge delta for the user's final call (Pragmatist condition).

## Non-goals (from PRD + council)

Re-tracking state.md; new continuity file / common-dir singleton; live parallel sharing; abandoned-worktree recovery; retroactive migration; **full agent smart-merge A** (only a safe-stop on divergence in this PR).
