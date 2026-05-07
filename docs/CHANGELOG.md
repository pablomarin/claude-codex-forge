# Changelog

All notable changes to claude-codex-forge.

## 5.22 — 2026-05-01 · Codex PTY shim — work around openai/codex#19945

`codex exec` silently exits with empty stdout (exit 0, zero bytes) when run with stdio detached from a controlling TTY AND a non-trivial prompt — exactly the conditions Claude Code's Bash tool creates every time the Forge invokes `/codex` or `/council`. The bug was [introduced in codex 0.124.0](https://github.com/openai/codex/issues/19945) (last unaffected: 0.123.0), still present in 0.125.0 / 0.128.0, and has no upstream fix as of 2026-05-01.

Field reports describe 10–17 minute hangs on long audit prompts, ending in `kill` exit-144. The Forge memory previously attributed the symptom to "long prompt overload"; that was incomplete — prompt length is one of two triggers, not the trigger.

**The fix: a cross-platform PTY shim** at `.claude/hooks/lib/codex-pty.sh` (Unix) and `codex-pty.ps1` (Windows). All `codex exec` invocations across `/codex` and `/council` now route through the shim, which allocates a pseudo-terminal so codex sees `isatty(stdin/out) == true` and produces real output.

**Unix path:** `python3` + a lightweight helper script (`codex-pty-helper.py`) using `pty.fork()` + `waitpid(WNOHANG)` polling. We can't use BSD `script(1)` because it requires a parent TTY (`tcgetattr` on parent stdin) which Claude Code's Bash tool — running with stdin connected to a Unix domain socket — does not have. We can't use Python's `pty.spawn()` either: the 3.9 stdlib version hangs on macOS after the child exits because the parent's `select()` loop blocks on a `master_fd` that never reports EOF. The explicit waitpid-based helper sidesteps both problems.

**Windows path:** detect-then-bypass. PS 7+ with non-redirected stdio uses ConPTY natively (no shim needed). Redirected stdio probes `winpty.exe` (PATH first, then Git for Windows install paths). WSL is opt-in via `CLAUDE_FORGE_CODEX_PTY_VIA_WSL=1`. Last resort: direct invoke with stderr warning. Per the research brief, #19945 has zero confirmed Windows reproductions — the .ps1 shim exists primarily for ADR 0005 platform parity.

**Opt-out** via `CLAUDE_FORGE_CODEX_PTY_BYPASS=1` (mirrors the v5.21 PR #592 pattern). Useful when upstream is confirmed fixed, or when an EDR / corporate sandbox blocks PTY allocation.

**Test coverage:** 20 unit tests for the Unix shim (mocked codex + isatty assertions + real-pty integration via `/bin/echo` + stdin-from-/dev/null liveness). 9 cross-file contract assertions in `test-contracts.sh` enforce env-var name parity, header references to issue #19945, callsite migration completeness, and setup-script wiring on both platforms.

**Retest criterion:** drop the shim once codex 0.128+ is empirically confirmed clean by re-running issue #19945's repro: `setsid codex exec "$LARGE_PROMPT" < /dev/null` producing non-empty output. Until then, leave it in place.

**Existing installs need `./setup.sh -f`** to pick up the shim files, then any new `/new-feature` or `/fix-bug` invocation in a downstream project will use the migrated callsites.

## 5.21 — 2026-04-30 · PermissionRequest hook auto-approves writes to .claude/local/\*\*

Field-confirmed bug from msai-v2 (Claude Code v2.1.123): `/new-feature` invoked from inside a `.worktrees/<name>/` directory prompted the user for permission to use `Edit(.claude/local/state.md)` despite **all four path-scoped allow rules** (v5.19 `./.claude/local/**` pair plus v5.21 `**/.claude/local/**` pair) being loaded into the session — confirmed via `/permissions`. The settings.json fix didn't actually fix the user-visible problem.

Root cause is the broader [v2.1.80+ permission regression](https://github.com/anthropics/claude-code/issues/36593): both bare and path-scoped Write/Edit allow rules fail to auto-approve in recent Claude Code versions. PR #574 (v5.19) addressed it with explicit path-scoped patterns; this release accepts that the regression hits both bare AND path-scoped rules and pivots to the documented escape hatch — a hook.

**The fix: a PermissionRequest hook** that auto-approves Write/Edit on `.claude/local/**`. PermissionRequest fires only when Claude Code is about to show a permission dialog (narrower than PreToolUse, which fires on every tool call) and emits `hookSpecificOutput.decision.behavior=allow` to skip the prompt. Hooks bypass the broken permission engine entirely.

**Path validation, per Codex design review:**

- Substring match would be exploitable (`.claude/local/../../etc/passwd`). The hook normalizes separators (Windows `\` → `/`), rejects any `..` path segment, resolves relative paths against hook-provided `cwd`, lexically collapses `.` and empty segments, then segment-matches `*/.claude/local/*` (requires `/` boundary on both sides — rejects substring spoofs like `/foo.claude/localbar/`).
- **Fail-open by design**: parse failures, missing `jq`, malformed paths, traversal attempts, empty paths, and unknown tools all exit silently with no allow JSON — Claude Code falls back to its default permission flow and prompts the user. The hook is a UX improvement, not a security boundary.
- **Opt-out** via `CLAUDE_FORGE_AUTO_APPROVE_LOCAL_WRITES=0` env var.

**Why PermissionRequest, not PreToolUse?** PermissionRequest fires only when CC is about to show a dialog — the hook adds zero overhead to Write/Edit calls that are already auto-approved by other rules. PreToolUse would run on every Write/Edit, which is unnecessary work.

**v5.21 also keeps the v5.19 + v5.21 patterns in `permissions.allow`** as belt-and-suspenders. They're not effective today (regression), but they're correct gitignore-style patterns that will start working the day Anthropic resolves [#36593](https://github.com/anthropics/claude-code/issues/36593) — at which point the hook becomes redundant fallback.

- `hooks/auto-approve-local-writes.sh` + `.ps1` — new PermissionRequest hook scripts (cross-platform parity).
- `settings/settings.template.json` — added `PermissionRequest` event with `Write|Edit` matcher; kept the v5.21 `**/.claude/local/**` allow patterns alongside v5.19's.
- `settings/settings-windows.template.json` — same two additions for parity.
- `setup.sh` + `setup.ps1` — copy the new hook scripts on install/upgrade.
- `CLAUDE.md` — file-tree comment + Hook Design section updated.
- `README.md` — version badge bump 5.20 → 5.21, prepend version-history row.

**Existing installs:** run `setup.sh --upgrade`. The new hook script lands in `.claude/hooks/`; settings.json gets merged (PermissionRequest event added; user customizations preserved). **Restart any running Claude Code session in the project** — settings.json loads at session start, so a mid-session upgrade doesn't take effect until you exit and re-launch.

## 5.20 — 2026-04-29 · Bump Codex CLI model gpt-5.4 → gpt-5.5

OpenAI shipped GPT-5.5 on 2026-04-23 and Codex CLI now accepts it as a model identifier (`developers.openai.com/codex/models` lists it as the recommended choice). Codex CLI's default is still `gpt-5.4` as of `rust-v0.125.0`, so the upgrade requires an explicit model-string swap — automation doesn't get gpt-5.5 by accident.

Researched the CLI release notes (`rust-v0.124.0` → `rust-v0.125.0`) for any breaking changes — there are none. All flags and config keys we use (`-m`/`--model`, `-c key=value`, `--sandbox`, `--ephemeral`, `--uncommitted`, `--base`, `--commit`, `--full-auto`, `--skip-git-repo-check`, `model`, `review_model`, `model_reasoning_effort`) remain supported on the same subcommands. The `xhigh` reasoning level is still valid and inherits onto gpt-5.5 per the model catalog.

So this is a pure model-name swap.

- `commands/codex.md` — 5 invocation strings updated (`-m "gpt-5.4"` → `-m "gpt-5.5"`, plus `-c model=` and `-c review_model=` config-key examples in the reference table).
- `skills/council/references/peer-review-protocol.md` — 3 council-advisor invocation strings updated.
- `README.md` — version badge bump 5.19 → 5.20, prepend version-history row.

**Existing installs:** the new model lands on next `setup.sh --upgrade` (commands and skills are refreshed; user customizations in `settings.json` are preserved).

## 5.19 — 2026-04-29 · Allow Write/Edit on .claude/local/\*\* without prompting

Field bug from msai-v2: `/new-feature` workflow prompted the user for permission to use `Write(.claude/local/state.md)` despite `"Write"` being in the project's `permissions.allow` list. Three converging causes:

1. **`.claude/` directory has elevated protection** — per the [official Claude Code permissions docs](https://code.claude.com/docs/en/permissions#permission-modes), writes to `.claude/` prompt even in `bypassPermissions` mode (anti-corruption guard). `.claude/commands`, `.claude/agents`, `.claude/skills` are documented as exempt; `.claude/local/` is NOT.
2. **Bare-tool-name regression** — [GitHub issue #36593](https://github.com/anthropics/claude-code/issues/36593) documents Claude Code v2.1.80+ failing to auto-approve under blanket `"Write"` / `"Edit"` allow rules. Workaround per docs: pair the bare entry with explicit `Tool(path)` patterns.
3. **State.md is the only `.claude/local/` artifact today** but the canonical workflow file is written to on every `/new-feature`, `/fix-bug`, and Phase update — frequent prompting kills the workflow's "feel autonomous" goal.

Fix adds two explicit allow rules per template, sitting alongside the bare entries so behavior degrades gracefully on older Claude Code versions where bare worked.

- `settings/settings.template.json` — added `Write(./.claude/local/**)` and `Edit(./.claude/local/**)` to `allow`.
- `settings/settings-windows.template.json` — same two additions for parity.
- `README.md` — version badge bump 5.18 → 5.19, prepend version-history row.

**Existing installs:** the new rules land on next `setup.sh --upgrade` (settings.json gets merged; user customizations preserved).

## 5.18 — 2026-04-28 · Tighten reconcile prompt — enumerate all CONTINUITY reference types

The 5.17 soft tip and 5.16 migration warning shipped a single-clause prompt that only addressed the `@CONTINUITY.md` dangling-import line at the top of CLAUDE.md. Field bug from msai-v2: leftover references at line 102 (file-tree diagram listing CONTINUITY.md as a project file) and line 212 (`(see CONTINUITY)` deferred-followup pointer) survived running the v5.17 prompt because the wording only covered the @-import case AND the "preserving my project-specific content" clause actively pushed Claude to keep them.

Prompt expanded to (a) instruct Claude to scan the ENTIRE file, (b) enumerate four concrete reference types (`@CONTINUITY.md` import lines, file-tree diagrams, prose pointers like `see CONTINUITY` / `in CONTINUITY.md` / `(CONTINUITY)`, comments/labels referencing CONTINUITY.md), and (c) explicitly carve CONTINUITY pointers OUT of the "preserve project-specific content" rule by labeling them "stale infrastructure references."

> Reconcile my CLAUDE.md against `$SCRIPT_DIR/CLAUDE.template.md`. Port any new template sections, preserving my project-specific content. Then scan the ENTIRE file and remove every dangling reference to CONTINUITY.md left over from before the 5.15 migration. Look for: `@CONTINUITY.md` import lines (usually at the top); file-tree diagrams that list CONTINUITY.md as a project file; prose pointers like `see CONTINUITY`, `in CONTINUITY.md`, `(CONTINUITY)`; comments or labels that reference CONTINUITY.md as a location. CONTINUITY.md no longer exists — its content moved to CLAUDE.md (durable), `docs/adr/` (decisions), and `.claude/local/state.md` (volatile). Remove these references; the "preserve project-specific content" rule does NOT apply to CONTINUITY pointers — they are stale infrastructure references.

- `setup.sh` + `setup.ps1` — soft tip body expanded; closing-quote position preserved on last echo line; ASCII-only output for cross-platform byte-parity (per migration-script gotcha).
- `scripts/migrate-continuity.sh` + `scripts/migrate-continuity.ps1` — Variant B warning body matches setup.sh/setup.ps1 exactly (parity).
- `tests/template/test-setup.sh` + `test-contracts.sh` — assertions updated: legacy `@CONTINUITY.md line on top` exact-phrase check replaced with `@CONTINUITY.md import lines` (5.18 wording); three new lock-in assertions per platform (`scan the ENTIRE file`, `File-tree diagrams`, `stale infrastructure references`) so the broader scope cannot silently regress.
- `README.md` — version badge bump 5.17 → 5.18, prepend version-history row.

**Existing installs:** the new wording lands on next `setup.sh --upgrade`. No content migration needed. Re-run the recommended prompt against your CLAUDE.md to clean up any leftover CONTINUITY references that survived the v5.17 pass.

## 5.17 — 2026-04-28 · Drop per-file template-drift cry-wolf hint; soft "ask Claude to reconcile" tip

Removes the per-file inline `Template may have drifted. To review: git diff --no-index ...` hint that fired every time CLAUDE.md was preserved during `--upgrade`. Same cry-wolf problem as the consolidated preamble dropped in 5.16, just at a different layer.

Replaced with a single soft tip at end of upgrade summary recommending the full Variant B "ask Claude to reconcile" prompt (matches the migration script's wording from 5.16, including the `@CONTINUITY.md` dangling-import cleanup clause for consistency). Fires once per upgrade (when CLAUDE.md was preserved), not per-file. Soft `Tip:` prefix in blue, no warning glyph.

The "Full guide" reference uses the absolute path to the Forge clone (`$SCRIPT_DIR/docs/guides/upgrading.md` on bash, `$ScriptDir/docs/guides/upgrading.md` on PowerShell) so it resolves correctly when users run `setup.sh --upgrade` from inside their project (the harness guides aren't shipped to downstream installs).

This is a fix-up of an earlier attempt that Codex flagged with two P2 issues: the soft tip dropped the `@CONTINUITY.md` cleanup clause (inconsistent with Variant B), and the "Full guide" reference used a relative path that resolved under the user's project. Both addressed here.

- `setup.sh` + `setup.ps1` — removed inline `print_template_drift_hint` / `Write-TemplateDriftHint` helpers + invocations; added soft tip at end of upgrade summary with full Variant B prompt and absolute-path guide reference
- `tests/template/test-setup.sh` + `test-contracts.sh` — updated assertions: legacy "Template may have drifted" string banned in installers, soft tip + `@CONTINUITY.md` clause present, absolute path used for "Full guide"

## 5.16 — 2026-04-28 · Migration UX — consolidated "ask Claude" reconcile message; dropped cry-wolf drift hint

Replaces two separate warnings with one consolidated instruction:

- `setup.sh -f` / `--upgrade` previously printed "⚠ Template may have drifted since your last upgrade" with a `git diff --no-index` command on every run, regardless of actual drift — cry wolf.
- `setup.sh --migrate` previously printed a separate "@CONTINUITY.md dangling import — remove manually" warning.

Both are now replaced by a single Variant B message at the end of `--migrate` output telling the user to paste this prompt into Claude Code:

> Reconcile my CLAUDE.md against `$SCRIPT_DIR/CLAUDE.template.md`. Port any new template sections I'm missing, preserving my project-specific content. If you see an `@CONTINUITY.md` line on top, remove it -- it's a dangling import from before the 5.15 migration.

Codex reviewed Variant A (minimal — bet that "reconcile" naturally removes the @-import) vs Variant B (explicit @-import callout); picked B because "reconcile + preserve project-specific" gives Claude room to keep unmatched top-of-file lines, and the @-import line is exactly the kind of stale-but-user-owned content that can survive without explicit naming.

A "Manual fallback" subsection in `docs/guides/upgrading.md` covers SSH / scripted-install users (per Codex's caveat).

- `scripts/migrate-continuity.{sh,ps1}` — replace @-import warning with Variant B message; both compute their own SCRIPT_DIR (bash/PS dispatch is direct, no env-var pass-through).
- `setup.sh` + `setup.ps1` — drop the `git diff --no-index ... CLAUDE.template.md ...` cry-wolf hint from the upgrade summary. Legacy CONTINUITY.md detection block stays (actionable, not cry-wolf). Four-variant Upgrade-done message stays.
- `docs/guides/upgrading.md` — add "Manual fallback" subsection; rewrite the dangling-import paragraph to point at the migration's Variant B prompt.
- `README.md` — version badge bump 5.15 → 5.16, prepend version-history row.

**Existing installs:** the new wording lands on next `setup.sh --upgrade`. No content migration needed.

## 5.15 — 2026-04-28 · CONTINUITY split — durable facts to CLAUDE.md, decisions to docs/adr/, volatile state to .claude/local/state.md (gitignored)

Closes the multi-developer state-file conflict failure mode at the source: CONTINUITY.md mixed two genres (durable team-shared facts + volatile per-developer state) in one tracked file, producing merge conflicts on every multi-dev pull and silently injecting stale per-developer state into Claude's auto-loaded context. PR #2 of the multi-PR drift-hygiene initiative; PR #1 (drift-hygiene, 5.14) addressed the symptom via SessionStart fetch + warning. PR #2 fixes the source by splitting the artifact.

Council fired (5 advisors + Codex chairman, xhigh reasoning). Phase 1 Contrarian Gate returned OBJECT (Codex argued PR #1's bug was _shared_ stale state, not auto-load semantics). Per protocol, escalated to full council on high-impact-surface ground. Final tally: Pragmatist + Hawk APPROVE A; Maintainer CONDITIONAL on A; Simplifier OBJECT (wants Anthropic-blessed `CLAUDE.local.md`); Contrarian CONDITIONAL leaning B with schema discipline (also surfaced Option C: `.claude/state.md` without `/local/`). Chairman picked Option A: `.claude/local/state.md`, gitignored, NOT auto-loaded — "PR #1 proved that stale state in model context is harmful; shared tracking was the trigger, but auto-load was the transport."

- **`.claude/local/state.md` (NEW path)** — gitignored, per-developer, NOT auto-loaded by Claude Code. Hooks read it via shell on demand. Schema: Workflow (Command/Phase/Next step + Checklist), State (Done/Now/Next/Deferred), Open Questions, Blockers. Default Command is `none` (explicit inactive state).
- **`docs/adr/NNNN-*.md` (NEW directory)** — per-file ADRs (Nygard core + MADR's "Considered Options" extension). Five seed ADRs ship: 0001 (this decision), 0002 (bash+PS dual-platform), 0003 (template-distributed no-build-step), 0004 (Diátaxis docs), 0005 (hard platform parity rule). README index + blank template.
- **`hooks/check-state-updated.{sh,ps1}` redesigned as advisory-only** — drops only the CONTINUITY-specific gate (`git status --porcelain` block, incompatible with gitignored state). Extracts active workflow Cmd/Phase/Next, prints reminder. CHANGELOG threshold gate remains. Gating role for state moves entirely to PreToolUse hook.
- **`hooks/check-workflow-gates.{sh,ps1}` hard-cut** — reads only `.claude/local/state.md`. Missing file → friendly stderr breadcrumb pointing at `--migrate`, exits 0 (no fallback to legacy CONTINUITY.md).
- **`setup.sh --migrate` (NEW flag)** — user-invoked, deterministic content migration from legacy `CONTINUITY.md`. Extracts Goal → CLAUDE.md, Architecture/Key Decisions table → per-file ADRs (auto-numbered after seed), Done (trimmed to 3) / Now / Next → state.md. Idempotent. Original CONTINUITY.md preserved byte-for-byte. Flags dangling `@CONTINUITY.md` imports in preserved CLAUDE.md files.
- **`setup.sh -f` / `--upgrade`** — installs new files alongside legacy CONTINUITY.md (preserved). Updated upgrade summary block prompts user to run `--migrate` if a legacy file is detected.
- **`CLAUDE.template.md`** — `@CONTINUITY.md` line removed from line 1 (research finding: Claude Code @-import fails silently on missing target). Project Overview now contains a Goal subsection placeholder for migrated content.
- **`CONTINUITY.template.md` deleted** — no longer generated.
- **`tests/template/test-migrate.sh` (NEW)** — fixtures: extracts goal, creates ADRs from decisions table, trims Done to 3, byte-preserves original, idempotent (sentinel marker), flags dangling import, gracefully handles no-legacy-file.
- **`tests/template/test-contracts.sh`** — new contracts: zero CONTINUITY refs in hooks/commands/rules/agents/settings (excluding intentional user-facing breadcrumb messages); bash/PS hook parity on missing-state breadcrumb; ADR template shape; all seed ADRs have canonical 5 sections.
- **`tests/template/test-hooks.sh`** — fixtures migrated to state.md; new tests for hard-cut behavior (no CONTINUITY fallback) and Stop-hook-advisory-only.
- **`tests/template/test-setup.sh`** — assertions for state.md install, gitignore mutation idempotency, ADR install, CONTINUITY.template.md NOT shipped, -f preserves existing CONTINUITY.md.
- **`docs/explanation/memory-architecture.md`** — diagram updated to reflect three-artifact split.
- **`scripts/migrate-continuity.{sh,ps1}` (NEW)** — refactored migration helper out of setup.sh per Codex plan-review feedback (P2). Same algorithm, ~250 LOC each, parity-tested. setup.{sh,ps1} dispatches to these on `--migrate`.
- **Forge dogfood** — Forge's own CONTINUITY.md migrated in this PR. Forge's CLAUDE.md folds in durable content. Forge's docs/adr/ contains the seed ADRs. Forge's `.claude/local/state.md` holds the volatile workflow state.
- **Migration is hard-cut** — no fallback in hooks. Existing installs that upgrade but don't run `--migrate` see a friendly breadcrumb on commit/push attempts pointing at the migration flag.
- **Idempotency via sentinel marker** — `<!-- forge:migrated YYYY-MM-DD -->` is written into migrated content; subsequent `--migrate` runs detect the marker and no-op without mutating any user-edited content. Prevents data loss on rerun.

**Existing installs need `./setup.sh -f` to pick up the new files, then `./setup.sh --migrate` to move their CONTINUITY.md content to the new structure.**

Test suite: refer to `bash tests/template/run-all.sh` output post-merge for the exact pre→post assertion delta. ~30 new assertions + 1 new suite (test-migrate.sh).

## 5.14 — 2026-04-27 · Drift hygiene — SessionStart `git fetch` + worktree from `origin/<default>`

Closes the multi-developer staleness failure mode: local `main` silently 97 commits behind origin while Claude reads `CONTINUITY.md` as authoritative state and confidently cites already-merged PRs as "open." Worse, `/new-feature` and `/fix-bug` were creating worktrees from local `HEAD`, so feature branches got built on stale baselines. PR #1 of a multi-PR initiative; PR #2 (CONTINUITY.md split + per-developer state migration) is non-goals here.

Council fired on the inline-vs-factored fork (5 advisors + chairman). Verdict: narrow Option C — factor only `hooks/lib/default-branch.{sh,ps1}` (the one piece with proven drift history), keep Pre-Flight inline in `commands/*.md`, simple-detect `gtimeout || timeout || skip` for macOS. Plan went through 4 review iterations (10 → 3 → 1 → 0 findings). Code review loop ran **7 iterations** to genuine convergence (4 P1 + 5 P2 → 1 P2 → 1 P2 → 1 P2 → 1 P2 + 1 P3 → 1 P1 + 1 P2 → CLEAN). Per `rules/critical-rules.md` "NO BUGS LEFT BEHIND" — all reviewer findings fixed in-branch, no follow-up deferrals.

- **`hooks/lib/default-branch.{sh,ps1}` (NEW)** — first-ever `hooks/lib/` directory. Detection chain: `git symbolic-ref refs/remotes/origin/HEAD` → local `main` → local `master` → bail (exit 1). Strict contract: branch name on stdout only, silent stderr, exit 0/1. Dual-mode (script-callable + sourceable) so consumer hooks can dot-source on Windows (avoids spawning `pwsh` from `powershell.exe` 5.1).
- **`hooks/session-start.sh` + `.ps1`** — read `source` from stdin JSON; gate `git fetch origin` on `startup`/`resume` only (not `clear`/`compact`). Compute behind count vs `origin/<default>` after verifying BOTH refs exist (guards rev-list exit-128). Append a one-line drift warning to `additionalContext` when behind. SessionStart cannot block (exit 2 is advisory only — surfaces as warning string). PowerShell variant uses `Start-Job -ArgumentList $cwd -ScriptBlock { Set-Location -LiteralPath $dir; ... }` for PS 5.1 + emits `$LASTEXITCODE` on success stream so parent gates on actual fetch result, not just `Wait-Job` completion.
- **`commands/new-feature.md` + `commands/fix-bug.md` Pre-Flight** — `# DRIFT-PREFLIGHT-{NEW,ALREADY}-{BEGIN,END}` marker pairs (bash comments inside fenced blocks; byte-identical contract enforced by `test-contracts.sh`). NEW block: track `FETCH_OK`, fetch + behind-check, fast-forward only when on default with clean tree, base worktree from `origin/<default>` (or local `<default>` if fetch failed, or last-resort `HEAD`). ALREADY block: smaller advisory warning when parent default is behind (no auto-FF from inside a worktree).
- **`hooks/check-state-updated.sh:33` + `.ps1:39`** — replaced hardcoded `git merge-base main HEAD` with the lib helper. Bash uses `bash "$LIB"`; PowerShell dot-sources via `. $libPath`.
- **`setup.sh` + `setup.ps1`** — install `hooks/lib/default-branch.{sh,ps1}` to `.claude/hooks/lib/` in downstream repos. Windows installs get BOTH the `.sh` and `.ps1` helpers because the `commands/*.md` Pre-Flight bash blocks invoke `bash "$LIB"` under Git Bash on Windows.
- **`tests/template/test-default-branch.sh` (NEW, 16 assertions)** — 7 bash fixtures + 2 pwsh fixtures cover origin/HEAD set/unset, main/master fallback, no remote, neither-branch bail, detached HEAD.
- **`tests/template/test-session-start.sh` (NEW, 11 assertions)** — source-gating (clear/compact skip fetch), behind detection, fetch-failure silent degrade (uses nonexistent local path so failure is immediate — no DNS stall on hosts without `gtimeout`/`timeout`), `additionalContext` < 2KB, valid JSON output.
- **`tests/template/test-contracts.sh` (3 new contracts)** — no migrated-pattern `main` references in `hooks/*` outside `hooks/lib/` (scope-honest title); DRIFT-PREFLIGHT-NEW + ALREADY blocks byte-identical across `new-feature.md` and `fix-bug.md`.
- **`tests/template/run-all.sh` + `test-lint.sh`** — register the new fixtures + lib files so the canonical drivers actually invoke and parse-check them.
- **`CLAUDE.md`** — File Structure now shows `hooks/lib/`; Template→Generated mapping has 2 new rows; SessionStart hook description calls out source-gating + the cannot-block constraint.

Reviewer findings fixed in-branch (per "NO BUGS LEFT BEHIND"):

- **`set -e + $((0+0))` exit-1 bug** in `check-state-updated.sh` — pre-existing latent bug; removed `set -e` (every external call already has explicit `2>/dev/null` + `|| fallback`).
- **Helper-bail silent fallback** at 6 sites — added breadcrumbs: stderr in `check-state-updated.{sh,ps1}` + `commands/*.md` Pre-Flight; appended to `additionalContext` in SessionStart hooks (the only path that reaches Claude on SessionStart since stderr-on-exit-0 goes to debug log only).
- **`BASE="HEAD"` last-resort warning** in DRIFT-PREFLIGHT-NEW — explicit echo with short HEAD identifier asking user to verify intent.
- **Dirty/diverged tree no longer blocks worktree creation** — `git worktree add` is independent of caller's checkout state, so dirty-tree + diverged-FF are warn-and-proceed (the worktree still bases from `origin/<default>` cleanly).
- **Behind-check + auto-FF gated on `FETCH_OK`** in both NEW and ALREADY blocks — prevents reporting drift against stale `origin/*` refs after fetch failure, and prevents a second network call via `git pull`.
- **`origin/HEAD` stale-rename caveat documented** in `hooks/lib/default-branch.sh` — Method 1 verifies the candidate has a corresponding `refs/remotes/origin/<name>` ref before returning, but a fully stale rename (where the retired remote-tracking ref also survives) requires user-side `git remote set-head origin --auto && git fetch --prune` to refresh the cache. Documented as a known limitation; no network-free heuristic has acceptable false-positive rates.
- **Merge-base fallback chain** in `check-state-updated.{sh,ps1}` — prefer local `<default>` if it exists, else `origin/<default>` (handles single-branch clones), else `HEAD~10`.
- **DIRTY pipefail asymmetry** — added regex guard symmetric with BEHIND; `[[ "$DIRTY" =~ ^[0-9]+$ ]] || DIRTY=0` plus trailing `|| echo 0` for users with `set -o pipefail`.
- **Test gap fixtures added (8 new):** master-default fixture for `check-state-updated.sh` migration; both-`main`-and-`master` local fixture; install-presence assertion; cross-platform drift-warning string parity contract; `TIMEOUT_CMD` empty-path coverage; empty/unknown `source` value fixtures.
- **Comment trims** — removed 3 ephemeral history references in `test-contracts.sh` (Codex anecdote, Council attribution, regression-string history) per comment-analyzer review.

Explicitly out of scope (PR #2 / future work):

- **CONTINUITY.md split** — separating durable project facts from per-developer volatile state.
- **macOS without `gtimeout`/`timeout`** — accepts ~75s degraded-network stall (council-accepted; Maintainer dissent recorded).
- **Audit-log breadcrumb infrastructure** — chairman-deferred per council; PR #1's stderr/additionalContext breadcrumbs satisfy the "non-silent failure" requirement without inventing a logging side-channel.

Suite: 256/256 assertions across 7 bash suites pass (lint 20, fixtures 23, contracts 64, hooks 22, default-branch 16, session-start 11, setup 100). PowerShell parity tests skip on dev hosts without `pwsh`; CI must have it installed.

**Existing installs need `./setup.sh -f`** to pick up `hooks/lib/`, the updated SessionStart hook, the migrated `check-state-updated.sh`, and the new Pre-Flight bash in `commands/*.md`.

## 5.13 — 2026-04-21 · Phase 4 task-DAG dispatch with file-conflict constraints

Replaces the previous Phase 4 one-liner (`/superpowers:executing-plans`) with a structured dispatch plan. Field evidence: user's msai-v2 run (19-task backtest feature) had the orchestrator hand-rolling a 16-wave table from scratch because the template gave no parallelism guidance. Research agent + Codex second-opinion both identified **DAG with continuous dispatch** as the correct primitive over static file-overlap waves; Anthropic's multi-agent research post cited for the `default 3 / max 5` concurrency ceiling.

Council-reviewed (5 advisors, 2 `OBJECT`) and revised before merge. The initial draft shipped five spec-level bugs; all five fixed in the same branch.

- **`commands/new-feature.md` Phase 4** — new structure: optional `/compact` banner, `Trivial plans (≤3 tasks)` carve-out (Pragmatist), mandatory `§4.0 Dispatch Plan` for 4+ tasks (task DAG appended to plan file under `## Dispatch Plan` heading), `§4.1 Execute via subagent-driven-development` with `Handling failures` bullets (Scalability Hawk), `§4.2 Headless / Walk-Away Mode` as opt-in phrase (not a menu item).
- **`commands/fix-bug.md` Phase 4** — mirrored structure; simple fixes (1-2 files) keep single-threaded path; complex fixes (3+) reference `new-feature.md` in the same `.claude/commands/` directory (Maintainer: the initial draft said `commands/new-feature.md` literal, which fails post-install because `setup.sh` copies to `.claude/commands/`).
- **Append-only exception deleted** — the initial draft allowed "new test files, new exports, new-timestamp migrations MAY run concurrently." Three advisors flagged this unsafe: two subagents appending to `__init__.py` or `index.ts` race under concurrent writers; same-second timestamp migrations collide on filename and `alembic_version` head. Same-file writes now always serialize via `Depends on`; the only "concurrent add" case is distinct new files at different paths, which are already disjoint under the standard `Writes` rule.
- **`Writes` column requires concrete file paths** (Maintainer) — not directories, not globs. Example table updated from `alembic/versions/...` (directory-like, contradicted the "same physical file" conflict rule) to `alembic/versions/2026_04_22_add_series.py` (concrete).
- **Scheduling principle now reads "serial is the default; parallel requires proven independence"** — Contrarian's reframe. File-disjointness is necessary but not sufficient; shared types/imports/schemas encode as `Depends on`, not parallel.
- **Docs drift fixed** (Contrarian) — Required Plugins tables in both command files + `docs/reference/commands.md` + `docs/explanation/workflow.md` ASCII diagram now list `/superpowers:subagent-driven-development` as default Phase 4 executor with `/superpowers:executing-plans` demoted to headless mode.

Explicitly NOT shipped (deferred per chairman synthesis):

- **Status/Evidence columns + mid-plan context-budget checkpoint** (Scalability Hawk) — secondary. Would need hook enforcement (like the evidence-based E2E gate) to be load-bearing. Out of scope for this markdown-only revision; revisit if field evidence shows the DAG being ignored or silently failing mid-plan.
- **Concurrency cap enforcement** — `default 3 / max 5` is prose. No hook prevents an over-eager orchestrator from dispatching 8. If this decays into a suggestion on week 3, add a `check-dispatch-plan.sh` gate patterned on `check-workflow-gates.sh`.
- **Revert default to `/superpowers:executing-plans`** (Contrarian) — overruled. Executing-plans hid the same planning ambiguity with less control; subagent-driven-development is a first-class Superpowers skill.

Suite: 233 assertions across 5 bash suites pass. 5 files changed across two commits on the branch (`4c37350` initial + `9d82af8` council revisions).

**Remediation for existing installs:** `./setup.sh -f` to pick up the new Phase 4 content.

## 5.12 — 2026-04-21 · Template-drift notice on `setup.sh -f` / `--upgrade`

Closes the downstream pain path the user surfaced directly: after bumping the harness repo, running `./setup.sh -f` in a pre-existing project didn't warn that `CLAUDE.template.md` had evolved since their `CLAUDE.md` was originally copied. The user only saw `Your CLAUDE.md and CONTINUITY.md were not modified` and had to manually ask Claude to reconcile the template against the local file.

Codex second-opinion pass (5 plan-review iterations + 2 code-review iterations) locked the approach at: **loud notice, no auto-diff, no section-marker merging**. Rejected alternatives: auto-running `git diff` inline during install (noisy on heavily-customized CLAUDE.md) and section-marker-based partial ownership (user file is intentionally freeform).

- **`setup.sh` + `setup.ps1`** — new helper (`print_template_drift_hint` / `Write-TemplateDriftHint`) fired at the CLAUDE.md / CONTINUITY.md preserved-file branches; consolidated reminder block at the end-of-`--upgrade` summary. Both installers capture pre-copy `had_claude_md` / `$hadClaude` booleans so we only claim a file was preserved when this run actually preserved it (fixing a pre-existing bug where the summary lied if the user deleted one of the files before `--upgrade`). Emitted `git diff --no-index` command uses single-quoted paths + `$(pwd)`-absolutized local side so it survives copy-paste across shells and working dirs.
- **Final-summary line** now has four boolean-gated variants (both preserved / only CLAUDE / only CONTINUITY / neither). The legacy hardcoded `were not modified` is gone.
- **`tests/template/test-setup.sh`** — Test 8 extended with CONTINUITY.md sentinel + hash check + drift-notice assertions + first-install regression guard; new Test 10 (Scenarios A/B/C) covers the asymmetric preservation matrix (CLAUDE deleted, CONTINUITY deleted, both deleted). Suite grows from 75 → 100 assertions in test-setup.sh.
- **`tests/template/test-contracts.sh` Contract 7** — template-drift parity gate. Asserts both installers ship (i) the user-facing `Template may have drifted` string, (ii) both template filenames, (iii) `git diff --no-index`, (iv) exact call-site fingerprints like `print_template_drift_hint "CLAUDE.template.md" "CLAUDE.md"` (closes the dead-helper / missing-callsite loophole), (v) all three positive final-summary variants + negative guard against the legacy `were not modified` string. Contract 7 is the only Windows safety net — bash tests can't execute PowerShell — so variants must exist literally in both files.

Suite: 179 → 223 assertions across 5 bash suites, ~5s local run.

Explicitly NOT shipped (scope discipline, deferred per Codex iter-1 plan review):

- **`--global` / `GLOBAL-CLAUDE.template.md`** — currently goes through `copy_file` which overwrites. Adding drift notice there would first require deciding whether `~/.claude/CLAUDE.md` should become user-owned. Separate policy question, separate PR.
- **Auto-diff rendering** in the installer — Codex recommended deferring behind an opt-in `--show-template-diff` flag if demand emerges. Noisy by default on heavily-customized CLAUDE.md.
- **Path-apostrophe escape in emitted `git diff` command** — P3 from code review iter 2 (project path like `Client's Repo` would break single-quoting). Fixing properly requires `printf %q` (bash) + `EscapeSingleQuotedStringContent` (PowerShell); real overkill for a diff suggestion string. Out of scope.

**Remediation for existing installs:** `./setup.sh -f` to pick up the notice. The notice fires inside the existing-file branch which runs any time `CLAUDE.md` / `CONTINUITY.md` already exist — no new flags needed.

## 5.11 — 2026-04-20 · ARRANGE rule — close the E2E actor-boundary gap via text layer

Closes the MSAI field-testing gap where Claude ran `docker exec postgres psql -c "INSERT INTO ..."` during E2E setup, bypassing the ARRANGE rule. When the user caught it, Claude "backed out" with a raw `DELETE` (compounding the violation) and had also sidestepped a real bug in the sanctioned CLI path (violating NO BUGS LEFT BEHIND in the same flow).

**Council verdict on path forward** (5 advisors + Codex chairman, Contrarian reframe decisive): the failure is a rule-text + actor-boundary problem, not a command-detection problem. Ship text-layer fixes; shelf the shell-regex hook.

- **`rules/critical-rules.md:9`** — E2E TESTING bullet now names ARRANGE explicitly with concrete forbidden examples (`psql -c "INSERT"`, `mysql -e "UPDATE"`, `mongosh --eval`) and ties to NO BUGS LEFT BEHIND. Previously only mentioned "No cheating in VERIFY" — silent on ARRANGE, the phase that was actually violated.
- **`rules/testing.md:176`** — the sentence "This principle applies strictly to the VERIFY phase, **not** the ARRANGE phase" was a direct contradiction of the forbidden list immediately below. Rewritten: ARRANGE has flexibility about _which_ sanctioned interface to use, but not permission to sidestep them. Raw DB writes, internal endpoints, and file-injection are forbidden in both phases.
- **`agents/verify-e2e.md` Critical Constraint #2** — was "ARRANGE may use sanctioned setup paths"; now explicitly forbids raw DB writes and tells the agent to report FAIL_INFRA on broken sanctioned paths rather than routing around them.
- **`commands/new-feature.md` + `commands/fix-bug.md` Phase 5.4** — new phase-local ARRANGE-boundary reminder for the main agent _before_ verify-e2e dispatch. The Contrarian's actor-boundary insight: the cheat happened in the main session, not the subagent; bind the main agent to the same rule at the exact moment the behavior is decided.

5 files changed, 7 insertions, 3 deletions.

Explicitly NOT shipped — shell-regex PreToolUse hook:

- **v1** (stderr WARN): wrong output channel — per Anthropic docs, `PreToolUse` stderr only reaches Claude on exit 2; exit 0 drops stderr silently.
- **v2** (stdout JSON + pinned-start regex): still had greedy `.*` false positives on `SELECT ... '%INSERT%'` literals.
- **v3** (anti-FP guards): Guard 2 (quote-prefix rejection) introduced a new false negative on `docker exec pg bash -lc "psql -c \"INSERT\""` — the hook would have FAILED to catch a near-variant of the motivating MSAI cheat. Still had persistent false positives on `python -c`, `jq`, `curl -d` payloads where `psql` appears as a string literal.

Three rounds of polish traded one gap for another — the Scalability Hawk's original OBJECT was vindicated. Archived v3 plan + full council reasoning in `docs/plans/2026-04-20-arrange-rule-enforcement-plan.md` (gitignored). Revisit only if the text layer fails in field testing, and only with a different primitive (audit-log-only telemetry, Stop-hook phase-scoped reminder, etc. — **not** a PreToolUse shell-regex).

## 5.10 — 2026-04-18 · Evidence-based E2E gate (Phase 2 of the enforcement cycle)

Closes the Contrarian's deferred P0 from the 5.9 Council session: the paperwork-only gate let a bad-faith operator type `[x] E2E verified` without actually running the verify-e2e agent. Phase 2 binds the checkbox claim to a real filesystem artifact.

Motivation: user observed downstream sessions attempting `gh pr create` before code reviews, simplify, or E2E were actually done — Claude was checking boxes prematurely and the 5.9 checklist-only gate couldn't catch it.

- **Evidence check in `check-workflow-gates.sh` + `.ps1`**. When `- [x] E2E verified` is present WITHOUT an `N/A:` suffix, the hook now requires a file in `tests/e2e/reports/` whose mtime is later than the branch-off commit (`git merge-base HEAD main`, falling back to `master`). Without a fresh report: exit 2 with a specific "checkbox is typed but no report was produced" error. The N/A escape (`- [x] E2E verified — N/A: <reason>`) still bypasses the check.
- **Cross-platform mtime**: `stat -c %Y` for GNU, `stat -f %m` for BSD/macOS. PowerShell uses `LastWriteTime` against a UnixTime-derived `DateTimeOffset`. Detected at runtime.
- **Graceful degradation**: user on `main`, repo with neither `main` nor `master`, or missing git history → evidence check skipped. The checklist check still fires. Documented as degraded env, not policy violation.
- **`rules/testing.md`**: new "Evidence-based gate" subsection under "Canonical E2E gate vocabulary" explaining the two-phase check + degradation behavior.
- **`tests/template/test-hooks.sh`**: 8 new assertions (5 scenarios) exercising the evidence check — fresh report → 0, no report → 2 + stderr, stale report only → 2, N/A bypass → 0, degraded env (no main/master) → 0. Each scenario builds a real scratch git repo with a branch-off point to give the hook something to compare against.

Suite: 170 → 178 assertions, all pass.

Explicitly still NOT covered by evidence check:

- **Code review loop**, **Simplified**, **Verified (tests)** — these gates still use the paperwork-only check. They have no natural filesystem artifact convention yet. Adding them would require agents/commands to persist status files, which is a separate design pass.
- Report quality — only file existence + freshness is verified. A trivial report that claims PASS on no actual UCs still passes. Human reviewer catches this.

## 5.9 — 2026-04-18 · E2E verified gate — close the silent-skip loophole

Closes the loophole the Engineering Council flagged: before this release, `check-workflow-gates.sh` blocked commit/push/PR on `Code review loop` / `Simplified` / `Verified (tests`, but NOT on `E2E verified`. A downstream project (msai-v2) shipped 155 commits with every E2E checklist item unchecked. Council verdict (5 advisors + Codex chairman): ship narrow enforcement, canonicalize marker vocabulary in the same PR, defer operator-verification redesign.

- **`E2E verified` added to the gated markers** in `hooks/check-workflow-gates.sh` and `.ps1`. An active workflow with `- [ ] E2E verified` now blocks `git commit`, `git push`, and `gh pr create` with exit 2. The gate accepts either the checked-passing form (`- [x] E2E verified via verify-e2e agent (Phase 5.4)`) or the documented N/A escape (`- [x] E2E verified — N/A: <reason>`).
- **Canonical marker vocabulary** — `rules/testing.md` now has a "Canonical E2E gate vocabulary" section naming the exact stem (`E2E verified`) and N/A form. The old drifting string `E2E use cases tested — N/A` in the rules has been unified to match the hook + workflow commands.
- **Remediation message** — both hooks now print specific next-step commands when gates fail: `/codex review`, `/simplify`, `verify-app` agent, `verify-e2e` agent, plus the N/A format. Points at `rules/testing.md` for the full contract.
- **`tests/template/test-hooks.sh`** — new fixture-driven suite (13 assertions) feeding synthetic CONTINUITY.md into the hook and asserting exit codes: all checked → exit 0, E2E unchecked → exit 2 + correct stderr, E2E N/A → exit 0, non-ship command → always 0, inactive workflow → always 0, near-miss items (PR reviews addressed, Plan review loop, E2E use cases designed) NOT gated, PowerShell parity (skipped without pwsh).
- **`test-contracts.sh` Contract 6** — cross-file marker consistency: the exact stem `E2E verified` must appear in both hooks, both workflow commands, and `rules/testing.md`. The N/A form uses em-dash (—) literally, contracted across all files.

Suite grows 147 → 170 assertions, all pass on this branch.

Explicitly NOT in this PR (Council deferred):

- Operator-driven verify-e2e mode (contradicts current ARRANGE/VERIFY boundary; needs its own design pass)
- Non-fullstack guard reading `interface_type` from CLAUDE.md (acceptable risk for now — N/A escape handles library/CLI-only projects)
- Evidence-based gating that checks for an actual `tests/e2e/reports/*.md` artifact (larger contract change)
- CI activation via `setup.sh --with-ci` (separate PR)
- Structured HTML-comment marker anchors for drift immunity (deferred to hardening pass)

## 5.8 — 2026-04-18 · Multi-project interpreter preflight + isolation guide

Handles the "I work on 5 projects with different Python/Node versions" case. Recommendation came from a 5-advisor Engineering Council session with Codex chairman synthesis.

- **`docs/guides/multi-project-isolation.md`** — canonical doc explaining the `uv` + `pnpm` dependency-isolation model, why the harness does NOT switch interpreter binaries for you, and which version managers to use (`uv python install`, `pyenv`, `fnm`, `nvm`, `volta`). Linked from `docs/getting-started.md` and `docs/guides/parallel-sessions.md`.
- **Warn-only preflight in `setup.sh` + `setup.ps1`** (before `Prerequisites OK`). Reads repo-root `.python-version`, `.nvmrc`, and root `package.json` `engines.node`. Prints a warning with install guidance if the declared runtime is unavailable. **Never changes exit code.** Silent when no pins exist. Detection checks in order: `uv python list` → `pyenv versions` → `python3.MAJOR.MINOR` → `python3 --version` match for Python; `node --version` major match → `fnm`/`nvm`/`volta` listings for Node.
- **Explicitly NOT shipped** per Council minority-report resolution: no session-start hook check (wrong layer), no `verify-app` preamble (another policy surface before installer/doc contract is settled), no subdir detection (monorepo pattern deferred), no silence flag (remove pin file to disable per-project).
- **Test suite grows 119 → 143 assertions.** `test-setup.sh` adds 4 scenarios (impossible Python version, impossible Node version, no pins → silent, matching version → green). `test-contracts.sh` adds a shell/PowerShell parity contract asserting both installers reference the same files and canonical guide.

## 5.7 — 2026-04-18 · Template self-test suite

Fast local regression protection for template changes — avoids the prior commit-push-merge-install-in-downstream-repo loop.

- **`tests/template/`** — 4 bash suites, 111 assertions, runs in ~5 seconds via `bash tests/template/run-all.sh`. Zero external dependencies beyond bash + jq.
- **test-setup.sh** (39 assertions) exercises `setup.sh --with-playwright` against flat, monorepo (`frontend/`), multi-candidate, `--playwright-dir` override, and `apps/r&d` metachar layouts. Covers idempotency (hash-based), `-f` force-refresh, and `--upgrade` smoke. The metachar test confirms PR #482's bash-parameter-expansion fix for the `&`-substitution bug.
- **test-fixtures.sh** (23 assertions) fingerprints template content: branding leak, trace/video CI security default, cookie-auth default with block-comment-aware check for the insecure `localStorage` pattern, verify-e2e response header, post-tool-format monorepo walk-up, prd/create.md fence balance.
- **test-contracts.sh** (23 assertions) cross-file consistency: every VERDICT value in `verify-e2e.md` is consumed by `new-feature.md` + `fix-bug.md` and vice versa, SUGGESTED_PATH is honored, `.claude/playwright-dir` marker has both a writer (setup.sh / setup.ps1) and readers (command docs), `__PLAYWRIGHT_DIR__` placeholder is handled in both shell and PowerShell.
- **test-lint.sh** (26 assertions) `bash -n` on every shell script, `pwsh` parse on `.ps1` files (skipped without pwsh), `jq empty` on JSON templates, placeholder-coverage check.

## 5.6 — 2026-04-17 · Template monorepo support + Playwright security fixes

Batch fix for 9 Copilot findings surfaced in a downstream user project (mcpgateway) plus 4 related "missed" items from a Codex review. All are template-level bugs — downstream users pick them up via `setup.sh --upgrade`.

- **Monorepo-aware Playwright scaffolding.** `setup.sh --with-playwright` now supports `--playwright-dir <path>` override and auto-detects `frontend/`, `apps/web/`, `web/`, `client/` when exactly one candidate has `package.json`. Multi-candidate falls back to repo root with a warning. Scaffolded CI workflow has the detected path stamped into `working-directory`, `cache-dependency-path`, and `upload-artifact` so monorepo installs work out of the box.
- **Playwright security hardening.** Default `trace` and `video` to `off` on CI (opt-in via `PLAYWRIGHT_CI_TRACE=1` / `PLAYWRIGHT_CI_VIDEO=1`) to prevent credential leaks via `storageState`-captured artifacts. Auth fixture now uses cookie/session login as the active default; the insecure API-key-in-localStorage path is demoted to a commented "LOCAL DEV ONLY" block with a security warning.
- **`verify-e2e` agent read-only contract fixed.** Agent frontmatter declared no Write tools but Step 5 instructed it to write markdown to `tests/e2e/reports/`. Agent now returns a structured `VERDICT: / SUGGESTED_PATH: / --- / <body>` response; main agent parses and persists. `commands/new-feature.md` and `commands/fix-bug.md` Phase 5.4 updated accordingly.
- **`post-tool-format` hook monorepo-aware.** Walks up from the edited file to find the nearest `pyproject.toml` instead of assuming `$CLAUDE_PROJECT_DIR/src`. Restores `ruff check --fix` (was silently dropped) and decouples it from `ruff format` so a lint failure doesn't skip formatting. Mirrored in `.ps1`.
- **`commands/prd/create.md` fence nesting.** Repaired misplaced four-backtick close that was ejecting Appendix B from the PRD template, plus three orphan triple-backticks at end of file.
- **`playwright.config.template.ts` header.** Removed "claude-codex-forge" from the docblock — template was leaking its own name into downstream projects' code.
- **Workflow commands monorepo-aware.** `commands/new-feature.md` and `commands/fix-bug.md` Pre-Flight dep install now iterates over common frontend/backend subdirectories instead of only checking repo root. Phase 5.4b framework detection locates `playwright.config.ts` across the same subdirectory set.
- **Docs sync.** `agents/verify-app.md`, `CLAUDE.template.md`, `rules/testing.md`, `templates/playwright/README.md`, `docs/guides/playwright-ci-bridge.md` updated to reflect the new `<pw-dir>` pattern and cookie-auth default.

## 5.5 — 2026-04-17 · E2E enforcement + research-first + repo rename

- **`verify-e2e` agent** — dedicated subagent for user-journey E2E through API/UI/CLI, accumulated regression suite in `tests/e2e/use-cases/` (PR #449).
- **Playwright CI bridge** — `--with-playwright` setup flag scaffolds `playwright.config.ts`, auth fixture, specs dir, and reference GitHub Actions workflow (PR #450).
- **`research-first` agent** — Phase 2 of `/new-feature` queries Context7/official docs/changelogs before design, producing structured briefs in `docs/research/` (PR #472).
- **Repo renamed** from `claude-code-templates` → `claude-codex-forge`.
- **README rebrand + restructure** — repositioned as "engineering harness powered by two coding agents" (PR #473); split into `docs/` tree with trailhead README (PR follows).
- **Codex skill flag reference** — added complete flag reference and powerful `-c` config overrides to `/codex` skill (PR #474).

## 5.4 — 2026-03-31 · Engineering Council

Multi-perspective decision analysis inspired by Karpathy's LLM Council. 5 engineering advisors (3 Claude + 2 Codex) with Codex chairman. Contrarian gate validates approach selection (no self-certification). Auto-triggers during `/new-feature` and `/fix-bug` brainstorming when genuine ambiguity detected. Configurable advisor profiles. Mandatory minority reports preserve dissent.

## 5.3 — 2026-03-01 · Silent context injection

SessionStart hook now uses `hookSpecificOutput.additionalContext` for clean, non-visible branch injection. Fires on all 4 events (startup, resume, clear, compact). External script replaces inline echo.

## 5.2 — 2026-02-20 · Frontend design

Added `frontend-design` plugin (built-in) and `rules/frontend-design.md` for TypeScript/fullstack projects — typography, color, spacing, responsive, accessibility, animation standards. Documented optional MCP add-ons (Vercel, Next.js DevTools).

## 5.1 — 2026-02-19 · CLAUDE.md split

Slimmed CLAUDE.md to ~50 lines (user-owned: project description, tech stack, commands). Moved workflow, principles, worktree policy, critical rules, and memory instructions to `.claude/rules/` files that are auto-loaded and safe to overwrite on updates. Following official best practice of keeping CLAUDE.md under 60-100 lines.

## 5.0 — 2026-02-19 · Removed Compound Engineering

Replaced with built-in Claude Code quality gates (`/review-pr-comments`, `/pr-review-toolkit:review-pr`, `/codex review`). E2E testing via standalone Playwright MCP. Knowledge compounding via `docs/solutions/` + auto memory. Only Superpowers remains as third-party plugin. Added standalone MCP servers (Playwright, Context7) to project settings.

## 4.0 — 2026-02-19 · Persistent memory

Added global memory system (`--global` flag), PreCompact hooks to save learnings before context compression, global Stop hook for memory reminders, `~/.claude/CLAUDE.md` template with memory instructions. Inspired by OpenClaw's pre-compaction memory flush pattern. Auto memory enabled by default.

## 3.4 — 2026-02-16 · Codex command

Added `/codex` command for getting second opinions from OpenAI's Codex CLI. Code review and general feedback modes.

## 3.3 — 2026-01-22 · Finish-branch command

Added `/finish-branch` command that handles PR merge + worktree cleanup. Removed `/superpowers:finishing-a-development-branch` from workflows (redundant testing, no worktree awareness). `/quick-fix` now just commits directly.

## 3.2 — 2026-01-19 · Simplified worktrees

Claude now `cd`s into worktrees instead of using path prefixes. Removed `.session_worktree` file — no shared state between sessions. Hooks and verify-app simplified to use current directory.

## 3.1 — 2026-01-19 · Parallel development

Workflow commands auto-create git worktrees for isolated parallel sessions. Hooks are worktree-aware. verify-app agent accepts worktree path.

## 3.0 — 2026-01-18 · Workflow commands

Added `/new-feature`, `/fix-bug`, `/quick-fix` commands that contain full workflows. Refactored CLAUDE.md to be lean (140 lines vs 318). E2E via Playwright MCP.

## 2.7 — 2026-01-18

Simplified CONTINUITY.md: Done section keeps only 2-3 recent items, removed redundant sections (Working Set, Test Status, Active Artifacts). Leaner template.

## 2.6 — 2026-01-18

Hooks follow Anthropic best practices: path traversal protection, sensitive file skip, `$CLAUDE_PROJECT_DIR` for absolute paths. Added external post-tool-format.sh script.

## 2.5 — 2026-01-17

E2E testing via Playwright MCP. Removed E2E from verify-app agent.

## 2.4 — 2026-01-17

Knowledge compounding now uses `docs/solutions/` instead of inline CLAUDE.md learnings. Searchable files with YAML frontmatter, auto-categorized by problem type.

## 2.3 — 2026-01-17

Enhanced workflow with Superpowers skills: systematic-debugging, verification-before-completion. Updated Stop hook checklist.

## 2.2 — 2026-01-17

Fixed MCP permissions — wildcards don't work, use explicit server names.

## 2.1 — 2026-01-11

Added native Windows/PowerShell support — hooks now work without jq on Windows, platform-specific settings templates.

## 2.0 — 2026-01-10

Added code-simplifier, verify-app agent, SubagentStop hook, prompt-based Stop hook, project-agnostic templates, clear setup scenarios.

## 1.0 — 2026-01-02

Initial setup with Superpowers.
