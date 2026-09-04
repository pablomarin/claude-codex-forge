# Forge opinion workflow — Fresh Review and Investigation

Use the fixed-target compatibility launcher registered by the active Claude Code or Codex adapter.
It declares the current host to the dispatcher; `main_host` is routing metadata, not authenticated
session identity or reviewer evidence. Never invent a `main` engine flag. User-facing reviewer
choices map only to `--engine auto|claude|codex`; `auto` means the other engine. A healthy explicit
same-engine request is a fresh independent reviewer, not a fallback.

## Inputs

Claude Code invokes this workflow as `/opinion <request>`; Codex invokes it as `$opinion <request>`.
Adding `investigate` after either host-native entry point selects the investigation profile.
Otherwise classify the request as one of: general second opinion/analysis/brainstorming/question
(`general`), plan, PRD, review comments, code review, or independent investigation reproduction.
General is hermetic and read-only. Resolve the workflow's persisted immutable base SHA/ref from
`.forge/local/state.md`; never recompute it from a moving default branch. Put the exact request in a
regular prompt file under `.forge/local/reviews/`.

`FORGE_REVIEW_TRANSPORT_AUTHORIZED`: Starting the Forge workflow already authorizes sending the
complete bounded immutable candidate snapshot, prompt, and evidence to the developer-configured
Claude Code or Codex reviewer service. Private, sensitive, or unchanged tracked candidate content
does not require another approval. This expected transport is not an external mutation and does not
grant the reviewer arbitrary network tools or authority to source additional secrets, credentials,
or gitignored developer state from outside the candidate; access outside the worktree; other
projects; arbitrary destinations; or external mutations.

Invoke the fixed launcher for this host:

- Claude Code: `.forge/hooks/lib/host-context.sh launch --host claude -- .forge/hooks/lib/agent-dispatch.sh run ...`
- Codex: `.forge/hooks/lib/host-context.sh launch --host codex -- .forge/hooks/lib/agent-dispatch.sh run ...`
- Windows uses `host-context.ps1 -Mode launch -Host <host> -LaunchArguments ...`.

The stable dispatcher arguments are documented by `agent-dispatch run`; pass an explicit artifact,
workflow base, role/profile, prompt, output, and 20-minute timeout. Show its selection/fallback line
and receipt path. Never reinterpret missing, empty, malformed, contradictory, or prose-only output
as a verdict.

## Result handling

For a review, declare `review_mode=broad|closure`.
Use one broad review, one repair pass, and one closure review.
Closure checks only named findings and direct regressions. Do not start a second broad scan. One
still-open reachable P0/P1 may receive one surgical repair plus surgical verification, then surface
the blocker to the developer. P3, cosmetic, speculative, purely theoretical, and unchanged-
candidate concerns do not keep the loop open; a concrete material P2 still prevents certification.

- `CLEAN` certifies only when maximum severity is `NONE` or `P3` and no P0/P1/P2 record exists.
- `FINDINGS` is a successful review result, not an engine fallback. Repair and invoke only within
  the bounded broad/repair/closure policy above.
- `BLOCKED artifact|authorization|invariant` stops without fallback.
- Engine/capability launch failure follows the dispatcher's visible one-retry policy. With
  `--fallback-policy none`, no retry occurs.

Code requires two distinct fresh receipts over the identical candidate: `code-spec` and
`code-quality`. Validate them with `agent-dispatch verify-pair`; neither lens substitutes for the
other. Council seats always use `--fallback-policy none`; only council-advisor may use exact-id
`new`/`resume` transport. The council orchestrator owns whole-topology fallback.

For a Developer Demo PR body, verify every Mermaid diagram edge against its `file:line` Evidence
row. An unsupported or false claimed-current-behavior edge is a P1 finding; explicitly planned or
inferred Gate-1 briefing edges are exempt.

## Investigation

Use `--profile investigate --role investigation`. This launches a fresh full-capability process of
the selected engine in the real worktree. It inherits the normal user/project configuration,
Forge state and memory, installed tools and skills, MCP servers, network, databases, and APIs.
Forge does not add a safe-mode, tool allowlist, stripped home/config, disposable candidate, or
replay boundary to this role. Claude uses safety-classified `auto` permission mode so an
unattended cross-engine call can use normal tools without bypassing safety checks. Because
non-interactive Codex otherwise defaults to read-only, Forge selects `danger-full-access` with
native `on-request` approval and search enabled for this explicit role. The developer's existing
authorization boundaries still apply. Because the investigator may edit the live worktree, its
receipt is evidence of the investigation run, not immutable-candidate review certification.

An investigation is a hypothesis. Run a separate `investigation-repro` invocation with only the
claim, exact primary check, and an independent control. Treat it as verified/actionable only when
the reproduction receipt says `REPRODUCED` and both primary and control behave as predicted.

Destructive or externally mutating actions still require the existing explicit human authority;
the authorized action remains human-executed.
Use `authorized-action prepare` only for an allowlisted
fixed executable/argv adapter, show the deterministic command, and ask the developer to execute it.
An agent-written approval or audit receipt grants no tool, runner, or credential. Record the
developer-reported outcome as `UNVERIFIED` until independent reproduction succeeds. MCP-only
mutation is `BLOCKED` in v1.
