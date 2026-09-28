# Short Codex workflow names

Base: ccff9143fe238d23b09c6d7c03d2d5c24e46df49. User approved the naming change,
documentation updates, and ordinary reviewer transport. No commit/push/PR authorized.

## Problem and minimal solution

The managed manifest generates seven Codex skills with a redundant `workflow-`
prefix although Claude exposes the same canonical workflows without it. Rename
the seven destinations and generated names to finish-branch, fix-bug, new-feature,
prd-create, prd-discuss, quick-fix, and review-pr-comments. Canonical workflow paths,
Claude commands, reviewer transport disclosures, and workflow behavior stay intact.

Use manifest tombstones for the seven retired generated wrappers. Before ordinary
setup or transactional refresh overwrites a new short destination, require its
existing bytes to match its installed-files receipt and generated canonical identity;
otherwise block with an actionable custom-skill collision diagnostic. Retire old
wrappers only with the same ownership proof. Preserve modified/unowned old wrappers
and sibling files, with a warning. Validate paths against symlinks. Reuse current
transaction deletion/backup machinery for full refresh. Implement an explicit v6
retirement executor (existing tombstones are not executed): Bash calls the shared
Python ownership helper, PowerShell validates/removes natively. Full refresh calls
the Python inventory on the LIVE target before staging, then adds the proven old
paths to its journaled deletions; checking only the staging tree is insufficient.
Ordinary cleanup runs before installed-files.tsv is replaced. Keep native PowerShell
behavior equivalent and do not introduce a new runtime dependency there.

## Task 1: Implement and verify the naming contract

- Write behavioral tests for fresh generation, unchanged v6 upgrade, idempotence,
  modified old-wrapper preservation, custom new-name collision, and full-refresh
  preview/application. Observe RED before production edits.
- Update manifest, ownership-aware retirement, Bash/PowerShell installer paths,
  and existing test expectations. Observe GREEN.
- Update current README, reference, customization/parallel guides and changelog;
  also update host-capabilities.tsv's command surface, both setup completion banners,
  and docs/explanation/workflow.md. Preserve historical plans/changelog entries.
  Document migration and collisions, including the safe interrupted-install repair:
  move an unproven colliding skill aside, rerun setup, and manually reconcile custom
  content. A generated marker alone must never authorize overwriting edited content.
- Run focused installer/parity tests, then run-fast. Review the final diff with
  fresh spec and quality lenses; report Windows execution honestly if unavailable.

User journey: project owner installs or upgrades Forge, invokes `$fix-bug` instead
of `$workflow-fix-bug`, and gets the same canonical procedure as `/fix-bug`.
CLI installer integration is the relevant E2E surface; no application UI changed.

Acceptance: seven short entries, no duplicate proven-old adapters, no custom data
loss, no workflow-policy changes, current docs consistent, focused and fast tests green.

## Progress

- Diagnosis: adapter name is derived directly from the manifest destination directory.
- Pre-flight: manifest names are consumed by both installers, tests, and docs.
- Exact forge-v6-producer role is not exposed by this host's tools; implementation
  stays inline, with independent review rather than a fabricated role receipt.
