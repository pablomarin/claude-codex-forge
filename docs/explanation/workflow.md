# The Complete Workflow

Forge v6 owns the engineering lifecycle for both Claude Code and Codex. Superpowers and
other workflow plugins are not required. Claude command spellings below have matching
Codex skills such as `$fix-bug`; see the [commands map](../reference/commands.md).

## Feature and bug-fix paths

| Phase | Feature | Bug fix | Evidence or result |
| --- | --- | --- | --- |
| Start or resume | `/new-feature` | `/fix-bug` | Existing isolated worktree, immutable base and canonical local state |
| Understand | PRD and current dependency research | Exact reproduction, working control and root-cause investigation | Observable acceptance criteria and supported failure |
| Plan | Compare viable approaches and write bounded tasks | Write the minimal repair and regression plan | Fresh configured plan review; bounded repair and closure |
| Implement | Tasks in dependency order | Smallest root-cause repair | Producer follows RED → GREEN → refactor, with actual task evidence |
| User journey | Preliminary feature E2E while fixes are allowed | Preliminary regression journey while fixes are allowed | Actor, scenario, interface, steps, meaningful outcome and persistence |
| Finalize | Solution/release material and simplification | Solution/release material and simplification | One staged-clean candidate fingerprint |
| Certify | Distinct fresh spec and quality reviews, verify-app and E2E | Same candidate-bound gates | Real reports and receipts; mutation invalidates the final set |
| Promote | Exact-tree promotion and commit | Same | Revalidated candidate and shipping gates |
| Publish | Authorized push and PR creation | Same | Human approval for the exact current external action |
| Finish | Process review comments, then `/finish-branch` | Same | Exact reviewed head and CI, authorized merge and safe cleanup |

The canonical feature and bug-fix workflows define the detailed steps; the
[commands map](../reference/commands.md) identifies both host entry points. Installed copies
live under `.forge/workflows/`; the table is an explanation, not a second executable policy.
Bug fixes include diagnosis and a reviewed plan. Do not skip planning by labeling a full
bug-fix workflow "simple".

The producer reports the intended RED failure, GREEN results and unresolved concerns.
Tests must exercise the owned behavior with independent expectations; source text and
schema assertions certify their actual contracts, not agent obedience. Debugging locates
the first incorrect boundary using safe evidence and working controls, rather than a chain
of guessed patches. These practices are owned by Forge's canonical rules and roles.

## Quick fixes

`/quick-fix` is the narrow alternative for trivial supported changes. The main agent runs
one obvious focused check directly; ship hooks validate its clean recorded base and scope
limit. It dispatches no code-review or verifier agents. User-facing effects, uncertainty,
higher risk or scope growth move work to `/fix-bug` or `/new-feature`.

## Review and verification

Ordinary review prefers the other engine and visibly falls back to a fresh same-engine
reviewer if necessary. Findings are a completed review, not a fallback trigger.
Review defaults to one broad review, one repair and one closure limited to named findings
and direct regressions. Concrete material P0/P1/P2 defects block certification; advisory
P3 suggestions do not justify perpetual polish. Only the human adjudicates an exhausted
canonical review limit.

Use focused owning checks and the project's fast local gate. Exhaustive local suites need
an explicit request. Native Windows and authenticated host behavior require their own
evidence; portable or synthetic checks cannot stand in for them. Process success or a
confident producer report alone cannot certify an unchanged or changed candidate.

The installed `.forge/rules/workflow.md` owns receipt validity, review budgets,
resource discipline and current-session shipping. State remains in `.forge/local/state.md`;
verified durable project knowledge belongs in `.forge/memory/` and solution documentation.

## Native `/goal` composition

Forge composes over the active host's native `/goal` only after the developer invokes it
or explicitly requests native Goal autonomy. It records the objective, nonce, persistent
budget, checklist, evidence and exact next step. An offered checkpoint does not activate
Goal or grant publication authority.

Switching hosts starts a fresh native session from shared state; native conversation
history does not transfer. Ordinary review fallback remains automatic. User input,
consequential external actions and exhausted budgets retain their human boundaries.
When required native behavior is unverified, report the missing qualification rather
than claiming runtime readiness. See [native Goal composition](autonomous-goal.md).
