param(
    [Parameter(Mandatory = $true)][string]$Journal,
    [string]$Target = "."
)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$python = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
if (-not $python) { [Console]::Error.WriteLine("BLOCKED: Python 3 is required for recover-full-refresh"); exit 1 }
& $python.Source (Join-Path $repoRoot "scripts\merge-settings.py") recover-full-refresh `
    --journal $Journal --target $Target
exit $LASTEXITCODE
