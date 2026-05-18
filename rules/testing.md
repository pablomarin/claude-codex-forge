# Testing

## Structure

```
tests/
├── conftest.py      # Shared fixtures
├── unit/            # Isolated, fast, mock external
├── integration/     # Real database, real services
└── e2e/             # Full system, browser tests
```

## Naming

- Files: `test_{module}.py`
- Functions: `test_{action}_{scenario}_{expected}`

```python
def test_create_user_with_valid_data_returns_user(): ...
def test_create_user_with_duplicate_email_raises_conflict(): ...
```

## Arrange-Act-Assert Pattern

ALWAYS structure tests with clear AAA separation:

```python
async def test_create_user_with_valid_data(session):
    # Arrange
    repo = UserRepository(session)
    data = UserCreate(email="test@example.com", name="Test")

    # Act
    result = await repo.create(data)

    # Assert
    assert result.id is not None
    assert result.email == "test@example.com"
```

## Fixtures

Use factories over hard-coded data:

```python
@pytest.fixture
def make_user():
    def _make(email: str = None, **kwargs) -> User:
        return User(email=email or f"{uuid4()}@test.com", **kwargs)
    return _make

async def test_get_user(session, make_user):
    user = make_user(name="Test")
    session.add(user)
    # ...
```

## Mocking Rules

| Mock                           | Don't Mock                    |
| ------------------------------ | ----------------------------- |
| External APIs (Stripe, OpenAI) | Your own code                 |
| Email/SMS services             | Database in integration tests |
| Network requests               | Business logic                |
| Time (`datetime.now`)          | Repository methods            |

```python
# Mock external services
@patch("app.services.email.send")
async def test_signup_sends_welcome_email(mock_send, client):
    await client.post("/signup", json=data)
    mock_send.assert_called_once()
```

## E2E Tests (Playwright)

Use stable selectors:

```typescript
// CORRECT: data-testid or role
await page.getByTestId("submit-btn").click();
await page.getByRole("button", { name: "Submit" }).click();

// WRONG: fragile CSS selectors
await page.locator(".btn-primary").click();
```

Verify persistence:

```typescript
await page.getByLabel("Name").fill("Test");
await page.getByRole("button", { name: "Save" }).click();
await page.reload();
await expect(page.getByText("Test")).toBeVisible(); // Still there?
```

## E2E Use Case Design

E2E tests are **user use cases** — think like a person using the product, not a developer testing code.

Each use case MUST include:

1. **Intent** — A real user goal in plain language
   Example: "User creates a new project and invites a teammate"
   **Smell test:** If you cannot describe the Intent to a non-developer in one sentence without naming endpoints, code, tables, components, or other internal terms, it is not a user journey — it is an integration test. Rewrite it before continuing.
2. **Steps** — The user's actions through the chosen interface, in order
   - UI: `Navigate to /projects → Click "New Project" → Fill name → Click "Create"`
   - API: `POST /api/v1/projects with {name: "Launch"} → GET /api/v1/projects to list back`
   - CLI: `mycli project add --name "Launch" → mycli project list`
3. **Verification** — Something the **user would see** through the same interface — UI text/elements, API response body/status, or CLI stdout/exit code. Never a database row, internal log, or function return.
   Example: Project appears in list, success toast shows
4. **Persistence** — Reload, re-request, or re-invoke and confirm the state stuck
   Example: Reload /projects → project still visible

### What E2E is NOT

- ❌ Testing a function returns the right value (unit test)
- ❌ Testing an API endpoint returns 200 (integration test — narrow contract check)
- ❌ Testing a component renders correctly (component test)
- ❌ Clicking one button and checking one element (too shallow)
- ❌ Testing the same internal data path through two interfaces just to "cover both" (still one assertion, just duplicated)

### GOOD vs BAD use cases (canonical examples)

These are the patterns to match against. The BAD versions are **valid integration/component tests** — they are simply not E2E use cases.

#### UI use case — fullstack/UI feature

**❌ BAD (component-shaped):**

```
Intent:        Verify TodoForm renders a submit button
Interface:     UI
Setup:         N/A
Steps:         Navigate to /todos
Verification:  Submit button is visible
Persistence:   N/A
```

Why bad: the Intent names a component. No real user goal. No persistence. Verification checks one DOM element, not a user-visible outcome of an action.

**✅ GOOD (user-journey):**

```
Intent:        Signed-in user creates a todo and confirms it survives a page reload
Interface:     UI
Setup:         Register + login via the public signup flow (POST /api/v1/users, then UI login)
Steps:         Navigate to /todos → Click "New Todo" → Type "Buy milk" → Click "Create"
Verification:  "Buy milk" appears in the list AND a "Created" toast is visible
Persistence:   Reload /todos → "Buy milk" is still in the list
```

#### API use case — public/product API feature

**❌ BAD (contract-shaped):**

```
Intent:        POST /api/v1/orders returns 201 with valid body
Interface:     API
Setup:         N/A
Steps:         curl POST /api/v1/orders with valid JSON
Verification:  Response status is 201
Persistence:   N/A
```

Why bad: tests a single endpoint contract. Doesn't span the journey of a user achieving something through the API. No persistence check.

**✅ GOOD (user-journey):**

```
Intent:        Authenticated customer places an order and finds it in their order history
Interface:     API
Setup:         POST /api/v1/users (register) → POST /api/v1/sessions (login, capture token)
Steps:         POST /api/v1/orders {items:[…]} with auth → GET /api/v1/users/me/orders
Verification:  POST returns 201 + Location header; GET response contains the new order with the id from the Location header
Persistence:   Re-request GET /api/v1/users/me/orders → order still listed
```

#### CLI use case — CLI feature

**❌ BAD (flag-shaped):**

```
Intent:        Verify `mycli add --name` accepts a string argument
Interface:     CLI
Setup:         N/A
Steps:         Run `mycli add --name foo`
Verification:  Exit code is 0
Persistence:   N/A
```

Why bad: tests argument parsing. No user goal — operators don't run `add` just to see exit code 0; they run it to add something they later use.

**✅ GOOD (user-journey):**

```
Intent:        Operator adds a project, then lists it back in a separate invocation
Interface:     CLI
Setup:         Run `mycli init` to create the local config
Steps:         Run `mycli project add --name "launch-2026"` → run `mycli project list`
Verification:  `add` stdout matches `Created project launch-2026` and exit 0; `list` stdout contains `launch-2026`
Persistence:   Exit the shell, open a new shell, run `mycli project list` → `launch-2026` is still listed
```

### When E2E is required

Any change to **user-facing behavior**: API changes, UI changes, new pages, flow changes, form changes, navigation changes, permission changes — anything a user would notice.

### When E2E can be skipped (N/A)

Purely internal changes with zero user-facing impact: migrations, internal scripts, CI config, dev tooling, behavior-preserving refactors.
Must write justification: `- [x] E2E verified — N/A: [reason]`

## Canonical E2E gate vocabulary

There is **one** gated marker name. The Stop hook (`check-workflow-gates.sh`/`.ps1`) blocks `git commit` / `git push` / `gh pr create` when the marker is `- [ ]` (unchecked) in the active Workflow checklist.

| Gate element              | Canonical form                                                                                             |
| ------------------------- | ---------------------------------------------------------------------------------------------------------- |
| **Marker stem**           | `E2E verified` — this exact two-word phrase appears in every gated context                                 |
| **Checklist entry**       | `- [ ] E2E verified via verify-e2e agent (Phase 5.4)` (from `new-feature.md` / `fix-bug.md`)               |
| **Checked after passing** | `- [x] E2E verified via verify-e2e agent (Phase 5.4)`                                                      |
| **Checked as N/A**        | `- [x] E2E verified — N/A: <reason>` (reason must be specific; "not needed" does not satisfy human review) |
| **Hook regex key**        | `E2E verified` (literal substring match, present in all three checked-state variants)                      |

Changing any of these strings in one place requires updating the hook + tests in the same PR. The `test-contracts.sh` cross-file contract asserts this.

### Evidence-based gate

The `check-workflow-gates.sh`/`.ps1` hook does TWO checks on the `E2E verified` marker:

1. **Checklist check** — `- [ ] E2E verified ...` in an active workflow blocks the commit/push/PR.
2. **Evidence check** — `- [x] E2E verified ...` **without** `N/A:` requires a real report file in `tests/e2e/reports/` whose mtime is later than the branch-off commit. If no such file exists, the hook blocks with a specific "checkbox is typed but no report was actually produced" error.

Why: a bad-faith actor can type `[x]` without running the verify-e2e agent. The evidence check binds the checkbox claim to a filesystem artifact — the agent's report, persisted via Phase 5.4 Step 3 (`mkdir -p tests/e2e/reports && Write`).

The N/A escape (`- [x] E2E verified — N/A: <reason>`) skips the evidence check. Human reviewers catch lazy N/A justifications at PR review time.

Intentionally NOT covered by evidence check (gracefully skipped):

- User is on `main` (no feature branch) → no merge-base → skip
- Repo has neither `main` nor `master` → skip
- Repo has no git history that reaches a branch point → skip

These are degraded environments, not policy violations. The checklist check still fires.

## E2E Interface Selection — Feature-Surface-Driven

**The interface(s) a use case exercises must match the surface the user touches FOR THIS FEATURE — not the project's defaults.**

Two-step selection:

1. **CLAUDE.md `## E2E Configuration` tells you which interfaces the project EXPOSES.** This is the capability envelope — the floor of what's possible to test:

| Project Type  | Interfaces Available | Tools                 | Playwright Required?       |
| ------------- | -------------------- | --------------------- | -------------------------- |
| **fullstack** | API + UI             | HTTP + Playwright MCP | Yes (when UI UCs exist)    |
| **api**       | API only             | HTTP (curl/httpie)    | No                         |
| **cli**       | CLI only             | Subprocess + stdout   | No                         |
| **hybrid**    | Mixed per feature    | Mixed                 | Only if UI use cases exist |

2. **The feature tells you which interface(s) the user actually touches.** Pick from the envelope based on the feature surface:

| Feature shape                                             | Interface(s) for this feature's UCs                                            |
| --------------------------------------------------------- | ------------------------------------------------------------------------------ |
| New UI page, form, flow, or visual element                | **UI**                                                                         |
| New **public/product** REST/GraphQL endpoint              | **API**                                                                        |
| New CLI command, flag, or output                          | **CLI**                                                                        |
| Public flow that crosses UI + API (e.g., signup, billing) | **API + UI** (API-first ordering — contract before presentation)               |
| Same feature exposed in multiple surfaces                 | One UC per surface a user can actually use                                     |
| **Internal/private endpoint backing a UI page**           | **UI** only — endpoint contract coverage belongs in integration tests, not E2E |
| Purely internal (no user surface — migration, refactor)   | E2E: N/A with justification                                                    |

**Key principle (Codex review of v5.31):** A new REST endpoint is only an API E2E target if it is part of the **public product API** — something an external integrator or operator would call. An endpoint that exists only to back a UI page is an internal seam; cover its contract in integration tests, and write the E2E use case at the UI surface where the user actually interacts.

**Fullstack ordering:** when a feature requires both API and UI use cases, run API first, UI second. API failure means the contract/state layer is broken (stop immediately — UI will fail for the wrong reason). API pass + UI failure means the presentation layer is broken (different diagnosis, both reports needed).

## ARRANGE vs VERIFY — The "No Cheating" Boundary

E2E tests simulate a real user who has no access to internal systems. VERIFY must stay strictly within user-facing interfaces — no exceptions. ARRANGE has slightly wider latitude (setup through any user-accessible interface — see the allowed/forbidden lists below) but **also** forbids raw DB writes, internal endpoints, and file-injection. Setup gets flexibility about **which** sanctioned interface to use; it does not get permission to sidestep them. If the sanctioned path is broken, fix it — do not route around it (see `rules/critical-rules.md` **NO BUGS LEFT BEHIND**).

**ARRANGE (test setup) — allowed methods:**

| Method                             | Example                                         |
| ---------------------------------- | ----------------------------------------------- |
| Public API endpoints               | `POST /api/v1/users` to create a test account   |
| Public signup/login flows          | Register + authenticate via documented flows    |
| CLI commands                       | `myapp create-account --email test@example.com` |
| UI flows                           | Fill signup form and submit via Playwright      |
| Documented seed/bootstrap commands | `make seed-dev`, `manage.py loaddata`           |

**ARRANGE — forbidden:**

- Direct database queries
- Internal/undocumented endpoints
- Modifying files on disk to inject state
- Reading source code to find shortcuts

**VERIFY (assertions) — no cheating, period:**

- API: check response status, body, headers
- UI: check what's visible on screen (use `data-testid` and roles, not CSS selectors)
- CLI: check stdout/stderr and exit codes
- Persistence: reload/re-request through the same interface

**The principle:** _Setup through any user-accessible interface. Verify through the interface being tested._

## Use Case Lifecycle

```
Phase 3.2b: Design use cases          → plan file (draft)
Phase 5.4:  Execute feature use cases → verify-e2e agent, markdown report
Phase 5.4b: Execute regression suite  → verify-e2e agent, tests/e2e/use-cases/
Phase 6.2b: Graduate passing cases    → tests/e2e/use-cases/[feature].md
```

Use cases live in the plan file during development, then graduate to `tests/e2e/use-cases/` as permanent regression tests after they pass.

**Simple-fix exception** (`/fix-bug` path with 1-2 file fixes that skip Phase 3): use cases are staged at `docs/plans/<bug-name>-use-cases.md` in Phase 5.4 Step 0, then graduated in Phase 6.2b like complex fixes. Staging prevents 5.4b regression mode from picking up unverified use cases.

## Failure Classification

The verify-e2e agent produces a structured markdown report with five per-UC classification types:

| Classification            | Meaning                                                                                                                                            | Blocks ship?                  |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| **PASS**                  | Works as specified                                                                                                                                 | No                            |
| **FAIL_BUG**              | Real product defect — user would hit this                                                                                                          | **Yes**                       |
| **FAIL_STALE**            | Use case references changed interface (endpoint/page/selector renamed) — needs update                                                              | No (maintenance flag)         |
| **FAIL_INFRA**            | Server down, timeout, flaky selector                                                                                                               | Retry once, then warn         |
| **FAIL_INVALID_USE_CASE** | Use case fails authoring discipline — `NOT_USER_JOURNEY` or `WRONG_INTERFACE`. Bounces back to the main agent to rewrite the UC before re-running. | **Yes** (test-design failure) |

`FAIL_INVALID_USE_CASE` reasons:

- **`NOT_USER_JOURNEY`** — the Intent reads as an integration/contract/component test (names code, endpoints as the goal, or has no Persistence step). The smell test in `## E2E Use Case Design` failed.
- **`WRONG_INTERFACE`** — the declared Interface does not match the surface the user touches for this feature (e.g., API UC for a feature whose only user surface is a UI page; UI UC for a CLI-only feature).

The verify-e2e agent reports `FAIL_INVALID_USE_CASE` per offending UC and maps these to top-level `VERDICT: FAIL`. The caller (main agent in `/new-feature` Phase 5.4 or `/fix-bug` Phase 5.4) rewrites the UC in the plan file (or `docs/plans/<bug-name>-use-cases.md` staging file for simple fixes) and re-invokes verify-e2e. The Phase 5.4 checklist box stays unchecked until verify-e2e returns PASS.

## Playwright Framework Bridge (Optional)

Projects can opt into the Playwright test framework to add CI-enforced regression coverage on top of the markdown use cases + verify-e2e agent.

### When to use

Enable if:

- External contributors will open PRs (no Claude session runs on their PRs)
- You want nightly regression or pre-deploy smoke
- You want zero-LLM-cost regression runs (after the initial spec generation)

Skip if:

- Solo project with every PR opened by someone who runs `/new-feature`
- Project has no web UI (API-only, CLI, Python-only — framework doesn't apply)
- You're comfortable with agent-only regression (session-bound)

### How to enable

```bash
./setup.sh -p "My App" -t fullstack --with-playwright
```

This installs, into the repo root (flat layouts) or into the first detected frontend subdirectory (`frontend/`, `apps/web/`, `web/`, `client/`) for monorepo layouts — use `--playwright-dir <path>` to override:

- `playwright.config.ts`
- `tests/e2e/fixtures/auth.ts` (auth bypass pattern)
- `tests/e2e/specs/` directory for generated spec files
- `docs/ci-templates/e2e.yml` — GitHub Actions workflow as a reference (not auto-activated); `working-directory` is stamped to match the scaffold location

Then, from wherever Playwright was scaffolded (`cd frontend` first on monorepos, nothing for flat layouts):

```bash
pnpm add -D @playwright/test
pnpm exec playwright install
# Optional: activate CI
cp docs/ci-templates/e2e.yml .github/workflows/e2e.yml
```

### The two-layer model

| Layer                                              | Source of truth                    | When it runs                                                    | Cost                  |
| -------------------------------------------------- | ---------------------------------- | --------------------------------------------------------------- | --------------------- |
| **Markdown use case** (`tests/e2e/use-cases/*.md`) | Intent — what a user wants         | Phase 5.4/5.4b during `/new-feature` or `/fix-bug`              | LLM tokens per run    |
| **Spec file** (`tests/e2e/specs/*.spec.ts`)        | Deterministic replay of the intent | CI on every PR, nightly cron, local `pnpm exec playwright test` | Free after generation |

The verify-e2e agent explores the UI once during Phase 5.4 (authoring) and records observed selectors in its report. Then in Phase 6.2c the main implementation agent reads that report and writes a stable spec file using the recorded selectors. The verify-e2e agent stays read-only throughout; only the main agent has Write/Edit tools.

### Auth fixture pattern

E2E tests should authenticate ONCE per run, not per test. The auth fixture stores browser state after login and reuses it across specs. Configure via env vars:

- `TEST_API_KEY` (preferred — fastest) OR
- `TEST_USER_EMAIL` + `TEST_USER_PASSWORD` (fallback)

See `tests/e2e/fixtures/auth.ts` for the template.

### CI integration

The ships-as-reference CI template runs:

- **On PR:** smoke-tagged specs only (~2 min)
- **Nightly:** full suite
- **Manual:** workflow_dispatch for ad-hoc runs

Uploads HTML report + traces as artifacts on failure.

## Rules

1. ALWAYS follow Arrange-Act-Assert pattern
2. ALWAYS test both success and error cases
3. ALWAYS use factories/fixtures over hard-coded data
4. ALWAYS design E2E as user use cases (Intent → Steps → Verification → Persistence)
5. NEVER mock your own code in unit tests
6. NEVER use fragile CSS selectors in E2E — use `data-testid` or roles
7. NEVER commit with failing tests
8. PREFER `pytest.mark.parametrize` for testing multiple inputs
