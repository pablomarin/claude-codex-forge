#!/usr/bin/env bash
# Deterministic Forge v6 linked-worktree creation, state seeding, and fold-back.

set -u

forge_lifecycle_fail() {
    printf '%s\n' "$1" >&2
    return 1
}

forge_lifecycle_physical() {
    (cd "$1" 2>/dev/null && pwd -P)
}

forge_lifecycle_primary() {
    git -C "$1" worktree list --porcelain 2>/dev/null \
        | sed -n 's/^worktree //p' | head -1
}

forge_lifecycle_common() {
    local root="$1" common
    common=$(git -C "$root" rev-parse --git-common-dir 2>/dev/null) || return 1
    case "$common" in /*) ;; *) common="$root/$common" ;; esac
    forge_lifecycle_physical "$common"
}

forge_lifecycle_validate_worktree() {
    local requested="$1" target primary target_common primary_common
    target=$(forge_lifecycle_physical "$requested") \
        || { forge_lifecycle_fail "FOLD_SAFE_STOP: worktree is missing: $requested"; return 1; }
    git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || { forge_lifecycle_fail "FOLD_SAFE_STOP: not a Git worktree: $target"; return 1; }
    primary=$(forge_lifecycle_primary "$target")
    primary=$(forge_lifecycle_physical "$primary") \
        || { forge_lifecycle_fail "FOLD_SAFE_STOP: primary checkout is unavailable"; return 1; }
    target_common=$(forge_lifecycle_common "$target") || return 1
    primary_common=$(forge_lifecycle_common "$primary") || return 1
    [ "$target_common" = "$primary_common" ] \
        || { forge_lifecycle_fail "FOLD_SAFE_STOP: worktree belongs to another repository"; return 1; }
    printf '%s\t%s\n' "$target" "$primary"
}

forge_lifecycle_safe_relative() {
    case "$1" in ''|/*|../*|*/../*|*/..|.|..) return 1 ;; *) return 0 ;; esac
}

forge_lifecycle_copy_missing() {
    local primary="$1" target="$2" rel="$3" source destination parent cursor
    forge_lifecycle_safe_relative "$rel" || return 1
    case "$rel" in .forge/local|.forge/local/*) return 0 ;; esac
    source="$primary/$rel"
    destination="$target/$rel"
    [ -f "$source" ] && [ ! -L "$source" ] || return 0
    [ ! -e "$destination" ] && [ ! -L "$destination" ] || return 0
    parent=$(dirname "$destination")
    cursor="$target"
    IFS='/' read -r -a _forge_parts <<< "$(dirname "$rel")"
    for _forge_part in "${_forge_parts[@]}"; do
        [ "$_forge_part" = . ] && continue
        cursor="$cursor/$_forge_part"
        [ ! -L "$cursor" ] || { forge_lifecycle_fail "SEED_BLOCKED: aliased destination ancestor: $cursor"; return 1; }
    done
    mkdir -p "$parent" || return 1
    cp -p "$source" "$destination" || return 1
}

forge_lifecycle_source_mode() {
    local root="$1" file
    for file in "$root/state.template.md" "$root/manifests/managed-v6.tsv"; do
        [ -f "$file" ] && [ ! -L "$file" ] || return 1
    done
}

forge_lifecycle_bootstrap() {
    local primary="$1" target="$2" ledger rel
    ledger="$primary/.forge/installed-files.tsv"
    if [ ! -f "$ledger" ] || [ -L "$ledger" ]; then
        if forge_lifecycle_source_mode "$primary" && forge_lifecycle_source_mode "$target"; then
            return 0
        fi
        forge_lifecycle_fail "SEED_BLOCKED: primary checkout is neither an installed Forge tree nor a tracked Forge source tree"
        return 1
    fi
    while IFS=$'\t' read -r rel _; do
        [ -n "$rel" ] || continue
        forge_lifecycle_copy_missing "$primary" "$target" "$rel" || return 1
    done < "$ledger"
    # These are project-owned discovery/context surfaces, so they are not all
    # manifest-owned. Copy only when present and missing in the linked worktree.
    for rel in .forge/version .forge/installed-files.tsv CLAUDE.md AGENTS.md docs/agent-context.md \
        .claude/settings.json .codex/config.toml .codex/hooks.json .mcp.json; do
        forge_lifecycle_copy_missing "$primary" "$target" "$rel" || return 1
    done
}

forge_lifecycle_extract_narrative() {
    local input="$1" output="$2"
    [ -f "$input" ] && [ ! -L "$input" ] || return 1
    awk '
        BEGIN { section=0; in_now=0; state_stage=0; bad_order=0 }
        /^## State$/ { section=1; seen_state=1; print; next }
        section==1 && /^## Open Questions$/ { section=2; seen_open=1; in_now=0; print; next }
        section==2 && /^## Blockers$/ { section=3; seen_blockers=1; print; next }
        section>0 && /^## / { exit }
        section==1 && /^### Done/ { if (state_stage!=0) bad_order=1; state_stage=1; seen_done=1; in_now=0; print; next }
        section==1 && /^### Now$/ { if (state_stage!=1) bad_order=1; state_stage=2; seen_now=1; in_now=1; print; print ""; next }
        section==1 && /^### Next$/ { if (state_stage!=2) bad_order=1; state_stage=3; seen_next=1; in_now=0; print; next }
        section==1 && /^### Deferred$/ { if (state_stage!=3) bad_order=1; state_stage=4; seen_deferred=1; in_now=0; print; next }
        section==1 { if (!in_now) print; next }
        section==2 || section==3 { print; next }
        END {
            if (!(seen_state && seen_done && seen_now && seen_next && seen_deferred && seen_open && seen_blockers && state_stage==4 && !bad_order)) exit 42
        }
    ' "$input" > "$output"
}

forge_lifecycle_merge_narrative() {
    local base="$1" narrative="$2" output="$3"
    grep -qxF '## State' "$base" && grep -qxF '## Update Rules' "$base" || return 1
    awk '
        NR==FNR { snapshot=snapshot $0 ORS; next }
        /^## State$/ { printf "%s", snapshot; skip=1; next }
        skip && /^## Update Rules$/ { skip=0; print; next }
        !skip { print }
    ' "$narrative" "$base" > "$output"
}

forge_lifecycle_publish() {
    local source="$1" destination="$2" parent temp
    parent=$(dirname "$destination")
    mkdir -p "$parent" || return 1
    [ ! -L "$parent" ] && [ ! -L "$destination" ] \
        || { forge_lifecycle_fail "SEED_BLOCKED: aliased state destination"; return 1; }
    temp=$(mktemp "$parent/.forge-state.XXXXXX") || return 1
    cp "$source" "$temp" || { rm -f "$temp"; return 1; }
    mv -f "$temp" "$destination"
}

forge_lifecycle_seed() {
    local requested="$1" pair target primary source_state template local_dir snapshot narrative merged
    pair=$(forge_lifecycle_validate_worktree "$requested") || return 1
    target=${pair%%$'\t'*}; primary=${pair#*$'\t'}
    [ "$target" != "$primary" ] \
        || { forge_lifecycle_fail "SEED_BLOCKED: target must be a linked worktree"; return 1; }
    forge_lifecycle_bootstrap "$primary" "$target" || return 1
    source_state="$primary/.forge/local/state.md"
    template="$target/.forge/state.template.md"
    if [ ! -f "$template" ] || [ -L "$template" ]; then
        if forge_lifecycle_source_mode "$target"; then template="$target/state.template.md"; fi
    fi
    local_dir="$target/.forge/local"
    snapshot="$local_dir/.state-seed-snapshot.md"
    [ ! -e "$local_dir/state.md" ] && [ ! -L "$local_dir/state.md" ] \
        || { forge_lifecycle_fail "SEED_BLOCKED: target state already exists"; return 1; }
    [ ! -e "$snapshot" ] && [ ! -L "$snapshot" ] \
        || { forge_lifecycle_fail "SEED_BLOCKED: target seed snapshot already exists"; return 1; }
    [ -f "$template" ] && [ ! -L "$template" ] \
        || { forge_lifecycle_fail "SEED_BLOCKED: target state template is unavailable"; return 1; }
    mkdir -p "$local_dir" || return 1
    narrative=$(mktemp "$local_dir/.narrative.XXXXXX") || return 1
    merged=$(mktemp "$local_dir/.merged.XXXXXX") || { rm -f "$narrative"; return 1; }
    if ! forge_lifecycle_extract_narrative "$source_state" "$narrative"; then
        rm -f "$narrative" "$merged"
        forge_lifecycle_fail "SEED_BLOCKED: primary state narrative is missing or malformed"
        return 1
    fi
    if ! forge_lifecycle_merge_narrative "$template" "$narrative" "$merged"; then
        rm -f "$narrative" "$merged"
        forge_lifecycle_fail "SEED_BLOCKED: target state template is missing required sections"
        return 1
    fi
    forge_lifecycle_publish "$narrative" "$snapshot" \
        && forge_lifecycle_publish "$merged" "$local_dir/state.md"
    local rc=$?
    rm -f "$narrative" "$merged"
    [ "$rc" -eq 0 ] || return "$rc"
    printf 'SEED_OK: worktree=%s snapshot=.forge/local/.state-seed-snapshot.md\n' "$target"
}

forge_lifecycle_fold() {
    local requested="$1" pair target primary snapshot worktree_state primary_state local_dir primary_narrative worktree_narrative merged before
    pair=$(forge_lifecycle_validate_worktree "$requested") || return 1
    target=${pair%%$'\t'*}; primary=${pair#*$'\t'}
    [ "$target" != "$primary" ] \
        || { forge_lifecycle_fail "FOLD_SAFE_STOP: fold must run for a linked worktree"; return 1; }
    snapshot="$target/.forge/local/.state-seed-snapshot.md"
    worktree_state="$target/.forge/local/state.md"
    primary_state="$primary/.forge/local/state.md"
    for _forge_file in "$snapshot" "$worktree_state" "$primary_state"; do
        [ -f "$_forge_file" ] && [ ! -L "$_forge_file" ] \
            || { forge_lifecycle_fail "FOLD_SAFE_STOP: missing or aliased state input: $_forge_file"; return 1; }
    done
    local_dir="$target/.forge/local"
    primary_narrative=$(mktemp "$local_dir/.primary-narrative.XXXXXX") || return 1
    worktree_narrative=$(mktemp "$local_dir/.worktree-narrative.XXXXXX") || { rm -f "$primary_narrative"; return 1; }
    merged=$(mktemp "$local_dir/.folded-state.XXXXXX") || { rm -f "$primary_narrative" "$worktree_narrative"; return 1; }
    if ! forge_lifecycle_extract_narrative "$primary_state" "$primary_narrative" \
        || ! forge_lifecycle_extract_narrative "$worktree_state" "$worktree_narrative"; then
        rm -f "$primary_narrative" "$worktree_narrative" "$merged"
        forge_lifecycle_fail "FOLD_SAFE_STOP: state narrative is structurally incomplete"
        return 1
    fi
    if ! cmp -s "$snapshot" "$primary_narrative"; then
        rm -f "$primary_narrative" "$worktree_narrative" "$merged"
        forge_lifecycle_fail "FOLD_DIVERGED: primary narrative changed after worktree seed; reconcile manually"
        return 1
    fi
    if ! forge_lifecycle_merge_narrative "$primary_state" "$worktree_narrative" "$merged"; then
        rm -f "$primary_narrative" "$worktree_narrative" "$merged"
        forge_lifecycle_fail "FOLD_SAFE_STOP: primary state cannot accept folded narrative"
        return 1
    fi
    before=$(mktemp "$primary/.forge/local/.state-before-fold.XXXXXX") || return 1
    cp "$primary_state" "$before" || { rm -f "$before"; return 1; }
    if ! forge_lifecycle_publish "$merged" "$primary_state"; then
        cp "$before" "$primary_state" 2>/dev/null || true
        rm -f "$before" "$primary_narrative" "$worktree_narrative" "$merged"
        forge_lifecycle_fail "FOLD_SAFE_STOP: atomic primary state publication failed"
        return 1
    fi
    rm -f "$before" "$primary_narrative" "$worktree_narrative" "$merged"
    printf 'FOLD_OK: worktree=%s primary=%s\n' "$target" "$primary"
}

forge_lifecycle_bind_identity() {
    local target="$1" base_ref="$2" base_sha="$3" state common temp
    state="$target/.forge/local/state.md"
    common=$(forge_lifecycle_common "$target") || return 1
    temp=$(mktemp "$target/.forge/local/.identity.XXXXXX") || return 1
    awk -F'|' -v root="$target" -v common="$common" -v base_ref="$base_ref" -v base_sha="$base_sha" '
        {
            key=$2; gsub(/^[ \t]+|[ \t]+$/, "", key)
            if (key=="Worktree root")        { print "| Worktree root | " root " |"; next }
            if (key=="Git common directory") { print "| Git common directory | " common " |"; next }
            if (key=="Workflow base ref")    { print "| Workflow base ref | " base_ref " |"; next }
            if (key=="Workflow base SHA")    { print "| Workflow base SHA | " base_sha " |"; next }
            print
        }
    ' "$state" > "$temp" || { rm -f "$temp"; return 1; }
    forge_lifecycle_publish "$temp" "$state"
    local rc=$?
    rm -f "$temp"
    return "$rc"
}

forge_lifecycle_create() {
    local kind="" name="" base="" root target branch resolved
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --kind) kind="${2:-}"; shift 2 ;;
            --name) name="${2:-}"; shift 2 ;;
            --base) base="${2:-}"; shift 2 ;;
            *) forge_lifecycle_fail "CREATE_BLOCKED: unknown option: $1"; return 1 ;;
        esac
    done
    case "$kind" in feat|fix) ;; *) forge_lifecycle_fail "CREATE_BLOCKED: --kind must be feat or fix"; return 1 ;; esac
    case "$name" in ''|*[!a-z0-9._-]*|[.-]*|*..) forge_lifecycle_fail "CREATE_BLOCKED: invalid lowercase worktree name"; return 1 ;; esac
    [ -n "$base" ] || { forge_lifecycle_fail "CREATE_BLOCKED: --base is required"; return 1; }
    root=$(git rev-parse --show-toplevel 2>/dev/null) \
        || { forge_lifecycle_fail "CREATE_BLOCKED: run from the primary Git checkout"; return 1; }
    root=$(forge_lifecycle_physical "$root") || return 1
    [ "$(forge_lifecycle_physical "$(forge_lifecycle_primary "$root")")" = "$root" ] \
        || { forge_lifecycle_fail "CREATE_BLOCKED: create must run from the primary checkout"; return 1; }
    resolved=$(git -C "$root" rev-parse --verify "$base^{commit}" 2>/dev/null) \
        || { forge_lifecycle_fail "CREATE_BLOCKED: base does not resolve to a commit: $base"; return 1; }
    branch="$kind/$name"; target="$root/.worktrees/$name"
    [ ! -e "$target" ] && [ ! -L "$target" ] \
        || { forge_lifecycle_fail "CREATE_BLOCKED: target already exists: $target"; return 1; }
    if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
        forge_lifecycle_fail "CREATE_BLOCKED: branch already exists: $branch"; return 1
    fi
    mkdir -p "$root/.worktrees" || return 1
    git -C "$root" worktree add -q -b "$branch" "$target" "$resolved" || return 1
    if ! forge_lifecycle_seed "$target" || ! forge_lifecycle_bind_identity "$target" "$base" "$resolved"; then
        git -C "$root" worktree remove --force "$target" >/dev/null 2>&1 || true
        git -C "$root" branch -D "$branch" >/dev/null 2>&1 || true
        return 1
    fi
    printf 'CREATE_OK: branch=%s worktree=%s base=%s\n' "$branch" "$target" "$resolved"
}

forge_lifecycle_usage() {
    printf 'usage: worktree-lifecycle.sh create --kind feat|fix --name <slug> --base <ref-or-sha>\n' >&2
    printf '       worktree-lifecycle.sh seed --worktree <path>\n' >&2
    printf '       worktree-lifecycle.sh fold --worktree <path>\n' >&2
}

action="${1:-}"; [ "$#" -gt 0 ] && shift
case "$action" in
    create) forge_lifecycle_create "$@" ;;
    seed|fold)
        [ "${1:-}" = --worktree ] && [ -n "${2:-}" ] && [ "$#" -eq 2 ] \
            || { forge_lifecycle_usage; exit 2; }
        "forge_lifecycle_$action" "$2"
        ;;
    *) forge_lifecycle_usage; exit 2 ;;
esac
