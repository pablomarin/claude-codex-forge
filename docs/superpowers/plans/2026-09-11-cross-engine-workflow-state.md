# Cross-Engine Workflow State Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Forge V6 workflow activation and continuation executable through both Claude and Codex without weakening local-state safety controls.

**Architecture:** Add one bounded `workflow-state` command with Bash and PowerShell twins that reuse the canonical state resolver. The command owns only show, atomic activation, and allowlisted checkpoint transitions; canonical workflows call it through identical arguments while the safety hook retains its targeted direct-read and common-write blocks.

**Tech Stack:** Bash 3.2, Windows PowerShell 5.1, Markdown state, Git worktrees, deterministic shell tests.

**Spec:** `docs/superpowers/specs/2026-09-11-cross-engine-workflow-state-design.md`

## Global Constraints

- Preserve one canonical `.forge/` policy with thin Claude and Codex adapters.
- Add no lock, lease, permanent engine owner, generic field setter, or receipt runtime.
- Keep the safety hook's targeted direct `.forge/local` reads and common inline writes blocked.
- Preserve immutable workflow base identity, exact-candidate receipts, mutation invalidation, and promotion gates.
- Keep Bash and PowerShell behavior equivalent and PowerShell 5.1 compatible.
- Follow RED then GREEN for every behavior change and commit only after the owning focused checks.

---

### Task 1: Define the Bounded State Contract in Executable Tests

**Files:**

- Create: `tests/template/test-workflow-state.sh`
- Modify: `tests/template/run-fast.sh`
- Modify: `tests/template/run-all.sh`
- Modify: `tests/template/test-lint.sh`

**Interfaces:**

- Consumes: a real temporary Git repository with `.forge/version`, `.forge/local/state.md`, and the shipped helper paths.
- Produces: behavioral assertions for `show`, `activate`, atomic failure, and platform parity.

- [ ] **Step 1: Write the failing behavior suite**

Create fixtures from `state.template.md`, then invoke the `show` and `activate` interfaces first:

```bash
bash "$REPO_ROOT/hooks/lib/workflow-state.sh" show
bash "$REPO_ROOT/hooks/lib/workflow-state.sh" activate --host claude --workflow quick-fix \
  --task handoff-smoke --base-ref main --phase diagnosis --next-step 'write RED test'
```

The suite accepts `--group show-activate` to run only the Task 1 contract and defaults to `all` once
Task 3 adds checkpoint cases. Register the new shell test in the executable/syntax lists in
`tests/template/test-lint.sh` before the first GREEN claim.

Assert literal identity values, resolved base SHA, the six task-derived receipt paths, an untouched
Council receipt, directory existence, and byte-identical state after rejected input. Add negative
cases for a conflicting active task, invalid slug/ref/host/workflow/value, `|`, CR/LF, outer
whitespace, duplicate table fields, malformed V6 state, a legacy-only state, and a symlinked state
path. Pin that a later review iteration survives identical re-activation. When PowerShell is
present, run the same fixture matrix against the `.ps1` twin. A terminal activation case belongs to
Task 3 because it depends on checkpoint behavior.

- [ ] **Step 2: Run the new suite and observe RED**

Run:

```bash
bash tests/template/test-workflow-state.sh
```

Expected: fail because `hooks/lib/workflow-state.sh` and `.ps1` do not exist.

- [ ] **Step 3: Register the suite**

Add it to `run-fast.sh` and `run-all.sh` so later aggregate verification cannot omit the capability
contract.

### Task 2: Implement `show` and Atomic `activate`

**Files:**

- Create: `hooks/lib/workflow-state.sh`
- Create: `hooks/lib/workflow-state.ps1`
- Modify: `manifests/managed-v6.tsv`
- Modify: `tests/template/test-setup.sh`
- Modify: `tests/template/test-lint.sh`
- Modify: `docs/reference/file-structure.md`

**Interfaces:**

- Consumes: the Task 1 argv contract and canonical V6 state resolved by `state-path`.
- Produces: state on stdout for `show`; an atomically updated state and two task directories for `activate`.

- [ ] **Step 1: Implement the minimal Bash helper**

Source `state-path.sh`; validate literal arguments; use `git rev-parse` to derive the worktree,
Git-common directory, and immutable base SHA. Use one `awk` transform that requires exactly one of
every target row, write a temporary file beside state, recheck the original state hash, validate the
result, then `mv` it into place. Create only the canonical evidence and review task directories after
all validation succeeds.

- [ ] **Step 2: Run the suite to GREEN for Bash show/activate**

Run `bash tests/template/test-workflow-state.sh --group show-activate` and require every Bash
show/activate case to pass.

- [ ] **Step 3: Implement the PowerShell twin**

Use `Get-ForgeStatePath`, literal argument validation, `Resolve-Path`, `git rev-parse`, a line-array
transform with exact row counts, a same-directory temporary file, and `[IO.File]::Replace` or
same-volume move semantics compatible with Windows PowerShell 5.1. Recheck the original state hash
immediately before publication, matching the Bash optimistic concurrency guard.

- [ ] **Step 4: Install both helpers**

Add canonical manifest rows mapping the two source files to
`.forge/hooks/lib/workflow-state.sh` and `.forge/hooks/lib/workflow-state.ps1`.
Extend `tests/template/test-setup.sh` with installed existence, executable-bit, and source-hash
assertions for both platform files. Add the helper pair to `docs/reference/file-structure.md`.
Add both new helper files to the explicit Bash and PowerShell lists in `tests/template/test-lint.sh`.

- [ ] **Step 5: Verify focused behavior and installer ownership**

Run:

```bash
bash tests/template/test-workflow-state.sh
bash tests/template/test-contracts.sh
bash tests/template/test-setup.sh
bash tests/template/test-lint.sh
```

Expected: all exit 0; PowerShell runtime cases may be explicitly skipped only when unavailable.

- [ ] **Step 6: Commit show and activation**

Run `git diff --check`, stage the Task 1 and Task 2 paths, and commit with:

```bash
git commit -m "fix: add bounded workflow state activation"
```

### Task 3: Implement Allowlisted Checkpoints

**Files:**

- Modify: `tests/template/test-workflow-state.sh`
- Modify: `hooks/lib/workflow-state.sh`
- Modify: `hooks/lib/workflow-state.ps1`

**Interfaces:**

- Consumes: `checkpoint --host <claude|codex> --phase <single-line-value> --next-step <single-line-value> [--begin-review]`.
- Produces: atomic updates limited to host, phase, next step, and optionally current iteration plus one.

- [ ] **Step 1: Add and observe failing checkpoint tests**

Assert a normal checkpoint preserves base and receipts byte-for-byte, a host switch updates only the
three named fields, and `--begin-review` changes iteration from `0` to `1` exactly. Assert unknown
options and malformed or duplicate iteration rows fail without mutation. Add a controlled
concurrent-edit fixture by sourcing the helper's bounded publish function, changing state after its
initial hash is captured, and asserting publication fails without overwriting that edit. Checkpoint
to the exact terminal `complete`/`none` values and assert a subsequent activation may replace the
completed workflow—including the same workflow/task tuple—while a non-terminal workflow remains
protected. When PowerShell is available, dot-source its bounded publish function and run the same
concurrent-edit assertion.

- [ ] **Step 2: Implement the minimal Bash checkpoint**

Reuse the validated atomic table transform. Do not accept field names, state paths, receipt paths,
base identity, candidate identity, or a caller-selected iteration.

- [ ] **Step 3: Mirror checkpoint in PowerShell**

Expose the same option grammar, validation, and monotonic increment behavior.

- [ ] **Step 4: Run focused GREEN verification**

Run `bash tests/template/test-workflow-state.sh`; require all available runtime cases to pass.

- [ ] **Step 5: Commit checkpoint behavior**

Run `git diff --check`, stage the Task 3 paths, and commit with:

```bash
git commit -m "fix: add allowlisted workflow checkpoints"
```

### Task 4: Make the Portable Command the Canonical Workflow Surface

**Files:**

- Modify: `tests/template/test-bash-safety.sh`
- Modify: `tests/template/test-workflow-parity.sh`
- Modify: `tests/template/test-contracts.sh`
- Modify: `hooks/check-bash-safety.sh`
- Modify: `hooks/check-bash-safety.ps1`
- Modify: `hooks/check-state-updated.sh`
- Modify: `hooks/check-state-updated.ps1`
- Modify: `hooks/session-start.sh`
- Modify: `hooks/session-start.ps1`
- Modify: `tests/template/test-hooks.sh`
- Modify: `tests/template/test-session-start.sh`
- Modify: `tests/template/test-state-roundtrip.sh`
- Modify: `rules/workflow.md`
- Modify: `commands/new-feature.md`
- Modify: `commands/fix-bug.md`
- Modify: `commands/quick-fix.md`
- Modify: `state.template.md`
- Modify: `FORGE.template.md`

**Interfaces:**

- Consumes: installed `.forge/hooks/lib/workflow-state` helpers.
- Produces: one literal cross-host activation/checkpoint mechanism and actionable safety-hook guidance.

- [ ] **Step 1: Add failing consumer and safety tests**

Require literal helper invocations to pass the real safety hook while direct `cat`, `rg`, `mkdir`,
redirects, chains, and the hook's existing targeted mutation forms remain blocked. Require all three
workflows and the canonical rule to name `show`, `activate`, `checkpoint`, activation-first ordering,
and `--begin-review` before review dispatch. Require Stop and session-start reminders to use
`workflow-state show`. Add negative assertions removing instructions to read
`.forge/local/state.md` directly or use host-native tools for workflow-state transitions from the
three workflows, `rules/workflow.md`, and `FORGE.template.md`.

- [ ] **Step 2: Observe RED**

Run:

```bash
bash tests/template/test-bash-safety.sh
bash tests/template/test-workflow-parity.sh
bash tests/template/test-contracts.sh
bash tests/template/test-hooks.sh
bash tests/template/test-session-start.sh
bash tests/template/test-state-roundtrip.sh
```

Expected: helper allow cases pass already, while canonical consumer requirements fail.

- [ ] **Step 3: Update canonical workflow surfaces**

Replace host-native state-read/write instructions with the bounded helper for workflow transitions.
Keep native file tools for checklist narrative and non-state artifacts. Make activation the first
post-discovery action, define `checkpoint --phase complete --next-step none` as the terminal
transition that permits the next activation, and use `checkpoint --begin-review` before each paired
final review. Update both Stop reminders and session-start to point to `workflow-state show`.

- [ ] **Step 4: Correct safety-hook remediation**

For canonical state reads, direct users to `workflow-state show`. For canonical workflow-state
writes, direct users to `activate` or `checkpoint`; retain native Write/Edit guidance for other local
artifacts. Add no bypass branch and do not expand the hook's documented LEAN coverage.

- [ ] **Step 5: Run focused GREEN verification**

Run all six Step 2 suites plus `bash tests/template/test-lint.sh`; require all to exit 0.

- [ ] **Step 6: Commit canonical workflow integration**

Run `git diff --check`, stage the Task 4 paths, and commit with:

```bash
git commit -m "fix: use portable workflow state transitions"
```

### Task 5: Qualify Installation and the Real Host Handoff

**Files:**

- Modify: `docs/CHANGELOG.md`
- Modify: `README.md`

**Interfaces:**

- Consumes: a fresh disposable installation of the final candidate and authenticated native clients.
- Produces: automated aggregate evidence and a local live-handoff receipt; no downstream source mutation.

- [ ] **Step 1: Document the corrected capability boundary**

Record in the existing CHANGELOG 6.2 section and README version-history row that V6.2 adds the
bounded state command, retains targeted local-state shell denial, and requires installed-host
qualification. Do not claim PowerShell runtime proof unless it ran.

- [ ] **Step 2: Run focused and aggregate verification**

Run:

```bash
bash tests/template/test-workflow-state.sh
bash tests/template/run-fast.sh
bash tests/template/run-all.sh
git diff --check
```

Expected: all executable suites exit 0 and the diff check is clean.

- [ ] **Step 3: Install into a fresh disposable downstream clone**

Run `setup.sh --upgrade` from the source worktree, verify the managed helper hashes, and confirm the
real downstream repository remains unchanged.

- [ ] **Step 4: Run the decisive Claude-to-Codex handoff**

Have real Claude invoke activation before discretionary investigation or tracked mutation. Stop at
a persisted RED checkpoint, then launch a fresh real Codex process in the same physical worktree to
run `show` and `checkpoint`. Assert preserved base SHA, iteration, candidate fingerprint, index tree,
and exact next step except for allowlisted checkpoint fields. Confirm the safety hook's tested direct
local-state forms are still blocked and candidate mutation invalidates bound receipts.

- [ ] **Step 5: Record proof limits**

If Claude CLI or PowerShell is unavailable, label those exact dimensions unverified rather than
substituting static tests. A Claude Desktop run may prove its own client surface but not Claude CLI.

- [ ] **Step 6: Commit release documentation**

Run `git diff --check`, stage `docs/CHANGELOG.md` and `README.md`, and commit with:

```bash
git commit -m "docs: describe portable Forge 6.2 state handling"
```
