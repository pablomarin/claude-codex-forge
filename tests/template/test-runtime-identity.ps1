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
    New-Item -ItemType Directory -Path (Split-Path -Parent $env:FORGE_DISPATCH_INVESTIGATION_ARTIFACT) -Force | Out-Null
    [IO.File]::WriteAllText($env:FORGE_DISPATCH_INVESTIGATION_ARTIFACT, "bounded-reproduction`n")
  }
  default { exit 76 }
}
exit 0
'@ | Set-Content -LiteralPath $fake -Encoding UTF8
    $qualify = Join-Path $root "scripts\qualify-dispatch-isolation.ps1"
    foreach ($engine in @("claude", "codex")) {
        $output = Join-Path $scratch "$engine.json"
        & $qualify -Engine $engine -ProjectRoot $project -Output $output -FixtureMode -EnginePath $fake | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $detail = if (Test-Path -LiteralPath $output) { Get-Content -LiteralPath $output -Raw } else { 'receipt missing' }
            throw "$engine deterministic dispatch fixture failed: $detail"
        }
        $receipt = Get-Content -Raw $output | ConvertFrom-Json
        if ($receipt.status -ne "PASS" -or $receipt.ephemeral -ne "PASS" -or $receipt.council_resume -ne "PASS" -or $receipt.investigation_full_agent -ne "PASS") { throw "$engine incomplete PASS receipt" }
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
if ($Arguments[0] -eq "--help" -or ($Arguments -contains "--help")) { Write-Host "-a --search --permission-mode --safe-mode --strict-mcp-config --setting-sources --session-id --resume --no-session-persistence --add-dir --ignore-user-config --ignore-rules --ephemeral --sandbox --json --disable"; exit 0 }
$joined = $Arguments -join " "
[IO.File]::AppendAllText($env:FORGE_FAKE_ARGV_LOG, "engine=$env:FORGE_FAKE_ENGINE_NAME cwd=$((Get-Location).Path) home=$env:HOME userprofile=$env:USERPROFILE username=$env:USERNAME argv=$joined`n")
if ($joined -match 'FORGE_INVESTIGATION') {
  New-Item -ItemType Directory -Path (Split-Path -Parent $env:FORGE_DISPATCH_INVESTIGATION_ARTIFACT) -Force | Out-Null
  [IO.File]::WriteAllText($env:FORGE_DISPATCH_INVESTIGATION_ARTIFACT, "bounded-reproduction`n")
  Write-Host "worktree=$((Get-Location).Path)`nartifact_written=true"; exit 0
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
        if ($engine -eq 'claude') {
            $userProfile = [Environment]::GetFolderPath('UserProfile')
            if ($argv -notlike "*home=$userProfile userprofile=$userProfile username=$env:USERNAME*") { throw 'Claude live qualifier did not preserve the authenticated Windows identity' }
            if ($argv -notlike '*Return exactly these four key=value lines and nothing else*') { throw 'Claude council prompt does not require the machine-bound response shape' }
            if ($argv -notlike '*return exactly these two key=value lines and nothing else*') { throw 'Claude investigation prompt does not require the machine-bound response shape' }
        }
        $investigationArgv = @($argv -split "`n" | Where-Object { $_ -match 'FORGE_INVESTIGATION' }) -join "`n"
        if ($investigationArgv -notmatch [regex]::Escape("cwd=$project") -or $investigationArgv -match '--safe-mode|--setting-sources|--ignore-user-config|--ignore-rules|--add-dir') { throw "$engine investigation is not a normal full-agent worktree process" }
        if ($engine -eq 'codex' -and ($investigationArgv -notmatch '-a on-request --search exec' -or $investigationArgv -notmatch '--sandbox danger-full-access')) { throw 'Codex investigation is missing full-capability on-request mode' }
        if ($engine -eq 'claude' -and ($investigationArgv -notmatch '--permission-mode auto' -or $investigationArgv -match '--sandbox')) { throw 'Claude investigation is missing safety-classified full-agent mode' }
    }
    foreach ($failure in @("cross-seat", "canary")) {
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
