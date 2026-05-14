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

Originally skipped (Option A off the table per EXP 1 FAIL). However, after Pablo's strategic pivot toward using NATIVE `/goal` instead of building Option B, this question became newly-critical and was run as a refined EXP 4 (AskUserQuestion pause/resume). EXP 5 (subagent dispatch) and EXP 6 (multi-action turn) were added.

### EXP 4 result (AskUserQuestion pause/resume — added during pivot)

**Date run:** 2026-05-13 (late session, after pivot)

**Setup:** Pablo typed `/goal complete only after Pablo answers any question I ask via AskUserQuestion. Call AskUserQuestion once with a simple yes/no.` Claude called AskUserQuestion with a yes/no about overlay visibility. Pablo answered "No — overlay gone" via the AskUserQuestion UI.

**Observed:**

- Goal paused while AskUserQuestion modal was up (loop blocked on user input — expected)
- During the modal, the `◎ /goal active` overlay was **hidden** (Pablo confirmed)
- After Pablo answered, the loop **did not auto-clear** — kept producing Stop hook feedback
- First verifier pass: flagged ambiguity (`stop_hook_active: false` in metadata despite hook clearly firing)
- Second verifier pass: returned "Condition status: SATISFIED" — but goal still did not auto-clear cleanly
- Pablo had to manually type `/goal clear` to escape

**Verdict:** **WEAK PASS / PARTIAL FAIL** — AskUserQuestion works mechanically inside `/goal` but does NOT reliably trigger goal completion.

**Critical implication for the forge:**

**Do NOT make AskUserQuestion answers the direct `/goal` completion condition.** They don't reliably auto-clear. Instead, use the pattern: **AskUserQuestion is the TRIGGER; a side-effect file or Bash output is the GATE.** The agent asks the user (via AskUserQuestion), then on a YES answer runs a Bash command that produces transcript evidence (e.g., `touch .claude/state/pr-authorized`) which the verifier matches.

### EXP 5 result (subagent dispatch — added during pivot)

**Date run:** 2026-05-13 (late session)

**Setup:** Pablo typed `/goal complete only after Claude has dispatched an Explore subagent (Agent tool with subagent_type=Explore) and the subagent's results appear in this transcript.` Claude called `Agent(subagent_type="Explore", prompt="find any 3 .md files in this repo")`. Subagent returned 3 file paths.

**Observed:**

- Subagent dispatch worked cleanly via Agent tool
- Subagent results (3 markdown file paths) appeared in transcript
- First verifier pass: SAME `stop_hook_active: false` transient state bug as EXP 4 (this time on the very first Stop hook fire, before any AskUserQuestion involvement — so the bug is general, not AskUserQuestion-specific)
- Second verifier pass: **self-corrected** (`stop_hook_active: true` restored), recognized the condition as satisfied
- Goal **auto-cleared cleanly** — overlay stopped (Pablo confirmed)

**Verdict:** **PASS** with state-instability caveat — auto-clear works for transcript-evidence completion; the lifecycle state bug is real but transient (self-resolves within 1-2 verifier passes).

### EXP 6 — deferred

Multi-action-turn test (Bash + Read + assistant output in one turn). Not run; EXP 4 + EXP 5 already produced the critical lessons. Marked optional for future curiosity.

### Combined picture (EXP 4 + EXP 5)

The contrast between EXP 4 and EXP 5 is decisive:

| Completion trigger | Auto-clear? |
|---|---|
| **AskUserQuestion answer** | ❌ Does NOT auto-clear; required manual `/goal clear` |
| **Subagent dispatch + transcript evidence** | ✅ Auto-clears cleanly |
| **Bash output in transcript** (proto-EXP-2) | ✅ Auto-clears cleanly |
| **User types literal token in message** (EXP 2 absence) | ✅ Auto-clears cleanly |

**Rule for the forge:** `/goal` reliably auto-clears on **transcript evidence**. It does NOT reliably auto-clear on **AskUserQuestion answers alone**.

The `stop_hook_active: false` transient bug appears after **any lifecycle event** (after `/goal clear`, after AskUserQuestion modal closes). Self-resolves within 1-2 verifier passes. Forge hooks need to tolerate this.

### Final decision (2026-05-13 EOD, REVISED post-pivot)

- **Option chosen:** **HYBRID** — supersedes pure Option B.
  - **Loop driver:** Anthropic's native `/goal` (not a forge-built loop).
  - **Evidence-bundle:** Forge ships `build-evidence.sh` + Stop-hook integration that emits JSON into the transcript each turn. The `/goal` verifier (Haiku) reads it.
  - **Human-input pattern:** AskUserQuestion → on user YES, agent produces concrete file/Bash evidence in the same turn (so the verifier sees both the answer AND deterministic state).
  - **One-shot rule:** ONE `/goal` per session (set after PRD, runs to PR-ready). Resetting mid-session triggers the lifecycle state bug.
- **Rationale:**
  - EXP 1 FAIL: `/forge-goal` can't be auto-invoked from a slash command. Forge must INSTRUCT the user to type `/goal` manually with the right condition. Acceptable UX.
  - EXP 2 STRICT WAIT: native verifier is robust enough to read transcript evidence reliably.
  - EXP 4 WEAK PASS: AskUserQuestion answers ≠ auto-clear. Use file-evidence pattern.
  - EXP 5 PASS: subagent dispatch works fine inside `/goal`. Council and verify-e2e fan-out is viable.
  - Anthropic's docs explicitly position `/goal` and Stop-hook as peer choices ("Pick based on what should start the next turn"). Using `/goal` as the driver is the endorsed path.
  - Forge code surface DRAMATICALLY smaller than pure Option B.
- **Next workstream (revised):**
  1. Build `build-evidence.sh` (+ PowerShell parity) — JSON evidence bundle, runs in Stop hook each turn.
  2. Define the `/goal` condition template the forge prints at end of PRD phase (e.g., *"complete when build-evidence.sh JSON shows all_gates_green=true AND PR is open AND .claude/state/pr-authorized exists"*).
  3. Update the workflow phases to produce concrete transcript evidence at each gate transition (file writes, Bash command outputs, state.md updates).
  4. Define structured reviewer output schema with `PLAN_REVISION_REQUIRED` flag.
  5. `/prd:discuss forge-goal` to formalize the user-facing flow.
- **Lifecycle / UX concerns:**
  - **No reset:** ONE `/goal` per session — don't reset mid-flow (lifecycle state bug)
  - **AskUserQuestion pattern:** never use answer-alone as completion gate; always pair with file/Bash evidence
  - **Transient verifier state bug:** hooks must tolerate 1-2 weird passes after lifecycle events
  - **Budget exhaustion messaging:** native `/goal` handles this; forge inherits Anthropic's UX
  - **Compaction:** not tested; per docs, condition survives `--resume` with counters reset; needs real-world validation
  - **Stale evidence poisoning (Codex, post-EXP-5 review):** Every `build-evidence.sh` JSON blob MUST include a goal-session nonce or timestamp. The verifier (via the condition phrasing) must require evidence produced AFTER the current `/goal` was set, AND after any AskUserQuestion answer. Without this, the verifier could rubber-stamp on stale JSON from before a reviewer raised a P1 finding or before the human-input gate. Concrete pattern: the Stop hook injects `{"session_nonce": "<uuid>", "produced_at": "<unix-ts>", ...}` and the `/goal` condition references both — *"complete when the most recent evidence JSON in transcript has session_nonce=<X> and all_gates_green=true and produced_at > <goal-set-time>"*.

### Codex's review track (chronological)

1. **Initial design exploration:** AMBER verdict with 3 constraints (artifact verifier, human-gate boundary, plan-revision escape valve) + 3 unnamed risks (budget evasion, state.md corruption, reviewer collusion).
2. **3-experiment plan stress-test:** APPROVE-WITH-REFINEMENT (split EXP 2 outcomes, reorder so EXP 1 runs first).
3. **Post-EXP-1 sanity check:** Agreed EXP 1 FAIL solid; flagged the absence-test as Codex's contribution.
4. **Post-pivot strategic re-evaluation (after Pablo proposed native `/goal`):** PIVOT-NOW. Better product fit, worse control fit. Named 9 newly-critical unknowns.
5. **Post-EXP-4+5 sanity check (this entry):** REFINE. Agreed with HYBRID superseding pure Option B. Critical addition: stale-evidence-poisoning safeguard via session nonce + produced-at timestamp.

---

## Sources

- [Claude Code /goal docs](https://code.claude.com/docs/en/goal)
- [Claude Code 2.1.139 release notes](https://github.com/anthropics/claude-code/releases)
- [Claude Code 2.1: Agent View + /goal (explainx.ai)](https://explainx.ai/blog/anthropic-claude-code-agent-view-goal-command)
- [jthack/claude-goal — community port reference](https://github.com/jthack/claude-goal)
- Codex stress-test sessions: this conversation transcript (2026-05-13).
