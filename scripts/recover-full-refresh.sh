#!/usr/bin/env bash
set -u
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P) || exit 1
JOURNAL=""
TARGET=$(pwd -P)
while [ "$#" -gt 0 ]; do
    case "$1" in
        --journal) JOURNAL="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        *) echo "BLOCKED: unknown recover-full-refresh option: $1" >&2; exit 1 ;;
    esac
done
[ -n "$JOURNAL" ] || { echo "Usage: recover-full-refresh.sh --journal FILE [--target ROOT]" >&2; exit 1; }
exec python3 "$SCRIPT_DIR/scripts/merge-settings.py" recover-full-refresh --journal "$JOURNAL" --target "$TARGET"
