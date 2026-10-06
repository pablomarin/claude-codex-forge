# Inactive Goal Stop evidence output

Immutable base: main, 306af0e2ec5a3dc08c37674df3b0f77986446daf.

## Reproduction and cause

The installed build-evidence hook prints FORGE_GOAL_EVIDENCE markers and JSON even when canonical Goal nonce is absent or the template placeholder. A completed quick-fix fixture with no Goal reproduces this with both Claude and Codex payloads in Bash and PowerShell. check-state-updated may also invoke this builder when the fingerprint is stale. Forge6.4.6 suppressed completed workflow advisories but left this independent emitter unconditional.

The actual MSAI feature worktree remains /new-feature nautilus-v2-research with inactive Goal. The app chat Check project status has primary cwd /Users/pablomarin/Code/msai-v2 while local commands target the linked worktree. The pasted primary branch/HEAD match that chat directory. An absent tool workdir cannot be reconstructed safely from Stop; no sibling selection, state reset, branch switch or Goal activation is part of this repair.

## Bounded repair

Keep evidence computation, atomic fingerprint publication, state validation and enforcement unchanged. Default build-evidence output is silent when the canonical Goal nonce is inactive; active Goal retains its existing JSON. Preserve explicit full diagnostic inspection using --diagnostic in Bash and -Diagnostic in PowerShell. The diagnostic option emits data and grants no Goal authorization. Use the first nonce row case-insensitively in both builders, matching existing Goal accounting; cover capitalized keys and duplicate rows without new parsing machinery. Keep registered hook command strings unchanged and Codex allow output valid. Only diagnostic tests requesting inactive Goal payload fields opt into the diagnostic mode.

Owned paths: hooks/build-evidence.sh and .ps1; focused test-build-evidence.sh and test-stop-workflow.sh/.ps1, existing test-hooks.sh and pr-authorization-fixture.py diagnostic callsites; docs/reference/hooks.md and changelog/version badge.

## Acceptance and TDD

1. Observe RED: no-Goal ordinary/completed workflow registered builder and inline Stop paths emit no FORGE_GOAL_EVIDENCE markers; current source fails this assertion.
2. Test missing/empty/template nonce, active and completed quick-fix/new-feature/fix-bug, first/repeat and CRLF Stops in Bash and PowerShell with Claude and Codex as main.
3. Run both registered Stop commands, not only check-state-updated; assert no inactive Goal JSON, valid Codex allow output and preserved event-worktree fingerprint locality. Linked feature and completed primary controls must retain their respective context.
4. Active Goal output, shared ledger charging and budget refusal retain owning executable controls. Invalid canonical state, active workflow checkpoint, changelog and shipping gates remain enforced.
5. Explicit diagnostics retain schema/receipt/breaker and no-Goal data inspection; the option never activates the ledger.
6. Focused suites and fast source gate; installed setup journeys for both main hosts using Bash/PS7. Native Windows5.1 remains CI-owned. No authenticated vendor or native host claims from fixture events.

One bounded fresh configured plan review precedes production edits; distinct final code-spec/code-quality review receipts and app/E2E verification certify one frozen candidate. Publish Forge6.4.7 only with the completed change. Downstream active states, custom configuration and project changes must be preserved when updating the repaired installation. Keep unrelated prior P3 advisories deferred.
