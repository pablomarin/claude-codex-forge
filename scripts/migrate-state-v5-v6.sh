#!/usr/bin/env bash
set -u
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P) || exit 1
SOURCE="${1:-.claude/local/state.md}"
DESTINATION="${2:-.forge/local/state.md}"
command -v python3 >/dev/null 2>&1 || { echo "BLOCKED: Python 3 is required for state translation" >&2; exit 1; }
exec python3 "$SCRIPT_DIR/scripts/merge-settings.py" migrate-state-v5-v6 \
    --source "$SOURCE" --destination "$DESTINATION"
