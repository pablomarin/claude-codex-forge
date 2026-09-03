# Remove Blocking Native-Host Receipts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Forge's false protected-host authorization gate so Claude Code and Codex sessions can continue any linked worktree in the same repository without reopening the client or minting a worktree receipt.

**Architecture:** Keep `host-context.{sh,ps1}` as a compatibility launcher so existing trusted hook command definitions do not change, but reduce it to a no-op hook plus a fixed-target launcher that exports declared host metadata. Agent and council dispatchers use that declared value only for routing, while candidate, review, verification, state, and promotion evidence remain bound to the exact physical worktree and artifact.

**Tech Stack:** Bash, PowerShell 5.1, Python 3 settings merger, JSON hook templates, Git worktrees, shell contract suites, authenticated Claude Code and Codex clients.

**Spec:** `docs/superpowers/specs/2026-09-03-remove-blocking-host-receipts-design.md`

## Global Constraints

- Immutable workflow base: `refs/heads/main` at `7a0417b6e64e6f0efb1f62f433b50aaa83cc8cca`.
- Do not add global hooks, a daemon, leases, session-indexed authority, or worktree locks.
- Do not share candidate, review, verification, state, goal, authorization, or promotion evidence between worktrees.
- Keep existing managed `.codex/hooks.json` host-context command strings byte-identical during this upgrade.
- Treat `main_host` as declared routing metadata, not authenticated initiating-session identity.
- Retain only `claude` and `codex` as accepted declared-host values.
- The compatibility launcher may execute only the canonical agent or council dispatcher.
- Leave existing `~/.forge/host-contexts` data inert; do not delete user-home data during setup or upgrade.
- No test, harness, child command, or real-user E2E may use `--dangerously-bypass-hook-trust` or an equivalent trust or permission bypass.
- If a real Claude Code or Codex client is unavailable or unauthenticated, report the E2E as `BLOCKED`; do not substitute a fake-engine pass.
- Bash and PowerShell decisions must remain behaviorally equivalent, with PowerShell 5.1 exercised in Windows CI.

## File Structure

| Responsibility | Files |
| --- | --- |
| Compatibility no-op hook and fixed-target host declaration | `hooks/lib/host-context.sh`, `hooks/lib/host-context.ps1` |
| Reviewer routing, receipts, and multi-turn binding | `hooks/lib/agent-dispatch.sh`, `hooks/lib/agent-dispatch.ps1` |
| Council routing and topology receipts | `hooks/lib/council-dispatch.sh`, `hooks/lib/council-dispatch.ps1` |
| Obsolete shell guard and Claude permission retirement | `hooks/check-bash-safety.sh`, `hooks/check-bash-safety.ps1`, `settings/settings.template.json`, `settings/settings-windows.template.json`, `scripts/merge-settings.py` |
| Core and platform regressions | `tests/template/test-agent-dispatch.sh`, `tests/template/test-agent-dispatch.ps1`, `tests/template/test-council-dispatch.sh`, `tests/template/test-council-dispatch.ps1`, `tests/template/test-dual-engine-e2e.sh`, `tests/template/test-dual-engine-e2e.ps1`, `tests/template/test-bash-safety.sh`, `tests/template/test-merge-settings.sh`, `tests/template/test-hooks.sh`, `tests/template/test-setup.sh`, `tests/template/test-contracts.sh` |
| Workflow and user documentation | `commands/new-feature.md`, `commands/fix-bug.md`, `commands/opinion.md`, `skills/council/SKILL.template.md`, `skills/council/references/peer-review-protocol.md`, `docs/guides/parallel-sessions.md`, `docs/reference/hooks.md`, `docs/reference/file-structure.md`, `docs/CHANGELOG.md` |

---

### Task 1: Replace Receipt Authority with Declared-Host Routing

**Files:**
- Modify: `tests/template/test-agent-dispatch.sh:9-125,258-306`
- Modify: `tests/template/test-agent-dispatch.ps1:3-81,181-188`
- Modify: `tests/template/test-council-dispatch.sh:12-72`
- Modify: `tests/template/test-council-dispatch.ps1:7-48`
- Modify: `tests/template/test-dual-engine-e2e.sh:10-129`
- Modify: `tests/template/test-dual-engine-e2e.ps1:6-115`
- Modify: `hooks/lib/host-context.sh:1-127`
- Modify: `hooks/lib/host-context.ps1:1-103`
- Modify: `hooks/lib/agent-dispatch.sh:5-10,55-106,638-657,716-719`
- Modify: `hooks/lib/agent-dispatch.ps1:24-32,577-601,648-674`
- Modify: `hooks/lib/council-dispatch.sh:5-42,136-142`
- Modify: `hooks/lib/council-dispatch.ps1:29-45,72-74`

**Interfaces:**
- Consumes: Existing Bash `hook --host claude|codex` and `launch --host claude|codex -- COMMAND`; existing PowerShell `-Mode hook|launch -Host claude|codex -LaunchTarget agent|council`.
- Produces: `FORGE_NATIVE_HOST=claude|codex` in the launched child; `hook` exits zero without persistent state; `launch` rejects every target except the canonical agent/council dispatcher; review and council receipts continue recording `main_host`, requested/attempted/actual engine, fallback, role/seat, and exact candidate/worktree identity.

- [ ] **Step 1: Write failing no-receipt and routing-metadata tests**

  In `test-agent-dispatch.sh`, delete `capture_context`, delete its callsites, and make `launch_dispatch` set only the guarded source-test launcher path:

  ```bash
  launch_dispatch() {
      local dir="$1" host="$2"; shift 2
      (cd "$dir" && PATH="$FAKES:$PATH" FORGE_HOST_CONTEXT_TEST_MODE=1 \
        FORGE_HOST_CONTEXT_TEST_LAUNCHER="$DISPATCH" FORGE_DISPATCH_TEST_MODE=1 \
        bash "$HOST_CONTEXT" launch --host "$host" -- "$DISPATCH" "$@")
  }
  ```

  Add this regression before the reviewer matrix:

  ```bash
  start_test "host compatibility hook and launcher need no receipt authority"
  S=$(scratch_dir dispatch-no-host-receipt); make_repo "$S"; mkdir -p "$S/home"
  printf '{"session_id":"ignored","cwd":"%s"}\n' "$S" \
    | (cd "$S" && HOME="$S/home" bash "$HOST_CONTEXT" hook --host claude)
  assert_equals "$?" "0" "legacy hook command remains a successful compatibility no-op"
  assert_file_missing "$S/home/.forge/host-contexts" "compatibility hook creates no host authority directory"
  printf 'review\n' > "$S/prompt.txt"
  run_dispatch "$S" claude ignored auto >/dev/null 2>&1
  assert_equals "$?" "0" "fixed launcher reaches review without a receipt"
  assert_receipt_value "$S" main_host claude
  assert_receipt_value "$S" first_attempted_engine codex
  assert_receipt_value "$S" actual_engine codex
  ```

  Add assertions that the launched child sees `FORGE_NATIVE_HOST=codex` and does not see `FORGE_NATIVE_SESSION_ID`, `FORGE_HOST_CONTEXT_FILE`, or `FORGE_HOST_CONTEXT_LAUNCHER_HASH`. Keep the wrong-launcher test but expect fixed-target rejection rather than a hash mismatch. Assert a direct dispatcher invocation with missing or invalid `FORGE_NATIVE_HOST` blocks before candidate capture.

  Mirror this behavior in `test-agent-dispatch.ps1`: remove `Set-Context` and `issue-test`, call `-Mode hook` with a scratch user profile, assert no `.forge\host-contexts`, invoke `-Mode launch` directly, and assert `main_host=claude` with the opposite auto reviewer.

  Change council fixtures to set `FORGE_NATIVE_HOST=claude` directly instead of installing a fake `host-context` verifier. Assert `topology.receipt` includes `main_host=claude` and that every `actual_engine.<seat>.<phase>` equals the fake executable actually invoked.

  In both dual-engine seams, remove the receipt-issuing hook call. Run the installed launcher first as Codex and then as Claude without any authority directory, assert both reviews succeed, and assert candidate/worktree identity remains present in both receipts.

  Also start one Codex-declared and one Claude-declared review concurrently with distinct output paths. Wait for both process IDs, require both exit zero, and assert their receipts have distinct invocation IDs but the same expected worktree identity. This proves concurrent launches have no shared host-authority file while avoiding an intentional race on one output path.

- [ ] **Step 2: Run focused suites and verify RED**

  Run:

  ```bash
  bash tests/template/test-agent-dispatch.sh
  bash tests/template/test-council-dispatch.sh
  bash tests/template/test-dual-engine-e2e.sh
  ```

  Expected: FAIL because the compatibility hook still writes receipts, launch still requires one, and dispatchers still call `host-context verify`.

  On Windows CI or a Windows checkout, run:

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/template/test-agent-dispatch.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/template/test-council-dispatch.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/template/test-dual-engine-e2e.ps1
  ```

  Expected: the same receipt creation/requirement failures.

- [ ] **Step 3: Replace the Bash host-context implementation**

  Retain fixed canonical agent/council path resolution and the installed-harness guard around source-test path substitution. Delete authority-root, identity, revision, hashing, schema, TTL, nonce, receipt read/write, `issue-test`, and `verify` code. Implement only:

  ```bash
  case "$mode" in
  hook)
      case "$host" in claude|codex) ;; *) die_context 'hook host must be claude or codex' ;; esac
      cat >/dev/null 2>&1 || true
      ;;
  launch)
      case "$host" in claude|codex) ;; *) die_context 'fixed launcher host must be claude or codex' ;; esac
      # Canonicalize $1, then require exact equality with launcher_context or council_context.
      export FORGE_NATIVE_HOST="$host"
      unset FORGE_NATIVE_SESSION_ID FORGE_HOST_CONTEXT_FILE FORGE_HOST_CONTEXT_LAUNCHER_HASH
      exec "$@"
      ;;
  *) die_context 'usage: host-context.sh hook|launch' ;;
  esac
  ```

  The test-only path substitution remains unavailable when the script is materialized inside the current Git worktree; it is test plumbing, never host authority.

- [ ] **Step 4: Replace the PowerShell host-context implementation**

  Restrict `Mode` to `hook|launch`, remove `SessionId`, consume and discard stdin in hook mode, and launch only `Get-Launcher` or `Get-Council`:

  ```powershell
  if ($Mode -eq 'hook') {
      $null = [Console]::In.ReadToEnd()
      exit 0
  }
  $env:FORGE_NATIVE_HOST = $EngineHost
  Remove-Item Env:FORGE_NATIVE_SESSION_ID,Env:FORGE_HOST_CONTEXT_FILE,Env:FORGE_HOST_CONTEXT_LAUNCHER_HASH -ErrorAction SilentlyContinue
  $target = if ($LaunchTarget -eq 'council') { Get-Council } else { Get-Launcher }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $target @boundArguments
  exit $LASTEXITCODE
  ```

  Delete authority paths, hashes, TTLs, nonces, receipt parsing/writing, `issue-test`, and `verify`. Preserve JSON argument transport so empty and spaced arguments remain exact.

- [ ] **Step 5: Remove receipt verification from agent dispatchers**

  In Bash, replace receipt verification with:

  ```bash
  active_host=${FORGE_NATIVE_HOST:-}
  case "$active_host" in
    claude|codex) ;;
    *)
      write_early_receipt invariant declared-main-host-missing
      printf 'BLOCKED[invariant]: declared main host must be claude or codex; receipt=%s\n' "$receipt" >&2
      exit 2
      ;;
  esac
  case "$engine" in auto) [ "$active_host" = claude ] && first=codex || first=claude ;; *) first="$engine" ;; esac
  ```

  Mirror the enum check in PowerShell using `$env:FORGE_NATIVE_HOST -cin @('claude','codex')`. Remove `HOST_CONTEXT`/`HostContext`, `FORGE_HOST_CONTEXT_FILE`, and `contextHash` dependencies. Remove `context_hash` from new/resume council session metadata and its equality check; retain exact active host, session ID, engine, role, seat, question, artifact, worktree, qualification, snapshot, canary, and seat bindings.

- [ ] **Step 6: Remove receipt verification from council dispatchers**

  In Bash, use:

  ```bash
  main=${FORGE_NATIVE_HOST:-}
  case "$main" in claude|codex) ;; *) die 'declared main host must be claude or codex' ;; esac
  ```

  Mirror the enum check in PowerShell. Keep `main_host`, intended and actual seat engines, topology mode, fallback reason, seat/session/turn identities, and output hashes. Do not add a replacement authentication token.

- [ ] **Step 7: Run focused suites and verify GREEN**

  Run:

  ```bash
  bash tests/template/test-agent-dispatch.sh
  bash tests/template/test-council-dispatch.sh
  bash tests/template/test-dual-engine-e2e.sh
  ```

  Expected: all PASS; no host authority directory is created; exact candidate/worktree invalidation tests remain green.

- [ ] **Step 8: Commit the core fix**

  ```bash
  git add hooks/lib/host-context.sh hooks/lib/host-context.ps1 hooks/lib/agent-dispatch.sh hooks/lib/agent-dispatch.ps1 hooks/lib/council-dispatch.sh hooks/lib/council-dispatch.ps1 tests/template/test-agent-dispatch.sh tests/template/test-agent-dispatch.ps1 tests/template/test-council-dispatch.sh tests/template/test-council-dispatch.ps1 tests/template/test-dual-engine-e2e.sh tests/template/test-dual-engine-e2e.ps1
  git commit -m "fix: remove blocking host receipt authority"
  ```

### Task 2: Retire Obsolete Receipt Permissions Without Changing Hook Commands

**Files:**
- Modify: `tests/template/test-bash-safety.sh:84-93`
- Modify: `tests/template/test-merge-settings.sh:191-216`
- Modify: `tests/template/test-hooks.sh:2928-2976`
- Modify: `hooks/check-bash-safety.sh:90-97`
- Modify: `hooks/check-bash-safety.ps1:100-104`
- Modify: `settings/settings.template.json:24-60`
- Modify: `settings/settings-windows.template.json:24-63`
- Modify: `scripts/merge-settings.py:1-8,2460-2522`

**Interfaces:**
- Consumes: Exact legacy Forge-owned permission values for `~/.forge/host-contexts`; unchanged host-context hook registrations in Claude and Codex templates.
- Produces: New installs contain no host-context read/write restrictions; upgrades remove only the exact obsolete Forge values; hook command strings and unrelated user permissions remain unchanged.

- [ ] **Step 1: Write failing permission-retirement and hook-stability tests**

  Change the Bash safety corpus to allow both legacy hook invocations because they are now no-ops:

  ```bash
  start_test "bash: host compatibility hook is harmless from an agent command"
  assert_allow_sh 'printf '\''{"thread_id":"ignored"}'\'' | .forge/hooks/lib/host-context.sh hook --host codex' \
      "Codex compatibility hook is a no-op"
  assert_allow_sh 'echo '\''{"session_id":"ignored"}'\'' | bash .forge/hooks/lib/host-context.sh hook --host claude' \
      "Claude compatibility hook is a no-op"
  ```

  In `test-merge-settings.sh`, merge a recognized Forge settings template into a user file containing all four obsolete values plus custom permissions. Assert:

  ```python
  retired = {
      "Read(~/.forge/host-contexts/**)",
      "Edit(~/.forge/host-contexts/**)",
      "Bash(*.forge/host-contexts*:*)",
  }
  assert retired.isdisjoint(set(settings["permissions"]["deny"]))
  assert "~/.forge/host-contexts" not in settings["sandbox"]["filesystem"]["denyWrite"]
  assert "Bash(project-custom:*)" in settings["permissions"]["deny"]
  ```

  Add a control using a non-Forge template and prove the same strings remain, so generic settings merges do not delete user values.

  In `test-hooks.sh`, require both settings templates to omit `~/.forge/host-contexts`. Continue asserting that Claude and Codex register the existing host-context command on both `SessionStart` and `UserPromptSubmit`, but describe it as a stable compatibility no-op. Compare each full command string to its pre-fix literal so this change cannot manufacture a new Codex hook hash.

- [ ] **Step 2: Run focused suites and verify RED**

  Run:

  ```bash
  bash tests/template/test-bash-safety.sh
  bash tests/template/test-merge-settings.sh
  bash tests/template/test-hooks.sh
  ```

  Expected: FAIL because safety hooks still block manual no-op invocation, templates still contain obsolete denies, and the add-only merger preserves retired values.

- [ ] **Step 3: Remove the obsolete guard and new-install permissions**

  Delete only the `host-context hook` branch from both bash-safety implementations. Remove these exact values from Unix and Windows settings templates:

  ```text
  Read(~/.forge/host-contexts/**)
  Edit(~/.forge/host-contexts/**)
  Bash(*.forge/host-contexts*:*)
  ~/.forge/host-contexts
  ```

  Do not change the `forgeManagedId: host-context` groups or their command strings.

- [ ] **Step 4: Add exact managed retirement to the settings merger**

  Add:

  ```python
  RETIRED_FORGE_PERMISSION_DENIES = {
      "Read(~/.forge/host-contexts/**)",
      "Edit(~/.forge/host-contexts/**)",
      "Bash(*.forge/host-contexts*:*)",
  }
  RETIRED_FORGE_SANDBOX_DENY_WRITES = {"~/.forge/host-contexts"}

  def is_forge_project_settings_template(template):
      return any(
          hook.get("forgeManagedId") == "host-context"
          for groups in template.get("hooks", {}).values()
          if isinstance(groups, list)
          for group in groups
          if isinstance(group, dict)
          for hook in group.get("hooks", [])
          if isinstance(hook, dict)
      )
  ```

  When and only when the predicate is true, filter the exact retired values from `user.permissions.deny` and `user.sandbox.filesystem.denyWrite`, append one deterministic change description per modified collection, and preserve every other value and object. Update the module strategy comment to document this one exact managed-retirement exception to add-only merging.

- [ ] **Step 5: Run focused suites and verify GREEN**

  Run:

  ```bash
  bash tests/template/test-bash-safety.sh
  bash tests/template/test-merge-settings.sh
  bash tests/template/test-hooks.sh
  bash tests/template/test-full-refresh.sh
  ```

  Expected: all PASS; custom permission rows remain; host-context hook command strings are byte-identical.

- [ ] **Step 6: Commit permission retirement**

  ```bash
  git add hooks/check-bash-safety.sh hooks/check-bash-safety.ps1 settings/settings.template.json settings/settings-windows.template.json scripts/merge-settings.py tests/template/test-bash-safety.sh tests/template/test-merge-settings.sh tests/template/test-hooks.sh
  git commit -m "fix: retire obsolete host receipt permissions"
  ```

### Task 3: Pin Linked-Worktree Continuation and Update the User Contract

**Files:**
- Modify: `tests/template/test-setup.sh:1412-1443`
- Modify: `tests/template/test-contracts.sh:2048-2062,2353-2417,2419-2460`
- Modify: `commands/new-feature.md:5-27`
- Modify: `commands/fix-bug.md:5-26`
- Modify: `commands/opinion.md:15-25`
- Modify: `skills/council/SKILL.template.md:60-75`
- Modify: `skills/council/references/peer-review-protocol.md:7-20`
- Modify: `docs/guides/parallel-sessions.md:1-69`
- Modify: `docs/reference/hooks.md:1-38`
- Modify: `docs/reference/file-structure.md:35-47`
- Modify: `docs/CHANGELOG.md:1-75`

**Interfaces:**
- Consumes: Task 1 receipt-free launch behavior, Task 2 stable hook strings, existing Git-common-directory router, and exact-worktree evidence.
- Produces: Deterministic linked-worktree routing/hook-stability coverage and one consistent user promise across workflows, council guidance, hook reference, parallel-session guide, file map, and changelog.

- [ ] **Step 1: Write failing setup and documentation contract tests**

  Extend the existing `primary Codex router delegates only to the trusted current worktree` setup test to capture these full strings before linked-worktree refresh and assert they remain identical afterward:

  ```text
  bash "$(git rev-parse --show-toplevel)/.forge/hooks/lib/host-context.sh" hook --host codex
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$root = (& git rev-parse --show-toplevel).Trim(); & (Join-Path $root '.forge\hooks\lib\host-context.ps1') -Mode hook -Host codex"
  ```

  Keep the existing two-sibling routing and unrelated Git-common-directory rejection.

  In `test-contracts.sh`, require both workflows to contain:

  ```text
  A session opened in the primary checkout may continue the linked worktree
  No per-worktree Forge receipt
  task-root reopening is required
  concurrent sessions are allowed
  candidate-bound evidence becomes stale
  ```

  Require opinion/council documentation to call `main_host` routing metadata, require the hook reference to describe the retained host-context event as a compatibility no-op, and assert active runtime/docs contain none of:

  ```text
  protected current host receipt is required
  protected main host context is required
  reopen the host in the worktree
  SessionStart hook creates and UserPromptSubmit refreshes the protected host receipt
  ```

  Replace the PowerShell `receipt_hash=` assertion with checks that the compatibility launcher exports `FORGE_NATIVE_HOST` and removes all three legacy receipt environment variables.

- [ ] **Step 2: Run setup and contract tests and verify RED**

  Run:

  ```bash
  bash tests/template/test-setup.sh
  bash tests/template/test-contracts.sh
  ```

  Expected: setup hook strings remain stable, while the documentation contract fails on the old reopen, protected-receipt, and concurrent-edit prohibition text.

- [ ] **Step 3: Replace workflow and council instructions**

  Replace resume/start step 4 in both workflows with:

  ```markdown
  4. Continue work in the linked worktree from the current or a later Claude Code or Codex
     session. A session opened in the primary checkout may continue the linked worktree by using
     it as the working directory; opening the client at the worktree path remains optional. The
     installed adapter declares the current host for reviewer routing. No per-worktree Forge
     receipt, copied session identity, hook-trust bypass, or task-root reopening is required.
  ```

  Describe `host-context launch` in opinion/council material as the fixed-target compatibility launcher that declares the main host for routing. Remove claims that it authenticates or hashes the initiating session.

- [ ] **Step 4: Update public guidance and changelog**

  State that repository hook setup/trust happens once unless the native host reports a genuinely new or changed definition. State that concurrent sessions are allowed, Forge provides no edit lock, and any session's candidate mutation naturally invalidates stale evidence. Include this exact journey:

  ```text
  Open either host in the repository -> say "get into this worktree and continue" -> work there ->
  close or switch hosts -> repeat without reopening at the worktree path.
  ```

  In the changelog, correct the current v6 active behavior. Historical ADR and research documents remain historical and are not rewritten.

- [ ] **Step 5: Run contract and behavior suites and verify GREEN**

  Run:

  ```bash
  bash tests/template/test-setup.sh
  bash tests/template/test-contracts.sh
  bash tests/template/test-hooks.sh
  bash tests/template/test-agent-dispatch.sh
  bash tests/template/test-council-dispatch.sh
  bash tests/template/test-dual-engine-e2e.sh
  ```

  Expected: all PASS; active documentation contains no worktree-root reopen remediation; unrelated Git repositories remain rejected by the Codex router.

- [ ] **Step 6: Commit linked-worktree contract changes**

  ```bash
  git add tests/template/test-setup.sh tests/template/test-contracts.sh commands/new-feature.md commands/fix-bug.md commands/opinion.md skills/council/SKILL.template.md skills/council/references/peer-review-protocol.md docs/guides/parallel-sessions.md docs/reference/hooks.md docs/reference/file-structure.md docs/CHANGELOG.md
  git commit -m "docs: allow cross-host worktree continuation"
  ```

### Task 4: Final Verification, Real-User E2E, and HE Insights Proof

**Files:**
- Verify: all files committed by Tasks 1-3
- Runtime evidence only: `.forge/local/reviews/`, `.forge/local/evidence/`, and `/tmp/forge-host-handoff-e2e` (uncommitted)
- Downstream refresh target after read-only preview: `/Users/pablomarin/Code/he-vivi-insights`

**Interfaces:**
- Consumes: Final candidate, installed authenticated `codex` and `claude`, HE Insights primary checkout, and `/Users/pablomarin/Code/he-vivi-insights/.worktrees/insight-display-priority`.
- Produces: Complete suite evidence, no-bypass real-client transcripts, downstream plan-review proof, and a frozen candidate ready for PR/merge/cleanup.

#### E2E Use Cases

**UC-HOST-01 — Later Codex session continues a linked worktree**

- **Actor:** Developer returning in a new authenticated Codex session opened at the HE Insights repository checkout.
- **Scenario:** The display-priority worktree contains an approved plan and durable Forge state. The developer asks the new session to enter that worktree and continue plan review.
- **Intent:** Resume work without reopening Codex at the worktree path or trusting hooks again.
- **Interface:** CLI (normal Codex client).
- **Setup:** Forge is refreshed in HE Insights, existing project hooks have ordinary persisted Codex trust, and the display-priority worktree exists.
- **Steps:**
  1. Start a normal Codex session at `/Users/pablomarin/Code/he-vivi-insights` without a trust-bypass option.
  2. Say `Get into /Users/pablomarin/Code/he-vivi-insights/.worktrees/insight-display-priority and continue the recorded plan-review step.`
  3. Let Codex invoke the installed reviewer from the linked worktree.
- **Verification:** Stdout shows the linked-worktree path and a completed reviewer selection; it never explains that a protected receipt or task-root reopening is required.
- **Persistence:** Close that session, start another normal Codex session at the primary checkout, repeat the request, and confirm the next invocation reaches the same linked-worktree state. Start Codex directly in the linked worktree once as a control and confirm it reaches the same dispatcher without additional Forge trust.

**UC-HOST-02 — Claude Code continues the Codex worktree**

- **Actor:** Developer switching from Codex to an authenticated Claude Code session during the same HE Insights feature.
- **Scenario:** Codex has left durable Forge state and candidate-bound review evidence in the display-priority worktree. The developer asks Claude Code, opened at the repository checkout, to continue it.
- **Intent:** Change hosts without copying receipts, session identifiers, or reopening at the worktree path.
- **Interface:** CLI (normal Claude Code client).
- **Setup:** UC-HOST-01 has completed and the same worktree remains available.
- **Steps:**
  1. Start Claude Code normally at `/Users/pablomarin/Code/he-vivi-insights` with ordinary project trust and no permission bypass.
  2. Say `Get into /Users/pablomarin/Code/he-vivi-insights/.worktrees/insight-display-priority and continue from .forge/local/state.md.`
  3. Let Claude Code invoke the next recorded review or verification action in that worktree.
- **Verification:** Stdout shows the worktree's next durable step and successful dispatcher progress; no worktree receipt, copied native session ID, or reopen instruction appears.
- **Persistence:** Close Claude Code, start Codex normally at the primary checkout, and confirm Codex can read the same durable checkpoint and continue.

**UC-HOST-03 — Concurrent sessions do not contend on host authority**

- **Actor:** Developer running authenticated Codex and Claude Code sessions against one coordinated worktree.
- **Scenario:** Both sessions perform read-only review actions with distinct output files in a disposable linked worktree while its candidate remains unchanged.
- **Intent:** Use concurrent agents without a shared host-receipt race or Forge worktree lock.
- **Interface:** CLI (normal Codex and Claude Code clients).
- **Setup:** Create a disposable `fix/host-handoff-e2e` worktree through the installed lifecycle helper, add a harmless tracked fixture file there, and configure separate review output paths. Do not mutate the display-priority candidate for this concurrency check.
- **Steps:**
  1. Start normal Codex and Claude Code sessions from the HE Insights repository checkout without bypass flags.
  2. Ask each session to enter the disposable host-handoff worktree and run its assigned read-only review.
  3. Wait for both reviews, then change one candidate file through one session.
- **Verification:** Both initial invocations return human-readable reviewer results without a host-authority collision; after mutation, the next verification explains that candidate-bound evidence is stale.
- **Persistence:** Re-run review against the new candidate and confirm new receipts validate while old receipts remain stale.

**UC-HOST-04 — Another repository cannot use the primary Codex router**

- **Actor:** Developer with an unrelated Git repository at `/tmp/forge-host-handoff-e2e/unrelated`.
- **Scenario:** A hook payload names a cwd whose Git common directory differs from the registered Forge repository.
- **Intent:** Ensure removing host receipts does not weaken repository-bound hook routing.
- **Interface:** CLI (Codex hook command).
- **Setup:** Initialize `/tmp/forge-host-handoff-e2e/unrelated` without copying Forge evidence.
- **Steps:**
  1. Submit a normal hook event naming the unrelated cwd to HE Insights' registered primary router.
  2. Observe stderr and inspect the unrelated repository through the CLI.
- **Verification:** Stderr explains that the Git common directory differs, and the unrelated repository contains no routed Forge output.
- **Persistence:** Submit the event again and confirm the router rejects it consistently without creating state.

#### Surface coverage decision

- CLI: Covered by UC-HOST-01 through UC-HOST-04.
- UI: N/A — Forge's user-facing surface for this change is the Claude Code/Codex coding-agent session and installed command/hook flow, not a web UI.
- API: N/A — this change adds no public network API.

- [ ] **Step 1: Run static safety and focused suites**

  Run:

  ```bash
  git diff --check main...HEAD
  rg -n 'FORGE_HOST_CONTEXT_FILE|FORGE_NATIVE_SESSION_ID|FORGE_HOST_CONTEXT_LAUNCHER_HASH' hooks/lib/agent-dispatch.sh hooks/lib/agent-dispatch.ps1 hooks/lib/council-dispatch.sh hooks/lib/council-dispatch.ps1
  rg -n -- '--dangerously-bypass-hook-trust' tests/template/test-dual-engine-e2e.sh tests/template/test-dual-engine-e2e.ps1
  bash tests/template/test-agent-dispatch.sh
  bash tests/template/test-council-dispatch.sh
  bash tests/template/test-bash-safety.sh
  bash tests/template/test-merge-settings.sh
  bash tests/template/test-hooks.sh
  bash tests/template/test-setup.sh
  bash tests/template/test-full-refresh.sh
  bash tests/template/test-dual-engine-e2e.sh
  ```

  Expected: both `rg` commands return no matches and every focused suite PASS. Receipt-environment names remain only in the compatibility launcher's explicit cleanup and in negative regression coverage; the trust-bypass flag remains only in documentation that prohibits it.

- [ ] **Step 2: Run the complete Bash template suite**

  Run:

  ```bash
  bash tests/template/run-all.sh
  ```

  Expected: PASS with zero failed suites on an unchanged candidate.

- [ ] **Step 3: Verify PowerShell parity**

  Require Windows CI to run:

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/template/test-agent-dispatch.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/template/test-council-dispatch.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/template/test-dual-engine-e2e.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/template/run-all.ps1
  ```

  Expected: all PASS. A missing Windows runner is `BLOCKED`, not parity proof.

- [ ] **Step 4: Preview and refresh HE Insights**

  Run the read-only preview first:

  ```bash
  cd /Users/pablomarin/Code/he-vivi-insights
  /Users/pablomarin/Code/claude-codex-forge/setup.sh -F --dry-run
  ```

  Require `UPGRADE: READY`, inspect the exact owned paths, and confirm authorization before the non-preview refresh. Do not bypass an ownership blocker or infer permission to delete customized project content.

- [ ] **Step 5: Run the real-client no-bypass continuation matrix**

  First use the current Codex desktop task, opened outside the HE Insights linked worktree, to run the recorded plan-review command with tool cwd set to `/Users/pablomarin/Code/he-vivi-insights/.worktrees/insight-display-priority`. This directly exercises the desktop user journey that originally failed.

  Then confirm the normal `codex` and `claude` clients are installed and authenticated and create later host sessions with these commands:

  ```bash
  cd /Users/pablomarin/Code/he-vivi-insights
  codex exec --sandbox workspace-write --color never --output-last-message /tmp/forge-host-handoff-e2e/codex-later.txt 'Get into /Users/pablomarin/Code/he-vivi-insights/.worktrees/insight-display-priority and continue the recorded plan-review step. Do not change production code.'
  claude -p --permission-mode auto 'Get into /Users/pablomarin/Code/he-vivi-insights/.worktrees/insight-display-priority and continue from .forge/local/state.md. Run only the next recorded read-only review action; do not change production code.' > /tmp/forge-host-handoff-e2e/claude-handoff.txt
  codex exec --sandbox workspace-write --color never --output-last-message /tmp/forge-host-handoff-e2e/codex-return.txt 'Get into /Users/pablomarin/Code/he-vivi-insights/.worktrees/insight-display-priority and report the next incomplete durable step from Forge state. Do not change files.'
  ```

  Run the concurrent read-only pair with distinct requested output paths, wait for both process IDs, and record both exit codes. Use `ps -ww -p PID -o command=` while they run and retain the three transcripts under `/tmp/forge-host-handoff-e2e`; reject the result if any command or transcript contains a trust or permission bypass. Execute UC-HOST-04 directly through HE Insights' installed `codex-worktree-dispatch.sh` with JSON cwd `/tmp/forge-host-handoff-e2e/unrelated`.

  Expected: both hosts continue the display-priority worktree from a primary-checkout session, a later Codex session repeats the flow, overlapping read-only reviews do not contend on host authority, candidate mutation invalidates only candidate-bound evidence, and the unrelated Git common directory remains blocked.

- [ ] **Step 6: Freeze, review, deliver, and clean up**

  If any verification fails, return to the owning task, add the discriminating regression there, apply the smallest correction, and rerun that task's full GREEN command before continuing. Once stable, freeze the exact final candidate, run the required code-spec/code-quality review pair, rerun final verification after any mutation, then use the repository's normal PR workflow to push, merge, update local `main`, delete the merged local and remote branch, and remove this worktree.
