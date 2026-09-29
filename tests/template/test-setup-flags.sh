#!/usr/bin/env bash
# Focused contract for the public setup mode flags.

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

snapshot_project() {
    local root="$1"
    (
        cd "$root" || exit 1
        find . -path './.git' -prune -o -path './.fakehome' -prune -o -type f -print \
            | LC_ALL=C sort \
            | while IFS= read -r file; do
                printf '%s\t%s\n' "$file" "$(hash_file "$file")"
            done
    )
}

start_test "help presents upgrade and force without case-sensitive mode selection"
S1=$(scratch_dir setup-flags-help)
"$REPO_ROOT/setup.sh" --help > "$S1/help.log" 2>&1
assert_contains "$S1/help.log" "-u, --upgrade" "help exposes routine upgrade"
assert_contains "$S1/help.log" "-f, --force" "help exposes authoritative force reconciliation"
assert_contains "$S1/help.log" "transactional full installation/reconciliation" \
    "force is described as the full reconciliation mode"
assert_not_contains "$S1/help.log" "-F, --full-refresh" \
    "deprecated uppercase -F is no longer advertised"
assert_not_contains "$S1/help.log" "Set up global" \
    "help does not advertise global installation"

start_test "global install is retired and non-mutating"
G=$(scratch_dir retired-global-flag)
git -C "$G" init -q
mkdir -p "$G/home"
mkdir -p "$G/.fakehome"
before=$(snapshot_project "$G")
(cd "$G" && HOME="$G/home" "$REPO_ROOT/setup.sh" --global) > "$G/.fakehome/global.log" 2>&1
assert_equals "$?" "1" "--global exits nonzero"
after=$(snapshot_project "$G")
assert_equals "$after" "$before" "--global changes no project bytes"
assert_contains "$G/.fakehome/global.log" 'global installation is retired' \
    "retired flag explains project-only installation"
assert_contains "$G/.fakehome/global.log" '--retire-global' "retired flag names cleanup path"

start_test "legacy global retirement is explicit and preview-only by default"
R=$(scratch_dir retire-global-routing)
mkdir -p "$R/home/.claude" "$R/logs"
printf 'PERSONAL_HOME_BYTES\n' > "$R/home/.claude/personal.txt"
personal_hash=$(hash_file "$R/home/.claude/personal.txt")
HOME="$R/home" "$REPO_ROOT/setup.sh" --retire-global > "$R/logs/unix.log" 2>&1
assert_equals "$?" "0" "Unix setup routes retirement preview"
assert_contains "$R/logs/unix.log" 'RETIRE_GLOBAL_DIGEST=' \
    "Unix retirement preview emits a confirmation digest"
assert_hash_equals "$R/home/.claude/personal.txt" "$personal_hash" \
    "Unix retirement preview preserves personal home bytes"
assert_file_missing "$R/home/.forge" "Unix retirement preview creates no Forge home"
if command -v pwsh >/dev/null 2>&1; then
    HOME="$R/home" pwsh -NoLogo -NoProfile -File "$REPO_ROOT/setup.ps1" -RetireGlobal \
        > "$R/logs/windows.log" 2>&1
    assert_equals "$?" "0" "PowerShell setup routes retirement preview"
    assert_contains "$R/logs/windows.log" 'RETIRE_GLOBAL_DIGEST=' \
        "PowerShell retirement preview emits a confirmation digest"
    assert_hash_equals "$R/home/.claude/personal.txt" "$personal_hash" \
        "PowerShell retirement preview preserves personal home bytes"
    assert_file_missing "$R/home/.forge" "PowerShell retirement preview creates no Forge home"
else
    skip_test "pwsh unavailable; PowerShell retirement routing covered by Windows CI"
fi

start_test "project setup leaves an unrelated project and home unchanged"
A=$(scratch_dir project-only-a)
B=$(scratch_dir project-only-b)
git -C "$A" init -q
git -C "$B" init -q
mkdir -p "$A/home/.claude"
printf 'HOME_SENTINEL\n' > "$A/home/.claude/personal.txt"
b_hash=$(snapshot_project "$B")
home_hash=$(hash_file "$A/home/.claude/personal.txt")
(cd "$A" && HOME="$A/home" "$REPO_ROOT/setup.sh") > "$A/setup.log" 2>&1
assert_equals "$?" "0" "project-only setup succeeds"
assert_equals "$(snapshot_project "$B")" "$b_hash" "uninstalled project is unchanged"
assert_hash_equals "$A/home/.claude/personal.txt" "$home_hash" "home is unchanged"
assert_file_missing "$A/home/.forge/version" "no global Forge is created"
assert_contains "$A/setup.log" \
  'NATIVE_GOAL_RUNTIME: PENDING reason=live-qualification-not-run' \
  "project setup reports deterministic install without overstating live qualification"

start_test "active ownership and materialization are project-only"
if awk -F '\t' '$1 !~ /^#/ && $6 == "global" { found=1 } END { exit found ? 0 : 1 }' \
    "$REPO_ROOT/manifests/managed-v6.tsv"; then
    fail "managed manifest contains no active global scope rows"
else
    pass "managed manifest contains no active global scope rows"
fi
MATERIALIZE_GLOBAL=$(scratch_dir materialize-global-rejected)
mkdir -p "$MATERIALIZE_GLOBAL/target"
bash "$REPO_ROOT/scripts/materialize-adapters.sh" \
    --repo-root "$REPO_ROOT" --target "$MATERIALIZE_GLOBAL/target" \
    --scope global --platform unix --release-version 6.3 \
    > "$MATERIALIZE_GLOBAL/output.log" 2>&1
assert_equals "$?" "1" "active materializer rejects global scope"
assert_file_missing "$MATERIALIZE_GLOBAL/target/.forge/version" \
    "rejected global scope writes no version"

start_test "force dry-run previews the authoritative transaction without writes"
S2=$(scratch_dir setup-flags-preview)
git -C "$S2" init -q
before=$(snapshot_project "$S2")
run_setup "$S2" "$S2/.fakehome/preview.log" -f --dry-run
assert_equals "$?" "0" "-f --dry-run succeeds"
after=$(snapshot_project "$S2")
assert_equals "$after" "$before" "-f --dry-run leaves project files unchanged"
assert_file_missing "$S2/.forge/version" "dry-run does not publish the Forge stamp"
assert_contains "$S2/.fakehome/preview.log" "UPGRADE: READY" "dry-run reports transaction readiness"

start_test "force executes the authoritative full reconciliation"
S3=$(scratch_dir setup-flags-force)
git -C "$S3" init -q
run_setup "$S3" "$S3/force.log" -f
assert_equals "$?" "0" "-f succeeds on a fresh project"
EXPECTED_RELEASE=$(sed -nE 's/^##[[:space:]]+([0-9]+\.[0-9]+).*/\1/p' \
    "$REPO_ROOT/docs/CHANGELOG.md" | head -1)
assert_equals "$(tr -d '\r\n' < "$S3/.forge/version")" "$EXPECTED_RELEASE" \
    "project stamp records the exact Forge release"
assert_contains "$S3/force.log" "FORGE_VERSION: $EXPECTED_RELEASE" \
    "setup reports the installed project release"
assert_file_missing "$S3/.claude/.forge-version" \
    "project does not retain the Claude-specific version pin"
assert_file_missing "$S3/.fakehome/.claude/.forge-version" \
    "project setup writes no machine-wide version stamp"
assert_contains "$S3/force.log" "UPGRADE: READY" "-f reports transactional completion"
mkdir -p "$S3/docs"
printf '%s\n' 'FORCE_CONTEXT_SENTINEL' > "$S3/docs/agent-context.md"
run_setup "$S3" "$S3/force-rerun.log" -f
assert_equals "$?" "0" "-f can reconcile an existing v6 installation"
assert_contains "$S3/docs/agent-context.md" "FORCE_CONTEXT_SENTINEL" \
    "-f preserves project-owned agent context"

start_test "upgrade preserves project-owned and custom configuration"
S4=$(scratch_dir setup-flags-upgrade)
git -C "$S4" init -q
run_setup "$S4" "$S4/install.log"
assert_equals "$?" "0" "initial installation succeeds"
mkdir -p "$S4/docs"
printf '%s\n' 'PROJECT_CONTEXT_SENTINEL' > "$S4/docs/agent-context.md"
python3 - "$S4/.mcp.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data.setdefault("mcpServers", {})["project-custom"] = {"command": "custom-mcp"}
path.write_text(json.dumps(data, indent=2) + "\n")
PY
run_setup "$S4" "$S4/upgrade.log" --upgrade
assert_equals "$?" "0" "--upgrade succeeds on an existing v6 installation"
assert_contains "$S4/docs/agent-context.md" "PROJECT_CONTEXT_SENTINEL" \
    "--upgrade preserves agent context"
assert_contains "$S4/.mcp.json" '"project-custom"' "--upgrade preserves custom MCP entries"
assert_contains "$S4/upgrade.log" "RUNTIME_QUALIFICATION: final owner '$REPO_ROOT/scripts/qualify-runtime-final.sh'; live project" \
    "manual and agent-assisted upgrade name the final runtime qualifier"
assert_contains "$S4/upgrade.log" "$REPO_ROOT/docs/qualification/agent-mode-selection.md" \
    "runtime qualification guidance names the required operator-evidence guide"
assert_not_contains "$S4/upgrade.log" "VERIFY_RUNTIME:" \
    "upgrade does not advertise the non-certifying verifier as final qualification"

start_test "legacy full-refresh spelling remains a deprecated compatibility alias"
S5=$(scratch_dir setup-flags-legacy)
git -C "$S5" init -q
run_setup "$S5" "$S5/legacy-short.log" -F --dry-run
assert_equals "$?" "0" "legacy -F alias still succeeds"
assert_contains "$S5/legacy-short.log" "DEPRECATED: -F is an alias for -f" \
    "legacy -F prints migration guidance"
run_setup "$S5" "$S5/legacy-long.log" --full-refresh --dry-run
assert_equals "$?" "0" "legacy --full-refresh alias still succeeds"
assert_contains "$S5/legacy-long.log" "DEPRECATED: --full-refresh is an alias for --force" \
    "legacy long form prints migration guidance"

start_test "PowerShell exposes the same public modes"
assert_contains "$REPO_ROOT/setup.ps1" 'Write-Host "  -u, -Upgrade' \
    "PowerShell help exposes routine upgrade"
assert_contains "$REPO_ROOT/setup.ps1" 'Write-Host "  -f, -Force' \
    "PowerShell help exposes authoritative force reconciliation"
assert_not_contains "$REPO_ROOT/setup.ps1" 'Write-Host "  -R, -FullRefresh' \
    "PowerShell no longer advertises the legacy full-refresh mode"
assert_contains "$REPO_ROOT/setup.ps1" 'DEPRECATED: -FullRefresh/-R is an alias for -Force' \
    "PowerShell retains a diagnosed compatibility alias"

report "setup flag contract"
