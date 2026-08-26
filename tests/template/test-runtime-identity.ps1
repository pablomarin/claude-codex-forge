$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$claude = Get-Content -Raw (Join-Path $root "tests\template\fixtures\host-events\claude-2.1.237.json") | ConvertFrom-Json
if ($claude.modelUsage.PSObject.Properties.Name -ne "claude-opus-4-1") { throw "Claude model fixture drift" }
if ($claude.modelUsage.'claude-opus-4-1'.provider -ne "anthropic") { throw "Claude provider fixture drift" }
$codexLines = Get-Content (Join-Path $root "tests\template\fixtures\host-events\codex-0.144.1.jsonl")
if (($codexLines | Select-String '"model"|"provider"|"effort"').Count -ne 0) { throw "Codex fixture invents identity" }
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("forge-task2-ps-dispatch-" + [Guid]::NewGuid().ToString("N"))
try {
    $project = Join-Path $scratch "project"
    New-Item -ItemType Directory -Path (Join-Path $project ".forge") -Force | Out-Null
    & git -C $project init -q
    & git -C $project config user.email forge@example.invalid
    & git -C $project config user.name Forge
    [IO.File]::WriteAllText((Join-Path $project "caller.txt"), "caller`n")
    & git -C $project add caller.txt
    & git -C $project commit -qm caller
    $fake = Join-Path $scratch "fake-engine.ps1"
    @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
if ($Arguments[0] -eq "--version") { Write-Host "$env:FORGE_FAKE_ENGINE_NAME 1.0"; exit 0 }
switch ($env:FORGE_DISPATCH_FIXTURE_ACTION) {
  "ephemeral" {
    if ($env:FORGE_FAKE_CANARY_LEAK -eq "1") { Write-Host "FORGE_CANARY_LEAK" }
    else { Write-Host "ephemeral:$env:FORGE_DISPATCH_SENTINEL`:canary=false" }
  }
  "council-start" {
    New-Item -ItemType Directory -Path $env:FORGE_DISPATCH_SESSION_STORE -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $env:FORGE_DISPATCH_SESSION_STORE $env:FORGE_DISPATCH_SESSION_ID), $env:FORGE_DISPATCH_SEAT_HASH)
    Write-Host "thread.started:$env:FORGE_DISPATCH_SESSION_ID"
  }
  "council-resume" {
    $seat = [IO.File]::ReadAllText((Join-Path $env:FORGE_DISPATCH_SESSION_STORE $env:FORGE_DISPATCH_SESSION_ID))
    if ($seat -cne $env:FORGE_DISPATCH_SEAT_HASH) { exit 75 }
    Write-Host "thread.resumed:$env:FORGE_DISPATCH_SESSION_ID"
  }
  "investigate" {
    New-Item -ItemType Directory -Path (Join-Path $env:FORGE_DISPATCH_INVESTIGATION_ROOT "artifacts") -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $env:FORGE_DISPATCH_INVESTIGATION_ROOT "artifacts\qualification.txt"), "bounded-reproduction`n")
  }
  default { exit 76 }
}
exit 0
'@ | Set-Content -LiteralPath $fake -Encoding UTF8
    $qualify = Join-Path $root "scripts\qualify-dispatch-isolation.ps1"
    foreach ($engine in @("claude", "codex")) {
        $output = Join-Path $scratch "$engine.json"
        & $qualify -Engine $engine -ProjectRoot $project -Output $output -FixtureMode -EnginePath $fake | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$engine deterministic dispatch fixture failed" }
        $receipt = Get-Content -Raw $output | ConvertFrom-Json
        if ($receipt.status -ne "PASS" -or $receipt.ephemeral -ne "PASS" -or $receipt.council_resume -ne "PASS" -or $receipt.investigation_replay -ne "PASS") { throw "$engine incomplete PASS receipt" }
    }
    $previousLeak = $env:FORGE_FAKE_CANARY_LEAK
    try {
        $env:FORGE_FAKE_CANARY_LEAK = "1"
        $blockedOutput = Join-Path $scratch "codex-leak.json"
        & $qualify -Engine codex -ProjectRoot $project -Output $blockedOutput -FixtureMode -EnginePath $fake | Out-Null
        if ($LASTEXITCODE -eq 0) { throw "canary leak was accepted by PowerShell dispatch qualification" }
        if ((Get-Content -Raw $blockedOutput | ConvertFrom-Json).status -ne "BLOCKED") { throw "canary leak did not produce a truthful BLOCKED receipt" }
    } finally { $env:FORGE_FAKE_CANARY_LEAK = $previousLeak }

    $liveFake = Join-Path $scratch "fake-live-engine.ps1"
    @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
if ($Arguments[0] -eq "--version") { Write-Host "$env:FORGE_FAKE_ENGINE_NAME 9.9"; exit 0 }
if ($Arguments[0] -eq "--help" -or ($Arguments -contains "--help")) { Write-Host "--safe-mode --strict-mcp-config --setting-sources --session-id --resume --no-session-persistence --add-dir --ignore-user-config --ignore-rules --ephemeral --sandbox --json --disable"; exit 0 }
$joined = $Arguments -join " "
[IO.File]::AppendAllText($env:FORGE_FAKE_ARGV_LOG, "$env:FORGE_FAKE_ENGINE_NAME`t$joined`n")
if ($joined -match 'FORGE_INVESTIGATION') {
  if ($env:FORGE_FAKE_DISPATCH_FAILURE -eq "path-escape") { [IO.File]::WriteAllText((Join-Path $env:FORGE_FAKE_ESCAPE_TARGET "escaped.txt"), "escape-attempt`n") }
  else {
    New-Item -ItemType Directory -Path (Join-Path $env:FORGE_DISPATCH_INVESTIGATION_ROOT "artifacts") -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $env:FORGE_DISPATCH_INVESTIGATION_ROOT "artifacts\qualification.txt"), "bounded-reproduction`n")
    if ($env:FORGE_FAKE_DISPATCH_FAILURE -eq "undeclared") { [IO.File]::WriteAllText((Join-Path $env:FORGE_DISPATCH_INVESTIGATION_ROOT "undeclared.txt"), "bad`n") }
    if ($env:FORGE_FAKE_DISPATCH_FAILURE -eq "no-clobber") { New-Item -ItemType Directory -Path (Join-Path $env:FORGE_DISPATCH_REPLAY_TARGET "artifacts") -Force | Out-Null; [IO.File]::WriteAllText((Join-Path $env:FORGE_DISPATCH_REPLAY_TARGET "artifacts\qualification.txt"), "keep`n") }
  }
  $candidateId = $env:FORGE_DISPATCH_CANDIDATE_ID; if ($env:FORGE_FAKE_DISPATCH_FAILURE -eq "candidate") { $candidateId = "wrong-candidate" }
  Write-Host "candidate_id=$candidateId`ncanary_observed=false"; exit 0
}
if ($env:FORGE_FAKE_ENGINE_NAME -eq "claude") {
  if ($joined -match '--no-session-persistence' -and $joined -notmatch 'FORGE_INVESTIGATION') { $canary = if ($env:FORGE_FAKE_CANARY_RESULT) { $env:FORGE_FAKE_CANARY_RESULT } else { "false" }; Write-Host "sentinel=$env:FORGE_DISPATCH_SENTINEL`ncanary_observed=$canary"; exit 0 }
  $seat = $env:FORGE_DISPATCH_SEAT_HASH; if ($env:FORGE_FAKE_DISPATCH_FAILURE -eq "cross-seat" -and $joined -match '--resume') { $seat = "wrong-seat" }
  Write-Host "session_id=$env:FORGE_DISPATCH_SESSION_ID`nseat_hash=$seat`nconfig_hash=$env:FORGE_DISPATCH_CONFIG_HASH`ncanary_observed=false"; exit 0
}
if ($joined -match '--ephemeral') { $canary = if ($env:FORGE_FAKE_CANARY_RESULT) { $env:FORGE_FAKE_CANARY_RESULT } else { "false" }; Write-Host "{`"type`":`"item.completed`",`"sentinel`":`"$env:FORGE_DISPATCH_SENTINEL`",`"canary_observed`":$canary}"; exit 0 }
$seat = $env:FORGE_DISPATCH_SEAT_HASH; if ($env:FORGE_FAKE_DISPATCH_FAILURE -eq "cross-seat" -and $joined -match 'exec resume') { $seat = "wrong-seat" }
if ($joined -match 'FORGE_COUNCIL_START') { Write-Host "{`"type`":`"thread.started`",`"thread_id`":`"$env:FORGE_DISPATCH_SESSION_ID`"}" }
Write-Host "{`"type`":`"turn.completed`",`"thread_id`":`"$env:FORGE_DISPATCH_SESSION_ID`",`"seat_hash`":`"$seat`",`"config_hash`":`"$env:FORGE_DISPATCH_CONFIG_HASH`",`"canary_observed`":false}"
'@ | Set-Content -LiteralPath $liveFake -Encoding UTF8
    foreach ($engine in @("claude", "codex")) {
        $env:FORGE_FAKE_ENGINE_NAME = $engine
        $env:FORGE_FAKE_ARGV_LOG = Join-Path $scratch "$engine-live.argv"
        $liveOutput = Join-Path $scratch "$engine-live.json"
        & $qualify -Engine $engine -ProjectRoot $project -Output $liveOutput -TestLiveDriver -EnginePath $liveFake | Out-Null
        if ($LASTEXITCODE -ne 0 -or (Get-Content -Raw $liveOutput | ConvertFrom-Json).status -ne "PASS") { throw "$engine guarded live driver failed" }
        $argv = [IO.File]::ReadAllText($env:FORGE_FAKE_ARGV_LOG)
        if ($argv -notmatch 'FORGE_COUNCIL_START' -or $argv -notmatch 'FORGE_INVESTIGATION') { throw "$engine live command construction incomplete" }
    }
    foreach ($failure in @("cross-seat", "canary", "candidate", "undeclared", "path-escape", "no-clobber")) {
        $env:FORGE_FAKE_ENGINE_NAME = "codex"; $env:FORGE_FAKE_DISPATCH_FAILURE = $failure; $env:FORGE_FAKE_CANARY_RESULT = if ($failure -eq "canary") { "true" } else { "" }
        $env:FORGE_FAKE_ESCAPE_TARGET = $project; $env:FORGE_FAKE_ARGV_LOG = Join-Path $scratch "$failure.argv"
        $blocked = Join-Path $scratch "$failure.json"
        & $qualify -Engine codex -ProjectRoot $project -Output $blocked -TestLiveDriver -EnginePath $liveFake | Out-Null
        if ($LASTEXITCODE -eq 0 -or (Get-Content -Raw $blocked | ConvertFrom-Json).status -ne "BLOCKED") { throw "$failure was accepted by PowerShell live qualification" }
    }
    Remove-Item Env:FORGE_FAKE_DISPATCH_FAILURE -ErrorAction SilentlyContinue
    Remove-Item Env:FORGE_FAKE_CANARY_RESULT -ErrorAction SilentlyContinue
    Write-Host "PASS test-runtime-identity.ps1"
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
