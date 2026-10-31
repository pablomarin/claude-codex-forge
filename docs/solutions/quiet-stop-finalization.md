# Quiet Stops and changelog finalization

Ordinary Stop events now allow a reply to finish even when the workflow checkpoint is unchanged
or more than three files have changed. The Bash and PowerShell hooks no longer count changed
files, require a root changelog edit, query GitHub for an open PR, or publish a last-Stop hash.
Canonical state validation, active Goal accounting and budgets, finalization receipt advisories,
and the independent shipping gates remain.

The canonical [finalization policy](../../rules/workflow.md#changelog-finalization) requires a
single consolidated entry for a completed change set after implementation, preliminary checks
and simplification, before the final candidate is frozen and merged. The state template no longer
routes progress notes into release history or requests per-task changelog entries. The canonical
policy explicitly supersedes that wording in older preserved local state templates.

Install and upgrade no longer create a root customer changelog. Existing customer histories are
preserved byte-for-byte, including a nested application's history. Forge's own source release
history remains `docs/CHANGELOG.md`, and installed Forge version metadata remains separate.
This change does not delete, combine or rename previously created customer files.

Regression coverage exercises both host registrations, repeated active and completed workflow
Stops, multi-file branches, nested application histories, linked event working directories,
invalid state and shipping controls, and native Goal ledger idempotence. Installer tests exercise
fresh install, upgrade and full refresh with absent, nested and multiple existing histories.
The Bash suite is registered in the release runner; Windows discovers its PowerShell twin.

Portable PowerShell and registered-hook fixtures qualify those tested contracts. They do not
certify an authenticated Desktop session or native Windows PowerShell 5.1. Existing checkpoint
hash sidecars are unused. Existing legacy waiver scope names remain readable without making a
waiver necessary for ordinary replies. The quick-fix path-budget exception still covers only the
exact root metadata paths; a nested customer changelog counts toward its existing path limit.
