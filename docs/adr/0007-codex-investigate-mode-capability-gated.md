# 0007 — Separate hermetic review from full-agent investigation

## Status

Amended (2026-08-27; originally accepted 2026-05-27)

## Context

Hermetic review is excellent for independent source/design analysis but cannot answer questions that
require current documentation, project tooling, databases, cloud APIs, or live operational state.
The original v5 investigate mode added selected read-only capabilities inside a repo-confined
workspace. In practice that boundary also removed the normal project state, memory, tools, MCP,
credentials, and host configuration that make an investigator useful, and it duplicated policy
already owned by the active host.

## Considered Options

- **Option A (chosen):** keep ordinary review hermetic, but launch investigation as a fresh normal
  full-capability engine process in the real worktree.
- **Option B:** retain the disposable candidate, selected read-only channels, and bounded replay.
  Rejected because it prevents ordinary engineering investigation and requires capability-specific
  hand-off machinery.
- **Option C:** make every opinion full-capability. Rejected because immutable, independent review
  remains a valuable and enforceable contract.

## Decision

`/opinion investigate` in Claude Code and `$opinion investigate` in Codex start a fresh selected
engine in the real worktree. Forge does not replace the user's home/config, disable project
instructions/plugins/MCP, add a tool allowlist, create a disposable candidate, or replay selected
outputs. Claude is launched in safety-classified auto mode so an unattended cross-engine call can
use normal tools without bypassing checks. Codex is launched with full host access, search, and
native on-request approval because its non-interactive default is read-only. Both share Forge
state and memory.

The investigator may edit the worktree. Destructive or externally mutating actions still require
the explicit authority already required by the normal workflow; this ADR grants no new human
authority. Investigation results remain hypotheses until a separate isolated primary/control
`investigation-repro` receipt says `REPRODUCED`.

## Consequences

- ✅ Either engine can investigate with the same capabilities it has as a normal engineering agent.
- ✅ No credential-copy, MCP allowlist, replay protocol, or second project configuration is needed.
- ✅ Claude can execute unattended through its native safety classifier without bypassing permissions.
- ✅ Codex can write and use network/API integrations without silently inheriting its read-only exec default.
- ✅ Ordinary opinion/code review remains fresh, isolated, read-only, and candidate-bound.
- ⚠️ A full investigator can modify the worktree and reach services allowed by normal host policy;
  its receipt cannot certify an immutable candidate.
- ⚠️ Single-user local threat assumptions still apply. Multi-tenant use requires a separate
  isolation design.
