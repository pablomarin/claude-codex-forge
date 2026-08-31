# Playwright CI Bridge (optional)

**Monday, 9 AM.** A first-time contributor opens a PR touching `/api/auth/login`. No Forge agent session runs, so `verify-e2e` does not explore the journey. Their PR goes green, merges, and breaks login for a thousand users by Wednesday.

The bridge fixes that. Every passing use case the agent explores becomes a deterministic `.spec.ts` file that CI replays in ~90 seconds, on every PR, zero LLM cost.

## Enable it

Append `--with-playwright` to your setup command:

**macOS / Linux:**

```bash
~/claude-codex-forge/setup.sh -p "My App" -t fullstack --with-playwright
```

**Windows (PowerShell):**

```powershell
& $HOME\claude-codex-forge\setup.ps1 -p "My App" -t fullstack -WithPlaywright
```

## Where it scaffolds (monorepo-aware)

Setup picks a Playwright directory (`<pw-dir>`):

1. If `--playwright-dir <path>` is passed, use that.
2. Otherwise, if exactly one of `frontend/`, `apps/web/`, `web/`, `client/` contains a `package.json`, scaffold into that subdirectory.
3. If multiple candidates match, fall back to repo root and print a warning so you can pick with the explicit flag.
4. If none match, scaffold at repo root (flat layouts).

## What gets scaffolded

| Path                                  | Purpose                                                                                                                                                              |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `<pw-dir>/playwright.config.ts`       | Playwright framework config (set `baseURL`, uncomment `setup` project)                                                                                               |
| `<pw-dir>/tests/e2e/fixtures/auth.ts` | Cookie-based auth fixture (secure default; API-key path commented out)                                                                                               |
| `<pw-dir>/tests/e2e/specs/`           | Empty dir for deterministic specs (main agent writes into this)                                                                                                      |
| `<pw-dir>/tests/e2e/.auth/.gitignore` | Credential-safe (never committed)                                                                                                                                    |
| `docs/ci-templates/e2e.yml`           | Reference GitHub Actions workflow (not auto-activated). `working-directory` is stamped with `<pw-dir>` at scaffold time so the workflow runs correctly on monorepos. |

## One-time install after setup

Run these from `<pw-dir>` — repo root for flat layouts, or `cd <pw-dir>` first on monorepos (setup.sh prints the exact command at the end):

```bash
pnpm add -D @playwright/test && pnpm exec playwright install
# set TEST_USER_EMAIL + TEST_USER_PASSWORD in .env (cookie auth — the secure default)
# TEST_API_KEY is an insecure local-dev-only fallback — see the SECURITY WARNING in tests/e2e/fixtures/auth.ts
# review playwright.config.ts — set baseURL, uncomment the "setup" project
```

## How your workflow changes — two touchpoints

| Phase               | What happens                                                                                                                                               |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **5.4b regression** | Runs `pnpm exec playwright test` when every UC has a matching spec; falls through to the `verify-e2e` agent during partial migration — safe at every point |
| **6.2c (new)**      | **Main** implementation agent reads the `verify-e2e` report + markdown UC, writes `tests/e2e/specs/<feature>.spec.ts` using selectors the agent observed   |

The `verify-e2e` agent stays read-only. Only the main agent writes specs. This is a hard invariant.

## The two layers

- **`tests/e2e/use-cases/*.md`** — intent, lives with your plan
- **`tests/e2e/specs/*.spec.ts`** — deterministic replay, runs everywhere (local, CI, cron, contributor PRs)

See `.forge/rules/testing.md` for the full model.
