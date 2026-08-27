#!/bin/bash
# PermissionRequest hook: auto-approve Write/Edit on .forge/local/**
#
# Workaround for anthropics/claude-code#36593 — Claude Code v2.1.80+
# regression where path-scoped Write/Edit allow rules in settings.json
# don't auto-approve. The workflow file .forge/local/state.md is written
# on every /new-feature, /fix-bug, and Phase update; without this hook,
# CC v2.1.80+ prompts the user on every state-md write.
#
# PermissionRequest fires only when CC is about to show a permission
# dialog, so this hook adds no overhead to Write/Edit calls that are
# already allowed by other rules.
#
# Input (JSON via stdin): {tool_name, tool_input: {file_path}, cwd, ...}
# Allow:  emit hookSpecificOutput JSON to stdout, exit 0
# Defer:  print nothing, exit 0 (CC falls back to default permission flow)
#
# Opt-out: set CLAUDE_FORGE_AUTO_APPROVE_LOCAL_WRITES=0 to disable.
#
# Fail-open philosophy: any parse error, missing jq, malformed path,
# traversal segment, or unknown tool → silent defer (no allow emitted).
# This hook is a UX improvement, not a security boundary.

# Honor opt-out
if [ "${CLAUDE_FORGE_AUTO_APPROVE_LOCAL_WRITES:-1}" = "0" ]; then
    exit 0
fi

INPUT=$(cat)

# Require jq for safe JSON parsing; defer if absent
command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Only act on Write|Edit; defer everything else
case "$TOOL" in
    Write|Edit) ;;
    *) exit 0 ;;
esac

# Defer on empty path
[ -z "$FILE_PATH" ] && exit 0

# Normalize separators: Windows-style backslashes → forward slashes
NORMALIZED=$(printf '%s' "$FILE_PATH" | tr '\\' '/')

# Reject any traversal segment in the input path (defense in depth).
# Must match '..' as a path segment, not as a substring (so '..foo' is fine).
case "/$NORMALIZED/" in
    *"/../"*) exit 0 ;;
esac

# Resolve relative paths against hook-provided cwd
case "$NORMALIZED" in
    /*) ABS="$NORMALIZED" ;;
    *)  [ -z "$CWD" ] && exit 0; ABS="$CWD/$NORMALIZED" ;;
esac

# Lexically collapse '.' and empty segments. ('..' was already rejected.)
COLLAPSED=$(printf '%s' "$ABS" | awk -F/ '
{
    n = 0
    for (i = 1; i <= NF; i++) {
        if ($i == "" || $i == ".") continue
        out[++n] = $i
    }
    result = ""
    for (i = 1; i <= n; i++) result = result "/" out[i]
    if (result == "") result = "/"
    print result
}')

# Segment match: path must contain /.forge/local/ as a directory boundary.
case "$COLLAPSED" in
    */.forge/local/*|*/.claude/local/*)
        cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
EOF
        ;;
esac

exit 0
