param(
    [ValidateSet('write', 'check')][string]$Mode,
    [string]$Kind,
    [string]$Candidate,
    [string]$Command,
    [string]$Profile,
    [string]$Report,
    [ValidateSet('PASS', 'FAIL', 'BLOCKED')][string]$Result,
    [int]$ExitStatus = -1,
    [string]$Output,
    [string]$StartedAt,
    [string]$EndedAt,
    [string]$State
)

# PowerShell 5.1 mirror of verification-receipt.sh. Receipts are line-oriented
# key/value data and are parsed strictly; no receipt is ever dot-sourced.
$ErrorActionPreference = 'Stop'
$Utf8 = New-Object Text.UTF8Encoding($false)

function Get-ShaBytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-ShaText([string]$Text) { return Get-ShaBytes ($Utf8.GetBytes($Text)) }
function Get-ShaFile([string]$Path) { return Get-ShaBytes ([IO.File]::ReadAllBytes($Path)) }
function Get-Kv([string]$Path, [string]$Key) {
    $values = New-Object Collections.Generic.List[string]
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $position = $line.IndexOf('=')
        if ($position -gt 0 -and $line.Substring(0, $position) -ceq $Key) { $values.Add($line.Substring($position + 1)) }
    }
    if ($values.Count -ne 1) { throw "BLOCKED[evidence]: $Key must occur exactly once in $Path" }
    return $values[0]
}
function Get-StateValue([string]$Path, [string]$Key) {
    $values = New-Object Collections.Generic.List[string]
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $parts = $line.Split('|')
        if ($parts.Count -ge 4 -and $parts[1].Trim() -ceq $Key) { $values.Add($parts[2].Trim()) }
    }
    if ($values.Count -ne 1) { throw "BLOCKED[evidence]: state linkage $Key must occur exactly once" }
    return $values[0]
}
function Get-OwnedPath([string]$Root, [string]$Raw, [bool]$MustExist) {
    if (-not $Raw -or $Raw.Contains("`n") -or $Raw.Contains("`r")) { throw 'BLOCKED[evidence]: invalid Forge-local path' }
    $path = if ([IO.Path]::IsPathRooted($Raw)) { [IO.Path]::GetFullPath($Raw) } else { [IO.Path]::GetFullPath((Join-Path $Root $Raw)) }
    $prefix = [IO.Path]::GetFullPath((Join-Path $Root '.forge\local')).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'BLOCKED[evidence]: evidence path escapes .forge/local' }
    if ($MustExist) {
        $item = Get-Item -LiteralPath $path -Force
        if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'BLOCKED[evidence]: evidence must be a no-follow regular file' }
    }
    else {
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        $existing = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($existing -and (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'BLOCKED[evidence]: linked output rejected' }
    }
    return $path
}
function Test-Fresh([string]$Timestamp) {
    try { $parsed = [DateTimeOffset]::ParseExact($Timestamp, 'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal) }
    catch { return $false }
    $age = ([DateTimeOffset]::UtcNow - $parsed.ToUniversalTime()).TotalSeconds
    $maximum = 86400
    if ($env:FORGE_RECEIPT_MAX_AGE_SECONDS -match '^[0-9]+$') { $maximum = [int]$env:FORGE_RECEIPT_MAX_AGE_SECONDS }
    return $age -ge -300 -and $age -le $maximum
}
function Test-CurrentCandidate([string]$Root, [string]$Receipt) {
    if ((Get-Kv $Receipt 'schema_version') -cne '2' -or (Get-Kv $Receipt 'candidate_state') -cne 'staged-clean') { return $false }
    $fingerprint = Join-Path $PSScriptRoot 'candidate-fingerprint.ps1'
    if (-not (Test-Path -LiteralPath $fingerprint)) { $fingerprint = Join-Path $Root 'hooks\lib\candidate-fingerprint.ps1' }
    if (-not (Test-Path -LiteralPath $fingerprint)) { return $false }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('forge-current-' + [Guid]::NewGuid().ToString('N'))
    try {
        & $fingerprint -Mode freeze -Artifact 'git:working-tree' -WorkflowBaseSha (Get-Kv $Receipt 'workflow_base_sha') -WorkflowBaseRef (Get-Kv $Receipt 'workflow_base_ref') -Output $temporary
        if ($LASTEXITCODE -ne 0) { return $false }
        foreach ($key in @('candidate_id', 'worktree_identity', 'git_head', 'workflow_base_sha', 'index_tree', 'candidate_state')) {
            if ((Get-Kv $Receipt $key) -cne (Get-Kv $temporary $key)) { return $false }
        }
        return $true
    }
    catch { return $false }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}
function Test-Review([string]$Root, [string]$Receipt, [string]$Role, [string]$CandidateReceipt) {
    try {
        foreach ($key in @('schema_version','invocation_id','timestamp','main_host','requested_engine','actual_engine','fallback','fallback_reason','role','profile','fresh_process','artifact_kind','artifact_hash','worktree_identity','git_head','workflow_base_sha','output_path','output_hash','process_exit_status','semantic_verdict','max_severity','findings_digest','result_schema_version','blocked_class')) { $null = Get-Kv $Receipt $key }
        if ((Get-Kv $Receipt 'schema_version') -cne '1' -or (Get-Kv $Receipt 'role') -cne $Role -or (Get-Kv $Receipt 'profile') -cne 'review' -or (Get-Kv $Receipt 'fresh_process') -cne 'true') { return $false }
        if (-not (Test-Fresh (Get-Kv $Receipt 'timestamp'))) { return $false }
        if ((Get-Kv $Receipt 'artifact_kind') -cne 'git-working-tree' -or (Get-Kv $Receipt 'artifact_hash') -cne (Get-Kv $CandidateReceipt 'candidate_id')) { return $false }
        foreach ($key in @('worktree_identity','git_head','workflow_base_sha')) { if ((Get-Kv $Receipt $key) -cne (Get-Kv $CandidateReceipt $key)) { return $false } }
        if ((Get-Kv $Receipt 'process_exit_status') -cne '0' -or (Get-Kv $Receipt 'semantic_verdict') -cne 'CLEAN' -or (Get-Kv $Receipt 'blocked_class') -cne 'none') { return $false }
        if (@('NONE','P3') -cnotcontains (Get-Kv $Receipt 'max_severity')) { return $false }
        $digest = Get-Kv $Receipt 'findings_digest'; if ($digest -notmatch '^[0-9a-fA-F]{64}$') { return $false }
        $report = Get-OwnedPath $Root (Get-Kv $Receipt 'output_path') $true
        if ((Get-ShaFile $report) -cne (Get-Kv $Receipt 'output_hash')) { return $false }
        $requested = Get-Kv $Receipt 'requested_engine'; $actual = Get-Kv $Receipt 'actual_engine'; $fallback = Get-Kv $Receipt 'fallback'; $reason = Get-Kv $Receipt 'fallback_reason'
        if (@('auto','claude','codex') -cnotcontains $requested -or @('claude','codex') -cnotcontains $actual) { return $false }
        if ($fallback -ceq 'false') { if ($reason -cne 'none' -or ($requested -cne 'auto' -and $requested -cne $actual)) { return $false } }
        elseif ($fallback -ceq 'true') { if (-not $reason -or $reason -ceq 'none') { return $false } }
        else { return $false }
        return $true
    }
    catch { return $false }
}
function Test-Verifier([string]$Root, [string]$Receipt, [string]$ReceiptKind, [string]$CandidateReceipt) {
    try {
        foreach ($key in @('schema_version','receipt_kind','invocation_id','started_at','ended_at','candidate_id','worktree_identity','git_head','workflow_base_sha','index_tree','command_hash','profile','exit_status','report_path','report_hash','result')) { $null = Get-Kv $Receipt $key }
        if ((Get-Kv $Receipt 'schema_version') -cne '2' -or (Get-Kv $Receipt 'receipt_kind') -cne $ReceiptKind -or -not (Test-Fresh (Get-Kv $Receipt 'ended_at'))) { return $false }
        if ((Get-Kv $Receipt 'exit_status') -cne '0' -or (Get-Kv $Receipt 'result') -cne 'PASS') { return $false }
        foreach ($key in @('candidate_id','worktree_identity','git_head','workflow_base_sha','index_tree')) { if ((Get-Kv $Receipt $key) -cne (Get-Kv $CandidateReceipt $key)) { return $false } }
        $report = Get-OwnedPath $Root (Get-Kv $Receipt 'report_path') $true
        return (Get-ShaFile $report) -ceq (Get-Kv $Receipt 'report_hash')
    }
    catch { return $false }
}

function Invoke-VerificationReceipt {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('write', 'check')][string]$ReceiptMode,
        [string]$ReceiptKind, [string]$CandidatePath, [string]$CommandText,
        [string]$ProfileName, [string]$ReportPath, [string]$ReceiptResult,
        [int]$ReceiptExitStatus = -1, [string]$OutputPath,
        [string]$ReceiptStartedAt, [string]$ReceiptEndedAt, [string]$StatePath
    )
    $response = [ordered]@{ Status = 2; Lines = @(); Error = '' }
    $root = (& git rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    if (-not $root) { $response.Error = 'BLOCKED[evidence]: Git worktree required'; return [pscustomobject]$response }
    $root = (Resolve-Path $root).Path

    if ($ReceiptMode -eq 'write') {
        if (@('verify-app','e2e') -cnotcontains $ReceiptKind -or @('PASS','FAIL','BLOCKED') -cnotcontains $ReceiptResult -or $ReceiptExitStatus -lt 0) {
            $response.Error = 'BLOCKED[evidence]: invalid verifier receipt arguments'; return [pscustomobject]$response
        }
        try {
            $candidateFile = Get-OwnedPath $root $CandidatePath $true
            if (-not (Test-CurrentCandidate $root $candidateFile)) { throw 'candidate is not current staged-clean identity' }
            $reportFile = Get-OwnedPath $root $ReportPath $true; $outputFile = Get-OwnedPath $root $OutputPath $false
            if (-not $ReceiptStartedAt) { $ReceiptStartedAt = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
            if (-not $ReceiptEndedAt) { $ReceiptEndedAt = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
            if (-not (Test-Fresh $ReceiptStartedAt) -or -not (Test-Fresh $ReceiptEndedAt)) { throw 'verifier timestamps are stale or invalid' }
            $invocation = Get-ShaText "$ReceiptKind|$ReceiptStartedAt|$PID|$CommandText|$(Get-Kv $candidateFile 'candidate_id')`n"
            $body = "schema_version=2`nreceipt_kind=$ReceiptKind`ninvocation_id=$invocation`nstarted_at=$ReceiptStartedAt`nended_at=$ReceiptEndedAt`n"
            foreach ($key in @('candidate_id','worktree_identity','git_head','workflow_base_sha','index_tree')) { $body += "$key=$(Get-Kv $candidateFile $key)`n" }
            $body += "command_hash=$(Get-ShaText $CommandText)`nprofile=$ProfileName`nexit_status=$ReceiptExitStatus`nreport_path=$reportFile`nreport_hash=$(Get-ShaFile $reportFile)`nresult=$ReceiptResult`n"
            [IO.File]::WriteAllText("$outputFile.tmp.$PID", $body, $Utf8)
            Move-Item -LiteralPath "$outputFile.tmp.$PID" -Destination $outputFile -Force
            $response.Status = 0; $response.Lines = @("RECEIPT:$outputFile")
        }
        catch { $response.Error = "BLOCKED[evidence]: $($_.Exception.Message)" }
        return [pscustomobject]$response
    }

    try {
        if (-not $StatePath) { $StatePath = '.forge\local\state.md' }
        $stateFile = if ([IO.Path]::IsPathRooted($StatePath)) { [IO.Path]::GetFullPath($StatePath) } else { [IO.Path]::GetFullPath((Join-Path $root $StatePath)) }
        if ((Get-Content -LiteralPath $stateFile -TotalCount 1) -cne '<!-- forge:state-schema v6 -->') { throw 'receipt-v2 requires canonical v6 state' }
        $candidateFile = Get-OwnedPath $root (Get-StateValue $stateFile 'Candidate receipt') $true
        $specFile = Get-OwnedPath $root (Get-StateValue $stateFile 'Spec review receipt') $true
        $qualityFile = Get-OwnedPath $root (Get-StateValue $stateFile 'Quality review receipt') $true
        $appFile = Get-OwnedPath $root (Get-StateValue $stateFile 'Verify app receipt') $true
        $e2eFile = Get-OwnedPath $root (Get-StateValue $stateFile 'E2E receipt') $true
        $iteration = Get-StateValue $stateFile 'Review iteration'; if ($iteration -notmatch '^[0-9]+$') { throw 'Review iteration must be numeric' }
        $candidateOk = Test-CurrentCandidate $root $candidateFile
        $reviewsOk = $false; $appOk = $false; $e2eOk = $false
        if ($candidateOk -and (Test-Review $root $specFile 'code-spec' $candidateFile) -and (Test-Review $root $qualityFile 'code-quality' $candidateFile)) {
            $reviewsOk = (Get-Kv $specFile 'invocation_id') -cne (Get-Kv $qualityFile 'invocation_id')
        }
        if ($candidateOk) { $appOk = Test-Verifier $root $appFile 'verify-app' $candidateFile; $e2eOk = Test-Verifier $root $e2eFile 'e2e' $candidateFile }
        $ship = $candidateOk -and $reviewsOk -and $appOk -and $e2eOk
        $response.Lines = @(
            "CANDIDATE_VALID:$($candidateOk.ToString().ToLowerInvariant())",
            "REVIEWS_VALID:$($reviewsOk.ToString().ToLowerInvariant())",
            "VERIFY_APP_VALID:$($appOk.ToString().ToLowerInvariant())",
            "E2E_VALID:$($e2eOk.ToString().ToLowerInvariant())",
            "REVIEW_ITERATION:$iteration",
            "CANDIDATE_ID:$(Get-Kv $candidateFile 'candidate_id')",
            "SHIP_READY:$($ship.ToString().ToLowerInvariant())"
        )
        if ($ship) { $response.Status = 0 }
    }
    catch { $response.Error = "BLOCKED[evidence]: $($_.Exception.Message)" }
    return [pscustomobject]$response
}

# Dot-source consumers call Invoke-VerificationReceipt directly. Only the
# standalone entrypoint writes streams or exits the host process.
if ($MyInvocation.InvocationName -ne '.') {
    $receiptResponse = Invoke-VerificationReceipt -ReceiptMode $Mode -ReceiptKind $Kind -CandidatePath $Candidate -CommandText $Command -ProfileName $Profile -ReportPath $Report -ReceiptResult $Result -ReceiptExitStatus $ExitStatus -OutputPath $Output -ReceiptStartedAt $StartedAt -ReceiptEndedAt $EndedAt -StatePath $State
    foreach ($line in $receiptResponse.Lines) { Write-Output $line }
    if ($receiptResponse.Error) { [Console]::Error.WriteLine($receiptResponse.Error) }
    exit $receiptResponse.Status
}
