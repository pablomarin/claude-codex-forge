param(
    [Parameter(Mandatory = $true)][ValidateSet('hook', 'launch')][string]$Mode,
    [Alias('Host')][ValidateSet('claude', 'codex')][string]$EngineHost,
    [string[]]$LaunchArguments = @(),
    [string]$LaunchArgumentsJson,
    [ValidateSet('agent', 'council')][string]$LaunchTarget = 'agent'
)

$ErrorActionPreference = 'Stop'
$ScriptPath = (Get-Item -LiteralPath $MyInvocation.MyCommand.Path -Force).FullName

function Get-Root {
    $value = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[invariant]: Git worktree required' }
    return (Resolve-Path $value).Path
}
function Assert-TestModeAllowed {
    $rootPrefix = (Get-Root).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if ($ScriptPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'BLOCKED[invariant]: test launcher override is disabled in an installed harness'
    }
}
function Resolve-FixedTarget([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "BLOCKED[invariant]: fixed $Label dispatcher is unavailable" }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "BLOCKED[invariant]: linked $Label dispatcher rejected" }
    return $item.FullName
}
function Get-Launcher {
    $path = Join-Path (Get-Root) '.forge/hooks/lib/agent-dispatch.ps1'
    if ($env:FORGE_HOST_CONTEXT_TEST_MODE -eq '1' -and $env:FORGE_HOST_CONTEXT_TEST_LAUNCHER) {
        Assert-TestModeAllowed
        $path = $env:FORGE_HOST_CONTEXT_TEST_LAUNCHER
    }
    return Resolve-FixedTarget $path 'agent'
}
function Get-Council {
    $path = Join-Path (Get-Root) '.forge/hooks/lib/council-dispatch.ps1'
    if ($env:FORGE_HOST_CONTEXT_TEST_MODE -eq '1') {
        Assert-TestModeAllowed
        if ($env:FORGE_HOST_CONTEXT_TEST_COUNCIL) { $path = $env:FORGE_HOST_CONTEXT_TEST_COUNCIL }
        elseif ($env:FORGE_HOST_CONTEXT_TEST_LAUNCHER) { return Get-Launcher }
    }
    return Resolve-FixedTarget $path 'council'
}

try {
    if (-not $EngineHost) { throw 'BLOCKED[invariant]: host must be claude or codex' }
    if ($Mode -eq 'hook') {
        $null = [Console]::In.ReadToEnd()
        exit 0
    }

    $boundArguments = if ($LaunchArgumentsJson) { @($LaunchArgumentsJson | ConvertFrom-Json) } else { @($LaunchArguments) }
    $target = if ($LaunchTarget -eq 'council') { Get-Council } else { Get-Launcher }
    $env:FORGE_NATIVE_HOST = $EngineHost
    Remove-Item Env:FORGE_NATIVE_SESSION_ID, Env:FORGE_HOST_CONTEXT_FILE, Env:FORGE_HOST_CONTEXT_LAUNCHER_HASH -ErrorAction SilentlyContinue
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $target @boundArguments
    exit $LASTEXITCODE
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
}
