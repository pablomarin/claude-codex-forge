# Reviewer execution settings repair

## Approved outcome and immutable base

Ordinary reviews must request Claude Opus 5.5 or GPT-6-Astra, extra-high (`xhigh`) effort,
vendor fast mode, and exactly 1,200 seconds per attempt, including fallback and closure.
The developer selected the full fix-bug scope and confirmed 20 minutes. A timeout is a
ceiling, not a required runtime.

- Base ref: `main`
- Base SHA: `6ab5214fd2dc5ae49e77e26f7c15bd9649dfe7ec`
- Branch: `fix/reviewer-execution-settings`

## Reproduction and proven cause

Recent msai-v2 calls explicitly supplied `--timeout-seconds 600`; he-vivi-insights supplied
`180`. The dispatcher defaults to 1200 but accepts every positive override. These shorter
budgets cause premature termination and fallback. Claude's ordinary-review capability row
also requests `max`, whereas the developer's desired extra-high setting is `xhigh`.
V5 had complete launch examples; V6's opinion workflow abbreviates them with `run ...`.

## Minimal implementation

1. Change only Claude's `model-certifying` capability row to `xhigh`, including its mechanism.
   Preserve Codex's correct ordinary profile and the dedicated council effort profiles.
2. In both agent-dispatch platform twins, reject non-1200 production `review` timeouts before
   candidate capture or engine launch. Retain positive-integer validation, existing `investigate`
   configurability, and shortened timeouts under the existing deterministic test mode.
3. Add `timeout_seconds` and `requested_fast_mode=true` to invocation receipts on both platforms.
   Include both in invocation configuration hashing. Report requested settings, not an
   unobservable provider guarantee. Existing identity, isolation and authorization checks remain.
4. Add a binding paragraph to FORGE.template.md, and complete Claude-host and Codex-host
   examples in commands/opinion.md. Resolve the immutable base ref/SHA from workflow state;
   provide engine, fallback, role/profile, artifact, prompt/output and `--timeout-seconds 1200`.
   The dispatcher selects model/effort/fast mode; do not introduce direct vendor launch recipes.
   Forbid shortening outer deadlines or terminating a reviewer merely because it is silent.
5. Add focused behavioral tests in tests/template/test-agent-dispatch.sh; align the existing
   model assertions in tests/template/test-platform-parity.sh. Update docs/CHANGELOG.md to
   6.4.2 and the README badge. Do not change installer ownership or historical release prose.

## Regression and acceptance checks

- Refuse 180, 600 and above-1200 production review timeouts before candidate/engine side effects.
- Accept explicit and default 1200. Preserve shortened deterministic fixture controls.
- Exercise both Bash and PowerShell policy behavior, using existing fake engines for successful
  calls; no live engine or twenty-minute wait belongs in the deterministic regression suite.
- Ordinary Claude launches request `xhigh`; Codex remains `xhigh`. Both host directions and
  fallback retain their existing vendor fast mode.
- Receipts and invocation hashes bind the actual requested timeout and fast mode.
- Run owning dispatch and parity checks, then tests/template/run-fast.sh. Inspect the final diff.

## Journey coverage and boundaries

This changes the internal harness, with no application UI/API/user journey. Harness acceptance
is the executable rejection and successful isolated fixture path on both platforms. Record a
candidate-bound N/A report for application E2E alongside harness verification evidence.
Commit, push, PR, merge and downstream installation require separate developer authorization.

## Approved review-mode clarification (2026-10-03)

The developer approved correcting the misleading disposable-investigation description and
regression coverage, and explicitly rejected any extra consent or permission question for reviews.
Standing approval therefore covers ordinary review and full-agent investigation launches,
including investigation selected by the main agent from the task's actual requirements.
No new authorization token, prompt, or dispatcher gate is part of this change.

- Ordinary reviews remain isolated and read-only. Select full-agent investigation when the task
  requires live project tools, services, network or worktree writes; explain the selection without
  asking permission. A permission denial or timeout alone must never switch review to investigation.
- Correct rules/workflow.md to describe real-worktree investigation. Align FORGE.template.md,
  commands/opinion.md, docs/reference/permissions.md, docs/explanation/codex-investigate.md and the
  current Desktop qualification journeys. Preserve normal host security and destructive/external
  mutation boundaries; standing launch approval is not approval to ship or mutate external systems.
- Update both scripts/materialize-adapters platform twins so installed native descriptions do not
  claim investigation is excluded from standing launch approval. Preserve thin adapters.
- Align owning policy/materialization contracts with the approved behavior. Add behavioral dispatch
  coverage that permission failures cannot grant investigation capabilities or broader fallback
  access, using fake engines only. Existing role/profile validation and sandbox settings remain.
- Pressure-test the consuming agent with ordinary-review, live-investigation and permission-failure
  scenarios. Deterministic tests cannot establish actual Desktop prompt behavior.
- Keep this within the same unreleased 6.4.2 change set and update its changelog entry. Run focused
  owning checks plus the fast local gate; refreeze and obtain fresh final paired/verifier receipts.
