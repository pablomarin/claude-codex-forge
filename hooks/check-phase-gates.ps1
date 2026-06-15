# hooks/check-phase-gates.ps1 — PreToolUse phase-gate guard.
# Delegates policy to hooks/lib/forge-workflow.ps1.

$InputJson = ""
try {
    if ([Console]::IsInputRedirected) { $InputJson = [Console]::In.ReadToEnd() }
} catch {}

$Root = $env:CLAUDE_PROJECT_DIR
if (-not $Root) {
    $Cwd = ""
    try {
        if ($InputJson) {
            $Data = $InputJson | ConvertFrom-Json
            if ($Data.cwd) { $Cwd = [string]$Data.cwd }
        }
    } catch {}
    if ($Cwd -and (Test-Path $Cwd)) {
        try { $Root = (& git -C $Cwd rev-parse --show-toplevel 2>$null) } catch {}
        if (-not $Root) { $Root = $Cwd }
    } else {
        try { $Root = (& git rev-parse --show-toplevel 2>$null) } catch {}
        if (-not $Root) { $Root = (Get-Location).Path }
    }
}

$Lib = Join-Path $Root ".claude\hooks\lib\forge-workflow.ps1"
if (-not (Test-Path $Lib)) { $Lib = Join-Path $Root "hooks\lib\forge-workflow.ps1" }
if (-not (Test-Path $Lib)) { exit 0 }

$InputJson | & $Lib check-tool
exit $LASTEXITCODE
