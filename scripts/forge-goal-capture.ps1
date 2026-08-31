param(
    [string]$Project,
    [string]$SessionId,
    [string]$Transcript,
    [string]$Result,
    [switch]$ValidateBinding
)
$ErrorActionPreference = "Stop"
$TrustedCapture = '__FORGE_CAPTURE_PATH__'
$CaptureRoot = '__FORGE_CAPTURE_ROOT__'
$CodexIdentity = '__FORGE_CODEX_IDENTITY__'
$CaptureRevision = '__FORGE_CAPTURE_REVISION__'
$WriterRevision = '__FORGE_WRITER_REVISION__'
$Utf8NoBom = New-Object Text.UTF8Encoding($false)
function Get-ForgeCaptureHash([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-ForgeCaptureTextHash([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Utf8NoBom.GetBytes($Text)))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-ForgeCaptureCapability([string]$Path) {
    $rootHelp = (& $Path --help 2>&1) -join "`n"
    $execHelp = (& $Path exec --help 2>&1) -join "`n"
    $combined = $rootHelp + $execHelp; $lines = New-Object System.Collections.Generic.List[string]; $lines.Add("forge-codex-capability-v1")
    foreach ($flag in @("--ignore-user-config", "--ignore-rules", "--ephemeral", "--sandbox", "--add-dir")) { $lines.Add("$flag=" + $(if ($combined -match [regex]::Escape($flag)) { "present" } else { "absent" })) }
    return Get-ForgeCaptureTextHash (($lines -join "`n") + "`n")
}
function Test-ForgeUnaliasedFile([string]$Path) {
    return ((Test-Path $Path -PathType Leaf) -and -not ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint))
}
function Get-ForgeCaptureFields([string]$Path) {
    $fields = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) { $index = $line.IndexOf('='); if ($index -gt 0) { $fields[$line.Substring(0,$index)] = $line.Substring($index + 1) } }
    return $fields
}
function Get-ForgeBoundCodexIdentity {
    if (-not (Test-ForgeUnaliasedFile $CodexIdentity) -or -not (Test-ForgeUnaliasedFile "$CodexIdentity.sha256")) { throw "BLOCKED: setup-recorded Codex identity is absent or aliased" }
    $identityHash = Get-ForgeCaptureHash $CodexIdentity
    if ([IO.File]::ReadAllText("$CodexIdentity.sha256").Trim() -cne $identityHash) { throw "BLOCKED: Codex identity seal mismatch" }
    $fields = Get-ForgeCaptureFields $CodexIdentity
    foreach ($pair in @(@("format","forge-codex-identity-v1"),@("engine","codex"),@("identity_class","operator-setup"),@("status","QUALIFIED"),@("capture_revision",$CaptureRevision),@("writer_revision",$WriterRevision))) {
        if ($fields[$pair[0]] -cne $pair[1]) { throw "BLOCKED: Codex identity is fixture-only, stale, or incomplete" }
    }
    $invocation = $fields["invocation_path"]; $binary = $fields["binary_path"]
    if (-not [IO.Path]::IsPathRooted($invocation) -or -not [IO.Path]::IsPathRooted($binary) -or -not (Test-Path $invocation -PathType Leaf) -or -not (Test-ForgeUnaliasedFile $binary)) { throw "BLOCKED: Codex identity paths are not physical absolute files" }
    if ((Resolve-Path $invocation).Path -cne $binary -or (Resolve-Path $binary).Path -cne $binary) { throw "BLOCKED: Codex binary binding changed" }
    if ((Get-ForgeCaptureHash $binary) -cne $fields["binary_sha256"]) { throw "BLOCKED: Codex binary hash changed" }
    $actualVersion = ((& $binary --version 2>$null) | Select-Object -First 1)
    if ($actualVersion -cne $fields["version"] -or (Get-ForgeCaptureCapability $binary) -cne $fields["capability_revision"]) { throw "BLOCKED: Codex version/capability binding changed" }
    return [pscustomobject]@{ Fields=$fields; Hash=$identityHash }
}

$actual = (Resolve-Path $MyInvocation.MyCommand.Path).Path
if ($actual -cne $TrustedCapture -or -not (Test-ForgeUnaliasedFile $TrustedCapture)) { throw "BLOCKED: copied, symlinked, or untrusted goal capture helper" }
$seal = "$TrustedCapture.sha256"
if (-not (Test-ForgeUnaliasedFile $seal) -or ([IO.File]::ReadAllText($seal).Trim() -cne (Get-ForgeCaptureHash $TrustedCapture))) { throw "BLOCKED: capture helper revision seal mismatch" }
if (-not (Test-Path $Project -PathType Container)) { throw "BLOCKED: project must be an existing directory" }
$projectRoot = (& git -C $Project rev-parse --show-toplevel | Select-Object -First 1); if ($LASTEXITCODE -ne 0) { throw "BLOCKED: project is not a Git worktree" }
$projectRoot = (Resolve-Path $projectRoot).Path
$common = (& git -C $projectRoot rev-parse --git-common-dir | Select-Object -First 1); if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $projectRoot $common }; $common = (Resolve-Path $common).Path
$captureRootPhysical = (Resolve-Path $CaptureRoot).Path
if ($captureRootPhysical.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $captureRootPhysical.StartsWith($common + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "BLOCKED: capture root is inside a workspace root" }
$identity = Get-ForgeBoundCodexIdentity
$projectId = Get-ForgeCaptureTextHash "$projectRoot`n$common`n"
if ($ValidateBinding) { Write-Host "STRUCTURALLY_ELIGIBLE: project_id=$projectId identity_sha256=$($identity.Hash); authenticated TUI evidence not captured"; exit 0 }

if ($SessionId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') { throw "BLOCKED: session id must be UUIDv4" }
if (-not (Test-ForgeUnaliasedFile $Transcript) -or -not (Test-ForgeUnaliasedFile $Result)) { throw "BLOCKED: transcript/result must be unaliased files" }
$fields = $identity.Fields; $cliPath = $fields["binary_path"]
$transcriptLines = @([IO.File]::ReadAllLines($Transcript))
foreach ($exact in @("capture_channel=operator-codex-tui", "identity_sha256=$($identity.Hash)", "cli_path=$cliPath", "cli_sha256=$($fields['binary_sha256'])", "cli_version=$($fields['version'])", "capability_revision=$($fields['capability_revision'])", "session_id=$SessionId", "project_root=$projectRoot", "command=/goal", "/goal activated", "status captured", "pause captured", "checkpoint resumed", "FORGE_GOAL_BUDGET_EXHAUSTED", "FORGE_GOAL_STUCK_WARNING")) { if ($transcriptLines -cnotcontains $exact) { throw "BLOCKED: TUI transcript missing exact binding: $exact" } }
$resultLines = @([IO.File]::ReadAllLines($Result))
foreach ($exact in @("native_activation=PASS", "checkpoint_resume=PASS", "budget_oracle=PASS", "stuck_oracle=PASS")) { if ($resultLines -cnotcontains $exact) { throw "BLOCKED: TUI result missing $exact" } }
$parent = Join-Path $CaptureRoot $projectId; New-Item -ItemType Directory -Path $parent -Force | Out-Null
$destination = Join-Path $parent $SessionId; $lock = "$destination.lock"
$lockStream = New-Object IO.FileStream($lock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    if (Test-Path $destination) { throw "BLOCKED: capture session already exists; replay refused" }
    New-Item -ItemType Directory -Path $destination | Out-Null
    Copy-Item -LiteralPath $Transcript -Destination (Join-Path $destination "transcript.txt")
    Copy-Item -LiteralPath $Result -Destination (Join-Path $destination "result.txt")
    $storedTranscript = Join-Path $destination "transcript.txt"; $storedResult = Join-Path $destination "result.txt"; $receipt = Join-Path $destination "capture.receipt"
    $lines = @(
        "format=forge-codex-goal-tui-capture-v3", "engine=codex", "command=/goal", "capture_channel=physical-operator-action", "fixture_only=false",
        "project_root=$projectRoot", "git_common_dir=$common", "project_id=$projectId", "identity_path=$CodexIdentity", "identity_sha256=$($identity.Hash)",
        "cli_path=$cliPath", "cli_sha256=$($fields['binary_sha256'])", "cli_version=$($fields['version'])", "capability_revision=$($fields['capability_revision'])", "session_id=$SessionId",
        "transcript_path=$storedTranscript", "transcript_sha256=$(Get-ForgeCaptureHash $storedTranscript)", "result_path=$storedResult", "result_sha256=$(Get-ForgeCaptureHash $storedResult)",
        "capture_revision=$CaptureRevision", "writer_revision=$WriterRevision"
    )
    [IO.File]::WriteAllLines($receipt, $lines, $Utf8NoBom)
} finally { $lockStream.Dispose(); Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue }
Write-Host "CAPTURED: $receipt"
