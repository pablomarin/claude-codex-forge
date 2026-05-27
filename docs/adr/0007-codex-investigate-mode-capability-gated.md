# 0007 — Add a Codex Investigate mode, capability-gated and sandbox-enforced

## Status

Accepted (2026-05-27)

## Context

`/codex` and `/council` ran Codex hermetically — `--sandbox read-only`, no network, no credentials — which is correct for code/design review but cripples Codex for **investigation** (debugging, reverse-engineering, data-spelunking). Field evidence: in a Snowflake-backed repo, letting Codex run non-sandboxed with the project's real (read-only) credentials, network, a context brief, and an `.env`-sourced SQL runner let it crack a metric defect (a phantom employee inflating a Minutes-Per-Room numerator) that the hermetic mode could never have reached; Claude then independently reproduced the finding before it was trusted. The Forge serves every kind of project (Postgres, Oracle, Snowflake, AWS, GCP, …), so the capability must be system-agnostic, and it must work **inside an autonomous `/forge-goal` `/goal` run** where no human is in the loop.

## Considered Options

- **Option A (chosen):** A distinct, capability-gated Investigate mode — a pure prompt addition where Claude provisions Codex from the project's own connection surface, sandbox-confined to the repo, read-only, no user prompt, cross-verified.
- **Option B:** Fold investigation powers into the existing General mode — rejected: General's safety is a _contract_ (read-only/no-network); making it opportunistically gain network+creds turns the guarantee into runtime judgment.
- **Option C:** Ship per-system runners + a declarative tool-allow-list manifest + an authorization modal + a per-`/goal` scope field — rejected as over-engineering: for single-user local tooling the machinery is ceremony that prevents none of the real residual risks, and a modal breaks `/goal` autonomy.

## Decision

We add Investigate as a separate `/codex` mode (Section D), and a `/council` live-state fact-finding clause that reuses it. It is gated by **capability-need, not task-type**: it engages only when the task needs project credentials, network, external systems, live data, or non-hermetic execution. Two properties are non-negotiable. First, the "stays inside the repo" boundary is enforced by the **Codex sandbox** (`--sandbox workspace-write` + repo `-C`, never `danger-full-access`), **not** by prompt text — because Codex may be steered by malicious content in the data it inspects, so an instruction it is told to obey is not a boundary. Second, the mode **never prompts the user**: Claude provisions Codex from credentials it already holds (a lateral hand-off, not a new escalation), which is what lets it run autonomously inside `/goal` where `AskUserQuestion` is reserved solely for PR creation. The mode is read-only/non-mutating, and every finding must be independently cross-verified by Claude before it is trusted.

## Consequences

- ✅ Codex becomes a real peer investigator on live systems (any backend, via the project's own MCP/CLI/runner) instead of a sandboxed code reader, and it works autonomously inside `/goal`.
- ✅ No new machinery: a prompt-only change that reuses the existing gitignored in-repo write surface and the existing `.env` credential convention.
- ⚠️ Read-only + network + credentials, running autonomously, carries accepted residual exposure — credit burn, prompt-injection via inspected data, credential exposure via network. For the Forge's single-user/local threat model this is not engineered around; Claude already carries the identical exposure when it investigates directly.
- 🔮 Betting that the sandbox flag (`workspace-write`, repo-confined) is the real boundary. Invalidated if a future Codex version weakens `workspace-write` confinement or if the Forge is ever used in a multi-tenant/shared context — then the capability needs real isolation, not just a sandbox flag.
