#!/usr/bin/env bash
# Runtime contract for the authoritative Forge v5 -> v6 full-refresh transaction.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

run_refresh() {
    local target="$1" log="$2"
    local physical_target
    shift 2
    mkdir -p "$target/.fakehome"
    physical_target=$(cd "$target" && pwd -P)
    (cd "$physical_target" && HOME="$physical_target/.fakehome" "$REPO_ROOT/setup.sh" "$@") >"$log" 2>&1
}

make_git_repo() {
    local target="$1"
    mkdir -p "$target"
    git -C "$target" init -q
}

write_active_v5_state() {
    local target="$1" token="${2:-V5_CHECKPOINT_TOKEN}"
    mkdir -p "$target/.claude/local"
    sed "s/(what you're actively working on)/$token/" "$REPO_ROOT/state.template.md" \
        | sed '1{/forge:state-schema v6/d;}' > "$target/.claude/local/state.md"
}

snapshot_project() {
    local root="$1"
    (
        cd "$root" || exit 1
        find . -path './.git' -prune -o -type f -print \
            | LC_ALL=C sort \
            | while IFS= read -r file; do
                printf '%s\t%s\n' "$file" "$(hash_file "$file")"
            done
    )
}

start_test "full-refresh flags are explicit and force/full-refresh are incompatible"
S1=$(scratch_dir full-refresh-flags)
make_git_repo "$S1"
"$REPO_ROOT/setup.sh" --help >"$S1/help" 2>&1
assert_contains "$S1/help" "-F, --full-refresh" "Bash help documents authoritative full refresh"
run_refresh "$S1" "$S1/conflict" -f -F
assert_equals "$?" "1" "Bash rejects combining force and full refresh"
assert_contains "$S1/conflict" "cannot be combined" "flag conflict is explained"

start_test "full-refresh preview uses the real planner without target writes"
S1P=$(scratch_dir full-refresh-preview)
make_git_repo "$S1P"
mkdir -p "$S1P/.claude/hooks" "$S1P/.fakehome"
printf '5.61\n' > "$S1P/.claude/.forge-version"
git -C "$REPO_ROOT" show cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:hooks/session-start.sh \
    > "$S1P/.claude/hooks/session-start.sh"
write_active_v5_state "$S1P" "DRY_RUN_STATE"
preview_log="${S1P}.preview.log"
before=$(snapshot_project "$S1P")
run_refresh "$S1P" "$preview_log" -F --dry-run
assert_equals "$?" "0" "exact v5 preview is ready"
after=$(snapshot_project "$S1P")
assert_equals "$after" "$before" "preview leaves every target file byte-identical"
assert_file_missing "$S1P/.forge/version" "preview writes no v6 stamp"
assert_file_missing "$S1P/.forge/local/migration-guard" "preview writes no transaction guard"
assert_contains "$preview_log" "UPGRADE: READY" "preview has a final readiness summary"
assert_contains "$preview_log" "ACTIVE_FORGE: unchanged" "preview does not claim mutation"

S1G=$(scratch_dir full-refresh-preview-global)
make_git_repo "$S1G"
mkdir -p "$S1G/.fakehome/.claude"
printf '5.61\n' > "$S1G/.fakehome/.claude/.forge-version"
global_log="${S1G}.preview.log"
before_global=$(snapshot_project "$S1G/.fakehome")
run_refresh "$S1G" "$global_log" -g -F --dry-run
assert_equals "$?" "0" "global exact v5 preview is ready"
after_global=$(snapshot_project "$S1G/.fakehome")
assert_equals "$after_global" "$before_global" "global preview leaves HOME byte-identical"
assert_file_missing "$S1G/.fakehome/.forge/version" "global preview writes no v6 stamp"

run_refresh "$S1P" "${S1P}.dry-run-only.log" --dry-run
assert_equals "$?" "1" "dry-run without full refresh is rejected"
run_refresh "$S1P" "${S1P}.dry-run-conflict.log" -f -F --dry-run
assert_equals "$?" "1" "force and full-refresh preview remain incompatible"
run_refresh "$S1P" "${S1P}.force-v5.log" -f
assert_equals "$?" "1" "ordinary force refuses a stamped v5 harness"
assert_contains "${S1P}.force-v5.log" "-F --dry-run" "v5 force refusal points to read-only preview first"

start_test "state-path helper prefers validated v6 and falls back only for unmigrated v5"
S2=$(scratch_dir state-path)
mkdir -p "$S2/.claude/local" "$S2/.forge/local"
printf 'legacy\n' > "$S2/.claude/local/state.md"
# shellcheck disable=SC1090
source "$REPO_ROOT/hooks/lib/state-path.sh"
S2_PHYSICAL=$(cd "$S2" && pwd -P)
assert_equals "$(forge_state_path "$S2" read)" "$S2_PHYSICAL/.claude/local/state.md" \
    "unmigrated install reads v5 state"
printf '<!-- forge:state-schema v6 -->\ncanonical\n' > "$S2/.forge/local/state.md"
printf '6\n' > "$S2/.forge/version"
assert_equals "$(forge_state_path "$S2" read)" "$S2_PHYSICAL/.forge/local/state.md" \
    "validated v6 state wins when both paths exist"
assert_equals "$(forge_state_path "$S2" write)" "$S2_PHYSICAL/.forge/local/state.md" \
    "all v6 writes resolve to canonical state"
printf 'corrupt\n' > "$S2/.forge/local/state.md"
forge_state_path "$S2" read >"$S2/out" 2>"$S2/err"
assert_equals "$?" "1" "invalid canonical state does not downgrade to legacy"
assert_contains "$S2/err" "invalid Forge v6 state" "invalid canonical state is diagnosable"
rm -f "$S2/.forge/local/state.md"
: > "$S2/.forge/version"
forge_state_path "$S2" read > "$S2/empty-version-out" 2> "$S2/empty-version-err"
assert_equals "$?" "1" "empty Forge version never downgrades to legacy state"
assert_contains "$S2/empty-version-err" "invalid Forge v6 state" \
    "empty Forge version is treated as an invalid migrated surface"

S2L=$(scratch_dir state-path-symlink)
mkdir -p "$S2L/outside/local"
printf '6\n' > "$S2L/outside/version"
printf '<!-- forge:state-schema v6 -->\nOUTSIDE_STATE\n' > "$S2L/outside/local/state.md"
ln -s "$S2L/outside" "$S2L/.forge"
forge_state_path "$S2L" read > "$S2L/out" 2> "$S2L/err"
assert_equals "$?" "1" "canonical state helper rejects a symlinked Forge ancestor"
assert_contains "$S2L/err" "symlink" "state ancestor rejection is diagnosable"
forge_state_path "$S2L" write > "$S2L/write-out" 2> "$S2L/write-err"
assert_equals "$?" "1" "canonical state writes reject a symlinked Forge ancestor"

start_test "v6 evidence uses canonical state and refuses legacy review/goal/auth evidence"
S3=$(scratch_dir state-consumer)
make_git_repo "$S3"
mkdir -p "$S3/.claude/local" "$S3/.forge/local" "$S3/.forge/hooks/lib"
cp "$REPO_ROOT/hooks/lib/state-path.sh" "$S3/.forge/hooks/lib/state-path.sh"
cp "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/all-green.md" "$S3/.claude/local/state.md"
{
    printf '<!-- forge:state-schema v6 -->\n'
    cat "$REPO_ROOT/tests/template/fixtures/state-md-build-evidence/with-goal-session.md"
} > "$S3/.forge/local/state.md"
printf '6\n' > "$S3/.forge/version"
(cd "$S3" && bash "$REPO_ROOT/hooks/build-evidence.sh") >"$S3/evidence" 2>&1
assert_contains "$S3/evidence" '"session_nonce":"00000000-0000-0000-0000-000000000001"' \
    "evidence reads canonical v6 state"
mv "$S3/.forge/local/state.md" "$S3/.forge/local/state.invalid"
(cd "$S3" && bash "$REPO_ROOT/hooks/build-evidence.sh") >"$S3/invalid-evidence" 2>&1
assert_equals "$?" "2" "invalid/missing v6 state fails the evidence boundary closed"
assert_contains "$S3/invalid-evidence" 'FORGE_STATE_INVALID' \
    "invalid/missing v6 state never reuses legacy goal evidence"

start_test "stamped exact v5 refresh translates state, installs both hosts, and reports categories"
S4=$(scratch_dir full-refresh-happy)
make_git_repo "$S4"
mkdir -p "$S4/.claude/hooks" "$S4/.claude/local" "$S4/.claude/commands"
printf '5.61\n' > "$S4/.claude/.forge-version"
git -C "$REPO_ROOT" show cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:hooks/session-start.sh \
    > "$S4/.claude/hooks/session-start.sh"
git -C "$REPO_ROOT" show cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:commands/new-feature.md \
    > "$S4/.claude/commands/new-feature.md"
write_active_v5_state "$S4" "V5_CHECKPOINT_TOKEN"
printf 'SEED_SNAPSHOT_BYTES\n' > "$S4/.claude/local/.state-seed-snapshot.md"
printf 'CUSTOM_EXTENSION_BYTES\n' > "$S4/.claude/developer-extension.txt"
run_refresh "$S4" "$S4/refresh.log" -F -p "Spaced Project!"
assert_equals "$?" "0" "recognized stamped v5 refresh succeeds"
assert_contains "$S4/.forge/local/state.md" "<!-- forge:state-schema v6 -->" \
    "translated state has v6 schema marker"
assert_contains "$S4/.forge/local/state.md" "V5_CHECKPOINT_TOKEN" \
    "active checkpoint narrative survives translation"
assert_contains "$S4/.forge/local/.state-seed-snapshot.md" "SEED_SNAPSHOT_BYTES" \
    "state seed snapshot moves to the canonical local path"
assert_contains "$S4/.claude/developer-extension.txt" "CUSTOM_EXTENSION_BYTES" \
    "custom Claude extension remains byte-identical"
assert_contains "$S4/.forge/local/state.md" 'nonce=`<session-nonce>`' \
    "authorization format documentation remains narrative rather than evidence"
assert_dir_exists "$S4/.forge/local/migration-backups" \
    "raw originals are retained under Forge local backups"
assert_file_missing "$S4/.claude/.forge-version" "proven obsolete v5 stamp is deleted at commit"
assert_file_missing "$S4/.claude/local/state.md" "translated v5 state source is removed only at commit"
assert_file_exists "$S4/.claude/commands/new-feature.md" "Claude adapter materialized"
assert_contains "$S4/.claude/commands/new-feature.md" "canonical-path:" \
    "exact legacy command is replaced by the thin v6 adapter"
assert_file_exists "$S4/.agents/skills/workflow-new-feature/SKILL.md" "Codex adapter materialized"
assert_contains "$S4/refresh.log" "CREATED" "categorized CREATED report emitted"
assert_contains "$S4/refresh.log" "REWRITTEN" "categorized REWRITTEN report emitted"
assert_contains "$S4/refresh.log" "PRESERVED" "categorized PRESERVED report emitted"
assert_contains "$S4/refresh.log" "INSTALLATION: MATERIALIZED" "materialization status emitted"

start_test "ambiguous legacy bytes and old/new state conflicts block before mutation"
S5=$(scratch_dir full-refresh-blocked)
make_git_repo "$S5"
mkdir -p "$S5/.claude/hooks"
printf '5.61\n' > "$S5/.claude/.forge-version"
printf 'developer changed this hook\n' > "$S5/.claude/hooks/session-start.sh"
write_active_v5_state "$S5"
before=$(hash_file "$S5/.claude/hooks/session-start.sh")
run_refresh "$S5" "$S5/blocked.log" -F
assert_equals "$?" "1" "modified known managed file blocks refresh"
assert_hash_equals "$S5/.claude/hooks/session-start.sh" "$before" "blocked refresh preserves ambiguous bytes"
assert_file_missing "$S5/.forge/version" "blocked refresh never writes v6 stamp"
assert_contains "$S5/blocked.log" "BLOCKED" "blocked ownership is reported"

S5C=$(scratch_dir full-refresh-conflict)
make_git_repo "$S5C"
write_active_v5_state "$S5C" "OLD_STATE"
mkdir -p "$S5C/.forge/local"
printf '<!-- forge:state-schema v6 -->\nNEW_STATE\n' > "$S5C/.forge/local/state.md"
run_refresh "$S5C" "$S5C/conflict.log" -F
assert_equals "$?" "1" "old/new state conflict is never guessed"
assert_contains "$S5C/conflict.log" "state conflict" "state conflict is explicit"
assert_not_contains "$S5C/.forge/local/state.md" "OLD_STATE" "existing canonical state is untouched"

start_test "preview reports every ordinary ownership blocker before staging"
S5M=$(scratch_dir full-refresh-multi-blocker)
make_git_repo "$S5M"
mkdir -p "$S5M/.claude/hooks"
printf '5.61\n' > "$S5M/.claude/.forge-version"
for hook in session-start.sh check-bash-safety.sh; do
    git -C "$REPO_ROOT" show "cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:hooks/$hook" \
        > "$S5M/.claude/hooks/$hook"
    printf '\nDEVELOPER_MODIFIED_%s\n' "$hook" >> "$S5M/.claude/hooks/$hook"
done
printf '{ malformed settings\n' > "$S5M/.claude/settings.json"
write_active_v5_state "$S5M" "MULTI_BLOCKER_STATE"
session_hash=$(hash_file "$S5M/.claude/hooks/session-start.sh")
safety_hash=$(hash_file "$S5M/.claude/hooks/check-bash-safety.sh")
settings_hash=$(hash_file "$S5M/.claude/settings.json")
multi_log="${S5M}.preview.log"
run_refresh "$S5M" "$multi_log" -F --dry-run
assert_equals "$?" "1" "multi-blocker preview returns nonzero"
assert_contains "$multi_log" ".claude/hooks/session-start.sh" "preview lists the first modified hook"
assert_contains "$multi_log" ".claude/hooks/check-bash-safety.sh" "preview lists the second modified hook"
assert_contains "$multi_log" ".claude/settings.json" "preview lists malformed settings"
assert_contains "$multi_log" "BLOCKERS: 3" "preview reports the complete blocker count"
assert_hash_equals "$S5M/.claude/hooks/session-start.sh" "$session_hash" "first blocker remains byte-identical"
assert_hash_equals "$S5M/.claude/hooks/check-bash-safety.sh" "$safety_hash" "second blocker remains byte-identical"
assert_hash_equals "$S5M/.claude/settings.json" "$settings_hash" "malformed settings remain byte-identical"
assert_file_missing "$S5M/.forge/version" "blocked inventory writes no v6 stamp"
assert_file_missing "$S5M/.forge/local/migration-guard" "blocked inventory writes no guard"
assert_file_missing "$S5M/.forge/local/migration-journals" "blocked inventory writes no journal"
assert_file_missing "$S5M/.forge/local/migration-backups" "blocked inventory writes no backup"
assert_file_missing "$S5M/.forge/local/migration-reports" "blocked inventory writes no report"

start_test "symlink destination and injected commit failure cannot produce a partial stamp"
S6=$(scratch_dir full-refresh-symlink)
make_git_repo "$S6"
mkdir -p "$S6/elsewhere"
ln -s "$S6/elsewhere" "$S6/.forge"
run_refresh "$S6" "$S6/symlink.log" -F
assert_equals "$?" "1" "symlinked managed ancestor is rejected"
assert_contains "$S6/symlink.log" "symlink" "symlink rejection is explicit"

S6F=$(scratch_dir full-refresh-rollback)
make_git_repo "$S6F"
printf 'developer root bytes\n' > "$S6F/CLAUDE.md"
root_before=$(hash_file "$S6F/CLAUDE.md")
(cd "$S6F" && HOME="$S6F/.fakehome" FORGE_FULL_REFRESH_FAIL_AFTER=2 \
    "$REPO_ROOT/setup.sh" -F) >"$S6F/failure.log" 2>&1
assert_equals "$?" "1" "injected commit-phase failure returns nonzero"
assert_hash_equals "$S6F/CLAUDE.md" "$root_before" "rollback restores replaced developer file"
assert_file_missing "$S6F/.forge/version" "rollback never leaves a readiness stamp"
assert_contains "$S6F/failure.log" "ROLLED_BACK" "rollback disposition is reported"

for failure_point in 1 @penultimate; do
    S6P=$(scratch_dir "full-refresh-failure-${failure_point#@}")
    make_git_repo "$S6P"
    printf 'FAILURE_POINT_DEVELOPER_BYTES\n' > "$S6P/CLAUDE.md"
    write_active_v5_state "$S6P" "FAILURE_POINT_STATE_BYTES"
    failure_root_hash=$(hash_file "$S6P/CLAUDE.md")
    failure_state_hash=$(hash_file "$S6P/.claude/local/state.md")
    (cd "$S6P" && HOME="$S6P/.fakehome" FORGE_FULL_REFRESH_FAIL_AFTER="$failure_point" \
        "$REPO_ROOT/setup.sh" -F) > "$S6P/failure.log" 2>&1
    assert_equals "$?" "1" "failure after $failure_point live rename returns nonzero"
    assert_hash_equals "$S6P/CLAUDE.md" "$failure_root_hash" \
        "failure after $failure_point restores developer root bytes"
    assert_hash_equals "$S6P/.claude/local/state.md" "$failure_state_hash" \
        "failure after $failure_point restores usable v5 state bytes"
    assert_file_missing "$S6P/.forge/version" \
        "failure after $failure_point cannot write the late v6 stamp"
    assert_contains "$S6P/failure.log" "ROLLED_BACK" \
        "failure after $failure_point reports verified rollback"
done

start_test "full refresh is idempotent and project scope never mutates selected home harness"
S7=$(scratch_dir full-refresh-idempotent)
make_git_repo "$S7"
mkdir -p "$S7/.fakehome/.forge"
printf 'HOME_SENTINEL\n' > "$S7/.fakehome/.forge/sentinel"
run_refresh "$S7" "$S7/first.log" -F
assert_equals "$?" "0" "clean project full refresh succeeds"
first_manifest=$(hash_file "$S7/.forge/managed-files.tsv")
run_refresh "$S7" "$S7/second.log" -F
assert_equals "$?" "0" "second full refresh succeeds"
assert_hash_equals "$S7/.forge/managed-files.tsv" "$first_manifest" "managed manifest is idempotent"
assert_contains "$S7/.fakehome/.forge/sentinel" "HOME_SENTINEL" "project transaction does not mutate home harness"

start_test "global refresh is explicit and confined to selected HOME"
S8=$(scratch_dir full-refresh-global)
mkdir -p "$S8/home" "$S8/invoker"
S8_HOME=$(cd "$S8/home" && pwd -P)
(cd "$S8/invoker" && HOME="$S8_HOME" "$REPO_ROOT/setup.sh" --global -F) >"$S8/global.log" 2>&1
assert_equals "$?" "0" "explicit global full refresh succeeds"
assert_file_exists "$S8/home/.forge/version" "global v6 stamp is under selected home"
assert_file_exists "$S8/home/.claude/CLAUDE.md" "global Claude adapter installed"
assert_file_exists "$S8/home/.codex/AGENTS.md" "global Codex adapter installed"
assert_file_missing "$S8/invoker/.forge/version" "global transaction writes nothing to invoker"

start_test "every supported v5 release selector proves an exact managed fingerprint"
S9=$(scratch_dir full-refresh-release-matrix)
while IFS=$'\t' read -r release commit _stamp_mode _fingerprint_set _region_set; do
    case "$release" in ""|'#'*) continue ;; esac
    release_root="$S9/$release"
    make_git_repo "$release_root"
    mkdir -p "$release_root/.claude/hooks" "$release_root/.claude/local"
    printf '%s\n' "$release" > "$release_root/.claude/.forge-version"
    git -C "$REPO_ROOT" show "$commit:hooks/session-start.sh" \
        > "$release_root/.claude/hooks/session-start.sh"
    printf '%s\n' \
        '{' \
        '  "developerSibling": {"punctuation": "keep !@#$%^&*()"},' \
        '  "enabledPlugins": {"developer-inert@example": true}' \
        '}' > "$release_root/.claude/settings.json"
    write_active_v5_state "$release_root" "RELEASE_${release}_CHECKPOINT"
    run_refresh "$release_root" "$release_root/refresh.log" -F
    assert_equals "$?" "0" "release $release exact fingerprint refreshes"
    assert_contains "$release_root/.claude/settings.json" '"developerSibling"' \
        "release $release preserves unknown settings siblings"
    assert_contains "$release_root/refresh.log" "PRESERVED_COMPAT" \
        "release $release inventories compatibility configuration"
done < "$REPO_ROOT/manifests/legacy-v5-releases.tsv"

start_test "pre-stamp exact fingerprint migrates but a one-byte near-match remains untouched"
S10=$(scratch_dir full-refresh-prestamp)
make_git_repo "$S10"
mkdir -p "$S10/.claude/hooks"
git -C "$REPO_ROOT" show d30dee8b045b202df39c5d3efabd3b49ea7b8950:hooks/session-start.sh \
    > "$S10/.claude/hooks/session-start.sh"
write_active_v5_state "$S10" "PRESTAMP_CHECKPOINT"
run_refresh "$S10" "$S10/refresh.log" -F
assert_equals "$?" "0" "exact pre-stamp v5 fingerprint is recognized"
assert_contains "$S10/.forge/local/state.md" "PRESTAMP_CHECKPOINT" \
    "pre-stamp checkpoint survives translation"

S10N=$(scratch_dir full-refresh-nearmatch)
make_git_repo "$S10N"
mkdir -p "$S10N/.claude/hooks"
git -C "$REPO_ROOT" show d30dee8b045b202df39c5d3efabd3b49ea7b8950:hooks/session-start.sh \
    > "$S10N/.claude/hooks/session-start.sh"
printf '\n' >> "$S10N/.claude/hooks/session-start.sh"
near_hash=$(hash_file "$S10N/.claude/hooks/session-start.sh")
run_refresh "$S10N" "$S10N/refresh.log" -F
assert_equals "$?" "1" "one-byte pre-stamp near-match blocks"
assert_hash_equals "$S10N/.claude/hooks/session-start.sh" "$near_hash" \
    "one-byte near-match remains byte-identical"
assert_file_missing "$S10N/.forge/version" "near-match cannot stamp readiness"

start_test "first and penultimate concurrent edits are preserved without a partial stamp"
for injection in @first @penultimate; do
    race_root=$(scratch_dir "full-refresh-concurrent-${injection#@}")
    make_git_repo "$race_root"
    (cd "$race_root" && HOME="$race_root/.fakehome" \
        FORGE_FULL_REFRESH_INJECT_EDIT_RELATIVE="$injection" \
        "$REPO_ROOT/setup.sh" -F) > "$race_root/race.log" 2>&1
    assert_equals "$?" "1" "$injection concurrent edit blocks"
    assert_contains "$race_root/race.log" "concurrent edit before quarantine" \
        "$injection race is diagnosed"
    assert_contains "$race_root/race.log" "FORGE_CONCURRENT_EDIT" \
        "$injection concurrently-created bytes are reported"
    assert_file_missing "$race_root/.forge/version" "$injection race cannot stamp readiness"
done

start_test "destination appearance after quarantine preserves both versions for recovery"
S12=$(scratch_dir full-refresh-destination-race)
make_git_repo "$S12"
mkdir -p "$S12/.forge/local"
printf '<!-- forge:state-schema v6 -->\nORIGINAL_CANONICAL_STATE\n' > "$S12/.forge/local/state.md"
state_before=$(hash_file "$S12/.forge/local/state.md")
(cd "$S12" && HOME="$S12/.fakehome" \
    FORGE_FULL_REFRESH_INJECT_DESTINATION_RACE_RELATIVE='.forge/local/state.md' \
    "$REPO_ROOT/setup.sh" -F) > "$S12/race.log" 2>&1
assert_equals "$?" "1" "destination race blocks"
assert_contains "$S12/.forge/local/state.md" "FORGE_DESTINATION_RACE" \
    "new destination bytes are never clobbered"
journal12=$(find "$S12/.forge/local/migration-journals" -name '*.json' -type f -print -quit)
assert_matches "$journal12" '"phase": "recovery_required"' \
    "uncertain rollback retains a recovery-required journal"
quarantined_state=$(find "$S12/.forge/local/migration-staging" -path '*/quarantine/.forge/local/state.md' -type f -print -quit)
assert_hash_equals "$quarantined_state" "$state_before" \
    "quarantine retains the original version byte-for-byte"
assert_file_missing "$S12/.forge/version" "destination race cannot stamp readiness"

start_test "verified recovery restores an inactive transaction and clears only its stale guard"
S13=$(scratch_dir full-refresh-recovery)
make_git_repo "$S13"
S13=$(cd "$S13" && pwd -P)
txid="1700000000-11111111111111111111111111111111"
mkdir -p "$S13/.forge/local/migration-journals" \
    "$S13/.forge/local/migration-staging/$txid/quarantine/.claude/commands" \
    "$S13/.forge/local/setup-transaction.guard" "$S13/.claude/commands"
printf 'ORIGINAL_RECOVERY_BYTES\n' \
    > "$S13/.forge/local/migration-staging/$txid/quarantine/.claude/commands/new-feature.md"
printf 'INSTALLED_RECOVERY_BYTES\n' > "$S13/.claude/commands/new-feature.md"
original_recovery_hash=$(hash_file "$S13/.forge/local/migration-staging/$txid/quarantine/.claude/commands/new-feature.md")
installed_recovery_hash=$(hash_file "$S13/.claude/commands/new-feature.md")
cat > "$S13/.forge/local/migration-journals/$txid.json" <<EOF
{
  "schema": "forge-full-refresh-journal-v1",
  "transaction_id": "$txid",
  "transaction_root": "$S13",
  "scope": "project",
  "phase": "committing",
  "operations": [{
    "relative": ".claude/commands/new-feature.md",
    "source": "$S13/.forge/local/migration-staging/$txid/stage/.claude/commands/new-feature.md",
    "destination": "$S13/.claude/commands/new-feature.md",
    "quarantine": "$S13/.forge/local/migration-staging/$txid/quarantine/.claude/commands/new-feature.md",
    "original_hash": "$original_recovery_hash",
    "staged_hash": "$installed_recovery_hash",
    "installed_hash": "$installed_recovery_hash",
    "status": "installed"
  }]
}
EOF
printf '{"pid":999999,"transaction_id":"%s","created_unix":1}\n' "$txid" \
    > "$S13/.forge/local/setup-transaction.guard/owner.json"
"$REPO_ROOT/scripts/recover-full-refresh.sh" \
    --journal "$S13/.forge/local/migration-journals/$txid.json" --target "$S13" \
    > "$S13/recovery.log" 2>&1
assert_equals "$?" "0" "inactive exact journal recovers"
assert_contains "$S13/.claude/commands/new-feature.md" "ORIGINAL_RECOVERY_BYTES" \
    "verified original is restored"
assert_file_missing "$S13/.forge/local/setup-transaction.guard" \
    "matching inactive stale guard is removed"
assert_contains "$S13/.forge/local/migration-journals/$txid.json" '"phase": "recovered"' \
    "journal records recovered terminal phase"

start_test "hand-edited recovery paths and incomplete journals fail closed"
S14=$(scratch_dir full-refresh-hostile-journal)
make_git_repo "$S14"
S14=$(cd "$S14" && pwd -P)
mkdir -p "$S14/.forge/local/migration-journals"
printf 'DO_NOT_TOUCH\n' > "$S14/developer.txt"
hostile_hash=$(hash_file "$S14/developer.txt")
hostile_txid="1700000000-22222222222222222222222222222222"
printf '{"schema":"forge-full-refresh-journal-v1","transaction_id":"%s","transaction_root":"%s","scope":"project","phase":"committing","operations":[{"relative":"developer.txt","source":"%s/.forge/local/migration-staging/%s/stage/developer.txt","destination":"%s/developer.txt","quarantine":"%s/.forge/local/migration-staging/%s/quarantine/developer.txt","original_hash":"","installed_hash":"%s","status":"installed","delete":false}]}\n' \
    "$hostile_txid" "$S14" "$S14" "$hostile_txid" "$S14" "$S14" "$hostile_txid" "$hostile_hash" \
    > "$S14/.forge/local/migration-journals/$hostile_txid.json"
"$REPO_ROOT/scripts/recover-full-refresh.sh" \
    --journal "$S14/.forge/local/migration-journals/$hostile_txid.json" --target "$S14" \
    > "$S14/recovery.log" 2>&1
assert_equals "$?" "1" "hand-edited quarantine path is rejected"
assert_hash_equals "$S14/developer.txt" "$hostile_hash" "hostile journal cannot mutate developer bytes"
run_refresh "$S14" "$S14/new-refresh.log" -F
assert_equals "$?" "1" "new transaction refuses an incomplete journal"
assert_contains "$S14/new-refresh.log" "requires recovery" "incomplete journal reports recovery command"
assert_file_missing "$S14/.forge/version" "incomplete journal cannot stamp readiness"

start_test "missing Python and malformed JSON fail before mutation"
S15=$(scratch_dir full-refresh-preflight)
make_git_repo "$S15"
mkdir -p "$S15/no-python-bin"
ln -s /usr/bin/dirname "$S15/no-python-bin/dirname"
PATH="$S15/no-python-bin" /bin/bash "$REPO_ROOT/scripts/full-refresh.sh" \
    --target "$S15" --scope project > "$S15/python.log" 2>&1
assert_equals "$?" "1" "missing Python blocks authoritative migration"
assert_contains "$S15/python.log" "Python 3 is required" "missing Python is explicit"
assert_file_missing "$S15/.forge" "Python preflight mutates no Forge path"

S15J=$(scratch_dir full-refresh-malformed-json)
make_git_repo "$S15J"
mkdir -p "$S15J/.claude"
printf '{ malformed: developer-secret-token }\n' > "$S15J/.claude/settings.json"
malformed_hash=$(hash_file "$S15J/.claude/settings.json")
run_refresh "$S15J" "$S15J/refresh.log" -F
assert_equals "$?" "1" "malformed protected JSON blocks"
assert_hash_equals "$S15J/.claude/settings.json" "$malformed_hash" \
    "malformed JSON remains byte-identical"
assert_file_missing "$S15J/.forge/version" "malformed JSON cannot stamp readiness"

start_test "preserved overlapping plugin blocks runtime readiness without blocking migration"
S16=$(scratch_dir full-refresh-plugin-overlap)
make_git_repo "$S16"
mkdir -p "$S16/.claude"
printf '%s\n' \
    '{' \
    '  "developerSecret": "SECRET_SIBLING_SURVIVES",' \
    '  "enabledPlugins": {"superpowers@claude-plugins-official": true}' \
    '}' > "$S16/.claude/settings.json"
run_refresh "$S16" "$S16/refresh.log" -F
assert_equals "$?" "0" "unowned exact historical plugin entry is preserved"
assert_contains "$S16/.claude/settings.json" "SECRET_SIBLING_SURVIVES" \
    "unknown settings sibling survives semantically"
assert_contains "$S16/.claude/settings.json" "superpowers@claude-plugins-official" \
    "historical plugin entry is not tombstoned without provenance"
assert_contains "$S16/refresh.log" "PRESERVED_COMPAT_BLOCKED" \
    "overlapping plugin is categorized as compatibility-blocked"
assert_contains "$S16/refresh.log" "claude RUNTIME_READY: BLOCKED" \
    "overlapping ambient plugin prevents a clean runtime claim"

start_test "mixed legacy instruction recognizers preserve arbitrary user regions byte-for-byte"
S17=$(scratch_dir full-refresh-regions)
make_git_repo "$S17"
git -C "$REPO_ROOT" show d30dee8b045b202df39c5d3efabd3b49ea7b8950:CLAUDE.template.md \
    > "$S17/CLAUDE.md"
sed -i.bak 's/# CLAUDE.md - \[Project Name\]/# CLAUDE.md - Spaces, punctuation!/' "$S17/CLAUDE.md"
sed -i.bak 's/\[One sentence describing what this project does and who benefits\.\]/CUSTOM_USER_REGION_!@#$%^\&*()/' "$S17/CLAUDE.md"
rm -f "$S17/CLAUDE.md.bak"
run_refresh "$S17" "$S17/refresh.log" -F
assert_equals "$?" "0" "exact managed regions with customized user bytes migrate"
assert_contains "$S17/CLAUDE.md" 'CUSTOM_USER_REGION_!@#$%^&*()' \
    "project user-region bytes survive in the v6 root surface"

S17G=$(scratch_dir full-refresh-global-regions)
mkdir -p "$S17G/home/.claude" "$S17G/invoker"
git -C "$REPO_ROOT" show d30dee8b045b202df39c5d3efabd3b49ea7b8950:GLOBAL-CLAUDE.template.md \
    > "$S17G/home/.claude/CLAUDE.md"
sed -i.bak 's/<!-- Add your personal preferences below\. Examples: -->/GLOBAL_CUSTOM_REGION_!@#$%^\&*()/' \
    "$S17G/home/.claude/CLAUDE.md"
rm -f "$S17G/home/.claude/CLAUDE.md.bak"
S17G_HOME=$(cd "$S17G/home" && pwd -P)
(cd "$S17G/invoker" && HOME="$S17G_HOME" "$REPO_ROOT/setup.sh" --global -F) \
    > "$S17G/refresh.log" 2>&1
assert_equals "$?" "0" "exact global managed region with customized user bytes migrates"
assert_contains "$S17G/home/.claude/CLAUDE.md" 'GLOBAL_CUSTOM_REGION_!@#$%^&*()' \
    "global user-region bytes survive in the v6 root surface"

start_test "continuity migration receipt authorizes only the exact source and canonical target"
S18=$(scratch_dir full-refresh-continuity-receipt)
make_git_repo "$S18"
write_active_v5_state "$S18" "CONTINUITY_RECEIPT_CHECKPOINT"
cat > "$S18/CONTINUITY.md" <<'EOF'
# CONTINUITY

## State

### Now

- continuity migration then full refresh
EOF
cat > "$S18/CLAUDE.md" <<'EOF'
# Developer-owned instructions

## Project Overview
EOF
(cd "$S18" && HOME="$S18/.fakehome" "$REPO_ROOT/setup.sh" --migrate) \
    > "$S18/migrate.log" 2>&1
assert_equals "$?" "0" "Bash continuity migration succeeds before full refresh"
receipt18="$S18/.forge/local/migration-evidence/continuity-state-v5-v6.json"
assert_file_exists "$receipt18" "continuity migration creates a protected translation receipt"
run_refresh "$S18" "$S18/refresh.log" -F
assert_equals "$?" "0" "receipt-proven continuity translation can continue through full refresh"
assert_contains "$S18/.forge/local/state.md" "continuity migration then full refresh" \
    "full refresh prefers the receipt-bound canonical continuity state"
assert_file_missing "$S18/.claude/local/state.md" \
    "receipt-proven surviving legacy state is retired only at commit"

for tamper in receipt schema source target; do
    tamper_root=$(scratch_dir "full-refresh-continuity-${tamper}")
    make_git_repo "$tamper_root"
    write_active_v5_state "$tamper_root" "CONTINUITY_${tamper}_CHECKPOINT"
    printf '# CONTINUITY\n\n## State\n\n### Now\n\n- receipt tamper case\n' \
        > "$tamper_root/CONTINUITY.md"
    printf '# Developer instructions\n\n## Project Overview\n' > "$tamper_root/CLAUDE.md"
    (cd "$tamper_root" && HOME="$tamper_root/.fakehome" "$REPO_ROOT/setup.sh" --migrate) \
        > "$tamper_root/migrate.log" 2>&1
    tamper_receipt="$tamper_root/.forge/local/migration-evidence/continuity-state-v5-v6.json"
    case "$tamper" in
        receipt)
            if [ -f "$tamper_receipt" ]; then
                python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["source_hash"]="0"*64; open(p,"w").write(json.dumps(d)+"\n")' "$tamper_receipt"
            fi
            ;;
        schema)
            python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["source_schema"]="forge-state-v5-stale"; open(p,"w").write(json.dumps(d)+"\n")' "$tamper_receipt"
            ;;
        source) printf '\nSOURCE_TAMPER\n' >> "$tamper_root/.claude/local/state.md" ;;
        target) printf '\nTARGET_TAMPER\n' >> "$tamper_root/.forge/local/state.md" ;;
    esac
    run_refresh "$tamper_root" "$tamper_root/refresh.log" -F
    assert_equals "$?" "1" "$tamper continuity evidence blocks full refresh"
    assert_contains "$tamper_root/refresh.log" "continuity translation receipt" \
        "$tamper mismatch is diagnosed as untrusted continuity evidence"
    assert_file_missing "$tamper_root/.forge/version" \
        "$tamper mismatch cannot stamp v6 readiness"
done

start_test "released v5 hook registrations map once to exact thin delegates"
S19=$(scratch_dir full-refresh-hook-settings)
make_git_repo "$S19"
mkdir -p "$S19/.claude/hooks"
printf '5.61\n' > "$S19/.claude/.forge-version"
git -C "$REPO_ROOT" show cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:settings/settings.template.json \
    > "$S19/.claude/settings.json"
python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
for blocks in d.get("hooks",{}).values():
  for block in blocks:
    for hook in block.get("hooks",[]):
      c=hook.get("command","")
      if ".claude/hooks/" in c and c.startswith("$CLAUDE_PROJECT_DIR/"):
        print(c.split("$CLAUDE_PROJECT_DIR/.claude/",1)[1])' \
    "$S19/.claude/settings.json" | while IFS= read -r hook_relative; do
        mkdir -p "$S19/.claude/$(dirname "$hook_relative")"
        git -C "$REPO_ROOT" show \
            "cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:$hook_relative" \
            > "$S19/.claude/$hook_relative"
    done
write_active_v5_state "$S19" "HOOK_SETTINGS_CHECKPOINT"
run_refresh "$S19" "$S19/refresh.log" -F
assert_equals "$?" "0" "full released v5.61 settings migrate with proven hooks"
python3 -c 'import json,sys
d=json.load(open(sys.argv[1])); seen={}; inline=[]; managed=[]
for event,blocks in d.get("hooks",{}).items():
  for block in blocks:
    for hook in block.get("hooks",[]):
      c=hook.get("command","")
      if "COMPACTION IMMINENT" in c: inline.append(c)
      if "/hooks/" in c and c.startswith("$CLAUDE_PROJECT_DIR/"):
        mid=hook.get("forgeManagedId")
        if mid: managed.append((mid,event,c))
        else:
          name=c.rsplit("/",1)[-1]; seen.setdefault(name,[]).append(c)
bad={k:v for k,v in seen.items() if len(v)!=1 or "/.claude/hooks/" not in v[0]}
expected_managed=[("subagent-review-receipt","SubagentStop","$CLAUDE_PROJECT_DIR/.forge/hooks/check-subagent-review.sh")]
raise SystemExit(1 if bad or managed!=expected_managed or len(inline)!=1 else 0)' "$S19/.claude/settings.json"
assert_equals "$?" "0" "installed event/matcher config executes each proven hook exactly once"
assert_contains "$S19/.claude/hooks/session-start.sh" '.forge/hooks/session-start.sh' \
    "preserved v5 registration resolves through a thin canonical delegate"

S19D=$(scratch_dir full-refresh-hook-dangling)
make_git_repo "$S19D"
mkdir -p "$S19D/.claude/hooks"
printf '5.61\n' > "$S19D/.claude/.forge-version"
git -C "$REPO_ROOT" show cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:settings/settings.template.json \
    > "$S19D/.claude/settings.json"
run_refresh "$S19D" "$S19D/refresh.log" -F
assert_equals "$?" "1" "released registration with missing referenced hook blocks"
assert_contains "$S19D/refresh.log" "referenced legacy hook" \
    "dangling released hook registration is diagnosed"
assert_file_missing "$S19D/.forge/version" "dangling hook config cannot stamp readiness"

S19M=$(scratch_dir full-refresh-hook-modified)
make_git_repo "$S19M"
mkdir -p "$S19M/.claude/hooks"
printf '5.61\n' > "$S19M/.claude/.forge-version"
git -C "$REPO_ROOT" show cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:settings/settings.template.json \
    > "$S19M/.claude/settings.json"
python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
for blocks in d.get("hooks",{}).values():
  for block in blocks:
    for hook in block.get("hooks",[]):
      c=hook.get("command","")
      if ".claude/hooks/" in c and c.startswith("$CLAUDE_PROJECT_DIR/"):
        print(c.split("$CLAUDE_PROJECT_DIR/.claude/",1)[1])' \
    "$S19M/.claude/settings.json" | while IFS= read -r hook_relative; do
        mkdir -p "$S19M/.claude/$(dirname "$hook_relative")"
        git -C "$REPO_ROOT" show \
            "cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:$hook_relative" \
            > "$S19M/.claude/$hook_relative"
    done
printf '\nDEVELOPER_MODIFIED_HOOK\n' >> "$S19M/.claude/hooks/session-start.sh"
modified_hook_hash=$(hash_file "$S19M/.claude/hooks/session-start.sh")
run_refresh "$S19M" "$S19M/refresh.log" -F
assert_equals "$?" "1" "released registration with a modified referenced hook blocks"
assert_hash_equals "$S19M/.claude/hooks/session-start.sh" "$modified_hook_hash" \
    "modified referenced hook remains byte-identical"
assert_file_missing "$S19M/.forge/version" "modified referenced hook cannot stamp readiness"

start_test "manifest-driven mixed-region segmentation ignores inline anchors and blocks ambiguity"
S20=$(scratch_dir full-refresh-region-inline)
make_git_repo "$S20"
git -C "$REPO_ROOT" show d30dee8b045b202df39c5d3efabd3b49ea7b8950:CLAUDE.template.md \
    > "$S20/CLAUDE.md"
python3 -c 'import sys
p=sys.argv[1]; b=open(p,"rb").read(); b=b.replace(b"# CLAUDE.md - [Project Name]",b"# CLAUDE.md - Anchor-like user text"); b=b.replace(b"[One sentence describing what this project does and who benefits.]",b"Developer text mentions ### Research Enforcement inline and must survive."); open(p,"wb").write(b)' "$S20/CLAUDE.md"
run_refresh "$S20" "$S20/refresh.log" -F
assert_equals "$?" "0" "inline boundary-looking user text does not select a false region"
assert_contains "$S20/CLAUDE.md" 'Developer text mentions ### Research Enforcement inline' \
    "inline anchor-like project text is byte-preserved"

S20A=$(scratch_dir full-refresh-region-ambiguous)
make_git_repo "$S20A"
git -C "$REPO_ROOT" show d30dee8b045b202df39c5d3efabd3b49ea7b8950:CLAUDE.template.md \
    > "$S20A/CLAUDE.md"
python3 -c 'import sys
p=sys.argv[1]; b=open(p,"rb").read().replace(b"# CLAUDE.md - [Project Name]",b"# CLAUDE.md - Ambiguous regions"); s=b.index(b"### Research Enforcement"); e=b.index(b"### Key Commands",s); branch=b[s:e]+b"### Key Commands\n\nAMBIGUOUS_USER_BRANCH\n"; b=b[:s]+branch+b[s:]; open(p,"wb").write(b)' "$S20A/CLAUDE.md"
ambiguous_hash=$(hash_file "$S20A/CLAUDE.md")
run_refresh "$S20A" "$S20A/refresh.log" -F
assert_equals "$?" "1" "two valid project segmentations block rather than guessing"
assert_hash_equals "$S20A/CLAUDE.md" "$ambiguous_hash" \
    "ambiguous project root remains byte-identical"

S20G=$(scratch_dir full-refresh-global-region-inline)
mkdir -p "$S20G/home/.claude" "$S20G/invoker"
git -C "$REPO_ROOT" show d30dee8b045b202df39c5d3efabd3b49ea7b8950:GLOBAL-CLAUDE.template.md \
    > "$S20G/home/.claude/CLAUDE.md"
python3 -c 'import sys
p=sys.argv[1]; b=open(p,"rb").read(); b=b.replace(b"<!-- Add your personal preferences below. Examples: -->",b"Developer text mentions ## Cross-Project Conventions inline."); open(p,"wb").write(b)' "$S20G/home/.claude/CLAUDE.md"
S20G_HOME=$(cd "$S20G/home" && pwd -P)
(cd "$S20G/invoker" && HOME="$S20G_HOME" "$REPO_ROOT/setup.sh" --global -F) \
    > "$S20G/refresh.log" 2>&1
assert_equals "$?" "0" "inline boundary-looking global user text remains unambiguous"
assert_contains "$S20G/home/.claude/CLAUDE.md" 'Developer text mentions ## Cross-Project Conventions inline.' \
    "inline anchor-like global text is byte-preserved"

S20GA=$(scratch_dir full-refresh-global-region-ambiguous)
mkdir -p "$S20GA/home/.claude" "$S20GA/invoker"
git -C "$REPO_ROOT" show d30dee8b045b202df39c5d3efabd3b49ea7b8950:GLOBAL-CLAUDE.template.md \
    > "$S20GA/home/.claude/CLAUDE.md"
python3 -c 'import sys
p=sys.argv[1]; b=open(p,"rb").read(); marker=b"## Personal Preferences\n"; i=b.index(marker)+len(marker); b=b[:i]+b"\n## Cross-Project Conventions\n\nAMBIGUOUS_USER_BOUNDARY\n"+b[i:]; open(p,"wb").write(b)' "$S20GA/home/.claude/CLAUDE.md"
global_ambiguous_hash=$(hash_file "$S20GA/home/.claude/CLAUDE.md")
S20GA_HOME=$(cd "$S20GA/home" && pwd -P)
(cd "$S20GA/invoker" && HOME="$S20GA_HOME" "$REPO_ROOT/setup.sh" --global -F) \
    > "$S20GA/refresh.log" 2>&1
assert_equals "$?" "1" "two valid global segmentations block rather than guessing"
assert_hash_equals "$S20GA/home/.claude/CLAUDE.md" "$global_ambiguous_hash" \
    "ambiguous global root remains byte-identical"

start_test "rollback destination race retains every version until explicit verified recovery"
S21=$(scratch_dir full-refresh-rollback-race)
make_git_repo "$S21"
printf 'ROLLBACK_ORIGINAL_DEVELOPER_BYTES\n' > "$S21/CLAUDE.md"
rollback_original_hash=$(hash_file "$S21/CLAUDE.md")
(cd "$S21" && HOME="$S21/.fakehome" \
    FORGE_FULL_REFRESH_FAIL_AFTER='@penultimate' \
    FORGE_FULL_REFRESH_INJECT_ROLLBACK_RACE_RELATIVE='CLAUDE.md' \
    "$REPO_ROOT/setup.sh" -F) > "$S21/rollback.log" 2>&1
assert_equals "$?" "1" "destination race during rollback fails closed"
assert_contains "$S21/CLAUDE.md" 'FORGE_ROLLBACK_DESTINATION_RACE' \
    "concurrently-created rollback destination is never unlinked"
journal21=$(find "$S21/.forge/local/migration-journals" -name '*.json' -type f -print -quit 2>/dev/null)
assert_matches "$journal21" '"phase": "recovery_required"' \
    "rollback exception durably records recovery_required"
quarantine21=$(find "$S21/.forge/local/migration-staging" -path '*/quarantine/CLAUDE.md' -type f -print -quit 2>/dev/null)
assert_hash_equals "$quarantine21" "$rollback_original_hash" \
    "rollback race retains the exact original in quarantine"
installed21=$(find "$S21/.forge/local/migration-staging" -path '*/rollback-installed/CLAUDE.md' -type f -print -quit 2>/dev/null)
assert_file_exists "$installed21" "rollback race retains the displaced installed version"
mv "$S21/CLAUDE.md" "$S21/rollback-race-preserved.txt"
"$REPO_ROOT/scripts/recover-full-refresh.sh" --journal "$journal21" --target "$S21" \
    > "$S21/recovery.log" 2>&1
assert_equals "$?" "0" "explicit recovery restores after operator preserves the race version"
assert_hash_equals "$S21/CLAUDE.md" "$rollback_original_hash" \
    "verified recovery restores the exact original"
assert_contains "$S21/rollback-race-preserved.txt" 'FORGE_ROLLBACK_DESTINATION_RACE' \
    "explicit recovery leaves the concurrent version preserved separately"

start_test "global full refresh rejects root and noncanonical selected homes before Python"
S22=$(scratch_dir full-refresh-global-home-validation)
mkdir -p "$S22/fake-bin" "$S22/real-home"
cat > "$S22/fake-bin/python3" <<'EOF'
#!/bin/sh
printf 'INVOKED\n' > "$FORGE_FAKE_PYTHON_MARKER"
exit 0
EOF
chmod +x "$S22/fake-bin/python3"
FORGE_FAKE_PYTHON_MARKER="$S22/root-python-invoked" \
    PATH="$S22/fake-bin:/usr/bin:/bin" HOME=/ \
    "$REPO_ROOT/setup.sh" --global -F > "$S22/root.log" 2>&1
assert_equals "$?" "1" "filesystem root is rejected as a selected global home"
assert_file_missing "$S22/root-python-invoked" "root rejection occurs before Python or transaction writes"
FORGE_FAKE_PYTHON_MARKER="$S22/noncanonical-python-invoked" \
    PATH="$S22/fake-bin:/usr/bin:/bin" \
    /bin/bash "$REPO_ROOT/scripts/full-refresh.sh" \
    --target "$S22/real-home/../real-home" --scope global > "$S22/noncanonical.log" 2>&1
assert_equals "$?" "1" "noncanonical selected global home is rejected"
assert_file_missing "$S22/noncanonical-python-invoked" \
    "noncanonical-home rejection occurs before Python or transaction writes"
/bin/bash "$REPO_ROOT/scripts/full-refresh.sh" \
    --target "$S22/missing-home" --scope global > "$S22/missing.log" 2>&1
assert_equals "$?" "1" "nonexistent selected global home is rejected"

cleanup_scratch_dirs
report "test-full-refresh.sh"
