#!/usr/bin/env bash
# Operator-only Forge goal authorization writer. Its installed physical path and
# immutable authorization root are sealed by global setup.
set -e

TRUSTED_WRITER='__FORGE_WRITER_PATH__'
AUTHORIZATION_ROOT='__FORGE_AUTHORIZATION_ROOT__'
WRITER_REVISION='__FORGE_WRITER_REVISION__'

physical_file() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }
hash_file_writer() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
actual_writer=$(physical_file "$0")
[ "$actual_writer" = "$TRUSTED_WRITER" ] && [ ! -L "$actual_writer" ] || { echo "BLOCKED: copied, symlinked, or untrusted goal authorization writer" >&2; exit 2; }
seal="$TRUSTED_WRITER.sha256"
[ -f "$seal" ] && [ ! -L "$seal" ] && [ "$(cat "$seal")" = "$(hash_file_writer "$TRUSTED_WRITER")" ] || { echo "BLOCKED: authorization writer revision seal mismatch" >&2; exit 2; }
case "$WRITER_REVISION" in ????????????????????????????????????????????????????????????????) ;; *) echo "BLOCKED: unsealed writer source revision" >&2; exit 2 ;; esac

project="" objective_hash="" nonce="" ceiling=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --project) project="$2"; shift 2 ;;
        --objective-hash) objective_hash="$2"; shift 2 ;;
        --nonce) nonce="$2"; shift 2 ;;
        --ceiling) ceiling="$2"; shift 2 ;;
        *) echo "BLOCKED: unsupported option $1" >&2; exit 2 ;;
    esac
done
[ -d "$project" ] || { echo "BLOCKED: project directory missing" >&2; exit 3; }
case "$objective_hash" in ""|*[!A-Za-z0-9._-]*) echo "BLOCKED: invalid objective hash" >&2; exit 3 ;; esac
case "$nonce" in ????????-????-4???-[89abAB]???-????????????) ;; *) echo "BLOCKED: nonce must be UUIDv4" >&2; exit 3 ;; esac
case "$ceiling" in ""|*[!0-9]*|0) echo "BLOCKED: ceiling must be positive" >&2; exit 3 ;; esac

project_root=$(git -C "$project" rev-parse --show-toplevel 2>/dev/null) || { echo "BLOCKED: project is not a Git worktree" >&2; exit 3; }
project_root=$(cd "$project_root" && pwd -P)
common=$(git -C "$project_root" rev-parse --git-common-dir 2>/dev/null)
case "$common" in /*) ;; *) common="$project_root/$common" ;; esac
common=$(cd "$common" && pwd -P)
if command -v shasum >/dev/null 2>&1; then project_id=$(printf '%s\n%s\n' "$project_root" "$common" | shasum -a 256 | awk '{print $1}'); else project_id=$(printf '%s\n%s\n' "$project_root" "$common" | sha256sum | awk '{print $1}'); fi

[ -d "$AUTHORIZATION_ROOT" ] && [ ! -L "$AUTHORIZATION_ROOT" ] || { echo "BLOCKED: sealed authorization root unavailable or aliased" >&2; exit 4; }
authorization_project="$AUTHORIZATION_ROOT/$project_id"
[ ! -L "$authorization_project" ] || { echo "BLOCKED: aliased authorization project root" >&2; exit 4; }
mkdir -p "$authorization_project"
destination="$authorization_project/$nonce.auth"
umask 077
tmp="$authorization_project/.$nonce.tmp.$$"
trap 'rm -f "$tmp"' EXIT HUP INT TERM
{
    printf 'format=forge-goal-authorization-v1\n'
    printf 'project_root=%s\n' "$project_root"
    printf 'git_common_dir=%s\n' "$common"
    printf 'project_id=%s\n' "$project_id"
    printf 'objective_hash=%s\n' "$objective_hash"
    printf 'nonce=%s\n' "$nonce"
    printf 'ceiling=%s\n' "$ceiling"
    printf 'approval_channel=physical-operator-action\n'
    printf 'issue_id=%s-%s\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$$"
    printf 'writer_revision=%s\n' "$WRITER_REVISION"
} > "$tmp"
if ! ln "$tmp" "$destination" 2>/dev/null; then echo "BLOCKED: authorization nonce already exists; replay/replacement refused" >&2; exit 4; fi
rm -f "$tmp"; trap - EXIT HUP INT TERM
echo "AUTHORIZED: $destination"
