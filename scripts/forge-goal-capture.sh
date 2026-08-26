#!/usr/bin/env bash
# Operator-only capture of an authenticated Codex TUI /goal proof. Global setup
# seals this helper, its selected Codex identity, and evidence outside worktrees.
set -eu

TRUSTED_CAPTURE='__FORGE_CAPTURE_PATH__'
CAPTURE_ROOT='__FORGE_CAPTURE_ROOT__'
CODEX_IDENTITY='__FORGE_CODEX_IDENTITY__'
CAPTURE_REVISION='__FORGE_CAPTURE_REVISION__'
WRITER_REVISION='__FORGE_WRITER_REVISION__'

physical_file_capture() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }
hash_file_capture() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
hash_capability_capture() {
    local binary="$1" root_help exec_help flag state
    root_help=$($binary --help 2>&1 || true)
    exec_help=$($binary exec --help 2>&1 || true)
    if command -v shasum >/dev/null 2>&1; then
        { printf 'forge-codex-capability-v1\n'; for flag in --ignore-user-config --ignore-rules --ephemeral --sandbox --add-dir; do state=absent; case "$root_help$exec_help" in *"$flag"*) state=present ;; esac; printf '%s=%s\n' "$flag" "$state"; done; } | shasum -a 256 | awk '{print $1}'
    else
        { printf 'forge-codex-capability-v1\n'; for flag in --ignore-user-config --ignore-rules --ephemeral --sandbox --add-dir; do state=absent; case "$root_help$exec_help" in *"$flag"*) state=present ;; esac; printf '%s=%s\n' "$flag" "$state"; done; } | sha256sum | awk '{print $1}'
    fi
}
resolve_cli_capture() {
    local path="$1" target
    case "$path" in /*) ;; *) path=$(physical_file_capture "$path") ;; esac
    while [ -L "$path" ]; do
        target=$(readlink "$path") || return 1
        case "$target" in /*) path="$target" ;; *) path="$(dirname "$path")/$target" ;; esac
    done
    physical_file_capture "$path"
}
identity_value_capture() { sed -n "s/^$2=//p" "$1" | head -1; }

actual=$(physical_file_capture "$0")
[ "$actual" = "$TRUSTED_CAPTURE" ] && [ ! -L "$actual" ] || { echo "BLOCKED: copied, symlinked, or untrusted goal capture helper" >&2; exit 2; }
seal="$TRUSTED_CAPTURE.sha256"
[ -f "$seal" ] && [ ! -L "$seal" ] && [ "$(cat "$seal")" = "$(hash_file_capture "$TRUSTED_CAPTURE")" ] || { echo "BLOCKED: capture helper revision seal mismatch" >&2; exit 2; }

validate_identity_capture() {
    local identity_seal invocation_path resolved_invocation actual_hash actual_version actual_capability
    [ -f "$CODEX_IDENTITY" ] && [ ! -L "$CODEX_IDENTITY" ] || return 1
    identity_seal="$CODEX_IDENTITY.sha256"
    [ -f "$identity_seal" ] && [ ! -L "$identity_seal" ] || return 1
    identity_hash=$(hash_file_capture "$CODEX_IDENTITY")
    [ "$(cat "$identity_seal")" = "$identity_hash" ] || return 1
    [ "$(identity_value_capture "$CODEX_IDENTITY" format)" = forge-codex-identity-v1 ] || return 1
    [ "$(identity_value_capture "$CODEX_IDENTITY" engine)" = codex ] || return 1
    [ "$(identity_value_capture "$CODEX_IDENTITY" identity_class)" = operator-setup ] || return 1
    [ "$(identity_value_capture "$CODEX_IDENTITY" status)" = QUALIFIED ] || return 1
    [ "$(identity_value_capture "$CODEX_IDENTITY" capture_revision)" = "$CAPTURE_REVISION" ] || return 1
    [ "$(identity_value_capture "$CODEX_IDENTITY" writer_revision)" = "$WRITER_REVISION" ] || return 1
    invocation_path=$(identity_value_capture "$CODEX_IDENTITY" invocation_path)
    cli_path=$(identity_value_capture "$CODEX_IDENTITY" binary_path)
    cli_sha=$(identity_value_capture "$CODEX_IDENTITY" binary_sha256)
    cli_version=$(identity_value_capture "$CODEX_IDENTITY" version)
    capability_revision=$(identity_value_capture "$CODEX_IDENTITY" capability_revision)
    case "$invocation_path:$cli_path" in /*:/*) ;; *) return 1 ;; esac
    [ -x "$invocation_path" ] && [ -x "$cli_path" ] && [ ! -L "$cli_path" ] || return 1
    resolved_invocation=$(resolve_cli_capture "$invocation_path") || return 1
    [ "$resolved_invocation" = "$cli_path" ] || return 1
    [ "$(resolve_cli_capture "$cli_path")" = "$cli_path" ] || return 1
    actual_hash=$(hash_file_capture "$cli_path"); [ "$actual_hash" = "$cli_sha" ] || return 1
    actual_version=$($cli_path --version 2>/dev/null | head -1 || true); [ -n "$actual_version" ] && [ "$actual_version" = "$cli_version" ] || return 1
    actual_capability=$(hash_capability_capture "$cli_path"); [ "$actual_capability" = "$capability_revision" ] || return 1
}

project="" session="" transcript="" result="" validate_binding=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --project) project="$2"; shift 2 ;;
        --session-id) session="$2"; shift 2 ;;
        --transcript) transcript="$2"; shift 2 ;;
        --result) result="$2"; shift 2 ;;
        --validate-binding) validate_binding=true; shift ;;
        *) echo "BLOCKED: unsupported option $1" >&2; exit 2 ;;
    esac
done
[ -d "$project" ] || { echo "BLOCKED: project must be an existing directory" >&2; exit 3; }
project_root=$(git -C "$project" rev-parse --show-toplevel 2>/dev/null) || { echo "BLOCKED: project is not a Git worktree" >&2; exit 3; }
project_root=$(cd "$project_root" && pwd -P)
common=$(git -C "$project_root" rev-parse --git-common-dir); case "$common" in /*) ;; *) common="$project_root/$common" ;; esac; common=$(cd "$common" && pwd -P)
capture_root=$(cd "$CAPTURE_ROOT" && pwd -P)
case "$capture_root/" in "$project_root/"*|"$common/"*) echo "BLOCKED: capture root is inside a workspace root" >&2; exit 3 ;; esac
validate_identity_capture || { echo "BLOCKED: setup-recorded Codex identity is absent, fixture-only, stale, aliased, or hash-invalid" >&2; exit 3; }
if command -v shasum >/dev/null 2>&1; then project_id=$(printf '%s\n%s\n' "$project_root" "$common" | shasum -a 256 | awk '{print $1}'); else project_id=$(printf '%s\n%s\n' "$project_root" "$common" | sha256sum | awk '{print $1}'); fi
if [ "$validate_binding" = true ]; then
    echo "STRUCTURALLY_ELIGIBLE: project_id=$project_id identity_sha256=$identity_hash; authenticated TUI evidence not captured"
    exit 0
fi

case "$session" in ????????-????-4???-[89abAB]???-????????????) ;; *) echo "BLOCKED: session id must be UUIDv4" >&2; exit 3 ;; esac
[ -f "$transcript" ] && [ ! -L "$transcript" ] && [ -f "$result" ] && [ ! -L "$result" ] || { echo "BLOCKED: transcript/result must be unaliased files" >&2; exit 3; }
for exact in \
    "capture_channel=operator-codex-tui" "identity_sha256=$identity_hash" \
    "cli_path=$cli_path" "cli_sha256=$cli_sha" "cli_version=$cli_version" \
    "capability_revision=$capability_revision" "session_id=$session" \
    "project_root=$project_root" "command=/goal" "/goal activated" \
    "status captured" "pause captured" "checkpoint resumed" \
    FORGE_GOAL_BUDGET_EXHAUSTED FORGE_GOAL_STUCK_WARNING; do
    grep -qxF "$exact" "$transcript" || { echo "BLOCKED: TUI transcript missing exact binding: $exact" >&2; exit 4; }
done
for exact in native_activation=PASS checkpoint_resume=PASS budget_oracle=PASS stuck_oracle=PASS; do grep -qxF "$exact" "$result" || { echo "BLOCKED: TUI result missing $exact" >&2; exit 4; }; done

destination="$CAPTURE_ROOT/$project_id/$session"
parent=$(dirname "$destination")
[ ! -L "$parent" ] || { echo "BLOCKED: aliased capture project root" >&2; exit 4; }
mkdir -p "$parent"
if ! mkdir "$destination" 2>/dev/null; then echo "BLOCKED: capture session already exists; replay refused" >&2; exit 4; fi
trap 'rm -rf "$destination"' EXIT HUP INT TERM
umask 077
cp "$transcript" "$destination/transcript.txt"
cp "$result" "$destination/result.txt"
transcript_hash=$(hash_file_capture "$destination/transcript.txt"); result_hash=$(hash_file_capture "$destination/result.txt")
receipt="$destination/capture.receipt"
{
    printf 'format=forge-codex-goal-tui-capture-v3\nengine=codex\ncommand=/goal\n'
    printf 'capture_channel=physical-operator-action\nfixture_only=false\n'
    printf 'project_root=%s\ngit_common_dir=%s\nproject_id=%s\n' "$project_root" "$common" "$project_id"
    printf 'identity_path=%s\nidentity_sha256=%s\n' "$CODEX_IDENTITY" "$identity_hash"
    printf 'cli_path=%s\ncli_sha256=%s\ncli_version=%s\ncapability_revision=%s\nsession_id=%s\n' "$cli_path" "$cli_sha" "$cli_version" "$capability_revision" "$session"
    printf 'transcript_path=%s\ntranscript_sha256=%s\n' "$destination/transcript.txt" "$transcript_hash"
    printf 'result_path=%s\nresult_sha256=%s\n' "$destination/result.txt" "$result_hash"
    printf 'capture_revision=%s\nwriter_revision=%s\n' "$CAPTURE_REVISION" "$WRITER_REVISION"
} > "$receipt"
trap - EXIT HUP INT TERM
echo "CAPTURED: $receipt"
