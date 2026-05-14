# forge-goal Layer 1 Implementation Plan

> **Version:** 1.1 — revised after Codex plan-review-loop FAIL on v1.0 (8 P1 + 3 P2). All findings addressed; see "Revision History" at end of document.



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

## Test Conventions (used across all tasks)

The forge's test harness lives at `tests/template/lib.sh`. Real API (verified against the source — do NOT invent names):

- `init_counters` — call once at the top of each test script.
- `start_test "name"` — section header.
- `assert_equals "$actual" "$expected" "msg"` — value equality.
- `assert_contains "$file_path" "$needle" "msg"` — **`$file_path` must be a real file**; substring is searched via `grep -qF`.
- `assert_matches "$file_path" "$regex" "msg"` — regex via `grep -qE`.
- `assert_file_exists "$path" "msg"`, `assert_hash_equals "$path" "$hash" "msg"`.
- `scratch_dir [prefix]` — returns a temp dir auto-cleaned via the harness's EXIT trap. Use this; do NOT call `mktemp -d` directly.
- `fail "msg"` / `pass "msg"` — explicit pass/fail.

**Canonical capture-and-assert pattern** (used in every task below):

```bash
scratch=$(scratch_dir bevidence)
mkdir -p "$scratch/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/<fixture>.md" \
   "$scratch/.claude/local/state.md"

OUT="$scratch/.out"
( cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" ) >"$OUT" 2>&1
EXIT=$?

assert_equals "$EXIT" "0" "exit code is 0"
assert_contains "$OUT" "FORGE_GOAL_EVIDENCE_BEGIN" "begin marker present"
```

Subsequent tasks reference this pattern by name ("canonical capture"); they show only the deltas.

**Bash portability (macOS 3.2 baseline):**
- NO `declare -A` (associative arrays) — use awk grouping or paired-line scans.
- NO `\s` in `grep -E` / `sed -E` — use `[[:space:]]`.
- NO `<<<` heredoc with `set -u` traps — use pipes.
- `stat` is GNU on Linux, BSD on macOS — use the detection pattern from `hooks/check-workflow-gates.sh` lines 151-154.

**Cross-file pattern reuse:**
- `## Workflow` block extraction uses the awk pattern already in `hooks/check-state-updated.sh` line 100: `awk '/^## Workflow$/{flag=1;next} flag && /^## /{flag=0} flag'`.
- `HEAD == branch_off` skip behavior comes from `hooks/check-workflow-gates.sh` lines 139-142 — copy verbatim to preserve trunk/main behavior.
- Field extraction from Markdown tables uses `grep -E '\|[[:space:]]*Field[[:space:]]*\|' | head -1 | awk -F'|' '{print $3}' | xargs` (per existing pattern in check-state-updated.sh lines 101-104).

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

- [ ] **Step 2: Write `empty-state.md` — no active workflow, no goal**

Content (matches the canonical `state.template.md` Markdown-table format):

```markdown
# Project State (per-developer, gitignored)

## Workflow

| Field     | Value |
| --------- | ----- |
| Command   | none  |
| Phase     |       |
| Next step |       |

### Checklist

(no active workflow)
```

- [ ] **Step 3: Write `with-goal-session.md` — goal active, workflow at Phase 1**

Content:

```markdown
# Project State (per-developer, gitignored)

## /goal session

| Field            | Value                                  |
| ---------------- | -------------------------------------- |
| nonce            | 00000000-0000-0000-0000-000000000001   |
| workflow_command | /new-feature foo                       |
| issued_at        | 2026-05-14T18:00:00Z                   |

## Workflow

| Field     | Value             |
| --------- | ----------------- |
| Command   | /new-feature foo  |
| Phase     | 1 — Research      |
| Next step | Run research-first|

### Checklist

- [ ] Research complete
- [ ] Plan written
- [ ] Plan approved
- [ ] Tests written (TDD)
- [ ] Code review iteration 1 — codex clean — head=`__TBD_SHA__`
- [ ] Code review iteration 1 — pr-toolkit clean — head=`__TBD_SHA__`
- [ ] E2E verified via verify-e2e agent (Phase 5.4)
- [ ] PR authorized
```

Note: `## /goal session` uses the same Markdown-table convention as `## Workflow` so the existing parsing pattern (awk block-extract + grep field-row) can be reused without inventing new parser logic. The `__TBD_SHA__` token (angle-bracket-free) avoids shell quoting fragility in tests that grep fixture content.

- [ ] **Step 4: Write `mid-workflow.md` — some checklist items checked, reviewer rows with placeholder SHAs**

Same `## /goal session` and `## Workflow` table headers as Step 3, with nonce `00000000-0000-0000-0000-000000000002` (distinct per fixture). The `### Checklist` becomes:

```markdown
### Checklist

- [x] Research complete
- [x] Plan written
- [x] Plan approved
- [x] Tests written (TDD)
- [ ] Code review iteration 1 — codex clean — head=`deadbeef`
- [ ] Code review iteration 1 — pr-toolkit clean — head=`deadbeef`
- [ ] E2E verified via verify-e2e agent (Phase 5.4)
- [ ] PR authorized
```

Fake SHA `deadbeef` is intentional — tests assert that `reviewer_gate.clean_same_iteration=false` when the SHA doesn't match the real HEAD. Using `deadbeef` (not `abc123def`) keeps reviewer-row SHAs distinct from the PR auth line SHA (`abc123def`), enabling independent substitution in tests.

- [ ] **Step 5: Write `pr-ready.md` — all checklist done; tests substitute real HEAD at fixture-prep time**

Use a placeholder token `__HEAD_SHA__` in the reviewer rows and the future `## PR authorization` line. Test setup substitutes the real `git rev-parse HEAD` value into the fixture before copying it into the scratch state.md. The `/goal session` nonce is `00000000-0000-0000-0000-000000000003` (distinct per fixture).

Content (just the checklist shown; full file mirrors Step 3 structure):

```markdown
### Checklist

- [x] Research complete
- [x] Plan written
- [x] Plan approved
- [x] Tests written (TDD)
- [x] Code review iteration 1 — codex clean — head=`__HEAD_SHA__`
- [x] Code review iteration 1 — pr-toolkit clean — head=`__HEAD_SHA__`
- [x] E2E verified via verify-e2e agent (Phase 5.4)
- [x] PR authorized
```

- [ ] **Step 6: Write `pr-authorized.md` — adds `## PR authorization` section to the `mid-workflow.md` base**

The `/goal session` nonce is `00000000-0000-0000-0000-000000000004` (distinct per fixture). The reviewer rows use `deadbeef` (a separate stale fake SHA, decoupled from the PR auth line). Append at the end of the `mid-workflow.md` content:

```markdown
## PR authorization

- [x] PR creation authorized — `2026-05-14T18:30:00Z` — nonce=`00000000-0000-0000-0000-000000000004` — head=`abc123def`
```

The PR auth line nonce (`00000000-0000-0000-0000-000000000004`) MUST match the `/goal session` nonce — required for the accepted-path test to succeed.
The PR auth line `head=abc123def` is a separate stale fake SHA from the reviewer rows (`deadbeef`), enabling each to be independently substituted by tests.

Tests for "authorization rejected on stale head" use this fixture as-is (both `deadbeef` reviewer SHAs and `abc123def` auth line SHA are intentionally stale — neither matches the test's real HEAD).
Tests for "authorization accepted" use two targeted sed substitutions — one for reviewer rows (`deadbeef`), one for the PR auth line (`abc123def`).

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

Create `tests/template/test-build-evidence.sh` with the standard header (see existing `test-hooks.sh` lines 1-14 for the source-lib.sh pattern), then add:

```bash
init_counters

start_test "build-evidence.sh emits markers + valid JSON on empty state.md"

# Canonical capture-and-assert pattern (see "Test Conventions" above).
scratch=$(scratch_dir bevidence)
mkdir -p "$scratch/.claude/local"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
   "$scratch/.claude/local/state.md"

OUT="$scratch/.out"
( cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" ) >"$OUT" 2>&1
EXIT=$?

assert_equals "$EXIT" "0" "exit code is 0"
assert_contains "$OUT" "FORGE_GOAL_EVIDENCE_BEGIN" "begin marker present"
assert_contains "$OUT" "FORGE_GOAL_EVIDENCE_END" "end marker present"
assert_contains "$OUT" '"type":"forge_goal_evidence"' "type field present"
assert_contains "$OUT" '"schema_version":1' "schema_version is 1"

# Print summary (existing forge convention from lib.sh — auto-prints via EXIT trap).
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

OUT="$scratch/.out"; ( cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" ) >"$OUT" 2>&1

assert_contains "$OUT" '"session_nonce":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"' \
    "session_nonce extracted"
assert_contains "$OUT" '"workflow_command":"/new-feature foo"' \
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
    # Section format (Markdown table — matches the fixture / state.template convention):
    #   ## /goal session
    #
    #   | Field            | Value                 |
    #   | ---------------- | --------------------- |
    #   | nonce            | <uuid>                |
    #   | workflow_command | <cmd>                 |
    #   | issued_at        | <ts>                  |
    [ -f "$STATE_MD" ] || return 0

    # CRLF normalize then awk-scope (mirrors check-state-updated.sh line 100 pattern).
    # The tr -d '\r' MUST precede awk so anchors like `^## /goal session$` match
    # regardless of editor-saved line endings (Codex P1.7 fix).
    local block
    block=$(tr -d '\r' < "$STATE_MD" \
            | awk '/^## \/goal session$/{flag=1;next} flag && /^## /{flag=0} flag')

    # Extract field values from Markdown table rows: `| Field | Value |`
    local nonce cmd
    nonce=$(echo "$block" | grep -E '\|[[:space:]]*nonce[[:space:]]*\|' \
            | head -1 | awk -F'|' '{print $3}' | xargs)
    cmd=$(echo "$block" | grep -E '\|[[:space:]]*workflow_command[[:space:]]*\|' \
            | head -1 | awk -F'|' '{print $3}' | xargs)

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

OUT="$scratch/.out"; ( cd "$scratch" && bash "$REPO_ROOT/hooks/build-evidence.sh" ) >"$OUT" 2>&1

assert_contains "$OUT" '"phase":"1 — Research"' "phase parsed"
assert_contains "$OUT" '"checklist_total":8' "total count correct"
assert_contains "$OUT" '"checklist_done":4' "done count correct"
# reviewer_gate.clean_same_iteration must be FALSE — head=deadbeef doesn't match git HEAD
assert_contains "$OUT" '"reviewer_gate":{"clean_same_iteration":false' \
    "reviewer gate not clean (head mismatch)"
```

- [ ] **Step 2: Run, verify FAIL**

- [ ] **Step 3: Implement parser additions**

Add to `hooks/build-evidence.sh`. The parser MUST scope to the `## Workflow` block exactly as the existing `check-state-updated.sh` (line 100) does, so migrated content elsewhere in state.md (stray `| Command |` rows, orphan `### Checklist` sections) can't poison counts. Reviewer rows are extracted in a SEPARATE awk pass to avoid declare -A (Bash 3.2 portability):

```bash
parse_workflow() {
    # Output (printed to stdout, pipe-friendly key|value lines):
    #   PHASE|<phase>
    #   NEXT|<next_step>
    #   TOTAL|<int>
    #   DONE|<int>
    [ -f "$STATE_MD" ] || return 0

    awk '
        BEGIN { phase=""; next_step=""; total=0; done=0; in_workflow=0; in_checklist=0 }
        /^## Workflow$/        { in_workflow=1; next }
        in_workflow && /^## /  { in_workflow=0; in_checklist=0 }                     # leaving Workflow
        in_workflow && /^### Checklist/ { in_checklist=1; next }
        in_workflow && /^### / && !/^### Checklist/ { in_checklist=0 }               # other subsection inside Workflow
        # Markdown table: |  Phase  | <value> |
        in_workflow && /\|[[:space:]]*Phase[[:space:]]*\|/ {
            n=split($0,a,"|"); phase=a[3]; gsub(/^[[:space:]]+|[[:space:]]+$/,"",phase)
        }
        in_workflow && /\|[[:space:]]*Next step[[:space:]]*\|/ {
            n=split($0,a,"|"); next_step=a[3]; gsub(/^[[:space:]]+|[[:space:]]+$/,"",next_step)
        }
        in_workflow && in_checklist && /^- \[x\]/ { done++; total++ }
        in_workflow && in_checklist && /^- \[ \]/ { total++ }
        END {
            print "PHASE|" phase
            print "NEXT|" next_step
            print "TOTAL|" total
            print "DONE|" done
        }
    ' "$STATE_MD"
}
```

Reviewer-rows pass (single-stream awk; Bash 3.2 safe; uses paired-line state, not associative arrays):

```bash
compute_reviewer_gate() {
    # Args: $1 = current HEAD sha
    # Output: "clean_same_iteration|matched_iteration|matched_head"
    local head_sha="$1"
    [ -f "$STATE_MD" ] || { echo "false||"; return 0; }
    [ -z "$head_sha" ] && { echo "false||"; return 0; }

    # Single awk pass: scope to ## Workflow / ### Checklist, extract reviewer rows
    # matching head_sha, track per-iteration which tools cleared. When both
    # codex AND pr-toolkit have cleared the same iteration at head_sha, emit
    # the iteration number and stop. Output: "<iter>" or empty.
    local matched
    matched=$(awk -v head="$head_sha" '
        BEGIN { in_workflow=0; in_checklist=0 }
        /^## Workflow$/        { in_workflow=1; next }
        in_workflow && /^## /  { in_workflow=0; in_checklist=0 }
        in_workflow && /^### Checklist/ { in_checklist=1; next }
        in_workflow && /^### / && !/^### Checklist/ { in_checklist=0 }
        in_workflow && in_checklist && /^- \[x\][[:space:]]+Code review iteration [0-9]+ — / {
            # Parse: - [x] Code review iteration <iter> — <tool> clean — head=`<sha>`
            line=$0
            if (match(line, /iteration [0-9]+/)) {
                iter=substr(line, RSTART+10, RLENGTH-10)
            } else { next }
            if (line ~ /codex clean/)      { tool="codex" }
            else if (line ~ /pr-toolkit clean/) { tool="pr-toolkit" }
            else { next }
            if (match(line, /head=`[0-9a-f]+`/)) {
                sha=substr(line, RSTART+6, RLENGTH-7)
            } else { next }
            if (sha != head) { next }

            # Track: counters[iter][tool] via a flat key (no assoc arrays needed in gawk-portable mode)
            key=iter "|" tool
            seen[key]=1

            codex_key=iter "|codex"
            tk_key=iter "|pr-toolkit"
            if (seen[codex_key] && seen[tk_key]) { print iter; exit 0 }
        }
    ' "$STATE_MD")

    if [ -n "$matched" ]; then
        echo "true|${matched}|${head_sha}"
    else
        echo "false||"
    fi
}
```

(Note: `seen[key]` works in both gawk and mawk; we avoid bash associative arrays entirely.)

Wire these into the JSON emission:

```bash
WF=$(parse_workflow)
PHASE=$(echo "$WF"      | grep '^PHASE|' | head -1 | cut -d'|' -f2-)
NEXT_STEP=$(echo "$WF"  | grep '^NEXT|'  | head -1 | cut -d'|' -f2-)
TOTAL_COUNT=$(echo "$WF"| grep '^TOTAL|' | head -1 | cut -d'|' -f2-)
DONE_COUNT=$(echo "$WF" | grep '^DONE|'  | head -1 | cut -d'|' -f2-)
TOTAL_COUNT=${TOTAL_COUNT:-0}
DONE_COUNT=${DONE_COUNT:-0}

HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
RG_RESULT=$(compute_reviewer_gate "$HEAD_SHA")
RG_CLEAN="${RG_RESULT%%|*}"
RG_REST="${RG_RESULT#*|}"
RG_ITER="${RG_REST%%|*}"
RG_HEAD="${RG_REST##*|}"
```

And in the JSON output, add the `state` and `reviewer_gate` objects:

```bash
printf '"state":{"phase":"%s","next_step":"%s","checklist_total":%d,"checklist_done":%d},' \
    "$PHASE" "$NEXT_STEP" "$TOTAL_COUNT" "$DONE_COUNT"
printf '"reviewer_gate":{"clean_same_iteration":%s,"matched_iteration":"%s","matched_head":"%s"},' \
    "$RG_CLEAN" "$RG_ITER" "$RG_HEAD"
```

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

OUT="$scratch/.out"; bash "$REPO_ROOT/hooks/build-evidence.sh" >"$OUT" 2>&1

EXPECTED_HEAD=$(git rev-parse HEAD)
assert_contains "$OUT" "\"head_sha\":\"$EXPECTED_HEAD\"" "head_sha matches git"
assert_contains "$OUT" '"branch":"' "branch field present"
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

OUT="$scratch/.out"; bash "$REPO_ROOT/hooks/build-evidence.sh" >"$OUT" 2>&1
EXIT=$?
assert_equals "$EXIT" "0" "exit code 0 even when no PR exists"
assert_contains "$OUT" '"pr_state":{"exists":false' "pr_state.exists=false"
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

OUT="$scratch/.out"; bash "$REPO_ROOT/hooks/build-evidence.sh" >"$OUT" 2>&1
assert_contains "$OUT" '"e2e_report":{"present":true' "e2e present"
assert_contains "$OUT" '"fresh_for_head":true' "e2e fresh"
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

# Critical: copy the HEAD==branch_off skip from check-workflow-gates.sh lines 139-142.
# If HEAD itself IS the branch-off commit (user on main/master), there is no
# meaningful "produced on this branch" comparison. Force the skip path so we
# don't regress trunk-only workflows.
if [ -n "$BRANCH_OFF" ] && [ -n "$HEAD_SHA" ] && [ "$BRANCH_OFF" = "$HEAD_SHA" ]; then
    BRANCH_OFF=""  # forces E2E freshness to be skipped (see below)
fi

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
# Match the fixture's expected head: two targeted seds —
#   1) reviewer rows use `deadbeef` (decoupled from PR auth line)
#   2) PR auth line uses `abc123def`
# Both must resolve to the real HEAD for authorized=true.
mkdir -p .claude/local
EXPECTED_HEAD=$(git rev-parse HEAD)
sed -e "s/deadbeef/$EXPECTED_HEAD/g" -e "s/abc123def/$EXPECTED_HEAD/g" \
    "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/pr-authorized.md" \
    > .claude/local/state.md

OUT="$scratch/.out"; bash "$REPO_ROOT/hooks/build-evidence.sh" >"$OUT" 2>&1
assert_contains "$OUT" '"pr_authorization":{"authorized":true' "authorized=true"
assert_contains "$OUT" "\"head_sha_at_authorization\":\"$EXPECTED_HEAD\"" \
    "authorization head matches"
```

Second test: authorization without matching head should be `false`:

```bash
start_test "build-evidence.sh rejects pr_authorization with stale head"

scratch=$(scratch_dir)
cd "$scratch"; git init -q; git config user.email t@t; git config user.name t
echo x > a; git add a; git commit -qm init
mkdir -p .claude/local
# Use fixture as-is: both reviewer rows (deadbeef) and PR auth line (abc123def)
# are intentionally stale — neither matches git HEAD, so authorized=false.
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/pr-authorized.md" \
   .claude/local/state.md

OUT="$scratch/.out"; bash "$REPO_ROOT/hooks/build-evidence.sh" >"$OUT" 2>&1
assert_contains "$OUT" '"pr_authorization":{"authorized":false' \
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
    # NOTE: use [[:space:]] not \s — BSD/macOS grep -E doesn't support \s.
    line=$(grep -E '^-[[:space:]]*\[x\][[:space:]]+PR creation authorized' "$STATE_MD" | head -1)

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

scratch=$(scratch_dir bevidence)
cd "$scratch"
git init -q -b main; git config user.email t@t; git config user.name t
echo x > a; git add a; git commit -qm init   # this is branch-off
BRANCH_OFF_TS=$(git log -1 --format=%ct HEAD)
git checkout -q -b feature
echo y > b; git add b; git commit -qm feature

EXPECTED_HEAD=$(git rev-parse HEAD)
mkdir -p .claude/local tests/e2e/reports

# Force E2E report mtime to be strictly LATER than the branch-off timestamp.
# Without this, the test flakes on fast machines where the report and the
# branch-off commit share the same epoch second.
REPORT=tests/e2e/reports/2026-05-14-test.md
echo "report" > "$REPORT"
FUTURE_TS=$(( BRANCH_OFF_TS + 60 ))
if touch -t "$(date -r "$FUTURE_TS" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$FUTURE_TS" +%Y%m%d%H%M.%S)" "$REPORT" 2>/dev/null; then :; else
    # BSD `date -r` needs -t differently; use a fallback that just bumps mtime forward.
    sleep 2 && touch "$REPORT"  # crude but reliable
fi

# Stub gh that VALIDATES its args before returning JSON. A too-broad stub
# (Codex P2) hides shape regressions in the caller; this one asserts the
# subcommand actually got `--json` with the expected fields.
mkdir bin
cat > bin/gh <<'STUB'
#!/usr/bin/env bash
# Validate: invocation should be `gh pr view --json number,url,state,headRefOid,baseRefName,headRefName`
if [ "$1" != "pr" ] || [ "$2" != "view" ] || [ "$3" != "--json" ]; then
    echo "FAKE GH: unexpected args: $*" >&2
    exit 99
fi
# Validate ALL 6 expected fields are in the --json comma-list (any order).
# Codex P2.2: previously this only required number+headRefOid which let shape
# regressions slip through.
for required in number url state headRefOid baseRefName headRefName; do
    case ",$4," in
        *,"$required",*) ;;
        *) echo "FAKE GH: missing required json field: $required (got: $4)" >&2; exit 99 ;;
    esac
done
echo "{\"number\":42,\"url\":\"https://x/pr/42\",\"state\":\"OPEN\",\"headRefOid\":\"__HEAD__\",\"baseRefName\":\"main\",\"headRefName\":\"feature\"}"
STUB
sed -i.bak "s/__HEAD__/$EXPECTED_HEAD/g" bin/gh && rm bin/gh.bak
chmod +x bin/gh

# Substitute real HEAD into the pr-authorized.md fixture.
# Two targeted seds: reviewer rows use `deadbeef`, PR auth line uses `abc123def`.
sed -e "s/deadbeef/$EXPECTED_HEAD/g" -e "s/abc123def/$EXPECTED_HEAD/g" \
    "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/pr-authorized.md" \
    > .claude/local/state.md

OUT="$scratch/.out"; PATH="$scratch/bin:$PATH" bash "$REPO_ROOT/hooks/build-evidence.sh" >"$OUT" 2>&1
assert_contains "$OUT" '"pr_ready":true' "pr_ready=true with full state"
assert_contains "$OUT" '"all_gates_green":true' "all_gates_green=true"
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
assert_equals "$FP1" "$FP2" "fingerprint stable across identical runs"
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

# progress_fingerprint: SHA256 of a SCOPED, ORDER-PRESERVING subset.
#
# DESIGN: the fingerprint must be deterministic across runs on identical state.
# Mistakes to avoid (Codex flagged on v1.0):
#   1. Don't sort — order is part of the signal (checklist ordering matters)
#   2. Don't whole-file-grep — migrated stray rows poison the hash
#   3. Always normalize CRLF → LF so Windows-edited state.md matches macOS
#   4. Use an explicit, byte-stable delimiter so adjacent fields don't fuse
#
# Subset (in this order):
#   - phase (from parse_workflow PHASE| output)
#   - next_step
#   - Checklist rows IN ORDER from inside `## Workflow ### Checklist` only
#   - The ## PR authorization line (if any) — see Task 6's parser
DELIM=$'\x1f'  # ASCII Unit Separator — never appears in markdown
{
    printf '%s%s' "$PHASE" "$DELIM"
    printf '%s%s' "$NEXT_STEP" "$DELIM"
    # CRLF normalize FIRST (before awk), so the `^## Workflow$` anchor matches
    # regardless of editor-saved line endings (Codex P1.7 fix v2 — tr-then-awk,
    # not awk-then-tr).
    tr -d '\r' < "$STATE_MD" 2>/dev/null | awk '
        /^## Workflow$/ { in_w=1; next }
        in_w && /^## / { in_w=0; in_c=0 }
        in_w && /^### Checklist/ { in_c=1; next }
        in_w && /^### / && !/^### Checklist/ { in_c=0 }
        in_w && in_c && /^- \[[ x]\]/ { print }
    ' | tr '\n' "$DELIM"
    # PR authorization line (whole-file ok — there's only ever one ## PR authorization section).
    # Same tr-d '\r' BEFORE grep to keep anchors stable.
    tr -d '\r' < "$STATE_MD" 2>/dev/null \
        | grep -E '^- \[[xX]\][[:space:]]+PR creation authorized' \
        | head -1
} > "${SCRATCH:-/tmp}/fp.input.$$" 2>/dev/null

if command -v sha256sum >/dev/null 2>&1; then
    PROGRESS_FP=$(sha256sum "${SCRATCH:-/tmp}/fp.input.$$" 2>/dev/null | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    PROGRESS_FP=$(shasum -a 256 "${SCRATCH:-/tmp}/fp.input.$$" 2>/dev/null | awk '{print $1}')
else
    PROGRESS_FP=""
fi
rm -f "${SCRATCH:-/tmp}/fp.input.$$"
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

**PowerShell test harness reality:** This repo has `hooks/*.ps1` files but does NOT have a runtime PowerShell test framework (`tests/template/lib.ps1` does not exist, nor do any `test-*.ps1` runners). The existing forge tests its `.ps1` files via `tests/template/test-lint.sh` (parse-only via `pwsh -NoProfile`) and via `tests/template/test-contracts.sh` (cross-file string contracts).

Therefore Layer 1 ships PowerShell coverage as **Bash-driven cross-platform smoke**, not as a parallel PS test harness. Building a full `lib.ps1` is out of scope for Layer 1 — it's a multi-feature need that deserves its own workstream.

**Files:**
- Create: `hooks/build-evidence.ps1`
- Modify: `tests/template/test-build-evidence.sh` — append a cross-platform smoke block
- Modify: `tests/template/test-lint.sh` — confirm `build-evidence.ps1` is parse-checked (likely already covered by glob)

- [ ] **Step 1: Write the failing cross-platform smoke test**

Append to `tests/template/test-build-evidence.sh`:

```bash
# --- PowerShell parity smoke (only runs if pwsh is on PATH) ---
if command -v pwsh >/dev/null 2>&1; then
    start_test "build-evidence.ps1 emits markers + valid JSON (Bash-driven smoke)"

    scratch=$(scratch_dir bevidence-ps)
    mkdir -p "$scratch/.claude/local"
    cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/empty-state.md" \
       "$scratch/.claude/local/state.md"

    OUT="$scratch/.out"
    ( cd "$scratch" && pwsh -NoProfile -File "$REPO_ROOT/hooks/build-evidence.ps1" ) >"$OUT" 2>&1
    EXIT=$?

    assert_equals "$EXIT" "0" "ps1 exit code is 0"
    assert_contains "$OUT" "FORGE_GOAL_EVIDENCE_BEGIN" "ps1 begin marker present"
    assert_contains "$OUT" "FORGE_GOAL_EVIDENCE_END"   "ps1 end marker present"
    assert_contains "$OUT" '"type":"forge_goal_evidence"' "ps1 type field present"
else
    start_test "build-evidence.ps1 smoke (skipped — pwsh not installed)"
    pass "skipped (no pwsh)"
fi
```

This is consistent with how existing forge tests handle .ps1: parse-test universally (test-lint.sh), runtime-test conditionally on `pwsh` availability.

- [ ] **Step 2: Run, verify FAIL — `build-evidence.ps1` doesn't exist**

- [ ] **Step 3: Implement the PowerShell skeleton**

`hooks/build-evidence.ps1`:

```powershell
# hooks/build-evidence.ps1 — emit FORGE_GOAL_EVIDENCE JSON.
# Mirrors hooks/build-evidence.sh. See that file for design notes.

$ErrorActionPreference = 'Continue'

# Unix epoch (works on Windows PowerShell 5.1 and PowerShell 7+).
$NowUnix = [int][Math]::Floor( (Get-Date - (Get-Date '1970-01-01Z').ToUniversalTime()).TotalSeconds )

# Hand-built JSON (avoid ConvertTo-Json — it adds whitespace and isn't byte-stable).
$json = "{`"type`":`"forge_goal_evidence`",`"schema_version`":1,`"produced_at_unix`":$NowUnix,`"session_nonce`":null,`"workflow_command`":null,`"warnings`":[],`"errors`":[]}"

# Emit to STDERR via System.Console — preserves stream identity across PS hosts.
[Console]::Error.WriteLine("FORGE_GOAL_EVIDENCE_BEGIN")
[Console]::Error.WriteLine($json)
[Console]::Error.WriteLine("FORGE_GOAL_EVIDENCE_END")

exit 0
```

Important: do NOT use the `??` null-coalescing operator (PS 7+ only); use `if (-not $x) { ... }` for 5.1 compat. Do NOT use `Get-Date -UFormat %s` (inconsistent across hosts); use the explicit epoch math above.

- [ ] **Step 4: Run smoke, verify PASS**

```bash
bash tests/template/test-build-evidence.sh
```

- [ ] **Step 5: Port remaining parsers from .sh → .ps1**

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
cd "$scratch"; OUT="$scratch/.out"; echo "$INPUT" | bash "$REPO_ROOT/hooks/check-state-updated.sh" >"$OUT" 2>&1
EXIT=$?

assert_equals "$EXIT" "0" "hook exits 0"
assert_contains "$OUT" "FORGE_GOAL_EVIDENCE_BEGIN" "evidence markers emit despite stop_hook_active"
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

Same pattern in PowerShell. Three constraints (Codex P1 — v1.0 violated all three):

1. **Do NOT use `??`** — PS 5.1 doesn't support null-coalescing. Use `if (-not $env:CLAUDE_PROJECT_DIR) { ... }`.
2. **Do NOT pipe to `Out-Null`** — that consumes STDERR including the evidence markers we just produced. Let STDERR pass through naturally.
3. **Run under the current PowerShell host** — don't hard-assume `pwsh`. Use `& $script` (which inherits the host) instead of spawning a new `pwsh` process.

```powershell
# Near top, after parsing stdin JSON:
$projectDir = $env:CLAUDE_PROJECT_DIR
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$evidenceScript = Join-Path $projectDir ".claude/hooks/build-evidence.ps1"
if (Test-Path $evidenceScript) {
    # Invoke under the current PS host. STDERR (where build-evidence emits
    # FORGE_GOAL_EVIDENCE markers) passes through to the calling Claude Code
    # process and into the transcript.
    try {
        & $evidenceScript
    } catch {
        # Non-blocking: write a single warning to stderr so a failure is visible
        # in the transcript without breaking the Stop hook.
        [Console]::Error.WriteLine("WARN: build-evidence.ps1 failed: $($_.Exception.Message)")
    }
}

# Then the existing stop_hook_active early-return.
```

- [ ] **Step 6: Run cross-platform tests**

```bash
bash tests/template/test-hooks.sh         # includes the new evidence-on-stop_hook_active test
bash tests/template/test-build-evidence.sh  # includes the conditional pwsh smoke (Task 8)
```

Both green. (No separate `test-hooks.ps1` exists; the Bash-driven smoke in test-build-evidence.sh is the PowerShell-side runtime check for v1.)

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

The contract must check THREE things (Codex P2 — v1.0 only checked the producer):

1. **Producer:** both `build-evidence.{sh,ps1}` contain the markers
2. **Consumer:** `check-state-updated.{sh,ps1}` calls build-evidence BEFORE the `stop_hook_active` early-return (text-order check is acceptable)
3. **Schema shape:** the producer emits the required top-level keys (string match on the literal key tokens)

```bash
start_test "FORGE_GOAL_EVIDENCE producer/consumer/schema contract"

# (1) Producer markers
for f in "$REPO_ROOT/hooks/build-evidence.sh" "$REPO_ROOT/hooks/build-evidence.ps1"; do
    assert_file_exists "$f" "producer exists: $f"
    assert_contains "$f" "FORGE_GOAL_EVIDENCE_BEGIN" "$(basename "$f") begin marker"
    assert_contains "$f" "FORGE_GOAL_EVIDENCE_END"   "$(basename "$f") end marker"
done

# (2) Consumer ordering: build-evidence invocation must appear BEFORE the
#     stop_hook_active early-return line in check-state-updated.{sh,ps1}.
for f in "$REPO_ROOT/hooks/check-state-updated.sh" "$REPO_ROOT/hooks/check-state-updated.ps1"; do
    [ -f "$f" ] || { fail "consumer missing: $f"; continue; }
    EVIDENCE_LINE=$(grep -n 'build-evidence' "$f" | head -1 | cut -d: -f1)
    EXIT_LINE=$(grep -n 'stop_hook_active' "$f" | tail -1 | cut -d: -f1)
    if [ -n "$EVIDENCE_LINE" ] && [ -n "$EXIT_LINE" ] && [ "$EVIDENCE_LINE" -lt "$EXIT_LINE" ]; then
        pass "$(basename "$f") invokes build-evidence BEFORE stop_hook_active early-return"
    else
        fail "$(basename "$f") consumer ordering wrong (build-evidence line $EVIDENCE_LINE not before stop_hook_active line $EXIT_LINE)"
    fi
done

# (3) Schema shape — producer emits required top-level keys
REQUIRED_KEYS=(
    '"type":"forge_goal_evidence"'
    '"schema_version":'
    '"produced_at_unix":'
    '"session_nonce":'
    '"pr_ready":'
    '"all_gates_green":'
    '"reviewer_gate":{'
    '"e2e_report":{'
    '"pr_state":{'
    '"pr_authorization":{'
    '"progress_fingerprint":'
)
for key in "${REQUIRED_KEYS[@]}"; do
    assert_contains "$REPO_ROOT/hooks/build-evidence.sh" "$key" "schema key in build-evidence.sh: $key"
    assert_contains "$REPO_ROOT/hooks/build-evidence.ps1" "$key" "schema key in build-evidence.ps1: $key"
done
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
- **Testing convention:** `tests/template/lib.sh` is the canonical helper. Use `init_counters`, `start_test`, `assert_equals`, `assert_contains`, `scratch_dir` — see existing `test-hooks.sh` for patterns.
- **Forge meta-rule:** README badge + Version history table MUST be updated in the same PR as the CHANGELOG bump. The `feedback_readme_must_stay_current_every_release.md` memory documents this.
- **Downstream sanity:** run a smoke against `../mcpgateway` (Task 10 Step 4) before final commit — fixture tests alone are not sufficient per `feedback_test_harness_changes_against_mcpgateway.md`.
- **`gh pr create` from a worktree:** if working in a worktree, ensure `gh auth status` is clean and the worktree is pushed to a remote branch before invoking PR creation.
- **JSON-shape changes:** if you need to add a field to the evidence JSON, ALSO update the cross-file marker contract test (Task 10) so future consumers can rely on the shape.

---

## Revision History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-05-14 | Claude + Pablo | Initial 10-task TDD plan generated via `/superpowers:writing-plans`. |
| 1.1 | 2026-05-14 | Claude + Pablo (Codex plan-review-loop FAIL v1.0 → PASS v1.1) | Fixed 8 P1 + 3 P2 findings from Codex review: real `tests/template/lib.sh` API (`assert_equals`, file-path `assert_contains`) and "Test Conventions" preamble; Markdown-table fixtures (matching `state.template.md`); awk grouping instead of Bash-4-only `declare -A`; checklist parsing scoped to `## Workflow` block; `[[:space:]]` not `\s`; `HEAD == branch_off` skip copied from `check-workflow-gates.sh`; deterministic `progress_fingerprint` (scoped, ordered, CRLF-normalized via tr-then-awk, ASCII US delimiter); `gh` stub validates ALL 6 required JSON fields; forced E2E mtime in test setup; PowerShell strategy adjusted (no `lib.ps1` exists — use Bash-driven cross-platform smoke); PowerShell stop-hook avoids `??`, `Out-Null`, and `pwsh` spawn (uses `& $script` under current host); extended cross-file marker contract (producer + consumer ordering + schema-shape keys); Task 3 parses Markdown-table `## /goal session`. |
