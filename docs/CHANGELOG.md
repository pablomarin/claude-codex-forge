# Changelog

All notable changes to claude-codex-forge.

## 5.45 — 2026-06-01

**Fix `setup.sh` / `setup.ps1` silently aborting when run in-place (forge dogfooding).** `copy_file` (and PowerShell `Copy-TemplateFile`) did a bare `cp`/`Copy-Item` with no same-file guard. Run in-place (`SCRIPT_DIR` == repo root, e.g. a maintainer dogfooding via `./setup.sh --upgrade` in the forge repo), the docs/adr seed copies resolve source and destination to the **same file** — `cp X X` errors "are identical" with a non-zero exit, and `set -e` (setup.sh:7) aborts the whole installer **before** the rules sync ever runs, so `rules/`/`commands/` never refresh into `.claude/`. Fix: a self-copy guard in the shared copy helper — bash `[[ -e "$dest" ]] && [[ "$src" -ef "$dest" ]]` (true inode identity), PowerShell `Resolve-Path … -ceq` (case-sensitive path identity; a true inode check needs PS 7.1+ `ResolveLinkTarget`, absent on the 5.1 floor per ADR 0002 — sufficient since the repo's copies are plain files). Placed before the force/exists branches so it short-circuits even under `-f`/`-Upgrade`. TDD: a regression test extracts the real `copy_file` and exercises a self-copy under `set -e` (failed before the guard, passes after); a `pwsh`-gated parity test covers `Copy-TemplateFile`. Codex-reviewed (2 iterations to clean) + pr-review-toolkit (1 P2 fixed: the PS guard had no test). Full suite 771 green (11 suites). Also documents the gotcha that piping a `set -e` script to `tail` masks the failing exit via `PIPESTATUS`.

## 5.44 — 2026-06-01

**Add a "Ground Your Claims" behavioral non-negotiable.** New rule requiring epistemic honesty: state what you verified vs. what you're inferring and say which, cite `file:line` before asserting about code, run behavior before claiming it works, and say "I haven't checked X" instead of guessing fluently — _"Confident guessing is a defect, the same caliber as a known bug left behind."_ Ships across its three copies, mirroring the existing **No Bugs Left Behind** pattern: a caps bullet in `rules/critical-rules.md` (sibling of `CHALLENGE ME` / `NO BUGS LEFT BEHIND`), a headline `## Ground Your Claims Policy` section in `CLAUDE.template.md`, and a `## Ground Your Claims` global default in `GLOBAL-CLAUDE.template.md`. A new `test-contracts.sh` parity contract binds the three copies on a case-insensitive title stem + the exact link phrase, so an edit to one fails CI until the others follow (the contract caught its own caps-vs-Title-Case bug on first run). Rationale, grounded in this session's research on evaluation-awareness / accountability framing: a prose rule is a **weak tier-1 lever** that decays in large context windows — its value is expectation-setting and giving the developer vocabulary to flag ungrounded answers; the durable enforcement remains the human + Codex review loop, not the line. Docs + 1 contract assertion; full template suite 775 green.

## 5.43 — 2026-05-28

**Close the workflow-gate integrity hole + fix 4 sibling bugs in `check-workflow-gates.{sh,ps1}`.** A docs-only checkpoint commit mid-workflow used to force marking the 4 ship gates `- [x] N/A`, which permanently satisfied them with nothing to re-open them — so the later real-code ship could pass with **no review evidence**. Fix: a **no-code carve-out** — a `git commit` that stages ONLY documentation skips the code-quality gates for that commit **without mutating `state.md`** (the boxes stay `- [ ]`, so the real-code commit and the push/PR gate still enforce). The docs predicate is path∩extension (curated doc filenames anywhere + prose extensions `.md/.mdx/.markdown/.rst` under a `docs/` dir); everything else is code (so this repo's own `commands/*.md`, `rules/*.md` stay gated). Fail-safe throughout: any non-doc path, or an `-a`/`--amend`/`-p`/`-i`/`-o`/interactive commit mode (whose content isn't in the staged diff) → enforce. Scoped to `git commit`; push/PR always enforce, and because state is never mutated, any commit-time under-gating is caught at push/PR. Sibling fixes: **(a)** PASS-before-N/A ordering so a stale `N/A:` line can't mask a real `(N iterations) — PASS` evidence requirement; **(b)** a malformed checked loop line (`- [x] Code review loop` with neither PASS nor N/A) now blocks instead of silently passing; **(c)** PowerShell E2E-scan parity (scoped to the `### Checklist` + anchored match, matching the `.sh`); **(d)** repo-context resolution via the trustworthy stdin `cwd` + `git rev-parse --show-toplevel` (worktree/subdir-correct) instead of the hook's raw process CWD — `-C` is no longer parsed from command text (unsafe to do with regex). Review hardening: command-separator normalization (real **and** literal `\n`/`\r`) runs before ship detection, so newline-separated ship chains in a single tool call are caught by the compound guard. Includes the companion anchored-unchecked-probe hotfix (PR #779). +24 `test-hooks.sh` assertions + 6 `test-contracts.sh` parity assertions; full suite 731 green. Codex-reviewed (5 iterations to CLEAN) + pr-review-toolkit (no P0/P1).

## 5.42 — 2026-05-27

**Document how `/codex` mode selection works** (FAQ developers were asking). Clarifies the premise: Codex doesn't pick the mode — Claude does, from your request. The hermetic modes (Code Review / Design Review / General) are keyword/context-routed; Investigate is **capability-routed, not keyword-triggered** (Claude enters it only when the task needs credentials / network / external systems / live data / execution, so a plain "review this" never silently escalates to live access). Improves existing docs only — adds a routing note above the `/codex` modes table in `docs/reference/commands.md` and expands the "How it triggers — and who chooses" section of `docs/explanation/codex-investigate.md`. No new files; docs-only.

## 5.41 — 2026-05-27

**Document autonomous goal mode and Codex Investigate mode as first-class features.** Both shipped (v5.29 / v5.40) but lived only in the version-history table — a reader of the README would never know they existed. Now surfaced as headline capabilities: two new **"What you get"** bullets, two **"How it works"** links, two **Documentation**-table rows, and two new explainer docs — `docs/explanation/autonomous-goal.md` (optional + PRD-gated; Council decides without intervention; PR creation is the one human gate; **watch-and-steer by typing in the prompt** in both `/goal` and manual modes; the developer owns a bulletproof PRD) and `docs/explanation/codex-investigate.md` (why review-mode Codex can't run queries; how Claude provisions it with live-system access; why it's safe — repo-confined sandbox, never `danger-full-access`, read-only, cross-verified; works inside `/goal`). `docs/reference/commands.md` gains a `/codex` modes table (incl. Investigate, previously undocumented) and an autonomous-`/goal` subsection. Docs-only release.

## 5.40 — 2026-05-27

**Add a Codex Investigate mode (`/codex` Section D) + `/council` live-state fact-finding.** Lets Claude provision Codex as a peer **investigator** with the project's real (read-only) credentials + network — so Codex can dig into live systems (DB / cloud / API) instead of reading code in a hermetic sandbox vacuum. Mechanism is project-agnostic: Claude equips Codex from whatever this repo already uses (MCP server, project CLI, or an `.env`-sourced runner). Three non-negotiable constraints: (1) **repo-confined Codex sandbox** (`--sandbox workspace-write` + `-C "$(pwd)"`, never `danger-full-access`) — the boundary is the sandbox, NOT prompt text, because Codex may be prompt-injected by the data it inspects; (2) **never prompt the user** — Claude provisions Codex from credentials it already holds (lateral, not a new escalation), so it runs autonomously inside a `/forge-goal` `/goal` session where `AskUserQuestion` is reserved solely for PR creation; (3) **read-only / never mutate** — investigation never changes things; mutation is implementation, routed through `/new-feature`/`/fix-bug`. Findings must be **independently cross-verified** by Claude (evidence packet → independent reproduction) before they are trusted. Gated by **capability-need, not task-type**. Decision recorded in ADR 0007 (which also indexes the previously-missing ADR 0006). Pure prompt change — no new machinery; reuses the gitignored in-repo write surface and the existing `.env` credential convention. Accepted residual for the single-user/local threat model: read-only + network + creds still carries credit-burn / prompt-injection-via-data / network exposure (Claude already carries the identical exposure).

## 5.39 — 2026-05-26

**Enforce per-iteration clean evidence for Plan review + Code review loops.** The `check-workflow-gates` PreToolUse hook now blocks ship actions when `- [x] Plan review loop (N iterations) — PASS` or `- [x] Code review loop (N iterations) — PASS` is checked in state.md without matching per-iter clean lines for iteration N. Plan review binds to plan-file sha256 (`plan_sha`); code review binds to current HEAD. **Codex is mandatory** (this repo is Claude × Codex dual-engine) — there is no codex-unavailable auto-escape; the only ship escape is an N/A justification on the loop line (`- [x] Plan review loop — N/A: <reason>`), mirroring the existing E2E `N/A:` gate and caught by a human at PR review. `build-evidence` does NOT count N/A as clean evidence, so a `/forge-goal` autonomous run cannot self-complete without real Codex evidence — if Codex is unavailable, `/goal` halts and a human takes over. Also hardens the hook: CRLF-encoded state.md no longer silently bypasses gates (strips `\r` before the `## Workflow` anchor; ships a `.gitattributes`), and compound ship commands (`git commit && git push`, including leading-nonship chains like `git status && git commit && git push`) are blocked so an unreviewed HEAD can't be shipped past the gate. `build-evidence` emits a new `plan_review_gate` field in FORGE_GOAL_EVIDENCE alongside the existing `reviewer_gate`, and the `/goal` completion predicate now requires `plan_review_gate.clean_same_iteration=true`. Closes the same-iteration-clean shortcut surfaced by the msai-v2 v5.38 /goal run (iter-6 had 2 P1 still pending; agent ticked PASS and skipped iter-7).

## 5.38 — 2026-05-25 · Whole-UC NOT_USER_JOURNEY + stale-text cleanup

Codex final-pass on v5.34–v5.37 found one structural enforcement gap plus three stale-text sites. All addressed.

**Structural fix — NOT_USER_JOURNEY broadened to whole-UC shape.** Codex demonstrated a real escape route in v5.37: an old UC with a decent-looking Intent (e.g., "Customer creates an order through the API") could still slide through regression mode if its Steps are a single isolated call, Verification is bare status, and Persistence is N/A. The individual hard gates (`TOO_SHALLOW`, `THIN_VERIFICATION`, `MISSING_PERSISTENCE`) are skipped in regression to avoid retroactive breakage — but the _combination_ of all three is "this isn't a journey at all", and that signal should fire in every mode.

`agents/verify-e2e.md` judgment-call #7 now has TWO triggers:

- **(a) Intent shape** (existing) — RED FLAG on code-shaped Intent text.
- **(b) Whole-UC shape (NEW)** — RED FLAG when Steps are shallow AND Verification is bare AND Persistence is N/A or absent, all three together. Either trigger fires `NOT_USER_JOURNEY` in any mode (including regression/smoke). Includes a worked example showing the kind of UC this catches.

This is the structural enforcement that delivers Pablo's stated intent of v5.37: legacy code-shaped UCs SHOULD be surfaced by the regression suite so they get rewritten. Without the whole-UC trigger, only the most obviously code-shaped Intents got caught.

**Stale-text fixes (Codex final-pass):**

- **`rules/testing.md` Failure Classification table** — was out of sync, listing `FAIL_INVALID_USE_CASE` as having only `NOT_USER_JOURNEY` / `WRONG_INTERFACE`. Now enumerates all 9 reason codes, grouped into Hard-SHAPE reasons (skipped in regression by v5.35) and Judgment-call reasons (fire in all modes by design).
- **`rules/testing.md` NOT_USER_JOURNEY definition** — said the trigger included "no Persistence step", which contradicted the agent (missing persistence is `MISSING_PERSISTENCE`, a hard gate). Corrected.
- **`commands/fix-bug.md:819` simple-fix parenthetical** — still listed the old 6 fields. Now lists all 8 (Actor + Scenario + Interface + Intent + Setup + Steps + Verification + Persistence).

**Tests** — Contract 2f extended with 13 new assertions: rules/testing.md lists all 7 v5.34 reason codes by name + uses the Hard-SHAPE / Judgment-call bucket vocabulary; negative-guard ensures the stale "no Persistence step" wording can't drift back; verify-e2e.md states the whole-UC shape trigger + mode-by-design intent. **392 total** across 4 hot-path suites, 0 failed.

**What we deliberately did NOT do** from Codex's pass: the vocabulary-layering simplification (collapse mechanical/policy/hard-shape/judgment into 2 buckets instead of the current 4). Reshuffling would churn the same files we just stabilized; current layering is dense but defensible, and contract tests lock it.

## 5.37 — 2026-05-25 · Reframe: legacy-UC bounce-back is intentional design

Pablo's clarification on v5.36: the residual-risk framing ("NOT_USER_JOURNEY can still fire on legacy regression UCs — that's a side effect of v5.35's mode gating") undersells what's happening. The intent is the opposite of residual: when the regression suite encounters an old code-shaped UC, the journey-quality bounce-back **should** fire so the team can rewrite it to the new standard. The point of pulling forward old bad UCs is that they were testing the wrong thing all along.

**Changes (wording only, no behavior change):**

- **`commands/new-feature.md` + `commands/fix-bug.md` Phase 5.4b** — promoted the `FAIL_INVALID_USE_CASE` regression-mode entry from a one-liner to a two-bullet split. **Hard-SHAPE reasons** (skipped in regression by v5.35) and **Judgment-call reasons** (`NOT_USER_JOURNEY`, `WRONG_INTERFACE`) are now explicitly named buckets. The judgment-call bullet states bluntly: "**DO fire in regression mode by design**" — old bad UCs surfaced this way are real finds, not noise.
- **`agents/verify-e2e.md`** Step 2b — mirror note added below the v5.35 mode-gating paragraph: the judgment calls fire in `regression` and `smoke` modes by design (v5.37). Pre-valid bias still applies to borderline phrasing; blatantly code-shaped Intents still get classified `FAIL_INVALID_USE_CASE` in any mode.

**Tests:** Contract 2f updated to lock the new bucket vocabulary (`Hard-SHAPE reasons` / `Judgment-call reasons` / `DO fire in regression mode by design`). 6 assertions added, 378 total across 4 hot-path suites, 0 failed.

## 5.36 — 2026-05-25 · Codex review fixes to v5.34/v5.35

Codex assessment of v5.34 + v5.35 was mostly positive ("strong improvement, not a complete cure" — `927675b` and `6983a39` will materially move Pablo's user-journey-quality concern) but flagged five concrete fixes. All applied:

- **Stale 6-field intro lines.** Both commands had a now-contradictory sentence saying "Each UC must include **Intent**, **Interface**, **Setup**, **Steps**, **Verification**, and **Persistence**" — directly above the new 8-field required-shape checklist that added Actor + Scenario. Updated both intros to name all 8 fields.
- **"in this order" rigidity.** Dropped from both Phase 3.2b required-shape headings. Field order doesn't improve user-journey quality; it just creates formatting friction.
- **`Persistence: N/A` escape hatch.** Tightened in both `rules/testing.md` and `agents/verify-e2e.md` Step 2b to a narrow whitelist: only genuinely stateless outcomes (pure read-only query, idempotent stateless computation). Any UC whose Steps include create/update/delete/transition gets `MISSING_PERSISTENCE` regardless of justification text. Catches the "N/A — fix doesn't change state" / "N/A — this is a read endpoint" excuses Codex called out.
- **"Objective" claim softened.** Added a "Mechanical vs policy gates" note acknowledging that `SCENARIO_FLUFF`, `CHEAT_SETUP`, and the non-bare arm of `THIN_VERIFICATION` require judgment. They still block in feature mode (no functional change), but the docs no longer claim all hard gates are auto-detectable. Failure rationale must point at specific UC text, not a vibe.
- **Phase 5.4b regression-mode wording.** Both commands now say "hard SHAPE gates" (not "hard gates") and explicitly call out that `NOT_USER_JOURNEY` / `WRONG_INTERFACE` (judgment calls) still fire in regression mode. v5.35's mode-gating only protects against the new shape requirements, not the older journey-shape check.

**What we deliberately did NOT do** from Codex's review: chase the "lazy compliance loophole" further. An agent that writes `Scenario: They need to create an order and confirm it works` to satisfy the field requirement is hard to detect without crossing into parody. v5.34+v5.35+v5.36 is a 70% solution to the user-journey-quality problem; further hardening has diminishing returns.

**Files:**

- `rules/testing.md` — narrow Persistence: N/A whitelist with allowed/disallowed examples
- `agents/verify-e2e.md` — Mechanical vs policy gates note; narrow Persistence gate
- `commands/new-feature.md` + `commands/fix-bug.md` — 8-field intro lines, removed "in this order", Phase 5.4b says "hard SHAPE gates" and explicitly carves out the judgment-call reasons
- `tests/template/test-contracts.sh` — Contract 2f locks all 5 fixes. Updated v5.35 wording assertion ("rare in regression mode" instead of "should be rare"). **12 new assertions; 372 total.**

## 5.35 — 2026-05-25 · Step 2b hard gates gated to feature mode only

**Discovered immediately after v5.34 shipped.** v5.34's new hard gates (`MISSING_ACTOR`, `MISSING_SCENARIO`, `THIN_VERIFICATION`, etc.) were mode-agnostic. That retroactively breaks regression suites: any UC graduated under v5.31/v5.33 lacked the new `Actor:` / `Scenario:` fields, so the next regression run would mark all of them `FAIL_INVALID_USE_CASE` and block ship for purely historical reasons.

**Fix:** mirror v5.33's Step 2c gating. The hard gates run in `feature` mode only. In `regression` and `smoke` modes, hard-gate misses fall back to the prefer-valid bias used by the judgment calls. New UCs going through Phase 3.2b/6.2b authoring still get the strict shape because verify-e2e runs in `feature` mode at that point.

**Files:**

- `agents/verify-e2e.md` Step 2b — added "Mode gating for hard gates" paragraph + renamed the section header to `Hard gates (feature mode only, …)`.
- `commands/new-feature.md` + `commands/fix-bug.md` Phase 5.4b — verdict-handling blocks now reference `FAIL_INVALID_USE_CASE` with explicit "should be rare in regression mode" framing. If it does fire in regression, the message points to a graduation bug (a post-v5.34 UC checked into `tests/e2e/use-cases/` without the new shape) — fix the UC, not product code.
- `tests/template/test-contracts.sh` — new Contract 2e locks the mode-gating across all three files. 5 new assertions; **360 total** across 4 hot-path suites.

**Why no Codex review on this one:** Codex was attempted on the v5.34 commit but hit a network reconnect error mid-review and never returned a verdict. The trace before it died showed Codex was exploring the Phase 5.4b verdict-handling blocks — the very lines this commit fixes. Self-identified gap from the trace + applied Option A (feature-mode gating, the structural symmetry codex itself recommended in the v5.33 review of Step 2c).

## 5.34 — 2026-05-25 · E2E UC shape — Actor + Scenario + surface-specific Verification

**Surfaced by Pablo during ongoing /forge-goal soak.** Even with v5.31's smell test and v5.33's surface coverage audit, the agent kept drafting code-shaped UCs ("User creates a todo" / "POST /api/v1/orders returns 201"). Codex pinned the root cause: the rules said "be specific" but the canonical GOOD examples in `rules/testing.md` still modeled generic phrasing — and Step 2b's prefer-valid bias let borderline UCs slide. The model copies what the examples show, not what the prose argues for.

**Fix — required UC shape with hard gates** (Codex-revised plan, two iterations of pushback):

- **`rules/testing.md`** — UC template revised. Added two REQUIRED fields BEFORE Intent:
  - **Actor** — a specific role/situation (e.g., `Account admin with billing permissions`, `Visitor`, `Signed-in customer`, `API integrator`, `Operator from the CLI`). Bare `user` / `users` / `a user` is rejected as `MISSING_ACTOR`.
  - **Scenario** — 1-2 sentences with starting state + trigger + desired outcome. Must be traceable to a PRD persona / bug report / feature request. No age, city, hobbies, personality, or product-irrelevant filler. Biography fluff rejected as `SCENARIO_FLUFF`.
    Added surface-specific **Verification language rubric** (UI: sees/appears/shows; CLI: stdout shows/next invocation lists/exit code SUPPORTS outcome; API: receives/response includes/follow-up returns). Bare status code, bare exit code, or single element-visible check is rejected as `THIN_VERIFICATION`. Added Setup-cheat rule: Setup must NOT perform the action under test (rejected as `CHEAT_SETUP`). All three canonical GOOD examples (UI/API/CLI) rewritten end-to-end to model the new shape.

- **`agents/verify-e2e.md` Step 2b** — split into **hard gates** (objective shape requirements, no judgment bias: `MISSING_ACTOR`, `MISSING_SCENARIO`, `SCENARIO_FLUFF`, `CHEAT_SETUP`, `THIN_VERIFICATION`, `MISSING_PERSISTENCE`, `TOO_SHALLOW`) and **judgment calls** (prefer-valid bias preserved: `NOT_USER_JOURNEY` for borderline Intent wording, `WRONG_INTERFACE` for borderline surface mismatch). 7 new reason codes added to the classification.

- **`commands/new-feature.md` + `commands/fix-bug.md`** — Phase 3.2b inline checklist rewritten from prose smell test to the 8-field required UC shape. Both Phase 5.4 caller-handling blocks reference the full reason code set. Simple-fix Step 0 in fix-bug.md gets the same required-shape language.

**What we deliberately did NOT do** (per Codex's pushback on the original "ban bare 'user' / day-in-the-life paragraph" plan):

- **No mechanical bare-`user` ban** — folded into Actor validation as a sub-rule. "Bare actor identity" is what we reject; `Visitor`, `Signed-in member`, etc. are fine without naming a persona.
- **No "day-in-the-life paragraph"** — that framing invites biography-fluff parody. Codex's tighter "Scenario: 1-2 sentences, no fluff, traceable to PRD/bug/request" is what shipped.
- **No PRD persona carry-forward** — deferred; too brittle as a universal gate (not every flow goes through /prd:discuss).

**Architectural shifts:**

1. **Step 2b hard-gate vs judgment-call split** — missing fields are objective failures, not borderline. Only Intent wording and Interface selection retain the prefer-valid bias.
2. **Setup is no longer free real estate** — Setup that does the action under test counts as cheating; the UC is testing a read, not the journey it claims to test.
3. **Login is not part of every UC** — Setup declares the auth state and uses a sanctioned auth path; auth itself gets its own dedicated UCs. Stops every feature UC from re-testing login.

**New tests:** `tests/template/test-contracts.sh` gains Contract 2d — every new reason code (`MISSING_ACTOR`, `MISSING_SCENARIO`, `SCENARIO_FLUFF`, `CHEAT_SETUP`, `THIN_VERIFICATION`, `MISSING_PERSISTENCE`, `TOO_SHALLOW`) must be referenced in verify-e2e (producer) AND both command callers (consumer). Required field names + surface-specific Verification verbs locked in `rules/testing.md`. GOOD examples asserted to contain concrete Actor lines (not generic "User"). 34 new assertions; **355 total across 4 hot-path suites**.

**Files:**

- `rules/testing.md` — UC template revision, Verification rubric, three GOOD examples rewritten
- `agents/verify-e2e.md` — Step 2b hard-gate/judgment split, 7 new reason codes, UC1 + UC3 examples rewritten
- `commands/new-feature.md` — Phase 3.2b required-shape checklist, Phase 5.4 caller-handling reason codes
- `commands/fix-bug.md` — Phase 3.2b required-shape checklist, simple-fix Step 0 alignment, Phase 5.4 caller-handling reason codes
- `tests/template/test-contracts.sh` — Contract 2d (34 new assertions)
- `docs/CHANGELOG.md` + `README.md` — version bump 5.33 → 5.34

## 5.33 — 2026-05-18 · Multi-surface E2E coverage audit

**Surfaced during /forge-goal v1.0 soak in msai-v2 portfolio-backtest.** At the PR-creation gate, the user asked the agent whether the E2E tests covered UI, CLI, AND API. The agent admitted: it had designed UI + API UCs and silently skipped CLI even though the project's `msai` CLI exposes the same portfolio capability area. The agent's logic was "no CLI changes in my diff" — a description of implementation scope, not user-facing scope.

The v5.31 feature-surface rule existed and was correct in principle, but didn't force the agent to think about EVERY surface the project exposes. v5.33 adds an explicit multi-surface audit at authoring time, and a backstop in verify-e2e.

**Fixes:**

- **`rules/testing.md`** — new "Multi-surface coverage" subsection. A feature touches a _capability area_; users reach it through any of the _surfaces_ the project exposes. UCs must cover every surface the user could use — not just the surface the implementation diff touched. Defines acceptable vs unacceptable N/A justifications. "No CLI changes in my diff" is the canonical disqualifying example.
- **`commands/new-feature.md` Phase 3.2b** + **`commands/fix-bug.md` Phase 3.2b + simple-fix Phase 5.4 Step 0** — REQUIRED **Surface coverage audit** checklist before writing UCs. Three steps: enumerate exposed interfaces from `CLAUDE.md ## E2E Configuration`, ask per-interface "is this feature's capability area reachable here?", and declare a **Surface coverage decision** sub-block in the plan listing every exposed interface as either `Covered` or `N/A — <substantive justification>`.
- **`agents/verify-e2e.md` Step 2c (new)** — backstop. After UC shape validation (Step 2b) and before health check (Step 3), enumerate exposed interfaces from `CLAUDE.md`, tally interfaces covered by UCs, recognize pre-justified `N/A` lines, and emit `SURFACE_COVERAGE_WARNING` for any gap. Soft warning — does not change the verdict, does not classify UCs. During an autonomous `/forge-goal` run, the agent treats the warning as a `/council` trigger.
- **Report template** — new `## Surface Coverage` section always present, populated from Step 2c. Lists what the project exposes, what UCs cover, pre-justified exclusions, and any warnings.

**New tests:** `tests/template/test-contracts.sh` gains Contract 2c — `SURFACE_COVERAGE_WARNING` keyword present in agent (producer); `Surface coverage decision` sub-block name + warning marker present in both command callers (consumers); "Multi-surface coverage" section + decision vocabulary present in `rules/testing.md`. Regression guard: the disqualifying phrase _"no CLI changes in my diff"_ must appear in both commands so future drift doesn't silently allow the bad pattern. 10 new assertions (213 total contract assertions passing).

**Why a soft warning, not a hard FAIL:** some features genuinely are single-surface (a visual element, an admin-only flow, a deferred-to-v2 escape hatch). A hard FAIL would be too aggressive. A soft warning lets the reviewer or `/council` make the call — and surfaces the question early enough to be answered before PR creation rather than after.

**Files:**

- `rules/testing.md` — Multi-surface coverage subsection
- `commands/new-feature.md` — Surface coverage audit step at Phase 3.2b
- `commands/fix-bug.md` — Surface coverage audit at Phase 3.2b + simple-fix Phase 5.4 Step 0
- `agents/verify-e2e.md` — Step 2c surface coverage check + `## Surface Coverage` report section
- `tests/template/test-contracts.sh` — Contract 2c (10 new assertions)
- `docs/CHANGELOG.md` + `README.md` — version bump 5.32 → 5.33

## 5.32 — 2026-05-18 · Worktree CWD fix + split build-evidence into its own Stop hook

**Surfaced during the msai-v2 portfolio-backtest soak of /forge-goal v1.0.** Two coupled bugs:

1. **Worktree CWD bug.** Evidence JSON reported `session_nonce:null`, `phase:null`, `checklist_total:0` even though the worktree's state.md was correctly populated with an active `## /goal session`. Root cause: CC's Stop hook runs with CWD = `$CLAUDE_PROJECT_DIR` (which resolves to the PARENT project in worktree sessions, not the worktree). `build-evidence` read `.claude/local/state.md` relative to that CWD → wrong (or missing) state.md. Consequence: the PR-create authorization gate would NOT fire when the autonomous run reached `gh pr create` (it gates on a non-empty nonce in evidence). The agent would have opened a PR without the modal pause.

2. **Pre-PR Stop hook noise.** v5.30 only downgraded the CHANGELOG threshold gate to advisory when an OPEN PR existed. Pre-PR (where /forge-goal spends 90% of its time) still hit exit 2 → CC labeled the entire combined STDERR (build-evidence's evidence dump + check-state-updated's CHANGELOG nag) as "Stop hook error" → giant JSON dump flooded every Stop turn. The deferred "split build-evidence into its own Stop hook" refactor that v5.30 explicitly punted is now done.

**Fixes:**

- **`hooks/build-evidence.{sh,ps1}`** — registered as its **own** Stop hook entry in `settings.template.json` (BEFORE check-state-updated so the fingerprint side-channel file is written before stuck-detection reads it). Always exits 0 → its STDERR is rendered as informational `Ran stop hook` output, not labeled "error". Also: both scripts now parse `cwd` from the Stop hook stdin JSON and `cd` there at the top, fixing the worktree CWD bug. Fallback chain: `stdin.cwd` → `git rev-parse --show-toplevel` → current CWD.
- **`hooks/check-state-updated.{sh,ps1}`** — removed the inline call to build-evidence (it's now a separate hook). Added the same `cwd` parsing so stuck-detection reads/writes the worktree's `.claude/local/` not the main repo's. Comments updated to reflect the new architecture.
- **`settings/settings.template.json` + `settings-windows.template.json`** — Stop hook array now lists both build-evidence and check-state-updated commands in that order.
- **`scripts/merge-settings.py`** — added deep-merge for hook events. The old shallow merge skipped existing hook events entirely, so adding a new parallel command to an existing event (the v5.32 case) would never reach existing installs via `--upgrade`. New `merge_hook_event` rebuilds each matcher-block's hooks list **in template order**, picking up the user's version when present and inserting new template hooks at their template position. Preserves ordering invariants (critical for build-evidence-before-check-state-updated) AND any user-only customizations.

**New tests:**

- **`tests/template/test-hooks.sh`** — 2 new tests (5 new assertions): build-evidence reads state.md from `stdin.cwd` not its own CWD; check-state-updated stuck-detection accumulates in the worktree, not the main repo. Includes negative control proving the redirect actually happens.
- **`tests/template/test-contracts.sh`** — 4 new assertions: settings.template.json (and Windows mirror) register both hooks in the correct order (build-evidence first).
- **`tests/template/test-merge-settings.sh` (new file)** — 7 unit tests covering deep-merge: new command added to existing matcher-block in template order, idempotency (re-merge doesn't duplicate), new top-level event still added, new matcher-block appended, permissions arrays still merge.

**Architectural note:** The "merge inserts new hook in template position" behavior is what makes the v5.32 upgrade path safe. A user with the old `[check-state-updated]` Stop array gets `[build-evidence, check-state-updated]` after `--upgrade` — not `[check-state-updated, build-evidence]` (which would silently break stuck-detection because build-evidence's fingerprint side-channel wouldn't exist when stuck-check ran).

**Files:**

- `hooks/build-evidence.sh` + `.ps1` — stdin.cwd parse + chdir at top
- `hooks/check-state-updated.sh` + `.ps1` — removed inline build-evidence call + stdin.cwd parse
- `settings/settings.template.json` + `settings-windows.template.json` — two-Stop-hooks registration
- `scripts/merge-settings.py` — `merge_hook_event` deep-merge with template-order insertion
- `tests/template/test-hooks.sh` — worktree CWD tests
- `tests/template/test-contracts.sh` — Stop hook ordering contract
- `tests/template/test-merge-settings.sh` — new file, 7 unit tests
- `tests/template/run-all.sh` — registered the new suite
- `docs/CHANGELOG.md` + `README.md` — version bump 5.31 → 5.32

## 5.31 — 2026-05-18 · E2E user-journey enforcement

**Surfaced during /forge-goal v1.0 soak in msai-v2.** The agent was drafting E2E use cases that read like integration tests ("POST /api/users returns 201") instead of user journeys ("Customer places an order and finds it in their history"). Cause: the rules defined the required fields and listed anti-patterns but provided no positive worked example to pattern-match against; interface selection was driven by project type instead of by what the user actually touches for the feature; and the verify-e2e agent executed whatever it was handed without bouncing back ill-shaped UCs.

**Fix shape** (validated by Codex design review before implementation):

- **`rules/testing.md`** — added a "GOOD vs BAD use cases" section with canonical worked examples per UI / API / CLI. Strengthened the Intent field with a smell test ("If you cannot describe the Intent to a non-developer in one sentence without naming endpoints, code, tables, components, or other internal terms, it is not a user journey"). Replaced the project-type-driven interface matrix with a two-step **feature-surface-driven** model: `CLAUDE.md ## E2E Configuration` is the capability envelope (which interfaces exist); the feature determines which surface(s) the user actually touches. Added Codex's pushback: internal endpoints backing a UI page get a UI UC, not an API UC — endpoint contract coverage is integration-test territory. Added `FAIL_INVALID_USE_CASE` row to the failure classification table.
- **`rules/critical-rules.md`** — updated the E2E line to reflect the user-journey requirement and feature-surface interface rule. The old text repeated the now-superseded project-type matrix.
- **`commands/new-feature.md` Phase 3.2b** + **`commands/fix-bug.md` Phase 3.2b + simple-fix Phase 5.4 Step 0** — embed the 4-point smell test inline (Intent describable in one sentence, multiple actions, user-visible Verification, correct Interface). Replaced project-type bullet list with a feature-shape → interface table. Phase 5.4 caller handling extended to recognize `FAIL_INVALID_USE_CASE` and route it to "rewrite the UC, do not change product code".
- **`agents/verify-e2e.md`** — added **Step 2b: Validate use-case shape** between Load use cases (Step 2) and Health check (Step 3), so invalid UCs are caught BEFORE a server is even probed. New per-UC classification `FAIL_INVALID_USE_CASE` with sub-reasons `NOT_USER_JOURNEY` and `WRONG_INTERFACE`. Top-level `VERDICT:` enum unchanged (still `PASS | FAIL | PARTIAL`); invalid UCs map to `FAIL` with a "test-design failure, not a product bug" note in Verdict Reasoning. Report template gains a UC3 example showing the new classification with rationale + suggested rewrite.
- **`tests/template/test-contracts.sh`** — new Contract 2b: per-UC `FAIL_*` classifications listed in `verify-e2e.md`'s "Classification rules" must be handled in both `new-feature.md` and `fix-bug.md` (forward + reverse check). 10 new assertions (199 total contract assertions passing).

**Files changed:**

- `rules/testing.md` — GOOD/BAD examples + smell test + feature-surface interface model + `FAIL_INVALID_USE_CASE` row
- `rules/critical-rules.md` — E2E line rewritten
- `commands/new-feature.md` — Phase 3.2b smell test + interface table; Phase 5.4 verdict handling
- `commands/fix-bug.md` — Phase 3.2b smell test + interface table; simple-fix Step 0; Phase 5.4 verdict handling
- `agents/verify-e2e.md` — Step 2b validation + new classification + verdict mapping + report template update
- `tests/template/test-contracts.sh` — Contract 2b (per-UC classification handling)
- `docs/CHANGELOG.md` + `README.md` — version bump 5.30 → 5.31

## 5.30 — 2026-05-18 · Fix: Stop-hook "error" framing during /forge-goal soak

**Surfaced during soak of /forge-goal v1.0 in msai-v2.** Every Stop turn after PR creation printed the FORGE*GOAL_EVIDENCE JSON dump prefixed with "Stop hook error" because `check-state-updated.{sh,ps1}` invokes `build-evidence.{sh,ps1}` inline (shared STDERR) and then hit exit 2 on the CHANGELOG threshold gate. The exit-2 caused Claude Code to label the \_entire* combined STDERR — evidence + reminder — as an error from the calling hook.

**Fix:** when an OPEN PR already exists for the current branch, the CHANGELOG gate downgrades from blocking (exit 2) to advisory (exit 0). Rationale: pre-PR-create the block is correct (force CHANGELOG before opening PR), but once a PR is open the human reviewer carries the signal — per-turn blocking during CI wait is just noise, and exit 0 removes the "Stop hook error" framing so the evidence dump collapses behind ctrl+o.

**Also fixed:** wording — "files changed this session" → "files changed on branch vs `<default-branch>`". The count is committed + uncommitted diff vs the merge-base, not files-this-turn; the old wording suggested otherwise.

**Files:**

- `hooks/check-state-updated.sh` + `hooks/check-state-updated.ps1` — open-PR detection via `gh pr view --json state -q .state` (best-effort, no-gh → preserve original block); exit-2 → exit-0 + advisory when PR is OPEN; wording correction.
- `tests/template/test-hooks.sh` — new test 15b ("open PR → exit 0 advisory") using a path-shimmed `gh` stub. Test 15 extended to assert the new "on branch vs master" wording.

**Not changed:** `build-evidence` still writes evidence to STDERR (Layer 1 design). The split-evidence-into-own-Stop-hook refactor was considered and deferred — too invasive for a hot-path soak fix.

## 5.29 — 2026-05-16 · `/forge-goal` autonomous PRD-to-PR-ready workflow

**Why this exists:** Manual phase-by-phase shepherding through `/new-feature` and `/fix-bug` was the babysitting tax. `/forge-goal` lets the user type ONE command after PRD approval (or plan approval for bug fixes) and the agent autonomously drives plan → plan-review → implement → code-review → E2E → PR-ready, surfacing council for non-PR judgment moments and pausing only at PR creation.

**Capability:** After the gate checkpoint passes, the workflow command generates a session nonce, writes `## /goal session` to state.md, and prints a `/goal` command. The user types it; the agent enters autonomous mode. Stops at the PR-creation gate (AskUserQuestion modal + hook-enforced authorization signal in state.md) and at council-resolved decisions.

**Checkpoint placement:** `/new-feature` places the checkpoint at PRD-complete (after Phase 1, before Phase 2 Research). `/fix-bug` places it at Plan-Approved (after Phase 3.3 Plan Review Loop, before Phase 4 Execute) — because `/fix-bug` has no PRD phase. Simple fixes (1-2 files skipping Phase 3) are not eligible for the autonomous loop.

**New (Layer 1):**

- `hooks/build-evidence.{sh,ps1}` — read-only evidence emitter. Parses state.md, queries git/`gh pr view`/E2E reports, emits unified JSON between `FORGE_GOAL_EVIDENCE_BEGIN/END` markers. Computes `pr_ready`, deterministic `progress_fingerprint` (SHA256, CRLF-normalized, ordered, ASCII US delimiter).

**New (Layer 2):**

- `commands/new-feature.md` — PRD-Complete Checkpoint prints the `/goal` command; REPLACE semantics for `/goal session` and `## PR authorization`; PR-create AskUserQuestion modal documented; `all_gates_green` excluded from condition (post-PR checklist items are structurally unclearable while PR is open).
- `commands/fix-bug.md` — Plan-Approved Checkpoint at Phase 3→4 boundary; bug-fix-specific wording throughout; same REPLACE semantics and `all_gates_green` exclusion.
- `rules/workflow.md` — "Council During `/forge-goal`" trigger rule (route non-PR doubts to `/council`, leave reviewer-loop iterations as today).
- `state.template.md` — conventions for `## /goal session` (format documentation, no empty instance), `## PR authorization`, reviewer-iteration head-SHA labels, REPLACE semantics, and the non-empty-nonce "active" definition.

**Fixed (Layer 1):**

- `hooks/check-state-updated.{sh,ps1}` — invokes `build-evidence` BEFORE the `stop_hook_active` early-return. Previously the early-return suppressed evidence emission inside active `/goal` loops.

**Extended (Layer 2):**

- `hooks/check-workflow-gates.{sh,ps1}` — PR-create authorization guard. Blocks `gh pr create` during an active `/forge-goal` session unless `## PR authorization` matches the session nonce AND current HEAD SHA. "Active" = non-empty nonce. LAST-line defense for stale-duplicate state.md.
- `hooks/check-state-updated.{sh,ps1}` — stuck-detection soft warning. After 5 consecutive turns with identical `progress_fingerprint`, emits `FORGE_GOAL_STUCK_WARNING` to STDERR (informational, no abort).

**New tests:** `tests/template/test-build-evidence.sh` (35 assertions, Layer 1), 10 new test blocks in `test-hooks.sh` (6 PR-create guard + 4 stuck-detection), 8 new contracts in `test-contracts.sh` (Layer 1 + Layer 2, including fixture-based runtime parity tests for Bash vs PS guards).

**Architecture trace:** Native Anthropic `/goal` (CC 2.1.139+) drives the loop; forge supplies the evidence the verifier reads. State.md is the single source of truth (no sidecar state files). See `docs/plans/2026-05-14-forge-goal-design.md` and `docs/plans/2026-05-13-forge-goal-experiments.md`.

**Files:**

- `hooks/build-evidence.sh` + `hooks/build-evidence.ps1` — new (Layer 1 evidence primitive)
- `hooks/check-state-updated.sh` + `hooks/check-state-updated.ps1` — ordering fix (Layer 1) + stuck-detection (Layer 2)
- `hooks/check-workflow-gates.sh` + `hooks/check-workflow-gates.ps1` — PR-create authorization guard (Layer 2)
- `commands/new-feature.md` — PRD-Complete Checkpoint (Layer 2)
- `commands/fix-bug.md` — Plan-Approved Checkpoint (Layer 2)
- `rules/workflow.md` — council-during-`/forge-goal` trigger rule (Layer 2)
- `state.template.md` — `/goal session` + PR authorization + reviewer-iteration conventions (Layer 2)
- `tests/template/test-build-evidence.sh` — 35 new assertions (Layer 1)
- `tests/template/test-hooks.sh` — 10 new test blocks (Layer 2)
- `tests/template/test-contracts.sh` — FORGE_GOAL_EVIDENCE + 8 new Layer 2 contracts
- `setup.sh` + `setup.ps1` — install `build-evidence.{sh,ps1}` to downstream `.claude/hooks/`
- `docs/CHANGELOG.md` + `README.md` — version bump 5.27 → 5.29 (Layer 1 deferred; ships unified)

**Existing installs:** run `./setup.sh --upgrade` from your Forge clone to pick up all new scripts and updated templates.

## 5.27 — 2026-05-12 · `/council` chairman output reliability (`--output-last-message`)

**Bug:** When `/council` ran the chairman call, `codex exec` dumped everything to stdout — the CLI banner, the entire 16KB+ prompt echoed back, the `codex` marker, the response, and a `tokens used` footer. The skill said "Display the chairman's output VERBATIM" but never told Claude HOW to extract the response from that verbose capture. Claude improvised with ad-hoc `tail`/`grep`/`sed` patterns. When extraction failed it reported "Codex chairman exited without producing analysis on both attempts" — even when the verdict was sitting cleanly in the file, fully structured. Field-confirmed today: a single `/council` session in `actbl-he` produced 21KB and 4.3KB chairman responses (both with complete `## Council Verdict` / `### Minority Report` sections) and both were narrated as failures.

**Root cause:** parsing fragility, not a codex bug. The codex CLI has shipped `--output-last-message <FILE>` since [PR #4644](https://github.com/openai/codex/pull/4644) (2025-10-03, stable in 0.124+). The flag writes ONLY the assistant's final message — no banner, no prompt echo, no markers, no footer. The skill simply wasn't using it.

**The fix:** add `--output-last-message /tmp/council_<role>_response.txt` to all four codex invocations in `skills/council/references/peer-review-protocol.md` (Codex advisor, Chairman, Contrarian gate). Keep the existing `> /tmp/council_<role>.txt 2>&1` redirect as a forensic full-log capture. `SKILL.template.md` Step 5 now instructs Claude to read the verdict from the OLM file first, with the full log as a diagnostic fallback when the OLM file is missing or empty.

**Two-file pattern (per codex call):**

- `<role>_response.txt` — written only at clean shutdown by `--output-last-message`; contains JUST the assistant text. Read this for the verdict.
- `<role>.txt` — full stdout+stderr capture; contains banner + prompt echo + everything codex printed + any shim/error diagnostics before exit. Read this when the response file is missing or 0-byte to distinguish "codex failed mid-stream" from "codex succeeded but my parser was wrong" — the exact misread that motivated this PR.

**Empirically verified:** ran the patched dispatch through the PTY shim against codex 0.125.0. Prompt: "Say only the word HELLO and nothing else." Response file = 5 bytes containing `HELLO`. Full log = 513 bytes containing banner + prompt echo + response + `tokens used` footer. Direct codex (no shim) hung forever on no-TTY (`"Reading additional input from stdin..."`), confirming the PTY shim is still load-bearing — this fix is additive, not a shim replacement. Retirement canary for codex 0.129+ unchanged (2026-05-21).

**Failure-mode contract** (encoded in `peer-review-protocol.md` "Output Capture" section):

- Response file non-empty → codex succeeded; use the text verbatim.
- Response file missing or empty → codex did NOT reach clean shutdown. Quote the relevant excerpt from the full log (look for the `codex` marker, partial response sections, or `codex-pty:`-prefixed shim errors) and surface it to the user. Do NOT silently fall back to chairman-less mode without showing them what codex actually said.

**Files:**

- `skills/council/references/peer-review-protocol.md` — new "Output Capture" section explaining the two-file pattern once; `--output-last-message` + stdout redirect added to all 3 code blocks (Codex advisor, chairman, contrarian gate).
- `skills/council/SKILL.template.md` — Step 5 instructs Claude to read response from OLM file with full-log fallback for forensics; documents the new failure-mode messaging.
- `tests/template/test-contracts.sh` — new contract assert: `peer-review-protocol.md` must reference `--output-last-message`.
- `docs/CHANGELOG.md` + `README.md` — version bump 5.26 → 5.27.

**Existing installs:** run `./setup.sh --upgrade` from your Forge clone to pick up the updated council skill. No code changes; the user-visible behavior change is that `/council` failure narration becomes accurate — no more false "exited without producing analysis" when codex actually succeeded.

## 5.26 — 2026-05-10 · Database migration discipline rule (additive-only + expand-contract)

`rules/database.md` had no migration guidance — a real gap for any team running rolling deploys with image rollback. Surfaced when `msai-v2` codified its own deploy-pipeline-specific version and the question came up: "is this generally applicable?" Yes — it's the standard production-hygiene pattern (any team whose deploy pipeline rolls back image SHAs but not DB schema wants additive-only migrations so old code can talk to the newer schema after a rollback).

**What's new in `rules/database.md`:**

- "Migrations — additive-only discipline" section with the ✅/❌ patterns matrix (ADD column/table/index/nullable FK = safe; DROP/RENAME/NOT-NULL-without-backfill/type-narrowing = unsafe).
- The 3-release expand-contract pattern for destructive changes (Expand → Backfill+cutover → Contract).
- Escape hatch language for genuine emergencies: coordinate with team, disable auto-rollback for that deploy, treat as one-way with a maintenance window.
- Rule #5 added to the numbered rules list: `ALWAYS write additive-only migrations — use expand-contract for destructive changes`.

**Files:**

- `rules/database.md` — new "Migrations" section + new rule #5; existing rules renumbered 6→9.
- `docs/CHANGELOG.md` + `README.md` — version bump 5.25 → 5.26.

**Existing installs:** run `./setup.sh --upgrade` from your Forge clone to pick up the updated rule. No code changes; no behavior changes; just guidance Claude (and humans) will read when designing migrations.

## 5.25 — 2026-05-10 · Diagnose downstream-gitignored `.claude/` in STATE-INIT

When a downstream project gitignores `.claude/` wholesale (instead of only `.claude/local/` per Forge convention), `/new-feature` and `/fix-bug` create worktrees based on `origin/<default-branch>` that don't have any Forge files (no template, no hooks, no rules in the worktree's tracked tree). The STATE-INIT block emitted `STATE_TEMPLATE_NOT_FOUND_AT:<path>` with remediation "re-run `setup.sh --upgrade`" — but setup writes to the parent's working tree, which still won't propagate to the worktree branch under the same gitignore rule. Field-confirmed in `msai-v2` (`.gitignore:2` had `.claude/` from initial commit, pre-Forge adoption); the agent improvised an off-script `cp -R .claude/` from the parent into the worktree to recover.

**Root cause:** STATE-INIT only checked the worktree path for the template, then fell through to a generic "missing template" message that pointed at the wrong fix.

**The fix:** STATE-INIT now resolves the parent working tree via `git rev-parse --git-common-dir` (relative `.git` in main repo, absolute path to main's `.git` from a worktree — strip `/.git` only when absolute) and inspects the parent's `.gitignore`. If a bare `.claude/` line is present, it emits a new sentinel `STATE_TEMPLATE_DOWNSTREAM_GITIGNORED:<parent_root>` with the correct remediation: edit `.gitignore` to keep only `.claude/local/`, then `git add .gitignore .claude/ && git commit && git push`, then `git fetch && git rebase` from inside the worktree, then retry. Don't `cp -R` from the parent — that masks the misconfiguration and other Forge surfaces (hooks paths in `settings.json`, `default-branch.sh` lookup, workflow-gate hook reading `.claude/local/state.md`) still won't reach the worktree's tracked tree.

**Codex independent investigation** confirmed the diagnosis and recommended option C (loud preflight with correct remediation message) over option B (auto-mirror the parent's `.claude/` into the worktree): auto-mirror would silently paper over the contract violation while leaving ~6 other surfaces silently broken at downstream-PR-review time.

**Bonus fix — AC-2e false positive:** the Step 2b prose-scanning regex (`tests/template/test-contracts.sh`) for "redirect to .claude/" was missing the `(^|[[:space:]])` anchor that its sibling cp/mv and sed regexes have. As a result, any literal `>` in prose (e.g. inside `<placeholder>` syntax) followed eventually by `.claude/` on the same line falsely matched. Tightened all three call sites (AC-2b shell-block scan, AC-2c self-test, AC-2e prose scan) to use the anchored form, and added AC-2d — a negative self-test that asserts known-good `<placeholder>` prose patterns are NOT matched. AC-2c still passes its 16 synthetic positives.

**Files:**

- `commands/new-feature.md`, `commands/fix-bug.md` — STATE-INIT block adds parent-root resolution + `.gitignore` detection + new sentinel branch (block remains byte-identical between the two files); Step 2b prose adds bullet for the new sentinel with the structural fix.
- `tests/template/test-contracts.sh` — three redirect regexes anchored consistently; AC-2d negative-test added with 2 false-positive fixtures.
- `docs/CHANGELOG.md` + `README.md` — version bump 5.24 → 5.25.

**Existing installs:** run `./setup.sh --upgrade` from your Forge checkout to pick up the updated commands. Restart Claude Code afterward — slash-command definitions reload at session start. **If your downstream `.gitignore` has a bare `.claude/` line** (deviating from Forge convention), fix that next: replace with `.claude/local/`, `git add .claude/ .mcp.json`, commit, push.

## 5.24 — 2026-05-09 · State-init via Write tool — zero prompts on `/new-feature` & `/fix-bug`

`/new-feature` and `/fix-bug` were prompting users for permission on `cp` commands writing to `.claude/local/state.md` — both the script-level `cp` on first init AND agent-improvised `cp main_state worktree_state` on every state write. Field-confirmed in `msai-v2`.

**Root cause:** Claude Code's built-in heuristic prompts on **any Bash command** writing under `.claude/`, regardless of `permissions.allow`. The v5.21 PermissionRequest hook only matches `Write|Edit` (structured tools), not `Bash`. So `cp template .claude/local/state.md` always asks; the structured `Write` tool to the same path doesn't.

**The fix:** workflow text only — no hook changes, no settings changes, no `.ps1` parity work. The STATE-INIT bash block in `commands/new-feature.md` and `commands/fix-bug.md` is now **truly read-only**: it locates the template and emits one of three sentinels (`STATE_EXISTS`, `STATE_NEEDS_INIT_FROM:<path>`, `STATE_TEMPLATE_NOT_FOUND_AT:<path>`). The agent then uses the **Read** tool on the template + the **Write** tool on `.claude/local/state.md`. Write creates the missing `.claude/local/` parent directory in the same call — empirically verified ([ADR 0006](adr/0006-write-tool-creates-missing-parents.md)) — and is auto-approved by the v5.21 hook on `.claude/local/**`. Net: from "every cp prompts on every state write" to **zero prompts on the state-init path**.

**Codex-validated approach (against [Anthropic permissions docs](https://code.claude.com/docs/en/permissions)):**

- Anthropic's docs warn that Bash patterns trying to constrain command arguments are fragile. Their recommended mitigation for `.claude/`-write scenarios is the structured Write/Edit tool path, not Bash.
- Adding a Bash auto-approve hook for `.claude/local/**` would walk into the parsing pitfalls Anthropic flags (compound commands, redirects, variables, command substitution, symlinks). Out of scope for this fix.
- The workflow-text fix has no security trade-off: failure mode is "extra prompt", not a bypass.

**Engineering Council process:** the branch went through 5 Codex review iterations + a 5-advisor council to land the final shape. Earlier iterations retained a defensive `mkdir -p .claude/local` based on the assumption that the Write tool wouldn't reliably create parent directories — Codex Contrarian objected that this premise was unproven and was being locked in by tests. The council voted to ship a partial fix; before merging, ran the spike Codex Hawk requested ([ADR 0006](adr/0006-write-tool-creates-missing-parents.md) — fresh-worktree Write to `.claude/local/state.md` with no parent present, on Claude Code 2.1.138 / macOS 26.2). The Write tool created both parent directories and the file in one call. Result: dropped `mkdir`, simplified the contract tests, and shipped a true zero-prompt fix instead of the partial one. The Contrarian was right.

**Locked in by contract test:** `tests/template/test-contracts.sh` now asserts the STATE-INIT block contains **zero** Bash writes under `.claude/` (cp/mv/ln/install/dd/touch/tee/rm/rmdir/mkdir/sed-i/redirects, all banned). Re-introducing any of them resurrects the permission prompt this fix was added to remove. Self-test (AC-2c) feeds 16 synthetic violations to the detector and asserts each matches.

**Files:**

- `commands/new-feature.md`, `commands/fix-bug.md` — STATE-INIT block restructured (truly read-only steps 2a / 2b / 2c). Block remains byte-identical between the two files (existing AC-2 contract).
- `tests/template/test-contracts.sh` — AC-2b (no Bash writes under .claude/), AC-2c (16-violation self-test), AC-2e (Step 2b prose contract). Joins shell line continuations before grep'ing.
- `docs/adr/0006-write-tool-creates-missing-parents.md` (new) — captured spike evidence with version anchor.
- `docs/CHANGELOG.md` + `README.md` — version bump 5.23 → 5.24.

**Existing installs:** run `./setup.sh --upgrade` from your Forge checkout to pick up the updated commands. Restart Claude Code afterward — slash-command definitions reload at session start.

## 5.23 — 2026-05-07 · Switch superpowers identity to `@claude-plugins-official`

Forge had been pinning `superpowers@superpowers-marketplace` (the community marketplace by [obra](https://github.com/obra/superpowers-marketplace)). It works, but it requires `/plugin marketplace add obra/superpowers-marketplace` as a prerequisite — a step that wasn't documented in `commands/new-feature.md`'s Required Plugins section. As of 2026-01-15 ([anthropics/claude-plugins-official PR #148](https://github.com/anthropics/claude-plugins-official/pull/148)) the same plugin is published in Anthropic's official marketplace as `superpowers@claude-plugins-official` — installable in one step.

**Operational reason for the switch**: [obra/superpowers-marketplace#11](https://github.com/obra/superpowers-marketplace/issues/11) documents an upstream Claude Code installer bug — when the same plugin name lives in both marketplaces, Claude Code's matcher uses name only, ignoring the marketplace qualifier. Field-confirmed in `msai-v2`: settings.json had `enabledPlugins: { "superpowers@superpowers-marketplace": true }` while user-scope `installed_plugins.json` had `superpowers@claude-plugins-official`. Settings flag points at one identity, install record has the other — the `Skill` tool can't bridge them, so `/superpowers:writing-plans` returns "Unknown skill" despite settings appearing correct.

**What changed (9 files, mechanical)**:

- `settings/settings.template.json` + `settings-windows.template.json` — `enabledPlugins` flag flipped to the official identity
- `commands/new-feature.md` + `commands/fix-bug.md` — Required Plugins tables and JSON examples updated
- `docs/troubleshooting.md` — 3 references in the plugin-loading section
- `docs/getting-started.md` — install instruction simplified to one line; added explainer about why we picked official over community
- `setup.sh` + `setup.ps1` — final-summary install instruction now drops the `marketplace add` prerequisite line
- `README.md` — Quick Start step 5 same simplification

**No functional loss** — same Superpowers framework, same skills, same maintainer (obra). Just a different marketplace registration.

**Existing installs running `./setup.sh --upgrade`**: `merge-settings.py` is add-only, so both `superpowers@claude-plugins-official: true` and any pre-existing `superpowers@superpowers-marketplace: true` will coexist in `enabledPlugins`. Harmless — Claude Code will resolve whichever identity is installed. Users can manually drop the old flag after they confirm the new identity works.

## 5.22 — 2026-05-07 · Codex PTY shim — work around openai/codex#19945

`codex exec` silently exits with empty stdout (exit 0, zero bytes) when run with stdio detached from a controlling TTY AND a non-trivial prompt — exactly the conditions Claude Code's Bash tool creates every time the Forge invokes `/codex` or `/council`. The bug was [introduced in codex 0.124.0](https://github.com/openai/codex/issues/19945) (last unaffected: 0.123.0), still present in 0.125.0 / 0.128.0, and has no upstream fix as of 2026-05-07. The intermittent rate is ~30% on 0.125.0 — single-shot reproducers are unreliable, but the cumulative effect is that virtually every `/council` fan-out (3–5 parallel codex calls) hits the bug at least once.

Field reports describe 10–17 minute hangs on long audit prompts, ending in `kill` exit-144. The Forge memory previously attributed the symptom to "long prompt overload"; that was incomplete — prompt length is one of two triggers, not the trigger.

**The fix: a cross-platform PTY shim** at `.claude/hooks/lib/codex-pty.sh` (Unix) and `codex-pty.ps1` (Windows). All `codex exec` invocations across `/codex` and `/council` now route through the shim, which allocates a pseudo-terminal so codex sees `isatty(stdin/out) == true` and produces real output.

**Unix path:** `python3` + a lightweight helper script (`codex-pty-helper.py`) using `pty.fork()` + `waitpid(WNOHANG)` polling. We can't use BSD `script(1)` because it requires a parent TTY (`tcgetattr` on parent stdin) which Claude Code's Bash tool — running with stdin connected to a Unix domain socket — does not have. We can't use Python's `pty.spawn()` either: the 3.9 stdlib version hangs on macOS after the child exits because the parent's `select()` loop blocks on a `master_fd` that never reports EOF. The explicit waitpid-based helper sidesteps both problems.

**Windows path:** detect-then-bypass. PS 7+ with non-redirected stdio uses ConPTY natively (no shim needed). Redirected stdio probes `winpty.exe` (PATH first, then Git for Windows install paths). WSL is opt-in via `CLAUDE_FORGE_CODEX_PTY_VIA_WSL=1`. Last resort: direct invoke with stderr warning. Per the research brief, #19945 has zero confirmed Windows reproductions — the .ps1 shim exists primarily for ADR 0005 platform parity.

**Opt-out** via `CLAUDE_FORGE_CODEX_PTY_BYPASS=1` (mirrors the v5.21 PR #592 pattern). Useful when upstream is confirmed fixed, or when an EDR / corporate sandbox blocks PTY allocation.

**Iterations during review (4 commits squashed at merge):**

- **iter-1** (`6443abb`): main shim + tests + callsite migration in `commands/codex.md` and `skills/council/*`
- **iter-2** (`ff4489c`): cancellation signal forwarding. Without explicit handlers, parent SIGINT was silently absorbed by the helper's `except OSError: continue` clause (which catches `InterruptedError`), and codex would run to natural completion instead of canceling. Fixed: parent installs `_forward_signal` handler for SIGINT/SIGTERM/SIGHUP that does `os.kill(child_pid, signum)`; child resets these signals to `SIG_DFL` before `execvp` so they aren't inherited as `SIG_IGN` from bash's POSIX-mandated backgrounded-process behavior.
- **iter-3** (`9859abb`): busy-loop fix. The iter-2 stdin-EOF handling did `dup2(/dev/null, 0)` expecting `select()` to stop waking on fd 0. Empirically reproduced by the Engineering Council's Contrarian and Maintainer (independently): `python3 helper /bin/sleep 2 </dev/null` consumed ~2 CPU-seconds because `/dev/null` is always selectable. Fixed: track `stdin_open` flag, drop fd 0 from the select set after EOF.
- **iter-3+1** (`17a3a97`): EOT propagation. The iter-3 fix stopped the parent from polling fd 0, but never told the child the input had ended — children that read stdin (e.g., `/bin/cat` with piped input) hung forever. **Caught by codex itself** reviewing the helper through the shim during the live mcpgateway smoke test. Fixed: write `\x04` (EOT) to the pty master on stdin EOF; disable TTY ECHO at startup so the EOT doesn't echo back as `^D\b\b` and contaminate output.

**Test coverage:** 33 unit tests for the Unix shim (mocked codex + isatty assertions + real-pty integration via `/bin/echo` + stdin-from-/dev/null liveness + CPU regression for the busy-loop + signal-killed-child + piped-stdin EOF propagation). 115 cross-file contract assertions in `test-contracts.sh` (the suite total; 9 of them codex-pty specific) enforce env-var name parity, header references to issue #19945, callsite migration completeness, and setup-script wiring on both platforms.

**Drain cap raised to 16 MiB** (was 1 MiB in iter-1). Council's Scalability Hawk flagged that council-chairman synthesis at xhigh effort can plausibly exceed 1 MiB; a silent half-output is a more dangerous failure mode than a slightly-larger-than-needed buffer. The cap also now emits an unconditional stderr warning if reached so silent truncation is impossible.

**Retest criterion + retirement plan:** drop the shim once codex `0.128+` (or whatever stable version closes #19945) is empirically confirmed clean on Linux + macOS + Windows. The canonical reproducer is `setsid codex exec "$LARGE_PROMPT" < /dev/null` returning non-empty output (intermittent, so multi-trial). A retirement canary is scheduled as a Claude cloud routine for **2026-05-21 09:00 CDT** ([routine `trig_019fwhiNbxkcUdAcNJ9Eiex3`](https://claude.ai/code/routines/trig_019fwhiNbxkcUdAcNJ9Eiex3)) — it runs a 10-trial sentinel-based canary against the latest installed codex CLI and opens a draft Stage 1 retirement PR if 10/10 PASS on a stable codex version. The full council-recommended staged retirement is: bypass-by-version → noop the shim → revert callsites → delete files, with multi-week cooldowns between stages.

**Existing installs need `./setup.sh --upgrade`** to pick up the shim files (preserves your existing `.claude/settings.json` + `.mcp.json` customizations while merging in new entries). Then any new `/new-feature` or `/fix-bug` invocation in a downstream project will use the migrated callsites.

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
