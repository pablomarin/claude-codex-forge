$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("forge-retire-global-" + [Guid]::NewGuid().ToString("N"))
$script = Join-Path $root "scripts\retire-global.py"

function Write-Text([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Invoke-Retire([string]$TargetHome, [string[]]$Extra = @()) {
    $output = & python3 $script --repo-root $root --home $TargetHome --platform windows @Extra 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output }
}

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null

    $targetHome = Join-Path $scratch "home"
    $helper = Join-Path $targetHome ".forge\bin\forge-goal-authorize.ps1"
    Write-Text $helper "owned helper`n"
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $helper).Hash.ToLowerInvariant()
    Write-Text (Join-Path $targetHome ".forge\installed-files.tsv") ".forge/bin/forge-goal-authorize.ps1`t$hash`tv6`n"
    Write-Text (Join-Path $targetHome ".forge\version") "6`n"
    Write-Text (Join-Path $targetHome ".claude\CLAUDE.md") "PERSONAL CLAUDE`r`n<!-- forge:begin v6 -->`r`nOLD`r`n<!-- forge:end v6 -->`r`n"
    Write-Text (Join-Path $targetHome ".codex\AGENTS.md") "PERSONAL CODEX`r`n<!-- forge:begin v6 -->`r`nOLD`r`n<!-- forge:end v6 -->`r`n"

    $preview = Invoke-Retire $targetHome
    Require ($preview.Code -eq 0) "PowerShell retirement preview failed: $($preview.Output)"
    Require ($preview.Output.Contains("REMOVE .forge/bin/forge-goal-authorize.ps1")) "PowerShell preview did not prove the helper"
    Require ($preview.Output.Contains("PRESERVE .claude/CLAUDE.md personal-bytes")) "PowerShell preview did not preserve Claude bytes"
    $digest = ([regex]::Match($preview.Output, 'RETIRE_GLOBAL_DIGEST=([0-9a-f]{64})')).Groups[1].Value
    Require ($digest.Length -eq 64) "PowerShell preview emitted no digest"
    $apply = Invoke-Retire $targetHome @("--apply", "--digest", $digest)
    Require ($apply.Code -eq 0 -and $apply.Output.Contains("RETIRE_GLOBAL: COMPLETE")) "PowerShell apply failed: $($apply.Output)"
    Require (-not (Test-Path -LiteralPath $helper)) "PowerShell owned helper survived cleanup"
    Require (([IO.File]::ReadAllText((Join-Path $targetHome ".claude\CLAUDE.md"))).Contains("PERSONAL CLAUDE")) "PowerShell personal Claude bytes changed"

    $changedHome = Join-Path $scratch "changed"
    $changedHelper = Join-Path $changedHome ".forge\bin\forge-goal-authorize.ps1"
    Write-Text $changedHelper "owned helper`n"
    $changedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $changedHelper).Hash.ToLowerInvariant()
    Write-Text (Join-Path $changedHome ".forge\installed-files.tsv") ".forge/bin/forge-goal-authorize.ps1`t$changedHash`tv6`n"
    Write-Text $changedHelper "mutated`n"
    $changed = Invoke-Retire $changedHome
    Require ($changed.Code -eq 2 -and $changed.Output.Contains("BLOCKED .forge/bin/forge-goal-authorize.ps1")) "PowerShell modified helper was not blocked"

    $duplicateTarget = Join-Path $scratch "duplicate"
    Write-Text (Join-Path $duplicateTarget ".claude\CLAUDE.md") "<!-- forge:begin v6 -->`none`n<!-- forge:begin v6 -->`ntwo`n<!-- forge:end v6 -->`n"
    $duplicate = Invoke-Retire $duplicateTarget
    Require ($duplicate.Code -eq 2 -and $duplicate.Output.Contains("BLOCKED .claude/CLAUDE.md")) "PowerShell duplicate marker was not blocked"

    $partialTarget = Join-Path $scratch "partial"
    $partialMarker = Join-Path $partialTarget ".claude\CLAUDE.md"
    Write-Text $partialMarker "BEFORE`r`n<!-- forge:begin v6 -->`r`nOLD`r`n<!-- forge:end v6 -->`r`nAFTER`r`n"
    Write-Text (Join-Path $partialTarget ".forge\personal-note.txt") "KEEP`n"
    $partialPreview = Invoke-Retire $partialTarget
    Require ($partialPreview.Code -eq 0 -and $partialPreview.Output.Contains("PRESERVE .forge/personal-note.txt unknown")) "PowerShell partial preview did not preserve unknown bytes"
    $partialDigest = ([regex]::Match($partialPreview.Output, 'RETIRE_GLOBAL_DIGEST=([0-9a-f]{64})')).Groups[1].Value
    $partialApply = Invoke-Retire $partialTarget @("--apply", "--digest", $partialDigest)
    $partialText = [IO.File]::ReadAllText($partialMarker)
    Require ($partialApply.Code -eq 0 -and $partialText.Contains("BEFORE") -and $partialText.Contains("AFTER") -and -not $partialText.Contains("OLD")) "PowerShell partial apply changed personal marker bytes"
    Require ((Test-Path -LiteralPath (Join-Path $partialTarget ".forge\personal-note.txt"))) "PowerShell partial apply removed an unknown file"

    $settingsTarget = Join-Path $scratch "settings"
    $settingsPath = Join-Path $settingsTarget ".claude\settings.json"
    $settings = Get-Content -Raw (Join-Path $root "manifests\legacy-v6-global-settings.json") | ConvertFrom-Json
    $settings | Add-Member -NotePropertyName personal -NotePropertyValue ([pscustomobject]@{ keep = $true })
    $settings.permissions.deny += "PERSONAL_DENY"
    Write-Text $settingsPath (($settings | ConvertTo-Json -Depth 20) + "`n")
    $settingsPreview = Invoke-Retire $settingsTarget
    $settingsDigest = ([regex]::Match($settingsPreview.Output, 'RETIRE_GLOBAL_DIGEST=([0-9a-f]{64})')).Groups[1].Value
    $settingsApply = Invoke-Retire $settingsTarget @("--apply", "--digest", $settingsDigest)
    $settingsAfter = [IO.File]::ReadAllText($settingsPath)
    Require ($settingsApply.Code -eq 0 -and $settingsAfter.Contains("PERSONAL_DENY") -and $settingsAfter.Contains('"keep": true') -and -not $settingsAfter.Contains("forge-goal-authorize")) "PowerShell JSON inverse merge was not exact"

    $digestHome = Join-Path $scratch "digest"
    $marker = Join-Path $digestHome ".claude\CLAUDE.md"
    Write-Text $marker "PERSONAL`n<!-- forge:begin v6 -->`nOLD`n<!-- forge:end v6 -->`n"
    $digestPreview = Invoke-Retire $digestHome
    $oldDigest = ([regex]::Match($digestPreview.Output, 'RETIRE_GLOBAL_DIGEST=([0-9a-f]{64})')).Groups[1].Value
    $wrong = Invoke-Retire $digestHome @("--apply", "--digest", ("0" * 64))
    Require ($wrong.Code -eq 2 -and (Test-Path -LiteralPath $marker)) "PowerShell wrong digest did not block before writes"
    [IO.File]::AppendAllText($marker, "CHANGED`n")
    $stale = Invoke-Retire $digestHome @("--apply", "--digest", $oldDigest)
    Require ($stale.Code -eq 2 -and (Test-Path -LiteralPath $marker)) "PowerShell stale digest did not block before writes"

    $linkHome = Join-Path $scratch "link-home"
    $linkTarget = Join-Path $scratch "link-target"
    New-Item -ItemType Directory -Path $linkHome, $linkTarget -Force | Out-Null
    try {
        New-Item -ItemType SymbolicLink -Path (Join-Path $linkHome ".forge") -Target $linkTarget -ErrorAction Stop | Out-Null
        $linked = Invoke-Retire $linkHome
        Require ($linked.Code -eq 2 -and $linked.Output.Contains("BLOCKED .forge")) "PowerShell reparse-point control was not blocked"
    } catch {
        Write-Host "SKIP: runner did not permit reparse-point fixture"
    }

    $liveTarget = Join-Path $scratch "live"
    New-Item -ItemType Directory -Path $liveTarget -Force | Out-Null
    $release = ([regex]::Match([IO.File]::ReadAllText((Join-Path $root "docs\CHANGELOG.md")), '(?m)^##\s+(\d+\.\d+)')).Groups[1].Value
    & (Join-Path $root "scripts\materialize-adapters.ps1") -RepoRoot $root -Target $liveTarget -Scope global -Platform windows -ReleaseVersion $release | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "PowerShell current global harness fixture did not materialize" }
    $livePreview = Invoke-Retire $liveTarget
    $liveDigest = ([regex]::Match($livePreview.Output, 'RETIRE_GLOBAL_DIGEST=([0-9a-f]{64})')).Groups[1].Value
    $liveApply = Invoke-Retire $liveTarget @("--apply", "--digest", $liveDigest)
    $liveFiles = @(Get-ChildItem -LiteralPath $liveTarget -File -Recurse -Force -ErrorAction SilentlyContinue)
    Require ($livePreview.Code -eq 0 -and $liveApply.Code -eq 0 -and $liveFiles.Count -eq 0) "PowerShell current global harness did not retire completely: $($livePreview.Output) $($liveApply.Output)"

    Write-Host "PASS test-retire-global.ps1"
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
