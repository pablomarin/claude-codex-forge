# The Complete Workflow

How a feature goes from idea to merged PR.

The diagram uses Claude Code's slash-command spellings for readability. Codex exposes the same
canonical workflows as `$workflow-*` skills; see the [commands map](../reference/commands.md).

```
┌─────────────────────────────────────────────────────────────┐
│ 1. START: Launch a Workflow Command                         │
│    /new-feature {name} → creates isolated git worktree      │
│    /fix-bug {name}     → creates isolated git worktree      │
│    /quick-fix {name}   → creates a branch (small changes)   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. PRD PHASE (Custom Commands)                              │
│    /prd:discuss {feature}  → Refine user stories            │
│    /prd:create {feature}   → Generate structured PRD        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. RESEARCH — `research-first` agent (Phase 2 enforcement)  │
│    → Context7 + official docs + changelogs per dependency   │
│    → Produces structured brief in `docs/research/`          │
│    → Design phase reads this before any planning starts     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. DESIGN + BOUNDED REVIEW                                 │
│                                                             │
│    ┌───────────────────────────────────────────┐            │
│    │ a. /superpowers:brainstorming             │            │
│    │    → Interactive design exploration       │            │
│    │    → Followed by /council contrarian gate │            │
│    │      after approach comparison            │            │
│    └──────────────────┬────────────────────────┘            │
│                       ▼                                     │
│    ┌───────────────────────────────────────────┐            │
│    │ b. /superpowers:writing-plans             │            │
│    │    → Write detailed TDD tasks             │            │
│    └──────────────────┬────────────────────────┘            │
│                       ▼                                     │
│    ┌───────────────────────────────────────────┐            │
│    │ c. Main host + fresh opinion review plan  │◄──┐        │
│    │    → Two independent validations          │   │        │
│    │    → Other engine, else fresh same-engine │   │        │
│    └──────────────────┬────────────────────────┘   │        │
│                       ▼                            │        │
│              ┌────────────────┐                    │        │
│              │ P0/P1/P2?      │── Yes ──► Edit ────┘        │
│              └───────┬────────┘          plan               │
│                      No                                     │
│                      ▼                                      │
│              No P0/P1/P2s → Plan approved ✓                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. EXECUTE (Superpowers Plugin)                             │
│    /superpowers:subagent-driven-development                 │
│    → TDD enforced (RED-GREEN-REFACTOR)                      │
│    → Dispatch Plan (DAG) controls parallelism               │
│    → Auto-format on save (ruff/prettier)                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 5b. DEBUG (if bugs encountered)                             │
│    /superpowers:systematic-debugging                        │
│    → 4-phase root cause analysis                            │
│    → NO fixes without investigation first                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. PRELIMINARY REVIEW (fixes still allowed)                │
│                                                             │
│    ┌──────────────────────┐ ┌────────────────────────────┐  │
│    │ Fresh code-spec lens │ │ Fresh code-quality lens     │ │
│    │ → Fresh requirements │ │ → Fresh quality lens        │ │
│    │   conformance lens   │ │   on the same candidate     │ │
│    └──────────┬───────────┘ └─────────────┬───────────────┘ │
│               └──────────┬────────────────┘                 │
│                          ▼                                  │
│               ┌─────────────────────┐                       │
│               │ P0/P1/P2 issues?    │── Yes ──► Fix ──┐     │
│               └──────────┬──────────┘                 │     │
│                          No (P3s acceptable)     ┌────┘     │
│                          ▼                       │          │
│               Reviews passed ✓       ◄───────────┘          │
│                         (closure: named findings only)      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. SIMPLIFY + FREEZE                                       │
│    Forge-owned simplification phase                        │
│    → Cleans up architecture, improves readability           │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 8. FINAL REVIEW + VERIFY                                    │
│    → Fresh opinion receipts over the frozen candidate      │
│    "Use the verify-app agent"                               │
│    → Unit tests + migrations + lint + types                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 9. E2E USE CASE TESTS (if user-facing changes)              │
│    "Use the verify-e2e agent"                               │
│    → Feature mode: validate new user journeys               │
│    → Regression mode: replay tests/e2e/use-cases/ suite     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 10. COMPOUND LEARNINGS                                      │
│    docs/solutions/ + auto memory                            │
│    → Bug root causes, patterns, solutions saved             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 11. COMMIT & CREATE PR                                      │
│    → Update .forge/local/state.md (Done/Now/Next)           │
│    → Update docs/CHANGELOG.md (if 3+ files changed)         │
│    → git add, commit, push to origin                        │
│    → gh pr create                                           │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 12. WAIT FOR PR REVIEWS                                     │
│    → Copilot, Claude, Codex auto-review on GitHub           │
│    → Peer reviews from other developers                     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 13. PROCESS PR REVIEW COMMENTS                              │
│    /review-pr-comments                                      │
│    → Address comments from all reviewers                    │
│    → Fix issues, push, wait for approval                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 14. FINISH                                                  │
│    /finish-branch                                           │
│    → Merge PR to main (if not already merged)               │
│    → Delete remote branch                                   │
│    → Delete local branch + worktree                         │
│    → Restart servers from main                              │
└─────────────────────────────────────────────────────────────┘
```

## Native `/goal` with Forge Composition (Layer 2)

When the workflow's gate checkpoint passes (PRD-complete for `/new-feature`; Plan-Approved for
`/fix-bug`), Forge composes the current host's native `/goal` over the shared objective, nonce,
durable budget, checklist, evidence, authorization, and exact next step in `.forge/local/state.md`.
Claude Code and Codex sessions are not transferable: switching hosts starts a fresh native session
from that checkpoint.

### Checkpoint placement asymmetry

| Command              | Checkpoint    | Trigger                                                         |
| -------------------- | ------------- | --------------------------------------------------------------- |
| `/new-feature`       | PRD-Complete  | After Phase 1 PRD created, before Phase 2 Research              |
| `/fix-bug` (complex) | Plan-Approved | After Phase 3.3 Plan Review Loop passes, before Phase 4 Execute |
| `/fix-bug` (simple)  | None          | Simple fixes skip Phase 3 and have no plan file to drive from   |
| `/quick-fix`         | None          | Trivial changes are not eligible for autonomous loop            |

### What the loop does

- Reads `.forge/local/state.md` each turn (the workflow checklist + objective nonce)
- Surfaces candidate-bound evidence via `.forge/hooks/build-evidence.sh`
- Uses the active host's qualified native `/goal`; a native exit alone is never completion proof
- Stops for user input, PR creation, merge/deploy/publish, destructive or security-sensitive work,
  and every new external mutation
- Invokes `/council` instead of pausing for the user on any other ambiguous decision

### When NOT to use it

- Trivial changes (`/quick-fix` flow) — autonomous loop is overkill
- When you want to review each phase by hand
- When the active host cannot prove all native-goal Must behaviors (`RUNTIME_READY=BLOCKED`)

### Disabling it

Decline the autonomous loop offer at the checkpoint and the workflow falls back to the standard phase-by-phase flow.

## Why This Workflow?

Based on Boris Cherny's key insight:

> "Probably the most important thing to get great results out of Claude Code — **give Claude a way to verify its work**. If Claude has that feedback loop, it will **2-3x the quality** of the final result."

The harness operationalizes that insight across every phase for whichever host is main:

- **Research** gives the main host current docs (not stale training data)
- **Plan review** gives it a fresh second opinion _before_ writing code
- **TDD** gives it executable tests as its verification loop
- **Code review** gives it fresh spec and quality lenses on one frozen candidate
- **Simplify + verify + E2E** add candidate-bound evidence before commit
- **PR reviewers + `/review-pr-comments`** add review _after_ the PR is open
- **`docs/solutions/` + Forge memory** preserve verified learning

Review is deliberately bounded: one broad review, one repair pass, and one closure review limited to
named findings and direct regressions. P3, cosmetic, and speculative concerns do not keep the loop
open. A reachable P0/P1 security, correctness, or data-integrity defect still blocks; one surgical
repair and verification is allowed before Forge surfaces any remaining blocker to the developer.

The active host invokes the opinion workflow with its native name: Claude Code uses `/opinion` and
Codex uses `$opinion`. Both hosts reserve `/review` for native behavior. Host switches preserve
`.forge/local/state.md`, but simultaneous editing can overwrite work; Forge warns and does not add
locks or leases.
