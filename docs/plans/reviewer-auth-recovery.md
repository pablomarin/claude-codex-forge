# Bounded reviewer authentication recovery

Approved scope: stop losing an explicit Claude CLI expired-login error as a generic
process exit. Keep automatic reviewer fallback; if it cannot complete a review,
the main engine owns one interactive login handoff and one fresh retry of only
unfinished reviews. This extends the current branch, not the Pocket Tasks app.

Immutable workflow base: `HEAD` resolved to
`8c63954b5fd1f67f2a3ae21ea0cd82f2c9777ccc`.

## Evidence and root cause

Two real Claude fallback processes returned JSON `is_error: true` and
`Failed to authenticate. API Error: 401 OAuth access token has expired. Re-authenticate to continue.`
The dispatcher returns `process-exit-1` before parsing that wrapper; only the
first fallback reason is persisted, so the main engine cannot reliably distinguish
login recovery from network, capability, permission, or review failures.
The same installed CLI subsequently answered a tool-free request successfully in
the normal host context while sandboxed `auth status` said logged out. We have
not established why the original token refresh failed. Do not add a token cache,
refresh mutex, credential copying, or automatic logout to address a hypothesis.

Official references checked: https://code.claude.com/docs/en/authentication and
https://code.claude.com/docs/en/cli-reference. The supported interactive recovery
is `claude auth login`; authentication status alone does not prove request validity.

## Minimal change

- Update both `hooks/lib/agent-dispatch.sh` and `.ps1`: recognize the explicit
  expired OAuth error only in Claude's structured error wrapper. Keep the engine
  failure class (and fallback behavior). Persist sanitized `failure_reason` and
  `auth_recovery_engine` fields. No raw provider error text or credentials in receipts.
- Preserve an auth failure from either attempt. Request recovery only when the
  final review is blocked by engine/capability failure; successful fallback,
  findings, artifact mutation, authorization, and invariant blocks do not request login.
- Print an actionable `AUTH_REQUIRED` handoff only when recovery is needed.
  The dispatcher never starts login or retries indefinitely inside a reviewer.
- Add one shared main-engine recovery procedure to `rules/workflow.md`, linked
  from the shared policy and opinion entry point as needed for discoverability.
  Coalesce paired failures; checkpoint candidate, iteration, unfinished roles,
  failure receipts, each unfinished role's preserved regular prompt path and
  expected SHA-256 matching its failed receipt's `prompt_hash`, and whether the
  single recovery/retry was consumed. Verify those prompt bytes before retry;
  missing or changed prompts block rather than being reconstructed from memory.
  First distinguish a host credential-access restriction from an expired login.
  Use the host-approved credential context, never bypass a denied boundary.
  When needed, open an interactive terminal running `claude auth login`; the
  developer finishes the official flow without pasting secrets into chat.
  Recheck candidate identity, retry only unfinished roles once with new outputs
  and receipts, retain the same iteration if unchanged, and stop precisely on failure.
  Existing clean evidence and failed receipts are preserved. Changed candidates
  follow the normal refreeze/invalidation rule. Multi-turn council sessions are
  not silently restarted or mixed; use their existing all-main fallback contract.
- Update the current changelog entry. No installer layout, permissions, model,
  billing, credential storage, or new runtime dependency changes.

## Acceptance and verification

Use the existing real dispatcher suite and fake external CLI boundary. First
observe RED for explicit expired-login classification and actionable receipts.
Cover auth failure on either attempt, successful fallback, both engines failing,
false positives (review text mentions OAuth, HTTP 403/429/network errors), and
candidate mutation overriding recovery. Repeat an unfinished role with a clean
CLI response: new receipt, same candidate/iteration, prior clean lens unchanged,
pair verification succeeds. No fixture invokes real login or changes credentials.
Mirror PowerShell cases; report unavailable Windows execution honestly.

Run the owning suite, static platform parity, and ordinary fast gate. Review the
bounded diff once. Agent-guidance behavior requires a fresh consuming-agent
scenario with simulated process/tool responses (not grep assertions); label that
as simulated, not native GUI/auth E2E. A real expired-login UI recovery remains a
live qualification boundary unless naturally encountered and completed. Preserve
the unfinished original six-case matrix and do not claim full branch readiness.
