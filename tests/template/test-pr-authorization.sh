#!/usr/bin/env bash
# Focused publication parser regression coverage; also runs PowerShell if installed.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
python3 "$ROOT/tests/template/pr-authorization-fixture.py"
