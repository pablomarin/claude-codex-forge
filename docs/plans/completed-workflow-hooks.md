# Completed workflow Stop hooks and dual-main verification

Base: `main` at `f0ecd598d734c716dae0e3357e6523efcddda579`.

The developer authorized this repair and requires tests with both Claude and Codex as main,
with the other engine selected for independent review/opinion and mixed council participation.

## Reproduction and root cause

In Forge 6.4.5, a completed workflow with an unchanged state hash exits 2 on Stop.
The reminder and receipt-advisory branches inspect Command but never exclude Phase=complete.
Codex then continues the model. A primary checkout's completed quick-fix label can therefore
interrupt work occurring in a linked feature checkout. Routing correctly follows the event cwd;
do not guess another worktree or change shipping authorization/evidence boundaries.

## Bounded tasks

1. Add failing installed-hook regression cases, then exclude complete workflows from receipt
   advisories and checkpoint continuations in both Bash and PowerShell. Preserve state validation,
   native Goal accounting, changelog enforcement and shipping checks. Test both host payloads,
   active controls, repeated Stops, and linked-worktree routing without mutating live projects.
   Keep PowerShell checkpoint and Goal sidechannels in the resolved event worktree: .NET file
   writes require absolute paths after `Set-Location`. Use the supported SHA-256 command and
   normalize CRLF when reading workflow reminders.
   Registered Codex Windows commands must preserve the router's exit status with explicit
   `exit $LASTEXITCODE`; exercise the registered command, including active Stop and blocking
   PreToolUse controls, rather than calling the router directly with `-File`.
   PowerShell reviewer capture must resolve an already absolute Git common directory without
   appending it to the linked worktree; prove both primary and linked capture through the helper.
   Native Windows CI closes platform qualification. Its failures require the compiled Claude
   fixture to use the configured canonical model/provider envelope, plus diagnostic preservation.
   Quick-fix activation must await Git Head/Branch/BaseRef completion before selecting its first
   output and checking native status; prove successful, failed and wrong-branch controls with a
   delayed native command. Preserve exact branch/base/clean-worktree guards.
2. Expand deterministic dual-engine E2E and council fixtures to both main hosts, healthy
   other-engine review/opinion routing, and visible same-engine fallback. Mirror the acceptance
   coverage on PowerShell. Keep vendor CLI calls faked in deterministic suites.
3. Document the enduring two-main test requirement in CONTRIBUTING.md and explain completed
   Stop behavior in docs/reference/hooks.md. Bump the source release to 6.4.6 and update its
   changelog and README badge.

## Acceptance and user journeys

- Completed quick-fix/new-feature/fix-bug repeated Stops suppress historical receipt advisories
  and checkpoint continuations for Claude and Codex. Independent hook output remains possible.
- Active workflow checkpoint and stale-evidence reminders still occur; continuation-loop guard
  remains intact. A completed state does not waive changelog or shipping gates.
- Primary completed quick-fix and linked active feature remain independent; the hook uses the
  event cwd and names only that worktree's workflow. Checkpoint and Goal sidechannels belong
  to that same worktree, with no writes leaking into the primary checkout.
- Claude main selects Codex review/opinion; Codex main selects Claude. Engine failure visibly
  falls back to a fresh same-engine process with accurate receipts in both directions.
- Council topology and independent turn/session behavior are verified with each host as main.
- Run focused owning suites and tests/template/run-fast.sh. PowerShell execution is CI-owned
  if pwsh is unavailable; static parity is checked locally. Do not claim a fake-engine run proves
  authenticated native host operation, and do not run the exhaustive suite automatically.

Independent plan/code review uses the configured Forge dispatcher and immutable candidate.
The developer subsequently authorized publishing this repair, waiting for CI, merging to the
resolved default branch, and finishing this task branch. Downstream installation is separate.
