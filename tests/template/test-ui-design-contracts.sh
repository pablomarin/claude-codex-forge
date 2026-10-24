#!/usr/bin/env bash
# Cross-file UI design / independent browser QA contracts; no live visual qualification.
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters
ROLE="$REPO_ROOT/agents/forge-ui-qa.md"
VERIFIER="$REPO_ROOT/agents/verify-e2e.md"
SKILL="$REPO_ROOT/skills/ui-design/SKILL.template.md"
COMPONENTS="$REPO_ROOT/skills/ui-design/references/21st-dev-components.md"

start_test "21st discovery retrieves source before claiming component reuse"
assert_contains "$SKILL" 'retrieve and read its actual source before implementation' \
    "selected compatible components require source inspection in the skill entrypoint"
assert_contains "$SKILL" 'ask the user to sign in' \
    "entrypoint routes authentication limits to a login handoff"
for contract in \
    'ask the user once to sign in' \
    'continue work that does not depend on sign-in' \
    'Use available free component-code retrievals' \
    'shared across web, MCP and CLI' \
    'Do not spend copies on every search result' \
    'A copy prompt or install command alone is not source inspection' \
    'source retrieved and adapted' \
    'source inspected, not adopted' \
    'visual reference only' \
    'Do not infer exhaustion from a login screen'; do
    assert_contains "$COMPONENTS" "$contract" "component acquisition requires $contract"
done

start_test "browser QA is independent, bounded and evidence-based"
assert_file_exists "$ROLE" "managed forge-ui-qa role exists without replacing project ui-qa"
for contract in \
    'mcp__playwright__browser_take_screenshot' \
    'mcp__playwright__browser_resize' \
    'Read only this role file' \
    'Do not read source' \
    'Do not use shell' \
    'already signed-in' \
    'Writes allowed: no' \
    'documented design brief' \
    '1440x900' '390x844' \
    '10-second' 'progressive disclosure' \
    'Marketing, Product UI, and Trust-First' \
    'visual quality' 'usability' \
    'both scores must be at least 4' \
    'UI_QA_VERDICT: PASS | FAIL | BLOCKED' \
    'synthetic fixture' 'caller persists' \
    'reduced-motion' 'keyboard' 'transparency'; do
    assert_contains "$ROLE" "$contract" "UI QA requires $contract"
done
# Frontmatter tool boundary: Read permits loading the canonical role; browser actions
# permit rendered inspection. Shell, arbitrary JavaScript and product APIs must stay out.
if [[ -f "$ROLE" ]]; then
    capabilities=$(awk 'NR==1{next} /^---$/{exit} {print}' "$ROLE")
    if printf '%s\n' "$capabilities" | grep -Eq 'Bash|Write|Edit|browser_evaluate|browser_run_code'; then
        fail "UI QA grants an implementation/JavaScript tool"
    else
        pass "UI QA tool metadata excludes implementation and arbitrary JavaScript tools"
    fi
fi

start_test "existing E2E report aggregates independent same-candidate UI QA"
for contract in \
    'before every exit' \
    'candidate/design scope' \
    'unchanged full' \
    'same candidate' \
    'UI QA FAIL' \
    'BLOCKED, missing, stale, or wrong-candidate' \
    'Only UI QA PASS' \
    '## Independent UI QA' \
    'No new receipt'; do
    assert_contains "$VERIFIER" "$contract" "E2E aggregation requires $contract"
done
assert_not_contains "$VERIFIER" 'exit cleanly (not a failure' \
    "empty regression cannot bypass required UI QA"

start_test "both workflows design first, audit before freeze and audit final candidate"
for workflow in new-feature fix-bug; do
    file="$REPO_ROOT/commands/$workflow.md"
    for contract in \
        'Before UI implementation' \
        'ui-design' \
        'documented visual direction' \
        'fresh forge-ui-qa' \
        'before final freeze' \
        'final candidate' \
        'unchanged full UI QA subreport' \
        'candidate/design scope' \
        'workflow acceptance' \
        'hook-level visual'; do
        assert_contains "$file" "$contract" "$workflow requires $contract"
    done
done
report "UI design contracts"
