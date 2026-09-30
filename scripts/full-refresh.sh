#!/usr/bin/env bash
# Authoritative, transactional Forge full refresh (Unix entrypoint).

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P) || exit 1
TARGET=""
SCOPE=project
DRY_RUN=false
RELEASE_VERSION=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --scope) SCOPE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --release-version) RELEASE_VERSION="$2"; shift 2 ;;
        *) echo "BLOCKED: unknown full-refresh option: $1" >&2; exit 1 ;;
    esac
done
[ -n "$TARGET" ] || TARGET=$(pwd -P)
case "$SCOPE" in project) ;; *) echo "BLOCKED: active full refresh is project-only" >&2; exit 1 ;; esac
[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+$ ]] || { echo "BLOCKED: invalid release version" >&2; exit 2; }

if ! command -v python3 >/dev/null 2>&1; then
    echo "BLOCKED: Python 3 is required for authoritative JSON/state migration; no files were changed." >&2
    exit 1
fi
if [ -L "$TARGET" ] || [ ! -d "$TARGET" ]; then
    echo "BLOCKED: transaction root is missing or a symlink: $TARGET" >&2
    exit 1
fi
SELECTED_TARGET="$TARGET"
case "$SELECTED_TARGET" in
    /*) LEXICAL_TARGET="$SELECTED_TARGET" ;;
    *) LEXICAL_TARGET="$(pwd -P)/$SELECTED_TARGET" ;;
esac
TARGET=$(cd "$SELECTED_TARGET" 2>/dev/null && pwd -P) || exit 1
refresh_args=(full-refresh --repo-root "$SCRIPT_DIR" --target "$TARGET" --scope "$SCOPE" --platform unix --release-version "$RELEASE_VERSION")
[ "$DRY_RUN" = true ] && refresh_args+=(--dry-run)
export PYTHONDONTWRITEBYTECODE=1
exec python3 "$SCRIPT_DIR/scripts/merge-settings.py" "${refresh_args[@]}"
