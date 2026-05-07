# Engineering Council — Peer Review Protocol

> How the council runs: dispatch, anonymization, escalation, and synthesis rules.

---

## Dispatch Rules

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

### Codex Advisor Dispatch

Run via the codex-pty shim (`.claude/hooks/lib/codex-pty.sh`) — works around openai/codex#19945, which silently drops `codex exec` output when stdio is detached from a TTY (Claude Code's Bash tool). On Windows, use `.claude/hooks/lib/codex-pty.ps1` instead. Both forward args verbatim to `codex exec`:

```bash
.claude/hooks/lib/codex-pty.sh exec \
  -m "gpt-5.5" \
  -c model_reasoning_effort="high" \
  -c service_tier="fast" \
  --sandbox read-only \
  --ephemeral \
  --color never \
  "[persona description + question + context]"
```

**Note:** Use `reasoning_effort="high"` (not `xhigh`) for advisors to control cost. Reserve `xhigh` for the chairman only.

Run Codex advisors with `run_in_background: true` in the Bash tool so they execute concurrently with Claude subagents.

### Chairman Dispatch

After all advisors complete, construct the chairman prompt:

```bash
.claude/hooks/lib/codex-pty.sh exec \
  -m "gpt-5.5" \
  -c model_reasoning_effort="xhigh" \
  -c service_tier="fast" \
  --sandbox read-only \
  --ephemeral \
  --color never \
  "[chairman instructions + ALL raw advisor outputs + original question + codebase context]"
```

**Timeout: 1200000ms (20 minutes)** — chairman synthesis with xhigh reasoning can take time.

---

## Escalation Rules

### 3-then-5 Model (auto-triggered council only)

**Quick Council (3 advisors):** Simplifier (Claude) + Contrarian (Codex) + Pragmatist (Claude)

**Escalation triggers (any one is sufficient):**

- Any advisor returns OBJECT
- Any advisor reports low confidence
- Decision affects irreversible surface (see High-Impact Surfaces below)
- No majority verdict (3-way split)

**Full Council (+2 advisors):** Add Scalability Hawk (Claude) + Maintainer (Codex)

### Standalone `/council`

Always uses all 5 advisors. No escalation needed.

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

## Contrarian Gate (Auto-Trigger Only)

Before firing the full council, the Contrarian/Codex validates the "default wins" claim:

```bash
.claude/hooks/lib/codex-pty.sh exec \
  -m "gpt-5.5" \
  -c model_reasoning_effort="high" \
  -c service_tier="fast" \
  --sandbox read-only \
  --ephemeral \
  --color never \
  "Review this approach comparison for [project]. The author claims the Default approach dominates.

[Insert approach comparison table here]

Your job: validate or object.
- If the default clearly wins on most axes: respond VALIDATE with a one-line rationale.
- If the alternative has a credible case: respond OBJECT with your strongest counter-argument.
- If you need more information to decide: respond INSUFFICIENT with what's missing.

Respond with EXACTLY one of: VALIDATE, OBJECT, or INSUFFICIENT followed by your rationale."
```

**Decision flow after Contrarian gate:**

- VALIDATE → skip council, proceed with default
- OBJECT → check cheapest falsifying test (< 30 min → spike first; else check high-impact surface → fire council)
- INSUFFICIENT → fire council (ambiguity = risk)

---

## Fallback (No Codex)

When Codex CLI is not installed:

| Component          | Replacement                                        |
| ------------------ | -------------------------------------------------- |
| Codex advisors     | Skipped (run Claude advisors only)                 |
| Contrarian gate    | User validates the "default wins" claim            |
| Chairman synthesis | User is chairman — raw outputs shown, user decides |

**Detection:**

```bash
command -v codex &>/dev/null && echo "available" || echo "unavailable"
```

---

## Minority Report Requirement

The chairman MUST preserve dissent:

- If ANY advisor returned OBJECT → minority report is MANDATORY
- The minority report names WHO objected, WHAT their concern was, and WHY it was overruled
- "No minority objections" is ONLY valid when every advisor returned APPROVE
- This applies even if the chairman disagrees with the objection

This is the single most important rule in the protocol. Without it, synthesis erases the diversity the council exists to create.
