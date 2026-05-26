# state.md fixture: Plan review loop PASS with valid per-iter evidence

# Expected: check-workflow-gates allows (exit 0) once placeholders resolved

# **FAKE_PLAN_SHA** → sha256 of the test plan file

# **FAKE_HEAD_SHA** → current HEAD sha

## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [x] Plan review loop (3 iterations) — PASS
- [x] Plan review iteration 3 — codex clean — plan=`docs/plans/fake-plan.md` — plan_sha=`__FAKE_PLAN_SHA__` — ts=`2026-05-26T17:00:00Z`
- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — head=`__FAKE_HEAD_SHA__`
- [x] Code review iteration 1 — pr-toolkit clean — head=`__FAKE_HEAD_SHA__`
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
