param(
    [Parameter(Mandatory = $true)][ValidateSet('hook', 'issue-test', 'verify', 'launch')][string]$Mode,
    [ValidateSet('claude', 'codex')][string]$Host,
    [string]$SessionId,
    [string[]]$LaunchArguments = @(),
    [string]$LaunchArgumentsJson
)

$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$ScriptPath = (Get-Item -LiteralPath $MyInvocation.MyCommand.Path -Force).FullName
function Get-Sha([byte[]]$Bytes) { $sha = [Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() } }
function Get-ShaFile([string]$Path) { if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'MISSING' }; $item = Get-Item -LiteralPath $Path -Force; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return 'MISSING' }; return Get-Sha ([IO.File]::ReadAllBytes($Path)) }
function Get-Root { $value = (& git rev-parse --show-toplevel 2>$null); if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[invariant]: Git worktree required' }; return (Resolve-Path $value).Path }
function Get-Identity { $root = Get-Root; $common = (& git -C $root rev-parse --git-common-dir); $physical = (Resolve-Path (Join-Path $root $common)).Path; return Get-Sha ($Utf8.GetBytes("$root|$physical`n")) }
function Get-Revision { return Get-ShaFile (Join-Path (Get-Root) '.forge/managed-files.tsv') }
function Get-Value([string]$Path, [string]$Key) { $rows = @(Get-Content -LiteralPath $Path | Where-Object { $_ -like "$Key=*" }); if ($rows.Count -ne 1) { throw "BLOCKED[invariant]: context key $Key must occur exactly once" }; return $rows[0].Substring($Key.Length + 1) }
function Assert-TestModeAllowed {
    $rootPrefix = (Get-Root).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if ($ScriptPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'BLOCKED[invariant]: test host authority is disabled in an installed harness' }
}
function Get-AuthorityRoot {
    if ($env:FORGE_HOST_CONTEXT_TEST_MODE -eq '1') { Assert-TestModeAllowed; if (-not $env:FORGE_HOST_CONTEXT_TEST_ROOT) { throw 'BLOCKED[invariant]: test authority root is required' }; return [IO.Path]::GetFullPath($env:FORGE_HOST_CONTEXT_TEST_ROOT) }
    return Join-Path ([Environment]::GetFolderPath('UserProfile')) '.forge/host-contexts'
}
function Get-Launcher {
    $path = Join-Path (Get-Root) '.forge/hooks/lib/agent-dispatch.ps1'
    if ($env:FORGE_HOST_CONTEXT_TEST_MODE -eq '1' -and $env:FORGE_HOST_CONTEXT_TEST_LAUNCHER) { Assert-TestModeAllowed; $path = $env:FORGE_HOST_CONTEXT_TEST_LAUNCHER }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'BLOCKED[invariant]: fixed dispatcher launcher is unavailable' }
    $item = Get-Item -LiteralPath $path -Force; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'BLOCKED[invariant]: linked dispatcher launcher rejected' }
    return $item.FullName
}
function Get-CurrentReceipt { return Join-Path (Join-Path (Get-AuthorityRoot) (Get-Identity)) 'current.ctx' }
function Get-ActiveReceipt([string]$NativeHost) { return Join-Path (Join-Path (Get-AuthorityRoot) (Get-Identity)) "active-$NativeHost.ctx" }
function Assert-NoReparseAncestors([string]$Path) {
    $cursor = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    while ($cursor) { if (Test-Path -LiteralPath $cursor) { $item = Get-Item -LiteralPath $cursor -Force; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'BLOCKED[invariant]: reparse point in protected host receipt path' } }; $next = Split-Path -Parent $cursor; if ($next -eq $cursor) { break }; $cursor = $next }
}
function Test-Receipt([string]$ExpectedHost, [string]$Launcher) {
    $path = Get-ActiveReceipt $ExpectedHost
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'BLOCKED[invariant]: protected active-host receipt is required' }
    Assert-NoReparseAncestors $path; $item = Get-Item -LiteralPath $path -Force; if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'BLOCKED[invariant]: linked protected host receipt rejected' }
    if ((Get-Value $path 'schema_version') -ne '2' -or (Get-Value $path 'active_host') -cne $ExpectedHost) { throw 'BLOCKED[invariant]: active host receipt mismatch' }
    if ((Get-Value $path 'context_revision') -cne (Get-Revision) -or (Get-Value $path 'worktree_identity') -cne (Get-Identity)) { throw 'BLOCKED[invariant]: stale or cross-worktree host receipt' }
    $launcherHash = Get-ShaFile $Launcher
    if ((Get-Value $path 'launcher_path') -cne $Launcher -or (Get-Value $path 'launcher_hash') -cne $launcherHash) { throw 'BLOCKED[invariant]: host receipt launcher binding mismatch' }
    [long]$issued = Get-Value $path 'issued_epoch'; [long]$expires = Get-Value $path 'expires_epoch'; $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($issued -gt $now -or $expires -lt $now -or -not (Get-Value $path 'nonce') -or -not (Get-Value $path 'session_id')) { throw 'BLOCKED[invariant]: expired or incomplete host receipt' }
    $withoutHash = (@(Get-Content -LiteralPath $path | Where-Object { $_ -notlike 'receipt_hash=*' }) -join "`n") + "`n"
    $stored = Get-Value $path 'receipt_hash'; if ($stored -cne (Get-Sha ($Utf8.GetBytes($withoutHash)))) { throw 'BLOCKED[invariant]: host receipt hash mismatch' }
    return @{ Path = $path; Session = Get-Value $path 'session_id'; Hash = $stored; LauncherHash = $launcherHash }
}
function Write-Receipt([string]$NativeHost, [string]$NativeSession) {
    if (-not $NativeHost -or -not $NativeSession -or $NativeSession.Contains("`n") -or $NativeSession.Contains("`r")) { throw 'BLOCKED[invariant]: native SessionStart event lacks a safe host/session binding' }
    $launcher = Get-Launcher; $target = Get-CurrentReceipt; Assert-NoReparseAncestors $target
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); $expires = $now + 43200; $nonce = [Guid]::NewGuid().ToString('N')
    $body = "schema_version=2`nactive_host=$NativeHost`nsession_id=$NativeSession`ncontext_revision=$(Get-Revision)`nworktree_identity=$(Get-Identity)`nlauncher_path=$launcher`nlauncher_hash=$(Get-ShaFile $launcher)`nnonce=$nonce`nissued_epoch=$now`nexpires_epoch=$expires`n"
    $body += "receipt_hash=$(Get-Sha ($Utf8.GetBytes($body)))`n"
    $temporary = "$target.tmp.$PID"; [IO.File]::WriteAllText($temporary, $body, $Utf8); Move-Item -LiteralPath $temporary -Destination $target -Force
    $active = Get-ActiveReceipt $NativeHost; Assert-NoReparseAncestors $active
    if (Test-Path -LiteralPath $active) { $activeItem = Get-Item -LiteralPath $active -Force; if (($activeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'BLOCKED[invariant]: linked active host receipt rejected' } }
    $activeTemporary = "$active.tmp.$PID"; [IO.File]::Copy($target, $activeTemporary, $true); Move-Item -LiteralPath $activeTemporary -Destination $active -Force
    return $target
}

try {
    if ($Mode -eq 'hook') {
        $raw = [Console]::In.ReadToEnd(); $nativeSession = ''
        try { $json = $raw | ConvertFrom-Json; if ($json.session_id) { $nativeSession = [string]$json.session_id } elseif ($json.thread_id) { $nativeSession = [string]$json.thread_id } } catch {}
        Write-Receipt $Host $nativeSession | Out-Null; exit 0
    }
    if ($Mode -eq 'issue-test') {
        if ($env:FORGE_HOST_CONTEXT_TEST_MODE -ne '1') { throw 'BLOCKED[invariant]: test receipt issue mode is disabled' }; Assert-TestModeAllowed
        Write-Output (Write-Receipt $Host $SessionId); exit 0
    }
    $launcher = Get-Launcher
    if ($Mode -eq 'launch') {
        $receipt = Test-Receipt $Host $launcher
        $env:FORGE_NATIVE_HOST = $Host; $env:FORGE_NATIVE_SESSION_ID = $receipt.Session; $env:FORGE_HOST_CONTEXT_FILE = $receipt.Path; $env:FORGE_HOST_CONTEXT_LAUNCHER_HASH = $receipt.LauncherHash
        $boundArguments = if ($LaunchArgumentsJson) { @($LaunchArgumentsJson | ConvertFrom-Json) } else { @($LaunchArguments) }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher @boundArguments
        exit $LASTEXITCODE
    }
    if (-not $env:FORGE_NATIVE_HOST -or -not $env:FORGE_NATIVE_SESSION_ID -or -not $env:FORGE_HOST_CONTEXT_LAUNCHER_HASH) { throw 'BLOCKED[invariant]: protected launcher context is required' }
    $receipt = Test-Receipt $env:FORGE_NATIVE_HOST $launcher
    if ($env:FORGE_NATIVE_SESSION_ID -cne $receipt.Session -or $env:FORGE_HOST_CONTEXT_FILE -cne $receipt.Path -or $env:FORGE_HOST_CONTEXT_LAUNCHER_HASH -cne $receipt.LauncherHash) { throw 'BLOCKED[invariant]: launcher environment binding mismatch' }
    Write-Output $env:FORGE_NATIVE_HOST; exit 0
}
catch { [Console]::Error.WriteLine($_.Exception.Message); exit 2 }
