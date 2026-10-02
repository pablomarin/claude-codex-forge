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
assert_contains "$REPO_ROOT/commands/forge-goal.md" "explicit native Goal request is the human activation" \
    "native Goal action is the human activation"
assert_contains "$REPO_ROOT/commands/forge-goal.md" 'activation_count' \
    "goal workflow records monotonic activations"
assert_contains "$REPO_ROOT/commands/forge-goal.md" '20 * activation_count' \
    "goal workflow derives a fixed 20-turn tranche per activation"
assert_contains "$REPO_ROOT/commands/forge-goal.md" "sync the state's \`turn_count\`" \
    "goal continuation synchronizes state from the authoritative ledger before work"
assert_contains "$REPO_ROOT/commands/forge-goal.md" "state may lag the ledger by exactly one" \
    "goal contract documents the Stop-to-next-turn accounting boundary"
assert_contains "$MANAGED" $'canonical\thooks/lib/goal-ledger.sh\t.forge/hooks/lib/goal-ledger.sh' \
    "Bash repository ledger helper is installed"
assert_contains "$MANAGED" $'canonical\thooks/lib/goal-ledger.ps1\t.forge/hooks/lib/goal-ledger.ps1' \
    "PowerShell repository ledger helper is installed"
assert_contains "$REPO_ROOT/scripts/qualify-goal-feasibility.sh" 'interactive-native-goal-evidence-required' \
    "Bash qualifier does not treat a zero-exit host process as native Goal proof"
assert_contains "$REPO_ROOT/scripts/qualify-goal-feasibility.ps1" 'interactive-native-goal-evidence-required' \
    "PowerShell qualifier does not treat a zero-exit host process as native Goal proof"
assert_contains "$REPO_ROOT/scripts/qualify-goal-feasibility.sh" 'forge.native-goal-operator-evidence.v1' \
    "Bash qualifier accepts candidate-bound observed native Goal evidence"
assert_contains "$REPO_ROOT/scripts/qualify-goal-feasibility.ps1" 'forge.native-goal-operator-evidence.v1' \
    "PowerShell qualifier accepts candidate-bound observed native Goal evidence"
assert_contains "$REPO_ROOT/scripts/qualify-runtime-final.sh" '--claude-goal-evidence' \
    "Bash final qualifier routes Claude operator evidence explicitly"
assert_contains "$REPO_ROOT/scripts/qualify-runtime-final.sh" '--codex-goal-evidence' \
    "Bash final qualifier routes Codex operator evidence explicitly"
assert_contains "$REPO_ROOT/scripts/qualify-runtime-final.ps1" 'ClaudeGoalEvidence' \
    "PowerShell final qualifier routes Claude operator evidence explicitly"
assert_contains "$REPO_ROOT/scripts/qualify-runtime-final.ps1" 'CodexGoalEvidence' \
    "PowerShell final qualifier routes Codex operator evidence explicitly"

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
    start_test "full development workflows preserve portable continuity and candidate gates"
    for workflow in new-feature fix-bug; do
        file="$REPO_ROOT/commands/$workflow.md"
        for contract in "Last active host" "simultaneous editing" "base ref" "base SHA" "git add -A" "candidate" "authorization"; do
            assert_contains "$file" "$contract" "$workflow preserves $contract"
        done
        assert_contains "$file" "do not" "$workflow warns without adding a lock"
        for transition in "workflow-state.sh show" "workflow-state.sh activate" \
            "workflow-state.sh checkpoint" "--begin-review" \
            "before any discretionary investigation or tracked mutation" \
            "before production implementation" \
            "same candidate" "Any candidate mutation"; do
            assert_contains "$file" "$transition" "$workflow makes the $transition transition explicit"
        done
        assert_not_contains "$file" 'Read `.forge/local/state.md`' \
            "$workflow does not instruct a direct canonical state read"
        assert_not_contains "$file" 'Update `.forge/local/state.md`' \
            "$workflow does not instruct an unbounded canonical state write"
    done
    for workflow in new-feature fix-bug; do
        file="$REPO_ROOT/commands/$workflow.md"
        for contract in "TDD" "Preliminary" "simplification" "code-spec" "code-quality" "verify-app" "E2E" "mutation" ".forge/local/"; do
            assert_contains "$file" "$contract" "$workflow preserves $contract"
        done
    done
    assert_contains "$REPO_ROOT/commands/new-feature.md" "same-engine reviewer" "new-feature has automatic reviewer fallback"
    assert_contains "$REPO_ROOT/commands/fix-bug.md" "same-engine fallback" "fix-bug has automatic reviewer fallback"

    quick_fix="$REPO_ROOT/commands/quick-fix.md"
    for contract in "workflow-state.sh show" "workflow-state.sh activate" "workflow-state.sh checkpoint" 'worktree whose `HEAD`' "focused check directly" "at most three implementation paths" 'use `/fix-bug`' "required human authorization"; do
        assert_contains "$quick_fix" "$contract" "quick-fix preserves the direct-check contract: $contract"
    done
    assert_contains "$quick_fix" 'dispatches no `code-spec`' "quick-fix explicitly removes the spec reviewer"
    assert_contains "$quick_fix" '`code-quality`, `verify-app`, or `verify-e2e`' "quick-fix explicitly removes quality and verifier agents"
    assert_contains "$quick_fix" "no candidate-bound final receipt set" "quick-fix does not create final certification receipts"
    assert_not_contains "$quick_fix" "--begin-review" "quick-fix has no review-iteration transition"
fi

start_test "canonical policy routes workflow control rows through the bounded helper"
for surface in "$REPO_ROOT/rules/workflow.md" "$REPO_ROOT/FORGE.template.md"; do
    assert_contains "$surface" 'workflow-state.sh show' "$(basename "$surface") names bounded show"
    assert_contains "$surface" 'workflow-state.sh rebind' "$(basename "$surface") names bounded inactive rebind"
    assert_contains "$surface" 'workflow-state.sh activate' "$(basename "$surface") names bounded activation"
    assert_contains "$surface" 'workflow-state.sh checkpoint' "$(basename "$surface") names bounded checkpoint"
    assert_not_contains "$surface" 'Read `.forge/local/state.md`' \
        "$(basename "$surface") does not instruct a direct canonical state read"
done

start_test "project instructions preserve complete global policy and KISS/YAGNI"
for text in \
  'Apply KISS and YAGNI' \
  'Ground Your Claims' \
  'Host Neutrality' \
  'never save secrets or speculative conclusions' \
  'before context compaction or the end of substantial work'; do
    assert_contains "$REPO_ROOT/FORGE.template.md" "$text" \
        "project instructions preserve global policy: $text"
done
assert_contains "$REPO_ROOT/rules/principles.md" 'Apply KISS and YAGNI' \
    "principles name KISS and YAGNI"
assert_contains "$REPO_ROOT/rules/critical-rules.md" 'KISS AND YAGNI' \
    "critical rules name KISS and YAGNI"

start_test "development entrypoints load the shared startup boundary before workflow steps"
for workflow in new-feature fix-bug quick-fix; do
    entry=$(sed '/^## /q' "$REPO_ROOT/commands/$workflow.md")
    if printf '%s\n' "$entry" | grep -qF 'Startup boundary'; then
        pass "$workflow exposes activation-first startup at entry"
    else
        fail "$workflow buries activation behind discretionary work"
    fi
done
assert_contains "$REPO_ROOT/rules/workflow.md" '## Startup boundary' \
    "startup preflight has one canonical owner"
assert_contains "$REPO_ROOT/rules/workflow.md" 'Do not fabricate activation' \
    "a denied setup cannot be reported as an active workflow"
assert_contains "$REPO_ROOT/rules/workflow.md" 'prepared native worktree' \
    "startup supports native isolation without duplicating worktrees"
assert_contains "$REPO_ROOT/rules/workflow.md" 'worktree-lifecycle.sh adopt' \
    "startup canonicalizes a clean host-native worktree before activation"
for workflow in new-feature fix-bug; do
    assert_contains "$REPO_ROOT/commands/$workflow.md" 'worktree-lifecycle.sh adopt' \
        "$workflow adopts native isolation onto the Forge branch convention"
done
assert_contains "$REPO_ROOT/docs/guides/parallel-sessions.md" 'worktree-lifecycle.sh adopt' \
    "parallel-session guide documents native worktree adoption"
assert_contains "$REPO_ROOT/README.md" 'turn on **worktree** before sending the first prompt' \
    "README exposes the Claude Desktop isolation prerequisite at the workflow entrypoint"
assert_contains "$REPO_ROOT/rules/workflow.md" 'Quick-fix never creates a worktree' \
    "shared startup preserves the quick-fix no-worktree contract"
assert_contains "$REPO_ROOT/rules/workflow.md" 'Only `/new-feature` and `/fix-bug`' \
    "shared startup limits required worktree creation to isolated workflows"

if [[ "$stage" == complete ]]; then
    start_test "final cutover owns goal composition and removes transitional dependencies"
    assert_file_exists "$REPO_ROOT/commands/forge-goal.md" "canonical goal source exists"
    assert_file_missing "$REPO_ROOT/commands/codex.md" "transitional codex shim is removed"
    assert_file_exists "$REPO_ROOT/commands/opinion.md" "Forge uses the unreserved opinion command"
    assert_file_missing "$REPO_ROOT/commands/review.md" "Forge does not shadow either host's reserved review command"
    assert_contains "$MANAGED" $'canonical\tcommands/opinion.md\t.forge/workflows/opinion.md' "opinion has one canonical installed path"
    assert_contains "$MANAGED" $'adapter\ttemplates/adapters/claude-command.template.md\t.claude/commands/opinion.md' "Claude installs opinion, not review"
    assert_contains "$MANAGED" $'adapter\ttemplates/adapters/codex-skill.template.md\t.agents/skills/opinion/SKILL.md' "Codex installs the native opinion skill name"
    assert_contains "$MANAGED" $'canonical\tagents/forge-v6-producer.md\t.forge/agents/forge-v6-producer.md' "producer has one canonical installed path"
    assert_contains "$MANAGED" $'adapter\ttemplates/adapters/claude-agent.template.md\t.claude/agents/forge-v6-producer.md' "Claude installs the producer agent type"
    assert_contains "$MANAGED" $'adapter\ttemplates/adapters/codex-agent.template.toml\t.codex/agents/forge-v6-producer.toml' "Codex installs the producer agent type"
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
    for surface in FORGE.template.md commands/forge-goal.md; do
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
    claude_path="$INSTALL/.claude/commands/$workflow.md"
    codex_path="$INSTALL/.agents/skills/$claude_name/SKILL.md"
    assert_file_exists "$canonical" "canonical workflow installed: $workflow"
    assert_file_exists "$claude_path" "Claude adapter installed: $workflow"
    assert_file_exists "$codex_path" "Codex adapter installed: $workflow"
done

start_test "review-capable native workflow entries disclose transport before user invocation"
review_transport_disclosure='Invoking it authorizes only ordinary-review transport of the bounded immutable candidate, prompt, and evidence, including sensitive tracked or in-scope non-ignored files, to the configured Claude Code/Codex reviewer services. Investigation is excluded; investigate launches a separate full agent in the real worktree with normal config, tools, network, and write access under host approvals.'
for adapter in \
    .claude/commands/opinion.md \
    .claude/commands/new-feature.md \
    .claude/commands/fix-bug.md \
    .claude/commands/review-pr-comments.md \
    .claude/skills/council/SKILL.md \
    .agents/skills/opinion/SKILL.md \
    .agents/skills/new-feature/SKILL.md \
    .agents/skills/fix-bug/SKILL.md \
    .agents/skills/review-pr-comments/SKILL.md \
    .agents/skills/council/SKILL.md; do
    assert_contains "$INSTALL/$adapter" "$review_transport_disclosure" \
        "$adapter gives the user informed reviewer-transport notice before invocation"
done
assert_contains "$REPO_ROOT/scripts/materialize-adapters.ps1" "$review_transport_disclosure" \
    "PowerShell materializer mirrors the informed reviewer-transport disclosure"
for canonical_path in \
    .forge/workflows/opinion.md \
    .forge/workflows/new-feature.md \
    .forge/workflows/fix-bug.md \
    .forge/workflows/review-pr-comments.md \
    .forge/skills/council/SKILL.template.md; do
    assert_contains "$REPO_ROOT/scripts/materialize-adapters.sh" "$canonical_path" \
        "Bash disclosure selector includes $canonical_path"
    assert_contains "$REPO_ROOT/scripts/materialize-adapters.ps1" "$canonical_path" \
        "PowerShell disclosure selector includes $canonical_path"
done
for adapter in \
    .claude/commands/prd/discuss.md \
    .claude/commands/finish-branch.md \
    .claude/commands/quick-fix.md \
    .agents/skills/prd-discuss/SKILL.md \
    .agents/skills/finish-branch/SKILL.md \
    .agents/skills/quick-fix/SKILL.md; do
    assert_not_contains "$INSTALL/$adapter" "$review_transport_disclosure" \
        "$adapter does not claim ordinary-review transport consent"
done

assert_file_exists "$INSTALL/.forge/agents/forge-v6-producer.md" "canonical producer agent installed"
assert_file_exists "$INSTALL/.claude/agents/forge-v6-producer.md" "Claude producer agent installed"
assert_file_exists "$INSTALL/.codex/agents/forge-v6-producer.toml" "Codex producer agent installed"

start_test "installed Claude agent capabilities preserve canonical roles and restricted defaults"
agent_policy() {
    awk -v key="$2" '
        /^---\r?$/ { boundary++; next }
        boundary != 1 { next }
        /^[^[:space:]]/ { active=($0 ~ ("^" key ":")) }
        active { print }
    ' "$1"
}
assert_equals "$(agent_policy "$INSTALL/.claude/agents/forge-v6-producer.md" tools)" \
    "$(agent_policy "$INSTALL/.forge/agents/forge-v6-producer.md" tools)" \
    "producer adapter retains canonical tools including Edit and Write"
assert_equals "$(agent_policy "$INSTALL/.claude/agents/independent-reviewer.md" tools)" \
    "$(agent_policy "$INSTALL/.forge/agents/independent-reviewer.md" tools)" \
    "explicit read-only reviewer tool restriction is preserved"
for role in verify-app research-first; do
    assert_equals "$(agent_policy "$INSTALL/.claude/agents/$role.md" tools)" \
        'tools: "Read, Grep, Glob, Bash"' "$role keeps its existing restricted default"
done
assert_equals "$(agent_policy "$INSTALL/.claude/agents/verify-e2e.md" tools)" "" \
    "E2E verifier does not exclude host browser tools with a fixed builtin allowlist"
assert_contains "$INSTALL/.claude/agents/verify-e2e.md" 'disallowedTools:' \
    "E2E verifier explicitly restricts implementation-edit tools"
for denied in Write Edit NotebookEdit; do
    if agent_policy "$INSTALL/.claude/agents/verify-e2e.md" disallowedTools | grep -qw "$denied"; then
        pass "E2E verifier denies $denied"
    else
        fail "E2E verifier does not deny $denied"
    fi
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
    assert_contains "$INSTALL/CLAUDE.md" '@AGENTS.md' "Claude root imports the canonical adapter"
    assert_contains "$INSTALL/AGENTS.md" '.forge/instructions.md' "Codex root discovers canonical project policy"
    assert_contains "$LOG" "RUNTIME_READY=BLOCKED host=claude" "Claude collision blocks host readiness"
    assert_contains "$LOG" "rename .claude/commands/goal.md" "Claude collision prints exact rename guidance"
    assert_contains "$LOG" "RUNTIME_READY=BLOCKED host=codex" "Codex collision blocks host readiness"
    assert_contains "$LOG" "rename .agents/skills/goal/" "Codex collision prints exact rename guidance"
fi

report "test-workflow-parity.sh"
