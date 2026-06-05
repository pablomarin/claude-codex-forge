#!/usr/bin/env bash
# hooks/lib/review-scope.sh — single source of truth for the scoped-review-
# certification model (v5.54, ADR 0009). READ-ONLY: emits sentinel lines, never
# writes. Fail-open direction is MORE review: any ambiguity → SCOPE_REQUIRED:full.
#
# Usage: review-scope.sh <state_md_path> [--before <N>]
#   (run from a checkout of the branch; --before <N> ignores iteration rows with
#    number >= N — the gate uses it to compute the PRIOR clean head for chain checks)
# Sentinels:
#   CERTIFIED:<yes|no>  LAST_CLEAN_HEAD:<sha|none>  ANCESTOR_OK:<yes|no|n/a>
#   PR_OWNED_DELTA:<empty|docs-only|code|n/a>  UPSTREAM_FILES:<none|nonruntime|code|n/a>
#   SCOPE_REQUIRED:<full|delta|mechanical>  POST_CERT_ROUNDS:<n>  BREAKER:<ok|tripped>
#   ADJUDICATED:<yes|no>   # human adjudication line present at the CURRENT head
set -u
POST_CERT_REVIEW_ROUND_LIMIT=3   # canonical home — mirrored to prose by test-contracts.sh

STATE="${1:-}"
BEFORE_N=999999; [ "${2:-}" = "--before" ] && BEFORE_N="${3:-999999}"
emit_full() { echo "SCOPE_REQUIRED:full"; echo "POST_CERT_ROUNDS:${1:-0}"; echo "BREAKER:${2:-ok}"; echo "ADJUDICATED:${3:-no}"; exit 0; }
# emit_uncertified: the five fail-closed prefix lines + emit_full (which exits).
# The early guards (missing state, no git, detached HEAD) and the no-certification
# exit all emit this identical preamble — extracted to one site so the byte-for-byte
# "uncertified → full" output can never drift between them.
emit_uncertified() { echo "CERTIFIED:no"; echo "LAST_CLEAN_HEAD:none"; echo "ANCESTOR_OK:n/a"; echo "PR_OWNED_DELTA:n/a"; echo "UPSTREAM_FILES:n/a"; emit_full "$@"; }

[ -n "$STATE" ] && [ -f "$STATE" ] || emit_uncertified
git rev-parse HEAD >/dev/null 2>&1 || emit_uncertified
# Detached HEAD → fail closed to full (design Error-handling contract): scoped
# evidence binds to a BRANCH's review history; a detached checkout has none.
git symbolic-ref -q HEAD >/dev/null 2>&1 || emit_uncertified

# Default branch via the existing helper (sibling file), fallback main.
LIBDIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_BRANCH="$(bash "$LIBDIR/default-branch.sh" 2>/dev/null || echo main)"
DEFAULT_REF="$DEFAULT_BRANCH"
git rev-parse --verify "origin/$DEFAULT_BRANCH" >/dev/null 2>&1 && DEFAULT_REF="origin/$DEFAULT_BRANCH"
HEAD_SHA="$(git rev-parse HEAD)"

# --- Parse evidence lines from the ### Checklist of ## Workflow (CRLF-safe) ---
# EXACT heading anchor (^## Workflow$) — mirrors the hooks' hardened parser; a
# stale "## Workflow Archive" section from a migration must not feed the chain.
CHECKLIST="$(tr -d '\r' < "$STATE" | awk '/^## Workflow$/{w=1;next} w&&/^## /{w=0} w' | awk '/^### Checklist/{f=1;next} f&&/^### /{f=0} f')"
# rows: N|tool|scope|head|base  (scope=legacy + base empty when absent;
# tool=mechanical for re-stamps). Rows with N >= BEFORE_N are excluded.
ROWS="$(echo "$CHECKLIST" | awk -v maxn="$BEFORE_N" '
  /^- \[x\] Code review iteration [0-9]+ — / {
    n=$0; sub(/^- \[x\] Code review iteration /,"",n); sub(/ .*/,"",n)
    if (n+0 >= maxn+0) next
    # deep-pass is a SEPARATE tool: it never satisfies certification or the chain
    # (the existing gate greps `— codex clean —` and tails the last row; a deep-pass
    # row must not collide with that lookup or stand in for the loop reviews).
    tool=""; if ($0 ~ /— codex deep-pass clean/) tool="deep-pass"
    else if ($0 ~ /— codex clean/) tool="codex"
    else if ($0 ~ /— pr-toolkit clean/) tool="pr-toolkit"
    else if ($0 ~ /— mechanical re-stamp/) tool="mechanical"
    if (tool=="" || tool=="deep-pass") next
    # scope value must be delimiter-bound: scope=fullish / scope=delta-old are
    # UNKNOWN values → drop the row entirely (NOT legacy — a bad scoped row must
    # not certify through the legacy back-compat path).
    scope="legacy"
    if ($0 ~ /scope=/) {
      if (match($0,/scope=(full|delta|mechanical)([[:space:]]|$)/)) {
        scope=substr($0,RSTART+6,RLENGTH-6); sub(/[[:space:]]$/,"",scope)
      } else next
    }
    head=""; if (match($0,/head=`[0-9a-f]+`/)) { head=substr($0,RSTART+6,RLENGTH-7) }
    base=""; if (match($0,/base=`[0-9a-f]+`/)) { base=substr($0,RSTART+6,RLENGTH-7) }
    if (head=="") next
    print n "|" tool "|" scope "|" head "|" base
  }')"
# Loop-counter line: rounds with FINDINGS write no clean rows (the incident shape),
# so the loop line "Code review loop (N iterations)" is the authoritative round count.
LOOP_N="$(echo "$CHECKLIST" | grep -E 'Code review loop \([0-9]+ iterations\)' \
    | sed -E 's/.*Code review loop \(([0-9]+) iterations\).*/\1/' | tail -1)"
[ -n "$LOOP_N" ] || LOOP_N=0
# Count-less N/A detection (iter-10 P1): replacing the counted loop line with
# `Code review loop — N/A: <reason>` would zero LOOP_N and silently reset the
# breaker. Post-certification (applied below), a count-less N/A line is treated
# as breaker evasion → BREAKER:tripped (fail-closed; human adjudication clears).
# The count-PRESERVING form `Code review loop (<N> iterations) — N/A: <reason>`
# keeps the count and does not trip this.
NA_COUNTLESS=0
echo "$CHECKLIST" | grep -E 'Code review loop' | grep -E 'N/A:' \
    | grep -qvE '\([0-9]+ iterations\)' && NA_COUNTLESS=1

# Docs predicate — SAME SEMANTICS as `_is_doc_path()` in check-workflow-gates.sh
# (curated doc basenames anywhere; prose extensions ONLY under a docs/ dir; bare
# *.md outside docs/ is CODE so Forge product markdown like commands/*.md stays
# gated; docs/foo.py and docs/config.json are CODE). The case patterns below are
# kept byte-identical to the gate's — pinned by a T8 contract.
is_docs() {
    local p="$1" base
    base="${p##*/}"
    case "$base" in
        README|CHANGELOG|LICENSE|NOTICE|AUTHORS|CONTRIBUTORS|CONTRIBUTING|CODE_OF_CONDUCT) return 0 ;;
    esac
    case "$base" in
        README*|CHANGELOG*|LICENSE*|CONTRIBUTORS*|CONTRIBUTING*|CODE_OF_CONDUCT*)
            case "$base" in
                *.md|*.mdx|*.markdown|*.rst|*.txt) return 0 ;;
            esac ;;
    esac
    case "$p" in
        docs/*|*/docs/*)
            case "$base" in
                *.md|*.mdx|*.markdown|*.rst) return 0 ;;
            esac ;;
    esac
    return 1
}

# patch-id with EXPLICIT status checks: empty output from a SUCCESSFUL pipeline is
# an empty diff (research: patch-id on empty input is empty); any git failure
# (diff, patch-id) returns nonzero and the caller fails closed to full.
# --no-renames everywhere: a pure code→docs rename otherwise reports only the
# docs path and the moved code silently classifies docs-only (the existing
# commit carve-out uses --no-renames for exactly this reason).
# pid <merge-base> <commit> [file] — the merge-base is PRECOMPUTED by the caller
# (classify() already has mba/mbb), so this no longer re-spawns `git merge-base`
# per call. Optional third arg restricts the diff to one path.
pid() {
    local d out
    d="$(git diff --no-renames "$1" "$2" ${3:+--} ${3:+"$3"} 2>/dev/null)" || return 1
    out="$(printf '%s' "$d" | git patch-id --stable 2>/dev/null)" || return 1
    printf '%s\n' "$out" | awk '{print $1}'
}

# classify <from> <to> — sets C_DELTA (empty|docs-only|code) and C_UP
# (none|nonruntime|code) for the PR-owned change between two branch commits.
# Returns 1 on ANY git failure or broken ancestry (caller fails toward MORE review).
# Used BOTH for the final SCOPE_REQUIRED decision and to validate historical
# mechanical rows during chain construction (a fabricated mechanical-over-code row
# must not become the trusted prior clean head — iter-3 P1).
classify() {
    local from="$1" to="$2" pa pb files f fa fb mba mbb upf
    git cat-file -e "$from" 2>/dev/null || return 1
    git merge-base --is-ancestor "$from" "$to" 2>/dev/null || return 1
    mba="$(git merge-base "$DEFAULT_REF" "$from" 2>/dev/null)" || return 1
    mbb="$(git merge-base "$DEFAULT_REF" "$to" 2>/dev/null)"   || return 1
    pa="$(pid "$mba" "$from")" || return 1
    pb="$(pid "$mbb" "$to")"   || return 1
    C_DELTA=empty   # includes the both-empty case: no PR-owned diff on either commit
    if [ "$pa" != "$pb" ]; then
        C_DELTA=docs-only
        files="$( { git diff --name-only --no-renames "$mba" "$from" && git diff --name-only --no-renames "$mbb" "$to"; } 2>/dev/null)" || return 1
        files="$(printf '%s\n' "$files" | sort -u)"
        # LINE-based iteration (iter-8 P1): `for f in $files` word-splits on spaces,
        # so `src/a b.py` becomes two fake paths with empty per-file diffs and a
        # runtime change can classify docs-only. Paths git quotes (leading `"` —
        # newlines/escapes) are unresolvable here → fail closed to full.
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            case "$f" in \"*) return 1 ;; esac
            fa="$(pid "$mba" "$from" "$f")" || return 1
            fb="$(pid "$mbb" "$to" "$f")"   || return 1
            [ "$fa" = "$fb" ] && continue
            is_docs "$f" || { C_DELTA=code; break; }
        done <<EOF
$files
EOF
    fi
    C_UP=none
    upf="$(git diff --name-only --no-renames "$mba" "$mbb" 2>/dev/null)" || return 1
    if [ -n "$upf" ]; then
        C_UP=nonruntime
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            case "$f" in \"*) return 1 ;; esac
            is_docs "$f" || { C_UP=code; break; }
        done <<EOF
$upf
EOF
    fi
    return 0
}

# full_base_ok <head> <base> — a scope=full row's recorded base must be the true
# merge-base of the default ref and that head (the "I reviewed the whole PR-owned
# diff" claim is anchored at the fork point; a widened/narrowed base is not full).
full_base_ok() {
    local mb
    mb="$(git merge-base "$DEFAULT_REF" "$1" 2>/dev/null)" || return 1
    [ "$mb" = "$2" ]
}

# Human adjudication line bound to the CURRENT head (unblocks a tripped breaker).
ADJ=no
echo "$CHECKLIST" | grep -E '^- \[x\] Post-certification tail adjudicated by human — ' \
    | grep -q "head=\`$HEAD_SHA\`" && ADJ=yes

# Certification: lowest N with a COHERENT codex+pr-toolkit pair at the same head,
# scope full or legacy. Coherence (iter-3 P1): when both rows carry base= they must
# match, and a scope=full row's base must be the true merge-base for that head.
CERT_N=""; CERT_HEAD=""
for n in $(echo "$ROWS" | cut -d'|' -f1 | sort -n | uniq); do
    cl="$(echo "$ROWS" | awk -F'|' -v n="$n" '$1==n && $2=="codex" && ($3=="full"||$3=="legacy"){print $3"|"$4"|"$5}' | tail -1)"
    tl="$(echo "$ROWS" | awk -F'|' -v n="$n" '$1==n && $2=="pr-toolkit" && ($3=="full"||$3=="legacy"){print $3"|"$4"|"$5}' | tail -1)"
    [ -n "$cl" ] && [ -n "$tl" ] || continue
    cs="${cl%%|*}"; r="${cl#*|}"; chh="${r%%|*}"; cb="${r#*|}"
    ts="${tl%%|*}"; r="${tl#*|}"; th="${r%%|*}";  tb="${r#*|}"
    [ "$chh" = "$th" ] || continue
    if [ -n "$cb" ] && [ -n "$tb" ] && [ "$cb" != "$tb" ]; then continue; fi
    # A scope=full row MUST carry a valid base (= true merge-base for its head) —
    # only legacy scope-less rows may omit base (back-compat). A malformed scoped
    # row must not establish certification (iter-4 P1).
    ok=1
    if [ "$cs" = "full" ]; then { [ -n "$cb" ] && full_base_ok "$chh" "$cb"; } || ok=0; fi
    if [ "$ts" = "full" ]; then { [ -n "$tb" ] && full_base_ok "$th" "$tb"; } || ok=0; fi
    [ "$ok" = "1" ] || continue
    CERT_N="$n"; CERT_HEAD="$chh"; break
done

if [ -z "$CERT_N" ]; then
    emit_uncertified 0 ok "$ADJ"
fi
echo "CERTIFIED:yes"

# Last clean head: walk post-cert iterations in order, advancing ONLY on rows that
# re-validate TODAY (iter-3 P1 — rows are appended between ships, so a historical
# row may never have been gate-checked; the chain must not trust it on sight):
#   mechanical row  → base == chain head AND classify() between the two commits
#                     says mechanical was actually allowed (no code in delta/upstream)
#   scoped pair     → coherent (same scope+head+base); delta → base == chain head;
#                     full → base is the true merge-base for that head
#   legacy pair     → IGNORED post-cert (certify only; never rebind)
LAST_CLEAN_HEAD="$CERT_HEAD"
for n in $(echo "$ROWS" | cut -d'|' -f1 | sort -n | uniq); do
    [ "$n" -le "$CERT_N" ] && continue
    mline="$(echo "$ROWS" | awk -F'|' -v n="$n" '$1==n && $2=="mechanical" && $3=="mechanical"{print $4"|"$5}' | tail -1)"
    if [ -n "$mline" ]; then
        mh="${mline%%|*}"; mb="${mline##*|}"
        if [ "$mb" = "$LAST_CLEAN_HEAD" ] && classify "$LAST_CLEAN_HEAD" "$mh" \
           && [ "$C_DELTA" != "code" ] && [ "$C_UP" != "code" ]; then
            LAST_CLEAN_HEAD="$mh"
        fi
        continue
    fi
    cl="$(echo "$ROWS" | awk -F'|' -v n="$n" '$1==n && $2=="codex" && ($3=="full"||$3=="delta"){print $3"|"$4"|"$5}' | tail -1)"
    tl="$(echo "$ROWS" | awk -F'|' -v n="$n" '$1==n && $2=="pr-toolkit" && ($3=="full"||$3=="delta"){print $3"|"$4"|"$5}' | tail -1)"
    [ -n "$cl" ] && [ -n "$tl" ] || continue
    cs="${cl%%|*}"; r="${cl#*|}"; chh="${r%%|*}"; cb="${r#*|}"
    ts="${tl%%|*}"; r="${tl#*|}"; th="${r%%|*}";  tb="${r#*|}"
    [ "$cs" = "$ts" ] && [ "$chh" = "$th" ] && [ "$cb" = "$tb" ] && [ -n "$cb" ] || continue
    if [ "$cs" = "delta" ]; then
        [ "$cb" = "$LAST_CLEAN_HEAD" ] || continue   # stale-base delta never advances
        # The chain step itself must be REAL: ancestry intact + identity computable
        # (iter-6 P1 — a forged delta recorded after an amend/rebase must not become
        # the prior clean head for later rows; a rebase recovers only via a FULL pair).
        classify "$LAST_CLEAN_HEAD" "$chh" || continue
    else
        full_base_ok "$chh" "$cb" || continue        # full anchors at the true merge-base
    fi
    LAST_CLEAN_HEAD="$chh"
done
echo "LAST_CLEAN_HEAD:$LAST_CLEAN_HEAD"
# Rounds: max of (loop-counter − CERT_N) and the distinct post-cert evidence rows —
# finding-rounds appear only in the loop counter; clean rounds appear in both.
ROWS_POST="$(echo "$ROWS" | cut -d'|' -f1 | sort -n | uniq | awk -v c="$CERT_N" '$1>c' | wc -l | tr -d ' ')"
LOOP_POST=$(( LOOP_N > CERT_N ? LOOP_N - CERT_N : 0 ))
POST_CERT_ROUNDS=$(( LOOP_POST > ROWS_POST ? LOOP_POST : ROWS_POST ))
BREAKER=ok; [ "$POST_CERT_ROUNDS" -gt "$POST_CERT_REVIEW_ROUND_LIMIT" ] && BREAKER=tripped
# Post-certification count-less N/A = the breaker counter was erased → fail closed.
[ "$NA_COUNTLESS" = "1" ] && BREAKER=tripped

# --- Ancestry + PR-owned delta classification (chain head → current HEAD) ---
if ! classify "$LAST_CLEAN_HEAD" "$HEAD_SHA"; then
    # broken ancestry (rebase/rewrite) or any git failure → fail closed to full
    echo "ANCESTOR_OK:no"; echo "PR_OWNED_DELTA:n/a"; echo "UPSTREAM_FILES:n/a"; emit_full "$POST_CERT_ROUNDS" "$BREAKER" "$ADJ"
fi
echo "ANCESTOR_OK:yes"
echo "PR_OWNED_DELTA:$C_DELTA"
# Fold UNMERGED default-branch movement into the upstream surface (iter-7 P1):
# classify() sees only upstream code PULLED IN by merges (merge-base→merge-base);
# the PRD's interaction surface also covers what the default branch has moved
# AHEAD of the branch's incorporation point — the PR will merge into THAT. A
# docs-only rebind while main quietly moved runtime code must be delta, not
# mechanical. (Computed against the locally-known origin/<default>; a fetch
# refreshes it — the helper itself never touches the network.)
MBH="$(git merge-base "$DEFAULT_REF" "$HEAD_SHA" 2>/dev/null)" \
    || { echo "UPSTREAM_FILES:n/a"; emit_full "$POST_CERT_ROUNDS" "$BREAKER" "$ADJ"; }
PEND="$(git diff --name-only --no-renames "$MBH" "$DEFAULT_REF" 2>/dev/null)" \
    || { echo "UPSTREAM_FILES:n/a"; emit_full "$POST_CERT_ROUNDS" "$BREAKER" "$ADJ"; }
if [ -n "$PEND" ]; then
    [ "$C_UP" = "none" ] && C_UP=nonruntime
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in \"*) C_UP=code; break ;; esac   # quoted path → fail toward review
        is_docs "$f" || { C_UP=code; break; }
    done <<EOF
$PEND
EOF
fi
echo "UPSTREAM_FILES:$C_UP"

if [ "$C_DELTA" = "code" ] || [ "$C_UP" = "code" ]; then SCOPE=delta
else SCOPE=mechanical; fi
echo "SCOPE_REQUIRED:$SCOPE"
echo "POST_CERT_ROUNDS:$POST_CERT_ROUNDS"
echo "BREAKER:$BREAKER"
echo "ADJUDICATED:$ADJ"
exit 0
