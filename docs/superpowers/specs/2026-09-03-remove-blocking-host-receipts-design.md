# Design: Remove Blocking Native-Host Receipts

**Date:** 2026-09-03
**Status:** Draft for developer review

## Problem

Forge introduced protected native-host receipts in the dual-engine rewrite (`d44eed1`,
2026-08-31) to prevent the model from declaring which host was main. The receipt is keyed to the
physical worktree root plus Git common directory and binds absolute dispatcher paths. Plan review
therefore fails when a user opens Claude Code or Codex in the primary checkout and asks it to
continue an existing linked worktree, even though all commands run in that worktree.

The receipt does not deliver its claimed current-session authentication. `launch --host
claude|codex` selects a host from the command line, reads that host's latest receipt, and exports
the receipt's stored session ID. It never compares the caller with an independently authenticated
current-session ID. Any session can therefore use either recent host receipt when it exists. The
extra gate adds failure modes without protecting candidate correctness.

Candidate, review, verification, state, goal, authorization, and promotion evidence already bind
the exact physical worktree and artifact. Those are the controls that prevent stale or sibling
worktree evidence from certifying a change.

## User Contract

Forge setup installs the repository's Claude Code and Codex hooks once. After the host's ordinary
repository trust step, the user can:

1. open Claude Code or Codex in the repository's primary checkout;
2. create or select a feature/fix worktree;
3. tell the current session to work in that linked worktree;
4. close the session;
5. open a later session in either host at the repository checkout; and
6. tell it to continue the same worktree.

The user does not reopen the application at the worktree path, trust Forge separately in every
worktree, copy or synthesize receipts, or run a hook-trust bypass. Starting directly in a linked
worktree remains supported but is optional.

Concurrent sessions are allowed. Forge does not lock a worktree or coordinate simultaneous edits.
If one session changes a candidate another session reviewed, the existing candidate fingerprint
invalidates the stale evidence.

## Native Host Constraints

- Codex owns project-hook discovery and trust. Newly discovered or changed hook definitions may
  require review through Codex's normal `/hooks` flow; Forge must not bypass or imitate that trust
  decision. See [Codex hook review and trust](https://developers.openai.com/codex/hooks/#review-and-trust-hooks).
- Claude Code owns workspace trust and supports trusting an accepted parent folder. Forge must not
  create a second, per-worktree trust ceremony on top of it. See [Claude Code workspace trust](https://code.claude.com/docs/en/hooks#workspace-trust).
- Neither documented interface currently gives a project dispatcher an independently authenticated,
  agent-unforgeable current-host identity at launch. Forge therefore does not claim to authenticate
  one.

## Goals

1. Remove protected native-host receipts from every blocking review and council path.
2. Preserve one repository hook setup/trust boundary for all linked worktrees.
3. Keep all artifact and workflow evidence exact-worktree-bound.
4. Keep reviewer and council engine selection explicit and honestly recorded.
5. Avoid changing stable Codex hook definitions unnecessarily during upgrade.
6. Prove the normal Claude Code and Codex user journeys without trust-bypass flags.
7. Preserve Unix and Windows behavior parity.

## Non-goals

- Authenticating the initiating Claude Code or Codex session when neither host supplies a proven,
  agent-unforgeable launch-time identity.
- Adding global hooks, a daemon, leases, session-indexed authority, or worktree locks.
- Sharing candidate or review evidence between worktrees.
- Automatically approving a genuinely new or changed Codex hook definition.
- Preventing a trusted local user or trusted project process from invoking a Forge dispatcher.

## Design

### 1. Host is routing metadata, not authorization

The native Claude and Codex adapters declare `claude` or `codex` when invoking the shared
dispatcher. This declaration is a trusted workflow instruction, not a security boundary: the
current host APIs do not give Forge an independent, agent-unforgeable identity to compare at
launch. The dispatcher accepts only those exact values and records the field as
`declared_main_host` (or temporarily retains `main_host` with an explicit metadata-only contract
during compatibility migration).

The declared host selects the preferred opposite-engine reviewer for `--engine auto` and the
default council topology. It is not described as authenticated session identity and is not a
certification input.

The dispatcher independently records:

- declared main host;
- requested reviewer engine;
- first attempted engine;
- actual launched engine;
- fallback and fallback reason;
- role/profile or council seat; and
- exact candidate/worktree identity.

Review and council validation checks that each launched engine matches the requested/fallback or
seat decision. Forge may certify which reviewer executable it launched and which candidate it
reviewed; it does not certify the initiating application's identity.

### 2. Remove receipt authority while preserving upgrade compatibility

Remove receipt issuance, protected receipt lookup, schema/TTL/nonce validation, current/active host
files, and receipt-derived environment plumbing from the authorization path.

To avoid forcing an unnecessary Codex hook re-trust on existing repositories, the current
`host-context hook --host <host>` command definition remains temporarily as a no-op compatibility
shim. The current `host-context launch --host <host> -- <fixed-dispatcher>` interface similarly
becomes a thin compatibility wrapper that:

1. validates the host enum;
2. permits only the fixed agent or council dispatcher under the current worktree's canonical Forge
   directory;
3. exports the declared host as metadata; and
4. executes the target without reading or writing a protected receipt.

The wrapper must not retain receipt directories, TTLs, nonces, session IDs, hashes presented as
authority, or missing-receipt failures. Project refresh keeps the existing managed
`.codex/hooks.json` command text byte-identical when it already contains the current entries, so
this fix itself does not manufacture a new hook-trust prompt. A later version may remove the inert
entry through the ordinary hook-update and trust process.

### 3. Repository hooks serve linked worktrees

Codex keeps its existing stable primary-checkout router. For every native event it:

1. reads the event's absolute `cwd`;
2. resolves the event worktree and Git common directory;
3. requires the common directory to match the registered repository; and
4. invokes the target worktree's canonical hook.

Claude hooks continue resolving the event `cwd` and target worktree through their existing project
settings. Trust in the repository or an accepted parent folder remains the native host's concern;
Forge does not create a second worktree trust system.

Worktree creation may copy missing configuration mirrors for validation and host discovery, but
must not require a new protected Forge receipt or instruct the user to reopen the session.

### 4. Worktree evidence remains unchanged

The following stay bound to the exact physical worktree, Git state, workflow base, and candidate
hash as applicable:

- `.forge/local/state.md`;
- candidate fingerprints;
- plan and code review receipts;
- verification and E2E receipts;
- goal and external-mutation authorization;
- PR authorization; and
- candidate promotion/commit checks.

Evidence from one linked worktree cannot satisfy another. Any candidate mutation invalidates the
evidence whose fingerprint changed, regardless of which host or session performed the mutation.

## Error Handling

Forge must never emit `protected current host receipt is required`, `reopen the host in the
worktree`, or equivalent remediation.

It may still block for concrete failures such as:

- event Git common directory differs from the registered repository;
- target worktree or canonical dispatcher is absent or symlinked;
- candidate/review/verification evidence belongs to another worktree or stale artifact;
- requested/actual reviewer engine or council seat is inconsistent;
- host-native project hooks are genuinely unavailable or disabled; or
- a protected external mutation lacks user authorization.

If Codex reports that a new or changed hook definition needs review, setup directs the user to the
normal `/hooks` flow. That is repository hook trust, not a Forge worktree receipt requirement.

## Migration

- Existing protected host receipt files become unused. Setup does not need to delete user-home
  receipts to make the project work; they may be left inert and documented as safely removable.
- Project refresh replaces `host-context` behavior with the compatibility wrapper while preserving
  the existing hook command text where possible.
- Remove Forge permission entries whose only purpose was to protect `~/.forge/host-contexts` after
  verifying that no active code reads or writes the directory.
- Remove workflow prose that requires SessionStart/UserPromptSubmit receipt creation or reopening
  a task in a linked worktree.
- Update runtime-readiness checks so receipt presence is not a readiness requirement. Native hook
  discovery/execution, authentication, and required capabilities remain separate readiness facts.

## Test Strategy

### Deterministic tests

1. A dispatcher launched without any protected host receipt reaches candidate capture/review.
2. Claude and Codex compatibility wrappers declare the correct routing host and allow only the two
   fixed dispatchers.
3. `auto` selects the opposite engine from the declared host and records the actual engine.
4. Explicit engine selection, fallback, and council seat topology record the actual launched
   engine and reject inconsistent output.
5. A primary-checkout Codex router event with a linked-worktree `cwd` executes that worktree's hook.
6. A different Git common directory is rejected by the existing router.
7. Candidate/review/verification evidence from one linked worktree remains invalid in a sibling.
8. Concurrent sessions require no host-authority file and cannot invalidate one another merely by
   starting or submitting a prompt.
9. No active code or permission contract requires `~/.forge/host-contexts`.
10. Existing managed `.codex/hooks.json` command text remains byte-identical across this upgrade.
11. Bash and PowerShell make the same decisions.

### Real user E2E

Use authenticated installed Claude Code and Codex clients with ordinary persisted project trust:

1. initialize or refresh Forge in a disposable repository;
2. open Codex normally in the primary checkout;
3. create a linked feature worktree and continue work there without reopening Codex;
4. close Codex, open a new Codex session in the primary checkout, and continue the same worktree;
5. close Codex, open Claude Code in the primary checkout, and continue that worktree;
6. repeat the handoff in the opposite direction;
7. start each host directly in the linked worktree as a control;
8. run two sessions concurrently and prove neither is blocked by shared host authority;
9. mutate one candidate and prove only candidate-bound evidence becomes stale; and
10. attempt linked-worktree routing from another Git common directory and prove rejection.

The E2E harness and every child command must contain no `--dangerously-bypass-hook-trust` or
equivalent trust or permission bypass. It must not create, copy, or edit protected host receipts.
If either client is unavailable or unauthenticated, the E2E is `BLOCKED`, not replaced with a fake
success.

The acceptance result must explicitly prove that no worktree-specific trust or task-root reopening
was required.

## Documentation and Completion Boundary

Update workflow commands, hook reference, parallel-session guide, setup/runtime-readiness
diagnostics, troubleshooting, and changelog together. Documentation must distinguish native
repository hook trust from Forge's removed host-receipt mechanism.

The change is complete only when:

- focused dispatcher, worktree, hook, setup, and contract suites pass;
- PowerShell parity passes in Windows CI;
- the complete template suite passes on a frozen candidate;
- the real no-bypass Claude/Codex continuation matrix passes; and
- a refreshed HE Insights worktree performs the previously blocked plan review from a task opened
  at the repository checkout.
