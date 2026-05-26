# state.md fixture: Plan review loop checked PASS with no per-iter evidence

# Expected: check-workflow-gates rejects (exit 2)

## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [x] Plan review loop (3 iterations) — PASS
- [x] Code review loop (1 iterations) — PASS
- [x] Code review iteration 1 — codex clean — head=`abcdef0123456789abcdef0123456789abcdef01`
- [x] Code review iteration 1 — pr-toolkit clean — head=`abcdef0123456789abcdef0123456789abcdef01`
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work, no user-facing changes
