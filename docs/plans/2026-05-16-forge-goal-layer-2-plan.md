# forge-goal Layer 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Layer 2 of `/forge-goal` — the autonomous-loop capability that consumes Layer 1's evidence JSON. After PRD approval, the user types ONE `/goal` command and the agent autonomously drives plan → plan-review → implement → code-review → E2E → PR-ready, surfacing council for non-PR judgment moments and pausing only at PR creation.

**Architecture:** Workflow commands (`/new-feature`, `/fix-bug`) gain a "PRD-complete checkpoint" that generates a session nonce, writes `## /goal session` to state.md, and prints a precise `/goal` command for the user to copy-paste. `rules/workflow.md` adds a council-during-`/goal` trigger rule. `check-workflow-gates.sh`/`.ps1` adds an authorization guard on `gh pr create`. State.template.md documents the new sections.

**Tech Stack:** Bash + PowerShell hooks, Markdown workflow commands (slash-command bodies are prompts to Claude), forge's existing `tests/template/lib.sh` test harness, the Layer 1 `build-evidence.{sh,ps1}` consumed implicitly through transcript evidence.

**Source artifacts:**
- Design spec: `docs/plans/2026-05-14-forge-goal-design.md`
- PRD: `docs/prds/forge-goal.md` (US-002 through US-011)
- Layer 1 plan: `docs/plans/2026-05-14-forge-goal-layer-1-plan.md` (shipped on branch `research/forge-goal-experiments`)
- Experiment record: `docs/plans/2026-05-13-forge-goal-experiments.md`

**Branch strategy:** Build Layer 2 ON TOP of `research/forge-goal-experiments` (which already has Layer 1's 20 commits). When both layers are done, ship as a single PR / `/forge-goal v1.0`.

---

## File Structure

**Modified files:**
- `state.template.md` — add conventions for `## /goal session`, `## PR authorization`, reviewer-iteration head-SHA labels (Task 1)
- `rules/workflow.md` — add council-during-`/goal` trigger rule (Task 2)
- `hooks/check-workflow-gates.sh` — add PR-create authorization guard (Task 3)
- `hooks/check-workflow-gates.ps1` — PowerShell parity for the guard (Task 4)
- `commands/new-feature.md` — add PRD-complete checkpoint (nonce + state.md write + `/goal` print) + PR-create gate AskUserQuestion modal text (Task 5)
- `commands/fix-bug.md` — same pattern as Task 5 (Task 6)
- `README.md` — version badge + Version History (Task 8)
- `docs/CHANGELOG.md` — v5.29 entry covering Layer 1 + Layer 2 (Task 8)
- `docs/explanation/workflow.md` — reference `/forge-goal` autonomous flow (Task 7)
- `docs/guides/customize-project.md` — reference state.md new sections (Task 7)
- `docs/reference/permissions.md` — note the new gh-pr-create authorization gate (Task 7)
- `tests/template/test-contracts.sh` — extend with Layer 2 contracts (Task 8)
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
2. Cross-file contract tests in Task 8 (e.g., "commands/new-feature.md mentions PRD-complete checkpoint")
3. Dogfood — Task 8 includes a manual run-through

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

Add AFTER the existing `## Workflow` section (before `## State`):

```markdown
## /goal session

(populated by `/new-feature` or `/fix-bug` at the PRD-complete checkpoint when `/forge-goal` is active)

| Field            | Value |
| ---------------- | ----- |
| nonce            |       |
| workflow_command |       |
| issued_at        |       |
```

- [ ] **Step 3: Add the `## PR authorization` section description**

Add AFTER `## /goal session` (before `## State`):

```markdown
## PR authorization

(populated when the user authorizes `gh pr create` via the PR-create gate's AskUserQuestion modal during a `/forge-goal`-driven run)

- (single line appended on user YES, format: `- [x] PR creation authorized — \`<timestamp>\` — nonce=\`<nonce>\` — head=\`<head_sha>\``)
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
2. On YES, agent appends to `## PR authorization`:
   - `- [x] PR creation authorized — \`<ISO-8601 timestamp>\` — nonce=\`<session nonce>\` — head=\`<current HEAD SHA>\``
3. The PR-create PreToolUse guard blocks `gh pr create` unless this line is present with a matching nonce AND head SHA.
```

- [ ] **Step 5: Commit**

```bash
git add -f state.template.md
git commit -m "feat(template): state.md conventions for /goal session + PR authorization + reviewer-iteration head-SHA labels"
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

When a `/forge-goal`-driven `/goal` is active (`## /goal session` is populated in `.claude/local/state.md`), the agent's pause-for-user discipline changes:

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
# state.md has /goal session populated (forge-goal active) but NO PR authorization line.
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

Fourth test — `/forge-goal` is NOT active (no `## /goal session`), guard does NOT fire (allows the existing checklist-only behavior to remain in charge):

```bash
start_test "check-workflow-gates skips PR-auth guard when no ## /goal session (legacy workflow path)"

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

- [ ] **Step 3: Run tests, verify FAIL**

```bash
bash tests/template/test-hooks.sh 2>&1 | tail -20
```

Expected: 4 new test blocks failing (the guard doesn't exist yet in check-workflow-gates.sh).

- [ ] **Step 4: Implement the guard in `hooks/check-workflow-gates.sh`**

The guard fires ONLY when:
1. The Bash command being attempted matches `^\s*gh\s+pr\s+create\b`
2. `## /goal session` is present in `.claude/local/state.md` (i.e., `/forge-goal` is active)

When the guard fires, it checks:
- Is there a `## PR authorization` line with `- [x]`?
- Does its `nonce=<value>` match the `## /goal session` nonce?
- Does its `head=<sha>` match `git rev-parse HEAD`?

If any check fails: exit 2 with a clear error message. If all pass: fall through to the EXISTING checklist guard (which continues to apply unchanged).

Locate the existing block that matches `gh pr create` and ADD the new check IMMEDIATELY AFTER the existing pattern-match (before the existing checklist-completion logic). The patch in `hooks/check-workflow-gates.sh` (insert after the gh-pr-create command detection):

```bash
# ---------------------------------------------------------------------------
# Layer 2 — /forge-goal PR-create authorization guard
#
# When /forge-goal is active (## /goal session populated in state.md), gh pr
# create requires an explicit ## PR authorization line with matching nonce +
# current HEAD SHA. The line is written by the workflow agent after the user
# answers YES to the AskUserQuestion PR-create modal.
#
# When /forge-goal is NOT active (no ## /goal session), this guard is a no-op
# and the existing checklist-completion guard below runs unchanged.
# ---------------------------------------------------------------------------
if echo "$COMMAND" | grep -qE '^[[:space:]]*gh[[:space:]]+pr[[:space:]]+create\b'; then
    STATE_MD=".claude/local/state.md"
    if [ -f "$STATE_MD" ]; then
        # CRLF normalize before awk anchors (matches Layer 1 parser pattern)
        GOAL_BLOCK=$(tr -d '\r' < "$STATE_MD" \
                    | awk '/^## \/goal session$/{flag=1;next} flag && /^## /{flag=0} flag')
        if [ -n "$GOAL_BLOCK" ]; then
            # /forge-goal is active; enforce PR-auth requirements
            GOAL_NONCE=$(echo "$GOAL_BLOCK" \
                        | grep -E '\|[[:space:]]*nonce[[:space:]]*\|' \
                        | head -1 | awk -F'|' '{print $3}' | xargs)

            HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")

            PR_AUTH_LINE=$(tr -d '\r' < "$STATE_MD" \
                          | grep -E '^-[[:space:]]*\[x\][[:space:]]+PR creation authorized' \
                          | head -1)

            if [ -z "$PR_AUTH_LINE" ]; then
                echo "WORKFLOW GATE: gh pr create blocked — no ## PR authorization line in state.md." >&2
                echo "" >&2
                echo "A /forge-goal-driven workflow is active. PR creation requires user authorization." >&2
                echo "The agent must call AskUserQuestion and, on user YES, append:" >&2
                echo "  - [x] PR creation authorized — \`<ts>\` — nonce=\`<n>\` — head=\`<sha>\`" >&2
                echo "to the ## PR authorization section of .claude/local/state.md before retrying." >&2
                exit 2
            fi

            # Extract nonce and head from the auth line. Pattern:
            # - [x] PR creation authorized — `<ts>` — nonce=`<nonce>` — head=`<sha>`
            AUTH_NONCE=$(echo "$PR_AUTH_LINE" \
                        | sed -E 's/.*nonce=`([^`]+)`.*/\1/')
            AUTH_HEAD=$(echo "$PR_AUTH_LINE" \
                        | sed -E 's/.*head=`([^`]+)`.*/\1/')

            if [ "$AUTH_NONCE" != "$GOAL_NONCE" ]; then
                echo "WORKFLOW GATE: gh pr create blocked — PR authorization nonce mismatch." >&2
                echo "Expected nonce: $GOAL_NONCE" >&2
                echo "Authorization line nonce: $AUTH_NONCE" >&2
                echo "Stale authorization from a previous /forge-goal session. User must re-authorize." >&2
                exit 2
            fi

            if [ -z "$HEAD_SHA" ] || [ "$AUTH_HEAD" != "$HEAD_SHA" ]; then
                echo "WORKFLOW GATE: gh pr create blocked — PR authorization HEAD mismatch." >&2
                echo "Current HEAD: $HEAD_SHA" >&2
                echo "Authorization line head: $AUTH_HEAD" >&2
                echo "Commits added since authorization; user must re-authorize at the new HEAD." >&2
                exit 2
            fi

            # All checks passed; fall through to the existing checklist guard
        fi
    fi
fi
```

Place this block IMMEDIATELY AFTER the existing block that detects `gh pr create` for the current checklist gate. The exact insertion point depends on the current structure of `check-workflow-gates.sh` — read it first and pick the right spot. Match indentation and comment style of the existing file.

- [ ] **Step 5: Run tests, verify PASS**

```bash
bash tests/template/test-hooks.sh 2>&1 | tail -15
```

Expected: the 4 new test blocks now pass. Total test-hooks.sh assertion count increases by 4 (1 per test block).

- [ ] **Step 6: Commit**

```bash
git add -f hooks/check-workflow-gates.sh tests/template/test-hooks.sh
git commit -m "feat(hooks): PR-create authorization guard for /forge-goal active sessions

Blocks gh pr create when:
- /forge-goal is active (## /goal session present), AND
- ## PR authorization is missing, OR nonce-mismatched, OR head-SHA-stale.

The existing checklist-completion guard continues to fire independently
when /forge-goal is NOT active. CRLF-normalized parsing matches Layer 1
conventions. Bash 3.2 compatible (no declare -A)."
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

Port the Bash logic to PowerShell. The PS code mirrors Task 3's logic. PS 5.1 constraints from Layer 1: no `??`, no `2>&1 | Out-Null`, no `pwsh` spawn, prefer `-replace` for regex.

```powershell
# ---------------------------------------------------------------------------
# Layer 2 — /forge-goal PR-create authorization guard (PS parity for .sh)
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
                $goalNonce = $matches[1]
            }
        }

        if ($goalNonce) {
            # /forge-goal is active; enforce PR-auth requirements
            $headSha = ""
            try { $headSha = ((git rev-parse HEAD 2>$null) -join "").Trim() } catch {}

            $prAuthLine = ""
            foreach ($line in $lines) {
                if ($line -match '^-\s*\[x\]\s+PR creation authorized') {
                    $prAuthLine = $line
                    break
                }
            }

            if (-not $prAuthLine) {
                [Console]::Error.WriteLine("WORKFLOW GATE: gh pr create blocked — no ## PR authorization line in state.md.")
                [Console]::Error.WriteLine("")
                [Console]::Error.WriteLine("A /forge-goal-driven workflow is active. PR creation requires user authorization.")
                [Console]::Error.WriteLine("The agent must call AskUserQuestion and, on user YES, append:")
                [Console]::Error.WriteLine("  - [x] PR creation authorized — ``<ts>`` — nonce=``<n>`` — head=``<sha>``")
                [Console]::Error.WriteLine("to the ## PR authorization section of .claude/local/state.md before retrying.")
                exit 2
            }

            $authNonce = ""
            $authHead = ""
            if ($prAuthLine -match 'nonce=`([^`]+)`') { $authNonce = $matches[1] }
            if ($prAuthLine -match 'head=`([^`]+)`')  { $authHead = $matches[1] }

            if ($authNonce -ne $goalNonce) {
                [Console]::Error.WriteLine("WORKFLOW GATE: gh pr create blocked — PR authorization nonce mismatch.")
                [Console]::Error.WriteLine("Expected nonce: $goalNonce")
                [Console]::Error.WriteLine("Authorization line nonce: $authNonce")
                [Console]::Error.WriteLine("Stale authorization from a previous /forge-goal session. User must re-authorize.")
                exit 2
            }

            if (-not $headSha -or $authHead -ne $headSha) {
                [Console]::Error.WriteLine("WORKFLOW GATE: gh pr create blocked — PR authorization HEAD mismatch.")
                [Console]::Error.WriteLine("Current HEAD: $headSha")
                [Console]::Error.WriteLine("Authorization line head: $authHead")
                [Console]::Error.WriteLine("Commits added since authorization; user must re-authorize at the new HEAD.")
                exit 2
            }

            # All checks passed; fall through to the existing checklist guard
        }
    }
}
```

The exact variable names (`$command`, etc.) and insertion point depend on the existing `check-workflow-gates.ps1` structure. Read first, adapt the variable references to match.

- [ ] **Step 3: Verify parity via `test-contracts.sh` cross-file content checks** (extended in Task 8)

For now: confirm `bash tests/template/run-all.sh 2>&1 | tail -10` is still green. The PS implementation isn't directly tested in this task's TDD cycle (no PowerShell test harness); Task 8's contracts include a cross-file check that the Bash and PS guards mention the same key error strings.

- [ ] **Step 4: Commit**

```bash
git add -f hooks/check-workflow-gates.ps1
git commit -m "feat(hooks): PowerShell parity for /forge-goal PR-create authorization guard"
```

---

### Task 5: Update `commands/new-feature.md` with PRD-complete checkpoint + PR-create gate

**Files:**
- Modify: `commands/new-feature.md` (the workflow command markdown that gets installed to `.claude/commands/new-feature.md`)

- [ ] **Step 1: Read current `commands/new-feature.md` to find phase markers**

```bash
cat commands/new-feature.md | head -100
grep -n "Phase\|PRD\|Pre-Flight" commands/new-feature.md
```

Locate the PRD-complete checkpoint (after the PRD-discuss / PRD-create phase, before the plan phase begins).

- [ ] **Step 2: Add the PRD-complete `/goal`-printing checkpoint**

Add a NEW section to `commands/new-feature.md` titled `## PRD-Complete Checkpoint — Print /goal for autonomous loop`. This section runs AFTER PRD is complete and BEFORE plan creation begins. Content:

```markdown
## PRD-Complete Checkpoint — Print `/goal` for Autonomous Loop

When the PRD phase completes (PRD file exists in `docs/prds/<feature>.md` and the user is ready to advance), if you (the agent) judge `/forge-goal` would help here (the feature is substantial enough to warrant autonomous execution), you may offer the user the option to kick off the autonomous loop.

### Steps

1. **Generate a session nonce.** Run:
   ```bash
   uuidgen | tr 'A-Z' 'a-z'
   ```
   Capture the output (e.g. `5f1a2b3c-9d8e-4f6a-b7c8-1e2d3f4a5b6c`).

2. **Write the `## /goal session` section to `.claude/local/state.md`.** Use the Edit or Write tool to add this section AFTER `## Workflow` and BEFORE `## State`:
   ```markdown
   ## /goal session

   | Field            | Value                                  |
   | ---------------- | -------------------------------------- |
   | nonce            | <UUID-from-step-1>                     |
   | workflow_command | /new-feature <name>                    |
   | issued_at        | <ISO-8601-UTC-timestamp>               |
   ```
   Use `date -u +%Y-%m-%dT%H:%M:%SZ` for the timestamp.

3. **Print the `/goal` command for the user to copy-paste.** Format the message EXACTLY:

   ```
   ────────────────────────────────────────
    PRD approved. Type this to begin the autonomous loop:
   ────────────────────────────────────────

   /goal Continue the active Forge workflow from the current .claude/local/state.md checkpoint through plan, plan review, implementation, code review, simplify, verification, E2E, commit, push, PR authorization, and PR creation. Stop after the PR is open. Do not merge. If a non-PR decision would normally pause for human input, invoke /council and apply the chairman verdict. Completion condition: clear only when the latest FORGE_GOAL_EVIDENCE JSON printed after this /goal message has session_nonce="<NONCE>" AND pr_ready=true AND all_gates_green=true AND pr_state.state="OPEN" AND reviewer_gate.clean_same_iteration=true AND e2e_report.fresh_for_head=true AND pr_authorization.authorized=true. Ignore older evidence and evidence with any other session_nonce. CI status is not required.

   ────────────────────────────────────────
    Or type "no" to continue manually phase-by-phase.
   ```

   Substitute `<NONCE>` with the value from step 1.

4. **If the user types the `/goal` command**, you (the agent) enter autonomous mode per `rules/workflow.md` "Council During `/forge-goal` Autonomous Run" — pause for the PR-creation gate only, route all other doubts to `/council`.

5. **If the user declines** (types "no" or anything other than the `/goal` command), continue the standard `/new-feature` workflow phase-by-phase.

### Critical reminders during the autonomous loop

- **DO NOT** call `gh pr create` until you have run `AskUserQuestion` asking the user to authorize, and they answered YES, and you have appended the `## PR authorization` line to state.md with matching nonce + current HEAD SHA.
- **DO NOT** call `/goal clear` after success — `/goal` auto-clears when the verifier confirms the condition.
- **DO** track each code-review iteration by appending `- [x] Code review iteration <N> — codex clean — head=\`<sha>\`` AND `- [x] Code review iteration <N> — pr-toolkit clean — head=\`<sha>\`` to `### Checklist` (state.md). The `reviewer_gate.clean_same_iteration` evidence only fires when BOTH appear for the same iteration AND at the current HEAD.
- **DO** invoke `/council` whenever you would otherwise pause for the user (except PR creation). Apply the chairman's verdict; do not second-guess it.

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

On YES, append to `.claude/local/state.md` `## PR authorization` section:

```
- [x] PR creation authorized — `<ISO-8601-UTC-timestamp>` — nonce=`<session nonce>` — head=`<current HEAD SHA>`
```

Then run `gh pr create`. The PreToolUse guard (`check-workflow-gates.{sh,ps1}`) will verify the authorization line matches before allowing the command.

On NO, append a blocker line to `## Blockers` in state.md and STOP the autonomous loop.
```

- [ ] **Step 3: Commit**

```bash
git add -f commands/new-feature.md
git commit -m "feat(commands): /new-feature PRD-complete checkpoint prints /goal for autonomous loop

Adds the PRD-complete checkpoint that generates a session nonce, writes
## /goal session to state.md, and prints the /goal command for the user
to copy-paste. Also documents the PR-create AskUserQuestion modal text
and the reviewer-iteration head-SHA checklist convention."
```

---

### Task 6: Update `commands/fix-bug.md` with same PRD-complete checkpoint pattern

**Files:**
- Modify: `commands/fix-bug.md`

- [ ] **Step 1: Read current `commands/fix-bug.md` structure**

```bash
cat commands/fix-bug.md | head -100
grep -n "Phase\|PRD\|Pre-Flight" commands/fix-bug.md
```

- [ ] **Step 2: Add the same PRD-complete checkpoint section as Task 5**

Copy the entire `## PRD-Complete Checkpoint — Print /goal for Autonomous Loop` section verbatim from `commands/new-feature.md` into `commands/fix-bug.md`. ONE change: in the `/goal` condition string, replace `/new-feature <name>` with `/fix-bug <name>`.

Also, in the "Critical reminders" subsection, customize wording where appropriate (e.g., "bug fix" instead of "feature"); but the operational rules are identical.

Place the section at the same logical position — after PRD phase completes, before plan creation begins.

- [ ] **Step 3: Verify cross-file consistency**

```bash
diff <(awk '/^## PRD-Complete Checkpoint/,/^## /' commands/new-feature.md | head -100) \
     <(awk '/^## PRD-Complete Checkpoint/,/^## /' commands/fix-bug.md | head -100)
```

Expected: minor diffs (workflow_command value, "feature" vs "bug fix" wording). Structure should be identical.

- [ ] **Step 4: Commit**

```bash
git add -f commands/fix-bug.md
git commit -m "feat(commands): /fix-bug PRD-complete checkpoint prints /goal for autonomous loop"
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

When the workflow's PRD phase completes, the workflow command (`/new-feature` or `/fix-bug`) offers an autonomous-loop kickoff. The user copies the printed `/goal <condition>` command into their next message; the agent then drives plan → plan-review → implement → code-review-loop → E2E → PR-ready without further phase-by-phase prompting.

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

Decline the autonomous loop offer at the PRD-complete checkpoint and the workflow falls back to the standard phase-by-phase flow.
```

- [ ] **Step 3: Update `docs/guides/customize-project.md`**

Find the existing description of state.md sections. Add a paragraph noting the new sections:

```markdown
When a `/forge-goal`-driven workflow is active, additional sections appear in `.claude/local/state.md`:

- `## /goal session` — table with the autonomous-loop session nonce, originating workflow command, and issued-at timestamp.
- `## PR authorization` — single checkbox line appended when the user authorizes PR creation via the `AskUserQuestion` modal at the PR-create gate. Contains the timestamp, session nonce, and HEAD SHA at the moment of authorization.
- `### Checklist` rows for reviewer iterations include `head=\`<sha>\`` so the evidence script can verify both reviewers cleared at the same iteration AND at the same HEAD.
```

- [ ] **Step 4: Update `docs/reference/permissions.md`**

Find the existing `gh pr create` row in the permissions table. Update it (or add a footnote):

```markdown
| **gh pr create**                           | Yes     | Creating PR requires approval. During a `/forge-goal`-driven autonomous loop, also requires `## PR authorization` in state.md with matching nonce + HEAD SHA (set by the agent after the user answers YES to the PR-create AskUserQuestion modal). |
```

- [ ] **Step 5: Commit**

```bash
git add -f docs/explanation/workflow.md docs/guides/customize-project.md docs/reference/permissions.md
git commit -m "docs: reference /forge-goal autonomous loop + new state.md sections"
```

---

### Task 8: Layer 1+2 Release — CHANGELOG, README, cross-file contracts, dogfood

**Files:**
- Modify: `tests/template/test-contracts.sh` — add Layer 2 contracts
- Modify: `docs/CHANGELOG.md` — v5.29 entry (covers Layer 1 + Layer 2 combined)
- Modify: `README.md` — version badge + Version History row

- [ ] **Step 1: Extend `tests/template/test-contracts.sh`**

Add the following Layer 2 contracts (in addition to the existing Layer 1 contract from Task 10 of Layer 1):

```bash
# ---------------------------------------------------------------------------
# Contract: /forge-goal Layer 2 — workflow commands print the /goal command
# ---------------------------------------------------------------------------
start_test "Layer 2 — workflow commands have PRD-complete /goal-print checkpoint"

for f in "$REPO_ROOT/commands/new-feature.md" "$REPO_ROOT/commands/fix-bug.md"; do
    assert_file_exists "$f" "workflow command exists: $f"
    assert_contains "$f" "PRD-Complete Checkpoint" "$(basename "$f") has PRD-complete checkpoint section"
    assert_contains "$f" "/goal" "$(basename "$f") references /goal command"
    assert_contains "$f" "FORGE_GOAL_EVIDENCE" "$(basename "$f") references Layer 1 evidence markers in condition"
    assert_contains "$f" "session_nonce" "$(basename "$f") references session_nonce in condition"
    assert_contains "$f" "AskUserQuestion" "$(basename "$f") references AskUserQuestion at PR-create gate"
done

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
# Contract: /forge-goal Layer 2 — state.template.md has new sections
# ---------------------------------------------------------------------------
start_test "Layer 2 — state.template.md documents /goal session + PR authorization conventions"

ST_TPL="$REPO_ROOT/state.template.md"
assert_file_exists "$ST_TPL" "state.template.md exists"
assert_contains "$ST_TPL" "## /goal session" "/goal session section documented"
assert_contains "$ST_TPL" "## PR authorization" "PR authorization section documented"
assert_contains "$ST_TPL" "Code review iteration" "reviewer-iteration head-SHA convention documented"

# ---------------------------------------------------------------------------
# Contract: /forge-goal Layer 2 — check-workflow-gates has PR-auth guard
# ---------------------------------------------------------------------------
start_test "Layer 2 — check-workflow-gates.{sh,ps1} have PR-auth guard"

for f in "$REPO_ROOT/hooks/check-workflow-gates.sh" "$REPO_ROOT/hooks/check-workflow-gates.ps1"; do
    assert_file_exists "$f" "$f exists"
    assert_contains "$f" "PR creation authorized" "$(basename "$f") references PR auth line"
    assert_contains "$f" "/goal session" "$(basename "$f") gates on /goal session presence"
done
```

- [ ] **Step 2: Write `docs/CHANGELOG.md` v5.29 entry**

Find the current top of CHANGELOG.md (should still be v5.28 from Layer 1 if Layer 1 was pre-merged). REPLACE the v5.28 entry with a unified v5.29 entry covering both layers (since Layer 1 was not actually shipped to main alone — we deferred to ship them together):

```markdown
## 5.29 — `/forge-goal` autonomous PRD-to-PR-ready workflow

**Why this exists:** Manual phase-by-phase shepherding through `/new-feature` and `/fix-bug` was the babysitting tax. `/forge-goal` lets the user type ONE command after PRD approval and the agent autonomously drives plan → plan-review → implement → code-review → E2E → PR-ready, surfacing council for non-PR judgment moments and pausing only at PR creation.

**Capability:** After PRD completes, the workflow command (`/new-feature` or `/fix-bug`) generates a session nonce, writes `## /goal session` to state.md, and prints a `/goal` command. The user types it; the agent enters autonomous mode. Stops at the PR-creation gate (AskUserQuestion modal + hook-enforced authorization signal in state.md) and at council-resolved decisions.

**New:**

- `hooks/build-evidence.{sh,ps1}` — read-only evidence emitter. Parses state.md, queries git/`gh pr view`/E2E reports, emits unified JSON between `FORGE_GOAL_EVIDENCE_BEGIN/END` markers. Computes `pr_ready`, `all_gates_green`, deterministic `progress_fingerprint` (SHA256, CRLF-normalized, ordered, ASCII US delimiter).
- `commands/new-feature.md` + `commands/fix-bug.md` — PRD-complete checkpoint prints the `/goal` command; PR-create gate AskUserQuestion modal documented.
- `rules/workflow.md` — "Council During `/forge-goal`" trigger rule (route non-PR doubts to `/council`, leave reviewer-loop iterations as today).
- `state.template.md` — conventions for `## /goal session`, `## PR authorization`, reviewer-iteration head-SHA labels.

**Fixed:**

- `hooks/check-state-updated.{sh,ps1}` — invokes `build-evidence` BEFORE the `stop_hook_active` early-return. Previously the early-return suppressed evidence emission inside active `/goal` loops, making the verifier blind.

**Extended:**

- `hooks/check-workflow-gates.{sh,ps1}` — adds PR-create authorization guard. Blocks `gh pr create` during a `/forge-goal` session unless `## PR authorization` matches the session nonce AND current HEAD SHA.

**New tests:** `tests/template/test-build-evidence.sh` (35 assertions), four new test blocks in `test-hooks.sh` for the PR-create guard, four new contracts in `test-contracts.sh` (Layer 1 producer/consumer/schema + Layer 2 workflow-command/rule/state-template/PR-guard).

**Architecture trace:** Native Anthropic `/goal` (CC 2.1.139+) drives the loop; forge supplies the evidence the verifier reads. State.md is the single source of truth (no sidecar state files). See `docs/plans/2026-05-14-forge-goal-design.md` for the design rationale and `docs/plans/2026-05-13-forge-goal-experiments.md` for the experiments that established the mechanic.
```

- [ ] **Step 3: Update `README.md`**

Find the version badge and the Version History table. Update both to v5.29 with description matching the CHANGELOG headline:

```markdown
| 5.29 | 2026-05-16 | `/forge-goal` autonomous PRD-to-PR-ready workflow (Layers 1 + 2) |
```

- [ ] **Step 4: Run full test harness**

```bash
bash tests/template/run-all.sh 2>&1 | tail -15
```

Expected: all suites green. The new contracts in `test-contracts.sh` pass (~12 new assertions). Build-evidence test count unchanged from Layer 1 (35). test-hooks.sh count increases by 4 (the PR-create guard tests from Task 3).

- [ ] **Step 5: Dogfood test (manual, observational)**

Run a real `/forge-goal` end-to-end on a small forge feature. Suggested target: a tiny rule clarification or comment addition. Steps:

1. From the forge root, start a fresh Claude Code session.
2. Type `/new-feature dogfood-test` (or use the existing `research/forge-goal-experiments` branch since we're already there — but a fresh feature branch is cleaner).
3. Walk through the PRD phase. At PRD-complete, the agent should print the `/goal` command.
4. Copy + paste the `/goal` command.
5. Observe the agent advancing through phases without manual prompting.
6. When the PR-create gate fires (AskUserQuestion), answer YES.
7. Verify `gh pr create` actually runs (or document what blocks it — the hook should ALLOW it since authorization is properly recorded).
8. Verify the PR is open and the loop ends.

If the dogfood reveals real-world issues, capture them in a follow-up task or memory entry. If clean, mark Layer 2 as shipped.

- [ ] **Step 6: Downstream smoke against `../mcpgateway`** (matching Layer 1's pattern)

```bash
if [ -d ../mcpgateway ]; then
    cd ../mcpgateway
    bash ../claude-codex-forge/hooks/check-workflow-gates.sh < <(echo '{"tool_name":"Bash","tool_input":{"command":"gh pr create"}}') 2>&1 | head -10
    cd -
fi
```

Expected: the guard either fires correctly (if mcpgateway has a `/goal session` for some reason — unlikely) or exits cleanly (no `/goal session` → guard is a no-op, hands off to existing checklist guard which then evaluates per mcpgateway's state).

- [ ] **Step 7: Final commit**

```bash
git add -f tests/template/test-contracts.sh docs/CHANGELOG.md README.md
git commit -m "feat: ship /forge-goal v1.0 — autonomous PRD-to-PR-ready workflow

Layer 1 (build-evidence.{sh,ps1} + Stop-hook integration) + Layer 2 (workflow
command PRD-complete checkpoints + council-during-/goal rule + state.md
conventions + PR-create authorization guard) ship together as v5.29.

Net user value: after PRD approval, type ONE /goal command and walk away;
the agent drives plan → plan-review → implement → code-review → E2E →
PR-ready, surfacing council for non-PR doubts and pausing only at PR
creation. State.md is the single source of truth (no sidecar JSON state)."
```

---

## Self-Review

(Inline before invoking writing-plans handoff.)

**1. Spec coverage** — every Layer 2 PRD user story (US-001 through US-011) maps to a task here:

- US-001 (Interactive PRD Phase): handled by the existing `/prd:discuss` skill, which already runs before `/new-feature`'s PRD-complete checkpoint. The PRD phase itself isn't modified in Layer 2 — Layer 2 picks up at PRD-complete and onward.
- US-002 (Forge prints /goal): Tasks 5, 6.
- US-003 (Autonomous loop execution): Tasks 5, 6 (the printed `/goal` command's condition string defines the loop).
- US-004 (Council substitutes human): Task 2 (rule), Tasks 5, 6 (workflow commands reference the rule).
- US-005 (PR-create gate with summary): Tasks 5, 6 (AskUserQuestion modal text).
- US-006 ("PR-Ready" definition): Tasks 5, 6 (the condition string in the printed `/goal` enumerates the conditions).
- US-007 (Budget exhaustion): native `/goal` handles this; the printed condition doesn't fight it.
- US-008 (Stuck-detection soft warning): defers to Layer 1's `progress_fingerprint` + a soft-warning Stop hook addition — NOT in this plan. Flagged as a follow-up. (Layer 1's evidence emits the fingerprint; the warning emission could be a separate workstream.)
- US-009 (Observability during run): native `/goal` behavior — works out of the box.
- US-010 (Resume after interruption): native `/goal` behavior — works out of the box.
- US-011 (Downstream auto-availability): Layer 1's setup.sh wiring already copies build-evidence; Task 8 ships Layer 2 templates that downstream installs pick up via setup.sh's existing copy logic for `commands/*`, `rules/*`, `hooks/*`, `state.template.md`. No new wiring needed.

**Gap:** US-008 (stuck detection soft warning) is not built in Layer 2. The evidence emits the fingerprint; a separate hook addition would compare fingerprints across N turns and emit a soft warning. This is genuinely deferrable — the autonomous loop can hit budget exhaustion as the backstop. Recording as a follow-up.

**2. Placeholder scan** — none found. Every step has either a complete code block, a complete content block, or an explicit command + expected output.

**3. Type consistency** — checked:
- `## /goal session` section uses Markdown table format consistently (matches Layer 1's parse_goal_session expectations)
- `## PR authorization` line format is identical across state.template.md, the workflow command instructions, and the check-workflow-gates parsers (Tasks 3, 4)
- Session nonce + head SHA naming is consistent: `nonce=`<v>`` and `head=`<v>``
- Reviewer iteration row format matches Layer 1's `compute_reviewer_gate` parser

**4. Cross-platform watch** — Bash 3.2 / `[[:space:]]` / CRLF normalization patterns inherited from Layer 1 plan; explicit reminders in Task 3 + Task 4. No `declare -A` needed (the PR-auth parser is single-pass).

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-05-16-forge-goal-layer-2-plan.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task using `superpowers:subagent-driven-development`. Two-stage review (spec + code quality) per task. Same flow that shipped Layer 1's 10 tasks.

**2. Inline Execution** — Execute tasks in this session using `superpowers:executing-plans`. Batch checkpoints. Slower turnaround per task but full context for the user.

---

## Notes for the Executor

- **Branch:** stay on `research/forge-goal-experiments` (Layer 1's 20 commits + Layer 2's new commits, single coherent ship).
- **Test conventions:** Layer 1's `tests/template/lib.sh` API is unchanged. The new Layer 2 tests follow the same `assert_equals` / file-path `assert_contains` / `scratch_dir` patterns.
- **Plan-review-loop discipline:** before executing this plan, run `/codex` (Design Review mode) on it to catch any gaps. Layer 1's plan-review-loop found 8 P1 + 3 P2 findings on the first pass; expect similar pre-execution scrutiny here.
- **Scope skepticism:** Pablo's late-Layer-1 check ("is this overkill?") was right to flag. Layer 2's value-prop is much clearer than Layer 1's standalone, but each task should still pass the test: "Does this task deliver user-visible behavior, or is it infrastructure-for-Layer-3?" If a task feels too foundational, push back.
- **`/quick-fix` exclusion:** Layer 2 does NOT modify `/quick-fix`. Trivial changes (< 3 files) keep the manual workflow.
- **Dogfood expectation:** Task 8 Step 5 is a manual run-through. Plan time for ~30-60 minutes of real-world execution.
