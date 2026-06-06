#!/usr/bin/env bash
# tests/template/test-review-breaker.sh — EXECUTABLE tests for the convergence
# breaker (v5.54, ADR 0009). The contract suite (test-contracts.sh) statically pins
# that the helper twins + prose exist; THIS suite executes the load-bearing logic so a
# wrong awk, a wrong round-count, or a wrong head-binding fails CI even though the
# marker strings are still present.
#
#   Level 1 — hooks/lib/review-breaker.sh sentinels, run inside a REAL git repo.
#   Level 2 — the actual check-workflow-gates.sh breaker block, driven via a
#             PreToolUse stdin payload (pattern: test-hooks.sh), asserting the
#             block / release behavior on real scratch repos.
#   PS parity — re-run a subset through Invoke-ReviewBreaker where a PS runner exists.
#
# Run from repo root:  bash tests/template/test-review-breaker.sh

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

HELPER="$REPO_ROOT/hooks/lib/review-breaker.sh"
GATE="$REPO_ROOT/hooks/check-workflow-gates.sh"

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# build_repo: scratch git repo with main + a feat branch and one feature commit.
# Sets R. .claude/ is gitignored so `add -A` never tracks the helper/state and
# clobbers them on checkout. The breaker helper is read-only and reads state.md +
# one `git rev-parse HEAD`, so a single base + feat commit is enough.
build_repo() {
    R="$(scratch_dir revbreaker)"
    git -C "$R" init -q -b main
    git -C "$R" config user.email t@t.t; git -C "$R" config user.name t
    mkdir -p "$R/src"
    echo ".claude/" > "$R/.gitignore"
    echo "base" > "$R/src/app.py"
    git -C "$R" add -A; git -C "$R" commit -qm base
    git -C "$R" checkout -qb feat
    echo "feature" >> "$R/src/app.py"
    git -C "$R" add -A; git -C "$R" commit -qm feat1
}

# install_helper <repo>: copy ONLY review-breaker.sh into the scratch repo's
# .claude/hooks/lib/ (the gate's RS resolution path). The helper does not source
# default-branch.sh (verified: only references it in comments), so it is not copied.
install_helper() {
    local r="$1"
    mkdir -p "$r/.claude/hooks/lib"
    cp "$HELPER" "$r/.claude/hooks/lib/"
}

# write_state <repo> <checklist-body>: emit an active ## Workflow state.md whose
# ### Checklist is the supplied body.
write_state() {
    local r="$1" body="$2"
    mkdir -p "$r/.claude/local"
    { echo "## Workflow"; echo
      echo "| Field | Value |"
      echo "| Command | /new-feature x |"
      echo
      echo "### Checklist"; echo
      printf '%s\n' "$body"
    } > "$r/.claude/local/state.md"
}

# run_helper <repo>: run review-breaker.sh from a checkout of the branch (the
# helper's only git call is `rev-parse HEAD`, which needs to run in-repo). Sets
# RB_OUT to the 4 sentinel lines.
run_helper() { RB_OUT="$( ( cd "$1" && bash "$HELPER" .claude/local/state.md ) 2>/dev/null )"; }

# assert_contains_str <needle> <haystack> <msg>: literal substring match on a string.
assert_contains_str() {
    local needle="$1" hay="$2" msg="$3"
    if printf '%s' "$hay" | grep -qF -- "$needle"; then pass "$msg"
    else fail "$msg (missing '$needle' in: $(printf '%s' "$hay" | tr '\n' ' ' | cut -c1-200))"; fi
}
assert_not_contains_str() {
    local needle="$1" hay="$2" msg="$3"
    if printf '%s' "$hay" | grep -qF -- "$needle"; then
        fail "$msg (unexpectedly found '$needle' in: $(printf '%s' "$hay" | tr '\n' ' ' | cut -c1-200))"
    else pass "$msg"; fi
}

# ===========================================================================
# Level 1 — helper sentinels
# ===========================================================================

# --- (a) uncertified (empty checklist) → CERTIFIED:no, BREAKER:ok
start_test "(a) uncertified / empty evidence → CERTIFIED:no, BREAKER:ok"
build_repo; install_helper "$R"
write_state "$R" "- [ ] Code review loop (1 iterations) — iterate until no P0/P1/P2"
run_helper "$R"
assert_contains_str "CERTIFIED:no" "$RB_OUT" "no certifying pair → CERTIFIED:no"
assert_contains_str "BREAKER:ok"   "$RB_OUT" "uncertified branch → breaker inert"
assert_contains_str "POST_CERT_ROUNDS:0" "$RB_OUT" "no certification → 0 rounds"

# --- (b) legacy pair at head, no loop counter → CERTIFIED:yes, ROUNDS:0, BREAKER:ok
start_test "(b) legacy pair at head, no loop counter → CERTIFIED:yes, ROUNDS:0, BREAKER:ok"
build_repo; install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
write_state "$R" "- [x] Code review iteration 1 — codex clean — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
run_helper "$R"
assert_contains_str "CERTIFIED:yes" "$RB_OUT" "legacy pair at same head → certified"
assert_contains_str "POST_CERT_ROUNDS:0" "$RB_OUT" "no loop counter, no later rows → 0 rounds"
assert_contains_str "BREAKER:ok" "$RB_OUT" "0 rounds → breaker ok"

# --- (c) loop counter 4, cert at 1 → POST_CERT_ROUNDS:3, BREAKER:ok (boundary)
start_test "(c) loop counter 4, cert at 1 → ROUNDS:3, BREAKER:ok (limit not exceeded)"
build_repo; install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
write_state "$R" "- [ ] Code review loop (4 iterations) — iterate until no P0/P1/P2
- [x] Code review iteration 1 — codex clean — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
run_helper "$R"
assert_contains_str "POST_CERT_ROUNDS:3" "$RB_OUT" "4 − 1 = 3 rounds"
assert_contains_str "BREAKER:ok" "$RB_OUT" "3 == limit → not tripped (boundary)"

# --- (d) loop counter 5, cert at 1 → POST_CERT_ROUNDS:4, BREAKER:tripped
start_test "(d) loop counter 5, cert at 1 → ROUNDS:4, BREAKER:tripped"
build_repo; install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
write_state "$R" "- [ ] Code review loop (5 iterations) — iterate until no P0/P1/P2
- [x] Code review iteration 1 — codex clean — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
run_helper "$R"
assert_contains_str "POST_CERT_ROUNDS:4" "$RB_OUT" "5 − 1 = 4 rounds"
assert_contains_str "BREAKER:tripped" "$RB_OUT" "4 > 3 → tripped"

# --- (e) rows-only counting: cert at 1 + clean rows for iters 2..5 but loop line
#         still (1 iterations) → POST_CERT_ROUNDS:4 (the max() arm via distinct rows)
start_test "(e) rows-only counting (loop line stale at 1) → ROUNDS:4 via max() arm"
build_repo; install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
write_state "$R" "- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`
- [x] Code review iteration 2 — codex clean — head=\`${H}\`
- [x] Code review iteration 2 — pr-toolkit clean — head=\`${H}\`
- [x] Code review iteration 3 — codex clean — head=\`${H}\`
- [x] Code review iteration 3 — pr-toolkit clean — head=\`${H}\`
- [x] Code review iteration 4 — codex clean — head=\`${H}\`
- [x] Code review iteration 4 — pr-toolkit clean — head=\`${H}\`
- [x] Code review iteration 5 — codex clean — head=\`${H}\`
- [x] Code review iteration 5 — pr-toolkit clean — head=\`${H}\`"
run_helper "$R"
assert_contains_str "POST_CERT_ROUNDS:4" "$RB_OUT" "distinct post-cert rows 2..5 = 4 (max arm beats stale loop count)"
assert_contains_str "BREAKER:tripped" "$RB_OUT" "4 > 3 → tripped via rows"

# --- (f) count-less N/A AFTER certification → tripped; count-preserving N/A → ok
start_test "(f) post-cert count-less N/A → tripped; count-preserving N/A → ok"
build_repo; install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
write_state "$R" "- [x] Code review loop — N/A: ran out of budget
- [x] Code review iteration 1 — codex clean — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
run_helper "$R"
assert_contains_str "CERTIFIED:yes" "$RB_OUT" "certified pair present"
assert_contains_str "BREAKER:tripped" "$RB_OUT" "count-less N/A after cert = counter erasure → tripped"
# count-preserving form keeps the count → ok
write_state "$R" "- [x] Code review loop (2 iterations) — N/A: ran out of budget
- [x] Code review iteration 1 — codex clean — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
run_helper "$R"
assert_contains_str "BREAKER:ok" "$RB_OUT" "count-preserving N/A (2 iterations) → ok (2-1=1 round, under limit)"

# --- (g) count-less N/A, UNCERTIFIED → ok (pre-cert N/A is harmless)
start_test "(g) count-less N/A but uncertified → BREAKER:ok (pre-cert N/A harmless)"
build_repo; install_helper "$R"
write_state "$R" "- [x] Code review loop — N/A: skipping, no codex"
run_helper "$R"
assert_contains_str "CERTIFIED:no" "$RB_OUT" "no certifying pair → not certified"
assert_contains_str "BREAKER:ok" "$RB_OUT" "count-less N/A before certification does not trip the breaker"

# --- (h) ADJUDICATED head-bound: line at current head → yes; after a new commit → no
start_test "(h) adjudication line is HEAD-bound (yes at head, no after head moves)"
build_repo; install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
write_state "$R" "- [ ] Code review loop (5 iterations) — iterate until no P0/P1/P2
- [x] Code review iteration 1 — codex clean — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`
- [x] Post-certification tail adjudicated by human — accepted P2 tail — head=\`${H}\` — ts=\`2026-06-06T00:00:00Z\`"
run_helper "$R"
assert_contains_str "BREAKER:tripped" "$RB_OUT" "5−1=4 rounds → still tripped (adjudication is a separate sentinel)"
assert_contains_str "ADJUDICATED:yes" "$RB_OUT" "adjudication line bound to current head → yes"
# Move HEAD — the same adjudication line now points at a stale head.
echo "more" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm more
run_helper "$R"
assert_contains_str "ADJUDICATED:no" "$RB_OUT" "after a new commit, the adjudication head is stale → no"

# --- (i) dogfood tolerance: inert scope/base suffixes still certify; deep-pass /
#         mechanical rows ignored (do not certify alone)
start_test "(i) dogfood tolerance: scope/base suffixes certify; deep-pass + mechanical ignored"
build_repo; install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
write_state "$R" "- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`x\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`x\` — head=\`${H}\`"
run_helper "$R"
assert_contains_str "CERTIFIED:yes" "$RB_OUT" "rows carrying inert scope/base suffixes still certify"
# deep-pass + mechanical rows alone (no plain `codex clean` / `pr-toolkit clean` pair) → not certified
write_state "$R" "- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex deep-pass clean — head=\`${H}\`
- [x] Code review iteration 1 — mechanical re-stamp — head=\`${H}\`"
run_helper "$R"
assert_contains_str "CERTIFIED:no" "$RB_OUT" "deep-pass + mechanical rows alone do NOT certify"

# --- (j) stale `## Workflow Archive` section with evidence + real `## Workflow`
#         without → CERTIFIED:no (exact ^## Workflow$ anchor)
start_test "(j) exact anchor: '## Workflow Archive' evidence does NOT feed the real '## Workflow'"
build_repo; install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
mkdir -p "$R/.claude/local"
{ echo "## Workflow Archive"; echo
  echo "### Checklist"; echo
  echo "- [x] Code review loop (1 iterations) — PASS"
  echo "- [x] Code review iteration 1 — codex clean — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
  echo
  echo "## Workflow"; echo
  echo "| Field | Value |"
  echo "| Command | /new-feature x |"
  echo
  echo "### Checklist"; echo
  echo "- [ ] Code review loop (1 iterations) — iterate until no P0/P1/P2"
} > "$R/.claude/local/state.md"
RB_OUT="$( ( cd "$R" && bash "$HELPER" .claude/local/state.md ) 2>/dev/null )"
assert_contains_str "CERTIFIED:no" "$RB_OUT" "archive-section evidence is excluded by the exact ^## Workflow\$ anchor"

# --- (k) mixed-head pair (codex at H1, toolkit at H2, same N) → does NOT certify
start_test "(k) mixed-head pair (same N, different heads) → does NOT certify"
build_repo; install_helper "$R"
H1="$(git -C "$R" rev-parse HEAD)"
echo "x" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm c2
H2="$(git -C "$R" rev-parse HEAD)"
write_state "$R" "- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — head=\`${H1}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H2}\`"
run_helper "$R"
assert_contains_str "CERTIFIED:no" "$RB_OUT" "pair at different heads for the same N → not a coherent certification"

# ===========================================================================
# Level 2 — GATE behaviors (check-workflow-gates.sh breaker block)
#
# Run the REAL gate hook against scratch repos with review-breaker.sh installed
# under .claude/hooks/lib/. Driven via a PreToolUse stdin payload (pattern:
# test-hooks.sh / the retired test-review-scope.sh) with a `git commit` ship verb
# and a `cwd` at the repo root so the hook cds there and resolves RS.
# ===========================================================================

# run_gate <repo> [command]: run the gate hook with a ship-verb stdin payload.
# Sets GATE_RC (exit code) and GATE_ERR (combined stdout+stderr).
run_gate() {
    local r="$1" cmd="${2:-git commit -m wip}" esc
    esc="$(printf '%s' "$cmd" | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); print}')"
    printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$r" "$esc" \
        > "$r/.gate-input.json"
    GATE_ERR="$( ( cd "$r" && bash "$GATE" < "$r/.gate-input.json" ) 2>&1 )"
    GATE_RC=$?
}

assert_rc() { # <expected_rc> <msg>
    if [ "$GATE_RC" = "$1" ]; then pass "$2"
    else fail "$2 (got rc=$GATE_RC; err: $(printf '%s' "$GATE_ERR" | tr '\n' ' ' | cut -c1-200))"; fi
}

# tripped_state <repo> <head>: write a state.md whose breaker is tripped — loop
# counter 5 with certification at iteration 1 → post_cert_rounds = 4 > limit. All 4
# pre-ship quality gates are checked AND per-iter clean pairs exist for iterations
# 1..5 at the current head (so the gate's per-iter-evidence check is satisfied and
# the ONLY remaining block is the breaker, or — once adjudicated — nothing). Cert is
# still iteration 1 (lowest N with a coherent pair), so the breaker math is unchanged.
# Caller supplies extra lines via $EXTRA.
tripped_state() {
    local r="$1" h="$2" n
    mkdir -p "$r/.claude/local"
    { echo "## Workflow"; echo
      echo "| Field | Value |"
      echo "| Command | /new-feature x |"
      echo
      echo "### Checklist"; echo
      echo "- [x] Code review loop (5 iterations) — PASS"
      for n in 1 2 3 4 5; do
        echo "- [x] Code review iteration $n — codex clean — head=\`${h}\`"
        echo "- [x] Code review iteration $n — pr-toolkit clean — head=\`${h}\`"
      done
      echo "- [x] Simplified"
      echo "- [x] Verified (tests/lint/types)"
      echo "- [x] E2E verified — N/A: internal harness change, no user surface"
      printf '%s' "${EXTRA:-}"
    } > "$r/.claude/local/state.md"
}

# --- Gate 1: tripped + no adjudication → exit 2 + POST_CERT_REVIEW_ROUND_LIMIT
start_test "gate 1: breaker tripped, no adjudication → exit 2 + POST_CERT_REVIEW_ROUND_LIMIT"
build_repo; install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
EXTRA="" tripped_state "$R" "$H"
run_gate "$R"
assert_rc 2 "tripped breaker blocks the commit"
assert_contains_str "POST_CERT_REVIEW_ROUND_LIMIT" "$GATE_ERR" "stderr names the limit"
assert_contains_str "convergence breaker" "$GATE_ERR" "stderr names the convergence breaker"

# --- Gate 2: tripped + a `Code review loop — N/A:` escape → STILL exit 2
#     (the breaker block precedes the N/A handling and runs on a count-less N/A,
#      which itself keeps the breaker tripped).
start_test "gate 2: tripped + count-less 'Code review loop — N/A:' escape → STILL exit 2"
build_repo; install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo
  echo "| Field | Value |"
  echo "| Command | /new-feature x |"
  echo
  echo "### Checklist"; echo
  echo "- [x] Code review loop — N/A: out of budget"
  echo "- [x] Code review iteration 1 — codex clean — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
  echo "- [x] Simplified"
  echo "- [x] Verified (tests/lint/types)"
  echo "- [x] E2E verified — N/A: internal harness change, no user surface"
} > "$R/.claude/local/state.md"
run_gate "$R"
assert_rc 2 "count-less N/A does NOT bypass the breaker"
assert_contains_str "convergence breaker" "$GATE_ERR" "N/A escape still hits the breaker block"

# --- Gate 3: tripped + a DOCS-ONLY staged commit → STILL exit 2
#     (breaker precedes the docs-only carve-out).
start_test "gate 3: tripped + docs-only staged commit → STILL exit 2 (breaker precedes carve-out)"
build_repo; install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
EXTRA="" tripped_state "$R" "$H"
mkdir -p "$R/docs"; echo "note" >> "$R/docs/CHANGELOG.md"; git -C "$R" add docs/CHANGELOG.md
run_gate "$R"
assert_rc 2 "a docs-only staged diff does not get past the breaker"
assert_contains_str "convergence breaker" "$GATE_ERR" "docs-only commit still hits the breaker block"

# --- Gate 4: tripped + adjudication at current head → breaker RELEASES.
#     The other pre-ship gates are all checked, so a released breaker should let
#     the commit through cleanly (no other gate blocks). We assert the breaker
#     message is ABSENT (the load-bearing claim) AND, since the fixture is built
#     complete, that the gate exits 0 (commit needs no E2E evidence — N/A).
start_test "gate 4: tripped + adjudication at current head → breaker released (no breaker message)"
build_repo; install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
EXTRA="- [x] Post-certification tail adjudicated by human — accepted P2 tail — head=\`${H}\` — ts=\`2026-06-06T00:00:00Z\`
" tripped_state "$R" "$H"
run_gate "$R"
assert_not_contains_str "convergence breaker" "$GATE_ERR" "current-head adjudication releases the breaker"
assert_rc 0 "released breaker + all other gates checked (E2E N/A) → commit allowed"

# --- Gate 5: untripped happy path → no breaker message (cert at 1, loop 2 = 1 round)
start_test "gate 5: untripped (1 post-cert round) → no breaker message, commit allowed"
build_repo; install_helper "$R"
H="$(git -C "$R" rev-parse HEAD)"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo
  echo "| Field | Value |"
  echo "| Command | /new-feature x |"
  echo
  echo "### Checklist"; echo
  echo "- [x] Code review loop (2 iterations) — PASS"
  echo "- [x] Code review iteration 1 — codex clean — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
  echo "- [x] Code review iteration 2 — codex clean — head=\`${H}\`"
  echo "- [x] Code review iteration 2 — pr-toolkit clean — head=\`${H}\`"
  echo "- [x] Simplified"
  echo "- [x] Verified (tests/lint/types)"
  echo "- [x] E2E verified — N/A: internal harness change, no user surface"
} > "$R/.claude/local/state.md"
run_gate "$R"
assert_not_contains_str "convergence breaker" "$GATE_ERR" "1 post-cert round is under the limit → breaker inert"
assert_rc 0 "untripped happy path → commit allowed"

# ===========================================================================
# PowerShell parity — re-run cases d, f, h through Invoke-ReviewBreaker via the
# standalone entrypoint. Skipped (as a PASS) when no PowerShell runtime is
# present, so macOS/Linux CI stays green. Runner discovered via the repo's
# pwsh → powershell → powershell.exe fallback chain (matches test-contracts.sh).
# ===========================================================================
detect_pwsh() {
    if command -v pwsh >/dev/null 2>&1; then echo "pwsh"; return 0; fi
    if command -v powershell >/dev/null 2>&1; then echo "powershell"; return 0; fi
    if command -v powershell.exe >/dev/null 2>&1; then echo "powershell.exe"; return 0; fi
    return 1
}
HELPER_PS="$REPO_ROOT/hooks/lib/review-breaker.ps1"
PS_RUNNER="$(detect_pwsh || true)"
run_helper_ps() { ( cd "$1" && "$PS_RUNNER" -NoProfile -File "$HELPER_PS" .claude/local/state.md 2>/dev/null ); }

start_test "PowerShell parity (review-breaker.ps1 via Invoke-ReviewBreaker entrypoint)"
if [ -z "$PS_RUNNER" ]; then
    pass "skipped (no PowerShell runner)"
else
    # Case d: loop 5, cert 1 → ROUNDS:4, tripped
    build_repo
    H="$(git -C "$R" rev-parse HEAD)"
    write_state "$R" "- [ ] Code review loop (5 iterations) — iterate until no P0/P1/P2
- [x] Code review iteration 1 — codex clean — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
    out="$(run_helper_ps "$R")"
    assert_contains_str "POST_CERT_ROUNDS:4" "$out" "ps: 5−1=4 rounds"
    assert_contains_str "BREAKER:tripped" "$out" "ps: 4 > 3 → tripped"

    # Case f: count-less N/A after cert → tripped; count-preserving → ok
    build_repo
    H="$(git -C "$R" rev-parse HEAD)"
    write_state "$R" "- [x] Code review loop — N/A: out of budget
- [x] Code review iteration 1 — codex clean — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
    out="$(run_helper_ps "$R")"
    assert_contains_str "BREAKER:tripped" "$out" "ps: count-less N/A after cert → tripped"
    write_state "$R" "- [x] Code review loop (2 iterations) — N/A: out of budget
- [x] Code review iteration 1 — codex clean — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
    out="$(run_helper_ps "$R")"
    assert_contains_str "BREAKER:ok" "$out" "ps: count-preserving N/A → ok"

    # Case h: adjudication head-bound (yes at head, no after head moves)
    build_repo
    H="$(git -C "$R" rev-parse HEAD)"
    write_state "$R" "- [ ] Code review loop (5 iterations) — iterate until no P0/P1/P2
- [x] Code review iteration 1 — codex clean — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`
- [x] Post-certification tail adjudicated by human — accepted — head=\`${H}\` — ts=\`2026-06-06T00:00:00Z\`"
    out="$(run_helper_ps "$R")"
    assert_contains_str "ADJUDICATED:yes" "$out" "ps: adjudication at current head → yes"
    echo "more" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm more
    out="$(run_helper_ps "$R")"
    assert_contains_str "ADJUDICATED:no" "$out" "ps: after head moves → no"
fi

# lib.sh's EXIT trap prints scratch info; emit the summary explicitly.
report "test-review-breaker.sh"
