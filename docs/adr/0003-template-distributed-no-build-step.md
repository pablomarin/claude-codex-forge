# 0003 — Forge is distributed as a template with no build step

## Status

Amended by [ADR 0010](0010-dual-engine-canonical-harness.md) (2026-08-27). Forge still has no build
step; v6 installs one manifest-owned `.forge/` harness plus native host adapters and uses full
refresh rather than the legacy force/upgrade path.

## Context

Forge is consumed by downstream projects via `git clone claude-codex-forge && ./setup.sh -p MyProject`. Setup is a one-time install that copies templates (markdown, JSON, bash, PowerShell) into the target repo's `.claude/`, root, and `docs/` directories. Subsequent harness upgrades happen via `./setup.sh -f` or `--upgrade` from a fresh `claude-codex-forge` clone. The toolkit has no compiler, no transpilation, no package step.

## Considered Options

- **Option A (chosen):** Pure config + scripts. Templates are markdown / JSON / shell; setup.sh / setup.ps1 are installers. No `npm`, `pip`, `cargo`, or build-step required to install.
- **Option B:** Distribute as an `npm` or `pip` package with a CLI entry point. Rejected because Forge has no runtime dependency, and adding a package manager would gate adoption on Node.js or Python being installed (not given on every dev machine; especially restrictive on tightly-managed enterprise Windows boxes).
- **Option C:** Distribute as a Docker image. Rejected for similar friction reasons.

## Decision

Forge ships as a git repository with templates and shell installers. The user clones it, runs `setup.sh` (or `setup.ps1`), and consumes the outputs. Upgrades use the same installer with `-f` or `--upgrade`. The repository structure IS the distribution.

## Consequences

- ✅ Zero install friction. Any machine with bash or PowerShell can run the installer.
- ✅ Auditable: users can `cat setup.sh` before running.
- ✅ Forking and customization is trivial (just edit the templates).
- ⚠️ Schema validation is best-effort. JSON and markdown templates have no compile-time check; lint runs in `tests/template/test-lint.sh` post-install.
- ⚠️ No semantic versioning of templates. Drift is detected via `setup.sh -f` summary block (PR #523) but not formally versioned.
- 🔮 If Forge grows beyond what shell installers can manage cleanly, this ADR may be superseded by one introducing a structured build step.
