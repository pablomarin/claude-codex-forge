$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$runner = (Resolve-Path $MyInvocation.MyCommand.Path).Path
$suites = @(Get-ChildItem -Path $PSScriptRoot -Filter "test-*.ps1" -File | Sort-Object Name)
$duplicates = @($suites | Group-Object Name | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw "duplicate PowerShell suites: $($duplicates.Name -join ', ')" }
if ($suites.Count -eq 0) { throw "no PowerShell behavioral suites discovered" }
$failedSuites = @()
foreach ($suite in $suites) {
    if ($suite.FullName -eq $runner) { throw "runner discovered itself" }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $suite.FullName
    if ($LASTEXITCODE -ne 0) { $failedSuites += $suite.Name; Write-Host "FAIL: $($suite.Name)" }
}
if ($failedSuites.Count -ne 0) { throw "PowerShell suites failed: $($failedSuites -join ', ')" }
Write-Host "PASS: $($suites.Count) PowerShell suites"
