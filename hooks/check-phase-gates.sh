#!/usr/bin/env bash
# hooks/check-phase-gates.sh — PreToolUse phase-gate guard.
# Delegates policy to hooks/lib/forge-workflow.sh so CLI and hook behavior share one controller.

set -u

INPUT=""
if [ ! -t 0 ]; then
    INPUT=$(cat 2>/dev/null || true)
fi

ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$ROOT" ]; then
    if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
        CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
    else
        CWD=$(printf '%s' "$INPUT" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"cwd"[[:space:]]*:[[:space:]]*"//;s/"$//' || true)
    fi
    if [ -n "${CWD:-}" ] && [ -d "$CWD" ]; then
        ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")
    else
        ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    fi
fi

LIB="$ROOT/.claude/hooks/lib/forge-workflow.sh"
[ -f "$LIB" ] || LIB="$ROOT/hooks/lib/forge-workflow.sh"
[ -f "$LIB" ] || exit 0

printf '%s' "$INPUT" | bash "$LIB" check-tool
