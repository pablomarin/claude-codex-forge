# Forge V6 Strict Receipt Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make structured candidate-bound receipts unavoidable for active Forge V6 workflows while preserving honest E2E N/A evidence and Codex-to-Claude worktree continuation.

**Architecture:** Canonical V6 state, not population of one receipt-path cell, selects the structured evidence path in the ship hook, Stop evidence builder, and convergence breaker. The existing receipt helper remains the single validator and gains a candidate-bound E2E N/A result; canonical workflow prose supplies exact state transitions while host adapters remain thin.

**Tech Stack:** Bash 3.2, Windows PowerShell 5.1, Markdown state and workflow contracts, Git worktrees, deterministic shell test suites.

**Spec:** `docs/superpowers/specs/2026-09-10-v6-strict-receipt-workflow-design.md`

## Global Constraints

- Preserve one canonical `.forge/` policy with thin Claude and Codex adapters.
- Keep Bash and PowerShell behavior equivalent; use only PowerShell 5.1 syntax.
- Keep the direct documentation-only commit carve-out; never extend it to push or PR creation.
- Treat `Last active host` and receipt `main_host` as routing/audit metadata, never a lease.
- Never allow V6 placeholder, missing, stale, mixed-candidate, or non-clean receipts to fall through to legacy certification.
- Keep V5, mixed, custom, and unknown project reconciliation behind the read-only full-refresh preview.
- Follow RED then GREEN for each behavior change and run `git diff --check` before every commit.

---

### Task 1: Represent E2E N/A as Candidate-Bound Evidence

**Files:**

- Modify: `tests/template/test-build-evidence.sh`
- Modify: `hooks/lib/verification-receipt.sh`
- Modify: `hooks/lib/verification-receipt.ps1`
- Modify: `agents/verify-e2e.md`
- Modify: `rules/testing.md`

**Interfaces:**

- Consumes: candidate receipt schema version 2 and verifier report files under `.forge/local/`.
- Produces: `verification-receipt write --kind e2e --result N/A` and its PowerShell equivalent; report header `VERDICT: N/A` followed by `N/A_REASON: ` and a concrete reason.
- Preserves: `verify-app` successful certification requires `PASS`; E2E `PASS` remains unchanged.

- [ ] **Step 1: Add failing Bash receipt tests**

Extend the receipt-v2 fixture in `tests/template/test-build-evidence.sh` with these behaviors:

```bash
printf 'VERDICT: N/A\nN/A_REASON: internal harness-only change with no user surface\n' \
    > "$V2/.forge/local/evidence/e2e-na.report"
(cd "$V2" && bash "$REPO_ROOT/hooks/lib/verification-receipt.sh" write --kind e2e \
    --candidate .forge/local/evidence/candidate.receipt --command 'e2e scope decision' \
    --profile regression --report .forge/local/evidence/e2e-na.report --result N/A \
    --exit-status 0 --output .forge/local/evidence/e2e.receipt)
assert_equals "$?" "0" "candidate-bound E2E N/A receipt is written"
```

After writing the other current receipts, assert `verification-receipt check` emits
`E2E_VALID:true` and `SHIP_READY:true`. Add negative cases for an empty `N/A_REASON`, a
`VERDICT: N/A` verify-app report, and `--result N/A` with nonzero exit status; each must exit 2.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
bash tests/template/test-build-evidence.sh
```

Expected: FAIL because `N/A` is not an accepted receipt result or E2E report verdict.

- [ ] **Step 3: Implement the Bash N/A contract**

In `hooks/lib/verification-receipt.sh`:

- extend `vr_report_verdict` to accept only `e2e:N/A` in addition to existing pairs;
- add a reader that requires the second line to match `^N/A_REASON: .+[^[:space:]]$` for N/A;
- allow `N/A` only when `kind=e2e` and `exit-status=0`;
- keep verify-app PASS-only in `vr_validate_verifier`;
- allow E2E validation when result and report verdict are both `PASS`, or both `N/A` with a valid
  reason;
- keep report hashing and candidate identity checks unchanged so the reason is bound by the receipt.

The validation branch should have this shape:

```bash
result=$(vr_kv "$receipt" result)
report_verdict=$(vr_kv "$receipt" report_verdict)
case "$kind:$result:$report_verdict" in
    verify-app:PASS:PASS|e2e:PASS:PASS) ;;
    e2e:N/A:N/A) vr_e2e_na_reason "$report" >/dev/null || return 1 ;;
    *) return 1 ;;
esac
```

- [ ] **Step 4: Mirror the implementation in PowerShell 5.1**

Update both the script parameter validation and `Invoke-VerificationReceipt` argument validation to
accept `N/A`. In `Get-ReportVerdict`, accept `N/A` only for E2E. Add
`Get-E2eNaReason([string]$Path)` that reads the second line, requires a non-empty value after
`N/A_REASON:`, and throws otherwise. In `Test-Verifier`, use the same three accepted
kind/result/verdict combinations as Bash.

- [ ] **Step 5: Align the canonical verifier and testing documentation**

In `agents/verify-e2e.md`, add `N/A` to the verdict enumeration only for a proven non-user-facing
scope and require this exact leading report shape:

```text
VERDICT: N/A
N/A_REASON: internal-only change with no supported user journey
```

In `rules/testing.md`, replace the prose-only N/A certification claim with the requirement that the
checklist reason and candidate-bound E2E N/A report/receipt agree. Keep the existing narrow
eligibility examples.

- [ ] **Step 6: Run focused GREEN verification**

Run:

```bash
bash tests/template/test-build-evidence.sh
```

Then run:

```bash
bash tests/template/test-lint.sh
```

Expected: both suites exit 0. If `pwsh` is unavailable, record PowerShell execution as CI-owned;
static paired-file and syntax contracts must still pass.

- [ ] **Step 7: Commit the E2E evidence contract**

```bash
git add tests/template/test-build-evidence.sh hooks/lib/verification-receipt.sh hooks/lib/verification-receipt.ps1 agents/verify-e2e.md rules/testing.md
git commit -m "fix: bind e2e n-a to v6 candidates"
```

---

### Task 2: Make V6 Ship Gates Strict by Schema

**Files:**

- Modify: `tests/template/test-hooks.sh`
- Modify: `hooks/check-workflow-gates.sh`
- Modify: `hooks/check-workflow-gates.ps1`

**Interfaces:**

- Consumes: canonical state selected by `state-path` and an active `## Workflow` command.
- Produces: a shipping decision that always evaluates the complete structured receipt set for V6.
- Preserves: PR authorization and convergence checks run before shipping; docs-only direct commits
  can exit through the existing carve-out.

- [ ] **Step 1: Add failing strict-activation tests**

Add installed-V6 fixtures to `tests/template/test-hooks.sh` for:

1. A push with all legacy checklist rows checked but `Candidate receipt` and the other receipt cells
   still containing template markers. Assert exit 2, `final receipt set is missing`, and receipt
   initialization guidance.
2. A push whose active V6 state has no `## Receipts` block. Assert exit 2 and the same guidance.
3. A direct docs-only commit whose active V6 state links a missing candidate receipt. Assert exit
   0, proving the carve-out precedes strict receipt validation.
4. A push from that same docs-only fixture. Assert exit 2.
5. The existing complete receipt-v2 fixture. Assert it still exits 0.

Use `cwd`, `host`, and `tool_input.command` in every hook payload so the installed worktree boundary
is exercised.

- [ ] **Step 2: Run the hook test and verify RED**

Run:

```bash
bash tests/template/test-hooks.sh
```

Expected: the placeholder and missing-table pushes exit 0 through legacy checklist evaluation, and
the docs-only commit with explicit but incomplete receipt linkage fails because validation currently
occurs before its carve-out.

- [ ] **Step 3: Implement unconditional Bash V6 receipt validation**

Move the receipt validation block in `hooks/check-workflow-gates.sh` to immediately after the
docs-only commit carve-out. Replace candidate-cell activation with:

```bash
RECEIPT_V2_ACTIVE=true
VR="$HOOK_DIR/lib/verification-receipt.sh"
[ -f "$VR" ] || VR="$_TOPLEVEL/hooks/lib/verification-receipt.sh"
if [ ! -f "$VR" ] || ! VR_OUT=$(bash "$VR" check --state "$STATE_FILE" 2>&1); then
    echo "WORKFLOW GATE: final receipt set is missing, stale, mixed-candidate, or non-clean." >&2
    printf '%s\n' "${VR_OUT:-verification-receipt helper unavailable}" >&2
    echo "Initialize the V6 receipt paths and Review iteration, freeze the staged-clean candidate, then rerun both review lenses, verify-app, and E2E." >&2
    exit 2
fi
```

Keep `RECEIPT_V2_ACTIVE=true` so later compatibility-only checklist evidence branches cannot run.
Do not add an evidence-mode state field.

- [ ] **Step 4: Mirror the strict gate in PowerShell**

Move the PowerShell receipt block after `Test-IsDocPath` and its direct-commit carve-out. Set
`$ReceiptV2Active = $true` for canonical active V6 state, invoke
`Invoke-VerificationReceipt -ReceiptMode check`, and emit remediation text equivalent to Bash.
Do not depend on `Candidate receipt` contents to select the path.

- [ ] **Step 5: Run focused GREEN verification**

Run:

```bash
bash tests/template/test-hooks.sh
```

Then run:

```bash
bash tests/template/test-lint.sh
```

Expected: both exit 0, with PowerShell runtime cases executing only when a compatible executable is
installed.

- [ ] **Step 6: Commit the ship-gate correction**

```bash
git add tests/template/test-hooks.sh hooks/check-workflow-gates.sh hooks/check-workflow-gates.ps1
git commit -m "fix: require receipts for active v6 shipping"
```

---

### Task 3: Remove Legacy Fallback from Stop Evidence and Review Accounting

**Files:**

- Modify: `tests/template/test-build-evidence.sh`
- Modify: `tests/template/test-review-breaker.sh`
- Modify: `hooks/build-evidence.sh`
- Modify: `hooks/build-evidence.ps1`
- Modify: `hooks/lib/review-breaker.sh`
- Modify: `hooks/lib/review-breaker.ps1`

**Interfaces:**

- Consumes: first-line V6 schema marker, canonical state path, workflow command, and structured
  receipt checker output.
- Produces: Stop evidence with false candidate/reviewer/verifier gates until current receipts exist;
  convergence certification based only on structured V6 review receipts.
- Preserves: legacy clean-row accounting only for a genuinely non-V6 state read by the compatibility
  helper.

- [ ] **Step 1: Add failing Stop-evidence tests**

Create an active canonical V6 fixture with fully clean legacy Codex/PR-toolkit rows and placeholder
receipt paths. Run the real `build-evidence.sh` and assert:

```bash
assert_contains "$V2/evidence-placeholder.out" '"reviewer_gate":{"clean_same_iteration":false' \
    "V6 Stop evidence ignores legacy clean rows before receipt linkage"
assert_contains "$V2/evidence-placeholder.out" '"candidate_gate":{"staged_clean":false' \
    "V6 Stop evidence reports the missing candidate"
assert_contains "$V2/evidence-placeholder.out" '"all_receipts_same_candidate":false' \
    "V6 Stop evidence never marks placeholder receipts clean"
```

- [ ] **Step 2: Add failing convergence-breaker tests**

In `tests/template/test-review-breaker.sh`, add a canonical V6 state with legacy clean rows and
placeholder receipts. Assert `CERTIFIED:no`. Keep an equivalent legacy `.claude/local/state.md`
fixture and assert its historical clean rows still produce `CERTIFIED:yes` when the helper is
invoked directly for compatibility.

- [ ] **Step 3: Run both tests and verify RED**

Run:

```bash
bash tests/template/test-build-evidence.sh
```

Run separately:

```bash
bash tests/template/test-review-breaker.sh
```

Expected: V6 placeholder fixtures incorrectly consume legacy rows and fail the new assertions.

- [ ] **Step 4: Make Stop evidence schema-driven in Bash and PowerShell**

Extend `parse_workflow` and `Parse-Workflow` to return the canonical `Command` value. Define active
V6 as V6 state with command not empty, `none`, em dash, or hyphen. For active V6, initialize
`RECEIPT_GATE_OK`/`$ReceiptGateOk` false and invoke the receipt checker regardless of candidate cell
contents. Populate structured fields only from checker sentinels. Never restore reviewer clean from
legacy rows after active V6 classification.

- [ ] **Step 5: Make convergence certification schema-driven**

In both review-breaker implementations, derive V6 mode from the exact first-line marker
`<!-- forge:state-schema v6 -->`. When true, run only `verification-receipt check`; missing or
invalid receipts leave `CERTIFIED:no`. Run the Codex/PR-toolkit row reader only when the marker is
absent. Remove candidate-path-based `V2_ACTIVE` selection.

- [ ] **Step 6: Add the cross-host characterization and mutation cases**

Using the complete receipt fixture, write review receipts with `main_host=codex`, set
`Last active host` to `claude`, retain the same base SHA, review iteration, next step, and candidate,
then assert `verification-receipt check` and the ship hook both pass. Change only `Last active host`
back to `codex` and assert the candidate identity is unchanged. Then mutate `app.txt` and assert the
same receipts fail. This characterization should pass before production edits except where the new
strict classification is involved; it protects continuation while the classification changes.

- [ ] **Step 7: Run focused GREEN verification**

Run:

```bash
bash tests/template/test-build-evidence.sh
```

Run:

```bash
bash tests/template/test-review-breaker.sh
```

Run:

```bash
bash tests/template/test-lint.sh
```

Expected: all three exit 0.

- [ ] **Step 8: Commit the unified V6 evidence classification**

```bash
git add tests/template/test-build-evidence.sh tests/template/test-review-breaker.sh hooks/build-evidence.sh hooks/build-evidence.ps1 hooks/lib/review-breaker.sh hooks/lib/review-breaker.ps1
git commit -m "fix: unify v6 receipt classification"
```

---

### Task 4: Restore Explicit Workflow State Transitions

**Files:**

- Modify: `tests/template/test-workflow-parity.sh`
- Modify: `tests/template/test-state-roundtrip.sh`
- Modify: `tests/template/test-contracts.sh`
- Modify: `rules/workflow.md`
- Modify: `commands/new-feature.md`
- Modify: `commands/fix-bug.md`
- Modify: `commands/quick-fix.md`
- Modify: `state.template.md`
- Modify: `FORGE.template.md`

**Interfaces:**

- Consumes: task-local receipt directory, immutable workflow base SHA, dispatcher receipt paths,
  verifier receipt writer, and candidate promotion helper.
- Produces: one canonical, explicit activation-to-promotion state machine shared by Claude and Codex.

- [ ] **Step 1: Add failing workflow contract tests**

For each development workflow, require these exact semantic stems in
`tests/template/test-workflow-parity.sh`:

```text
Review iteration | 0
populate every receipt path
before production implementation
increment `Review iteration` before
same candidate
Any candidate mutation
```

Require `code-spec` and `code-quality` in `quick-fix.md`, not only the other two workflows. In
`test-state-roundtrip.sh`, require iteration zero and explicit cross-host retention of base SHA,
iteration, next step, and candidate linkage. In `test-contracts.sh`, require the strict V6 wording
in `FORGE.template.md` and reject “Candidate receipt activates receipt-v2” from active canonical
sources.

- [ ] **Step 2: Run contract tests and verify RED**

Run:

```bash
bash tests/template/test-workflow-parity.sh
```

Run:

```bash
bash tests/template/test-state-roundtrip.sh
```

Run:

```bash
bash tests/template/test-contracts.sh
```

Expected: failures for absent initialization/iteration stems and quick-fix's missing paired final
review contract.

- [ ] **Step 3: Add the canonical state-transition protocol**

In `rules/workflow.md`, add a concise numbered subsection that owns activation, plan-before-code,
preliminary E2E, freeze, pre-dispatch iteration increment, paired review, verifier receipt, mutation
invalidation, and exact promotion. State that V6 schema selects structured evidence immediately;
receipt population is state progress, not mode activation.

- [ ] **Step 4: Make each development workflow invoke the protocol explicitly**

At workflow activation, require a task-local directory, concrete receipt paths, and
`Review iteration | 0`. At the plan-to-implementation boundary in `new-feature` and `fix-bug`, state
that production implementation cannot begin before clean plan evidence. At finalization, require the
iteration increment before dispatch. In `quick-fix`, require both final review lenses and allow them
to run concurrently.

Do not copy the entire canonical protocol into every command. Each command states its phase-specific
transition and points to `rules/workflow.md` for the shared invariant.

- [ ] **Step 5: Align state and root policy**

Change the state template's default review iteration from a template marker to `0`. Explain that
all receipt paths are populated at workflow activation and that switching hosts retains base SHA,
iteration, next step, and unchanged candidate linkage. In `FORGE.template.md`, state that every
active canonical V6 shipping action requires the current structured receipt set and cannot be
certified by legacy prose.

- [ ] **Step 6: Run focused GREEN verification**

Run the same three commands from Step 2. Expected: all exit 0.

- [ ] **Step 7: Commit the workflow rails**

```bash
git add tests/template/test-workflow-parity.sh tests/template/test-state-roundtrip.sh tests/template/test-contracts.sh rules/workflow.md commands/new-feature.md commands/fix-bug.md commands/quick-fix.md state.template.md FORGE.template.md
git commit -m "fix: restore explicit v6 workflow transitions"
```

---

### Task 5: Publish the Forge 6.2 Upgrade Contract

**Files:**

- Modify: `docs/CHANGELOG.md`
- Modify: `README.md`
- Modify: `tests/template/test-contracts.sh`

**Interfaces:**

- Consumes: the installer version derived from the top numeric changelog heading.
- Produces: synchronized Forge version `6.2` in changelog, README badge, and first version-history
  row.

- [ ] **Step 1: Change the version contract test first**

Set `EXPECTED_FORGE_VERSION='6.2'`, require the first changelog heading to equal
`## 6.2 — 2026-09-10`, and require the first README history row to describe strict V6 structured
receipts plus preserved cross-host continuation.

- [ ] **Step 2: Run the contract test and verify RED**

Run:

```bash
bash tests/template/test-contracts.sh
```

Expected: FAIL because the published surfaces still report 6.1.

- [ ] **Step 3: Add the 6.2 release notes and README row**

Prepend a 6.2 changelog section covering:

- mandatory schema-selected V6 receipt evaluation across ship, Stop, and breaker consumers;
- structured candidate-bound E2E N/A;
- explicit review iteration and phase transitions;
- unchanged Codex-to-Claude and Claude-to-Codex same-worktree continuation;
- V6.0/V6.1 ordinary upgrade and V5/mixed/custom/unknown full-refresh-preview routing;
- honest local PowerShell qualification boundary.

Change the README badge to 6.2 and prepend a matching concise version-history row.

- [ ] **Step 4: Run the contract test and verify GREEN**

Run:

```bash
bash tests/template/test-contracts.sh
```

Expected: exit 0 with synchronized 6.2 surfaces.

- [ ] **Step 5: Commit the release contract**

```bash
git add docs/CHANGELOG.md README.md tests/template/test-contracts.sh
git commit -m "docs: publish Forge 6.2 receipt enforcement"
```

---

### Task 6: Final Integration and Evidence Review

**Files:**

- Verify: every file changed by Tasks 1-5

**Interfaces:**

- Consumes: the completed implementation and committed test history.
- Produces: fresh focused, fast, aggregate, and diff evidence for the exact final source bytes.

- [ ] **Step 1: Run focused owning suites**

Run each separately:

```bash
bash tests/template/test-build-evidence.sh
bash tests/template/test-hooks.sh
bash tests/template/test-review-breaker.sh
bash tests/template/test-workflow-parity.sh
bash tests/template/test-state-roundtrip.sh
bash tests/template/test-contracts.sh
```

Expected: each exits 0.

- [ ] **Step 2: Run the ordinary local integration gate**

```bash
bash tests/template/run-fast.sh
```

Expected: `All fast suites passed`.

- [ ] **Step 3: Run the exhaustive integration boundary once**

```bash
bash tests/template/run-all.sh
```

Expected: `All suites passed`. If an authenticated engine or Windows runtime boundary is not
available, report the exact skipped qualification instead of translating it into a pass.

- [ ] **Step 4: Inspect final repository integrity**

Run:

```bash
git diff --check main...HEAD
```

Run:

```bash
git status --short --branch
```

Run:

```bash
git log --oneline main..HEAD
```

Expected: no whitespace errors, no unintended uncommitted files, and only the design plus scoped
implementation commits on the feature branch.

- [ ] **Step 5: Review the final diff against the spec**

Confirm every acceptance criterion in the design has a named executable test. Check that no host
adapter gained duplicated canonical policy and no transitional candidate-path activation comment
remains in active V6 consumers.

- [ ] **Step 6: Prepare the integration handoff**

Summarize exact test counts, unavailable runtime boundaries, branch/worktree path, commits, and the
upgrade consequence. Do not push, open a PR, merge, or clean up without the separate human action
required by the repository workflow.
