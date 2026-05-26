# state.md fixture: Code review loop PASS with valid per-iter HEAD evidence

# Expected: check-workflow-gates allows (exit 0) once **FAKE_HEAD_SHA** resolved

# to the current HEAD sha.

## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — head=`__FAKE_HEAD_SHA__`
- [x] Code review iteration 1 — pr-toolkit clean — head=`__FAKE_HEAD_SHA__`
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
