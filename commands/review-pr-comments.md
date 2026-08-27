# /review-pr-comments — Host-Neutral Review Feedback

Use after a PR receives automated or human feedback. The active Claude Code or Codex host remains
the main agent for this session; reviewer choice is independent.

## 1. Read the Current Review Set

Resolve the current PR and fetch its review summaries, inline comments, unresolved conversations,
base, and head SHA. If no PR exists, stop. Record the review-set fingerprint and current candidate
in `.forge/local/state.md`; never treat stale comments or a previous candidate receipt as current.

## 2. Evaluate Before Editing

For each comment, identify the requested change and verify it against code, requirements, and project
rules. Do not agree performatively:

- valid finding — name the affected behavior and smallest correction;
- already fixed/stale — cite the current evidence;
- incorrect or conflicting — explain the technical objection;
- ambiguous or consequential — dispatch a fresh `/opinion` with the relevant artifact and question.

Use automatic other-engine review with visible fresh same-engine fallback. A finding is not an
engine failure and never triggers fallback.

Treat the current fingerprinted review set as one broad review, use one repair pass, then one
closure review limited to named findings and direct regressions. Do not start a second broad scan
for unchanged comments/candidate. One still-open reachable P0/P1 may receive one surgical repair
and verification; then surface the blocker to the developer. P3, cosmetic, and speculative concerns
do not keep the loop open.

## 3. Repair and Re-Certify

Apply accepted fixes with TDD where behavior changes, then run focused owning checks. Run the
Forge-owned simplification phase for code mutations. Stage all intended changes, freeze a new
candidate, and rerun the final gates that the mutation can affect: distinct `code-spec` and
`code-quality` reviews, `verify-app`, and applicable E2E. Persist candidate-bound receipts under
`.forge/local/`; any later mutation invalidates affected evidence.

## 4. External Mutations

Show the exact commit and push mutations and pause for explicit human authorization. A reviewer,
council, or native `/goal` cannot authorize them. After authorization, promote the exact candidate,
commit, and push. Report which review comments are resolved, rejected with evidence, or still
blocked. Do not merge; use `/finish-branch` only after separate merge authorization.
