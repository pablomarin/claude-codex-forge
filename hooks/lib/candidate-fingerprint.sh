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
kv_fp() {
    local file="$1" key="$2" count
    count=$(awk -F= -v k="$key" '$1==k{n++} END{print n+0}' "$file")
    [ "$count" -eq 1 ] || die_fp "$key must occur exactly once in $(basename "$file")"
    awk -F= -v k="$key" '$1==k{sub(/^[^=]*=/,""); print; exit}' "$file"
}
canonical_fp() {
    local raw="$1" must="${2:-true}" candidate parent
    case "$raw" in /*) candidate="$raw" ;; *) candidate="$PROMOTE_ROOT/$raw" ;; esac
    if [ "$must" = true ]; then regular_nofollow_fp "$candidate" || die_fp "regular file required: $raw"
    else mkdir -p "$(dirname "$candidate")" || die_fp "cannot create parent for $raw"; [ ! -L "$candidate" ] || die_fp "linked output rejected: $raw"; fi
    parent=$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P) || die_fp "cannot resolve $raw"
    printf '%s/%s\n' "$parent" "$(basename "$candidate")"
}
resolve_hook_fp() {
    local name="$1" raw parent
    raw=$(git -C "$PROMOTE_ROOT" rev-parse --git-path "hooks/$name" 2>/dev/null) || die_fp "cannot resolve $name hook"
    case "$raw" in /*) ;; *) raw="$PROMOTE_ROOT/$raw" ;; esac
    [ -e "$raw" ] || { printf '\n'; return 0; }
    regular_nofollow_fp "$raw" && [ -x "$raw" ] || die_fp "$name hook must be an executable no-follow regular file"
    parent=$(cd "$(dirname "$raw")" 2>/dev/null && pwd -P) || die_fp "cannot resolve $name hook"
    printf '%s/%s\n' "$parent" "$(basename "$raw")"
}
run_hook_fp() {
    local name="$1" hook="$2" expected="$3" runner="$4" message="$5" index="$6" rc
    [ -n "$hook" ] || return 0
    [ "$(hash_file_fp "$hook")" = "$expected" ] || die_fp "$name hook changed after capture"
    case "$name" in
        pre-commit) (cd "$runner" && GIT_INDEX_FILE="$index" "$hook") ;;
        prepare-commit-msg) (cd "$runner" && GIT_INDEX_FILE="$index" "$hook" "$message" "") ;;
        commit-msg) (cd "$runner" && GIT_INDEX_FILE="$index" "$hook" "$message") ;;
        post-commit) (cd "$runner" && GIT_INDEX_FILE="$index" "$hook") ;;
    esac
    rc=$?; [ "$rc" -eq 0 ] || return "$rc"
}
promote_fp() {
    local candidate="" state="" message="" receipt="" dependencies="" replay=0
    while [ "$#" -gt 0 ]; do case "$1" in
        --candidate) candidate="${2:-}"; shift 2 ;; --state) state="${2:-}"; shift 2 ;;
        --message-file) message="${2:-}"; shift 2 ;; --promotion-receipt) receipt="${2:-}"; shift 2 ;;
        --hook-dependencies) dependencies="${2:-}"; shift 2 ;; --replay-attempt) replay="${2:-}"; shift 2 ;;
        *) die_fp "unknown promote argument $1" ;; esac; done
    case "$replay" in 0|1) ;; *) die_fp 'replay-attempt must be 0 or 1' ;; esac
    PROMOTE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die_fp 'Git worktree required'
    PROMOTE_ROOT=$(cd "$PROMOTE_ROOT" && pwd -P)
    candidate=$(canonical_fp "$candidate" true); state=$(canonical_fp "$state" true)
    message=$(canonical_fp "$message" true); receipt=$(canonical_fp "$receipt" false)
    case "$candidate:$state:$message:$receipt" in
        "$PROMOTE_ROOT/.forge/local"/*:"$PROMOTE_ROOT/.forge/local"/*:"$PROMOTE_ROOT/.forge/local"/*:"$PROMOTE_ROOT/.forge/local"/*) ;;
        *) die_fp 'promotion inputs and receipt must be under .forge/local' ;;
    esac
    vr="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/verification-receipt.sh"
    [ -f "$vr" ] || vr="$PROMOTE_ROOT/hooks/lib/verification-receipt.sh"
    [ -f "$vr" ] || die_fp 'verification-receipt helper unavailable'
    bash "$vr" check --state "$state" >/dev/null 2>&1 || die_fp 'final receipt set does not certify the current candidate'
    [ "$(kv_fp "$candidate" schema_version)" = 2 ] && [ "$(kv_fp "$candidate" candidate_state)" = staged-clean ] || die_fp 'staged-clean schema-v2 candidate required'
    old_id=$(kv_fp "$candidate" candidate_id); head=$(kv_fp "$candidate" git_head); tree=$(kv_fp "$candidate" index_tree)
    [ "$(git -C "$PROMOTE_ROOT" rev-parse HEAD)" = "$head" ] || die_fp 'candidate parent is stale'
    git -C "$PROMOTE_ROOT" cat-file -e "$tree^{tree}" 2>/dev/null || die_fp 'frozen index tree is missing'
    branch=$(git -C "$PROMOTE_ROOT" symbolic-ref -q HEAD 2>/dev/null) || die_fp 'promotion requires a checked-out branch'

    pre=$(resolve_hook_fp pre-commit); prepare=$(resolve_hook_fp prepare-commit-msg); commitmsg=$(resolve_hook_fp commit-msg); post=$(resolve_hook_fp post-commit)
    pre_hash=none; prepare_hash=none; commitmsg_hash=none; post_hash=none
    [ -z "$pre" ] || pre_hash=$(hash_file_fp "$pre"); [ -z "$prepare" ] || prepare_hash=$(hash_file_fp "$prepare")
    [ -z "$commitmsg" ] || commitmsg_hash=$(hash_file_fp "$commitmsg"); [ -z "$post" ] || post_hash=$(hash_file_fp "$post")

    runner=$(mktemp -d "${TMPDIR:-/tmp}/forge-promote.XXXXXX") || die_fp 'cannot create promotion runner'
    rmdir "$runner" || die_fp 'cannot reserve promotion runner path'
    patch=$(mktemp "${TMPDIR:-/tmp}/forge-hook-replay.XXXXXX") || { rmdir "$runner"; die_fp 'cannot create replay artifact'; }
    cleanup_promote_fp() { git -C "$PROMOTE_ROOT" worktree remove --force "$runner" >/dev/null 2>&1 || true; rm -f "$patch"; }
    trap cleanup_promote_fp EXIT HUP INT TERM
    git -C "$PROMOTE_ROOT" worktree add -q --detach "$runner" "$head" || die_fp 'cannot create disposable promotion worktree'
    git -C "$runner" read-tree --reset -u "$tree" || die_fp 'cannot materialize frozen index tree'
    runner_index=$(git -C "$runner" rev-parse --git-path index)
    case "$runner_index" in /*) ;; *) runner_index="$runner/$runner_index" ;; esac
    runner_message=$(git -C "$runner" rev-parse --git-path COMMIT_EDITMSG)
    case "$runner_message" in /*) ;; *) runner_message="$runner/$runner_message" ;; esac
    cp "$message" "$runner_message" || die_fp 'cannot prepare commit message'

    dep_hash=none
    if [ -n "$dependencies" ]; then
        dependencies=$(canonical_fp "$dependencies" true)
        dep_hash=$(hash_file_fp "$dependencies")
        while IFS=$'\t' read -r rel expected; do
            [ -n "$rel" ] || continue; scalar_fp dependency "$rel"
            case "$rel" in /*|../*|*/../*|.git|.git/*|.forge/local|.forge/local/*) die_fp "hook dependency escapes policy: $rel" ;; esac
            source="$PROMOTE_ROOT/$rel"; regular_nofollow_fp "$source" || die_fp "hook dependency missing: $rel"
            git -C "$PROMOTE_ROOT" check-ignore -q -- "$rel" || die_fp "hook dependency must be ignored: $rel"
            [ "$(hash_file_fp "$source")" = "$expected" ] || die_fp "hook dependency hash changed: $rel"
            mkdir -p "$runner/$(dirname "$rel")"; cp -p "$source" "$runner/$rel" || die_fp "cannot project hook dependency: $rel"
            chmod a-w "$runner/$rel" 2>/dev/null || die_fp "hook dependency is not read-only: $rel"
        done < "$dependencies"
    fi

    run_hook_fp pre-commit "$pre" "$pre_hash" "$runner" "$runner_message" "$runner_index" || die_fp 'pre-commit hook failed'
    run_hook_fp prepare-commit-msg "$prepare" "$prepare_hash" "$runner" "$runner_message" "$runner_index" || die_fp 'prepare-commit-msg hook failed'
    run_hook_fp commit-msg "$commitmsg" "$commitmsg_hash" "$runner" "$runner_message" "$runner_index" || die_fp 'commit-msg hook failed'

    after_tree=$(git -C "$runner" write-tree 2>/dev/null) || die_fp 'hook runner index is invalid'
    runner_untracked=$(git -C "$runner" ls-files --others --exclude-standard -- . | head -1)
    if [ "$after_tree" != "$tree" ] || ! git -C "$runner" diff --quiet || [ -n "$runner_untracked" ]; then
        [ "$replay" = 0 ] || die_fp 'hook mutated again after one bounded replay'
        while IFS= read -r special; do die_fp "hook produced linked or special path: ${special#"$runner"/}"; done \
            < <(find -P "$runner" -path "$runner/.git" -prune -o \( -type l -o ! -type f ! -type d \) -print 2>/dev/null)
        git -C "$runner" add -A || die_fp 'cannot capture hook changes'
        changed=$(git -C "$runner" diff --cached --name-only "$tree" | wc -l | tr -d ' ')
        [ "$changed" -le "${FORGE_HOOK_REPLAY_MAX_FILES:-32}" ] || die_fp 'hook replay exceeds file limit'
        git -C "$runner" diff --cached --numstat "$tree" | grep -q '^-' && die_fp 'binary hook replay is outside policy'
        git -C "$runner" diff --cached --binary "$tree" > "$patch" || die_fp 'cannot capture hook replay artifact'
        [ "$(size_fp "$patch")" -le "${FORGE_HOOK_REPLAY_MAX_BYTES:-1048576}" ] || die_fp 'hook replay exceeds byte limit'
        bash "$vr" check --state "$state" >/dev/null 2>&1 || die_fp 'candidate changed before hook replay'
        git -C "$PROMOTE_ROOT" apply --index --binary "$patch" || die_fp 'validated hook replay could not be applied'
        cleanup_promote_fp; trap - EXIT HUP INT TERM
        printf 'HOOK_REPLAY_REQUIRED: changes were staged; freeze and rerun all final gates once\n' >&2
        exit 3
    fi

    signing=$(git -C "$PROMOTE_ROOT" config --bool commit.gpgsign 2>/dev/null || printf false)
    if [ "$signing" = true ]; then new_commit=$(git -C "$PROMOTE_ROOT" commit-tree -S "$tree" -p "$head" < "$runner_message") || die_fp 'signed commit-tree failed'
    else new_commit=$(git -C "$PROMOTE_ROOT" commit-tree "$tree" -p "$head" < "$runner_message") || die_fp 'commit-tree failed'; fi
    [ "$(git -C "$PROMOTE_ROOT" rev-parse "$new_commit^{tree}")" = "$tree" ] || die_fp 'temporary commit tree mismatch'
    [ "$(git -C "$PROMOTE_ROOT" rev-parse "$new_commit^")" = "$head" ] || die_fp 'temporary commit parent mismatch'
    bash "$vr" check --state "$state" >/dev/null 2>&1 || die_fp 'candidate changed before compare-and-swap'
    git -C "$PROMOTE_ROOT" update-ref "$branch" "$new_commit" "$head" || die_fp 'compare-and-swap rejected concurrent branch movement'

    post_status=not-run
    if [ -n "$post" ]; then
        [ "$(hash_file_fp "$post")" = "$post_hash" ] || die_fp 'post-commit hook changed after capture'
        if (cd "$PROMOTE_ROOT" && GIT_INDEX_FILE="$(git -C "$PROMOTE_ROOT" rev-parse --git-path index)" "$post"); then post_status=pass
        else post_status=failed; fi
    fi
    dirty=false; [ -n "$(git -C "$PROMOTE_ROOT" status --porcelain --untracked-files=all)" ] && dirty=true
    tmp_receipt="$receipt.tmp.$$"
    printf 'schema_version=2\nold_candidate_id=%s\nold_head=%s\nhook_pre_commit_hash=%s\nhook_prepare_commit_msg_hash=%s\nhook_commit_msg_hash=%s\nhook_post_commit_hash=%s\nhook_dependency_manifest_hash=%s\ntemporary_commit=%s\nnew_branch_commit=%s\nnew_branch_tree=%s\nworktree_identity=%s\npost_commit_status=%s\npost_commit_dirty=%s\n' \
        "$old_id" "$head" "$pre_hash" "$prepare_hash" "$commitmsg_hash" "$post_hash" "$dep_hash" "$new_commit" "$new_commit" "$tree" "$(kv_fp "$candidate" worktree_identity)" "$post_status" "$dirty" > "$tmp_receipt"
    mv "$tmp_receipt" "$receipt" || die_fp 'cannot publish promotion receipt'
    cleanup_promote_fp; trap - EXIT HUP INT TERM
    [ "$post_status" != failed ] || { printf 'POST_COMMIT_HOOK_FAILED\n' >&2; exit 2; }
    [ "$dirty" = false ] || { printf 'POST_COMMIT_DIRTY\n' >&2; exit 2; }
    printf 'PROMOTED:%s\n' "$new_commit"
    exit 0
}

mode="${1:-}"; [ "$#" -gt 0 ] && shift
if [ "$mode" = promote ]; then promote_fp "$@"; fi
artifact=""; base=""; base_ref=""; output=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --artifact) artifact="${2:-}"; shift 2 ;; --workflow-base-sha) base="${2:-}"; shift 2 ;;
        --workflow-base-ref) base_ref="${2:-}"; shift 2 ;; --output) output="${2:-}"; shift 2 ;;
        *) die_fp "unknown argument $1" ;;
    esac
done
[ "$mode" = capture ] || [ "$mode" = identity ] || [ "$mode" = freeze ] \
    || die_fp 'usage: candidate-fingerprint.sh capture|identity|freeze ...'
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
root_index=$(git -C "$root" rev-parse --git-path index 2>/dev/null) || die_fp 'cannot resolve worktree index'
case "$root_index" in /*) ;; *) root_index="$root/$root_index" ;; esac
regular_nofollow_fp "$root_index" || die_fp 'worktree index must be a no-follow regular file'
source_objects=$(git -C "$root" rev-parse --git-path objects 2>/dev/null) || die_fp 'cannot resolve source Git object database'
case "$source_objects" in /*) ;; *) source_objects="$root/$source_objects" ;; esac
[ -d "$source_objects" ] || die_fp 'source Git object database is unavailable'
source_objects=$(cd "$source_objects" && pwd -P)
# Even write-tree may update the index cache extension. Give every capture a
# private index. Review capture and identity also use a temporary object database
# so they never need write access to the source repository's Git metadata.
capture_index=$(mktemp "${TMPDIR:-/tmp}/forge-index.XXXXXX") || die_fp 'cannot create private index snapshot'
recheck_index=$(mktemp "${TMPDIR:-/tmp}/forge-index-recheck.XXXXXX") || { rm -f "$capture_index"; die_fp 'cannot create private index recheck'; }
capture_objects=""
if [ "$mode" != freeze ]; then
    capture_objects=$(mktemp -d "${TMPDIR:-/tmp}/forge-objects.XXXXXX") || { rm -f "$capture_index" "$recheck_index"; die_fp 'cannot create private object database'; }
fi
private_git_fp() {
    local private_index="$1"; shift
    if [ -n "$capture_objects" ]; then
        GIT_INDEX_FILE="$private_index" GIT_OBJECT_DIRECTORY="$capture_objects" \
            GIT_ALTERNATE_OBJECT_DIRECTORIES="$source_objects" git -C "$root" "$@"
    else
        GIT_INDEX_FILE="$private_index" git -C "$root" "$@"
    fi
}
cp "$root_index" "$capture_index" || { rm -f "$capture_index" "$recheck_index"; die_fp 'cannot snapshot worktree index'; }
manifest=$(mktemp "${TMPDIR:-/tmp}/forge-untracked.XXXXXX"); paths=$(mktemp "${TMPDIR:-/tmp}/forge-paths.XXXXXX"); paths_after=$(mktemp "${TMPDIR:-/tmp}/forge-paths-after.XXXXXX")
trap 'rm -f "$capture_index" "$recheck_index" "$manifest" "$paths" "$paths_after"; [ -z "$capture_objects" ] || rm -r -- "$capture_objects" 2>/dev/null || true' EXIT HUP INT TERM
index_tree=$(private_git_fp "$capture_index" write-tree 2>/dev/null) || die_fp 'index cannot be represented as a tree'
staged_hash=$(private_git_fp "$capture_index" diff --cached --binary HEAD | hash_stream_fp)
unstaged_hash=$(private_git_fp "$capture_index" diff --binary | hash_stream_fp)
: > "$manifest"; : > "$paths"; untracked_count=0; total=0; max_file=${FORGE_CANDIDATE_MAX_FILE_BYTES:-10485760}; max_total=${FORGE_CANDIDATE_MAX_TOTAL_BYTES:-52428800}
# Git does not enumerate every special untracked inode (notably FIFOs). Walk
# lstat-style first and reject any untracked link/device/socket/pipe. Tracked
# symlinks remain inert Git mode+target bytes and are allowed.
while IFS= read -r special; do
    rel=${special#"$root"/}; case "$rel" in .git|.git/*|.forge/local|.forge/local/*) continue ;; esac
    # Generated environments such as .venv commonly contain symlinks. If Git
    # excludes the path, it is outside the review candidate and must not block
    # capture. Unignored special paths remain fail-closed below.
    private_git_fp "$capture_index" check-ignore -q -- "$rel" 2>/dev/null && continue
    private_git_fp "$capture_index" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || die_fp "untracked path is not a regular file: $rel"
done < <(find -P "$root" \( -path "$root/.git" -o -path "$root/.forge/local" \) -prune -o \( -type l -o ! -type f ! -type d \) -print 2>/dev/null)
private_git_fp "$capture_index" ls-files --others --exclude-standard -z -- . ':(exclude).forge/local/**' > "$paths"
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
candidate_id=$(printf '%s\n' "$base" "$head" "$index_tree" "$worktree_identity" | hash_stream_fp)
candidate_state=dirty
if private_git_fp "$capture_index" diff --quiet && [ "$untracked_count" -eq 0 ]; then candidate_state=staged-clean; fi
artifact_kind=""; artifact_identity=""; snapshot=""
case "$artifact" in
git:working-tree)
    artifact_kind=git-working-tree
    if [ "$candidate_state" = staged-clean ]; then artifact_identity="$candidate_id"
    else artifact_identity=$(printf '%s\n' "$base" "$head" "$index_tree" "$staged_hash" "$unstaged_hash" "$untracked_hash" "$worktree_identity" | hash_stream_fp)
    fi
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

if [ "$mode" = freeze ]; then
    [ "$artifact_kind" = git-working-tree ] || die_fp 'only git:working-tree can be frozen'
    [ "$candidate_state" = staged-clean ] || die_fp 'freeze requires no unstaged or in-scope untracked changes'
    [ -n "$output" ] || die_fp 'freeze output is required'
elif [ "$mode" = capture ]; then
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
            if ! private_git_fp "$capture_index" diff --cached --quiet HEAD; then
                private_git_fp "$capture_index" diff --cached --binary HEAD | git -C "$snapshot" apply --index --binary --whitespace=nowarn 2>/dev/null || die_fp 'staged candidate materialization failed'
            fi
            if ! private_git_fp "$capture_index" diff --quiet; then
                private_git_fp "$capture_index" diff --binary | git -C "$snapshot" apply --binary --whitespace=nowarn 2>/dev/null || die_fp 'unstaged candidate materialization failed'
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
        if [ "$artifact_kind" = git-working-tree ]; then
            git -C "$snapshot" add -A || die_fp 'candidate index materialization failed'
            candidate_tree=$(git -C "$snapshot" write-tree 2>/dev/null) || die_fp 'candidate tree materialization failed'
            candidate_commit=$(printf 'Forge immutable review candidate\n' | \
                GIT_AUTHOR_NAME=Forge GIT_AUTHOR_EMAIL=forge@invalid \
                GIT_COMMITTER_NAME=Forge GIT_COMMITTER_EMAIL=forge@invalid \
                git -C "$snapshot" commit-tree "$candidate_tree" -p "$head" 2>/dev/null) \
                || die_fp 'candidate commit materialization failed'
            git -C "$snapshot" update-ref refs/heads/candidate "$candidate_commit" \
                || die_fp 'candidate ref materialization failed'
            git -C "$snapshot" checkout -q --detach "$candidate_commit" \
                || die_fp 'candidate checkout materialization failed'
        else
            git -C "$snapshot" update-ref refs/heads/candidate "$head" \
                || die_fp 'candidate ref materialization failed'
        fi
    fi
    snapshot=$(cd "$snapshot" 2>/dev/null && pwd -P) || die_fp 'cannot canonicalize candidate snapshot'
fi

# Recheck every source identity after materialization. A race discards certification.
[ "$(git -C "$root" rev-parse HEAD)" = "$head" ] || die_fp 'HEAD changed during capture'
cp "$root_index" "$recheck_index" || die_fp 'cannot recheck worktree index'
[ "$(private_git_fp "$recheck_index" write-tree)" = "$index_tree" ] || die_fp 'index changed during capture'
[ "$(private_git_fp "$recheck_index" diff --cached --binary HEAD | hash_stream_fp)" = "$staged_hash" ] || die_fp 'staged content changed during capture'
[ "$(private_git_fp "$recheck_index" diff --binary | hash_stream_fp)" = "$unstaged_hash" ] || die_fp 'unstaged content changed during capture'
private_git_fp "$recheck_index" ls-files --others --exclude-standard -z -- . ':(exclude).forge/local/**' > "$paths_after"
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
    private_git_fp "$recheck_index" check-ignore -q -- "$rel" 2>/dev/null && continue
    private_git_fp "$recheck_index" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || die_fp "untracked special path appeared during capture: $rel"
done < <(find -P "$root" \( -path "$root/.git" -o -path "$root/.forge/local" \) -prune -o \( -type l -o ! -type f ! -type d \) -print 2>/dev/null)

emit="${output:-/dev/stdout}"; mkdir -p "$(dirname "$emit")"
{
  schema=1; [ "$mode" = freeze ] && schema=2
  printf 'schema_version=%s\nartifact_kind=%s\nartifact_identity=%s\nartifact_hash=%s\ncandidate_id=%s\ncandidate_state=%s\nworktree_identity=%s\ngit_head=%s\nworkflow_base_ref=%s\nworkflow_base_sha=%s\nindex_tree=%s\nstaged_hash=%s\nunstaged_hash=%s\nuntracked_hash=%s\nuntracked_count=%s\n' \
    "$schema" "$artifact_kind" "$artifact_identity" "$artifact_identity" "$candidate_id" "$candidate_state" "$worktree_identity" "$head" "$base_ref" "$base" "$index_tree" "$staged_hash" "$unstaged_hash" "$untracked_hash" "$untracked_count"
  [ -z "$snapshot" ] || printf 'snapshot_path=%s\n' "$snapshot"
} > "$emit"
