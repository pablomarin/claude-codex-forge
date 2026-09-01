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

function Record-PriorContinuityMigration {
    param([string]$Project)
    $python = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python -ErrorAction Stop }
    $merge = Join-Path $script:root "scripts\merge-settings.py"
    $source = Join-Path $Project ".claude\local\state.md"
    $destination = Join-Path $Project ".forge\local\state.md"
    $receipt = Join-Path $Project ".forge\local\migration-evidence\continuity-state-v5-v6.json"
    & $python.Source $merge migrate-state-v5-v6 --source $source --destination $destination | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "prior continuity state translation failed" }
    Push-Location $Project
    try {
        & $python.Source $merge write-continuity-receipt --source $source --destination $destination --receipt $receipt | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "prior continuity receipt creation failed" }
    } finally {
        Pop-Location
    }
    $claude = Join-Path $Project "CLAUDE.md"
    Write-Text $claude ("<!-- forge:migrated 2026-08-31 -->`n`n" + [IO.File]::ReadAllText($claude))
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

function Install-ReleasedCore {
    param([string]$Project, [string]$Version, [string]$Commit)
    Write-Text (Join-Path $Project ".claude\.forge-version") "$Version`n"
    Export-GitBlob ("${Commit}:hooks/session-start.ps1") (Join-Path $Project ".claude\hooks\session-start.ps1")
    Export-GitBlob ("${Commit}:commands/new-feature.md") (Join-Path $Project ".claude\commands\new-feature.md")
    Write-V5State $Project ("WINDOWS_PROFILE_" + $Version + "_STATE")
}

function Assert-OneActiveForge {
    param([string]$Project, [string]$Label)
    $version = Join-Path $Project ".forge\version"
    $instructions = Join-Path $Project ".forge\instructions.md"
    $manifest = Join-Path $Project ".forge\managed-files.tsv"
    $claudeRoot = [IO.File]::ReadAllText((Join-Path $Project "CLAUDE.md"))
    $codexRoot = [IO.File]::ReadAllText((Join-Path $Project "AGENTS.md"))
    Assert-True ((Test-Path -LiteralPath $version -PathType Leaf) -and ([IO.File]::ReadAllText($version).Trim() -eq "6")) "$Label has the v6 stamp"
    Assert-True ((Test-Path -LiteralPath $instructions -PathType Leaf) -and (Test-Path -LiteralPath $manifest -PathType Leaf)) "$Label has one canonical Forge source and ownership manifest"
    Assert-True (([regex]::Matches($claudeRoot, '<!-- forge:begin v6 -->').Count -eq 1) -and ([regex]::Matches($codexRoot, '<!-- forge:begin v6 -->').Count -eq 1)) "$Label has one bounded adapter per native root"
    $commands = @(Get-ChildItem -LiteralPath (Join-Path $Project ".claude\commands") -Filter "*.md" -File -Recurse -ErrorAction SilentlyContinue)
    $nonThin = @($commands | Where-Object {
        $text = [IO.File]::ReadAllText($_.FullName)
        -not ($text.Contains("forge-generated: true") -and $text.Contains("canonical-path:"))
    })
    Assert-True ($nonThin.Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $Project ".claude\commands\codex.md"))) "$Label retains only thin Claude workflows and no retired codex command"
    $settingsPath = Join-Path $Project ".claude\settings.json"
    $badHook = $false
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        foreach ($eventProperty in $settings.hooks.PSObject.Properties) {
            foreach ($block in $eventProperty.Value) {
                foreach ($hook in $block.hooks) {
                    if ($hook.type -eq "prompt") { $badHook = $true }
                    $command = [string]$hook.command
                    if ($command.Contains('$CLAUDE_PROJECT_DIR/.claude/hooks/')) {
                        $leaf = (($command -split '\.claude/hooks/', 2)[1] -split '["''\s]', 2)[0]
                        $delegate = Join-Path $Project (".claude\hooks\" + ($leaf -replace '/', '\'))
                        if (-not (Test-Path -LiteralPath $delegate -PathType Leaf) -or -not [IO.File]::ReadAllText($delegate).Contains(".forge/hooks/")) { $badHook = $true }
                    }
                }
            }
        }
    }
    Assert-True (-not $badHook) "$Label has no active v5 prompt or full-body hook registration"
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
    Export-GitBlob "cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:hooks/session-start.ps1" `
        (Join-Path $previewProject ".claude\hooks\session-start.ps1")
    Write-V5State $previewProject "WINDOWS_DRY_RUN_STATE"
    $previewBefore = Get-ProjectSnapshot $previewProject
    $preview = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R", "-DryRun") -WorkingDirectory $previewProject `
        -Environment @{ HOME = (Join-Path $scratch "preview-home"); USERPROFILE = (Join-Path $scratch "preview-home") }
    if ($preview.Code -ne 0 -or -not $preview.Output.Contains("UPGRADE: READY")) {
        throw "FAIL: setup.ps1 -FullRefresh -DryRun uses the real planner (code=$($preview.Code); output=$($preview.Output.Trim()))"
    }
    Assert-True $true "setup.ps1 -FullRefresh -DryRun uses the real planner"
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

    $sentinelRoot = New-Project "sentinel-root"
    Write-Text (Join-Path $sentinelRoot ".claude\.forge-version") "5.60`n"
    $releasedRoot = Join-Path $scratch "released-CLAUDE.md"
    Export-GitBlob "80dffe872cc0830243a617eacfecce1e5fc2a6f5:CLAUDE.template.md" $releasedRoot
    $releasedText = [IO.File]::ReadAllText($releasedRoot).Replace(
        "[PROJECT DESCRIPTION - 2-3 sentences explaining what this project does]", "WINDOWS_SENTINEL_PROJECT_BYTES"
    ).Replace(".claude/rules/testing.md", ".forge/rules/testing.md").Replace(
        "/codex <instruction>    #", "/opinion <instruction>  #"
    )
    Write-Text (Join-Path $sentinelRoot "CLAUDE.md") ("<!-- forge:migrated 2026-04-28 -->`n`n" + $releasedText)
    Write-V5State $sentinelRoot "WINDOWS_SENTINEL_STATE"
    $sentinelResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $sentinelRoot
    $sentinelInstalled = [IO.File]::ReadAllText((Join-Path $sentinelRoot "CLAUDE.md"))
    Assert-True ($sentinelResult.Code -eq 0 -and $sentinelInstalled.Contains("WINDOWS_SENTINEL_PROJECT_BYTES") -and ([regex]::Matches($sentinelInstalled, '<!-- forge:begin v6 -->').Count -eq 1) -and -not $sentinelInstalled.Contains("/codex") -and -not $sentinelInstalled.Contains(".claude/rules/")) "PowerShell reconciles a sentinel-prefixed root without losing project bytes"

    $ambiguousAgents = New-Project "ambiguous-agents"
    Write-Text (Join-Path $ambiguousAgents ".claude\.forge-version") "5.60`n"
    Write-Text (Join-Path $ambiguousAgents "AGENTS.md") "# Project instructions`n`n@CONTINUITY.md`nUse /codex and .claude/rules/ for policy.`n"
    Write-V5State $ambiguousAgents "WINDOWS_AMBIGUOUS_AGENTS_STATE"
    $ambiguousHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $ambiguousAgents "AGENTS.md")).Hash
    $ambiguousResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R", "-DryRun") -WorkingDirectory $ambiguousAgents
    Assert-True ($ambiguousResult.Code -ne 0 -and ([regex]::Matches($ambiguousResult.Output, 'code=ROOT_POLICY_AMBIGUOUS').Count -eq 1) -and (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $ambiguousAgents "AGENTS.md")).Hash -eq $ambiguousHash) "PowerShell groups ambiguous project-owned root references without mutation"

    $aliasProject = New-Project "legacy-alias"
    Write-Text (Join-Path $aliasProject ".claude\.forge-version") "5.60`n"
    $aliasPath = Join-Path $aliasProject ".agents\skills\ui-design\SKILL.md"
    Export-GitBlob "80dffe872cc0830243a617eacfecce1e5fc2a6f5:skills/ui-design/SKILL.template.md" $aliasPath
    Write-V5State $aliasProject "WINDOWS_ALIAS_STATE"
    $aliasResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $aliasProject
    Assert-True ($aliasResult.Code -eq 0 -and [IO.File]::ReadAllText($aliasPath).Contains("forge-generated: true")) "PowerShell replaces an exact version-bound cross-host alias"
    $modifiedAlias = New-Project "legacy-alias-modified"
    Write-Text (Join-Path $modifiedAlias ".claude\.forge-version") "5.60`n"
    $modifiedAliasPath = Join-Path $modifiedAlias ".agents\skills\ui-design\SKILL.md"
    Export-GitBlob "80dffe872cc0830243a617eacfecce1e5fc2a6f5:skills/ui-design/SKILL.template.md" $modifiedAliasPath
    [IO.File]::AppendAllText($modifiedAliasPath, "`nWINDOWS_PROJECT_ALIAS_CHANGE`n", $utf8NoBom)
    Write-V5State $modifiedAlias "WINDOWS_MODIFIED_ALIAS_STATE"
    $modifiedAliasResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R", "-DryRun") -WorkingDirectory $modifiedAlias
    Assert-True ($modifiedAliasResult.Code -ne 0 -and $modifiedAliasResult.Output.Contains(".agents/skills/ui-design/SKILL.md")) "PowerShell blocks a modified cross-host alias"

    $v558Alias = New-Project "legacy-alias-v558"
    Write-Text (Join-Path $v558Alias ".claude\.forge-version") "5.58`n"
    $v558AliasPath = Join-Path $v558Alias ".agents\skills\ui-design\SKILL.md"
    Export-GitBlob "cc2b901fc1203f8b46693c8a0c95b6fe3a0fdf34:skills/ui-design/SKILL.template.md" $v558AliasPath
    Write-V5State $v558Alias "WINDOWS_V558_ALIAS_STATE"
    $v558AliasResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $v558Alias
    Assert-True ($v558AliasResult.Code -eq 0 -and [IO.File]::ReadAllText($v558AliasPath).Contains("forge-generated: true")) "PowerShell replaces an exact known alias despite an older compatible stamp"

    $crossHostCompat = New-Project "cross-host-compat"
    Write-Text (Join-Path $crossHostCompat ".claude\.forge-version") "5.58`n"
    $legacyCodexHook = Join-Path $crossHostCompat ".codex\hooks\session-start.ps1"
    $legacySkillReference = Join-Path $crossHostCompat ".agents\skills\ui-design\references\polish-checklist.md"
    $customCompatHook = Join-Path $crossHostCompat ".codex\hooks\check-workflow-gates.sh"
    Export-GitBlob "cc2b901fc1203f8b46693c8a0c95b6fe3a0fdf34:hooks/session-start.ps1" $legacyCodexHook
    Export-GitBlob "cc2b901fc1203f8b46693c8a0c95b6fe3a0fdf34:skills/ui-design/references/polish-checklist.md" $legacySkillReference
    Export-GitBlob "cc2b901fc1203f8b46693c8a0c95b6fe3a0fdf34:hooks/check-workflow-gates.sh" $customCompatHook
    [IO.File]::AppendAllText($customCompatHook, "`nWINDOWS_PROJECT_CUSTOMIZED_HOOK`n", $utf8NoBom)
    $customCompatHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $customCompatHook).Hash
    $legacyCommand = "'" + $legacyCodexHook + "'"
    $crossHostPayload = [ordered]@{
        projectSetting = "KEEP-CROSS-HOST-SETTING"
        hooks = [ordered]@{
            SessionStart = @([ordered]@{
                matcher = "startup|resume|clear|compact"
                hooks = @([ordered]@{ type = "command"; command = $legacyCommand })
            })
            CustomEvent = @([ordered]@{ projectOwned = "KEEP-CUSTOM-EVENT" })
        }
    }
    Write-Text (Join-Path $crossHostCompat ".codex\hooks.json") (($crossHostPayload | ConvertTo-Json -Depth 20) + "`n")
    Write-V5State $crossHostCompat "WINDOWS_CROSS_HOST_COMPAT_STATE"
    $crossHostRun = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $crossHostCompat
    $crossHostInstalled = Get-Content -LiteralPath (Join-Path $crossHostCompat ".codex\hooks.json") -Raw | ConvertFrom-Json
    $crossHostProperties = @($crossHostInstalled.hooks.PSObject.Properties.Name)
    $installedSessionIds = @($crossHostInstalled.hooks.session_start | ForEach-Object { $_.forgeManagedId })
    Assert-True ($crossHostRun.Code -eq 0 -and
        -not (Test-Path -LiteralPath $legacyCodexHook) -and
        -not (Test-Path -LiteralPath $legacySkillReference) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $customCompatHook).Hash -eq $customCompatHash) `
        "PowerShell full refresh retires exact compatibility copies and preserves customized inert files"
    Assert-True ($crossHostProperties -notcontains "SessionStart" -and
        $crossHostProperties -contains "CustomEvent" -and
        $crossHostInstalled.projectSetting -eq "KEEP-CROSS-HOST-SETTING" -and
        $installedSessionIds -contains "session-start") `
        "PowerShell full refresh removes only the proven registration and preserves user JSON"

    $managedCompat = New-Project "managed-cross-host-compat"
    $materializer = Join-Path $root "scripts\materialize-adapters.ps1"
    $managedFirst = Invoke-IsolatedPowerShell -Script $materializer -Arguments @(
        "-RepoRoot", $root, "-Target", $managedCompat, "-Scope", "project", "-Platform", "windows"
    ) -WorkingDirectory $managedCompat
    Assert-True ($managedFirst.Code -eq 0) "PowerShell managed compatibility fixture starts as v6"
    $managedLegacyHook = Join-Path $managedCompat ".codex\hooks\session-start.ps1"
    $managedLegacyReference = Join-Path $managedCompat ".agents\skills\ui-design\references\polish-checklist.md"
    $managedCustomHook = Join-Path $managedCompat ".codex\hooks\check-workflow-gates.sh"
    Export-GitBlob "cc2b901fc1203f8b46693c8a0c95b6fe3a0fdf34:hooks/session-start.ps1" $managedLegacyHook
    Export-GitBlob "cc2b901fc1203f8b46693c8a0c95b6fe3a0fdf34:skills/ui-design/references/polish-checklist.md" $managedLegacyReference
    Export-GitBlob "cc2b901fc1203f8b46693c8a0c95b6fe3a0fdf34:hooks/check-workflow-gates.sh" $managedCustomHook
    [IO.File]::AppendAllText($managedCustomHook, "`nWINDOWS_PROJECT_CUSTOMIZED_HOOK`n", $utf8NoBom)
    $managedCustomHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $managedCustomHook).Hash
    $managedHooksPath = Join-Path $managedCompat ".codex\hooks.json"
    $managedHooks = Get-Content -LiteralPath $managedHooksPath -Raw | ConvertFrom-Json
    $managedHooks | Add-Member -NotePropertyName projectSetting -NotePropertyValue "KEEP-CROSS-HOST-SETTING" -Force
    $managedHooks.hooks | Add-Member -NotePropertyName SessionStart -NotePropertyValue @([pscustomobject]@{
        matcher = "startup|resume|clear|compact"
        hooks = @([pscustomobject]@{ type = "command"; command = ("'" + $managedLegacyHook + "'") })
    }) -Force
    $managedHooks.hooks | Add-Member -NotePropertyName CustomEvent -NotePropertyValue @([pscustomobject]@{
        projectOwned = "KEEP-CUSTOM-EVENT"
    }) -Force
    Write-Text $managedHooksPath (($managedHooks | ConvertTo-Json -Depth 30) + "`n")
    $managedSecond = Invoke-IsolatedPowerShell -Script $materializer -Arguments @(
        "-RepoRoot", $root, "-Target", $managedCompat, "-Scope", "project", "-Platform", "windows"
    ) -WorkingDirectory $managedCompat
    $managedInstalled = Get-Content -LiteralPath $managedHooksPath -Raw | ConvertFrom-Json
    $managedProperties = @($managedInstalled.hooks.PSObject.Properties.Name)
    $managedSessionIds = @($managedInstalled.hooks.session_start | ForEach-Object { $_.forgeManagedId })
    Assert-True ($managedSecond.Code -eq 0 -and
        -not (Test-Path -LiteralPath $managedLegacyHook) -and
        -not (Test-Path -LiteralPath $managedLegacyReference) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $managedCustomHook).Hash -eq $managedCustomHash) `
        "PowerShell managed refresh retires exact compatibility copies and preserves customized inert files"
    Assert-True ($managedProperties -notcontains "SessionStart" -and
        $managedProperties -contains "CustomEvent" -and
        $managedInstalled.projectSetting -eq "KEEP-CROSS-HOST-SETTING" -and
        $managedSessionIds -contains "session-start") `
        "PowerShell managed refresh removes only the proven registration and preserves user JSON"

    $managedInstalled.hooks | Add-Member -NotePropertyName PreToolUse -NotePropertyValue @([pscustomobject]@{
        matcher = "Bash"
        hooks = @([pscustomobject]@{ type = "command"; command = ("'" + $managedCustomHook + "'") })
    }) -Force
    Write-Text $managedHooksPath (($managedInstalled | ConvertTo-Json -Depth 30) + "`n")
    $managedBlocked = Invoke-IsolatedPowerShell -Script $materializer -Arguments @(
        "-RepoRoot", $root, "-Target", $managedCompat, "-Scope", "project", "-Platform", "windows"
    ) -WorkingDirectory $managedCompat
    Assert-True ($managedBlocked.Code -ne 0 -and
        $managedBlocked.Output.Contains("referenced legacy cross-host hook is missing, modified, or ambiguous") -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $managedCustomHook).Hash -eq $managedCustomHash) `
        "PowerShell managed refresh blocks an actively registered customized compatibility hook"

    $seededContent = New-Project "seeded-content"
    Write-Text (Join-Path $seededContent ".claude\.forge-version") "5.60`n"
    $seededAdr = Join-Path $seededContent "docs\adr\README.md"
    Export-GitBlob "80dffe872cc0830243a617eacfecce1e5fc2a6f5:docs/adr/README.md" $seededAdr
    [IO.File]::AppendAllText($seededAdr, "`n| [0099](0099-project.md) | Project decision | Accepted |`n", $utf8NoBom)
    $seededCi = Join-Path $seededContent "docs\ci-templates\e2e.yml"
    $seededCiSource = Join-Path $scratch "seeded-e2e-source.yml"
    Export-GitBlob "80dffe872cc0830243a617eacfecce1e5fc2a6f5:templates/ci-workflows/e2e.yml" $seededCiSource
    Write-Text $seededCi ([IO.File]::ReadAllText($seededCiSource).Replace("__PLAYWRIGHT_DIR__", "frontend"))
    Write-V5State $seededContent "WINDOWS_SEEDED_CONTENT_STATE"
    $seededAdrHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $seededAdr).Hash
    $seededCiHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $seededCi).Hash
    $seededPreview = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R", "-DryRun") -WorkingDirectory $seededContent
    Assert-True ($seededPreview.Code -eq 0 -and $seededPreview.Output.Contains("PRESERVED: docs/adr/README.md (modified seeded project content)") -and $seededPreview.Output.Contains("PRESERVED: docs/ci-templates/e2e.yml (modified seeded project content)")) "PowerShell preserves modified non-runtime Forge seeds during preview"
    $seededRun = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $seededContent
    Assert-True ($seededRun.Code -eq 0 -and (Get-FileHash -Algorithm SHA256 -LiteralPath $seededAdr).Hash -eq $seededAdrHash -and (Get-FileHash -Algorithm SHA256 -LiteralPath $seededCi).Hash -eq $seededCiHash) "PowerShell migration preserves seeded project content byte-for-byte"

    $activeRule = New-Project "active-rule-modified"
    Write-Text (Join-Path $activeRule ".claude\.forge-version") "5.60`n"
    $activeRulePath = Join-Path $activeRule ".claude\rules\critical-rules.md"
    Export-GitBlob "80dffe872cc0830243a617eacfecce1e5fc2a6f5:rules/critical-rules.md" $activeRulePath
    [IO.File]::AppendAllText($activeRulePath, "`nWINDOWS_PROJECT_POLICY_CHANGE`n", $utf8NoBom)
    $blockedSeededAdr = Join-Path $activeRule "docs\adr\README.md"
    Export-GitBlob "80dffe872cc0830243a617eacfecce1e5fc2a6f5:docs/adr/README.md" $blockedSeededAdr
    [IO.File]::AppendAllText($blockedSeededAdr, "`nWINDOWS_PROJECT_ADR_INDEX_CHANGE`n", $utf8NoBom)
    Write-V5State $activeRule "WINDOWS_ACTIVE_RULE_STATE"
    $activeRuleHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $activeRulePath).Hash
    $activeRuleResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R", "-DryRun") -WorkingDirectory $activeRule
    Assert-True ($activeRuleResult.Code -ne 0 -and $activeRuleResult.Output.Contains("code=LEGACY_FILE_MODIFIED") -and $activeRuleResult.Output.Contains("preserve the project-specific behavior in docs/agent-context.md or another project-owned source") -and $activeRuleResult.Output.Contains("PRESERVED: docs/adr/README.md (modified seeded project content)") -and (Get-FileHash -Algorithm SHA256 -LiteralPath $activeRulePath).Hash -eq $activeRuleHash) "PowerShell keeps modified active policy blocking while explaining preservation and reporting preserved seeded content"

    $customHarness = New-Project "independent-harness"
    Write-Text (Join-Path $customHarness ".claude\.forge-version") "5.61`n"
    Write-Text (Join-Path $customHarness ".agent-workflows\runtime\workflow-runtime.mjs") "console.log('WINDOWS_CUSTOM_RUNTIME')`n"
    Write-Text (Join-Path $customHarness "AGENTS.md") "# Project policy`n`nRun .agent-workflows/runtime/workflow-runtime.mjs for hooks.`n"
    Write-V5State $customHarness "WINDOWS_CLAUDE_STATE"
    $customState = [IO.File]::ReadAllText((Join-Path $root "state.template.md")) -replace '^<!-- forge:state-schema v6 -->\r?\n', ''
    Write-Text (Join-Path $customHarness ".agent-workflows\local\state.md") $customState
    $customBefore = Get-ProjectSnapshot $customHarness
    $customResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R", "-DryRun") -WorkingDirectory $customHarness
    Assert-True ($customResult.Code -ne 0 -and ([regex]::Matches($customResult.Output, 'code=CUSTOM_HARNESS_COLLISION').Count -eq 1) -and ([regex]::Matches($customResult.Output, 'code=MULTIPLE_STATE_SOURCES').Count -eq 1) -and ((Get-ProjectSnapshot $customHarness) -ceq $customBefore)) "PowerShell groups independent harness and multiple-state choices without mutation"

    $profiles = Join-Path $scratch "downstream-profiles"
    [IO.Directory]::CreateDirectory($profiles) | Out-Null

    $profile1 = New-Project "profile-1"
    Install-ReleasedCore $profile1 "5.60" "80dffe872cc0830243a617eacfecce1e5fc2a6f5"
    $profile1RootBlob = Join-Path $profiles "profile-1-CLAUDE.md"
    Export-GitBlob "80dffe872cc0830243a617eacfecce1e5fc2a6f5:CLAUDE.template.md" $profile1RootBlob
    $profile1Root = [IO.File]::ReadAllText($profile1RootBlob).Replace(
        "[PROJECT DESCRIPTION - 2-3 sentences explaining what this project does]", "WINDOWS_PROFILE_ONE_CONTEXT"
    ).Replace(".claude/rules/testing.md", ".forge/rules/testing.md").Replace(
        "/codex <instruction>    #", "/opinion <instruction>  #"
    )
    Write-Text (Join-Path $profile1 "CLAUDE.md") ("<!-- forge:migrated 2026-04-28 -->`n`n" + $profile1Root)
    Write-Text (Join-Path $profile1 ".claude\rules\project-domain.md") "WINDOWS_PROFILE_ONE_RULE`n"
    Write-Text (Join-Path $profile1 "docs\adr\0099-project.md") "WINDOWS_PROFILE_ONE_ADR`n"
    Write-Text (Join-Path $profile1 ".claude\settings.json") '{"enabledPlugins":{"superpowers@claude-plugins-official":true},"developerSetting":"keep"}'
    $profile1Before = Get-ProjectSnapshot $profile1
    $profile1Preview = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R", "-DryRun") -WorkingDirectory $profile1
    Assert-True ($profile1Preview.Code -eq 0 -and $profile1Preview.Output.Contains("UPGRADE: READY") -and $profile1Preview.Output.Contains("claude RUNTIME_READY: BLOCKED") -and ((Get-ProjectSnapshot $profile1) -ceq $profile1Before)) "Windows profile 1 previews ready without writes and separates plugin readiness"
    $profile1Run = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $profile1
    Assert-True ($profile1Run.Code -eq 0 -and [IO.File]::ReadAllText((Join-Path $profile1 ".claude\rules\project-domain.md")).Contains("WINDOWS_PROFILE_ONE_RULE") -and [IO.File]::ReadAllText((Join-Path $profile1 "docs\adr\0099-project.md")).Contains("WINDOWS_PROFILE_ONE_ADR")) "Windows profile 1 preserves project content and executes"
    Assert-OneActiveForge $profile1 "Windows profile 1"

    $profile2 = New-Project "profile-2"
    Install-ReleasedCore $profile2 "5.58" "cc2b901fc1203f8b46693c8a0c95b6fe3a0fdf34"
    Write-Text (Join-Path $profile2 ".codex\project-context.md") "WINDOWS_PROFILE_TWO_CODEX`n"
    Write-Text (Join-Path $profile2 ".agents\skills\project-audit\SKILL.md") "---`nname: project-audit`ndescription: Project-owned audit skill.`n---`n"
    Write-Text (Join-Path $profile2 "docs\ci\README.md") "WINDOWS_PROFILE_TWO_CI`n"
    & git -C $profile2 add .claude .codex .agents docs
    & git -C $profile2 -c user.name=Forge -c user.email=forge@example.invalid commit -qm "tracked mixed profile"
    $profile2Before = Get-ProjectSnapshot $profile2
    $profile2Preview = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R", "-DryRun") -WorkingDirectory $profile2
    Assert-True ($profile2Preview.Code -eq 0 -and ((Get-ProjectSnapshot $profile2) -ceq $profile2Before)) "Windows profile 2 tracked mixed tree previews without writes"
    $profile2Run = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $profile2
    Assert-True ($profile2Run.Code -eq 0 -and [IO.File]::ReadAllText((Join-Path $profile2 ".codex\project-context.md")).Contains("WINDOWS_PROFILE_TWO_CODEX") -and [IO.File]::ReadAllText((Join-Path $profile2 "docs\ci\README.md")).Contains("WINDOWS_PROFILE_TWO_CI")) "Windows profile 2 preserves custom Codex and CI content"
    Assert-OneActiveForge $profile2 "Windows profile 2"

    $profile3 = New-Project "profile-3"
    Install-ReleasedCore $profile3 "5.60" "80dffe872cc0830243a617eacfecce1e5fc2a6f5"
    Export-GitBlob "80dffe872cc0830243a617eacfecce1e5fc2a6f5:skills/generate-image/SKILL.template.md" (Join-Path $profile3 ".agents\skills\generate-image\SKILL.md")
    Export-GitBlob "80dffe872cc0830243a617eacfecce1e5fc2a6f5:skills/ui-design/SKILL.template.md" (Join-Path $profile3 ".agents\skills\ui-design\SKILL.md")
    Write-Text (Join-Path $profile3 ".claude\agents\project-quality.md") "WINDOWS_PROFILE_THREE_AGENT`n"
    Write-Text (Join-Path $profile3 "AGENTS.md") "# Project`n`n@CONTINUITY.md`nUse /codex and .claude/rules/.`n"
    $profile3Blocked = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R", "-DryRun") -WorkingDirectory $profile3
    Assert-True ($profile3Blocked.Code -ne 0 -and ([regex]::Matches($profile3Blocked.Output, 'code=ROOT_POLICY_AMBIGUOUS').Count -eq 1)) "Windows profile 3 groups obsolete project root references"
    Write-Text (Join-Path $profile3 "AGENTS.md") "# Project`n`nWINDOWS_PROFILE_THREE_NEUTRAL`n"
    $profile3Run = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $profile3
    Assert-True ($profile3Run.Code -eq 0 -and [IO.File]::ReadAllText((Join-Path $profile3 ".agents\skills\ui-design\SKILL.md")).Contains("forge-generated: true") -and [IO.File]::ReadAllText((Join-Path $profile3 ".claude\agents\project-quality.md")).Contains("WINDOWS_PROFILE_THREE_AGENT")) "Windows profile 3 replaces exact aliases and preserves its custom agent"
    Assert-OneActiveForge $profile3 "Windows profile 3"

    $profile4 = New-Project "profile-4"
    Install-ReleasedCore $profile4 "5.61" "cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff"
    Write-Text (Join-Path $profile4 ".agent-workflows\runtime\workflow-runtime.mjs") "console.log('WINDOWS_PROFILE_FOUR_RUNTIME')`n"
    Write-Text (Join-Path $profile4 ".agent-workflows\policy.md") "WINDOWS_PROFILE_FOUR_POLICY`n"
    $profile4State = [IO.File]::ReadAllText((Join-Path $root "state.template.md")).Replace("(what you're actively working on)", "WINDOWS_PROFILE_FOUR_NEWER_STATE")
    Write-Text (Join-Path $profile4 ".agent-workflows\local\state.md") $profile4State
    Write-Text (Join-Path $profile4 "AGENTS.md") "Run .agent-workflows/runtime/workflow-runtime.mjs.`n"
    Write-Text (Join-Path $profile4 ".claude\settings.json") '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"node .agent-workflows/runtime/workflow-runtime.mjs"}]}]}}'
    Write-Text (Join-Path $profile4 ".agents\skills\custom-runtime\SKILL.md") "---`nname: custom-runtime`ndescription: Project runtime skill.`n---`n"
    Write-Text (Join-Path $profile4 ".claude\hooks\project-runtime.ps1") "Write-Output 'WINDOWS_PROFILE_FOUR_HOOK'`n"
    $profile4Before = Get-ProjectSnapshot $profile4
    $profile4Blocked = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R", "-DryRun") -WorkingDirectory $profile4
    Assert-True ($profile4Blocked.Code -ne 0 -and ([regex]::Matches($profile4Blocked.Output, 'code=CUSTOM_HARNESS_COLLISION').Count -eq 1) -and ([regex]::Matches($profile4Blocked.Output, 'code=MULTIPLE_STATE_SOURCES').Count -eq 1) -and ((Get-ProjectSnapshot $profile4) -ceq $profile4Before)) "Windows profile 4 groups harness and state choices without writes"
    $archiveRuntime = Join-Path $profile4 "docs\archive\legacy-agent-workflows\runtime"
    $archiveState = Join-Path $profile4 "docs\archive\legacy-state\claude-state.md"
    [IO.Directory]::CreateDirectory((Split-Path -Parent $archiveRuntime)) | Out-Null
    [IO.Directory]::CreateDirectory((Split-Path -Parent $archiveState)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $profile4 ".claude\local\state.md") -Destination $archiveState
    Copy-Item -LiteralPath (Join-Path $profile4 ".agent-workflows\local\state.md") -Destination (Join-Path $profile4 ".claude\local\state.md") -Force
    Move-Item -LiteralPath (Join-Path $profile4 ".agent-workflows") -Destination $archiveRuntime
    Write-Text (Join-Path $profile4 "AGENTS.md") "# Project`n`nWINDOWS_PROFILE_FOUR_NEUTRAL`n"
    Write-Text (Join-Path $profile4 ".claude\settings.json") "{}`n"
    $profile4Run = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $profile4
    Assert-True ($profile4Run.Code -eq 0 -and [IO.File]::ReadAllText((Join-Path $archiveRuntime "runtime\workflow-runtime.mjs")).Contains("WINDOWS_PROFILE_FOUR_RUNTIME") -and [IO.File]::ReadAllText((Join-Path $profile4 ".forge\local\state.md")).Contains("WINDOWS_PROFILE_FOUR_NEWER_STATE")) "Windows profile 4 executes only after explicit archive and state selection"
    Assert-OneActiveForge $profile4 "Windows profile 4"

    $managedSetup = New-Project "managed-setup"
    [IO.Directory]::CreateDirectory((Join-Path $managedSetup "docs\adr")) | Out-Null
    Copy-Item -LiteralPath (Join-Path $root "docs\adr\README.md") `
        -Destination (Join-Path $managedSetup "docs\adr\README.md")
    Copy-Item -LiteralPath (Join-Path $root "docs\adr\0001-volatile-state-not-auto-loaded.md") `
        -Destination (Join-Path $managedSetup "docs\adr\0001-volatile-state-not-auto-loaded.md")
    Write-Text (Join-Path $managedSetup "docs\adr\0006-write-tool-creates-missing-parents.md") `
        "# Project ADR 0006`n`nWINDOWS_CUSTOM_PROJECT_DECISION`n"
    $customAdrHash = (Get-FileHash -Algorithm SHA256 -LiteralPath `
        (Join-Path $managedSetup "docs\adr\0006-write-tool-creates-missing-parents.md")).Hash
    $managedRun = Invoke-IsolatedPowerShell -Script $setup -Arguments @() -WorkingDirectory $managedSetup `
        -Environment @{ HOME = (Join-Path $scratch "managed-home"); USERPROFILE = (Join-Path $scratch "managed-home") }
    $retiredHelpers = @(
        "default-branch.sh", "default-branch.ps1", "review-breaker.sh", "review-breaker.ps1",
        "codex-pty.sh", "codex-pty.ps1", "codex-pty-helper.py"
    )
    $retiredHelperFound = @($retiredHelpers | Where-Object {
        Test-Path -LiteralPath (Join-Path $managedSetup (".claude\hooks\lib\" + $_))
    })
    Assert-True ($managedRun.Code -eq 0 -and $retiredHelperFound.Count -eq 0 -and
        (Test-Path -LiteralPath (Join-Path $managedSetup ".forge\hooks\lib\codex-pty.ps1") -PathType Leaf) -and
        -not (Test-Path -LiteralPath (Join-Path $managedSetup ".claude\local\state.md")) -and
        -not (Test-Path -LiteralPath (Join-Path $managedSetup ".claude\state.template.md"))) `
        "ordinary Windows v6 setup installs canonical helpers/state without retired copies"
    $managedAdrIndex = [IO.File]::ReadAllText((Join-Path $managedSetup "docs\adr\README.md"))
    $customAdrHashAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath `
        (Join-Path $managedSetup "docs\adr\0006-write-tool-creates-missing-parents.md")).Hash
    Assert-True ($managedAdrIndex.Contains("This directory records architecture decisions for this project.") -and
        -not $managedAdrIndex.Contains("0010-dual-engine-canonical-harness.md") -and
        -not (Test-Path -LiteralPath (Join-Path $managedSetup "docs\adr\0001-volatile-state-not-auto-loaded.md")) -and
        $customAdrHashAfter -eq $customAdrHash) `
        "ordinary Windows v6 setup retires exact Forge ADR seeds and preserves project ADRs"
    $installedCouncil = [IO.File]::ReadAllText((Join-Path $managedSetup ".forge\skills\council\SKILL.template.md"))
    Assert-True ($installedCouncil.Contains(".forge/hooks/lib/codex-pty.sh") -and -not $installedCouncil.Contains(".claude/hooks/lib/codex-pty")) `
        "ordinary Windows v6 setup installs canonical council shim paths"

    $project = New-Project "project"
    Write-AdversarialV5State $project
    $projectOperatorHome = Join-Path $scratch "unused-home"
    Write-Text (Join-Path $projectOperatorHome ".forge\bin\forge-goal-authorize.ps1") "# operator helper`n"
    Export-GitBlob "cc79afc29f03ec3b9610a0d4dc9ffcb0bd2475ff:docs/adr/README.md" `
        (Join-Path $project "docs\adr\README.md")
    $first = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $project `
        -Environment @{ HOME = $projectOperatorHome; USERPROFILE = $projectOperatorHome }
    Assert-True ($first.Code -eq 0) "setup.ps1 -R translates a project under Windows PowerShell 5.1: $($first.Output.Trim())"
    Assert-True ($first.Output.Contains("CODEX_HOOKS: MATERIALIZED primary worktree registration") -and
        -not $first.Output.Contains("CODEX_HOOKS: BLOCKED linked worktree") -and
        $first.Output.Contains("VERIFY_RUNTIME: '$(Join-Path $project '.forge\bin\verify-runtime')' live --project-root '$project'")) `
        "PowerShell transaction diagnostics describe the live primary project"
    Assert-True ($first.Output.Contains("GOAL_OVERLAY: BLOCKED pending qualify-goal-feasibility.ps1") -and
        -not $first.Output.Contains("GOAL_OVERLAY: BLOCKED run")) `
        "PowerShell transaction diagnostics inspect the operator home"
    Assert-True ($first.Output.Contains("DELETED: docs/adr/README.md (exact released Forge seed)") -and
        -not (Test-Path -LiteralPath (Join-Path $project "docs\adr\README.md"))) `
        "PowerShell report distinguishes exact retired Forge seed deletion"
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

    $retiredContinuity = New-Project "continuity-retired"
    Write-V5State $retiredContinuity "WINDOWS_CONTINUITY_RETIRED"
    Write-Text (Join-Path $retiredContinuity "CONTINUITY.md") "# CONTINUITY`n`n- preserve me`n"
    $retiredBefore = Get-ProjectSnapshot $retiredContinuity
    $retiredResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-Migrate") -WorkingDirectory $retiredContinuity
    Assert-True ($retiredResult.Code -ne 0 -and $retiredResult.Output.Contains("retired in Forge 6") -and $retiredResult.Output.Contains("-FullRefresh -DryRun") -and ((Get-ProjectSnapshot $retiredContinuity) -ceq $retiredBefore)) "retired PowerShell continuity command is inert and points to preview"

    $unresolvedContinuity = New-Project "continuity-unresolved"
    Write-V5State $unresolvedContinuity "WINDOWS_CONTINUITY_UNRESOLVED"
    Write-Text (Join-Path $unresolvedContinuity "CONTINUITY.md") "# CONTINUITY`n`n- unresolved legacy state`n"
    $unresolvedBefore = Get-ProjectSnapshot $unresolvedContinuity
    $unresolvedPreview = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R", "-DryRun") -WorkingDirectory $unresolvedContinuity
    Assert-True ($unresolvedPreview.Code -ne 0 -and $unresolvedPreview.Output.Contains("code=LEGACY_CONTINUITY_UNRESOLVED") -and ((Get-ProjectSnapshot $unresolvedContinuity) -ceq $unresolvedBefore)) "unresolved Windows continuity file blocks preview without writes"
    $unresolvedExecute = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $unresolvedContinuity
    Assert-True ($unresolvedExecute.Code -ne 0 -and $unresolvedExecute.Output.Contains("code=LEGACY_CONTINUITY_UNRESOLVED") -and ((Get-ProjectSnapshot $unresolvedContinuity) -ceq $unresolvedBefore) -and -not (Test-Path -LiteralPath (Join-Path $unresolvedContinuity ".forge\version"))) "unresolved Windows continuity file blocks execution without persistent writes"

    $continuity = New-Project "continuity"
    Write-V5State $continuity "WINDOWS_CONTINUITY_STATE"
    Write-Text (Join-Path $continuity "CONTINUITY.md") "# CONTINUITY`n`n## State`n`n### Now`n`n- Windows continuity flow`n"
    Write-Text (Join-Path $continuity "CLAUDE.md") "# Developer instructions`n`n## Project Overview`n"
    Record-PriorContinuityMigration $continuity
    $receipt = Join-Path $continuity ".forge\local\migration-evidence\continuity-state-v5-v6.json"
    Assert-True (Test-Path -LiteralPath $receipt -PathType Leaf) "prior PowerShell continuity migration has a translation receipt"
    $continued = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $continuity
    Assert-True ($continued.Code -eq 0) "receipt-proven PowerShell continuity migration continues through full refresh"

    $tampered = New-Project "continuity-tamper"
    Write-V5State $tampered "WINDOWS_CONTINUITY_TAMPER"
    Write-Text (Join-Path $tampered "CONTINUITY.md") "# CONTINUITY`n`n## State`n`n### Now`n`n- tamper`n"
    Write-Text (Join-Path $tampered "CLAUDE.md") "# Developer instructions`n`n## Project Overview`n"
    Record-PriorContinuityMigration $tampered
    $tamperedReceipt = Join-Path $tampered ".forge\local\migration-evidence\continuity-state-v5-v6.json"
    $receiptObject = Get-Content -LiteralPath $tamperedReceipt -Raw | ConvertFrom-Json
    $receiptObject.target_hash = "0" * 64
    Write-Text $tamperedReceipt (($receiptObject | ConvertTo-Json -Depth 10) + "`n")
    $tamperResult = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-R") -WorkingDirectory $tampered
    Assert-True ($tamperResult.Code -ne 0 -and $tamperResult.Output.Contains("continuity translation receipt")) "tampered PowerShell continuity receipt blocks before mutation"

    $globalPreviewHome = Join-Path $scratch "global-preview"
    Write-Text (Join-Path $globalPreviewHome ".claude\.forge-version") "5.61`n"
    $globalPreviewBefore = Get-ProjectSnapshot $globalPreviewHome
    $globalPreview = Invoke-IsolatedPowerShell -Script $setup -Arguments @("-Global", "-R", "-DryRun") `
        -Environment @{ HOME = $globalPreviewHome; USERPROFILE = $globalPreviewHome }
    Assert-True ($globalPreview.Code -eq 0 -and $globalPreview.Output.Contains("UPGRADE: READY") -and ((Get-ProjectSnapshot $globalPreviewHome) -ceq $globalPreviewBefore)) "setup.ps1 routes global preview to the canonical Windows home without writes"
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
