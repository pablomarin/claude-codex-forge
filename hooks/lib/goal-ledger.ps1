#!/usr/bin/env pwsh
# Repository-local, worktree-shared accounting for native Goal activations.

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("activate", "charge")]
    [string]$Action,
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][string]$State,
    [string]$EventJson = "",
    [Parameter(ValueFromPipeline = $true)][string]$InputObject
)

$ErrorActionPreference = "Stop"
$Utf8 = New-Object Text.UTF8Encoding($false)
$Tranche = 20
$LockPath = $null
$ExitCode = 0

function Fail([string]$Message) {
    throw [IO.InvalidDataException]::new($Message)
}

function Get-Sha256Text([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Utf8.GetBytes($Text)))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-Sha256File([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Test-Aliased([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return [bool]((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Ensure-PlainDirectory([string]$Path) {
    if (Test-Aliased $Path) { Fail "ledger ancestor is aliased: $Path" }
    if (-not (Test-Path -LiteralPath $Path)) { [IO.Directory]::CreateDirectory($Path) | Out-Null }
    if (-not (Test-Path -LiteralPath $Path -PathType Container) -or (Test-Aliased $Path)) { Fail "invalid ledger directory: $Path" }
}

function Get-RecordValue([string]$Path, [string]$Key) {
    $prefix = $Key + "="
    $matches = @([IO.File]::ReadAllLines($Path) | Where-Object { $_.StartsWith($prefix, [StringComparison]::Ordinal) })
    if ($matches.Count -ne 1) { return $null }
    return $matches[0].Substring($prefix.Length)
}

function Get-StateValue([string]$Section, [string]$Key) {
    $active = $false
    $foundValues = [Collections.Generic.List[string]]::new()
    foreach ($line in [IO.File]::ReadAllLines($State)) {
        if ($line -eq $Section) { $active = $true; continue }
        if ($active -and $line.StartsWith("## ", [StringComparison]::Ordinal)) { $active = $false }
        if ($active -and $line -match '^\|\s*([^|]+?)\s*\|\s*(.*?)\s*\|$') {
            if ($Matches[1].Trim().Equals($Key, [StringComparison]::OrdinalIgnoreCase)) { $foundValues.Add($Matches[2].Trim()) }
        }
    }
    if ($foundValues.Count -ne 1) { Fail "state field '$Key' is missing or duplicated" }
    return $foundValues[0]
}

function Write-NewFile([string]$Path, [string]$Content, [string]$Label) {
    $normalized = $Content.TrimEnd("`r", "`n") + "`n"
    try {
        $stream = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $bytes = $Utf8.GetBytes($normalized)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally { $stream.Dispose() }
    } catch [IO.IOException] {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Test-Aliased $Path) -or [IO.File]::ReadAllText($Path) -ne $normalized) {
            Fail "$Label no-clobber publication failed"
        }
    }
    if (Test-Aliased $Path) { Fail "$Label publication is aliased" }
    try { (Get-Item -LiteralPath $Path).IsReadOnly = $true } catch { }
}

function Assert-RecordShape([string]$Path, [int]$Lines, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Test-Aliased $Path)) { Fail "$Label is missing or aliased" }
    if (@([IO.File]::ReadAllLines($Path)).Count -ne $Lines) { Fail "$Label has malformed content" }
}

function Acquire-Lock([string]$Path) {
    for ($attempt = 0; $attempt -lt 300; $attempt++) {
        if (Test-Aliased $Path) { Fail "ledger lock is aliased" }
        try {
            New-Item -ItemType Directory -Path $Path -ErrorAction Stop | Out-Null
            $script:LockPath = $Path
            return
        } catch [IO.IOException] {
            Start-Sleep -Milliseconds 10
        }
    }
    Fail "ledger lock is abandoned or unavailable"
}

function Validate-Binding {
    Assert-RecordShape $Binding 5 "binding"
    if ((Get-RecordValue $Binding "format") -ne "forge-goal-ledger-v2" -or
        (Get-RecordValue $Binding "project_id") -ne $ProjectId -or
        (Get-RecordValue $Binding "nonce") -ne $Nonce -or
        (Get-RecordValue $Binding "objective_hash") -ne $Objective -or
        (Get-RecordValue $Binding "turn_tranche") -ne "$Tranche") { Fail "state/binding mismatch" }
}

function Validate-Activations {
    $entries = @(Get-ChildItem -LiteralPath $Activations -Force | Sort-Object Name)
    $ids = @()
    $expected = 1
    foreach ($entry in $entries) {
        $name = "{0:D8}" -f $expected
        if (-not $entry.Name.Equals($name, [StringComparison]::Ordinal) -or $entry.PSIsContainer) { Fail "activation sequence has a gap or invalid entry" }
        Assert-RecordShape $entry.FullName 9 "activation $name"
        $aid = Get-RecordValue $entry.FullName "activation_id"
        if ((Get-RecordValue $entry.FullName "format") -ne "forge-goal-activation-v2" -or
            (Get-RecordValue $entry.FullName "sequence") -ne "$expected" -or
            (Get-RecordValue $entry.FullName "nonce") -ne $Nonce -or
            (Get-RecordValue $entry.FullName "objective_hash") -ne $Objective -or
            [string]::IsNullOrWhiteSpace($aid) -or
            [string]::IsNullOrWhiteSpace((Get-RecordValue $entry.FullName "state_sha256"))) { Fail "activation $name is malformed" }
        if ($ids -ccontains $aid) { Fail "activation id is duplicated" }
        $ids += $aid
        $expected++
    }
    $script:ActivationRecordCount = $entries.Count
}

function Validate-Turns {
    $entries = @(Get-ChildItem -LiteralPath $Turns -Force | Sort-Object Name)
    $keys = @()
    $expected = 1
    foreach ($entry in $entries) {
        $name = "{0:D8}" -f $expected
        if (-not $entry.Name.Equals($name, [StringComparison]::Ordinal) -or $entry.PSIsContainer) { Fail "turn sequence has a gap or invalid entry" }
        Assert-RecordShape $entry.FullName 12 "turn $name"
        $key = Get-RecordValue $entry.FullName "turn_key"
        if ((Get-RecordValue $entry.FullName "format") -ne "forge-goal-turn-v2" -or
            (Get-RecordValue $entry.FullName "sequence") -ne "$expected" -or
            (Get-RecordValue $entry.FullName "nonce") -ne $Nonce -or
            (Get-RecordValue $entry.FullName "objective_hash") -ne $Objective -or
            [string]::IsNullOrWhiteSpace($key) -or
            [string]::IsNullOrWhiteSpace((Get-RecordValue $entry.FullName "turn_id")) -or
            [string]::IsNullOrWhiteSpace((Get-RecordValue $entry.FullName "state_sha256"))) { Fail "turn $name is malformed" }
        if ($keys -ccontains $key) { Fail "turn identity is duplicated" }
        $keys += $key
        $expected++
    }
    $script:TurnEntries = $entries
    $script:TurnRecordCount = $entries.Count
}

function Publish-Exhaustion {
    $checkpointContent = @"
format=forge-goal-checkpoint-v2
nonce=$Nonce
objective_hash=$Objective
turn_count=$TurnRecordCount
turn_ceiling=$TurnCeiling
workflow_command=$Workflow
phase=$Phase
next_step=$NextStep
state_sha256=$(Get-Sha256File $State)
"@
    Write-NewFile $Checkpoint $checkpointContent "checkpoint"
    $exhaustedContent = @"
FORGE_GOAL_BUDGET_EXHAUSTED
format=forge-goal-exhausted-v2
nonce=$Nonce
objective_hash=$Objective
turn_count=$TurnRecordCount
turn_ceiling=$TurnCeiling
checkpoint=$Checkpoint
checkpoint_sha256=$(Get-Sha256File $Checkpoint)
"@
    Write-NewFile $Exhausted $exhaustedContent "exhausted-marker"
}

function Test-ValidExhaustion {
    $any = (Test-Path -LiteralPath $Checkpoint) -or (Test-Path -LiteralPath $Exhausted) -or (Test-Aliased $Checkpoint) -or (Test-Aliased $Exhausted)
    if (-not $any) { return $false }
    Assert-RecordShape $Checkpoint 9 "checkpoint"
    Assert-RecordShape $Exhausted 8 "exhausted-marker"
    $first = [IO.File]::ReadAllLines($Exhausted)[0]
    if ((Get-RecordValue $Checkpoint "format") -ne "forge-goal-checkpoint-v2" -or
        (Get-RecordValue $Checkpoint "nonce") -ne $Nonce -or
        (Get-RecordValue $Checkpoint "objective_hash") -ne $Objective -or
        (Get-RecordValue $Checkpoint "turn_count") -ne "$TurnRecordCount" -or
        (Get-RecordValue $Checkpoint "turn_ceiling") -ne "$TurnCeiling" -or
        $first -ne "FORGE_GOAL_BUDGET_EXHAUSTED" -or
        (Get-RecordValue $Exhausted "format") -ne "forge-goal-exhausted-v2" -or
        (Get-RecordValue $Exhausted "checkpoint") -ne $Checkpoint -or
        (Get-RecordValue $Exhausted "checkpoint_sha256") -ne (Get-Sha256File $Checkpoint)) { Fail "checkpoint/exhausted binding mismatch" }
    return $true
}

try {
    if (-not (Test-Path -LiteralPath $Project -PathType Container) -or (Test-Aliased $Project)) { Fail "project root is missing or aliased" }
    $rootText = (& git -C $Project rev-parse --show-toplevel 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rootText)) { Fail "project is not a Git checkout" }
    $ProjectRoot = (Resolve-Path -LiteralPath $rootText).Path
    if (-not (Test-Path -LiteralPath $State -PathType Leaf) -or (Test-Aliased $State)) { Fail "active state is missing or aliased" }
    $commonText = (& git -C $ProjectRoot rev-parse --git-common-dir 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commonText)) { Fail "Git common directory is unavailable" }
    if (-not [IO.Path]::IsPathRooted($commonText)) { $commonText = Join-Path $ProjectRoot $commonText }
    if (Test-Aliased $commonText) { Fail "Git common directory is aliased" }
    $Common = (Resolve-Path -LiteralPath $commonText).Path

    $Nonce = Get-StateValue "## /goal session" "nonce"
    $Objective = Get-StateValue "## /goal session" "objective_hash"
    $ActivationId = Get-StateValue "## /goal session" "activation_id"
    $ActivationHost = Get-StateValue "## /goal session" "activation_host"
    $ActivatedAt = Get-StateValue "## /goal session" "activated_at"
    $Workflow = Get-StateValue "## /goal session" "workflow_command"
    $StateTurnCountText = Get-StateValue "## /goal session" "turn_count"
    $TurnCeilingText = Get-StateValue "## /goal session" "turn_ceiling"
    $ActivationCountText = Get-StateValue "## /goal session" "activation_count"
    $Phase = Get-StateValue "## Workflow" "Phase"
    $NextStep = Get-StateValue "## Workflow" "Next step"
    if ($Nonce -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') { Fail "invalid active nonce" }
    if ($ActivationId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') { Fail "invalid activation id" }
    if ($Objective -notmatch '^[A-Za-z0-9._-]+$') { Fail "invalid objective hash" }
    $StateTurnCount = 0
    $TurnCeiling = 0
    $ActivationCount = 0
    if (-not [int]::TryParse($StateTurnCountText, [ref]$StateTurnCount) -or $StateTurnCount -lt 0) { Fail "invalid state turn count" }
    if (-not [int]::TryParse($TurnCeilingText, [ref]$TurnCeiling) -or $TurnCeiling -lt 1) { Fail "invalid turn ceiling" }
    if (-not [int]::TryParse($ActivationCountText, [ref]$ActivationCount) -or $ActivationCount -lt 1) { Fail "invalid activation count" }
    if ($TurnCeiling -ne ($Tranche * $ActivationCount)) { Fail "turn ceiling does not match activation count" }

    $ProjectId = Get-Sha256Text $Common
    $ForgeGoals = Join-Path $Common "forge-goals"
    $GoalRoot = Join-Path $ForgeGoals $Nonce
    $Activations = Join-Path $GoalRoot "activations"
    $Turns = Join-Path $GoalRoot "turns"
    $Binding = Join-Path $GoalRoot "binding"
    $Checkpoint = Join-Path $GoalRoot "checkpoint"
    $Exhausted = Join-Path $GoalRoot "exhausted"
    $Lock = Join-Path $ForgeGoals ("." + $Nonce + ".lock")
    Ensure-PlainDirectory $ForgeGoals
    Ensure-PlainDirectory $GoalRoot
    Ensure-PlainDirectory $Activations
    Ensure-PlainDirectory $Turns
    Acquire-Lock $Lock

    if (-not (Test-Path -LiteralPath $Binding)) {
        if ($Action -ne "activate") { Fail "goal activation binding is missing" }
        $bindingContent = @"
format=forge-goal-ledger-v2
project_id=$ProjectId
nonce=$Nonce
objective_hash=$Objective
turn_tranche=$Tranche
"@
        Write-NewFile $Binding $bindingContent "binding"
    }
    Validate-Binding
    Validate-Activations
    Validate-Turns

    if ($Action -eq "activate") {
        if ($StateTurnCount -ne $TurnRecordCount) { Fail "state turn count rolled back or advanced beyond ledger" }
        if ($ActivationRecordCount -eq $ActivationCount) {
            $existing = Join-Path $Activations ("{0:D8}" -f $ActivationCount)
            if ((Get-RecordValue $existing "activation_id") -ne $ActivationId) { Fail "activation count reuses a different activation id" }
        } elseif ($ActivationRecordCount -eq ($ActivationCount - 1)) {
            $record = @"
format=forge-goal-activation-v2
sequence=$ActivationCount
nonce=$Nonce
objective_hash=$Objective
activation_id=$ActivationId
activation_host=$ActivationHost
activated_at=$ActivatedAt
workflow_command=$Workflow
state_sha256=$(Get-Sha256File $State)
"@
            Write-NewFile (Join-Path $Activations ("{0:D8}" -f $ActivationCount)) $record "activation"
        } else { Fail "activation count does not extend the ledger monotonically" }
        Validate-Activations
        if ($ActivationRecordCount -ne $ActivationCount) { Fail "activation publication count mismatch" }
        if ($ActivationCount -gt 1) {
            if ((Test-Aliased $Checkpoint) -or (Test-Aliased $Exhausted)) { Fail "derived exhaustion artifact is aliased" }
            Remove-Item -LiteralPath $Checkpoint, $Exhausted -Force -ErrorAction SilentlyContinue
        }
    } else {
        if ($EventJson -ne "-") { Fail "charge requires -EventJson -" }
        $eventText = if ($null -ne $InputObject) { $InputObject } else { [Console]::In.ReadToEnd() }
        try { $event = $eventText | ConvertFrom-Json -ErrorAction Stop } catch { Fail "event JSON is malformed" }
        $TurnId = if ($event.turn_id) { [string]$event.turn_id } elseif ($event.hook_turn_id) { [string]$event.hook_turn_id } else { [string]$event.assistant_message_id }
        if ([string]::IsNullOrWhiteSpace($TurnId) -and $event.last_assistant_message) {
            $TurnId = Get-Sha256Text ((if ($event.session_id) { [string]$event.session_id } else { "unknown" }) + "`n" + [string]$event.last_assistant_message)
        }
        if ([string]::IsNullOrWhiteSpace($TurnId)) { Fail "event has no stable turn id" }
        $Session = if ($event.session_id) { [string]$event.session_id } else { "unknown" }
        $EngineHost = if ($event.host) { [string]$event.host } elseif ($event.engine) { [string]$event.engine } else { "unknown" }
        if ($EngineHost -notin @("claude", "codex")) { $EngineHost = "unknown" }
        $TurnKey = if ($TurnId -match '^[A-Za-z0-9._-]+$') { $TurnId } else { Get-Sha256Text $TurnId }
        if ($ActivationRecordCount -ne $ActivationCount) { Fail "state activation count does not match ledger" }
        if ($StateTurnCount -gt $TurnRecordCount -or ($TurnRecordCount - $StateTurnCount) -gt 1) { Fail "state turn count rolled back or advanced beyond ledger" }
        $duplicateEntry = @($TurnEntries | Where-Object { (Get-RecordValue $_.FullName "turn_key") -eq $TurnKey } | Select-Object -First 1)
        $duplicate = $duplicateEntry.Count -gt 0
        if ($duplicate) {
            $duplicatePath = $duplicateEntry[0].FullName
            if ((Get-RecordValue $duplicatePath "turn_id") -ne $TurnId -or
                (Get-RecordValue $duplicatePath "activation_count") -ne "$ActivationCount" -or
                (Get-RecordValue $duplicatePath "host") -ne $EngineHost -or
                (Get-RecordValue $duplicatePath "session_id") -ne $Session -or
                (Get-RecordValue $duplicatePath "state_sha256") -ne (Get-Sha256File $State) -or
                (Get-RecordValue $duplicatePath "phase") -ne $Phase -or
                (Get-RecordValue $duplicatePath "next_step") -ne $NextStep) { Fail "duplicate turn identity has non-equivalent content" }
        } else {
            if (Test-ValidExhaustion) {
                [Console]::Error.WriteLine("FORGE_GOAL_BUDGET_EXHAUSTED: checkpoint=$Checkpoint")
            } else {
                if ($TurnRecordCount -ge $TurnCeiling) { Fail "turn ceiling reached without valid exhaustion checkpoint" }
                $next = $TurnRecordCount + 1
                $turnRecord = @"
format=forge-goal-turn-v2
sequence=$next
nonce=$Nonce
objective_hash=$Objective
activation_count=$ActivationCount
turn_id=$TurnId
turn_key=$TurnKey
host=$EngineHost
session_id=$Session
state_sha256=$(Get-Sha256File $State)
phase=$Phase
next_step=$NextStep
"@
                Write-NewFile (Join-Path $Turns ("{0:D8}" -f $next)) $turnRecord "turn"
                Validate-Turns
                if ($TurnRecordCount -eq $TurnCeiling) {
                    Publish-Exhaustion
                    [Console]::Error.WriteLine("FORGE_GOAL_BUDGET_EXHAUSTED: checkpoint=$Checkpoint")
                }
            }
        }
    }
} catch {
    [Console]::Error.WriteLine("FORGE_GOAL_LEDGER_TAMPERED: " + $_.Exception.Message)
    $ExitCode = 2
} finally {
    if ($LockPath -and (Test-Path -LiteralPath $LockPath -PathType Container)) {
        Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
    }
}

exit $ExitCode
