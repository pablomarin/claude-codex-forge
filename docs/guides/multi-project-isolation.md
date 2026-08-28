# Multi-Project Isolation

If you use Claude Codex Forge across several projects at once, each with its own Python / Node / library versions, here is what the harness isolates for you automatically — and what you still have to arrange yourself.

## TL;DR

- **Dependencies** are isolated per project by `uv` (Python) and `pnpm` (Node). You get this for free.
- **Interpreter binaries** (`python3.10` vs `python3.12`, `node 18` vs `node 22`) are NOT switched for you. Use a version manager — `uv python install`, `pyenv`, `nvm`, `fnm`, or `volta`.
- **`setup.sh` runs a warn-only preflight** at install/upgrade time that reads `.python-version`, `.nvmrc`, and root `package.json` `engines.node` and tells you if the declared runtime is missing. It never blocks — setup always completes with exit 0.

## What the harness isolates automatically

### Python dependencies — via `uv`

When you run `uv sync` in a project, `uv` creates a project-local `.venv/` directory with exactly the interpreter version and packages `pyproject.toml` specifies. `uv run pytest` uses that venv automatically. No manual `source .venv/bin/activate` is needed.

The `post-tool-format.sh` hook that ships with this harness walks up from any edited `.py` file to find the nearest `pyproject.toml`, then runs `uv run ruff check --fix` and `uv run ruff format` from that directory — so monorepos with `backend/src/`, `apps/api/`, or similar layouts all get the right per-project lint/format config.

### Node dependencies — via `pnpm`

`pnpm install` populates a project-local `node_modules/` directory. `pnpm exec playwright test` uses the local install. Nothing global is touched.

### Worktrees for parallel work — via `/new-feature` and `/fix-bug`

Each active feature gets its own worktree under `.worktrees/<name>/` with its own filesystem state.
Claude Code and Codex sessions can work in separate worktrees without cross-contamination. Forge
warns against simultaneous edits in one worktree and does not add locks. Each worktree reuses the
same `.venv/` / `node_modules/` via symlinks from the main worktree.

## What the harness does NOT switch for you

Interpreter binaries. If project A's `pyproject.toml` declares `requires-python = ">=3.10,<3.11"` and project B declares `">=3.12"`, the harness does not install either version or route your calls to the right one. You need a version manager.

Recommended:

| Language | Primary recommendation                   | Alternatives                   |
| -------- | ---------------------------------------- | ------------------------------ |
| Python   | `uv python install <version>`            | `pyenv`, `mise`, `asdf`, Conda |
| Node     | `fnm` (fast, auto-switches via `.nvmrc`) | `volta`, `nvm`, `mise`, `asdf` |

Once installed, `uv sync` and `pnpm install` respect the active version. For Python, if the exact version `pyproject.toml` requires is missing, `uv` will usually fetch it on demand — so `uv python install` may not even be needed as a separate step. Node doesn't auto-fetch; you install versions explicitly.

## How the `setup.sh` preflight helps

Before printing `Prerequisites OK`, `setup.sh` checks whether repo-root version declarations can be satisfied:

| File scanned                       | What's checked                                                                                                                                                     |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `.python-version`                  | Pinned Python version (e.g. `3.12.5`). Preflight verifies a matching interpreter is discoverable via `uv python list`, `pyenv versions`, or `python3.X --version`. |
| `.nvmrc`                           | Pinned Node version (e.g. `20.11.0` or `20`). Preflight verifies `node --version` matches, or that `fnm`/`nvm`/`volta` can provide it.                             |
| root `package.json` `engines.node` | Declared constraint (e.g. `">=20"`). Preflight checks `node --version` satisfies the minimum; warns otherwise.                                                     |

**If a declared runtime is missing or mismatched, preflight prints a warning with install guidance and continues.** It does NOT set a non-zero exit code. It does NOT stop `setup.sh`; the authoritative `-F` full refresh runs the same preflight.

**If neither `.python-version` / `.nvmrc` / root `package.json` exists, preflight is silent** — the check doesn't run, so there's no noise for projects that don't pin versions.

**If the required version manager isn't installed** (no `pyenv` / no `fnm` / no `uv`), preflight falls back to checking the system interpreter. If the system interpreter doesn't match, you see a warning telling you to install one of the recommended version managers.

## Scope and limitations of the preflight

Intentionally narrow for v1:

- **Repo root only.** Sub-directory `.python-version` files (monorepo patterns like `backend/.python-version`) are NOT checked. The `uv` walk-up in the post-tool-format hook handles those at runtime; pre-flight doesn't duplicate it.
- **Warning only.** No exit codes change. No session blocking. If you're mid-upgrade on a project whose pinned versions are stale, you still get to finish the upgrade.
- **No interpreter switching.** Preflight diagnoses; you fix. A well-written message will tell you which command to run (`uv python install 3.12`, `fnm install 20`, etc.).
- **No `verify-app` integration.** The `verify-app` agent already runs `uv run pytest`, which fails loudly on interpreter issues. We don't layer a second check there — Codex's Scalability Hawk advisor argued for it, Council deferred.
- **No session-start hook.** Hooks fire on every session, every worktree, for every tech stack. Running an interpreter probe there would mean N shell-outs per startup and a support matrix covering pyenv/conda/poetry/nix/asdf/mise/volta/fnm/nvm. Not worth it.

## Troubleshooting

### `setup.sh` says my Python version is missing but I just installed it

Some version managers require a shell restart before their shims are on `PATH`. Close and reopen the terminal, then rerun `setup.sh -F`. If you use `uv`, run `uv python install <version>` — it's immediate.

### I don't use version managers and setup.sh warns anyway

If you have system `python3` that satisfies `.python-version` but no version manager, preflight should detect it via `python3 --version`. If you're still seeing warnings, the declared version likely doesn't exactly match what `python3` provides (e.g., `.python-version: 3.12.5` but system has `3.12.3`). Either update `.python-version` to allow the installed patch, or install the exact version.

### I use Conda / Docker / Nix and your warnings are wrong for me

Preflight's heuristic can't cover every version-manager pattern in the ecosystem. For exotic setups, the warning is informational; dismiss it. We err toward under-enforcement to avoid false positives.

### Can I silence the preflight entirely?

Not via a flag — the warning is useful most of the time and silent when you have no version pins. If you want to suppress it for a project, remove or empty the `.python-version` / `.nvmrc` files. If you want to suppress it for a CI run, redirect stdout/stderr appropriately.

## Related guides

- [Parallel Development](parallel-sessions.md) — worktree isolation for multiple host sessions on one project
- [Getting Started](../getting-started.md) — overall install steps with prerequisites
- [Upgrading](upgrading.md) — authoritative `setup.sh -F` refresh mechanics
