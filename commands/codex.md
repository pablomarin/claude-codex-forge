# /codex — Deprecated Transitional Shim (Tasks 5–8)

`/codex` is retained temporarily so existing feature, bug, rule, and skill callers do not dangle
while they are converted. It no longer launches Codex directly.

Read `.forge/workflows/review.md` completely and execute `/review` with the original `$ARGUMENTS`.
Preserve the old General/design/code/investigate intent, but map it to the host-neutral dispatcher:

- the current native host is the main agent;
- the legacy command's reviewer request is `--engine codex`;
- ordinary fallback is automatic and visible;
- council calls use `--fallback-policy none`;
- all results use the Forge v6 receipt/envelope contracts under `.forge/local/reviews/`.

Do not copy the former Codex-specific prompt, sandbox, or output logic into this shim. Task 9 removes
and tombstones it only after every live caller resolves to `/review`.
