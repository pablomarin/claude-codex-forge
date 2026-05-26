# `/forge-goal` — Design

**Date:** 2026-05-14
**Status:** Draft, ready for `/superpowers:writing-plans`
**Decision method:** Brainstorming + Codex second opinion (3 grounding audits + 2 design passes) + experiment evidence (EXP 1, 2, 4, 5 on Anthropic's native `/goal` mechanic)
**Source artifacts:**
- PRD: `docs/prds/forge-goal.md` (v1.2, GROUNDED)
- Discussion: `docs/prds/forge-goal-discussion.md` (4 rounds, 21 Q&A)
- Experiments: `docs/plans/2026-05-13-forge-goal-experiments.md` (EXP 1 FAIL, EXP 2 STRICT-WAIT, EXP 4 WEAK-PASS, EXP 5 PASS)

---

## Problem

The claude-codex-forge harness requires the user to manually advance Claude through every workflow phase after `/new-feature` or `/fix-bug` kicks off. This is the babysitting tax: type "go", "next", "now run code review", etc. The discipline is great; the babysitting is not.

Anthropic shipped `/goal` in Claude Code 2.1.139 — a session-scoped Stop-hook + system-reminder + Haiku-class verifier that lets an agent loop autonomously until a stated completion condition is met. We want to leverage `/goal` so that, after the PRD is approved, the user types ONE command and the agent autonomously drives the workflow to PR-ready.

Two non-negotiable constraints:

1. **Existing gates and discipline must be preserved unchanged.** TDD, plan-review-loop, code-review-loop, E2E reports, NO BUGS LEFT BEHIND — all stay.
2. **`state.md` is the single source of truth.** No state proliferation across sidecar JSON files. (Per Pablo's explicit constraint after Codex's first design pass.)

---

## Decision

Build a **HYBRID architecture**: native Anthropic `/goal` drives the loop; the forge ships `build-evidence.sh` to produce deterministic transcript evidence the Haiku verifier reads. State.md owns all workflow assertions; everything else is derived/validated.

### Key principles

1. **State.md is the single contract.** New sections are added only when state.md genuinely needs them: `## /goal session` (nonce + workflow command + issued_at) and `## PR authorization` (one-line gate). No sidecar state files.
2. **`build-evidence.sh` is read-only.** It parses state.md, queries git/`gh`/E2E reports, and emits unified JSON between transcript markers. It never persists.
3. **AskUserQuestion is the trigger, file/checkbox is the gate** (per EXP 4). The PR-creation modal triggers the user; the authorization checkbox is what the verifier actually reads.
4. **Council reuses its existing mechanism.** No state.md audit log; conversation transcript IS the audit (per PRD §6).
5. **`/forge-goal` is not a new slash command.** `/new-feature` and `/fix-bug` print the `/goal` command at the PRD-complete checkpoint.
6. **ONE `/goal` per session.** Resetting mid-session triggers the transient lifecycle state bug observed in EXP 5.
7. **Two-layer delivery.** Layer 1 = `build-evidence.sh` standalone (strengthens existing hooks). Layer 2 = everything else.

---

## Architecture

### 1. Evidence Primitive (Layer 1)

**File:** `hooks/build-evidence.sh` (Unix) + `hooks/build-evidence.ps1` (Windows). Copied by `setup.sh`/`setup.ps1` into `.claude/hooks/` on every install.

**Invocation:** `.claude/hooks/build-evidence.sh` (no arguments required; reads state implicitly from cwd).

**Inputs read:**

- `.claude/local/state.md` — sections: `## /goal session`, `## Workflow`, `## PR authorization` (and any existing sections used by current hooks)
- Git: `git rev-parse HEAD`, `git rev-parse --abbrev-ref HEAD`, `git merge-base HEAD main` (fallback `master`), `git status --porcelain`, `git rev-parse HEAD^{tree}`
- `gh pr view --json number,url,state,headRefName,baseRefName,headRefOid` (best-effort; absence is not a hard fail)
- `tests/e2e/reports/*.md` mtimes (compared against branch-off commit timestamp — same logic as existing `check-workflow-gates.sh`)

**Output:** unified JSON written to STDERR between literal markers:

```
FORGE_GOAL_EVIDENCE_BEGIN
{ ...json... }
FORGE_GOAL_EVIDENCE_END
```

(STDERR because the existing Stop hooks already use STDERR for blocking-style messages; the verifier reads transcript regardless of stream.)

**JSON schema (top-level keys):**

| Key | Type | Source |
|---|---|---|
| `type` | string `"forge_goal_evidence"` | constant |
| `schema_version` | int `1` | constant; bump if schema changes |
| `session_nonce` | string \| null | parsed from `## /goal session` |
| `produced_at_unix` | int | `date +%s` at script run |
| `evidence_seq` | int | monotonically incrementing per-session counter; sourced from a single-line file `.claude/local/forge-goal-seq` (auto-created; this is NOT state, it's a counter) |
| `workflow_command` | string \| null | parsed from `## /goal session` |
| `branch` | string | `git rev-parse --abbrev-ref HEAD` |
| `head_sha` | string | `git rev-parse HEAD` |
| `tree_sha` | string | `git rev-parse HEAD^{tree}` |
| `branch_off_commit` | string \| null | `git merge-base HEAD <main\|master>` |
| `working_tree_dirty` | bool | `git status --porcelain` non-empty |
| `state` | object | `{ phase, next_step, checklist_total, checklist_done, checklist_pending: [...] }` parsed from `## Workflow` |
| `reviewer_gate` | object | derived (see §4 below) |
| `e2e_report` | object | `{ present, path, mtime_unix, fresh_for_head }` — `fresh_for_head` = mtime > branch-off ts |
| `pr_state` | object | `{ exists, number, url, state, head_oid, base_ref, head_ref }` (from `gh pr view`) |
| `pr_authorization` | object | `{ authorized, authorized_at_unix, head_sha_at_authorization }` parsed from `## PR authorization` line |
| `pr_ready` | bool | derived: PR open + reviewer_gate.clean_same_iteration + e2e_report.fresh_for_head + pr_authorization.authorized AND nonce-matches + head_sha currency |
| `all_gates_green` | bool | derived: all state.md checklist items checked AND pr_ready |
| `progress_fingerprint` | string | SHA256 of subset (see §5 below) |
| `warnings` | array of strings | non-fatal issues |
| `errors` | array of strings | parse failures, missing files, etc. — non-blocking |

**Exit codes:**

- `0` — parseable JSON emitted (success path)
- `1` — bad arguments (script-level error)
- `2` — runtime failure (e.g., git not available); the Stop hook handles this gracefully — emits an `errors`-only JSON and continues; never blocks

**Independent usefulness (Layer 1 standalone):** even without `/goal`, build-evidence.sh strengthens the existing `check-workflow-gates.sh` checks by centralizing reviewer/PR/E2E currency in one JSON blob. Tests can verify hook behavior against this JSON.

### 2. Stop Hook Integration

**File:** `hooks/check-state-updated.sh` (Unix) + `.ps1` (Windows). Modified, not replaced.

**Change required:** the existing `stop_hook_active` early-return MUST be moved to AFTER evidence emission. Today it returns immediately if `stop_hook_active` is true; that suppresses our evidence emission inside an active `/goal`. New flow:

```
[entry]
  ├─ run build-evidence.sh → emit FORGE_GOAL_EVIDENCE_BEGIN/END to STDERR
  ├─ check stop_hook_active → if true, exit 0 (goal verifier will read evidence)
  └─ [existing stale-state nagging behavior]
```

This is a **real bug fix** for `/goal`-driven autonomy; it's also harmless when `/goal` is not active (evidence emission costs ~ms; verifier won't read it).

### 3. `/goal` Condition Template

**Triggered by:** `/new-feature` and `/fix-bug` workflow commands at the **PRD-complete checkpoint** (BEFORE plan creation). Per Pablo's discussion answer Q20, the workflow commands print the `/goal` for the user to copy-paste.

**Steps the workflow command takes at the checkpoint:**

1. Generate a session nonce (UUID v4 via `uuidgen` or `[guid]::NewGuid()`)
2. Write/refresh `## /goal session` in state.md:
   ```markdown
   ## /goal session

   - nonce: `<uuid>`
   - workflow_command: `/new-feature foo` (or `/fix-bug bar`)
   - issued_at: `2026-05-14T18:00:00Z`
   ```
3. Print this exact block to the user (the `<NONCE>` is substituted in):

   ```
   ────────────────────────────────────────
    Now type this as your next message:
   ────────────────────────────────────────

   /goal Continue the active Forge workflow until the latest FORGE_GOAL_EVIDENCE JSON has pr_ready=true AND session_nonce="<NONCE>". Do not count stale evidence. PR-ready requires: PR open, PR head equals current HEAD, code reviewers clean on the same state.md iteration at current HEAD, fresh E2E report for this branch, and PR authorization checked in state.md after AskUserQuestion approval. If a non-PR decision would normally pause for human input, invoke /council and apply the chairman verdict. Stop after the PR is open. Do not merge.
   ```

The condition is JSON-key-precise (verifier is text-only but strict) and explicitly references `session_nonce` (so a stale transcript from another run can't satisfy it).

### 4. Reviewer Gate Durability

**Problem:** without sidecar JSON, how does the verifier know that "Codex clean" and "PR-toolkit clean" both passed **on the same iteration at the current HEAD**?

**Answer:** reviewer iteration checkboxes in state.md carry the head SHA in their label.

**State.md convention (added under `## Workflow` → `### Code review loop` or similar existing section):**

```markdown
- [x] Code review iteration 3 — codex clean — head=`<sha>`
- [x] Code review iteration 3 — pr-toolkit clean — head=`<sha>`
```

**`build-evidence.sh` derivation rule:**

```
reviewer_gate.clean_same_iteration =
  exists at least one iteration N where:
    BOTH `iteration N — codex clean — head=<sha>`
    AND  `iteration N — pr-toolkit clean — head=<sha>`
    AND  both `<sha>` values equal current HEAD
```

This makes "rubber-stamping" much harder: the agent would have to forge head SHAs that match the current commit, which is detectable on inspection.

### 5. PR-Creation Gate

**Flow:**

1. Agent calls `AskUserQuestion` with this modal:

   ```
   Authorize PR creation?

   Branch <branch> is pushed and Forge gates are green. Create a PR to <base> with the following summary?

   <inline summary>

   Yes writes the authorization line to state.md and runs `gh pr create`.
   No pauses the workflow for your direction.
   ```

   The `<inline summary>` is computed by the agent at modal time (changed files, tests added, reviewer status per tool/iteration, E2E report path, council fires count, PR title/body draft). **NOT persisted** to state.md — it lives only in the modal.

2. On user YES, the agent:
   a. Appends to state.md `## PR authorization`:
      ```markdown
      ## PR authorization

      - [x] PR creation authorized — `2026-05-14T18:30:00Z` — nonce=`<n>` — head=`<sha>`
      ```
   b. Runs `gh pr create` with the title/body from the summary

3. On user NO, the loop pauses. State.md preserves progress; user can take over manually.

**`build-evidence.sh` derivation rule for `pr_authorization.authorized`:**

```
pr_authorization.authorized = true IFF:
  state.md has `- [x] PR creation authorized — <ts> — nonce=<n> — head=<sha>`
  AND `<n>` matches `## /goal session` nonce
  AND `<sha>` equals current HEAD
```

**Guard at the hook level:** add a `PreToolUse` check in `check-workflow-gates.{sh,ps1}` for Bash commands matching `^\s*gh\s+pr\s+create\b`. Block the command if the authorization line is missing or its nonce/head SHA doesn't match. This prevents the agent from running `gh pr create` without the user's prior YES.

**`gh pr create` failure handling:** max 2 attempts. If the second attempt fails AND the output mentions "already exists", treat it as success (the PR was created on attempt 1 but the command's response was lost). For auth/network failures, retry once after a brief delay. After two failures, pause the loop and append a blocker to state.md.

**Acknowledged UX wart (Codex landmine #3):** the existing forge settings require user permission approval for `gh pr create` via the Bash permission system. AskUserQuestion is the product gate; the Bash permission prompt is redundant but not a correctness problem. State.md authorization is canonical; `gh pr view` confirms creation.

### 6. Council Inside `/forge-goal`

**Trigger rule (added to `rules/workflow.md`):**

> While a `/forge-goal`-driven `/goal` is active: before asking the user any question during the autonomous run, ask yourself — **is this a PR creation authorization?** If yes, call `AskUserQuestion`. If no, invoke `/council` with the question and apply the chairman verdict.

**Recognized triggers for council** (added to the rule as guidance, not exhaustive):

- Ambiguous product or technical choice that would otherwise prompt the user
- A reviewer recommends plan revision (not just code patch)
- High-impact implementation fork (multiple defensible approaches)
- A retry of a failed tool/subagent has also failed
- Unrecognizable council/reviewer output requires interpretation

**Explicit NON-triggers (no council fire):**

- Normal plan-review-loop iterations (Claude + Codex back-and-forth on the plan)
- Normal code-review-loop iterations (Codex + PR-toolkit + Claude fix cycles)
- Any moment that doesn't actually require human-level judgment

**Invocation:** primary mechanism is the existing `Skill` tool with `council` and the question. Fallback (if Skill invocation fails): direct execution of `.claude/skills/council/SKILL.md` via Task + codex-pty shim.

**Audit:** lives in the conversation transcript. Claude's response naming the council outcome and the applied action is the durable record (per PRD §6 — "logged" satisfied by transcript).

**Council failure handling:** retry the failing advisor or chairman invocation once. If still no chairman verdict, pause the loop and append a blocker line to state.md's checklist; the user takes over.

### 7. Stuck Detection

**Mechanism:** `build-evidence.sh` emits a `progress_fingerprint` = SHA256 of this subset of state.md content:

- `## Workflow` table rows (command, phase, next step)
- The full checklist (all `- [ ]` and `- [x]` lines and their labels)
- Reviewer iteration rows (per §4)
- `## PR authorization` line (if present)

Excluded from the fingerprint: prose noise, conversation context, council output, body of `## PR authorization`'s metadata other than the checkbox state.

**Stuck signal:** when the same `progress_fingerprint` appears in `N=5` consecutive `FORGE_GOAL_EVIDENCE` blocks in the transcript with matching `session_nonce`, the next Stop hook fire ALSO appends a soft warning to STDERR:

```
FORGE_GOAL_STUCK_WARNING: no measurable progress for 5 turns; consider invoking /council, checkpointing state.md, or surfacing a blocker. Continuing.
```

The warning does NOT abort. The loop continues. Native `/goal` budget will eventually exhaust (US-007 in PRD).

**Limitation acknowledged:** transcript-based fingerprint comparison is less deterministic than a persisted counter — if compaction drops a fingerprint, the N-count can reset. This is the explicit trade-off for state.md-only simplicity. Acceptable for v1.

---

## Layer Split (per PRD discussion Q14)

### Layer 1: Evidence Primitive (ships first, standalone)

Deliverables:

- `hooks/build-evidence.sh` + `hooks/build-evidence.ps1`
- Wired into existing `hooks/check-state-updated.{sh,ps1}` (move `stop_hook_active` early-return after evidence emission)
- `setup.sh`/`setup.ps1` copy the new files to `.claude/hooks/`
- Unit tests for the parser
- Smoke test against `../mcpgateway` per Pablo's known preference

**Useful regardless of `/forge-goal`:** the JSON evidence centralizes what existing hooks already compute ad-hoc (E2E mtime check, reviewer status). Layer 1 hardens existing gate hooks even before Layer 2.

### Layer 2: Autonomous Loop Capability (ships after Layer 1)

Deliverables:

- `/new-feature` and `/fix-bug` updated to print the `/goal` command at PRD-complete checkpoint (and to write `## /goal session` to state.md)
- State.md template updated with conventions for `## /goal session`, `## PR authorization`, reviewer-iteration head-SHA labels
- `rules/workflow.md` updated with the council-during-`/goal` trigger rule
- `check-workflow-gates.sh` updated to guard `gh pr create` against authorization mismatch
- AskUserQuestion modal text for PR authorization is part of the workflow commands' rendered output
- Documentation: update README, troubleshooting, and the existing rules to reference `/forge-goal` patterns

---

## Cross-Platform Notes

- **`stat` syntax:** `build-evidence.sh` will use GNU/BSD detection (existing `check-workflow-gates.sh` already does this — copy the pattern).
- **JSON encoding:** PowerShell's `ConvertTo-Json` differs subtly from `jq`-style output. The hooks must produce **byte-identical** JSON where it matters for transcript matching. Use a shared JSON-shape contract documented in this file; both implementations write to it explicitly.
- **UUID generation:** `uuidgen` on macOS/Linux; `[guid]::NewGuid().ToString()` on PowerShell.
- **Newline handling:** state.md must use LF on both platforms (no CRLF leakage). Existing forge convention; just enforce.

---

## Files Changed

**New files:**

- `hooks/build-evidence.sh`
- `hooks/build-evidence.ps1`
- (Optional) `hooks/lib/state-md-parser.sh` — shared parser if shape becomes complex

**Modified files:**

- `hooks/check-state-updated.sh` + `.ps1` — relocate `stop_hook_active` early-return
- `hooks/check-workflow-gates.sh` + `.ps1` — add `gh pr create` authorization guard
- `commands/new-feature.md` — add PRD-complete checkpoint + `/goal` printing
- `commands/fix-bug.md` — same
- `rules/workflow.md` — add council-during-`/goal` trigger rule
- `state.template.md` — add conventions for new sections (`## /goal session`, `## PR authorization`)
- `setup.sh` + `setup.ps1` — copy new hooks to `.claude/hooks/`
- `README.md` + `docs/` — reference the new capability

**Templates that need updating:**

- `state.template.md` — add conventions for `## /goal session`, `## PR authorization`, reviewer-iteration head-SHA labels
- `CLAUDE.template.md` — reference the `/forge-goal`-driven autonomous flow in the workflow section

---

## Test Plan

Per PRD Q21 — **(a) + (d)**: dogfood on the forge first, then manual `msai-v2` smoke before declaring v1 done.

### Layer 1 acceptance

- Unit tests for `build-evidence.sh` parser against fixture state.md files
- Hook integration test: run `check-state-updated.sh` with a controlled state.md and verify FORGE_GOAL_EVIDENCE markers appear in STDERR
- PowerShell parity test (existing forge test pattern)
- Downstream smoke: copy build-evidence.sh into `../mcpgateway` and run against its state.md

### Layer 2 acceptance

- Forge-dogfood: pick a small forge feature (e.g., add a minor rule clarification or a small `build-evidence` enhancement), run the full `/forge-goal` flow end-to-end, observe PRD-to-PR-ready
- Council-fire scenario: artificially set up a moment that would prompt the user, observe council fires and chairman verdict applied
- Budget exhaustion: set `/goal` to a tiny budget, confirm graceful checkpoint + clear failure message (US-007)
- Stuck detection: leave the loop idle for 5+ turns, confirm warning fires once
- Manual msai-v2 smoke: Pablo runs one real autonomous loop on a small downstream feature

---

## Open Questions (deferred to implementation phase)

These don't block writing the implementation plan but should be resolved during build:

- [ ] Exact handling when `## /goal session` is missing but `/goal` is active (user typed a custom condition instead of the workflow-printed one) — graceful degradation OR hard error?
- [ ] If the user manually edits `## PR authorization` to fake authorization, does anything else catch it? (We do head-SHA + nonce match, which is reasonable but not crypto.)
- [ ] How does this interact with `/release` (which also runs workflows)? Probably out of scope for v1; release is a different lifecycle.
- [ ] Should the printed `/goal` command be customizable per workflow? (E.g., `/fix-bug` may want a slightly different completion condition since its phases differ.) Probably yes; design the template renderer to accept workflow-specific overrides.

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `/goal` semantics change in a future CC release | Forge code surface is minimal (just build-evidence.sh + hook integration); detection via canary check at session start |
| Verifier rubber-stamps stale evidence | Mitigated by session_nonce + produced_at_unix + evidence_seq in JSON; condition references nonce |
| Reviewer rubber-stamping via [x] without work | Mitigated by head-SHA in reviewer rows; verifier requires SHA match |
| State.md gets edited externally during loop | Same risk as today; out of scope (existing forge assumes single agent in session) |
| PowerShell parity drift over time | Existing forge test contracts already enforce parity; extend tests to cover build-evidence.ps1 |
| Compaction loses fingerprint history → stuck detection misses | Acknowledged limitation; budget exhaustion is the backstop |

---

## What ships in this design

Two deliverables, sequenced:

1. **`build-evidence.sh` standalone** (Layer 1) — useful immediately even before `/forge-goal`
2. **The autonomous-loop capability** (Layer 2) — `/goal` printed by workflow commands, state.md conventions, hook guards, council-during-loop rule

Together they satisfy the PRD's US-001 through US-011, with deferred design details listed in Open Questions above.

---

## Next step

Run `/superpowers:writing-plans` to produce the implementation plan (file-by-file build sequence with checkpoints).
