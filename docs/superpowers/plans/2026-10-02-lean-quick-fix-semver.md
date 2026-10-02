# Lean Quick-Fix and Per-Change SemVer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make quick-fix a direct-check, agent-free workflow and publish every merged Forge change as an exact three-component SemVer release.

**Architecture:** Keep the first changelog release heading as Forge's source version, but require exact `MAJOR.MINOR.PATCH` on all source/output boundaries while accepting legacy `6` and `6.MINOR` stamps only as upgrade inputs. Give `/quick-fix <slug>` a narrow, fail-closed exemption in both ship-hook twins after shared state/configuration/authorization checks and before full-workflow receipt enforcement; leave `/fix-bug` and `/new-feature` certification unchanged.

**Tech Stack:** Bash, Windows PowerShell 5.1-compatible PowerShell, Python 3 standard library, Markdown workflow policy, shell contract fixtures.

**Spec:** `docs/superpowers/specs/2026-10-02-lean-quick-fix-semver-design.md`

## Global Constraints

- Release this work as exact SemVer `6.4.0`.
- One merged change set/PR receives one version; intermediate commits do not each become releases.
- Source/materializer/runtime outputs require exact `MAJOR.MINOR.PATCH`.
- Upgrade/full-refresh readers accept only legacy `6`, legacy `6.MINOR`, or current `6.MINOR.PATCH`; malformed values and unsupported majors block.
- Quick-fix is limited to clearly understood, low-risk, non-user-facing changes touching at most
  three implementation files with an obvious focused check; exact required release metadata
  `README.md` and `docs/CHANGELOG.md` does not consume that implementation-path budget.
- Quick-fix dispatches no `code-spec`, `code-quality`, `verify-app`, or `verify-e2e` role and creates no candidate-bound final receipt set.
- New quick-fix activation requires a clean worktree at the resolved base, and ship hooks revalidate
  the recorded base plus complete changed-path scope before granting the receipt exemption.
- `/fix-bug` and `/new-feature` retain the complete paired-review and verification receipt contract.
- Bash and PowerShell behavior must remain equivalent; PowerShell source stays compatible with Windows PowerShell 5.1.
- README release prose covers only material user-facing changes; `docs/CHANGELOG.md` records every released change.
- Use focused owning suites plus `bash tests/template/run-fast.sh`; do not run exhaustive local aggregate suites without explicit authorization.

## Review Focus

1. An exact `/quick-fix valid-slug` may bypass final receipts, but malformed variants such as `/quick-fix Bad` or `/quick-fix ../x` must remain blocked; Task 2 adds both positive and negative fixtures.
2. Quick-fix must not bypass an active native-Goal PR authorization check; Task 2 adds a `gh pr create` fixture with a nonce and no authorization.
3. `/fix-bug` and `/new-feature` with the same missing receipts must still block; Task 2 keeps explicit control fixtures for both workflows.
4. Existing stamps `6` and `6.3` must upgrade, while a source release argument `6.4` must be rejected and `6.4.0` accepted; Task 1 exercises each boundary.
5. A failed full-refresh transaction must leave the prior stamp byte-identical; Task 1 extends the existing rollback assertion with a legacy two-component starting stamp.
6. Quick-fix activation over a dirty or ahead-of-base worktree, or shipping more than three
   implementation paths, must block; Task 2 adds Bash and PowerShell controls.
7. Stop/evidence hooks and generated adapters must not reintroduce reviewer/verifier requirements
   or review-transport disclosure for quick-fix; Task 2 tests all three surfaces.

---

### Task 1: Migrate the Executable Release Contract to SemVer

**Files:**
- Modify: `tests/template/test-setup.sh`
- Modify: `tests/template/test-setup-flags.sh`
- Modify: `tests/template/test-full-refresh.sh`
- Modify: `tests/template/test-full-refresh.ps1`
- Modify: `tests/template/test-runtime-identity.sh`
- Modify: `tests/template/test-hooks.sh`
- Modify: `tests/template/test-contracts.sh`
- Modify: `tests/template/test-agent-dispatch.sh`
- Modify: `tests/template/test-agent-dispatch.ps1`
- Modify: `tests/template/test-codex-workflow-names.sh`
- Modify: `tests/template/test-codex-workflow-names.ps1`
- Modify: `tests/template/test-workflow-state.sh`
- Modify: `tests/template/test-worktree-lifecycle.sh`
- Modify: `setup.sh`
- Modify: `setup.ps1`
- Modify: `scripts/materialize-adapters.sh`
- Modify: `scripts/materialize-adapters.ps1`
- Modify: `scripts/full-refresh.sh`
- Modify: `scripts/full-refresh.ps1`
- Modify: `scripts/merge-settings.py`
- Modify: `scripts/verify-runtime.sh`
- Modify: `scripts/verify-runtime.ps1`
- Modify: `hooks/lib/state-path.sh`
- Modify: `hooks/lib/state-path.ps1`
- Modify: `hooks/check-workflow-gates.sh`
- Modify: `hooks/check-workflow-gates.ps1`
- Modify: `docs/CHANGELOG.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: top `docs/CHANGELOG.md` heading; existing target `.forge/version`; `--release-version` / `-ReleaseVersion` arguments.
- Produces: exact source/output release `MAJOR.MINOR.PATCH`; migration acceptance for `6`, `6.MINOR`, and `6.MINOR.PATCH`; unchanged `FORGE_VERSION:` and `FORGE_VERSION_CHANGE:` diagnostics.

- [ ] **Step 1: Change parser and boundary tests to require three components**

First establish the planned release input: create the `## 6.4.0 — 2026-10-02` heading in
`docs/CHANGELOG.md` and move all existing `### Unreleased ...` subsections out from under `6.3`
into it. Do not yet claim the new quick-fix implementation is complete; add those details after the
behavior exists. This ensures every RED fixture that derives the checked-out source release receives
the intended nonempty `6.4.0` value rather than failing because its parser returns an empty string.

In `tests/template/test-setup.sh`, change the changelog parser fixture to make `7.3.2` the only valid source release and add an incomplete-source negative control:

```bash
mkdir -p "$work/good/docs"
printf '# Changelog\n\n## 7.3.2 — 2026-01-01\n' > "$work/good/docs/CHANGELOG.md"
assert_equals "$(_run_fv "$work/good")" "7.3.2" \
    "forge_version: parses a normal three-component heading"

mkdir -p "$work/incomplete/docs"
printf '# Changelog\n\n## 7.3 — 2026-01-01\n' > "$work/incomplete/docs/CHANGELOG.md"
assert_equals "$(_run_fv "$work/incomplete")" "unknown" \
    "forge_version: rejects a two-component source release"
```

Update every test helper that extracts the current release from the changelog to capture three
components:

```bash
sed -nE 's/^##[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+).*/\1/p'
```

The affected Bash helpers are in `test-setup.sh`, `test-setup-flags.sh`, `test-full-refresh.sh`,
`test-agent-dispatch.sh`, and `test-codex-workflow-names.sh`. Update the matching PowerShell
changelog expressions in `test-full-refresh.ps1`, `test-agent-dispatch.ps1`, and
`test-codex-workflow-names.ps1` to capture `([0-9]+\.[0-9]+\.[0-9]+)` as well.

Replace hard-coded valid source/materializer arguments `6.3` with `6.4.0` in setup-flag,
workflow-state, worktree-lifecycle, and runtime-identity fixtures. Do not replace legacy installed
stamp fixtures whose purpose is migration compatibility.

- [ ] **Step 2: Add legacy-input and malformed-source assertions**

Extend `test_forge_version_stamp` in `tests/template/test-setup.sh` so both legacy forms upgrade to
the exact changelog release:

```bash
for legacy_version in 6 6.3; do
    printf '%s\n' "$legacy_version" > "$S/.forge/version"
    run_setup "$S" "$S/.up-$legacy_version.log" -p FV -t python --upgrade
    assert_equals "$?" "0" "fv: legacy $legacy_version V6 upgrade exits 0"
    assert_contains "$S/.up-$legacy_version.log" \
        "FORGE_VERSION_CHANGE: $legacy_version -> $EXPECT" \
        "fv: upgrade reports $legacy_version to exact SemVer"
    assert_equals "$(tr -d '\r\n' < "$S/.forge/version")" "$EXPECT" \
        "fv: legacy $legacy_version advances to exact SemVer"
done
```

In `tests/template/test-setup-flags.sh`, invoke the Bash materializer once with
`--release-version 6.4` and assert exit `2` plus `BLOCKED: invalid release version`; retain a valid
`6.4.0` control. In `tests/template/test-full-refresh.ps1`, use the existing
`Invoke-IsolatedPowerShell` helper to invoke `scripts/materialize-adapters.ps1` with
`-ReleaseVersion 6.4`; assert a nonzero `Code` and output containing `ReleaseVersion`. Retain a
`6.4.0` control through the existing `$expectedRelease` materialization fixture.

In `tests/template/test-full-refresh.sh` and `test-full-refresh.ps1`, add a project initially
stamped `6.3`, and another stamped `6.4.0`; run successful refreshes to `$EXPECTED_RELEASE` and
assert both transitions/read paths. Add a new rollback case beginning with `6.3`, capture its hash,
force the existing transaction failure, and assert the hash is unchanged. Preserve the existing
no-prior-stamp rollback fixture as a separate control.

In `tests/template/test-runtime-identity.sh`, write `6.4.0` and assert discovery prints
`FORGE_VERSION: 6.4.0`; add a `6.4` project and assert runtime verification exits nonzero with
`FORGE_VERSION: BLOCKED malformed project release`. Under the existing `pwsh` availability guard,
run `verify-runtime.ps1 discovery` against the same valid and malformed fixtures and require the
same outcomes.

Add setup/preflight rejection controls for malformed installed stamps `6.4.0.1` and `6.4.x` in
Bash and PowerShell, plus a successful `setup.ps1 -Upgrade` control for installed `6.4.0`. In
`tests/template/test-hooks.sh`, materialize a `6.4.0` fixture, corrupt its
managed configuration, and prove both workflow-gate twins still emit `FORGE_CONFIG_TAMPERED`; also
prove both state-path twins accept `6.4.0` and reject `6.4.0.1`.

- [ ] **Step 3: Run the focused tests and verify RED**

Run:

```bash
bash tests/template/test-setup-flags.sh
bash tests/template/test-runtime-identity.sh
bash tests/template/test-setup.sh
bash tests/template/test-full-refresh.sh
bash tests/template/test-hooks.sh
```

Expected: failures show current source parsers truncate `7.3.2` to `7.3`, current materializers
reject `6.4.0`, current runtime verification rejects the three-component stamp, and current
compatibility/config readers reject or skip an installed three-component V6 stamp.

- [ ] **Step 4: Make source/output validators exact three-component SemVer**

In `setup.sh`, replace `forge_version` extraction and validation with:

```bash
forge_version() {
    local top v
    top=$(grep -m1 '^## ' "$SCRIPT_DIR/docs/CHANGELOG.md" 2>/dev/null)
    v=$(printf '%s' "$top" | sed -nE 's/^##[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
    if [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then printf '%s' "$v"; else printf 'unknown'; fi
}
```

Require the same exact shape for `$FORGE_VERSION`, Bash materializer/full-refresh arguments, and the
Bash runtime verifier:

```bash
^[0-9]+\.[0-9]+\.[0-9]+$
```

Apply the PowerShell equivalent to `Get-ForgeVersion`, `materialize-adapters.ps1`,
`full-refresh.ps1`, and `verify-runtime.ps1`:

```powershell
^\d+\.\d+\.\d+$
```

In `scripts/merge-settings.py`, require source `release_version` with:

```python
if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", release_version) is None:
    raise RefreshBlocked("invalid release version")
```

Update materializer usage text from `MAJOR.MINOR` to `MAJOR.MINOR.PATCH`.

- [ ] **Step 5: Preserve legacy V6 stamps only at compatibility readers**

In `setup.sh` and `setup.ps1`, validate an existing target stamp as one to three numeric components
whose major is exactly `6`. Preserve unsupported-major diagnostics separately from malformed input.
Use these exact shapes:

```bash
^([0-9]+)(\.[0-9]+){0,2}$
```

```powershell
^(\d+)(\.\d+){0,2}$
```

In `scripts/merge-settings.py`, update both V6 compatibility recognizers in `inventory_legacy()`
and `reconcile_legacy_hook_settings()` to accept `6` plus one or two numeric suffixes:

```python
current_v6 = re.fullmatch(r"6(?:\.[0-9]+){0,2}", current_version) is not None
```

Then replace the full-refresh installed-version special case with:

```python
installed_match = re.fullmatch(r"([0-9]+)(?:\.[0-9]+){0,2}", installed_version)
if installed_match is None:
    raise RefreshBlocked("malformed Forge release at .forge/version")
if installed_match.group(1) != "6":
    raise RefreshBlocked(f"unsupported Forge layout major {installed_match.group(1)}")
```

Extend V6 discovery/config-boundary recognition in `state-path.sh`, `state-path.ps1`, and both
workflow-gate hooks from one optional suffix to two:

```text
^6(\.[0-9]+){0,2}$
```

Do not broaden accepted characters, add prerelease/build metadata, or implement precedence sorting.

- [ ] **Step 6: Complete and assert synchronized `6.4.0` release metadata**

Keep the `6.4.0` heading and previously unreleased notes established in Step 1. Add the complete
planned release notes for the SemVer contract, lean quick-fix behavior, compatibility, contributor
policy, and Bash/PowerShell parity. Update the README badge to `6.4.0` and add one concise `6.4.0`
history row because this is a material workflow/version-contract release. Task 3 will tighten the
surrounding explanation after the workflow implementation is complete, without creating another
release entry.

In `tests/template/test-contracts.sh`, use independent current-release and README-history constants:

```bash
FIRST_CHANGELOG_VERSION=$(printf '%s\n' "$FIRST_CHANGELOG_RELEASE" \
    | sed -E 's/^## ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
if printf '%s\n' "$FIRST_CHANGELOG_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    pass "top changelog release is exact MAJOR.MINOR.PATCH"
else
    fail "top changelog release is exact MAJOR.MINOR.PATCH"
fi
EXPECTED_FORGE_VERSION="$FIRST_CHANGELOG_VERSION"
EXPECTED_README_HISTORY_VERSION='6.4.0'
```

Keep changelog and badge equal to `EXPECTED_FORGE_VERSION`; compare the first README history row to
`EXPECTED_README_HISTORY_VERSION`. Remove the hard-coded current-version and literal top-release
assertions so a future patch release changes only the source changelog heading and README badge,
without another test-constant edit or a patch-by-patch README history row.

- [ ] **Step 7: Run focused GREEN verification**

Run:

```bash
bash tests/template/test-setup-flags.sh
bash tests/template/test-runtime-identity.sh
bash tests/template/test-setup.sh
bash tests/template/test-full-refresh.sh
bash tests/template/test-hooks.sh
bash tests/template/test-agent-dispatch.sh
bash tests/template/test-codex-workflow-names.sh
bash tests/template/test-workflow-state.sh
bash tests/template/test-worktree-lifecycle.sh
bash tests/template/test-contracts.sh
```

When `pwsh` is installed, also run:

```bash
pwsh -NoProfile -File tests/template/test-full-refresh.ps1
pwsh -NoProfile -File tests/template/test-agent-dispatch.ps1
pwsh -NoProfile -File tests/template/test-codex-workflow-names.ps1
```

Expected: every suite exits `0`; the current release is `6.4.0`; legacy `6` and `6.3` upgrade;
two-component source arguments fail; malformed/unsupported stamps remain blocked; rollback preserves
the old stamp.

- [ ] **Step 8: Inspect the executable SemVer checkpoint without committing**

```bash
git diff --check
git status --short
git diff -- setup.sh setup.ps1 scripts hooks tests/template
```

Keep these bytes uncommitted. This repository freezes one staged-clean final candidate and commits
only through candidate promotion after all final receipts are valid.

---

### Task 2: Remove Reviewers and Verify Agents from Quick-Fix

**Files:**
- Modify: `tests/template/test-hooks.sh`
- Modify: `tests/template/test-workflow-parity.sh`
- Modify: `tests/template/test-contracts.sh`
- Modify: `tests/template/test-resource-discipline.sh`
- Modify: `tests/template/test-workflow-state.sh`
- Modify: `hooks/check-workflow-gates.sh`
- Modify: `hooks/check-workflow-gates.ps1`
- Modify: `hooks/check-state-updated.sh`
- Modify: `hooks/check-state-updated.ps1`
- Modify: `hooks/build-evidence.sh`
- Modify: `hooks/build-evidence.ps1`
- Modify: `hooks/lib/workflow-state.sh`
- Modify: `hooks/lib/workflow-state.ps1`
- Modify: `scripts/materialize-adapters.sh`
- Modify: `scripts/materialize-adapters.ps1`
- Modify: `commands/quick-fix.md`
- Modify: `rules/workflow.md`
- Modify: `FORGE.template.md`

**Interfaces:**
- Consumes: canonical V6 `Workflow/Command` value and the already-enforced shared ship/configuration/Goal authorization checks.
- Produces: exact, base-bound `/quick-fix <slug>` receipt exemption; unchanged full receipt
  enforcement for `/fix-bug` and `/new-feature`; clean-base activation, three-implementation-path
  enforcement, direct-check Stop/evidence behavior, and reviewer-free generated adapters.

- [ ] **Step 1: Add ship-hook fixtures for the exact quick-fix exemption**

Refactor `_run_strict_v6_receipt_sh` in `tests/template/test-hooks.sh` to accept a fifth optional
workflow command and write it into the state table:

```bash
local label="$1" cmd="$2" receipt_mode="$3" staged_path="${4:-}"
local workflow_command="${5:-/new-feature test}"
```

Add these assertions using missing receipts:

```bash
R=$(_run_strict_v6_receipt_sh quick-fix-push 'git push' missing '' '/quick-fix valid-slug')
assert_equals "${R##*|}" "0" "exact quick-fix bypasses final receipt enforcement"

R=$(_run_strict_v6_receipt_sh quick-fix-bad 'git push' missing '' '/quick-fix Bad')
assert_equals "${R##*|}" "2" "malformed quick-fix cannot bypass receipts"

R=$(_run_strict_v6_receipt_sh quick-fix-path 'git push' missing '' '/quick-fix ../x')
assert_equals "${R##*|}" "2" "path-like quick-fix slug cannot bypass receipts"

R=$(_run_strict_v6_receipt_sh fix-bug-control 'git push' missing '' '/fix-bug valid-slug')
assert_equals "${R##*|}" "2" "fix-bug still requires final receipts"

R=$(_run_strict_v6_receipt_sh feature-control 'git push' missing '' '/new-feature valid-slug')
assert_equals "${R##*|}" "2" "new-feature still requires final receipts"
```

Add `_run_strict_v6_receipt_ps` as the PowerShell twin: create the fixture through
`_run_strict_v6_receipt_sh` with a distinct label, reuse its `.hook-input.json`, invoke
`$HOOK_PS` from that fixture with `pwsh -NoProfile -File`, and return `dir|exit`. Under the existing
`command -v pwsh` guard, repeat the exact-slug, uppercase-slug, path-like-slug, `/fix-bug`, and
`/new-feature` assertions above against that helper.

Add a quick-fix fixture with an active `/goal session` nonce and no PR authorization, invoke
`gh pr create`, and assert exit `2` plus `no ## PR authorization` in both Bash and PowerShell. This
pins the exemption after the authorization boundary.

Each positive quick-fix fixture must include a valid `Identity/Workflow base SHA` equal to the
fixture's initial commit and no more than three implementation paths changed from that base. Add
negative fixtures for a missing base, a non-ancestor base, four implementation paths, and three
implementation paths plus the exact release metadata paths `README.md` and `docs/CHANGELOG.md`;
only the last case is allowed. Mirror all cases through the PowerShell hook when `pwsh` is present.

- [ ] **Step 2: Change workflow contract tests to demand the lean path**

In `tests/template/test-workflow-parity.sh`, keep shared activation, branch/base, direct-check, and
authorization assertions for all workflows, but restrict candidate-freeze, same-candidate,
mutation, and `--begin-review` requirements to `new-feature` and `fix-bug`.

For `quick-fix.md`, assert direct verification and escalation language, then reject every removed
surface:

```bash
assert_contains "$REPO_ROOT/commands/quick-fix.md" "focused owning check" \
    "quick-fix performs direct focused verification"
assert_contains "$REPO_ROOT/commands/quick-fix.md" 'use `/fix-bug`' \
    "quick-fix escalates work outside its limits"
for removed in code-spec code-quality verify-app verify-e2e E2E --begin-review \
    "candidate receipt" "review iteration" "closure review"; do
    assert_not_contains "$REPO_ROOT/commands/quick-fix.md" "$removed" \
        "quick-fix omits $removed"
done
```

In `tests/template/test-contracts.sh`, require `--begin-review` only in `new-feature.md` and
`fix-bug.md`. In `test-resource-discipline.sh`, remove quick-fix from the closure-review assertion
and instead assert it contains no broad/closure review loop.

In `tests/template/test-workflow-state.sh`, add Bash and PowerShell assertions that a new
`quick-fix` activation succeeds only when `HEAD` equals the resolved base and `git status
--porcelain --untracked-files=all` is empty. Prove dirty content and an ahead-of-base commit both
block, while an exact resume of an already-active quick-fix still succeeds. Add an uppercase slug
control proving the PowerShell twin rejects it case-sensitively.

In `tests/template/test-hooks.sh`, assert the Stop-hook twins do not emit
`FORGE_FINAL_EVIDENCE_STALE` for an exact quick-fix but still emit it for `/fix-bug`. Exercise
`build-evidence.sh` and `.ps1` so exact quick-fix uses a truthful direct-check readiness path while
full workflows still require receipts. In `test-workflow-parity.sh`, remove quick-fix adapters from
the transport-disclosure allowlist and add them to the explicit no-disclosure assertions; require
both materializer selectors to omit `.forge/workflows/quick-fix.md`.

- [ ] **Step 3: Run the focused tests and verify RED**

Run:

```bash
bash tests/template/test-hooks.sh
bash tests/template/test-workflow-parity.sh
bash tests/template/test-contracts.sh
bash tests/template/test-resource-discipline.sh
bash tests/template/test-workflow-state.sh
```

Expected: the exact quick-fix ship fixture exits `2`, and workflow contracts fail because the
current quick-fix still requires paired reviewers, candidate freeze, Verify app, E2E, and closure
review; activation accepts an existing delta; Stop/evidence still demand receipts; and generated
adapters still claim review transport.

- [ ] **Step 4: Add the fail-closed quick-fix exemption to both hooks**

In `hooks/check-workflow-gates.sh`, after the complete native-Goal PR authorization block and before
the convergence breaker, add:

```bash
if printf '%s\n' "$WORKFLOW_CMD" \
    | grep -qE '^/quick-fix [a-z0-9]+(-[a-z0-9]+)*$'; then
    forge_allow
fi
```

In `hooks/check-workflow-gates.ps1`, at the identical semantic boundary, use case-sensitive
matching:

```powershell
if ($cmd -cmatch '^/quick-fix [a-z0-9]+(-[a-z0-9]+)*$') {
    Exit-ForgeAllow
}
```

Before either allow, parse exactly one `Identity/Workflow base SHA`, require a valid commit that is
an ancestor of `HEAD`, and count the complete tracked delta from that base. Exclude only exact
`README.md` and `docs/CHANGELOG.md` paths from the implementation count; allow at most three other
paths. A missing/malformed/non-ancestor base or larger delta does not take the exemption and falls
through to ordinary receipt enforcement. Do not place the exemption before state validation,
configuration-integrity checking, compound-ship rejection, or native-Goal PR authorization.

In `hooks/lib/workflow-state.sh`, before publishing a **new** quick-fix activation, require current
`HEAD` to equal the resolved base SHA and `git status --porcelain --untracked-files=all` to be empty.
Apply byte-equivalent behavior in `workflow-state.ps1`; use `-cnotmatch` for the task slug and
case-sensitive workflow membership so uppercase commands cannot activate only on Windows. Do not
apply the clean-base condition to an exact resume.

- [ ] **Step 5: Replace quick-fix with the direct-check workflow**

Rewrite `commands/quick-fix.md` to retain startup, activation, acceptance, TDD/static check,
changelog/version update, staging/diff inspection, commit, and external-authorization boundaries.
Use this final step sequence:

```markdown
1. Show/resume state and activate `/quick-fix <slug>` on a non-protected branch.
2. State the acceptance check and no-more-than-three affected files.
3. Write and observe RED first for behavior, or define a direct static/rendered documentation check.
4. Make the smallest change and run the focused owning check directly in the main session.
5. Apply the repository's release policy when one exists; in this Forge source repository that
   means one complete changelog entry and one exact SemVer bump for the mergeable change.
6. Stage only the intended files, inspect the staged diff, and commit.
7. Checkpoint complete, then pause for explicit authorization before push, PR, merge, or another external mutation.
```

State explicitly that user-facing behavior, security/data/API/migration scope, architecture, unclear
causality, more than three files, or a non-obvious check requires `/fix-bug` or `/new-feature`
before implementation continues.

Define the three-file limit as implementation paths; exact required release metadata
`README.md` and `docs/CHANGELOG.md` is additional. Do not tell arbitrary downstream projects to
modify their setup-managed `.forge/version` stamp.

- [ ] **Step 6: Separate canonical quick-fix policy from full certification**

In `rules/workflow.md`, make the nine-step candidate receipt state machine apply only to
`/new-feature` and `/fix-bug`. Add a short `### Quick-fix direct-check path` subsection specifying
activation, acceptance, RED-first/direct check, no agent dispatch or receipts, scope escalation, and
normal external authorization. Scope the later “commit only through candidate promotion” language
to full workflows; quick-fix uses an ordinary inspected commit after its focused check.

In `FORGE.template.md`, change “Every active canonical V6 shipping action requires the current
structured receipt set” to say full `/new-feature` and `/fix-bug` shipping requires it, while an
exact active quick-fix uses its focused-check contract and never uses legacy prose to certify a full
workflow. Likewise, scope “push and PR creation always enforce the receipt boundary” to full
workflows while preserving the shared quick-fix scope and authorization boundary.

Update the corresponding assertions in `tests/template/test-contracts.sh`, including the existing
global receipt-v2 sentence pin and the quick-fix “candidate-bound evidence becomes stale” pin near
its workflow-command assertions. Keep that concurrency warning in both full workflows.

Also scope the later `rules/workflow.md` compatibility-reader sentence (“Every active canonical V6
workflow uses the current structured receipts”) and every candidate/review/verify/promotion step in
`## Finalization Order` to `/new-feature` and `/fix-bug`. Add contract assertions for these exact
full-workflow qualifications so future edits cannot silently restore global receipt requirements.

Update `check-state-updated.sh` and `.ps1` to suppress only the final-receipt stale advisory for an
exact case-sensitive quick-fix command. Update `build-evidence.sh` and `.ps1` with an explicit
`quick_fix_direct` boolean: keep candidate/reviewer/verifier fields false when no receipts exist,
but let `pr_ready` skip those receipt predicates for the exact direct-check path after ordinary PR
head, authorization, and breaker checks. Emit the boolean in the JSON so the reason is truthful.

Remove `.forge/workflows/quick-fix.md` from the ordinary-review disclosure selectors in both
materializers. The generated Claude and Codex quick-fix adapters must omit that disclosure; all
review-capable workflow/skill adapters retain it.

- [ ] **Step 7: Run focused GREEN verification**

Run:

```bash
bash tests/template/test-hooks.sh
bash tests/template/test-workflow-parity.sh
bash tests/template/test-contracts.sh
bash tests/template/test-resource-discipline.sh
bash tests/template/test-workflow-state.sh
```

Expected: exact quick-fix fixtures exit `0`; malformed quick-fix and both full-workflow controls
exit `2`; Goal PR authorization, dirty/ahead activation, invalid base, and four implementation
paths still block; Stop/evidence and generated adapters use the direct-check contract; all workflow
text contracts pass on Bash and PowerShell where available.

- [ ] **Step 8: Inspect the lean quick-fix checkpoint without committing**

```bash
git diff --check
git status --short
git diff -- hooks/check-workflow-gates.sh hooks/check-workflow-gates.ps1 \
    commands/quick-fix.md rules/workflow.md FORGE.template.md \
    hooks/check-state-updated.sh hooks/check-state-updated.ps1 \
    hooks/build-evidence.sh hooks/build-evidence.ps1 hooks/lib/workflow-state.sh \
    hooks/lib/workflow-state.ps1 scripts/materialize-adapters.sh \
    scripts/materialize-adapters.ps1 \
    tests/template/test-hooks.sh tests/template/test-workflow-parity.sh \
    tests/template/test-contracts.sh tests/template/test-resource-discipline.sh \
    tests/template/test-workflow-state.sh
```

Do not create an intermediate implementation commit; preserve one final promotable candidate.

---

### Task 3: Add Repository Release Policy and User Documentation

**Files:**
- Create: `docs/agent-context.md`
- Modify: `tests/template/test-contracts.sh`
- Modify: `CONTRIBUTING.md`
- Modify: `README.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/explanation/workflow.md`
- Modify: `docs/reference/commands.md`
- Modify: `docs/reference/hooks.md`

**Interfaces:**
- Consumes: exact release `6.4.0`; lean quick-fix/full-workflow distinction from Tasks 1 and 2.
- Produces: team-owned per-change release policy; complete changelog record; concise material README history; accurate workflow/hook reference.

- [ ] **Step 1: Add failing documentation-policy contracts**

In `tests/template/test-contracts.sh`, define `AGENT_CONTEXT="$REPO_ROOT/docs/agent-context.md"` and
require these exact policy stems:

```bash
assert_file_exists "$AGENT_CONTEXT" "Forge source repository has team-owned project context"
for stem in \
    "MAJOR.MINOR.PATCH" \
    "one version per merged change set" \
    "MAJOR" "MINOR" "PATCH" \
    '`docs/CHANGELOG.md` records every released change' \
    '`README.md` release prose is reserved for material'; do
    assert_contains "$AGENT_CONTEXT" "$stem" "agent context carries release policy: $stem"
done
```

Add assertions that the detailed workflow and hook references identify quick-fix as a direct-check
path and state that receipt enforcement remains for `/fix-bug` and `/new-feature`. Require
`CONTRIBUTING.md` to tell both source-repository hosts to read `docs/agent-context.md` before a
change; this makes the new policy discoverable through the thin root adapters.

- [ ] **Step 2: Run the contract test and verify RED**

Run:

```bash
bash tests/template/test-contracts.sh
```

Expected: failure because `docs/agent-context.md` does not exist and active docs still imply all
development workflows use candidate receipts.

- [ ] **Step 3: Create the repository-owned contributor policy**

Create `docs/agent-context.md` with this policy:

```markdown
# Claude Codex Forge Project Context

## Release versioning

Every merged change set receives one new Forge version in `MAJOR.MINOR.PATCH` form. Intermediate
commits on the same branch do not each receive a version.

Use one version per merged change set or PR.

- Increment MAJOR for an intentionally breaking installed contract or compatibility boundary.
- Increment MINOR for a backward-compatible capability or material workflow change.
- Increment PATCH for fixes, documentation, tests, or internal maintenance.

The first release heading in `docs/CHANGELOG.md` is the source version.
`docs/CHANGELOG.md` records every released change.
Keep the README version badge current.
`README.md` release prose is reserved for material installation, compatibility, workflow, or product changes.
Do not duplicate patch-by-patch changelog detail there.
```

Add the source-discovery sentence to `CONTRIBUTING.md` near its sources-of-truth list without
duplicating the policy itself.

- [ ] **Step 4: Finalize `6.4.0` documentation without duplicating release detail**

Move every current `### Unreleased ...` subsection from beneath `6.3` into the new
`## 6.4.0 — 2026-10-02` section, then confirm that section completely covers:

- quick-fix has no reviewers, Verify app, E2E, candidate freeze, or structured final receipts;
- direct focused verification and scope escalation remain mandatory;
- exact three-component SemVer and legacy `6` / `6.MINOR` upgrade compatibility;
- the new per-merged-change versioning and documentation policy; and
- Bash/PowerShell hook and installer parity; and
- the previously unreleased runtime-exec, inactive-worktree, council, verification-policy, review-
  authorization, and reviewer-model-pin changes that first ship in this release.

Keep the README badge and concise `6.4.0` history row added in Task 1. Add one short paragraph near
the main workflow table explaining that quick-fix is the deliberate direct-check path and full
feature/bug workflows retain frozen candidate certification. Do not reproduce hook placement,
regexes, or test details in README.

- [ ] **Step 5: Align detailed workflow and hook references**

In `docs/explanation/workflow.md`, distinguish:

```text
quick-fix: activate -> RED/direct check -> change -> focused check -> version/changelog -> authorized ship
full workflow: plan -> build -> freeze -> paired review -> verify-app/E2E -> authorized ship
```

In `docs/reference/commands.md`, state that quick-fix runs the focused check in the main session and
that the listed review/verification roles belong to feature and bug-fix certification.

In `docs/reference/hooks.md`, state that `check-workflow-gates` preserves shared state/configuration/
authorization checks but exempts only an exact canonical quick-fix from the final receipt set.

- [ ] **Step 6: Run documentation and release GREEN checks**

Run:

```bash
bash tests/template/test-contracts.sh
git diff --check
```

Expected: `test-contracts.sh` exits `0`; changelog and badge report `6.4.0`; the README history row
is concise; agent context contains the complete release policy; no whitespace errors are reported.

- [ ] **Step 7: Inspect the release-policy checkpoint without committing**

```bash
git diff --check
git status --short
git diff -- CONTRIBUTING.md docs/agent-context.md README.md docs/CHANGELOG.md \
    docs/explanation/workflow.md docs/reference/commands.md docs/reference/hooks.md \
    tests/template/test-contracts.sh
```

Do not commit yet; these files belong in the same exact final candidate as the executable changes.

---

### Task 4: Integrate and Certify the Final Candidate

**Files:**
- Verify: all files changed by Tasks 1-3
- Update local evidence only: `.forge/local/` through Forge helpers and receipt writers

**Interfaces:**
- Consumes: exact release `6.4.0`, executable SemVer boundaries, lean quick-fix hook behavior, documentation contracts.
- Produces: staged-clean candidate with focused verification, fast-gate evidence, paired full-workflow reviews, Verify app receipt, exercised E2E user journeys, and exact-tree promotion readiness.

- [ ] **Step 1: Run all focused owning suites together**

Run each command separately:

```bash
bash tests/template/test-setup-flags.sh
bash tests/template/test-runtime-identity.sh
bash tests/template/test-setup.sh
bash tests/template/test-full-refresh.sh
bash tests/template/test-hooks.sh
bash tests/template/test-workflow-parity.sh
bash tests/template/test-resource-discipline.sh
bash tests/template/test-agent-dispatch.sh
bash tests/template/test-codex-workflow-names.sh
bash tests/template/test-workflow-state.sh
bash tests/template/test-worktree-lifecycle.sh
bash tests/template/test-contracts.sh
```

Run `pwsh -NoProfile -File tests/template/test-full-refresh.ps1` when `pwsh` is available. Record an
unavailable local PowerShell runtime honestly; Windows PowerShell 5.1 execution remains CI-owned.

Expected: every executed suite reports zero failures.

- [ ] **Step 2: Run preliminary user-journey E2E while fixes are allowed**

Use `verify-e2e` in feature mode for two executable developer journeys:

1. upgrade a legacy `6.3` installation to `6.4.0`, then verify the runtime identity and preserved
   project-owned content; and
2. attempt ship actions with an exact active `/quick-fix valid-slug`, a malformed quick-fix, and an
   active `/fix-bug` without receipts, proving only the exact quick-fix takes the lean path.

Persist the preliminary report under `.forge/local/` with its unchanged leading `VERDICT:` and
`SUGGESTED_PATH:` headers. Fix any reachable product failure with RED-first coverage before the
final freeze.

- [ ] **Step 3: Run the repository fast gate**

Run:

```bash
bash tests/template/run-fast.sh
```

Expected: `Fast summary` reports all fast suites passed. Do not substitute `run-all.sh`.

- [ ] **Step 4: Run the Forge-owned simplification phase**

Run the repository's configured simplification phase over the complete implementation delta. Apply
only behavior-preserving simplifications, then rerun every affected focused owning test before
continuing. This occurs while mutation is still allowed and before the final candidate freeze.

- [ ] **Step 5: Audit the final release and scope**

Run separately:

```bash
git diff --check
git status --short
rg -n -P 'MAJOR\.MINOR(?!\.PATCH)' setup.sh setup.ps1 scripts hooks tests/template
rg -n -F '^[0-9]+\.[0-9]+$' setup.sh scripts hooks tests/template
rg -n -F '^\d+\.\d+$' setup.ps1 scripts hooks tests/template
rg -n "code-spec|code-quality|verify-app|verify-e2e|--begin-review|closure review|candidate receipt|review iteration" commands/quick-fix.md
```

Expected: no whitespace errors; only intended tracked files changed; no active two-component
source/output validator remains; the quick-fix forbidden-term search returns no matches. Review
historical changelog/spec text separately rather than rewriting history.

- [ ] **Step 6: Stage and freeze one exact full-workflow candidate**

Stage only the approved task files, inspect `git diff --cached --check`, `git diff --cached --stat`,
and `git diff --cached`, then
write the candidate receipt using the repository's existing candidate-fingerprint helper. Confirm
the worktree is staged-clean before review.

- [ ] **Step 7: Run the current full-workflow certification for this branch**

This branch is itself a `/fix-bug`, so it remains subject to the current full workflow even though
it changes future quick-fix behavior. Invoke `workflow-state checkpoint --begin-review`, dispatch
distinct fresh `code-spec` and `code-quality` reviews over the same candidate and iteration, then
run Verify app and the final candidate-bound E2E matrix for both developer journeys from Step 2.
Any candidate mutation invalidates those receipts and requires refreeze plus affected closure
checks.

- [ ] **Step 8: Revalidate and promote the exact certified tree**

Run the repository's verification-receipt check against canonical state and require:

```text
CANDIDATE_VALID:true
REVIEWS_VALID:true
VERIFY_APP_VALID:true
E2E_VALID:true
SHIP_READY:true
```

Create `.forge/local/evidence/lean-quick-fix-workflow/commit-message.txt` with the single line
`fix: streamline quick-fix and version every release` using the normal patch/file-edit tool, then
promote through the repository helper rather than invoking `git commit` directly:

```bash
bash hooks/lib/candidate-fingerprint.sh promote \
    --candidate .forge/local/evidence/lean-quick-fix-workflow/candidate.receipt \
    --state .forge/local/state.md \
    --message-file .forge/local/evidence/lean-quick-fix-workflow/commit-message.txt \
    --promotion-receipt .forge/local/evidence/lean-quick-fix-workflow/promotion.receipt \
    --replay-attempt 0
```

If the helper reports `HOOK_REPLAY_REQUIRED`, refreeze and rerun every affected final gate exactly
once before promoting with `--replay-attempt 1`. After successful promotion, re-run the receipt
check so the promotion receipt keeps `CANDIDATE_VALID:true`, then checkpoint the workflow complete.

Do not push, create a PR, merge, deploy, or delete branches without the corresponding fresh human
authorization.
