param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $false)][ValidateSet("project", "global")][string]$Scope = "project"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
    [Console]::Error.WriteLine("BLOCKED: transaction root is missing or not a directory: $Target")
    exit 1
}
$targetItem = Get-Item -LiteralPath $Target -Force
$targetAncestor = $targetItem
while ($null -ne $targetAncestor) {
    if ($targetAncestor.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        [Console]::Error.WriteLine("BLOCKED: junction/reparse-point transaction root ancestor: $($targetAncestor.FullName)")
        exit 1
    }
    $targetAncestor = $targetAncestor.Parent
}
$targetRoot = (Resolve-Path -LiteralPath $Target).Path
if ($Scope -eq "global") {
    if (-not [IO.Path]::IsPathRooted($Target) -or $Target -cne $targetRoot) {
        [Console]::Error.WriteLine("BLOCKED: selected global Forge home is not canonical: $Target")
        exit 1
    }
    $trimmedTarget = $targetRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $trimmedRoot = [IO.Path]::GetPathRoot($targetRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($trimmedTarget -eq $trimmedRoot) {
        [Console]::Error.WriteLine("BLOCKED: drive/UNC root cannot be selected as the global Forge home: $Target")
        exit 1
    }
}

# PowerShell 5.1 exposes symlinks, junctions, and other reparse points through
# FileAttributes.ReparsePoint. Reject every host root before Python creates the
# transaction guard; the shared engine repeats the no-follow checks per file.
foreach ($relative in @(".forge", ".claude", ".codex", ".agents")) {
    $candidate = Join-Path $targetRoot $relative
    if (Test-Path -LiteralPath $candidate) {
        $item = Get-Item -LiteralPath $candidate -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            [Console]::Error.WriteLine("BLOCKED: junction/reparse-point managed path: $candidate")
            exit 1
        }
    }
}

$python = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
if (-not $python) {
    [Console]::Error.WriteLine("BLOCKED: Python 3 is required for authoritative JSON/state migration; no files were changed.")
    exit 1
}

& $python.Source (Join-Path $repoRoot "scripts\merge-settings.py") full-refresh `
    --repo-root $repoRoot --target $targetRoot --scope $Scope --platform windows
exit $LASTEXITCODE
