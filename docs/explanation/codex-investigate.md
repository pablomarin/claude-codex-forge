# `/opinion investigate` Profile

> **TL;DR** — `/opinion investigate` asks a fresh Claude Code or Codex reviewer to work inside a
> disposable, repo-confined candidate with only explicitly declared capabilities. It can reproduce
> a bug or query a live system without mutating the developer's real worktree; findings require an
> independent primary/control reproduction before they become actionable.

## Why it matters

Ordinary `/opinion` review is hermetic: read-only and without network. That is the right posture for
reviewing code, but source alone cannot answer every operational question. A hermetic reviewer cannot:

- run a SQL query to see what the data actually says,
- reach a cloud or API to check real state,
- execute a script to reproduce a bug,
- go outside the sandbox at all.

For a whole class of real work — _why is this metric wrong?_, _is the data actually as of yesterday?_, _reverse-engineer this report's rule_ — reading code isn't enough. The answer lives in the live system. That's the gap Investigate mode closes.

## What it does

The current host prepares a bounded context and the Forge dispatcher selects the requested engine.
The child receives only the declared query/runner surface inside a disposable candidate. The real
worktree and protected authorization records are never exposed to child writes. If the requested
engine is unavailable, selection falls back automatically and visibly to a fresh same-engine child.

It's deliberately **project-agnostic**: the Forge ships no Snowflake/Postgres/AWS code. It works for any backend because it borrows the connection surface your project already has.

## Why it's safe

Giving an autonomous agent live access sounds risky — so the safety is structural, not hopeful:

1. **Disposable candidate — never the real worktree.** The dispatcher launches either engine in a
   fresh confined copy with only the declared capability surface. The child cannot write protected
   Forge state, authorization, or the developer's real candidate.
2. **Read-only / never mutate.** Investigation looks; it never changes. Use the narrowest role available (e.g. a SELECT-only DB role). Anything that needs to mutate is _implementation_, routed through the normal `/new-feature` or `/fix-bug` workflow — not investigation.
3. **Credentials never leak into logs.** They're sourced from the project's `.env`/config at the runner boundary — never typed into a command line, the prompt, or anything that lands in a transcript.
4. **Findings are independently reproduced before they're trusted.** The dispatcher owns a primary
   check and independent control; `REPRODUCED` requires both to behave as predicted. A child claim
   alone is never enough.

(Decision rationale and the full threat-model discussion live in [ADR 0007](../adr/0007-codex-investigate-mode-capability-gated.md).)

## It works inside `/goal`

Investigation can run inside native `/goal` when all required capabilities are already authorized.
It cannot authorize credentials, a new external mutation, PR creation, or destructive work; those
boundaries checkpoint and return to the developer.

## How it triggers — and who chooses

**The command is explicit.** Use `/opinion` for hermetic review and `/opinion investigate` when the
request needs a disposable writable candidate, network, execution, or a declared live-data channel.
The dispatcher—not a permanent main-engine choice—selects Claude Code or Codex.

Investigation is appropriate for project credentials, external systems (DB/cloud/API), live data,
or non-hermetic execution. A plain `/opinion` never silently escalates to those capabilities. See
the [`/opinion` profiles](../reference/commands.md#opinion-profiles) for the exact mechanics.

## Accepted residual

The Forge's threat model is single-user, local-only (see `rules/security.md`). Read-only + network +
credentials still carries exposure: credit burn, prompt injection through inspected data, and network
exfiltration. A multi-tenant deployment requires additional isolation.
