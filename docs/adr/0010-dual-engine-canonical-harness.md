# 0010 — Use one canonical dual-engine harness with native host adapters

## Status

Accepted (2026-08-27)

## Context

Forge v5 treated Claude Code as the implementation host and invoked Codex at selected review and
council points. Developers now need either host to lead, the other (or a fresh same-engine process)
to review, and the ability to resume one worktree from the other host. Copying full policy trees
between host directories creates drift; symlinks are not a portable or uniformly trusted discovery
mechanism on Bash 3.2, Windows PowerShell 5.1, Claude Code, and Codex. A breaking migration also must
distinguish Forge-owned v5 bytes from user content rather than overwrite by pathname.

## Considered Options

- **Option A (chosen):** one `.forge/` source of truth with generated native adapters and an
  ownership-aware full refresh.
- **Option B:** duplicate a complete harness under each host directory and rely on setup order to
  keep it synchronized.
- **Option C:** symlink host discovery paths directly to a shared tree.
- **Option D:** keep Claude permanently main and expose Codex only as a reviewer.

## Decision

Forge uses no permanent main-agent setting. The current host leads each action, while canonical
workflow state, policy, dispatch, and evidence live below `.forge/`. Claude Code and Codex receive
thin native discovery adapters generated from the same versioned manifest.

### Canonical Harness and Host Adapters

`.forge/instructions.md`, `.forge/rules/`, `.forge/workflows/`, `.forge/skills/`, `.forge/agents/`,
and `.forge/hooks/` are authoritative. `.forge/local/state.md` is the cross-host checkpoint;
artifact-bound receipts under `.forge/local/` make valid evidence portable across hosts but not
across worktrees or candidates. Root instruction blocks and host directories point to canonical
content through host-native files rather than symlinks or duplicated policy.

Host availability is role- and capability-specific. A missing or unsuitable preferred reviewer
falls back visibly to a fresh same-engine process. A mixed-engine council uses three advisors on
the current host, two on the other engine, and the other engine as chairman; if the other engine is
absent or fails, Forge discards the partial attempt and reruns the whole council on the current
host. Investigation is a separate explicitly authorized capability profile. Native `/goal` remains
owned by each host and composes the same Forge objective, nonce, checkpoint, memory, and human-only
PR authorization boundary.

### Fresh-Run Review Independence

Reviewers run in fresh processes without inherited primary conversation, ambient plugins, hooks,
skills, or write-capable MCP. Ordinary review is read-only. Investigation receives only declared
network/query/workspace capabilities in a disposable copy, and a finding remains a hypothesis
until a distinct primary/control reproduction succeeds. Receipts record requested and actual
engine, fallback reason, invocation identity, role/profile, worktree, and immutable artifact
identity.

### Manifest-Driven Full Refresh

`./setup.sh -F` and `./setup.ps1 -FullRefresh` (`-R`) are the authoritative v5-to-v6 migration.
The manifest classifies canonical files, adapters, merge-owned entries, marker-owned regions,
protected content, and versioned legacy fingerprints. The transaction stages and validates a
complete result, backs up every replaced byte, publishes readiness markers last, and rolls back or
requires explicit journal recovery on uncertainty. Project and global scopes are separate.

## Consequences

- ✅ Developers can alternate Claude Code and Codex by task or checkpoint without duplicating the
  plan, state, memory, or evidence contract.
- ✅ One-engine installations remain usable through visible fresh same-engine review and all-main
  council fallback.
- ✅ Host-specific discovery, trust, hooks, commands/skills, and goals remain native while shared
  policy has one owner.
- ✅ Full refresh removes only proven Forge-owned legacy content and preserves custom/user bytes.
- ⚠️ `MATERIALIZED` does not imply `RUNTIME_READY`; each installed host still needs capability,
  authentication, discovery, and hook-trust qualification.
- ⚠️ Forge does not lock a worktree. Simultaneous edits from both hosts can invalidate the
  candidate and its receipts.
- ⚠️ Grok Build is a future capability adapter, not a v1 compatibility claim. It requires its own
  version, trust, discovery, hook, goal, and acceptance matrix before support is advertised.
