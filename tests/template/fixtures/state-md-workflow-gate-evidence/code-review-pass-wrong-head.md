# state.md fixture: Code review loop PASS with per-iter clean lines at a STALE HEAD

# Expected: check-workflow-gates rejects (exit 2) — head never matches a real HEAD

# (literal 40-zeros sha).

## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — head=`0000000000000000000000000000000000000000`
- [x] Code review iteration 1 — pr-toolkit clean — head=`0000000000000000000000000000000000000000`
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
