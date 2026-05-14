# /forge-goal — Go/No-Go Experiment Plan

> **Status:** pre-decision research. This document defines the experiments that determine whether claude-codex-forge adopts **Option A** (wrap Anthropic's `/goal`) or **Option B** (forge-native loop) for autonomous post-plan workflow execution.
>
> **Authored:** 2026-05-13 (Pablo + Claude Opus 4.7 + Codex gpt-5.5 xhigh).

---

## Background

Anthropic shipped `/goal` in Claude Code 2.1.139 (2026-05-12). `/goal` takes a natural-language completion condition and loops the agent across turns until a Haiku-class verifier deems the condition met, or a budget (turns/tokens/time) is exhausted.

The forge's existing workflow philosophy is heavily gated: every commit/push/PR is conditional on a checklist in `.claude/local/state.md`, with hook enforcement for evidence artifacts (E2E reports with mtime check, reviewer-pass-on-same-iteration, etc.).

We're evaluating **`/forge-goal`** — a thin wrapper that lets the agent autonomously drive Phase 4 → 5 → 6 of `/new-feature` (TDD → code-review-loop → E2E) after the plan is approved, stopping at human-required gates (PR creation, merge).

## Two candidate shapes

| | **Option A** — wrap `/goal` | **Option B** — forge-native loop |
|---|---|---|
| Loop driver | Anthropic's `/goal` + Haiku verifier | Forge Stop hook + `build-evidence.sh` |
| Budget tracking | Free from Anthropic | Reinvent (turn counter, token approximation) |
| CC version requirement | 2.1.139+ | Any |
| Forge code surface | Small | Larger |
| Risk if `/goal` changes | High | None |

## Known facts (from research)

- **Verifier is text-only.** Per Anthropic docs, the `/goal` verifier (Haiku) reads condition + transcript-so-far and returns yes/no + reason. It does NOT call tools. So evidence-bundle script output must reach the transcript via a **Stop-hook producer**, not via a verifier-side call.
- **AskUserQuestion is the pause mechanic.** No built-in `/goal` pause signal; the loop suspends naturally when the agent calls `AskUserQuestion` (Agent View surfaces "Needs input").
- **state.md is durable.** Re-read every turn; survives compaction. The goal condition must stay short to fit compaction text budget.

## Three open mechanical questions

| ID | Question | Decision impact |
|---|---|---|
| **Q1** | Can `/goal` be invoked from inside a slash command markdown file? | If no → Option A degrades to "print command for user to type." |
| **Q2** | Is the verifier strict, weak (rubber-stamp), or actually tool-capable? | Each branch implies a different condition-engineering approach. |
| **Q3** | Does `AskUserQuestion` mid-loop suspend `/goal` cleanly? | If no → Option A can't safely gate PR creation. |

---

## Experiment plan

### Step 1 — EXP 1: Nested invocation probe (do FIRST; ~30 sec)

The linchpin. If `/goal` can't be invoked from inside a slash command, Option A is mostly dead and we go straight to Option B.

**Setup:** Create `.claude/commands/probe-goal.md` with body:

```
/goal create the file /tmp/forge_goal_probe
```

**Run:** Invoke `/probe-goal` in a Claude Code 2.1.139+ interactive session.

**Outcomes:**

- **PASS** — `/goal` overlay panel appears with elapsed/turns/tokens. Nested invocation works. Option A is viable.
- **FAIL** — Claude treats the text as prose, no overlay. Option A degrades; default to Option B.

Record the actual observation verbatim in the results section below.

---

### Step 2 — Build the evidence primitive (regardless of EXP 1 result)

This is the actual valuable work — it ships in **both** options and strengthens existing gate hooks independently.

`.claude/hooks/build-evidence.sh` emits JSON:

```json
{
  "commit_sha": "<HEAD>",
  "branch": "<branch>",
  "branch_off_commit": "<merge-base>",
  "e2e_report": {
    "path": "tests/e2e/reports/...",
    "mtime": "<unix>",
    "valid": true
  },
  "reviewer_runs": [
    { "tool": "codex", "pass": true, "commit_at_run": "<sha>" },
    { "tool": "pr-toolkit", "pass": true, "commit_at_run": "<sha>" }
  ],
  "pr_state": { "exists": false, "number": null, "url": null },
  "all_gates_green": false
}
```

Wire it into the Stop hook (`check-state-updated.sh`) so its output is appended to the transcript after each agent turn. This primitive is:

- **In Option A:** the verifier reads the JSON from the transcript to evaluate the goal.
- **In Option B:** the forge loop checks `all_gates_green` directly.
- **In neither option:** it still strengthens `check-workflow-gates.sh` (which currently checks E2E mtime ad-hoc) by centralizing evidence validation.

PowerShell parity: `.claude/hooks/build-evidence.ps1` ships in the same PR.

---

### Step 3 — EXP 2: Verifier behavior probe (refined per Codex feedback)

Now that the evidence script exists, test how strict the verifier is. **Three distinct outcomes — do not collapse them.**

**Run (fresh session, no other goal active):**

```
/goal complete only when bash /tmp/never_exists.sh exits 0.
Do NOT fabricate the result.
Do NOT mark the goal complete unless the script has actually been run AND its output is in the transcript.
```

**Observe across ~3 turns:**

| Outcome | What we see | Design implication |
|---|---|---|
| **STRICT WAIT** | Goal stays active; Haiku consistently returns "no" with reason ~"script output not in transcript" | Verifier is rigorous → **Option A works with transcript evidence**. |
| **FALSE POSITIVE** | Goal declared met within 1-2 turns despite the script never running | Verifier is weak → **Option A needs hardened condition** (cryptographic anchor, e.g. HEAD SHA in condition + verifier checks transcript contains output stamped with that SHA), or fall back to Option B. |
| **TOOL EXECUTION** | Haiku itself runs Bash to execute the script | Docs are wrong → simplifies design (verifier can be authoritative; evidence-bundle as direct check). |

---

### Step 4 — EXP 3: Human-pause probe

**Run:**

```
/goal ask me before running 'gh pr create'; pause after asking; do not proceed without my reply
```

**Outcomes:**

- **PASS** — `AskUserQuestion` fires; goal suspends; Agent View shows "Needs input." Reply resumes the loop.
- **FAIL** — Goal ignores the question and continues looping, OR errors out. Option A can't safely gate PR creation.

---

### Step 5 — Decision matrix

| EXP 1 | EXP 2 | EXP 3 | Verdict |
|---|---|---|---|
| PASS | STRICT WAIT | PASS | **Option A** — ship as designed |
| PASS | TOOL EXECUTION | PASS | **Option A** — simplified (verifier authoritative; no Stop-hook producer needed) |
| PASS | FALSE POSITIVE | PASS | **Option A — hardened** (cryptographic anchor on evidence) OR fall back to B |
| FAIL (Q1) | * | * | **Option B** — forge-native loop using the evidence primitive |
| * | * | FAIL (Q3) | **Option B** — Option A can't safely gate human-required steps |

---

## What ships regardless of verdict

- **The evidence primitive** (Step 2). Strengthens existing gate hooks; foundation for whichever loop driver wins.
- **Structured reviewer output schema** with `PLAN_REVISION_REQUIRED` flag (separate workstream; needed by both options to close the "agent rationalizes broken plan" risk Codex flagged).

## What does NOT ship until experiments complete

- The `/forge-goal` slash command itself.
- Budget/turn-counter mechanics (Option B only; deferred until Option B is confirmed needed).
- The probe-goal stub (delete after EXP 1).

## Open questions to revisit post-experiments

- If EXP 2 shows FALSE POSITIVE: cheapest cryptographic anchor? Candidates: (a) HEAD SHA literal in condition + verifier checks transcript contains output matching that SHA, (b) Stop-hook signs JSON with an HMAC the condition references, (c) embed a per-session nonce.
- If compaction proves to drop goal state (Q4 from research, unconfirmed): add SessionStart hook that re-injects the goal condition on `resume` subtypes.
- Reviewer-schema delivery: a `PLAN_REVISION_REQUIRED` field is needed in codex/PR-toolkit/council output. Where does this live — a new state.md section, a CHANGELOG-style file, or per-finding JSON?

## Results (fill in after running)

### EXP 1 result

- **Date run:** 2026-05-13
- **Observed:**
  - **Control:** `/goal create a file at /tmp/forge_goal_control. Stop after it exists` (typed directly at user prompt) caused CC to inject a system reminder into Claude's context: *"A session-scoped Stop hook is now active with condition: ... Briefly acknowledge the goal, then immediately start (or continue) working toward it... The hook will block stopping until the condition holds. It auto-clears once the condition is met..."* This is the actual `/goal` mechanic.
  - **Probe:** `/probe-goal` (which has `/goal complete only after the file /tmp/forge_goal_probe exists...` as its markdown body) resulted in CC expanding the body and sending it to Claude as **plain prose**. No system reminder. No Stop hook activation. No goal overlay visible to user. No `/goal` dispatch.
- **Verdict:** **FAIL** — nested `/goal` invocation inside a slash-command markdown file does NOT dispatch the built-in `/goal` command. CC's command parser does not recursively re-parse expanded command bodies.

### Bonus finding — what `/goal` actually IS (mechanic exposed during control)

The `/goal` command is **not** a separate verifier API. Its implementation is:

1. A **session-scoped Stop hook** injected by CC, blocking the agent's turn-end until the condition holds.
2. A **system-reminder prompt injection** instructing the agent to treat the condition as its directive ("do not pause to ask the user what to do").
3. An **auto-clear mechanism** when the condition is met — likely Haiku-class verifier reading the transcript at Stop time, returning yes/no, releasing the Stop hook on "yes."

Implication: **the forge already owns both primitives** (Stop hooks via `check-state-updated.sh`, system reminders via hook stdout). Option B's "forge-native loop" is architecturally identical to `/goal`'s own implementation — same pattern, just with our evidence-bundle JSON as the condition and our verification logic in place of Haiku.

### EXP 2 result (absence test — proposed by Codex, run same session)

**Date run:** 2026-05-13

**Setup:** Pablo typed `/goal complete only when Pablo types "kumquat-77" in a new user message after this goal is set. Do not type "kumquat-77" yourself. Just acknowledge the goal and wait.` The agent (Claude) acknowledged minimally and then produced placeholder responses (`—`, `.`) across multiple Stop attempts WITHOUT typing the password. Pablo deliberately delayed typing the password to test whether the verifier would rubber-stamp.

**Observed across 7 Stop-hook iterations:**

The Stop hook fired 7 times. Every time, Haiku returned a detailed `no` with reasoning. The reasoning grew more granular each iteration:

- **Iteration 1:** "The transcript contains no user message from Pablo typing 'kumquat-77' after the goal was set. The only message after the goal setup is Claude's acknowledgment..."
- **Iteration 2:** Enumerated post-setup messages; distinguished "Stop hook feedback (system, not user)" from "Claude's acknowledgment."
- **Iterations 3–4:** Continued enumeration; classified my `—` and `.` outputs as "Claude placeholder responses."
- **Iteration 5:** Verifier introspected on its OWN prompt, identifying `"Based on the conversation transcript above, has the following stopping condition been satisfied?..."` as the verifier prompt and correctly marking it as a system message, not user input.
- **Iterations 6–7:** Consistent strict-no with the same classification logic.

When Pablo finally typed `kumquat-77`, the goal cleared on the next Stop attempt.

**Verdict:** **STRICT WAIT** (cleanly confirmed, 7 iterations).

**Sub-findings about Haiku-as-verifier:**

1. **Correctly distinguishes condition-text from new-evidence.** The token `kumquat-77` appears in the goal-setting message itself (twice) — Haiku ruled this doesn't count; only a NEW user message satisfies.
2. **Correctly distinguishes user messages from Claude messages from system messages.** Even when Claude's text references the password ("not typing the password"), Haiku knows Claude is not Pablo.
3. **Robust under attempted obfuscation.** Single-character placeholder responses (`—`, `.`) don't degrade reasoning quality; verifier explicitly notes "Claude placeholder responses."
4. **Self-aware about its own prompting.** Verifier identifies its own evaluation prompt as system-injected and excludes it from "user messages."

**Implication for Option B:**

The forge does NOT need to engineer hardened conditions (cryptographic anchors, signed JSON) to defend against rubber-stamping IF it uses a Haiku-class verifier. The native `/goal` verifier is robust. BUT — Option B explicitly chose deterministic Bash-script verification (not LLM) to avoid relying on Haiku stability over time. EXP 2's positive result is supportive of an Option B variant that uses Haiku as a backup/sanity-check, but the deterministic-bash primary path remains the right call.

### EXP 3 — skipped

EXP 3 was designed to test whether `/goal` honors `AskUserQuestion`-driven pauses for human-required gates (PR creation). With Option A off the table after EXP 1 FAIL, this question is moot for `/forge-goal` design — Option B controls its own Stop-hook loop and can release on any signal we choose (file existence, hook output, state.md field, etc.). Marked N/A.

### EXP 2 result (absence test)

See above ("EXP 2 result (absence test — proposed by Codex, run same session)") — moved inline for narrative continuity.

**Verdict:** STRICT WAIT confirmed across 7 iterations.

### EXP 3 result

Skipped — Option A off the table per EXP 1 FAIL; AskUserQuestion-pause question moot for Option B (forge controls its own Stop-hook release semantics).

### Final decision (2026-05-13 EOD)

- **Option chosen:** **B** — forge-native loop using existing Stop hook + system-reminder primitives.
- **Rationale:**
  - EXP 1 FAIL ruled out Option A architecturally (nested `/goal` in a slash command body does not dispatch).
  - EXP 2 STRICT WAIT removed the verifier-rubber-stamp risk concern, validating that transcript-based verification CAN be made robust — but Option B's deterministic-bash primary path was already preferred for stability reasons (Anthropic could change `/goal` semantics; the forge owns its own loop).
  - Bonus mechanic discovery: `/goal` is architecturally Stop-hook + system-reminder + verifier — the forge already owns the first two primitives. Option B isn't a reimplementation; it's the SAME pattern with a deterministic verifier instead of an LLM-class one.
- **Next workstream:**
  1. Build `build-evidence.sh` (+ PowerShell parity) — JSON evidence bundle as the deterministic verifier.
  2. Extend `check-state-updated.sh` to inject a system reminder + block stop when `/forge-goal` is active and `all_gates_green=false`.
  3. Define `/forge-goal` as a tiny launcher (flips an "active" flag in state.md; records budget).
  4. Define structured reviewer output schema with `PLAN_REVISION_REQUIRED` flag (needed regardless to close the "agent rationalizes broken plan" risk).
- **Open lifecycle/UX concerns (raised by Codex):**
  - State cleanup on completion / abort
  - Budget exhaustion messaging (must fail loudly, not silently)
  - Duplicate reminder suppression (one reminder per turn, not stacked)
  - Failure messaging — what does "stuck" look like vs `/goal`'s overlay?
  These need explicit treatment in the Option B PRD/plan.

---

## Sources

- [Claude Code /goal docs](https://code.claude.com/docs/en/goal)
- [Claude Code 2.1.139 release notes](https://github.com/anthropics/claude-code/releases)
- [Claude Code 2.1: Agent View + /goal (explainx.ai)](https://explainx.ai/blog/anthropic-claude-code-agent-view-goal-command)
- [jthack/claude-goal — community port reference](https://github.com/jthack/claude-goal)
- Codex stress-test sessions: this conversation transcript (2026-05-13).
