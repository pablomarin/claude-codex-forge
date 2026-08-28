#!/usr/bin/env bash
# Protected, one-current native-host receipt and fixed dispatcher launcher.
set -u

die_context() { printf 'BLOCKED[invariant]: %s\n' "$*" >&2; exit 2; }
hash_stream_context() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'; else sha256sum | awk '{print $1}'; fi; }
hash_file_context() { [ -f "$1" ] && [ ! -L "$1" ] && hash_stream_context < "$1" || printf 'MISSING'; }
root_context() { git rev-parse --show-toplevel 2>/dev/null || die_context 'not inside a Git worktree'; }
physical_root_context() { local root; root=$(root_context); (cd "$root" && pwd -P); }
identity_context() { local root common; root=$(physical_root_context); common=$(git -C "$root" rev-parse --git-common-dir 2>/dev/null) || die_context 'cannot resolve Git common directory'; common=$(cd "$root" && cd "$common" && pwd -P); printf '%s|%s\n' "$root" "$common" | hash_stream_context; }
revision_context() { hash_file_context "$(physical_root_context)/.forge/managed-files.tsv"; }
value_context() {
    local file="$1" key="$2" count
    count=$(awk -F= -v k="$key" '$1==k {n++} END {print n+0}' "$file")
    [ "$count" -eq 1 ] || die_context "context key $key must occur exactly once"
    awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$file"
}
test_mode_allowed_context() {
    local root script_parent script
    root=$(physical_root_context); script_parent=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || die_context 'cannot resolve host launcher script'; script="$script_parent/$(basename "$0")"
    case "$script" in "$root"/*) die_context 'test host authority is disabled in an installed harness' ;; esac
}
authority_root_context() {
    if [ "${FORGE_HOST_CONTEXT_TEST_MODE:-0}" = 1 ]; then
        test_mode_allowed_context
        [ -n "${FORGE_HOST_CONTEXT_TEST_ROOT:-}" ] || die_context 'test authority root is required'
        printf '%s\n' "$FORGE_HOST_CONTEXT_TEST_ROOT"
    else
        printf '%s\n' "${HOME:?}/.forge/host-contexts"
    fi
}
launcher_context() {
    local root requested parent
    root=$(physical_root_context); requested="$root/.forge/hooks/lib/agent-dispatch.sh"
    if [ "${FORGE_HOST_CONTEXT_TEST_MODE:-0}" = 1 ] && [ -n "${FORGE_HOST_CONTEXT_TEST_LAUNCHER:-}" ]; then test_mode_allowed_context; requested="$FORGE_HOST_CONTEXT_TEST_LAUNCHER"; fi
    [ -f "$requested" ] && [ ! -L "$requested" ] || die_context 'fixed dispatcher launcher is unavailable'
    parent=$(cd "$(dirname "$requested")" 2>/dev/null && pwd -P) || die_context 'cannot resolve fixed dispatcher launcher'
    printf '%s/%s\n' "$parent" "$(basename "$requested")"
}
council_context() {
    local root requested parent
    root=$(physical_root_context); requested="$root/.forge/hooks/lib/council-dispatch.sh"
    if [ "${FORGE_HOST_CONTEXT_TEST_MODE:-0}" = 1 ]; then
        test_mode_allowed_context
        if [ -n "${FORGE_HOST_CONTEXT_TEST_COUNCIL:-}" ]; then requested="$FORGE_HOST_CONTEXT_TEST_COUNCIL"; else requested=$(launcher_context); fi
    fi
    [ -f "$requested" ] && [ ! -L "$requested" ] || die_context 'fixed council dispatcher is unavailable'
    parent=$(cd "$(dirname "$requested")" 2>/dev/null && pwd -P) || die_context 'cannot resolve fixed council dispatcher'
    printf '%s/%s\n' "$parent" "$(basename "$requested")"
}
current_context() { local authority identity; authority=$(authority_root_context); identity=$(identity_context); printf '%s/%s/current.ctx\n' "$authority" "$identity"; }
active_context() { local authority identity; authority=$(authority_root_context); identity=$(identity_context); printf '%s/%s/active-%s.ctx\n' "$authority" "$identity" "$1"; }
validate_receipt_context() {
    local file="$1" expected_host="$2" launcher="$3" council="$4" schema host session revision identity launcher_path launcher_hash council_path council_hash issued expires nonce stored body now expected_file
    [ -f "$file" ] && [ ! -L "$file" ] || die_context 'protected current host receipt is required'
    expected_file=$(active_context "$expected_host"); [ "$file" = "$expected_file" ] || die_context 'host receipt is not the protected active-host receipt'
    schema=$(value_context "$file" schema_version); host=$(value_context "$file" active_host); session=$(value_context "$file" session_id)
    revision=$(value_context "$file" context_revision); identity=$(value_context "$file" worktree_identity)
    launcher_path=$(value_context "$file" launcher_path); launcher_hash=$(value_context "$file" launcher_hash)
    council_path=$(value_context "$file" council_path); council_hash=$(value_context "$file" council_hash)
    issued=$(value_context "$file" issued_epoch); expires=$(value_context "$file" expires_epoch); nonce=$(value_context "$file" nonce); stored=$(value_context "$file" receipt_hash)
    [ "$schema" = 2 ] || die_context 'unsupported host receipt schema'
    case "$host" in claude|codex) ;; *) die_context 'invalid host receipt engine' ;; esac
    [ "$host" = "$expected_host" ] || die_context 'active host does not match fixed launcher'
    [ -n "$session" ] && [ -n "$nonce" ] || die_context 'host receipt lacks native session binding'
    [ "$revision" = "$(revision_context)" ] && [ "$identity" = "$(identity_context)" ] || die_context 'host receipt is stale or belongs to another worktree'
    [ "$launcher_path" = "$launcher" ] && [ "$launcher_hash" = "$(hash_file_context "$launcher")" ] || die_context 'host receipt launcher binding mismatch'
    [ "$council_path" = "$council" ] && [ "$council_hash" = "$(hash_file_context "$council")" ] || die_context 'host receipt council binding mismatch'
    case "$issued:$expires" in *[!0-9:]*|:*) die_context 'host receipt time binding is invalid' ;; esac
    now=$(date +%s); [ "$issued" -le "$now" ] && [ "$expires" -ge "$now" ] || die_context 'host receipt is expired or not yet valid'
    body=$(awk -F= '$1!="receipt_hash" {print}' "$file" | hash_stream_context); [ "$stored" = "$body" ] || die_context 'host receipt hash mismatch'
    VALID_CONTEXT_SESSION="$session"; VALID_CONTEXT_HASH="$stored"; VALID_CONTEXT_LAUNCHER_HASH="$launcher_hash"
}
issue_context() {
    local host="$1" session="$2" launcher council authority current active parent tmp active_tmp now expires nonce
    case "$host" in claude|codex) ;; *) die_context 'hook host must be claude or codex' ;; esac
    case "$session" in ''|*$'\n'*|*$'\r'*) die_context 'native SessionStart event has no safe session/thread id' ;; esac
    launcher=$(launcher_context); council=$(council_context); authority=$(authority_root_context); current=$(current_context); active=$(active_context "$host"); parent=$(dirname "$current")
    mkdir -p "$parent" || die_context 'cannot create protected host receipt directory'
    [ ! -L "$authority" ] && [ ! -L "$parent" ] && [ ! -L "$current" ] && [ ! -L "$active" ] || die_context 'linked protected host receipt path rejected'
    chmod 700 "$authority" "$parent" 2>/dev/null || true
    now=$(date +%s); expires=$((now + ${FORGE_HOST_CONTEXT_TTL_SECONDS:-43200})); nonce="$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM:-0}"
    tmp="$current.tmp.$$"; umask 077
    {
      printf 'schema_version=2\nactive_host=%s\nsession_id=%s\ncontext_revision=%s\nworktree_identity=%s\nlauncher_path=%s\nlauncher_hash=%s\ncouncil_path=%s\ncouncil_hash=%s\nnonce=%s\nissued_epoch=%s\nexpires_epoch=%s\n' \
        "$host" "$session" "$(revision_context)" "$(identity_context)" "$launcher" "$(hash_file_context "$launcher")" "$council" "$(hash_file_context "$council")" "$nonce" "$now" "$expires"
    } > "$tmp" || die_context 'cannot write protected host receipt'
    printf 'receipt_hash=%s\n' "$(hash_file_context "$tmp")" >> "$tmp"
    chmod 600 "$tmp" 2>/dev/null || true; mv "$tmp" "$current" || die_context 'cannot publish protected host receipt'
    active_tmp="$active.tmp.$$"; cp "$current" "$active_tmp" || die_context 'cannot stage active host receipt'
    chmod 600 "$active_tmp" 2>/dev/null || true; mv "$active_tmp" "$active" || die_context 'cannot publish active host receipt'
    printf '%s\n' "$current"
}

mode="${1:-}"; [ "$#" -gt 0 ] && shift
case "$mode" in
hook)
    host=""; while [ "$#" -gt 0 ]; do case "$1" in --host) host="${2:-}"; shift 2 ;; *) die_context "unknown hook argument $1" ;; esac; done
    input=$(cat 2>/dev/null || true); session=""
    if command -v jq >/dev/null 2>&1; then session=$(printf '%s' "$input" | jq -r '.session_id // .thread_id // ""' 2>/dev/null || true); fi
    [ -n "$session" ] || session=$(printf '%s' "$input" | sed -nE 's/.*"(session_id|thread_id)"[[:space:]]*:[[:space:]]*"([^"\\]+)".*/\2/p' | head -1)
    issue_context "$host" "$session" >/dev/null
    ;;
issue-test)
    [ "${FORGE_HOST_CONTEXT_TEST_MODE:-0}" = 1 ] || die_context 'test receipt issue mode is disabled'; test_mode_allowed_context
    host=""; session=""; while [ "$#" -gt 0 ]; do case "$1" in --host) host="${2:-}"; shift 2 ;; --session-id) session="${2:-}"; shift 2 ;; *) die_context "unknown test issue argument $1" ;; esac; done
    issue_context "$host" "$session"
    ;;
launch)
    host=""; while [ "$#" -gt 0 ]; do case "$1" in --host) host="${2:-}"; shift 2 ;; --) shift; break ;; *) die_context "unknown launch argument $1" ;; esac; done
    case "$host" in claude|codex) ;; *) die_context 'fixed launcher host must be claude or codex' ;; esac
    launcher=$(launcher_context); council=$(council_context); [ "$#" -gt 0 ] || set -- "$launcher"
    requested="$1"; requested_parent=$(cd "$(dirname "$requested")" 2>/dev/null && pwd -P) || die_context 'cannot resolve requested launcher'; requested="$requested_parent/$(basename "$requested")"
    [ "$requested" = "$launcher" ] || [ "$requested" = "$council" ] || die_context 'requested command is not a bound Forge dispatcher'
    current=$(active_context "$host"); validate_receipt_context "$current" "$host" "$launcher" "$council"
    export FORGE_NATIVE_HOST="$host" FORGE_NATIVE_SESSION_ID="$VALID_CONTEXT_SESSION" FORGE_HOST_CONTEXT_FILE="$current" FORGE_HOST_CONTEXT_LAUNCHER_HASH="$VALID_CONTEXT_LAUNCHER_HASH"
    exec "$@"
    ;;
verify)
    file="${FORGE_HOST_CONTEXT_FILE:-}"; host="${FORGE_NATIVE_HOST:-}"; launcher=$(launcher_context); council=$(council_context)
    [ -n "$file" ] && [ -n "$host" ] && [ -n "${FORGE_HOST_CONTEXT_LAUNCHER_HASH:-}" ] || die_context 'protected launcher context is required'
    validate_receipt_context "$file" "$host" "$launcher" "$council"
    [ "$FORGE_HOST_CONTEXT_LAUNCHER_HASH" = "$VALID_CONTEXT_LAUNCHER_HASH" ] || die_context 'launcher environment binding mismatch'
    [ "${FORGE_NATIVE_SESSION_ID:-}" = "$VALID_CONTEXT_SESSION" ] || die_context 'native session environment mismatch'
    printf '%s\n' "$host"
    ;;
*) die_context 'usage: host-context.sh hook|launch|verify' ;;
esac
