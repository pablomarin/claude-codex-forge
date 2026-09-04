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
assert_contains "$S3/.forge/version" "6" "-f installs the canonical v6 harness"
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
