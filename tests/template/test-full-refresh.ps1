$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$setup = Join-Path $root "setup.ps1"
$refresh = Join-Path $root "scripts\full-refresh.ps1"
$recover = Join-Path $root "scripts\recover-full-refresh.ps1"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("forge-full-refresh-ps51-" + [Guid]::NewGuid().ToString("N"))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
$passes = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:passes++
    Write-Host "PASS: $Message"
}

function Write-Text {
    param([string]$Path, [string]$Text)
    $parent = Split-Path -Parent $Path
    if ($parent) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $script:utf8NoBom)
}

function New-Project {
    param([string]$Name)
    $path = Join-Path $script:scratch $Name
    [IO.Directory]::CreateDirectory($path) | Out-Null
    & git -C $path init -q
    if ($LASTEXITCODE -ne 0) { throw "git init failed: $path" }
    return $path
}

function Write-V5State {
    param([string]$Project, [string]$Token)
    $state = [IO.File]::ReadAllText((Join-Path $script:root "state.template.md"))
    $state = $state -replace '^<!-- forge:state-schema v6 -->\r?\n', ''
    $state = $state.Replace("(what you're actively working on)", $Token)
    Write-Text (Join-Path $Project ".claude\local\state.md") $state
}

function Write-AdversarialV5State {
    param([string]$Project)
    Write-V5State $Project "WINDOWS_STATE_TRANSLATION`n`n- Narrative code review iteration remains developer context."
    $path = Join-Path $Project ".claude\local\state.md"
    $state = [IO.File]::ReadAllText($path)
    $goalReceipt = '## /goal session' + "`n`n" +
        '| Field | Value |' + "`n" + '| --- | --- |' + "`n" +
        '| nonce | 00000000-0000-4000-8000-000000000001 |' + "`n" +
        '| workflow_command | /new-feature windows-state |' + "`n" +
        '| issued_at | 2026-08-27T00:00:00Z |'
    $state = [regex]::Replace($state, '(?m)^## /goal session\r?$', $goalReceipt)
    $state = [regex]::Replace($state, '(?m)^## PR authorization\r?$',
        '## PR authorization' + "`n`n" + '- [x] PR creation authorized' + "`n" + '- Narrative PR authorization wording remains developer context.')
    $dash = [char]0x2014
    $tick = [char]96
    $reviewReceipt = "### Checklist`n`n- [x] Code review iteration 2 $dash codex clean $dash head=$tick" +
        'abcdef0123456789abcdef0123456789abcdef01' + "$tick"
    $state = [regex]::Replace($state, '(?m)^### Checklist\r?$', $reviewReceipt)
    Write-Text $path $state
}

function Get-ProjectSnapshot {
    param([string]$Project)
    $prefix = $Project.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    return @(
        Get-ChildItem -LiteralPath $Project -Force -File -Recurse |
            Where-Object { -not $_.FullName.StartsWith((Join-Path $Project ".git") + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) } |
            Sort-Object FullName |
            ForEach-Object {
                $relative = $_.FullName.Substring($prefix.Length)
                "$relative`t$((Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash)"
            }
    ) -join "`n"
}

function Export-GitBlob {
    param([string]$RevisionPath, [string]$Destination)
    $parent = Split-Path -Parent $Destination
    if ($parent) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    $python = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python -ErrorAction Stop }
    & $python.Source -c "import pathlib,subprocess,sys; pathlib.Path(sys.argv[3]).write_bytes(subprocess.check_output(['git','-C',sys.argv[1],'show',sys.argv[2]]))" `
        $script:root $RevisionPath $Destination
    if ($LASTEXITCODE -ne 0) { throw "git blob export failed: $RevisionPath" }
}

function Install-V561WindowsHooks {
    param([string]$Project)
    $settingsPath = Join-Path $Project ".claude\settings.json"
    Export-GitBlob "cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:settings/settings-windows.template.json" $settingsPath
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    foreach ($eventProperty in $settings.hooks.PSObject.Properties) {
        foreach ($block in $eventProperty.Value) {
            foreach ($hook in $block.hooks) {
                $command = [string]$hook.command
                if ($command -match '\$CLAUDE_PROJECT_DIR/\.claude/hooks/([^"''\s]+)') {
                    $relative = $Matches[1]
                    Export-GitBlob ("cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:hooks/" + $relative) `
                        (Join-Path $Project (".claude\hooks\" + ($relative -replace '/', '\')))
                }
            }
        }
    }
}

function Invoke-IsolatedPowerShell {
    param(
        [string]$Script,
        [string[]]$Arguments,
        [hashtable]$Environment = @{},
        [string]$WorkingDirectory = $script:root
    )
    $saved = @{}
    foreach ($key in $Environment.Keys) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], "Process")
    }
    Push-Location $WorkingDirectory
    try {
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            $output = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1 | Out-String)
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previousPreference }
    } finally {
        Pop-Location
        foreach ($key in $Environment.Keys) {
            [Environment]::SetEnvironmentVariable($key, $saved[$key], "Process")
        }
    }
    return [PSCustomObject]@{ Code = $code; Output = $output }
}

try {
    $previewProject = New-Project "preview"
    Write-Text (Join-Path $previewProject ".claude\.forge-version") "5.61`n"
    Write-V5State $previewProject "WINDOWS_DRY_RUN_STATE"
    $previewBefore = Get-ProjectSnapshot $previewProject
    $preview = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R", "-DryRun") -WorkingDirectory $previewProject `
        -Environment @{ HOME = (Join-Path $scratch "preview-home"); USERPROFILE = (Join-Path $scratch "preview-home") }
    Assert-True ($preview.Code -eq 0 -and $preview.Output.Contains("UPGRADE: READY")) "setup.ps1 -FullRefresh -DryRun uses the real planner"
    Assert-True ((Get-ProjectSnapshot $previewProject) -ceq $previewBefore) "PowerShell preview leaves every target file byte-identical"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $previewProject ".forge\version"))) "PowerShell preview writes no v6 stamp"
    $dryRunOnly = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-DryRun") -WorkingDirectory $previewProject
    Assert-True ($dryRunOnly.Code -ne 0) "PowerShell rejects -DryRun without -FullRefresh"

    $multiBlocker = New-Project "multi-blocker"
    Write-Text (Join-Path $multiBlocker ".claude\.forge-version") "5.61`n"
    foreach ($hook in @("session-start.ps1", "check-bash-safety.ps1")) {
        $hookPath = Join-Path $multiBlocker (".claude\hooks\" + $hook)
        Export-GitBlob ("cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:hooks/" + $hook) $hookPath
        [IO.File]::AppendAllText($hookPath, "`nDEVELOPER_MODIFIED_$hook`n", $utf8NoBom)
    }
    Write-Text (Join-Path $multiBlocker ".claude\settings.json") "{ malformed settings`n"
    Write-V5State $multiBlocker "WINDOWS_MULTI_BLOCKER_STATE"
    $sessionHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $multiBlocker ".claude\hooks\session-start.ps1")).Hash
    $safetyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $multiBlocker ".claude\hooks\check-bash-safety.ps1")).Hash
    $settingsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $multiBlocker ".claude\settings.json")).Hash
    $multiResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R", "-DryRun") -WorkingDirectory $multiBlocker
    Assert-True ($multiResult.Code -ne 0) "PowerShell multi-blocker preview returns nonzero"
    Assert-True ($multiResult.Output.Contains(".claude/hooks/session-start.ps1") -and $multiResult.Output.Contains(".claude/hooks/check-bash-safety.ps1") -and $multiResult.Output.Contains(".claude/settings.json")) "PowerShell preview lists every ordinary blocker"
    Assert-True ($multiResult.Output.Contains("BLOCKERS: 3")) "PowerShell preview reports the complete blocker count"
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $multiBlocker ".claude\hooks\session-start.ps1")).Hash -eq $sessionHash -and (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $multiBlocker ".claude\hooks\check-bash-safety.ps1")).Hash -eq $safetyHash -and (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $multiBlocker ".claude\settings.json")).Hash -eq $settingsHash) "PowerShell blocked inventory preserves all source bytes"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $multiBlocker ".forge\version"))) "PowerShell blocked inventory writes no v6 stamp"

    $project = New-Project "project"
    Write-AdversarialV5State $project
    $first = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $project `
        -Environment @{ HOME = (Join-Path $scratch "unused-home"); USERPROFILE = (Join-Path $scratch "unused-home") }
    Assert-True ($first.Code -eq 0) "setup.ps1 -R translates a project under Windows PowerShell 5.1: $($first.Output.Trim())"
    $canonicalState = Join-Path $project ".forge\local\state.md"
    Assert-True ((Test-Path -LiteralPath $canonicalState) -and ([IO.File]::ReadAllText($canonicalState).Contains("WINDOWS_STATE_TRANSLATION"))) "translated canonical state preserves the active checkpoint"
    $canonicalStateText = [IO.File]::ReadAllText($canonicalState)
    Assert-True (-not $canonicalStateText.Contains("00000000-0000-4000-8000-000000000001") -and -not $canonicalStateText.Contains("Code review iteration 2")) "PowerShell migration invalidates structurally valid legacy receipts"
    Assert-True ($canonicalStateText.Contains("Narrative code review iteration remains developer context.") -and $canonicalStateText.Contains("Narrative PR authorization wording remains developer context.")) "PowerShell migration preserves review and authorization narrative verbatim"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $project ".claude\local\state.md"))) "legacy state is retired only after commit"
    $manifest = Join-Path $project ".forge\managed-files.tsv"
    $firstHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifest).Hash
    $second = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $project `
        -Environment @{ HOME = (Join-Path $scratch "unused-home"); USERPROFILE = (Join-Path $scratch "unused-home") }
    Assert-True ($second.Code -eq 0) "second setup.ps1 -R succeeds"
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $manifest).Hash -eq $firstHash) "project full refresh is byte-idempotent"

    $hookProject = New-Project "released-hooks"
    Write-Text (Join-Path $hookProject ".claude\.forge-version") "5.61`n"
    Install-V561WindowsHooks $hookProject
    Write-V5State $hookProject "WINDOWS_HOOK_SETTINGS"
    $hookResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $hookProject
    Assert-True ($hookResult.Code -eq 0) "released v5.61 Windows hook settings migrate behaviorally"
    $installedSettings = Get-Content -LiteralPath (Join-Path $hookProject ".claude\settings.json") -Raw | ConvertFrom-Json
    $commands = @()
    $managedHooks = @()
    foreach ($eventProperty in $installedSettings.hooks.PSObject.Properties) {
        foreach ($block in $eventProperty.Value) {
            foreach ($hook in $block.hooks) {
                if ($hook.command) {
                    $commands += [string]$hook.command
                    if ($hook.forgeManagedId) { $managedHooks += "$($eventProperty.Name)|$($hook.forgeManagedId)|$($hook.command)" }
                }
            }
        }
    }
    $legacyCommands = @($commands | Where-Object { $_.Contains('$CLAUDE_PROJECT_DIR/.claude/hooks/') })
    $inlineCommands = @($commands | Where-Object { $_.Contains('COMPACTION IMMINENT') })
    $hookLeaves = @($legacyCommands | ForEach-Object { ($_ -split '/hooks/', 2)[1].Trim('"') })
    $duplicateLeaves = @($hookLeaves | Group-Object | Where-Object Count -ne 1)
    $expectedManaged = @(
        'SessionStart|host-context|powershell -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.forge/hooks/lib/host-context.ps1" -Mode hook -Host claude',
        'SubagentStop|subagent-review-receipt|powershell -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.forge/hooks/check-subagent-review.ps1"',
        'PreToolUse|external-mutation-auth|powershell -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.forge/hooks/check-external-mutation-auth.ps1"'
    )
    $hookDetail = "legacy=$($legacyCommands.Count); managed=$($managedHooks -join ' || '); duplicates=$($duplicateLeaves.Name -join ',')"
    Assert-True ($legacyCommands.Count -eq 9 -and (Compare-Object $managedHooks $expectedManaged -CaseSensitive).Count -eq 0 -and $duplicateLeaves.Count -eq 0) "each released Windows hook registration executes through exactly one thin delegate ($hookDetail)"
    Assert-True ($inlineCommands.Count -eq 1) "semantically duplicate Windows PreCompact inline registration is suppressed"

    $danglingHook = New-Project "released-hooks-dangling"
    Write-Text (Join-Path $danglingHook ".claude\.forge-version") "5.61`n"
    Export-GitBlob "cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:settings/settings-windows.template.json" `
        (Join-Path $danglingHook ".claude\settings.json")
    $danglingResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $danglingHook
    Assert-True ($danglingResult.Code -ne 0 -and $danglingResult.Output.Contains("referenced legacy hook")) "dangling released Windows hook registration blocks before mutation"

    $modifiedHook = New-Project "released-hooks-modified"
    Write-Text (Join-Path $modifiedHook ".claude\.forge-version") "5.61`n"
    Install-V561WindowsHooks $modifiedHook
    $modifiedPath = Join-Path $modifiedHook ".claude\hooks\session-start.ps1"
    [IO.File]::AppendAllText($modifiedPath, "`nDEVELOPER_MODIFIED_HOOK`n", $utf8NoBom)
    $modifiedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $modifiedPath).Hash
    $modifiedResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $modifiedHook
    Assert-True ($modifiedResult.Code -ne 0 -and (Get-FileHash -Algorithm SHA256 -LiteralPath $modifiedPath).Hash -eq $modifiedHash) "modified referenced Windows hook blocks without mutation"

    $continuity = New-Project "continuity"
    Write-V5State $continuity "WINDOWS_CONTINUITY_STATE"
    Write-Text (Join-Path $continuity "CONTINUITY.md") "# CONTINUITY`n`n## State`n`n### Now`n`n- Windows continuity flow`n"
    Write-Text (Join-Path $continuity "CLAUDE.md") "# Developer instructions`n`n## Project Overview`n"
    $migrated = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-Migrate") -WorkingDirectory $continuity
    Assert-True ($migrated.Code -eq 0) "setup.ps1 -Migrate succeeds before -R"
    $receipt = Join-Path $continuity ".forge\local\migration-evidence\continuity-state-v5-v6.json"
    Assert-True (Test-Path -LiteralPath $receipt -PathType Leaf) "PowerShell continuity migration writes a translation receipt"
    $continued = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $continuity
    Assert-True ($continued.Code -eq 0) "receipt-proven PowerShell continuity migration continues through full refresh"

    $tampered = New-Project "continuity-tamper"
    Write-V5State $tampered "WINDOWS_CONTINUITY_TAMPER"
    Write-Text (Join-Path $tampered "CONTINUITY.md") "# CONTINUITY`n`n## State`n`n### Now`n`n- tamper`n"
    Write-Text (Join-Path $tampered "CLAUDE.md") "# Developer instructions`n`n## Project Overview`n"
    $null = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-Migrate") -WorkingDirectory $tampered
    $tamperedReceipt = Join-Path $tampered ".forge\local\migration-evidence\continuity-state-v5-v6.json"
    $receiptObject = Get-Content -LiteralPath $tamperedReceipt -Raw | ConvertFrom-Json
    $receiptObject.target_hash = "0" * 64
    Write-Text $tamperedReceipt (($receiptObject | ConvertTo-Json -Depth 10) + "`n")
    $tamperResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $tampered
    Assert-True ($tamperResult.Code -ne 0 -and $tamperResult.Output.Contains("continuity translation receipt")) "tampered PowerShell continuity receipt blocks before mutation"

    $setupSource = [IO.File]::ReadAllText($setup)
    Assert-True ($setupSource.Contains('& $refreshHelper -Target $HOME -Scope global')) "setup.ps1 routes global refresh to the canonical Windows home"
    $fixtureHome = Join-Path $scratch "home"
    [IO.Directory]::CreateDirectory($fixtureHome) | Out-Null
    $noncanonicalHome = Join-Path $fixtureHome "..\home"
    $noncanonicalResult = Invoke-IsolatedPowerShell -Script $refresh -Arguments @("-Target", $noncanonicalHome, "-Scope", "global")
    Assert-True ($noncanonicalResult.Code -ne 0) "noncanonical selected Windows home is rejected"

    $driveRoot = [IO.Path]::GetPathRoot($scratch)
    $rootResult = Invoke-IsolatedPowerShell -Script $refresh -Arguments @("-Target", $driveRoot, "-Scope", "global")
    Assert-True ($rootResult.Code -ne 0) "drive root is rejected as a global transaction home"
    $junctionOutside = Join-Path $scratch "junction-outside"
    $junction = Join-Path $scratch "junction-home"
    [IO.Directory]::CreateDirectory($junctionOutside) | Out-Null
    & cmd.exe /c "mklink /J `"$junction`" `"$junctionOutside`"" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "failed to create test junction" }
    $junctionResult = Invoke-IsolatedPowerShell -Script $refresh -Arguments @("-Target", $junction, "-Scope", "global")
    Assert-True ($junctionResult.Code -ne 0 -and $junctionResult.Output.Contains("reparse-point")) "real junction transaction root is rejected"
    [IO.Directory]::CreateDirectory((Join-Path $junctionOutside "nested-home")) | Out-Null
    $junctionAncestorResult = Invoke-IsolatedPowerShell -Script $refresh `
        -Arguments @("-Target", (Join-Path $junction "nested-home"), "-Scope", "global")
    Assert-True ($junctionAncestorResult.Code -ne 0 -and $junctionAncestorResult.Output.Contains("reparse-point")) "real junction transaction-root ancestor is rejected"

    $destinationRace = New-Project "destination-race"
    $destinationRaceResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $destinationRace `
        -Environment @{ FORGE_FULL_REFRESH_INJECT_DESTINATION_RACE_RELATIVE = ".forge/local/state.md" }
    $destinationRaceState = Join-Path $destinationRace ".forge\local\state.md"
    Assert-True ($destinationRaceResult.Code -ne 0 -and ([IO.File]::ReadAllText($destinationRaceState).Contains("FORGE_DESTINATION_RACE"))) "Windows no-clobber destination race preserves concurrent bytes"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $destinationRace ".forge\version"))) "Windows destination race never stamps readiness"

    $rollback = New-Project "rollback"
    $rollbackRoot = Join-Path $rollback "CLAUDE.md"
    Write-Text $rollbackRoot "WINDOWS_ROLLBACK_ORIGINAL`n"
    $rollbackHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $rollbackRoot).Hash
    $rollbackResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $rollback `
        -Environment @{ FORGE_FULL_REFRESH_FAIL_AFTER = "@penultimate" }
    Assert-True ($rollbackResult.Code -ne 0) "injected Windows commit failure returns nonzero"
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $rollbackRoot).Hash -eq $rollbackHash) "verified Windows rollback restores original bytes"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $rollback ".forge\version"))) "failed Windows transaction never stamps readiness"

    $race = New-Project "rollback-race"
    $raceRoot = Join-Path $race "CLAUDE.md"
    Write-Text $raceRoot "WINDOWS_RACE_ORIGINAL`n"
    $raceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $raceRoot).Hash
    $raceResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $race `
        -Environment @{
            FORGE_FULL_REFRESH_FAIL_AFTER = "@penultimate"
            FORGE_FULL_REFRESH_INJECT_ROLLBACK_RACE_RELATIVE = "CLAUDE.md"
        }
    Assert-True ($raceResult.Code -ne 0 -and ([IO.File]::ReadAllText($raceRoot).Contains("FORGE_ROLLBACK_DESTINATION_RACE"))) "rollback race never clobbers the concurrent destination"
    $journal = Get-ChildItem -LiteralPath (Join-Path $race ".forge\local\migration-journals") -Filter "*.json" | Select-Object -First 1
    Assert-True ($journal -and ([IO.File]::ReadAllText($journal.FullName).Contains('"phase": "recovery_required"'))) "rollback race persists recovery_required journal"
    $quarantine = Get-ChildItem -LiteralPath (Join-Path $race ".forge\local\migration-staging") -Filter "CLAUDE.md" -File -Recurse | Where-Object FullName -Match '[\\/]quarantine[\\/]CLAUDE\.md$' | Select-Object -First 1
    Assert-True ($quarantine -and (Get-FileHash -Algorithm SHA256 -LiteralPath $quarantine.FullName).Hash -eq $raceHash) "rollback race retains the original in quarantine"
    $preservedRace = Join-Path $race "rollback-race-preserved.txt"
    Move-Item -LiteralPath $raceRoot -Destination $preservedRace
    $recovery = Invoke-IsolatedPowerShell -Script $recover -Arguments @("-Journal", $journal.FullName, "-Target", $race)
    Assert-True ($recovery.Code -eq 0) "explicit PowerShell recovery succeeds after the concurrent version is preserved"
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath $raceRoot).Hash -eq $raceHash) "PowerShell recovery restores the verified original"
    Assert-True ([IO.File]::ReadAllText($preservedRace).Contains("FORGE_ROLLBACK_DESTINATION_RACE")) "PowerShell recovery preserves the concurrent version separately"

    Write-Host "PASS: test-full-refresh.ps1 ($passes assertions)"
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
