#!/usr/bin/env bash
# hooks/lib/review-breaker.sh — convergence-breaker for the code-review loop
# (v5.54, ADR 0009). READ-ONLY: emits 4 sentinel lines, never writes. Small state.md
# reader — NO git diff machinery (the only git call is `rev-parse HEAD`).
#
# Usage: review-breaker.sh <state_md_path>   (run from a checkout of the branch)
# Sentinels (emitted in this exact order):
#   CERTIFIED:<yes|no>  POST_CERT_ROUNDS:<n>  BREAKER:<ok|tripped>  ADJUDICATED:<yes|no>
#
# Fail-safe direction: missing state / no git → CERTIFIED:no POST_CERT_ROUNDS:0
# BREAKER:ok ADJUDICATED:no (the breaker is inert on uncertified / non-workflow repos).
set -u
POST_CERT_REVIEW_ROUND_LIMIT=3   # canonical home — mirrored to prose by test-contracts.sh

STATE="${1:-}"
emit_inert() { echo "CERTIFIED:no"; echo "POST_CERT_ROUNDS:0"; echo "BREAKER:ok"; echo "ADJUDICATED:no"; exit 0; }

[ -n "$STATE" ] && [ -f "$STATE" ] || emit_inert
git rev-parse HEAD >/dev/null 2>&1 || emit_inert
HEAD_SHA="$(git rev-parse HEAD)"

# --- Parse evidence lines from the ### Checklist of ## Workflow (CRLF-safe) ---
# EXACT heading anchor (^## Workflow$) — mirrors the hooks' hardened parser; a
# stale "## Workflow Archive" section from a migration must not feed the count.
CHECKLIST="$(tr -d '\r' < "$STATE" | awk '/^## Workflow$/{w=1;next} w&&/^## /{w=0} w' | awk '/^### Checklist/{f=1;next} f&&/^### /{f=0} f')"

# rows: N|tool|head — match the exact legacy clean stems and ignore unknown/non-clean
# rows (mechanical, codex deep-pass); extra fields such as `scope=full — base=...`
# from this branch's dogfooding are safe — treated as inert suffixes, not scoped
# semantics. Note `— codex deep-pass clean` does NOT contain the substring
# `— codex clean`, so it is naturally ignored. head=`<hex>` is required.
ROWS="$(echo "$CHECKLIST" | awk '
  /^- \[x\] Code review iteration [0-9]+ — / {
    n=$0; sub(/^- \[x\] Code review iteration /,"",n); sub(/ .*/,"",n)
    tool=""
    if ($0 ~ /— codex clean/) tool="codex"
    else if ($0 ~ /— pr-toolkit clean/) tool="pr-toolkit"
    if (tool=="") next
    head=""; if (match($0,/head=`[0-9a-f]+`/)) { head=substr($0,RSTART+6,RLENGTH-7) }
    if (head=="") next
    print n "|" tool "|" head
  }')"

# Loop-counter line: rounds with FINDINGS write no clean rows (the incident shape),
# so the loop line "Code review loop (N iterations)" is the authoritative round count.
LOOP_N="$(echo "$CHECKLIST" | grep -E 'Code review loop \([0-9]+ iterations\)' \
    | sed -E 's/.*Code review loop \(([0-9]+) iterations\).*/\1/' | tail -1)"
[ -n "$LOOP_N" ] || LOOP_N=0

# Count-less N/A detection: replacing the counted loop line with
# `Code review loop — N/A: <reason>` would zero LOOP_N and silently reset the
# breaker. Post-certification (applied below), a count-less N/A line is treated
# as breaker evasion → BREAKER:tripped (fail-closed; human adjudication clears).
# The count-PRESERVING form `Code review loop (<N> iterations) — N/A: <reason>`
# keeps the count and does not trip this.
NA_COUNTLESS=0
echo "$CHECKLIST" | grep -E 'Code review loop' | grep -E 'N/A:' \
    | grep -qvE '\([0-9]+ iterations\)' && NA_COUNTLESS=1

# Certification: lowest N with BOTH engines clean at the SAME head.
CERT_N=""; CERT_HEAD=""
for n in $(echo "$ROWS" | cut -d'|' -f1 | sort -n | uniq); do
    [ -n "$n" ] || continue
    ch="$(echo "$ROWS" | awk -F'|' -v n="$n" '$1==n && $2=="codex"{print $3}' | tail -1)"
    th="$(echo "$ROWS" | awk -F'|' -v n="$n" '$1==n && $2=="pr-toolkit"{print $3}' | tail -1)"
    [ -n "$ch" ] && [ -n "$th" ] || continue
    [ "$ch" = "$th" ] || continue
    CERT_N="$n"; CERT_HEAD="$ch"; break
done

# Human adjudication line bound to the CURRENT head (unblocks a tripped breaker).
ADJ=no
echo "$CHECKLIST" | grep -E '^- \[x\] Post-certification tail adjudicated by human — ' \
    | grep -q "head=\`$HEAD_SHA\`" && ADJ=yes

if [ -z "$CERT_N" ]; then
    # Uncertified: breaker inert (certification has not occurred yet).
    echo "CERTIFIED:no"; echo "POST_CERT_ROUNDS:0"; echo "BREAKER:ok"; echo "ADJUDICATED:$ADJ"
    exit 0
fi
echo "CERTIFIED:yes"

# Rounds: max of (loop-counter − CERT_N) and the distinct post-cert evidence rows —
# finding-rounds appear only in the loop counter; clean rounds appear in both.
ROWS_POST="$(echo "$ROWS" | cut -d'|' -f1 | sort -n | uniq | awk -v c="$CERT_N" 'NF && $1>c' | wc -l | tr -d ' ')"
LOOP_POST=$(( LOOP_N > CERT_N ? LOOP_N - CERT_N : 0 ))
POST_CERT_ROUNDS=$(( LOOP_POST > ROWS_POST ? LOOP_POST : ROWS_POST ))

BREAKER=ok; [ "$POST_CERT_ROUNDS" -gt "$POST_CERT_REVIEW_ROUND_LIMIT" ] && BREAKER=tripped
# Post-certification count-less N/A = the breaker counter was erased → fail closed.
[ "$NA_COUNTLESS" = "1" ] && BREAKER=tripped

echo "POST_CERT_ROUNDS:$POST_CERT_ROUNDS"
echo "BREAKER:$BREAKER"
echo "ADJUDICATED:$ADJ"
exit 0
