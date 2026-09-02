# Canonical Forge workflow-state resolver. PowerShell 5.1 compatible.

function Test-ForgeStateV6 {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    $lines = @([IO.File]::ReadAllLines($Path))
    if ($lines.Count -eq 0 -or $lines[0] -ne '<!-- forge:state-schema v6 -->') { return $false }

    $matches = New-Object Collections.Generic.List[int]
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq '## Workflow') { $matches.Add($i) } }
    if ($matches.Count -ne 1) { return $false }
    $workflowIndex = $matches[0]

    $counts = @{ 'Command' = 0; 'Phase' = 0; 'Next step' = 0 }
    for ($i = $workflowIndex + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^## ') { break }
        if ($lines[$i] -match '^\|\s*(Command|Phase|Next step)\s*\|') { $counts[$Matches[1]]++ }
    }
    return ($counts['Command'] -eq 1 -and $counts['Phase'] -le 1 -and $counts['Next step'] -le 1)
}

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
        if (-not (Test-ForgeStateV6 $canonical)) {
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
