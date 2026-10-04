<!-- forge:state-schema v6 -->
# Project State (per-developer, gitignored)

> This file holds your active workflow state. It is NOT shared with the team.
> Hooks read this file on demand. Claude and Codex inspect it through the bounded workflow-state
> helper when the workflow rule says to.
>
> If you started a workflow with `/new-feature` or `/fix-bug`, the Workflow section below tracks your progress.
> The Done / Now / Next sections capture your current focus across sessions.

## Identity

| Field                | Value |
| -------------------- | ----- |
| Worktree root        |       |
| Git common directory |       |
| Last active host     |       |
| Workflow base ref    |       |
| Workflow base SHA    |       |

The worktree root and Git common directory are resolved physical paths. The workflow
base ref and SHA remain immutable for one workflow. Switching between Claude and Codex
changes only `Last active host`; it retains the base SHA, review iteration, next step, and
unchanged candidate linkage, and it never restarts completed gates.

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
Plan-Approved checkpoint, after the user invokes the host's native `/goal` or explicitly requests
native Goal autonomy)

Format when active:

| Field            | Value                                  |
| ---------------- | -------------------------------------- |
| nonce            | <uuid-v4-lowercase>                    |
| objective_hash   | <sha256-of-stable-objective>            |
| activation_id    | <uuid-v4-lowercase>                    |
| activation_host  | claude OR codex                        |
| activated_at     | <ISO-8601-UTC-timestamp>               |
| workflow_command | /new-feature <name> OR /fix-bug <name> |
| turn_count       | <validated-repository-ledger-count>     |
| turn_ceiling     | <20-times-activation-count>             |
| activation_count | <positive-monotonic-integer>            |
| evidence_path    | .forge/local/evidence/latest.json       |

**Activation semantics:** native `/goal` or an explicit native Goal request is the human activation.
For a new objective, replace the entire block atomically with a new nonce, activation UUID, zero
turns, activation count `1`, and ceiling `20`, then run `.forge/hooks/lib/goal-ledger.sh activate`
(or the PowerShell twin). A same-objective reactivation retains the nonce and validated turn count,
generates a new activation UUID, increments `activation_count`, and sets `turn_ceiling` to
`20 * activation_count` before calling the helper. Agent-authored state records accounting; it is
never authority to start or resume native autonomy.

**Guard "active" definition:** the `/goal session` is considered ACTIVE when the nonce
row is non-empty (`nonce` column has a UUID value). A heading with no nonce row, or a
missing section entirely, is treated as INACTIVE by all guards and hooks.

The immutable ledger lives under the physical Git common directory at
`forge-goals/<nonce>/`, so linked worktrees and both engines share one monotonic count. User input,
PR creation, merge, deployment, publishing, destructive work, and other external mutations retain
their normal explicit-authorization pauses.

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

## Receipts

| Field                  | Value |
| ---------------------- | ----- |
| Review iteration       | 0 |
| First certified iteration | none |
| Candidate receipt      | .forge/local/evidence/<task-id>/candidate.receipt |
| Spec review receipt    | .forge/local/reviews/<task-id>/spec.receipt |
| Quality review receipt | .forge/local/reviews/<task-id>/quality.receipt |
| Verify app receipt     | .forge/local/evidence/<task-id>/verify-app.receipt |
| E2E receipt            | .forge/local/evidence/<task-id>/e2e.receipt |
| Promotion receipt      | .forge/local/evidence/<task-id>/promotion.receipt |
| Council receipt        | .forge/local/council/<council-id>/receipt.json |

Each action receipt records `host=<claude|codex>`. Receipt paths are worktree-local;
they cannot satisfy gates in a sibling worktree.
Populate every receipt path when the workflow activates. `Review iteration` starts at `0` and is
incremented before each final paired-review dispatch. `First certified iteration` is helper-owned:
it starts as `none`, is set from the first valid paired-review receipt, and never advances. A
populated candidate path is progress, not an evidence-mode switch.

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

The currently active host is responsible for advancing this file. Inspect control state with
`.forge/hooks/lib/workflow-state.sh show`; recover an inactive fast-forwarded binding with
`workflow-state.sh rebind`; start it with `workflow-state.sh activate`; and advance it with
`workflow-state.sh checkpoint` (use the `.ps1` twin on Windows). Only those bounded helpers may
update identity, workflow, receipt-path, or review-iteration control rows. Use native file tools
only for checklist and narrative content. The Stop hook reminds Claude or Codex of the active
workflow; the ship hook gates commit/push/PR on the checklist.

**On task completion:**

1. Add to Done (keep last 2-3; older history goes to `docs/CHANGELOG.md`)
2. Move top of Next → Now
3. Add to CHANGELOG.md if significant

**On new feature start (`/new-feature` or `/fix-bug` Pre-Flight step 3):**

1. Run `workflow-state.sh activate` with the workflow, task, host, base, phase, and exact next step.
2. Populate only the workflow checklist with native file tools; delete orphaned checkbox lines
   outside `### Checklist`.

**On code-review iteration start (during a `/forge-goal`-driven run):**

1. Freeze one staged-clean `git:working-tree` candidate and persist its candidate receipt.
2. Run `workflow-state.sh checkpoint --host <claude|codex> --phase review --next-step '<exact next
   step>' --begin-review` exactly once before the paired dispatch.
3. Record distinct `code-spec` and `code-quality` review receipts for the same review iteration and candidate. Engine choice is neutral: same-engine reviews and a visible fallback are valid when each receipt records requested engine, actual engine, and fallback reason.
4. Persist candidate-bound `verify-app` and `e2e` receipts only after their reports are written under `.forge/local/evidence/` and hashed by `verification-receipt`.
5. Any staged, unstaged, or in-scope untracked mutation invalidates the complete final receipt set. Freeze the new candidate and rerun both review lenses plus both verifiers; never relabel an old receipt.
6. Genuine unmigrated v5 fixtures retain the legacy checklist reader during dual-read. Every active canonical V6 workflow is receipt-native immediately; legacy clean rows cannot certify it.
7. Exact-tree promotion revalidates the receipt set before hook execution and compare-and-swap, then records `Promotion receipt`; the real branch is not advanced early.
8. **Convergence breaker (v5.54):** for canonical V6, the unique `Receipts/Review iteration` value is counted from the helper-owned `Receipts/First certified iteration`; legacy checklist counters remain readable only for pre-V6 state. After certification, malformed, missing, duplicate, or backward canonical counters fail closed. More than `POST_CERT_REVIEW_ROUND_LIMIT` (=3) further rounds trips a hook-enforced breaker that blocks commit/push/PR. Only a HUMAN decides whether to release it. After that explicit decision, the agent records in `### Checklist`:
   - `- [x] Post-certification tail adjudicated by human — <decision> — head=\`<sha>\` — ts=\`<ISO8601>\``
   The line is head-bound; the agent transcribes the actual human decision, never self-adjudicates, and never asks the human to edit the file. In legacy pre-V6 state, if the loop line carries an iteration count, an N/A escape must KEEP it (`- [x] Code review loop (<N> iterations) — N/A: <reason>`) — a count-less `Code review loop — N/A:` after certification reads as legacy counter erasure and trips the breaker. Canonical V6 checklist wording never controls or erases its receipt-table counter.

**On plan-review iteration completion (during any complex-fix workflow):**

1. Append a checklist line to `### Checklist` capturing the iteration number, plan file, and plan content sha256:
   - `- [x] Plan review iteration <N> — <actual-engine> clean — plan=\`docs/plans/<name>.md\` — plan_sha=\`<sha256>\` — ts=\`<ISO8601>\``
   Record the reviewer engine that actually ran (`claude` or `codex`). The bound fields may continue on contiguous indented Markdown lines; never relabel an existing review row.
2. Compute `plan_sha` with `shasum -a 256 <path>` (macOS), `sha256sum <path>` (Linux), or `(Get-FileHash -Algorithm SHA256 <path>).Hash` (PowerShell).
3. When checking the loop-complete checkbox `- [x] Plan review loop (<N> iterations) — PASS`, the per-iter clean line for iteration N must be present AND its `plan_sha` must match the current plan file content. The PreToolUse `check-workflow-gates` hook enforces this on ship actions.
4. If a fix changes the plan, re-run reviewers and append a NEW iteration row; do NOT mutate existing rows.
5. Reviewer selection is not an escape: prefer the other engine, then visibly dispatch a fresh same-engine reviewer when that engine is missing or lacks the required capability. Do not halt solely because the preferred engine is unavailable. A justified `- [x] Plan review loop — N/A: <reason>` still does NOT set the evidence gate clean; `/goal` can complete only from a real current-artifact receipt, and blocks only if the fallback also fails.

**On PR creation authorization (during a `/forge-goal`-driven run):**

1. Agent calls `AskUserQuestion` asking the user to authorize `gh pr create`.
2. On YES, agent REPLACES the entire `## PR authorization` section content with:
   - `- [x] PR creation authorized — \`<ISO-8601 timestamp>\` — nonce=\`<session nonce>\` — head=\`<current HEAD SHA>\``
3. The PR-create PreToolUse guard blocks `gh pr create` unless this line is present with a matching nonce AND head SHA.
4. On re-authorization (user re-authorizes after new commits): REPLACE the existing auth line with the fresh one; do NOT append.

**On worktree seed (`/new-feature` / `/fix-bug` Pre-Flight, when seeding from main):**

The continuity narrative **round-trips** through main so it survives worktree teardown (it is otherwise gitignored and dies with the worktree). The **foldable** sections are `### Done` / `### Next` / `### Deferred` (under `## State`), plus `## Open Questions` and `## Blockers`. The **gate** sections (`## Workflow`, `## /goal session`, `## PR authorization`) NEVER travel — they stay worktree-local with their REPLACE/singleton semantics.

1. A fresh worktree's foldable narrative is copied **verbatim** from main's `state.md`, with `### Now` cleared (a new feature has no active "Now").
2. A narrative-only **seed snapshot** is written to `.forge/local/.state-seed-snapshot.md` (gitignored, worktree-local) — a record of main's foldable narrative at seed time, used by `/finish-branch` to detect divergence.

**On `/finish-branch` (round-trip fold-back, BEFORE the worktree is removed):**

1. Compare main's current foldable narrative to the seed snapshot.
2. **Unchanged** → deterministically replace main's foldable sections with the worktree's; set main's `### Now` empty. Gate sections on main are left untouched.
3. **Changed / snapshot missing / worktree state absent / structurally incomplete** → **loud safe-stop**: warn and do NOT overwrite; leave files intact for manual reconciliation. (No LLM merge — divergence is a safe-stop in this version.)
