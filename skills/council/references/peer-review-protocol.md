# Engineering Council — Peer Review Protocol

> How the council runs: eligibility, topology, anonymization, fallback, and synthesis rules.

---

## Eligibility

Run this full topology only for an explicit developer request, an unresolved concrete high-impact
architectural fork, or a genuine non-destructive product or engineering decision required to
continue an active native Goal. The cheapest safe falsifying check is the
smallest reversible check that can disprove the disputed assumption without changing production.
If it produces a deterministic smallest answer, use that answer instead of Council. Ordinary
plan/code-review findings, soft warnings, implementation choices, and engine failures stay with
their owning workflow and are not council triggers.

## Dispatch Rules

### Dynamic six-seat topology (CRITICAL)

Use the fixed-target compatibility launcher with its exact council target: `host-context.sh
launch --host <host> -- .forge/hooks/lib/council-dispatch.sh ...` on Unix, or
`host-context.ps1 -Mode launch -Host <host> -LaunchTarget council
-LaunchArgumentsJson ...` on Windows. `main_host` is routing metadata, not
authenticated session identity; candidate and worktree evidence remain the
review authority. The dispatcher starts five fresh advisor sessions, resumes those exact sessions for
anonymous peer critique, then starts one fresh chairman session: six sessions
and eleven turns. The healthy assignment is three advisor seats on the main
engine, two advisor seats plus chairman on the other engine. Every seat uses
`fallback_policy=none`. A known unavailable other engine starts one all-main
attempt; a runtime other-engine failure discards the entire partial council and
reruns all six fresh sessions on main. A main-engine failure blocks; there is no
per-seat fallback.

### Parallelism (CRITICAL)

All advisors dispatch IN PARALLEL. The only serial dependency is the chairman, which runs after all advisors complete.

```
Step 1: All advisors fire simultaneously
  ├── Claude subagents via Agent tool (multiple tool calls in one message)
  ├── Codex advisors via codex exec (run_in_background: true)
  │
  ▼ Wait for all to complete
  │
Step 2: Chairman (Codex exec) — SEQUENTIAL
  │   Receives all raw outputs
  │
  ▼
Step 3: Present to user
```

### Claude Advisor Dispatch

Spawn via the Task tool with `subagent_type: "council-advisor"`. Include in the prompt:

1. The advisor persona (copied from `advisors.md`)
2. The question or decision context
3. Any relevant file paths or code snippets

All Claude advisors go in a SINGLE message with multiple Task tool calls = parallel execution.

### Output Capture (CRITICAL — applies to ALL codex invocations below)

Every codex call writes TWO files:

| File pattern                                                     | When written           | Contents                                                                                | Read it when                                                     |
| ---------------------------------------------------------------- | ---------------------- | --------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `/tmp/council_<role>_response.txt` (via `--output-last-message`) | Only at clean shutdown | JUST the assistant's final message — no banner, no prompt echo, no `tokens used` footer | Happy path: parse the response                                   |
| `/tmp/council_<role>.txt` (stdout+stderr via `> ... 2>&1`)       | Streamed live          | Banner + entire echoed prompt + response + `tokens used` footer + any errors            | Failure path: diagnose why the response file is missing or empty |

**Why both:** the `--output-last-message` file gives a clean, marker-free response (codex 0.124+ stable, per [openai/codex#4644](https://github.com/openai/codex/pull/4644)). The stdout capture is forensic — if codex hangs, crashes, or rate-limits before producing a final agent message, the response file is absent or 0-byte, but the stdout capture still holds whatever codex printed before dying. Without the stdout capture you cannot distinguish "codex failed mid-stream" from "codex succeeded but my parsing was wrong" — exactly the misread that prompted this two-file pattern.

**Failure-mode contract:**

- Response file exists and is non-empty → codex succeeded; use that text verbatim.
- Response file missing OR empty → codex did NOT reach clean shutdown with a final agent message. Read the stdout capture for diagnostics (look for the `codex` marker, partial response sections, or `codex-pty:`-prefixed shim errors). Surface the failure to the user with the relevant excerpt; do not silently fall back to the chairman-less path without telling them what codex actually said.

### Codex Advisor Dispatch

Run via the codex-pty shim (`.forge/hooks/lib/codex-pty.sh`) — works around openai/codex#19945, which silently drops `codex exec` output when stdio is detached from a TTY (Claude Code's Bash tool). On Windows, use `.forge/hooks/lib/codex-pty.ps1` instead. Both forward args verbatim to `codex exec`:

```bash
.forge/hooks/lib/codex-pty.sh exec \
  -m "gpt-5.6-sol" \
  -c model_reasoning_effort="high" \
  -c service_tier="fast" \
  --sandbox read-only \
  --ephemeral \
  --color never \
  --output-last-message /tmp/council_<advisor>_response.txt \
  "[persona description + question + context]" \
  > /tmp/council_<advisor>.txt 2>&1
```

Replace `<advisor>` with the role name (e.g. `contrarian`, `maintainer`). The `--output-last-message` flag writes the clean response; the trailing redirect captures the full transcript for forensics (see "Output Capture" above).

**Note:** Use `reasoning_effort="high"` (not `xhigh`) for advisors to control cost. Reserve `xhigh` for the chairman only.

Run Codex advisors with `run_in_background: true` in the Bash tool so they execute concurrently with Claude subagents.

### Chairman Dispatch

After all advisors complete, construct the chairman prompt:

```bash
.forge/hooks/lib/codex-pty.sh exec \
  -m "gpt-5.6-sol" \
  -c model_reasoning_effort="xhigh" \
  -c service_tier="fast" \
  --sandbox read-only \
  --ephemeral \
  --color never \
  --output-last-message /tmp/council_chairman_response.txt \
  "[chairman instructions + ALL raw advisor outputs + original question + codebase context]" \
  > /tmp/council_chairman.txt 2>&1
```

**Timeout: 1200000ms (20 minutes)** — chairman synthesis with xhigh reasoning can take time.

After the call completes, read `/tmp/council_chairman_response.txt` (the clean verdict). If it is missing or empty, apply the failure-mode contract from "Output Capture" above — inspect `/tmp/council_chairman.txt` for partial output or error excerpts and surface the diagnosis to the user.

---

## Full Topology

The executable dispatcher always runs five advisor starts, five anonymous peer-review resumes, and
one fresh chairman synthesis. There is no quick or three-seat mode. If the other engine is known
unavailable, the dispatcher starts one all-main-engine topology. If it fails during a mixed attempt,
the dispatcher discards that attempt and reruns the complete topology on main.

---

## High-Impact Surfaces (Canonical List)

This is the single source of truth for what constitutes a "high-impact surface." All other files reference this list.

- **Schema/database migrations** — DDL changes, new tables, column alterations
- **Public API contracts** — endpoint additions/removals, request/response shape changes
- **Authentication/permissions** — auth flows, RBAC, token handling, session management
- **Payment/billing** — charge logic, subscription management, refund flows
- **Configuration defaults affecting all users** — feature flags, rate limits, default settings
- **Rollout/deployment strategy** — blue-green, canary, migration ordering
- **Architecture boundaries** — service boundaries, shared libraries, database ownership, message contracts

---

## Minority Report Requirement

The chairman MUST preserve dissent:

- If ANY advisor returned OBJECT → minority report is MANDATORY
- The minority report names WHO objected, WHAT their concern was, and WHY it was overruled
- "No minority objections" is ONLY valid when every advisor returned APPROVE
- This applies even if the chairman disagrees with the objection

This is the single most important rule in the protocol. Without it, synthesis erases the diversity the council exists to create.
