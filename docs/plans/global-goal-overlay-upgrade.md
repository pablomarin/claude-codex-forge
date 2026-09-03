# Global Goal Overlay Upgrade Fix Plan

## Problem

A user may have a real Forge v5 global Claude harness, install or refresh a Forge v6 project, and
only later install the v6 global harness. Project setup writes the advisory machine stamp
`~/.claude/.forge-version=6.0`, but it does not materialize the canonical global v6 stamp
`~/.forge/version`. A subsequent read-only global full-refresh preview incorrectly treats the
advisory `6.0` value as an unsupported legacy global release and blocks before fingerprint-based
ownership reconciliation.

The project installer also reports the optional machine integration as `GOAL_OVERLAY: BLOCKED`,
which makes an otherwise usable project appear incomplete and conflates three states: global
materialization, protected goal authority, and authenticated goal qualification.

## Reproduction and Root Cause

- Base ref: `main`
- Immutable base SHA: `c83391e4162b8c57e9e48ef8c4518478538f5ba9`
- Reproduction: a home containing v5 global Claude files, no `.forge/version`, and an advisory
  `.claude/.forge-version` containing `6.0` produces `UNSUPPORTED_LEGACY_RELEASE` under
  `setup.sh --global -F --dry-run`.
- First incorrect decision: `inventory_legacy()` in `scripts/merge-settings.py` treats the
  historical machine advisory stamp as the selected global legacy release whenever the canonical
  global v6 stamp is absent.
- Working control: when no selector is available, the existing inventory already checks actual
  files against every released fingerprint and tries every declared root-region segmentation.

## Minimal Change

1. For global scope only, do not make an unsupported advisory machine stamp an ownership finding.
   Preserve project-scope release-stamp behavior unchanged. Let the existing all-release
   fingerprint and region recognizers classify actual global files.
2. Replace the ambiguous optional status with separate, stable diagnostics:
   `GLOBAL_HARNESS`, `NORMAL_PROJECT_WORKFLOWS`, and `NATIVE_GOAL_RUNTIME`.
3. Keep project goal workflow/state under `.forge/`; keep only trusted authorization/capture
   helpers and global grounding under the machine home.
4. Mirror status behavior in Bash and PowerShell. Add no new runtime, file format, or migration
   mechanism.

## Changed Paths

- `scripts/merge-settings.py`
- `scripts/materialize-adapters.sh`
- `scripts/materialize-adapters.ps1`
- `setup.sh`
- `setup.ps1`
- `tests/template/test-full-refresh.sh`
- `tests/template/test-full-refresh.ps1`
- `tests/template/test-goal-feasibility.sh`
- `tests/template/test-goal-feasibility.ps1`
- `docs/CHANGELOG.md`

## Regression Tests

1. Construct a general global home from a released v5 global template, overlay the current v6
   advisory machine stamp, and verify the preview no longer emits `UNSUPPORTED_LEGACY_RELEASE`.
2. Verify exact released global bytes remain fingerprint-provable while modified mixed root text
   still blocks ownership reconciliation.
3. Verify project setup without a global harness reports ordinary workflows ready and protected
   native goal unavailable, not a blanket blocked project.
4. Verify global materialization reports the global harness materialized and native goal
   qualification pending. Replace the existing Bash and PowerShell goal-feasibility assertions
   that require the blanket `GOAL_OVERLAY: BLOCKED` status. Exercise Bash behavior and the
   equivalent Windows PowerShell suite.

## Acceptance Criteria

- No global upgrade uses `~/.claude/.forge-version` as v6 global installation authority.
- `~/.forge/version=6` remains the only canonical global v6 stamp.
- Unknown or modified legacy files remain preserved or blocked by existing ownership rules.
- Project-scope v5 release selection is unchanged.
- Ordinary project workflows are explicitly reported ready when only optional global goal support
  is absent.
- Bash and PowerShell implementations remain equivalent.

## User Journey Coverage

- Actor: existing Forge v5 user who upgrades projects before machine-global policy.
- Scenario: project setup advances the advisory machine version, then the user previews global v6
  migration.
- Interface: `setup.sh --global -F --dry-run` / `setup.ps1 -Global -FullRefresh -DryRun` and normal
  project setup diagnostics.
- Verification: the false unsupported-release blocker is absent; actual ownership findings remain;
  diagnostics explain that ordinary project workflows are unaffected.
- Persistence: the preview remains read-only; execution writes the canonical global v6 stamp only
  after a successful transaction.
