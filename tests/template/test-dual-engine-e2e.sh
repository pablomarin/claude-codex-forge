#!/usr/bin/env bash
# Compact Task 11 integration contract. The acceptance rows map to their
# owning suites; only the install -> declared-host -> fallback seam runs here.
set -u
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

coverage_rows() {
    cat <<'EOF'
UC01	authoritative-legacy-refresh	test-full-refresh.sh,test-setup.sh
UC02	global-dual-host-setup	test-setup.sh,test-full-refresh.sh
UC03	clean-install-one-engine	test-setup.sh,test-agent-dispatch.sh
UC04	four-review-modes	test-agent-dispatch.sh,test-build-evidence.sh
UC05	cross-host-resume	test-state-roundtrip.sh,test-agent-dispatch.sh
UC06	artifact-invalidation	test-build-evidence.sh,test-hooks.sh
UC07	council-healthy	test-council-dispatch.sh
UC08	council-degraded	test-council-dispatch.sh
UC09	council-overrides	test-council-dispatch.sh
UC10	investigation-authorization	test-agent-dispatch.sh,test-authorized-action.sh
UC11	goal-parity-resume	test-goal-feasibility.sh,test-state-roundtrip.sh,test-hooks.sh
UC12	failed-migration-honesty	test-full-refresh.sh
UC13	cross-worktree-evidence	test-state-roundtrip.sh,test-build-evidence.sh
UC14	materialized-versus-ready	test-setup.sh,test-runtime-identity.sh
UC15	native-goal-collision	test-workflow-parity.sh,test-goal-feasibility.sh
UC16	mutation-free-finalization	test-build-evidence.sh,test-hooks.sh
UC17	linked-worktree-codex-hooks	test-setup.sh,test-hooks.sh
EOF
}

if [[ "${1:-}" == "--list-coverage" ]]; then
    coverage_rows
    exit 0
fi

start_test "17 acceptance use cases map once to existing owning suites"
MAP=$(scratch_dir dual-engine-map)/coverage.tsv
coverage_rows > "$MAP"
assert_equals "$(wc -l < "$MAP" | tr -d ' ')" "17" "coverage map has 17 rows"
assert_equals "$(cut -f1 "$MAP" | LC_ALL=C sort -u | wc -l | tr -d ' ')" "17" "coverage ids are unique"
missing=0
while IFS=$'\t' read -r use_case _ owners; do
    case "$use_case" in UC0[1-9]|UC1[0-7]) ;; *) fail "invalid use-case id: $use_case"; missing=1; continue ;; esac
    old_ifs=$IFS; IFS=,; set -- $owners; IFS=$old_ifs
    for owner in "$@"; do
        if [[ -f "$REPO_ROOT/tests/template/$owner" ]]; then
            :
        else
            fail "$use_case owner missing: $owner"
            missing=1
        fi
    done
done < "$MAP"
[[ "$missing" -eq 0 ]] && pass "every mapped owner is an existing focused suite"
assert_file_exists "$REPO_ROOT/tests/template/test-dual-engine-e2e.ps1" "PowerShell integration mirror exists"
assert_contains "$REPO_ROOT/tests/template/run-all.sh" 'test-dual-engine-e2e.sh' "Bash runner registers the integration suite once"

start_test "one installed seam reaches visible fresh same-engine fallback without state mutation"
S=$(scratch_dir dual-engine-seam)
P="$S/project"; H="$S/home"; B="$S/bin"
mkdir -p "$P" "$H" "$B"
git -C "$P" init -q
git -C "$P" config user.email forge@example.invalid
git -C "$P" config user.name Forge
printf 'base\n' > "$P/app.txt"
git -C "$P" add app.txt
git -C "$P" commit -qm base
cat > "$B/claude" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  --version) printf '2.1.237 (Claude Code)\\n'; exit 0 ;;
  --help) printf '%s\\n' '-p --safe-mode --strict-mcp-config --mcp-config --settings --setting-sources --tools --permission-mode --add-dir --model --effort --output-format --no-session-persistence --session-id --resume'; exit 0 ;;
esac
exec "$REPO_ROOT/tests/template/fixtures/fake-engines/claude" "\$@"
EOF
chmod +x "$B/claude"
(cd "$P" && PATH="$B:/usr/bin:/bin" HOME="$H" FORGE_ENGINE_IDENTITY_FIXTURE=1 \
    "$REPO_ROOT/setup.sh" -p Integration -t fullstack) > "$S/setup.log" 2>&1
assert_equals "$?" "0" "clean setup materializes the seam fixture"
assert_contains "$S/setup.log" 'INSTALLATION: MATERIALIZED' "setup separates materialization from readiness"
assert_contains "$S/setup.log" 'codex RUNTIME_READY: BLOCKED' "missing preferred engine is reported honestly"
git -C "$P" add -A
git -C "$P" commit -qm installed
base=$(git -C "$P" rev-parse HEAD)
branch=$(git -C "$P" branch --show-current)
common=$(git -C "$P" rev-parse --git-common-dir); common=$(cd "$P" && cd "$common" && pwd -P)
mkdir -p "$P/.forge/local/reviews"
cat > "$P/.forge/local/state.md" <<EOF
<!-- forge:state-schema v6 -->
# Project State

## Identity

| Field | Value |
| --- | --- |
| Worktree root | $(cd "$P" && pwd -P) |
| Git common directory | $common |
| Last active host | claude |
| Workflow base ref | refs/heads/$branch |
| Workflow base SHA | $base |

## Workflow

## Receipts
| Field | Value |
| Review iteration | 1 |
EOF
printf 'Review the installed seam.\n' > "$P/.forge/local/reviews/prompt.txt"
dispatcher="$P/.forge/hooks/lib/agent-dispatch.sh"
context="$P/.forge/hooks/lib/host-context.sh"
before=$(hash_file "$P/.forge/local/state.md")
(cd "$P" && PATH="$B:/usr/bin:/bin" HOME="$H" FORGE_DISPATCH_TEST_MODE=1 FORGE_TEST_DISABLE_ENGINE=codex \
    bash "$context" launch --host claude -- "$dispatcher" run --engine auto \
    --fallback-policy automatic --role general --profile review --artifact git:working-tree \
    --workflow-base-sha "$base" --workflow-base-ref "refs/heads/$branch" \
    --prompt-file "$P/.forge/local/reviews/prompt.txt" \
    --output "$P/.forge/local/reviews/result.txt" --timeout-seconds 2) > "$S/dispatch.log" 2>&1
assert_equals "$?" "0" "installed dispatcher completes the same-engine fallback"
assert_contains "$S/dispatch.log" 'visible fallback' "fallback is visible to the developer"
receipt=$(find "$P/.forge/local/reviews" -type f -name '*.receipt' | LC_ALL=C sort | tail -1)
assert_contains "$receipt" 'first_attempted_engine=codex' "receipt records the unavailable preferred engine"
assert_contains "$receipt" 'actual_engine=claude' "receipt records the fresh same-engine reviewer"
assert_contains "$receipt" 'fallback=true' "receipt records degraded topology"
assert_hash_equals "$P/.forge/local/state.md" "$before" "reviewer does not mutate canonical workflow state"
assert_file_missing "$H/.forge/host-contexts" "installed review needs no host authority directory"

(cd "$P" && PATH="$B:/usr/bin:/bin" HOME="$H" FORGE_DISPATCH_TEST_MODE=1 FORGE_TEST_DISABLE_ENGINE=codex \
    bash "$context" launch --host codex -- "$dispatcher" run --engine auto \
    --fallback-policy automatic --role general --profile review --artifact git:working-tree \
    --workflow-base-sha "$base" --workflow-base-ref "refs/heads/$branch" \
    --prompt-file "$P/.forge/local/reviews/prompt.txt" \
    --output "$P/.forge/local/reviews/codex-main-result.txt" --timeout-seconds 2) >/dev/null 2>&1
assert_equals "$?" "0" "a later Codex-declared session reaches the same installed project"
if grep -l '^main_host=codex$' "$P/.forge/local/reviews/"*.receipt >/dev/null 2>&1; then
    pass "later review records Codex as declared routing host"
else
    fail "later review omitted Codex declared routing metadata"
fi

(cd "$P" && PATH="$B:/usr/bin:/bin" HOME="$H" FORGE_DISPATCH_TEST_MODE=1 FORGE_TEST_DISABLE_ENGINE=codex \
    bash "$context" launch --host claude -- "$dispatcher" run --engine claude --fallback-policy none --role general --profile review --artifact git:working-tree \
    --workflow-base-sha "$base" --workflow-base-ref "refs/heads/$branch" --prompt-file "$P/.forge/local/reviews/prompt.txt" --output "$P/.forge/local/reviews/concurrent-claude.txt" --timeout-seconds 2 >"$S/concurrent-claude.log" 2>&1; echo $? > "$S/concurrent-claude.rc") & claude_pid=$!
(cd "$P" && PATH="$B:/usr/bin:/bin" HOME="$H" FORGE_DISPATCH_TEST_MODE=1 FORGE_TEST_DISABLE_ENGINE=codex \
    bash "$context" launch --host codex -- "$dispatcher" run --engine claude --fallback-policy none --role general --profile review --artifact git:working-tree \
    --workflow-base-sha "$base" --workflow-base-ref "refs/heads/$branch" --prompt-file "$P/.forge/local/reviews/prompt.txt" --output "$P/.forge/local/reviews/concurrent-codex.txt" --timeout-seconds 2 >"$S/concurrent-codex.log" 2>&1; echo $? > "$S/concurrent-codex.rc") & codex_pid=$!
wait "$claude_pid"; wait "$codex_pid"
assert_equals "$(cat "$S/concurrent-claude.rc")" "0" "concurrent Claude-declared review succeeds"
assert_equals "$(cat "$S/concurrent-codex.rc")" "0" "concurrent Codex-declared review succeeds"
assert_file_missing "$H/.forge/host-contexts" "concurrent reviews create no shared host authority"

report "test-dual-engine-e2e.sh"
