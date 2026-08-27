# /quick-fix — Host-Neutral Small-Change Workflow

Use only for a clearly understood, low-risk change that touches at most three files, needs no
architecture decision, and has an obvious verification path. Otherwise use `/fix-bug` or
`/new-feature`.

## Steps

1. Read `.forge/local/state.md`, resolve the active host, and record `Last active host`. Resume the
   next unchecked step after a host switch. Warn about simultaneous editing; do not lock the tree.
2. Confirm the branch is not protected. Persist the intended base ref and immutable resolved base SHA
   before the first change.
3. State the acceptance check and affected files. If behavior changes, write and observe a failing
   test first; documentation-only corrections use a direct rendered/static check instead.
4. Make the smallest change and run the owning focused check.
5. Update applicable solution/changelog material. Run the Forge-owned simplification phase only
   when code changed.
6. Force-stage only explicitly approved ignored artifacts, then `git add -A`; freeze the staged-clean
   candidate.
7. Run a fresh `code-quality` review, `verify-app`, and applicable E2E read-only against that same
   candidate. User-facing changes require the feature/regression journey matrix; non-user-facing
   changes may record E2E N/A with a concrete supported reason.
8. Any mutation invalidates affected evidence. Restage, refreeze, and rerun the affected final gates.
9. Promote the exact candidate and commit. Update `.forge/local/state.md` and verified memory.
10. Show any push/PR mutation and pause for explicit human authorization. Stop after the requested
    external action; do not merge unless separately authorized.

Reviewer `auto` uses the other installed engine and falls back automatically to a fresh same-engine
reviewer on launch/capability failure. A finding is not fallback. Reports and receipts remain under
`.forge/local/` and do not become post-verification source changes.
