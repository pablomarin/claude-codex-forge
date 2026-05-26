# state.md fixture: Code review loop checked PASS with no per-iter clean lines

# Expected: check-workflow-gates rejects (exit 2)

## Workflow

| Field   | Value                        |
| ------- | ---------------------------- |
| Command | /new-feature fixture-feature |
| Phase   | 5 — Quality Gates            |

### Checklist

- [x] Code review loop (2 iterations) — PASS
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified — N/A: harness work
