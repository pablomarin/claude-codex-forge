#!/usr/bin/env bash
# Behavioral contract for preview-first retirement of the legacy machine-wide Forge harness.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

snapshot_project() {
    local root="$1"
    (
        cd "$root" || exit 1
        find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
            printf '%s\t%s\n' "$file" "$(hash_file "$file")"
        done
    )
}

run_retire() {
    local home="$1" log="$2"
    shift 2
    python3 "$REPO_ROOT/scripts/retire-global.py" \
        --repo-root "$REPO_ROOT" --home "$home" --platform unix "$@" >"$log" 2>&1
}

seed_owned_helper() {
    local home="$1"
    mkdir -p "$home/.forge/bin"
    printf 'owned helper\n' > "$home/.forge/bin/forge-goal-authorize"
    printf '.forge/bin/forge-goal-authorize\t%s\tv6\n' \
        "$(hash_file "$home/.forge/bin/forge-goal-authorize")" \
        > "$home/.forge/installed-files.tsv"
}

start_test "preview is read-only and proves only legacy Forge-owned bytes"
H=$(scratch_dir retire-global)
mkdir -p "$H/home/.forge/bin" "$H/home/.claude" "$H/home/.codex"
printf '6\n' > "$H/home/.forge/version"
printf 'PERSONAL CLAUDE\n<!-- forge:begin v6 -->\nOLD FORGE\n<!-- forge:end v6 -->\n' \
  > "$H/home/.claude/CLAUDE.md"
printf 'PERSONAL CODEX\n<!-- forge:begin v6 -->\nOLD FORGE\n<!-- forge:end v6 -->\n' \
  > "$H/home/.codex/AGENTS.md"
printf 'owned helper\n' > "$H/home/.forge/bin/forge-goal-authorize"
helper_hash=$(hash_file "$H/home/.forge/bin/forge-goal-authorize")
printf '.forge/bin/forge-goal-authorize\t%s\tv6\n' "$helper_hash" \
  > "$H/home/.forge/installed-files.tsv"
printf 'KEEP ME\n' > "$H/home/.forge/personal-note.txt"
before=$(snapshot_project "$H/home")
run_retire "$H/home" "$H/preview.log"
assert_equals "$?" "0" "global retirement preview succeeds"
after=$(snapshot_project "$H/home")
assert_equals "$after" "$before" "preview writes no bytes"
assert_contains "$H/preview.log" 'REMOVE .forge/bin/forge-goal-authorize' \
  "preview proves installed helper ownership"
assert_contains "$H/preview.log" 'PRESERVE .claude/CLAUDE.md personal-bytes' \
  "preview preserves personal Claude bytes"
assert_contains "$H/preview.log" 'PRESERVE .forge/personal-note.txt unknown' \
  "preview preserves an unknown Forge-home file"
assert_contains "$H/preview.log" 'RETIRE_GLOBAL_DIGEST=' "preview emits digest"

DIGEST=$(sed -n 's/^RETIRE_GLOBAL_DIGEST=//p' "$H/preview.log")
run_retire "$H/home" "$H/apply.log" --apply --digest "$DIGEST"
assert_equals "$?" "0" "digest-bound apply succeeds"
assert_file_missing "$H/home/.forge/bin/forge-goal-authorize" "owned helper is removed"
assert_file_missing "$H/home/.forge/installed-files.tsv" "legacy ownership receipt is removed"
assert_contains "$H/home/.claude/CLAUDE.md" 'PERSONAL CLAUDE' "personal Claude bytes survive"
assert_not_contains "$H/home/.claude/CLAUDE.md" '<!-- forge:begin v6 -->' "Claude Forge block is removed"
assert_contains "$H/home/.codex/AGENTS.md" 'PERSONAL CODEX' "personal Codex bytes survive"
assert_contains "$H/home/.forge/personal-note.txt" 'KEEP ME' "unknown Forge-home file survives"
assert_contains "$H/apply.log" 'RETIRE_GLOBAL: COMPLETE' "apply reports completion"

start_test "modified installed files and malformed marker blocks are blocked"
M=$(scratch_dir retire-global-modified)
seed_owned_helper "$M/home"
printf 'changed after receipt\n' > "$M/home/.forge/bin/forge-goal-authorize"
run_retire "$M/home" "$M/modified.log"
assert_equals "$?" "2" "modified installed helper blocks preview"
assert_contains "$M/modified.log" 'BLOCKED .forge/bin/forge-goal-authorize' \
    "modified helper is visibly blocked"

mkdir -p "$M/markers/.claude"
printf '<!-- forge:begin v6 -->\none\n<!-- forge:begin v6 -->\ntwo\n<!-- forge:end v6 -->\n' \
    > "$M/markers/.claude/CLAUDE.md"
run_retire "$M/markers" "$M/markers.log"
assert_equals "$?" "2" "duplicate marker blocks preview"
assert_contains "$M/markers.log" 'BLOCKED .claude/CLAUDE.md' "duplicate marker is visible"

start_test "symlinked roots are rejected before planning"
L=$(scratch_dir retire-global-link)
mkdir -p "$L/home" "$L/elsewhere"
ln -s "$L/elsewhere" "$L/home/.forge"
before_link=$(snapshot_project "$L/home")
run_retire "$L/home" "$L/link.log"
assert_equals "$?" "2" "symlinked .forge is rejected"
assert_equals "$(snapshot_project "$L/home")" "$before_link" "link rejection writes no bytes"
assert_contains "$L/link.log" 'BLOCKED .forge' "link rejection names the unsafe path"

start_test "partial installs retire safely without requiring unrelated files"
P=$(scratch_dir retire-global-partial)
mkdir -p "$P/home/.claude"
printf 'BEFORE\n<!-- forge:begin v6 -->\nOLD\n<!-- forge:end v6 -->\nAFTER\n' \
    > "$P/home/.claude/CLAUDE.md"
run_retire "$P/home" "$P/preview.log"
assert_equals "$?" "0" "partial installation preview succeeds"
PDIGEST=$(sed -n 's/^RETIRE_GLOBAL_DIGEST=//p' "$P/preview.log")
run_retire "$P/home" "$P/apply.log" --apply --digest "$PDIGEST"
assert_equals "$?" "0" "partial installation apply succeeds"
assert_contains "$P/home/.claude/CLAUDE.md" 'BEFORE' "partial cleanup preserves prefix"
assert_contains "$P/home/.claude/CLAUDE.md" 'AFTER' "partial cleanup preserves suffix"
assert_not_contains "$P/home/.claude/CLAUDE.md" 'OLD' "partial cleanup removes bounded Forge bytes"

mkdir -p "$P/custom/.claude"
printf 'CUSTOM CLAUDE ONLY\n' > "$P/custom/.claude/CLAUDE.md"
run_retire "$P/custom" "$P/custom.log"
assert_equals "$?" "0" "custom file without a Forge marker is not treated as an installation"
assert_contains "$P/custom.log" 'PRESERVE .claude/CLAUDE.md no-forge-marker' \
    "unowned custom adapter is visibly preserved"

start_test "settings cleanup removes only exact historical global values"
J=$(scratch_dir retire-global-json)
mkdir -p "$J/home/.claude"
python3 - "$REPO_ROOT/manifests/legacy-v6-global-settings.json" "$J/home/.claude/settings.json" <<'PY'
import json
import pathlib
import sys

settings = json.loads(pathlib.Path(sys.argv[1]).read_text())
settings["personal"] = {"keep": True}
settings["permissions"]["deny"].append("PERSONAL_DENY")
pathlib.Path(sys.argv[2]).write_text(json.dumps(settings, indent=2) + "\n")
PY
run_retire "$J/home" "$J/preview.log"
assert_equals "$?" "0" "mixed settings preview succeeds"
JDIGEST=$(sed -n 's/^RETIRE_GLOBAL_DIGEST=//p' "$J/preview.log")
run_retire "$J/home" "$J/apply.log" --apply --digest "$JDIGEST"
assert_equals "$?" "0" "mixed settings apply succeeds"
assert_contains "$J/home/.claude/settings.json" 'PERSONAL_DENY' "personal list entry survives"
assert_contains "$J/home/.claude/settings.json" '"keep": true' "personal JSON object survives"
assert_not_contains "$J/home/.claude/settings.json" 'forge-goal-authorize' \
    "historical Forge settings values are removed"

start_test "apply rejects a wrong digest and post-preview byte changes"
D=$(scratch_dir retire-global-digest)
mkdir -p "$D/home/.claude"
printf 'PERSONAL\n<!-- forge:begin v6 -->\nOLD\n<!-- forge:end v6 -->\n' \
    > "$D/home/.claude/CLAUDE.md"
run_retire "$D/home" "$D/preview.log"
DDIGEST=$(sed -n 's/^RETIRE_GLOBAL_DIGEST=//p' "$D/preview.log")
before_wrong=$(snapshot_project "$D/home")
run_retire "$D/home" "$D/wrong.log" --apply --digest "0000000000000000000000000000000000000000000000000000000000000000"
assert_equals "$?" "2" "wrong digest blocks apply"
assert_equals "$(snapshot_project "$D/home")" "$before_wrong" "wrong digest writes no bytes"

printf 'CHANGED\n' >> "$D/home/.claude/CLAUDE.md"
before_changed=$(snapshot_project "$D/home")
run_retire "$D/home" "$D/changed.log" --apply --digest "$DDIGEST"
assert_equals "$?" "2" "post-preview mutation blocks apply"
assert_equals "$(snapshot_project "$D/home")" "$before_changed" "changed plan writes no bytes"

start_test "PowerShell runner discovers the parity suite"
assert_file_exists "$REPO_ROOT/tests/template/test-retire-global.ps1" \
    "PowerShell retirement suite exists"
assert_contains "$REPO_ROOT/tests/template/run-all.ps1" '-Filter "test-*.ps1"' \
    "PowerShell runner auto-discovers the retirement suite"


report "test-retire-global.sh"
