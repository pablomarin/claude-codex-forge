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
if [ -z "$STATE" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    if [ -f "$ROOT/.forge/local/state.md" ]; then STATE="$ROOT/.forge/local/state.md"
    elif [ -f "$ROOT/.claude/local/state.md" ]; then STATE="$ROOT/.claude/local/state.md"
    fi
fi
emit_inert() { echo "CERTIFIED:no"; echo "POST_CERT_ROUNDS:0"; echo "BREAKER:ok"; echo "ADJUDICATED:no"; exit 0; }

# Decimal helpers mirror workflow-state's platform-neutral integer contract:
# canonical non-negative decimal text with no leading zeroes. They deliberately
# avoid machine-width arithmetic so the Bash and PowerShell readers accept the
# same values as the workflow-state writer.
decimal_valid_nonnegative() {
    case "$1" in ''|*[!0-9]*|0[0-9]*) return 1 ;; *) return 0 ;; esac
}
decimal_subtract() {
    local minuend="$1" subtrahend="$2" result="" borrow=0 i j a b digit
    [ ${#minuend} -gt ${#subtrahend} ] \
        || { [ ${#minuend} -eq ${#subtrahend} ] && [ "$minuend" \> "$subtrahend" -o "$minuend" = "$subtrahend" ]; } \
        || return 1
    i=$((${#minuend} - 1)); j=$((${#subtrahend} - 1))
    while [ "$i" -ge 0 ]; do
        a=${minuend:$i:1}; b=0
        [ "$j" -lt 0 ] || b=${subtrahend:$j:1}
        digit=$((a - borrow - b)); borrow=0
        if [ "$digit" -lt 0 ]; then digit=$((digit + 10)); borrow=1; fi
        result="$digit$result"
        i=$((i - 1)); j=$((j - 1))
    done
    result=$(printf '%s\n' "$result" | sed 's/^0*//')
    printf '%s\n' "${result:-0}"
}

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

# Legacy loop-counter line: rounds with FINDINGS wrote no clean rows, so pre-V6
# state uses "Code review loop (N iterations)" as its authoritative round count.
# Canonical V6 uses Receipts/Review iteration below and ignores this prose.
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

# Certification: a v6 schema marker always selects receipt-v2, even before a
# candidate path exists. Legacy rows remain readable only for pre-v6 state.
CERT_N=""; CERT_HEAD=""; V2_ACTIVE=false; ANCHOR_INVALID=false
CURRENT_N=""; CURRENT_INVALID=false; FIRST_COUNT=0
V2_SCHEMA=$(sed -n '1{s/\r$//;p;}' "$STATE")
case "$V2_SCHEMA" in '<!-- forge:state-schema v6 -->')
    V2_ACTIVE=true
    CURRENT_COUNT=$(tr -d '\r' < "$STATE" | awk -F'|' '
        /^## / { section=$0; sub(/^## /,"",section); next }
        section=="Receipts" && /^\|/ {
            key=$2; gsub(/^[ \t]+|[ \t]+$/,"",key)
            if(key=="Review iteration") count++
        }
        END { print count+0 }')
    if [ "$CURRENT_COUNT" -ne 1 ]; then
        CURRENT_INVALID=true
    else
        CURRENT_N=$(tr -d '\r' < "$STATE" | awk -F'|' '
            /^## / { section=$0; sub(/^## /,"",section); next }
            section=="Receipts" && /^\|/ {
                key=$2; gsub(/^[ \t]+|[ \t]+$/,"",key)
                if(key=="Review iteration") {
                    value=$3; gsub(/^[ \t]+|[ \t]+$/,"",value); print value; exit
                }
            }')
        decimal_valid_nonnegative "$CURRENT_N" || CURRENT_INVALID=true
    fi
    FIRST_COUNT=$(tr -d '\r' < "$STATE" | awk -F'|' '
        /^## / { section=$0; sub(/^## /,"",section); next }
        section=="Receipts" && /^\|/ {
            key=$2; gsub(/^[ \t]+|[ \t]+$/,"",key)
            if(key=="First certified iteration") count++
        }
        END { print count+0 }')
    if [ "$FIRST_COUNT" -gt 1 ]; then
        ANCHOR_INVALID=true; CERT_N=0
    elif [ "$FIRST_COUNT" -eq 1 ]; then
        FIRST_CERT=$(tr -d '\r' < "$STATE" | awk -F'|' '
            /^## / { section=$0; sub(/^## /,"",section); next }
            section=="Receipts" && /^\|/ {
                key=$2; gsub(/^[ \t]+|[ \t]+$/,"",key)
                if(key=="First certified iteration") {
                    value=$3; gsub(/^[ \t]+|[ \t]+$/,"",value); print value; exit
                }
            }')
        case "$FIRST_CERT" in none) ;;
            *) if decimal_valid_nonnegative "$FIRST_CERT" && [ "$FIRST_CERT" != 0 ]; then
                   CERT_N="$FIRST_CERT"; CERT_HEAD="$HEAD_SHA"
               else
                   ANCHOR_INVALID=true; CERT_N=0
               fi ;;
        esac
    fi
    if [ -z "$CERT_N" ]; then
        VR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)/verification-receipt.sh"
        [ -f "$VR" ] || VR="hooks/lib/verification-receipt.sh"
        if [ -f "$VR" ]; then
            V2_OUT=$(bash "$VR" check --state "$STATE" 2>/dev/null || true)
            if [ "$(printf '%s\n' "$V2_OUT" | sed -n 's/^REVIEWS_VALID://p' | tail -1)" = true ]; then
                CERT_N=$(printf '%s\n' "$V2_OUT" | sed -n 's/^REVIEW_ITERATION://p' | tail -1)
                CERT_HEAD="$HEAD_SHA"
                [ "$FIRST_COUNT" -eq 1 ] || ANCHOR_INVALID=true
            fi
        fi
    fi
    ;;
esac
if [ "$V2_ACTIVE" != true ]; then
    for n in $(echo "$ROWS" | cut -d'|' -f1 | sort -n | uniq); do
        [ -n "$n" ] || continue
        ch="$(echo "$ROWS" | awk -F'|' -v n="$n" '$1==n && $2=="codex"{print $3}' | tail -1)"
        th="$(echo "$ROWS" | awk -F'|' -v n="$n" '$1==n && $2=="pr-toolkit"{print $3}' | tail -1)"
        [ -n "$ch" ] && [ -n "$th" ] || continue
        [ "$ch" = "$th" ] || continue
        CERT_N="$n"; CERT_HEAD="$ch"; break
    done
fi

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

# Canonical V6 count comes only from the unique receipt-table rows. Legacy
# state retains max(loop counter, distinct clean rows) and counter-erasure rules.
BREAKER=ok; POST_CERT_ROUNDS=0
if [ "$V2_ACTIVE" = true ]; then
    if [ "$CURRENT_INVALID" = true ] || ! POST_CERT_ROUNDS=$(decimal_subtract "$CURRENT_N" "$CERT_N"); then
        POST_CERT_ROUNDS=0; BREAKER=tripped
    elif [ ${#POST_CERT_ROUNDS} -gt 1 ] || [ "$POST_CERT_ROUNDS" -gt "$POST_CERT_REVIEW_ROUND_LIMIT" ]; then
        BREAKER=tripped
    fi
else
    ROWS_POST="$(echo "$ROWS" | cut -d'|' -f1 | sort -n | uniq | awk -v c="$CERT_N" 'NF && $1>c' | wc -l | tr -d ' ')"
    LOOP_POST=$(( LOOP_N > CERT_N ? LOOP_N - CERT_N : 0 ))
    POST_CERT_ROUNDS=$(( LOOP_POST > ROWS_POST ? LOOP_POST : ROWS_POST ))
    [ "$POST_CERT_ROUNDS" -gt "$POST_CERT_REVIEW_ROUND_LIMIT" ] && BREAKER=tripped
fi
[ "$ANCHOR_INVALID" = false ] || BREAKER=tripped
# Only legacy state stores its counter in checklist wording. Canonical V6 prose
# may be count-less because Receipts/Review iteration cannot be erased by it.
[ "$V2_ACTIVE" = true ] || [ "$NA_COUNTLESS" = "0" ] || BREAKER=tripped

echo "POST_CERT_ROUNDS:$POST_CERT_ROUNDS"
echo "BREAKER:$BREAKER"
echo "ADJUDICATED:$ADJ"
exit 0
