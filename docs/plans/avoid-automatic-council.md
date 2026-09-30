# Avoid Automatic Council Escalation

## Reproduction

During a normal `/new-feature` plan review, the workflow instruction “Use `/council` for a
consequential fork or a contrarian check” can launch the full council. The executable dispatcher
always runs five advisor starts, five peer-review resumes, and one chairman turn. The council skill
still documents a quick automatic mode that the dispatcher does not implement.

## Root Cause

V6 replaced V5's bounded contrarian gate with broad automatic-council wording while retaining stale
quick-mode documentation. Shared autonomous-goal policy also sends ordinary non-PR doubts to the
council. Together these make routine plan or code-review judgment eligible for an eleven-turn tool.

## Base

- Ref: `origin/main`
- SHA: `bbabfa8e7e75932e498f3b70e4a22c13afcfd78a`

## Minimal Change

1. Contract that normal feature/fix workflows and shared policy forbid routine council dispatch.
2. Outside active native Goal, make council eligible only when the developer explicitly requests it
   or a concrete high-impact architectural fork remains unresolved after the cheapest safe
   falsifying check. During active native Goal, preserve V5's decision path: council may resolve a
   genuine non-destructive product or engineering decision required to continue when the check does
   not produce a deterministic smallest answer. Apply the chairman verdict and continue Goal; all
   human-authority actions still pause for the developer.
3. State that ordinary plan/code-review findings stay in the existing broad-review, one-repair,
   focused-closure loop.
4. Remove the skill and public-doc claims for an automatic quick council; truthfully document the
   full eleven-turn topology.
5. Remove the remaining automatic escalation from soft E2E coverage warnings and routine
   autonomous-goal signals. A signal stays in its owning bounded workflow. During active Goal, only
   a genuine decision needed to continue may add eligibility beyond the explicit-request and
   unresolved-high-impact-fork cases.
6. Do not add a second dispatcher mode, new hook, configuration switch, or heuristic.

## Changed Paths

- `tests/template/test-contracts.sh`
- `commands/new-feature.md`
- `commands/fix-bug.md`
- `rules/workflow.md`
- `skills/council/SKILL.template.md`
- `skills/council/references/peer-review-protocol.md`
- `skills/council/references/output-schema.md`
- `rules/testing.md`
- `rules/critical-rules.md`
- `agents/verify-e2e.md`
- `commands/forge-goal.md`
- `hooks/check-state-updated.sh`
- `hooks/check-state-updated.ps1`
- `docs/explanation/engineering-council.md`
- `docs/explanation/workflow.md`
- `docs/explanation/harness-philosophy.md`
- `docs/explanation/autonomous-goal.md`
- `docs/CHANGELOG.md`

## Acceptance Criteria

- A normal feature or bug-fix plan always proceeds to the single fresh plan reviewer without an
  automatic council.
- Ordinary plan-review and code-review findings remain inside their bounded repair/closure loops.
- Council remains available for explicit requests and genuinely unresolved high-impact architecture.
- During active native Goal, council remains available when a genuine non-destructive product or
  engineering decision is required to continue; apply the chairman verdict and continue Goal, while
  human-authority actions still pause. Ordinary review findings, warnings, and engine/test failures
  are not that trigger by themselves.
- Installed council documentation matches the executable full topology.
- Soft E2E warnings, reviewer findings, stuck warnings, engine/test failures, and ordinary
  implementation uncertainty do not automatically invoke council.
- Focused contract tests, council dispatcher tests, the fast suite, and `git diff --check` pass.

## TDD

1. Add contract assertions and observe them fail against current workflow text.
2. Make the smallest policy/documentation changes that satisfy those assertions.
3. Run focused tests, then the fast aggregate suite.

## User-Journey Coverage

Documentation/workflow-policy change only. No product UI/API/CLI journey changes; deterministic
contract tests are the applicable verification surface.
