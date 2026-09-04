#!/usr/bin/env bash
# Stable native-host metadata adapter and fixed Forge dispatcher launcher.
set -u

die_context() { printf 'BLOCKED[invariant]: %s\n' "$*" >&2; exit 2; }
root_context() { git rev-parse --show-toplevel 2>/dev/null || die_context 'not inside a Git worktree'; }
physical_root_context() { local root; root=$(root_context); (cd "$root" && pwd -P); }
test_mode_allowed_context() {
    local root script_parent script
    root=$(physical_root_context)
    script_parent=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || die_context 'cannot resolve host launcher script'
    script="$script_parent/$(basename "$0")"
    case "$script" in "$root"/*) die_context 'test launcher override is disabled in an installed harness' ;; esac
}
canonical_target_context() {
    local requested="$1" label="$2" parent
    [ -f "$requested" ] && [ ! -L "$requested" ] || die_context "fixed $label dispatcher is unavailable"
    parent=$(cd "$(dirname "$requested")" 2>/dev/null && pwd -P) || die_context "cannot resolve fixed $label dispatcher"
    printf '%s/%s\n' "$parent" "$(basename "$requested")"
}
launcher_context() {
    local root requested
    root=$(physical_root_context)
    requested="$root/.forge/hooks/lib/agent-dispatch.sh"
    if [ "${FORGE_HOST_CONTEXT_TEST_MODE:-0}" = 1 ] && [ -n "${FORGE_HOST_CONTEXT_TEST_LAUNCHER:-}" ]; then
        test_mode_allowed_context
        requested="$FORGE_HOST_CONTEXT_TEST_LAUNCHER"
    fi
    canonical_target_context "$requested" agent
}
council_context() {
    local root requested
    root=$(physical_root_context)
    requested="$root/.forge/hooks/lib/council-dispatch.sh"
    if [ "${FORGE_HOST_CONTEXT_TEST_MODE:-0}" = 1 ]; then
        test_mode_allowed_context
        if [ -n "${FORGE_HOST_CONTEXT_TEST_COUNCIL:-}" ]; then requested="$FORGE_HOST_CONTEXT_TEST_COUNCIL"; else requested=$(launcher_context); fi
    fi
    canonical_target_context "$requested" council
}
validate_host_context() {
    case "$1" in claude|codex) ;; *) die_context "$2 host must be claude or codex" ;; esac
}

mode="${1:-}"
[ "$#" -gt 0 ] && shift
case "$mode" in
hook)
    host=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --host) host="${2:-}"; shift 2 ;;
        *) die_context "unknown hook argument $1" ;;
        esac
    done
    validate_host_context "$host" hook
    cat >/dev/null 2>&1 || true
    ;;
launch)
    host=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --host) host="${2:-}"; shift 2 ;;
        --) shift; break ;;
        *) die_context "unknown launch argument $1" ;;
        esac
    done
    validate_host_context "$host" 'fixed launcher'
    launcher=$(launcher_context)
    council=$(council_context)
    [ "$#" -gt 0 ] || set -- "$launcher"
    requested="$1"
    [ -f "$requested" ] && [ ! -L "$requested" ] || die_context 'requested command is not a canonical Forge dispatcher'
    requested_parent=$(cd "$(dirname "$requested")" 2>/dev/null && pwd -P) || die_context 'cannot resolve requested launcher'
    requested="$requested_parent/$(basename "$requested")"
    [ "$requested" = "$launcher" ] || [ "$requested" = "$council" ] || die_context 'requested command is not a canonical Forge dispatcher'
    export FORGE_NATIVE_HOST="$host"
    unset FORGE_NATIVE_SESSION_ID FORGE_HOST_CONTEXT_FILE FORGE_HOST_CONTEXT_LAUNCHER_HASH
    exec "$@"
    ;;
*) die_context 'usage: host-context.sh hook|launch' ;;
esac
