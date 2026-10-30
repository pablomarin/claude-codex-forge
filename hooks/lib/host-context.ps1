param(
    [Parameter(Mandatory = $true)][ValidateSet('hook', 'launch', 'prepare-context', 'probe', 'check-process', 'probe-event')][string]$Mode,
    [Alias('Host')][ValidateSet('claude', 'codex')][string]$EngineHost,
    [string[]]$LaunchArguments = @(),
    [string]$LaunchArgumentsJson,
    [ValidateSet('agent', 'council')][string]$LaunchTarget = 'agent',
    [string]$Worktree,
    [string]$ExpectedRootHex
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

function Convert-ContextPath([string]$Path) {
    if ($Path -match '[\x00-\x1f\x7f]') { throw 'context path contains a control character' }
    if ($env:OS -eq 'Windows_NT') { return $Path.Replace('\', '/').ToLowerInvariant() }
    return $Path
}
function Get-ContextRoot([string]$Directory) {
    $absolute = if ($env:OS -eq 'Windows_NT') {
        $Directory -match '^(?:[A-Za-z]:[\\/]|[\\/]{2}[^\\/]+[\\/][^\\/]+)'
    } else { $Directory.StartsWith('/') }
    if (-not $Directory -or -not $absolute -or -not (Test-Path -LiteralPath $Directory -PathType Container)) {
        throw 'event/process directory must be an existing absolute directory'
    }
    $encoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        $rootValue = @(& git -C $Directory rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -ne 0 -or $rootValue.Count -ne 1) { throw 'directory is outside a Git worktree' }
        $root = (Resolve-Path -LiteralPath ([string]$rootValue[0])).ProviderPath
        $commonValue = @(& git -C $root rev-parse --git-common-dir 2>$null)
        if ($LASTEXITCODE -ne 0 -or $commonValue.Count -ne 1) { throw 'Git common directory is unavailable' }
        $common = [string]$commonValue[0]
        if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $root $common }
        $common = (Resolve-Path -LiteralPath $common).ProviderPath
        return [PSCustomObject]@{ Root = (Convert-ContextPath $root); Common = (Convert-ContextPath $common) }
    } finally { [Console]::OutputEncoding = $encoding }
}
function Decode-ContextRoot([string]$Hex) {
    if ($Hex.Length -lt 2 -or $Hex.Length -gt 16384 -or $Hex -cnotmatch '\A(?:[0-9a-f]{2})+\z') {
        throw 'expected root must be bounded, even lowercase UTF-8 hex'
    }
    $bytes = New-Object byte[] ($Hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
        if ($bytes[$i] -eq 0) { throw 'expected root contains a NUL byte' }
    }
    $decoder = New-Object Text.UTF8Encoding($false, $true)
    $decoded = $decoder.GetString($bytes)
    if ($decoded -match '[\x00-\x1f\x7f]' -or (-not $decoded.StartsWith('/') -and $decoded -cnotmatch '\A[a-z]:/')) {
        throw 'expected root must be a canonical absolute path without control characters'
    }
    return $decoded
}
function Assert-UniqueJsonKeys([string]$Text) {
    # ConvertFrom-Json can silently keep a duplicate key's last value. Check
    # object keys before using any command or cwd from this diagnostic event.
    $tokens = [regex]::Matches($Text, '"(?:\\.|[^"\\])*"|[{}\[\],:]|[^{}\[\],:\s]+')
    # PowerShell 7's JSON reader permits comments/trailing commas. Native hook
    # events use strict JSON; reject those extensions consistently with 5.1.
    $withoutStrings = [regex]::Replace($Text, '"(?:\\.|[^"\\])*"', '""')
    if ($withoutStrings -match '//|/\*|,\s*[}\]]') { throw 'malformed native event JSON' }
    $stack = New-Object Collections.Stack
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = $tokens[$i].Value
        if ($token.StartsWith('"') -and $token -match '[\x00-\x1f]') { throw 'unescaped control character in native JSON' }
        if ($token -eq '{' -or $token -eq '[') {
            $keys = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            $stack.Push([PSCustomObject]@{ IsObject = ($token -eq '{'); Keys = $keys })
        } elseif ($token -eq '}' -or $token -eq ']') {
            if ($stack.Count -eq 0) { throw 'malformed native event JSON' }
            $null = $stack.Pop()
        } elseif ($token.StartsWith('"') -and $i + 1 -lt $tokens.Count -and $tokens[$i + 1].Value -eq ':') {
            if ($stack.Count -eq 0 -or -not $stack.Peek().IsObject) { throw 'malformed native event JSON' }
            $key = @(ConvertFrom-Json -InputObject ('[' + $token + ']'))[0]
            if (-not $stack.Peek().Keys.Add([string]$key)) { throw 'duplicate native event JSON key' }
        }
    }
}

$expectedDisplay = '<unavailable>'
$actualDisplay = '<unavailable>'
try {
    if ($Mode -eq 'probe') {
        [Console]::Error.WriteLine('FORGE_NATIVE_CONTEXT: UNVERIFIED; the probe process ran without an observed native diagnostic denial. Keep normal hooks enabled; do not treat a local process check as native alignment.')
        exit 2
    }
    if ($Mode -eq 'prepare-context') {
        $context = Get-ContextRoot $Worktree
        $bytes = (New-Object Text.UTF8Encoding($false, $true)).GetBytes($context.Root)
        $hex = ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
        $null = Decode-ContextRoot $hex
        $helper = '.forge/hooks/lib/host-context.ps1'
        if (-not (Test-Path -LiteralPath (Join-Path $context.Root $helper) -PathType Leaf)) { $helper = 'hooks/lib/host-context.ps1' }
        $null = Resolve-FixedTarget (Join-Path $context.Root $helper) 'context'
        $engine = if ([IO.Path]::GetFileNameWithoutExtension((Get-Process -Id $PID).Path) -eq 'powershell') { 'powershell.exe' } else { 'pwsh' }
        if (-not (Get-Command $engine -CommandType Application -ErrorAction SilentlyContinue)) { throw 'PowerShell engine is not available on PATH' }
        Write-Output "$engine -NoProfile -ExecutionPolicy Bypass -File $helper -Mode probe -ExpectedRootHex $hex"
        Write-Output "$engine -NoProfile -ExecutionPolicy Bypass -File $helper -Mode check-process -ExpectedRootHex $hex"
        exit 0
    }
    if ($Mode -eq 'probe-event') {
        [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
        $raw = [Console]::In.ReadToEnd()
        # This operation only diagnoses the fixed probe. It never rewrites cwd,
        # executes the command, or grants permission to another operation.
        $family = '(?:bash (?:\.forge/)?hooks/lib/host-context\.sh probe\b|(?:powershell\.exe|pwsh) -NoProfile -ExecutionPolicy Bypass -File (?:\.forge/)?hooks/lib/host-context\.ps1 -Mode probe\b)'
        try { $event = ConvertFrom-Json -InputObject $raw } catch {
            if ($raw -cmatch ('"command"\s*:\s*"' + $family)) { throw 'malformed native event JSON' }
            exit 0
        }
        $command = $event.tool_input.command
        if ($command -isnot [string] -or $command -cnotmatch ('\A' + $family)) { exit 0 }
        if (-not $raw.TrimStart().StartsWith('{') -or $event -isnot [PSCustomObject] -or $event.tool_input -isnot [PSCustomObject]) {
            throw 'native event and tool_input must be JSON objects'
        }
        if ($raw.Contains([string][char]0)) { throw 'native event JSON contains a raw NUL byte' }
        Assert-UniqueJsonKeys $raw
        $bashPattern = '\Abash (?:\.forge/)?hooks/lib/host-context\.sh probe (?<hex>[0-9a-f]+)\z'
        $psPattern = '\A(?:powershell\.exe|pwsh) -NoProfile -ExecutionPolicy Bypass -File (?:\.forge/)?hooks/lib/host-context\.ps1 -Mode probe -ExpectedRootHex (?<hex>[0-9a-f]+)\z'
        if ($command -match '[\r\n\x00]' -or -not ($command -cmatch $bashPattern -or $command -cmatch $psPattern)) {
            throw 'probe must be one exact canonical command, without extra tokens or shell composition'
        }
        $expectedDisplay = Decode-ContextRoot $Matches.hex
        if ($event.cwd -isnot [string]) { throw 'native event cwd is missing or not a string' }
        $context = Get-ContextRoot $event.cwd
        $actualDisplay = $context.Root
        if ($actualDisplay -cne $expectedDisplay) { throw 'native event belongs to another worktree' }
        [Console]::Error.WriteLine("FORGE_NATIVE_CONTEXT: MATCH expected=$expectedDisplay actual=$actualDisplay common=$($context.Common). Intentional diagnostic denial; run the separate check-process command. This grants no shipping authority.")
        exit 2
    }
    if ($Mode -eq 'check-process') {
        $expectedDisplay = Decode-ContextRoot $ExpectedRootHex
        $context = Get-ContextRoot (Get-Location).ProviderPath
        $actualDisplay = $context.Root
        if ($actualDisplay -cne $expectedDisplay) { throw 'tool process belongs to another worktree' }
        Write-Output "FORGE_PROCESS_CONTEXT: MATCH expected=$expectedDisplay actual=$actualDisplay common=$($context.Common); native=UNVERIFIED by this process check."
        exit 0
    }
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
    if ($Mode -eq 'probe-event') {
        [Console]::Error.WriteLine("FORGE_NATIVE_CONTEXT: MISMATCH expected=$expectedDisplay actual=$actualDisplay; $($_.Exception.Message). Bind or open the existing intended worktree in the native host, then repeat probe and check-process. Do not copy receipts or rewrite event cwd.")
    } elseif ($Mode -eq 'check-process') {
        [Console]::Error.WriteLine("FORGE_PROCESS_CONTEXT: MISMATCH expected=$expectedDisplay actual=$actualDisplay; $($_.Exception.Message)")
    } else { [Console]::Error.WriteLine($_.Exception.Message) }
    exit 2
}
