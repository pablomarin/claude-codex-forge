# Forge Runtime Workflow Engine Plan

## Goal

Make Forge workflows deterministic at runtime instead of relying on prose instructions and agent self-discipline. The first target is the Phase 3 → Phase 4 context-efficiency seam: after an approved plan and `Implementation Handoff`, the agent must stop at a machine-enforced gate before implementation can mutate code.

## Archon Findings to Borrow

Archon controls workflow execution with a runtime engine, not only prompts:

- Workflow definitions are data (`.archon/workflows/*.yaml`) parsed by a loader.
- Execution is a DAG of nodes with `depends_on`, `when`, `trigger_rule`, and explicit node types.
- Human pauses are first-class `approval` nodes that store paused state and require `/workflow approve` or `/workflow reject`.
- Fresh context is explicit (`context: fresh` or loop `fresh_context: true`).
- Loops are bounded (`until`, `max_iterations`) and often force fresh context each iteration.
- Each node has durable output (`$nodeId.output`), run artifacts, logs, and resumability.

Forge should borrow the control model, but not Archon's TypeScript engine wholesale. Forge is a no-build template toolkit with Bash/PowerShell parity, so the first implementation should be a small deterministic controller plus hooks.

## Design Principles

1. **Runtime authority beats prose.** Markdown commands can explain what to do, but hooks/controller scripts decide whether the agent is allowed to proceed.
2. **Start narrow.** Enforce the Phase 3 → Phase 4 seam before attempting a full workflow DAG engine.
3. **Artifact-first context.** Implementation after the seam must read plan/handoff artifacts instead of relying on prior transcript context.
4. **Cross-platform parity.** Any shipped controller/hook logic needs `.sh` and `.ps1` twins with tests.
5. **Fail closed at gates, fail open when inactive.** A pending phase gate blocks implementation; absence of a workflow run should not break normal Claude usage.

## Proposed Architecture

### 1. Workflow Runtime State

Add a gitignored local state artifact:

```text
.claude/local/workflow-run.json
.claude/local/workflow-events.jsonl
```

Initial schema:

```json
{
  "version": 1,
  "workflow": "/new-feature",
  "phase": "3 — Design",
  "next_step": "Implementation Handoff",
  "plan_file": "docs/superpowers/plans/<name>.md",
  "gates": {
    "phase-3-4": {
      "status": "pending",
      "opened_at": "<ISO8601>",
      "reason": "Implementation Handoff complete; choose same-context, compact, or fresh-session before implementation.",
      "allowed_modes": ["same-context", "compact", "fresh-session"],
      "selected_mode": null,
      "approved_at": null
    }
  }
}
```

`workflow-events.jsonl` records append-only events:

```jsonl
{"ts":"...","event":"gate_opened","gate":"phase-3-4","plan_file":"..."}
{"ts":"...","event":"gate_approved","gate":"phase-3-4","mode":"fresh-session"}
```

### 2. Runtime Controller Scripts

Ship paired scripts:

```text
hooks/lib/forge-workflow.sh
hooks/lib/forge-workflow.ps1
```

Subcommands:

```bash
forge-workflow status
forge-workflow open-gate phase-3-4 --plan docs/superpowers/plans/<name>.md
forge-workflow approve-gate phase-3-4 --mode same-context|compact|fresh-session
forge-workflow check-tool --event PreToolUse
```

Responsibilities:

- Read/write `.claude/local/workflow-run.json`.
- Append event JSONL.
- Detect pending gates.
- Decide whether a tool action is allowed.
- Print terse, machine-stable blocker messages.

### 3. Phase Gate Hook

Add a new PreToolUse hook:

```json
{
  "matcher": "Bash|Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/check-phase-gates.sh"
    }
  ]
}
```

Windows mirror:

```json
"powershell -ExecutionPolicy Bypass -File \"$CLAUDE_PROJECT_DIR/.claude/hooks/check-phase-gates.ps1\""
```

Hook behavior:

- If no `workflow-run.json` or no pending gate: exit 0.
- If `phase-3-4` pending:
  - Allow reads and safe status commands.
  - Allow writes under `.claude/local/**` needed to approve the gate.
  - Block code writes and implementation Bash commands.
  - Emit:

```text
PHASE_GATE_PENDING: phase-3-4
Implementation Handoff is complete. Choose how to cross the Phase 3→4 seam:
- same-context: approve and continue in this session
- compact: run /compact, then approve
- fresh-session: start a new session in the worktree and approve there
Allowed command: hooks/lib/forge-workflow.sh approve-gate phase-3-4 --mode <mode>
```

This prevents the agent from drifting into Phase 4 even if it ignores the markdown instruction to stop.

### 4. Workflow Command Changes

Update `/new-feature` Phase 3.4:

1. Append `## Implementation Handoff` to the plan.
2. Open the phase gate:

```bash
.claude/hooks/lib/forge-workflow.sh open-gate phase-3-4 --plan docs/superpowers/plans/<name>.md
```

3. Stop and tell the user to choose:
   - same context
   - `/compact`
   - fresh session

Update `/fix-bug` complex path the same way.

### 5. Approval UX

Manual approval can be done by the agent after explicit user choice:

```bash
.claude/hooks/lib/forge-workflow.sh approve-gate phase-3-4 --mode compact
```

For `compact` mode, recommended sequence:

1. User chooses compact.
2. Agent opens/keeps gate pending and says: run `/compact`, then continue.
3. After compaction, agent runs `approve-gate --mode compact` and proceeds.

For `fresh-session` mode:

1. Agent leaves gate pending.
2. User starts a new session in the worktree.
3. Fresh agent reads `.claude/local/workflow-run.json`, plan file, and handoff.
4. Fresh agent runs `approve-gate --mode fresh-session` and proceeds.

### 6. Future YAML Runtime Layer

After the phase gate proves useful, add declarative workflow specs. Because Forge has no YAML parser dependency, choose one of:

- **JSON first:** `.claude/workflows/new-feature.json` parsed by Bash/PowerShell with constrained schema.
- **YAML later:** only if we ship a parser or restrict to a tiny line-oriented subset.

Proposed shape:

```json
{
  "name": "new-feature",
  "phases": [
    { "id": "requirements", "next": "research" },
    { "id": "research", "next": "design" },
    {
      "id": "design",
      "exit_requires": ["plan_review_clean", "implementation_handoff_present"],
      "gate": "phase-3-4",
      "next": "implementation"
    },
    { "id": "implementation", "context_policy": "fresh_recommended", "next": "quality" }
  ]
}
```

The controller would validate phase transitions and gates against this spec. Markdown commands become documentation and prompts; the spec/controller becomes authority.

## Implementation Tasks

### Task 1 — Runtime state fixtures and schema docs

- Add `docs/reference/workflow-runtime.md`.
- Document `workflow-run.json`, `workflow-events.jsonl`, gate statuses, and modes.
- Add fixtures under `tests/template/fixtures/workflow-runtime/`.

### Task 2 — Bash controller

- Add `hooks/lib/forge-workflow.sh`.
- Implement `status`, `open-gate`, `approve-gate`, `check-tool`.
- Use no required dependencies beyond POSIX-ish shell; use `jq` if present, grep/sed fallback otherwise.
- Ensure idempotent open/approve behavior.

### Task 3 — PowerShell controller

- Add `hooks/lib/forge-workflow.ps1`.
- Mirror Bash semantics exactly.
- Use PowerShell JSON support.
- Avoid PS 7-only syntax; maintain PS 5.1 floor.

### Task 4 — Phase gate hooks

- Add `hooks/check-phase-gates.sh` and `.ps1`.
- Wire them into `settings/settings.template.json` and `settings/settings-windows.template.json` for `Bash|Edit|Write` PreToolUse.
- Allow `.claude/local/**` updates and read/status commands while gate is pending.
- Block implementation writes/Bash while gate is pending.

### Task 5 — Workflow command integration

- Update `commands/new-feature.md` Phase 3.4 to open the gate and stop.
- Update `commands/fix-bug.md` complex path similarly.
- Update `rules/workflow.md` to state that pending phase gates are runtime authority.
- Update reference docs and CHANGELOG.

### Task 6 — Tests

Add tests for:

- `open-gate` creates expected state.
- `open-gate` is idempotent.
- `approve-gate` records selected mode and event.
- Pending gate blocks Bash implementation commands.
- Pending gate blocks Edit/Write to source paths.
- Pending gate allows `.claude/local/**` writes.
- Approved gate allows implementation.
- Bash/PowerShell source parity contracts.
- Settings include hook in both Unix/Windows templates.

### Task 7 — Dogfood test

In `tiny_notes`:

1. Run `/new-feature note-archive-and-restore` manually.
2. Let Phase 3 write plan + Implementation Handoff.
3. Confirm gate blocks Phase 4 mutation if agent tries to continue.
4. Choose `fresh-session`.
5. Start a fresh session in the worktree.
6. Continue from `workflow-run.json` + plan handoff.
7. Measure context drop and quality outcome.

### Dogfood results — 2026-06-17

Target repo: `/home/aescala82/projects/forge-empty`.

- `pinned-notes` validated the Forge-upgrade preflight fix and the basic durable gate path: the generated worktree included `.claude/hooks/lib/forge-workflow.sh` and `.claude/hooks/check-phase-gates.sh`, the plan contained `## Implementation Handoff` + `### Task Contract`, and the feature shipped with 222 tests, ruff, mypy strict, code review, E2E, and regression passing. That run used the older direct-approval semantics, so it did **not** validate the later awaiting-state fix.
- `note-count-command` validated the current `fresh-session` state machine: `select-gate --mode fresh-session` left `phase-3-4` in `awaiting-fresh-session` with `approved_at=null`, recorded `gate_selected`, and blocked attempted `Edit` and implementation `Bash` actions with `PHASE_GATE_PENDING`.
- The fresh implementation session received `WORKFLOW_RUNTIME_GATE` from `SessionStart`, read `docs/plans/note-count-command.md` → `## Implementation Handoff`, approved via `.claude/hooks/lib/forge-workflow.sh approve-gate phase-3-4 --mode fresh-session`, then implemented after the gate was approved.
- Quality outcome stayed acceptable: `note-count-command` passed 234 pytest tests, ruff, `mypy --strict tiny_notes.py`, code-review loop, and CLI E2E.
- Context outcome was directionally positive: planning/gate session peaked at 197,309 context tokens; fresh implementation session peaked at 119,896. This is not a controlled benchmark, but it supports the Phase 3→4 seam as a runtime context-efficiency lever.

## Acceptance Criteria

- The agent cannot enter Phase 4 implementation while `phase-3-4` gate is pending.
- The gate can be approved only with one of `same-context`, `compact`, or `fresh-session`.
- The gate state is durable under `.claude/local/` and survives `/clear`, `/compact`, and fresh sessions.
- Existing workflows with no active gate behave unchanged.
- Bash and PowerShell implementations have matching behavior.
- Tests pass for controller, hooks, settings, and command text contracts.

## Non-goals for First PR

- Full Archon-style DAG executor.
- General YAML parser.
- Automatic creation of fresh Claude Code sessions.
- Automatic `/compact` invocation.
- Replacing `.claude/local/state.md` workflow tracking.
- Model/effort routing.

## Risks and Open Questions

- **PreToolUse for Edit/Write:** confirm Claude Code sends enough path/action data to block source edits reliably. If not, use PostToolUse as a backstop that fails loudly after a forbidden write, but PreToolUse is preferred.
- **Approving compact mode:** hooks cannot prove `/compact` occurred unless SessionStart compact subtype writes a marker. This can be a follow-up; first PR can require explicit user approval after compaction.
- **JSON manipulation in Bash:** robust enough for constrained schema, but grows painful if we expand too far. This is a reason to keep v1 narrow.
- **False blocks:** gate must allow reading, status checks, and `.claude/local/**` state updates so agents can recover without user hand-editing.
