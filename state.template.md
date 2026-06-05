# Project State (per-developer, gitignored)

> This file holds your active workflow state. It is NOT shared with the team.
> Hooks read this file on demand. Claude reads it when the workflow rule says to.
>
> If you started a workflow with `/new-feature` or `/fix-bug`, the Workflow section below tracks your progress.
> The Done / Now / Next sections capture your current focus across sessions.

## Workflow

| Field     | Value |
| --------- | ----- |
| Command   | none  |
| Phase     |       |
| Next step |       |

### Checklist

(populated by `/new-feature` or `/fix-bug` Pre-Flight)

---

## /goal session

(populated by `/new-feature` at the PRD-complete checkpoint, or by `/fix-bug` at the
Plan-Approved checkpoint, when the user opts into the `/forge-goal` autonomous loop)

Format when active:

| Field            | Value                                  |
| ---------------- | -------------------------------------- |
| nonce            | <uuid-v4-lowercase>                    |
| workflow_command | /new-feature <name> OR /fix-bug <name> |
| issued_at        | <ISO-8601-UTC-timestamp>               |

**REPLACE semantics:** the entire `## /goal session` block (heading + table) is
replaced atomically on each new autonomous-loop kickoff. A stale session from a
previous run is never appended to — it is overwritten in full. When no session is
active, this section is absent from the file.

**Guard "active" definition:** the `/goal session` is considered ACTIVE when the nonce
row is non-empty (`nonce` column has a UUID value). A heading with no nonce row, or a
missing section entirely, is treated as INACTIVE by all guards and hooks.

---

## PR authorization

(populated when the user authorizes `gh pr create` via the PR-create gate's
AskUserQuestion modal during a `/forge-goal`-driven run)

**REPLACE semantics:** this section holds exactly ONE authorization line at a time.
On a new authorization, the agent REPLACES any existing content in this section with
the new line — never appends. Multiple lines would cause the guard to use the LAST
one (defensive), but proper REPLACE semantics keep the section as a singleton.

Format when authorized:

- [x] PR creation authorized — `<ISO-8601-UTC-timestamp>` — nonce=`<session-nonce>` — head=`<current-HEAD-SHA>`

**Stale auth defense:** if state.md is somehow corrupted and contains multiple
authorization lines (should not happen with REPLACE semantics), the guard uses the
LAST matching line. Multiple lines in this section indicate a state.md corruption —
surface to user.

---

## State

### Done (recent 2-3 only)

- (your most recent completed work)

### Now

- (what you're actively working on)

### Next

- (what's queued)

### Deferred

- (parked items with reason)

---

## Open Questions

- (questions needing resolution)

## Blockers

- (anything blocking forward progress)

---

## Update Rules

You (Claude) are responsible for updating this file. The Stop hook reminds you of the active workflow; the PreToolUse hook gates commit/push/PR on the checklist.

**On task completion:**

1. Add to Done (keep last 2-3; older history goes to `docs/CHANGELOG.md`)
2. Move top of Next → Now
3. Add to CHANGELOG.md if significant

**On new feature start (`/new-feature` or `/fix-bug` Pre-Flight step 3):**

1. REPLACE the `## Workflow` section entirely
2. Delete any orphaned checkbox lines outside `### Checklist`

**On code-review iteration completion (during a `/forge-goal`-driven run):**

1. Append scoped checklist line(s) to `### Checklist` capturing the iteration number, tool, scope, base, and HEAD SHA. Scoped evidence is a COHERENT PAIR — both engines, same scope, same base, same head (a mixed pair is rejected by the gate). The first clean pass is **certification** (a `scope=full` pair); post-certification re-reviews scope to the PR-owned delta. Full grammar and dispatch model live in `rules/workflow.md` "Certification + scoped re-reviews". The seven canonical forms:
   - `- [x] Code review iteration <N> — codex clean — scope=full — base=\`<merge-base-sha>\` — head=\`<sha>\``
   - `- [x] Code review iteration <N> — pr-toolkit clean — scope=full — base=\`<merge-base-sha>\` — head=\`<sha>\``
   - `- [x] Code review iteration <N> — codex clean — scope=delta — base=\`<last-clean-head>\` — head=\`<sha>\``
   - `- [x] Code review iteration <N> — pr-toolkit clean — scope=delta — base=\`<last-clean-head>\` — head=\`<sha>\``
   - `- [x] Code review iteration <N> — mechanical re-stamp — scope=mechanical — base=\`<last-clean-head>\` — head=\`<sha>\`` (no reviewer ran — valid only when the gate's recomputation agrees)
   - `- [x] Code review iteration <N> — codex deep-pass clean — scope=full — base=\`<merge-base-sha>\` — head=\`<sha>\``(informational — never substitutes for the loop's`codex clean` row)
   - `- [x] Post-certification tail adjudicated by human — <decision> — head=\`<sha>\` — ts=\`<ISO8601>\`` (HUMAN-only — unblocks a tripped convergence breaker; the agent NEVER writes this on its own initiative)
   - Back-compat (legacy pre-v5.54 form, accepted only as certification evidence): `- [x] Code review iteration <N> — codex clean — head=\`<sha>\`` — new workflows MUST use the scoped grammar above.
2. For a `scope=full` or `scope=delta` PAIR, both `codex clean` AND `pr-toolkit clean` must be present for the SAME iteration AND at the SAME current HEAD for the `reviewer_gate.clean_same_iteration` evidence to be true.
3. If a fix changes HEAD, re-run reviewers and append a NEW iteration row; do NOT mutate existing rows.
4. **Convergence breaker / adjudication:** more than POST_CERT_REVIEW_ROUND_LIMIT (=3) rounds past certification, or a fix round that introduces a new P0/P1 in its own delta → STOP. In a `/goal` run, write a `## Blockers` line and HALT for the human (council may be invoked BY the human only — never as the autonomous risk-acceptor). The gate hook blocks ship while the breaker is tripped until the human appends the `Post-certification tail adjudicated by human` line above.
5. **N/A is count-preserving after certification:** if the loop line carries an iteration count, an N/A escape must keep it — `- [x] Code review loop (<N> iterations) — N/A: <reason>`; a count-less `Code review loop — N/A:` line after certification reads as breaker-counter erasure and trips the breaker (helper fail-closed).

**On plan-review iteration completion (during any complex-fix workflow):**

1. Append a checklist line to `### Checklist` capturing the iteration number, plan file, and plan content sha256:
   - `- [x] Plan review iteration <N> — codex clean — plan=\`docs/plans/<name>.md\` — plan_sha=\`<sha256>\` — ts=\`<ISO8601>\``
2. Compute `plan_sha` with `shasum -a 256 <path>` (macOS), `sha256sum <path>` (Linux), or `(Get-FileHash -Algorithm SHA256 <path>).Hash` (PowerShell).
3. When checking the loop-complete checkbox `- [x] Plan review loop (<N> iterations) — PASS`, the per-iter clean line for iteration N must be present AND its `plan_sha` must match the current plan file content. The PreToolUse `check-workflow-gates` hook enforces this on ship actions.
4. If a fix changes the plan, re-run reviewers and append a NEW iteration row; do NOT mutate existing rows.
5. Escape (the ONLY one — Codex is mandatory in this repo): `- [x] Plan review loop — N/A: <reason>`. An N/A line skips the per-iter evidence check on ship actions and is caught by human reviewers at PR time. It does NOT set the evidence gate clean — a `/goal` autonomous run cannot self-complete on N/A; it halts for a human if Codex is genuinely unavailable.

**On PR creation authorization (during a `/forge-goal`-driven run):**

1. Agent calls `AskUserQuestion` asking the user to authorize `gh pr create`.
2. On YES, agent REPLACES the entire `## PR authorization` section content with:
   - `- [x] PR creation authorized — \`<ISO-8601 timestamp>\` — nonce=\`<session nonce>\` — head=\`<current HEAD SHA>\``
3. The PR-create PreToolUse guard blocks `gh pr create` unless this line is present with a matching nonce AND head SHA.
4. On re-authorization (user re-authorizes after new commits): REPLACE the existing auth line with the fresh one; do NOT append.

**On worktree seed (`/new-feature` / `/fix-bug` Pre-Flight, when seeding from main):**

The continuity narrative **round-trips** through main so it survives worktree teardown (it is otherwise gitignored and dies with the worktree). The **foldable** sections are `### Done` / `### Next` / `### Deferred` (under `## State`), plus `## Open Questions` and `## Blockers`. The **gate** sections (`## Workflow`, `## /goal session`, `## PR authorization`) NEVER travel — they stay worktree-local with their REPLACE/singleton semantics.

1. A fresh worktree's foldable narrative is copied **verbatim** from main's `state.md`, with `### Now` cleared (a new feature has no active "Now").
2. A narrative-only **seed snapshot** is written to `.claude/local/.state-seed-snapshot.md` (gitignored, worktree-local) — a record of main's foldable narrative at seed time, used by `/finish-branch` to detect divergence.

**On `/finish-branch` (round-trip fold-back, BEFORE the worktree is removed):**

1. Compare main's current foldable narrative to the seed snapshot.
2. **Unchanged** → deterministically replace main's foldable sections with the worktree's; set main's `### Now` empty. Gate sections on main are left untouched.
3. **Changed / snapshot missing / worktree state absent / structurally incomplete** → **loud safe-stop**: warn and do NOT overwrite; leave files intact for manual reconciliation. (No LLM merge — divergence is a safe-stop in this version.)
