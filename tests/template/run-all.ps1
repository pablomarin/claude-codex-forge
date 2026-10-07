param([switch]$ListSuites, [string]$SuiteName, [string]$ResultPath)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$runner = (Resolve-Path $MyInvocation.MyCommand.Path).Path
$suites = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "test-*.ps1" -File | Sort-Object Name)
$duplicates = @($suites | Group-Object Name | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw "duplicate PowerShell suites: $($duplicates.Name -join ', ')" }
if ($suites.Count -eq 0) { throw "no PowerShell behavioral suites discovered" }
if ($ListSuites) {
    if ($SuiteName -or $ResultPath) { throw "discovery cannot execute a suite or write a result" }
    ConvertTo-Json -InputObject @($suites | ForEach-Object { $_.Name }) -Compress
    exit 0
}
if ($SuiteName) {
    $suites = @($suites | Where-Object { $_.Name -ceq $SuiteName })
    if ($suites.Count -ne 1) { throw "unknown exact PowerShell suite: $SuiteName" }
}
if ($ResultPath) {
    if (-not $SuiteName -or -not [IO.Path]::IsPathRooted($ResultPath)) { throw "results require an exact suite and absolute outside-checkout path" }
    $ResultPath = [IO.Path]::GetFullPath($ResultPath)
    $parent = Split-Path -Parent $ResultPath
    # Existing physical parent prevents symlink/reparse aliases into this checkout.
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "result parent must exist outside checkout" }
    $physical = (Resolve-Path -LiteralPath $parent).Path
    $cursor = Get-Item -LiteralPath $physical
    while ($null -ne $cursor) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "result parent cannot traverse reparse points" }
        $cursor = $cursor.Parent
    }
    $comparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ($physical.Equals($root, $comparison) -or $physical.StartsWith($root + [IO.Path]::DirectorySeparatorChar, $comparison)) { throw "result path must be outside checkout" }
    if (Test-Path -LiteralPath $ResultPath) { throw "result path must be new" }
}
function Get-CandidateObservation {
    $head = & git -C $root rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw "cannot resolve candidate HEAD" }
    $tree = & git -C $root rev-parse 'HEAD^{tree}'
    if ($LASTEXITCODE -ne 0) { throw "cannot resolve candidate tree" }
    $status = @(& git -C $root status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0) { throw "cannot observe candidate status" }
    return @{ head = [string]$head; tree = [string]$tree; clean = ($status.Count -eq 0) }
}
$failedSuites = @()
foreach ($suite in $suites) {
    if ($suite.FullName -eq $runner) { throw "runner discovered itself" }
    $before = if ($ResultPath) { Get-CandidateObservation } else { $null }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "SUITE_START name=$($suite.Name) utc=$([DateTime]::UtcNow.ToString('o'))"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $suite.FullName
    $code = $LASTEXITCODE
    $timer.Stop()
    if ($null -eq $code) { throw "suite did not return a process exit code" }
    $elapsed = $timer.Elapsed.TotalSeconds.ToString('F3', [Globalization.CultureInfo]::InvariantCulture)
    Write-Host "SUITE_END name=$($suite.Name) exit=$code elapsed_s=$elapsed utc=$([DateTime]::UtcNow.ToString('o'))"
    if ($ResultPath) {
        $after = Get-CandidateObservation
        $result = [ordered]@{
            format = 'forge-windows-suite-v1'; suite = $suite.Name; exit_code = [int]$code
            elapsed_seconds = $timer.Elapsed.TotalSeconds
            ps_major = $PSVersionTable.PSVersion.Major; ps_minor = $PSVersionTable.PSVersion.Minor
            os = [string]$env:OS
            head_before = $before.head; tree_before = $before.tree; clean_before = $before.clean
            head_after = $after.head; tree_after = $after.tree; clean_after = $after.clean
        }
        [IO.File]::WriteAllText($ResultPath, ($result | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
    }
    if ($code -ne 0) { $failedSuites += $suite.Name; Write-Host "FAIL: $($suite.Name)" }
}
if ($failedSuites.Count -ne 0) { throw "PowerShell suites failed: $($failedSuites -join ', ')" }
Write-Host "PASS: $($suites.Count) PowerShell suites"
