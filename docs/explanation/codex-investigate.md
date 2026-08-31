# Opinion `investigate` Profile

> **TL;DR** — Claude Code's `/opinion investigate` or Codex's `$opinion investigate` starts a fresh
> selected-engine agent in the real worktree with the host's normal project configuration, state,
> memory, tools, MCP servers, network, databases, and APIs.

## Why it matters

Ordinary opinion review is deliberately hermetic: read-only and without network. That is the right
posture for independent code review, but source alone cannot answer every operational question. An
investigator may need to run project tooling, inspect a database, call a cloud API, research current
documentation, or create a reproduction in the worktree.

## What it does

The current host selects the requested reviewer engine and starts a fresh ephemeral process. Unlike
ordinary review, Forge does not replace HOME, strip user/project configuration, disable plugins or
MCP, add a safe-mode/tool allowlist, create a disposable candidate, or replay selected files
afterward. Claude uses native safety-classified `auto` mode. Codex uses native `on-request`
approval with `danger-full-access` and search because `codex exec` otherwise defaults to a
read-only sandbox. The
investigator works directly in the same worktree and sees the same `.forge/local/state.md`,
durable/local memory, instructions, and normal host integrations.

If the requested engine cannot launch, Forge visibly retries once with a fresh same-engine fallback
according to the normal dispatcher policy. The receipt records `investigation_mode=full-agent-worktree`.

## Boundaries that still apply

“Full agent” means the investigator has the host capabilities needed for the task; it does not erase
the developer's explicit authorization boundaries. In particular:

1. Destructive or externally mutating operations still require the authority that the normal
   workflow requires for that operation.
2. Secrets stay in normal host/project credential stores rather than prompts, argv, receipts, or
   tracked artifacts.
3. The investigator may edit the worktree, so its receipt is not immutable-candidate review
   certification.
4. A finding remains a hypothesis until a separate `investigation-repro` run receives only the
   claim, exact primary check, and an independent control. Only `REPRODUCED` is certifying.

This split is intentional: ordinary review remains a narrow independent evidence boundary;
investigation behaves like a normal fresh engineering agent. See
[ADR 0007](../adr/0007-codex-investigate-mode-capability-gated.md).

## It works inside `/goal`

Investigation can run inside native `/goal` using the capabilities already available to that host.
If a normal workflow boundary requires fresh human authority, the investigation checkpoints there
instead of inventing authorization.

## How it triggers

Claude Code uses `/opinion investigate <request>`; Codex uses `$opinion investigate <request>`.
The dispatcher prefers the other engine and visibly falls back to a fresh same-engine process on a
launch/capability failure. There is no permanent main-engine choice.
