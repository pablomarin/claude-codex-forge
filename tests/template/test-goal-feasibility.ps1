$ErrorActionPreference = "Stop"
$ledgerSuite = Join-Path $PSScriptRoot "test-goal-ledger.ps1"
& $ledgerSuite
exit $LASTEXITCODE
