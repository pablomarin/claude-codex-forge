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

1. Append a checklist line to `### Checklist` capturing the iteration number, tool, and HEAD SHA:
   - `- [x] Code review iteration <N> — codex clean — head=\`<sha>\``
   - `- [x] Code review iteration <N> — pr-toolkit clean — head=\`<sha>\``
2. Both `codex clean` AND `pr-toolkit clean` must be present for the SAME iteration AND at the SAME current HEAD for the `reviewer_gate.clean_same_iteration` evidence to be true.
3. If a fix changes HEAD, re-run reviewers and append a NEW iteration row; do NOT mutate existing rows.

**On plan-review iteration completion (during any complex-fix workflow):**

1. Append a checklist line to `### Checklist` capturing the iteration number, plan file, and plan content sha256:
   - `- [x] Plan review iteration <N> — codex clean — plan=\`docs/plans/<name>.md\` — plan_sha=\`<sha256>\` — ts=\`<ISO8601>\``
2. Compute `plan_sha` with `shasum -a 256 <path>` (macOS), `sha256sum <path>` (Linux), or `(Get-FileHash -Algorithm SHA256 <path>).Hash` (PowerShell).
3. When checking the loop-complete checkbox `- [x] Plan review loop (<N> iterations) — PASS`, the per-iter clean line for iteration N must be present AND its `plan_sha` must match the current plan file content. The PreToolUse `check-workflow-gates` hook enforces this on ship actions.
4. If a fix changes the plan, re-run reviewers and append a NEW iteration row; do NOT mutate existing rows.
5. Escapes (rare):
   - `codex unavailable, user-confirmed — ts=\`<ts>\``— accepted ONLY if`command -v codex` returns non-zero at gate time
   - `codex unavailable, council-confirmed — council_nonce=\`<n>\` — ts=\`<ts>\``— accepted in`/goal` autonomous mode (council is the audit trail)

**On PR creation authorization (during a `/forge-goal`-driven run):**

1. Agent calls `AskUserQuestion` asking the user to authorize `gh pr create`.
2. On YES, agent REPLACES the entire `## PR authorization` section content with:
   - `- [x] PR creation authorized — \`<ISO-8601 timestamp>\` — nonce=\`<session nonce>\` — head=\`<current HEAD SHA>\``
3. The PR-create PreToolUse guard blocks `gh pr create` unless this line is present with a matching nonce AND head SHA.
4. On re-authorization (user re-authorizes after new commits): REPLACE the existing auth line with the fresh one; do NOT append.
