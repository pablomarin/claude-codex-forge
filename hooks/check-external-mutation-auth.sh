#!/usr/bin/env bash
# Defense in depth for unattended investigators, not an approval authenticator.
# Main-session authorization belongs to the human conversation and native host controls.
# Silent success defers to those controls; this hook never emits an allow decision.
set -u
[ "${FORGE_INVESTIGATION_CHILD:-}" = 1 ] || exit 0
input=$(cat 2>/dev/null || true)
if command -v jq >/dev/null 2>&1; then command_text=$(printf '%s' "$input" | jq -r '.tool_input.command // .command // ""' 2>/dev/null || true); else command_text="$input"; fi
case "$command_text" in
 *"gh issue close"*|*"gh pr merge"*|*"gh pr create"*|*"git push"*|*"npm publish"*|*"rm -rf"*|*"rm -r "*|*"Remove-Item -Recurse"*|*"kubectl apply"*|*"kubectl delete"*|*"kubectl patch"*|*"curl -X POST"*|*"curl -X PUT"*|*"curl -X PATCH"*|*"curl -X DELETE"*|*"mcp__"*"create"*|*"mcp__"*"update"*|*"mcp__"*"delete"*)
 printf '%s\n' 'BLOCKED: return the proposed consequential action to the main session for human approval and agent execution through normal host controls.' >&2
 exit 2 ;;
esac
exit 0
