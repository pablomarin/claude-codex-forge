# Forge Workflow Runtime

Forge workflow runtime state is the machine-readable authority for phase gates that prose instructions cannot reliably enforce.

## Files

Runtime state is local and gitignored:

- `.claude/local/workflow-run.json` — current workflow run and gate status
- `.claude/local/workflow-events.jsonl` — append-only event log

These files are developer/worktree-local. Do not commit them.

## Phase 3 → Phase 4 gate

The first runtime gate is `phase-3-4`. It opens after the plan file contains an approved `## Implementation Handoff` and plan-review clean evidence has been stamped.

Pending state blocks implementation mutations until a crossing mode is selected.

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
.claude/hooks/lib/forge-workflow.sh approve-gate phase-3-4 --mode same-context|compact|fresh-session
.claude/hooks/lib/forge-workflow.sh check-tool
```

Windows installs a PowerShell mirror at `.claude/hooks/lib/forge-workflow.ps1`.

## Events

`workflow-events.jsonl` records durable event lines:

```jsonl
{"ts":"2026-06-15T00:00:00Z","event":"gate_opened","gate":"phase-3-4","plan_file":"docs/plans/example.md"}
{"ts":"2026-06-15T00:05:00Z","event":"gate_approved","gate":"phase-3-4","plan_file":"docs/plans/example.md","mode":"fresh-session"}
```

`open-gate` and `approve-gate` are idempotent for the same gate/plan/mode.

## Hook behavior

`check-phase-gates` runs as a `PreToolUse` hook for `Bash|Edit|Write`.

When no gate is pending, it exits 0 and normal Claude usage is unchanged.

When `phase-3-4` is pending, it allows:

- read/status Bash commands (`git status`, `git diff`, `rg`, `ls`, etc.)
- controller commands (`status`, `open-gate`, `approve-gate`)
- `Edit`/`Write` under `.claude/local/**`

It blocks implementation Bash/Edit/Write actions with stderr beginning:

```text
PHASE_GATE_PENDING: phase-3-4
```
