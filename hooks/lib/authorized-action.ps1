param(
    [Parameter(Mandatory = $true)][ValidateSet('prepare', 'report')][string]$Mode,
    [string]$Adapter,
    [string]$System,
    [string]$Operation,
    [string]$Target,
    [string[]]$Arg = @(),
    [string]$ExpectedEffect,
    [string]$Output,
    [string]$Manifest,
    [ValidateSet('SUCCESS', 'FAILED', 'UNCERTAIN')][string]$Outcome
)

$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
function Get-Sha([string]$Text) { $sha = [Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($sha.ComputeHash($Utf8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() } }
function Get-Root { $value = (& git rev-parse --show-toplevel 2>$null); if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[authorization]: Git worktree required' }; return (Resolve-Path $value).Path }
function Get-Identity { $root = Get-Root; $common = (Resolve-Path (Join-Path $root (& git -C $root rev-parse --git-common-dir))).Path; return Get-Sha "$root|$common`n" }
function Get-Value([string]$Path, [string]$Key) { $rows = @(Get-Content -LiteralPath $Path | Where-Object { $_ -like "$Key=*" }); if ($rows.Count -ne 1) { throw "BLOCKED[authorization]: action key $Key must occur exactly once" }; return $rows[0].Substring($Key.Length + 1) }
function Assert-Scalar([string]$Name, [string]$Value) { if ($Value.Contains("`n") -or $Value.Contains("`r")) { throw "BLOCKED[authorization]: $Name contains a newline" } }
function Escape-Receipt([string]$Value) { return $Value.Replace('%', '%25').Replace('=', '%3D').Replace("`t", '%09').Replace("`r", '%0D').Replace("`n", '%0A') }
function Get-LocalOutput([string]$Path) {
    if (-not $Path) { throw 'BLOCKED[authorization]: local action output is required' }
    $root = Get-Root; $actions = Join-Path $root '.forge/local/actions'
    $ownedDirectory = $root
    foreach ($part in @('.forge', 'local', 'actions')) {
        $ownedDirectory = Join-Path $ownedDirectory $part
        if (Test-Path -LiteralPath $ownedDirectory) {
            $ownedItem = Get-Item -LiteralPath $ownedDirectory -Force
            if (-not $ownedItem.PSIsContainer -or (($ownedItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'BLOCKED[authorization]: linked action path rejected' }
        }
        else { New-Item -ItemType Directory -Path $ownedDirectory | Out-Null }
    }
    $full = [IO.Path]::GetFullPath($Path); $prefix = $actions.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'BLOCKED[authorization]: action record must stay under .forge/local/actions' }
    $relative = $full.Substring($prefix.Length)
    $relativeParent = Split-Path -Parent $relative; $cursor = $actions
    foreach ($part in @($relativeParent -split '[\\/]' | Where-Object { $_ })) {
        $cursor = Join-Path $cursor $part
        if (Test-Path -LiteralPath $cursor) { $item = Get-Item -LiteralPath $cursor -Force; if (-not $item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'BLOCKED[authorization]: linked action record rejected' } }
        else { New-Item -ItemType Directory -Path $cursor | Out-Null }
    }
    if (Test-Path -LiteralPath $full) { throw 'BLOCKED[authorization]: action output already exists or is linked' }
    return $full
}

try {
    if ($Mode -eq 'prepare') {
        foreach ($pair in @(@('adapter', $Adapter), @('system', $System), @('operation', $Operation), @('target', $Target), @('expected effect', $ExpectedEffect))) { Assert-Scalar $pair[0] $pair[1] }
        if (-not $ExpectedEffect) { throw 'BLOCKED[authorization]: expected effect is required' }
        $executable = ''; $rendered = ''
        switch ("$Adapter`:$System`:$Operation") {
            'gh-issue-close:github:close-issue' {
                if ($Arg.Count -ne 2 -or $Arg[0] -notmatch '^[A-Za-z0-9_.\/-]+$' -or $Arg[1] -notmatch '^\d+$') { throw 'BLOCKED[authorization]: invalid gh issue-close argv' }
                $executable = 'gh'; $rendered = "gh issue close $($Arg[1]) --repo $($Arg[0])"
            }
            'kubectl-rollout-restart:kubernetes:rollout-restart' {
                if ($Arg.Count -ne 2 -or $Arg[0] -notmatch '^[A-Za-z0-9_.-]+$' -or $Arg[1] -notmatch '^[A-Za-z0-9_.-]+$') { throw 'BLOCKED[authorization]: invalid kubectl rollout argv' }
                $executable = 'kubectl'; $rendered = "kubectl -n $($Arg[0]) rollout restart deployment/$($Arg[1])"
            }
            default { throw 'BLOCKED[authorization]: adapter is not allowlisted; MCP-only mutation remains manual and blocked' }
        }
        $Output = Get-LocalOutput $Output
        $nonce = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + "-$PID-" + [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $actionHash = Get-Sha "$Adapter`n$System`n$Operation`n$Target`n$rendered`n$ExpectedEffect`n"
        $body = "schema_version=1`nstatus=PENDING_HUMAN_EXECUTION`nnonce=$nonce`nworktree_identity=$(Get-Identity)`nadapter=$Adapter`nsystem=$System`noperation=$Operation`ntarget=$(Escape-Receipt $Target)`naction_hash=$actionHash`nexpected_effect=$(Escape-Receipt $ExpectedEffect)`ncommand_executable=$executable`ncommand_rendered=$(Escape-Receipt $rendered)`ncreated_at=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))`n"
        [IO.File]::WriteAllText($Output, $body, $Utf8)
        Write-Output "PENDING: developer must execute this exact command in their own terminal; Forge will not run it:`n$rendered"
        exit 0
    }
    if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) { throw 'BLOCKED[authorization]: regular pending manifest required' }
    $manifestItem = Get-Item -LiteralPath $Manifest -Force
    if (($manifestItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or (Get-Value $Manifest 'status') -ne 'PENDING_HUMAN_EXECUTION') { throw 'BLOCKED[authorization]: valid pending manifest required' }
    if ((Get-Value $Manifest 'worktree_identity') -cne (Get-Identity)) { throw 'BLOCKED[authorization]: pending manifest belongs to another worktree' }
    $Output = Get-LocalOutput $Output
    $body = "schema_version=1`nstatus=REPORTED`nnonce=$(Get-Value $Manifest 'nonce')`nworktree_identity=$(Get-Identity)`naction_hash=$(Get-Value $Manifest 'action_hash')`nreported_outcome=$Outcome`nreported_at=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))`nverification=UNVERIFIED`nnext_step=independent-investigation-repro`n"
    [IO.File]::WriteAllText($Output, $body, $Utf8)
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
}
