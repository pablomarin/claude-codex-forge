# Canonical Forge workflow-state resolver. PowerShell 5.1 compatible.

function Get-ForgeStatePath {
    param(
        [Parameter(Mandatory = $false)][string]$Root = ".",
        [Parameter(Mandatory = $false)][ValidateSet("Read", "Write")][string]$Mode = "Read"
    )

    try { $physicalRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path }
    catch { throw "BLOCKED: invalid Forge state root: $Root" }

    $canonical = Join-Path $physicalRoot ".forge\local\state.md"
    $legacy = Join-Path $physicalRoot ".claude\local\state.md"
    foreach ($candidate in @(
        (Join-Path $physicalRoot ".forge"),
        (Join-Path $physicalRoot ".forge\local"),
        $canonical
    )) {
        if (Test-Path -LiteralPath $candidate) {
            if ((Get-Item -LiteralPath $candidate -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "BLOCKED: reparse-point Forge state path: $candidate"
            }
        }
    }
    if ($Mode -eq "Write") { return $canonical }

    $versionPath = Join-Path $physicalRoot ".forge\version"
    $version = ""
    $versionPresent = Test-Path -LiteralPath $versionPath
    if ($versionPresent) {
        if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf) -or
            ((Get-Item -LiteralPath $versionPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "BLOCKED: invalid Forge v6 state at $canonical"
        }
        $versionLines = @(Get-Content -LiteralPath $versionPath -ErrorAction SilentlyContinue)
        if ($versionLines.Count -gt 0 -and $null -ne $versionLines[0]) { $version = $versionLines[0].Trim() }
    }

    if ((Test-Path -LiteralPath $canonical) -or $versionPresent) {
        if ($versionPresent -and $version -ne "6") {
            throw "BLOCKED: invalid Forge v6 state at $canonical"
        }
        if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) {
            throw "BLOCKED: invalid Forge v6 state at $canonical"
        }
        $item = Get-Item -LiteralPath $canonical -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "BLOCKED: reparse-point Forge v6 state at $canonical"
        }
        $first = @(Get-Content -LiteralPath $canonical -TotalCount 1 -ErrorAction SilentlyContinue)[0]
        if ($first -ne "<!-- forge:state-schema v6 -->") {
            throw "BLOCKED: invalid Forge v6 state at $canonical"
        }
        return $canonical
    }

    if (Test-Path -LiteralPath $legacy -PathType Leaf) {
        foreach ($candidate in @((Join-Path $physicalRoot ".claude"), (Join-Path $physicalRoot ".claude\local"))) {
            if ((Get-Item -LiteralPath $candidate -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "BLOCKED: reparse-point legacy state path: $candidate"
            }
        }
        $item = Get-Item -LiteralPath $legacy -Force
        if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $legacy }
    }
    return $null
}
