# Template Self-Tests

Regression suite for the claude-codex-forge template itself — not for user projects that install the template.

## Why

The dev loop for template changes used to be: commit → push → merge → run `setup.sh --upgrade` in a downstream repo (e.g. a downstream project) → see if it works. Slow, dangerous, no regression protection. This suite catches the same class of bugs locally in ~5 seconds with no downstream repo needed.

## Run everything

```bash
bash tests/template/run-all.sh
```

Exits 0 if every suite passed, 1 otherwise. Intended for both local runs and CI.

## Run one suite

```bash
bash tests/template/test-setup.sh       # behavior — runs setup.sh in scratch dirs
bash tests/template/test-fixtures.sh    # content — grep fingerprints of templates
bash tests/template/test-contracts.sh   # cross-file consistency (e.g. VERDICT header)
bash tests/template/test-lint.sh        # syntax — bash -n, pwsh parse, jq validate
```

## Suites

| File                | What it checks                                                                                                                                                                                                                                                                              |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `test-setup.sh`     | Runs `setup.sh --with-playwright` against 5 project layouts (flat, `frontend/`, multi-candidate, `--playwright-dir` override, `apps/r&d` metachar), plus idempotency (hash-based), `-f` force-refresh, and `--upgrade` smoke                                                                |
| `test-fixtures.sh`  | Fingerprint grep on template source files — branding leak, trace/video CI security default, cookie-auth default (with block-comment-aware check for the insecure `localStorage` pattern), verify-e2e response header, `post-tool-format.sh` monorepo walk-up, `prd/create.md` fence balance |
| `test-contracts.sh` | Cross-file consistency: verify-e2e `VERDICT:` header values must match caller branch labels in `commands/new-feature.md` and `commands/fix-bug.md`; no caller may branch on a verdict the agent doesn't emit                                                                                |
| `test-lint.sh`      | `bash -n` on every shell script we ship; `pwsh -NoProfile` parse on every `.ps1` (if `pwsh` is installed); `jq` validate on JSON templates; placeholder-substitution coverage (`__PLAYWRIGHT_DIR__` must be handled in BOTH `setup.sh` and `setup.ps1`)                                     |

## Environment variables

| Variable             | Effect                                                                                             |
| -------------------- | -------------------------------------------------------------------------------------------------- |
| `KEEP_TMP=1`         | Always preserve scratch dirs under `${TMPDIR:-/tmp}/forge.*` (useful for debugging a passing test) |
| `KEEP_TMP_ON_FAIL=1` | Preserve scratch dirs only when a test exits non-zero (post-mortem)                                |
| `NO_COLOR=1`         | Disable ANSI color codes in output                                                                 |

## Adding a new test

1. **If it's a behavior of `setup.sh`** — add to `test-setup.sh` as a new `Test N:` block. Use `scratch_dir`, `make_project`, `run_setup`, and the `assert_*` helpers from `lib.sh`.
2. **If it's a regression check on template content** — add to `test-fixtures.sh`. Use `assert_contains` / `assert_not_contains` / `assert_matches`. For anything that might appear inside a `/* ... */` block comment, use the python3-based stripper pattern already in `test-fixtures.sh` Test 2.
3. **If it's a cross-file contract** — add to `test-contracts.sh`. These are the tests that catch "two files drift apart" bugs.
4. **If it's a syntax/parse check** — add to `test-lint.sh`.

Every helper is in `lib.sh`. Don't duplicate assertion logic across suites.

## Known gaps (intentional)

- `hooks/post-tool-format.sh` runtime behavior (needs crafted stdin JSON + real Python project). Covered by `test-fixtures.sh`'s static check of the script contents, not by a runtime harness. Upgrade if a regression slips through.
- `markdownlint` on the full docs tree. Fence-balance check in `test-fixtures.sh` covers the one known class of failure; add a full `markdownlint` run if docs lint becomes a recurring problem.
- Full end-to-end of a downstream project actually running against a scaffolded `setup.sh --with-playwright`. Too slow for this suite; rely on dogfooding in a downstream project.

## Flake-risk conventions

- Always use `mktemp -d` and `trap EXIT` for cleanup — never hardcode `/tmp/test-foo/`.
- Always use `grep -qF` (literal) when asserting substrings. Reserve `grep -qE` for cases where you actually want a regex.
- Don't compare mtimes for idempotency — `setup.sh` writes some files unconditionally by design. Use `hash_file` / `assert_hash_equals` on the specific files whose content must be stable.
- Don't assert on raw color-coded stdout. Use logfiles with `--color never` or matching on the uncolored substring.
