# Contributing to Claude Codex Forge

Claude Codex Forge is a versioned, dual-engine engineering harness for Claude Code and Codex. This
repository contains the source templates, installers, adapters, hooks, tests, and documentation that
are materialized into downstream projects.

## Sources of truth

- `CONTRIBUTING.md` is the canonical guide for developing this repository.
- `FORGE.template.md` is the canonical policy installed into downstream projects as
  `.forge/instructions.md`.
- `manifests/managed-v6.tsv` defines which source owns each installed destination.
- `templates/adapters/CLAUDE.block.template.md` and
  `templates/adapters/AGENTS.block.template.md` are thin native discovery adapters. They point both
  hosts to the same installed policy; they are not independent copies of that policy.
- Root `CLAUDE.md` and `AGENTS.md` are equally thin adapters for contributors working in this source
  repository.

Do not maintain shared rules twice. Change the appropriate canonical source, then update both native
adapters only when their host-specific discovery syntax or behavior actually differs.

## Repository map

| Area | Purpose |
| --- | --- |
| `setup.sh`, `setup.ps1` | Unix and Windows installers; behavior must remain equivalent |
| `manifests/` | Versioned ownership, capabilities, compatibility, and migration data |
| `commands/`, `rules/`, `agents/`, `skills/` | Canonical workflow and policy sources |
| `hooks/` | Shared enforcement with Bash and PowerShell implementations |
| `settings/` | Claude and Codex configuration templates |
| `templates/adapters/` | Thin host-native adapters over canonical `.forge` content |
| `scripts/` | Setup, migration, qualification, and evidence helpers |
| `tests/template/` | Deterministic contract, installer, hook, migration, and parity suites |
| `docs/` | User guides, reference, explanations, ADRs, and release history |

## Engineering rules

- Prefer the smallest change that solves a reachable user problem. Stop when another review pass has
  lower expected engineering value than its time and token cost.
- Do not add machinery for implausible edge cases. Preserve fail-closed behavior at real security,
  authorization, ownership, and evidence boundaries.
- Use test-driven development for behavior changes: reproduce the failure, make the smallest repair,
  then rerun the owning suite.
- Ground completion claims in fresh executable evidence. State any unexecuted platform or live-host
  boundary honestly.
- Preserve user-owned content and unrelated worktree changes. Installer-managed regions may change;
  text outside their markers must not.
- Every runtime hook or installer behavior implemented in Bash must have an equivalent PowerShell
  implementation. If PowerShell is unavailable locally, rely on static parity and report Windows
  runtime verification as CI-owned.
- Keep the harness dependency-light and portable. Reuse existing helpers and formats before adding a
  new runtime, framework, or service.

## Development workflow

1. Work in an isolated branch or worktree.
2. Read the owning manifest, source, adapter, and focused test before editing.
3. Add or update the smallest test that proves the contract being changed.
4. Run that test and confirm the expected failure.
5. Implement the change in every owned platform twin.
6. Rerun focused tests, then use the aggregate suite only at a meaningful integration boundary.
7. Review the final diff for accidental user-content, history, or ownership changes.

Common verification commands:

```bash
bash tests/template/test-contracts.sh
bash tests/template/test-platform-parity.sh
bash tests/template/test-setup.sh
bash tests/template/run-all.sh
git diff --check
```

Use the narrowest relevant command while iterating. `run-all.sh` is the final integration check, not a
loop body.

## Installer ownership

Downstream projects receive one canonical `.forge/` harness plus host-native `.claude/`, `.codex/`,
`.agents/`, `CLAUDE.md`, and `AGENTS.md` adapters. Setup preserves content outside bounded Forge
markers and unrelated settings entries. `.forge/local/` is developer-local and must not be committed.

When changing installed layout or ownership:

1. update `manifests/managed-v6.tsv`;
2. update both installers and their platform twins where applicable;
3. update focused layout, setup, migration, and parity contracts;
4. update current user documentation without rewriting historical changelog entries.

`CLAUDE.template.md` remains only for proven v5 reconciliation and migration. New v6 Claude root
adapters come from `templates/adapters/CLAUDE.block.template.md`.
