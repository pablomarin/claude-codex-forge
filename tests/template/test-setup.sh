#!/usr/bin/env bash
# tests/template/test-setup.sh — behavior tests for setup.sh --with-playwright.
#
# Exercises the real setup.sh against scratch project layouts to confirm
# monorepo detection, stamping, idempotency, force-refresh, metachar
# handling, and --upgrade merge behavior.
#
# Run from repo root:  bash tests/template/test-setup.sh

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

# ---------------------------------------------------------------------------
# Helper: set up a minimal scratch project. Layout can be:
#   flat        — package.json at root
#   frontend    — frontend/package.json
#   multi       — frontend/ AND apps/web/ both have package.json
#   custom      — apps/dashboard/package.json
#   metachar    — apps/r&d/package.json (for literal-substitution test)
# ---------------------------------------------------------------------------
make_project() {
    local dir="$1" layout="$2"
    mkdir -p "$dir"
    (cd "$dir" && git init -q)

    case "$layout" in
        flat)
            echo '{"name":"flat-test"}' > "$dir/package.json"
            ;;
        frontend)
            mkdir -p "$dir/frontend"
            echo '{"name":"fe-test"}' > "$dir/frontend/package.json"
            ;;
        multi)
            mkdir -p "$dir/frontend" "$dir/apps/web"
            echo '{"name":"fe"}' > "$dir/frontend/package.json"
            echo '{"name":"web"}' > "$dir/apps/web/package.json"
            ;;
        custom)
            mkdir -p "$dir/apps/dashboard"
            echo '{"name":"dashboard"}' > "$dir/apps/dashboard/package.json"
            ;;
        metachar)
            mkdir -p "$dir/apps/r&d"
            echo '{"name":"rnd"}' > "$dir/apps/r&d/package.json"
            ;;
    esac
}

# ===========================================================================
# Test 1: flat layout — scaffolds at repo root
# ===========================================================================
start_test "Test 1: flat layout → playwright at root"

S1=$(scratch_dir flat)
make_project "$S1" flat
LOG1="$S1/.setup.log"

run_setup "$S1" "$LOG1" -p "FlatTest" -t fullstack --with-playwright
assert_equals "$?" "0" "setup exits 0 on flat layout"

assert_file_exists "$S1/playwright.config.ts" \
    "playwright.config.ts scaffolded at root"
assert_file_exists "$S1/tests/e2e/fixtures/auth.ts" \
    "auth fixture scaffolded at root"
assert_dir_exists "$S1/tests/e2e/specs" \
    "specs dir scaffolded at root"
assert_file_exists "$S1/.claude/playwright-dir" \
    "playwright-dir marker exists"
assert_equals "$(cat "$S1/.claude/playwright-dir")" "." \
    "marker records '.' for flat layout"
assert_file_exists "$S1/docs/ci-templates/e2e.yml" \
    "CI template scaffolded"
assert_contains "$S1/docs/ci-templates/e2e.yml" "working-directory: ." \
    "CI template stamped with '.'"
assert_not_contains "$S1/docs/ci-templates/e2e.yml" "__PLAYWRIGHT_DIR__" \
    "no placeholder leak in CI template"

# ===========================================================================
# Test 2: frontend/ auto-detect
# ===========================================================================
start_test "Test 2: frontend/ subdir → auto-detect"

S2=$(scratch_dir frontend)
make_project "$S2" frontend
LOG2="$S2/.setup.log"

run_setup "$S2" "$LOG2" -p "FeTest" -t fullstack --with-playwright
assert_equals "$?" "0" "setup exits 0 on frontend/ layout"

assert_file_exists "$S2/frontend/playwright.config.ts" \
    "playwright.config.ts scaffolded to frontend/"
assert_file_missing "$S2/playwright.config.ts" \
    "no playwright.config.ts at root"
assert_equals "$(cat "$S2/.claude/playwright-dir")" "frontend" \
    "marker records 'frontend'"
assert_contains "$S2/docs/ci-templates/e2e.yml" "working-directory: frontend" \
    "CI template stamped with 'frontend'"

# ===========================================================================
# Test 3: multiple candidates → fall back to root with warning
# ===========================================================================
start_test "Test 3: multi-candidate → root fallback with warning"

S3=$(scratch_dir multi)
make_project "$S3" multi
LOG3="$S3/.setup.log"

run_setup "$S3" "$LOG3" -p "MultiTest" -t fullstack --with-playwright
assert_equals "$?" "0" "setup exits 0 on multi-candidate layout"

assert_matches "$LOG3" "Multiple frontend candidates" \
    "warning printed for ambiguous layout"
assert_file_exists "$S3/playwright.config.ts" \
    "playwright.config.ts fallback to root"
assert_equals "$(cat "$S3/.claude/playwright-dir")" "." \
    "marker records '.' on fallback"

# ===========================================================================
# Test 4: --playwright-dir override
# ===========================================================================
start_test "Test 4: --playwright-dir apps/dashboard override"

S4=$(scratch_dir custom)
make_project "$S4" custom
LOG4="$S4/.setup.log"

run_setup "$S4" "$LOG4" -p "CustomTest" -t fullstack \
    --with-playwright --playwright-dir apps/dashboard
assert_equals "$?" "0" "setup exits 0 on --playwright-dir override"

assert_file_exists "$S4/apps/dashboard/playwright.config.ts" \
    "playwright.config.ts scaffolded to apps/dashboard/"
assert_equals "$(cat "$S4/.claude/playwright-dir")" "apps/dashboard" \
    "marker records 'apps/dashboard'"
assert_contains "$S4/docs/ci-templates/e2e.yml" "working-directory: apps/dashboard" \
    "CI template stamped with 'apps/dashboard'"

# ===========================================================================
# Test 5: metachar path (apps/r&d) — literal substitution
# This is the bug Codex reproduced: awk's gsub (and sed) interpret '&' as
# the matched text, so path becomes 'apps/r__PLAYWRIGHT_DIR__d'. Confirm
# the bash-param-expansion fix handles this correctly.
# ===========================================================================
start_test "Test 5: --playwright-dir 'apps/r&d' → literal substitution"

S5=$(scratch_dir metachar)
make_project "$S5" metachar
LOG5="$S5/.setup.log"

run_setup "$S5" "$LOG5" -p "MetaTest" -t fullstack \
    --with-playwright --playwright-dir 'apps/r&d'
assert_equals "$?" "0" "setup exits 0 with metachar path"

assert_equals "$(cat "$S5/.claude/playwright-dir")" "apps/r&d" \
    "marker records literal 'apps/r&d'"
assert_contains "$S5/docs/ci-templates/e2e.yml" "working-directory: apps/r&d" \
    "CI template contains literal 'apps/r&d'"
assert_not_contains "$S5/docs/ci-templates/e2e.yml" "__PLAYWRIGHT_DIR__" \
    "& did not expand to matched placeholder"

# ===========================================================================
# Test 6: idempotency — rerun without -f must not clobber CI templates
# (hash specific files, not the whole tree, to avoid flake from .claude/
# playwright-dir rewrites, CLAUDE.md in-place seds, etc.)
# ===========================================================================
start_test "Test 6: idempotent rerun preserves CI template"

S6=$(scratch_dir idem)
make_project "$S6" frontend
LOG6a="$S6/.setup.1.log"
LOG6b="$S6/.setup.2.log"

run_setup "$S6" "$LOG6a" -p "IdemTest" -t fullstack --with-playwright
assert_equals "$?" "0" "initial setup exits 0"

# Capture hashes of the stamped files
HASH_YML_BEFORE=$(hash_file "$S6/docs/ci-templates/e2e.yml")
HASH_MD_BEFORE=$(hash_file "$S6/docs/ci-templates/README.md")
HASH_PWCFG_BEFORE=$(hash_file "$S6/frontend/playwright.config.ts")

# Simulate a user edit to the CI template to ensure it isn't clobbered
echo "# USER EDIT SENTINEL" >> "$S6/docs/ci-templates/e2e.yml"
HASH_YML_EDITED=$(hash_file "$S6/docs/ci-templates/e2e.yml")

# Rerun without -f
run_setup "$S6" "$LOG6b" -p "IdemTest" -t fullstack --with-playwright
assert_equals "$?" "0" "rerun exits 0"

assert_hash_equals "$S6/docs/ci-templates/e2e.yml" "$HASH_YML_EDITED" \
    "CI template preserves user edit on rerun (no -f)"
assert_hash_equals "$S6/docs/ci-templates/README.md" "$HASH_MD_BEFORE" \
    "CI template README unchanged on rerun"
assert_hash_equals "$S6/frontend/playwright.config.ts" "$HASH_PWCFG_BEFORE" \
    "playwright.config.ts unchanged on rerun"

# ===========================================================================
# Test 7: -f force refresh overwrites user edits
# ===========================================================================
start_test "Test 7: -f forces CI template refresh"

LOG6c="$S6/.setup.3.log"
run_setup "$S6" "$LOG6c" -p "IdemTest" -t fullstack --with-playwright -f
assert_equals "$?" "0" "setup with -f exits 0"

# After -f, user sentinel should be gone (template refreshed from source)
assert_not_contains "$S6/docs/ci-templates/e2e.yml" "USER EDIT SENTINEL" \
    "-f refreshes CI template (user edit overwritten)"
assert_hash_equals "$S6/docs/ci-templates/e2e.yml" "$HASH_YML_BEFORE" \
    "CI template hash matches original after -f"

# ===========================================================================
# Test 8: --upgrade smoke — the actual downstream pain path
# Also exercises the "user content is never clobbered" invariant: CLAUDE.md,
# CONTINUITY.md, AND docs/CHANGELOG.md must survive -f and --upgrade intact.
# ===========================================================================
start_test "Test 8: --upgrade smoke on existing install"

S8=$(scratch_dir upgrade)
make_project "$S8" frontend
LOG8a="$S8/.setup.install.log"
LOG8b="$S8/.setup.upgrade.log"
LOG8c="$S8/.setup.force.log"

# Initial install
run_setup "$S8" "$LOG8a" -p "UpgradeTest" -t fullstack --with-playwright
assert_equals "$?" "0" "initial install exits 0"
assert_file_exists "$S8/.claude/commands/new-feature.md" \
    "initial install populated .claude/commands"
assert_file_exists "$S8/docs/CHANGELOG.md" \
    "initial install created docs/CHANGELOG.md"

# First-install soft-tip regression guard: LOG8a is the initial-install
# log from above. CLAUDE.md/CONTINUITY.md did not exist before that run, so
# no soft tip (or legacy drift notice) should have fired.
assert_not_contains "$LOG8a" "Template may have drifted" \
    "first install does NOT show legacy drift notice (UC3 regression guard)"
assert_not_contains "$LOG8a" "ask Claude to reconcile" \
    "first install does NOT show soft reconcile tip (5.17 regression guard)"

# Simulate the user actually using CHANGELOG and CLAUDE.md — they add their
# own release entries and project notes. This is the content that MUST NOT
# be wiped on later upgrade/force.
CHANGELOG_SENTINEL="## 1.2.3 — USER RELEASE ENTRY SENTINEL"
echo "$CHANGELOG_SENTINEL" >> "$S8/docs/CHANGELOG.md"
CLAUDE_SENTINEL="## USER-OWNED PROJECT NOTE SENTINEL"
echo "$CLAUDE_SENTINEL" >> "$S8/CLAUDE.md"
CONTINUITY_SENTINEL="## USER-OWNED TASK STATE SENTINEL"
echo "$CONTINUITY_SENTINEL" >> "$S8/CONTINUITY.md"
HASH_CHANGELOG=$(hash_file "$S8/docs/CHANGELOG.md")
HASH_CLAUDE=$(hash_file "$S8/CLAUDE.md")
HASH_CONTINUITY=$(hash_file "$S8/CONTINUITY.md")

# Run --upgrade — the downstream pain path
run_setup "$S8" "$LOG8b" --upgrade
assert_equals "$?" "0" "--upgrade exits 0"
assert_file_exists "$S8/.claude/commands/new-feature.md" \
    ".claude/commands still present after --upgrade"
assert_file_exists "$S8/CLAUDE.md" \
    "CLAUDE.md preserved by --upgrade"
assert_contains "$S8/CLAUDE.md" "USER-OWNED PROJECT NOTE SENTINEL" \
    "--upgrade preserves user content in CLAUDE.md"
assert_contains "$S8/CONTINUITY.md" "USER-OWNED TASK STATE SENTINEL" \
    "--upgrade preserves user content in CONTINUITY.md"
assert_contains "$S8/docs/CHANGELOG.md" "USER RELEASE ENTRY SENTINEL" \
    "--upgrade preserves user entries in docs/CHANGELOG.md"
assert_hash_equals "$S8/docs/CHANGELOG.md" "$HASH_CHANGELOG" \
    "--upgrade does not touch CHANGELOG at all"
assert_hash_equals "$S8/CLAUDE.md" "$HASH_CLAUDE" \
    "--upgrade does not touch CLAUDE.md at all"
assert_hash_equals "$S8/CONTINUITY.md" "$HASH_CONTINUITY" \
    "--upgrade does not touch CONTINUITY.md at all"

# UC1 soft tip: --upgrade with CLAUDE.md preserved → end-of-summary soft tip
# with full Variant B prompt, both-preserved final summary, migration prompt
# for legacy CONTINUITY.md.
# Post PR #2: CONTINUITY.template.md no longer exists. Legacy CONTINUITY.md gets
# a migration prompt, and the both-preserved final summary points at --migrate.
# 5.17: per-file inline drift hint dropped; soft tip fires once at end of summary
# when CLAUDE.md was preserved.
assert_not_contains "$LOG8b" "Template may have drifted" \
    "UC1: --upgrade does NOT contain legacy 'Template may have drifted' hint (5.17)"
assert_contains "$LOG8b" "ask Claude to reconcile your CLAUDE.md" \
    "UC1: --upgrade shows soft reconcile tip (5.17)"
assert_contains "$LOG8b" "Reconcile my CLAUDE.md against" \
    "UC1: --upgrade soft tip includes full Variant B prompt"
assert_contains "$LOG8b" "@CONTINUITY.md import lines" \
    "UC1: --upgrade soft tip includes @CONTINUITY.md cleanup clause (5.18 wording)"
# 5.18: tightened prompt asks Claude to scan the whole file for ALL leftover
# CONTINUITY references (tree diagrams, prose pointers, labels) -- not just
# the @-import line. Lock in the new tokens so the broader scope cannot
# silently regress. Field bug origin: msai-v2 retained line-102 tree-diagram
# and line-212 prose pointer after running the v5.17 prompt.
assert_contains "$LOG8b" "scan the ENTIRE file" \
    "UC1: --upgrade soft tip instructs full-file scan (5.18)"
assert_contains "$LOG8b" "File-tree diagrams" \
    "UC1: --upgrade soft tip names tree-diagram references (5.18)"
assert_contains "$LOG8b" "stale infrastructure references" \
    "UC1: --upgrade soft tip frames CONTINUITY refs as not-user-content (5.18)"
assert_contains "$LOG8b" "Full guide:" \
    "UC1: --upgrade soft tip includes 'Full guide:' reference"
assert_contains "$LOG8b" "/docs/guides/upgrading.md" \
    "UC1: --upgrade soft tip 'Full guide:' uses absolute path to Forge clone"
assert_contains "$LOG8b" "CLAUDE.template.md" \
    "UC1: --upgrade references CLAUDE.template.md"
assert_not_contains "$LOG8b" "CONTINUITY.template.md" \
    "UC1: --upgrade does NOT reference CONTINUITY.template.md (deleted in PR #2)"
assert_contains "$LOG8b" "./setup.sh --migrate" \
    "UC1: --upgrade prompts --migrate for legacy CONTINUITY.md"
assert_contains "$LOG8b" "Your CLAUDE.md and CONTINUITY.md were preserved (run --migrate to move content to the new structure)" \
    "UC1: --upgrade final summary = both-preserved variant (--migrate suffix)"
assert_not_contains "$LOG8b" "were not modified" \
    "UC1: --upgrade does NOT contain legacy 'were not modified' string"

# Also verify -f (force) preserves user content. -f is the big hammer that
# SHOULD refresh .claude/* and CI templates, but MUST still leave CLAUDE.md,
# CONTINUITY.md, and docs/CHANGELOG.md alone — they are user content.
run_setup "$S8" "$LOG8c" -p "UpgradeTest" -t fullstack --with-playwright -f
assert_equals "$?" "0" "-f exits 0"
assert_hash_equals "$S8/docs/CHANGELOG.md" "$HASH_CHANGELOG" \
    "-f does not touch CHANGELOG"
assert_hash_equals "$S8/CLAUDE.md" "$HASH_CLAUDE" \
    "-f does not touch CLAUDE.md"
assert_hash_equals "$S8/CONTINUITY.md" "$HASH_CONTINUITY" \
    "-f does not touch CONTINUITY.md"

# UC2 soft tip: -f path runs the install branch (not the --upgrade branch),
# which does NOT emit the soft tip. Confirm legacy drift hint is absent and
# that the -f path is silent on the reconcile tip (which is upgrade-mode-only).
assert_not_contains "$LOG8c" "Template may have drifted" \
    "UC2: -f does NOT contain legacy 'Template may have drifted' hint (5.17)"

# ===========================================================================
# Test 8b: --upgrade on an ALREADY-MIGRATED install — no unsatisfiable nag
# Regression (v5.48): a repo that ran `--migrate` keeps CONTINUITY.md (the
# migration preserves it byte-for-byte) and gains a `<!-- forge:migrated DATE -->`
# sentinel in CLAUDE.md + .claude/local/state.md. Before the fix, every later
# `--upgrade` re-nagged "run --migrate" — an unsatisfiable instruction, since
# re-running --migrate is a no-op once the sentinel is present. The banner must
# instead report the file is already migrated and point at removal (gated on
# confirming the migrated content landed).
# ===========================================================================
start_test "Test 8b: --upgrade on already-migrated install (no migrate-nag)"

S8M=$(scratch_dir upgrade-migrated)
make_project "$S8M" frontend
LOG8m_install="$S8M/.setup.install.log"
LOG8m="$S8M/.setup.upgrade.log"

run_setup "$S8M" "$LOG8m_install" -p "MigratedTest" -t fullstack
assert_equals "$?" "0" "Test 8b: migrated-case initial install exits 0"

# Simulate the exact post-migration state scripts/migrate-continuity.sh leaves:
# the sentinel stamped into CLAUDE.md + state.md, CONTINUITY.md preserved on disk.
MIGRATED_SENTINEL="<!-- forge:migrated 2026-04-28 -->"
printf '\n%s\n' "$MIGRATED_SENTINEL" >> "$S8M/CLAUDE.md"
printf '\n%s\n' "$MIGRATED_SENTINEL" >> "$S8M/.claude/local/state.md"
printf '# Legacy notes\n\nOld task state.\n' > "$S8M/CONTINUITY.md"

run_setup "$S8M" "$LOG8m" --upgrade
assert_equals "$?" "0" "Test 8b: --upgrade on migrated install exits 0"

# The core fix: no "run --migrate" nag once the sentinel is present.
assert_not_contains "$LOG8m" "./setup.sh --migrate" \
    "Test 8b: migrated install does NOT nag './setup.sh --migrate'"
assert_not_contains "$LOG8m" "run --migrate to move content" \
    "Test 8b: migrated install banner drops the 'run --migrate' suffix"
# Instead it points the user at removing the now-redundant file, citing the date.
assert_contains "$LOG8m" "already migrated" \
    "Test 8b: migrated install reports CONTINUITY.md already migrated"
assert_contains "$LOG8m" "content landed" \
    "Test 8b: migrated install gates removal on confirming content landed"
assert_contains "$LOG8m" "2026-04-28" \
    "Test 8b: migrated install cites the migration date from the sentinel"

# ===========================================================================
# Test 8c: state.md-only sentinel is NOT enough to claim the file is migrated
# Codex P2 (v5.48): the durable migration target is CLAUDE.md (git-committed).
# state.md is gitignored and recreated blank on a fresh clone, so a marker found
# only there does NOT prove the durable bucket was written. Such a partial state
# must fall through to the (idempotent) --migrate prompt, never the removal
# hint — pointing at removal could discard still-unmoved content.
# ===========================================================================
start_test "Test 8c: state.md-only sentinel does NOT trigger removal hint (Codex P2)"

S8P=$(scratch_dir upgrade-partial)
make_project "$S8P" frontend
LOG8p_install="$S8P/.setup.install.log"
LOG8p="$S8P/.setup.upgrade.log"

run_setup "$S8P" "$LOG8p_install" -p "PartialTest" -t fullstack
assert_equals "$?" "0" "Test 8c: partial-case initial install exits 0"

# Marker ONLY in state.md; CLAUDE.md (durable bucket) has NO sentinel.
printf '\n<!-- forge:migrated 2026-04-28 -->\n' >> "$S8P/.claude/local/state.md"
printf '# Legacy notes\n\nUnmoved content.\n' > "$S8P/CONTINUITY.md"

run_setup "$S8P" "$LOG8p" --upgrade
assert_equals "$?" "0" "Test 8c: --upgrade on partial install exits 0"

# Without a CLAUDE.md sentinel we must NOT claim the file was migrated/removable...
assert_not_contains "$LOG8p" "content landed" \
    "Test 8c: state.md-only marker does NOT point at removing CONTINUITY.md"
assert_not_contains "$LOG8p" "already migrated" \
    "Test 8c: state.md-only marker does NOT report 'already migrated'"
# ...and we DO fall through to the (idempotent, harmless) --migrate prompt.
assert_contains "$LOG8p" "./setup.sh --migrate" \
    "Test 8c: state.md-only marker still prompts the --migrate path"

# ===========================================================================
# Test 8d: prefix-only / date-less sentinel — migrated, but no garbage in banner
# The migrate helper's idempotency probe keys on the bare prefix `<!-- forge:migrated`
# (SENTINEL_PREFIX), so a hand-edited space-less/date-less marker like
# `<!-- forge:migrated-->` is "already migrated" to the helper — re-running --migrate
# is a no-op. The upgrade detector must agree (Codex P3, iter 3): treat it as migrated
# (suppress the --migrate nag) WITHOUT splicing a garbage date — no "(-->)" / "()"
# artifact next to the destructive removal hint (Codex P2, iter 2).
# ===========================================================================
start_test "Test 8d: prefix-only date-less sentinel migrates without garbage in banner"

S8D=$(scratch_dir upgrade-nodate)
make_project "$S8D" frontend
LOG8d_install="$S8D/.setup.install.log"
LOG8d="$S8D/.setup.upgrade.log"

run_setup "$S8D" "$LOG8d_install" -p "NoDateTest" -t fullstack
assert_equals "$?" "0" "Test 8d: nodate-case initial install exits 0"

# Prefix-only sentinel (no space, no date) in CLAUDE.md — the strict form the
# migrate helper treats as migrated but a date-requiring detector would miss.
printf '\n<!-- forge:migrated-->\n' >> "$S8D/CLAUDE.md"
printf '# Legacy notes\n' > "$S8D/CONTINUITY.md"

run_setup "$S8D" "$LOG8d" --upgrade
assert_equals "$?" "0" "Test 8d: --upgrade on date-less sentinel exits 0"

# Still recognized as migrated → no nag, points at removal...
assert_not_contains "$LOG8d" "./setup.sh --migrate" \
    "Test 8d: date-less sentinel does NOT nag './setup.sh --migrate'"
assert_contains "$LOG8d" "already migrated" \
    "Test 8d: date-less sentinel still reports 'already migrated'"
assert_contains "$LOG8d" "content landed" \
    "Test 8d: date-less sentinel still points at removal (gated on content landed)"
# ...but with NO spliced-in garbage date.
assert_not_contains "$LOG8d" "(-->)" \
    "Test 8d: banner has no '(-->)' artifact from the date-less sentinel"
assert_not_contains "$LOG8d" "migrated ()" \
    "Test 8d: banner has no empty '()' artifact from the date-less sentinel"

# ===========================================================================
# Test 9: runtime preflight — warns but never blocks
# ===========================================================================
start_test "Test 9: runtime preflight is warn-only"

# Case A: .python-version pinned to an impossible version → warning + exit 0
S9a=$(scratch_dir preflight-py)
make_project "$S9a" flat
echo "99.99.99" > "$S9a/.python-version"
LOG9a="$S9a/.setup.log"

run_setup "$S9a" "$LOG9a" -p "PreflightA" -t python
assert_equals "$?" "0" "impossible .python-version → setup still exits 0"
assert_matches "$LOG9a" ".python-version requires.*99\.99\.99" \
    "preflight warns about missing Python version"
assert_contains "$LOG9a" "uv python install 99.99.99" \
    "warning includes install guidance"
assert_contains "$LOG9a" "multi-project-isolation.md" \
    "warning points to the canonical doc"
assert_contains "$LOG9a" "Prerequisites OK" \
    "setup proceeds past preflight to Prerequisites OK"

# Case B: .nvmrc pinned to an impossible version → warning + exit 0
S9b=$(scratch_dir preflight-node)
make_project "$S9b" flat
echo "999" > "$S9b/.nvmrc"
LOG9b="$S9b/.setup.log"

run_setup "$S9b" "$LOG9b" -p "PreflightB" -t typescript
assert_equals "$?" "0" "impossible .nvmrc → setup still exits 0"
assert_matches "$LOG9b" ".nvmrc requires Node.*999" \
    "preflight warns about missing Node version"
assert_contains "$LOG9b" "fnm install 999" \
    "warning includes fnm install guidance"

# Case C: no version pins at all → preflight silent (no warnings emitted)
S9c=$(scratch_dir preflight-none)
make_project "$S9c" flat
LOG9c="$S9c/.setup.log"

run_setup "$S9c" "$LOG9c" -p "PreflightC" -t fullstack
assert_equals "$?" "0" "no pins → setup exits 0"
assert_not_contains "$LOG9c" ".python-version requires" \
    "no Python warning when no .python-version"
assert_not_contains "$LOG9c" ".nvmrc requires" \
    "no Node warning when no .nvmrc"
assert_not_contains "$LOG9c" "multi-project-isolation.md" \
    "no canonical-doc reference when no warnings fired"

# Case D: .python-version matching the system interpreter → green check, no warning
# Use the actual running python3 version so this is deterministic across CI machines.
S9d=$(scratch_dir preflight-match)
make_project "$S9d" flat
if command -v python3 >/dev/null 2>&1; then
    PY_CURRENT=$(python3 --version 2>&1 | awk '{print $2}')
    if [[ -n "$PY_CURRENT" ]]; then
        echo "$PY_CURRENT" > "$S9d/.python-version"
        LOG9d="$S9d/.setup.log"
        run_setup "$S9d" "$LOG9d" -p "PreflightD" -t python
        assert_equals "$?" "0" "matching .python-version → setup exits 0"
        assert_contains "$LOG9d" "Python $PY_CURRENT available" \
            "preflight reports Python version as available"
        assert_not_contains "$LOG9d" ".python-version requires" \
            "no warning when version is available"
    fi
else
    printf "  %s·%s skipped (python3 not installed): Case D\n" "$C_DIM" "$C_RESET"
fi

# Case E: .nvmrc with an EXACT version that can't possibly exist → warning
# Regression guard for Codex's P2 finding: an exact version pin like
# "20.11.0" must NOT be satisfied by ANY 20.x — check exact-match semantics.
# Use "20.99999.0" which is guaranteed absent from any reasonable system.
S9e=$(scratch_dir preflight-nvmrc-exact)
make_project "$S9e" flat
echo "20.99999.0" > "$S9e/.nvmrc"
LOG9e="$S9e/.setup.log"

run_setup "$S9e" "$LOG9e" -p "PreflightE" -t typescript
assert_equals "$?" "0" "exact .nvmrc mismatch → setup exits 0"
assert_matches "$LOG9e" ".nvmrc requires Node.*20\.99999\.0" \
    "preflight warns when exact .nvmrc version is missing (even if major matches system)"

# Case F: malformed package.json → preflight must NOT abort setup
# Regression guard for Codex's P2 finding about set -e + jq.
S9f=$(scratch_dir preflight-bad-json)
make_project "$S9f" flat
echo '{"name": "bad", this is not valid json' > "$S9f/package.json"
LOG9f="$S9f/.setup.log"

run_setup "$S9f" "$LOG9f" -p "PreflightF" -t typescript
assert_equals "$?" "0" "malformed package.json → setup STILL exits 0 (no set -e abort)"
assert_contains "$LOG9f" "Prerequisites OK" \
    "setup reached Prerequisites OK despite malformed package.json"

# ===========================================================================
# Test 10: Asymmetric preservation matrix — drift notice & final summary
# variants per {CLAUDE.md, CONTINUITY.md} × {preserved, recreated}.
# Codex P2 fix: test-8 only exercised the both-preserved path. Without this
# test the four final-summary variants can silently regress — especially on
# PowerShell since bash UCs don't execute .ps1.
# ===========================================================================
start_test "Test 10: asymmetric preservation drift notice"

# Scenario A — legacy install with CONTINUITY.md, no CLAUDE.md.
# Post PR #2 the fresh install does not create CONTINUITY.md, so we seed it
# manually to simulate a legacy install that hasn't run --migrate yet (the
# motivating real-world scenario for this variant).
# Expect: migration prompt for CONTINUITY, only-CONTINUITY final summary variant.
S10a=$(scratch_dir upgrade-asym-a)
make_project "$S10a" frontend
run_setup "$S10a" "$S10a/.install.log" -p "AsymA" -t fullstack
assert_equals "$?" "0" "Scenario A: initial install exits 0"
rm -f "$S10a/CLAUDE.md"  # simulate user clearing CLAUDE.md
echo "# legacy CONTINUITY.md" > "$S10a/CONTINUITY.md"  # seed legacy file

run_setup "$S10a" "$S10a/.upgrade.log" --upgrade
assert_equals "$?" "0" "Scenario A: --upgrade exits 0"
assert_file_exists "$S10a/CLAUDE.md" \
    "Scenario A: CLAUDE.md recreated from template"
assert_file_exists "$S10a/CONTINUITY.md" \
    "Scenario A: CONTINUITY.md still present"

# Migration prompt must fire because legacy CONTINUITY.md is present.
assert_contains "$S10a/.upgrade.log" "Legacy CONTINUITY.md detected" \
    "Scenario A: migration prompt fires (for legacy CONTINUITY)"
assert_contains "$S10a/.upgrade.log" "./setup.sh --migrate" \
    "Scenario A: migration prompt suggests ./setup.sh --migrate"
assert_not_contains "$S10a/.upgrade.log" "CONTINUITY.template.md" \
    "Scenario A: log does NOT reference CONTINUITY.template.md (deleted in PR #2)"
# Final summary: only-CONTINUITY variant (with --migrate suffix).
assert_contains "$S10a/.upgrade.log" "Your CONTINUITY.md was preserved (run --migrate to move content to the new structure)" \
    "Scenario A: final summary = only-CONTINUITY variant (--migrate suffix)"
assert_not_contains "$S10a/.upgrade.log" "Your CLAUDE.md and CONTINUITY.md were preserved" \
    "Scenario A: final summary is NOT the both-preserved variant"
assert_not_contains "$S10a/.upgrade.log" "were not modified" \
    "Scenario A: final summary does NOT contain legacy string"
# 5.17: soft tip is gated on had_claude_md=true. Scenario A removed CLAUDE.md
# before --upgrade, so the soft tip must NOT fire.
assert_not_contains "$S10a/.upgrade.log" "ask Claude to reconcile" \
    "Scenario A: no soft reconcile tip when CLAUDE.md was not preserved (5.17)"

# Scenario B — user deleted CONTINUITY.md, kept CLAUDE.md.
# Mirror of Scenario A.
S10b=$(scratch_dir upgrade-asym-b)
make_project "$S10b" frontend
run_setup "$S10b" "$S10b/.install.log" -p "AsymB" -t fullstack
assert_equals "$?" "0" "Scenario B: initial install exits 0"
rm -f "$S10b/CONTINUITY.md"

run_setup "$S10b" "$S10b/.upgrade.log" --upgrade
assert_equals "$?" "0" "Scenario B: --upgrade exits 0"
assert_contains "$S10b/.upgrade.log" "CLAUDE.template.md" \
    "Scenario B: soft tip references CLAUDE.template.md"
assert_contains "$S10b/.upgrade.log" "ask Claude to reconcile your CLAUDE.md" \
    "Scenario B: soft tip fires when CLAUDE.md is preserved (5.17)"
assert_not_contains "$S10b/.upgrade.log" "Template may have drifted" \
    "Scenario B: legacy drift hint is gone (5.17)"
assert_contains "$S10b/.upgrade.log" "Your CLAUDE.md was preserved (user content)" \
    "Scenario B: final summary = only-CLAUDE variant"
assert_not_contains "$S10b/.upgrade.log" "Your CLAUDE.md and CONTINUITY.md were preserved" \
    "Scenario B: final summary is NOT the both-preserved variant"
assert_not_contains "$S10b/.upgrade.log" "were not modified" \
    "Scenario B: final summary does NOT contain legacy string"

# Scenario C — user deleted BOTH files. Drift block must be suppressed
# entirely, and the final summary collapses to the bare "Upgrade done!" form.
S10c=$(scratch_dir upgrade-asym-c)
make_project "$S10c" frontend
run_setup "$S10c" "$S10c/.install.log" -p "AsymC" -t fullstack
assert_equals "$?" "0" "Scenario C: initial install exits 0"
rm -f "$S10c/CLAUDE.md" "$S10c/CONTINUITY.md"

run_setup "$S10c" "$S10c/.upgrade.log" --upgrade
assert_equals "$?" "0" "Scenario C: --upgrade exits 0"
assert_not_contains "$S10c/.upgrade.log" "Template may have drifted" \
    "Scenario C: no legacy drift block when nothing was preserved"
assert_not_contains "$S10c/.upgrade.log" "ask Claude to reconcile" \
    "Scenario C: no soft reconcile tip when CLAUDE.md was not preserved (5.17)"
assert_not_contains "$S10c/.upgrade.log" "was preserved" \
    "Scenario C: final summary does NOT claim 'was preserved'"
assert_not_contains "$S10c/.upgrade.log" "were preserved" \
    "Scenario C: final summary does NOT claim 'were preserved'"
assert_not_contains "$S10c/.upgrade.log" "were not modified" \
    "Scenario C: final summary does NOT contain legacy string"
# Bare variant should still be present (so users know the run succeeded).
assert_contains "$S10c/.upgrade.log" "Upgrade done!" \
    "Scenario C: bare 'Upgrade done!' variant present"

# ===========================================================================
# Test 11: hooks/lib helper installed + executable + hash-identical to source
# P1 gap from drift-hygiene PR #1 review: setup.sh copies the lib helper, but
# no test asserted its presence, mode, or integrity in the scratch install.
# ===========================================================================
start_test "Test 11: hooks/lib/default-branch.sh installed by setup.sh"

S11=$(scratch_dir hooks-lib)
make_project "$S11" flat
LOG11="$S11/.setup.log"

run_setup "$S11" "$LOG11" -p "HooksLibTest" -t fullstack
assert_equals "$?" "0" "setup exits 0"

# File must exist in the installed tree
assert_file_exists "$S11/.claude/hooks/lib/default-branch.sh" \
    ".claude/hooks/lib/default-branch.sh installed"

# Must be executable (chmod +x applied by setup.sh)
if [[ -x "$S11/.claude/hooks/lib/default-branch.sh" ]]; then
    pass ".claude/hooks/lib/default-branch.sh is executable"
else
    fail ".claude/hooks/lib/default-branch.sh is NOT executable"
fi

# Content must be hash-identical to the source in the repo
SRC_HASH=$(hash_file "$REPO_ROOT/hooks/lib/default-branch.sh")
assert_hash_equals "$S11/.claude/hooks/lib/default-branch.sh" "$SRC_HASH" \
    "installed default-branch.sh matches source (hash-identical)"

# review-scope.sh — same three assertions (installed, executable, hash-identical)
assert_file_exists "$S11/.claude/hooks/lib/review-scope.sh" \
    ".claude/hooks/lib/review-scope.sh installed"

if [[ -x "$S11/.claude/hooks/lib/review-scope.sh" ]]; then
    pass ".claude/hooks/lib/review-scope.sh is executable"
else
    fail ".claude/hooks/lib/review-scope.sh is NOT executable"
fi

SRC_HASH_RS=$(hash_file "$REPO_ROOT/hooks/lib/review-scope.sh")
assert_hash_equals "$S11/.claude/hooks/lib/review-scope.sh" "$SRC_HASH_RS" \
    "installed review-scope.sh matches source (hash-identical)"

# review-scope.ps1 — PowerShell mirror is shipped by setup.sh too (dot-sourced by
# the .ps1 gate hooks on Windows). Assert presence + hash-identical (not +x: .ps1
# files are not chmod'd by setup.sh).
assert_file_exists "$S11/.claude/hooks/lib/review-scope.ps1" \
    ".claude/hooks/lib/review-scope.ps1 installed"

SRC_HASH_RSPS=$(hash_file "$REPO_ROOT/hooks/lib/review-scope.ps1")
assert_hash_equals "$S11/.claude/hooks/lib/review-scope.ps1" "$SRC_HASH_RSPS" \
    "installed review-scope.ps1 matches source (hash-identical)"

# Note: setup.ps1 (Windows installer) installs default-branch.ps1; setup.sh
# (Unix installer) installs only default-branch.sh. The cross-installer parity
# is covered by test-contracts.sh (Contract: hooks/lib parity setup.sh ↔ setup.ps1).

# ===========================================================================
# Test 12: state.md, ADR, gitignore install assertions (PR #2 — continuity-split)
# ===========================================================================
start_test "Test 12: continuity-split install assertions"

# Verify state.template.md installs to .claude/local/state.md (fresh install).
test_state_md_installs() {
    local scratch; scratch=$(scratch_dir state-md-install)
    ( cd "$scratch" && mkdir -p .fakehome && HOME="$scratch/.fakehome" bash "$REPO_ROOT/setup.sh" -p TestProj -t fullstack >/dev/null 2>&1 )
    if [ -f "$scratch/.claude/local/state.md" ]; then
        pass ".claude/local/state.md installed on fresh setup"
    else
        fail ".claude/local/state.md NOT installed on fresh setup"
    fi
    # The harness-side state.template.md (from T12 Step 3 amendment) is also installed.
    if [ -f "$scratch/.claude/state.template.md" ]; then
        pass ".claude/state.template.md installed (T12 Step 3 amendment)"
    else
        fail ".claude/state.template.md NOT installed (T12 Step 3 amendment expected)"
    fi
    # state.template.md (root) ships in the harness source tree.
    if [ -f "$REPO_ROOT/state.template.md" ]; then
        pass "state.template.md ships in repo root (source of truth)"
    else
        fail "state.template.md MISSING from repo root"
    fi
}

# Verify .gitignore is mutated to include .claude/local/.
test_gitignore_has_claude_local() {
    local scratch; scratch=$(scratch_dir gitignore-claude-local)
    ( cd "$scratch" && mkdir -p .fakehome && HOME="$scratch/.fakehome" bash "$REPO_ROOT/setup.sh" -p TestProj -t fullstack >/dev/null 2>&1 )
    if [ -f "$scratch/.gitignore" ] && grep -qxF ".claude/local/" "$scratch/.gitignore"; then
        pass ".claude/local/ present in .gitignore"
    else
        fail ".claude/local/ NOT in .gitignore (or .gitignore missing)"
    fi
}

# Verify gitignore mutation is idempotent (second setup -f does not duplicate).
test_gitignore_idempotent() {
    local scratch; scratch=$(scratch_dir gitignore-idempotent)
    ( cd "$scratch" && mkdir -p .fakehome && HOME="$scratch/.fakehome" bash "$REPO_ROOT/setup.sh" -p TestProj -t fullstack >/dev/null 2>&1 )
    ( cd "$scratch" && mkdir -p .fakehome && HOME="$scratch/.fakehome" bash "$REPO_ROOT/setup.sh" -f -p TestProj -t fullstack >/dev/null 2>&1 )
    local count
    count=$(grep -cxF ".claude/local/" "$scratch/.gitignore" 2>/dev/null || echo 0)
    assert_equals "$count" "1" ".claude/local/ entry is idempotent (one occurrence after -f rerun)"
}

# Verify ADRs install.
test_adrs_install() {
    local scratch; scratch=$(scratch_dir adrs-install)
    ( cd "$scratch" && mkdir -p .fakehome && HOME="$scratch/.fakehome" bash "$REPO_ROOT/setup.sh" -p TestProj -t fullstack >/dev/null 2>&1 )
    local all_ok=true
    for adr in template README 0001-volatile-state-not-auto-loaded 0002-bash-and-powershell-dual-platform 0003-template-distributed-no-build-step 0004-diataxis-docs-structure 0005-hard-platform-parity-rule; do
        if [ ! -f "$scratch/docs/adr/${adr}.md" ]; then
            fail "docs/adr/${adr}.md not installed"
            all_ok=false
        fi
    done
    $all_ok && pass "all ADR files installed (template, README, 0001-0005)"
}

# Verify CONTINUITY.template.md is NOT installed (legacy file should not be generated
# in a fresh install — though the source CONTINUITY.template.md may still ship in the
# harness during the hard-cut transition; this check covers the *target* project).
test_no_continuity_installed() {
    local scratch; scratch=$(scratch_dir no-continuity-installed)
    ( cd "$scratch" && mkdir -p .fakehome && HOME="$scratch/.fakehome" bash "$REPO_ROOT/setup.sh" -p TestProj -t fullstack >/dev/null 2>&1 )
    # Allow CONTINUITY.md to exist if setup still seeds it during transition; the
    # critical check is that it is NOT auto-imported by CLAUDE.md after PR #2.
    # Conservative assertion: no CONTINUITY.md in the freshly-set-up project after PR #2.
    if [ ! -f "$scratch/CONTINUITY.md" ]; then
        pass "CONTINUITY.md not installed in fresh project (post PR #2)"
    else
        fail "CONTINUITY.md unexpectedly installed in fresh project (post PR #2 expects none)"
    fi
}

# Verify -f preserves an existing CONTINUITY.md byte-for-byte.
test_f_preserves_existing_continuity() {
    local scratch; scratch=$(scratch_dir f-preserves-continuity)
    echo "user content" > "$scratch/CONTINUITY.md"
    local before; before=$(hash_file "$scratch/CONTINUITY.md")
    ( cd "$scratch" && mkdir -p .fakehome && HOME="$scratch/.fakehome" bash "$REPO_ROOT/setup.sh" -f -p TestProj -t fullstack >/dev/null 2>&1 )
    if [ -f "$scratch/CONTINUITY.md" ]; then
        local after; after=$(hash_file "$scratch/CONTINUITY.md")
        assert_equals "$before" "$after" "existing CONTINUITY.md byte-preserved through -f"
    else
        fail "CONTINUITY.md was deleted by -f (should be preserved)"
    fi
}

# P2-3 regression guard: -f must NEVER overwrite an existing populated
# .claude/local/state.md. The if-guard at setup.sh:533 protects this today, but
# a future refactor could replace it with copy_file (which overwrites under -f).
test_f_preserves_existing_state_md() {
    local scratch; scratch=$(scratch_dir f-preserves-state-md)
    # Initial install creates state.md.
    ( cd "$scratch" && mkdir -p .fakehome && HOME="$scratch/.fakehome" bash "$REPO_ROOT/setup.sh" -p TestProj -t fullstack >/dev/null 2>&1 )
    # Simulate a developer populating state.md with real workflow content.
    echo "## USER WORKFLOW STATE SENTINEL" >> "$scratch/.claude/local/state.md"
    local before; before=$(hash_file "$scratch/.claude/local/state.md")
    # Re-run with -f. state.md must NOT be overwritten.
    ( cd "$scratch" && mkdir -p .fakehome && HOME="$scratch/.fakehome" bash "$REPO_ROOT/setup.sh" -f -p TestProj -t fullstack >/dev/null 2>&1 )
    if [ -f "$scratch/.claude/local/state.md" ]; then
        local after; after=$(hash_file "$scratch/.claude/local/state.md")
        assert_equals "$before" "$after" "existing .claude/local/state.md byte-preserved through -f"
    else
        fail ".claude/local/state.md was deleted by -f (should be preserved)"
    fi
}

# P2-2 regression guard: fresh-install banner must NOT mention CONTINUITY.md
# (post PR #2, no CONTINUITY.md is created — pointing users at it is misleading).
# It SHOULD mention the new artifacts (.claude/local/state.md and docs/adr/).
test_fresh_install_banner_no_continuity_ref() {
    local scratch; scratch=$(scratch_dir fresh-banner-no-continuity)
    local log="$scratch/.setup.log"
    ( cd "$scratch" && mkdir -p .fakehome && HOME="$scratch/.fakehome" bash "$REPO_ROOT/setup.sh" -p TestProj -t fullstack > "$log" 2>&1 )
    # Extract the "What was created" block: from header until the next "Plugins"
    # header (the "What was created" block has interior blank lines, so a single
    # blank-line terminator is wrong). ANSI color codes and the trailing blank
    # are tolerated.
    local block
    block=$(awk '/What was created:/{flag=1;next} flag && /Plugins pre-enabled/{flag=0} flag' "$log")
    if echo "$block" | grep -qE "^[[:space:]]*CONTINUITY\.md"; then
        fail "fresh-install banner still mentions CONTINUITY.md (post PR #2 it shouldn't)"
    else
        pass "fresh-install banner does not mention CONTINUITY.md"
    fi
    # Positive: mentions state.md and docs/adr/ (the new artifacts).
    if echo "$block" | grep -qF ".claude/local/state.md"; then
        pass "banner mentions .claude/local/state.md (new artifact)"
    else
        fail "banner does not mention .claude/local/state.md (got: $block)"
    fi
    if echo "$block" | grep -qF "docs/adr/"; then
        pass "banner mentions docs/adr/ (new artifact)"
    else
        fail "banner does not mention docs/adr/"
    fi
    # P1-A/P1-B regression guard: the ENTIRE post-install output (not just the
    # "What was created" block) must be free of CONTINUITY.md references.
    # Iter-1 only scoped to the "What was created" block, which is why the
    # "Next steps" block ("Edit CONTINUITY.md", "git add ... CONTINUITY.md ...")
    # slipped through. Scan the whole log, ignoring this very test's filename
    # context which is irrelevant to user-facing output.
    assert_not_contains "$log" "CONTINUITY.md" "fresh-install full output has zero CONTINUITY.md mentions (P1-A/P1-B guard)"
}

# ===========================================================================
# Self-copy guard: copy_file must not abort under `set -e` when src and dest
# are the same file. This happens when setup.sh is run IN-PLACE (e.g. a forge
# maintainer dogfooding via `./setup.sh --upgrade` in the repo itself):
# SCRIPT_DIR == repo root, so copies like docs/adr/template.md → docs/adr/
# template.md become `cp X X`, which errors "are identical" with a non-zero
# exit. setup.sh:7 has `set -e`, so without a guard the script silently dies
# before the rules sync. Tests exercise the REAL copy_file extracted from
# setup.sh so they track the shipped implementation.
# ===========================================================================
extract_copy_file() {
    # Write a file containing just the copy_file function body, extracted
    # verbatim from the real setup.sh.
    local dest="$1"
    awk '/^copy_file\(\) \{/,/^\}/' "$REPO_ROOT/setup.sh" > "$dest"
    # Brittleness guard: the awk regex needs the exact `copy_file() {` line.
    # A cosmetic reformat (extra space, brace on next line, rename) yields an
    # empty extraction — fail with a clear message instead of letting the
    # self-copy test report a misleading "guard missing".
    [ -s "$dest" ] || fail "extract_copy_file: no 'copy_file() {' found in setup.sh — declaration style changed?"
}

# Source the extracted copy_file under `set -e` and invoke it with src/dest.
# Echoes captured stdout, which contains SURVIVED iff copy_file returned without
# tripping set -e (the regression signal). Shared by both bash guard tests so the
# brittle `set -e` runner scaffold lives in exactly one place.
run_copy_file_under_set_e() {
    local work="$1" src="$2" dst="$3" fn="$4"
    local runner="$work/runner.sh"
    cat > "$runner" <<EOF
set -e
RED=''; GREEN=''; BLUE=''; NC=''
FORCE=true
source "$fn"
copy_file "$src" "$dst" "case" >/dev/null
echo SURVIVED
EOF
    bash "$runner" 2>/dev/null || true
}

test_copy_file_self_copy_guard() {
    start_test "copy_file: self-copy under set -e does not abort (in-place dogfood regression)"

    local work; work=$(scratch_dir selfcopy)
    local fn="$work/copy_file_extracted.sh"
    extract_copy_file "$fn"

    local f="$work/same.txt"
    echo "payload" > "$f"

    local out; out=$(run_copy_file_under_set_e "$work" "$f" "$f" "$fn")

    if [[ "$out" == *SURVIVED* ]]; then
        pass "self-copy completes (set -e not tripped by 'cp: are identical')"
    else
        fail "self-copy aborted under set -e — copy_file lacks a same-file guard"
    fi

    assert_contains "$f" "payload" "self-copied file content left intact"
}

test_copy_file_normal_copy_still_works() {
    start_test "copy_file: normal copy still works after self-copy guard"

    local work; work=$(scratch_dir normalcopy)
    local fn="$work/copy_file_extracted.sh"
    extract_copy_file "$fn"

    local src="$work/src.txt" dst="$work/dst.txt"
    echo "hello" > "$src"

    local out; out=$(run_copy_file_under_set_e "$work" "$src" "$dst" "$fn")

    if [[ "$out" == *SURVIVED* ]]; then
        pass "normal copy completes"
    else
        fail "normal copy aborted unexpectedly"
    fi
    assert_file_exists "$dst" "normal copy created the destination"
    assert_contains "$dst" "hello" "normal copy produced correct content"
}

test_copy_file_ps1_self_copy_guard() {
    # PowerShell parity for the self-copy guard (Copy-TemplateFile in setup.ps1).
    # Follows the repo's pwsh-conditional-skip convention (see
    # test-build-evidence.sh / test-default-branch.sh): runs only when pwsh is on
    # PATH, otherwise records a skip. Under $ErrorActionPreference='Stop', an
    # unguarded `Copy-Item X X` throws; the guard must short-circuit so the call
    # completes. Extracts the REAL Copy-TemplateFile so the test tracks shipped code.
    if ! command -v pwsh >/dev/null 2>&1; then
        start_test "Copy-TemplateFile self-copy guard (skipped — pwsh not installed)"
        pass "skipped (no pwsh)"
        return
    fi

    start_test "Copy-TemplateFile: self-copy does not throw under ErrorActionPreference=Stop (ps1 parity)"

    local work; work=$(scratch_dir pscopy)
    local fn="$work/Copy-TemplateFile.ps1"
    awk '/^function Copy-TemplateFile \{/,/^\}/' "$REPO_ROOT/setup.ps1" > "$fn"
    [ -s "$fn" ] || fail "no 'function Copy-TemplateFile {' found in setup.ps1 — declaration style changed?"

    local f="$work/same.txt"
    echo "payload" > "$f"

    local runner="$work/runner.ps1"
    cat > "$runner" <<EOF
\$ErrorActionPreference = 'Stop'
function Write-Color { param([string]\$Text, [string]\$Color) }
\$Force = \$true
. "$fn"
Copy-TemplateFile "$f" "$f" "self-copy" | Out-Null
Write-Output "SURVIVED"
EOF

    local out
    out=$(pwsh -NoProfile -File "$runner" 2>/dev/null) || true

    if [[ "$out" == *SURVIVED* ]]; then
        pass "ps1 self-copy completes (guard fired before Copy-Item self-copy)"
    else
        fail "ps1 self-copy threw — Copy-TemplateFile lacks a same-file guard"
    fi
    assert_contains "$f" "payload" "ps1 self-copied file content left intact"
}

# ===========================================================================
# Forge version stamp (v5.51): committed .claude/.forge-version pin + machine
# stamp + advisory drift warning (all advisory, fail-open, never blocks).
# ===========================================================================
test_forge_version_stamp() {
    start_test "forge version stamp: pin + machine stamp + direction-aware advisory"
    local EXPECT
    EXPECT=$(sed -nE 's/^##[[:space:]]+([0-9]+\.[0-9]+).*/\1/p' "$REPO_ROOT/docs/CHANGELOG.md" | head -1)

    # Fresh install → project pin AND machine stamp both equal the forge's version.
    local S; S=$(scratch_dir fvstamp); make_project "$S" flat
    run_setup "$S" "$S/.setup.log" -p FV -t python
    assert_equals "$?" "0" "fv: fresh install exits 0"
    assert_file_exists "$S/.claude/.forge-version" "fv: project pin written on fresh install"
    assert_equals "$(cat "$S/.claude/.forge-version" 2>/dev/null)" "$EXPECT" "fv: project pin == CHANGELOG version"
    assert_equals "$(cat "$S/.fakehome/.claude/.forge-version" 2>/dev/null)" "$EXPECT" "fv: machine stamp written under HOME"

    # --upgrade with an OLDER pin → UPGRADE advisory, exits 0 (advisory), pin advances.
    printf '0.1\n' > "$S/.claude/.forge-version"
    run_setup "$S" "$S/.up.log" -p FV -t python --upgrade
    assert_equals "$?" "0" "fv: --upgrade exits 0 (advisory only, never blocks)"
    assert_contains "$S/.up.log" "UPGRADE the project" "fv: older pin → UPGRADE advisory shown"
    assert_equals "$(cat "$S/.claude/.forge-version")" "$EXPECT" "fv: pin advanced after upgrade"

    # -f with a NEWER pin → DOWNGRADE advisory (and -f, not just --upgrade, warns), exits 0.
    printf '99.99\n' > "$S/.claude/.forge-version"
    run_setup "$S" "$S/.dn.log" -p FV -t python -f
    assert_equals "$?" "0" "fv: -f exits 0 (advisory only)"
    assert_contains "$S/.dn.log" "DOWNGRADE the project" "fv: newer pin + -f → DOWNGRADE advisory shown"

    # -f with an OLDER pin → UPGRADE advisory (proves -f reaches the UPGRADE branch,
    # not just the --upgrade path).
    printf '0.2\n' > "$S/.claude/.forge-version"
    run_setup "$S" "$S/.fup.log" -p FV -t python -f
    assert_contains "$S/.fup.log" "UPGRADE the project" "fv: older pin + -f → UPGRADE advisory shown"

    # Malformed existing pin → NO advisory (the prev pin is validated as X.Y first).
    printf 'garbage\n' > "$S/.claude/.forge-version"
    run_setup "$S" "$S/.mal.log" -p FV -t python --upgrade
    assert_not_contains "$S/.mal.log" "UPGRADE the project" "fv: malformed prev pin → no upgrade advisory (fail-open)"
    assert_not_contains "$S/.mal.log" "DOWNGRADE the project" "fv: malformed prev pin → no downgrade advisory (fail-open)"

    # Legacy-partial: machinery present (settings.json) but NO stamp, plain (non-force)
    # rerun → must NOT fabricate a pin (it would lie about the actual on-disk version).
    local L; L=$(scratch_dir fvlegacy); make_project "$L" flat
    run_setup "$L" "$L/.seed.log" -p FV -t python
    rm -f "$L/.claude/.forge-version"
    run_setup "$L" "$L/.plain.log" -p FV -t python
    assert_file_missing "$L/.claude/.forge-version" "fv: plain rerun on legacy machinery does NOT fabricate a pin"
}

# Extract + unit-test the real forge_version() parser (mirrors extract_copy_file).
# Covers the validated-parse branch: a non-version top heading (e.g. "## [Unreleased]")
# or a missing CHANGELOG must yield "unknown" — never echo the heading — so setup
# skips stamping rather than poisoning the pin with garbage.
test_forge_version_parse() {
    start_test "forge_version(): validated parse → 'unknown' on non-version / missing CHANGELOG"
    local work; work=$(scratch_dir fvparse)
    local fn="$work/forge_version_extracted.sh"
    awk '/^forge_version\(\) \{/,/^\}/' "$REPO_ROOT/setup.sh" > "$fn"
    [ -s "$fn" ] || { fail "extract forge_version: no 'forge_version() {' in setup.sh — declaration changed?"; return; }

    _run_fv() {  # $1 = SCRIPT_DIR to feed the function
        local sd="$1" runner="$work/run.sh"
        cat > "$runner" <<EOF
SCRIPT_DIR="$sd"
source "$fn"
forge_version
EOF
        bash "$runner" 2>/dev/null
    }

    # Normal version heading → parsed.
    mkdir -p "$work/good/docs"; printf '# Changelog\n\n## 7.3 — 2026-01-01\n' > "$work/good/docs/CHANGELOG.md"
    assert_equals "$(_run_fv "$work/good")" "7.3" "forge_version: parses a normal '## 7.3' heading"

    # Non-version TOP heading → unknown (only the first heading is inspected; we must
    # NOT scan past "## [Unreleased]" to a stale older release — Codex code-review P2-1).
    mkdir -p "$work/unrel/docs"; printf '# Changelog\n\n## [Unreleased]\n\n## 7.3 — x\n' > "$work/unrel/docs/CHANGELOG.md"
    assert_equals "$(_run_fv "$work/unrel")" "unknown" "forge_version: non-version top heading → unknown (no scan-past)"

    # Only non-version headings → unknown.
    mkdir -p "$work/none/docs"; printf '# Changelog\n\n## [Unreleased]\n' > "$work/none/docs/CHANGELOG.md"
    assert_equals "$(_run_fv "$work/none")" "unknown" "forge_version: no numeric top heading → unknown"

    # Missing CHANGELOG → unknown (fail-open, no echo of garbage).
    mkdir -p "$work/missing"
    assert_equals "$(_run_fv "$work/missing")" "unknown" "forge_version: missing CHANGELOG → unknown"
}

test_forge_version_stamp
test_forge_version_parse
test_state_md_installs
test_gitignore_has_claude_local
test_gitignore_idempotent
test_adrs_install
test_no_continuity_installed
test_f_preserves_existing_continuity
test_f_preserves_existing_state_md
test_fresh_install_banner_no_continuity_ref
test_copy_file_self_copy_guard
test_copy_file_normal_copy_still_works
test_copy_file_ps1_self_copy_guard

# ===========================================================================
# Report
# ===========================================================================
report "test-setup.sh"
