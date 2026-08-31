# hooks/lib/default-branch.ps1 — detect the repo's default branch.
#
# Detection chain (mirrors hooks/lib/default-branch.sh):
#   1. git symbolic-ref refs/remotes/origin/HEAD --short
#   2. fallback: local main exists
#   3. fallback: local master exists
#   4. bail (exit 1)
#
# Contract: branch name on stdout, exit 0/1, no stderr noise.
#
# Dual-mode (CRITICAL for cross-launcher safety):
#   On Windows, the shipped Claude Code launcher is `powershell.exe` (5.1) per
#   settings/settings-windows.template.json. Spawning `pwsh` (7+) from inside
#   a 5.1 hook would fail on stock Windows because pwsh is not installed.
#   Therefore consumer hooks MUST dot-source this file, not subprocess it:
#     . "$libPath"
#     $default = Get-DefaultBranch
#   Dot-source works identically in 5.1 and 7+, no subprocess required.

function Get-DefaultBranch {
    $ErrorActionPreference = 'SilentlyContinue'

    # Method 1: origin/HEAD symbolic ref.
    # Same stale-rename caveat as the bash version: verify origin/<candidate>
    # actually exists before trusting Method 1's output.
    $ref = git symbolic-ref --short -q refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $ref) {
        $candidate = $ref -replace '^origin/', ''
        if ($candidate) {
            $null = git show-ref --verify --quiet "refs/remotes/origin/$candidate" 2>$null
            if ($LASTEXITCODE -eq 0) {
                return $candidate
            }
            # Fall through: stale rename — origin/HEAD points at a retired branch.
        }
    }
    # Method 2: local main exists
    $null = git show-ref --verify --quiet refs/heads/main 2>$null
    if ($LASTEXITCODE -eq 0) {
        return 'main'
    }
    # Method 3: local master exists
    $null = git show-ref --verify --quiet refs/heads/master 2>$null
    if ($LASTEXITCODE -eq 0) {
        return 'master'
    }
    return $null
}

# Dual-mode entry point. When invoked as a script (e.g. via `& "$libPath"` or
# `pwsh -File "$libPath"`), call the function and emit the branch name on the
# PowerShell success/stdout stream so BOTH in-PowerShell callers (`$x = & "$libPath"`)
# AND bash subprocess callers (`$(pwsh -File ...)`) capture it correctly.
# When dot-sourced, $MyInvocation.InvocationName is "." — the function is
# defined and this block is skipped.
#
# IMPORTANT — choice of emission API:
#   - Write-Host           → information stream; INVISIBLE to in-PS capture. Wrong.
#   - [Console]::Out.Write → process stdout but NOT the PS success stream;
#                            invisible to `& "$libPath"` capture. Wrong.
#   - Write-Output         → success stream; captured by both in-PS callers AND
#                            bash subprocess capture. Adds a trailing newline,
#                            but `$(pwsh -File ...)` strips trailing whitespace,
#                            so the bash side is fine. CORRECT.
if ($MyInvocation.InvocationName -ne '.') {
    $branch = Get-DefaultBranch
    if ($branch) {
        Write-Output $branch
        exit 0
    } else {
        exit 1
    }
}
