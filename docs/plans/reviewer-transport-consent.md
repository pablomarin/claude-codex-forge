# Fix reviewer transport consent

## Reproduction

A Codex main agent spawned the Forge `independent-reviewer` with a private, bounded Task 4
source/test diff. The reviewer received the payload, then returned:

```text
verdict=BLOCKED
blocked_class=authorization
blocked_reason=external Codex review of the private diff requires explicit user approval
```

The parent consequently stopped and asked the developer to approve the same disclosure.

## Root cause

Forge classifies new external mutations as human-authorized but never explicitly classifies the
expected transfer of a workflow's immutable candidate and review context to the
developer-configured Claude/Codex review services. A fresh reviewer can therefore conservatively
misclassify ordinary private-code review transport as a new external mutation. This is both a
policy and prompt-propagation gap, not missing reviewer browsing access: ordinary review is
intentionally hermetic, while `investigate` already runs as a fresh full-capability agent with the
selected host's normal network and tools. The isolated CLI reviewer deliberately strips ambient
instructions, so changing only the root policy or native reviewer role cannot reach that path.

## Immutable base

- Base ref: `main`
- Base SHA: `7c9dec604611955094a35547a6b00e9c5c95cfce`

## Minimal change

1. Add one canonical standing-consent rule: starting a Forge workflow authorizes sending its
   bounded immutable candidate snapshot, prompts, and evidence to the developer-configured
   Claude/Codex reviewer services. The candidate may include unchanged tracked repository files and
   in-scope non-ignored working-tree files. This expected transport is not an external mutation and
   must not cause a disclosure prompt.
2. State the complete-candidate boundary honestly: tracked and in-scope non-ignored content is
   authorized even when private or sensitive, and developers must remove or gitignore anything that
   must not leave their environment before the workflow. Preserve the boundary against sourcing
   additional secrets, credentials, or gitignored developer state from outside the candidate;
   paths outside the workflow worktree; other projects; arbitrary destinations; deploys;
   publication; destructive work; or other external mutation.
3. Inject that bounded authorization statement into every isolated dispatcher review prompt and
   tell the native independent reviewer the supplied candidate already crossed the authorized
   transport boundary. Privacy or unchanged tracked files alone are not authorization blockers.
4. Keep ordinary review hermetic. Keep normal network/tools only in `investigate`.
5. Document the distinction in the opinion and permissions references and changelog.

## Changed paths

- `FORGE.template.md`
- `agents/independent-reviewer.md`
- `commands/opinion.md`
- `hooks/lib/agent-dispatch.sh`
- `hooks/lib/agent-dispatch.ps1`
- `docs/reference/permissions.md`
- `docs/CHANGELOG.md`
- focused dispatcher/contract tests under `tests/template/`

No broad `network_access=true`, permission-profile change, or adapter policy duplication. Add the
changelog entry inside the existing `## 6.0 — 2026-08-27` section; do not change the release/version
heading or installer version pin.

## Regression test

The focused contract suite must fail unless:

- canonical workflow policy classifies the complete immutable workflow candidate transport to the
  configured reviewer services as already authorized and not an external mutation;
- the independent reviewer cannot block solely because the supplied candidate is private,
  sensitive, contains unchanged tracked files, or includes in-scope non-ignored content;
- policy and reviewer prompts retain the boundary against sourcing additional secrets,
  credentials, gitignored or outside-worktree state, other projects, arbitrary destinations,
  deploys, publication, destructive work, and any other external mutation;
- the actual isolated Bash and PowerShell reviewer prompts receive that authorization boundary;
- ordinary review remains hermetic and investigation remains the only full-agent network profile;
- installed copies preserve those contracts.

## Acceptance criteria

- A fresh Forge reviewer treats a private bounded candidate sent to configured Claude/Codex services
  as authorized review input without asking again.
- Reviewers still cannot source additional secrets or perform arbitrary outbound access or external
  mutations.
- Investigators retain the selected host's normal main-agent-equivalent capabilities and existing
  human mutation boundaries.
- Bash contract/materialization tests pass; platform parity remains unchanged.
- Existing `network_access = false` remains unchanged.

## User-journey coverage

This is agent workflow policy, not a product UI/API/CLI journey. E2E is N/A; deterministic contract
and downstream materialization tests own the supported behavior.
