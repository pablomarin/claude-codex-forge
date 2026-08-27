#!/usr/bin/env bash
# Deterministic contract checks for skill-pressure qualification artifacts.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

FIXTURES="$REPO_ROOT/tests/template/fixtures/skill-pressure"
DECISIONS="$FIXTURES/candidate-decisions.tsv"
RUNNER="$REPO_ROOT/scripts/qualify-skill-pressure.sh"
RUNNER_PS="$REPO_ROOT/scripts/qualify-skill-pressure.ps1"
MANIFEST="$REPO_ROOT/manifests/managed-v6.tsv"

start_test "skill-pressure decisions reject duplicate workflow ownership"
assert_file_exists "$DECISIONS" "candidate decision fixture exists"
assert_file_exists "$RUNNER" "Bash qualification runner exists"
assert_file_exists "$RUNNER_PS" "PowerShell qualification runner exists"

if [[ -f "$DECISIONS" ]]; then
    expected=(
        brainstorming
        writing-plans
        systematic-debugging
        subagent-driven-development
        executing-plans
        requesting-review
        receiving-review
        simplifying-work
        verifying-work
    )

    header=$(head -n 1 "$DECISIONS")
    if [[ "$header" == $'candidate\tdecision\tlive_callsite\tcanonical_owner\trationale' ]]; then
        pass "candidate decision fixture has the canonical schema"
    else
        fail "candidate decision fixture has an invalid schema"
    fi

    for candidate in "${expected[@]}"; do
        row=$(awk -F '\t' -v candidate="$candidate" '$1 == candidate { count++; value=$0 } END { if (count == 1) print value; else exit 1 }' "$DECISIONS") || row=""
        if [[ -n "$row" ]]; then
            pass "$candidate has exactly one decision"
            IFS=$'\t' read -r name decision callsite owner rationale <<< "$row"
            [[ "$decision" == "REJECTED_DUPLICATE" ]] && pass "$candidate is rejected as duplicate" || fail "$candidate must be rejected as duplicate"
            [[ -n "$callsite" && -n "$owner" && -n "$rationale" ]] && pass "$candidate records live ownership evidence" || fail "$candidate is missing ownership evidence"
        else
            fail "$candidate must have exactly one decision"
        fi
    done

    extra=$(awk -F '\t' 'NR > 1 { seen[$1]++ } END { for (name in seen) if (seen[name] != 1) print name }' "$DECISIONS")
    [[ -z "$extra" ]] && pass "candidate decisions contain no duplicate rows" || fail "candidate decisions contain duplicate rows: $extra"
fi

start_test "duplicate candidates do not become managed portable skills"
for candidate in brainstorming writing-plans systematic-debugging subagent-driven-development executing-plans requesting-review receiving-review simplifying-work verifying-work; do
    if grep -qF "skills/$candidate/SKILL.template.md" "$MANIFEST"; then
        fail "$candidate must not be added to the managed manifest without a unique contract"
    else
        pass "$candidate is absent from the managed manifest"
    fi
done

start_test "existing portable skills and required references contain no host-specific tool invocation syntax"
for skill in "$REPO_ROOT/skills/release/SKILL.template.md" "$REPO_ROOT/skills/ui-design/SKILL.template.md" "$REPO_ROOT/skills/generate-image/SKILL.template.md" "$REPO_ROOT/skills/ui-design/references/21st-dev-components.md"; do
    assert_file_exists "$skill" "portable skill exists: $(basename "$(dirname "$skill")")"
    assert_not_contains "$skill" "WebFetch:" "$(basename "$(dirname "$skill")") does not name a host fetch tool"
    assert_not_contains "$skill" "Playwright subagent" "$(basename "$(dirname "$skill")") does not require a host-specific subagent"
    assert_not_contains "$skill" "MCP" "$(basename "$(dirname "$skill")") does not require an unresolved plugin/tool"
done

start_test "qualification runner validates attestation linkage without model access"
if grep -qF $'scripts/qualify-skill-pressure.sh\t.forge/bin/qualify-skill-pressure\tall\tshared\tproject' "$MANIFEST" && grep -qF $'scripts/qualify-skill-pressure.ps1\t.forge/bin/qualify-skill-pressure.ps1\tall\tshared\tproject' "$MANIFEST"; then
    pass "both qualification runners are materialized by the managed manifest"
else
    fail "both qualification runners must be materialized by the managed manifest"
fi
if bash "$RUNNER" --validate-fixture "$DECISIONS" >/dev/null; then
    pass "Bash runner validates deterministic fixture"
else
    fail "Bash runner must validate deterministic fixture"
fi

if command -v pwsh >/dev/null 2>&1 || command -v powershell >/dev/null 2>&1 || command -v powershell.exe >/dev/null 2>&1; then
    pass "PowerShell runtime is available for the owning Windows suite"
else
    pass "PowerShell runtime unavailable locally; source parity remains CI-owned"
fi
assert_contains "$RUNNER_PS" "ValidateFixture" "PowerShell runner accepts the deterministic validation mode"
assert_contains "$RUNNER_PS" "FORGE_SKILL_PRESSURE_COMMAND" "PowerShell runner requires explicit authenticated execution"

start_test "qualification runner rejects falsely clean RED and mismatched GREEN receipts"
PRESSURE_SCRATCH=$(scratch_dir skill-pressure)
SCENARIO="$PRESSURE_SCRATCH/scenario.md"
FAKE_RUNNER="$PRESSURE_SCRATCH/fake-pressure.sh"
printf 'scenario for qualification\n' > "$SCENARIO"
cat > "$FAKE_RUNNER" <<'EOF'
#!/usr/bin/env bash
set -eu
while [ "$#" -gt 0 ]; do
    case "$1" in
        --skill) skill="$2"; shift 2 ;;
        --phase) phase="$2"; shift 2 ;;
        --scenario) scenario="$2"; shift 2 ;;
        --red-attestation) red="$2"; shift 2 ;;
        *) shift ;;
    esac
done
sha=$(shasum -a 256 "$scenario" | awk '{print $1}')
case "${FORGE_SKILL_TEST_CASE:-}" in
    red-compliant) printf 'skill=%s\nphase=red\nscenario_sha256=%s\noutcome=COMPLIANT\nrationalization=unexpected clean result\n' "$skill" "$sha" ;;
    green-mismatched) printf 'skill=other-skill\nphase=green\nscenario_sha256=%s\noutcome=COMPLIANT\nprior_red_sha256=wrong\n' "$sha" ;;
    green-valid) printf 'skill=%s\nphase=green\nscenario_sha256=%s\noutcome=COMPLIANT\nprior_red_sha256=%s\n' "$skill" "$sha" "$(shasum -a 256 "$red" | awk '{print $1}')" ;;
    *) printf 'skill=%s\nphase=%s\nscenario_sha256=%s\noutcome=COMPLIANT\n' "$skill" "$phase" "$sha" ;;
esac
EOF
chmod +x "$FAKE_RUNNER"
if FORGE_SKILL_PRESSURE_COMMAND="$FAKE_RUNNER" FORGE_SKILL_TEST_CASE=red-compliant bash "$RUNNER" --skill fixture-skill --phase red --scenario "$SCENARIO" --attestation "$PRESSURE_SCRATCH/red.receipt" >/dev/null 2>&1; then
    fail "Bash runner must reject a falsely COMPLIANT RED receipt"
else
    pass "Bash runner rejects a falsely COMPLIANT RED receipt"
fi
printf 'skill=fixture-skill\nphase=red\nscenario_sha256=%s\noutcome=NONCOMPLIANT\nrationalization=without the skill the agent skipped the required contract\n' "$(shasum -a 256 "$SCENARIO" | awk '{print $1}')" > "$PRESSURE_SCRATCH/valid-red.receipt"
if FORGE_SKILL_PRESSURE_COMMAND="$FAKE_RUNNER" FORGE_SKILL_TEST_CASE=green-mismatched bash "$RUNNER" --skill fixture-skill --phase green --scenario "$SCENARIO" --attestation "$PRESSURE_SCRATCH/green.receipt" --red-attestation "$PRESSURE_SCRATCH/valid-red.receipt" >/dev/null 2>&1; then
    fail "Bash runner must reject a GREEN receipt with mismatched bindings"
else
    pass "Bash runner rejects a GREEN receipt with mismatched bindings"
fi
if FORGE_SKILL_PRESSURE_COMMAND="$FAKE_RUNNER" FORGE_SKILL_TEST_CASE=green-valid bash "$RUNNER" --skill fixture-skill --phase green --scenario "$SCENARIO" --attestation "$PRESSURE_SCRATCH/green-valid.receipt" --red-attestation "$PRESSURE_SCRATCH/valid-red.receipt" >/dev/null 2>&1; then
    pass "Bash runner accepts a GREEN receipt bound to the validated RED receipt"
else
    fail "Bash runner must accept a correctly bound GREEN receipt"
fi

report "test-skill-pressure-schema.sh"
