# SessionStart hook: silently inject git context into Claude.
# Source-gated: git fetch + behind-check ONLY on startup|resume.

$ErrorActionPreference = 'SilentlyContinue'

# Read stdin JSON to get the session source ('startup'|'resume'|'clear'|'compact').
$inputJson = [Console]::In.ReadToEnd()
$source = ""
try {
    $data = $inputJson | ConvertFrom-Json
    if ($data.source) { $source = $data.source }
} catch { $source = "" }

try {
    $branch = git branch --show-current 2>$null
    if (-not $branch) { $branch = "unknown" }
} catch {
    $branch = "unknown"
}

$context = "Current branch: $branch"

if ($source -eq "startup" -or $source -eq "resume") {
    # Dot-source (not subprocess) — works in both PowerShell 5.1 (powershell.exe)
    # and 7 (pwsh). Spawning pwsh would fail on stock Windows.
    $hookDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $libPath = Join-Path $hookDir "lib\default-branch.ps1"
    $default = ""
    if (Test-Path $libPath) {
        . $libPath
        $detected = Get-DefaultBranch
        if ($detected) { $default = $detected }
    }

    # Helper-bail breadcrumb (mirrors session-start.sh): when default is empty,
    # append to additionalContext so Claude sees that drift detection skipped.
    if (-not $default) {
        $context = "$context (drift check skipped — default-branch helper bailed)"
    }

    if ($default) {
        # Run fetch with a 5s job timeout (PowerShell-native, no coreutils dependency).
        # CRITICAL: Start-Job's child runspace defaults its location to the user's
        # home directory (PS 5.1) or the parent's $PWD only if -WorkingDirectory is
        # passed (PS 6+). For 5.1 compatibility we capture $PWD outside and
        # Set-Location inside the job block so git runs in the actual repo.
        $cwd = (Get-Location).Path
        # Job emits the inner $LASTEXITCODE on the success stream so the parent
        # can distinguish "fetch succeeded" from "fetch failed but completed in <5s".
        # Without this gate, a fast-failing fetch (auth error, broken remote, host
        # down) makes $completed truthy and we'd compute drift from stale origin/* refs.
        $job = Start-Job -ArgumentList $cwd -ScriptBlock {
            param($dir)
            Set-Location -LiteralPath $dir
            git fetch origin --quiet 2>$null
            $LASTEXITCODE
        }
        $completed = Wait-Job $job -Timeout 5
        $jobExit = if ($completed) { Receive-Job $job -ErrorAction SilentlyContinue } else { 1 }
        Remove-Job $job -Force -ErrorAction SilentlyContinue

        if ($completed -and $jobExit -eq 0) {
            # Verify BOTH refs exist before rev-list — guards against exit-128 silently
            # reporting 0 behind when local <default> is missing.
            $null = git rev-parse --verify "$default" 2>$null
            $localOk = ($LASTEXITCODE -eq 0)
            $null = git rev-parse --verify "origin/$default" 2>$null
            $remoteOk = ($LASTEXITCODE -eq 0)
            if ($localOk -and $remoteOk) {
                $behind = git rev-list --count "$default..origin/$default" 2>$null
                if ($behind -and $behind -match '^\d+$' -and [int]$behind -gt 0) {
                    $context = "$context (default branch '$default' is $behind commits behind origin — pull before starting work)"
                }
            }
        }
    }

    # Forge version drift (advisory) — mirror of session-start.sh. Compare the project
    # pin vs this machine's stamp; direction via a [version] numeric compare (NOT string —
    # 5.50 vs 5.9). Fail-open ($ErrorActionPreference is already SilentlyContinue); never blocks.
    $proj = $env:CLAUDE_PROJECT_DIR
    if (-not $proj) { try { $proj = (git rev-parse --show-toplevel 2>$null) } catch { $proj = "" } }
    if ($proj -and $HOME) {
        $pin = ""; $mine = ""
        try { if (Test-Path (Join-Path $proj ".claude/.forge-version")) { $pin = (@(Get-Content (Join-Path $proj ".claude/.forge-version"))[0]).Trim() } } catch {}
        try { if (Test-Path (Join-Path $HOME ".claude/.forge-version")) { $mine = (@(Get-Content (Join-Path $HOME ".claude/.forge-version"))[0]).Trim() } } catch {}
        # Require a clean X.Y on BOTH sides — malformed/multiline fails open (no advisory).
        if (($pin -match '^\d+\.\d+$') -and ($mine -match '^\d+\.\d+$') -and $pin -ne $mine) {
            $mineOlder = $false
            try { $mineOlder = ([version]("$mine.0") -lt [version]("$pin.0")) } catch {}
            if ($mineOlder) {
                $context = "$context (this project pins Forge $pin; you're on $mine — don't run setup -Upgrade here unless you're the designated upgrader)"
            } else {
                $context = "$context (this project pins Forge $pin; you're on $mine — fine to work; only upgrade the project as a deliberate PR)"
            }
        }
    }
}

$output = @{
    hookSpecificOutput = @{
        hookEventName     = "SessionStart"
        additionalContext = $context
    }
} | ConvertTo-Json -Compress

Write-Output $output
exit 0
