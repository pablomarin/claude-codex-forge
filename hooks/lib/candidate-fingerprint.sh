#!/usr/bin/env bash
# Single no-follow candidate capture primitive for reviews; Task 8 promotes it.
set -u

die_fp() { printf 'BLOCKED[artifact]: %s\n' "$*" >&2; exit 2; }
hash_stream_fp() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'; else sha256sum | awk '{print $1}'; fi; }
hash_file_fp() { hash_stream_fp < "$1"; }
size_fp() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null || die_fp "cannot stat $1"; }
regular_nofollow_fp() { [ -f "$1" ] && [ ! -L "$1" ]; }
scalar_fp() { case "$2" in *$'\n'*|*$'\r'*) die_fp "$1 contains a newline" ;; esac; }
state_value_fp() {
    local state="$1" field="$2" count
    count=$(awk -F'|' -v f="$field" '{k=$2; gsub(/^[ \t]+|[ \t]+$/, "", k); if (k==f) n++} END {print n+0}' "$state")
    [ "$count" -eq 1 ] || die_fp "canonical state field $field must occur exactly once"
    awk -F'|' -v f="$field" '{k=$2; gsub(/^[ \t]+|[ \t]+$/, "", k); if (k==f) {v=$3; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit}}' "$state"
}

mode="${1:-}"; [ "$#" -gt 0 ] && shift
artifact=""; base=""; base_ref=""; output=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --artifact) artifact="${2:-}"; shift 2 ;; --workflow-base-sha) base="${2:-}"; shift 2 ;;
        --workflow-base-ref) base_ref="${2:-}"; shift 2 ;; --output) output="${2:-}"; shift 2 ;;
        *) die_fp "unknown argument $1" ;;
    esac
done
[ "$mode" = capture ] || [ "$mode" = identity ] || die_fp 'usage: candidate-fingerprint.sh capture|identity ...'
[ -n "$artifact" ] && [ -n "$base" ] && [ -n "$base_ref" ] || die_fp 'artifact and immutable workflow base are required'
scalar_fp artifact "$artifact"; scalar_fp workflow-base-ref "$base_ref"
root=$(git rev-parse --show-toplevel 2>/dev/null) || die_fp 'Git worktree required'
root=$(cd "$root" && pwd -P); head=$(git -C "$root" rev-parse HEAD 2>/dev/null) || die_fp 'HEAD is unavailable'
common=$(git -C "$root" rev-parse --git-common-dir); common=$(cd "$root" && cd "$common" && pwd -P)
state="$root/.forge/local/state.md"
[ -f "$state" ] && [ ! -L "$state" ] || die_fp 'canonical state is required'
[ "$(sed -n '1p' "$state")" = '<!-- forge:state-schema v6 -->' ] || die_fp 'canonical state schema is unsupported'
state_root=$(state_value_fp "$state" 'Worktree root'); state_common=$(state_value_fp "$state" 'Git common directory')
state_ref=$(state_value_fp "$state" 'Workflow base ref'); state_base=$(state_value_fp "$state" 'Workflow base SHA')
[ "$state_root" = "$root" ] && [ "$state_common" = "$common" ] || die_fp 'canonical state belongs to another worktree'
[ "$base_ref" = "$state_ref" ] || die_fp 'caller workflow base ref differs from canonical state'
[ "$base" = "$state_base" ] || die_fp 'caller workflow base SHA differs from canonical state'
git -C "$root" cat-file -e "$base^{commit}" 2>/dev/null || die_fp 'workflow base commit is missing'
git -C "$root" merge-base --is-ancestor "$base" "$head" 2>/dev/null || die_fp 'workflow base is not an ancestor of HEAD'
base=$(git -C "$root" rev-parse "$base^{commit}")
worktree_identity=$(printf '%s|%s\n' "$root" "$common" | hash_stream_fp)
index_tree=$(git -C "$root" write-tree 2>/dev/null) || die_fp 'index cannot be represented as a tree'
staged_hash=$(git -C "$root" diff --cached --binary HEAD | hash_stream_fp)
unstaged_hash=$(git -C "$root" diff --binary | hash_stream_fp)
manifest=$(mktemp "${TMPDIR:-/tmp}/forge-untracked.XXXXXX"); paths=$(mktemp "${TMPDIR:-/tmp}/forge-paths.XXXXXX"); paths_after=$(mktemp "${TMPDIR:-/tmp}/forge-paths-after.XXXXXX")
trap 'rm -f "$manifest" "$paths" "$paths_after"' EXIT HUP INT TERM
: > "$manifest"; : > "$paths"; untracked_count=0; total=0; max_file=${FORGE_CANDIDATE_MAX_FILE_BYTES:-10485760}; max_total=${FORGE_CANDIDATE_MAX_TOTAL_BYTES:-52428800}
# Git does not enumerate every special untracked inode (notably FIFOs). Walk
# lstat-style first and reject any untracked link/device/socket/pipe. Tracked
# symlinks remain inert Git mode+target bytes and are allowed.
while IFS= read -r special; do
    rel=${special#"$root"/}; case "$rel" in .git|.git/*|.forge/local|.forge/local/*) continue ;; esac
    git -C "$root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || die_fp "untracked path is not a regular file: $rel"
done < <(find -P "$root" \( -path "$root/.git" -o -path "$root/.forge/local" \) -prune -o \( -type l -o ! -type f ! -type d \) -print 2>/dev/null)
git -C "$root" ls-files --others --exclude-standard -z -- . ':(exclude).forge/local/**' > "$paths"
while IFS= read -r -d '' rel; do
    scalar_fp path "$rel"; case "$rel" in /*|../*|*/../*) die_fp "untracked path escapes worktree: $rel" ;; esac
    file="$root/$rel"; regular_nofollow_fp "$file" || die_fp "untracked path is not a no-follow regular file: $rel"
    bytes=$(size_fp "$file"); [ "$bytes" -le "$max_file" ] || die_fp "untracked file exceeds limit: $rel"
    total=$((total + bytes)); [ "$total" -le "$max_total" ] || die_fp 'untracked scope exceeds total size limit'
    mode_bits=$(stat -f %Lp "$file" 2>/dev/null || stat -c %a "$file" 2>/dev/null || printf 0)
    printf '%s\t%s\t%s\t%s\n' "$rel" "$mode_bits" "$bytes" "$(hash_file_fp "$file")" >> "$manifest"
    untracked_count=$((untracked_count + 1))
done < "$paths"
LC_ALL=C sort "$manifest" -o "$manifest"
untracked_hash=$(hash_file_fp "$manifest")
artifact_kind=""; artifact_identity=""; snapshot=""
case "$artifact" in
git:working-tree)
    artifact_kind=git-working-tree
    artifact_identity=$(printf '%s\n' "$base" "$head" "$index_tree" "$staged_hash" "$unstaged_hash" "$untracked_hash" "$worktree_identity" | hash_stream_fp)
    ;;
git:head)
    artifact_kind=git-head; artifact_identity=$(printf '%s|%s\n' "$head" "$worktree_identity" | hash_stream_fp)
    ;;
file:*)
    artifact_kind=file; raw=${artifact#file:}; [ -n "$raw" ] || die_fp 'empty file artifact'
    case "$raw" in /*) file="$raw" ;; *) file="$root/$raw" ;; esac
    regular_nofollow_fp "$file" || die_fp 'file artifact must be a no-follow regular file'
    parent=$(cd "$(dirname "$file")" 2>/dev/null && pwd -P) || die_fp 'cannot canonicalize file artifact'; file="$parent/$(basename "$file")"
    case "$file" in "$root"/*) ;; *) die_fp 'file artifact escapes worktree' ;; esac
    artifact_identity=$(printf '%s|%s\n' "$file" "$(hash_file_fp "$file")" | hash_stream_fp)
    ;;
*) die_fp 'artifact must be file:PATH, git:head, or git:working-tree' ;;
esac

if [ "$mode" = capture ]; then
    [ -n "$output" ] || die_fp 'capture output is required'
    snapshot=$(mktemp -d "${TMPDIR:-/tmp}/forge-candidate.XXXXXX") || die_fp 'cannot create sibling candidate'
    if [ "$artifact_kind" = file ]; then mkdir -p "$snapshot/data"; cp -p "$file" "$snapshot/data/$(basename "$file")" || die_fp 'file snapshot failed'
    else
        git clone -q --no-hardlinks --no-checkout "$root" "$snapshot/repository" 2>/dev/null || die_fp 'candidate clone failed'
        git -C "$snapshot/repository" remote remove origin >/dev/null 2>&1 || die_fp 'candidate source binding removal failed'
        git -C "$snapshot/repository" reflog expire --expire=now --all >/dev/null 2>&1 || die_fp 'candidate clone provenance removal failed'
        mkdir "$snapshot/repository/.git/forge-disabled-hooks" || die_fp 'candidate hook isolation failed'
        git -C "$snapshot/repository" config core.hooksPath "$snapshot/repository/.git/forge-disabled-hooks" || die_fp 'candidate hook isolation failed'
        snapshot="$snapshot/repository"; git -C "$snapshot" checkout -q --detach "$head" || die_fp 'candidate checkout failed'
        if [ "$artifact_kind" = git-working-tree ]; then
            if ! git -C "$root" diff --cached --quiet HEAD; then
                git -C "$root" diff --cached --binary HEAD | git -C "$snapshot" apply --index --binary --whitespace=nowarn 2>/dev/null || die_fp 'staged candidate materialization failed'
            fi
            if ! git -C "$root" diff --quiet; then
                git -C "$root" diff --binary | git -C "$snapshot" apply --binary --whitespace=nowarn 2>/dev/null || die_fp 'unstaged candidate materialization failed'
            fi
            while IFS=$'\t' read -r rel mode_bits bytes expected; do
                [ -n "$rel" ] || continue; source_file="$root/$rel"; regular_nofollow_fp "$source_file" || die_fp "untracked path raced: $rel"
                [ "$(hash_file_fp "$source_file")" = "$expected" ] || die_fp "untracked content raced: $rel"
                mkdir -p "$snapshot/$(dirname "$rel")"; cp -p "$source_file" "$snapshot/$rel" || die_fp "cannot snapshot $rel"
            done < "$manifest"
        fi
        # A tracked Git symlink is reviewable only as inert target bytes. Never
        # leave a followable link in the disposable sibling candidate.
        while IFS= read -r -d '' link; do
            link_bytes="$link.forge-link-bytes.$$"
            readlink -n "$link" > "$link_bytes" || die_fp 'cannot capture tracked symlink target bytes'
            unlink "$link" || die_fp 'cannot inert tracked symlink'
            mv "$link_bytes" "$link" || die_fp 'cannot materialize inert tracked symlink bytes'
        done < <(find -P "$snapshot" -path "$snapshot/.git" -prune -o -type l -print0 2>/dev/null)
    fi
    snapshot=$(cd "$snapshot" 2>/dev/null && pwd -P) || die_fp 'cannot canonicalize candidate snapshot'
fi

# Recheck every source identity after materialization. A race discards certification.
[ "$(git -C "$root" rev-parse HEAD)" = "$head" ] || die_fp 'HEAD changed during capture'
[ "$(git -C "$root" write-tree)" = "$index_tree" ] || die_fp 'index changed during capture'
[ "$(git -C "$root" diff --cached --binary HEAD | hash_stream_fp)" = "$staged_hash" ] || die_fp 'staged content changed during capture'
[ "$(git -C "$root" diff --binary | hash_stream_fp)" = "$unstaged_hash" ] || die_fp 'unstaged content changed during capture'
git -C "$root" ls-files --others --exclude-standard -z -- . ':(exclude).forge/local/**' > "$paths_after"
cmp -s "$paths" "$paths_after" || die_fp 'untracked path set changed during capture'
while IFS=$'\t' read -r rel mode_bits bytes expected; do
    file="$root/$rel"; regular_nofollow_fp "$file" || die_fp "untracked path raced: $rel"
    [ "$(size_fp "$file")" = "$bytes" ] || die_fp "untracked size raced: $rel"
    current_mode=$(stat -f %Lp "$file" 2>/dev/null || stat -c %a "$file" 2>/dev/null || printf 0)
    [ "$current_mode" = "$mode_bits" ] || die_fp "untracked mode raced: $rel"
    [ "$(hash_file_fp "$file")" = "$expected" ] || die_fp "untracked content raced: $rel"
done < "$manifest"
while IFS= read -r special; do
    rel=${special#"$root"/}; case "$rel" in .git|.git/*|.forge/local|.forge/local/*) continue ;; esac
    git -C "$root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || die_fp "untracked special path appeared during capture: $rel"
done < <(find -P "$root" \( -path "$root/.git" -o -path "$root/.forge/local" \) -prune -o \( -type l -o ! -type f ! -type d \) -print 2>/dev/null)

emit="${output:-/dev/stdout}"; mkdir -p "$(dirname "$emit")"
{
  printf 'schema_version=1\nartifact_kind=%s\nartifact_identity=%s\nartifact_hash=%s\nworktree_identity=%s\ngit_head=%s\nworkflow_base_ref=%s\nworkflow_base_sha=%s\nindex_tree=%s\nstaged_hash=%s\nunstaged_hash=%s\nuntracked_hash=%s\nuntracked_count=%s\n' \
    "$artifact_kind" "$artifact_identity" "$artifact_identity" "$worktree_identity" "$head" "$base_ref" "$base" "$index_tree" "$staged_hash" "$unstaged_hash" "$untracked_hash" "$untracked_count"
  [ -z "$snapshot" ] || printf 'snapshot_path=%s\n' "$snapshot"
} > "$emit"
