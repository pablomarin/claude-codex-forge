param(
    [string]$Project,
    [string]$ObjectiveHash,
    [string]$Nonce,
    [int]$Ceiling
)
$ErrorActionPreference = "Stop"
$TrustedWriter = '__FORGE_WRITER_PATH__'
$AuthorizationRoot = '__FORGE_AUTHORIZATION_ROOT__'
$WriterRevision = '__FORGE_WRITER_REVISION__'
$Utf8NoBom = New-Object Text.UTF8Encoding($false)

function Get-ForgeFileHashValue([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
}
$actual = (Resolve-Path $MyInvocation.MyCommand.Path).Path
if ($actual -cne $TrustedWriter -or ((Get-Item -LiteralPath $TrustedWriter -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "BLOCKED: copied, symlinked, or untrusted goal authorization writer" }
$seal = "$TrustedWriter.sha256"
if (-not (Test-Path $seal -PathType Leaf) -or ((Get-Item -LiteralPath $seal -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or ([IO.File]::ReadAllText($seal).Trim() -cne (Get-ForgeFileHashValue $TrustedWriter))) { throw "BLOCKED: authorization writer revision seal mismatch" }
if ($WriterRevision -notmatch '^[0-9a-f]{64}$') { throw "BLOCKED: unsealed writer source revision" }
if (-not (Test-Path $Project -PathType Container)) { throw "BLOCKED: project directory missing" }
if ($ObjectiveHash -notmatch '^[A-Za-z0-9._-]+$') { throw "BLOCKED: invalid objective hash" }
if ($Nonce -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') { throw "BLOCKED: nonce must be UUIDv4" }
if ($Ceiling -lt 1) { throw "BLOCKED: ceiling must be positive" }
$projectRoot = (& git -C $Project rev-parse --show-toplevel | Select-Object -First 1)
if (-not $projectRoot) { throw "BLOCKED: project is not a Git worktree" }
$projectRoot = (Resolve-Path $projectRoot).Path
$common = (& git -C $projectRoot rev-parse --git-common-dir | Select-Object -First 1)
if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $projectRoot $common }
$common = (Resolve-Path $common).Path
$sha = [Security.Cryptography.SHA256]::Create()
try { $projectId = ([BitConverter]::ToString($sha.ComputeHash($Utf8NoBom.GetBytes("$projectRoot`n$common`n")))).Replace("-", "").ToLowerInvariant() }
finally { $sha.Dispose() }
if (-not (Test-Path $AuthorizationRoot -PathType Container) -or ((Get-Item -LiteralPath $AuthorizationRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "BLOCKED: sealed authorization root unavailable or aliased" }
$dir = Join-Path $AuthorizationRoot $projectId
if ((Test-Path $dir) -and ((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "BLOCKED: aliased authorization project root" }
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$destination = Join-Path $dir "$Nonce.auth"
$body = @(
    "format=forge-goal-authorization-v1", "project_root=$projectRoot", "git_common_dir=$common",
    "project_id=$projectId", "objective_hash=$ObjectiveHash", "nonce=$Nonce", "ceiling=$Ceiling",
    "approval_channel=physical-operator-action", "issue_id=$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))-$PID", "writer_revision=$WriterRevision"
) -join "`n"
$bytes = $Utf8NoBom.GetBytes($body + "`n")
$stream = New-Object IO.FileStream($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
Write-Host "AUTHORIZED: $destination"
