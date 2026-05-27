# Codex Investigate Mode

> **TL;DR** — In normal review, Codex is sandboxed: it can read your code but cannot reach the network, run a query, or touch anything outside the repo. **Investigate mode** lets Claude hand Codex the context, files, environment variables, and tools it needs to actually _run things_ against your live systems — a database, a cloud API, a data warehouse — so it becomes a real investigator instead of a code reader in a vacuum. It's safe (repo-confined sandbox, read-only, never "dangerous" mode), and it works inside an autonomous `/goal` run.

## Why it matters

The Forge's dual-agent design uses Codex as an independent second engine — `/codex review`, design review, the Engineering Council. In all of those, Codex runs **hermetically**: `--sandbox read-only`, **no network**. That's the right posture for reviewing code — you don't want a reviewer mutating anything — but it has a hard ceiling: **Codex can only look at code.** It cannot:

- run a SQL query to see what the data actually says,
- reach a cloud or API to check real state,
- execute a script to reproduce a bug,
- go outside the sandbox at all.

For a whole class of real work — _why is this metric wrong?_, _is the data actually as of yesterday?_, _reverse-engineer this report's rule_ — reading code isn't enough. The answer lives in the live system. That's the gap Investigate mode closes.

## What it does

Claude is your main coding agent, and it already knows how _this_ project connects to its systems — the `.env`, the CLIs, the MCP servers, the connection code. **Investigate mode is Claude provisioning Codex with that same connection surface**, so Codex can dig in alongside it. Claude assembles a context brief, sets up whatever access Codex needs the way it would use it itself (an MCP server, a project CLI, or a small `.env`-sourced runner — whatever this repo uses), and launches Codex with network and execution enabled. Two engines then investigate independently and cross-check each other's findings.

It's deliberately **project-agnostic**: the Forge ships no Snowflake/Postgres/AWS code. It works for any backend because it borrows the connection surface your project already has.

## Why it's safe

Giving an autonomous agent live access sounds risky — so the safety is structural, not hopeful:

1. **Repo-confined sandbox — never "dangerous" mode.** Codex runs with `--sandbox workspace-write` (network enabled) and `-C <repo>`, **never** `--sandbox danger-full-access`. The filesystem boundary is enforced by the sandbox flag, not by an instruction Codex is asked to obey — which matters because Codex could be steered by malicious content in the very data it reads. It physically cannot write to `~/.ssh`, your shell profile, or anything outside the repo.
2. **Read-only / never mutate.** Investigation looks; it never changes. Use the narrowest role available (e.g. a SELECT-only DB role). Anything that needs to mutate is _implementation_, routed through the normal `/new-feature` or `/fix-bug` workflow — not investigation.
3. **Credentials never leak into logs.** They're sourced from the project's `.env`/config at the runner boundary — never typed into a command line, the prompt, or anything that lands in a transcript.
4. **Findings are cross-verified before they're trusted.** Codex returns an evidence packet (hypothesis, exact queries, counts, before/after values). Claude independently reproduces it — ideally with its own separately-written queries — before the finding is acted on. "Codex said so" is never enough.

(Decision rationale and the full threat-model discussion live in [ADR 0007](../adr/0007-codex-investigate-mode-capability-gated.md).)

## It works inside `/goal`

Because Investigate mode **never prompts the user** — Claude provisions Codex from credentials it already holds, which is a lateral hand-off, not a new escalation — it runs cleanly inside an autonomous `/goal` session. The council can send Codex to gather _verified facts_ from the live system before advisors reason, instead of speculating. (`AskUserQuestion` stays reserved solely for the PR-creation gate, so nothing breaks the loop.)

## How it triggers — and who chooses

**Codex doesn't choose the mode. Claude does, from your request.** Codex (the subprocess) just receives a prompt and sandbox flags — it has no concept of "modes." The selection happens in Claude's `/codex` mode-detection: the hermetic modes (Code Review / Design Review / General) are routed by keyword and context, while Investigate is **capability-gated, not task-typed** — Claude doesn't match a magic word, it asks "does this task need something the sandbox denies?"

Investigate engages when the task needs any of: project credentials, network, external systems (DB / cloud / API), live data, or non-hermetic execution. In practice you ask for it naturally — _"have Codex dig into the data"_, _"give Codex what it needs to find the cause"_, _"let Codex actually run the query"_ — and Claude recognizes the capability need and provisions Codex accordingly. A plain _"review this"_ never silently escalates to live access; the escalation only happens when the work genuinely can't be answered from source alone. See the `/codex` modes table in the [Commands Reference](../reference/commands.md) for the exact mechanics.

## Accepted residual

The Forge's threat model is single-user, local-only (see `rules/security.md`). Read-only + network + credentials still carries some exposure — credit burn, prompt-injection via inspected data, credential exposure via the network. This is **not** engineered around with budget caps or egress allow-lists, because Claude already carries the identical exposure when it investigates directly. For a single developer on their own machine, the structural safety above is the right level; a multi-tenant deployment would need real isolation on top.
