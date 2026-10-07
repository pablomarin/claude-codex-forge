#!/usr/bin/env bash
# Portable PS7 runner check: tiny disposable suites, never the broad suites.
set -u
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) printf 'SKIP: POSIX PowerShell runner fixture; native Windows coverage belongs to CI\n'; exit 0 ;;
esac
source_root=$(cd "$(dirname "$0")/../.." && pwd)
runtime=$(command -v pwsh) || { printf 'SKIP: portable PowerShell runner check requires pwsh\n'; exit 0; }
fixture=$(mktemp -d "${TMPDIR:-/tmp}/forge-runner-fixture.XXXXXX") || exit 2
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/tests/template" "$fixture/bin"
cp "$source_root/tests/template/run-all.ps1" "$fixture/tests/template/run-all.ps1"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$runtime" > "$fixture/bin/powershell.exe"
chmod +x "$fixture/bin/powershell.exe"
printf 'Write-Host "fixture-failure-executed"; exit 7\n' > "$fixture/tests/template/test-a-fail.ps1"
printf 'Write-Host "fixture-success-executed"; exit 0\n' > "$fixture/tests/template/test-b-pass.ps1"
PATH="$fixture/bin:$PATH" "$runtime" -NoProfile -File "$fixture/tests/template/run-all.ps1" > "$fixture/result.log" 2>&1
status=$?
cat "$fixture/result.log"
failed=0
check() { if "$@"; then printf 'PASS runner: %s\n' "$*"; else printf 'FAIL runner: %s\n' "$*"; failed=$((failed+1)); fi; }
check test "$status" -ne 0
check grep -q 'fixture-failure-executed' "$fixture/result.log"
check grep -q 'fixture-success-executed' "$fixture/result.log"
check grep -qE 'SUITE_START name=test-a-fail.ps1 utc=[0-9]{4}-' "$fixture/result.log"
check grep -qE 'SUITE_END name=test-a-fail.ps1 exit=7 elapsed_s=[0-9.]+ utc=[0-9]{4}-' "$fixture/result.log"
check grep -qE 'SUITE_START name=test-b-pass.ps1 utc=[0-9]{4}-' "$fixture/result.log"
check grep -qE 'SUITE_END name=test-b-pass.ps1 exit=0 elapsed_s=[0-9.]+ utc=[0-9]{4}-' "$fixture/result.log"
check grep -q 'PowerShell suites failed: test-a-fail.ps1' "$fixture/result.log"
exit "$failed"
