#!/bin/bash
# PreCompact owns only the volatile Forge memory layer. Native host memories are
# optional context and are never copied or inspected by Forge.
set -u

INPUT=$(cat 2>/dev/null)
forge_allow() {
    printf '%s' "$INPUT" | grep -qE '"host"[[:space:]]*:[[:space:]]*"codex"' && printf '{}\n'
    exit 0
}
TRIGGER=unknown
CWD=""
if command -v jq >/dev/null 2>&1; then
    TRIGGER=$(printf '%s' "$INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null || echo unknown)
    CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)
fi
ROOT="${CLAUDE_PROJECT_DIR:-$CWD}"
[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
TOP=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$TOP" ] && ROOT="$TOP"
ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) || forge_allow
MEMORY_DIR="$ROOT/.forge/local/memory"
case "$MEMORY_DIR" in "$ROOT"/.forge/local/memory) ;; *) forge_allow ;; esac
mkdir -p "$MEMORY_DIR" 2>/dev/null || forge_allow
TOPIC_FILES=$(find "$MEMORY_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
echo "Pre-compact Forge memory: trigger=$TRIGGER, local=.forge/local/memory, topic_files=$TOPIC_FILES" >&2
echo "Save volatile drafts only under .forge/local/memory; promote vetted learnings to .forge/memory through review." >&2
forge_allow
