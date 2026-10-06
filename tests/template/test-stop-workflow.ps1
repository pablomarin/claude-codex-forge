# Windows installed Stop contracts with each host and linked event-cwd routing.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('forge-stop-workflow-' + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
$runtime = Get-Command powershell.exe -ErrorAction SilentlyContinue
if (-not $runtime) { $runtime = Get-Command pwsh -ErrorAction Stop }
$runtimePath = $runtime.Source
$unixRuntime = [IO.Path]::DirectorySeparatorChar -eq '/'
$failures = 0
$passes = 0

function Assert-Check([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:passes++; Write-Host "PASS $Message" }
    else { $script:failures++; Write-Host "FAIL $Message"; Write-Host $script:lastProcessError }
}
function Invoke-FixtureScript([string]$Root, [string]$Script, [string[]]$Arguments = @(), [string]$InputText = '', [switch]$CommandMode) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $runtimePath
    if ($CommandMode) {
        $nativeArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $Script)
    } else {
        $nativeArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Script) + $Arguments
    }
    if ($info.PSObject.Properties['ArgumentList']) {
        foreach ($argument in $nativeArguments) { $info.ArgumentList.Add($argument) }
    } else {
        # Windows PowerShell 5.1's process API has only the command-line string.
        $quoted = $nativeArguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }
        $info.Arguments = $quoted -join ' '
    }
    $info.WorkingDirectory = $Root
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables['PATH'] = (Join-Path $Root 'bin') + [IO.Path]::PathSeparator + $env:PATH
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $null = $process.Start()
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($InputText)
    $process.StandardInput.Close()
    $process.WaitForExit()
    $result = [PSCustomObject]@{ Status = $process.ExitCode; Out = $outTask.Result; Err = $errTask.Result }
    $process.Dispose()
    $script:lastProcessError = $result.Err
    return $result
}
function Install-Hooks([string]$Root) {
    foreach ($relative in @('.forge\local', '.claude', '.codex', 'bin')) {
        [IO.Directory]::CreateDirectory((Join-Path $Root $relative)) | Out-Null
    }
    # Stub from the first invocation; build-evidence also probes PR state.
    if ($unixRuntime) {
        [IO.File]::WriteAllText((Join-Path $Root 'bin/gh'), "#!/bin/sh`nexit 1`n", $utf8)
        # The Windows router's executable spelling maps to the installed pwsh
        # during portable local checks; Windows CI uses its native executable.
        [IO.File]::WriteAllText((Join-Path $Root 'bin/powershell.exe'), '#!/bin/sh' + "`n" + 'exec pwsh "$@"' + "`n", $utf8)
        & chmod +x (Join-Path $Root 'bin/gh') (Join-Path $Root 'bin/powershell.exe')
    } else {
        [IO.File]::WriteAllText((Join-Path $Root 'bin\gh.cmd'), "@exit /b 1`r`n", $utf8)
    }
    Copy-Item (Join-Path $repo 'hooks') (Join-Path $Root '.forge\hooks') -Recurse
    Copy-Item (Join-Path $repo 'settings\settings-windows.template.json') (Join-Path $Root '.claude\settings.json')
    Copy-Item (Join-Path $repo 'settings\codex-hooks.template.json') (Join-Path $Root '.codex\hooks.json')
    Copy-Item (Join-Path $repo 'state.template.md') (Join-Path $Root '.forge\local\state.md')
    [IO.File]::WriteAllText((Join-Path $Root '.forge\version'), "6`n", $utf8)
}
function New-Fixture([string]$Root, [string]$Workflow, [string]$MainHost) {
    [IO.Directory]::CreateDirectory((Join-Path $Root 'docs')) | Out-Null
    & git -C $Root init -q --initial-branch=main
    & git -C $Root config user.email forge-test@example.com
    & git -C $Root config user.name 'Forge Test'
    [IO.File]::WriteAllText((Join-Path $Root '.gitignore'), ".forge/`n.claude/`n.codex/`nbin/`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $Root 'README.md'), "fixture`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $Root 'docs\CHANGELOG.md'), "fixture`n", $utf8)
    & git -C $Root add .
    & git -C $Root commit -qm init
    $prefix = switch ($Workflow) { quick-fix { 'quick-fix' }; new-feature { 'feat' }; fix-bug { 'fix' } }
    & git -C $Root switch -qc "$prefix/stop-smoke"
    Install-Hooks $Root
    $result = Invoke-FixtureScript $Root (Join-Path $Root '.forge\hooks\lib\workflow-state.ps1') @(
        'activate', '--host', $MainHost, '--workflow', $Workflow, '--task', 'stop-smoke',
        '--base-ref', 'main', '--phase', 'implementation', '--next-step', 'finish smoke')
    if ($result.Status -ne 0) { throw "fixture activation failed: $($result.Err)" }
}
function Complete-Fixture([string]$Root, [string]$MainHost) {
    $result = Invoke-FixtureScript $Root (Join-Path $Root '.forge\hooks\lib\workflow-state.ps1') @(
        'checkpoint', '--host', $MainHost, '--phase', 'complete', '--next-step', 'await new work')
    if ($result.Status -ne 0) { throw "fixture completion failed: $($result.Err)" }
}
function Invoke-RegisteredCodex([string]$Root, [string]$Event, [string]$Hook, [string]$Payload) {
    $settings = Get-Content (Join-Path $Root '.codex\hooks.json') -Raw | ConvertFrom-Json
    $commands = @($settings.hooks.$Event.hooks | Where-Object { $_.commandWindows.Contains("-Hook $Hook") })
    if ($commands.Count -ne 1) { throw "missing registered Codex $Event hook $Hook" }
    $registered = [string]$commands[0].commandWindows
    if ($registered -notmatch '^powershell\.exe -NoProfile -ExecutionPolicy Bypass -Command "(.*)"$') {
        throw "unsupported registered Windows command: $registered"
    }
    # Pass the registration's inner code as one literal argv item; no shell expands it.
    return Invoke-FixtureScript -Root $Root -Script $Matches[1] -InputText $Payload -CommandMode
}
function Invoke-Stop([string]$RegisteredRoot, [string]$EventRoot, [string]$MainHost, [bool]$Active = $false, [string]$Turn = '') {
    $payload = @{ cwd = $EventRoot; host = $MainHost; hook_event_name = 'Stop'; stop_hook_active = $Active;
        session_id = 'stop-smoke'; turn_id = $Turn } | ConvertTo-Json -Compress
    if ($MainHost -eq 'codex') {
        return Invoke-RegisteredCodex $RegisteredRoot 'Stop' 'check-state-updated.ps1' $payload
    } else {
        $settings = Get-Content (Join-Path $RegisteredRoot '.claude\settings.json') -Raw | ConvertFrom-Json
        $command = @($settings.hooks.Stop.hooks | Where-Object { $_.command -match 'check-state-updated.ps1' })
        if ($command.Count -ne 1) { throw 'missing Claude Stop registration' }
        $scriptPath = Join-Path $RegisteredRoot '.forge\hooks\check-state-updated.ps1'
        $scriptArguments = @()
    }
    return Invoke-FixtureScript $RegisteredRoot $scriptPath $scriptArguments $payload
}
function Set-CrlfState([string]$Root) {
    $path = Join-Path $Root '.forge\local\state.md'
    $raw = [IO.File]::ReadAllText($path) -replace "`r", ''
    [IO.File]::WriteAllText($path, $raw.Replace("`n", "`r`n"), $utf8)
}
function Assert-Quiet($Result, [string]$Label) {
    Assert-Check ($Result.Status -eq 0) "$Label allows Stop"
    Assert-Check (-not $Result.Err.Contains('FORGE_FINAL_EVIDENCE_STALE')) "$Label suppresses historical receipt warning"
    Assert-Check (-not $Result.Err.Contains('WORKFLOW:')) "$Label suppresses completed continuation"
}
try {
    [IO.Directory]::CreateDirectory($scratch) | Out-Null
    if ($unixRuntime) { $scratch = (& bash -c 'cd "$1" && pwd -P' '--' $scratch).Trim() }
    foreach ($mainHost in @('claude', 'codex')) {
        foreach ($workflow in @('quick-fix', 'new-feature', 'fix-bug')) {
            $root = Join-Path $scratch "$mainHost-$workflow"
            New-Fixture $root $workflow $mainHost
            $result = Invoke-Stop $root $root $mainHost
            Assert-Check ($result.Status -eq 0) "$mainHost $workflow first active checkpoint"
            Complete-Fixture $root $mainHost
            foreach ($delivery in 1..3) { Assert-Quiet (Invoke-Stop $root $root $mainHost) "$mainHost $workflow completed delivery $delivery" }
        }
        $root = Join-Path $scratch "$mainHost-active"
        New-Fixture $root 'new-feature' $mainHost
        Set-CrlfState $root
        $result = Invoke-Stop $root $root $mainHost
        Assert-Check ($result.Status -eq 0) "$mainHost changed checkpoint allows Stop"
        Assert-Check ($result.Err.Contains('FORGE_FINAL_EVIDENCE_STALE')) "$mainHost active receipt warning"
        $result = Invoke-Stop $root $root $mainHost
        Assert-Check ($result.Status -eq 2) "$mainHost unchanged active checkpoint continues"
        Assert-Check ($result.Err.Contains('/new-feature stop-smoke')) "$mainHost active workflow label"
        $result = Invoke-Stop $root $root $mainHost $true
        Assert-Check ($result.Status -eq 0 -and -not $result.Err.Contains('WORKFLOW:')) "$mainHost continuation-loop guard"
        Complete-Fixture $root $mainHost
        Set-CrlfState $root
        Assert-Quiet (Invoke-Stop $root $root $mainHost) "$mainHost CRLF completed first Stop"
        Assert-Quiet (Invoke-Stop $root $root $mainHost) "$mainHost CRLF completed repeated Stop"
        foreach ($file in @('one', 'two', 'three', 'four')) { [IO.File]::WriteAllText((Join-Path $root $file), "before`n", $utf8) }
        & git -C $root add one two three four
        & git -C $root commit -qm fixture
        $result = Invoke-Stop $root $root $mainHost
        Assert-Check ($result.Status -eq 2 -and $result.Err.Contains('Update docs/CHANGELOG.md')) "$mainHost completed changelog gate"
        [IO.File]::AppendAllText((Join-Path $root 'docs\CHANGELOG.md'), "updated`n", $utf8)
        $payload = @{ cwd = $root; host = $mainHost; tool_name = 'Bash'; tool_input = @{ command = 'git push origin HEAD' } } | ConvertTo-Json -Compress
        if ($mainHost -eq 'codex') {
            $result = Invoke-RegisteredCodex $root 'PreToolUse' 'check-workflow-gates.ps1' $payload
        } else {
            $result = Invoke-FixtureScript $root (Join-Path $root '.forge\hooks\check-workflow-gates.ps1') @() $payload
        }
        Assert-Check ($result.Status -eq 2) "$mainHost registered shipping gate preserves blocking status 2"
        [IO.File]::AppendAllText((Join-Path $root '.forge\local\state.md'), "`n## Workflow`n| Command | none |`n", $utf8)
        $result = Invoke-Stop $root $root $mainHost
        Assert-Check ($result.Status -eq 2 -and $result.Err.Contains('FORGE_STATE_INVALID')) "$mainHost complete phase retains canonical state validation"

        $primary = Join-Path $scratch "$mainHost-primary"
        $linked = Join-Path $scratch "$mainHost-linked"
        New-Fixture $primary 'quick-fix' $mainHost
        Complete-Fixture $primary $mainHost
        & git -C $primary worktree add -qb feat/linked-smoke $linked main
        Install-Hooks $linked
        $result = Invoke-FixtureScript $linked (Join-Path $linked '.forge\hooks\lib\workflow-state.ps1') @(
            'activate', '--host', $mainHost, '--workflow', 'new-feature', '--task', 'linked-smoke',
            '--base-ref', 'main', '--phase', 'implementation', '--next-step', 'finish linked smoke')
        if ($result.Status -ne 0) { throw "linked activation failed: $($result.Err)" }
        $nested = Join-Path $linked 'nested'
        [IO.Directory]::CreateDirectory($nested) | Out-Null
        $before = (Get-FileHash (Join-Path $primary '.forge\local\state.md')).Hash
        $result = Invoke-Stop $primary $nested $mainHost
        Assert-Check ($result.Status -eq 0) "$mainHost first linked checkpoint"
        $result = Invoke-Stop $primary $nested $mainHost
        Assert-Check ($result.Status -eq 2 -and $result.Err.Contains('/new-feature linked-smoke')) "$mainHost linked active feature continuation"
        Assert-Check (-not $result.Err.Contains('/quick-fix')) "$mainHost primary label absent from linked feedback"
        Assert-Check (Test-Path (Join-Path $linked '.forge\local\forge-goal-last-fingerprint')) "$mainHost feature fingerprint belongs to event worktree"
        $primaryFiles = @(Get-ChildItem (Join-Path $primary '.forge\local') -Force | Where-Object { $_.Name -like 'forge-goal-last-fingerprint*' -or $_.Name -like '.state-last-stop.*' })
        Assert-Check ($primaryFiles.Count -eq 0) "$mainHost linked native I/O leaves no primary fingerprint or temp file"
        Assert-Check ((Get-FileHash (Join-Path $primary '.forge\local\state.md')).Hash -eq $before) "$mainHost linked Stop preserves primary state"
        Assert-Quiet (Invoke-Stop $primary $primary $mainHost) "$mainHost primary completed quick-fix"
        Assert-Check (Test-Path (Join-Path $linked '.forge\local\state-last-stop.sha256')) "$mainHost checkpoint sidecar belongs to linked worktree"
        Complete-Fixture $linked $mainHost
        Assert-Quiet (Invoke-Stop $primary $nested $mainHost) "$mainHost linked completion"
        $linkedState = Join-Path $linked '.forge\local\state.md'
        $raw = [IO.File]::ReadAllText($linkedState) -replace "`r", ''
        $raw = [regex]::Replace($raw, '(?ms)^## /goal session\n.*?(?=^## )', '')
        $raw += @"

## /goal session
| Field | Value |
| nonce | 66666666-6666-4666-8666-666666666666 |
| objective_hash | linked-objective |
| activation_id | 55555555-5555-4555-8555-555555555555 |
| activation_host | $mainHost |
| activated_at | 2026-09-28T00:00:00Z |
| workflow_command | /new-feature linked-smoke |
| turn_count | 0 |
| turn_ceiling | 20 |
| activation_count | 1 |
| evidence_path | .forge/local/evidence/latest.json |
"@
        [IO.File]::WriteAllText($linkedState, $raw, $utf8)
        $result = Invoke-FixtureScript $linked (Join-Path $linked '.forge\hooks\lib\goal-ledger.ps1') @('activate', '-Project', $linked, '-State', $linkedState)
        Assert-Check ($result.Status -eq 0) "$mainHost linked native Goal activation"
        # Publish once from the feature process cwd to isolate the counter's
        # event-cwd contract from the separately asserted Stop publication.
        $goalPayload = @{ cwd = $nested; host = $mainHost; stop_hook_active = $true } | ConvertTo-Json -Compress
        $result = Invoke-FixtureScript $linked (Join-Path $linked '.forge\hooks\build-evidence.ps1') @() $goalPayload
        Assert-Check ($result.Status -eq 0) "$mainHost linked fingerprint seeds the counter control"
        $primaryFingerprint = Join-Path $primary '.forge\local\forge-goal-last-fingerprint'
        $primaryFpHash = (Get-FileHash $primaryFingerprint).Hash
        foreach ($delivery in 1..2) {
            $result = Invoke-Stop $primary $nested $mainHost $true 'linked-goal-turn'
            Assert-Check ($result.Status -eq 0) "$mainHost linked native Goal Stop"
        }
        $featureFingerprint = Join-Path $linked '.forge\local\forge-goal-last-fingerprint'
        $featureCounter = Join-Path $linked '.forge\local\forge-goal-stuck-count'
        $counterMatches = $false
        if ((Test-Path $featureFingerprint) -and (Test-Path $featureCounter)) {
            $fp = [IO.File]::ReadAllText($featureFingerprint).Trim()
            $counterMatches = [IO.File]::ReadAllText($featureCounter).Trim() -eq "2|$fp"
        }
        Assert-Check $counterMatches "$mainHost linked stuck counter advances against its own fingerprint"
        Assert-Check (-not (Test-Path (Join-Path $primary '.forge\local\forge-goal-stuck-count'))) "$mainHost linked counter does not leak into primary"
        Assert-Check ((Get-FileHash $primaryFingerprint).Hash -eq $primaryFpHash) "$mainHost linked Goal preserves primary fingerprint"
        $primaryTemps = @(Get-ChildItem (Join-Path $primary '.forge\local') -Filter 'forge-goal-last-fingerprint.tmp.*' -Force)
        Assert-Check ($primaryTemps.Count -eq 0) "$mainHost linked Goal leaves no primary fingerprint temp file"

        $root = Join-Path $scratch "$mainHost-goal"
        New-Fixture $root 'new-feature' $mainHost
        Complete-Fixture $root $mainHost
        $state = Join-Path $root '.forge\local\state.md'
        $raw = [IO.File]::ReadAllText($state) -replace "`r", ''
        $raw = [regex]::Replace($raw, '(?ms)^## /goal session\n.*?(?=^## )', '')
        $nonce = '88888888-8888-4888-8888-888888888888'
        $raw += @"

## /goal session
| Field | Value |
| nonce | $nonce |
| objective_hash | objective-42 |
| activation_id | 77777777-7777-4777-8777-777777777777 |
| activation_host | $mainHost |
| activated_at | 2026-09-28T00:00:00Z |
| workflow_command | /new-feature stop-smoke |
| turn_count | 0 |
| turn_ceiling | 20 |
| activation_count | 1 |
| evidence_path | .forge/local/evidence/latest.json |
"@
        [IO.File]::WriteAllText($state, $raw, $utf8)
        $result = Invoke-FixtureScript $root (Join-Path $root '.forge\hooks\lib\goal-ledger.ps1') @('activate', '-Project', $root, '-State', $state)
        Assert-Check ($result.Status -eq 0) "$mainHost native Goal activation"
        Assert-Quiet (Invoke-Stop $root $root $mainHost $false 'goal-turn-1') "$mainHost completed workflow Goal Stop"
        Assert-Quiet (Invoke-Stop $root $root $mainHost $false 'goal-turn-1') "$mainHost duplicate Goal Stop"
        $turns = Join-Path $root ".git\forge-goals\$nonce\turns"
        Assert-Check (Test-Path (Join-Path $turns '00000001')) "$mainHost complete phase still charges Goal"
        Assert-Check (-not (Test-Path (Join-Path $turns '00000002'))) "$mainHost duplicate charge remains idempotent"
        Assert-Check ([IO.File]::ReadAllText((Join-Path $turns '00000001')).Contains("host=$mainHost")) "$mainHost ledger host attribution"
    }
    Write-Host "Stop workflow PowerShell: $passes passed, $failures failed"
    if ($failures -ne 0) { exit 1 }
} finally {
    if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
}
