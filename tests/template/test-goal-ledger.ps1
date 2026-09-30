$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ledger = Join-Path $root "hooks\lib\goal-ledger.ps1"
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("forge-project-goal-ps-" + [Guid]::NewGuid().ToString("N"))
$nonce = "11111111-1111-4111-8111-111111111111"
$activation = "22222222-2222-4222-8222-222222222222"
$activation2 = "33333333-3333-4333-8333-333333333333"
$utf8 = New-Object Text.UTF8Encoding($false)

function Write-State([string]$Project, [int]$TurnCount, [string]$ActivationId = $activation, [int]$ActivationCount = 1) {
    $path = Join-Path $Project ".forge\local\state.md"
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    $text = @"
<!-- forge:state-schema v6 -->
# State

## Workflow

| Field | Value |
| --- | --- |
| Command | /new-feature smoke |
| Phase | implementation |
| Next step | continue smoke |

## /goal session

| Field | Value |
| --- | --- |
| nonce | $nonce |
| objective_hash | obj123 |
| activation_id | $ActivationId |
| activation_host | claude |
| activated_at | 2026-09-28T00:00:00Z |
| workflow_command | /new-feature smoke |
| turn_count | $TurnCount |
| turn_ceiling | $(20 * $ActivationCount) |
| activation_count | $ActivationCount |
| evidence_path | .forge/local/evidence/latest.json |
"@
    [IO.File]::WriteAllText($path, $text.Replace("`r`n", "`n"), $utf8)
    return $path
}

try {
    [IO.Directory]::CreateDirectory($scratch) | Out-Null
    $project = Join-Path $scratch "project"
    [IO.Directory]::CreateDirectory($project) | Out-Null
    & git -C $project init -q
    $state = Write-State $project 0
    & $ledger activate -Project $project -State $state
    if ($LASTEXITCODE -ne 0) { throw "PowerShell activation failed" }
    $common = (& git -C $project rev-parse --git-common-dir).Trim()
    if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $project $common }
    $common = (Resolve-Path $common).Path
    $goalRoot = Join-Path $common "forge-goals\$nonce"
    if (-not (Test-Path (Join-Path $goalRoot "activations\00000001") -PathType Leaf)) { throw "PowerShell activation record missing" }
    '{"host":"claude","session_id":"s1","turn_id":"t1"}' | & $ledger charge -Project $project -State $state -EventJson -
    if ($LASTEXITCODE -ne 0) { throw "PowerShell first charge failed" }
    '{"host":"claude","session_id":"s1","turn_id":"t1"}' | & $ledger charge -Project $project -State $state -EventJson -
    if ($LASTEXITCODE -ne 0) { throw "PowerShell duplicate charge failed" }
    '{"host":"codex","session_id":"s1","turn_id":"t1"}' | & $ledger charge -Project $project -State $state -EventJson - 2>$null
    if ($LASTEXITCODE -eq 0) { throw "PowerShell non-equivalent duplicate was accepted" }
    $turns = @(Get-ChildItem (Join-Path $goalRoot "turns") -File | Where-Object Name -Match '^\d{8}$')
    if ($turns.Count -ne 1) { throw "PowerShell duplicate Stop charged more than once" }
    $binding = [IO.File]::ReadAllText((Join-Path $goalRoot "binding"))
    if (-not $binding.Contains("format=forge-goal-ledger-v2") -or -not $binding.Contains("turn_tranche=20")) { throw "PowerShell binding schema mismatch" }
    for ($n = 2; $n -le 20; $n++) {
        $state = Write-State $project ($n - 1)
        ('{"host":"claude","session_id":"s' + $n + '","turn_id":"t' + $n + '"}') |
            & $ledger charge -Project $project -State $state -EventJson -
        if ($LASTEXITCODE -ne 0) { throw "PowerShell charge $n failed" }
    }
    $turns = @(Get-ChildItem (Join-Path $goalRoot "turns") -File | Where-Object Name -Match '^\d{8}$')
    if ($turns.Count -ne 20) { throw "PowerShell ceiling did not stop at 20" }
    if (-not (Test-Path (Join-Path $goalRoot "checkpoint") -PathType Leaf) -or
        -not (Test-Path (Join-Path $goalRoot "exhausted") -PathType Leaf)) { throw "PowerShell exhaustion artifacts missing" }
    $state = Write-State $project 20 $activation2 2
    & $ledger activate -Project $project -State $state
    if ($LASTEXITCODE -ne 0) { throw "PowerShell reactivation failed" }
    if (-not (Test-Path (Join-Path $goalRoot "activations\00000002") -PathType Leaf)) { throw "PowerShell activation 2 missing" }
    if (Test-Path (Join-Path $goalRoot "exhausted")) { throw "PowerShell reactivation did not clear derived exhaustion" }
    '{"host":"codex","session_id":"s21","turn_id":"t21"}' |
        & $ledger charge -Project $project -State $state -EventJson -
    if ($LASTEXITCODE -ne 0) { throw "PowerShell reactivated charge failed" }
    $turns = @(Get-ChildItem (Join-Path $goalRoot "turns") -File | Where-Object Name -Match '^\d{8}$')
    if ($turns.Count -ne 21) { throw "PowerShell reactivation reset or skipped turns" }
    Write-Host "PASS test-goal-ledger.ps1"
} finally {
    if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
}
