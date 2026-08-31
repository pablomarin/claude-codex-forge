#!/usr/bin/env bash
# Defense in depth only. The real boundary is absent credentials/tools/runner in child config.
set -u
[ -z "${FORGE_DISPATCH_MODE:-}" ] || exit 0
input=$(cat 2>/dev/null || true)
if command -v jq >/dev/null 2>&1; then command_text=$(printf '%s' "$input" | jq -r '.tool_input.command // .command // ""' 2>/dev/null || true); else command_text="$input"; fi
case "$command_text" in
  *"gh issue close"*|*"gh pr merge"*|*"kubectl apply"*|*"kubectl delete"*|*"kubectl patch"*|*"curl -X POST"*|*"curl -X PUT"*|*"curl -X PATCH"*|*"curl -X DELETE"*|*"mcp__"*"create"*|*"mcp__"*"update"*|*"mcp__"*"delete"*)
    printf '%s\n' 'BLOCKED: external mutation remains human-executed in Forge v1. Prepare a pending action, then ask the developer to run the exact command in their terminal.' >&2
    exit 2 ;;
esac
exit 0
