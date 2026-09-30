#!/usr/bin/env pwsh
# Project-only native Goal qualification. The deterministic phase never calls
# an engine; the optional live phase uses the native authenticated client.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][string]$EvidenceDir,
    [Parameter(Mandatory = $true)][ValidateSet('none', 'claude', 'codex')][string]$Live,
    [string]$LiveEvidence = ''
)

$ErrorActionPreference = 'Stop'
$Utf8 = [Text.UTF8Encoding]::new($false)

function Get-Hash([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($Path)
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Get-TextHash([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Utf8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-EvidenceFields([string]$Path) {
    $result = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $index = $line.IndexOf('=')
        if ($index -le 0) { continue }
        $key = $line.Substring(0, $index)
        if ($result.ContainsKey($key)) { throw "duplicate operator evidence field: $key" }
        $result[$key] = $line.Substring($index + 1)
    }
    return $result
}

function Write-State([string]$Root, [int]$TurnCount, [string]$Nonce, [string]$Activation, [string]$Objective) {
    $path = Join-Path $Root '.forge\local\state.md'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    $body = @"
<!-- forge:state-schema v6 -->
# Goal qualification

## Workflow

| Field | Value |
| --- | --- |
| Command | /new-feature project-only-goal-qualification |
| Phase | verification |
| Next step | verify deterministic Goal accounting |

## /goal session

| Field | Value |
| --- | --- |
| nonce | $Nonce |
| objective_hash | $Objective |
| activation_id | $Activation |
| activation_host | codex |
| activated_at | 2026-09-29T00:00:00Z |
| workflow_command | /new-feature project-only-goal-qualification |
| turn_count | $TurnCount |
| turn_ceiling | 20 |
| activation_count | 1 |
| evidence_path | .forge/local/evidence/goal-qualification.json |
"@
    [IO.File]::WriteAllText($path, $body.Replace("`r`n", "`n"), $Utf8)
    return $path
}

$Project = (Resolve-Path -LiteralPath $Project).Path
if ($Live -eq 'none' -and $LiveEvidence) { throw 'LiveEvidence requires a live host' }
if (-not (Test-Path -LiteralPath (Join-Path $Project '.forge') -PathType Container)) {
    [Console]::Error.WriteLine('GOAL_DETERMINISTIC: BLOCKED reason=materialized-project-required')
    exit 3
}
$top = (& git -C $Project rev-parse --show-toplevel 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $top) {
    [Console]::Error.WriteLine('GOAL_DETERMINISTIC: BLOCKED reason=git-project-required')
    exit 3
}
$Project = (Resolve-Path -LiteralPath $top).Path
if (-not [IO.Path]::IsPathRooted($EvidenceDir)) { $EvidenceDir = Join-Path $Project $EvidenceDir }
[IO.Directory]::CreateDirectory($EvidenceDir) | Out-Null
$EvidenceDir = (Resolve-Path -LiteralPath $EvidenceDir).Path
$evidenceItem = Get-Item -LiteralPath $EvidenceDir -Force
if ($evidenceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    [Console]::Error.WriteLine('GOAL_DETERMINISTIC: BLOCKED reason=evidence-directory-invalid')
    exit 3
}

$scriptRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
if ($scriptRoot -match '[\\/]\.forge[\\/]bin$') {
    $ledger = Join-Path (Split-Path (Split-Path $scriptRoot -Parent) -Parent) '.forge\hooks\lib\goal-ledger.ps1'
} else {
    $ledger = Join-Path (Split-Path $scriptRoot -Parent) 'hooks\lib\goal-ledger.ps1'
}
if (-not (Test-Path -LiteralPath $ledger -PathType Leaf)) {
    [Console]::Error.WriteLine('GOAL_DETERMINISTIC: BLOCKED reason=repository-ledger-helper-missing')
    exit 3
}

$nonce = '11111111-1111-4111-8111-111111111111'
$activation = '22222222-2222-4222-8222-222222222222'
$objective = Get-TextHash 'forge-project-only-goal-qualification-v1'
$runDir = Join-Path $EvidenceDir ('deterministic-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + $PID)
$primary = Join-Path $runDir 'project'
$linked = Join-Path $runDir 'linked'
[IO.Directory]::CreateDirectory($primary) | Out-Null
& git -C $primary init -q
& git -C $primary config user.email forge@example.invalid
& git -C $primary config user.name Forge
[IO.File]::WriteAllText((Join-Path $primary 'app.txt'), "qualification`n", $Utf8)
& git -C $primary add app.txt
& git -C $primary commit -qm base
& git -C $primary branch linked
& git -C $primary worktree add -q $linked linked
if ($LASTEXITCODE -ne 0) { throw 'linked-worktree setup failed' }

$primaryState = Write-State $primary 0 $nonce $activation $objective
$linkedState = Write-State $linked 0 $nonce $activation $objective
& $ledger activate -Project $primary -State $primaryState
if ($LASTEXITCODE -ne 0) { throw 'Goal activation failed' }
'{"host":"codex","session_id":"qualification","turn_id":"q1"}' | & $ledger charge -Project $primary -State $primaryState -EventJson -
if ($LASTEXITCODE -ne 0) { throw 'first Goal charge failed' }
'{"host":"codex","session_id":"qualification","turn_id":"q1"}' | & $ledger charge -Project $linked -State $linkedState -EventJson -
if ($LASTEXITCODE -ne 0) { throw 'linked-worktree duplicate charge failed' }
for ($n = 2; $n -le 20; $n++) {
    $primaryState = Write-State $primary ($n - 1) $nonce $activation $objective
    ('{"host":"codex","session_id":"qualification","turn_id":"q' + $n + '"}') |
        & $ledger charge -Project $primary -State $primaryState -EventJson - 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Goal charge $n failed" }
}

$commonText = (& git -C $primary rev-parse --git-common-dir | Out-String).Trim()
if (-not [IO.Path]::IsPathRooted($commonText)) { $commonText = Join-Path $primary $commonText }
$common = (Resolve-Path -LiteralPath $commonText).Path
$goalRoot = Join-Path $common "forge-goals\$nonce"
$turns = @(Get-ChildItem -LiteralPath (Join-Path $goalRoot 'turns') -File | Where-Object Name -Match '^\d{8}$')
if ($turns.Count -ne 20 -or -not (Test-Path (Join-Path $goalRoot 'checkpoint') -PathType Leaf) -or
    -not (Test-Path (Join-Path $goalRoot 'exhausted') -PathType Leaf)) {
    throw 'ledger ceiling or checkpoint qualification failed'
}

$status = 'PASS'
$liveStatus = 'NOT_REQUESTED'
$reason = 'deterministic-project-ledger-pass'
$enginePath = ''
$engineVersion = ''
$liveOutputHash = ''
$operatorEvidencePath = ''
if ($Live -ne 'none') {
    $command = Get-Command $Live -ErrorAction SilentlyContinue
    if (-not $command) {
        $status = 'BLOCKED'; $liveStatus = 'BLOCKED'; $reason = 'binary-unavailable'
    } else {
        $enginePath = $command.Source
        $engineVersion = ((& $enginePath --version 2>$null) | Select-Object -First 1)
        if (-not $LiveEvidence) {
            $status = 'BLOCKED'; $liveStatus = 'BLOCKED'; $reason = 'interactive-native-goal-evidence-required'
        } elseif (-not (Test-Path -LiteralPath $LiveEvidence -PathType Leaf) -or
            ((Get-Item -LiteralPath $LiveEvidence -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $status = 'BLOCKED'; $liveStatus = 'BLOCKED'; $reason = 'operator-evidence-invalid'
        } else {
            $operatorEvidencePath = (Resolve-Path -LiteralPath $LiveEvidence).Path
            try {
                $fields = Get-EvidenceFields $operatorEvidencePath
                $head = ((& git -C $Project rev-parse HEAD) | Select-Object -First 1)
                $tree = ((& git -C $Project rev-parse 'HEAD^{tree}') | Select-Object -First 1)
                $valid = $fields.schema -ceq 'forge.native-goal-operator-evidence.v1' -and
                    $fields.evidence_mode -ceq 'operator-observed' -and $fields.result -ceq 'PASS' -and
                    $fields.host -ceq $Live -and $fields.project_root -ceq $Project -and
                    $fields.git_head -ceq $head -and $fields.tree_sha -ceq $tree -and
                    $fields.activation_observed -ceq 'true' -and $fields.progress_observed -ceq 'true' -and
                    $fields.stop_observed -ceq 'true'
            } catch { $valid = $false }
            if ($valid) {
                $liveStatus = 'READY'; $reason = 'operator-observed-native-goal-pass'
                $liveOutputHash = Get-Hash $operatorEvidencePath
            } else {
                $status = 'BLOCKED'; $liveStatus = 'BLOCKED'; $reason = 'operator-evidence-invalid'
            }
        }
    }
}

$receiptPath = Join-Path $EvidenceDir 'goal-qualification.json'
$receipt = [ordered]@{
    schema = 'forge.goal-feasibility.v2'; status = $status; project = $Project
    objective_hash = $objective; deterministic = 'PASS'; global_harness = 'NOT_REQUIRED'
    live_host = $Live; live_status = $liveStatus; reason = $reason
    engine_path = $enginePath; engine_version = $engineVersion
    operator_evidence_path = $operatorEvidencePath
    ledger_binding_sha256 = Get-Hash (Join-Path $goalRoot 'binding')
    checkpoint_sha256 = Get-Hash (Join-Path $goalRoot 'checkpoint')
    live_output_sha256 = $liveOutputHash
}
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Compress) + "`n", $Utf8)
Write-Host "GOAL_DETERMINISTIC: PASS evidence=$receiptPath"
Write-Host 'GLOBAL_HARNESS: NOT_REQUIRED'
if ($Live -ne 'none') {
    if ($liveStatus -eq 'READY') { Write-Host "GOAL_LIVE: READY host=$Live evidence=$receiptPath" }
    else { Write-Host "GOAL_LIVE: BLOCKED host=$Live reason=$reason evidence=$receiptPath" }
}
if ($status -eq 'PASS') { exit 0 }
exit 1
