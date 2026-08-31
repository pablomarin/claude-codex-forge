$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("forge-task2-ps-goal-" + [Guid]::NewGuid().ToString("N"))
$materializer = Join-Path $root "scripts\materialize-adapters.ps1"
$setup = Join-Path $root "setup.ps1"
try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null

    foreach ($scope in @("project", "global")) {
        $target = Join-Path $scratch $scope
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        if ($scope -eq "project") { & git -C $target init -q }
        & $materializer -RepoRoot $root -Target $target -Scope $scope -Platform windows | Out-Null
        $settings = Join-Path $target ".claude\settings.json"
        $profile = Get-Content -Raw $settings | ConvertFrom-Json
        foreach ($rule in @("Write(~/.forge/bin/**)", "Edit(~/.forge/bin/**)")) {
            if ($profile.permissions.deny -notcontains $rule) { throw "$scope profile does not deny $rule" }
        }
        if (@($profile.permissions.deny | Where-Object { $_ -like "Bash(*.forge/bin*" }).Count -eq 0) { throw "$scope profile does not command-gate the global Forge bin" }
        if ($profile.sandbox.filesystem.denyWrite -notcontains "~/.forge/bin") { throw "$scope sandbox does not protect the complete global Forge bin" }
        $before = [IO.File]::ReadAllBytes($settings)
        $backupBefore = @(Get-ChildItem "$settings.bak.*" -ErrorAction SilentlyContinue).Count
        & $materializer -RepoRoot $root -Target $target -Scope $scope -Platform windows | Out-Null
        $after = [IO.File]::ReadAllBytes($settings)
        $backupAfter = @(Get-ChildItem "$settings.bak.*" -ErrorAction SilentlyContinue).Count
        if ([Convert]::ToBase64String($before) -cne [Convert]::ToBase64String($after)) { throw "$scope second-run settings bytes changed" }
        if ($backupAfter -ne $backupBefore) { throw "$scope second-run created a spurious backup" }
    }

    $markerTarget = Join-Path $scratch "marker"
    New-Item -ItemType Directory -Path (Join-Path $markerTarget ".forge") -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $markerTarget ".forge\version"), "6`n")
    $prefix = [byte[]](0xEF,0xBB,0xBF) + [Text.Encoding]::UTF8.GetBytes("[Project Name] PERSONAL`r`n")
    $suffix = [Text.Encoding]::UTF8.GetBytes("`r`nPERSONAL-SUFFIX-NO-FINAL")
    $middle = [Text.Encoding]::UTF8.GetBytes("<!-- forge:begin v6 -->`r`nold`r`n<!-- forge:end v6 -->")
    foreach ($name in @("CLAUDE.md", "AGENTS.md")) { [IO.File]::WriteAllBytes((Join-Path $markerTarget $name), $prefix + $middle + $suffix) }
    & $materializer -RepoRoot $root -Target $markerTarget -Scope project -Platform windows | Out-Null
    foreach ($name in @("CLAUDE.md", "AGENTS.md")) {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $markerTarget $name))
        if ([Convert]::ToBase64String([byte[]]$prefix) -cne [Convert]::ToBase64String([byte[]]$bytes[0..($prefix.Length-1)])) { throw "$name prefix changed" }
        if ([Convert]::ToBase64String([byte[]]$suffix) -cne [Convert]::ToBase64String([byte[]]$bytes[($bytes.Length-$suffix.Length)..($bytes.Length-1)])) { throw "$name suffix changed" }
    }

    foreach ($surface in @("skills", "agents")) {
        foreach ($mode in @("default", "force", "upgrade")) {
            $legacy = Join-Path $scratch "legacy-$surface-$mode"
            New-Item -ItemType Directory -Path (Join-Path $legacy ".claude\$surface\custom") -Force | Out-Null
            $leaf = if ($surface -eq "skills") { Join-Path $legacy ".claude\skills\custom\SKILL.md" } else { Join-Path $legacy ".claude\agents\custom\agent.md" }
            [IO.File]::WriteAllText($leaf, "legacy")
            $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $setup)
            if ($mode -eq "force") { $arguments += "-Force" }
            if ($mode -eq "upgrade") { $arguments += "-Upgrade" }
            $stdout = Join-Path $legacy "stdout.log"; $stderr = Join-Path $legacy "stderr.log"
            $process = Start-Process powershell.exe -ArgumentList $arguments -WorkingDirectory $legacy -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
            if ($process.ExitCode -eq 0) { throw "$surface-only $mode PowerShell preflight succeeded" }
            if ((Get-Content -Raw $stderr) -notmatch 'BLOCKED: legacy Forge harness.*setup\.ps1.*-FullRefresh.*-DryRun') { throw "$surface-only $mode did not print preview-first remediation" }
            if (Test-Path (Join-Path $legacy ".forge\version")) { throw "$surface-only $mode wrote v6 material" }
        }
    }

    foreach ($mode in @("default", "force", "upgrade")) {
        $legacy = Join-Path $scratch "legacy-exact-settings-$mode"
        New-Item -ItemType Directory -Path (Join-Path $legacy ".claude") -Force | Out-Null
        $settings = Join-Path $legacy ".claude\settings.json"
        [IO.File]::WriteAllText($settings, '{"hooks":{}}')
        $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($settings))
        $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $setup)
        if ($mode -eq "force") { $arguments += "-Force" }
        if ($mode -eq "upgrade") { $arguments += "-Upgrade" }
        $stdout = Join-Path $legacy "stdout.log"; $stderr = Join-Path $legacy "stderr.log"
        $process = Start-Process powershell.exe -ArgumentList $arguments -WorkingDirectory $legacy -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if ($process.ExitCode -eq 0) { throw "exact settings-only $mode PowerShell preflight succeeded" }
        if ((Get-Content -Raw $stderr) -notmatch 'BLOCKED: legacy Forge harness.*setup\.ps1.*-FullRefresh.*-DryRun') { throw "exact settings-only $mode did not print preview-first remediation" }
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($settings)) -cne $before) { throw "exact settings-only $mode mutated v5 bytes" }
        if (Test-Path (Join-Path $legacy ".forge\version")) { throw "exact settings-only $mode wrote v6 material" }
    }

    $goalProject = Join-Path $scratch "goal-project"
    New-Item -ItemType Directory -Path (Join-Path $goalProject ".forge") -Force | Out-Null
    & git -C $goalProject init -q
    & git -C $goalProject config user.email forge@example.invalid
    & git -C $goalProject config user.name Forge
    [IO.File]::WriteAllText((Join-Path $goalProject "tracked.txt"), "tracked`n")
    & git -C $goalProject add tracked.txt
    & git -C $goalProject commit -qm base
    $globalTarget = Join-Path $scratch "global"
    $writer = Join-Path $globalTarget ".forge\bin\forge-goal-authorize.ps1"
    $capture = Join-Path $globalTarget ".forge\bin\forge-goal-capture.ps1"
    $codexIdentity = Join-Path $globalTarget ".forge\bin\codex.identity"
    if (-not (Test-Path -LiteralPath $codexIdentity -PathType Leaf)) { throw "PowerShell global setup did not record Codex identity" }
    if (-not (Test-Path -LiteralPath "$codexIdentity.sha256" -PathType Leaf)) { throw "PowerShell Codex identity seal missing" }
    & $writer -Project $goalProject -ObjectiveHash native-goal -Nonce "88888888-8888-4888-8888-888888888888" -Ceiling 1 | Out-Null
    $authorization = Get-ChildItem (Join-Path $globalTarget ".forge\goal-authorizations") -Filter "88888888-8888-4888-8888-888888888888.auth" -File -Recurse | Select-Object -First 1
    if (-not $authorization) { throw "PowerShell authorization record missing" }

    $fakeCodex = Join-Path $scratch "operator-codex.ps1"
    @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
if ($Arguments[0] -eq "--version") { Write-Output "codex-cli 9.9.1"; exit 0 }
if (($Arguments -join " ") -eq "--help" -or ($Arguments -join " ") -eq "exec --help") { Write-Output "--ignore-user-config --ignore-rules --ephemeral --sandbox --add-dir"; exit 0 }
exit 72
'@ | Set-Content -LiteralPath $fakeCodex -Encoding UTF8
    $session = "77777777-7777-4777-8777-777777777777"
    $projectPhysical = (Resolve-Path $goalProject).Path; $cliPhysical = (Resolve-Path $fakeCodex).Path
    $transcript = Join-Path $scratch "codex.tui"; $result = Join-Path $scratch "codex.result"
    @("capture_channel=operator-codex-tui", "cli_path=$cliPhysical", "cli_version=codex-cli 9.9.1", "session_id=$session", "project_root=$projectPhysical", "command=/goal", "/goal activated", "status captured", "pause captured", "checkpoint resumed", "FORGE_GOAL_BUDGET_EXHAUSTED", "FORGE_GOAL_STUCK_WARNING") | Set-Content -LiteralPath $transcript -Encoding UTF8
    @("native_activation=PASS", "checkpoint_resume=PASS", "budget_oracle=PASS", "stuck_oracle=PASS") | Set-Content -LiteralPath $result -Encoding UTF8
    $fakeRejected = $false
    try {
        & $capture -Project $goalProject -Cli $fakeCodex -SessionId $session -Transcript $transcript -Result $result | Out-Null
        if ($LASTEXITCODE -ne 0) { $fakeRejected = $true }
    } catch { $fakeRejected = $true }
    if (-not $fakeRejected) { throw "PowerShell fake-marker -Cli minted live/manual authority" }
    if (@(Get-ChildItem (Join-Path $globalTarget ".forge\goal-captures") -Filter "capture.receipt" -File -Recurse -ErrorAction SilentlyContinue).Count) { throw "PowerShell fake marker created a trusted receipt" }

    $fixtureBin = Join-Path $scratch "fixture-bin"; New-Item -ItemType Directory -Path $fixtureBin -Force | Out-Null
    Copy-Item -LiteralPath $fakeCodex -Destination (Join-Path $fixtureBin "codex.ps1")
    $fixtureHome = Join-Path $scratch "fixture-global"; New-Item -ItemType Directory -Path $fixtureHome -Force | Out-Null
    $previousPath = $env:PATH; $previousFixture = $env:FORGE_ENGINE_IDENTITY_FIXTURE
    try {
        $env:PATH = "$fixtureBin$([IO.Path]::PathSeparator)$previousPath"; $env:FORGE_ENGINE_IDENTITY_FIXTURE = "1"
        & $materializer -RepoRoot $root -Target $fixtureHome -Scope global -Platform windows | Out-Null
    } finally { $env:PATH = $previousPath; $env:FORGE_ENGINE_IDENTITY_FIXTURE = $previousFixture }
    $fixtureIdentity = Get-Content -Raw (Join-Path $fixtureHome ".forge\bin\codex.identity")
    if ($fixtureIdentity -notmatch '(?m)^identity_class=fixture-only$' -or $fixtureIdentity -notmatch '(?m)^status=QUALIFIED$') { throw "PowerShell fake schema identity was not complete and fixture-only" }
    $fixtureRejected = $false
    try {
        & (Join-Path $fixtureHome ".forge\bin\forge-goal-capture.ps1") -ValidateBinding -Project $goalProject | Out-Null
        if ($LASTEXITCODE -ne 0) { $fixtureRejected = $true }
    } catch { $fixtureRejected = $true }
    if (-not $fixtureRejected) { throw "PowerShell fixture-only identity became live/manual authority" }

    $identityFields = @{}
    foreach ($line in Get-Content -LiteralPath $codexIdentity) {
        if ($line -match '^([^=]+)=(.*)$') { $identityFields[$Matches[1]] = $Matches[2] }
    }
    $bindingSucceeded = $true; $bindingOutput = $null
    try {
        $bindingOutput = (& $capture -ValidateBinding -Project $goalProject 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { $bindingSucceeded = $false }
    } catch { $bindingSucceeded = $false; $bindingOutput = $_ | Out-String }
    if ($identityFields.identity_class -eq "operator-setup" -and $identityFields.status -eq "QUALIFIED") {
        if (-not $bindingSucceeded -or $bindingOutput -notmatch 'STRUCTURALLY_ELIGIBLE:') { throw "PowerShell setup-bound identity was not structurally eligible" }
    } elseif ($bindingSucceeded) { throw "PowerShell absent/fixture identity became structurally eligible" }
    if (@(Get-ChildItem (Join-Path $globalTarget ".forge\goal-captures") -Filter "capture.receipt" -File -Recurse -ErrorAction SilentlyContinue).Count) { throw "PowerShell binding probe fabricated TUI evidence" }

    $identityBytes = [IO.File]::ReadAllBytes($codexIdentity)
    [IO.File]::AppendAllText($codexIdentity, "`ntampered=true`n")
    $tamperRejected = $false
    try {
        & $capture -ValidateBinding -Project $goalProject | Out-Null
        if ($LASTEXITCODE -ne 0) { $tamperRejected = $true }
    } catch { $tamperRejected = $true }
    if (-not $tamperRejected) { throw "PowerShell changed Codex identity remained eligible" }
    [IO.File]::WriteAllBytes($codexIdentity, $identityBytes)

    $fake = Join-Path $scratch "fake-goal-engine.ps1"
    @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
if ($Arguments[0] -eq "--version") { Write-Host "$env:FORGE_FAKE_ENGINE_NAME 1.0"; exit 0 }
if ($env:FORGE_FAKE_GOAL_FAILURE -eq $env:FORGE_GOAL_FIXTURE_ACTION) { exit 71 }
switch ($env:FORGE_GOAL_FIXTURE_ACTION) {
  "activate" {
    @("phase=implementation", "next_step=resume-verification", "progress=fingerprint-a", "session_id=$env:FORGE_GOAL_SESSION_ID") | Set-Content (Join-Path $env:FORGE_GOAL_FIXTURE_DIR "checkpoint")
    Write-Host "native-activation:$env:FORGE_GOAL_SESSION_ID"
  }
  "resume" {
    if ((Get-Content -Raw (Join-Path $env:FORGE_GOAL_FIXTURE_DIR "checkpoint")) -notmatch [regex]::Escape("session_id=$env:FORGE_GOAL_SESSION_ID")) { exit 72 }
    @("phase=verification", "next_step=budget-check", "progress=fingerprint-a", "session_id=$env:FORGE_GOAL_SESSION_ID") | Set-Content (Join-Path $env:FORGE_GOAL_FIXTURE_DIR "checkpoint")
    Write-Host "checkpoint-resume:$env:FORGE_GOAL_SESSION_ID"
  }
  "manual-tui" {
    @("/goal activated", "checkpoint resumed", "FORGE_GOAL_BUDGET_EXHAUSTED", "FORGE_GOAL_STUCK_WARNING") | Set-Content $env:FORGE_GOAL_TRANSCRIPT
    @("native_activation=PASS", "checkpoint_resume=PASS", "budget_oracle=PASS", "stuck_oracle=PASS") | Set-Content $env:FORGE_GOAL_RESULT
  }
  default { exit 73 }
}
exit 0
'@ | Set-Content -LiteralPath $fake -Encoding UTF8
    $qualifyGoal = Join-Path $root "scripts\qualify-goal-feasibility.ps1"
    $workspaceReceipt = Join-Path $goalProject "fake-exec.receipt"
    @("format=forge-codex-goal-tui-capture-v3", "engine=codex", "command=/goal", "capture_channel=physical-operator-action", "project_root=$projectPhysical", "cli_path=$cliPhysical", "fixture_only=true") | Set-Content -LiteralPath $workspaceReceipt -Encoding UTF8
    $blockedWorkspace = Join-Path $scratch "workspace-receipt.json"
    & $qualifyGoal -Engine codex -ProjectRoot $goalProject -Output $blockedWorkspace -TrustedCapture $workspaceReceipt -TrustedHome $globalTarget | Out-Null
    if ($LASTEXITCODE -eq 0) { throw "PowerShell workspace-authored receipt certified native Codex /goal" }

    $liveClaude = Join-Path $scratch "live-claude.ps1"
    @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
if ($Arguments[0] -eq "--version") { Write-Output "claude-code 9.9.1"; exit 0 }
if ($Arguments[0] -eq "--help") { Write-Output "--safe-mode --strict-mcp-config --setting-sources --session-id --resume"; exit 0 }
$joined = $Arguments -join " "; [IO.File]::AppendAllText($env:FORGE_FAKE_GOAL_ARGV_LOG, "home=$env:HOME userprofile=$env:USERPROFILE username=$env:USERNAME argv=$joined`n")
$session = $env:FORGE_GOAL_SESSION_ID
if ($joined -match '--resume') { if ($env:FORGE_FAKE_GOAL_FAILURE -eq "stale-session") { $session = "wrong-session" }; Write-Output "checkpoint_resume=PASS`nphase=verification`nnext_step=budget-check`nprogress=fingerprint-a`nsession_id=$session`nFORGE_GOAL_BUDGET_EXHAUSTED`npaused=true`nFORGE_GOAL_STUCK_WARNING" }
else { Write-Output "native_activation=PASS`nphase=implementation`nnext_step=resume-verification`nprogress=fingerprint-a`nsession_id=$session" }
exit 0
'@ | Set-Content -LiteralPath $liveClaude -Encoding UTF8
    $env:FORGE_FAKE_GOAL_ARGV_LOG = Join-Path $scratch "live-claude.argv"
    $liveGoalOutput = Join-Path $scratch "live-claude.json"
    & $qualifyGoal -Engine claude -ProjectRoot $goalProject -Output $liveGoalOutput -TestLiveDriver -EnginePath $liveClaude -Authorization $authorization.FullName -TrustedHome $globalTarget | Out-Null
    $liveGoalReceipt=Get-Content -Raw $liveGoalOutput|ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $liveGoalReceipt.status -ne "PASS") { throw "PowerShell Claude live goal driver failed: $($liveGoalReceipt.reason)" }
    $goalArgv = [IO.File]::ReadAllText($env:FORGE_FAKE_GOAL_ARGV_LOG); $userProfile = [Environment]::GetFolderPath('UserProfile')
    if ($goalArgv -notlike "*home=$userProfile userprofile=$userProfile username=$env:USERNAME*") { throw 'PowerShell Claude goal qualifier did not preserve the authenticated Windows identity' }
    $env:FORGE_FAKE_GOAL_FAILURE = "stale-session"; $stale = Join-Path $scratch "stale.json"
    & $qualifyGoal -Engine claude -ProjectRoot $goalProject -Output $stale -TestLiveDriver -EnginePath $liveClaude -Authorization $authorization.FullName -TrustedHome $globalTarget | Out-Null
    if ($LASTEXITCODE -eq 0) { throw "PowerShell stale Claude resume was accepted" }
    Remove-Item Env:FORGE_FAKE_GOAL_FAILURE -ErrorAction SilentlyContinue
    foreach ($engine in @("claude", "codex")) {
        $output = Join-Path $scratch "$engine-goal.json"
        & $qualifyGoal -Engine $engine -ProjectRoot $goalProject -Output $output -FixtureMode -EnginePath $fake | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "$engine deterministic goal fixture failed" }
        $receipt = Get-Content -Raw $output | ConvertFrom-Json
        if ($receipt.status -ne "PASS" -or $receipt.native_activation -ne "PASS" -or $receipt.checkpoint_resume -ne "PASS" -or $receipt.budget_oracle -ne "PASS" -or $receipt.stuck_oracle -ne "PASS") { throw "$engine incomplete goal PASS receipt" }
    }
    $previousFailure = $env:FORGE_FAKE_GOAL_FAILURE
    try {
        $env:FORGE_FAKE_GOAL_FAILURE = "resume"
        $blockedOutput = Join-Path $scratch "codex-goal-failure.json"
        & $qualifyGoal -Engine codex -ProjectRoot $goalProject -Output $blockedOutput -FixtureMode -EnginePath $fake | Out-Null
        if ($LASTEXITCODE -eq 0) { throw "fake goal resume failure was accepted" }
        if ((Get-Content -Raw $blockedOutput | ConvertFrom-Json).status -ne "BLOCKED") { throw "fake goal failure did not produce a truthful BLOCKED receipt" }
    } finally { $env:FORGE_FAKE_GOAL_FAILURE = $previousFailure }

    Write-Host "PASS test-goal-feasibility.ps1"
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
