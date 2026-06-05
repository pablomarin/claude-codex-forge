# Workflow

**Use workflow commands.** They contain the full process - follow them exactly.

## Decision Matrix

| Scenario                   | Action                                              |
| -------------------------- | --------------------------------------------------- |
| Starting new feature       | Run `/new-feature <name>` (creates worktree)        |
| Fixing a bug               | Run `/fix-bug <name>` (creates worktree)            |
| Trivial change (< 3 files) | Run `/quick-fix <name>` (no worktree)               |
| Want a second opinion      | Run `/codex <instruction>` (code review or general) |
| Multi-perspective analysis | Run `/council <question>` (5 advisors + chairman)   |
| Creating PR to main        | **Ask**                                             |
| Merging PR to main         | **Ask**                                             |
| Skipping tests             | **Never**                                           |

## Workflow Tracking

**When a workflow is active** (`## Workflow` in .claude/local/state.md has Command != `none`):

1. **Before each action**: Read `## Workflow` in .claude/local/state.md — check current Phase and Next step
2. **Execute only** the `Next step` listed
3. **After completing a step**: Check the box in the Checklist and advance `Next step` to the next unchecked item
4. **On phase transition**: Update the `Phase` field

The Stop hook reminds you of the current phase on every response. The PreToolUse hook blocks commit/push/PR if quality gates are incomplete. This rule is re-injected every turn — it survives context compaction.

## Council During `/forge-goal` Autonomous Run

When a `/forge-goal`-driven `/goal` is active (`## /goal session` is populated in `.claude/local/state.md` with a non-empty nonce), the agent's pause-for-user discipline changes:

**Before asking the user any question during the autonomous run, ask yourself:**

> _Is this a PR creation authorization?_

- **If YES:** call `AskUserQuestion` with the PR-create modal. The user's answer is the only human-authority signal in the loop.
- **If NO:** invoke `/council` with the question. Apply the chairman's verdict. Continue the loop.

**Triggers for council** (the agent invokes council at its discretion when):

- An ambiguous product or technical choice would otherwise prompt the user
- A reviewer recommends plan revision (not just code patch)
- A high-impact implementation fork has multiple defensible approaches
- A retried tool/subagent has also failed
- Council/reviewer output is unrecognizable and needs interpretation

**Explicit NON-triggers:**

- Normal plan-review-loop iterations (Claude + Codex back-and-forth on the plan) — these stay as today's reviewer iteration flow
- Normal code-review-loop iterations (Codex + PR-toolkit + Claude fix cycles)
- A convergence-breaker (non-convergence) halt — human-only by design (US-003): write the Blockers line and stop; council may be invoked BY the human afterward, never as the autonomous risk-acceptor.
- Any moment that doesn't actually require human-level judgment

**Council failure handling:** If `/council` itself fails (network, advisor timeout, missing chairman verdict), the autonomous loop pauses and writes a blocker line to `.claude/local/state.md` (`## Blockers`). The user takes over.

**Audit:** Each council invocation during an autonomous run is durable in the conversation transcript — the agent's response naming the council outcome and the applied action is the record. No separate audit log file.

## Severity Rubric

| Level | Meaning                                                                | Action                     |
| ----- | ---------------------------------------------------------------------- | -------------------------- |
| P0    | Broken — will crash, lose data, or create security vulnerability       | Must fix before proceeding |
| P1    | Wrong — incorrect behavior, logic error, missing edge case             | Must fix before proceeding |
| P2    | Poor — code smell, maintainability issue, unclear intent, missing test | Must fix before proceeding |
| P3    | Nit — style, naming, minor suggestion                                  | May fix, does not block    |

## Revision Loop Protocol

Two revision loops enforce quality as a discipline protocol. Both follow the same pattern:

1. Run all available reviewers in parallel
2. Collect severity-tagged findings (P0/P1/P2/P3) using the rubric above
3. If P0/P1/P2 found → fix, increment counter in the workflow checklist, repeat
4. If only P3 or clean → check the box with final iteration count, proceed (P3s do not block)

**Plan review loop** (Phase 3, when entered): Claude + Codex review the plan against actual code.
Exit when: no P0/P1/P2 from all available reviewers on the same pass.
Codex is mandatory (this repo is Claude × Codex dual-engine). If Codex is unavailable, `/goal` halts and a human takes over; the loop cannot self-complete without real Codex evidence. The only ship escape is `- [x] Plan review loop — N/A: <reason>` for degraded interactive use, caught at PR review.
Note: `/fix-bug` skips Phase 3 for simple fixes (1-2 files) UNLESS the fix touches a high-impact surface (see canonical list in `references/peer-review-protocol.md`).

**Plan-stage severity — spec-loss is P1:** at the plan stage, an omission that could cause the **wrong feature to be built** is a **P1**, not a P2. This is because implementation subagents build FROM the plan's task list + test stubs, so a gap propagates and Gate 2 (code review) can only see code that is internally consistent with the _incomplete_ plan — plan-level spec-loss is invisible downstream. Classify as P1: missing required behavior, missing edge-case handling, a missing acceptance criterion needed to disambiguate implementation, or a missing test stub for a known-important behavior. Pure wording, organization, or maintainability smell stays P2. This sharpens classification only — it does **not** relax the exit; the loop still exits only on no P0/P1/P2.

**Approach comparison** (Phase 3, after brainstorming): Claude fills comparison table with fixed axes (Complexity, Blast Radius, Reversibility, Time to Validate, User/Correctness Risk). Contrarian/Codex validates the "default wins" claim. Council fires on OBJECT + high-impact surface. Spike first if cheapest falsifying test < 30 min.
If Codex unavailable: user validates skip.

**Code review loop** (Phase 5): Codex + PR Review Toolkit review the implementation.
Exit when: no P0/P1/P2 from all available reviewers on the same pass.
Codex is mandatory (this repo is Claude × Codex dual-engine). If Codex is unavailable, `/goal` halts and a human takes over; the loop cannot self-complete without real Codex evidence. The only ship escape is `- [x] Code review loop — N/A: <reason>` for degraded interactive use, caught at PR review.
Developer Demo honesty: when the PR body is a Developer Demo, an unsupported or wrong **diagram edge** — one that doesn't trace to a real `file:line` in the Evidence table (Gate 2 / claimed-current-behavior) — is a P1 finding. Gate-1 plan Briefing edges labeled `planned`/`inferred` are exempt.

**Certification + scoped re-reviews (v5.54, ADR 0009):** the loop runs FULL-scope reviews until the first pass where both engines are clean at `scope=full` on the same head — that is **certification** (record it with the deep pass below). After certification, before ANY re-review: **first refresh the default-branch ref — `git fetch origin --quiet`** (the helper itself never touches the network, so `UPSTREAM_FILES` is only as fresh as the local `origin/<default>`; a stale ref could mechanical-stamp past real upstream code movement). **If the fetch FAILS, mechanical is off the table for this round** — treat a `SCOPE_REQUIRED:mechanical` answer as `delta` (fail toward more review; the gate's own recompute stays offline/local by design — dispatch-time fetch is the freshness mechanism). Then run the scope helper — resolve it dual-path like the commands' preflight does for `default-branch.sh`: `RS="$ROOT/.claude/hooks/lib/review-scope.sh"; [ ! -f "$RS" ] && RS="$ROOT/hooks/lib/review-scope.sh"` (installed path first; Forge-internal fallback) — then `bash "$RS" .claude/local/state.md` and dispatch per `SCOPE_REQUIRED`: `mechanical` → record a single re-stamp line (no reviewer runs); `delta` → BOTH engines review the **PR-OWNED delta** from `LAST_CLEAN_HEAD` — NOT the literal two-dot diff: a post-cert merge from the default branch puts upstream code inside `git diff <base>..HEAD`, and upstream commits are NEVER findings targets (US-002) — they are interaction-analysis input only. Build the dispatch from the branch's own first-parent steps INCLUDING merge commits: `git log --first-parent <last-clean-head>..HEAD` — a post-cert conflict resolution often lives ONLY in the merge commit, so `--no-merges` would silently drop the very change that needs review. For each merge commit in that list, include its resolution evidence via `git show --remerge-diff <merge-sha>` (git ≥ 2.36 — shows only what the human/agent changed versus a clean automatic re-merge, i.e. the conflict resolutions, not the upstream payload); if `--remerge-diff` is unavailable, state the merge sha in the prompt and instruct reviewers that its conflict resolutions are in scope. Include the commit list (+ remerge-diffs) in both prompts. **Codex:** `exec review --base <last-clean-head>` (if a raw SHA is rejected, `git branch cert/<short-sha> <sha>` and pass that ref), with the scope statement + interaction clause injected via `-c developer_instructions=` (presets cannot combine with a prompt); **PR Review Toolkit:** invoke `/pr-review-toolkit:review-pr` passing the scope as its free-text argument. Canonical scope statement (both engines, pinned by contract): `Scoped delta review: findings are limited to this branch's own changes since <last-clean-head> (the PR-owned delta — commits listed below); upstream commits merged from the default branch are NOT findings targets. Also assess those incoming default-branch commits against this branch's touchpoints — files, APIs, configs, schemas, permissions, runtime behavior, dependencies.` (the toolkit's review agents take their scope from this argument; there is no --base flag — the statement IS the mechanism, and the evidence line still records base=<last-clean-head>); `full` → ancestry was broken (rebase) — full re-review, fail-closed. Evidence lines MUST carry `scope=… — base=\`<sha>\` — head=\`<sha>\`` (grammar in `state.template.md`). **Deep pass (default ON):** at certification, run ONE additional Codex NATIVE review (`exec review --base <default-branch>` — a different mode from the loop's reviews) instructed as an adversarial final audit, and record it as `codex deep-pass clean — scope=full …`. Repos may narrow this via a `## Review Configuration` section in CLAUDE.md (`deep_pass: high-impact-only` + surface list). **Interaction-surface halt:** if the interaction surface cannot be bounded (the incoming default-branch movement is too large or unintelligible to assess against the branch's touchpoints), or it touches a high-impact surface (canonical list: `references/peer-review-protocol.md`), write a `## Blockers` line and HALT for the human — never self-certify the interaction (US-002). **Scoped retries:** a degraded/failed reviewer pass is retried at the SAME scope and base — never widened autonomously. **Convergence breaker:** more than POST_CERT_REVIEW_ROUND_LIMIT (=3, canonical in `hooks/lib/review-scope.sh`) rounds past certification, or a fix round that introduces a new P0/P1 in its own delta → STOP: interactive, surface the open tail (severity + in-delta vs certified-unchanged) for the human to rule; in a `/goal` run, write a `## Blockers` line and HALT for the human (council may be invoked BY the human only — never as the risk-acceptor). The gate hook blocks ship while the breaker is tripped until the human records `- [x] Post-certification tail adjudicated by human — <decision> — head=\`<sha>\` — ts=\`<ISO8601>\`` — the agent NEVER writes that line on its own initiative. **N/A is count-preserving after certification:** if the loop line carries an iteration count, an N/A escape must keep it — `- [x] Code review loop (<N> iterations) — N/A: <reason>`; a count-less `Code review loop — N/A:` line after certification reads as breaker-counter erasure and trips the breaker (helper fail-closed).

**Evidence-line grammar (canonical — parsed by `check-workflow-gates` + `build-evidence`). Scoped evidence is recorded as a COHERENT PAIR — both engines, same scope, same base, same head; a mixed pair (e.g. codex full + pr-toolkit delta) is rejected by the gate:**

Full pair (certification, or full re-review after a rebase):

- `- [x] Code review iteration <N> — codex clean — scope=full — base=\`<merge-base-sha>\` — head=\`<sha>\``
- `- [x] Code review iteration <N> — pr-toolkit clean — scope=full — base=\`<merge-base-sha>\` — head=\`<sha>\``

Delta pair (post-certification re-review):

- `- [x] Code review iteration <N> — codex clean — scope=delta — base=\`<last-clean-head>\` — head=\`<sha>\``
- `- [x] Code review iteration <N> — pr-toolkit clean — scope=delta — base=\`<last-clean-head>\` — head=\`<sha>\``

Single lines:

- `- [x] Code review iteration <N> — mechanical re-stamp — scope=mechanical — base=\`<last-clean-head>\` — head=\`<sha>\`` (no reviewer ran — valid only when the gate's recomputation agrees)
- `- [x] Code review iteration <N> — codex deep-pass clean — scope=full — base=\`<merge-base-sha>\` — head=\`<sha>\`` (informational — never substitutes for the loop's `codex clean` row)
- `- [x] Post-certification tail adjudicated by human — <decision> — head=\`<sha>\` — ts=\`<ISO8601>\`` (HUMAN-only — unblocks a tripped breaker)

Never check a loop box until all available reviewers pass clean on the same iteration.

**Per-iteration clean evidence (enforced by `check-workflow-gates` hook on ship actions):**

For each loop, the agent MUST append a per-iteration clean line to `### Checklist` in `.claude/local/state.md`:

- **Plan review:** `- [x] Plan review iteration <N> — codex clean — plan=\`<path>\` — plan_sha=\`<sha256>\` — ts=\`<ts>\``
- **Code review (scoped — see the certification model above for the full grammar):** the first clean pass is **certification**, recorded as a `scope=full` PAIR: `- [x] Code review iteration <N> — codex clean — scope=full — base=\`<merge-base-sha>\` — head=\`<sha>\``AND`- [x] Code review iteration <N> — pr-toolkit clean — scope=full — base=\`<merge-base-sha>\` — head=\`<sha>\``. Post-certification re-reviews use the `scope=delta` pair (`base=\`<last-clean-head>\``), the `scope=mechanical` re-stamp single line, or the `scope=full` pair after a rebase — per the canonical grammar above.
  - Back-compat (legacy pre-v5.54 form): `- [x] Code review iteration <N> — codex clean — head=\`<sha>\`` is accepted ONLY as first-pass certification evidence; new workflows MUST use the scoped grammar.

The `[x] Plan review loop (N iterations) — PASS` / `[x] Code review loop (N iterations) — PASS` checkbox is checked ONLY AFTER all available reviewers report clean AND the per-iter line(s) are written. The hook blocks `git commit`, `git push`, and `gh pr create` if the loop checkbox is PASS without matching per-iter evidence.

**The only escape is N/A.** Codex is mandatory — there is no "codex unavailable" escape. For degraded interactive use only, the loop may be marked N/A:

- `- [x] Plan review loop — N/A: <reason>`
- `- [x] Code review loop — N/A: <reason>`

An N/A line skips the per-iter evidence check on ship actions (mirrors the `E2E verified — N/A:` gate) and is caught by human reviewers at PR time. An N/A escape does NOT set the evidence gate clean in `build-evidence` — so a `/forge-goal`-driven `/goal` cannot self-complete on N/A; it halts for a human if Codex is genuinely unavailable.
