# Forge upgrade state and version-ledger repair

## Reproduction

Base: `9e9a54ef85adf8b88f51d85f51797fade17c9556` (`main`, Forge 6.4.0).

1. Upgrade an existing Forge V6 project whose `.forge/version` contains an older supported V6 release. The installer stamps the new release after writing `.forge/installed-files.tsv`, so the ledger records the old version file digest. A second unchanged setup rewrites the ledger.
2. Upgrade an existing Forge V6 project whose generated local state predates the current `Identity` and `Receipts` sections. Routine materialization preserves that state byte-for-byte, then current `workflow-state show` rejects it and setup reports `NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=canonical-state-unreadable`.

Both symptoms were observed in the MSAI downstream upgrade from the legacy `6` stamp to `6.4.0`.

## Proven root causes

- `scripts/materialize-adapters.sh` and `scripts/materialize-adapters.ps1` write the installation ledger before replacing `.forge/version`. Their manifest writers prefer the existing file over the intended release text, so upgrades hash stale bytes.
- Both materializers create `state.md` only when absent. They have no bounded compatibility transition for older Forge-generated canonical state, although the installed runtime now requires the current control schema.

## Existing solution and constraints

- `hooks/lib/worktree-lifecycle.*` already provides the narrative boundary: preserve `## State`, `## Open Questions`, and `## Blockers` while rebuilding control surfaces from the current template. Its loose heading extraction is not sufficient as an upgrade recognizer; the upgrade must first prove the complete legacy top-level layout so that no other developer content is silently discarded.
- `workflow-state.*` and `state-path.*` intentionally fail closed on malformed or ambiguous canonical state. The upgrade must not weaken those readers or carry old review, Goal, or PR-authorization evidence forward.
- Full refresh stages the live state and invokes the same materializer under `FORGE_TRANSACTION_STAGE=1`. The routine compatibility transition must be disabled in that staged invocation: `scripts/merge-settings.py` remains the owner of V5 translation, transaction backup, allowlisting, and rollback. Existing full-refresh behavior must not regress.
- Bash and Windows PowerShell 5.1 materializers are paired implementations. Routine project setup must remain idempotent and must not require Python solely for this transition.

## Minimal production change

1. In each materializer, classify an existing local state before managed writes, except when `FORGE_TRANSACTION_STAGE=1`; the staged full-refresh path preserves its existing `merge-settings.py` ownership and behavior.
2. Preserve a state that passes the portable current-shape contract exactly. The transition classifier uses the stricter Bash-compatible encoding rule on both platforms: the schema marker is case-sensitive and must begin at byte zero with no BOM; CRLF is accepted. A BOM-prefixed or case-variant file is unrecognized and therefore preserved, never migrated.
3. Recognize only a checked-in historical transitional-V6 fixture: one schema marker, the exact ordered generated top-level sections (`Workflow`, `State`, `Open Questions`, `Blockers`, `Update Rules`), no `Identity`, `/goal session`, `PR authorization`, or `Receipts`, and no unknown top-level heading or free text outside the historical generated envelope. Accept the runtime's full inactive spelling set (`empty`, `none`, hyphen, or em dash) only when Phase and Next step are also empty or dash placeholders. Reject checked checklist/evidence rows, Goal nonces, PR authorization text anywhere in the file, review/receipt-shaped lines in narrative, duplicate headings/fields, mixed current/legacy controls, active commands, and every unrecognized historical shape. The checked-in fixtures, not a permissive heuristic, define eligibility.
4. For an eligible file, capture its hash, create or byte-verify one exact content-addressed ignored backup at `.forge/local/state.md.bak.<sha256>`, build a candidate from the current `state.template.md`, and replace only the template `## State`, `## Open Questions`, and `## Blockers` ranges with the exact legacy ranges (including `### Now`). Revalidate the candidate with the current reader. Immediately re-hash the live source and refuse on change, then publish with the same same-directory compare-and-swap pattern as `workflow-state.*` (`mv` on Bash; `[IO.File]::Replace` on PowerShell 5.1). Print the backup path and migration result. The backup is durable on routine setup and byte-idempotent on subsequent runs.
5. On an exact eligible fixture, either complete the transition or stop before other materializer-managed paths change. For every active, incomplete, mixed, duplicated, BOM-prefixed, custom, or otherwise unrecognized state, preserve the file byte-for-byte and retain today's successful installation plus `NORMAL_PROJECT_WORKFLOWS: BLOCKED` behavior; do not turn compatibility ambiguity into a new setup failure. Emit a stable compatibility diagnostic with a recovery path: finish any active workflow with the installed runtime, or manually copy the state aside, seed the current `state.template.md`, restore only reviewed narrative, and rerun setup. The no-partial-write claim applies only to an attempted recognized transition and the materializer; setup's pre-existing scaffolding directories remain outside that guarantee.
6. For `.forge/version`, always hash the intended release bytes rather than an existing stamp. Write `.forge/installed-files.tsv` to a same-directory temporary file and atomically rename it, then atomically replace `.forge/version` last. This prevents a truncated ledger and makes the first successful upgrade record the final release bytes without relying on a second run. Full refresh retains its transaction ordering and rollback.
7. Keep Bash 3.2 and Windows PowerShell 5.1 behavior equivalent, including BOM/CRLF classification, content-addressed backup naming, diagnostics, and atomic publication.

## Changed paths

- `scripts/materialize-adapters.sh`
- `scripts/materialize-adapters.ps1`
- `scripts/merge-settings.py` only if a narrow stage-ownership guard or diagnostic-target adjustment is required after the regression test; prefer keeping the guard in the materializers
- `tests/template/test-setup.sh`
- `tests/template/test-full-refresh.sh`
- `tests/template/test-full-refresh.ps1`
- the narrow owning PowerShell installer suite for direct materialization
- `docs/CHANGELOG.md`
- `README.md`

No runtime workflow reader, application code, or downstream project source is in scope.

## Regression tests

- Upgrade from an old supported V6 version and assert the ledger digest for `.forge/version` equals the final file digest on the first run, the ledger is complete, and state, stamp, ledger, and backup remain byte-identical on the second run.
- Check in the exact historical transitional state fixture(s) from supported V6 upgrade history, including the MSAI-producing shape, rather than constructing one ad hoc. For each fixture, declare and assert `preserved`, `migrated`, or `blocked`.
- Upgrade the eligible inactive fixture and assert setup succeeds, `workflow-state show` accepts the result, the three narrative ranges and `### Now` survive byte-for-byte, generated Update Rules are refreshed, no old gate evidence migrates, the diagnostic names the backup, and its content/hash are exact.
- Assert current state is byte-preserved. Assert active state, mixed/duplicated/incomplete state, unknown top-level content, evidence-shaped text in narrative, PR authorization text, Goal nonce, checked workflow evidence, and BOM variants are not migrated, remain byte-identical, allow installation to complete, and produce the existing blocked-workflow plus actionable compatibility diagnostics. Assert CRLF variants classify identically on Bash and PowerShell. Assert a source-state race during a recognized transition stops before other materializer-managed paths change.
- Run `bash tests/template/test-agent-dispatch.sh` as a focused regression because its intentionally incomplete canonical-state fixture must continue to install successfully.
- Exercise full refresh in dry-run and apply modes with the existing active V5 translation and destination-race fixtures. Assert the materializer does not perform the routine transition under `FORGE_TRANSACTION_STAGE=1`, dry-run/apply agree, the transaction remains allowlisted, and rollback/backups remain owned by full refresh.
- Exercise the direct compatibility contract through PowerShell when available locally; Windows PowerShell 5.1 CI remains the authoritative Windows environment.

The tests must fail against 6.4.0 before implementation and pass after the minimal repair.

## Acceptance criteria

- A first upgrade produces a ledger whose `.forge/version` digest matches the final installed release file.
- A proven inactive older generated state becomes valid current state without losing its narrative.
- Old checklist, Goal, review, and PR-authorization evidence cannot certify the rebuilt state.
- Active or ambiguous legacy state is never migrated or overwritten; installation retains its existing success semantics while normal workflows remain visibly blocked with an actionable recovery diagnostic.
- A second setup is byte-idempotent for the state, version stamp, and ledger.
- Full-refresh V5 translation, dry-run truthfulness, allowlisting, destination-race detection, and rollback behavior remain unchanged.
- Bash and PowerShell 5.1 implementations remain behaviorally equivalent.
- `bash tests/template/test-setup.sh`, `bash tests/template/test-full-refresh.sh`, and `bash tests/template/test-agent-dispatch.sh` pass as focused owning suites.
- `bash tests/template/run-fast.sh` passes on the final candidate.
- Release metadata is exactly `6.4.1` in the changelog source of truth and README badge. The version-history table remains milestone-only per repository policy.

## User-journey coverage

This is internal installer/runtime compatibility with no application UI, public API, or product CLI journey. Preliminary and final E2E are N/A only if the candidate-bound verifier confirms that classification. The executable installer fixtures are the acceptance boundary.
