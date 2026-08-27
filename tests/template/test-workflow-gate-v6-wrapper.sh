#!/usr/bin/env bash
# Test-only compatibility adapter: historical gate fixtures were authored at the
# v5 path. Promote their bytes to the v6 schema before invoking the real hook.
set -u
INPUT=$(cat)
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if command -v jq >/dev/null 2>&1; then target=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true); else target=""; fi
[ -n "$target" ] && [ -d "$target" ] || target=$(pwd -P)
root=$(git -C "$target" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$target")
if [ -f "$root/.claude/local/state.md" ] && [ ! -e "$root/.forge/local/state.md" ]; then
    mkdir -p "$root/.forge/local"
    { printf '<!-- forge:state-schema v6 -->\n'; cat "$root/.claude/local/state.md"; } > "$root/.forge/local/state.md"
fi
printf '%s' "$INPUT" | bash "$REPO_ROOT/hooks/check-workflow-gates.sh"
exit $?
