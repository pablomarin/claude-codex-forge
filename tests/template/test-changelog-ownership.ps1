# Native Windows PowerShell 5.1 suite; PS7 runs are portable smoke only.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$runtime = (Get-Process -Id $PID).Path
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('forge-changelog-' + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding $false
$passes = 0; $failures = 0
function Assert-Check([bool]$Condition, [string]$Label) {
    if ($Condition) { $script:passes++; Write-Host "PASS: $Label" }
    else { $script:failures++; Write-Host "FAIL: $Label" }
}
function Write-Text([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, $script:utf8)
}
$initialPath = $env:PATH
$fixtureBin = Join-Path $tmp 'bin'
foreach ($hostName in @('claude','codex')) {
    if ($env:OS -eq 'Windows_NT') {
        Write-Text (Join-Path $fixtureBin "$hostName.cmd") "@echo off`r`nexit /b 127`r`n"
    } else {
        Write-Text (Join-Path $fixtureBin $hostName) "#!/bin/sh`nexit 127`n"
        & chmod +x (Join-Path $fixtureBin $hostName)
    }
}
$env:PATH = $fixtureBin + [IO.Path]::PathSeparator + $env:PATH
try {
    foreach ($layout in @('none','nested','root-and-nested')) {
        $project = Join-Path $tmp $layout
        Write-Text (Join-Path $project 'package.json') '{"name":"customer-project"}'
        & git -C $project init -q
        if ($LASTEXITCODE -ne 0) { throw 'fixture Git initialization failed' }
        $nested = Join-Path $project 'apps/customer/docs/CHANGELOG.md'
        $rootHistory = Join-Path $project 'docs/CHANGELOG.md'
        if ($layout -ne 'none') {
            Write-Text $nested ("# Customer history`r`n`r`nExisting release: caf" + [char]0xE9 + ".`r`n")
            $nestedHash = (Get-FileHash -LiteralPath $nested -Algorithm SHA256).Hash
        }
        if ($layout -eq 'root-and-nested') {
            Write-Text $rootHistory "# Tooling history`n`nExisting customer-owned root history.`n"
            $rootHash = (Get-FileHash -LiteralPath $rootHistory -Algorithm SHA256).Hash
        }
        foreach ($mode in @('install','upgrade','refresh')) {
            $arguments = @('-NoProfile','-NonInteractive','-File',(Join-Path $root 'setup.ps1'),'-ThisCheckoutOnly')
            if ($mode -eq 'upgrade') { $arguments += '-Upgrade' }
            if ($mode -eq 'refresh') { $arguments += '-Force' }
            Push-Location -LiteralPath $project
            try {
                & $runtime @arguments > (Join-Path $tmp "$layout-$mode.log") 2>&1
                $status = $LASTEXITCODE
            } finally { Pop-Location }
            Assert-Check ($status -eq 0) "$mode succeeds for $layout"
            Assert-Check (Test-Path -LiteralPath (Join-Path $project '.forge/version')) "$mode retains Forge version metadata"
            if ($layout -eq 'root-and-nested') {
                Assert-Check ((Get-FileHash -LiteralPath $rootHistory -Algorithm SHA256).Hash -eq $rootHash) "$mode preserves existing root history bytes"
            } else {
                Assert-Check (-not (Test-Path -LiteralPath $rootHistory)) "$mode does not create a root changelog"
            }
            if ($layout -ne 'none') {
                Assert-Check ((Get-FileHash -LiteralPath $nested -Algorithm SHA256).Hash -eq $nestedHash) "$mode preserves existing nested history bytes"
            }
        }
    }
} finally { $env:PATH = $initialPath }
Write-Host "Changelog ownership: $passes passed, $failures failed; fixtures=$tmp"
if ($failures) { exit 1 }
exit 0
