#!/usr/bin/env bash
# Stage-aware dual-host workflow contract. Runs real setup for installed surfaces.

set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

CAP="$REPO_ROOT/manifests/workflow-capabilities.tsv"
MANAGED="$REPO_ROOT/manifests/managed-v6.tsv"
stage=$(sed -n 's/^# conversion-stage:[[:space:]]*//p' "$CAP" | head -1)

start_test "conversion stage and owned capability matrix"
case "$stage" in core|development|complete) pass "declares bounded conversion stage: $stage" ;; *) fail "missing/invalid conversion stage" ;; esac

required_capabilities="prd-discuss prd-create new-feature fix-bug quick-fix review investigation council goal-composition review-pr-comments finish-branch release state-memory verify-app verify-e2e"
for capability in $required_capabilities; do
    if awk -F '\t' -v capability="$capability" '$1 == "forge-workflow" && $2 == capability && $4 == "forge" && $5 ~ /^\.forge\// && $7 == "claude,codex" {found=1} END {exit found ? 0 : 1}' "$CAP"; then
        pass "$capability has one dual-host Forge owner"
    else
        fail "$capability lacks a dual-host Forge owner"
    fi
done

start_test "goal behavior matrix is persistent and host neutral"
for behavior in "Objective/nonce creation" "Budget exhaustion" "Stuck warning" "User input or authorization" "Interrupted session" "Same-host resume" "Cross-host resume" "Candidate mutation" "Terminal status"; do
    assert_contains "$REPO_ROOT/docs/prds/forge-goal.md" "| $behavior |" "goal PRD covers $behavior"
done
assert_contains "$REPO_ROOT/docs/prds/forge-goal.md" "Native host counters may reset; the authoritative Forge ceiling and consumed count never reset" "resume never resets the Forge budget"

start_test "bounded stage rejects unresolved external runtime dependencies"
scan_files="commands/review.md commands/prd/discuss.md commands/prd/create.md agents/research-first.md agents/verify-app.md agents/verify-e2e.md rules/workflow.md rules/critical-rules.md"
if [[ "$stage" == development || "$stage" == complete ]]; then
    scan_files="$scan_files commands/new-feature.md commands/fix-bug.md commands/quick-fix.md"
fi
if [[ "$stage" == complete ]]; then
    scan_files="$scan_files commands/finish-branch.md commands/review-pr-comments.md commands/forge-goal.md skills/release/SKILL.template.md FORGE.template.md templates/adapters/CLAUDE.block.template.md templates/adapters/AGENTS.block.template.md"
fi
for relative in $scan_files; do
    file="$REPO_ROOT/$relative"
    assert_file_exists "$file" "converted surface exists: $relative"
    if [[ -f "$file" ]] && grep -nE 'superpowers:|pr-review-toolkit|/simplify|code-simplifier|(^|[^[:alnum:]_-])/codex([^[:alnum:]_-]|$)' "$file" >/dev/null 2>&1; then
        fail "$relative has an unresolved external runtime dependency"
    else
        pass "$relative uses only Forge-owned runtime contracts"
    fi
done

start_test "installed Claude and Codex adapters expose each converted workflow"
INSTALL=$(scratch_dir workflow-parity)
(cd "$INSTALL" && git init -q)
printf '{"name":"workflow-parity"}\n' > "$INSTALL/package.json"
LOG="$INSTALL/setup.log"
FORGE_ENGINE_IDENTITY_FIXTURE=1 run_setup "$INSTALL" "$LOG" -p WorkflowParity -t fullstack
assert_equals "$?" "0" "setup materializes dual-host workflow fixture"

converted="review prd/discuss prd/create"
if [[ "$stage" == development || "$stage" == complete ]]; then converted="$converted new-feature fix-bug quick-fix"; fi
if [[ "$stage" == complete ]]; then converted="$converted finish-branch review-pr-comments"; fi
for workflow in $converted; do
    canonical="$INSTALL/.forge/workflows/$workflow.md"
    claude_name=$(printf '%s' "$workflow" | tr '/' '-')
    case "$workflow" in prd/discuss) claude_path="$INSTALL/.claude/commands/prd/discuss.md"; codex_path="$INSTALL/.agents/skills/workflow-prd-discuss/SKILL.md" ;; prd/create) claude_path="$INSTALL/.claude/commands/prd/create.md"; codex_path="$INSTALL/.agents/skills/workflow-prd-create/SKILL.md" ;; *) claude_path="$INSTALL/.claude/commands/$workflow.md"; codex_path="$INSTALL/.agents/skills/workflow-$claude_name/SKILL.md" ;; esac
    assert_file_exists "$canonical" "canonical workflow installed: $workflow"
    assert_file_exists "$claude_path" "Claude adapter installed: $workflow"
    assert_file_exists "$codex_path" "Codex adapter installed: $workflow"
done

if [[ "$stage" == complete ]]; then
    start_test "native goal composition does not shadow custom host goals"
    assert_file_exists "$INSTALL/.forge/workflows/goal.md" "canonical Forge goal contract installed"
    assert_file_missing "$INSTALL/.claude/commands/goal.md" "Forge does not install a Claude goal command"
    assert_file_missing "$INSTALL/.agents/skills/goal" "Forge does not install a Codex goal skill"
    assert_contains "$INSTALL/CLAUDE.md" "native `/goal`" "Claude root composes its native goal"
    assert_contains "$INSTALL/AGENTS.md" "native `/goal`" "Codex root composes its native goal"

    COLLISION=$(scratch_dir workflow-goal-collision)
    (cd "$COLLISION" && git init -q)
    mkdir -p "$COLLISION/.claude/commands" "$COLLISION/.agents/skills/goal"
    printf 'custom claude goal\n' > "$COLLISION/.claude/commands/goal.md"
    printf 'custom codex goal\n' > "$COLLISION/.agents/skills/goal/SKILL.md"
    CLOG="$COLLISION/setup.log"
    FORGE_ENGINE_IDENTITY_FIXTURE=1 run_setup "$COLLISION" "$CLOG" -p GoalCollision -t fullstack
    assert_equals "$(cat "$COLLISION/.claude/commands/goal.md")" "custom claude goal" "custom Claude goal is preserved"
    assert_equals "$(cat "$COLLISION/.agents/skills/goal/SKILL.md")" "custom codex goal" "custom Codex goal is preserved"
    assert_contains "$CLOG" "RUNTIME_READY=BLOCKED host=claude" "Claude collision blocks host readiness"
    assert_contains "$CLOG" "rename .claude/commands/goal.md" "Claude collision prints exact rename guidance"
    assert_contains "$CLOG" "RUNTIME_READY=BLOCKED host=codex" "Codex collision blocks host readiness"
    assert_contains "$CLOG" "rename .agents/skills/goal/" "Codex collision prints exact rename guidance"
fi

report "test-workflow-parity.sh"
