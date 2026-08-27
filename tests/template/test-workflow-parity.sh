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
scan_files="commands/opinion.md commands/prd/discuss.md commands/prd/create.md agents/research-first.md agents/verify-app.md agents/verify-e2e.md rules/workflow.md rules/critical-rules.md"
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

if [[ "$stage" == development || "$stage" == complete ]]; then
    start_test "development workflows preserve portable continuity and candidate gates"
    for workflow in new-feature fix-bug quick-fix; do
        file="$REPO_ROOT/commands/$workflow.md"
        for contract in "Last active host" "simultaneous editing" "base ref" "base SHA" "git add -A" "candidate" "authorization"; do
            assert_contains "$file" "$contract" "$workflow preserves $contract"
        done
        assert_contains "$file" "do not" "$workflow warns without adding a lock"
    done
    for workflow in new-feature fix-bug; do
        file="$REPO_ROOT/commands/$workflow.md"
        for contract in "TDD" "Preliminary" "simplification" "code-spec" "code-quality" "verify-app" "E2E" "mutation" ".forge/local/"; do
            assert_contains "$file" "$contract" "$workflow preserves $contract"
        done
    done
    assert_contains "$REPO_ROOT/commands/new-feature.md" "same-engine reviewer" "new-feature has automatic reviewer fallback"
    assert_contains "$REPO_ROOT/commands/fix-bug.md" "same-engine fallback" "fix-bug has automatic reviewer fallback"
    assert_contains "$REPO_ROOT/commands/quick-fix.md" "falls back automatically" "quick-fix has automatic reviewer fallback"
fi

if [[ "$stage" == complete ]]; then
    start_test "final cutover owns goal composition and removes transitional dependencies"
    assert_file_exists "$REPO_ROOT/commands/forge-goal.md" "canonical goal source exists"
    assert_file_missing "$REPO_ROOT/commands/codex.md" "transitional codex shim is removed"
    assert_file_exists "$REPO_ROOT/commands/opinion.md" "Forge uses the unreserved opinion command"
    assert_file_missing "$REPO_ROOT/commands/review.md" "Forge does not shadow either host's reserved review command"
    assert_contains "$MANAGED" $'canonical\tcommands/opinion.md\t.forge/workflows/opinion.md' "opinion has one canonical installed path"
    assert_contains "$MANAGED" $'adapter\ttemplates/adapters/claude-command.template.md\t.claude/commands/opinion.md' "Claude installs opinion, not review"
    assert_contains "$MANAGED" $'adapter\ttemplates/adapters/codex-skill.template.md\t.agents/skills/workflow-opinion/SKILL.md' "Codex installs opinion, not review"
    if awk -F '\t' '$3 == ".claude/commands/review.md" || $3 == ".agents/skills/workflow-review/SKILL.md" {found=1} END {exit found ? 0 : 1}' "$MANAGED"; then
        fail "managed manifest shadows a host-reserved review command"
    else
        pass "managed manifest leaves host-reserved review commands untouched"
    fi
    assert_contains "$MANAGED" $'canonical\tcommands/forge-goal.md\t.forge/workflows/goal.md' "goal has one canonical installed path"
    assert_contains "$MANAGED" $'protected\t-\t.claude/commands/goal.md' "Claude native goal collision is protected"
    assert_contains "$MANAGED" $'protected\t-\t.agents/skills/goal/SKILL.md' "Codex native goal collision is protected"
    for retired in '.forge/workflows/codex.md' '.claude/commands/codex.md' '.agents/skills/workflow-codex/SKILL.md'; do
        if awk -F '\t' -v retired="$retired" '$1 == "tombstone" && $3 == retired && $7 == "forge-proven-legacy" {found=1} END {exit found ? 0 : 1}' "$MANAGED"; then
            pass "retired codex surface has a provenance-aware tombstone: $retired"
        else
            fail "retired codex surface lacks a provenance-aware tombstone: $retired"
        fi
    done
    for settings in settings/settings.template.json settings/settings-windows.template.json; do
        assert_not_contains "$REPO_ROOT/$settings" 'superpowers@claude-plugins-official' "$settings removes the Superpowers dependency"
        assert_not_contains "$REPO_ROOT/$settings" 'pr-review-toolkit@claude-plugins-official' "$settings removes the PR toolkit dependency"
        assert_not_contains "$REPO_ROOT/$settings" '"type": "prompt"' "$settings uses receipt-only subagent evaluation"
    done
    for surface in FORGE.template.md templates/adapters/CLAUDE.block.template.md templates/adapters/AGENTS.block.template.md commands/forge-goal.md; do
        assert_contains "$REPO_ROOT/$surface" 'native `/goal`' "$surface composes native goal"
        assert_contains "$REPO_ROOT/$surface" 'FORGE_GOAL_BUDGET_EXHAUSTED' "$surface consumes budget exhaustion"
        assert_contains "$REPO_ROOT/$surface" 'FORGE_GOAL_STUCK_WARNING' "$surface consumes stuck warning"
    done
    for workflow in commands/finish-branch.md commands/review-pr-comments.md skills/release/SKILL.template.md; do
        assert_contains "$REPO_ROOT/$workflow" '.forge/' "$workflow uses canonical Forge state or evidence"
        assert_contains "$REPO_ROOT/$workflow" 'human authorization' "$workflow preserves external-mutation authority"
    done
    for workflow in new-feature fix-bug opinion; do
        assert_contains "$REPO_ROOT/commands/$workflow.md" "one broad review" "$workflow exposes the bounded review-loop budget"
        assert_contains "$REPO_ROOT/commands/$workflow.md" "one closure review" "$workflow exposes closure review"
    done
    if grep -R -nF -- '`/codex`' "$REPO_ROOT/commands" "$REPO_ROOT/rules" "$REPO_ROOT/agents" "$REPO_ROOT/skills" >/dev/null 2>&1; then
        fail "a live workflow/rule/agent/skill still invokes the transitional /codex command"
    else
        pass "no live workflow/rule/agent/skill invokes transitional /codex"
    fi
fi

start_test "installed Claude and Codex adapters expose each converted workflow"
INSTALL=$(scratch_dir workflow-parity)
(cd "$INSTALL" && git init -q)
printf '{"name":"workflow-parity"}\n' > "$INSTALL/package.json"
if [[ "$stage" == complete ]]; then
    mkdir -p "$INSTALL/.claude/commands" "$INSTALL/.agents/skills/goal"
    printf 'custom claude goal\n' > "$INSTALL/.claude/commands/goal.md"
    printf 'custom codex goal\n' > "$INSTALL/.agents/skills/goal/SKILL.md"
fi
LOG="$INSTALL/setup.log"
# Keep this fixture deterministic and offline: identity selection is injected, so installed
# host CLIs must not be probed by setup's configuration validator.
FIXTURE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
PATH="$FIXTURE_PATH" FORGE_ENGINE_IDENTITY_FIXTURE=1 run_setup "$INSTALL" "$LOG" -p WorkflowParity -t fullstack
assert_equals "$?" "0" "setup materializes dual-host workflow fixture"

converted="opinion prd/discuss prd/create"
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
    assert_equals "$(cat "$INSTALL/.claude/commands/goal.md")" "custom claude goal" "custom Claude goal is preserved"
    assert_equals "$(cat "$INSTALL/.agents/skills/goal/SKILL.md")" "custom codex goal" "custom Codex goal is preserved"
    if awk -F '\t' '$1 == "adapter" && ($3 == ".claude/commands/goal.md" || $3 == ".agents/skills/goal/SKILL.md") {found=1} END {exit found ? 0 : 1}' "$MANAGED"; then
        fail "managed manifest shadows a native goal adapter"
    else
        pass "managed manifest installs no native goal adapter"
    fi
    assert_not_contains "$INSTALL/.forge/installed-files.tsv" $'.claude/commands/goal.md\t' "custom Claude goal is not Forge-owned"
    assert_not_contains "$INSTALL/.forge/installed-files.tsv" $'.agents/skills/goal/SKILL.md\t' "custom Codex goal is not Forge-owned"
    assert_contains "$INSTALL/CLAUDE.md" 'native `/goal`' "Claude root composes its native goal"
    assert_contains "$INSTALL/AGENTS.md" 'native `/goal`' "Codex root composes its native goal"
    assert_contains "$LOG" "RUNTIME_READY=BLOCKED host=claude" "Claude collision blocks host readiness"
    assert_contains "$LOG" "rename .claude/commands/goal.md" "Claude collision prints exact rename guidance"
    assert_contains "$LOG" "RUNTIME_READY=BLOCKED host=codex" "Codex collision blocks host readiness"
    assert_contains "$LOG" "rename .agents/skills/goal/" "Codex collision prints exact rename guidance"
fi

report "test-workflow-parity.sh"
