#!/usr/bin/env bash
# hooks/lib/default-branch.sh — detect the repo's default branch.
#
# Detection chain (in order):
#   1. git symbolic-ref refs/remotes/origin/HEAD --short  (e.g. "origin/main")
#   2. fallback: local "main" exists
#   3. fallback: local "master" exists
#   4. bail (exit 1)
#
# Contract:
#   - Branch name on stdout ONLY (no trailing noise)
#   - Exit 0 on success, exit 1 on bail
#   - All git stderr redirected to /dev/null (silent contract)
#
# Dual-mode:
#   Script-call:  default_branch=$(bash "$ROOT/.forge/hooks/lib/default-branch.sh") || default_branch="main"
#   Source-mode:  source "$ROOT/.forge/hooks/lib/default-branch.sh"
#                 default_branch=$(detect_default_branch) || default_branch="main"
#
# KNOWN LIMITATION — stale-rename detection:
#   Detection is based on locally cached refs. After the REMOTE default branch
#   is renamed (e.g., master → main on the upstream), `git fetch` does not
#   refresh `refs/remotes/origin/HEAD`, and the old remote-tracking branch
#   (e.g., refs/remotes/origin/master) typically survives until pruned. In that
#   state Method 1 below can return the retired branch name. The user-side fix:
#       git remote set-head origin --auto
#       git fetch --prune
#   No network-free heuristic distinguishes "master is still the default" from
#   "master was renamed to main and origin/main is now authoritative" with
#   acceptable false-positive rates, so the helper trusts `origin/HEAD` as
#   cached and documents the manual refresh as the canonical fix.

detect_default_branch() {
    # Method 1: origin/HEAD symbolic ref (~95% of repos).
    # CAVEAT: origin/HEAD is locally cached and only refreshed by an explicit
    # `git remote set-head origin -a` (or --auto). If the remote default was
    # renamed and the cache is stale, origin/HEAD can point at a retired branch.
    # Defense: verify the returned name has a corresponding remote-tracking ref
    # (`refs/remotes/origin/<name>`); if not, fall through to Method 2/3 rather
    # than returning a name that no longer resolves.
    local ref candidate
    if ref=$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null); then
        candidate="${ref#origin/}"
        if [ -n "$candidate" ] && git show-ref --verify --quiet "refs/remotes/origin/$candidate" 2>/dev/null; then
            printf '%s' "$candidate"
            return 0
        fi
        # Fall through: origin/HEAD exists but its target ref doesn't (stale rename).
    fi
    # Method 2: local main exists
    if git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
        printf 'main'
        return 0
    fi
    # Method 3: local master exists
    if git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
        printf 'master'
        return 0
    fi
    # Bail
    return 1
}

# Dual-mode: when invoked as a script (not sourced), call the function and
# exit with its status. When sourced, the function is defined and the script
# returns immediately without exiting the caller.
#
# Idiom: BASH_SOURCE[0] equals $0 only when this file is the entry point
# (i.e., invoked as `bash this-file.sh`). When sourced, BASH_SOURCE[0] is
# this file's path while $0 is the parent script's name.
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    detect_default_branch
    exit $?
fi
