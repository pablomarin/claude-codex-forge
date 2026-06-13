# Testing

This always-loaded file is an index of non-negotiable testing invariants. Load detailed E2E doctrine only when needed from `docs/reference/testing-e2e.md`.

## Core invariants

1. NEVER skip tests or commit with failing tests.
2. Use TDD for implementation: failing test → smallest fix → refactor.
3. Test user-observable behavior and public contracts before implementation details.
4. Test both success and error cases.
5. Prefer factories/fixtures over hard-coded data.
6. Never mock your own code; mock external APIs, email/SMS, network, and time only.

## Unit and integration tests

Typical structure:

```text
tests/
├── conftest.py
├── unit/
├── integration/
└── e2e/
```

Naming:

- Files: `test_{module}.py`
- Functions: `test_{action}_{scenario}_{expected}`

Use Arrange-Act-Assert in every test:

```python
async def test_create_user_with_valid_data_returns_user(session):
    # Arrange
    repo = UserRepository(session)
    data = UserCreate(email="test@example.com", name="Test")

    # Act
    result = await repo.create(data)

    # Assert
    assert result.id is not None
```

Use `pytest.mark.parametrize` for multiple input cases. Integration tests should use real app seams (database/services) rather than mocking business logic.

## E2E Use Case Design

Before writing E2E use cases in `/new-feature` Phase 3.2b, `/fix-bug` Phase 3.2b, or `/fix-bug` simple-fix Step 0, **Read `docs/reference/testing-e2e.md`**.

E2E tests are user journeys: a specific actor in a specific situation achieving a real product outcome. Each UC MUST include:

1. **Actor** — specific role/situation, not bare `user`.
2. **Scenario** — 1–2 sentences: starting state + trigger + desired outcome; no biography fluff.
3. **Interface** — UI / API / CLI / API+UI, chosen from the feature surface.
4. **Intent** — what the Actor achieves in the Actor's terms.
5. **Setup** — sanctioned setup only; must NOT perform the action under test.
6. **Steps** — at least 2 user-meaningful steps through the declared interface.
7. **Verification** — user-observable outcome, not a bare status/exit/visibility check.
8. **Persistence** — reload, re-request, or re-invoke and confirm state stuck.

`Persistence: N/A` is narrow: allowed only for genuinely stateless outcomes. Any create/update/delete/transition journey needs Persistence. Use `- [x] E2E verified — N/A: <reason>` only for purely internal changes with a specific justification.

### Verification language — surface-specific

- UI: `sees, appears, is shown, can open, the page reads, the toast says, the row is highlighted`.
- CLI: `stdout shows, stderr explains, the next invocation lists/shows/returns, the human-readable line matches`.
- API: `receives, response includes, client can use, follow-up request returns, error body explains`.

### GOOD vs BAD use cases

Full worked examples live in `docs/reference/testing-e2e.md`. Canonical good Actors include:

```text
Actor:         Signed-in customer on the personal todo list
Actor:         API integrator wiring an external storefront to our order service
Actor:         Operator running the CLI on their laptop to bootstrap a new project
```

### Multi-surface coverage

For user-facing changes, read `CLAUDE.md ## E2E Configuration` and perform the surface audit from `docs/reference/testing-e2e.md`.

The plan must include a **Surface coverage decision** for every exposed interface:

- `Covered` — a UC exists for this surface, OR
- `N/A — <substantive justification>` — why users of this interface do not need this feature.

`SURFACE_COVERAGE_WARNING` from `verify-e2e` means UCs cover fewer surfaces than the project exposes without a sufficient pre-justification. Treat it as review/council input before checking the E2E gate.

## Canonical E2E gate vocabulary

There is one gated marker name: `E2E verified`.

- Checklist entry: `- [ ] E2E verified via verify-e2e agent (Phase 5.4)`.
- Checked after passing: `- [x] E2E verified via verify-e2e agent (Phase 5.4)`.
- Checked as N/A: `- [x] E2E verified — N/A: <reason>`.

The hook also requires evidence: a checked non-N/A E2E gate must have a fresh markdown report in `tests/e2e/reports/`.

## ARRANGE vs VERIFY — no cheating

E2E setup may use public APIs, signup/login flows, app CLI, UI flows, or documented seed/bootstrap commands. Never use raw DB writes, internal/undocumented endpoints, source-code shortcuts, or file injection. Verify only through the declared user-facing interface.

## Failure Classification

`verify-e2e` returns `FAIL_INVALID_USE_CASE` for malformed UCs. Reason-code vocabulary must stay in sync with `agents/verify-e2e.md` and `docs/reference/testing-e2e.md`.

**Hard-SHAPE reasons:**

- **`MISSING_ACTOR`**
- **`MISSING_SCENARIO`**
- **`SCENARIO_FLUFF`**
- **`CHEAT_SETUP`**
- **`THIN_VERIFICATION`**
- **`MISSING_PERSISTENCE`**
- **`TOO_SHALLOW`**

**Judgment-call reasons:**

- **`NOT_USER_JOURNEY`**
- **`WRONG_INTERFACE`**

## Verification agents

- Use `verify-app` for unit tests, integration tests, lint, type checks, builds, and migrations.
- Use `verify-e2e` for user-journey verification. The main agent persists its report to `tests/e2e/reports/`.

## Playwright notes

For UI E2E, use stable selectors: roles or `data-testid`; never fragile CSS selectors. Projects may opt into the Playwright framework with `setup.sh --with-playwright`; detailed CI/spec guidance is in `docs/reference/testing-e2e.md`.
