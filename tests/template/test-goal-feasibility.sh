#!/usr/bin/env bash
# Deterministic authorization-boundary fixtures. Does not call either engine.
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO_ROOT/tests/template/lib.sh"
init_counters

# Task 5's project-local ledger is the deterministic feasibility contract.
bash "$REPO_ROOT/tests/template/test-goal-ledger.sh"
exit $?
