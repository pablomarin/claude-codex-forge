#!/usr/bin/env bash
# Stable primary-checkout Codex hook router. Delegates policy to event worktree.
set -e

hook="${1:-}"
case "$hook" in
    *.sh) case "$hook" in */*|*..*) echo "BLOCKED: unsafe hook target" >&2; exit 2 ;; esac ;;
    *) echo "BLOCKED: hook target must be a canonical .sh basename" >&2; exit 2 ;;
esac

payload=$(mktemp "${TMPDIR:-/tmp}/forge-codex-event.XXXXXX")
trap 'rm -f "$payload"' EXIT HUP INT TERM
cat > "$payload"
cwd=$(sed -nE 's/.*"cwd"[[:space:]]*:[[:space:]]*"([^"\\]*)".*/\1/p' "$payload" | head -1)
[ -n "$cwd" ] && [ -d "$cwd" ] || { echo "BLOCKED: Codex event has no trusted cwd" >&2; exit 3; }
case "$cwd" in /*) ;; *) echo "BLOCKED: Codex event cwd is not absolute" >&2; exit 3 ;; esac

registered_root=$(cd "$(dirname "$0")/../../.." && pwd -P)
registered_common=$(git -C "$registered_root" rev-parse --git-common-dir 2>/dev/null) || exit 4
case "$registered_common" in /*) ;; *) registered_common="$registered_root/$registered_common" ;; esac
registered_common=$(cd "$registered_common" && pwd -P)

event_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || { echo "BLOCKED: event cwd is outside Git" >&2; exit 4; }
event_root=$(cd "$event_root" && pwd -P)
event_common=$(git -C "$event_root" rev-parse --git-common-dir 2>/dev/null) || exit 4
case "$event_common" in /*) ;; *) event_common="$event_root/$event_common" ;; esac
event_common=$(cd "$event_common" && pwd -P)
[ "$event_common" = "$registered_common" ] || { echo "BLOCKED: event Git common directory differs from registered repository" >&2; exit 5; }

target="$event_root/.forge/hooks/$hook"
[ -f "$target" ] && [ ! -L "$target" ] || { echo "BLOCKED: canonical hook absent from event worktree" >&2; exit 6; }
(cd "$event_root" && bash "$target" < "$payload")
