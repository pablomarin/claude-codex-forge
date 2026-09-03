# Design: Repository-Scoped Native Host Receipts

**Date:** 2026-09-03
**Status:** Draft for developer review

## Problem

Forge currently issues its protected native-host receipt from a project hook and binds that receipt
to one physical worktree root. That combines two different security boundaries:

- the native Claude Code or Codex session that authorizes dispatch; and
- the exact worktree candidate whose plan, code, and verification evidence is being reviewed.

The combination blocks the normal user workflow. A developer can open Codex or Claude Code in the
primary checkout, ask it to continue an existing linked worktree, and have every command execute in
that worktree, yet plan review fails because the session did not mint a receipt from that physical
root. Reopening a task at the worktree path is unnecessary Git ceremony and does not fit desktop
tasks, cross-host handoffs, or later resumed sessions.

Codex project hooks add a second failure mode: they run only after the user trusts the project's
hook configuration. A smoke test that starts Codex with `--dangerously-bypass-hook-trust` proves
only the bypass path and can hide the real user-facing failure.

## Goals

1. Let a user open Codex or Claude Code anywhere in a Forge repository and continue any linked
   worktree belonging to that repository.
2. Let a later session, including a session in the other host, continue the same worktree without
   reopening the client at that physical path.
3. Preserve exact worktree binding for candidates, reviews, verification, state, and authorization.
4. Keep native-host receipts unreadable and unwritable by the coding agent.
5. Detect a different repository, stale Forge runtime, altered launcher, expired receipt, or native
   session mismatch and fail closed with actionable remediation.
6. Exercise the same trusted-hook path a user exercises; release E2E must never use a hook-trust
   bypass flag.
7. Provide equivalent Unix and Windows behavior.

## Non-goals

- Allowing two agents to edit one worktree concurrently.
- Sharing candidate or review evidence between linked worktrees.
- Allowing a repository to mint its own protected native-session authority from an agent command.
- Trusting arbitrary project code merely because a user trusted one global Forge hook.
- Making a session opened outside the repository discover all project skills and configuration.
- Silently approving Codex hooks on the user's behalf.

## Security Model

Forge separates authority into two layers.

### Repository-scoped native-session authority

A native hook proves that the current Claude Code or Codex session started in a checkout belonging
to a particular Git repository. Its identity is the SHA-256 hash of the canonical Git common
directory. Every linked worktree of the repository resolves to that same identity; a separate clone
or unrelated repository does not.

The protected receipt is stored under:

```text
~/.forge/host-contexts/<repository-identity>/active-claude.ctx
~/.forge/host-contexts/<repository-identity>/active-codex.ctx
```

Claude and Codex never overwrite one another's active receipt. A new native session refreshes only
its host's receipt.

### Worktree-scoped artifact authority

Candidate fingerprints, plan/code reviews, verification receipts, state, goal authorization, and
all frozen-artifact checks continue to include the physical worktree identity. No existing
candidate-bound control becomes repository-scoped. A valid repository host receipt authorizes the
dispatcher to start; it does not make evidence from a sibling worktree reusable.

This separation is the central invariant: **session authority follows the repository; evidence
authority follows the worktree.**

## Stable Native Hook Installation

Global setup installs one Forge-owned host-receipt helper per platform under the protected global
harness and merges stable native hook registrations into the user's existing host configuration.
It preserves unrelated settings and hooks.

- Claude Code registers Forge's global helper for `SessionStart` and `UserPromptSubmit` in the
  user-level settings. `SessionStart` persists the native session identifier through Claude's
  environment-file mechanism so launch can compare the calling session with the protected receipt.
- Codex registers the same logical events in the user-level hooks file. Codex must present the hook
  through its normal `/hooks` trust flow. Setup reports `CODEX_HOOK_TRUST: REQUIRED` with that exact
  action until trust is present; it never claims runtime readiness merely because the JSON exists.
- The registered command invokes only the protected global helper. It does not execute a script
  selected from the current repository. The helper treats hook input as untrusted, resolves the
  canonical Git common directory from the event working directory, and records only bounded
  receipt data.

Project hooks remain responsible for project behavior such as workflow gates, formatting, state,
and evidence. The global hook owns only native-session qualification. Existing project
host-receipt hook entries are removed during refresh so there is one issuer and no order-dependent
race.

## Receipt Schema and Validation

The new receipt schema records exactly one value for each of:

```text
schema_version
active_host
session_id
repository_identity
git_common_dir
context_revision
launcher_hash
council_hash
nonce
issued_epoch
expires_epoch
receipt_hash
```

The global helper derives `context_revision`, `launcher_hash`, and `council_hash` from the checkout
named by the native event. It rejects symlinks/reparse points in the protected authority path and
publishes atomically with owner-only permissions where the platform supports them.

At launch from a target worktree, the installed project launcher:

1. resolves the target's physical root and canonical Git common directory;
2. selects the active receipt for the requested native host and repository identity;
3. validates schema, exact host, canonical common directory, receipt hash, time window, and nonce;
4. compares the calling native session identifier with `session_id` rather than accepting a receipt
   minted by some other active task;
5. hashes the target worktree's managed manifest and fixed dispatcher/council launchers and requires
   those hashes to match the qualified receipt; and
6. exports the validated context only to the fixed dispatcher process.

Absolute launcher paths are deliberately absent from the receipt. Linked worktrees have different
paths but must contain byte-identical qualified launchers. A target branch with a different Forge
revision or launcher bytes fails closed and asks the user to refresh or start/resubmit from that
revision; repository scope is not version bypass.

The launcher continues to accept only its fixed dispatcher or council target. The agent cannot
substitute another executable, invoke receipt issuance manually, read the protected receipt, or
override a mismatched native session merely by setting Forge environment variables.

## User Flow

After one machine-level setup and normal Codex hook trust, the intended interaction is:

```text
1. Open Codex or Claude Code in the repository's primary checkout.
2. Say: "Get into .worktrees/<name> and keep working."
3. The agent runs all worktree-specific commands with that worktree as their working directory.
4. Forge accepts the repository-scoped native session and validates worktree-scoped evidence there.
5. Close the session.
6. Open a later Codex or Claude Code session in the repository and repeat step 2.
```

Starting the native client directly in the linked worktree remains supported but is not required.
Switching hosts is supported after the previous host stops; it refreshes the other host's receipt
and resumes the same `.forge/local/state.md` checkpoint.

If Codex hook trust is missing, Forge says:

```text
BLOCKED[host-trust]: Forge's Codex hook is not trusted. Run /hooks, trust the Forge user hook,
then resubmit your prompt.
```

It must not tell the user to reopen the task at the worktree root. Missing global installation,
unsupported receipt schema, runtime hash mismatch, and different-repository mismatch each receive
their own precise remediation.

## Migration and Compatibility

- `setup.sh --global` / `setup.ps1 -Global` installs or refreshes the protected helper and merges
  the global native hook registrations without replacing unrelated user configuration.
- Project setup/refresh removes only the exact Forge-managed project receipt-issuer entries. Other
  project hooks remain unchanged.
- Schema-v2 physical-worktree receipts are not promoted or copied. Launch reports them as stale and
  asks for a normal prompt resubmission after global setup; the next native hook produces the new
  receipt.
- A project may be materialized before global setup, but native review/council dispatch remains
  explicitly not ready until the global helper is installed and, for Codex, trusted.
- Full-refresh ownership rules apply to legacy or modified hook entries. Ambiguous custom entries
  are preserved and block automatic reconciliation rather than being deleted.

## Test Strategy

Unit and fixture tests first establish the changed boundary:

1. a receipt issued in the primary checkout validates from two linked worktrees of the same repo;
2. candidate and review receipts from one worktree remain invalid in its sibling;
3. a separate clone/repository is rejected even when files and commits are identical;
4. stale managed revision, altered dispatcher/council bytes, expired receipt, malformed receipt,
   symlink/reparse authority path, wrong host, and wrong native session are rejected;
5. Claude and Codex receipts coexist without changing one another;
6. global setup is idempotent and preserves unrelated native hooks/settings;
7. project refresh removes the exact legacy receipt issuer and preserves unrelated project hooks;
8. Bash and PowerShell implement the same schema and decisions.

The release E2E then uses real installed clients and a disposable user profile:

- install Forge globally and into a disposable Git repository;
- launch interactive Codex normally, use `/hooks` to trust the Forge hook through the supported UI,
  start in the primary checkout, and ask it to continue an existing linked worktree;
- close Codex, start a second normal Codex session in the primary checkout, and continue the same
  worktree;
- stop Codex, start Claude Code normally in the primary checkout, and continue that worktree;
- repeat in the opposite order and also launch each client directly in the worktree;
- attempt dispatch from an unrelated repository and prove rejection;
- prove every successful dispatch produces worktree-specific candidate/review evidence.

The E2E command and its child processes must contain no `--dangerously-bypass-hook-trust` (or
equivalent trust-bypass option). The test must not synthesize, copy, or edit a protected host
receipt. A static assertion rejects the bypass string in the E2E harness, and runtime logs retain
the native session IDs, resolved repository/worktree identities, and dispatch result without
exposing receipt contents.

Authentication availability is reported separately from logic correctness. If either real client
is unavailable or unauthenticated, the release E2E is `BLOCKED`, not silently replaced with a fake
engine test.

## Documentation and Release Boundary

Update getting started, hook reference, parallel-session guidance, troubleshooting, command
instructions, setup diagnostics, and the changelog together. Remove every instruction that says a
task must be reopened at a linked worktree path solely to obtain a receipt.

The change is complete only when:

- focused Bash tests pass;
- PowerShell parity passes in Windows CI;
- the full template suite passes on the frozen candidate;
- real authenticated Codex and Claude Code continuation E2E passes without trust bypasses;
- a refreshed downstream HE Insights worktree can perform the previously blocked plan review from
  a task opened at the repository checkout; and
- the merged documentation describes exactly the behavior users observe.
