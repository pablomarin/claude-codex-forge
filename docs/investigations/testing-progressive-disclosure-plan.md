# Testing Rule Progressive Disclosure Plan

## Purpose

Reduce Forge startup context by converting `rules/testing.md` from a large always-loaded rule file into a small index, while preserving E2E quality gates and test-design discipline.

Related investigation:

```text
docs/investigations/startup-context-overhead.md
```

## Why this matters

Measured in `/home/aescala82/projects/forge-empty`:

```text
minimal Forge + caveman disabled:                    54,599 context tokens
minimal Forge + caveman disabled + testing.md moved: 43,556 context tokens
savings from removing testing.md:                     11,043 context tokens
```

`rules/testing.md` is the biggest proven Forge-owned startup lever so far.

## Proposed design

### 1. Keep `rules/testing.md` as a small always-loaded index

Target: roughly 40–80 lines, ideally under ~1k rough tokens.

Keep only universal invariants and routing instructions:

- Never skip tests.
- Use TDD for implementation.
- Prefer user-observable behavior over implementation-detail assertions.
- Use `verify-app` for unit/integration/lint/type verification.
- Use `verify-e2e` for user-journey verification.
- Before designing E2E use cases, read detailed testing references.
- If touching API/UI/CLI user surfaces, perform surface coverage audit.

### 2. Move detailed E2E doctrine to on-demand references

Candidate files:

```text
docs/reference/testing-e2e-use-cases.md
docs/reference/testing-surface-coverage.md
docs/reference/testing-verification-language.md
docs/reference/testing-failure-classification.md
```

Or a smaller number of consolidated references if that is easier to maintain:

```text
docs/reference/testing-e2e.md
docs/reference/testing-regression-and-playwright.md
```

Important: do **not** place detailed reference files under `.claude/rules/` if Claude Code autoloads that directory.

### 3. Command phases explicitly require reading the details

Update both:

```text
commands/new-feature.md
commands/fix-bug.md
```

At Phase 3.2b / E2E use case design, require:

```markdown
Before writing E2E use cases, Read:
- `docs/reference/testing-e2e-use-cases.md`
- `docs/reference/testing-surface-coverage.md`
- `docs/reference/testing-verification-language.md`
```

Then require the plan file to include a visible marker:

```markdown
Testing references loaded:
- `docs/reference/testing-e2e-use-cases.md`
- `docs/reference/testing-surface-coverage.md`
- `docs/reference/testing-verification-language.md`
```

This marker lets reviewers and tests verify that the agent loaded the detailed context when needed.

### 4. Keep enforcement inside `verify-e2e`

`agents/verify-e2e.md` can keep detailed validation logic because it is loaded only when invoked.

Do not weaken:

- required use-case fields
- surface coverage warning
- `FAIL_INVALID_USE_CASE` classifications
- ARRANGE vs VERIFY no-cheating boundary
- persistence requirements
- failure classification rules

## Verification plan

### A. Token verification

1. Reinstall Forge into `forge-empty` from this checkout.
2. Start fresh Claude session in `forge-empty`.
3. Send only `hi`.
4. Measure first assistant usage from JSONL.

Compare against baseline:

```text
minimal Forge: 56.0k
minimal Forge + caveman disabled: 54.6k
expected after testing index: about 45–47k, depending final index size
```

Success: startup context drops by roughly 8–10k without removing testing capability.

### B. Artifact verification

Run a throwaway `/new-feature` or simulated Phase 3.2b that requires user-facing E2E use cases.

Inspect generated plan file. It must contain:

```markdown
Testing references loaded:
- ...
```

And E2E use cases must include:

- Actor
- Scenario
- Interface
- Intent
- Setup
- Steps
- Verification
- Persistence
- Surface coverage decision

Success: detailed references are visibly acknowledged in the durable artifact.

### C. Behavior verification

Use a user-facing throwaway feature and run through E2E design + verification.

Expected:

- Main agent writes valid use cases.
- `verify-e2e` returns PASS for valid use cases when product behavior works.
- If product behavior fails, `verify-e2e` reports `FAIL_BUG`, not malformed test-design noise.

### D. Negative test

Deliberately create a malformed use case in a throwaway plan/report path:

```markdown
Actor: user
Verification: status code 200
Persistence: N/A
```

Run `verify-e2e` against it.

Expected:

```text
VERDICT: FAIL
FAIL_INVALID_USE_CASE
Reason includes one or more of:
- MISSING_ACTOR
- THIN_VERIFICATION
- MISSING_PERSISTENCE
```

Success: detailed validation still fires even though startup `testing.md` is slim.

### E. Template contract tests

Add or extend template tests, likely in:

```text
tests/template/test-contracts.sh
```

Suggested assertions:

- `rules/testing.md` remains below a size threshold, e.g. `< 150 lines` or `< 8k chars`.
- Detailed testing reference file(s) exist.
- `commands/new-feature.md` mentions the required testing reference reads.
- `commands/fix-bug.md` mentions the required testing reference reads.
- Commands require a `Testing references loaded:` marker in the plan file.
- `agents/verify-e2e.md` still contains key hard-gate reason codes:
  - `MISSING_ACTOR`
  - `MISSING_SCENARIO`
  - `SCENARIO_FLUFF`
  - `CHEAT_SETUP`
  - `THIN_VERIFICATION`
  - `MISSING_PERSISTENCE`
  - `TOO_SHALLOW`
  - `NOT_USER_JOURNEY`
  - `WRONG_INTERFACE`
  - `SURFACE_COVERAGE_WARNING`

## Success criteria

- Startup context reduced by roughly 8–10k tokens versus current minimal Forge.
- Detailed testing references are loaded when E2E use cases are designed.
- Plan files carry a visible `Testing references loaded:` marker.
- Valid E2E use cases still pass `verify-e2e`.
- Invalid E2E use cases are still rejected with `FAIL_INVALID_USE_CASE`.
- No review gates, ship gates, or evidence contracts are weakened.

## Guardrails

- Do not remove safety-critical testing rules without an on-demand replacement.
- Do not rely only on hidden hook context for testing rules.
- Do not place detailed references in autoloaded `.claude/rules/`.
- Keep command instructions explicit and auditable.
- Keep `verify-e2e` strict; it is the backstop if the main agent misses details.

## Progress log

- [x] Wrote progressive-disclosure plan.
- [ ] Split `rules/testing.md` into index + references.
- [ ] Update `/new-feature` and `/fix-bug` Phase 3.2b instructions.
- [ ] Add `Testing references loaded:` marker requirement.
- [ ] Add/extend template contract tests.
- [ ] Reinstall into `forge-empty` and measure startup context.
- [ ] Run positive behavior test.
- [ ] Run negative malformed-UC test.
- [ ] Review results and decide whether to apply same pattern to `workflow.md`.
