#!/usr/bin/env bash
# tests/template/test-review-scope.sh — EXECUTABLE tests for the scoped-review-
# certification helper (hooks/lib/review-scope.sh) and the gate behaviors that
# depend on it. Builds REAL scratch git repos per case (pattern: test-state-roundtrip.sh).
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

HELPER="$REPO_ROOT/hooks/lib/review-scope.sh"
assert_contains_str()     { case "$2" in *"$1"*) pass "$3";; *) fail "$3";; esac; }

# build_repo: scratch repo with main + feature branch. Sets R (repo), and leaves
# the feature branch checked out in a worktree-like clone dir $R/wt is NOT needed —
# helper runs from any checkout of the branch.
build_repo() {
    R="$(scratch_dir revscope)"
    git -C "$R" init -q -b main
    git -C "$R" config user.email t@t.t; git -C "$R" config user.name t
    mkdir -p "$R/src" "$R/docs"
    # .claude/ MUST be gitignored in the fixture: tests use `git add -A` on BOTH
    # branches — without this, a main-side add -A tracks the untracked .claude/
    # and the next `checkout feat` REMOVES the helper + state.md from the tree
    # (found empirically in the plan-stage smoke).
    echo ".claude/" > "$R/.gitignore"
    echo "base" > "$R/src/app.py"; echo "# doc" > "$R/docs/CHANGELOG.md"
    git -C "$R" add -A; git -C "$R" commit -qm base
    git -C "$R" checkout -qb feat
    echo "feature" >> "$R/src/app.py"
    git -C "$R" add -A; git -C "$R" commit -qm feat1
}
# write_evidence <repo> <iterN> <scope-or-LEGACY> <head>: writes a state.md with a
# both-engine clean pair at iteration N.
write_evidence() {
    local r="$1" n="$2" scope="$3" head="$4" sfx=""
    [ "$scope" != "LEGACY" ] && sfx=" — scope=${scope} — base=\`$(git -C "$r" merge-base main "$head")\`"
    mkdir -p "$r/.claude/local"
    cat > "$r/.claude/local/state.md" <<EOF
## Workflow

| Field | Value |
| Command | /new-feature x |

### Checklist

- [x] Code review iteration ${n} — codex clean${sfx} — head=\`${head}\`
- [x] Code review iteration ${n} — pr-toolkit clean${sfx} — head=\`${head}\`
EOF
}
run_helper() { ( cd "$1" && bash "$HELPER" .claude/local/state.md 2>/dev/null ); }

start_test "uncertified branch requires full scope"
build_repo
mkdir -p "$R/.claude/local"; echo "## Workflow" > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "CERTIFIED:no" "$out" "no evidence → not certified"
assert_contains_str "SCOPE_REQUIRED:full" "$out" "uncertified → full"

start_test "certified + no movement → mechanical (empty PR-owned delta)"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
out="$(run_helper "$R")"
assert_contains_str "CERTIFIED:yes" "$out" "full pair certifies"
assert_contains_str "PR_OWNED_DELTA:empty" "$out" "same head → empty delta"
assert_contains_str "SCOPE_REQUIRED:mechanical" "$out" "empty → mechanical"

start_test "merge-from-main with docs-only conflict shape → mechanical (the PR #89 case)"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
git -C "$R" checkout -q main
echo "main moved" >> "$R/docs/CHANGELOG.md"; git -C "$R" add -A; git -C "$R" commit -qm mainmove
git -C "$R" checkout -q feat; git -C "$R" merge -q main -m merge 2>/dev/null
out="$(run_helper "$R")"
assert_contains_str "PR_OWNED_DELTA:empty" "$out" "pure merge → PR-owned diff unchanged (patch-id stable)"
assert_contains_str "UPSTREAM_FILES:nonruntime" "$out" "upstream moved docs only"
assert_contains_str "SCOPE_REQUIRED:mechanical" "$out" "docs-only rebind → mechanical"

start_test "post-cert code commit → delta"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm fix
out="$(run_helper "$R")"
assert_contains_str "PR_OWNED_DELTA:code" "$out" "code commit → code delta"
assert_contains_str "SCOPE_REQUIRED:delta" "$out" "code → delta review"

start_test "post-cert docs-only branch commit → mechanical"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
echo "note" >> "$R/docs/CHANGELOG.md"; git -C "$R" add -A; git -C "$R" commit -qm docs
out="$(run_helper "$R")"
assert_contains_str "PR_OWNED_DELTA:docs-only" "$out" "docs commit → docs-only"
assert_contains_str "SCOPE_REQUIRED:mechanical" "$out" "docs-only → mechanical"

start_test "UNMERGED upstream code movement blocks mechanical (interaction surface)"
# main moves runtime code AFTER branch-off (no merge into the branch); branch
# makes a docs-only commit. The PR will merge into the moved main — the
# interaction surface is non-empty, so mechanical is not allowed (iter-7 P1).
build_repo
H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
git -C "$R" checkout -q main
echo "moved" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm "main moves code"
git -C "$R" checkout -q feat
echo "note" > "$R/docs/notes.md"
git -C "$R" add -A; git -C "$R" commit -qm docs
out="$(run_helper "$R")"
assert_contains_str "UPSTREAM_FILES:code" "$out" "unmerged main code movement detected"
assert_contains_str "SCOPE_REQUIRED:delta" "$out" "interaction surface → delta, not mechanical"

start_test "UNMERGED upstream docs-only movement keeps mechanical"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
git -C "$R" checkout -q main
echo "docs" >> "$R/docs/CHANGELOG.md"; git -C "$R" add -A; git -C "$R" commit -qm "main moves docs"
git -C "$R" checkout -q feat
echo "note" > "$R/docs/notes.md"
git -C "$R" add -A; git -C "$R" commit -qm docs
out="$(run_helper "$R")"
assert_contains_str "UPSTREAM_FILES:nonruntime" "$out" "docs-only main movement is nonruntime"
assert_contains_str "SCOPE_REQUIRED:mechanical" "$out" "nonruntime upstream keeps mechanical"

start_test "docs/ paths with code extensions are RUNTIME (gate-predicate parity)"
# is_docs() mirrors _is_doc_path() in check-workflow-gates.sh: docs/foo.py,
# docs/config.json, and bare *.md OUTSIDE docs/ (commands/*.md) are all CODE.
for f in "docs/example.py" "docs/config.json" "commands/new-feature.md"; do
    build_repo
    H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
    mkdir -p "$R/$(dirname "$f")"; echo "x" >> "$R/$f"
    git -C "$R" add -A; git -C "$R" commit -qm "touch $f"
    out="$(run_helper "$R")"
    assert_contains_str "PR_OWNED_DELTA:code" "$out" "$f → code delta"
    assert_contains_str "SCOPE_REQUIRED:delta" "$out" "$f → delta review"
done

start_test "code path WITH SPACES still classifies as code (line-based iteration)"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
echo "code" > "$R/src/a b.py"
git -C "$R" add -A; git -C "$R" commit -qm "spaced path"
out="$(run_helper "$R")"
assert_contains_str "PR_OWNED_DELTA:code" "$out" "src/a b.py survives iteration un-split"
assert_contains_str "SCOPE_REQUIRED:delta" "$out" "spaced code path → delta"

start_test "post-cert code→docs RENAME still requires delta (--no-renames)"
# A pure rename src/app.py → docs/app.md would, with rename detection on, report
# only the docs path and classify docs-only. --no-renames surfaces the code-side
# deletion. (Same reason the commit carve-out uses --no-renames.)
build_repo
H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
git -C "$R" mv src/app.py docs/app.md
git -C "$R" commit -qm "rename code to docs"
out="$(run_helper "$R")"
assert_contains_str "PR_OWNED_DELTA:code" "$out" "rename surfaces the deleted code path"
assert_contains_str "SCOPE_REQUIRED:delta" "$out" "code→docs rename → delta"

start_test "unknown scope value (scope=fullish) is dropped — never certifies as legacy"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review iteration 1 — codex clean — scope=fullish — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=fullish — base=\`${B}\` — head=\`${H}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "CERTIFIED:no" "$out" "scope=fullish rows dropped entirely"

start_test "stale '## Workflow Archive' section never feeds the chain (exact heading anchor)"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
mkdir -p "$R/.claude/local"
{ echo "## Workflow Archive"; echo; echo "### Checklist"; echo
  echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo; echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [ ] Code review loop (0 iterations) — iterate until no P0/P1/P2"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "CERTIFIED:no" "$out" "archive-section evidence ignored"

start_test "mechanical row with WRONG base does not advance the chain"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm fix
H2="$(git -C "$R" rev-parse HEAD)"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 2 — mechanical re-stamp — scope=mechanical — base=\`${B}\` — head=\`${H2}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "LAST_CLEAN_HEAD:$H" "$out" "mechanical with base≠prior-clean-head ignored (no self-validation)"

start_test "FABRICATED mechanical row over a CODE delta does not poison the chain"
# Chain rows are appended between ships and may never have been gate-checked —
# the helper must re-validate every historical mechanical claim by recomputation.
build_repo
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm "code fix"
H2="$(git -C "$R" rev-parse HEAD)"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 2 — mechanical re-stamp — scope=mechanical — base=\`${H}\` — head=\`${H2}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "LAST_CLEAN_HEAD:$H" "$out" "mechanical-over-code (base correct!) still does not advance"
assert_contains_str "SCOPE_REQUIRED:delta" "$out" "the unreviewed code delta still demands a delta review"

start_test "DELAYED poisoning: forged delta after an amend never becomes the prior clean head"
# cert at H → amend rewrites to H2 (H no longer an ancestor) → forged delta pair
# base=H head=H2. The chain must NOT advance through it (classify fails on broken
# ancestry), and the final decision must stay fail-closed full.
build_repo
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
git -C "$R" commit -q --amend -m rewritten
H2="$(git -C "$R" rev-parse HEAD)"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 2 — codex clean — scope=delta — base=\`${H}\` — head=\`${H2}\`"
  echo "- [x] Code review iteration 2 — pr-toolkit clean — scope=delta — base=\`${H}\` — head=\`${H2}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "LAST_CLEAN_HEAD:$H" "$out" "forged post-amend delta does not advance the chain"
assert_contains_str "SCOPE_REQUIRED:full" "$out" "rebase still fail-closed to full"

start_test "mixed-scope pair post-cert is ignored (pair coherence)"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm fix
H2="$(git -C "$R" rev-parse HEAD)"; B2="$(git -C "$R" merge-base main "$H2")"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 2 — codex clean — scope=full — base=\`${B2}\` — head=\`${H2}\`"
  echo "- [x] Code review iteration 2 — pr-toolkit clean — scope=delta — base=\`${H}\` — head=\`${H2}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "LAST_CLEAN_HEAD:$H" "$out" "full+delta mixed pair never advances the chain"

start_test "ADJUDICATED sentinel is head-bound"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
{ echo; echo "- [x] Post-certification tail adjudicated by human — accepted P2 tail — head=\`${H}\` — ts=\`2026-06-05T00:00:00Z\`"
  } >> "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "ADJUDICATED:yes" "$out" "adjudication line at current head → yes"
echo "x" >> "$R/docs/notes.md" 2>/dev/null || { mkdir -p "$R/docs"; echo "x" > "$R/docs/notes.md"; }
git -C "$R" add -A; git -C "$R" commit -qm docs
out="$(run_helper "$R")"
assert_contains_str "ADJUDICATED:no" "$out" "adjudication line at a STALE head → no"

start_test "deep-pass row neither certifies nor advances the chain"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review iteration 1 — codex deep-pass clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "CERTIFIED:no" "$out" "deep-pass alone is not the codex loop review"

start_test "non-main default branch (master) resolves correctly"
# Guard against a hardcoded-main regression: the helper must compute against the
# repo's ACTUAL default branch via default-branch.sh (here: master, no origin).
R="$(scratch_dir revscope)"
git -C "$R" init -q -b master
git -C "$R" config user.email t@t.t; git -C "$R" config user.name t
mkdir -p "$R/src" "$R/docs"
echo ".claude/" > "$R/.gitignore"
echo "base" > "$R/src/app.py"; echo "# doc" > "$R/docs/CHANGELOG.md"
git -C "$R" add -A; git -C "$R" commit -qm base
git -C "$R" checkout -qb feat
echo "feature" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm feat1
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base master "$H")"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  } > "$R/.claude/local/state.md"
echo "note" > "$R/docs/notes.md"; git -C "$R" add -A; git -C "$R" commit -qm docs
out="$(run_helper "$R")"
assert_contains_str "CERTIFIED:yes" "$out" "master-default repo certifies (no hardcoded main)"
assert_contains_str "SCOPE_REQUIRED:mechanical" "$out" "docs-only on master-default → mechanical"

start_test "detached HEAD → fail-closed full"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
git -C "$R" checkout -q --detach
out="$(run_helper "$R")"
assert_contains_str "CERTIFIED:no" "$out" "detached checkout has no branch review history"
assert_contains_str "SCOPE_REQUIRED:full" "$out" "detached → fail-closed full"

start_test "rebase (rewritten history) → fail-closed full"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
git -C "$R" commit -q --amend -m rewritten
out="$(run_helper "$R")"
assert_contains_str "ANCESTOR_OK:no" "$out" "amended head breaks ancestry"
assert_contains_str "SCOPE_REQUIRED:full" "$out" "rebase → fail-closed full"

start_test "legacy scope-less evidence certifies (back-compat)"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 LEGACY "$H"
out="$(run_helper "$R")"
assert_contains_str "CERTIFIED:yes" "$out" "legacy pair counts as full at its head"

start_test "scope=full rows WITHOUT base (or with a wrong base) do not certify"
# Only legacy scope-less rows get the base-less back-compat; a SCOPED full row
# missing base= (or carrying a non-merge-base) is malformed evidence.
build_repo
H="$(git -C "$R" rev-parse HEAD)"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review iteration 1 — codex clean — scope=full — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — head=\`${H}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "CERTIFIED:no" "$out" "base-less scoped full pair does not certify"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${H}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${H}\` — head=\`${H}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "CERTIFIED:no" "$out" "full pair with base≠merge-base does not certify"

start_test "breaker counts post-certification rounds FROM THE LOOP COUNTER (finding-rounds write no clean rows)"
# The incident shape: certification at iter 1, then rounds 2-5 each had FINDINGS —
# no clean rows exist for them. The only machine count is the loop-counter line
# 'Code review loop (N iterations)', which the protocol increments EVERY round.
build_repo
H="$(git -C "$R" rev-parse HEAD)"
mkdir -p "$R/.claude/local"
B="$(git -C "$R" merge-base main "$H")"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [ ] Code review loop (5 iterations) — iterate until no P0/P1/P2"
  echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "POST_CERT_ROUNDS:4" "$out" "loop counter 5 − cert iter 1 = 4 post-cert rounds"
assert_contains_str "BREAKER:tripped" "$out" "4 > limit(3) → tripped"

start_test "post-cert COUNT-LESS 'Code review loop — N/A:' trips the breaker (counter-erasure fail-closed)"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review loop — N/A: degraded"
  echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "BREAKER:tripped" "$out" "count-less N/A after certification fails closed"

start_test "count-PRESERVING N/A keeps the real round count (no false trip at N<=limit)"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review loop (2 iterations) — N/A: degraded"
  echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "BREAKER:ok" "$out" "counted N/A (2-1=1 post-cert round) stays ok"

start_test "legacy pair AFTER a scoped certification at a different head is ignored (no silent rebind)"
build_repo
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm fix
H2="$(git -C "$R" rev-parse HEAD)"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 2 — codex clean — head=\`${H2}\`"
  echo "- [x] Code review iteration 2 — pr-toolkit clean — head=\`${H2}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "LAST_CLEAN_HEAD:$H" "$out" "post-cert scope-less pair does NOT advance the clean chain"

start_test "multi-hop delta chain advances across hops"
# cert at H (iter 1), then two code commits each reviewed as a delta pair that
# chains off the prior clean head. The chain must walk H → H2 → H3, and (nothing
# changed since H3) the live decision is mechanical. The --before 3 view rewinds
# one hop, so the prior clean head as of iter <3 is H2.
build_repo
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "fix1" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm fix1
H2="$(git -C "$R" rev-parse HEAD)"
echo "fix2" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm fix2
H3="$(git -C "$R" rev-parse HEAD)"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 2 — codex clean — scope=delta — base=\`${H}\` — head=\`${H2}\`"
  echo "- [x] Code review iteration 2 — pr-toolkit clean — scope=delta — base=\`${H}\` — head=\`${H2}\`"
  echo "- [x] Code review iteration 3 — codex clean — scope=delta — base=\`${H2}\` — head=\`${H3}\`"
  echo "- [x] Code review iteration 3 — pr-toolkit clean — scope=delta — base=\`${H2}\` — head=\`${H3}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "LAST_CLEAN_HEAD:$H3" "$out" "two-hop delta chain advances H → H2 → H3"
assert_contains_str "SCOPE_REQUIRED:mechanical" "$out" "nothing changed since H3 → mechanical"
# --before 3 excludes iter-3 rows → prior clean head rewinds one hop to H2.
out="$( ( cd "$R" && bash "$HELPER" .claude/local/state.md --before 3 2>/dev/null ) )"
assert_contains_str "LAST_CLEAN_HEAD:$H2" "$out" "--before 3 view rewinds one hop to H2"

start_test "post-rebase FULL pair re-establishes the chain (rebase recovery)"
# cert at H (iter 1) → amend rewrites H → H2 (H no longer an ancestor). A NEW full
# pair at iter 2 anchored at the true merge-base for H2 re-certifies the chain at
# H2; ancestry is intact (LAST_CLEAN_HEAD==HEAD) so the live decision is mechanical.
build_repo
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
git -C "$R" commit -q --amend -m rewritten
H2="$(git -C "$R" rev-parse HEAD)"; B2="$(git -C "$R" merge-base main "$H2")"
mkdir -p "$R/.claude/local"
{ echo "## Workflow"; echo; echo "### Checklist"; echo
  echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
  echo "- [x] Code review iteration 2 — codex clean — scope=full — base=\`${B2}\` — head=\`${H2}\`"
  echo "- [x] Code review iteration 2 — pr-toolkit clean — scope=full — base=\`${B2}\` — head=\`${H2}\`"
  } > "$R/.claude/local/state.md"
out="$(run_helper "$R")"
assert_contains_str "LAST_CLEAN_HEAD:$H2" "$out" "post-rebase full pair re-anchors the chain at H2"
assert_contains_str "ANCESTOR_OK:yes" "$out" "chain head == HEAD → ancestry intact"
assert_contains_str "SCOPE_REQUIRED:mechanical" "$out" "re-certified at HEAD → mechanical"

# ===========================================================================
# PowerShell parity — re-run a subset of fixtures through review-scope.ps1 and
# assert the SAME sentinels the .sh produced. Skipped (as a PASS) when no
# PowerShell runtime is present, so macOS/Linux CI stays green. Runner is
# discovered via the repo's pwsh → powershell → powershell.exe fallback chain
# (same as test-contracts.sh's detect_pwsh), NOT `pwsh` alone.
# ===========================================================================
detect_pwsh() {
    if command -v pwsh >/dev/null 2>&1; then echo "pwsh"; return 0; fi
    if command -v powershell >/dev/null 2>&1; then echo "powershell"; return 0; fi
    if command -v powershell.exe >/dev/null 2>&1; then echo "powershell.exe"; return 0; fi
    return 1
}
HELPER_PS="$REPO_ROOT/hooks/lib/review-scope.ps1"
PS_RUNNER="$(detect_pwsh || true)"
# run_helper_ps <repo>: run the .ps1 standalone entrypoint from a checkout of the
# branch (mirrors run_helper for the .sh). default-branch.ps1 must be a sibling of
# review-scope.ps1 — it already is in the repo's hooks/lib, which is what we run.
run_helper_ps() { ( cd "$1" && "$PS_RUNNER" -NoProfile -File "$HELPER_PS" .claude/local/state.md 2>/dev/null ); }

start_test "PowerShell parity (review-scope.ps1)"
if [ -z "$PS_RUNNER" ]; then
    pass "skipped (no PowerShell runner)"
else
    # Case A: merge docs-only → mechanical (the PR #89 case)
    build_repo
    H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
    git -C "$R" checkout -q main
    echo "main moved" >> "$R/docs/CHANGELOG.md"; git -C "$R" add -A; git -C "$R" commit -qm mainmove
    git -C "$R" checkout -q feat; git -C "$R" merge -q main -m merge 2>/dev/null
    out="$(run_helper_ps "$R")"
    assert_contains_str "PR_OWNED_DELTA:empty" "$out" "ps: pure merge → PR-owned diff unchanged"
    assert_contains_str "UPSTREAM_FILES:nonruntime" "$out" "ps: upstream moved docs only"
    assert_contains_str "SCOPE_REQUIRED:mechanical" "$out" "ps: docs-only rebind → mechanical"

    # Case B: post-cert code commit → delta
    build_repo
    H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
    echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm fix
    out="$(run_helper_ps "$R")"
    assert_contains_str "PR_OWNED_DELTA:code" "$out" "ps: code commit → code delta"
    assert_contains_str "SCOPE_REQUIRED:delta" "$out" "ps: code → delta review"

    # Case C: rebase (rewritten history) → fail-closed full
    build_repo
    H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
    git -C "$R" commit -q --amend -m rewritten
    out="$(run_helper_ps "$R")"
    assert_contains_str "ANCESTOR_OK:no" "$out" "ps: amended head breaks ancestry"
    assert_contains_str "SCOPE_REQUIRED:full" "$out" "ps: rebase → fail-closed full"

    # Case D: docs/example.py is RUNTIME (docs-runtime predicate parity) → delta
    build_repo
    H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
    mkdir -p "$R/docs"; echo "x" >> "$R/docs/example.py"
    git -C "$R" add -A; git -C "$R" commit -qm "touch docs/example.py"
    out="$(run_helper_ps "$R")"
    assert_contains_str "PR_OWNED_DELTA:code" "$out" "ps: docs/example.py → code delta"
    assert_contains_str "SCOPE_REQUIRED:delta" "$out" "ps: docs/example.py → delta review"

    # Case E: code→docs RENAME still requires delta (--no-renames parity)
    build_repo
    H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
    git -C "$R" mv src/app.py docs/app.md
    git -C "$R" commit -qm "rename code to docs"
    out="$(run_helper_ps "$R")"
    assert_contains_str "PR_OWNED_DELTA:code" "$out" "ps: rename surfaces the deleted code path"
    assert_contains_str "SCOPE_REQUIRED:delta" "$out" "ps: code→docs rename → delta"

    # Case F: scope=fullish (unknown value) is dropped → CERTIFIED:no
    build_repo
    H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
    mkdir -p "$R/.claude/local"
    { echo "## Workflow"; echo; echo "### Checklist"; echo
      echo "- [x] Code review iteration 1 — codex clean — scope=fullish — base=\`${B}\` — head=\`${H}\`"
      echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=fullish — base=\`${B}\` — head=\`${H}\`"
      } > "$R/.claude/local/state.md"
    out="$(run_helper_ps "$R")"
    assert_contains_str "CERTIFIED:no" "$out" "ps: scope=fullish rows dropped entirely"

    # Case G: master-default repo (no hardcoded-main regression in the .ps1 helper)
    R="$(scratch_dir revscope)"
    git -C "$R" init -q -b master
    git -C "$R" config user.email t@t.t; git -C "$R" config user.name t
    mkdir -p "$R/src" "$R/docs"
    echo ".claude/" > "$R/.gitignore"
    echo "base" > "$R/src/app.py"; echo "# doc" > "$R/docs/CHANGELOG.md"
    git -C "$R" add -A; git -C "$R" commit -qm base
    git -C "$R" checkout -qb feat
    echo "feature" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm feat1
    H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base master "$H")"
    mkdir -p "$R/.claude/local"
    { echo "## Workflow"; echo; echo "### Checklist"; echo
      echo "- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`"
      echo "- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
      } > "$R/.claude/local/state.md"
    echo "note" > "$R/docs/notes.md"; git -C "$R" add -A; git -C "$R" commit -qm docs
    out="$(run_helper_ps "$R")"
    assert_contains_str "CERTIFIED:yes" "$out" "ps: master-default repo certifies (no hardcoded main)"
    assert_contains_str "SCOPE_REQUIRED:mechanical" "$out" "ps: docs-only on master-default → mechanical"

    # Case H: human adjudication line at the current head → ADJUDICATED:yes
    # (mirrors the bash "ADJUDICATED sentinel is head-bound" fixture). Guards the
    # backtick-escape defect at review-scope.ps1:317 wherever a PS runner exists.
    build_repo
    H="$(git -C "$R" rev-parse HEAD)"; write_evidence "$R" 1 full "$H"
    { echo; echo "- [x] Post-certification tail adjudicated by human — accepted P2 tail — head=\`${H}\` — ts=\`2026-06-05T00:00:00Z\`"
      } >> "$R/.claude/local/state.md"
    out="$(run_helper_ps "$R")"
    assert_contains_str "ADJUDICATED:yes" "$out" "ps: adjudication line at current head → yes"
fi

# ===========================================================================
# Level 2 — GATE behaviors (check-workflow-gates.sh scoped-cert validation)
#
# These run the REAL gate hook against scratch repos with the helpers installed
# under .claude/hooks/lib/ (the path the hook resolves RS from). The gate is
# driven via a PreToolUse stdin payload (pattern: test-hooks.sh) with a
# `git commit` ship verb + a `cwd` pointing at the repo root so the hook cds
# there and resolves $_TOPLEVEL/.claude/hooks/lib/review-scope.sh.
# ===========================================================================
GATE="$REPO_ROOT/hooks/check-workflow-gates.sh"

# install_helpers <repo>: copy the scope helper + its default-branch sibling
# into the scratch repo's .claude/hooks/lib/ (the gate's RS resolution path).
install_helpers() {
    local r="$1"
    mkdir -p "$r/.claude/hooks/lib"
    cp "$REPO_ROOT/hooks/lib/review-scope.sh" "$r/.claude/hooks/lib/"
    cp "$REPO_ROOT/hooks/lib/default-branch.sh" "$r/.claude/hooks/lib/"
}

# run_gate <repo> [command]: run the gate hook with a ship-verb stdin payload.
# Sets GATE_RC (exit code) and GATE_ERR (combined stdout+stderr). The hook reads
# `cwd` from the JSON and cds there; we pass the repo root so RS resolves.
run_gate() {
    local r="$1" cmd="${2:-git commit -m wip}" esc
    # JSON-escape backslashes + quotes in the command (matches test-hooks.sh).
    esc="$(printf '%s' "$cmd" | awk 'BEGIN{ORS=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); print}')"
    printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$r" "$esc" \
        > "$r/.gate-input.json"
    GATE_ERR="$( ( cd "$r" && bash "$GATE" < "$r/.gate-input.json" ) 2>&1 )"
    GATE_RC=$?
}

# write_gate_state <repo> — emit an ACTIVE-workflow state.md (## Workflow with a
# Command row + ### Checklist). $BODY (caller-set) is the checklist body. The
# Code review loop PASS line + per-iter evidence are supplied per-case in $BODY.
write_gate_state() {
    local r="$1"
    mkdir -p "$r/.claude/local"
    { echo "## Workflow"; echo
      echo "| Field | Value |"
      echo "| Command | /new-feature x |"
      echo
      echo "### Checklist"; echo
      printf '%s\n' "$BODY"
    } > "$r/.claude/local/state.md"
}

assert_rc() { # <expected_rc> <msg>
    if [ "$GATE_RC" = "$1" ]; then pass "$2"; else fail "$2 (got rc=$GATE_RC; err: $(printf '%s' "$GATE_ERR" | tr '\n' ' ' | cut -c1-200))"; fi
}

# --- Case 1: mechanical line whose recomputation says delta (code commit) → block
start_test "gate 1: mechanical claim over a CODE delta → block (mechanical claim rejected)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm fix
H2="$(git -C "$R" rev-parse HEAD)"
BODY="- [x] Code review loop (2 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — mechanical re-stamp — scope=mechanical — base=\`${H}\` — head=\`${H2}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 2 "code-delta mechanical → exit 2"
assert_contains_str "mechanical claim rejected" "$GATE_ERR" "stderr names mechanical claim rejected"

# --- Case 2: valid mechanical (docs-only) after certification → allow
start_test "gate 2: valid mechanical re-stamp (docs-only, base=prior clean head) → allow"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "note" >> "$R/docs/CHANGELOG.md"; git -C "$R" add -A; git -C "$R" commit -qm docs
H2="$(git -C "$R" rev-parse HEAD)"
BODY="- [x] Code review loop (2 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — mechanical re-stamp — scope=mechanical — base=\`${H}\` — head=\`${H2}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 0 "docs-only mechanical → exit 0"

# --- Case 3: scope=delta pair whose base is NOT the prior clean head → block
start_test "gate 3: scope=delta with wrong base (not prior clean head) → block (base chain)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm fix
H2="$(git -C "$R" rev-parse HEAD)"
BODY="- [x] Code review loop (2 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — codex clean — scope=delta — base=\`${B}\` — head=\`${H2}\`
- [x] Code review iteration 2 — pr-toolkit clean — scope=delta — base=\`${B}\` — head=\`${H2}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 2 "wrong-base delta → exit 2"
assert_contains_str "base chain" "$GATE_ERR" "stderr names base chain"

# --- Case 3b: scoped pair missing base= entirely → block (missing base)
start_test "gate 3b: scoped pair missing base= → block (missing base)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"
BODY="- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — head=\`${H}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 2 "base-less scoped pair → exit 2"
assert_contains_str "missing base" "$GATE_ERR" "stderr names missing base"

# --- Case 3c: mechanical line with NO prior certification (fabricated at N=1) → block
start_test "gate 3c: mechanical at N=1 with no prior certification → block (requires certification)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
BODY="- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — mechanical re-stamp — scope=mechanical — base=\`${B}\` — head=\`${H}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 2 "fabricated N=1 mechanical → exit 2"
assert_contains_str "requires certification" "$GATE_ERR" "stderr names requires certification"

# --- Case 3d: post-cert REBASE (amend) + forged scope=delta from old clean head → block
start_test "gate 3d: post-amend forged delta (broken ancestry) → block (requires a FULL review)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
git -C "$R" commit -q --amend -m rewritten
H2="$(git -C "$R" rev-parse HEAD)"
BODY="- [x] Code review loop (2 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — codex clean — scope=delta — base=\`${H}\` — head=\`${H2}\`
- [x] Code review iteration 2 — pr-toolkit clean — scope=delta — base=\`${H}\` — head=\`${H2}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 2 "forged post-amend delta → exit 2"
assert_contains_str "requires a FULL review" "$GATE_ERR" "stderr names requires a FULL review"

# --- Case 3e: pair with scope=fullish (unknown scope value) → block
start_test "gate 3e: scope=fullish (delimiter-bound) → block (unknown scope value)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
BODY="- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=fullish — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=fullish — base=\`${B}\` — head=\`${H}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 2 "scope=fullish → exit 2"
assert_contains_str "unknown scope value" "$GATE_ERR" "stderr names unknown scope value"

# --- Case 3f: DELAYED poisoning — cert at H → amend → forged iter-2 delta → iter-3 delta base=H2 → block
start_test "gate 3f: delayed poisoning chained through forged iter-2 → block (base chain)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
git -C "$R" commit -q --amend -m rewritten
H2="$(git -C "$R" rev-parse HEAD)"
echo "more" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm more
H3="$(git -C "$R" rev-parse HEAD)"
BODY="- [x] Code review loop (3 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — codex clean — scope=delta — base=\`${H}\` — head=\`${H2}\`
- [x] Code review iteration 2 — pr-toolkit clean — scope=delta — base=\`${H}\` — head=\`${H2}\`
- [x] Code review iteration 3 — codex clean — scope=delta — base=\`${H2}\` — head=\`${H3}\`
- [x] Code review iteration 3 — pr-toolkit clean — scope=delta — base=\`${H2}\` — head=\`${H3}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 2 "delayed-poison iter-3 delta → exit 2"
assert_contains_str "base chain" "$GATE_ERR" "stderr names base chain (prior clean head still H)"

# --- Case 4: >3 post-cert rounds, no adjudication → block (breaker)
start_test "gate 4: >3 post-cert rounds (loop 5, cert 1), no adjudication → block (breaker)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
BODY="- [ ] Code review loop (5 iterations) — iterate until no P0/P1/P2
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 2 "breaker tripped → exit 2"
assert_contains_str "POST_CERT_REVIEW_ROUND_LIMIT" "$GATE_ERR" "stderr names POST_CERT_REVIEW_ROUND_LIMIT"

# --- Case 4b: breaker tripped + Code review loop — N/A: degraded (no PASS) → STILL block
start_test "gate 4b: breaker tripped + 'Code review loop — N/A:' escape → STILL block"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
BODY="- [x] Code review loop — N/A: degraded
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 2 "N/A does not bypass breaker → exit 2"
assert_contains_str "POST_CERT_REVIEW_ROUND_LIMIT" "$GATE_ERR" "stderr names breaker (N/A counter-erasure fail-closed)"

# --- Case 4e: breaker tripped + DOCS-ONLY staged commit → STILL block (carve-out must not bypass)
start_test "gate 4e: breaker tripped + docs-only staged commit → STILL block (carve-out bypass)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
BODY="- [ ] Code review loop (5 iterations) — iterate until no P0/P1/P2
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`"
write_gate_state "$R"
# Stage ONLY a docs file (CHANGELOG under docs/ is a doc path → carve-out target).
echo "more" >> "$R/docs/CHANGELOG.md"; git -C "$R" add docs/CHANGELOG.md
run_gate "$R"
assert_rc 2 "docs-only commit does not bypass breaker → exit 2"
assert_contains_str "POST_CERT_REVIEW_ROUND_LIMIT" "$GATE_ERR" "stderr names breaker (before carve-out)"

# --- Case 4c: mixed pair — codex full + pr-toolkit delta at same head → block (incoherent)
start_test "gate 4c: mixed reviewer pair (codex full + pr-toolkit delta) → block (incoherent reviewer pair)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "fix" >> "$R/src/app.py"; git -C "$R" add -A; git -C "$R" commit -qm fix
H2="$(git -C "$R" rev-parse HEAD)"; B2="$(git -C "$R" merge-base main "$H2")"
BODY="- [x] Code review loop (2 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — codex clean — scope=full — base=\`${B2}\` — head=\`${H2}\`
- [x] Code review iteration 2 — pr-toolkit clean — scope=delta — base=\`${H}\` — head=\`${H2}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 2 "mixed pair → exit 2"
assert_contains_str "incoherent reviewer pair" "$GATE_ERR" "stderr names incoherent reviewer pair"

# --- Case 4d: full pair whose base is NOT the merge-base for head → block
start_test "gate 4d: scope=full base not the merge-base → block (not the merge-base)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"
# Use HEAD itself as a bogus base (not the merge-base for HEAD).
BODY="- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${H}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${H}\` — head=\`${H}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 2 "full base != merge-base → exit 2"
assert_contains_str "not the merge-base" "$GATE_ERR" "stderr names not the merge-base"

# --- Case 5: breaker tripped + adjudication line at current HEAD → allow
# Realistic post-adjudication shape: the human accepts the open tail, so the loop
# is marked N/A (its evidence check is skipped) and the adjudication line clears
# the breaker. The breaker block fires BEFORE the loop/UNCHECKED gates, so the
# adjudication is what makes the difference between this case and 4b.
start_test "gate 5: breaker tripped + human adjudication at current HEAD → allow"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
BODY="- [x] Code review loop — N/A: post-cert tail adjudicated by human
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Post-certification tail adjudicated by human — accepted P2 tail — head=\`${H}\` — ts=\`2026-06-05T00:00:00Z\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 0 "adjudicated breaker → exit 0"

# --- Case 6: legacy pair (no scope) at current head, NO prior certification → allow
start_test "gate 6: legacy scope-less pair, no prior certification → allow (back-compat)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"
BODY="- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — head=\`${H}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 0 "legacy pair certifies → exit 0"

# --- Case 6b: legacy pair at a NEW head AFTER a scoped certification → block
start_test "gate 6b: legacy pair after a scoped certification → block (post-cert must be scoped)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
echo "note" >> "$R/docs/CHANGELOG.md"; git -C "$R" add -A; git -C "$R" commit -qm docs
H2="$(git -C "$R" rev-parse HEAD)"
BODY="- [x] Code review loop (2 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 2 — codex clean — head=\`${H2}\`
- [x] Code review iteration 2 — pr-toolkit clean — head=\`${H2}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 2 "post-cert legacy pair → exit 2"
assert_contains_str "post-certification evidence must be scoped" "$GATE_ERR" "stderr names post-cert must be scoped"

# --- Case 7: scoped pair + a codex deep-pass row at the same iteration → allow (no CODEX_LINE poison)
start_test "gate 7: scoped pair + codex deep-pass row same iter → allow (deep-pass not poisoning lookup)"
build_repo; install_helpers "$R"
H="$(git -C "$R" rev-parse HEAD)"; B="$(git -C "$R" merge-base main "$H")"
BODY="- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — pr-toolkit clean — scope=full — base=\`${B}\` — head=\`${H}\`
- [x] Code review iteration 1 — codex deep-pass clean — scope=full — base=\`${B}\` — head=\`${H}\`"
write_gate_state "$R"
run_gate "$R"
assert_rc 0 "deep-pass row does not false-block → exit 0"

cleanup_scratch_dirs
report "test-review-scope.sh"
