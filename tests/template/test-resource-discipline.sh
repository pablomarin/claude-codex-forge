#!/usr/bin/env bash
# Resource-discipline contract for source and installed dual-host instruction chains.

set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

assert_loop_budget() {
    file="$1"
    label="$2"
    for contract in "one broad review" "one repair pass" "one closure review" \
        "named findings" "direct regressions" "second broad scan" \
        "reachable P0/P1" "one surgical repair"; do
        assert_contains "$file" "$contract" "$label carries $contract"
    done
}

start_test "canonical resource policy values correctness and finite resources"
for file in FORGE.template.md rules/principles.md; do
    path="$REPO_ROOT/$file"
    for contract in "Resource Discipline" "smallest correct solution" "developer time" \
        "session length" "tokens" "money" "perfection" "speculative" \
        "security" "data loss" "supported behavior" "acceptance criterion"; do
        assert_contains "$path" "$contract" "$file exposes $contract"
    done
done

start_test "review entry points enforce one bounded broad-repair-closure cycle"
for file in commands/new-feature.md commands/fix-bug.md commands/opinion.md; do
    assert_loop_budget "$REPO_ROOT/$file" "$file"
done
for file in commands/new-feature.md commands/fix-bug.md; do
    assert_contains "$REPO_ROOT/$file" "Before each plan-review iteration" \
        "$file applies the budget to plan findings"
    assert_contains "$REPO_ROOT/$file" "Before each final code-review iteration" \
        "$file applies the budget to code findings"
done

start_test "severity and mutation rules stop noise without hiding material failures"
POLICY="$REPO_ROOT/rules/workflow.md"
for contract in "P3" "cosmetic" "purely theoretical" "unchanged candidate" \
    "P2" "material" "rare" "data loss" "focused owning checks" \
    "complete aggregate" "final bytes" "Environment-only"; do
    assert_contains "$POLICY" "$contract" "workflow policy covers $contract"
done
assert_contains "$REPO_ROOT/rules/critical-rules.md" "RESOURCE DISCIPLINE" \
    "critical rules load resource discipline"
assert_contains "$REPO_ROOT/commands/quick-fix.md" "closure review" \
    "quick-fix inherits the closure stop rule"
assert_contains "$REPO_ROOT/commands/review-pr-comments.md" "closure review" \
    "review-pr-comments inherits the closure stop rule"

start_test "independent reviewer declares mode and cannot reopen closure scope"
assert_contains "$REPO_ROOT/agents/independent-reviewer.md" "review_mode=broad|closure" \
    "reviewer declares broad or closure mode"
assert_contains "$REPO_ROOT/agents/independent-reviewer.md" "named findings" \
    "reviewer closure is limited to named findings"
assert_contains "$REPO_ROOT/agents/independent-reviewer.md" "direct regressions" \
    "reviewer closure checks direct regressions"
assert_contains "$REPO_ROOT/agents/independent-reviewer.md" "second broad scan" \
    "reviewer cannot start another broad scan during closure"
assert_contains "$REPO_ROOT/FORGE.template.md" "FORGE_REVIEW_TRANSPORT_AUTHORIZED" \
    "canonical policy grants bounded configured-service reviewer transport"
assert_contains "$REPO_ROOT/FORGE.template.md" "solely because the candidate is private, sensitive, or contains unchanged tracked files" \
    "canonical policy prevents duplicate prompts for complete private candidate transport"
assert_contains "$REPO_ROOT/FORGE.template.md" "not an external mutation" \
    "canonical policy distinguishes reviewer transport from external mutation"
assert_contains "$REPO_ROOT/commands/opinion.md" "FORGE_REVIEW_TRANSPORT_AUTHORIZED" \
    "opinion workflow distinguishes reviewer transport from agent network capability"
assert_contains "$REPO_ROOT/agents/independent-reviewer.md" "FORGE_REVIEW_TRANSPORT_AUTHORIZED" \
    "native reviewer treats the supplied private candidate as authorized review input"
assert_contains "$REPO_ROOT/agents/independent-reviewer.md" "solely because the candidate is private, sensitive, or contains unchanged tracked files" \
    "native reviewer cannot reclassify complete private candidate transport as an authorization blocker"
assert_contains "$REPO_ROOT/settings/codex-config.template.toml" "network_access = false" \
    "standing reviewer transport does not grant blanket workspace network access"
assert_contains "$REPO_ROOT/templates/review-result.template.txt" "review_mode=broad|closure" \
    "result schema records the declared review mode"

start_test "installed Claude and Codex chains expose the same bounded policy"
INSTALL=$(scratch_dir resource-discipline)
(cd "$INSTALL" && git init -q)
printf '{"name":"resource-discipline"}\n' > "$INSTALL/package.json"
LOG="$INSTALL/setup.log"
FIXTURE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
PATH="$FIXTURE_PATH" FORGE_ENGINE_IDENTITY_FIXTURE=1 run_setup "$INSTALL" "$LOG" -p ResourceDiscipline -t fullstack
assert_equals "$?" "0" "setup materializes resource-discipline fixture"
for root in CLAUDE.md AGENTS.md; do
    assert_contains "$INSTALL/$root" ".forge/instructions.md" "$root loads canonical Forge instructions"
done
for file in .forge/instructions.md .forge/rules/principles.md; do
    assert_contains "$INSTALL/$file" "Resource Discipline" "$file installs the root policy"
done
for workflow in new-feature fix-bug opinion; do
    assert_loop_budget "$INSTALL/.forge/workflows/$workflow.md" "installed $workflow"
done
assert_contains "$INSTALL/.forge/agents/independent-reviewer.md" "review_mode=broad|closure" \
    "installed reviewer declares broad or closure mode"
assert_contains "$INSTALL/.forge/instructions.md" "FORGE_REVIEW_TRANSPORT_AUTHORIZED" \
    "installed canonical policy grants bounded configured-service reviewer transport"
assert_contains "$INSTALL/.forge/instructions.md" "solely because the candidate is private, sensitive, or contains unchanged tracked files" \
    "installed canonical policy prevents duplicate private-candidate prompts"
assert_contains "$INSTALL/.forge/instructions.md" "not an external mutation" \
    "installed canonical policy distinguishes reviewer transport from external mutation"
assert_contains "$INSTALL/.forge/agents/independent-reviewer.md" "FORGE_REVIEW_TRANSPORT_AUTHORIZED" \
    "installed reviewer consumes the standing transport authorization"
assert_contains "$INSTALL/.forge/agents/independent-reviewer.md" "solely because the candidate is private, sensitive, or contains unchanged tracked files" \
    "installed reviewer cannot reclassify complete private candidate transport as an authorization blocker"
assert_contains "$INSTALL/.forge/templates/review-result.template.txt" "review_mode=broad|closure" \
    "installed result schema records review mode"
assert_contains "$INSTALL/.claude/commands/opinion.md" ".forge/workflows/opinion.md" \
    "Claude opinion adapter loads the canonical review workflow"
assert_contains "$INSTALL/.agents/skills/opinion/SKILL.md" ".forge/workflows/opinion.md" \
    "Codex opinion adapter loads the canonical review workflow"

report "test-resource-discipline.sh"
