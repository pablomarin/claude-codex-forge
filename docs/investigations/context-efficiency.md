# Context Efficiency Investigation

## Purpose

Reduce main-thread context growth in Forge workflows without weakening quality gates, losing design rationale, or removing Claude × Codex adversarial review.

## Core tension

- **Context rot:** Long sessions accumulate noisy brainstorming, failed attempts, tool output, and review churn. Quality can degrade before the model reaches its maximum context window.
- **Lost implicit why:** Naive context clearing or phase handoff can lose rationale and unstated decisions embedded in prior actions.

Target: keep active working context lean while making durable handoff artifacts rich enough to preserve the important “why.”

## Findings from repo investigation

### Confirmed good patterns

- `/codex` runs out-of-process through `hooks/lib/codex-pty.sh` / `.ps1`.
- Codex clean output is read from `/tmp/codex_response.txt`; full transcript is redirected to `/tmp/codex_response_full.txt` and intentionally kept out of Claude context unless Codex fails.
- Plan review and code review gates are mandatory in `commands/new-feature.md`, `commands/fix-bug.md`, and `rules/workflow.md`.
- `verify-app` and `verify-e2e` are mandatory subagents for verification, keeping test output out of the main thread.
- `hooks/lib/review-breaker.sh` / `.ps1` caps post-certification code-review churn.
- Durable artifacts already exist: PRDs, plans, ADRs, `.claude/local/state.md`, Developer Briefing, E2E use cases/reports.

### Corrections / nuance

- `.claude/local/state.md` is not fully re-injected every turn. Hooks inject short workflow/evidence context; the agent is instructed to read state explicitly.
- Council is gated for full escalation, but `new-feature.md` Phase 3.1c always invokes `/council` in Contrarian Gate auto-trigger mode.
- Execution is partly context-isolated: implementation subagents do the work, but the orchestrator still manages dispatch, reviews diffs, and handles review cycles.
- There is already an optional compaction seam before Phase 4; this is a low-risk place to start.

## Suspected bloat sources

- Main-thread PRD discussion and requirements refinement.
- Brainstorming + approach comparison + contrarian gate.
- Plan writing and Developer Briefing construction.
- Claude-side plan review reading every planned file inline.
- Code-review fix cycles and PR body generation.
- Stop-hook `build-evidence` output during non-`/goal` sessions may be steady low-value noise.

## Measurement plan

Use Claude Code transcript JSONL files under:

```text
~/.claude/projects/<project-key>/*.jsonl
```

The helper script is:

```bash
scripts/context-metrics.py --project-root .
```

Useful variants:

```bash
# Analyze the newest transcript for this repo
scripts/context-metrics.py --project-root .

# Analyze every transcript for this repo
scripts/context-metrics.py --project-root . --all-sessions

# Emit machine-readable output
scripts/context-metrics.py --project-root . --json

# Analyze a specific transcript
scripts/context-metrics.py --transcript ~/.claude/projects/<project-key>/<session>.jsonl
```

For each assistant turn, compute:

```text
context_tokens = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
```

Track:

- Peak main-thread context tokens.
- p95 main-thread context tokens.
- Total main-thread output tokens.
- Phase at peak, when inferable from hook output.
- Main thread vs subagent sidechain split via `isSidechain`.
- Largest hook/tool outputs.

Implementation note: Claude Code can split one API response across several assistant JSONL rows that share identical usage. The script counts identical usage rows once per transcript file to avoid inflating totals.

## Model and effort budgeting notes

This is a separate lever from context trimming.

- **Model switching alone does not reduce context rot** if the same long transcript is passed forward. It mainly changes cost, latency, and model behavior.
- **Model switching plus fresh artifact boundaries can reduce context rot** when the downstream model starts from durable artifacts instead of the full prior conversation.
- **Lower reasoning/effort can save hidden thinking tokens** even when prompt context is unchanged. This is useful for implementation and mechanical verification work that follows an approved plan.

Suggested split:

| Phase / task | Candidate model / effort | Rationale |
| --- | --- | --- |
| PRD ambiguity, architecture forks | Opus / high | Judgment-heavy; preserves product and technical “why.” |
| Approach comparison + contrarian synthesis | Opus / high | Wrong strategic choice is expensive. |
| Plan review gate | High-effort Claude + high-effort Codex | High-leverage quality gate; keep adversarial review strong. |
| Implementation from approved plan | Sonnet / low-medium | Mostly executing a documented contract; escalate only on ambiguity. |
| Mechanical file edits | Lower effort | No deep reasoning needed when file/task contract is clear. |
| Verification agents | Low-medium | Mostly deterministic command execution and verdict summarization. |
| E2E exploratory verification | Medium | Needs some judgment about user-observable behavior. |
| Code review gate | High-effort Codex + PR Review Toolkit | Independent scrutiny remains a core quality lever. |
| PR body / Developer Demo | Medium, or high for complex architecture | Evidence-grounded synthesis; can be cheaper when facts are durable. |

Context passing model:

1. Planning model writes durable artifacts: PRD, research brief, plan, Approach Comparison, Contrarian Verdict, Developer Briefing, and an Implementation Handoff / Decision Ledger.
2. Implementation model starts fresh from selected artifacts and relevant files, not the full planning transcript.
3. Implementation returns concise diff/evidence summaries, not raw logs.
4. Review models remain independent and high-effort at mandatory gates.

Minimum handoff shape to preserve “why”:

```markdown
## Implementation Handoff

### Outcome
What to build.

### Decision Ledger
- Chose X because...
- Rejected Y because...
- Risk accepted: ...

### Non-goals
What not to change.

### Invariants
Must remain true.

### Task Contract
Task IDs, dependencies, concrete writes.

### Review Expectations
What reviewers should verify.
```

Policy direction:

- High effort is reserved for irreversible or high-leverage judgment: architecture, plan review, code review, auth/security/payment/database boundaries.
- Implementation defaults to lower effort only when an approved plan and concrete task contract exist.
- Escalate model/effort dynamically if implementation discovers ambiguity, plan/code mismatch, repeated test failure, or high-impact surface area.
- Never lower effort to bypass mandatory gates or evidence contracts.

Measurement implication: track context tokens separately from visible output tokens and reasoning/thinking tokens if exposed. If hidden reasoning tokens are not available in transcript JSONL, use provider dashboard cost/latency as a proxy and compare review-finding rates after lower-effort implementation.

## Change tiers

### Tier 0 — Measurement only

- Add a local metrics script/report command for transcript token usage.
- No workflow behavior changes.

### Tier 1 — Cheapest / safest

1. Suppress `build-evidence` Stop output unless `/goal` is active, while preserving exact behavior during active `/goal`.
2. Strengthen the existing post-plan-review / pre-Phase-4 compaction seam.
3. Add durable handoff / decision ledger sections before recommending compaction.
4. Add post-review-loop resolution summaries before final PR work if context is large.

### Tier 1.5 — Model / effort budgeting

- Keep planning and mandatory review gates high-effort.
- Run implementation and mechanical verification at lower effort when operating from an approved plan and explicit task contract.
- Preserve a clear escalation path back to higher-effort models for ambiguity, repeated failures, or high-impact surfaces.
- Compare cost/latency/reasoning-token savings against downstream review findings.

### Tier 2 — Offload Claude-side plan review

Move Phase 3.3a plan review into a dedicated review subagent that writes a durable artifact. Main thread reads only summary, required edits, reviewed file list, and artifact path. Codex remains mandatory.

### Tier 3 — Fresh-session seams for large work

For large, non-sequential features, split PRD/design and implementation using durable artifacts. Keep sequential mode for tightly coupled single-logical-change work.

### Tier 4 — Deeper redesign

Only after measurement: bounded brainstorming artifacts, structured council outputs, PR body generation from durable evidence, and possible workflow command restructuring.

## Guardrails

- Do not weaken mandatory review gates or evidence contracts.
- Keep Claude × Codex cross-model review intact.
- Maintain Bash + PowerShell parity for hook changes.
- Respect sequential mode: tightly coupled features prioritize decision continuity over leanness.
- Durable artifacts must carry rationale, not just decisions.

## Proposed first experiment

1. Add transcript metrics tooling.
2. Install this checkout into a throwaway target repo by invoking this clone's setup script directly, e.g.:

   ```bash
   cd /path/to/throwaway-target
   /home/aescala82/projects/forge-dev/setup.sh -p "Context Metrics Throwaway" -t fullstack
   cat .claude/local/forge-source.env
   ```

   The setup banner and `.claude/local/forge-source.env` must show `FORGE_SOURCE_DIR=/home/aescala82/projects/forge-dev`, not the machine's upstream `~/claude-codex-forge` clone.
3. Run a baseline workflow on a throwaway feature branch.
4. Apply Tier 1.1: suppress `build-evidence` Stop output when `/goal` is inactive.
5. Run a comparable workflow.
6. Compare peak/p95 main-thread context tokens and inspect any quality regressions.

## Progress log

- [x] Initial repository investigation completed.
- [x] Investigation plan written down.
- [x] Tier 0 metrics script created (`scripts/context-metrics.py`).
- [x] Setup provenance added so throwaway targets can verify they were installed from this checkout (`.claude/local/forge-source.env`).
- [ ] Baseline metrics captured.
- [ ] Tier 1.1 implemented with `.sh` / `.ps1` parity.
- [ ] After metrics captured.
- [ ] Results reviewed.
