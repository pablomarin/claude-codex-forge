# Design: Scoped Review Certification

**Date:** 2026-06-04
**Status:** Validated (autonomous /goal run — approval via Contrarian gate; strategy fixed by the 5-advisor council chairman verdict)
**PRD:** `docs/prds/scoped-review-certification.md`
**Research:** `docs/research/2026-06-04-scoped-review-certification.md`

## Problem (one paragraph)

The code-review loop's head-rebind rule has freshness but no scope model: any HEAD move triggers "re-run reviewers at the new HEAD," dispatched in practice as full-branch reviews. Stochastic reviewers ~always find something in a big diff, so a docs-only merge conflict re-opened a certified branch into a 10-round spiral (msai-v2 PR #89) with no stopping rule. We add a certification model: scoped, machine-visible evidence; PR-owned-delta re-reviews; a hook-enforced convergence breaker; a deliberate deep pass at certification.

## Architecture (units)

### Unit 1 — `hooks/lib/review-scope.sh` + `.ps1` (NEW; single source of truth)

A read-only helper, fixture-testable like `default-branch.sh`. Run from the branch worktree with the state.md path; emits sentinel lines:

```
CERTIFIED:<yes|no>                       # first both-engines-clean-at-scope=full exists in state.md
LAST_CLEAN_HEAD:<sha>                    # head of the most recent valid clean evidence
ANCESTOR_OK:<yes|no>                     # git merge-base --is-ancestor <last_clean_head> HEAD
PR_OWNED_DELTA:<empty|docs-only|code>    # see computation below
UPSTREAM_FILES:<none|nonruntime|code>    # default-branch movement: pulled-in by merges (merge-base→merge-base) PLUS still-unmerged movement ahead of the branch (merge-base→origin/<default> tip) — the PR merges into THAT
SCOPE_REQUIRED:<full|delta|mechanical>   # the decision
POST_CERT_ROUNDS:<n>                     # rounds past certification (max of loop-counter delta and evidence rows)
BREAKER:<ok|tripped>                     # POST_CERT_ROUNDS > POST_CERT_REVIEW_ROUND_LIMIT
ADJUDICATED:<yes|no>                     # human adjudication line present at the CURRENT head
```

**Chain construction is validated, not trusted** (plan-review hardening): `LAST_CLEAN_HEAD` advances past certification only through rows that re-validate today — a mechanical row needs base == chain head AND a recomputed empty/docs-only classification between the two commits; a scoped pair must be coherent (same scope/head/base), with delta chaining from the chain head and full anchored at the true merge-base. Fabricated or stale rows never become the trusted prior clean head.

**PR-owned-delta computation** (research-grounded):

- PR-owned diff at any commit X = `git diff $(git merge-base origin/<default> X)..X` (three-dot semantics — excludes upstream code pulled in by merges).
- Identity: whole-diff `| git patch-id --stable` → one stable ID. ID(last_clean_head) == ID(HEAD) → `PR_OWNED_DELTA:empty`.
- If IDs differ: per-file patch-id comparison over the union of changed files → the set of files whose PR-owned content actually changed; all matching the docs classification (`*.md`, `docs/**`, `LICENSE`) → `docs-only`, else `code`.
- `ANCESTOR_OK:no` (rebase/rewrite) → identity not establishable → `SCOPE_REQUIRED:full` (fail-closed to MORE review).

**Decision table:** not certified → `full`. Certified + delta empty/docs-only + upstream non-code → `mechanical`. Certified + (delta code OR upstream code) → `delta`. Ancestor broken → `full`.

**Scope of the decision table (plan-review iter-13 clarification):** `SCOPE_REQUIRED` answers "what scope must the NEXT review/re-stamp take" — it is consumed when a re-review is being DISPATCHED (post-rebind, per US-002's HEAD-move framing) and when the gates VALIDATE a recorded mechanical/delta claim. It does NOT add continuous upstream-drift ship gating on an UNCHANGED certified head: a branch certified at HEAD ships on that evidence even while `origin/<default>` moves, exactly as the Forge behaved before this feature (integration risk at merge time is handled by the merge/CI path, and any rebind that follows main-movement — merge, fix, docs commit — re-enters the scope computation, where pending upstream code correctly forces `delta`). Changing that boundary would be new enforcement far beyond the PR #89 incident and the council verdict, and would block every busy repo's certified ship behind upstream churn.

**Named constant:** `POST_CERT_REVIEW_ROUND_LIMIT=3` defined HERE (one canonical place); command prose mirrors it via contract test.

### Unit 2 — Evidence grammar (state.template.md + rules/workflow.md + both commands)

```
# Full pair (certification / post-rebase) — both engines, same scope+base+head:
- [x] Code review iteration <N> — codex clean — scope=full — base=`<merge-base-sha>` — head=`<sha>`
- [x] Code review iteration <N> — pr-toolkit clean — scope=full — base=`<merge-base-sha>` — head=`<sha>`
# Delta pair (post-certification re-review) — both engines, same scope+base+head:
- [x] Code review iteration <N> — codex clean — scope=delta — base=`<last-clean-head>` — head=`<sha>`
- [x] Code review iteration <N> — pr-toolkit clean — scope=delta — base=`<last-clean-head>` — head=`<sha>`
# Single lines:
- [x] Code review iteration <N> — mechanical re-stamp — scope=mechanical — base=`<last-clean-head>` — head=`<sha>`
- [x] Code review iteration <N> — codex deep-pass clean — scope=full — base=`<merge-base-sha>` — head=`<sha>`
- [x] Post-certification tail adjudicated by human — <decision summary> — head=`<sha>` — ts=`<ISO8601>`
```

- First certification = both engines clean at `scope=full`, same N, same head (+ the deep-pass line; see Unit 5 enforcement level).
- `scope=delta` requires BOTH engine lines (same N, same base/head). `scope=mechanical` is ONE agent line — no reviewer ran — and is only valid if the gate's recomputation agrees (Unit 3).
- **Backward compat:** legacy lines without `scope` are accepted as `scope=full` at their head for establishing certification; they never satisfy a rebind to a different head.

### Unit 3 — `check-workflow-gates.{sh,ps1}` (extend the existing code-review evidence gate)

On ship actions, in addition to today's head-equality:

1. Parse scope/base/head from the satisfying evidence lines; unknown scope value or missing fields on post-cert lines → block with a specific error.
2. **Recompute, don't trust:** call `review-scope.sh`; a `scope=mechanical` claim is accepted ONLY if `SCOPE_REQUIRED:mechanical` for that exact base→head pair; a `scope=delta` claim requires `ANCESTOR_OK:yes` and base == LAST_CLEAN_HEAD at recording time (chain check).
3. **Breaker:** if `BREAKER:tripped` and `ADJUDICATED:no` → block ship with the breaker message (open-tail summary instructions). The breaker check runs OUTSIDE the PASS-evidence branch — neither a `Code review loop — N/A:` escape nor an unchecked loop line bypasses it. In `/goal`, the prose mandates halting (Blockers line) when the breaker trips — the hook is the backstop that nothing ships regardless; `build-evidence` suppresses `pr_ready` on the same tripped+unadjudicated condition.
4. Human-adjudication line at current head → unblocks the breaker (not the severity gates; P0/P1 fixes still need their delta evidence).

### Unit 4 — `build-evidence.{sh,ps1}`

`reviewer_gate.clean_same_iteration` computed only from valid scoped evidence per Unit 2/3 semantics (mechanical/delta lines satisfy it when their chain is valid). Adds `reviewer_gate.post_cert_rounds` + `reviewer_gate.breaker` fields so `/goal` halts visibly.

### Unit 5 — Command prose (Phase 5.1 in both commands + rules/workflow.md + codex.md)

- The loop runs FULL scope until first certification. At certification: run the **deep pass** — Codex _native_ `review --base <pr-base-ref>` (different mode from the prompted loop reviews) with an adversarial final-audit instruction. Default ON for all features; repos may narrow via a `## Review Configuration` CLAUDE.md section (design: a `deep_pass: high-impact-only` key + surface list). Deep pass is prose-mandated + contract-pinned (not ship-gated — avoids bricking in-flight branches).
- After certification: before any re-review, run `review-scope.sh`; dispatch per `SCOPE_REQUIRED`. Delta dispatches use `codex exec review --base <last-clean-head>` (research: codex `--base` is merge-base-aware; if a raw SHA is rejected, create a lightweight ref `cert/<short-sha>` at the certified head and pass that — both handled in prose). Every delta prompt includes the interaction-surface clause (assess incoming default-branch commits vs the branch's touchpoints).
- **Scoped retries:** a degraded/failed reviewer pass is retried at the SAME scope/base; never widened autonomously.
- **Oscillation halt (prose):** a fix round that introduces a new P0/P1 in its own delta → halt immediately (interactive: surface tail; /goal: Blockers line + stop). The hook's round-limit is the countable backstop.
- `codex.md`: document the scoped dispatch forms.

### Unit 6 — Tests

- NEW executable suite `tests/template/test-review-scope.sh` (fixture git repos, like `test-state-roundtrip.sh`): certification detection; empty/docs-only/code delta classification incl. merge-from-main (CHANGELOG-conflict shape → mechanical) and rebase (→ full, fail-closed); breaker counting; legacy-line compat.
- Executable gate tests (extend `test-hooks.sh` or the new suite): mechanical claim rejected when recomputation says delta/full; stale-base chain blocked; breaker blocks ship without adjudication line; adjudication line at head unblocks.
- `test-contracts.sh`: grammar pinned across rules/commands/template/hooks; `POST_CERT_REVIEW_ROUND_LIMIT` mirrored; deep-pass prose pinned; scoped-retry clause pinned.

### Unit 7 — ADR 0009 + release hygiene

ADR 0009 "Review certification: scoped evidence + convergence breaker" (changes what a clean evidence line means: from "clean at HEAD" to "review debt since last clean evidence discharged at HEAD"). CHANGELOG `## 5.54`; README badge + row.

## Error handling

- Helper unrunnable (no git, detached states) → `SCOPE_REQUIRED:full` (fail-closed). Malformed state.md evidence → treated as uncertified → full.
- patch-id unavailable (ancient git) → full.
- Gate recomputation mismatch vs claimed scope → block with the specific divergence (claimed vs recomputed) — never silently accept.

## Testing strategy

Executable fixture suites are the gate (the v5.52 lesson: contract pins for prose + executable tests for every real decision branch). The helper is pure read-only bash/ps1 → unit-testable end-to-end with scratch repos.

## Non-goals

Plan-review loop; severity-policy change (FIX-3); LLM-computed scope; council-as-risk-acceptor; PowerShell-only divergences (parity is mandatory).
