# state.md fixture: Plan review loop PASS with a STALE plan_sha

# Expected: check-workflow-gates rejects (exit 2) — claimed sha never matches

# the test plan file (literal 64-zeros sha).

## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [x] Plan review loop (3 iterations) — PASS
- [x] Plan review iteration 3 — codex clean — plan=`docs/plans/fake-plan.md` — plan_sha=`0000000000000000000000000000000000000000000000000000000000000000` — ts=`2026-05-26T17:00:00Z`
- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — head=`abcdef0123456789abcdef0123456789abcdef01`
- [x] Code review iteration 1 — pr-toolkit clean — head=`abcdef0123456789abcdef0123456789abcdef01`
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
