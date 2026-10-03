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
General is hermetic and read-only. Resolve the workflow's persisted immutable base SHA/ref through
the bounded `workflow-state.sh show` reader; never recompute it from a moving default branch.
Put the exact request in a regular prompt file under `.forge/local/reviews/`.

For the ordinary review profile, `FORGE_REVIEW_TRANSPORT_AUTHORIZED` communicates the developer's
standing human approval in the canonical Human-Approved Reviews section (`.forge/instructions.md`;
source: `FORGE.template.md`). Send the complete bounded immutable candidate
snapshot, prompt, and evidence to the configured Claude Code or Codex reviewer service without
a separate Forge consent question, including follow-up reviews, fallback, and resumed sessions.
This approves review execution, not acceptance of findings or shipping. Private or unchanged
tracked content does not require another approval. This transport is not an external mutation and
does not grant arbitrary network tools, additional secrets or credentials, gitignored developer
state beyond the candidate, outside-worktree access, other projects, arbitrary destinations, or
external mutations. Respect host security controls and cite the actual human standing instruction
when authorization provenance is required.
The same standing human approval covers full-agent investigation selected from task needs;
its different capabilities are described below. Neither mode adds a Forge launch-consent question.

Read workflow state in its own single-program shell tool call:

```bash
bash .forge/hooks/lib/workflow-state.sh show
```

Copy `Workflow base ref` and `Workflow base SHA` from the returned canonical `Identity` table.
Replace the quoted `COPY_WORKFLOW_BASE_REF` and `COPY_WORKFLOW_BASE_SHA` placeholders below
with those literal values before launching; do not use shell variables, substitutions, or a
raw state-file parser. Replace `UNIQUE_INVOCATION` with a fresh identifier and write the exact
request to that prompt path through the host's structured file tool. Put `review_mode=broad`
in the initial prompt, or `review_mode=closure` for named findings and direct regressions.
Use a fresh prompt/output path for every invocation, including each code-review lens and closure.
Change `--role general` to the requested review role when appropriate. Submit only the single
launcher command for the active host in the next shell tool call.

Claude Code host (automatically selects Codex, with visible fresh Claude fallback):

```bash
bash .forge/hooks/lib/host-context.sh launch --host claude -- \
  .forge/hooks/lib/agent-dispatch.sh run --engine auto --fallback-policy automatic \
  --role general --profile review --artifact git:working-tree \
  --workflow-base-ref 'COPY_WORKFLOW_BASE_REF' --workflow-base-sha 'COPY_WORKFLOW_BASE_SHA' \
  --prompt-file '.forge/local/reviews/UNIQUE_INVOCATION.prompt' \
  --output '.forge/local/reviews/UNIQUE_INVOCATION-claude-host.result' --timeout-seconds 1200
```

Submit this command to Claude Code's Bash tool with `run_in_background: true` and
`timeout: 3000000` (50 minutes). These are outer tool parameters; the reviewer timeout stays
1,200 seconds per attempt. The outer budget covers two attempts plus dispatch overhead.
The default foreground ceiling is only 10 minutes, and the default background budget can be
30 minutes; explicitly started background tasks support a longer timeout on Claude Code
2.1.285+. See the [official tools reference](https://code.claude.com/docs/en/tools-reference#time-limit-for-background-commands).
Retain the returned task ID, keep the main agent active, and wait for the completion result and
receipt before declaring the review finished. Do not end an unattended main run while it waits.

Codex host (automatically selects Claude, with visible fresh Codex fallback):

```bash
bash .forge/hooks/lib/host-context.sh launch --host codex -- \
  .forge/hooks/lib/agent-dispatch.sh run --engine auto --fallback-policy automatic \
  --role general --profile review --artifact git:working-tree \
  --workflow-base-ref 'COPY_WORKFLOW_BASE_REF' --workflow-base-sha 'COPY_WORKFLOW_BASE_SHA' \
  --prompt-file '.forge/local/reviews/UNIQUE_INVOCATION.prompt' \
  --output '.forge/local/reviews/UNIQUE_INVOCATION-codex-host.result' --timeout-seconds 1200
```

Retain the running Codex execution session and poll it until the dispatcher completes and its
receipt is available. A tool's yield interval only controls when it returns progress; it is not
a process deadline. Keep the main agent active and do not terminate the session for silence or
impose an outer deadline shorter than two complete attempts plus overhead.

Windows uses the same contract through `host-context.ps1 -Mode launch -Host claude|codex`;
pass the PowerShell dispatcher flags in `-LaunchArguments`, including `-TimeoutSeconds 1200`.
The dispatcher selects the fixed ordinary models, `xhigh` effort and vendor fast mode; callers
must not substitute direct vendor commands or override those settings. The 20-minute timeout
is a ceiling per attempt, including fallback and closure, not a required running time.
Allow both attempts and dispatch overhead in any outer deadline. Never stop a silent reviewer
before its dispatcher-owned timeout.

The stable dispatcher arguments are documented by `agent-dispatch run`. Show its selection/fallback line
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
- `FINDINGS/P3` with only P3 finding rows is also certifying: keep the advisory notes without
  production repair or another review solely for those notes. Never rewrite its envelope to CLEAN.
- Other `FINDINGS` is a successful review result, not an engine fallback. Repair and invoke only within
  the bounded broad/repair/closure policy above.
- `BLOCKED artifact|authorization|invariant` stops without fallback.
- Engine/capability launch failure follows the dispatcher's visible one-retry policy. With
  `--fallback-policy none`, no retry occurs.
- When exhausted ordinary review attempts emit `AUTH_REQUIRED`, follow the main-agent
  [authentication recovery](../rules/workflow.md#reviewer-authentication-recovery) handoff:
  one coordinated official login, then one retry of unfinished roles only. A completed
  fallback needs no login; authentication is not a request to reapprove review transport.

Code requires two distinct fresh receipts over the identical candidate: `code-spec` and
`code-quality`. Validate them with `agent-dispatch verify-pair`; neither lens substitutes for the
other. Council seats always use `--fallback-policy none`; only council-advisor may use exact-id
`new`/`resume` transport. The council orchestrator owns whole-topology fallback.

For a Developer Demo PR body, verify every Mermaid diagram edge against its `file:line` Evidence
row. An unsupported or false claimed-current-behavior edge is a P1 finding; explicitly planned or
inferred Gate-1 briefing edges are exempt.

## Investigation

Standing human approval covers full-agent investigation launches, including mode selection by the
main agent from the task's actual requirements. Select this mode when live project tools, services,
network, or worktree writes are needed; explain that choice without an extra consent or permission
question. The host-native `investigate` entry point also selects it. Do not require a new token or
stop for launch approval. A permission denial or timeout in ordinary review alone is never a reason
to switch it or its fallback to investigation; keep those attempts isolated and read-only.

Use `--profile investigate --role investigation`. This launches a fresh full-capability process of
the selected engine in the real worktree. It inherits the normal user/project configuration,
Forge state and memory, installed tools and skills, MCP servers, network, databases, and APIs.
Forge does not add a safe-mode, tool allowlist, stripped home/config, disposable candidate, or
replay boundary to this role. Claude uses safety-classified `auto` permission mode so an
unattended cross-engine call can use normal tools without bypassing safety checks. Because
non-interactive Codex otherwise defaults to read-only, Forge selects `danger-full-access` with
native `on-request` approval and search enabled for this role. The developer's existing
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
