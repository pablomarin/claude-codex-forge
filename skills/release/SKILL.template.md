---
name: release
description: Prepare a release PR from dev to test or test to prod with explicit human authorization.
---

# Host-Neutral Release PR

The active Claude Code or Codex host may run this canonical skill. No engine is permanently main.

## Input

- `test`: compare head `dev` with base `test`
- `prod`: compare head `test` with base `prod`

Ask for the target when it is missing or invalid. Do not infer a different branch mapping.

## Prepare

1. Read `.forge/local/state.md`, then fetch the two exact remote refs and compare
   `origin/<base>..origin/<head>` without merges. If the
   range is empty, report no release and stop.
2. Read every commit subject/body in the range. Group all included PRs into Features, Fixes,
   Improvements, and Chores; omit empty groups and list every PR in reverse chronological order.
3. Get today's date from the host system. Title the PR `TEST MM/DD` or `PROD MM/DD`.
4. Build a body with a short summary, categorized changes, and a complete PR table. Do not add a
   Test Plan section or invent details absent from the commits.

## Authorize

Show the exact base, head, title, and body. PR creation is a new external mutation: pause for explicit
human authorization bound to the prepared content. Reviewer/council/native `/goal` authority does
not transfer. After authorization, create the PR once and report its URL. If a matching PR already
exists, report that URL rather than creating a duplicate. Do not merge or promote another environment.
Keep the prepared-content fingerprint and result under `.forge/local/`.
