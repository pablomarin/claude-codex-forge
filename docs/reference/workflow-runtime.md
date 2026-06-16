# Forge Workflow Runtime

Forge workflow runtime state is the machine-readable authority for phase gates that prose instructions cannot reliably enforce.

## Files

Runtime state is local and gitignored:

- `.claude/local/workflow-run.json` — current workflow run and gate status
- `.claude/local/workflow-events.jsonl` — append-only event log

These files are developer/worktree-local. Do not commit them.

## Phase 3 → Phase 4 gate

The first runtime gate is `phase-3-4`. It opens after the plan file contains an approved `## Implementation Handoff` and plan-review clean evidence has been stamped.

Non-approved state blocks implementation mutations until the gate is explicitly approved. Mode selection and approval are separate so the workflow can leave `fresh-session` / `compact` crossings in an awaiting state; command instructions require the resumed or fresh implementation session to read durable artifacts before approving. The v1 runtime records the selected mode but does **not** cryptographically enforce session identity.

### State machine

| State | Meaning | Implementation allowed? |
| --- | --- | --- |
| `pending` | Gate opened; no crossing mode selected yet. | No |
| `awaiting-compact` | User selected `compact`; approval must happen after compaction/resume. | No |
| `awaiting-fresh-session` | User selected `fresh-session`; approval should happen in the fresh implementation session after reading the handoff. | No |
| `approved` | Gate crossed; Phase 4 implementation may mutate code. | Yes |

Mode transitions:

```text
pending
  ├─ select-gate --mode same-context  → approved
  ├─ select-gate --mode compact       → awaiting-compact
  └─ select-gate --mode fresh-session → awaiting-fresh-session

awaiting-compact / awaiting-fresh-session
  └─ approve-gate --mode <selected-mode> → approved
```

A selected awaiting mode is intentionally sticky: selecting `fresh-session` cannot be re-selected as `same-context` without manual state repair. This prevents accidental drift across the seam.

```json
{
  "version": 1,
  "workflow": "/new-feature example",
  "phase": "3 — Design",
  "next_step": "Implementation Handoff",
  "plan_file": "docs/plans/example.md",
  "gates": {
    "phase-3-4": {
      "status": "pending",
      "opened_at": "2026-06-15T00:00:00Z",
      "reason": "Implementation Handoff complete; choose same-context, compact, or fresh-session before implementation.",
      "allowed_modes": ["same-context", "compact", "fresh-session"],
      "selected_mode": null,
      "selected_at": null,
      "approved_at": null
    }
  }
}
```

Selecting `fresh-session` or `compact` records an awaiting state while implementation remains blocked:

```json
{
  "gates": {
    "phase-3-4": {
      "status": "awaiting-fresh-session",
      "selected_mode": "fresh-session",
      "selected_at": "2026-06-15T00:03:00Z",
      "approved_at": null
    }
  }
}
```

Approved state records the selected mode:

```json
{
  "gates": {
    "phase-3-4": {
      "status": "approved",
      "selected_mode": "fresh-session",
      "selected_at": "2026-06-15T00:03:00Z",
      "approved_at": "2026-06-15T00:05:00Z"
    }
  }
}
```

## Controller

Use the shipped controller from the project root or worktree root:

```bash
.claude/hooks/lib/forge-workflow.sh status
.claude/hooks/lib/forge-workflow.sh open-gate phase-3-4 --plan docs/plans/<name>.md
.claude/hooks/lib/forge-workflow.sh select-gate phase-3-4 --mode same-context|compact|fresh-session
.claude/hooks/lib/forge-workflow.sh approve-gate phase-3-4 --mode same-context|compact|fresh-session
.claude/hooks/lib/forge-workflow.sh check-tool
```

Windows installs a PowerShell mirror at `.claude/hooks/lib/forge-workflow.ps1`.

Command semantics:

- `open-gate` creates the `pending` gate and appends `gate_opened`.
- `select-gate --mode same-context` records `gate_selected`, immediately records `gate_approved`, and sets status to `approved`.
- `select-gate --mode compact` records `gate_selected`, sets status to `awaiting-compact`, and leaves implementation blocked until `approve-gate --mode compact`.
- `select-gate --mode fresh-session` records `gate_selected`, sets status to `awaiting-fresh-session`, and leaves implementation blocked until `approve-gate --mode fresh-session` in the resumed/fresh implementation flow.
- `approve-gate` on an awaiting state requires `--mode` to match the selected mode.
- `approve-gate` from raw `pending` remains supported for manual/backward-compatible recovery.

## Events

`workflow-events.jsonl` records durable event lines:

```jsonl
{"ts":"2026-06-15T00:00:00Z","event":"gate_opened","gate":"phase-3-4","plan_file":"docs/plans/example.md"}
{"ts":"2026-06-15T00:03:00Z","event":"gate_selected","gate":"phase-3-4","plan_file":"docs/plans/example.md","mode":"fresh-session"}
{"ts":"2026-06-15T00:05:00Z","event":"gate_approved","gate":"phase-3-4","plan_file":"docs/plans/example.md","mode":"fresh-session"}
```

`open-gate`, `select-gate`, and `approve-gate` are idempotent for the same gate/plan/mode.

## Hook behavior

`check-phase-gates` runs as a `PreToolUse` hook for `Bash|Edit|Write`.

When no gate exists, or when `phase-3-4` is approved, it exits 0 and normal Claude usage is unchanged.

When `phase-3-4` is `pending`, `awaiting-compact`, or `awaiting-fresh-session`, it allows:

- read/status Bash commands (`git status`, `git diff`, `rg`, `ls`, etc.)
- controller commands (`status`, `open-gate`, `select-gate`, `approve-gate`)
- `Edit`/`Write` under `.claude/local/**`

It blocks implementation Bash/Edit/Write actions with stderr beginning:

```text
PHASE_GATE_PENDING: phase-3-4
```

`SessionStart` also checks `.claude/local/workflow-run.json`. If it finds `awaiting-compact` or `awaiting-fresh-session`, it injects a concise resume notice into context:

```text
WORKFLOW_RUNTIME_GATE: phase-3-4 status=<status> mode=<mode> plan=<plan>
```

The notice tells the resumed/fresh session to read the plan's `Implementation Handoff` and run the matching `approve-gate` command before Phase 4. SessionStart resolves the runtime state from stdin `cwd` first, then falls back to `CLAUDE_PROJECT_DIR`, so worktree sessions read their own `.claude/local/workflow-run.json`.

## Crossing-mode playbooks

### Same context

```bash
.claude/hooks/lib/forge-workflow.sh select-gate phase-3-4 --mode same-context
```

This selects and approves immediately. Use for small plans where carrying the current context is beneficial.

### Compact

```bash
.claude/hooks/lib/forge-workflow.sh select-gate phase-3-4 --mode compact
```

Then stop for `/compact`. After compaction/resume, read the Implementation Handoff and run:

```bash
.claude/hooks/lib/forge-workflow.sh approve-gate phase-3-4 --mode compact
```

### Fresh session

```bash
.claude/hooks/lib/forge-workflow.sh select-gate phase-3-4 --mode fresh-session
```

Then stop. A new session in the same worktree should read `.claude/local/workflow-run.json`, the plan file, and the plan's `Implementation Handoff`, then run:

```bash
.claude/hooks/lib/forge-workflow.sh approve-gate phase-3-4 --mode fresh-session
```

Only after approval should Phase 4 begin.
