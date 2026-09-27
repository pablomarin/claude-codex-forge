# Reviewer proxy preservation and fresh handoff validation

Approved direction: preserve the existing host proxy environment in isolated reviewer launches,
then repeat the disposable Claude -> Codex -> Claude test. Follow KISS, YAGNI, and red/green TDD.

Base: `8c63954` (resolved immutable SHA in `.forge/local/state.md`).

## Cause and minimal repair

The live Claude run produced DNS failures from both Codex and its Claude fallback. Both isolated
launches clear the environment and omit the proxy required by the outer sandbox. Preserve only
HTTP_PROXY, HTTPS_PROXY, NO_PROXY and their lowercase variants, when present, for reviewer
processes in Bash and PowerShell. Keep all other environment isolation and reviewer permissions.
Do not forward proxy variables to the explicitly no-network reproduction runner.

Official sources checked 2026-09-13:
- https://code.claude.com/docs/en/corporate-proxy
- https://code.claude.com/docs/en/sandboxing
- https://learn.chatgpt.com/docs/config-file/config-reference

## Changes and acceptance

- `hooks/lib/agent-dispatch.sh`, `hooks/lib/agent-dispatch.ps1`: bounded proxy pass-through.
- Existing fake-engine fixtures and dispatch tests: proxy values survive primary/fallback;
  unrelated ambient variables remain excluded. Observe failure before changing production.
- Changelog: document this reachable compatibility repair and exact verification limits.
- Existing targeted Bash config guard remains unchanged: the label-only false positive is a
  documented older limitation; avoid configuration-path echo labels in the test instructions.

## Live test

Create a fresh disposable clone of he-vivi-insights and install this source candidate. Establish
a clean baseline: the installer report ignore rule conflicts with four tracked historical reports;
in the disposable clone only, preserve those files with explicit ignore exceptions. Run the
repository boundary check and baseline tests before the handoff. Use scripts/forge_handoff_smoke.py
and tests/test_forge_handoff_smoke.py so the example respects the repository boundary.

Start a blank Claude UI session: activate workflow, record acceptance, produce RED, stop. Start a
fresh Codex process in the exact checkout: resume, implement, GREEN, freeze, stop before review.
Start a second blank Claude UI session: resume, begin iteration once, review, verify, certify.
Inspect state/receipts read-only between legs. Do not repair their workflow artifacts to force PASS.
Require push simulation blocked before certification, allowed after SHIP_READY:true, then blocked
again after an intentional mutation. No real push, PR, promotion, or customer-worktree change.

Run focused dispatch tests and run-fast once after repair. Final distinct code-spec/code-quality
reviews apply to the frozen source candidate. Record Windows runtime and all-GUI limitations.
