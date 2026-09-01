# Forge 6 Upgrade Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give v5 and mixed Forge repositories a read-only migration preview and a transactional path to exactly one active v6 harness without deleting uncertain project content.

**Architecture:** Keep the existing Python full-refresh transaction as the single migration engine. Add a no-write execution mode and a deterministic inventory phase that accumulates ownership/collision findings before staging; then reuse the existing materializer, journal, backup, no-clobber, and rollback paths for execution. Bash and PowerShell remain thin, behaviorally equivalent entry points.

**Tech Stack:** Bash 3.2+, Windows PowerShell 5.1, Python 3.9+ standard library, TSV/JSON manifests, deterministic shell fixtures.

**Spec:** `docs/superpowers/specs/2026-08-31-forge-v6-upgrade-hardening-design.md`

## Global Constraints

- `setup.sh -f` / `setup.ps1 -Force` refresh existing v6 and continue to refuse v5 or mixed legacy ownership.
- Preview is `setup.sh -F --dry-run` on Unix and `setup.ps1 -FullRefresh -DryRun` on Windows; `-R` remains the Windows alias for `-FullRefresh`.
- Dry-run and execution use the same planner, but execution repeats discovery under the transaction guard.
- Dry-run writes no project/global file, guard, backup, report, journal, or stamp.
- Successful execution leaves exactly one active filesystem Forge and writes `.forge/version` last.
- Unknown/project-owned content is preserved; modified or colliding active content is reported and blocks before live mutation.
- Independently installed plugin overlap may allow materialization but keeps the affected host `RUNTIME_READY: BLOCKED`.
- Do not add a runtime dependency, semantic/LLM merge, or project-specific deletion rule.
- Every Bash behavior has a PowerShell 5.1 twin; local PowerShell execution is not claimed when unavailable.
- Use focused suites while iterating and run `tests/template/run-all.sh` once on the frozen final candidate.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `setup.sh`, `setup.ps1` | Public flags, flag compatibility, routing, and user-facing legacy redirect. |
| `scripts/full-refresh.sh`, `scripts/full-refresh.ps1` | Canonical-root/platform validation and thin forwarding of dry-run intent. |
| `scripts/merge-settings.py` | Shared inventory, report, staging, transaction, rollback, and dry-run engine. |
| `manifests/legacy-v5-aliases.tsv` | Version-bound fingerprints for observed content-identical legacy cross-host copies. |
| `tests/template/test-full-refresh.sh`, `test-full-refresh.ps1` | Behavioral migration, no-write, ownership, collision, state, and transaction fixtures. |
| `tests/template/test-dual-layout.sh` | Parseability and historical truthfulness of the alias manifest. |
| `tests/template/test-contracts.sh` | Public CLI/documentation parity and no-retired-command contract. |
| `README.md`, `docs/guides/getting-started.md`, `docs/guides/setup-scenarios.md`, `docs/guides/upgrading.md`, `docs/reference/commands.md`, `docs/troubleshooting.md` | One current, user-facing upgrade story. |

### Task 1: Add a true no-write full-refresh preview

**Files:**
- Modify: `setup.sh:20-140`
- Modify: `setup.ps1:6-115`
- Modify: `scripts/full-refresh.sh:1-52`
- Modify: `scripts/full-refresh.ps1:1-67`
- Modify: `scripts/merge-settings.py:1221-1401`
- Test: `tests/template/test-full-refresh.sh`
- Test: `tests/template/test-full-refresh.ps1`

**Interfaces:**
- Produces: `full_refresh(repo_root: Path, target: Path, scope: str, platform: str, dry_run: bool = False) -> None`.
- Produces: immutable `UpgradeFinding(code, scope, path, detail, resolution)` records and
  `print_refresh_report(report, findings, upgrade, active_forge, next_step) -> None`.
- Produces: `merge-settings.py full-refresh --dry-run` and wrapper-level `--dry-run` / `-DryRun` forwarding.
- Preserves: the existing execution journal schema and recovery interface unchanged.

- [ ] **Step 1: Write the failing Bash CLI and no-write tests**

Add a local snapshot helper and one exact-v5 preview case to `test-full-refresh.sh`:

```bash
snapshot_project() {
    local root="$1"
    (
        cd "$root" || exit 1
        find . -path './.git' -prune -o -type f -print0 \
            | LC_ALL=C sort -z \
            | while IFS= read -r -d '' file; do
                printf '%s\t%s\n' "$file" "$(hash_file "$file")"
            done
    )
}

start_test "full-refresh dry-run uses the real planner without target writes"
S_DRY=$(scratch_dir full-refresh-dry-run)
make_git_repo "$S_DRY"
mkdir -p "$S_DRY/.claude/local"
mkdir -p "$S_DRY/.fakehome"
printf '5.61\n' > "$S_DRY/.claude/.forge-version"
write_active_v5_state "$S_DRY" "DRY_RUN_STATE"
before=$(snapshot_project "$S_DRY")
run_refresh "$S_DRY" "$S_DRY.preview.log" -F --dry-run
assert_equals "$?" "0" "exact v5 preview is ready"
after=$(snapshot_project "$S_DRY")
assert_equals "$after" "$before" "dry-run leaves every target file byte-identical"
assert_file_missing "$S_DRY/.forge/version" "dry-run writes no v6 stamp"
assert_contains "$S_DRY.preview.log" "UPGRADE: READY" "preview has a final readiness summary"
assert_contains "$S_DRY.preview.log" "ACTIVE_FORGE: unchanged" "preview does not claim mutation"
```

Add a global preview using a disposable `HOME`; assert its complete file snapshot is unchanged and
no `.forge/version` is created. Add flag assertions that `--dry-run` without `-F` fails and that
`-f -F --dry-run` remains invalid. Invoke `-f` against a stamped v5 fixture and require its blocked
message to point directly to `-F --dry-run` (and `-FullRefresh -DryRun` in the PowerShell contract).

- [ ] **Step 2: Write the failing PowerShell no-write test**

In `test-full-refresh.ps1`, capture all non-`.git` file hashes before and after `@("-R", "-DryRun")`; assert exit zero, no `.forge\version`, unchanged hashes, and `UPGRADE: READY`. Add a direct assertion that `-DryRun` without `-FullRefresh` returns nonzero.

- [ ] **Step 3: Run the focused suites to verify RED**

Run:

```bash
bash tests/template/test-full-refresh.sh
```

Expected: the new preview assertions fail because `--dry-run` is unknown or executes a live refresh. On Windows CI, `test-full-refresh.ps1` fails because `-DryRun` is undefined.

- [ ] **Step 4: Add the public flags and wrapper forwarding**

In `setup.sh`, add `DRY_RUN=false`, parse `--dry-run`, reject it unless `FULL_REFRESH=true`, document it in help, and pass it only to `scripts/full-refresh.sh`:

```bash
refresh_args=(--target "$(pwd -P)" --scope project)
[ "$DRY_RUN" = true ] && refresh_args+=(--dry-run)
bash "$refresh_helper" "${refresh_args[@]}"
```

Use the corresponding global target when `GLOBAL=true`. In `setup.ps1`, add `[switch]$DryRun`, reject `$DryRun -and -not $FullRefresh`, and append `-DryRun` to the helper call only when selected. Add `[switch]$DryRun` to `scripts/full-refresh.ps1`; parse `--dry-run` in `scripts/full-refresh.sh`; forward `--dry-run` to Python.
Change ordinary v5 preflight guidance in both installers to recommend preview first rather than live
`-F`/`-R` execution.

- [ ] **Step 5: Separate preview staging from live transaction metadata**

In `merge-settings.py`, import `dataclasses` and `tempfile`, define the final finding/report
interface, add the `dry_run` parameter and CLI flag, and choose work roots as follows:

```python
@dataclasses.dataclass(frozen=True, order=True)
class UpgradeFinding:
    code: str
    scope: str
    path: str
    detail: str
    resolution: str


def print_refresh_report(
    report: dict[str, list[str]],
    findings: tuple[UpgradeFinding, ...],
    *,
    upgrade: str,
    active_forge: str,
    next_step: str,
) -> None:
    for category in report:
        entries = sorted(set(report[category]))
        print(f"{category}: (none)" if not entries else "\n".join(f"{category}: {entry}" for entry in entries))
    for finding in findings:
        print(
            f"BLOCKED: code={finding.code} scope={finding.scope} path={finding.path} "
            f"detail={finding.detail} resolution={finding.resolution}"
        )
    print(f"UPGRADE: {upgrade}")
    print(f"ACTIVE_FORGE: {active_forge}")
    print(
        "CHANGES: "
        f"created={len(set(report['CREATED']))} rewritten={len(set(report['REWRITTEN']))} "
        f"deleted={len(set(report['DELETED']))} preserved={len(set(report['PRESERVED']))}"
    )
    print(f"BLOCKERS: {len(findings)}")
    print(f"NEXT_STEP: {next_step}")
```

Choose work roots as follows:

```python
temporary = None
guard: Optional[Path] = None
if dry_run:
    temporary = tempfile.TemporaryDirectory(prefix="forge-full-refresh-preview-")
    work_root = Path(temporary.name)
else:
    guard = acquire_guard(target, txid)
    work_root = target / ".forge/local/migration-staging" / txid
stage = work_root / "stage"
quarantine = work_root / "quarantine"
```

Build and validate the staged candidate in both modes. Before backup/journal creation, branch preview through the common report renderer:

```python
if dry_run:
    print_refresh_report(
        report,
        (),
        upgrade="READY",
        active_forge="unchanged",
        next_step="run full refresh without --dry-run",
    )
    return
```

Only execution creates `backup_root`, `journal_path`, the persistent migration report, or calls `apply_operations`. In `finally`, clean the temporary directory and call `shutil.rmtree(guard, ignore_errors=True)` only when `guard is not None`.
After a committed execution, call the same renderer with `UPGRADE: READY`, `ACTIVE_FORGE: v6`, and
`NEXT_STEP: review per-host RUNTIME_READY diagnostics`; retain `INSTALLATION: MATERIALIZED` as the
filesystem-status line immediately before that summary.

- [ ] **Step 6: Run focused GREEN and commit**

Run:

```bash
bash tests/template/test-full-refresh.sh
bash tests/template/test-contracts.sh
git diff --check
```

Expected: all pass; PowerShell behavioral execution remains Windows-CI-owned if unavailable locally.

Commit:

```bash
git add setup.sh setup.ps1 scripts/full-refresh.sh scripts/full-refresh.ps1 scripts/merge-settings.py tests/template/test-full-refresh.sh tests/template/test-full-refresh.ps1
git commit -m "feat: preview Forge full refresh without writes"
```

### Task 2: Inventory every ownership blocker before staging

**Files:**
- Modify: `scripts/merge-settings.py:42-850`
- Modify: `scripts/merge-settings.py:1221-1401`
- Test: `tests/template/test-full-refresh.sh`
- Test: `tests/template/test-full-refresh.ps1`

**Interfaces:**
- Consumes: Task 1 `UpgradeFinding` and `print_refresh_report`.
- Produces `LegacyInventory(selector, region_selector, recognized, proven_legacy, findings)`.
- Produces `inventory_legacy(repo_root: Path, target: Path, scope: str, platform: str) -> LegacyInventory`.
- Consumed by: Task 3 root/native/state discovery and the shared preview/execution path.

- [ ] **Step 1: Write a multi-blocker RED fixture**

Create a stamped v5.61 scratch project with two one-byte-modified released hooks, malformed `.claude/settings.json`, and an untouched sentinel file. Preview must return nonzero, print both modified paths plus the settings problem, print `BLOCKERS: 3`, leave the sentinel and both modified files byte-identical, and create no `.forge/version`, guard, journal, backup, or report.

Mirror the same three findings in `test-full-refresh.ps1` using Windows paths and assertions.

- [ ] **Step 2: Run the focused suites to verify first-error RED**

Run:

```bash
bash tests/template/test-full-refresh.sh
```

Expected: only the first modified file is reported and `BLOCKERS: 3` is absent.

- [ ] **Step 3: Add the deterministic legacy inventory type**

Add this standard-library dataclass beside `UpgradeFinding`:

```python
@dataclasses.dataclass(frozen=True)
class LegacyInventory:
    selector: str
    region_selector: str
    recognized: bool
    proven_legacy: frozenset[str]
    findings: tuple[UpgradeFinding, ...]
```

Implement `inventory_legacy` as a read-only pass over the stamp, selected fingerprint rows, managed destinations, and JSON surfaces. Continue after ownership/parse findings, sort findings by `(scope, path, code, detail)`, and reserve immediate `RefreshBlocked` for unsafe roots, symlinks/reparse points, unreadable directories, or invalid manifest schema.

- [ ] **Step 4: Render one complete actionable report**

For dry-run, call inventory before creating temporary staging and without a persistent guard. For
execution, acquire the transaction guard first and then run the complete inventory under that guard
before creating staging. If findings exist, call Task 1's renderer with `UPGRADE: BLOCKED`,
`ACTIVE_FORGE: unchanged`, and
`NEXT_STEP: resolve every listed blocker, then rerun full refresh preview`; return nonzero through
`RefreshBlocked("upgrade inventory contains blocking findings")`, and do not stage.

- [ ] **Step 5: Make staging consume the proven inventory**

Change `prepare_legacy` to accept `inventory: LegacyInventory`, use its selector/region selector/proven set, and remove duplicate first-error fingerprint/JSON discovery. Preview consumes its guard-free inventory; execution consumes the complete inventory produced after acquiring the guard. Revalidate each proven source hash before copying or deleting; a later changed hash is a transaction race and blocks without applying.

- [ ] **Step 6: Run focused GREEN and commit**

Run:

```bash
bash tests/template/test-full-refresh.sh
bash tests/template/test-dual-layout.sh
git diff --check
```

Commit:

```bash
git add scripts/merge-settings.py tests/template/test-full-refresh.sh tests/template/test-full-refresh.ps1
git commit -m "feat: report all Forge upgrade blockers"
```

### Task 3: Reconcile root adapters, native aliases, custom harnesses, and state

**Files:**
- Create: `manifests/legacy-v5-aliases.tsv`
- Modify: `scripts/merge-settings.py:120-220`
- Modify: `scripts/merge-settings.py:700-970`
- Modify: `tests/template/test-dual-layout.sh`
- Test: `tests/template/test-full-refresh.sh`
- Test: `tests/template/test-full-refresh.ps1`

**Interfaces:**
- Produces: `strip_reconciliation_sentinel(raw: bytes) -> tuple[bytes, bytes]` returning `(sentinel_prefix, legacy_body)`.
- Produces: `root_instruction_findings(target: Path, scope: str) -> tuple[UpgradeFinding, ...]`.
- Produces: `active_harness_findings(target: Path) -> tuple[UpgradeFinding, ...]`.
- Produces: `state_source_findings(target: Path) -> tuple[UpgradeFinding, ...]`.
- Extends: `released_ownership()` to return canonical fingerprints plus alias fingerprints.

- [ ] **Step 1: Write root-sentinel and historical-AGENTS RED cases**

Add one fixture whose `CLAUDE.md` begins `<!-- forge:migrated 2026-04-28 -->`, followed by an exact released v5 root body with project text in the declared user regions. Preview and execution must preserve the sentinel/project text, remove old managed prose, add one v6 marker, and leave no `/codex` or active `.claude/rules` policy reference.

Add a project-owned `AGENTS.md` containing `@CONTINUITY.md`, `/codex`, and `.claude/rules`. Preview must group all obsolete references under one `ROOT_POLICY_AMBIGUOUS` finding, preserve the file, and block before mutation. A clean project-owned `AGENTS.md` must be preserved with one bounded v6 adapter.

- [ ] **Step 2: Write alias/custom-content RED cases**

Create an untracked `.agents/skills/ui-design/SKILL.md` byte-identical to the stamped v5.60 `.claude` skill and a `.claude/agents/project-quality.md` custom agent. Execution must replace the exact alias with the v6 managed adapter while preserving the custom agent hash. A one-byte-modified alias must block and remain unchanged.

- [ ] **Step 3: Write custom-runtime and multi-state RED cases**

Create `.agent-workflows/runtime/workflow-runtime.mjs`, root instructions referencing it, Claude and Codex hook commands invoking it, `.claude/local/state.md`, and `.agent-workflows/local/state.md`. Preview must emit one `CUSTOM_HARNESS_COLLISION`, one `MULTIPLE_STATE_SOURCES`, include both state hashes and modification times, perform no writes, and avoid 20 per-file duplicate collision messages.

Mirror the sentinel, alias, custom runtime, and multi-state cases in `test-full-refresh.ps1` with real Windows path handling.

- [ ] **Step 4: Run focused suites to verify RED**

Run:

```bash
bash tests/template/test-full-refresh.sh
bash tests/template/test-dual-layout.sh
```

Expected: the leading sentinel prevents region recognition, alias provenance is absent, and the custom runtime/two-state conditions are not grouped.

- [ ] **Step 5: Implement sentinel-aware bounded root reconciliation**

Recognize only these leading lines before region matching:

```python
RECONCILIATION_SENTINEL = re.compile(
    rb"\A<!-- forge:(?:migrated|reconciled) \d{4}-\d{2}-\d{2} -->\r?\n(?:\r?\n)?"
)
```

Pass the remaining bytes to the existing versioned region recognizer, prepend the untouched sentinel and preserved user regions to staging, and let the materializer insert exactly one v6 marker. Scan preserved root text for the exact retired tokens `@CONTINUITY.md`, `/codex`, `.claude/commands/`, `.claude/rules/`, and `.claude/hooks/`; return one root finding listing line numbers rather than rewriting project text.

- [ ] **Step 6: Add versioned alias provenance**

Create a five-column TSV with header:

```text
# fingerprint-sets\tsource\tlegacy-alias-destination\tscope\tsha256
```

Add only the content-identical v5.60/v5.61 alias rows proven by the sanitized fixtures. Extend `released_ownership()` to parse and append these rows to fingerprint lookup, but keep them distinguishable for diagnostics. Update `test-dual-layout.sh` to recompute every alias hash from its declared historical source/release and reject duplicate destination/selector pairs.

- [ ] **Step 7: Group independent harness and state collisions**

Treat `.agent-workflows` as an independent active harness only when at least two authority signals exist: a regular runtime/policy file plus a root/settings/Codex-hook reference. Emit one finding with sorted authority paths and resolution `archive or retire the custom harness, remove its active registrations, then rerun -F --dry-run`.

Consider `.claude/local/state.md`, `.forge/local/state.md`, and `.agent-workflows/local/state.md` plausible only when regular files with a Forge project-state header/schema. If more than one non-receipt-proven source exists, emit one `MULTIPLE_STATE_SOURCES` finding with each path, SHA-256, and mtime; preserve all bytes.

- [ ] **Step 8: Run focused GREEN and commit**

Run:

```bash
bash tests/template/test-full-refresh.sh
bash tests/template/test-dual-layout.sh
bash tests/template/test-platform-parity.sh
git diff --check
```

Commit:

```bash
git add manifests/legacy-v5-aliases.tsv scripts/merge-settings.py tests/template/test-dual-layout.sh tests/template/test-full-refresh.sh tests/template/test-full-refresh.ps1
git commit -m "feat: reconcile mixed Forge upgrade surfaces"
```

### Task 4: Prove the four downstream upgrade profiles end to end

**Files:**
- Modify: `tests/template/test-full-refresh.sh`
- Modify: `tests/template/test-full-refresh.ps1`
- Modify: `scripts/merge-settings.py:1221-1401` only if an integration assertion exposes a shared-engine defect

**Interfaces:**
- Consumes: Tasks 1-3 public CLI, inventory records, alias manifest, and collision grouping.
- Produces: four sanitized integration fixtures and an executable `assert_one_active_forge` acceptance helper.

- [ ] **Step 1: Add a final-tree invariant helper**

In Bash, add `assert_one_active_forge <project>` that requires `.forge/version=6`, one Forge block in
each root adapter, canonical managed files present, every retained `.claude/commands` workflow to be
a thin v6 adapter, and no retired `/codex`, full-body v5 command, direct v5 hook registration, v5
prompt evaluator, or `.claude/rules` legacy policy. Add the equivalent `Assert-OneActiveForge`
PowerShell helper using literal-path and JSON parsing.

- [ ] **Step 2: Add four sanitized profile builders**

Build deterministic fixtures without private repository content:

1. v5.60 exact core + sentinel root + project ADR/rule + preserved overlapping plugin;
2. v5.58 tracked mixed Claude/Codex trees + custom CI docs;
3. v5.60 exact core + historical project `AGENTS.md` + exact alias skills + custom agent;
4. v5.61 + independent `.agent-workflows` runtime + custom skills/hooks + two states.

Use `git show <declared-release>:<source>` for released bytes and short tokens such as `PROJECT_ADR_BYTES` for project content.

- [ ] **Step 3: Assert preview behavior for all profiles**

Profiles 1 and 2 preview `READY` with no writes. Profile 1 execution preserves its plugin and reports
Claude `RUNTIME_READY: BLOCKED` without blocking filesystem migration. Profile 3 reports every root
ambiguity in one pass; after replacing only the ambiguous old Forge prose with neutral project text,
preview becomes `READY`. Profile 4 reports the grouped harness/state choice and remains byte-identical.

- [ ] **Step 4: Assert execution and explicit reconciliation**

Execute profiles 1-3 and call `assert_one_active_forge`. For profile 4, simulate the explicit project-owner choice by moving the custom runtime under `docs/archive/legacy-agent-workflows/`, removing its hook registrations, and selecting the newer state as `.claude/local/state.md`; rerun preview and execution, then assert one active Forge and preservation of the archived runtime/state backup.

- [ ] **Step 5: Assert worktree confinement and idempotency**

Create a linked sibling worktree with its own local state. Run preview and execution in the primary
worktree; assert sibling tracked bytes and local state hashes do not change. Run `-f` on the resulting
v6 primary and assert managed-manifest hash stability. Run `-F --dry-run` on that v6 primary and
assert `UPGRADE: READY`, no migration needed, and byte-identical state/stamps.

- [ ] **Step 6: Run integration GREEN and commit**

Run:

```bash
bash tests/template/test-full-refresh.sh
bash tests/template/test-setup.sh
bash tests/template/test-dual-layout.sh
bash tests/template/test-platform-parity.sh
git diff --check
```

Commit:

```bash
git add tests/template/test-full-refresh.sh tests/template/test-full-refresh.ps1 scripts/merge-settings.py
git commit -m "test: cover real Forge upgrade profiles"
```

### Task 5: Publish the upgrade UX and verify the frozen candidate

**Files:**
- Modify: `README.md`
- Modify: `docs/guides/getting-started.md`
- Modify: `docs/guides/setup-scenarios.md`
- Modify: `docs/guides/upgrading.md`
- Modify: `docs/reference/commands.md`
- Modify: `docs/troubleshooting.md`
- Modify: `tests/template/test-contracts.sh`

**Interfaces:**
- Consumes: final executable CLI/report strings from Tasks 1-4.
- Produces: one public upgrade story and final release evidence.

- [ ] **Step 1: Write failing documentation contracts**

Add exact assertions that active documentation contains:

```text
setup.sh -F --dry-run
setup.ps1 -FullRefresh -DryRun
UPGRADE: READY
UPGRADE: BLOCKED
ACTIVE_FORGE: v6
```

Require docs to distinguish `-f` from `-F`, preview from execution, `MATERIALIZED` from `RUNTIME_READY`, plugin readiness from filesystem collision, and current-worktree scope from sibling worktrees.

- [ ] **Step 2: Run contracts to verify RED**

Run:

```bash
bash tests/template/test-contracts.sh
```

Expected: new dry-run and one-active-Forge documentation assertions fail.

- [ ] **Step 3: Rewrite the bounded public upgrade sections**

Lead README and the upgrade guide with:

```bash
~/claude-codex-forge/setup.sh -F --dry-run
~/claude-codex-forge/setup.sh -F
```

```powershell
& $HOME\claude-codex-forge\setup.ps1 -FullRefresh -DryRun
& $HOME\claude-codex-forge\setup.ps1 -FullRefresh
```

Explain the four report outcomes: ready preview, ownership block, independent-harness choice, and successful one-active-v6 migration. State that users do not manually synchronize `CLAUDE.md` and `AGENTS.md`, and include the exact custom-runtime/state reconciliation sequence without claiming automatic deletion.

- [ ] **Step 4: Run focused final checks**

Run:

```bash
bash tests/template/test-contracts.sh
bash tests/template/test-full-refresh.sh
bash tests/template/test-setup.sh
bash tests/template/test-dual-layout.sh
bash tests/template/test-platform-parity.sh
bash tests/template/test-lint.sh
git diff --check
```

Expected: all Bash/static suites pass. Record PowerShell execution as Windows-CI-owned when no local runtime is present.

- [ ] **Step 5: Freeze and run the aggregate exactly once**

Stage the intended files, record `git write-tree`, make no further edits, then run:

```bash
NO_COLOR=1 bash tests/template/run-all.sh
```

Expected: `All suites passed`. If the aggregate exposes a real supported-path defect, unfreeze, add one focused regression, repair it, rerun the owning suite, refreeze, and run the aggregate one final time; do not expand the acceptance matrix.

- [ ] **Step 6: Commit the documentation and final contracts**

```bash
git add README.md docs/guides/getting-started.md docs/guides/setup-scenarios.md docs/guides/upgrading.md docs/reference/commands.md docs/troubleshooting.md tests/template/test-contracts.sh
git commit -m "docs: make Forge upgrades predictable"
```

- [ ] **Step 7: Final handoff**

Report the branch, commit sequence, focused counts, aggregate result, Windows CI status, and these honest boundaries:

- migration safety does not certify host authentication;
- independently developed active harnesses require an explicit owner decision;
- sibling worktrees are not mutated;
- no unsupported legacy layout is silently guessed or deleted.

### Task 6: Retire the standalone continuity migration

**Files:**
- Modify: `setup.sh`, `setup.ps1`
- Modify: `scripts/merge-settings.py`
- Delete: `scripts/migrate-continuity.sh`, `scripts/migrate-continuity.ps1`
- Modify: `hooks/check-state-updated.sh`, `hooks/check-state-updated.ps1`
- Modify: `hooks/check-workflow-gates.sh`, `hooks/check-workflow-gates.ps1`
- Modify: active README/docs and owning tests

**Interfaces:**
- Retires the functional `--migrate` / `-Migrate` workflow.
- Preserves the old spellings only as non-mutating error tombstones pointing to full-refresh preview.
- Produces `LEGACY_CONTINUITY_UNRESOLVED` during project full-refresh inventory.
- Preserves existing valid state-translation receipts and reconciliation sentinels.

- [x] **Step 1: Write RED retirement and inventory tests**

Require both retired flags to return nonzero without changing the project and direct users to
`-F --dry-run` / `-FullRefresh -DryRun`. Require an otherwise valid project containing unresolved
`CONTINUITY.md` to block preview and execution before persistent writes while preserving the file.

- [x] **Step 2: Keep proven prior migrations compatible**

Build a valid historical sentinel plus exact old/new state receipt without invoking the retired
command. Require full refresh to accept that evidence, while malformed or hash-mismatched receipts
remain blocked.

- [x] **Step 3: Remove the functional path and add fail-closed inventory**

Delete both heuristic migration helpers and their standalone suite. Remove the command from active
help/docs and redirect hook guidance to preview. Do not import semantic Markdown extraction into
full refresh. A bare unresolved file is preserved byte-for-byte and reported with manual
reconciliation instructions; execution repeats inventory under the transaction guard only after a
pre-guard inventory is clean.

- [x] **Step 4: Verify and deliver**

Run the focused full-refresh, setup, hooks, contracts, lint, and platform-parity suites, then one
final aggregate on the frozen tree. Commit, push `codex/forge-v6-upgrade-hardening`, and open a PR
against `main`.
