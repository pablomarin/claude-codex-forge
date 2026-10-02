# Forge Source Repository Context

Every merged change set or pull request MUST bump the Forge release to a new exact `MAJOR.MINOR.PATCH` version.

One merged change set receives one version bump; intermediate commits within that change set do not each require another bump.

The first release heading in `docs/CHANGELOG.md` is the source of truth for the current Forge version, and all source/materialized release boundaries MUST publish that exact three-component value.

`docs/CHANGELOG.md` MUST record every released change, including small fixes, internal workflow changes, compatibility changes, and documentation-only changes.

`README.md` MUST mention only material changes that help users understand a significant capability, workflow, compatibility, or adoption change; do not add a history row for every patch.

The README version badge MUST always equal the exact current release from the first changelog heading, even when no new README history row is warranted.

Stop review cycles at diminishing returns. If remaining findings are speculative or would add work
contrary to KISS or YAGNI, preserve and surface them instead of starting another broad review. This
does not waive concrete correctness, safety, data-integrity, or acceptance-criterion failures.
