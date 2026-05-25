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

E2E tests are **user use cases** — a specific actor in a specific situation achieving a real product outcome. The shape below is what verify-e2e validates in Step 2b. Missing any required field is a hard-fail.

Each use case MUST include:

1. **Actor** — A specific role/situation, NOT the bare word "user".
   Acceptable: `Account admin with billing permissions`, `Visitor`, `Signed-in customer`, `API integrator`, `Operator from the CLI`, `Any signed-in member`.
   Forbidden: `User`, `Users`, `A user` (no role, no situation — disqualified by Step 2b).
2. **Scenario** — 1-2 sentences setting starting state + trigger + desired outcome. No biography fluff (no age, city, hobbies, personality). Must be traceable to a PRD persona, bug report, or feature request.
   Example: `A portfolio manager has just imported holdings and needs to run the optimizer before sending the client report. They want the selected mode to be saved so tomorrow's rerun uses the same assumptions.`
3. **Interface** — UI / API / CLI / API+UI. Per the feature-surface table below.
4. **Intent** — One sentence stating what the Actor achieves, in the Actor's terms. No endpoints, code, tables, components, or internal language.
5. **Setup** — Sanctioned setup only (public API, public signup/login, app CLI, UI, documented seed commands). Must NOT perform the same action the UC is testing — that turns Verification into a trivial re-read (Step 2b rejects this as `CHEAT_SETUP`). Don't re-test login in every UC: declare the auth/account state needed and use a sanctioned auth path; auth itself gets its own dedicated UCs.
6. **Steps** — The Actor's actions through the declared interface, in order. At least 2 steps (a single isolated call is too shallow).
7. **Verification** — Surface-specific user-observable outcome. See the rubric below — a bare status code / bare exit code / single element-visible check is disqualified.
8. **Persistence** — Reload, re-request, or re-invoke through the same interface and confirm the state stuck. Missing Persistence is a hard-fail.

   **`Persistence: N/A` is narrow.** Allowed ONLY for genuinely stateless outcomes the product itself does not retain:
   - A pure read-only query whose result depends only on inputs the test already controls (e.g., `GET /api/v1/health`, `mycli --version`)
   - An idempotent computation that returns the same answer every call (e.g., a stateless calculator endpoint)

   Disallowed (verify-e2e rejects as `MISSING_PERSISTENCE`):
   - "N/A — fix doesn't change state" — the _fix_ may not, but the _journey_ still creates/updates/transitions state that the user expects to find later. Persist through the same interface.
   - "N/A — this is a read endpoint" — only valid if the read truly depends on nothing the test created. If your Setup created a resource and Verification observes it, then Persistence must re-read after a delay/reload.
   - Any UC whose Steps include creating, updating, deleting, or transitioning state.

### Verification language — surface-specific

Verification must describe what the Actor can **observe** AND ideally what they can **do next** with what just happened. Surface vocabulary:

| Surface | Acceptable verbs                                                                                        | Too thin alone              |
| ------- | ------------------------------------------------------------------------------------------------------- | --------------------------- |
| UI      | sees, appears, is shown, can open, the page reads, the toast says, the row is highlighted               | a single element is visible |
| CLI     | stdout shows, stderr explains, the next invocation lists/shows/returns, the human-readable line matches | exit code 0 alone           |
| API     | receives, response includes, client can use, follow-up request returns, error body explains             | status code alone           |

**Rule:** at least one verb from the Acceptable list, AND a meaningful "next observable thing" beyond bare status/exit/element. Example: "Receives 201 + Location header; following that link returns the same order id and item list."

### What E2E is NOT

- ❌ Testing a function returns the right value (unit test)
- ❌ Testing an API endpoint returns 200 (integration test — narrow contract check)
- ❌ Testing a component renders correctly (component test)
- ❌ Clicking one button and checking one element (too shallow)
- ❌ Testing the same internal data path through two interfaces just to "cover both" (still one assertion, just duplicated)
- ❌ Setup creates the thing and Verification reads it back (cheat — the real action belongs in Steps)

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

Why bad: no Actor, no Scenario. Intent names a component. Verification checks one DOM element. No Persistence.

**✅ GOOD (user-journey):**

```
Actor:         Signed-in customer on the personal todo list
Scenario:      They just remembered something to buy while making dinner and want
               it captured before they forget. They'll come back to the list tomorrow
               morning to plan the day.
Interface:     UI
Intent:        The customer captures a new todo and sees it survive a reload so they
               can trust the list overnight.
Setup:         Register a new customer via the public signup flow + log in via UI.
Steps:         Navigate to /todos → Click "New Todo" → Type "Buy milk" → Click "Create"
Verification:  The customer sees "Buy milk" appear in the list with a "Created" toast
               that names it; clicking the row opens its detail view.
Persistence:   Reload /todos → "Buy milk" is still in the list at the position it
               was created.
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

Why bad: no Actor, no Scenario. Tests a single endpoint contract. Verification is bare status. No Persistence.

**✅ GOOD (user-journey):**

```
Actor:         API integrator wiring an external storefront to our order service
Scenario:      They have a logged-in customer session token and a cart of items. They
               need to place the order programmatically and confirm it lands in the
               customer's history so the storefront can show it on the next page load.
Interface:     API
Intent:        The integrator places an order on behalf of a customer and retrieves
               it back from the customer's order history.
Setup:         Register a customer via POST /api/v1/users; obtain session token via
               POST /api/v1/sessions. (Do NOT pre-create the order — that's the
               action under test.)
Steps:         POST /api/v1/orders {items:[…]} with auth → GET /api/v1/users/me/orders
Verification:  The integrator receives 201 + a Location header; following that link
               returns the new order with the same items and total. GET /orders
               response includes the new order at the top with the id from Location.
Persistence:   Re-request GET /api/v1/users/me/orders after a short delay; the order
               is still listed with the same id and items.
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

Why bad: no Actor, no Scenario. Tests argument parsing. Verification is bare exit code. No Persistence.

**✅ GOOD (user-journey):**

```
Actor:         Operator running the CLI on their laptop to bootstrap a new project
Scenario:      They've just been assigned the "launch-2026" project and want to add
               it to their local registry so they can drive subsequent runs from the
               shell without opening the UI.
Interface:     CLI
Intent:        The operator adds a project and lists it back in a separate invocation
               to confirm it persists across shell sessions.
Setup:         Run `mycli init` once to create the local config. (Do NOT pre-create
               the project — that's the action under test.)
Steps:         Run `mycli project add --name "launch-2026"` → run `mycli project list`
Verification:  `add` stdout shows `Created project launch-2026 (id: <UUID>)` with
               exit 0; the next invocation `mycli project list` returns a table whose
               first row is `launch-2026 <UUID>`.
Persistence:   Exit the shell, open a new one, run `mycli project list` → the new
               row is still there with the same id.
```

### Multi-surface coverage — design UCs for EVERY surface the user could use

**Many features extend a capability area that the project already exposes through multiple interfaces.** A feature touches a _capability area_ (e.g., "create portfolio", "search products", "manage users"); the user reaches that capability through any of the _surfaces_ the project exposes for it — UI page, API endpoint, CLI command.

When designing UCs, ask **per feature**, not per implementation diff:

> For each interface the project exposes (per `CLAUDE.md ## E2E Configuration`), is this feature's capability area reachable through that interface today, or should it be after this PR? If yes — design a UC for it.

**Surface coverage decision (mandatory in the plan file):**

For each interface the project exposes, the plan must explicitly state either:

- **Covered** — a UC exists for this surface, OR
- **N/A — \<substantive justification\>** — why users of this interface don't need this feature

**Acceptable N/A justifications:**

- "CLI: N/A — feature is a purely visual element (no operational capability change)"
- "CLI: N/A — feature is admin-only via UI by product decision (CLI users are operators, not admins)"
- "API: N/A — feature is a UI-only UX refinement (no contract change)"

**NOT acceptable N/A justifications:**

- "CLI: N/A — no CLI changes in my diff" — that describes implementation, not user-facing scope. If the feature's capability area is reachable from CLI today and you've extended it in UI/API, the CLI should be extended too (or you need a substantive product reason it shouldn't).
- "API: N/A — only the UI calls this endpoint" — internal API for a UI surface → UC goes through the UI, not the API (see the interface-selection table). This is correct N/A _handling_, but write that justification clearly so it's auditable.

**Worked example (the bug this rule prevents):**

A project exposes UI + API + CLI (`CLAUDE.md` says `fullstack` with a CLI). The new feature is "portfolio backtest with optimizer modes." Implementation adds a UI compose page, a new API endpoint, and DB migrations. The agent designs UI UC + API UC and skips CLI because "no CLI changes in the diff."

**This is wrong.** The project's CLI already has `portfolio create` and `portfolio run` commands. After the PR, CLI users have a degraded experience — they can list portfolios but can't use the new modes. Either:
(a) Extend the CLI commands to expose the new modes (and write a CLI UC for them), OR
(b) Substantively justify why CLI is out of scope (e.g., "Full mode requires interactive risk-policy preview; deferred to v2 with a `--full-config FILE` escape hatch tracked in TODO #1234.")

The verify-e2e agent (Step 2c) emits a SURFACE_COVERAGE_WARNING when UCs cover fewer surfaces than the project exposes. The warning is informational — the human reviewer decides whether the gap is intentional. During an autonomous `/forge-goal` run, the agent treats this warning as a `/council` trigger if the gap was not pre-justified in the plan.

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

1. **CLAUDE.md `## E2E Configuration` tells you which interfaces the project EXPOSES.** This is the capability envelope — the floor of what's possible to test.

   **Read order** (Codex P2-2, v5.33 review): first look for an explicit `surfaces:` line. If present, it is authoritative — use it verbatim. If absent, fall back to the `interface_type` defaults below.

| Project Type  | Default surfaces (when `surfaces:` is absent) | Tools                 | Playwright Required?       |
| ------------- | --------------------------------------------- | --------------------- | -------------------------- |
| **fullstack** | API + UI                                      | HTTP + Playwright MCP | Yes (when UI UCs exist)    |
| **api**       | API only                                      | HTTP (curl/httpie)    | No                         |
| **cli**       | CLI only                                      | Subprocess + stdout   | No                         |
| **hybrid**    | Declared per UC                               | Mixed                 | Only if UI use cases exist |

**Why the explicit `surfaces:` field exists** (surfaced 2026-05-18 msai-v2 soak): a fullstack project that ALSO ships a CLI cannot be described by `interface_type` alone — the defaults map fullstack to UI + API only. Without `surfaces: [UI, API, CLI]`, verify-e2e Step 2c never warns when UCs miss the CLI surface, because it doesn't know the CLI exists. **Always declare `surfaces:` explicitly when the project's actual surfaces exceed the interface_type default.**

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

| Classification            | Meaning                                                                                                                                   | Blocks ship?                  |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| **PASS**                  | Works as specified                                                                                                                        | No                            |
| **FAIL_BUG**              | Real product defect — user would hit this                                                                                                 | **Yes**                       |
| **FAIL_STALE**            | Use case references changed interface (endpoint/page/selector renamed) — needs update                                                     | No (maintenance flag)         |
| **FAIL_INFRA**            | Server down, timeout, flaky selector                                                                                                      | Retry once, then warn         |
| **FAIL_INVALID_USE_CASE** | Use case fails authoring discipline. See the reason-code table below. Bounces back to the main agent to rewrite the UC before re-running. | **Yes** (test-design failure) |

`FAIL_INVALID_USE_CASE` reasons (kept in sync with `agents/verify-e2e.md` Step 2b):

**Hard-SHAPE reasons** (skipped in regression/smoke modes per v5.35 mode-gating — old UCs predate v5.34's shape requirement):

- **`MISSING_ACTOR`** — no Actor field, or bare "user"/"users"/"a user" without role and situation.
- **`MISSING_SCENARIO`** — no Scenario field.
- **`SCENARIO_FLUFF`** — Scenario contains biography filler (age, city, hobbies, personality) or product-irrelevant fluff instead of starting-state + trigger + outcome.
- **`CHEAT_SETUP`** — Setup performs the same action the UC is testing (e.g., Setup creates the resource and Steps just read it back).
- **`THIN_VERIFICATION`** — Verification is bare status code / bare exit code / single element-visible. No surface-appropriate observation language.
- **`MISSING_PERSISTENCE`** — no Persistence step, or `Persistence: N/A` used outside the narrow stateless-outcome whitelist (see `## E2E Use Case Design` Persistence rules).
- **`TOO_SHALLOW`** — fewer than 2 user-meaningful Steps.

**Judgment-call reasons** (fire in **all** modes including regression/smoke — by design, so legacy code-shaped UCs surface and get rewritten):

- **`NOT_USER_JOURNEY`** — the UC reads as an integration/contract/component test, EITHER because the Intent names code/endpoints as the goal, OR because the **whole-UC shape** (Steps + Verification + Persistence taken together) reads as a single endpoint/flag/component check. See "whole-UC shape" trigger in `agents/verify-e2e.md` Step 2b judgment-call #7.
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
