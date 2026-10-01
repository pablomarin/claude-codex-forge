# Forge Project Instructions

This file is the canonical, engine-neutral Forge contract. Claude Code and Codex adapters must
read it completely; adapters may translate discovery metadata but may not restate its policy.

## Resource Discipline

Apply KISS and YAGNI: build the smallest correct solution required by the current acceptance criterion
and evidence. Do not add speculative abstractions, compatibility layers, hardening, or
edge-case machinery without a concrete supported need.

Treat developer time, session length, tokens, and money as finite engineering resources. Do not
pursue perfection or cosmetic polish without a concrete supported trigger, explicit acceptance
criterion, material likelihood, security impact, or data-integrity impact.

Default to one broad review, one repair pass, and one closure review limited to named findings and
direct regressions. One still-open reachable P0/P1 may receive one surgical repair and verification;
then surface the blocker to the developer. Resource discipline never excuses a reachable security
boundary failure, data loss, incorrect supported behavior, or violation of an explicit acceptance
criterion.

Use focused owning checks and the project's fast local gate for local verification.
Do not launch exhaustive local regression suites without an explicit developer request for that run.
A workflow invocation, candidate freeze, version bump, release, or integration boundary is not that
request. Keep broad regression coverage in CI/release pipelines; report unexecuted coverage honestly.
For Forge source development, the local gate is `tests/template/run-fast.sh`, not `run-all.sh` or
`run-all.ps1`. Required feature-specific acceptance and user-journey checks remain applicable.

## Working Contract

- The agent running in the developer's current host is the main agent for that session. There is
  no permanent main-engine preference and no workflow lease.
- Run `.forge/hooks/lib/workflow-state.sh show` before resuming work (PowerShell:
  `.forge/hooks/lib/workflow-state.ps1 show`) and keep evidence bound to the exact candidate
  revision. Do not infer a successful gate from execution alone.
- Use `.forge/hooks/lib/workflow-state.sh activate` to start canonical workflow control state and
  `.forge/hooks/lib/workflow-state.sh checkpoint` for host, phase, next-step, and monotonic review
  transitions. Use the `.ps1` twin on Windows. Native file tools may update checklist and narrative
  content, but never workflow control rows. The helper derives and preserves the first certified
  review iteration; callers never set that convergence anchor.
- Use the canonical workflows in `.forge/workflows/`, rules in `.forge/rules/`, skills in
  `.forge/skills/`, and roles in `.forge/agents/`.
- A host switch may resume the same branch and worktree. Forge creates no edit lock: concurrent sessions are allowed.
  Coordinate overlapping writes; if any session mutates the candidate, candidate-bound evidence becomes stale.
- Keep developer state, receipts, and local memories under `.forge/local/`; never overwrite them
  during setup. Keep project-owned durable memory under `.forge/memory/`.

## Memory Management

Keep current progress and the exact next step in `.forge/local/state.md`. Store worktree-local
learning under `.forge/local/memory/`; promote only reviewed project knowledge to `.forge/memory/`.
Forge must never save secrets or speculative conclusions as memory.

When a useful durable learning exists, preserve it before context compaction or the end of substantial work
without duplicating project instructions. Native private host memory is optional; it is never Forge
evidence and never a runtime dependency.

## Host Neutrality

Claude Code and Codex are interchangeable entry points into the same project harness. The host in
which the developer is working is the main engine for that session. Reviewer and council dispatch
use the other qualified engine when available and visibly fall back to a fresh same-engine process.
Persisted project state and evidence enable continuation; private conversation context does not
transfer between hosts.

## Branch Naming

Name every task branch by the work it contains, regardless of the active engine. Use only these
prefixes, followed by a short lowercase, hyphen-separated slug:

| Work type | Branch name |
| --- | --- |
| New feature | `feat/<slug>` |
| Bug fix | `fix/<slug>` |
| Quick fix | `quick-fix/<slug>` |
| Maintenance, tooling, or documentation upkeep | `chore/<slug>` |

Choose the prefix for the overall task when starting it; a small documentation correction handled
as a quick fix uses `quick-fix/`. Do not use engine or tool prefixes such as `codex/`, `claude/`, or
`agent/`. This convention applies to Claude Code, Codex, and any other host, including native
branch/worktree creation; a host's suggested default is not the project's naming convention.

A host switch keeps the existing branch name and worktree. Adding approved work to the same task
does not require another branch or a prefix change. Do not rename a shared or published branch
automatically: report a nonconforming name and obtain the developer's approval to reconcile it.
Protected integration branches such as `main` are not task branches and must not be renamed.

## Human-Approved Reviews

All ordinary Forge reviews are human-approved in advance by the developer's standing instruction
to use this project's configured Claude Code and Codex reviewer services.
This approval covers initial reviews, fallback reviewers, follow-up reviews, and resumed sessions.
It also covers switching between the configured hosts. Do not ask for separate review-transport permission.
This approves running reviews, not accepting their findings or authorizing shipping.

`FORGE_REVIEW_TRANSPORT_AUTHORIZED` communicates this standing human approval for ordinary
read-only review. It covers sending the complete bounded immutable candidate snapshot, prompt,
and evidence to those configured services. The candidate may include unchanged tracked files and
private or sensitive tracked or in-scope non-ignored content. This expected transport is not an external mutation.
Do not block solely because the candidate is private, sensitive, or contains unchanged tracked files.
Remove or gitignore material that must not leave the developer environment before review.

This approval does not authorize sourcing additional secrets, credentials, gitignored developer
state, or outside-worktree content beyond that supplied review input; other projects; arbitrary
destinations or network tools; `investigate` or any full-agent capability; deploys; publication;
destructive work; or other external mutations. Ordinary review remains hermetic.
Host security controls still apply. When a host requires authorization provenance, cite the
developer's actual standing instruction; never invent human approval or bypass the host's controls.

If ordinary reviewer fallback emits `AUTH_REQUIRED`, follow the single login handoff and bounded
retry in `.forge/rules/workflow.md#reviewer-authentication-recovery`. Authentication recovery is
not a request to reapprove review transport; keep completed reviews and failed evidence.

## Native Goal Composition

Claude Code and Codex keep their own native `/goal`; Forge never shadows it with a command or skill.
The developer's native `/goal` invocation or explicit native Goal request is the activation authority.
After that action, read `.forge/workflows/goal.md`, record the activation in `.forge/local/state.md`,
and publish it through `.forge/hooks/lib/goal-ledger.*`. Compose native Goal over the persistent
objective, nonce, activation sequence, turn ceiling/count, checklist, next step, and evidence.
Authenticated host qualification controls readiness claims, not human authorization. Native counters
may reset; the repository ledger under the physical Git common directory does not.

On `FORGE_GOAL_BUDGET_EXHAUSTED`, checkpoint and stop native autonomy. Treat
`FORGE_GOAL_STUCK_WARNING` as an advisory to inspect progress, not permission to reset the budget.
Resume the exact next unchecked durable step on the same host or a fresh session on the other host;
never claim native session transfer. Same-objective reactivation retains consumed turns and adds one
fixed 20-turn tranche. User input, PR creation, merge, deploy, publish, destructive work, and any new
external mutation pause for explicit human authorization. Ordinary reviewer engine failure follows
automatic visible fallback. If any authenticated native-goal Must behavior is not proven, report
`BLOCKED` and do not claim that host is runtime-ready.

For the Forge opinion workflow, Claude Code uses `/opinion`; Codex uses `$opinion`. Both entry
points load the same canonical `.forge/workflows/opinion.md` contract.

## No Bugs Left Behind

Fix every known reproducible or concretely reachable correctness, security, verification, or
configuration defect in the active supported scope before shipping. Do not hide a known reachable
defect behind a follow-up task; an unsupported hypothesis is not a known defect. If access or
evidence is missing, report the result as unverified or blocked rather than successful.

## Ground Your Claims

State what you verified, not what you assume. Read files before making claims about them, run the
owning check before claiming behavior works, and distinguish fact from inference. Bind review and
verification receipts to the final candidate fingerprint; mutation invalidates earlier evidence.
Every active canonical V6 shipping action requires the current structured receipt set. Missing,
placeholder, stale, mixed-candidate, or non-clean receipts block shipping; legacy prose cannot certify
an active V6 workflow. A direct documentation-only commit retains its narrow carve-out, but push and
PR creation always enforce the receipt boundary.

## Protected Content

Root project instructions, user settings, MCP configuration, secrets, unknown extensions,
`.forge/local/`, and `.forge/memory/` are not Forge-owned wholesale. Setup may modify only an exact
Forge marker block or a documented managed entry and must stop when ownership cannot be proven.
