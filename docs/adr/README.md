# Architecture Decision Records

This directory holds the project's architecture decisions, one decision per file.

## Format

Each ADR follows the [Nygard 2011 template](https://www.cognitect.com/blog/2011/11/15/documenting-architecture-decisions) extended with [MADR's "Considered Options" section](https://adr.github.io/madr/):

- **Status** — Proposed / Accepted (date) / Superseded by NNNN / Deprecated
- **Context** — the forces that forced the decision
- **Considered Options** — what else we looked at
- **Decision** — what we chose, in active voice
- **Consequences** — what becomes easier, harder, what we're betting on

## Conventions

- Files are numbered monotonically: `0001-name.md`, `0002-name.md`, …
- ADRs are **immutable** — to change a decision, write a new ADR that supersedes the old. The old ADR's status flips to "Superseded by NNNN"; its content is preserved.
- Use `template.md` as the starter for new ADRs. Copy + rename + edit.

## Index

| Number                                                  | Title                                                                                  | Status                |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------- | --------------------- |
| [0001](0001-volatile-state-not-auto-loaded.md)          | Volatile workflow state lives at `.claude/local/state.md`, not auto-loaded             | Accepted (2026-04-28) |
| [0002](0002-bash-and-powershell-dual-platform.md)       | Forge ships bash and PowerShell hooks in parallel                                      | Accepted (2026-04-28) |
| [0003](0003-template-distributed-no-build-step.md)      | Forge is distributed as a template with no build step                                  | Accepted (2026-04-28) |
| [0004](0004-diataxis-docs-structure.md)                 | Forge documentation follows the Diátaxis framework                                     | Accepted (2026-04-28) |
| [0005](0005-hard-platform-parity-rule.md)               | Cross-platform parity is a hard invariant, not a "should"                              | Accepted (2026-04-28) |
| [0006](0006-write-tool-creates-missing-parents.md)      | Trust the Write tool to create missing parent directories                              | Accepted (2026-05-09) |
| [0007](0007-codex-investigate-mode-capability-gated.md) | Codex Investigate mode — capability-gated, sandbox-enforced                            | Accepted (2026-05-27) |
| [0008](0008-state-continuity-round-trip.md)             | Per-developer continuity narrative round-trips through main (seed + guarded fold-back) | Accepted (2026-06-02) |
