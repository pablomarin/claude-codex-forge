# Lean Quick-Fix and Per-Change SemVer Design

**Date:** 2026-10-02  
**Status:** Approved direction; implementation pending  
**Branch:** `fix/lean-quick-fix-workflow`

## Problem

Forge V6 currently subjects `/quick-fix` to the same final paired reviewers and candidate-bound
verification receipts as `/fix-bug` and `/new-feature`. That defeats the purpose of a deliberately
small, obvious workflow. The older V5 quick-fix omitted `code-spec` and `code-quality`, but still
required `verify-app`; the requested contract is intentionally leaner than V5 and removes all
reviewer and verification-agent dispatch from quick-fix.

Forge also publishes two-component versions such as `6.3`. The installer derives that value from
the first changelog release heading, materializers and runtime verification require `MAJOR.MINOR`,
and target repositories store the exact value in `.forge/version`. A documentation-only rule asking
contributors to use `MAJOR.MINOR.PATCH` would therefore contradict the executable upgrade contract.

## Goals

1. Make `/quick-fix` a genuinely agent-free workflow: no `code-spec`, `code-quality`, `verify-app`,
   `verify-e2e`, paired-review iteration, or final receipt-set requirement.
2. Preserve direct, proportionate verification by the main agent and escalate changes that are not
   clearly understood, low-risk, non-user-facing, and bounded to `/fix-bug` or `/new-feature`.
3. Exempt only an exact active `/quick-fix <slug>` from review and verifier evidence at ship time;
   retain common state validation, configuration-integrity checks, compound-ship protection, Goal
   PR authorization, and other shared safety hooks.
4. Publish exact three-component SemVer and bump it once for every merged change set/PR so routine
   `--upgrade` can distinguish every released Forge tree.
5. Record every released change in `docs/CHANGELOG.md`, while keeping README release prose limited
   to material installation, compatibility, workflow, or product changes.

## Non-goals

- Removing reviewer or verification agents from Forge. They remain required for `/fix-bug` and
  `/new-feature`.
- Allowing quick-fix for security boundaries, data migrations, API changes, architectural choices,
  user-facing behavior, or changes without an obvious focused check.
- Replacing the changelog-derived source version with a new version file.
- Treating every intermediate commit as a release. One merged change set/PR receives one version.
- Comparing arbitrary SemVer precedence during setup. Setup installs the exact release represented
  by the checked-out Forge source; it only needs to detect whether the target stamp differs.

## Quick-Fix Contract

`commands/quick-fix.md` remains limited to a clearly understood, low-risk change touching at most
three files. It will:

1. run the shared startup and activation boundary;
2. record the acceptance check and affected files;
3. require RED-first TDD for behavior changes or a direct static/rendered check for documentation;
4. make the smallest change and run the focused owning check directly in the main session;
5. update the changelog and release version when the change will be merged;
6. stage, inspect, and commit the intended diff; and
7. pause for explicit authorization before push, PR creation, merge, or another external mutation.

It will not freeze a candidate, begin a review iteration, dispatch a reviewer or verifier, create
review/verification receipts, run E2E, or describe reviewer fallback and closure loops. Discovery
that the change affects user-facing behavior or exceeds another quick-fix limit immediately
escalates to the full workflow before implementation continues.

## Enforcement Boundary

Both `hooks/check-workflow-gates.sh` and `hooks/check-workflow-gates.ps1` will recognize only the
canonical command form `/quick-fix <lowercase-hyphenated-slug>`. The exemption will occur after the
hook has:

- recognized and decompounded the ship action;
- resolved the real repository and canonical V6 state;
- revalidated managed hook configuration; and
- applied any active native-Goal PR authorization requirement.

The exemption occurs before checklist, convergence-breaker, and structured final-receipt checks.
Malformed commands, missing or invalid canonical state, other workflows, and legacy state do not
receive the exemption. Bash and PowerShell implementations must remain behaviorally equivalent.

The shared state schema may continue allocating receipt paths for all workflows. For quick-fix they
remain unused placeholders; changing the state schema is unnecessary and would increase migration
risk. Canonical policy and workflow documentation will explicitly distinguish the full-workflow
receipt state machine from the quick-fix direct-check path.

## Version Contract

The release created by this work is `6.4.0`: a backward-compatible, user-visible workflow and
versioning capability. Subsequent merged changes choose the increment using standard SemVer:

- **MAJOR** for an intentionally breaking installed contract or compatibility boundary;
- **MINOR** for a backward-compatible capability or material workflow change; and
- **PATCH** for fixes, documentation, tests, or internal maintenance.

The first release heading in `docs/CHANGELOG.md` remains the source version. Source-side parsers,
materializer arguments, and runtime verification require exact `MAJOR.MINOR.PATCH`. Upgrade and
full-refresh compatibility readers continue accepting existing V6 stamps in legacy `6` and
`6.MINOR` forms, then write the new exact three-component release last. Unsupported majors and
malformed values continue to block without advancing the target stamp.

`docs/agent-context.md` will be added as this repository's tracked, team-owned contributor context.
It will require one release bump and changelog entry per merged change set/PR and define the segment
selection above. It will also state that README release prose changes only for material high-level
changes. The README version badge remains exact metadata and may change for every release; its
version-history prose does not become a patch-by-patch duplicate of the changelog.

## Documentation Behavior

- `docs/CHANGELOG.md` receives the complete release record for every merged change set/PR. The top
  heading is always the exact current release and therefore drives setup.
- `README.md` describes the stable product and major user-visible changes. This release merits a
  concise `6.4.0` history row because it changes quick-fix behavior and the public version contract.
  Later patch releases update the badge but do not add release-history prose unless the underlying
  change is materially important to users.
- Detailed workflow and hook references document the quick-fix exemption. They remain the owning
  location for mechanics that do not belong in README.

## Compatibility and Failure Handling

- A project stamped `6`, `6.2`, or `6.3` remains eligible for the existing V6 upgrade/full-refresh
  path and is advanced to the exact current three-component version only after a successful
  transaction.
- A new three-component V6 stamp is accepted by session, hook, state-path, setup, materializer, and
  runtime-verification boundaries.
- A malformed stamp or unsupported major remains blocking. Failed setup or refresh preserves the
  previous stamp.
- Quick-fix exemption is fail-closed: only the exact canonical command and canonical V6 state are
  eligible. Any ambiguity follows the ordinary full-workflow evidence gate.

## Verification Strategy

Implementation follows RED-GREEN TDD:

1. Add quick-fix ship fixtures proving Bash and PowerShell currently reject an active quick-fix
   without review/verifier receipts, while `/fix-bug` remains blocked.
2. Change workflow-contract tests to reject reviewer, verifier, E2E, candidate-freeze, and
   `--begin-review` language in `quick-fix.md` while retaining direct focused verification and
   escalation language.
3. Add SemVer parser/materializer/runtime fixtures that require `6.4.0`, accept legacy V6 inputs
   only at migration boundaries, reject malformed three-component values, and verify that a failed
   transaction does not advance `.forge/version`.
4. Implement the smallest symmetric Bash, PowerShell, Python, workflow, and documentation changes.
5. Run focused workflow-gate, contract, setup, full-refresh, and runtime-identity suites, followed by
   `bash tests/template/run-fast.sh`. Exhaustive local runners remain opt-in and are not authorized
   by this design.

## Acceptance Criteria

- An active canonical `/quick-fix <slug>` can commit, push, and create a PR without reviewer or
  verifier receipts after its direct focused check and normal human authorization boundaries.
- The same missing receipt set still blocks `/fix-bug` and `/new-feature`.
- `quick-fix.md` contains no reviewer, verification-agent, E2E, candidate receipt, review iteration,
  or closure-loop requirement.
- Fresh installation and upgrade write `6.4.0`; runtime verification reports it as valid.
- Existing supported V6 stamps `6` and `6.MINOR` upgrade safely to the exact three-component release.
- `docs/agent-context.md` requires one SemVer bump and complete changelog entry per merged change
  set/PR and reserves README release prose for material changes.
- Bash and PowerShell focused parity tests and the Forge fast gate pass on the final candidate.
