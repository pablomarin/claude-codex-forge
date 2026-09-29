# Project-Only Forge Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Forge installation complete and explicitly versioned per repository, including native-goal composition, with no global runtime dependency and a safe one-time global retirement path.

**Architecture:** The active installer and manifest become project-only. `.forge/version` is the one exact per-repository release pin, `AGENTS.md` is the canonical adapter, and Claude's root adapter only imports it. Native host Goals provide continuation authority while a no-clobber ledger under the Git common directory preserves Forge's monotonic 20-turn budget across worktrees and hosts. A cleanup-only Python engine previews and digest-binds conservative retirement of historical global Forge material for both shell and PowerShell wrappers.

**Tech Stack:** Bash 3.2+, PowerShell 5.1+, Python 3 standard library, Git, Markdown/JSON/TOML configuration, Forge's shell test harness.

**Spec:** `docs/superpowers/specs/2026-09-28-project-only-forge-install-design.md`

## Global Constraints

- Supported installation and upgrade are repository-local; no active runtime reads or writes `~/.forge`.
- Publish this architecture as Forge `6.3`; `.forge/version` contains the exact `MAJOR.MINOR` release and is written last.
- Accept legacy `.forge/version` value `6` as an unpinned V6 layout; reject any unsupported major without mutation.
- Remove `.claude/.forge-version` and `~/.claude/.forge-version` as active version sources.
- Apply KISS and YAGNI explicitly in `FORGE.template.md`, `rules/principles.md`, and `rules/critical-rules.md`.
- `AGENTS.md` is the sole canonical root adapter; the Forge block in `CLAUDE.md` imports only `@AGENTS.md`.
- `docs/agent-context.md` is optional project-owned content and is never created or overwritten by setup.
- Native goal activation authorizes only bounded autonomous continuation; external mutations retain separate authorization.
- Forge charges at most one durable turn per unique host turn ID and uses a 20-turn tranche per human native-goal activation.
- Unix and Windows must make equivalent installation, ledger, cleanup, and failure decisions.
- Add no daemon, database, network service, third-party package, or replacement configuration framework.

## Review Focus

- Legacy version inputs: exact `6` upgrades to `6.3`, malformed and unsupported majors block, and a failed transaction never advances the pin. Covered in Task 1.
- Root adapter preservation: existing personal bytes, malformed markers, missing `docs/agent-context.md`, and Claude import precedence remain safe. Covered in Task 2.
- Global-retirement races and aliases: a changed preview digest, symlink/reparse traversal, modified managed bytes, and unknown files must preserve data and block only the affected operation. Covered in Task 3.
- Goal-ledger replay/concurrency: duplicate Stop delivery, simultaneous publication, deleted state, reduced counts, and linked-worktree paths cannot reset or double-charge the budget. Covered in Task 5.
- Partial host/runtime availability: missing Python blocks only legacy cleanup, while absent or unauthenticated Claude/Codex blocks only that live qualification and never normal project setup. Covered in Tasks 4 and 6.

---

### Task 1: Canonical Per-Repository Release Version

**Files:**
- Modify: `setup.sh`
- Modify: `setup.ps1`
- Modify: `scripts/materialize-adapters.sh`
- Modify: `scripts/materialize-adapters.ps1`
- Modify: `scripts/full-refresh.sh`
- Modify: `scripts/full-refresh.ps1`
- Modify: `scripts/merge-settings.py`
- Modify: `hooks/session-start.sh`
- Modify: `hooks/session-start.ps1`
- Modify: `scripts/verify-runtime.sh`
- Modify: `scripts/verify-runtime.ps1`
- Modify: `tests/template/test-setup-flags.sh`
- Modify: `tests/template/test-setup.sh`
- Modify: `tests/template/test-full-refresh.sh`
- Modify: `tests/template/test-full-refresh.ps1`
- Modify: `tests/template/test-session-start.sh`
- Modify: `tests/template/test-contracts.sh`

**Interfaces:**
- Consumes: the first release heading in `docs/CHANGELOG.md`, currently the source of the published `MAJOR.MINOR` release.
- Produces: exact `.forge/version`; `--release-version MAJOR.MINOR` / `-ReleaseVersion MAJOR.MINOR` materializer inputs; setup and verify output `FORGE_VERSION: <version>`.

- [ ] **Step 1: Add failing setup/version tests**

Add this contract to `tests/template/test-setup-flags.sh` after the fresh force-install case:

```bash
EXPECTED_RELEASE=$(sed -nE 's/^##[[:space:]]+([0-9]+\.[0-9]+).*/\1/p' \
    "$REPO_ROOT/docs/CHANGELOG.md" | head -1)
assert_equals "$(tr -d '\r\n' < "$S3/.forge/version")" "$EXPECTED_RELEASE" \
    "project stamp records the exact Forge release"
assert_contains "$S3/force.log" "FORGE_VERSION: $EXPECTED_RELEASE" \
    "setup reports the installed project release"
assert_file_missing "$S3/.claude/.forge-version" \
    "project does not retain the Claude-specific version pin"
assert_file_missing "$S3/.fakehome/.claude/.forge-version" \
    "project setup writes no machine-wide version stamp"
```

Add three fixtures to `tests/template/test-full-refresh.sh`:

```bash
EXPECTED_RELEASE=$(sed -nE 's/^##[[:space:]]+([0-9]+\.[0-9]+).*/\1/p' \
    "$REPO_ROOT/docs/CHANGELOG.md" | head -1)
start_test "exact project release is published last and legacy V6 is adopted"
V=$(scratch_dir exact-project-version)
git -C "$V" init -q
mkdir -p "$V/.forge"
printf '6\n' > "$V/.forge/version"
(cd "$V" && HOME="$V/home" "$REPO_ROOT/setup.sh" -f) > "$V/apply.log" 2>&1
assert_equals "$?" "0" "unversioned V6 refresh succeeds"
assert_equals "$(tr -d '\r\n' < "$V/.forge/version")" "$EXPECTED_RELEASE" \
    "unversioned V6 becomes the exact release"

BAD=$(scratch_dir unsupported-forge-major)
git -C "$BAD" init -q
mkdir -p "$BAD/.forge"
printf '7.0\n' > "$BAD/.forge/version"
before=$(hash_file "$BAD/.forge/version")
(cd "$BAD" && HOME="$BAD/home" "$REPO_ROOT/setup.sh" -f) > "$BAD/apply.log" 2>&1
assert_equals "$?" "1" "unsupported major blocks"
assert_hash_equals "$BAD/.forge/version" "$before" "unsupported version remains unchanged"
assert_contains "$BAD/apply.log" "BLOCKED: unsupported Forge layout major 7" \
    "unsupported major is diagnosed"
```

Replace the machine-stamp drift cases in `tests/template/test-session-start.sh` with assertions that
SessionStart neither reads nor mentions `~/.claude/.forge-version` and that `verify-runtime` reports
the repository's `.forge/version`.

- [ ] **Step 2: Run focused tests and confirm RED**

Run:

```bash
bash tests/template/test-setup-flags.sh
bash tests/template/test-full-refresh.sh
bash tests/template/test-session-start.sh
```

Expected: FAIL because materializers still write `6`, setup still writes both Claude-specific stamps,
and session-start still compares against the home stamp.

- [ ] **Step 3: Make exact release an explicit transaction input**

Keep the existing top-changelog parser in each installer, but validate it strictly and pass it into
every materializer/full-refresh call:

```bash
case "$FORGE_VERSION" in
    [0-9]*.[0-9]*) ;;
    *) echo "BLOCKED: published Forge release is unavailable" >&2; exit 2 ;;
esac
materialize_args+=(--release-version "$FORGE_VERSION")
```

```powershell
if ($ForgeVersion -notmatch '^\d+\.\d+$') {
    throw 'BLOCKED: published Forge release is unavailable'
}
$materializeArgs += @('-ReleaseVersion', $ForgeVersion)
```

Add a required release argument to both materializers. Write it only after all files, settings,
adapters, state, and installed-file receipts succeed:

```bash
case "$MATERIALIZE_RELEASE_VERSION" in
    [0-9]*.[0-9]*) ;;
    *) echo "BLOCKED: invalid release version" >&2; exit 2 ;;
esac
printf '%s\n' "$MATERIALIZE_RELEASE_VERSION" > "$MATERIALIZE_TARGET/.forge/version"
echo "FORGE_VERSION: $MATERIALIZE_RELEASE_VERSION"
```

```powershell
if ($ReleaseVersion -notmatch '^\d+\.\d+$') { throw 'BLOCKED: invalid release version' }
[IO.File]::WriteAllText((Join-Path $Target '.forge\version'), "$ReleaseVersion`n", $Utf8NoBom)
Write-Host "FORGE_VERSION: $ReleaseVersion"
```

Update `scripts/merge-settings.py` to receive `--release-version`, validate with
`re.fullmatch(r"[0-9]+\.[0-9]+", value)`, use `value.split(".", 1)[0]` for layout compatibility,
and stage `.forge/version` as the final transaction operation. Accept exact `6` as legacy V6; reject
any other bare or dotted major.

- [ ] **Step 4: Retire duplicate project and machine stamps**

Delete ordinary writes and reads of `.claude/.forge-version` and `~/.claude/.forge-version` from both
installers and SessionStart hooks. Preserve the existing manifest tombstone for a proven old project
stamp. Change upgrade diagnostics to compare the pre-transaction `.forge/version` with
`FORGE_VERSION` and print:

```text
FORGE_VERSION_CHANGE: 6.2 -> 6.3
```

Make both runtime verifiers read only `<project>/.forge/version`, validate `MAJOR.MINOR`, and print
`FORGE_VERSION: <value>`. Missing or malformed stamps make readiness `BLOCKED`.

- [ ] **Step 5: Run version and transaction tests GREEN**

Run:

```bash
bash tests/template/test-setup-flags.sh
bash tests/template/test-setup.sh
bash tests/template/test-full-refresh.sh
bash tests/template/test-session-start.sh
bash tests/template/test-contracts.sh
```

Expected: all pass; no test fixture requires a home version stamp.

- [ ] **Step 6: Commit the version contract**

```bash
git add setup.sh setup.ps1 scripts/materialize-adapters.sh scripts/materialize-adapters.ps1 \
  scripts/full-refresh.sh scripts/full-refresh.ps1 scripts/merge-settings.py \
  hooks/session-start.sh hooks/session-start.ps1 scripts/verify-runtime.sh \
  scripts/verify-runtime.ps1 tests/template/
git commit -m "feat: pin Forge release per repository"
```

### Task 2: Complete Project Policy and One Adapter

**Files:**
- Modify: `FORGE.template.md`
- Modify: `rules/principles.md`
- Modify: `rules/critical-rules.md`
- Modify: `rules/memory.md`
- Modify: `templates/adapters/AGENTS.block.template.md`
- Modify: `templates/adapters/CLAUDE.block.template.md`
- Modify: `CONTRIBUTING.md`
- Modify: `tests/template/test-workflow-parity.sh`
- Modify: `tests/template/test-setup.sh`
- Modify: `tests/template/test-contracts.sh`

**Interfaces:**
- Consumes: the policy outcomes in `GLOBAL-FORGE.template.md` before that file is retired in Task 4.
- Produces: complete `.forge/instructions.md`; canonical `AGENTS.md` discovery block; Claude bridge containing `@AGENTS.md` and no restated Forge policy.

- [ ] **Step 1: Add failing policy-migration tests**

Add exact assertions to `tests/template/test-workflow-parity.sh`:

```bash
for text in \
  'Apply KISS and YAGNI' \
  'Ground Your Claims' \
  'Host Neutrality' \
  'never save secrets or speculative conclusions' \
  'before context compaction or the end of substantial work'; do
    assert_contains "$REPO_ROOT/FORGE.template.md" "$text" \
        "project instructions preserve global policy: $text"
done
assert_contains "$REPO_ROOT/rules/principles.md" 'Apply KISS and YAGNI' \
    "principles name KISS and YAGNI"
assert_contains "$REPO_ROOT/rules/critical-rules.md" 'KISS AND YAGNI' \
    "critical rules name KISS and YAGNI"
```

Add installed-adapter assertions to `tests/template/test-setup.sh`:

```bash
assert_contains "$S/AGENTS.md" '`.forge/instructions.md`' \
    "AGENTS discovers canonical project policy"
assert_contains "$S/AGENTS.md" '`docs/agent-context.md` exists' \
    "AGENTS conditionally discovers project context"
assert_contains "$S/CLAUDE.md" '@AGENTS.md' "Claude imports the canonical adapter"
assert_not_contains "$S/CLAUDE.md" '@.forge/instructions.md' \
    "Claude does not bypass the canonical adapter"
assert_not_contains "$S/CLAUDE.md" 'FORGE_GOAL_BUDGET_EXHAUSTED' \
    "Claude bridge duplicates no goal policy"
assert_file_missing "$S/docs/agent-context.md" \
    "setup does not invent project-specific context"
```

Seed personal text before setup and assert its hash/content survives outside the Forge markers for
both root files.

- [ ] **Step 2: Run policy/adapter tests and confirm RED**

Run:

```bash
bash tests/template/test-workflow-parity.sh
bash tests/template/test-setup.sh
bash tests/template/test-contracts.sh
```

Expected: FAIL because KISS/YAGNI are not explicit on all three surfaces and Claude imports the
Forge instructions directly while duplicating goal prose.

- [ ] **Step 3: Merge the former global policy into project instructions**

Add this exact directive at the start of `FORGE.template.md`'s Resource Discipline section and
mirror it in the named rule files:

```markdown
Apply KISS and YAGNI: build the smallest correct solution required by current evidence and
acceptance criteria. Do not add speculative abstractions, compatibility layers, hardening, or
edge-case machinery without a concrete supported need.
```

Add concise `## Memory Management` and `## Host Neutrality` sections to `FORGE.template.md` that:

- route current progress to `.forge/local/state.md`;
- route worktree-local learning to `.forge/local/memory/`;
- route reviewed project knowledge to `.forge/memory/`;
- forbid secrets and speculative conclusions;
- require preserving a useful learning before compaction/end when one exists; and
- state that native private host memory is optional and never evidence or a dependency.

Keep operational detail in `rules/memory.md`; remove any suggestion that home memory is required.

- [ ] **Step 4: Reduce the adapters to discovery only**

Make the Forge block in `templates/adapters/AGENTS.block.template.md` exactly this policy body
between the existing marker/metadata lines:

```markdown
Read `.forge/instructions.md` completely before taking project action.
If `docs/agent-context.md` exists, read it as project-owned context. Do not create or overwrite it.
This adapter contains no Forge policy; `.forge/instructions.md` is canonical.
```

Make the Forge block in `templates/adapters/CLAUDE.block.template.md` contain only:

```markdown
@AGENTS.md
```

Update `CONTRIBUTING.md` to name `AGENTS.md` as canonical and `CLAUDE.md` as the compatibility
bridge.

- [ ] **Step 5: Run policy/adapter tests GREEN**

Run:

```bash
bash tests/template/test-workflow-parity.sh
bash tests/template/test-setup.sh
bash tests/template/test-contracts.sh
```

Expected: all pass, including personal-byte preservation and absent optional context.

- [ ] **Step 6: Commit the local policy and adapter contract**

```bash
git add FORGE.template.md rules/principles.md rules/critical-rules.md rules/memory.md \
  templates/adapters/AGENTS.block.template.md templates/adapters/CLAUDE.block.template.md \
  CONTRIBUTING.md tests/template/
git commit -m "feat: make project instructions complete"
```

### Task 3: Safe Legacy-Global Retirement Engine

**Files:**
- Create: `scripts/retire-global.py`
- Create: `manifests/legacy-v6-global.tsv`
- Create: `manifests/legacy-v6-global-settings.json`
- Create: `tests/template/test-retire-global.sh`
- Create: `tests/template/test-retire-global.ps1`
- Modify: `tests/template/run-all.sh`

**Interfaces:**
- Consumes: a target home, platform, historical global inventory, historical `.forge/installed-files.tsv`, and exact Forge markers/managed entries.
- Produces: deterministic `RetirementPlan` classifications, `RETIRE_GLOBAL_DIGEST=<sha256>`, and digest-bound apply; exit `0` for a complete preview/apply, `2` for blocked/changed material.

- [ ] **Step 1: Write failing Unix retirement tests**

Create `tests/template/test-retire-global.sh` using `tests/template/lib.sh`. Its first fixture must:

```bash
H=$(scratch_dir retire-global)
mkdir -p "$H/home/.forge/bin" "$H/home/.claude" "$H/home/.codex"
printf '6\n' > "$H/home/.forge/version"
printf 'PERSONAL CLAUDE\n<!-- forge:begin v6 -->\nOLD FORGE\n<!-- forge:end v6 -->\n' \
  > "$H/home/.claude/CLAUDE.md"
printf 'PERSONAL CODEX\n<!-- forge:begin v6 -->\nOLD FORGE\n<!-- forge:end v6 -->\n' \
  > "$H/home/.codex/AGENTS.md"
printf 'owned helper\n' > "$H/home/.forge/bin/forge-goal-authorize"
helper_hash=$(hash_file "$H/home/.forge/bin/forge-goal-authorize")
printf '.forge/bin/forge-goal-authorize\t%s\tv6\n' "$helper_hash" \
  > "$H/home/.forge/installed-files.tsv"
before=$(snapshot_project "$H/home")
python3 "$REPO_ROOT/scripts/retire-global.py" \
  --repo-root "$REPO_ROOT" --home "$H/home" --platform unix > "$H/preview.log"
assert_equals "$?" "0" "global retirement preview succeeds"
after=$(snapshot_project "$H/home")
assert_equals "$after" "$before" "preview writes no bytes"
assert_contains "$H/preview.log" 'REMOVE .forge/bin/forge-goal-authorize' \
  "preview proves installed helper ownership"
assert_contains "$H/preview.log" 'PRESERVE .claude/CLAUDE.md personal-bytes' \
  "preview preserves personal Claude bytes"
assert_contains "$H/preview.log" 'RETIRE_GLOBAL_DIGEST=' "preview emits digest"
```

Add controls for a modified installed file, duplicate/malformed markers, a symlinked `.forge`, an
unknown file under `.forge`, partial installations, wrong digest, and a changed byte between preview
and apply. Apply must preserve personal lines and unknown files and remove only listed owned bytes.

- [ ] **Step 2: Write failing PowerShell retirement parity tests**

Create `tests/template/test-retire-global.ps1` with equivalent fixtures using
`[IO.File]::WriteAllText`, `Get-FileHash`, and a directory junction/reparse-point control when the
runner permits it. Assert the same action/path classifications and digest behavior as Unix.

- [ ] **Step 3: Run the new tests and confirm RED**

Run:

```bash
bash tests/template/test-retire-global.sh
```

Expected: FAIL because `scripts/retire-global.py` and the legacy inventory do not exist.

- [ ] **Step 4: Define the cleanup-only inventory**

Create `manifests/legacy-v6-global.tsv` with only historical global destinations and proof modes:

```tsv
# kind	destination	platform	proof
canonical	.forge/instructions.md	all	installed-hash
canonical	.forge/version	all	exact-version
canonical	.forge/managed-files.tsv	all	installed-hash
canonical	.forge/installed-files.tsv	all	self
canonical	.forge/bin/forge-goal-authorize	unix	installed-hash
canonical	.forge/bin/forge-goal-authorize.ps1	windows	installed-hash
canonical	.forge/bin/forge-goal-capture	unix	installed-hash
canonical	.forge/bin/forge-goal-capture.ps1	windows	installed-hash
generated	.forge/bin/codex.identity	all	recognized-schema
generated	.forge/bin/codex.identity.sha256	all	recognized-seal
generated	.forge/goal-authorizations	all	recognized-tree
generated	.forge/goal-captures	all	recognized-tree
marker	.claude/CLAUDE.md	all	forge-marker-v6
marker	.codex/AGENTS.md	all	forge-marker-v6
marker	.codex/config.toml	all	forge-toml-marker-v6
merge	.claude/settings.json	all	legacy-v6-global-settings
generated	.claude/.forge-version	all	exact-release
```

Copy only the exact historical Forge-managed JSON values needed for inverse removal into
`manifests/legacy-v6-global-settings.json`. It is cleanup data, not an active settings template.

- [ ] **Step 5: Implement deterministic planning and digest binding**

Create these exact public types/functions in `scripts/retire-global.py`:

```python
@dataclasses.dataclass(frozen=True, order=True)
class Finding:
    action: str          # REMOVE, PRESERVE, BLOCKED, ABSENT
    path: str
    kind: str
    proof: str
    expected_sha256: str = ""

@dataclasses.dataclass(frozen=True)
class RetirementPlan:
    home: pathlib.Path
    platform: str
    findings: tuple[Finding, ...]

def plan_digest(plan: RetirementPlan) -> str:
    rows = [dataclasses.asdict(item) for item in sorted(plan.findings)]
    payload = json.dumps(rows, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()
```

Planning rules are exact:

1. Resolve the home physically and reject a symlink/reparse ancestor.
2. For `installed-hash`, require a regular file whose current SHA-256 equals its recorded
   `.forge/installed-files.tsv` hash; otherwise classify `BLOCKED`.
3. For marker files, require exactly one ordered begin/end pair; classify only the bounded block as
   `REMOVE` and bytes before/after as `PRESERVE`.
4. For JSON, remove only values exactly equal to the cleanup inventory and preserve all other keys,
   lists, ordering-independent semantics, and unknown objects.
5. For generated trees, accept only regular files matching the historical schema and reject links or
   unknown names.
6. Sort findings by path, action, kind, proof before hashing and printing.

Apply must recompute the plan, compare the supplied digest with `hmac.compare_digest`, abort before
the first write on any mismatch or `BLOCKED` finding, stage every replacement in a sibling temporary
file, promote only after all staged outputs validate, delete only empty directories, and print the
same finding list plus `RETIRE_GLOBAL: COMPLETE`.

- [ ] **Step 6: Run retirement tests GREEN**

Run:

```bash
bash tests/template/test-retire-global.sh
pwsh -NoProfile -File tests/template/test-retire-global.ps1
```

Expected: both pass where `pwsh` is available; Windows CI owns PowerShell 5.1 certification.

- [ ] **Step 7: Register tests and commit the cleanup engine**

Add the Unix suite to `tests/template/run-all.sh`. The existing Windows workflow invokes
`tests/template/run-all.ps1`, which auto-discovers `test-*.ps1`; add a contract assertion that the
new PowerShell suite is discovered rather than editing the workflow.

```bash
git add scripts/retire-global.py manifests/legacy-v6-global.tsv \
  manifests/legacy-v6-global-settings.json tests/template/test-retire-global.sh \
  tests/template/test-retire-global.ps1 tests/template/run-all.sh
git commit -m "feat: add safe global Forge retirement"
```

### Task 4: Remove Global Installation and Route Explicit Retirement

**Files:**
- Modify: `setup.sh`
- Modify: `setup.ps1`
- Modify: `manifests/managed-v6.tsv`
- Modify: `scripts/materialize-adapters.sh`
- Modify: `scripts/materialize-adapters.ps1`
- Modify: `scripts/full-refresh.sh`
- Modify: `scripts/full-refresh.ps1`
- Modify: `scripts/merge-settings.py`
- Delete: `GLOBAL-FORGE.template.md`
- Delete: `GLOBAL-CLAUDE.template.md`
- Delete: `GLOBAL-AGENTS.template.md`
- Delete: `settings/global-settings.template.json`
- Modify: `tests/template/test-setup-flags.sh`
- Modify: `tests/template/test-setup.sh`
- Modify: `tests/template/test-full-refresh.sh`
- Modify: `tests/template/test-full-refresh.ps1`
- Modify: `tests/template/test-dual-layout.sh`
- Modify: `tests/template/test-contracts.sh`

**Interfaces:**
- Consumes: `scripts/retire-global.py` and `manifests/legacy-v6-global.tsv` from Task 3.
- Produces: project-only setup; non-mutating retired `--global` diagnostic; `--retire-global [--apply --confirm DIGEST]` and PowerShell equivalents.

- [ ] **Step 1: Add failing public-CLI and isolation tests**

Add to `tests/template/test-setup-flags.sh`:

```bash
start_test "global install is retired and non-mutating"
G=$(scratch_dir retired-global-flag)
git -C "$G" init -q
mkdir -p "$G/home"
mkdir -p "$G/.fakehome"
before=$(snapshot_project "$G")
(cd "$G" && HOME="$G/home" "$REPO_ROOT/setup.sh" --global) > "$G/.fakehome/global.log" 2>&1
assert_equals "$?" "1" "--global exits nonzero"
after=$(snapshot_project "$G")
assert_equals "$after" "$before" "--global changes no project bytes"
assert_contains "$G/.fakehome/global.log" 'global installation is retired' \
    "retired flag explains project-only installation"
assert_contains "$G/.fakehome/global.log" '--retire-global' "retired flag names cleanup path"

start_test "project setup leaves an unrelated project and home unchanged"
A=$(scratch_dir project-only-a)
B=$(scratch_dir project-only-b)
git -C "$A" init -q
git -C "$B" init -q
mkdir -p "$A/home/.claude"
printf 'HOME_SENTINEL\n' > "$A/home/.claude/personal.txt"
b_hash=$(snapshot_project "$B")
home_hash=$(hash_file "$A/home/.claude/personal.txt")
(cd "$A" && HOME="$A/home" "$REPO_ROOT/setup.sh") > "$A/setup.log" 2>&1
assert_equals "$?" "0" "project-only setup succeeds"
assert_equals "$(snapshot_project "$B")" "$b_hash" "uninstalled project is unchanged"
assert_hash_equals "$A/home/.claude/personal.txt" "$home_hash" "home is unchanged"
assert_file_missing "$A/home/.forge/version" "no global Forge is created"
assert_contains "$A/setup.log" \
  'NATIVE_GOAL_RUNTIME: PENDING reason=live-qualification-not-run' \
  "project setup reports deterministic install without overstating live qualification"
```

Assert the managed manifest has no row whose scope column is `global`, no setup help advertises
global installation, and materializers reject `--scope global` / `-Scope global`.

- [ ] **Step 2: Run installer/layout tests and confirm RED**

Run:

```bash
bash tests/template/test-setup-flags.sh
bash tests/template/test-setup.sh
bash tests/template/test-dual-layout.sh
bash tests/template/test-contracts.sh
```

Expected: FAIL because global setup remains advertised, the manifest has global rows, and setup
writes home state.

- [ ] **Step 3: Replace global mode with retirement mode**

In `setup.sh`, parse these exact fields:

```bash
RETIRE_GLOBAL=false
RETIRE_APPLY=false
RETIRE_CONFIRM=""
```

`--global` / `-g` immediately prints the non-mutating retirement message and exits `1`.
`--retire-global` selects cleanup; `--apply` is legal only with retirement; `--confirm` requires one
64-character lowercase SHA-256. Dispatch cleanup before Git-root project preflight:

```bash
retire_args=(--repo-root "$SCRIPT_DIR" --home "${HOME:?HOME is required}" --platform unix)
[ "$RETIRE_APPLY" = true ] && retire_args+=(--apply)
[ -z "$RETIRE_CONFIRM" ] || retire_args+=(--confirm "$RETIRE_CONFIRM")
python3 "$SCRIPT_DIR/scripts/retire-global.py" "${retire_args[@]}"
```

Mirror the contract in
PowerShell with `-RetireGlobal`, `-Apply`, and `[string]$Confirm` and invoke `python` through a resolved
command. Missing Python prints `BLOCKED: Python 3 is required only for legacy global retirement`;
ordinary project installation continues.

- [ ] **Step 4: Make active materialization project-only**

Remove every global row from `manifests/managed-v6.tsv`; Task 3's legacy inventory is the only
remaining ownership map. Remove global branches, config materialization, **home** diagnostics, and
`scope global` from both adapter materializers and full-refresh wrappers. Retain a project-local
completion diagnostic: ordinary setup and upgrade print
`NATIVE_GOAL_RUNTIME: PENDING reason=live-qualification-not-run`; only Task 6's bound live
qualification may print `READY`, and an explicitly requested live qualification prints `BLOCKED`
with its concrete missing capability. No diagnostic names global setup as remediation.
`scripts/merge-settings.py` accepts only project scope for active reconciliation.

Delete the four global templates only after `test-workflow-parity.sh` proves Task 2's policy mapping
and Task 3's cleanup inventory exists. Keep changelog history untouched.

- [ ] **Step 5: Convert global full-refresh tests into retirement tests**

Remove assertions that global full refresh succeeds. Replace them with:

- `--global -f --dry-run` remains non-mutating and points to `--retire-global`;
- project full refresh never writes home;
- the cleanup-only manifest is rejected by active materialization;
- all former global fixture coverage is owned by `test-retire-global.*`.

- [ ] **Step 6: Run installation and retirement suites GREEN**

Run:

```bash
bash tests/template/test-setup-flags.sh
bash tests/template/test-setup.sh
bash tests/template/test-full-refresh.sh
bash tests/template/test-dual-layout.sh
bash tests/template/test-retire-global.sh
bash tests/template/test-contracts.sh
```

Expected: all pass and `rg` finds no active global scope:

```bash
rg -n -- '(--global|-Global|scope global|Scope.*global)' \
  setup.sh setup.ps1 scripts/materialize-adapters.* scripts/full-refresh.* manifests/managed-v6.tsv
```

Expected: only the explicit retired-flag diagnostic, with no active materialization branch.

- [ ] **Step 7: Commit project-only installation**

```bash
git add -A setup.sh setup.ps1 manifests scripts GLOBAL-FORGE.template.md \
  GLOBAL-CLAUDE.template.md GLOBAL-AGENTS.template.md settings/global-settings.template.json \
  tests/template/
git commit -m "feat: make Forge installation project-only"
```

### Task 5: Repository-Local Native-Goal Ledger

**Files:**
- Create: `hooks/lib/goal-ledger.sh`
- Create: `hooks/lib/goal-ledger.ps1`
- Modify: `hooks/check-state-updated.sh`
- Modify: `hooks/check-state-updated.ps1`
- Modify: `state.template.md`
- Modify: `commands/forge-goal.md`
- Modify: `commands/new-feature.md`
- Modify: `commands/fix-bug.md`
- Modify: `FORGE.template.md`
- Modify: `settings/settings.template.json`
- Modify: `settings/settings-windows.template.json`
- Modify: `settings/codex-config.template.toml`
- Modify: `manifests/managed-v6.tsv`
- Modify: `tests/template/test-goal-feasibility.sh`
- Modify: `tests/template/test-goal-feasibility.ps1`
- Modify: `tests/template/test-hooks.sh`
- Modify: `tests/template/test-workflow-parity.sh`
- Modify: `tests/template/test-contracts.sh`

**Interfaces:**
- Consumes: canonical `.forge/local/state.md`, Stop event JSON, physical worktree root, and Git common directory.
- Produces: `goal-ledger activate|charge`; repository ledger `<git-common-dir>/forge-goals/<nonce>`; derived activation count, ceiling, turn count, and exhaustion diagnostics.

- [ ] **Step 1: Replace global-authorization fixtures with failing repository-ledger tests**

In `tests/template/test-goal-feasibility.sh`, create a real Git repository with a linked worktree and
an active state block:

```markdown
## /goal session

| Field | Value |
| --- | --- |
| nonce | 11111111-1111-4111-8111-111111111111 |
| objective_hash | obj123 |
| activation_id | 22222222-2222-4222-8222-222222222222 |
| activation_host | claude |
| activated_at | 2026-09-28T00:00:00Z |
| workflow_command | /new-feature smoke |
| turn_count | 0 |
| turn_ceiling | 20 |
| activation_count | 1 |
| evidence_path | .forge/local/evidence/latest.json |
```

Publish activation 1, then feed the same Stop JSON twice:

```bash
bash "$P/.forge/hooks/lib/goal-ledger.sh" activate \
  --project "$P" --state "$P/.forge/local/state.md"
printf '%s' '{"host":"claude","session_id":"s1","turn_id":"t1"}' |
  bash "$P/.forge/hooks/lib/goal-ledger.sh" charge \
    --project "$P" --state "$P/.forge/local/state.md" --event-json -
printf '%s' '{"host":"claude","session_id":"s1","turn_id":"t1"}' |
  bash "$P/.forge/hooks/lib/goal-ledger.sh" charge \
    --project "$P" --state "$P/.forge/local/state.md" --event-json -
assert_equals "$(find "$COMMON/forge-goals/$NONCE/turns" -type f | wc -l | tr -d ' ')" "1" \
    "duplicate Stop delivery charges once"
```

Add cases for 20 unique turns, a 21st turn, two concurrent writers for the same ID, simultaneous
different IDs, linked-worktree resume, state count reduction, state deletion, objective mismatch,
symlinked ledger ancestors, malformed records, and a second sequential activation that raises the
same objective ceiling from 20 to 40 without resetting count. Deleting, duplicating, or skipping an
activation sequence number must fail closed.

- [ ] **Step 2: Run goal/hook tests and confirm RED**

Run:

```bash
bash tests/template/test-goal-feasibility.sh
bash tests/template/test-hooks.sh
bash tests/template/test-workflow-parity.sh
```

Expected: FAIL because the ledger helper does not exist and Stop still requires the sealed global
authorization writer.

- [ ] **Step 3: Implement the Bash no-clobber ledger**

`hooks/lib/goal-ledger.sh` exposes `activate` and `charge`. Parse the goal table by exact normalized field
names, validate the UUID/objective/positive integers, resolve physical project and Git common paths,
and use:

```bash
LEDGER_ROOT="$GIT_COMMON/forge-goals"
GOAL_ROOT="$LEDGER_ROOT/$NONCE"
ACTIVATION_ROOT="$GOAL_ROOT/activations"
TURN_ROOT="$GOAL_ROOT/turns"
```

Create an immutable `binding` on first activation with this schema:

```text
format=forge-goal-ledger-v2
project_id=<sha256 of normalized physical git common dir>
nonce=<uuid>
objective_hash=<hash>
turn_tranche=20
```

`activate` publishes the next sequential `activations/<8-digit-count>` record with format,
nonce/objective, the state's UUIDv4 activation ID, host, activation timestamp, and state hash. Existing activation
records must be contiguous from 1, regular, non-linked, and uniquely bound. Derive
`turn_ceiling = 20 * activation_count`; never rewrite the binding or an activation record.

Serialize turn publication with an atomically-created ledger lock directory. While holding the
lock, validate that `turns/` contains a contiguous sequence from `00000001` through the current
count, scan the immutable records for the normalized/hashed turn ID, and return idempotently only
when the existing record is byte-equivalent. Otherwise publish the next sequential turn record
through a same-filesystem temporary regular file plus `ln` no-clobber. Concurrent unique events
therefore receive different contiguous sequence numbers, concurrent duplicate events charge once,
and deleting, duplicating, renaming, or skipping any turn record fails closed. A process that finds
an abandoned or malformed lock fails closed with a concrete tamper/recovery diagnostic; it never
guesses or lowers the count. Count only the validated contiguous regular, non-linked turn records.

At count `>= turn_ceiling`, atomically publish `checkpoint` and `exhausted` bound to the current
state hash, phase, next step, count, and ceiling, then emit:

```text
FORGE_GOAL_BUDGET_EXHAUSTED: checkpoint=<physical-path>
```

Never create an external authorization record and never consult `$HOME`.

- [ ] **Step 4: Implement PowerShell parity**

`hooks/lib/goal-ledger.ps1` accepts:

```powershell
param(
    [ValidateSet('activate','charge')][string]$Action,
    [Parameter(Mandatory=$true)][string]$Project,
    [Parameter(Mandatory=$true)][string]$State,
    [string]$EventJson = '-'
)
```

Use `FileMode.CreateNew` for no-clobber publication, reject reparse points on every ancestor, write
UTF-8 without BOM and LF newlines, and produce byte-equivalent binding/turn/checkpoint schemas.

- [ ] **Step 5: Make Stop a thin ledger caller**

Delete the global authorization/writer/dual-ledger implementation from
`hooks/check-state-updated.*`. Retain evidence reminders, stuck detection, and ordinary workflow
checkpoint behavior. When the state contains an active nonce, pass the untouched Stop JSON to the
new helper exactly once. Propagate helper exit `2` and tamper diagnostics; do not silently continue.

Add both helpers to `manifests/managed-v6.tsv` under `.forge/hooks/lib/`.

- [ ] **Step 6: Update goal state and activation semantics**

Change `state.template.md` and `commands/forge-goal.md` to the exact fields in Step 1. Define:

- native `/goal` or explicit native Goal request is the human activation;
- first activation generates an activation UUID, sets ceiling `20` and activation count `1`, then
  calls `goal-ledger activate`;
- same-objective reactivation after exhaustion generates a new activation UUID, retains nonce/count,
  increments activation count, sets ceiling to `20 * activation_count`, then calls
  `goal-ledger activate`;
- changed objective creates a new nonce/count zero/ceiling 20;
- project state is accounting, not authority to start host continuation; and
- PR/merge/deploy/publish/destructive/external mutations still pause.

Update new-feature/fix-bug checkpoints to populate the state only after the user has invoked or
explicitly requested the native Goal.

- [ ] **Step 7: Replace obsolete permissions**

Remove all Forge-owned `~/.forge/bin`, `~/.forge/goal-*`, `forge-goal-authorize`, and
`forge-goal-capture` denies from project settings, including the stale Codex comment that goal
authorization lives outside project workspace-write roots. Replace the contradictory
`FORGE.template.md` requirement for a human-created trusted goal-authorization record with the
approved rule: the human's native `/goal` or explicit native Goal request is activation authority,
while authenticated live qualification governs only readiness claims. Add worktree-safe ledger
protection:

```json
"Edit(**/.git/forge-goals/**)",
"Bash(*forge-goals*:*)"
```

and the Windows slash equivalent. This glob must match the physical Git common directory when the
active root is a linked worktree; add a test whose worktree-local `.git` is a pointer file and whose
ledger lives under the primary checkout's Git common directory. Keep Codex writable roots
restricted to `.forge/local`; the Git common directory remains outside workspace-write. Update
settings-retirement logic so upgrades remove only the exact obsolete Forge deny values from
recognized Forge templates.

- [ ] **Step 8: Run goal, hook, settings, and parity tests GREEN**

Run:

```bash
bash tests/template/test-goal-feasibility.sh
bash tests/template/test-hooks.sh
bash tests/template/test-merge-settings.sh
bash tests/template/test-workflow-parity.sh
bash tests/template/test-contracts.sh
```

Expected: all pass; `rg` over active hooks/settings/workflows finds no `goal-authorizations`,
`goal-captures`, or `forge-goal-authorize` runtime reference.

- [ ] **Step 9: Commit project-local goal accounting**

```bash
git add hooks/lib/goal-ledger.sh hooks/lib/goal-ledger.ps1 \
  hooks/check-state-updated.sh hooks/check-state-updated.ps1 state.template.md \
  commands/forge-goal.md commands/new-feature.md commands/fix-bug.md FORGE.template.md \
  settings/ manifests/managed-v6.tsv tests/template/
git commit -m "feat: make native goal accounting repository-local"
```

### Task 6: Remove Global Goal Runtime and Rebuild Qualification

**Files:**
- Delete: `scripts/forge-goal-authorize.sh`
- Delete: `scripts/forge-goal-authorize.ps1`
- Delete: `scripts/forge-goal-capture.sh`
- Delete: `scripts/forge-goal-capture.ps1`
- Modify: `scripts/qualify-goal-feasibility.sh`
- Modify: `scripts/qualify-goal-feasibility.ps1`
- Modify: `scripts/qualify-runtime-final.sh`
- Modify: `scripts/qualify-runtime-final.ps1`
- Modify: `scripts/materialize-adapters.sh`
- Modify: `scripts/materialize-adapters.ps1`
- Modify: `scripts/merge-settings.py`
- Modify: `manifests/managed-v6.tsv`
- Modify: `tests/template/test-goal-feasibility.sh`
- Modify: `tests/template/test-goal-feasibility.ps1`
- Modify: `tests/template/test-dual-layout.sh`
- Modify: `tests/template/test-contracts.sh`
- Modify: `docs/qualification/agent-mode-selection.md`

**Interfaces:**
- Consumes: installed project-only Forge, repository-local ledger, authenticated native Claude/Codex clients when live qualification is requested.
- Produces: deterministic goal qualification plus optional authenticated live receipts under the current source workflow's `.forge/local/evidence/`; no home capture or authorization records.

- [ ] **Step 1: Add failing no-global qualification contracts**

Add assertions:

```bash
for retired in \
  scripts/forge-goal-authorize.sh scripts/forge-goal-authorize.ps1 \
  scripts/forge-goal-capture.sh scripts/forge-goal-capture.ps1; do
    assert_file_missing "$REPO_ROOT/$retired" "$retired is not an active runtime helper"
done
assert_not_contains "$REPO_ROOT/manifests/managed-v6.tsv" 'goal-authorize' \
    "active manifest installs no global authorizer"
assert_not_contains "$REPO_ROOT/scripts/qualify-goal-feasibility.sh" "$HOME/.forge" \
    "qualification has no home Forge dependency"
```

Create a clean-home project install, run deterministic qualification, and assert:

```text
GOAL_DETERMINISTIC: PASS
GLOBAL_HARNESS: NOT_REQUIRED
```

When `--live claude` or `--live codex` is requested with an unavailable/unauthenticated binary,
assert `GOAL_LIVE: BLOCKED host=<host> reason=<concrete>` and nonzero status rather than fake evidence.

- [ ] **Step 2: Run goal/qualification tests and confirm RED**

Run:

```bash
bash tests/template/test-goal-feasibility.sh
bash tests/template/test-dual-layout.sh
bash tests/template/test-contracts.sh
```

Expected: FAIL because global helpers and capture assumptions remain.

- [ ] **Step 3: Rebuild deterministic qualification around disposable project state**

Make `qualify-goal-feasibility.*` accept:

```text
--project <canonical-root>
--evidence-dir <project-local-or-disposable-path>
--live none|claude|codex
```

The deterministic phase creates an objective/state through documented activation semantics, feeds
unique and duplicate Stop events, verifies the Git-common ledger, resumes from a linked worktree,
forces exhaustion, and verifies the stuck warning. It writes only under the supplied project and
evidence directory.

The live phase uses the native product surface rather than a fabricated capture file:

- Claude: `claude -p "/goal <bounded disposable condition including stop after 20 turns>"` with the
  normal authenticated profile and no trust bypass.
- Codex: an ordinary native `/goal` in the authenticated client surface or the supported goal tool
  contract, never an agent-authored substitute.

Record client path/version, project root, objective, status transitions, and evidence hashes in the
source workflow evidence directory. Do not install a capture helper downstream.

- [ ] **Step 4: Remove active global-goal code and identities**

Delete the four helper sources and all materializer sealing/identity code. Remove global goal rows
from the active manifest (Task 4 should already have removed the scope) and remove their special
hash/permission cases from `merge-settings.py`. Historical paths remain only in
`manifests/legacy-v6-global.tsv` and changelog prose.

- [ ] **Step 5: Update final qualification aggregation**

Make `qualify-runtime-final.*` classify each host separately:

```text
NATIVE_GOAL_RUNTIME: READY host=claude evidence=<path>
NATIVE_GOAL_RUNTIME: BLOCKED host=codex reason=authentication-required
```

Normal workflows remain ready when a native Goal is unavailable; only the named host's goal
capability is blocked. Final release claims require both supported hosts or an explicitly accepted
documented limitation.

- [ ] **Step 6: Run qualification and source-absence tests GREEN**

Run:

```bash
bash tests/template/test-goal-feasibility.sh
bash tests/template/test-dual-layout.sh
bash tests/template/test-contracts.sh
bash scripts/qualify-goal-feasibility.sh --project "$PWD" \
  --evidence-dir "$PWD/.forge/local/evidence/project-only-goal" --live none
```

Expected: deterministic PASS and no active source reference outside the cleanup inventory/history:

```bash
rg -n -- '(goal-authorizations|goal-captures|forge-goal-authorize|forge-goal-capture)' \
  setup.sh setup.ps1 hooks settings manifests/managed-v6.tsv commands FORGE.template.md \
  scripts/qualify-goal-feasibility.sh scripts/qualify-goal-feasibility.ps1 \
  scripts/materialize-adapters.sh scripts/materialize-adapters.ps1
```

Expected: no matches.

- [ ] **Step 7: Commit runtime removal and qualification**

```bash
git add -A scripts hooks settings manifests tests/template docs/qualification
git commit -m "feat: qualify native goals without global Forge"
```

### Task 7: Publish the Project-Only Installation Contract

**Files:**
- Modify: `README.md`
- Modify: `docs/getting-started.md`
- Modify: `docs/guides/upgrading.md`
- Modify: `docs/guides/setup-scenarios.md`
- Modify: `docs/guides/agent-assisted-setup.md`
- Modify: `docs/reference/commands.md`
- Modify: `docs/reference/cheatsheet.md`
- Modify: `docs/troubleshooting.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `tests/template/test-contracts.sh`

**Interfaces:**
- Consumes: final CLI, version, adapter, goal, and cleanup behavior from Tasks 1-6.
- Produces: Forge 6.3 release documentation with one-command install/upgrade and a separate legacy-retirement path.

- [ ] **Step 1: Add failing documentation contracts**

Update the release contract in `tests/template/test-contracts.sh`:

```bash
EXPECTED_FORGE_VERSION='6.3'
assert_contains "$README" 'setup.sh --upgrade' "README shows one-command project upgrade"
assert_contains "$README" 'cat .forge/version' "README shows the project version pin"
assert_contains "$README" 'different repositories may run different Forge versions' \
    "README explains per-repository versions"
assert_contains "$README" 'setup.sh --retire-global' \
    "README documents separate legacy cleanup"
```

Scan active documentation before the Version History/Changelog sections and fail on language that
requires `--global`, `-Global`, `~/.forge`, global memory setup, or a global goal helper for normal
operation.

- [ ] **Step 2: Run documentation contracts and confirm RED**

Run:

```bash
bash tests/template/test-contracts.sh
```

Expected: FAIL because the README and guides still instruct global setup and publish 6.2.

- [ ] **Step 3: Rewrite the primary install and upgrade path**

The README quick start must lead with only:

```bash
cd /path/to/project
/path/to/forge/setup.sh
```

and:

```bash
cd /path/to/project
/path/to/forge/setup.sh --upgrade
```

Place adjacent PowerShell equivalents. Explain that `.forge/version` is committed, exact, and
independent per repository. Show `cat .forge/version` and `Get-Content .forge\version`.

Move global retirement into a clearly labeled one-time migration section with preview, digest copy,
and apply. State that it is never needed for a fresh project-only installation.

- [ ] **Step 4: Synchronize every guide and reference**

Update getting-started, upgrading, setup scenarios, agent-assisted setup, commands, cheatsheet, and
troubleshooting to use the same commands and terms. Document:

- complete local policy and memory behavior;
- canonical `AGENTS.md` plus Claude bridge;
- optional project-owned agent context;
- native-goal 20-turn tranches and separate external-mutation authorization;
- exact per-repository versioning; and
- safe retirement classifications and digest mismatch remediation.

Historical changelog/version-table entries remain unchanged.

- [ ] **Step 5: Publish Forge 6.3 release metadata**

Change the README badge/history and prepend `docs/CHANGELOG.md` with `## 6.3 — 2026-09-28`. Cover:

- project-only complete installation;
- exact `.forge/version` pin and removal of machine/Claude duplicate stamps;
- complete local policy with KISS/YAGNI;
- canonical AGENTS plus Claude bridge;
- project-local native-goal ledger and removed global helpers; and
- preview/digest/apply legacy-global retirement.

- [ ] **Step 6: Run documentation contracts GREEN**

Run:

```bash
bash tests/template/test-contracts.sh
```

Expected: PASS with synchronized 6.3 surfaces and no active normal-use global instructions.

- [ ] **Step 7: Commit documentation and release metadata**

```bash
git add README.md docs/ tests/template/test-contracts.sh
git commit -m "docs: publish Forge 6.3 project-only setup"
```

### Task 8: Full Verification and Real Cross-Host Acceptance

**Files:**
- Create: `.forge/local/evidence/project-only-forge-install/e2e-report.md` (ignored evidence)
- Modify only if a named verification failure requires a bounded TDD repair.

**Interfaces:**
- Consumes: the complete implementation and exact branch candidate.
- Produces: deterministic suite results, Windows CI evidence, authenticated Claude/Codex project-only handoff evidence, and honest limitations.

- [ ] **Step 1: Run static and full deterministic suites**

Run:

```bash
git diff --check main...HEAD
bash tests/template/run-all.sh
```

Expected: all registered Unix suites pass. Also run the focused PowerShell suites locally when
`pwsh` exists:

```bash
pwsh -NoProfile -File tests/template/test-retire-global.ps1
pwsh -NoProfile -File tests/template/test-goal-feasibility.ps1
pwsh -NoProfile -File tests/template/test-full-refresh.ps1
```

Expected: PASS or explicitly `UNAVAILABLE` locally; Windows PowerShell 5.1 CI remains mandatory.

- [ ] **Step 2: Build two disposable project-only controls**

Create Project A and Project B under one disposable root. Snapshot Project B and the fake home.
Install Forge only in Project A and verify:

```bash
test "$(cat "$A/.forge/version")" = '6.3'
test ! -e "$HOME_FIXTURE/.forge"
test "$(snapshot_project "$B")" = "$B_BEFORE"
```

Run ordinary `new-feature`, `fix-bug`, and `quick-fix` smoke journeys from natural user requests;
do not mention Forge internals, Claude/Codex roles, receipt filenames, or expected implementation
steps in the prompts.

- [ ] **Step 3: Run Claude-to-Codex native-goal handoff**

In a fresh Claude session rooted at Project A, use a native Goal whose user-visible condition is:

```text
Implement the approved disposable feature until its acceptance tests pass and verification is
recorded, or stop after 20 turns. Pause before any PR, push, merge, deployment, publication,
destructive action, secret access, or other external mutation.
```

Stop at a durable checkpoint, open the exact same worktree in Codex, explicitly activate the same
bounded native objective, and continue. Return to Claude for final review/verification. Prove the
nonce/objective remain bound and the Git-common turn count never decreases or resets.

- [ ] **Step 4: Run Codex-to-Claude control and budget exhaustion**

Repeat in the opposite direction. In a separate disposable objective, charge 20 unique turns and
prove the twentieth publishes `FORGE_GOAL_BUDGET_EXHAUSTED`, the next step is preserved, and no
substantive twenty-first turn occurs. Explicitly reactivate the same objective and prove the ceiling
becomes 40 while the consumed count remains 20.

- [ ] **Step 5: Prove evidence and authorization boundaries**

Freeze one candidate, complete paired reviews and verification, then deliberately mutate an in-scope
file. Verify `SHIP_READY:true` is withdrawn and a new candidate/review cycle is required. Attempt a
simulated PR-create/push/merge/deploy command without separate authorization and prove the existing
gate blocks it; native goal activation must not satisfy that gate.

- [ ] **Step 6: Prove global retirement against a disposable historical home**

Materialize a historical global fixture with personal Claude/Codex bytes. Run preview, capture the
digest, apply that digest, and prove only `REMOVE` items disappeared. Mutate one byte after a second
preview and prove apply blocks with no partial mutation.

- [ ] **Step 7: Record the acceptance report**

Write the ignored E2E report with:

- exact source HEAD and tree;
- exact installed `.forge/version`;
- client paths/versions and authentication state;
- disposable roots;
- commands/prompts used;
- turn counts, checkpoints, and host transitions;
- deterministic and live outcomes;
- external-mutation/evidence invalidation results; and
- every unavailable or accepted limitation, without relabeling it PASS.

- [ ] **Step 8: Run branch verification before review**

Run:

```bash
git status --short
git diff --check main...HEAD
bash tests/template/run-all.sh
bash scripts/verify-runtime.sh discovery --project-root "$PWD"
```

Expected: tracked worktree clean, all deterministic suites green, runtime discovery truthful. Then
freeze the exact staged-clean candidate and enter the Forge paired review, verify-app, E2E receipt,
Windows CI, promotion, and PR-authorization workflow. Do not push, open, or merge a PR without the
separate user authorization required at that boundary.
