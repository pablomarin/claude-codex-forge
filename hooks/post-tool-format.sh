#!/bin/bash
# .claude/hooks/post-tool-format.sh
# This hook runs after Edit or Write tool is used.
# It automatically formats the modified file based on its type.
#
# Optional: jq (recommended for robust JSON parsing, falls back to grep)
# Optional: ruff (for Python), prettier (for JS/TS/JSON/MD)
#
# Security: Follows Anthropic best practices
# - Validates and sanitizes inputs
# - Blocks path traversal attacks
# - Skips sensitive files
# - Uses quoted variables

set -e

# Read and parse input
INPUT=$(cat)

# Parse file_path (jq preferred, grep fallback)
if command -v jq &> /dev/null; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
else
    FILE_PATH=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Exit if no file path
[ -z "$FILE_PATH" ] && exit 0

# Security: Block path traversal
if echo "$FILE_PATH" | grep -q '\.\.'; then
    echo "Security: Path traversal blocked" >&2
    exit 0
fi

# Security: Skip sensitive files
BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in
    .env*|*.key|*.pem|*.secret|*credential*|*password*|*.p12|*.pfx)
        exit 0
        ;;
esac

# Skip files in sensitive directories
case "$FILE_PATH" in
    *.git/*|*node_modules/*|*.ssh/*|*secrets/*)
        exit 0
        ;;
esac

# Get file extension
EXTENSION="${FILE_PATH##*.}"

# Format based on file type
case "$EXTENSION" in
    py)
        # Python files — format with ruff, using the nearest pyproject.toml as config.
        # Walks up from the edited file to find the project root (works for
        # monorepo layouts like backend/src/ or apps/api/, not just flat repos).
        # Runs `ruff check --fix` and `ruff format` independently so a lint
        # failure does not skip formatting.

        # Normalize to absolute path (so dir walking works regardless of cwd)
        ABS_PATH="$FILE_PATH"
        case "$ABS_PATH" in
            /*) ;;
            *) ABS_PATH="${CLAUDE_PROJECT_DIR:-$(pwd)}/$FILE_PATH" ;;
        esac

        # Walk up from the file's directory looking for pyproject.toml
        SEARCH_DIR="$(dirname "$ABS_PATH")"
        RUFF_ROOT=""
        while [ "$SEARCH_DIR" != "/" ] && [ -n "$SEARCH_DIR" ]; do
            if [ -f "$SEARCH_DIR/pyproject.toml" ]; then
                RUFF_ROOT="$SEARCH_DIR"
                break
            fi
            SEARCH_DIR="$(dirname "$SEARCH_DIR")"
        done

        if [ -n "$RUFF_ROOT" ]; then
            # Run from the project root so ruff picks up [tool.ruff] config
            (cd "$RUFF_ROOT" && uv run ruff check --fix "$ABS_PATH" 2>/dev/null) || true
            (cd "$RUFF_ROOT" && uv run ruff format "$ABS_PATH" 2>/dev/null) || true
        fi
        # If no pyproject.toml found anywhere above: skip silently.
        ;;
    ts|tsx|js|jsx)
        # TypeScript/JavaScript files - format with prettier
        npx prettier --write "$FILE_PATH" 2>/dev/null || true
        ;;
    json)
        # JSON files - format with prettier (skip package-lock.json)
        [ "$BASENAME" = "package-lock.json" ] && exit 0
        npx prettier --write "$FILE_PATH" 2>/dev/null || true
        ;;
    md)
        # Markdown is intentionally NOT auto-formatted (v5.56). The harness ships
        # hand-authored markdown (rules/, commands/, skills/, agents/, docs/) that
        # uses an escaped-backtick convention (\`...\`) and sentinel/byte-pinned
        # blocks enforced by tests/template/test-contracts.sh. prettier 3.x corrupts
        # that markdown — it merges escaped-backtick continuation lines and strips
        # the spaces around inline code — which both garbles the prose and breaks
        # the byte-identical contracts. Skipping is strictly safer than reformatting.
        :
        ;;
esac

exit 0
