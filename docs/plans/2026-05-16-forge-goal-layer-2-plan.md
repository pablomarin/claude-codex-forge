# forge-goal Layer 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Layer 2 of `/forge-goal` — the autonomous-loop capability that consumes Layer 1's evidence JSON. After PRD approval (for `/new-feature`) or plan approval (for `/fix-bug`), the user types ONE `/goal` command and the agent autonomously drives plan → plan-review → implement → code-review → E2E → PR-ready, surfacing council for non-PR judgment moments and pausing only at PR creation.

**Architecture:** Workflow commands (`/new-feature`, `/fix-bug`) gain a checkpoint section that generates a session nonce, writes `## /goal session` to state.md, and prints a precise `/goal` command for the user to copy-paste. `rules/workflow.md` adds a council-during-`/goal` trigger rule. `check-workflow-gates.sh`/`.ps1` adds an authorization guard on `gh pr create`. State.template.md documents the new sections (documentation only — no pre-populated empty instance).

**Key asymmetry:** `/new-feature` places the checkpoint at PRD-complete (end of Phase 1). `/fix-bug` places it at Plan-Approved (Phase 3 → Phase 4 boundary) because `/fix-bug` has NO PRD phase. The checkpoint mechanics are identical; only the placement trigger differs.

**Tech Stack:** Bash + PowerShell hooks, Markdown workflow commands (slash-command bodies are prompts to Claude), forge's existing `tests/template/lib.sh` test harness, the Layer 1 `build-evidence.{sh,ps1}` consumed implicitly through transcript evidence.

**Source artifacts:**
- Design spec: `docs/plans/2026-05-14-forge-goal-design.md`
- PRD: `docs/prds/forge-goal.md` (US-002 through US-011)
- Layer 1 plan: `docs/plans/2026-05-14-forge-goal-layer-1-plan.md` (shipped on branch `research/forge-goal-experiments`)
- Experiment record: `docs/plans/2026-05-13-forge-goal-experiments.md`

**Branch strategy:** Build Layer 2 ON TOP of `research/forge-goal-experiments` (which already has Layer 1's 20 commits). When both layers are done, ship as a single PR / `/forge-goal v1.0`.

---

## Revision History

| Version | Date       | Changes |
| ------- | ---------- | ------- |
| v1.0    | 2026-05-16 | Initial plan |
| v1.1    | 2026-05-16 | Address Codex plan-review findings (4 P1 + 2 P2): P1.1 remove `all_gates_green` from `/goal` condition; P1.2 remove pre-populated empty `## /goal session` from state.template.md + align Bash/PS guards to non-empty-nonce definition of "active"; P1.3 rename `/fix-bug` checkpoint to "Plan-Approved" at Phase 3→4 boundary; P1.4 add explicit REPLACE semantics for `/goal session` + PR auth (last-line-wins + singleton enforcement); P2.1 expand Task 10 contracts with fixture-based runtime tests; P2.2 add Task 9 stuck-detection soft warning |

---

## File Structure

**Modified files:**
- `state.template.md` — add conventions for `## /goal session`, `## PR authorization`, reviewer-iteration head-SHA labels (Task 1)
- `rules/workflow.md` — add council-during-`/goal` trigger rule (Task 2)
- `hooks/check-workflow-gates.sh` — add PR-create authorization guard (Task 3)
- `hooks/check-workflow-gates.ps1` — PowerShell parity for the guard (Task 4)
- `commands/new-feature.md` — add PRD-complete checkpoint (nonce + state.md write + `/goal` print) + PR-create gate AskUserQuestion modal text (Task 5)
- `commands/fix-bug.md` — Plan-Approved checkpoint at Phase 3→4 boundary, bug-fix-specific wording (Task 6)
- `hooks/check-state-updated.sh` + `hooks/check-state-updated.ps1` — stuck-detection soft warning when `/forge-goal` is active (Task 9)
- `docs/explanation/workflow.md` — reference `/forge-goal` autonomous flow (Task 7)
- `docs/guides/customize-project.md` — reference state.md new sections (Task 7)
- `docs/reference/permissions.md` — note the new gh-pr-create authorization gate (Task 7)
- `README.md` — version badge + Version History (Task 10)
- `docs/CHANGELOG.md` — v5.29 entry covering Layer 1 + Layer 2 (Task 10)
- `tests/template/test-contracts.sh` — extend with Layer 2 contracts (Task 10)
- `tests/template/test-hooks.sh` — add PR-create guard test cases (Tasks 3-4)

**No new files.** Layer 2 is template/rule/hook modifications + documentation. No new scripts (the agent uses Edit/Write tools directly to manage state.md sections — no helper script needed).

---

## Test Conventions

Same as Layer 1's preamble (see `docs/plans/2026-05-14-forge-goal-layer-1-plan.md` "Test Conventions"). Key reminders:

- `assert_equals` + file-path `assert_contains` (real `lib.sh` API)
- Use `scratch_dir` (auto-cleanup); no raw `mktemp`
- macOS Bash 3.2 baseline: no `declare -A`, use `[[:space:]]` not `\s`
- CRLF normalization (`tr -d '\r'`) BEFORE awk anchors when adding new state.md parsing
- Wrap test work in `( cd "$scratch" && ... )` subshells (avoids pwd leakage)

For markdown content changes (workflow commands, rules, state.template, docs), there's no traditional unit test — verify via:
1. Inspection — does the changed file say what the plan says it should?
2. Cross-file contract tests in Task 10 (e.g., "commands/new-feature.md mentions PRD-complete checkpoint")
3. Dogfood — Task 10 includes a manual run-through

---

## Tasks

### Task 1: Update `state.template.md` with new section conventions

**Files:**
- Modify: `state.template.md` (canonical state.md template that ships to downstream installs)

- [ ] **Step 1: Read current `state.template.md` to see existing format**

```bash
cat state.template.md
```

The file currently has `## Workflow`, `## State`, `## Open Questions`, `## Blockers`, `## Update Rules`. New sections need to fit this style.

- [ ] **Step 2: Add the `## /goal session` section description**

Add AFTER the existing `## Workflow` section (before `## State`). This section documents the FORMAT of the `/goal session` table — it does NOT pre-populate an empty table instance. The live table is created by the workflow command at the PRD-Complete / Plan-Approved checkpoint.

```markdown
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
```

- [ ] **Step 3: Add the `## PR authorization` section description**

Add AFTER the `## /goal session` documentation (before `## State`):

```markdown
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
```

- [ ] **Step 4: Update the `## Update Rules` section to document the reviewer-iteration head-SHA convention**

Add a new sub-section to `## Update Rules`:

```markdown
**On code-review iteration completion (during a `/forge-goal`-driven run):**

1. Append a checklist line to `### Checklist` capturing the iteration number, tool, and HEAD SHA:
   - `- [x] Code review iteration <N> — codex clean — head=\`<sha>\``
   - `- [x] Code review iteration <N> — pr-toolkit clean — head=\`<sha>\``
2. Both `codex clean` AND `pr-toolkit clean` must be present for the SAME iteration AND at the SAME current HEAD for the `reviewer_gate.clean_same_iteration` evidence to be true.
3. If a fix changes HEAD, re-run reviewers and append a NEW iteration row; do NOT mutate existing rows.

**On PR creation authorization (during a `/forge-goal`-driven run):**

1. Agent calls `AskUserQuestion` asking the user to authorize `gh pr create`.
2. On YES, agent REPLACES the entire `## PR authorization` section content with:
   - `- [x] PR creation authorized — \`<ISO-8601 timestamp>\` — nonce=\`<session nonce>\` — head=\`<current HEAD SHA>\``
3. The PR-create PreToolUse guard blocks `gh pr create` unless this line is present with a matching nonce AND head SHA.
4. On re-authorization (user re-authorizes after new commits): REPLACE the existing auth line with the fresh one; do NOT append.
```

- [ ] **Step 5: Commit**

```bash
git add -f state.template.md
git commit -m "feat(template): state.md conventions for /goal session + PR authorization + reviewer-iteration head-SHA labels

No empty /goal session instance pre-populated — the section is absent until a
workflow command creates it at the PRD-complete or Plan-Approved checkpoint.
Documents REPLACE semantics and the non-empty-nonce definition of 'active'."
```

---

### Task 2: Add council-during-`/goal` trigger rule to `rules/workflow.md`

**Files:**
- Modify: `rules/workflow.md`

- [ ] **Step 1: Read current `rules/workflow.md` to find the canonical location**

```bash
cat rules/workflow.md | head -50
```

Find the Decision Matrix and Workflow Tracking sections.

- [ ] **Step 2: Add a new section after "Workflow Tracking"**

Append this section (positioned after "Workflow Tracking", before "Severity Rubric"):

```markdown
## Council During `/forge-goal` Autonomous Run

When a `/forge-goal`-driven `/goal` is active (`## /goal session` is populated in `.claude/local/state.md` with a non-empty nonce), the agent's pause-for-user discipline changes:

**Before asking the user any question during the autonomous run, ask yourself:**

> *Is this a PR creation authorization?*

- **If YES:** call `AskUserQuestion` with the PR-create modal. The user's answer is the only human-authority signal in the loop.
- **If NO:** invoke `/council` with the question. Apply the chairman's verdict. Continue the loop.

**Triggers for council** (the agent invokes council at its discretion when):

- An ambiguous product or technical choice would otherwise prompt the user
- A reviewer recommends plan revision (not just code patch)
- A high-impact implementation fork has multiple defensible approaches
- A retried tool/subagent has also failed
- Council/reviewer output is unrecognizable and needs interpretation

**Explicit NON-triggers:**

- Normal plan-review-loop iterations (Claude + Codex back-and-forth on the plan) — these stay as today's reviewer iteration flow
- Normal code-review-loop iterations (Codex + PR-toolkit + Claude fix cycles)
- Any moment that doesn't actually require human-level judgment

**Council failure handling:** If `/council` itself fails (network, advisor timeout, missing chairman verdict), the autonomous loop pauses and writes a blocker line to `.claude/local/state.md` (`## Blockers`). The user takes over.

**Audit:** Each council invocation during an autonomous run is durable in the conversation transcript — the agent's response naming the council outcome and the applied action is the record. No separate audit log file.
```

- [ ] **Step 3: Commit**

```bash
git add -f rules/workflow.md
git commit -m "feat(rules): council-during-/forge-goal trigger rule

When /forge-goal is active, the agent's pause-for-user discipline routes
non-PR-creation questions to /council instead of AskUserQuestion. PR
creation remains the only human-authority signal in the loop."
```

---

### Task 3: PR-create authorization guard in `check-workflow-gates.sh`

**Files:**
- Modify: `hooks/check-workflow-gates.sh`
- Modify: `tests/template/test-hooks.sh` (add tests)

- [ ] **Step 1: Read current `check-workflow-gates.sh` structure**

```bash
cat hooks/check-workflow-gates.sh
```

Locate the existing PreToolUse decision block (matches `git commit`, `git push`, `gh pr create`). The new guard is INDEPENDENT of the existing checklist-completion guard — it adds an EXTRA condition when the command is `gh pr create`.

- [ ] **Step 2: Write failing tests in `tests/template/test-hooks.sh`**

Add to `tests/template/test-hooks.sh` (before the existing `report` line, after the current tests):

```bash
# ---------------------------------------------------------------------------
# Layer 2: PR-create authorization guard
# ---------------------------------------------------------------------------

start_test "check-workflow-gates blocks gh pr create when ## PR authorization missing during active /forge-goal"

scratch=$(scratch_dir wgates-prauth-missing)
mkdir -p "$scratch/.claude/local"
# state.md has /goal session populated with non-empty nonce (forge-goal active)
# but NO PR authorization line.
cat > "$scratch/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — PR Ready      |
| Next step | Authorize PR      |

### Checklist

- [x] All gates green via verify-app
- [x] E2E verified via verify-e2e agent (Phase 5.4)
- [ ] PR authorized

EOF

(
    cd "$scratch"
    INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
    OUT="$scratch/.out"
    echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" >"$OUT" 2>&1
    EXIT_CODE=$?
    echo "$EXIT_CODE" > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "2" "gh pr create BLOCKED when no ## PR authorization line (exit 2)"
assert_contains "$scratch/.out" "PR creation authorized" "hook output mentions the missing authorization"
```

Second test — authorization present and matching:

```bash
start_test "check-workflow-gates allows gh pr create when ## PR authorization matches nonce + HEAD"

scratch=$(scratch_dir wgates-prauth-match)
mkdir -p "$scratch/.claude/local"
(
    cd "$scratch"
    git init -q -b main >/dev/null
    git config user.email "t@t"
    git config user.name "t"
    echo x > a; git add a; git commit -qm init
    HEAD_SHA=$(git rev-parse HEAD)
    echo "$HEAD_SHA" > "$scratch/.expected_head"

    cat > .claude/local/state.md <<EOF
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — PR Ready      |
| Next step | Authorize PR      |

### Checklist

- [x] All gates green via verify-app
- [x] E2E verified via verify-e2e agent (Phase 5.4)
- [x] PR authorized

## PR authorization

- [x] PR creation authorized — \`2026-05-16T10:15:00Z\` — nonce=\`aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\` — head=\`$HEAD_SHA\`
EOF

    INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
    OUT="$scratch/.out"
    echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" >"$OUT" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "0" "gh pr create ALLOWED when nonce + HEAD match (exit 0)"
```

Third test — authorization present but HEAD mismatched:

```bash
start_test "check-workflow-gates blocks gh pr create when ## PR authorization head mismatched"

scratch=$(scratch_dir wgates-prauth-stalehead)
mkdir -p "$scratch/.claude/local"
(
    cd "$scratch"
    git init -q -b main >/dev/null
    git config user.email "t@t"
    git config user.name "t"
    echo x > a; git add a; git commit -qm init
    echo y > a; git add a; git commit -qm second  # advance HEAD past authorization point

    cat > .claude/local/state.md <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — PR Ready      |
| Next step | Authorize PR      |

### Checklist

- [x] PR authorized

## PR authorization

- [x] PR creation authorized — `2026-05-16T10:15:00Z` — nonce=`aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee` — head=`abc123def_stale_head`
EOF

    INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
    OUT="$scratch/.out"
    echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" >"$OUT" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "2" "gh pr create BLOCKED when authorization head doesn't match current HEAD (exit 2)"
assert_contains "$scratch/.out" "PR creation authorized" "hook output references the stale authorization"
```

Fourth test — `/forge-goal` is NOT active (no non-empty nonce in `## /goal session`), guard does NOT fire:

```bash
start_test "check-workflow-gates skips PR-auth guard when no non-empty nonce in /goal session (legacy workflow path)"

scratch=$(scratch_dir wgates-prauth-noforgegoal)
mkdir -p "$scratch/.claude/local"
# state.md WITHOUT ## /goal session — the existing checklist guard runs unchanged.
cat > "$scratch/.claude/local/state.md" <<'EOF'
## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — Ship          |
| Next step | gh pr create      |

### Checklist

- [x] All gates green via verify-app
- [x] E2E verified via verify-e2e agent (Phase 5.4)
EOF

(
    cd "$scratch"
    INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
    OUT="$scratch/.out"
    echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" >"$OUT" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "0" "PR-auth guard skipped when no /forge-goal session active"
```

Fifth test (P1.2 fix — empty /goal session heading with no nonce is treated as INACTIVE):

```bash
start_test "check-workflow-gates treats /goal session with empty nonce row as INACTIVE (no block)"

scratch=$(scratch_dir wgates-prauth-emptynonce)
mkdir -p "$scratch/.claude/local"
# state.md has ## /goal session heading but nonce row has no value — should be INACTIVE.
cat > "$scratch/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            |       |
| workflow_command |       |
| issued_at        |       |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — Ship          |
| Next step | gh pr create      |

### Checklist

- [x] All gates green via verify-app
- [x] E2E verified via verify-e2e agent (Phase 5.4)
EOF

(
    cd "$scratch"
    INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
    OUT="$scratch/.out"
    echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" >"$OUT" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "0" "PR-auth guard INACTIVE when /goal session nonce is empty (exit 0)"
```

Sixth test (P1.4 fix — stale-duplicate auth lines, guard uses LAST one):

```bash
start_test "check-workflow-gates uses LAST PR authorization line when multiple present (stale-duplicate defense)"

scratch=$(scratch_dir wgates-prauth-duplicate)
mkdir -p "$scratch/.claude/local"
(
    cd "$scratch"
    git init -q -b main >/dev/null
    git config user.email "t@t"
    git config user.name "t"
    echo x > a; git add a; git commit -qm init
    HEAD_SHA=$(git rev-parse HEAD)

    cat > .claude/local/state.md <<EOF
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## PR authorization

- [x] PR creation authorized — \`2026-05-16T09:00:00Z\` — nonce=\`stale-nonce-old-session\` — head=\`staleshastale\`
- [x] PR creation authorized — \`2026-05-16T10:15:00Z\` — nonce=\`aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\` — head=\`$HEAD_SHA\`

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — PR Ready      |
| Next step | Authorize PR      |

### Checklist

- [x] E2E verified via verify-e2e agent (Phase 5.4)
EOF

    INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
    OUT="$scratch/.out"
    echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" >"$OUT" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "0" "guard uses LAST auth line (matching nonce+HEAD) and ALLOWS when last line is valid"
```

- [ ] **Step 3: Run tests, verify FAIL**

```bash
bash tests/template/test-hooks.sh 2>&1 | tail -20
```

Expected: 6 new test blocks failing (the guard doesn't exist yet in check-workflow-gates.sh).

- [ ] **Step 4: Implement the guard in `hooks/check-workflow-gates.sh`**

The guard fires ONLY when:
1. The Bash command being attempted matches `^\s*gh\s+pr\s+create\b`
2. `## /goal session` block in `.claude/local/state.md` has a NON-EMPTY nonce value (i.e., `/forge-goal` is active)

**"Active" definition for Bash guard:** parse the `## /goal session` block and extract the nonce row value. The session is active IFF `GOAL_NONCE` is non-empty after parsing. A missing section, a section with an empty nonce cell, or a nonce value of only whitespace → all treated as INACTIVE (guard is a no-op).

When the guard fires, it checks:
- Is there a `## PR authorization` section with a `- [x] PR creation authorized` line?
- Does the LAST such line's `nonce=<value>` match `GOAL_NONCE`?
- Does the LAST such line's `head=<sha>` match `git rev-parse HEAD`?
  (Using LAST line is the defensive choice for stale-duplicate state.md corruption. Proper REPLACE semantics keep exactly one line.)

If any check fails: exit 2 with a clear error message. If all pass: fall through to the EXISTING checklist guard (which continues to apply unchanged).

```bash
# ---------------------------------------------------------------------------
# Layer 2 — /forge-goal PR-create authorization guard
#
# When /forge-goal is active (## /goal session has a non-empty nonce in state.md),
# gh pr create requires an explicit ## PR authorization line with matching nonce +
# current HEAD SHA. The line is written by the workflow agent after the user
# answers YES to the AskUserQuestion PR-create modal.
#
# ACTIVE definition: GOAL_NONCE is non-empty after parsing. An empty nonce cell,
# a missing /goal session section, or missing state.md → guard is a no-op.
#
# LAST-LINE defense: if state.md has multiple PR auth lines (state corruption),
# the guard uses the LAST one. Proper REPLACE semantics keep exactly one line;
# multiple lines surface as a diagnostic in the error message.
#
# When /forge-goal is NOT active, this guard is a no-op and the existing
# checklist-completion guard below runs unchanged.
# ---------------------------------------------------------------------------
if echo "$COMMAND" | grep -qE '^[[:space:]]*gh[[:space:]]+pr[[:space:]]+create\b'; then
    STATE_MD=".claude/local/state.md"
    if [ -f "$STATE_MD" ]; then
        # CRLF normalize before awk anchors (matches Layer 1 parser pattern)
        GOAL_BLOCK=$(tr -d '\r' < "$STATE_MD" \
                    | awk '/^## \/goal session$/{flag=1;next} flag && /^## /{flag=0} flag')
        GOAL_NONCE=""
        if [ -n "$GOAL_BLOCK" ]; then
            GOAL_NONCE=$(echo "$GOAL_BLOCK" \
                        | grep -E '\|[[:space:]]*nonce[[:space:]]*\|' \
                        | head -1 | awk -F'|' '{print $3}' | tr -d ' \t')
        fi
        if [ -n "$GOAL_NONCE" ]; then
            # /forge-goal is active (non-empty nonce); enforce PR-auth requirements
            HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")

            # Use LAST matching auth line (stale-duplicate defense; REPLACE semantics
            # should keep exactly one, but guard defensively against state corruption)
            PR_AUTH_LINE=$(tr -d '\r' < "$STATE_MD" \
                          | grep -E '^-[[:space:]]*\[x\][[:space:]]+PR creation authorized' \
                          | tail -1)

            # Count auth lines for diagnostic
            AUTH_LINE_COUNT=$(tr -d '\r' < "$STATE_MD" \
                             | grep -c '^-[[:space:]]*\[x\][[:space:]]*PR creation authorized' 2>/dev/null || echo 0)

            if [ -z "$PR_AUTH_LINE" ]; then
                echo "WORKFLOW GATE: gh pr create blocked — no ## PR authorization line in state.md." >&2
                echo "" >&2
                echo "A /forge-goal-driven workflow is active (nonce: $GOAL_NONCE)." >&2
                echo "PR creation requires user authorization via AskUserQuestion." >&2
                echo "On user YES, append (REPLACE any existing ## PR authorization content):" >&2
                echo "  - [x] PR creation authorized — \`<ts>\` — nonce=\`<n>\` — head=\`<sha>\`" >&2
                exit 2
            fi

            if [ "$AUTH_LINE_COUNT" -gt 1 ]; then
                echo "WORKFLOW GATE WARNING: Multiple PR authorization lines found in state.md (count: $AUTH_LINE_COUNT)." >&2
                echo "This indicates state.md corruption — REPLACE semantics should keep exactly one line." >&2
                echo "Using the LAST authorization line for this check. Consider cleaning state.md." >&2
            fi

            # Extract nonce and head from the auth line. Pattern:
            # - [x] PR creation authorized — `<ts>` — nonce=`<nonce>` — head=`<sha>`
            AUTH_NONCE=$(echo "$PR_AUTH_LINE" \
                        | sed -E 's/.*nonce=`([^`]+)`.*/\1/')
            AUTH_HEAD=$(echo "$PR_AUTH_LINE" \
                        | sed -E 's/.*head=`([^`]+)`.*/\1/')

            if [ "$AUTH_NONCE" != "$GOAL_NONCE" ]; then
                echo "WORKFLOW GATE: gh pr create blocked — PR authorization nonce mismatch." >&2
                echo "Session nonce:  $GOAL_NONCE" >&2
                echo "Auth line nonce: $AUTH_NONCE" >&2
                echo "Stale authorization from a previous /forge-goal session. Re-authorize via AskUserQuestion." >&2
                exit 2
            fi

            if [ -z "$HEAD_SHA" ] || [ "$AUTH_HEAD" != "$HEAD_SHA" ]; then
                echo "WORKFLOW GATE: gh pr create blocked — PR authorization HEAD mismatch." >&2
                echo "Current HEAD: $HEAD_SHA" >&2
                echo "Auth line head: $AUTH_HEAD" >&2
                echo "Commits added since authorization; re-authorize at the new HEAD." >&2
                exit 2
            fi

            # All checks passed; fall through to the existing checklist guard
        fi
    fi
fi
```

Place this block IMMEDIATELY AFTER the existing block that detects `gh pr create` for the current checklist gate. Read the file first to find the exact insertion point and match indentation/comment style.

- [ ] **Step 5: Run tests, verify PASS**

```bash
bash tests/template/test-hooks.sh 2>&1 | tail -15
```

Expected: the 6 new test blocks now pass.

- [ ] **Step 6: Commit**

```bash
git add -f hooks/check-workflow-gates.sh tests/template/test-hooks.sh
git commit -m "feat(hooks): PR-create authorization guard for /forge-goal active sessions

Blocks gh pr create when:
- /forge-goal is active (## /goal session nonce is non-empty), AND
- ## PR authorization is missing, OR nonce-mismatched, OR head-SHA-stale.

'Active' = non-empty nonce cell. Empty nonce row / missing section = INACTIVE.
LAST-line defense for stale-duplicate state.md (REPLACE semantics enforced
by workflow commands keeps exactly one auth line; guard handles corruption).
CRLF-normalized parsing. Bash 3.2 compatible (no declare -A)."
```

---

### Task 4: PowerShell parity — PR-create authorization guard in `check-workflow-gates.ps1`

**Files:**
- Modify: `hooks/check-workflow-gates.ps1`

- [ ] **Step 1: Read current `check-workflow-gates.ps1` to find the gh-pr-create branch**

```bash
cat hooks/check-workflow-gates.ps1
```

Locate the existing block that matches `gh pr create` for the checklist gate.

- [ ] **Step 2: Add the Layer 2 guard immediately after**

Port the Bash logic to PowerShell. The PS code mirrors Task 3's logic with the same "active" definition (non-empty nonce). PS 5.1 constraints from Layer 1: no `??`, no `2>&1 | Out-Null`, no `pwsh` spawn, prefer `-replace` for regex.

```powershell
# ---------------------------------------------------------------------------
# Layer 2 — /forge-goal PR-create authorization guard (PS parity for .sh)
#
# ACTIVE definition: $goalNonce is non-empty after parsing. An empty nonce
# cell, missing /goal session section, or missing state.md → guard is no-op.
# LAST-LINE defense: multiple PR auth lines → use last (REPLACE semantics
# should keep exactly one; multiple = state.md corruption, surface to user).
# ---------------------------------------------------------------------------
if ($command -match '^\s*gh\s+pr\s+create\b') {
    $stateMd = ".claude/local/state.md"
    if (Test-Path $stateMd) {
        # CRLF normalize, then scope to ## /goal session block
        $raw = Get-Content $stateMd -Raw
        if (-not $raw) { $raw = "" }
        $lines = ($raw -replace "`r", "") -split "`n"
        $inSession = $false
        $goalNonce = ""
        foreach ($line in $lines) {
            if ($line -match '^## /goal session$') { $inSession = $true; continue }
            if ($inSession -and $line -match '^## ') { break }
            if (-not $inSession) { continue }
            if ($line -match '^\|\s*nonce\s*\|\s*(.+?)\s*\|$') {
                $goalNonce = $matches[1].Trim()
            }
        }

        if ($goalNonce) {
            # /forge-goal is active (non-empty nonce); enforce PR-auth requirements
            $headSha = ""
            try { $headSha = ((git rev-parse HEAD 2>$null) -join "").Trim() } catch {}

            # Collect ALL auth lines, use LAST (stale-duplicate defense)
            $prAuthLines = @()
            foreach ($line in $lines) {
                if ($line -match '^-\s*\[x\]\s+PR creation authorized') {
                    $prAuthLines += $line
                }
            }
            $prAuthLine = if ($prAuthLines.Count -gt 0) { $prAuthLines[-1] } else { "" }

            if ($prAuthLines.Count -gt 1) {
                [Console]::Error.WriteLine("WORKFLOW GATE WARNING: Multiple PR authorization lines found ($($prAuthLines.Count)). State.md corruption — REPLACE semantics should keep exactly one. Using LAST line.")
            }

            if (-not $prAuthLine) {
                [Console]::Error.WriteLine("WORKFLOW GATE: gh pr create blocked — no ## PR authorization line in state.md.")
                [Console]::Error.WriteLine("")
                [Console]::Error.WriteLine("A /forge-goal-driven workflow is active (nonce: $goalNonce).")
                [Console]::Error.WriteLine("PR creation requires user authorization via AskUserQuestion.")
                [Console]::Error.WriteLine("On user YES, REPLACE any existing ## PR authorization content with:")
                [Console]::Error.WriteLine("  - [x] PR creation authorized -- ``<ts>`` -- nonce=``<n>`` -- head=``<sha>``")
                exit 2
            }

            $authNonce = ""
            $authHead = ""
            if ($prAuthLine -match 'nonce=`([^`]+)`') { $authNonce = $matches[1] }
            if ($prAuthLine -match 'head=`([^`]+)`')  { $authHead = $matches[1] }

            if ($authNonce -ne $goalNonce) {
                [Console]::Error.WriteLine("WORKFLOW GATE: gh pr create blocked — PR authorization nonce mismatch.")
                [Console]::Error.WriteLine("Session nonce:   $goalNonce")
                [Console]::Error.WriteLine("Auth line nonce: $authNonce")
                [Console]::Error.WriteLine("Stale authorization from a previous /forge-goal session. Re-authorize via AskUserQuestion.")
                exit 2
            }

            if (-not $headSha -or $authHead -ne $headSha) {
                [Console]::Error.WriteLine("WORKFLOW GATE: gh pr create blocked — PR authorization HEAD mismatch.")
                [Console]::Error.WriteLine("Current HEAD: $headSha")
                [Console]::Error.WriteLine("Auth line head: $authHead")
                [Console]::Error.WriteLine("Commits added since authorization; re-authorize at the new HEAD.")
                exit 2
            }

            # All checks passed; fall through to the existing checklist guard
        }
    }
}
```

The exact variable names (`$command`, etc.) and insertion point depend on the existing `check-workflow-gates.ps1` structure. Read first, adapt variable references to match.

- [ ] **Step 3: Verify parity via `test-contracts.sh` cross-file content checks** (extended in Task 10)

For now: confirm `bash tests/template/run-all.sh 2>&1 | tail -10` is still green. The PS implementation isn't directly tested in this task's TDD cycle (no PowerShell test harness); Task 10's contracts include:
(a) a cross-file check that the Bash and PS guards mention the same key error strings, and
(b) a conditional `pwsh` runtime parity test when `command -v pwsh` succeeds.

- [ ] **Step 4: Commit**

```bash
git add -f hooks/check-workflow-gates.ps1
git commit -m "feat(hooks): PowerShell parity for /forge-goal PR-create authorization guard

Mirrors Bash guard: ACTIVE = non-empty nonce, LAST-line defense for
stale-duplicate state.md, REPLACE semantics enforced by workflow commands."
```

---

### Task 5: Update `commands/new-feature.md` with PRD-complete checkpoint + PR-create gate

**Files:**
- Modify: `commands/new-feature.md` (the workflow command markdown that gets installed to `.claude/commands/new-feature.md`)

- [ ] **Step 1: Read current `commands/new-feature.md` to find phase markers**

```bash
grep -n "Phase\|PRD\|Pre-Flight" commands/new-feature.md | head -30
```

**Confirmed from pre-revision read:** `/new-feature` HAS a Phase 1 Requirements (PRD) phase (using `/prd:discuss` + `/prd:create`), followed by Phase 2 Research, Phase 3 Design + Review Loop, Phase 4 Execute, Phase 5 Quality Gates, Phase 6 Finish. The checkpoint is named **PRD-Complete Checkpoint** and placed after Phase 1 (PRD created, before Phase 2 Research begins).

- [ ] **Step 2: Add the PRD-complete `/goal`-printing checkpoint**

Add a NEW section to `commands/new-feature.md` titled `## PRD-Complete Checkpoint — Print /goal for Autonomous Loop`. This section runs AFTER Phase 1 (PRD complete) and BEFORE Phase 2 (Research) begins. Content:

```markdown
## PRD-Complete Checkpoint — Print `/goal` for Autonomous Loop

When Phase 1 (PRD) completes (PRD file exists in `docs/prds/<feature>.md` and the user is ready to advance), if you (the agent) judge `/forge-goal` would help here (the feature is substantial enough to warrant autonomous execution), you may offer the user the option to kick off the autonomous loop.

### Steps

1. **Generate a session nonce.** Run:
   ```bash
   uuidgen | tr 'A-Z' 'a-z'
   ```
   Capture the output (e.g. `5f1a2b3c-9d8e-4f6a-b7c8-1e2d3f4a5b6c`).

2. **REPLACE any existing `## /goal session` and `## PR authorization` sections in `.claude/local/state.md`.** Use the Edit tool to find the existing `## /goal session` heading (if any) and replace the entire block — heading + table + any trailing blank lines up to the next `## ` heading — with the new session. Likewise, if `## PR authorization` has any existing content, clear it now (stale auth from a prior run must not persist). Then write the new `/goal session` block immediately AFTER `## Workflow` and BEFORE `## State`:

   ```markdown
   ## /goal session

   | Field            | Value                                  |
   | ---------------- | -------------------------------------- |
   | nonce            | <UUID-from-step-1>                     |
   | workflow_command | /new-feature <name>                    |
   | issued_at        | <ISO-8601-UTC-timestamp>               |
   ```

   Use `date -u +%Y-%m-%dT%H:%M:%SZ` for the timestamp.

   **If `## /goal session` does not exist yet**, insert the section (heading + table) in the correct position using the Edit tool's insert-before capability on the `## State` heading.

3. **Print the `/goal` command for the user to copy-paste.** Format the message EXACTLY:

   ```
   ────────────────────────────────────────
    PRD approved. Type this to begin the autonomous loop:
   ────────────────────────────────────────

   /goal Continue the active Forge workflow from the current .claude/local/state.md checkpoint through research, plan, plan review, implementation, code review, simplify, verification, E2E, commit, push, PR authorization, and PR creation. Stop after the PR is open. Do not merge. If a non-PR decision would normally pause for human input, invoke /council and apply the chairman verdict. Completion condition: clear only when the latest FORGE_GOAL_EVIDENCE JSON printed after this /goal message has session_nonce="<NONCE>" AND pr_ready=true AND pr_state.state="OPEN" AND reviewer_gate.clean_same_iteration=true AND e2e_report.fresh_for_head=true AND pr_authorization.authorized=true. Ignore older evidence and evidence with any other session_nonce. CI status is not required.

   ────────────────────────────────────────
    Or type "no" to continue manually phase-by-phase.
   ```

   Substitute `<NONCE>` with the value from step 1.

   **Note:** `all_gates_green` is intentionally excluded from the condition. The `/new-feature` checklist includes post-PR items like "PR reviews addressed" and "Branch finished" — those cannot be checked while the PR is still open, making `all_gates_green` unsatisfiable at stop time. The condition above instead uses `pr_ready=true` (which captures the key quality gates: reviewer clean, E2E fresh, PR auth) plus explicit `pr_state.state="OPEN"` and `pr_authorization.authorized=true` checks.

4. **If the user types the `/goal` command**, you (the agent) enter autonomous mode per `rules/workflow.md` "Council During `/forge-goal` Autonomous Run" — pause for the PR-creation gate only, route all other doubts to `/council`.

5. **If the user declines** (types "no" or anything other than the `/goal` command), continue the standard `/new-feature` workflow phase-by-phase.

### Critical reminders during the autonomous loop

- **DO NOT** call `gh pr create` until you have run `AskUserQuestion` asking the user to authorize, and they answered YES, and you have REPLACED the `## PR authorization` section in state.md with the new authorization line (matching nonce + current HEAD SHA at the moment of authorization).
- **DO NOT** call `/goal clear` after success — `/goal` auto-clears when the verifier confirms the condition.
- **DO** track each code-review iteration by appending `- [x] Code review iteration <N> — codex clean — head=\`<sha>\`` AND `- [x] Code review iteration <N> — pr-toolkit clean — head=\`<sha>\`` to `### Checklist` (state.md). The `reviewer_gate.clean_same_iteration` evidence only fires when BOTH appear for the same iteration AND at the current HEAD.
- **DO** invoke `/council` whenever you would otherwise pause for the user (except PR creation). Apply the chairman's verdict; do not second-guess it.
- **REPLACE, never append** when writing `/goal session` or `## PR authorization`. Appending creates stale duplicate entries that confuse Layer 1's parsers.

### PR-create gate — AskUserQuestion modal text

When you (the agent) are ready to run `gh pr create` during a `/forge-goal`-driven run, FIRST call `AskUserQuestion` with this exact modal:

```
Authorize PR creation?

Branch <branch> is pushed and Forge gates are green. Summary of work:
- Files changed: <count> (<top-3-by-line-count>)
- Tests added/modified: <count>
- Reviewer status: codex clean (iter <N>) + pr-toolkit clean (iter <N>)
- E2E report: <report-path>
- Council fires this run: <count>

Create a PR to <base> using the title "<title>" and the summary above?
- Yes: write authorization to state.md and run gh pr create
- No: pause the workflow for your direction
```

On YES, REPLACE the entire `## PR authorization` section in `.claude/local/state.md` with exactly ONE line:

```
- [x] PR creation authorized — `<ISO-8601-UTC-timestamp>` — nonce=`<session nonce>` — head=`<current HEAD SHA>`
```

If `## PR authorization` does not exist yet, create it. If it exists with old content, replace all content (heading + old lines) with the heading + this one new line. Never append.

Then run `gh pr create`. The PreToolUse guard (`check-workflow-gates.{sh,ps1}`) will verify the authorization line matches before allowing the command.

On NO, append a blocker line to `## Blockers` in state.md and STOP the autonomous loop.
```

- [ ] **Step 3: Commit**

```bash
git add -f commands/new-feature.md
git commit -m "feat(commands): /new-feature PRD-complete checkpoint prints /goal for autonomous loop

Adds the PRD-complete checkpoint (after Phase 1, before Phase 2) that generates
a session nonce, REPLACES any stale /goal session and PR auth in state.md, and
prints the /goal command. Condition string excludes all_gates_green (post-PR
checklist items are structurally unclearable while PR is open). REPLACE semantics
documented explicitly. PR-create AskUserQuestion modal text documented."
```

---

### Task 6: Update `commands/fix-bug.md` with Plan-Approved checkpoint

**Files:**
- Modify: `commands/fix-bug.md`

- [ ] **Step 1: Read current `commands/fix-bug.md` structure**

```bash
grep -n "Phase\|PRD\|Pre-Flight\|Plan" commands/fix-bug.md | head -30
```

**Confirmed from pre-revision read:** `/fix-bug` has NO PRD phase. Its phases are:
- Pre-Flight
- Phase 1: Research Existing Solutions
- Phase 2: Systematic Debugging
- Phase 3: Plan the Fix (complex fixes only — has Plan Review Loop at 3.3)
- Phase 4: Execute the Fix
- Phase 5: Quality Gates
- Phase 6: Finish

The checkpoint must be placed at the **Phase 3 → Phase 4 boundary** — specifically AFTER Phase 3.3 Plan Review Loop passes (plan-review-loop box checked), and BEFORE Phase 4 begins. This applies only to complex fixes that went through Phase 3 (simple fixes skip Phase 3 and have no plan file — they skip the checkpoint too).

- [ ] **Step 2: Add the Plan-Approved checkpoint section**

Add a NEW section to `commands/fix-bug.md` titled `## Plan-Approved Checkpoint — Print /goal for Autonomous Loop`. This section is placed AFTER Phase 3 (at the end of Phase 3, after the Plan Review Loop subsection) and BEFORE Phase 4. It applies to complex fixes only (simple fixes that skip Phase 3 also skip this checkpoint).

```markdown
## Plan-Approved Checkpoint — Print `/goal` for Autonomous Loop

> **Applies to complex fixes only** (Phase 3 entered — plan file exists + plan-review-loop checked off). Simple fixes (1-2 files, Phase 3 skipped) do NOT have an autonomous-loop kickoff point because there is no plan file to drive from.

When Phase 3.3 Plan Review Loop completes cleanly (plan-review-loop box checked, no P0/P1/P2 from all available reviewers on the same pass), if you (the agent) judge `/forge-goal` would help here (the fix is substantial enough to warrant autonomous execution), you may offer the user the option to kick off the autonomous loop.

### Steps

1. **Generate a session nonce.** Run:
   ```bash
   uuidgen | tr 'A-Z' 'a-z'
   ```
   Capture the output (e.g. `5f1a2b3c-9d8e-4f6a-b7c8-1e2d3f4a5b6c`).

2. **REPLACE any existing `## /goal session` and `## PR authorization` sections in `.claude/local/state.md`.** Use the Edit tool to find the existing `## /goal session` heading (if any) and replace the entire block — heading + table + any trailing blank lines up to the next `## ` heading — with the new session. Likewise, if `## PR authorization` has any existing content, clear it now (stale auth from a prior run must not persist). Then write the new `/goal session` block immediately AFTER `## Workflow` and BEFORE `## State`:

   ```markdown
   ## /goal session

   | Field            | Value                                  |
   | ---------------- | -------------------------------------- |
   | nonce            | <UUID-from-step-1>                     |
   | workflow_command | /fix-bug <name>                        |
   | issued_at        | <ISO-8601-UTC-timestamp>               |
   ```

   Use `date -u +%Y-%m-%dT%H:%M:%SZ` for the timestamp.

   **If `## /goal session` does not exist yet**, insert the section (heading + table) in the correct position using the Edit tool's insert-before capability on the `## State` heading.

3. **Print the `/goal` command for the user to copy-paste.** Format the message EXACTLY:

   ```
   ────────────────────────────────────────
    Fix plan approved. Type this to begin the autonomous loop:
   ────────────────────────────────────────

   /goal Continue the active Forge bug-fix workflow from the current .claude/local/state.md checkpoint through implementation, code review, simplify, verification, E2E, commit, push, PR authorization, and PR creation. Stop after the PR is open. Do not merge. If a non-PR decision would normally pause for human input, invoke /council and apply the chairman verdict. Completion condition: clear only when the latest FORGE_GOAL_EVIDENCE JSON printed after this /goal message has session_nonce="<NONCE>" AND pr_ready=true AND pr_state.state="OPEN" AND reviewer_gate.clean_same_iteration=true AND e2e_report.fresh_for_head=true AND pr_authorization.authorized=true. Ignore older evidence and evidence with any other session_nonce. CI status is not required.

   ────────────────────────────────────────
    Or type "no" to continue manually phase-by-phase.
   ```

   Substitute `<NONCE>` with the value from step 1.

   **Note:** `all_gates_green` is intentionally excluded from the condition. The `/fix-bug` checklist includes post-PR items like "PR reviews addressed" and "Branch finished" — those cannot be checked while the PR is still open, making `all_gates_green` unsatisfiable at stop time. The condition above instead uses `pr_ready=true` (which captures the key quality gates: reviewer clean, E2E fresh, PR auth) plus explicit `pr_state.state="OPEN"` and `pr_authorization.authorized=true` checks.

4. **If the user types the `/goal` command**, you (the agent) enter autonomous mode per `rules/workflow.md` "Council During `/forge-goal` Autonomous Run" — pause for the PR-creation gate only, route all other doubts to `/council`.

5. **If the user declines** (types "no" or anything other than the `/goal` command), continue the standard `/fix-bug` workflow phase-by-phase from Phase 4.

### Critical reminders during the autonomous loop

- **DO NOT** call `gh pr create` until you have run `AskUserQuestion` asking the user to authorize, and they answered YES, and you have REPLACED the `## PR authorization` section in state.md with the new authorization line (matching nonce + current HEAD SHA at the moment of authorization).
- **DO NOT** call `/goal clear` after success — `/goal` auto-clears when the verifier confirms the condition.
- **DO** track each code-review iteration by appending `- [x] Code review iteration <N> — codex clean — head=\`<sha>\`` AND `- [x] Code review iteration <N> — pr-toolkit clean — head=\`<sha>\`` to `### Checklist` (state.md). The `reviewer_gate.clean_same_iteration` evidence only fires when BOTH appear for the same iteration AND at the current HEAD.
- **DO** invoke `/council` whenever you would otherwise pause for the user (except PR creation). Apply the chairman's verdict; do not second-guess it.
- **REPLACE, never append** when writing `/goal session` or `## PR authorization`. Appending creates stale duplicate entries that confuse Layer 1's parsers.

### PR-create gate — AskUserQuestion modal text

When you (the agent) are ready to run `gh pr create` during a `/forge-goal`-driven run, FIRST call `AskUserQuestion` with this exact modal:

```
Authorize PR creation?

Branch <branch> is pushed and Forge gates are green. Summary of fix:
- Files changed: <count> (<top-3-by-line-count>)
- Tests added/modified: <count>
- Reviewer status: codex clean (iter <N>) + pr-toolkit clean (iter <N>)
- E2E report: <report-path>
- Council fires this run: <count>

Create a PR to <base> using the title "<title>" and the summary above?
- Yes: write authorization to state.md and run gh pr create
- No: pause the workflow for your direction
```

On YES, REPLACE the entire `## PR authorization` section in `.claude/local/state.md` with exactly ONE line:

```
- [x] PR creation authorized — `<ISO-8601-UTC-timestamp>` — nonce=`<session nonce>` — head=`<current HEAD SHA>`
```

If `## PR authorization` does not exist yet, create it. If it exists with old content, replace all content (heading + old lines) with the heading + this one new line. Never append.

Then run `gh pr create`. The PreToolUse guard (`check-workflow-gates.{sh,ps1}`) will verify the authorization line matches before allowing the command.

On NO, append a blocker line to `## Blockers` in state.md and STOP the autonomous loop.
```

- [ ] **Step 3: Verify cross-file differences are ONLY the intended ones**

```bash
diff <(awk '/^## Plan-Approved Checkpoint/,/^## Phase 4/' commands/fix-bug.md | head -120) \
     <(awk '/^## PRD-Complete Checkpoint/,/^## Phase 2/' commands/new-feature.md | head -120)
```

Expected diffs (legitimate):
- Section title: "Plan-Approved Checkpoint" vs "PRD-Complete Checkpoint"
- Phase boundary: "Phase 3 → Phase 4" vs "Phase 1 → Phase 2"
- workflow_command value: `/fix-bug <name>` vs `/new-feature <name>`
- Print banner: "Fix plan approved." vs "PRD approved."
- Scope note: "through implementation, code review..." (skips plan/research) vs "through research, plan, plan review, implementation..."
- "complex fixes only" scope note
- "Summary of fix" vs "Summary of work"

Structure should be otherwise identical (same REPLACE semantics, same exclusion of `all_gates_green`, same nonce steps, same modal format, same PR-create behavior).

- [ ] **Step 4: Commit**

```bash
git add -f commands/fix-bug.md
git commit -m "feat(commands): /fix-bug Plan-Approved checkpoint prints /goal for autonomous loop

Places checkpoint at Phase 3→4 boundary (after plan-review-loop passes,
before execution). Named Plan-Approved (not PRD-complete) because /fix-bug
has no PRD phase. Applies to complex fixes only. Same REPLACE semantics
and all_gates_green exclusion as /new-feature's checkpoint."
```

---

### Task 7: Update documentation (README, explanation, guides, reference)

**Files:**
- Modify: `docs/explanation/workflow.md` — reference `/forge-goal` autonomous flow
- Modify: `docs/guides/customize-project.md` — reference state.md new sections
- Modify: `docs/reference/permissions.md` — note the new gh-pr-create authorization gate

- [ ] **Step 1: Read each file's relevant section**

```bash
grep -n "gh pr create\|workflow\|state.md" docs/explanation/workflow.md docs/guides/customize-project.md docs/reference/permissions.md
```

- [ ] **Step 2: Add `/forge-goal` paragraphs to `docs/explanation/workflow.md`**

Append a new section to `docs/explanation/workflow.md` (after the main workflow description, before any FAQ or appendices):

```markdown
## `/forge-goal` Autonomous Loop (Layer 2)

When the workflow's gate checkpoint passes (PRD-complete for `/new-feature`; Plan-Approved for `/fix-bug`), the workflow command offers an autonomous-loop kickoff. The user copies the printed `/goal <condition>` command into their next message; the agent then drives plan → plan-review → implement → code-review-loop → E2E → PR-ready without further phase-by-phase prompting.

### Checkpoint placement asymmetry

| Command | Checkpoint | Trigger |
| --- | --- | --- |
| `/new-feature` | PRD-Complete | After Phase 1 PRD created, before Phase 2 Research |
| `/fix-bug` (complex) | Plan-Approved | After Phase 3.3 Plan Review Loop passes, before Phase 4 Execute |
| `/fix-bug` (simple) | None | Simple fixes skip Phase 3 and have no plan file to drive from |
| `/quick-fix` | None | Trivial changes are not eligible for autonomous loop |

### What the loop does

- Reads `.claude/local/state.md` each turn (the workflow checklist + `/goal session` nonce)
- Surfaces evidence each turn via `hooks/build-evidence.sh` (Layer 1) — a JSON blob between `FORGE_GOAL_EVIDENCE_BEGIN/END` markers on STDERR
- The native Anthropic `/goal` verifier reads the transcript on each Stop event and decides whether the completion condition holds
- Stops only at the PR-creation gate (AskUserQuestion authorizes; the `check-workflow-gates` hook enforces nonce + HEAD match before `gh pr create` runs)
- Invokes `/council` instead of pausing for the user on any other ambiguous decision

### When NOT to use it

- Trivial changes (`/quick-fix` flow) — autonomous loop is overkill
- When you want to review each phase by hand
- When `/goal` is unavailable on your Claude Code version (requires CC 2.1.139+)

### Disabling it

Decline the autonomous loop offer at the checkpoint and the workflow falls back to the standard phase-by-phase flow.
```

- [ ] **Step 3: Update `docs/guides/customize-project.md`**

Find the existing description of state.md sections. Add a paragraph noting the new sections:

```markdown
When a `/forge-goal`-driven workflow is active, additional sections appear in `.claude/local/state.md`:

- `## /goal session` — table with the autonomous-loop session nonce, originating workflow command, and issued-at timestamp. Absent when no loop is active; written by the workflow command checkpoint and REPLACED (not appended) on each new kickoff.
- `## PR authorization` — single authorization line written when the user authorizes PR creation via the `AskUserQuestion` modal at the PR-create gate. Contains the timestamp, session nonce, and HEAD SHA at the moment of authorization. REPLACED (not appended) on each re-authorization.
- `### Checklist` rows for reviewer iterations include `head=\`<sha>\`` so the evidence script can verify both reviewers cleared at the same iteration AND at the same HEAD.

**REPLACE semantics are critical:** both `/goal session` and `## PR authorization` are managed as singletons. The workflow commands always overwrite existing content, never append. Appending would cause Layer 1's parsers (which use `head -1` on matching lines) to pick up stale data from previous sessions.
```

- [ ] **Step 4: Update `docs/reference/permissions.md`**

Find the existing `gh pr create` row in the permissions table. Update it (or add a footnote):

```markdown
| **gh pr create**                           | Yes     | Creating PR requires approval. During a `/forge-goal`-driven autonomous loop, also requires `## PR authorization` in state.md with matching nonce + HEAD SHA (set by the agent after the user answers YES to the PR-create AskUserQuestion modal). The authorization is tied to the session nonce (no cross-session replay) and the exact HEAD SHA at authorization time (no stale commits). |
```

- [ ] **Step 5: Commit**

```bash
git add -f docs/explanation/workflow.md docs/guides/customize-project.md docs/reference/permissions.md
git commit -m "docs: reference /forge-goal autonomous loop + new state.md sections

Documents checkpoint placement asymmetry (/new-feature PRD-complete vs
/fix-bug Plan-Approved), REPLACE semantics for /goal session and PR auth,
and the gh-pr-create nonce+HEAD authorization gate."
```

---

### Task 8: Stuck-Detection Soft Warning

**PRD coverage:** US-008 — "When the loop appears stuck (no progress for N turns), the agent gets a soft signal warning; auto-abort is NOT enforced."

**Files:**
- Modify: `hooks/check-state-updated.sh`
- Modify: `hooks/check-state-updated.ps1`
- Modify: `tests/template/test-hooks.sh` (add stuck-detection test cases)

**Design:** When `/forge-goal` is active, compare the current `progress_fingerprint` (emitted by `build-evidence.sh`) to fingerprints from the previous turns, tracked via a counter file at `.claude/local/forge-goal-stuck-count`. If 5 consecutive turns emit the same fingerprint: emit a soft warning to STDERR. Warning is informational — no abort, no exit-code change.

**Counter file format:** `.claude/local/forge-goal-stuck-count` contains two lines:
```
<last_seen_fingerprint>
<consecutive_count>
```
Reset to `0` when fingerprint changes. This file is gitignored (under `.claude/local/`).

- [ ] **Step 1: Write failing tests in `tests/template/test-hooks.sh`**

Add stuck-detection tests:

```bash
# ---------------------------------------------------------------------------
# Layer 2: Stuck-detection soft warning (US-008)
# ---------------------------------------------------------------------------

start_test "check-state-updated emits FORGE_GOAL_STUCK_WARNING after 5 consecutive identical fingerprints"

scratch=$(scratch_dir stuck-detection-fires)
mkdir -p "$scratch/.claude/local"
cat > "$scratch/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 4 — Execute       |
| Next step | Implement         |
EOF

# Simulate 5 consecutive identical fingerprints by pre-writing the counter file.
printf 'abc123fingerprint\n5\n' > "$scratch/.claude/local/forge-goal-stuck-count"

(
    cd "$scratch"
    # Invoke with a simulated evidence fingerprint matching the stuck one.
    # The hook reads the counter file and sees count=5 → emits warning.
    FORGE_GOAL_FINGERPRINT="abc123fingerprint" \
        bash "$REPO_ROOT/hooks/check-state-updated.sh" >"$scratch/.out" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "0" "stuck-detection warning does NOT abort (exit 0)"
assert_contains "$scratch/.out" "FORGE_GOAL_STUCK_WARNING" "hook emits FORGE_GOAL_STUCK_WARNING after 5 identical fingerprints"
```

```bash
start_test "check-state-updated does NOT emit warning after 4 consecutive identical fingerprints"

scratch=$(scratch_dir stuck-detection-silent)
mkdir -p "$scratch/.claude/local"
cat > "$scratch/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 4 — Execute       |
| Next step | Implement         |
EOF

# Only 4 consecutive — below threshold.
printf 'abc123fingerprint\n4\n' > "$scratch/.claude/local/forge-goal-stuck-count"

(
    cd "$scratch"
    FORGE_GOAL_FINGERPRINT="abc123fingerprint" \
        bash "$REPO_ROOT/hooks/check-state-updated.sh" >"$scratch/.out" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "0" "hook exits 0 at 4 consecutive (below threshold)"
# The output should NOT contain the warning
if grep -q "FORGE_GOAL_STUCK_WARNING" "$scratch/.out"; then
    fail_test "hook emitted FORGE_GOAL_STUCK_WARNING at 4 consecutive (should not)"
else
    pass_test "no FORGE_GOAL_STUCK_WARNING at 4 consecutive (correct)"
fi
```

```bash
start_test "check-state-updated resets stuck counter on fingerprint change"

scratch=$(scratch_dir stuck-detection-reset)
mkdir -p "$scratch/.claude/local"
cat > "$scratch/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 4 — Execute       |
| Next step | Implement         |
EOF

# Counter shows 10 identical — would trigger — but fingerprint CHANGES this turn.
printf 'old-fingerprint\n10\n' > "$scratch/.claude/local/forge-goal-stuck-count"

(
    cd "$scratch"
    FORGE_GOAL_FINGERPRINT="new-different-fingerprint" \
        bash "$REPO_ROOT/hooks/check-state-updated.sh" >"$scratch/.out" 2>&1
    echo $? > "$scratch/.exit"
    # Counter file should now contain new fingerprint with count=1
    COUNT_CONTENT=$(cat .claude/local/forge-goal-stuck-count 2>/dev/null || echo "")
    echo "$COUNT_CONTENT" > "$scratch/.count_content"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "0" "hook exits 0 after fingerprint change"
if grep -q "FORGE_GOAL_STUCK_WARNING" "$scratch/.out"; then
    fail_test "hook emitted FORGE_GOAL_STUCK_WARNING after fingerprint change (should not)"
else
    pass_test "no warning after fingerprint change (correct — counter reset)"
fi
assert_contains "$scratch/.count_content" "new-different-fingerprint" "counter file updated to new fingerprint"
```

```bash
start_test "check-state-updated skips stuck detection when /forge-goal is NOT active"

scratch=$(scratch_dir stuck-detection-inactive)
mkdir -p "$scratch/.claude/local"
# No /goal session (or empty nonce) → stuck detection does not fire
cat > "$scratch/.claude/local/state.md" <<'EOF'
## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 4 — Execute       |
| Next step | Implement         |
EOF

# Even if counter says 10 identical — no active /goal session → no detection
printf 'abc123fingerprint\n10\n' > "$scratch/.claude/local/forge-goal-stuck-count"

(
    cd "$scratch"
    FORGE_GOAL_FINGERPRINT="abc123fingerprint" \
        bash "$REPO_ROOT/hooks/check-state-updated.sh" >"$scratch/.out" 2>&1
    echo $? > "$scratch/.exit"
)

EXIT=$(cat "$scratch/.exit")
assert_equals "$EXIT" "0" "hook exits 0 when no active /forge-goal session"
if grep -q "FORGE_GOAL_STUCK_WARNING" "$scratch/.out"; then
    fail_test "hook emitted FORGE_GOAL_STUCK_WARNING when /forge-goal inactive (should not)"
else
    pass_test "no stuck-detection when /forge-goal inactive (correct)"
fi
```

- [ ] **Step 2: Run tests, verify FAIL**

```bash
bash tests/template/test-hooks.sh 2>&1 | grep -E "PASS|FAIL|stuck" | tail -20
```

Expected: 4 new stuck-detection test blocks failing.

- [ ] **Step 3: Implement stuck-detection in `hooks/check-state-updated.sh`**

Read the current file first:
```bash
cat hooks/check-state-updated.sh
```

Add the stuck-detection block BEFORE the existing early-return / `stop_hook_active` check (so it fires even when the stop hook is active inside a `/goal` loop). Placement: after the initial state.md read, inside the `/forge-goal`-active branch.

```bash
# ---------------------------------------------------------------------------
# Layer 2: Stuck-detection soft warning (US-008)
#
# When /forge-goal is active and the caller supplies FORGE_GOAL_FINGERPRINT
# (set by build-evidence.sh before invoking this hook, or by the Stop hook
# pipeline), compare the current fingerprint to the previous turn's.
# If 5 consecutive identical fingerprints: emit a soft warning to STDERR.
# The warning is INFORMATIONAL — does NOT abort (exit 0 always).
#
# Counter file: .claude/local/forge-goal-stuck-count
# Format: two lines: <last_fingerprint>\n<consecutive_count>
# ---------------------------------------------------------------------------
STUCK_THRESHOLD=5
STUCK_COUNTER_FILE=".claude/local/forge-goal-stuck-count"
CURRENT_FINGERPRINT="${FORGE_GOAL_FINGERPRINT:-}"

if [ -n "$GOAL_NONCE" ] && [ -n "$CURRENT_FINGERPRINT" ]; then
    # Read existing counter
    LAST_FP=""
    LAST_COUNT=0
    if [ -f "$STUCK_COUNTER_FILE" ]; then
        LAST_FP=$(sed -n '1p' "$STUCK_COUNTER_FILE" 2>/dev/null | tr -d '\r' | tr -d '\n')
        LAST_COUNT=$(sed -n '2p' "$STUCK_COUNTER_FILE" 2>/dev/null | tr -d '\r' | tr -d '\n')
        # Validate count is a number
        case "$LAST_COUNT" in
            ''|*[!0-9]*) LAST_COUNT=0 ;;
        esac
    fi

    if [ "$CURRENT_FINGERPRINT" = "$LAST_FP" ]; then
        NEW_COUNT=$((LAST_COUNT + 1))
    else
        NEW_COUNT=1
    fi

    # Update counter file (atomic-ish: write to tmp then mv)
    TMP_COUNTER=$(mktemp "${STUCK_COUNTER_FILE}.XXXXXX" 2>/dev/null || echo "${STUCK_COUNTER_FILE}.tmp")
    printf '%s\n%s\n' "$CURRENT_FINGERPRINT" "$NEW_COUNT" > "$TMP_COUNTER"
    mv "$TMP_COUNTER" "$STUCK_COUNTER_FILE" 2>/dev/null || true

    if [ "$NEW_COUNT" -ge "$STUCK_THRESHOLD" ]; then
        echo "FORGE_GOAL_STUCK_WARNING: no measurable progress for ${NEW_COUNT} consecutive turns (fingerprint unchanged). Consider invoking /council to unblock, checkpointing your state in state.md, or surfacing a blocker. The autonomous loop continues — this is a soft signal only." >&2
    fi
fi
```

**Integration note:** The `FORGE_GOAL_FINGERPRINT` env var must be set by the Stop hook pipeline before invoking `check-state-updated.sh`. The Stop hook calls `build-evidence.sh` first (Layer 1 already ensures this); the fingerprint from that output should be passed as an env var. Update the Stop hook invocation chain in `check-state-updated.sh` (or its caller) accordingly — read the actual hook structure first to find the right integration point.

- [ ] **Step 4: Implement PS parity in `hooks/check-state-updated.ps1`**

Port the stuck-detection block. PS 5.1 constraints apply (no `??`, use `[Console]::Error.WriteLine`).

```powershell
# ---------------------------------------------------------------------------
# Layer 2: Stuck-detection soft warning (US-008) — PS parity for .sh
# ---------------------------------------------------------------------------
$stuckThreshold = 5
$stuckCounterFile = ".claude/local/forge-goal-stuck-count"
$currentFingerprint = $env:FORGE_GOAL_FINGERPRINT

if ($goalNonce -and $currentFingerprint) {
    $lastFp = ""
    $lastCount = 0
    if (Test-Path $stuckCounterFile) {
        $counterLines = (Get-Content $stuckCounterFile -Raw) -replace "`r", "" -split "`n"
        if ($counterLines.Count -ge 1) { $lastFp = $counterLines[0].Trim() }
        if ($counterLines.Count -ge 2) {
            $parsed = 0
            if ([int]::TryParse($counterLines[1].Trim(), [ref]$parsed)) { $lastCount = $parsed }
        }
    }

    if ($currentFingerprint -eq $lastFp) {
        $newCount = $lastCount + 1
    } else {
        $newCount = 1
    }

    # Write counter file
    try {
        [System.IO.File]::WriteAllText(
            (Resolve-Path $stuckCounterFile -ErrorAction SilentlyContinue).Path,
            "$currentFingerprint`n$newCount`n"
        )
    } catch {
        # Best-effort; if file write fails, don't abort
        try {
            $dir = Split-Path $stuckCounterFile -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [System.IO.File]::WriteAllText(
                [System.IO.Path]::GetFullPath($stuckCounterFile),
                "$currentFingerprint`n$newCount`n"
            )
        } catch {}
    }

    if ($newCount -ge $stuckThreshold) {
        [Console]::Error.WriteLine("FORGE_GOAL_STUCK_WARNING: no measurable progress for $newCount consecutive turns (fingerprint unchanged). Consider invoking /council to unblock, checkpointing your state in state.md, or surfacing a blocker. The autonomous loop continues — this is a soft signal only.")
    }
}
```

- [ ] **Step 5: Run tests, verify PASS**

```bash
bash tests/template/test-hooks.sh 2>&1 | grep -E "PASS|FAIL|stuck" | tail -20
```

Expected: all 4 stuck-detection test blocks now pass.

- [ ] **Step 6: Commit**

```bash
git add -f hooks/check-state-updated.sh hooks/check-state-updated.ps1 tests/template/test-hooks.sh
git commit -m "feat(hooks): stuck-detection soft warning for /forge-goal active sessions (US-008)

After 5 consecutive turns with identical progress_fingerprint, emits
FORGE_GOAL_STUCK_WARNING to STDERR. Warning is informational only (exit 0).
Counter file: .claude/local/forge-goal-stuck-count (gitignored, two-line format).
Resets on fingerprint change. Skips when /forge-goal is inactive (empty nonce).
Bash + PowerShell parity."
```

---

### Task 9: Update documentation (explanation, guides, reference)

**Files:**
- Modify: `docs/explanation/workflow.md` — reference `/forge-goal` autonomous flow
- Modify: `docs/guides/customize-project.md` — reference state.md new sections
- Modify: `docs/reference/permissions.md` — note the new gh-pr-create authorization gate

*(This was formerly Task 7. Renumbered to accommodate Task 8 stuck-detection.)*

- [ ] **Step 1: Read each file's relevant section**

```bash
grep -n "gh pr create\|workflow\|state.md" docs/explanation/workflow.md docs/guides/customize-project.md docs/reference/permissions.md
```

- [ ] **Step 2: Add `/forge-goal` paragraphs to `docs/explanation/workflow.md`**

Append a new section to `docs/explanation/workflow.md` (after the main workflow description, before any FAQ or appendices):

```markdown
## `/forge-goal` Autonomous Loop (Layer 2)

When the workflow's gate checkpoint passes (PRD-complete for `/new-feature`; Plan-Approved for complex `/fix-bug`), the workflow command offers an autonomous-loop kickoff. The user copies the printed `/goal <condition>` command into their next message; the agent then drives plan → plan-review → implement → code-review-loop → E2E → PR-ready without further phase-by-phase prompting.

### Checkpoint placement asymmetry

| Command | Checkpoint name | Trigger |
| --- | --- | --- |
| `/new-feature` | PRD-Complete Checkpoint | After Phase 1 PRD created, before Phase 2 Research |
| `/fix-bug` (complex) | Plan-Approved Checkpoint | After Phase 3.3 Plan Review Loop passes, before Phase 4 Execute |
| `/fix-bug` (simple) | None | Simple fixes skip Phase 3 and have no plan file to drive from |
| `/quick-fix` | None | Trivial changes are not eligible for autonomous loop |

### What the loop does

- Reads `.claude/local/state.md` each turn (the workflow checklist + `/goal session` nonce)
- Surfaces evidence each turn via `hooks/build-evidence.sh` (Layer 1) — a JSON blob between `FORGE_GOAL_EVIDENCE_BEGIN/END` markers on STDERR
- The native Anthropic `/goal` verifier reads the transcript on each Stop event and decides whether the completion condition holds
- Stops only at the PR-creation gate (AskUserQuestion authorizes; the `check-workflow-gates` hook enforces nonce + HEAD match before `gh pr create` runs)
- Invokes `/council` instead of pausing for the user on any other ambiguous decision
- Emits a soft stuck-detection warning (FORGE_GOAL_STUCK_WARNING) after 5 consecutive turns with no measurable progress — loop continues, this is advisory only

### When NOT to use it

- Trivial changes (`/quick-fix` flow) — autonomous loop is overkill
- Simple bug fixes (1-2 files, skipping Phase 3) — no plan file to drive from
- When you want to review each phase by hand
- When `/goal` is unavailable on your Claude Code version (requires CC 2.1.139+)

### Disabling it

Decline the autonomous loop offer at the checkpoint and the workflow falls back to the standard phase-by-phase flow.
```

- [ ] **Step 3: Update `docs/guides/customize-project.md`**

Find the existing description of state.md sections. Add a paragraph noting the new sections:

```markdown
When a `/forge-goal`-driven workflow is active, additional sections appear in `.claude/local/state.md`:

- `## /goal session` — table with the autonomous-loop session nonce, originating workflow command, and issued-at timestamp. Absent when no loop is active; written by the workflow command checkpoint and REPLACED (not appended) on each new kickoff.
- `## PR authorization` — single authorization line written when the user authorizes PR creation via the `AskUserQuestion` modal at the PR-create gate. Contains the timestamp, session nonce, and HEAD SHA at the moment of authorization. REPLACED (not appended) on each re-authorization.
- `### Checklist` rows for reviewer iterations include `head=\`<sha>\`` so the evidence script can verify both reviewers cleared at the same iteration AND at the same HEAD.

The file `.claude/local/forge-goal-stuck-count` (also gitignored) tracks consecutive identical fingerprints for the stuck-detection warning. It is reset automatically when progress is detected and can be deleted manually to silence a spurious warning.

**REPLACE semantics are critical:** both `/goal session` and `## PR authorization` are managed as singletons. The workflow commands always overwrite existing content, never append. Appending would cause Layer 1's parsers to pick up stale data from previous sessions.
```

- [ ] **Step 4: Update `docs/reference/permissions.md`**

Find the existing `gh pr create` row in the permissions table. Update it (or add a footnote):

```markdown
| **gh pr create**                           | Yes     | Creating PR requires approval. During a `/forge-goal`-driven autonomous loop, also requires `## PR authorization` in state.md with matching nonce + HEAD SHA (set by the agent after the user answers YES to the PR-create AskUserQuestion modal). The authorization is tied to the session nonce (no cross-session replay) and the exact HEAD SHA at authorization time (no stale commits). |
```

- [ ] **Step 5: Commit**

```bash
git add -f docs/explanation/workflow.md docs/guides/customize-project.md docs/reference/permissions.md
git commit -m "docs: reference /forge-goal autonomous loop + new state.md sections + stuck-detection

Documents checkpoint placement asymmetry, REPLACE semantics, forge-goal-stuck-count
counter file, and the gh-pr-create nonce+HEAD authorization gate."
```

---

### Task 10: Layer 1+2 Release — CHANGELOG, README, cross-file contracts, dogfood

**Files:**
- Modify: `tests/template/test-contracts.sh` — add Layer 2 contracts
- Modify: `docs/CHANGELOG.md` — v5.29 entry (covers Layer 1 + Layer 2 combined)
- Modify: `README.md` — version badge + Version History row

- [ ] **Step 1: Extend `tests/template/test-contracts.sh`**

Add the following Layer 2 contracts (in addition to the existing Layer 1 contract):

```bash
# ---------------------------------------------------------------------------
# Contract: /forge-goal Layer 2 — workflow commands have their checkpoint sections
# ---------------------------------------------------------------------------
start_test "Layer 2 — /new-feature has PRD-Complete Checkpoint with correct content"

NF="$REPO_ROOT/commands/new-feature.md"
assert_file_exists "$NF" "commands/new-feature.md exists"
assert_contains "$NF" "PRD-Complete Checkpoint" "new-feature.md has PRD-complete checkpoint section"
assert_contains "$NF" "FORGE_GOAL_EVIDENCE" "new-feature.md references Layer 1 evidence markers in condition"
assert_contains "$NF" "session_nonce" "new-feature.md references session_nonce in condition"
assert_contains "$NF" "pr_ready=true" "new-feature.md uses pr_ready=true in condition"
assert_contains "$NF" "AskUserQuestion" "new-feature.md references AskUserQuestion at PR-create gate"
# P1.1: all_gates_green must NOT appear in the /goal condition string
if grep -q 'all_gates_green=true' "$NF"; then
    fail_test "new-feature.md /goal condition contains all_gates_green=true (unsatisfiable — must be absent)"
else
    pass_test "new-feature.md /goal condition does NOT contain all_gates_green=true (correct)"
fi
# P1.4: REPLACE semantics documented
assert_contains "$NF" "REPLACE" "new-feature.md documents REPLACE semantics for /goal session and PR auth"

start_test "Layer 2 — /fix-bug has Plan-Approved Checkpoint at Phase 3→4 boundary"

FB="$REPO_ROOT/commands/fix-bug.md"
assert_file_exists "$FB" "commands/fix-bug.md exists"
assert_contains "$FB" "Plan-Approved Checkpoint" "fix-bug.md has Plan-Approved checkpoint (not PRD-complete)"
# P1.3: fix-bug must NOT use PRD-complete naming
if grep -q "PRD-Complete Checkpoint" "$FB"; then
    fail_test "fix-bug.md has PRD-Complete Checkpoint section (incorrect — must be Plan-Approved)"
else
    pass_test "fix-bug.md does NOT have PRD-Complete Checkpoint naming (correct)"
fi
assert_contains "$FB" "Phase 3" "fix-bug.md checkpoint references Phase 3"
assert_contains "$FB" "Phase 4" "fix-bug.md checkpoint references Phase 4 boundary"
assert_contains "$FB" "session_nonce" "fix-bug.md references session_nonce in condition"
assert_contains "$FB" "pr_ready=true" "fix-bug.md uses pr_ready=true in condition"
# P1.1: all_gates_green must NOT appear in the /goal condition string
if grep -q 'all_gates_green=true' "$FB"; then
    fail_test "fix-bug.md /goal condition contains all_gates_green=true (unsatisfiable — must be absent)"
else
    pass_test "fix-bug.md /goal condition does NOT contain all_gates_green=true (correct)"
fi
# P1.4: REPLACE semantics documented
assert_contains "$FB" "REPLACE" "fix-bug.md documents REPLACE semantics for /goal session and PR auth"

# ---------------------------------------------------------------------------
# Contract: /forge-goal Layer 2 — rules/workflow.md has council-during-/goal rule
# ---------------------------------------------------------------------------
start_test "Layer 2 — rules/workflow.md has council-during-/goal trigger rule"

WF_RULE="$REPO_ROOT/rules/workflow.md"
assert_file_exists "$WF_RULE" "rules/workflow.md exists"
assert_contains "$WF_RULE" "Council During" "council section header present"
assert_contains "$WF_RULE" "PR creation authorization" "PR-creation pause exception documented"
assert_contains "$WF_RULE" "/council" "invokes /council for non-PR doubts"

# ---------------------------------------------------------------------------
# Contract: /forge-goal Layer 2 — state.template.md has new section docs (no empty instance)
# ---------------------------------------------------------------------------
start_test "Layer 2 — state.template.md documents /goal session + PR authorization conventions"

ST_TPL="$REPO_ROOT/state.template.md"
assert_file_exists "$ST_TPL" "state.template.md exists"
assert_contains "$ST_TPL" "## /goal session" "/goal session section documented"
assert_contains "$ST_TPL" "## PR authorization" "PR authorization section documented"
assert_contains "$ST_TPL" "Code review iteration" "reviewer-iteration head-SHA convention documented"
assert_contains "$ST_TPL" "REPLACE semantics" "REPLACE semantics documented in state.template.md"
# P1.2: state.template must NOT have a pre-populated empty /goal session table
# (The section documents the FORMAT, not an empty instance.)
# Check that the nonce row, if present, does not have an empty value placeholder
# that would cause the Bash guard to find a block with no actual nonce.
if grep -E '^\|\s*nonce\s*\|\s*\|\s*$' "$ST_TPL" > /dev/null 2>&1; then
    fail_test "state.template.md has empty nonce row (would cause false-active /goal session detection)"
else
    pass_test "state.template.md does NOT have empty nonce row (correct — format documented, not instantiated)"
fi

# ---------------------------------------------------------------------------
# Contract: /forge-goal Layer 2 — check-workflow-gates has PR-auth guard
# ---------------------------------------------------------------------------
start_test "Layer 2 — check-workflow-gates.{sh,ps1} have PR-auth guard with consistent key strings"

for f in "$REPO_ROOT/hooks/check-workflow-gates.sh" "$REPO_ROOT/hooks/check-workflow-gates.ps1"; do
    assert_file_exists "$f" "$f exists"
    assert_contains "$f" "PR creation authorized" "$(basename "$f") references PR auth line"
    assert_contains "$f" "GOAL_NONCE\|goalNonce" "$(basename "$f") uses nonce variable for active-session detection"
done

# P1.2: Bash guard must use non-empty GOAL_NONCE (not just block presence) as "active" definition
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.sh" 'if [ -n "$GOAL_NONCE"' "Bash guard checks non-empty GOAL_NONCE (not just block presence)"
# PS guard must also use non-empty goalNonce
assert_contains "$REPO_ROOT/hooks/check-workflow-gates.ps1" 'if ($goalNonce)' "PS guard checks non-empty goalNonce"

# ---------------------------------------------------------------------------
# Contract: /forge-goal Layer 2 — stuck-detection in check-state-updated
# ---------------------------------------------------------------------------
start_test "Layer 2 — check-state-updated.{sh,ps1} have stuck-detection code"

for f in "$REPO_ROOT/hooks/check-state-updated.sh" "$REPO_ROOT/hooks/check-state-updated.ps1"; do
    assert_file_exists "$f" "$f exists"
    assert_contains "$f" "FORGE_GOAL_STUCK_WARNING" "$(basename "$f") emits FORGE_GOAL_STUCK_WARNING"
    assert_contains "$f" "forge-goal-stuck-count" "$(basename "$f") references the counter file"
done

# ---------------------------------------------------------------------------
# Runtime parity contract: Bash vs PS guards for nonce-mismatch + empty-inactive
# (conditional on pwsh availability)
# ---------------------------------------------------------------------------
start_test "Layer 2 — PS guard runtime parity with Bash guard (nonce-mismatch + empty-inactive; skipped if pwsh absent)"

if command -v pwsh > /dev/null 2>&1; then
    # Test 1: nonce mismatch → both guards must exit 2 with "nonce mismatch" in stderr
    scratch=$(scratch_dir parity-nonce-mismatch)
    mkdir -p "$scratch/.claude/local"
    cat > "$scratch/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | correct-session-nonce |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## PR authorization

- [x] PR creation authorized — `2026-05-16T10:15:00Z` — nonce=`stale-different-nonce` — head=`abc123`
EOF

    (
        cd "$scratch"
        INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
        echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" > "$scratch/.bash_out" 2>&1
        echo $? > "$scratch/.bash_exit"
        echo "$INPUT" | pwsh -NoProfile -File "$REPO_ROOT/hooks/check-workflow-gates.ps1" > "$scratch/.ps_out" 2>&1
        echo $? > "$scratch/.ps_exit"
    )

    BASH_EXIT=$(cat "$scratch/.bash_exit")
    PS_EXIT=$(cat "$scratch/.ps_exit")
    assert_equals "$BASH_EXIT" "2" "Bash guard exits 2 on nonce mismatch"
    assert_equals "$PS_EXIT" "2" "PS guard exits 2 on nonce mismatch (parity)"
    assert_contains "$scratch/.bash_out" "nonce mismatch" "Bash guard mentions nonce mismatch"
    assert_contains "$scratch/.ps_out" "nonce mismatch" "PS guard mentions nonce mismatch (parity)"

    # Test 2: empty nonce row → both guards treat session as INACTIVE (exit 0)
    scratch2=$(scratch_dir parity-empty-nonce)
    mkdir -p "$scratch2/.claude/local"
    cat > "$scratch2/.claude/local/state.md" <<'EOF'
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            |       |
| workflow_command |       |
| issued_at        |       |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — Ship          |
| Next step | gh pr create      |

### Checklist

- [x] E2E verified via verify-e2e agent (Phase 5.4)
EOF

    (
        cd "$scratch2"
        INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
        echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" > "$scratch2/.bash_out" 2>&1
        echo $? > "$scratch2/.bash_exit"
        echo "$INPUT" | pwsh -NoProfile -File "$REPO_ROOT/hooks/check-workflow-gates.ps1" > "$scratch2/.ps_out" 2>&1
        echo $? > "$scratch2/.ps_exit"
    )

    BASH_EXIT2=$(cat "$scratch2/.bash_exit")
    PS_EXIT2=$(cat "$scratch2/.ps_exit")
    assert_equals "$BASH_EXIT2" "0" "Bash guard exits 0 on empty nonce (INACTIVE)"
    assert_equals "$PS_EXIT2" "0" "PS guard exits 0 on empty nonce (INACTIVE, parity)"

else
    pass_test "pwsh not available — PS runtime parity tests skipped (not a failure)"
fi

# ---------------------------------------------------------------------------
# Stale-duplicate auth line contract: guard uses LAST auth line
# ---------------------------------------------------------------------------
start_test "Layer 2 — Bash guard uses LAST PR authorization line when multiple present"

if command -v git > /dev/null 2>&1; then
    scratch=$(scratch_dir stale-dup-contract)
    mkdir -p "$scratch/.claude/local"
    (
        cd "$scratch"
        git init -q -b main >/dev/null 2>&1
        git config user.email "t@t"
        git config user.name "t"
        echo x > a; git add a; git commit -qm init >/dev/null 2>&1
        HEAD_SHA=$(git rev-parse HEAD)

        cat > .claude/local/state.md <<EOF
## /goal session

| Field            | Value |
| ---------------- | ----- |
| nonce            | current-nonce |
| workflow_command | /new-feature foo |
| issued_at        | 2026-05-16T10:00:00Z |

## PR authorization

- [x] PR creation authorized — \`2026-05-16T09:00:00Z\` — nonce=\`stale-nonce\` — head=\`stalehash\`
- [x] PR creation authorized — \`2026-05-16T10:15:00Z\` — nonce=\`current-nonce\` — head=\`$HEAD_SHA\`

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 6 — PR Ready      |
| Next step | Authorize PR      |

### Checklist

- [x] E2E verified via verify-e2e agent (Phase 5.4)
EOF

        INPUT='{"tool_name":"Bash","tool_input":{"command":"gh pr create --title test"}}'
        echo "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh" > .bash_out 2>&1
        echo $? > .bash_exit
    )

    BASH_EXIT=$(cat "$scratch/.bash_exit")
    assert_equals "$BASH_EXIT" "0" "Bash guard uses LAST auth line (matching) and ALLOWS (exit 0)"
else
    pass_test "git not available — stale-duplicate contract test skipped"
fi
```

- [ ] **Step 2: Write `docs/CHANGELOG.md` v5.29 entry**

Find the current top of CHANGELOG.md (should still be v5.28 from Layer 1 if Layer 1 was pre-merged). REPLACE the v5.28 entry with a unified v5.29 entry covering both layers (since Layer 1 was not actually shipped to main alone — we deferred to ship them together):

```markdown
## 5.29 — `/forge-goal` autonomous PRD-to-PR-ready workflow

**Why this exists:** Manual phase-by-phase shepherding through `/new-feature` and `/fix-bug` was the babysitting tax. `/forge-goal` lets the user type ONE command after PRD approval (or plan approval for bug fixes) and the agent autonomously drives plan → plan-review → implement → code-review → E2E → PR-ready, surfacing council for non-PR judgment moments and pausing only at PR creation.

**Capability:** After the gate checkpoint passes, the workflow command generates a session nonce, writes `## /goal session` to state.md, and prints a `/goal` command. The user types it; the agent enters autonomous mode. Stops at the PR-creation gate (AskUserQuestion modal + hook-enforced authorization signal in state.md) and at council-resolved decisions.

**Checkpoint placement:** `/new-feature` places the checkpoint at PRD-complete (after Phase 1, before Phase 2 Research). `/fix-bug` places it at Plan-Approved (after Phase 3.3 Plan Review Loop, before Phase 4 Execute) — because `/fix-bug` has no PRD phase. Simple fixes (1-2 files skipping Phase 3) are not eligible for the autonomous loop.

**New (Layer 1):**

- `hooks/build-evidence.{sh,ps1}` — read-only evidence emitter. Parses state.md, queries git/`gh pr view`/E2E reports, emits unified JSON between `FORGE_GOAL_EVIDENCE_BEGIN/END` markers. Computes `pr_ready`, deterministic `progress_fingerprint` (SHA256, CRLF-normalized, ordered, ASCII US delimiter).

**New (Layer 2):**

- `commands/new-feature.md` — PRD-Complete Checkpoint prints the `/goal` command; REPLACE semantics for `/goal session` and `## PR authorization`; PR-create AskUserQuestion modal documented; `all_gates_green` excluded from condition (post-PR checklist items are structurally unclearable while PR is open).
- `commands/fix-bug.md` — Plan-Approved Checkpoint at Phase 3→4 boundary; bug-fix-specific wording throughout; same REPLACE semantics and `all_gates_green` exclusion.
- `rules/workflow.md` — "Council During `/forge-goal`" trigger rule (route non-PR doubts to `/council`, leave reviewer-loop iterations as today).
- `state.template.md` — conventions for `## /goal session` (format documentation, no empty instance), `## PR authorization`, reviewer-iteration head-SHA labels, REPLACE semantics, and the non-empty-nonce "active" definition.

**Fixed (Layer 1):**

- `hooks/check-state-updated.{sh,ps1}` — invokes `build-evidence` BEFORE the `stop_hook_active` early-return. Previously the early-return suppressed evidence emission inside active `/goal` loops.

**Extended (Layer 2):**

- `hooks/check-workflow-gates.{sh,ps1}` — PR-create authorization guard. Blocks `gh pr create` during an active `/forge-goal` session unless `## PR authorization` matches the session nonce AND current HEAD SHA. "Active" = non-empty nonce. LAST-line defense for stale-duplicate state.md.
- `hooks/check-state-updated.{sh,ps1}` — stuck-detection soft warning. After 5 consecutive turns with identical `progress_fingerprint`, emits `FORGE_GOAL_STUCK_WARNING` to STDERR (informational, no abort).

**New tests:** `tests/template/test-build-evidence.sh` (35 assertions, Layer 1), 10 new test blocks in `test-hooks.sh` (6 PR-create guard + 4 stuck-detection), 8 new contracts in `test-contracts.sh` (Layer 1 + Layer 2, including fixture-based runtime parity tests for Bash vs PS guards).

**Architecture trace:** Native Anthropic `/goal` (CC 2.1.139+) drives the loop; forge supplies the evidence the verifier reads. State.md is the single source of truth (no sidecar state files). See `docs/plans/2026-05-14-forge-goal-design.md` and `docs/plans/2026-05-13-forge-goal-experiments.md`.
```

- [ ] **Step 3: Update `README.md`**

Find the version badge and the Version History table. Update both to v5.29:

```markdown
| 5.29 | 2026-05-16 | `/forge-goal` autonomous PRD-to-PR-ready workflow (Layers 1 + 2) |
```

- [ ] **Step 4: Run full test harness**

```bash
bash tests/template/run-all.sh 2>&1 | tail -20
```

Expected: all suites green.

- [ ] **Step 5: Dogfood test (manual, observational)**

Run a real `/forge-goal` end-to-end on a small forge feature:

1. From the forge root, start a fresh Claude Code session.
2. Type `/new-feature dogfood-test`.
3. Walk through the PRD phase. At PRD-complete, the agent should print the `/goal` command.
4. Copy + paste the `/goal` command.
5. Observe the agent advancing through phases without manual prompting.
6. Verify the stuck-detection counter file appears in `.claude/local/forge-goal-stuck-count` and changes each turn with progress.
7. When the PR-create gate fires (AskUserQuestion), answer YES.
8. Verify `gh pr create` actually runs (the hook should ALLOW it since authorization is properly recorded).
9. Verify the PR is open and the loop ends.

If the dogfood reveals real-world issues, capture them in a follow-up task or memory entry.

- [ ] **Step 6: Downstream smoke against `../mcpgateway`**

```bash
if [ -d ../mcpgateway ]; then
    cd ../mcpgateway
    bash ../claude-codex-forge/hooks/check-workflow-gates.sh < <(echo '{"tool_name":"Bash","tool_input":{"command":"gh pr create"}}') 2>&1 | head -10
    cd -
fi
```

Expected: the guard either fires correctly (if mcpgateway has a `/goal session` with a non-empty nonce — unlikely) or exits cleanly (empty/missing nonce → guard is a no-op).

- [ ] **Step 7: Final commit**

```bash
git add -f tests/template/test-contracts.sh docs/CHANGELOG.md README.md
git commit -m "feat: ship /forge-goal v1.0 — autonomous PRD-to-PR-ready workflow

Layer 1 (build-evidence.{sh,ps1} + Stop-hook integration) + Layer 2 (workflow
command checkpoints + council-during-/goal rule + state.md conventions +
PR-create authorization guard + stuck-detection soft warning) ship together as v5.29.

Net user value: after PRD approval (or plan approval for bug fixes), type ONE
/goal command and walk away; the agent drives plan → plan-review → implement →
code-review → E2E → PR-ready, surfacing council for non-PR doubts and pausing
only at PR creation. State.md is the single source of truth (no sidecar JSON state)."
```

---

## Self-Review

**1. All 6 Codex findings addressed?**

- **P1.1 (condition string unsatisfiable):** Fixed — `all_gates_green=true` removed from the `/goal` condition string in BOTH Task 5 (`/new-feature`) and Task 6 (`/fix-bug`). Condition relies on `pr_ready=true` + `pr_state.state="OPEN"` + `pr_authorization.authorized=true` + `session_nonce` match. Explicit rationale documented inline (post-PR items can't be checked while PR is open). Contract test asserts `all_gates_green=true` absent from both command files.

- **P1.2 (empty `/goal session` + inconsistent "active" definition):** Fixed two ways: (1) Task 1 removes the pre-populated empty `## /goal session` table from state.template.md — the section documents the format but no empty instance is present in the template. (2) Task 3 Bash guard and Task 4 PS guard both define "active" as non-empty `GOAL_NONCE` / `$goalNonce` after parsing. Added test 5 (empty-nonce-inactive case). State template documents the "active = non-empty nonce" definition. Contract test asserts both guards use the nonce variable and that template has no empty nonce row.

- **P1.3 (`/fix-bug` checkpoint placement):** Fixed — Task 6 uses "Plan-Approved Checkpoint" name and places it at Phase 3 → Phase 4 boundary (after plan-review-loop passes, before execution begins). Confirmed by reading `commands/fix-bug.md`: no PRD phase exists; phases are Pre-Flight → Phase 1 (Research) → Phase 2 (Debugging) → Phase 3 (Plan) → Phase 4 (Execute). Contract test asserts `Plan-Approved Checkpoint` present AND `PRD-Complete Checkpoint` absent in `fix-bug.md`.

- **P1.4 (REPLACE semantics):** Fixed throughout: Task 1 documents REPLACE semantics + singleton enforcement in state.template.md. Task 5 (`/new-feature`) and Task 6 (`/fix-bug`) both specify explicit REPLACE instructions for `/goal session` (clearing stale session on kickoff) and `## PR authorization` (replacing on YES, not appending). Last-line-wins defensive logic added to Task 3 (Bash) and Task 4 (PS). State template documents the "stale auth defense" (last line used for multiple lines). Contract tests assert REPLACE appears in both command files.

- **P2.1 (contracts too weak):** Fixed — Task 10 Step 1 now includes: nonce-mismatch fixture test, empty-inactive fixture test, stale-duplicate-auth test, conditional pwsh runtime parity (Bash vs PS, same scenarios), and stale-dup-last-line contract. These are fixture-based runtime tests, not grep patterns.

- **P2.2 (US-008 stuck-detection deferred):** Implemented as Task 8. Adds stuck-detection to `check-state-updated.{sh,ps1}` via `FORGE_GOAL_FINGERPRINT` env var + `.claude/local/forge-goal-stuck-count` counter file. 5-turn threshold. Warning is informational (exit 0). Four test cases. Task 9 (formerly 7) renumbered accordingly. Final task is Task 10 (formerly 8).

**2. Revision history table updated to v1.1?** Yes — revision history table at top of document.

**3. Task count reflects stuck-detection?** Yes — 10 tasks total: Tasks 1–7 (original), Task 8 (new: stuck-detection), Task 9 (docs, formerly Task 7), Task 10 (release, formerly Task 8).

**4. New contract tests add genuine runtime fixtures?** Yes — Task 10 contracts include fixture-based runtime tests: real state.md files written to scratch dirs, real hook invocations, exit code + stderr content assertions. Not just grep patterns.

**5. `/fix-bug` checkpoint correctly named and placed?** Yes — "Plan-Approved Checkpoint" at Phase 3 → Phase 4 boundary, with explicit scope note ("complex fixes only"), confirmed against actual `fix-bug.md` structure.

**6. `/new-feature` checkpoint placement verified?** Yes — confirmed `new-feature.md` has Phase 1 (Requirements/PRD) → Phase 2 (Research) structure. PRD-Complete Checkpoint placed after Phase 1 and before Phase 2. Naming stays "PRD-Complete Checkpoint."

**7. REPLACE semantics concrete?** Yes — specific Edit tool usage described ("find the existing heading + block, replace entire block"), singleton enforcement documented, stale-clearing on kickoff, re-authorization replacement (not append) all explicit.

---

## Spec Coverage

Every Layer 2 PRD user story (US-001 through US-011) maps to a task:

- US-001 (Interactive PRD Phase): handled by the existing `/prd:discuss` skill, unchanged. Layer 2 picks up at PRD-complete (or plan-approved) and onward.
- US-002 (Forge prints /goal): Tasks 5, 6.
- US-003 (Autonomous loop execution): Tasks 5, 6 (the printed `/goal` command's condition string defines the loop).
- US-004 (Council substitutes human): Task 2 (rule), Tasks 5, 6 (workflow commands reference the rule).
- US-005 (PR-create gate with summary): Tasks 5, 6 (AskUserQuestion modal text).
- US-006 ("PR-Ready" definition): Tasks 5, 6 (the condition string enumerates the conditions — `pr_ready`, `pr_state.state="OPEN"`, `pr_authorization.authorized`, etc.; `all_gates_green` explicitly excluded as unsatisfiable).
- US-007 (Budget exhaustion): native `/goal` handles this; the printed condition doesn't fight it.
- US-008 (Stuck-detection soft warning): Task 8.
- US-009 (Observability during run): native `/goal` behavior — works out of the box.
- US-010 (Resume after interruption): native `/goal` behavior — works out of the box.
- US-011 (Downstream auto-availability): Layer 1's setup.sh wiring already copies build-evidence; Task 9/10 ships Layer 2 templates that downstream installs pick up via setup.sh's existing copy logic for `commands/*`, `rules/*`, `hooks/*`, `state.template.md`. No new wiring needed.

---

## Notes for the Executor

- **Branch:** stay on `research/forge-goal-experiments` (Layer 1's 20 commits + Layer 2's new commits, single coherent ship).
- **Test conventions:** Layer 1's `tests/template/lib.sh` API is unchanged. The new Layer 2 tests follow the same `assert_equals` / file-path `assert_contains` / `scratch_dir` patterns.
- **Scope skepticism:** Pablo's late-Layer-1 check ("is this overkill?") was right to flag. Layer 2's value-prop is much clearer than Layer 1's standalone, but each task should still pass the test: "Does this task deliver user-visible behavior, or is it infrastructure-for-Layer-3?" If a task feels too foundational, push back.
- **`/quick-fix` exclusion:** Layer 2 does NOT modify `/quick-fix`. Trivial changes (< 3 files) keep the manual workflow.
- **Dogfood expectation:** Task 10 Step 5 is a manual run-through. Plan time for ~30-60 minutes of real-world execution.
- **FORGE_GOAL_FINGERPRINT integration:** Task 8's stuck-detection expects `FORGE_GOAL_FINGERPRINT` as an env var. Read `check-state-updated.sh` carefully during Task 8 Step 3 to find the exact point where `build-evidence.sh` output is available and wire the env var correctly. If the Stop hook calls build-evidence via stdout capture, extract the fingerprint field from the JSON before invoking state-updated.
