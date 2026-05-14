# forge-goal Layer 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `build-evidence.sh` (and PowerShell parity) plus Stop-hook integration as a standalone improvement to claude-codex-forge. This is Layer 1 of the `/forge-goal` two-layer delivery — it strengthens existing gate hooks even before Layer 2 lands.

**Architecture:** A read-only Bash/PowerShell script that parses `.claude/local/state.md`, queries git/`gh`/E2E reports, and emits a unified evidence JSON between `FORGE_GOAL_EVIDENCE_BEGIN/END` markers. The existing `check-state-updated.sh` hook is updated to call the script and to move its `stop_hook_active` early-return AFTER evidence emission (a real bug we surface).

**Tech Stack:** Bash (GNU/BSD-portable, same conventions as existing forge hooks), PowerShell 5.1+/7+, `jq`-free JSON emission (string-built), `git`/`gh` CLIs, forge's existing test harness at `tests/template/`.

**Source spec:** `docs/plans/2026-05-14-forge-goal-design.md` (sections 1-2, 4, plus File Inventory).

---

## File Structure

**New files:**
- `hooks/build-evidence.sh` — Bash implementation (~250 lines)
- `hooks/build-evidence.ps1` — PowerShell parity (~250 lines)
- `tests/template/test-build-evidence.sh` — Bash-side test suite
- `tests/template/test-build-evidence.ps1` — PowerShell-side test suite (mirrors .sh tests)
- `tests/template/fixtures/state-md-build-evidence/` — fixture state.md files for the parser

**Modified files:**
- `hooks/check-state-updated.sh` — relocate `stop_hook_active` early-return AFTER evidence emission; call build-evidence
- `hooks/check-state-updated.ps1` — same
- `setup.sh` — `copy_file` for `build-evidence.sh`
- `setup.ps1` — `Copy-TemplateFile` for `build-evidence.ps1`
- `tests/template/run-all.sh` — register the new test script
- `tests/template/test-contracts.sh` — add cross-file contract: marker strings used by build-evidence must match what existing/future hooks expect
- `docs/CHANGELOG.md` — Layer 1 release entry
- `README.md` — version badge + Version history row

**Why this decomposition:**
- `build-evidence.sh` has ONE clear responsibility (read state, emit JSON). State parsing, external queries, and derived computations are internal concerns; tests verify external behavior only.
- Tests live alongside existing forge tests in `tests/template/` using the existing `lib.sh` harness.
- The Stop hook stays separate; build-evidence is a tool it invokes.

---

## Tasks

### Task 1: Test Fixtures

**Files:**
- Create: `tests/template/fixtures/state-md-build-evidence/empty-state.md`
- Create: `tests/template/fixtures/state-md-build-evidence/with-goal-session.md`
- Create: `tests/template/fixtures/state-md-build-evidence/mid-workflow.md`
- Create: `tests/template/fixtures/state-md-build-evidence/pr-ready.md`
- Create: `tests/template/fixtures/state-md-build-evidence/pr-authorized.md`

- [ ] **Step 1: Create fixture directory**

```bash
mkdir -p tests/template/fixtures/state-md-build-evidence
```

- [ ] **Step 2: Write `empty-state.md` (no active workflow, no goal)**

Content:
```markdown
## Workflow

- Command: none
- Phase: idle
- Next step: (no active workflow)
```

- [ ] **Step 3: Write `with-goal-session.md` (goal active, workflow at Phase 1)**

Content:
```markdown
## /goal session

- nonce: `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee`
- workflow_command: `/new-feature foo`
- issued_at: `2026-05-14T18:00:00Z`

## Workflow

- Command: /new-feature foo
- Phase: 1 — Research
- Next step: Run research-first agent

### Checklist

- [ ] Research complete
- [ ] Plan written
- [ ] Plan approved
- [ ] Tests written (TDD)
- [ ] Code review iteration 1 — codex clean — head=`<TBD>`
- [ ] Code review iteration 1 — pr-toolkit clean — head=`<TBD>`
- [ ] E2E verified via verify-e2e agent (Phase 5.4)
- [ ] PR authorized
```

- [ ] **Step 4: Write `mid-workflow.md` (some checklist items checked)**

Same as `with-goal-session.md` but with the first 4 checklist items checked, and reviewer rows with placeholder SHAs:

```markdown
### Checklist

- [x] Research complete
- [x] Plan written
- [x] Plan approved
- [x] Tests written (TDD)
- [ ] Code review iteration 1 — codex clean — head=`abc123def`
- [ ] Code review iteration 1 — pr-toolkit clean — head=`abc123def`
- [ ] E2E verified via verify-e2e agent (Phase 5.4)
- [ ] PR authorized
```

(Use a known fake SHA `abc123def` — tests use this as the "expected HEAD" to assert against.)

- [ ] **Step 5: Write `pr-ready.md` (all checklist done, reviewer rows match HEAD)**

Same structure with all checkboxes `[x]` and reviewer head SHAs that the test will assert match git HEAD (test substitutes the actual HEAD at fixture-prep time — see test helper in Task 2 below).

- [ ] **Step 6: Write `pr-authorized.md` (with `## PR authorization` section)**

Adds:
```markdown
## PR authorization

- [x] PR creation authorized — `2026-05-14T18:30:00Z` — nonce=`aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee` — head=`abc123def`
```

- [ ] **Step 7: Commit fixtures**

```bash
git add -f tests/template/fixtures/state-md-build-evidence/
git commit -m "test(fixtures): state.md variants for build-evidence parser"
```

---

### Task 2: `build-evidence.sh` Skeleton + Markers + Empty JSON

**Files:**
- Create: `hooks/build-evidence.sh`
- Create: `tests/template/test-build-evidence.sh`
- Modify: `tests/template/run-all.sh:N` (add the new test script to the runner)

- [ ] **Step 1: Write the failing test (empty fixture → markers + empty JSON)**

Append to `tests/template/test-build-evidence.sh` (after the standard header pattern from `test-hooks.sh`):

```bash
start_test "build-evidence.sh emits markers + valid JSON on empty state.md"

scratch=$(scratch_dir)
mkdir -p "$scratch/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
   "$scratch/.claude/local/state.md"

OUTPUT=$(cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" 2>&1)
EXIT=$?

assert_eq "$EXIT" "0" "exit code is 0"
assert_contains "$OUTPUT" "FORGE_GOAL_EVIDENCE_BEGIN" "begin marker present"
assert_contains "$OUTPUT" "FORGE_GOAL_EVIDENCE_END" "end marker present"
assert_contains "$OUTPUT" '"type":"forge_goal_evidence"' "type field present"
assert_contains "$OUTPUT" '"schema_version":1' "schema_version is 1"
```

- [ ] **Step 2: Run the test, verify it fails**

```bash
bash tests/template/test-build-evidence.sh
```

Expected: FAIL — `hooks/build-evidence.sh: No such file or directory`.

- [ ] **Step 3: Write minimal `hooks/build-evidence.sh`**

```bash
#!/usr/bin/env bash
# hooks/build-evidence.sh — emit FORGE_GOAL_EVIDENCE JSON to STDERR.
#
# Read-only. Parses .claude/local/state.md plus git/gh/E2E state and emits a
# unified evidence JSON between FORGE_GOAL_EVIDENCE_BEGIN/END markers.
# Stop hook (check-state-updated.sh) invokes this each turn so the Haiku
# verifier inside an active /goal sees the evidence in the transcript.

set -u

NOW_UNIX=$(date +%s)

# Emit minimal JSON for skeleton. Subsequent tasks fill in real fields.
{
    echo "FORGE_GOAL_EVIDENCE_BEGIN"
    printf '{'
    printf '"type":"forge_goal_evidence",'
    printf '"schema_version":1,'
    printf '"produced_at_unix":%d,' "$NOW_UNIX"
    printf '"session_nonce":null,'
    printf '"workflow_command":null,'
    printf '"warnings":[],'
    printf '"errors":[]'
    printf '}\n'
    echo "FORGE_GOAL_EVIDENCE_END"
} >&2

exit 0
```

Make executable:

```bash
chmod +x hooks/build-evidence.sh
```

- [ ] **Step 4: Register the test in `tests/template/run-all.sh`**

Add `bash "$REPO_ROOT/tests/template/test-build-evidence.sh"` to the list of test scripts in `run-all.sh` (locate the existing list and append).

- [ ] **Step 5: Run test, verify PASS**

```bash
bash tests/template/test-build-evidence.sh
```

Expected: 1 PASS group with all 5 assertions green.

- [ ] **Step 6: Commit**

```bash
git add -f hooks/build-evidence.sh tests/template/test-build-evidence.sh tests/template/run-all.sh
git commit -m "feat(hooks): build-evidence.sh skeleton with FORGE_GOAL_EVIDENCE markers"
```

---

### Task 3: state.md Parser — `## /goal session` Section

**Files:**
- Modify: `hooks/build-evidence.sh` — add parser for `## /goal session` block
- Modify: `tests/template/test-build-evidence.sh` — add tests for the parser

- [ ] **Step 1: Write failing tests**

Append to `tests/template/test-build-evidence.sh`:

```bash
start_test "build-evidence.sh parses ## /goal session section"

# Setup: copy with-goal-session.md as state.md
scratch=$(scratch_dir)
mkdir -p "$scratch/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/with-goal-session.md" \
   "$scratch/.claude/local/state.md"

OUTPUT=$(cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" 2>&1)

assert_contains "$OUTPUT" '"session_nonce":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"' \
    "session_nonce extracted"
assert_contains "$OUTPUT" '"workflow_command":"/new-feature foo"' \
    "workflow_command extracted"
```

- [ ] **Step 2: Run, verify FAIL**

Expected: assertions fail (current output has `"session_nonce":null`).

- [ ] **Step 3: Implement the parser**

Add a function near the top of `hooks/build-evidence.sh` (before the JSON emission block):

```bash
STATE_MD=".claude/local/state.md"

parse_goal_session() {
    # Echo "nonce|workflow_command" or empty if section missing.
    # Section format:
    #   ## /goal session
    #   - nonce: `<uuid>`
    #   - workflow_command: `<cmd>`
    [ -f "$STATE_MD" ] || return 0

    local nonce=""
    local cmd=""
    local in_section=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^##\ +/goal\ session ]]; then
            in_section=1
            continue
        fi
        if [ $in_section -eq 1 ] && [[ "$line" =~ ^##\  ]]; then
            # Next section started; stop.
            break
        fi
        if [ $in_section -eq 1 ]; then
            if [[ "$line" =~ ^-\ +nonce:\ +\`([^\`]+)\` ]]; then
                nonce="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^-\ +workflow_command:\ +\`([^\`]+)\` ]]; then
                cmd="${BASH_REMATCH[1]}"
            fi
        fi
    done < "$STATE_MD"

    printf '%s|%s' "$nonce" "$cmd"
}

# Helper to emit JSON string fields (handles null vs quoted-string).
json_str_field() {
    # Usage: json_str_field "key" "value" — value can be empty (becomes null).
    local key="$1"
    local val="$2"
    if [ -z "$val" ]; then
        printf '"%s":null' "$key"
    else
        # Minimal escaping — backslash and double-quote only. State.md doesn't
        # carry control chars in these fields by convention.
        local esc="${val//\\/\\\\}"
        esc="${esc//\"/\\\"}"
        printf '"%s":"%s"' "$key" "$esc"
    fi
}
```

Then in the JSON emission block, replace the `null` literals:

```bash
GOAL_PARSED=$(parse_goal_session)
GOAL_NONCE="${GOAL_PARSED%%|*}"
GOAL_CMD="${GOAL_PARSED##*|}"

# In the printf block, replace the two `null` lines with:
$(json_str_field "session_nonce" "$GOAL_NONCE"),
$(json_str_field "workflow_command" "$GOAL_CMD"),
```

(The `printf` re-arrangement needs care — use a single composed JSON string or multiple `printf` lines.)

- [ ] **Step 4: Run test, verify PASS**

```bash
bash tests/template/test-build-evidence.sh
```

Expected: all 7 assertions pass (2 new + 5 from skeleton test).

- [ ] **Step 5: Commit**

```bash
git add -f hooks/build-evidence.sh tests/template/test-build-evidence.sh
git commit -m "feat(hooks): parse ## /goal session section in build-evidence.sh"
```

---

### Task 4: state.md Parser — `## Workflow` Checklist + Reviewer Rows

**Files:**
- Modify: `hooks/build-evidence.sh`
- Modify: `tests/template/test-build-evidence.sh`

- [ ] **Step 1: Write failing tests**

```bash
start_test "build-evidence.sh parses workflow checklist counts and reviewer rows"

scratch=$(scratch_dir)
mkdir -p "$scratch/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/mid-workflow.md" \
   "$scratch/.claude/local/state.md"

OUTPUT=$(cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" 2>&1)

assert_contains "$OUTPUT" '"phase":"1 — Research"' "phase parsed"
assert_contains "$OUTPUT" '"checklist_total":8' "total count correct"
assert_contains "$OUTPUT" '"checklist_done":4' "done count correct"
# reviewer_gate.clean_same_iteration must be FALSE — head=abc123def doesn't match git HEAD
assert_contains "$OUTPUT" '"reviewer_gate":{"clean_same_iteration":false' \
    "reviewer gate not clean (head mismatch)"
```

- [ ] **Step 2: Run, verify FAIL**

- [ ] **Step 3: Implement parser additions**

Add to `hooks/build-evidence.sh`:

```bash
parse_workflow() {
    # Emits: phase|next_step|total|done|reviewer_iteration_lines (NL-separated)
    # via a tempfile to avoid shell escaping pain. Returns the tempfile path.
    [ -f "$STATE_MD" ] || { echo ""; return 0; }

    local tmp; tmp=$(mktemp)
    awk '
        BEGIN { phase=""; next_step=""; total=0; done=0; in_workflow=0; in_checklist=0 }
        /^## Workflow/ { in_workflow=1; next }
        /^## / && in_workflow { in_workflow=0; in_checklist=0 }
        in_workflow && /^- Phase: / { sub(/^- Phase: /, ""); phase=$0; next }
        in_workflow && /^- Next step: / { sub(/^- Next step: /, ""); next_step=$0; next }
        /^### Checklist/ { in_checklist=1; next }
        in_checklist && /^- \[x\]/ { done++; total++ }
        in_checklist && /^- \[ \]/ { total++ }
        in_checklist && /Code review iteration .* head=`[^`]+`/ {
            print "REVIEWER|" $0 >> "/dev/stderr"
        }
        END {
            print "PHASE|" phase
            print "NEXT|" next_step
            print "TOTAL|" total
            print "DONE|" done
        }
    ' "$STATE_MD" > "$tmp" 2> "${tmp}.reviewers"

    echo "$tmp"
}
```

Add a separate function for reviewer gate evaluation:

```bash
compute_reviewer_gate() {
    # Args: $1 = reviewers tmpfile, $2 = current HEAD sha
    # Output: "clean_same_iteration|matched_iteration|matched_head"
    local reviewers_file="$1"
    local head_sha="$2"

    [ -f "$reviewers_file" ] || { echo "false||"; return 0; }
    [ -z "$head_sha" ] && { echo "false||"; return 0; }

    # Group reviewer lines by iteration number; require BOTH codex AND pr-toolkit
    # clean for the same iteration at the current HEAD.
    local clean="false"
    local match_iter=""
    local match_head=""

    declare -A iter_codex iter_toolkit

    while IFS= read -r line; do
        # Match: - [x] Code review iteration N — <tool> clean — head=`<sha>`
        if [[ "$line" =~ \[x\][[:space:]]+Code\ review\ iteration\ ([0-9]+)\ +—\ +([a-z\-]+)\ +clean\ +—\ +head=\`([0-9a-f]+)\` ]]; then
            local iter="${BASH_REMATCH[1]}"
            local tool="${BASH_REMATCH[2]}"
            local sha="${BASH_REMATCH[3]}"

            if [ "$sha" = "$head_sha" ]; then
                case "$tool" in
                    codex)      iter_codex["$iter"]="$sha" ;;
                    pr-toolkit) iter_toolkit["$iter"]="$sha" ;;
                esac
            fi
        fi
    done < "$reviewers_file"

    for iter in "${!iter_codex[@]}"; do
        if [ -n "${iter_toolkit[$iter]:-}" ]; then
            clean="true"
            match_iter="$iter"
            match_head="${iter_codex[$iter]}"
            break
        fi
    done

    echo "${clean}|${match_iter}|${match_head}"
}
```

Wire these into the JSON emission. Add:

```bash
WF_PARSED_FILE=$(parse_workflow)
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
RG_RESULT=$(compute_reviewer_gate "${WF_PARSED_FILE}.reviewers" "$HEAD_SHA")
RG_CLEAN="${RG_RESULT%%|*}"
# ... (extract phase, next_step, total, done from WF_PARSED_FILE)
```

And in the JSON output, add the `state` and `reviewer_gate` keys.

- [ ] **Step 4: Run test, verify PASS**

- [ ] **Step 5: Commit**

```bash
git add -f hooks/build-evidence.sh tests/template/test-build-evidence.sh
git commit -m "feat(hooks): parse Workflow checklist + reviewer iteration rows"
```

---

### Task 5: External State — git + `gh` + E2E reports

**Files:**
- Modify: `hooks/build-evidence.sh`
- Modify: `tests/template/test-build-evidence.sh`

- [ ] **Step 1: Write failing tests for git state, gh fallback, and E2E**

Add to `tests/template/test-build-evidence.sh`:

```bash
start_test "build-evidence.sh queries git state and includes head_sha"

scratch=$(scratch_dir)
# scratch is already a git repo via scratch_dir helper? if not, init one:
cd "$scratch"
git init -q
git config user.email "test@test"
git config user.name "Test"
echo "x" > a.txt
git add a.txt
git commit -q -m "init"

mkdir -p .claude/local
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
   .claude/local/state.md

OUTPUT=$(bash "$REPO_ROOT/hooks/build-evidence.sh" 2>&1)

EXPECTED_HEAD=$(git rev-parse HEAD)
assert_contains "$OUTPUT" "\"head_sha\":\"$EXPECTED_HEAD\"" "head_sha matches git"
assert_contains "$OUTPUT" '"branch":"' "branch field present"
```

Then a second test for `gh` graceful absence:

```bash
start_test "build-evidence.sh handles gh pr view absence gracefully"

scratch=$(scratch_dir)
cd "$scratch"; git init -q; git config user.email t@t; git config user.name t
echo x > a; git add a; git commit -qm init
mkdir -p .claude/local
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
   .claude/local/state.md

OUTPUT=$(bash "$REPO_ROOT/hooks/build-evidence.sh" 2>&1)
EXIT=$?
assert_eq "$EXIT" "0" "exit code 0 even when no PR exists"
assert_contains "$OUTPUT" '"pr_state":{"exists":false' "pr_state.exists=false"
```

Third test for E2E report freshness (reuse existing tests/e2e/reports convention):

```bash
start_test "build-evidence.sh detects fresh E2E report"

scratch=$(scratch_dir)
cd "$scratch"; git init -q -b main; git config user.email t@t; git config user.name t
echo x > a; git add a; git commit -qm init  # this is branch-off
git checkout -q -b feature
mkdir -p tests/e2e/reports .claude/local
echo "report" > tests/e2e/reports/2026-05-14-test.md  # newer than branch-off
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
   .claude/local/state.md

OUTPUT=$(bash "$REPO_ROOT/hooks/build-evidence.sh" 2>&1)
assert_contains "$OUTPUT" '"e2e_report":{"present":true' "e2e present"
assert_contains "$OUTPUT" '"fresh_for_head":true' "e2e fresh"
```

- [ ] **Step 2: Run, verify FAIL**

- [ ] **Step 3: Implement git state, gh, and E2E queries**

Add to `hooks/build-evidence.sh`:

```bash
# Git state
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
TREE_SHA=$(git rev-parse HEAD^{tree} 2>/dev/null || echo "")
DIRTY="false"
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then DIRTY="true"; fi

BRANCH_OFF=$(git merge-base HEAD main 2>/dev/null \
            || git merge-base HEAD master 2>/dev/null \
            || echo "")

BRANCH_OFF_TS=""
if [ -n "$BRANCH_OFF" ]; then
    BRANCH_OFF_TS=$(git log -1 --format=%ct "$BRANCH_OFF" 2>/dev/null || echo "")
fi

# gh pr view — best effort
PR_EXISTS="false"
PR_NUMBER="null"
PR_URL=""
PR_STATE=""
PR_HEAD_OID=""
PR_BASE_REF=""
PR_HEAD_REF=""

if command -v gh >/dev/null 2>&1; then
    PR_JSON=$(gh pr view --json number,url,state,headRefOid,baseRefName,headRefName 2>/dev/null || echo "")
    if [ -n "$PR_JSON" ]; then
        PR_EXISTS="true"
        # Minimal field extraction without jq dep — use grep + sed
        PR_NUMBER=$(echo "$PR_JSON" | grep -o '"number":[0-9]*' | sed 's/.*://')
        PR_URL=$(echo "$PR_JSON" | grep -o '"url":"[^"]*"' | sed 's/.*"url":"//;s/"$//')
        PR_STATE=$(echo "$PR_JSON" | grep -o '"state":"[^"]*"' | sed 's/.*"state":"//;s/"$//')
        PR_HEAD_OID=$(echo "$PR_JSON" | grep -o '"headRefOid":"[^"]*"' | sed 's/.*"headRefOid":"//;s/"$//')
        PR_BASE_REF=$(echo "$PR_JSON" | grep -o '"baseRefName":"[^"]*"' | sed 's/.*"baseRefName":"//;s/"$//')
        PR_HEAD_REF=$(echo "$PR_JSON" | grep -o '"headRefName":"[^"]*"' | sed 's/.*"headRefName":"//;s/"$//')
    fi
fi

# E2E report freshness — reuse the mtime logic from check-workflow-gates.sh
E2E_PRESENT="false"
E2E_FRESH="false"
E2E_PATH=""
E2E_MTIME=""

if [ -d "tests/e2e/reports" ]; then
    # stat syntax: GNU vs BSD
    if stat -c %Y /dev/null >/dev/null 2>&1; then
        STAT_CMD='stat -c %Y'
    else
        STAT_CMD='stat -f %m'
    fi

    NEWEST_PATH=""
    NEWEST_MTIME=0
    for r in tests/e2e/reports/*.md; do
        [ -f "$r" ] || continue
        m=$($STAT_CMD "$r" 2>/dev/null || echo 0)
        if [ "$m" -gt "$NEWEST_MTIME" ]; then
            NEWEST_MTIME="$m"
            NEWEST_PATH="$r"
        fi
    done

    if [ -n "$NEWEST_PATH" ]; then
        E2E_PRESENT="true"
        E2E_PATH="$NEWEST_PATH"
        E2E_MTIME="$NEWEST_MTIME"
        if [ -n "$BRANCH_OFF_TS" ] && [ "$NEWEST_MTIME" -gt "$BRANCH_OFF_TS" ]; then
            E2E_FRESH="true"
        fi
    fi
fi
```

Wire these into the JSON output. Add the `branch`, `head_sha`, `tree_sha`, `branch_off_commit`, `working_tree_dirty`, `pr_state`, and `e2e_report` objects.

- [ ] **Step 4: Run tests, verify PASS**

- [ ] **Step 5: Commit**

```bash
git add -f hooks/build-evidence.sh tests/template/test-build-evidence.sh
git commit -m "feat(hooks): build-evidence reads git + gh pr view + E2E freshness"
```

---

### Task 6: `## PR authorization` Parser + Derived Fields

**Files:**
- Modify: `hooks/build-evidence.sh`
- Modify: `tests/template/test-build-evidence.sh`

- [ ] **Step 1: Write failing tests**

```bash
start_test "build-evidence.sh parses ## PR authorization line"

scratch=$(scratch_dir)
cd "$scratch"; git init -q; git config user.email t@t; git config user.name t
echo x > a; git add a; git commit -qm init
# Match the fixture's expected head: rewrite the fixture's `abc123def` to actual HEAD
mkdir -p .claude/local
EXPECTED_HEAD=$(git rev-parse HEAD)
sed "s/abc123def/$EXPECTED_HEAD/g" \
    "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/pr-authorized.md" \
    > .claude/local/state.md

OUTPUT=$(bash "$REPO_ROOT/hooks/build-evidence.sh" 2>&1)
assert_contains "$OUTPUT" '"pr_authorization":{"authorized":true' "authorized=true"
assert_contains "$OUTPUT" "\"head_sha_at_authorization\":\"$EXPECTED_HEAD\"" \
    "authorization head matches"
```

Second test: authorization without matching head should be `false`:

```bash
start_test "build-evidence.sh rejects pr_authorization with stale head"

scratch=$(scratch_dir)
cd "$scratch"; git init -q; git config user.email t@t; git config user.name t
echo x > a; git add a; git commit -qm init
mkdir -p .claude/local
# Use fixture as-is (abc123def doesn't match git HEAD)
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/pr-authorized.md" \
   .claude/local/state.md

OUTPUT=$(bash "$REPO_ROOT/hooks/build-evidence.sh" 2>&1)
assert_contains "$OUTPUT" '"pr_authorization":{"authorized":false' \
    "authorization false when head mismatched"
```

- [ ] **Step 2: Run, verify FAIL**

- [ ] **Step 3: Implement the parser + derivation**

Add to `hooks/build-evidence.sh`:

```bash
parse_pr_authorization() {
    # Echo "authorized_bool|authorized_at|head_sha_at_auth|nonce_at_auth"
    [ -f "$STATE_MD" ] || { echo "false|||"; return 0; }
    [ -z "$HEAD_SHA" ] && { echo "false|||"; return 0; }
    [ -z "$GOAL_NONCE" ] && { echo "false|||"; return 0; }

    local line
    line=$(grep -E '^-\s*\[x\]\s+PR creation authorized' "$STATE_MD" | head -1)

    if [ -z "$line" ]; then
        echo "false|||"
        return 0
    fi

    # Match: - [x] PR creation authorized — `<ts>` — nonce=`<n>` — head=`<sha>`
    if [[ "$line" =~ \[x\][[:space:]]+PR\ creation\ authorized\ +—\ +\`([^\`]+)\`\ +—\ +nonce=\`([^\`]+)\`\ +—\ +head=\`([^\`]+)\` ]]; then
        local at="${BASH_REMATCH[1]}"
        local nonce="${BASH_REMATCH[2]}"
        local head="${BASH_REMATCH[3]}"

        if [ "$nonce" = "$GOAL_NONCE" ] && [ "$head" = "$HEAD_SHA" ]; then
            echo "true|${at}|${head}|${nonce}"
        else
            echo "false|${at}|${head}|${nonce}"
        fi
    else
        echo "false|||"
    fi
}

PA_PARSED=$(parse_pr_authorization)
PA_AUTH="${PA_PARSED%%|*}"
# (extract other fields similarly)
```

Wire into JSON output as `"pr_authorization"` object.

- [ ] **Step 4: Run tests, verify PASS**

- [ ] **Step 5: Commit**

```bash
git add -f hooks/build-evidence.sh tests/template/test-build-evidence.sh
git commit -m "feat(hooks): parse ## PR authorization with nonce+head match"
```

---

### Task 7: Derived Computations — `pr_ready`, `all_gates_green`, `progress_fingerprint`

**Files:**
- Modify: `hooks/build-evidence.sh`
- Modify: `tests/template/test-build-evidence.sh`

- [ ] **Step 1: Write failing tests for derived fields**

```bash
start_test "build-evidence.sh computes pr_ready and all_gates_green"

# Set up scratch: pr-ready.md fixture, head SHA substituted, PR exists (mock?)
# Since gh pr view requires a real PR, this test focuses on the LOGIC by using
# a wrapper that fakes gh output. Easiest: a stub gh in PATH for the test.

scratch=$(scratch_dir)
cd "$scratch"; git init -q -b main; git config user.email t@t; git config user.name t
echo x > a; git add a; git commit -qm init
git checkout -q -b feature
echo y > b; git add b; git commit -qm feature

EXPECTED_HEAD=$(git rev-parse HEAD)
mkdir -p .claude/local tests/e2e/reports
echo "report" > tests/e2e/reports/2026-05-14-test.md  # fresh

# Stub gh that returns a fake "open PR"
mkdir bin
cat > bin/gh <<EOF
#!/usr/bin/env bash
echo '{"number":42,"url":"https://x/pr/42","state":"OPEN","headRefOid":"$EXPECTED_HEAD","baseRefName":"main","headRefName":"feature"}'
EOF
chmod +x bin/gh

sed "s/abc123def/$EXPECTED_HEAD/g" \
    "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/pr-authorized.md" \
    > .claude/local/state.md

OUTPUT=$(PATH="$scratch/bin:$PATH" bash "$REPO_ROOT/hooks/build-evidence.sh" 2>&1)
assert_contains "$OUTPUT" '"pr_ready":true' "pr_ready=true with full state"
assert_contains "$OUTPUT" '"all_gates_green":true' "all_gates_green=true"
```

Second test for `progress_fingerprint` stability:

```bash
start_test "build-evidence.sh emits stable progress_fingerprint"

# Run twice on identical state, expect identical fingerprint.
scratch=$(scratch_dir)
cd "$scratch"; git init -q; git config user.email t@t; git config user.name t
echo x > a; git add a; git commit -qm init
mkdir -p .claude/local
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/mid-workflow.md" \
   .claude/local/state.md

OUT1=$(bash "$REPO_ROOT/hooks/build-evidence.sh" 2>&1)
OUT2=$(bash "$REPO_ROOT/hooks/build-evidence.sh" 2>&1)

FP1=$(echo "$OUT1" | grep -o '"progress_fingerprint":"[^"]*"')
FP2=$(echo "$OUT2" | grep -o '"progress_fingerprint":"[^"]*"')
assert_eq "$FP1" "$FP2" "fingerprint stable across identical runs"
```

- [ ] **Step 2: Run, verify FAIL**

- [ ] **Step 3: Implement derived computations**

Add to `hooks/build-evidence.sh`:

```bash
# pr_ready: PR open AND PR head matches AND reviewer gate clean AND E2E fresh AND PR auth match
PR_OPEN="false"
[ "$PR_STATE" = "OPEN" ] && PR_OPEN="true"

PR_HEAD_MATCH="false"
[ "$PR_HEAD_OID" = "$HEAD_SHA" ] && PR_HEAD_MATCH="true"

PR_READY="false"
if [ "$PR_OPEN" = "true" ] && [ "$PR_HEAD_MATCH" = "true" ] && \
   [ "$RG_CLEAN" = "true" ] && [ "$E2E_FRESH" = "true" ] && \
   [ "$PA_AUTH" = "true" ]; then
    PR_READY="true"
fi

# all_gates_green: every checklist [ ] is gone AND pr_ready=true
ALL_GATES="false"
if [ "$DONE_COUNT" -eq "$TOTAL_COUNT" ] && [ "$PR_READY" = "true" ]; then
    ALL_GATES="true"
fi

# progress_fingerprint: SHA256 of subset
# Subset = workflow phase + next + checklist contents + reviewer rows + PR auth state
FP_INPUT=$(printf '%s\n%s\n' "$PHASE" "$NEXT_STEP")
FP_INPUT="${FP_INPUT}$(grep -E '^- \[[ x]\]' "$STATE_MD" 2>/dev/null | sort)"
FP_INPUT="${FP_INPUT}$(grep -E '^- \[[ x]\]\s+PR creation authorized' "$STATE_MD" 2>/dev/null)"

if command -v sha256sum >/dev/null 2>&1; then
    PROGRESS_FP=$(printf '%s' "$FP_INPUT" | sha256sum | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    PROGRESS_FP=$(printf '%s' "$FP_INPUT" | shasum -a 256 | awk '{print $1}')
else
    PROGRESS_FP=""
fi
```

Add to JSON output:

```bash
printf '"pr_ready":%s,' "$PR_READY"
printf '"all_gates_green":%s,' "$ALL_GATES"
printf '"progress_fingerprint":"%s",' "$PROGRESS_FP"
```

- [ ] **Step 4: Run tests, verify PASS**

- [ ] **Step 5: Commit**

```bash
git add -f hooks/build-evidence.sh tests/template/test-build-evidence.sh
git commit -m "feat(hooks): derive pr_ready, all_gates_green, progress_fingerprint"
```

---

### Task 8: PowerShell Parity — `build-evidence.ps1`

**Files:**
- Create: `hooks/build-evidence.ps1`
- Create: `tests/template/test-build-evidence.ps1`

- [ ] **Step 1: Write failing PowerShell test (mirror of Task 2 skeleton test)**

`tests/template/test-build-evidence.ps1`:

```powershell
# Mirrors tests/template/test-build-evidence.sh structure.
# Run from repo root: pwsh tests/template/test-build-evidence.ps1

$ErrorActionPreference = 'Stop'
$REPO_ROOT = (Get-Item "$PSScriptRoot/../..").FullName
. "$REPO_ROOT/tests/template/lib.ps1"  # If exists; else inline helpers.

Start-Test "build-evidence.ps1 emits markers + valid JSON on empty state.md"

$scratch = New-ScratchDir
New-Item -ItemType Directory -Force -Path "$scratch/.claude/local" | Out-Null
Copy-Item "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" `
          "$scratch/.claude/local/state.md"

Push-Location $scratch
$output = pwsh -NoProfile -File "$REPO_ROOT/hooks/build-evidence.ps1" 2>&1 | Out-String
$exit = $LASTEXITCODE
Pop-Location

Assert-Eq $exit 0 "exit code is 0"
Assert-Contains $output "FORGE_GOAL_EVIDENCE_BEGIN" "begin marker"
Assert-Contains $output "FORGE_GOAL_EVIDENCE_END" "end marker"
Assert-Contains $output '"type":"forge_goal_evidence"' "type field"
```

- [ ] **Step 2: Run test (FAIL — script doesn't exist)**

- [ ] **Step 3: Implement PowerShell skeleton**

`hooks/build-evidence.ps1`:

```powershell
# hooks/build-evidence.ps1 — emit FORGE_GOAL_EVIDENCE JSON to STDERR.
# Mirrors hooks/build-evidence.sh. See that file for design notes.

$ErrorActionPreference = 'Continue'

$NowUnix = [int][double]::Parse((Get-Date -UFormat %s))

# Skeleton: emit minimal JSON
$json = @"
{"type":"forge_goal_evidence","schema_version":1,"produced_at_unix":$NowUnix,"session_nonce":null,"workflow_command":null,"warnings":[],"errors":[]}
"@

[Console]::Error.WriteLine("FORGE_GOAL_EVIDENCE_BEGIN")
[Console]::Error.WriteLine($json)
[Console]::Error.WriteLine("FORGE_GOAL_EVIDENCE_END")

exit 0
```

- [ ] **Step 4: Run test, verify PASS**

- [ ] **Step 5: Port remaining parsers from .sh to .ps1**

This is the bulk of the work. Port each parser function (`parse_goal_session`, `parse_workflow`, `parse_pr_authorization`) and external state queries (`git`, `gh`, E2E mtime) to PowerShell. Use `Get-Content`, `Select-String`, `[regex]` for parsing.

Key conversion notes:
- Bash `[[ ... =~ ... ]]` → PowerShell `if ($line -match '...') { $matches[1]... }`
- Bash `grep` → PowerShell `Select-String`
- Bash `stat -c %Y` → PowerShell `(Get-Item $path).LastWriteTime.ToFileTimeUtc()` (with conversion to Unix epoch)
- Bash `git rev-parse` → invoke `git` directly (same)
- Bash `gh pr view --json X` → same; parse with `ConvertFrom-Json`
- JSON emission: hand-built string (don't use `ConvertTo-Json` — it adds whitespace; we need byte-stable output for fingerprinting)

Port tests AS YOU GO — for each Bash test, write the PowerShell mirror, run, verify PASS, then move on.

- [ ] **Step 6: Verify all tests pass on both platforms (Bash + PowerShell)**

```bash
bash tests/template/test-build-evidence.sh
pwsh tests/template/test-build-evidence.ps1
```

Expected: both green.

- [ ] **Step 7: Commit**

```bash
git add -f hooks/build-evidence.ps1 tests/template/test-build-evidence.ps1
git commit -m "feat(hooks): build-evidence.ps1 PowerShell parity"
```

---

### Task 9: Stop-Hook Integration — Move `stop_hook_active` Early Return

**Files:**
- Modify: `hooks/check-state-updated.sh`
- Modify: `hooks/check-state-updated.ps1`
- Modify: `tests/template/test-hooks.sh` (or new test for this scenario)

- [ ] **Step 1: Write failing test — evidence must emit even when `stop_hook_active=true`**

Add to `tests/template/test-hooks.sh` (or a new file):

```bash
start_test "check-state-updated emits build-evidence markers even when stop_hook_active=true"

scratch=$(scratch_dir)
mkdir -p "$scratch/.claude/local" "$scratch/.claude/hooks"
cp "$REPO_ROOT/hooks/build-evidence.sh" "$scratch/.claude/hooks/build-evidence.sh"
chmod +x "$scratch/.claude/hooks/build-evidence.sh"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
   "$scratch/.claude/local/state.md"

# Simulate Claude Code calling the hook with stop_hook_active=true
INPUT='{"stop_hook_active":true,"transcript_path":"/tmp/x"}'
cd "$scratch" && OUTPUT=$(echo "$INPUT" | bash "$REPO_ROOT/hooks/check-state-updated.sh" 2>&1)
EXIT=$?

assert_eq "$EXIT" "0" "hook exits 0"
assert_contains "$OUTPUT" "FORGE_GOAL_EVIDENCE_BEGIN" "evidence markers emit despite stop_hook_active"
```

- [ ] **Step 2: Run, verify FAIL**

Expected: assertion fails — the current hook returns early on stop_hook_active before emitting evidence.

- [ ] **Step 3: Modify `hooks/check-state-updated.sh`**

Move the build-evidence call AND its execution to BEFORE the existing `stop_hook_active` early-return. Pattern:

```bash
# At the top of check-state-updated.sh, after stdin parsing:

# Emit FORGE_GOAL evidence first — this must run on every Stop call,
# including those triggered inside an active /goal loop (stop_hook_active=true),
# so the /goal verifier sees the current evidence in transcript each turn.
EVIDENCE_SCRIPT="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/hooks/build-evidence.sh"
if [ -x "$EVIDENCE_SCRIPT" ]; then
    bash "$EVIDENCE_SCRIPT" || true  # non-blocking; failures emit empty markers
fi

# THEN the existing stop_hook_active early-return:
STOP_HOOK_ACTIVE=$(... existing parse ...)
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# ... rest of existing hook logic ...
```

- [ ] **Step 4: Run test, verify PASS**

- [ ] **Step 5: Mirror change in `hooks/check-state-updated.ps1`**

Same pattern in PowerShell:

```powershell
# Near top, after parsing stdin JSON:
$evidenceScript = Join-Path ($env:CLAUDE_PROJECT_DIR ?? (Get-Location)) ".claude/hooks/build-evidence.ps1"
if (Test-Path $evidenceScript) {
    try { pwsh -NoProfile -File $evidenceScript 2>&1 | Out-Null } catch {}
}

# Then the existing stop_hook_active early-return.
```

(Note: the script's STDERR is what gets passed through, so capture-then-rewrite may not be needed; verify in PowerShell tests.)

- [ ] **Step 6: Run both Bash and PowerShell hook tests**

```bash
bash tests/template/test-hooks.sh
pwsh tests/template/test-hooks.ps1
```

Both green.

- [ ] **Step 7: Commit**

```bash
git add -f hooks/check-state-updated.sh hooks/check-state-updated.ps1 tests/template/test-hooks.sh
git commit -m "fix(hooks): emit build-evidence BEFORE stop_hook_active early-return

Existing early-return path suppressed evidence emission inside an active /goal
loop, which would have made the verifier blind. Move evidence emission to the
top of the hook so it always runs, then keep the early-return for the rest of
the hook logic (CHANGELOG nag, etc.)."
```

---

### Task 10: setup.sh / setup.ps1 Wiring + Downstream Smoke + Release

**Files:**
- Modify: `setup.sh`
- Modify: `setup.ps1`
- Modify: `docs/CHANGELOG.md`
- Modify: `README.md`
- Modify: `tests/template/test-contracts.sh` (add cross-file marker contract)

- [ ] **Step 1: Add `build-evidence.{sh,ps1}` to `setup.sh`**

Find the existing hook-copy block in `setup.sh` (look for `copy_file ... check-state-updated.sh`). Add:

```bash
copy_file "$HOOKS_SRC/build-evidence.sh" ".claude/hooks/build-evidence.sh"
chmod +x ".claude/hooks/build-evidence.sh"
```

- [ ] **Step 2: Same in `setup.ps1`**

Find the matching `Copy-TemplateFile` block:

```powershell
Copy-TemplateFile (Join-Path $hooksDir "build-evidence.ps1") ".claude\hooks\build-evidence.ps1" ".claude\hooks\build-evidence.ps1"
```

- [ ] **Step 3: Add cross-file marker contract to `tests/template/test-contracts.sh`**

```bash
start_test "FORGE_GOAL_EVIDENCE markers are stable across producer/consumer"

# Producer
grep -q "FORGE_GOAL_EVIDENCE_BEGIN" "$REPO_ROOT/hooks/build-evidence.sh" \
    || fail "build-evidence.sh must contain FORGE_GOAL_EVIDENCE_BEGIN marker"
grep -q "FORGE_GOAL_EVIDENCE_END" "$REPO_ROOT/hooks/build-evidence.sh" \
    || fail "build-evidence.sh must contain FORGE_GOAL_EVIDENCE_END marker"

# PowerShell parity
grep -q "FORGE_GOAL_EVIDENCE_BEGIN" "$REPO_ROOT/hooks/build-evidence.ps1" \
    || fail "build-evidence.ps1 must contain FORGE_GOAL_EVIDENCE_BEGIN marker"
```

- [ ] **Step 4: Run a downstream smoke test against `../mcpgateway`**

```bash
# Assumes ../mcpgateway exists with a current .claude/local/state.md
cd ../mcpgateway
bash ../claude-codex-forge/hooks/build-evidence.sh 2>&1 | head -20
```

Expected: FORGE_GOAL_EVIDENCE_BEGIN/END markers + parseable JSON. Exit 0. Document any portability issues found.

- [ ] **Step 5: Update `docs/CHANGELOG.md`**

Add a new `## X.YY (Layer 1)` entry summarizing:
- New: `build-evidence.sh` + PowerShell parity — read-only evidence emitter
- Fixed: `check-state-updated.sh` now emits evidence BEFORE `stop_hook_active` early-return (real bug fix; restores evidence visibility inside active `/goal` loops)
- New tests: `test-build-evidence.{sh,ps1}` + cross-file marker contract

- [ ] **Step 6: Bump version badge + Version history row in `README.md`**

Per the existing forge convention (see memory: "README must stay current with every release").

- [ ] **Step 7: Run the full test harness**

```bash
bash tests/template/run-all.sh
pwsh tests/template/run-all.ps1  # if it exists; else iterate test-*.ps1 manually
```

All tests green.

- [ ] **Step 8: Commit + PR**

```bash
git add -f setup.sh setup.ps1 docs/CHANGELOG.md README.md tests/template/test-contracts.sh
git commit -m "feat: ship build-evidence.sh + PowerShell parity (Layer 1 of /forge-goal)

Layer 1 is independently useful — it strengthens existing gate hooks by
centralizing E2E mtime checks, reviewer-iteration head-SHA matching, PR
state, and progress fingerprinting into a unified JSON evidence blob. Used
standalone today; consumed by the /forge-goal autonomous-loop verifier in
Layer 2.

Also fixes a real bug: check-state-updated.sh was suppressing its own
evidence emission inside active /goal loops via the stop_hook_active
early-return. Now evidence emits first, then the early-return runs.
"
```

Create the PR:

```bash
git push -u origin <branch>
gh pr create --title "feat: build-evidence.sh + Stop-hook integration (Layer 1 of /forge-goal)" --body "..."
```

---

## Self-Review

(Performed inline by the planner.)

**1. Spec coverage:**
- Spec §1 Evidence Primitive → Tasks 2-7 (skeleton, parsers, queries, derivations, emission)
- Spec §2 Stop Hook Integration → Task 9 (move early-return + wire evidence call)
- Spec §4 Reviewer Gate Durability → Task 4 + Task 6 (reviewer rows with head=<sha>; pr_authorization match)
- Spec § File Inventory (Layer 1 portion) → Tasks 1, 2, 8, 9, 10
- Spec § Test Plan (Layer 1) → Tasks 1, 2-7 inline tests, Task 10 cross-file contracts + smoke

Missing: nothing in Layer 1 scope. Layer 2 items intentionally deferred to Plan 2.

**2. Placeholder scan:** None found. Every step has either a code block or an explicit command + expected output.

**3. Type consistency:** JSON keys are consistent across tasks (verified: `session_nonce`, `head_sha`, `pr_state.state`, `reviewer_gate.clean_same_iteration`, `pr_authorization.authorized`, `pr_ready`, `all_gates_green`, `progress_fingerprint`).

**4. Cross-Platform Watch:**
- `stat` syntax: handled (GNU/BSD detection in Task 5)
- JSON emission: hand-built strings (no `ConvertTo-Json`) for byte stability
- UUID / SHA256: documented per platform in Task 8 conversion notes
- PowerShell parity is its own task (Task 8) — don't skip it

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-05-14-forge-goal-layer-1-plan.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best for: catching errors early, keeping each task's context focused, parallel-ish dev where it's safe.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints. Best for: when you want to be in the loop on every decision and don't mind a longer session.

Which approach?

---

## Notes for the Executor

- **Branch:** continue work on `research/forge-goal-experiments` OR create a new branch `feature/forge-goal-layer-1` off main. Recommend the latter for cleaner PR scope.
- **Testing convention:** `tests/template/lib.sh` is the canonical helper. Use `init_counters`, `start_test`, `assert_eq`, `assert_contains`, `scratch_dir` — see existing `test-hooks.sh` for patterns.
- **Forge meta-rule:** README badge + Version history table MUST be updated in the same PR as the CHANGELOG bump. The `feedback_readme_must_stay_current_every_release.md` memory documents this.
- **Downstream sanity:** run a smoke against `../mcpgateway` (Task 10 Step 4) before final commit — fixture tests alone are not sufficient per `feedback_test_harness_changes_against_mcpgateway.md`.
- **`gh pr create` from a worktree:** if working in a worktree, ensure `gh auth status` is clean and the worktree is pushed to a remote branch before invoking PR creation.
- **JSON-shape changes:** if you need to add a field to the evidence JSON, ALSO update the cross-file marker contract test (Task 10) so future consumers can rely on the shape.
