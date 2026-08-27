param(
    [string]$Source = ".claude\local\state.md",
    [string]$Destination = ".forge\local\state.md"
)
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$python = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
if (-not $python) { [Console]::Error.WriteLine("BLOCKED: Python 3 is required for state translation"); exit 1 }
& $python.Source (Join-Path $repoRoot "scripts\merge-settings.py") migrate-state-v5-v6 `
    --source $Source --destination $Destination
exit $LASTEXITCODE
