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

## Revised design

### 1. Keep `rules/testing.md` as a small always-loaded index

Target: roughly 40–80 lines, ideally under ~1k rough tokens.

Keep only universal invariants and routing instructions:

- Never skip tests.
- Use TDD for implementation.
- Prefer user-observable behavior over implementation-detail assertions.
- Keep unit/integration structure and AAA naming guidance very short.
- Use `verify-app` for unit/integration/lint/type verification.
- Use `verify-e2e` for user-journey verification.
- E2E use cases require: Actor, Scenario, Interface, Intent, Setup, Steps, Verification, Persistence.
- Before designing E2E use cases, read `docs/reference/testing-e2e.md`.
- If touching API/UI/CLI user surfaces, perform the surface coverage audit from `docs/reference/testing-e2e.md`.

### 2. Move detailed E2E doctrine to one on-demand reference first

Start with one consolidated file:

```text
docs/reference/testing-e2e.md
```

Move the long E2E sections from `rules/testing.md` into that file:

- E2E Use Case Design
- Verification language — surface-specific
- What E2E is NOT
- GOOD vs BAD examples
- Multi-surface coverage
- Surface coverage decision examples
- Failure Classification / canonical gate vocabulary, if currently present

Why one file first:

- Lower implementation risk.
- Fewer installer copy calls.
- Fewer command references to keep in sync.
- Easier startup ablation: `rules/testing.md` shrinks while capability moves to a single explicit reference.

Later, if the one file becomes hard to navigate, split it into smaller references such as:

```text
docs/reference/testing-e2e-use-cases.md
docs/reference/testing-surface-coverage.md
docs/reference/testing-verification-language.md
docs/reference/testing-failure-classification.md
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
- `docs/reference/testing-e2e.md`
```

Then require the plan file to include a visible marker:

```markdown
Testing references loaded:
- `docs/reference/testing-e2e.md`
```

This marker lets reviewers and tests verify that the agent loaded the detailed context when needed.

Also update every stale command reference that currently says to use examples or detailed checklists from `rules/testing.md`; those should point to `docs/reference/testing-e2e.md` after the split.

For `/fix-bug`, update both paths:

- Complex-fix Phase 3.2b plan-file path.
- Simple-fix Step 0 staging-file path (`docs/plans/<bug-name>-use-cases.md`).

### 4. Keep enforcement inside `verify-e2e`

`agents/verify-e2e.md` can keep detailed validation logic because it is loaded only when invoked.

Do not weaken:

- required use-case fields
- surface coverage warning
- `FAIL_INVALID_USE_CASE` classifications
- ARRANGE vs VERIFY no-cheating boundary
- persistence requirements
- failure classification rules

Update stale references inside `agents/verify-e2e.md`:

- If it points to `rules/testing.md` for detailed E2E examples or allowed-method lists, point to `docs/reference/testing-e2e.md` instead.
- Keep any rules needed for agent self-sufficiency directly in `verify-e2e.md`; do not rely on the main agent having read the reference.

### 5. Install the new reference downstream

Because downstream projects are created by `setup.sh` / `setup.ps1`, adding `docs/reference/testing-e2e.md` in this repo is not enough.

Update both installers:

```text
setup.sh
setup.ps1
```

Required installer behavior:

- Ensure `docs/reference` exists.
- Copy `docs/reference/testing-e2e.md` to downstream projects.
- Preserve normal copy semantics: skip existing user-edited files unless force/upgrade behavior already says otherwise.

Update setup tests if they assert copied docs or expected file sets.

## Implementation sequence

### Step 1 — Create the reference file

1. Create `docs/reference/testing-e2e.md`.
2. Move detailed E2E doctrine from `rules/testing.md` into it.
3. Keep wording and reason-code vocabulary byte-stable where possible to reduce accidental behavior drift.

### Step 2 — Slim `rules/testing.md`

Rewrite `rules/testing.md` as an index:

- Universal test invariants.
- Short unit/integration guidance.
- E2E field list.
- Explicit instruction to read `docs/reference/testing-e2e.md` before E2E use-case design.
- Pointers to `verify-app` and `verify-e2e`.

### Step 3 — Update workflow commands

Update `commands/new-feature.md`:

- Phase 3.2b requires reading `docs/reference/testing-e2e.md` before writing UCs.
- Phase 3.2b requires the `Testing references loaded:` marker in the plan.
- Replace stale detailed-example references from `rules/testing.md` to `docs/reference/testing-e2e.md`.

Update `commands/fix-bug.md`:

- Same changes in complex-fix Phase 3.2b.
- Same changes in simple-fix Step 0 staging-file path.

### Step 4 — Update `verify-e2e.md`

- Replace stale references to detailed `rules/testing.md` sections with `docs/reference/testing-e2e.md`.
- Keep strict validation text and reason-code vocabulary intact.

### Step 5 — Update installers

- Add `docs/reference` mkdir/copy in `setup.sh`.
- Mirror in `setup.ps1`.
- Update any setup tests that should assert the reference is installed.

### Step 6 — Add static contract tests

Add or extend `tests/template/test-contracts.sh` assertions:

- `rules/testing.md` remains below a size threshold, e.g. `< 150 lines` or `< 8k chars`.
- `docs/reference/testing-e2e.md` exists.
- `commands/new-feature.md` mentions `docs/reference/testing-e2e.md`.
- `commands/fix-bug.md` mentions `docs/reference/testing-e2e.md`.
- Both commands require `Testing references loaded:`.
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
- `setup.sh` and `setup.ps1` both install `docs/reference/testing-e2e.md`.

## Verification plan

### A. Static verification

Run:

```bash
python3 -m py_compile scripts/context-metrics.py
bash tests/template/test-contracts.sh
bash tests/template/test-lint.sh
bash tests/template/test-setup.sh
```

If local Windows PowerShell is blocked by execution policy, run PowerShell parity checks in an environment where `pwsh` is available or document the skip.

### B. Token verification

1. Reinstall Forge into `forge-empty` from this checkout.
2. Start a fresh Claude session in `forge-empty`.
3. Send only `hi`.
4. Measure first assistant usage from JSONL:

```bash
scripts/context-metrics.py --project-root /home/aescala82/projects/forge-empty --startup
```

Compare against baseline:

```text
minimal Forge:                  56.0k
minimal Forge + caveman disabled: 54.6k
expected after testing index:   about 45–47k, depending final index size
```

Success: startup context drops by roughly 8–10k without removing testing capability.

### C. Artifact verification

Run a throwaway `/new-feature` or simulated Phase 3.2b that requires user-facing E2E use cases.

Inspect generated plan file. It must contain:

```markdown
Testing references loaded:
- `docs/reference/testing-e2e.md`
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

### D. Behavior verification

Use a user-facing throwaway feature and run through E2E design + verification.

Expected:

- Main agent writes valid use cases.
- `verify-e2e` returns PASS for valid use cases when product behavior works.
- If product behavior fails, `verify-e2e` reports `FAIL_BUG`, not malformed test-design noise.

### E. Negative test

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

## Success criteria

- Startup context reduced by roughly 8–10k tokens versus current minimal Forge.
- `rules/testing.md` is a compact always-loaded index.
- Detailed testing references are loaded when E2E use cases are designed.
- Plan files carry a visible `Testing references loaded:` marker.
- Valid E2E use cases still pass `verify-e2e`.
- Invalid E2E use cases are still rejected with `FAIL_INVALID_USE_CASE`.
- New reference file is installed into downstream projects by both Unix and Windows installers.
- No review gates, ship gates, or evidence contracts are weakened.

## Guardrails

- Do not remove safety-critical testing rules without an on-demand replacement.
- Do not rely only on hidden hook context for testing rules.
- Do not place detailed references in autoloaded `.claude/rules/`.
- Keep command instructions explicit and auditable.
- Keep `verify-e2e` strict; it is the backstop if the main agent misses details.
- Maintain Bash + PowerShell installer parity.
- Do not start `workflow.md` progressive disclosure until this `testing.md` pattern is measured and proven.

## Progress log

- [x] Wrote initial progressive-disclosure plan.
- [x] Revised plan to use one consolidated `docs/reference/testing-e2e.md` first.
- [ ] Split `rules/testing.md` into index + reference.
  - [x] Created consolidated reference: `docs/reference/testing-e2e.md`.
  - [x] Slimmed `rules/testing.md` into compact index.
- [x] Update `/new-feature` and `/fix-bug` Phase 3.2b instructions.
- [x] Add `Testing references loaded:` marker requirement.
- [x] Update `verify-e2e.md` stale references.
- [x] Update `setup.sh` and `setup.ps1` to install the new reference.
- [x] Add/extend template contract tests.
- [ ] Reinstall into `forge-empty` and measure startup context.
- [ ] Run positive behavior test.
- [ ] Run negative malformed-UC test.
- [ ] Review results and decide whether to apply same pattern to `workflow.md`.
