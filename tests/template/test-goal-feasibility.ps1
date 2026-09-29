$ErrorActionPreference = "Stop"
$ledgerSuite = Join-Path $PSScriptRoot "test-goal-ledger.ps1"
& $ledgerSuite
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach ($retired in @(
    'scripts\forge-goal-authorize.sh', 'scripts\forge-goal-authorize.ps1',
    'scripts\forge-goal-capture.sh', 'scripts\forge-goal-capture.ps1'
)) {
    if (Test-Path -LiteralPath (Join-Path $root $retired)) { throw "retired active helper still exists: $retired" }
}
$qualifier = Join-Path $root 'scripts\qualify-goal-feasibility.ps1'
$source = Get-Content -LiteralPath $qualifier -Raw
$retiredAuthorization = 'goal-' + 'authorizations'
$retiredCapture = 'goal-' + 'captures'
if ($source.Contains($retiredAuthorization) -or $source.Contains($retiredCapture)) {
    throw 'PowerShell goal qualification still depends on a machine-global harness'
}
Write-Host 'PASS: PowerShell project-only goal qualification contract'
