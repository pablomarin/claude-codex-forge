#!/usr/bin/env powershell
[CmdletBinding()]
param(
    [string]$ValidateFixture,
    [string]$Skill,
    [ValidateSet('red', 'green')][string]$Phase,
    [string]$Scenario,
    [string]$Attestation,
    [string]$RedAttestation
)

$ErrorActionPreference = 'Stop'
function Test-DecisionFixture([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing fixture: $Path" }
    $rows = Get-Content -LiteralPath $Path
    if ($rows.Count -lt 10 -or $rows[0] -cne "candidate`tdecision`tlive_callsite`tcanonical_owner`trationale") { throw 'invalid fixture schema' }
    foreach ($candidate in @('brainstorming','writing-plans','systematic-debugging','subagent-driven-development','executing-plans','requesting-review','receiving-review','simplifying-work','verifying-work')) {
        $match = @($rows | Select-Object -Skip 1 | Where-Object { ($_ -split "`t", 5)[0] -ceq $candidate })
        if ($match.Count -ne 1) { throw "candidate decision missing or duplicated: $candidate" }
        $fields = $match[0] -split "`t", 5
        if ($fields[1] -cne 'REJECTED_DUPLICATE' -or [string]::IsNullOrWhiteSpace($fields[2]) -or [string]::IsNullOrWhiteSpace($fields[3]) -or [string]::IsNullOrWhiteSpace($fields[4])) { throw "candidate rationale incomplete: $candidate" }
    }
}
function Get-ReceiptValue([string]$Path, [string]$Key) {
    $matches = @(Get-Content -LiteralPath $Path | Where-Object { $_.StartsWith($Key + '=') })
    if ($matches.Count -ne 1) { throw "receipt must have exactly one $Key field" }
    $value = $matches[0].Substring($Key.Length + 1)
    if ([string]::IsNullOrWhiteSpace($value)) { throw "receipt has empty $Key field" }
    return $value
}
function Get-ReceiptSha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Assert-Receipt([string]$Path, [string]$ExpectedPhase, [string]$ExpectedOutcome, [string]$ExpectedSkill, [string]$ExpectedScenario) {
    if ((Get-ReceiptValue $Path 'skill') -cne $ExpectedSkill -or (Get-ReceiptValue $Path 'phase') -cne $ExpectedPhase -or (Get-ReceiptValue $Path 'scenario_sha256') -cne $ExpectedScenario -or (Get-ReceiptValue $Path 'outcome') -cne $ExpectedOutcome) { throw 'receipt binding mismatch' }
    if ($ExpectedPhase -eq 'red') { [void](Get-ReceiptValue $Path 'rationalization') }
}

if ($ValidateFixture) {
    if ($Skill -or $Phase -or $Scenario -or $Attestation -or $RedAttestation) { throw '-ValidateFixture cannot be combined with qualification options' }
    Test-DecisionFixture $ValidateFixture
    exit 0
}
if (-not $Skill -or -not $Phase -or -not $Scenario -or -not $Attestation) { throw 'Skill, Phase, Scenario, and Attestation are required' }
if (-not (Test-Path -LiteralPath $Scenario -PathType Leaf)) { throw "scenario does not exist: $Scenario" }
if (-not $env:FORGE_SKILL_PRESSURE_COMMAND) { throw 'FORGE_SKILL_PRESSURE_COMMAND is required for authenticated qualification' }
if (-not (Test-Path -LiteralPath $env:FORGE_SKILL_PRESSURE_COMMAND -PathType Leaf)) { throw "qualified runner does not exist: $($env:FORGE_SKILL_PRESSURE_COMMAND)" }
$scenarioSha256 = Get-ReceiptSha256 $Scenario
if ($Phase -eq 'green') {
    if (-not $RedAttestation -or -not (Test-Path -LiteralPath $RedAttestation -PathType Leaf)) { throw 'green qualification requires a prior red attestation' }
    Assert-Receipt $RedAttestation 'red' 'NONCOMPLIANT' $Skill $scenarioSha256
    $redSha256 = Get-ReceiptSha256 $RedAttestation
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Attestation) | Out-Null
& $env:FORGE_SKILL_PRESSURE_COMMAND --skill $Skill --phase $Phase --scenario $Scenario --red-attestation $RedAttestation | Set-Content -LiteralPath $Attestation -NoNewline
if ($Phase -eq 'red') {
    Assert-Receipt $Attestation 'red' 'NONCOMPLIANT' $Skill $scenarioSha256
} else {
    Assert-Receipt $Attestation 'green' 'COMPLIANT' $Skill $scenarioSha256
    if ((Get-ReceiptValue $Attestation 'prior_red_sha256') -cne $redSha256) { throw 'GREEN attestation is not bound to the supplied RED attestation' }
}
