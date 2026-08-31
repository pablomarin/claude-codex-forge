param([Parameter(Mandatory=$true)][string]$Hook)
$ErrorActionPreference = "Stop"
if ($Hook -notmatch '^[A-Za-z0-9-]+\.ps1$') { throw "BLOCKED: unsafe hook target" }
$payloadText = [Console]::In.ReadToEnd()
$payload = $payloadText | ConvertFrom-Json
if (-not $payload.cwd -or -not [IO.Path]::IsPathRooted([string]$payload.cwd)) { throw "BLOCKED: Codex event has no trusted absolute cwd" }
$registeredRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$registeredCommon = (& git -C $registeredRoot rev-parse --git-common-dir).Trim()
if (-not [IO.Path]::IsPathRooted($registeredCommon)) { $registeredCommon = Join-Path $registeredRoot $registeredCommon }
$registeredCommon = (Resolve-Path $registeredCommon).Path
$eventRoot = (& git -C $payload.cwd rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) { throw "BLOCKED: event cwd is outside Git" }
$eventCommon = (& git -C $eventRoot rev-parse --git-common-dir).Trim()
if (-not [IO.Path]::IsPathRooted($eventCommon)) { $eventCommon = Join-Path $eventRoot $eventCommon }
$eventCommon = (Resolve-Path $eventCommon).Path
if ($eventCommon -cne $registeredCommon) { throw "BLOCKED: event Git common directory differs from registered repository" }
$target = Join-Path $eventRoot ".forge\hooks\$Hook"
if (-not (Test-Path $target -PathType Leaf) -or ((Get-Item $target).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "BLOCKED: canonical hook absent from event worktree" }
Push-Location $eventRoot
try {
    $payloadText | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $target
    exit $LASTEXITCODE
} finally { Pop-Location }
