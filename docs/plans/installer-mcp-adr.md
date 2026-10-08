# Preserve existing MCP registrations and the project ADR template

Workflow: fix-bug installer-mcp-adr. Immutable base: main at
2df573f8cf70a7f8a2156a8b125adc7a13baa4da (6.4.10).

## Reproduction and root cause

Actual renderer invocation with standard `[mcp_servers.context7]` hosted HTTP and
`[mcp_servers.playwright]` stdio entries adds both Forge-prefixed defaults. The bounded
block renderer preserves outside bytes but never consults the existing known entries.
The PowerShell materializer implements the same unconditional default block.

Actual full-refresh dry-run on recognized 5.61 scaffold schedules an exact released
`docs/adr/template.md` for deletion while preserving a modified project ADR README
referencing it. The legacy inventory treats that reusable template as a retired seed;
full refresh materializes canonical adapters rather than ordinary setup's ADR seeding.
Local logs: `.forge/local/evidence/installer-mcp-adr/`.

## Minimal implementation

1. In the existing Python Codex renderer and PowerShell materializer, inspect standard
   `context7` and `playwright` table registrations outside the bounded Forge block.
   Preserve every outside byte and existing transport/auth/arguments. Omit only the
   corresponding generated Forge fallback. Also omit the fallback when a customized
   safe `.mcp.json` transport translates into that standard name inside the new block;
   this prevents two copies even when the outside TOML starts empty. Replacing the managed block also removes
   a previously generated duplicate inside that block. Do not remove user-owned
   Forge-prefixed entries outside it; reuse those known prefixed registrations rather
   than creating a colliding generated table. Keep fresh defaults when neither a
   standard nor a known prefixed entry is supplied by outside config or translation.
   Ensure MCP translation does not re-add a known standard registration already present
   in the outside config. Other aliases/transports retain current behavior; no general
   deduplication, network probing, TOML dependency or configuration conversion.
2. Preserve `docs/adr/template.md` as project-owned reusable scaffold during full refresh,
   including byte-exact legacy copies. Preserve customized templates and README bytes.
   Continue retiring exact Forge-internal numbered ADRs and existing ownership guards.
   Do not introduce a new ownership schema or broad seeded-content policy change.
3. Update owning tests and concise upgrade/setup documentation. Correct guidance that
   local npx servers require Node on the agent's PATH; hosted HTTP connections do not.
   Bump one pending release to 6.4.11 in first changelog heading and README badge.

## Owned paths / acceptance

Production: `scripts/render-codex-config.py`, `scripts/materialize-adapters.ps1`,
`scripts/merge-settings.py`; only edit additional existing owners if an observed
integration boundary requires it. Tests: existing focused config/merger/layout suites
and full-refresh Bash/PowerShell fixtures, or one focused regression driver included
in the fast gate if existing large suites cannot provide cheap actual behavior coverage.
Docs: `docs/guides/upgrading.md`, `docs/guides/agent-assisted-setup.md`, changelog and badge.

Observe meaningful RED before repair, then GREEN using real renderer/materializers and
full-refresh entrypoint. Cover fresh defaults, either/both standard registrations,
hosted Context7 and custom arguments/auth preserved, managed-duplicate cleanup,
user-owned prefixed entries untouched, custom MCP translation, repeated upgrade,
malformed marker rejection, exact and modified ADR template preservation, README
link resolution and exact internal ADR retirement. Keep tests' expected bytes derived
independently from requirements. No edits to mcpgateway or global configuration.

## User journeys / final gates

Disposable projects: both recorded mains through Bash and portable PS7 installers,
routine upgrade and full-refresh where applicable; preservation of app/settings/state
and repeated operation idempotence. Portable PS7 is not native Windows5.1 qualification.
Owning focused checks then run-fast, exact staged candidate freeze, distinct configured
code-spec/code-quality reviews, fresh app and installed E2E reports/receipts. No
exhaustive local run-all. No live MCP launch/auth/network is required to verify the
configuration contract. Stop after reviewed local preparation; publication/PR/merge
requires current exact human shipping authority. No new Goal or cleanup scope.
