#!/bin/bash
# PostToolUse formatter for Claude Write/Edit and Codex apply_patch payloads.
# Patch bodies are parsed as inert text; they are never evaluated by a shell.
set -u
INPUT=$(cat 2>/dev/null)
command -v jq >/dev/null 2>&1 || { printf '{}\n'; exit 0; }
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // .tool // ""' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)
[ -n "$CWD" ] || CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] || ROOT="$CWD"
ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) || { printf '{}\n'; exit 0; }

case "$TOOL" in
    Write|Edit)
        PATHS=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)
        ;;
    apply_patch)
        # Recognize only patch file headers. Semicolons, substitutions, and other
        # body text remain data and can never become a command.
        PATHS=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .tool_input.patch // .input // ""' 2>/dev/null \
            | sed -nE 's/^\*\*\* (Add|Update) File: //p' | awk '!seen[$0]++')
        ;;
    *) printf '{}\n'; exit 0 ;;
esac

format_one() {
    local file_path="$1" abs base ext search root parent physical
    [ -n "$file_path" ] || return 0
    case "/$file_path/" in *'/../'*) return 0 ;; esac
    case "$file_path" in /*) abs="$file_path" ;; *) abs="$ROOT/$file_path" ;; esac
    # Lexical containment is checked before any formatter sees the path.
    case "$abs" in "$ROOT"/*) ;; *) return 0 ;; esac
    # Resolve the parent physically so an in-repository symlink cannot redirect
    # a formatter write outside the worktree. Reject a symlinked file as well.
    [ ! -L "$abs" ] || return 0
    parent=$(cd "$(dirname "$abs")" 2>/dev/null && pwd -P) || return 0
    physical="$parent/$(basename "$abs")"
    case "$physical" in "$ROOT"/*) ;; *) return 0 ;; esac
    abs="$physical"
    base=$(basename "$abs")
    case "$base" in .env*|*.key|*.pem|*.secret|*credential*|*password*|*.p12|*.pfx) return 0 ;; esac
    case "$abs" in */.git/*|*/node_modules/*|*/.ssh/*|*/secrets/*) return 0 ;; esac
    ext="${base##*.}"
    case "$ext" in
        py)
            search=$(dirname "$abs"); root=""
            while [ "$search" != / ] && [ -n "$search" ]; do
                if [ -f "$search/pyproject.toml" ]; then root="$search"; break; fi
                search=$(dirname "$search")
            done
            if [ -n "$root" ]; then
                (cd "$root" && uv run ruff check --fix "$abs" 2>/dev/null) || true
                (cd "$root" && uv run ruff format "$abs" 2>/dev/null) || true
            fi
            ;;
        ts|tsx|js|jsx) npx prettier --write "$abs" 2>/dev/null || true ;;
        json) [ "$base" = package-lock.json ] || npx prettier --write "$abs" 2>/dev/null || true ;;
        md) : ;;
    esac
}
while IFS= read -r path; do format_one "$path"; done <<EOF
$PATHS
EOF
printf '{}\n'
exit 0
