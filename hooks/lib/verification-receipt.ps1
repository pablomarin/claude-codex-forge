param(
    [ValidateSet('write', 'check', 'close-docs', 'record-review-waiver', 'check-review-waiver', 'record-workflow-waiver', 'check-workflow-waiver')][string]$Mode,
    [string]$Kind,
    [string]$Candidate,
    [string]$Command,
    [string]$Profile,
    [string]$Report,
    [ValidateSet('PASS', 'FAIL', 'BLOCKED', 'PARTIAL', 'N/A')][string]$Result,
    [int]$ExitStatus = -1,
    [string]$Output,
    [string]$StartedAt,
    [string]$EndedAt,
    [string]$State,
    [string]$PreviousCandidate,
    [string]$Decision,
    [string]$Provenance,
    [string]$Skip,
    [string]$Boundary = 'ship'
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
function Get-ReportVerdict([string]$Path, [string]$ReceiptKind) {
    $first = ([IO.File]::ReadLines($Path) | Select-Object -First 1).TrimEnd("`r")
    if ($first -notmatch '^VERDICT: ([A-Z/]+)$') { throw 'report must begin with a canonical VERDICT header' }
    $verdict = $matches[1]
    if ($ReceiptKind -eq 'verify-app' -and $verdict -notin @('PASS','FAIL','BLOCKED')) { throw 'invalid verify-app report verdict' }
    if ($ReceiptKind -eq 'e2e' -and $verdict -notin @('PASS','FAIL','PARTIAL','N/A')) { throw 'invalid E2E report verdict' }
    return $verdict
}
function Get-E2eNaReason([string]$Path) {
    $lines = [IO.File]::ReadAllLines($Path)
    if ($lines.Count -lt 3 -or $lines[2].TrimEnd("`r") -notmatch '^N/A_REASON:\s*(\S(?:.*\S)?)\s*$') {
        throw 'E2E N/A report requires a concrete line-3 N/A_REASON'
    }
    return $matches[1]
}
function Test-CurrentCandidate([string]$Root, [string]$Receipt) {
    if ((Get-Kv $Receipt 'schema_version') -cne '2' -or (Get-Kv $Receipt 'candidate_state') -cne 'staged-clean') { return $false }
    $fingerprint = Join-Path $PSScriptRoot 'candidate-fingerprint.ps1'
    if (-not (Test-Path -LiteralPath $fingerprint)) { $fingerprint = Join-Path $Root 'hooks\lib\candidate-fingerprint.ps1' }
    if (-not (Test-Path -LiteralPath $fingerprint)) { return $false }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('forge-current-' + [Guid]::NewGuid().ToString('N'))
    try {
        & $fingerprint -Mode identity -Artifact 'git:working-tree' -WorkflowBaseSha (Get-Kv $Receipt 'workflow_base_sha') -WorkflowBaseRef (Get-Kv $Receipt 'workflow_base_ref') -Output $temporary
        if ($LASTEXITCODE -ne 0) { return $false }
        foreach ($key in @('candidate_id', 'worktree_identity', 'git_head', 'workflow_base_sha', 'index_tree', 'candidate_state')) {
            if ((Get-Kv $Receipt $key) -cne (Get-Kv $temporary $key)) { return $false }
        }
        return $true
    }
    catch { return $false }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}
function Test-PromotedCandidate([string]$Root, [string]$Receipt, [string]$Promotion) {
    $temporaryFingerprint = Join-Path ([IO.Path]::GetTempPath()) ('forge-promoted-' + [Guid]::NewGuid().ToString('N'))
    try {
        foreach ($key in @('schema_version','old_candidate_id','old_head','temporary_commit','new_branch_commit','new_branch_tree','worktree_identity','post_commit_status','post_commit_dirty')) { $null = Get-Kv $Promotion $key }
        if ((Get-Kv $Promotion 'schema_version') -cne '2' -or (Get-Kv $Receipt 'schema_version') -cne '2' -or (Get-Kv $Receipt 'candidate_state') -cne 'staged-clean') { return $false }
        $oldId = Get-Kv $Receipt 'candidate_id'
        $oldHead = Get-Kv $Receipt 'git_head'
        $base = Get-Kv $Receipt 'workflow_base_sha'
        $baseRef = Get-Kv $Receipt 'workflow_base_ref'
        $tree = Get-Kv $Receipt 'index_tree'
        $worktree = Get-Kv $Receipt 'worktree_identity'
        if ($oldId -cne (Get-ShaText "$base`n$oldHead`n$tree`n$worktree`n")) { return $false }
        if ((Get-Kv $Promotion 'old_candidate_id') -cne $oldId -or (Get-Kv $Promotion 'old_head') -cne $oldHead -or (Get-Kv $Promotion 'worktree_identity') -cne $worktree) { return $false }
        $currentHead = [string](& git -C $Root rev-parse HEAD 2>$null)
        $temporaryCommit = Get-Kv $Promotion 'temporary_commit'
        $branchCommit = Get-Kv $Promotion 'new_branch_commit'
        if ($temporaryCommit -cne $branchCommit -or $branchCommit -cne $currentHead.Trim()) { return $false }
        if ((Get-Kv $Promotion 'new_branch_tree') -cne $tree -or ([string](& git -C $Root rev-parse "$currentHead^{tree}" 2>$null)).Trim() -cne $tree) { return $false }
        $parentLine = ([string](& git -C $Root rev-list --parents -n 1 $currentHead 2>$null)).Trim()
        $parentFields = @($parentLine -split '\s+')
        if ($parentFields.Count -ne 2 -or $parentFields[1] -cne $oldHead) { return $false }
        if (@('pass','not-run') -cnotcontains (Get-Kv $Promotion 'post_commit_status') -or (Get-Kv $Promotion 'post_commit_dirty') -cne 'false') { return $false }
        $fingerprint = Join-Path $PSScriptRoot 'candidate-fingerprint.ps1'
        if (-not (Test-Path -LiteralPath $fingerprint)) { $fingerprint = Join-Path $Root 'hooks\lib\candidate-fingerprint.ps1' }
        if (-not (Test-Path -LiteralPath $fingerprint)) { return $false }
        & $fingerprint -Mode identity -Artifact 'git:working-tree' -WorkflowBaseSha $base -WorkflowBaseRef $baseRef -Output $temporaryFingerprint
        if ($LASTEXITCODE -ne 0) { return $false }
        if ((Get-Kv $temporaryFingerprint 'git_head') -cne $currentHead) { return $false }
        foreach ($key in @('worktree_identity','workflow_base_sha','index_tree','candidate_state')) {
            if ((Get-Kv $Receipt $key) -cne (Get-Kv $temporaryFingerprint $key)) { return $false }
        }
        return $true
    }
    catch { return $false }
    finally { Remove-Item -LiteralPath $temporaryFingerprint -Force -ErrorAction SilentlyContinue }
}
function Test-Review([string]$Root, [string]$Receipt, [string]$Role, [string]$CandidateReceipt, [string]$Iteration) {
    try {
        foreach ($key in @('schema_version','invocation_id','timestamp','main_host','requested_engine','actual_engine','fallback','fallback_reason','role','profile','review_iteration','fresh_process','artifact_kind','artifact_hash','worktree_identity','git_head','workflow_base_sha','output_path','output_hash','process_exit_status','semantic_verdict','max_severity','findings_digest','result_schema_version','blocked_class')) { $null = Get-Kv $Receipt $key }
        if ((Get-Kv $Receipt 'schema_version') -cne '1' -or (Get-Kv $Receipt 'role') -cne $Role -or (Get-Kv $Receipt 'profile') -cne 'review' -or (Get-Kv $Receipt 'review_iteration') -cne $Iteration -or (Get-Kv $Receipt 'fresh_process') -cne 'true') { return $false }
        if (-not (Test-Fresh (Get-Kv $Receipt 'timestamp'))) { return $false }
        if ((Get-Kv $Receipt 'artifact_kind') -cne 'git-working-tree' -or (Get-Kv $Receipt 'artifact_hash') -cne (Get-Kv $CandidateReceipt 'candidate_id')) { return $false }
        foreach ($key in @('worktree_identity','git_head','workflow_base_sha')) { if ((Get-Kv $Receipt $key) -cne (Get-Kv $CandidateReceipt $key)) { return $false } }
        if ((Get-Kv $Receipt 'process_exit_status') -cne '0' -or (Get-Kv $Receipt 'blocked_class') -cne 'none') { return $false }
        $verdict = Get-Kv $Receipt 'semantic_verdict'; $severity = Get-Kv $Receipt 'max_severity'
        if (@('CLEAN:NONE','CLEAN:P3','FINDINGS:P3') -cnotcontains "${verdict}:${severity}") { return $false }
        $digest = Get-Kv $Receipt 'findings_digest'; if ($digest -notmatch '^[0-9a-fA-F]{64}$') { return $false }
        $report = Get-OwnedPath $Root (Get-Kv $Receipt 'output_path') $true
        if ((Get-ShaFile $report) -cne (Get-Kv $Receipt 'output_hash')) { return $false }
        if ((Get-Kv $report 'schema_version') -cne '1' -or (Get-Kv $report 'blocked_class') -cne 'none' -or
            (Get-Kv $report 'verdict') -cne $verdict -or (Get-Kv $report 'max_severity') -cne $severity) { return $false }
        $findings = @(Get-Content -LiteralPath $report | Where-Object { $_ -clike 'finding=*' })
        foreach ($finding in $findings) { if (($finding -split '\|')[1] -cne 'P3') { return $false } }
        if ($verdict -ceq 'FINDINGS' -and $findings.Count -eq 0) { return $false }
        $requested = Get-Kv $Receipt 'requested_engine'; $actual = Get-Kv $Receipt 'actual_engine'; $fallback = Get-Kv $Receipt 'fallback'; $reason = Get-Kv $Receipt 'fallback_reason'
        if (@('auto','claude','codex') -cnotcontains $requested -or @('claude','codex') -cnotcontains $actual) { return $false }
        if ($fallback -ceq 'false') { if ($reason -cne 'none' -or ($requested -cne 'auto' -and $requested -cne $actual)) { return $false } }
        elseif ($fallback -ceq 'true') { if (-not $reason -or $reason -ceq 'none') { return $false } }
        else { return $false }
        return $true
    }
    catch { return $false }
}
function Test-Verifier([string]$Root, [string]$Receipt, [string]$ReceiptKind, [string]$CandidateReceipt, [string]$AllowedOmissions = '') {
    try {
        foreach ($key in @('schema_version','receipt_kind','invocation_id','started_at','ended_at','candidate_id','worktree_identity','git_head','workflow_base_sha','index_tree','command_hash','profile','exit_status','report_path','report_hash','report_verdict','result')) { $null = Get-Kv $Receipt $key }
        if ((Get-Kv $Receipt 'schema_version') -cne '2' -or (Get-Kv $Receipt 'receipt_kind') -cne $ReceiptKind -or -not (Test-Fresh (Get-Kv $Receipt 'ended_at'))) { return $false }
        if ((Get-Kv $Receipt 'exit_status') -cne '0') { return $false }
        foreach ($key in @('candidate_id','worktree_identity','git_head','workflow_base_sha','index_tree')) { if ((Get-Kv $Receipt $key) -cne (Get-Kv $CandidateReceipt $key)) { return $false } }
        $report = Get-OwnedPath $Root (Get-Kv $Receipt 'report_path') $true
        if ((Get-ShaFile $report) -cne (Get-Kv $Receipt 'report_hash')) { return $false }
        $actualVerdict = Get-ReportVerdict $report $ReceiptKind
        $reportLines = [IO.File]::ReadAllLines($report)
        $markers = @($reportLines | Where-Object { $_.StartsWith('HUMAN_WAIVED_CHECKS:', [StringComparison]::Ordinal) })
        if ($markers.Count -gt 0) {
            if ($markers.Count -ne 1 -or $actualVerdict -cne 'PASS' -or -not $AllowedOmissions -or
                $reportLines.Count -lt 3 -or $reportLines[2] -cne "HUMAN_WAIVED_CHECKS: $AllowedOmissions") { return $false }
        }
        $reportVerdict = Get-Kv $Receipt 'report_verdict'
        $result = Get-Kv $Receipt 'result'
        if ($actualVerdict -cne $reportVerdict) { return $false }
        if ($ReceiptKind -ceq 'verify-app' -and $result -ceq 'PASS' -and $reportVerdict -ceq 'PASS') { return $true }
        if ($ReceiptKind -ceq 'e2e' -and $result -ceq 'PASS' -and $reportVerdict -ceq 'PASS') { return $true }
        if ($ReceiptKind -ceq 'e2e' -and $result -ceq 'N/A' -and $reportVerdict -ceq 'N/A') {
            $null = Get-E2eNaReason $report
            return $true
        }
        return $false
    }
    catch { return $false }
}

# Human approval is separate authorization, never an independent review PASS.
# Bind both the staged candidate and its exact ordinary (possibly merge) commit.
function Get-WorkflowSkips([string]$Raw) {
    $fixed = @('review','verify-app','e2e','simplification','plan-review','convergence','changelog','continuation')
    if ($Raw -ceq 'all') { return $fixed -join ',' }
    if (-not $Raw -or $Raw -cmatch '[^a-z0-9,:-]' -or $Raw -match '^,|,$|,,') { throw 'explicit nonempty skip scopes required' }
    $tokens = @($Raw.Split(',')); $seen = @()
    foreach ($token in $tokens) {
        if ($seen -ccontains $token) { throw 'duplicate skip scope' }
        if ($fixed -cnotcontains $token -and $token -cnotmatch '^(verify-app|e2e):[a-z0-9]+(-[a-z0-9]+)*$') { throw 'unknown skip scope' }
        $seen += $token
    }
    foreach ($kind in @('verify-app','e2e')) {
        if ($tokens -ccontains $kind -and @($tokens | Where-Object { $_.StartsWith("${kind}:", [StringComparison]::Ordinal) }).Count -gt 0) { throw 'overlapping skip scopes' }
    }
    $normalized = @($fixed | Where-Object { $tokens -ccontains $_ })
    [string[]]$subchecks = @($tokens | Where-Object { $_.Contains(':') })
    [Array]::Sort($subchecks, [StringComparer]::Ordinal)
    return (@($normalized) + @($subchecks)) -join ','
}
function Get-WorkflowSubchecks([string]$Gates, [string]$Kind) {
    return @($Gates.Split(',') | Where-Object { $_.StartsWith("${Kind}:", [StringComparison]::Ordinal) } | ForEach-Object { $_.Substring($Kind.Length + 1) }) -join ','
}
function Assert-WorkflowEvidence([string]$Root, [string]$StateFile, [string]$CandidateFile, [string]$Gates) {
    $skips = $Gates.Split(',')
    if ($skips -cnotcontains 'review') {
        $spec = Get-OwnedPath $Root (Get-StateValue $StateFile 'Spec review receipt') $true
        $quality = Get-OwnedPath $Root (Get-StateValue $StateFile 'Quality review receipt') $true
        $iteration = Get-StateValue $StateFile 'Review iteration'
        if (-not (Test-Review $Root $spec 'code-spec' $CandidateFile $iteration) -or
            -not (Test-Review $Root $quality 'code-quality' $CandidateFile $iteration) -or
            (Get-Kv $spec 'invocation_id') -ceq (Get-Kv $quality 'invocation_id')) { throw 'unwaived independent review is missing or unsuccessful' }
    }
    foreach ($kind in @('verify-app','e2e')) {
        if ($skips -ccontains $kind) { continue }
        $field = if ($kind -ceq 'verify-app') { 'Verify app receipt' } else { 'E2E receipt' }
        $file = Get-OwnedPath $Root (Get-StateValue $StateFile $field) $true
        if (-not (Test-Verifier $Root $file $kind $CandidateFile (Get-WorkflowSubchecks $Gates $kind))) { throw "unwaived $kind is missing, stale or unsuccessful" }
    }
}
function Test-WaiverText([string]$Text) {
    return -not [string]::IsNullOrWhiteSpace($Text) -and $Text -notmatch '[\x00\r\n]'
}
function Invoke-WaiverGit([string]$Root, [string[]]$Arguments) {
    $lines = @(& git -C $Root @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'review waiver Git identity check failed' }
    return $lines -join "`n"
}
function Get-WaiverNonce([string]$StateFile) {
    $sections = 0; $inside = $false; $values = @()
    foreach ($line in [IO.File]::ReadAllLines($StateFile)) {
        if ($line -ceq '## /goal session') { $sections++; $inside = $true; continue }
        if ($line.StartsWith('## ')) { $inside = $false }
        if ($inside) {
            $parts = $line.Split('|')
            if ($parts.Count -ge 4 -and $parts[1].Trim() -ceq 'nonce') { $values += $parts[2].Trim() }
        }
    }
    if ($sections -gt 1 -or $values.Count -gt 1) { throw 'review waiver requires unambiguous Goal nonce' }
    if ($values.Count -eq 0 -or -not $values[0] -or $values[0] -ceq '<uuid-v4-lowercase>') { return 'none' }
    if ($values[0] -ceq 'none') { throw 'active Goal nonce conflicts with inactive review waiver marker' }
    return [string]$values[0]
}
function Get-WaiverScope([string]$Root, [string]$StateFile, [string]$CandidateFile) {
    $workflow = Get-StateValue $StateFile 'Command'
    if (-not (Test-WaiverText $workflow) -or $workflow -in @('none','-',[string][char]0x2014) -or $workflow.Contains('<')) { throw 'review waiver requires an active workflow' }
    $baseRef = Get-StateValue $StateFile 'Workflow base ref'; $base = Get-StateValue $StateFile 'Workflow base SHA'
    if ($baseRef -cne (Get-Kv $CandidateFile 'workflow_base_ref') -or $base -cne (Get-Kv $CandidateFile 'workflow_base_sha')) { throw 'review waiver workflow base differs from candidate' }
    $branch = Invoke-WaiverGit $Root @('symbolic-ref','-q','HEAD')
    if ($branch -cnotmatch '^refs/heads/.+$') { throw 'review waiver requires a named branch' }
    return [ordered]@{ workflow_command = $workflow; workflow_base_ref = $baseRef; workflow_base_sha = $base; goal_nonce = (Get-WaiverNonce $StateFile); branch_ref = $branch }
}
function Get-WaiverParents([string]$Root) {
    $head = Invoke-WaiverGit $Root @('rev-parse','HEAD')
    $parents = @($head)
    $rawPath = Invoke-WaiverGit $Root @('rev-parse','--git-path','MERGE_HEAD')
    $mergePath = if ([IO.Path]::IsPathRooted($rawPath)) { $rawPath } else { Join-Path $Root $rawPath }
    $mergeItem = Get-Item -LiteralPath $mergePath -Force -ErrorAction SilentlyContinue
    if ($mergeItem) {
        if ($mergeItem.PSIsContainer -or (($mergeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'review waiver merge parents must be a regular file' }
        $mergeParents = @([IO.File]::ReadAllLines($mergePath))
        if ($mergeParents.Count -eq 0) { throw 'review waiver merge parents are empty' }
        $parents += $mergeParents
    }
    $seenParents = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($parent in $parents) {
        if (-not $seenParents.Add($parent)) { throw 'review waiver merge parents must be distinct' }
        if ($parent -cnotmatch '^[0-9a-f]{40}([0-9a-f]{24})?$' -or (Invoke-WaiverGit $Root @('rev-parse',"$parent^{commit}")) -cne $parent) { throw 'review waiver parent is invalid' }
    }
    return $parents -join ' '
}
function Get-WaiverCandidateState([string]$Root, [string]$CandidateFile, [string]$Parents) {
    if ((Get-Kv $CandidateFile 'schema_version') -cne '2' -or (Get-Kv $CandidateFile 'candidate_state') -cne 'staged-clean') { throw 'review waiver requires a staged-clean candidate' }
    $base = Get-Kv $CandidateFile 'workflow_base_sha'; $oldHead = Get-Kv $CandidateFile 'git_head'
    $tree = Get-Kv $CandidateFile 'index_tree'; $worktree = Get-Kv $CandidateFile 'worktree_identity'
    if ((Get-Kv $CandidateFile 'candidate_id') -cne (Get-ShaText "$base`n$oldHead`n$tree`n$worktree`n")) { throw 'review waiver candidate identity is invalid' }
    if ($Parents -cne $oldHead -and -not $Parents.StartsWith("$oldHead ", [StringComparison]::Ordinal)) { throw 'review waiver first parent differs from approved HEAD' }
    $currentHead = Invoke-WaiverGit $Root @('rev-parse','HEAD')
    if ($currentHead -ceq $oldHead) {
        if (-not (Test-CurrentCandidate $Root $CandidateFile) -or (Get-WaiverParents $Root) -cne $Parents) { throw 'review waiver staged candidate or ordered parents changed' }
        if ($Parents -ceq $oldHead -and (Invoke-WaiverGit $Root @('rev-parse',"$oldHead^{tree}")) -ceq $tree) { return 'postcommit' }
        return 'precommit'
    }
    if ($Parents -ceq $oldHead -and (Invoke-WaiverGit $Root @('rev-parse',"$oldHead^{tree}")) -ceq $tree) { throw 'review waiver approved an existing commit, not another child commit' }
    if ((Get-WaiverParents $Root) -cne $currentHead -or
        (Invoke-WaiverGit $Root @('rev-parse',"$currentHead^{tree}")) -cne $tree -or
        (Invoke-WaiverGit $Root @('rev-list','--parents','-n','1',$currentHead)) -cne "$currentHead $Parents") { throw 'review waiver commit tree or ordered parents changed' }
    $fingerprint = Join-Path $PSScriptRoot 'candidate-fingerprint.ps1'
    if (-not (Test-Path -LiteralPath $fingerprint)) { $fingerprint = Join-Path $Root 'hooks/lib/candidate-fingerprint.ps1' }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('forge-waiver-current-' + [Guid]::NewGuid().ToString('N'))
    try {
        & $fingerprint -Mode identity -Artifact 'git:working-tree' -WorkflowBaseSha $base -WorkflowBaseRef (Get-Kv $CandidateFile 'workflow_base_ref') -Output $temporary
        if ($LASTEXITCODE -ne 0 -or (Get-Kv $temporary 'git_head') -cne $currentHead) { throw 'review waiver cannot validate current commit' }
        foreach ($key in @('worktree_identity','workflow_base_sha','index_tree','candidate_state')) {
            if ((Get-Kv $CandidateFile $key) -cne (Get-Kv $temporary $key)) { throw 'review waiver requires the exact clean committed candidate' }
        }
        return 'postcommit'
    }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}
function Assert-ReviewWaiver([string]$Root, [string]$StateFile, [string]$CandidateFile, [string]$AppFile, [string]$E2eFile, [string]$Waiver) {
    $schema = Get-Kv $Waiver 'schema_version'; $kind = Get-Kv $Waiver 'receipt_kind'
    if ($schema -ceq '2' -and $kind -ceq 'human-workflow-waiver') {
        $gates = Get-Kv $Waiver 'waived_gates'
        if ((Get-WorkflowSkips $gates) -cne $gates) { throw 'invalid normalized workflow skip scopes' }
    } elseif ($schema -cne '1' -or $kind -cne 'human-review-waiver') { throw 'invalid waiver schema or kind' }
    if (-not (Test-Fresh (Get-Kv $Waiver 'recorded_at')) -or -not (Test-WaiverText (Get-Kv $Waiver 'decision')) -or
        -not (Test-WaiverText (Get-Kv $Waiver 'provenance'))) { throw 'waiver decision or provenance missing, invalid or stale' }
    if ((Get-Kv $Waiver 'candidate_path') -cne $CandidateFile -or (Get-Kv $Waiver 'candidate_hash') -cne (Get-ShaFile $CandidateFile)) { throw 'review waiver candidate receipt changed' }
    foreach ($key in @('candidate_id','worktree_identity','git_head','index_tree')) {
        if ((Get-Kv $Waiver $key) -cne (Get-Kv $CandidateFile $key)) { throw 'review waiver candidate identity changed' }
    }
    $scope = Get-WaiverScope $Root $StateFile $CandidateFile
    foreach ($key in $scope.Keys) { if ((Get-Kv $Waiver $key) -cne $scope[$key]) { throw 'review waiver workflow, Goal, or branch changed' } }
    if ($schema -ceq '1' -and ((Get-Kv $Waiver 'verify_app_receipt_hash') -cne (Get-ShaFile $AppFile) -or (Get-Kv $Waiver 'e2e_receipt_hash') -cne (Get-ShaFile $E2eFile) -or
        -not (Test-Verifier $Root $AppFile 'verify-app' $CandidateFile) -or -not (Test-Verifier $Root $E2eFile 'e2e' $CandidateFile))) { throw 'review waiver verification is missing, stale, changed, or unsuccessful' }
    return Get-WaiverCandidateState $Root $CandidateFile (Get-Kv $Waiver 'parents')
}
function Write-ReviewWaiver([string]$Root, [string]$StateFile, [string]$CandidateFile, [string]$AppFile, [string]$E2eFile, [string]$HumanDecision, [string]$HumanProvenance, [string]$Skipped = '') {
    if (-not (Test-WaiverText $HumanDecision) -or -not (Test-WaiverText $HumanProvenance)) { throw 'review waiver requires the actual human decision and conversation provenance' }
    if (-not (Test-CurrentCandidate $Root $CandidateFile)) { throw 'review waiver needs the current staged-clean frozen candidate' }
    $scope = Get-WaiverScope $Root $StateFile $CandidateFile
    $body = @('schema_version=1','receipt_kind=human-review-waiver',"recorded_at=$([DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))", "decision=$HumanDecision", "provenance=$HumanProvenance")
    if ($Skipped) {
        $body[0] = 'schema_version=2'; $body[1] = 'receipt_kind=human-workflow-waiver'
        $body += "waived_gates=$(Get-WorkflowSkips $Skipped)"
    }
    foreach ($key in $scope.Keys) { $body += "$key=$($scope[$key])" }
    $body += @("candidate_path=$CandidateFile", "candidate_hash=$(Get-ShaFile $CandidateFile)")
    foreach ($key in @('candidate_id','worktree_identity','git_head','index_tree')) { $body += "$key=$(Get-Kv $CandidateFile $key)" }
    $body += "parents=$(Get-WaiverParents $Root)"
    if (-not $Skipped) { $body += @("verify_app_receipt_hash=$(Get-ShaFile $AppFile)", "e2e_receipt_hash=$(Get-ShaFile $E2eFile)") }
    $suffix = if ($Skipped) { 'workflow-waiver' } else { 'review-waiver' }
    $waiver = Get-OwnedPath $Root "$CandidateFile.$suffix" $false
    $temporary = Get-OwnedPath $Root "$waiver.tmp.$PID" $false
    try {
        [IO.File]::WriteAllText($temporary, (($body -join "`n") + "`n"), $Utf8)
        $waiverState = Assert-ReviewWaiver $Root $StateFile $CandidateFile $AppFile $E2eFile $temporary
        Move-Item -LiteralPath $temporary -Destination $waiver -Force
        return [pscustomobject]@{ Path = $waiver; State = $waiverState }
    }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}


# Original receipts keep their original candidate and age; a separate bounded
# closure proves only the opt-in non-runtime prose delta to the final candidate.
function Test-DocsBundle([string]$Root, [string]$Source, [string]$Spec, [string]$Quality, [string]$App, [string]$E2e, [string]$Iteration) {
    return (Test-Review $Root $Spec 'code-spec' $Source $Iteration) -and
        (Test-Review $Root $Quality 'code-quality' $Source $Iteration) -and
        (Get-Kv $Spec 'invocation_id') -cne (Get-Kv $Quality 'invocation_id') -and
        (Test-Verifier $Root $App 'verify-app' $Source) -and (Test-Verifier $Root $E2e 'e2e' $Source)
}
function Invoke-DocsGit([string]$Root, [string[]]$Arguments) {
    $lines = @(& git -C $Root @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'documentation delta Git check failed' }
    return $lines -join "`n"
}
function Test-DocsObject([string]$Root, [string]$Object) {
    # Windows PowerShell turns redirected native stderr into terminating errors
    # under Stop. This existence probe must use Git's exit status for absence.
    $ErrorActionPreference = 'Continue'
    & git -C $Root cat-file -e $Object 2>$null
    return $LASTEXITCODE -eq 0
}
function Assert-DocsIdentity([string]$Root, [string]$Source, [string]$Target) {
    if ((Get-Kv $Source 'schema_version') -cne '2' -or (Get-Kv $Source 'candidate_state') -cne 'staged-clean') { throw 'original staged-clean schema-v2 candidate required' }
    foreach ($key in @('workflow_base_ref','workflow_base_sha','worktree_identity')) {
        if ((Get-Kv $Source $key) -cne (Get-Kv $Target $key)) { throw 'original candidate base or worktree differs' }
    }
    $base = Get-Kv $Source 'workflow_base_sha'; $head = Get-Kv $Source 'git_head'; $tree = Get-Kv $Source 'index_tree'; $worktree = Get-Kv $Source 'worktree_identity'
    foreach ($oid in @($base,$head,$tree)) { if ($oid -cnotmatch '^[0-9a-f]+$') { throw 'invalid original Git identity' } }
    if ((Get-Kv $Source 'candidate_id') -cne (Get-ShaText "$base`n$head`n$tree`n$worktree`n") -or
        -not (Test-DocsObject $Root "$head^{commit}") -or -not (Test-DocsObject $Root "$tree^{tree}")) { throw 'original candidate identity is invalid' }
}
function Assert-DocsParent([string]$Root, [string]$Source, [string]$Target, [string]$Promotion) {
    $head = Get-Kv $Source 'git_head'; $commit = Get-Kv $Target 'git_head'
    if ($head -ceq $commit) { if ($Promotion -cne 'none') { throw 'unexpected original promotion' }; return }
    if ($Promotion -ceq 'none') { throw 'original exact promotion provenance is missing' }
    if ((Get-Kv $Promotion 'schema_version') -cne '2' -or
        (Get-Kv $Promotion 'old_candidate_id') -cne (Get-Kv $Source 'candidate_id') -or
        (Get-Kv $Promotion 'old_head') -cne $head -or
        (Get-Kv $Promotion 'worktree_identity') -cne (Get-Kv $Source 'worktree_identity') -or
        (Get-Kv $Promotion 'temporary_commit') -cne $commit -or (Get-Kv $Promotion 'new_branch_commit') -cne $commit -or
        (Get-Kv $Promotion 'new_branch_tree') -cne (Get-Kv $Source 'index_tree') -or
        (Get-Kv $Promotion 'post_commit_dirty') -cne 'false' -or @('pass','not-run') -cnotcontains (Get-Kv $Promotion 'post_commit_status')) { throw 'original exact promotion provenance is invalid' }
    if ((Invoke-DocsGit $Root @('rev-parse', "$commit^{tree}")) -cne (Get-Kv $Source 'index_tree') -or
        (Invoke-DocsGit $Root @('rev-list','--parents','-n','1',$commit)) -cne "$commit $head") { throw 'candidate parent changed outside original exact Forge promotion' }
}
function Test-DocsPath([string]$Path) {
    if ($Path.StartsWith('/') -or $Path.Contains('..') -or $Path.Contains('\') -or $Path -match '[*?\[\]\x00-\x1f]') { return $false }
    $lower = $Path.ToLowerInvariant(); $baseName = ($lower -split '/')[-1]
    if ($lower -notmatch '^(docs/|changelog\.md$)' -or $lower -match '/(plans|requirements|\.forge|\.claude|\.codex|\.agents|commands|rules|skills|agents|hooks|scripts|settings|templates|manifests|tests)/') { return $false }
    if ($baseName -match '^(agents\..*|claude\..*|forge\.template\..*|contributing.*|agent-context\..*|policy.*|instructions.*|requirements.*|prd\..*|design\..*|config.*|plan\..*)$') { return $false }
    return $baseName -match '\.(md|markdown)$'
}
function Get-DocsTreeBlob([string]$Root, [string]$Tree, [string]$Path) {
    $entry = Invoke-DocsGit $Root @('ls-tree',$Tree,'--',$Path)
    if ($entry -cnotmatch '^100644 blob ([0-9a-f]+)\t') { throw 'documentation policy and source markers must be tracked regular 100644 files' }
    return $matches[1]
}
function Get-DocsDelta([string]$Root, [string]$Source, [string]$Target) {
    $oldTree = Get-Kv $Source 'index_tree'; $newTree = Get-Kv $Target 'index_tree'
    $policy = '.forge/verification-scope.tsv'
    if (-not (Test-DocsObject $Root "${oldTree}:$policy") -and -not (Test-DocsObject $Root "${newTree}:$policy")) {
        foreach ($marker in @('FORGE.template.md','state.template.md','manifests/managed-v6.tsv')) {
            $null = Get-DocsTreeBlob $Root $oldTree $marker; $null = Get-DocsTreeBlob $Root $newTree $marker
        }
        $policy = 'manifests/verification-scope.tsv'
    }
    $blob = Get-DocsTreeBlob $Root $oldTree $policy
    if ($blob -cne (Get-DocsTreeBlob $Root $newTree $policy)) { throw 'documentation scope policy changed' }
    $policyLines = (Invoke-DocsGit $Root @('show',"${oldTree}:$policy")) -split "`n"
    if ($policyLines[0].TrimEnd("`r") -cne '# forge:non-runtime-prose v1') { throw 'invalid documentation scope policy header' }
    $declared = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    for ($i = 1; $i -lt $policyLines.Count; $i++) {
        $line = $policyLines[$i].TrimEnd("`r")
        if (-not $line -or $line.StartsWith('#')) { continue }
        $fields = $line.Split("`t")
        if ($fields.Count -ne 2 -or $fields[0] -cne 'prose' -or -not $fields[1] -or $fields[1].StartsWith('/') -or $fields[1].Contains('..') -or $fields[1] -match '[*?\[\]\x00-\x1f]' -or -not $declared.Add($fields[1])) { throw 'invalid or duplicate prose declaration' }
    }
    $raw = Invoke-DocsGit $Root @('-c','core.quotePath=true','diff','--raw','--no-abbrev','--no-renames','--no-ext-diff','--no-textconv',$oldTree,$newTree,'--')
    if (-not $raw) { throw 'documentation closure requires a changed tree' }
    foreach ($line in ($raw -split "`n")) {
        $parts = $line.Split("`t")
        if ($parts.Count -ne 2) { throw 'ambiguous documentation delta path' }
        $fields = $parts[0] -split ' '; $path = $parts[1]
        if ($fields.Count -ne 5 -or $fields[0] -cne ':100644' -or $fields[1] -cne '100644' -or $fields[4] -cne 'M' -or
            -not (Test-DocsPath $path) -or -not $declared.Contains($path)) { throw 'delta is outside the declared non-runtime prose contract' }
        $oldText = Invoke-DocsGit $Root @('show',"${oldTree}:$path"); $newText = Invoke-DocsGit $Root @('show',"${newTree}:$path")
        if ($oldText.Contains([char]0) -or $newText.Contains([char]0)) { throw 'binary prose is ineligible' }
        if (($path -split '/')[-1].ToLowerInvariant() -match '^changelog\.(md|markdown)$') {
            $oldHeading = @($oldText -split "`n" | Where-Object { $_ -cmatch '^##\s' } | Select-Object -First 1)
            $newHeading = @($newText -split "`n" | Where-Object { $_ -cmatch '^##\s' } | Select-Object -First 1)
            if ($oldHeading.Count -ne 1 -or $newHeading.Count -ne 1 -or $oldHeading[0] -cne $newHeading[0]) { throw 'machine-consumed release heading changed' }
        }
    }
    $null = Invoke-DocsGit $Root @('diff','--no-ext-diff','--no-textconv','--check',$oldTree,$newTree,'--')
    return [pscustomobject]@{ PolicyPath = $policy; PolicyBlob = $blob; DeltaHash = (Get-ShaText ($raw + "`n")) }
}
function Copy-DocsArchive([string]$Root, [string]$Source, [string]$Destination) {
    $path = Get-OwnedPath $Root $Destination $false
    if (Test-Path -LiteralPath $path) {
        if ((Get-ShaFile $path) -cne (Get-ShaFile $Source)) { throw 'original documentation evidence archive was changed' }
    }
    else {
        $temporary = Get-OwnedPath $Root "$path.tmp.$PID" $false
        [IO.File]::WriteAllBytes($temporary, [IO.File]::ReadAllBytes($Source))
        Move-Item -LiteralPath $temporary -Destination $path -Force
    }
    return $path
}
function Test-DocsClosure([string]$Root, [string]$CandidateFile, [string]$SpecFile, [string]$QualityFile, [string]$AppFile, [string]$E2eFile, [string]$Iteration) {
    try {
        $closure = Get-OwnedPath $Root "$CandidateFile.docs-closure" $true
        if ((Get-Kv $closure 'schema_version') -cne '1' -or (Get-Kv $closure 'receipt_kind') -cne 'docs-closure' -or
            (Get-Kv $closure 'docs_check') -cne 'PASS' -or (Get-Kv $closure 'review_iteration') -cne $Iteration -or
            -not (Test-Fresh (Get-Kv $closure 'closed_at')) -or (Get-Kv $closure 'new_candidate_hash') -cne (Get-ShaFile $CandidateFile) -or
            (Get-Kv $closure 'new_candidate_id') -cne (Get-Kv $CandidateFile 'candidate_id')) { return $false }
        $source = Get-OwnedPath $Root (Get-Kv $closure 'original_candidate_path') $true
        if ((Get-ShaFile $source) -cne (Get-Kv $closure 'original_candidate_hash')) { return $false }
        Assert-DocsIdentity $Root $source $CandidateFile
        $promotion = Get-Kv $closure 'source_promotion_path'
        if ($promotion -cne 'none') {
            $promotion = Get-OwnedPath $Root $promotion $true
            if ((Get-ShaFile $promotion) -cne (Get-Kv $closure 'source_promotion_hash')) { return $false }
        }
        elseif ((Get-Kv $closure 'source_promotion_hash') -cne 'none') { return $false }
        Assert-DocsParent $Root $source $CandidateFile $promotion
        foreach ($entry in @(@('spec',$SpecFile),@('quality',$QualityFile),@('verify_app',$AppFile),@('e2e',$E2eFile))) {
            if ((Get-Kv $closure ($entry[0] + '_receipt_hash')) -cne (Get-ShaFile $entry[1])) { return $false }
        }
        if (-not (Test-DocsBundle $Root $source $SpecFile $QualityFile $AppFile $E2eFile $Iteration)) { return $false }
        $delta = Get-DocsDelta $Root $source $CandidateFile
        return (Get-Kv $closure 'policy_path') -ceq $delta.PolicyPath -and (Get-Kv $closure 'policy_blob') -ceq $delta.PolicyBlob -and (Get-Kv $closure 'delta_hash') -ceq $delta.DeltaHash
    }
    catch { return $false }
}
function Write-DocsClosure([string]$Root, [string]$StateFile, [string]$CandidateFile, [string]$Previous, [string]$SpecFile, [string]$QualityFile, [string]$AppFile, [string]$E2eFile, [string]$Iteration) {
    if (-not (Test-CurrentCandidate $Root $CandidateFile)) { throw 'docs closure needs the current staged-clean final candidate' }
    $source = Get-OwnedPath $Root $Previous $true
    Assert-DocsIdentity $Root $source $CandidateFile
    if (-not (Test-DocsBundle $Root $source $SpecFile $QualityFile $AppFile $E2eFile $Iteration)) { throw 'original candidate lacks a complete fresh passing receipt set' }
    $promotion = 'none'; $promotionHash = 'none'
    if ((Get-Kv $source 'git_head') -cne (Get-Kv $CandidateFile 'git_head')) {
        $promotion = Get-OwnedPath $Root (Get-StateValue $StateFile 'Promotion receipt') $true
    }
    Assert-DocsParent $Root $source $CandidateFile $promotion
    $delta = Get-DocsDelta $Root $source $CandidateFile
    $archived = Copy-DocsArchive $Root $source "$CandidateFile.docs-original-$(Get-Kv $source 'candidate_id').receipt"
    if ($promotion -cne 'none') {
        $promotionHash = Get-ShaFile $promotion
        $promotion = Copy-DocsArchive $Root $promotion "$CandidateFile.docs-promotion-$promotionHash.receipt"
    }
    if (-not (Test-CurrentCandidate $Root $CandidateFile) -or -not (Test-DocsBundle $Root $archived $SpecFile $QualityFile $AppFile $E2eFile $Iteration)) { throw 'candidate or original evidence changed during docs closure' }
    Assert-DocsParent $Root $archived $CandidateFile $promotion
    $rechecked = Get-DocsDelta $Root $archived $CandidateFile
    if ($delta.PolicyPath -cne $rechecked.PolicyPath -or $delta.PolicyBlob -cne $rechecked.PolicyBlob -or $delta.DeltaHash -cne $rechecked.DeltaHash) { throw 'documentation delta changed during closure' }
    $closure = Get-OwnedPath $Root "$CandidateFile.docs-closure" $false
    $temporary = Get-OwnedPath $Root "$closure.tmp.$PID" $false
    $body = @('schema_version=1','receipt_kind=docs-closure',"closed_at=$([DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))",
        "original_candidate_path=$archived", "original_candidate_hash=$(Get-ShaFile $archived)", "new_candidate_id=$(Get-Kv $CandidateFile 'candidate_id')", "new_candidate_hash=$(Get-ShaFile $CandidateFile)",
        "source_promotion_path=$promotion", "source_promotion_hash=$promotionHash", "review_iteration=$Iteration")
    foreach ($entry in @(@('spec',$SpecFile),@('quality',$QualityFile),@('verify_app',$AppFile),@('e2e',$E2eFile))) { $body += "$($entry[0])_receipt_hash=$(Get-ShaFile $entry[1])" }
    $body += @("policy_path=$($delta.PolicyPath)","policy_blob=$($delta.PolicyBlob)","delta_hash=$($delta.DeltaHash)",'docs_check=PASS')
    [IO.File]::WriteAllText($temporary, (($body -join "`n") + "`n"), $Utf8)
    Move-Item -LiteralPath $temporary -Destination $closure -Force
    return $closure
}

function Invoke-VerificationReceipt {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('write', 'check', 'close-docs', 'record-review-waiver', 'check-review-waiver', 'record-workflow-waiver', 'check-workflow-waiver')][string]$ReceiptMode,
        [string]$ReceiptKind, [string]$CandidatePath, [string]$CommandText,
        [string]$ProfileName, [string]$ReportPath, [string]$ReceiptResult,
        [int]$ReceiptExitStatus = -1, [string]$OutputPath,
        [string]$ReceiptStartedAt, [string]$ReceiptEndedAt, [string]$StatePath, [string]$PreviousCandidatePath,
        [string]$ReceiptDecision, [string]$ReceiptProvenance, [string]$ReceiptSkip, [ValidateSet('ship','stop')][string]$ReceiptBoundary = 'ship'
    )
    $response = [ordered]@{ Status = 2; Lines = @(); Error = '' }
    $root = (& git rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    if (-not $root) { $response.Error = 'BLOCKED[evidence]: Git worktree required'; return [pscustomobject]$response }
    $root = (Resolve-Path $root).Path

    if ($ReceiptMode -eq 'write') {
        if (@('verify-app','e2e') -cnotcontains $ReceiptKind -or @('PASS','FAIL','BLOCKED','PARTIAL','N/A') -cnotcontains $ReceiptResult -or $ReceiptExitStatus -lt 0) {
            $response.Error = 'BLOCKED[evidence]: invalid verifier receipt arguments'; return [pscustomobject]$response
        }
        try {
            $candidateFile = Get-OwnedPath $root $CandidatePath $true
            if (-not (Test-CurrentCandidate $root $candidateFile)) { throw 'candidate is not current staged-clean identity' }
            $reportFile = Get-OwnedPath $root $ReportPath $true; $outputFile = Get-OwnedPath $root $OutputPath $false
            $reportVerdict = Get-ReportVerdict $reportFile $ReceiptKind
            if ($reportVerdict -cne $ReceiptResult) { throw 'report verdict and requested receipt result differ' }
            if ($ReceiptResult -ceq 'N/A') {
                if ($ReceiptKind -cne 'e2e' -or $ReceiptExitStatus -ne 0) { throw 'N/A is valid only for a successful E2E scope decision' }
                $null = Get-E2eNaReason $reportFile
            }
            if (-not $ReceiptStartedAt) { $ReceiptStartedAt = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
            if (-not $ReceiptEndedAt) { $ReceiptEndedAt = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') }
            if (-not (Test-Fresh $ReceiptStartedAt) -or -not (Test-Fresh $ReceiptEndedAt)) { throw 'verifier timestamps are stale or invalid' }
            $invocation = Get-ShaText "$ReceiptKind|$ReceiptStartedAt|$PID|$CommandText|$(Get-Kv $candidateFile 'candidate_id')`n"
            $body = "schema_version=2`nreceipt_kind=$ReceiptKind`ninvocation_id=$invocation`nstarted_at=$ReceiptStartedAt`nended_at=$ReceiptEndedAt`n"
            foreach ($key in @('candidate_id','worktree_identity','git_head','workflow_base_sha','index_tree')) { $body += "$key=$(Get-Kv $candidateFile $key)`n" }
            $body += "command_hash=$(Get-ShaText $CommandText)`nprofile=$ProfileName`nexit_status=$ReceiptExitStatus`nreport_path=$reportFile`nreport_hash=$(Get-ShaFile $reportFile)`nreport_verdict=$reportVerdict`nresult=$ReceiptResult`n"
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
        if ($ReceiptMode -in @('record-workflow-waiver','check-workflow-waiver')) {
            $stateFile = Get-OwnedPath $root $stateFile $true
            if ($ReceiptMode -ceq 'record-workflow-waiver') {
                $gates = Get-WorkflowSkips $ReceiptSkip
                $recorded = Write-ReviewWaiver $root $stateFile $candidateFile '' '' $ReceiptDecision $ReceiptProvenance $gates
                $waiverState = $recorded.State; $response.Lines = @("WORKFLOW_WAIVER:$($recorded.Path)")
            } else {
                $newPath = "$candidateFile.workflow-waiver"
                if (Get-Item -LiteralPath $newPath -Force -ErrorAction SilentlyContinue) {
                    $waiver = Get-OwnedPath $root $newPath $true
                    if ((Get-Kv $waiver 'receipt_kind') -cne 'human-workflow-waiver') { throw 'invalid workflow waiver kind' }
                    $gates = Get-Kv $waiver 'waived_gates'; $appFile = ''; $e2eFile = ''
                } else {
                    $waiver = Get-OwnedPath $root "$candidateFile.review-waiver" $true; $gates = 'review'
                    $appFile = Get-OwnedPath $root (Get-StateValue $stateFile 'Verify app receipt') $true
                    $e2eFile = Get-OwnedPath $root (Get-StateValue $stateFile 'E2E receipt') $true
                }
                $waiverState = Assert-ReviewWaiver $root $stateFile $candidateFile $appFile $e2eFile $waiver
                if ($ReceiptBoundary -ceq 'ship') { Assert-WorkflowEvidence $root $stateFile $candidateFile $gates }
            }
            $response.Status = 0
            $response.Lines += @('WORKFLOW_WAIVER_VALID:true','WORKFLOW_STATUS:human-waived',"WAIVED_GATES:$gates", "WORKFLOW_WAIVER_STATE:$waiverState")
            return [pscustomobject]$response
        }
        if ($ReceiptMode -in @('record-review-waiver','check-review-waiver')) {
            $stateFile = Get-OwnedPath $root $stateFile $true
            $appFile = Get-OwnedPath $root (Get-StateValue $stateFile 'Verify app receipt') $true
            $e2eFile = Get-OwnedPath $root (Get-StateValue $stateFile 'E2E receipt') $true
            if ($ReceiptMode -ceq 'record-review-waiver') {
                $recordedWaiver = Write-ReviewWaiver $root $stateFile $candidateFile $appFile $e2eFile $ReceiptDecision $ReceiptProvenance
                $response.Lines = @("REVIEW_WAIVER:$($recordedWaiver.Path)")
                $waiverState = $recordedWaiver.State
            }
            else {
                $waiver = Get-OwnedPath $root "$candidateFile.review-waiver" $true
                $waiverState = Assert-ReviewWaiver $root $stateFile $candidateFile $appFile $e2eFile $waiver
            }
            $response.Status = 0
            $response.Lines += @('REVIEW_WAIVER_VALID:true','REVIEW_STATUS:human-waived',"REVIEW_WAIVER_STATE:$waiverState")
            return [pscustomobject]$response
        }
        $specFile = Get-OwnedPath $root (Get-StateValue $stateFile 'Spec review receipt') $true
        $qualityFile = Get-OwnedPath $root (Get-StateValue $stateFile 'Quality review receipt') $true
        $appFile = Get-OwnedPath $root (Get-StateValue $stateFile 'Verify app receipt') $true
        $e2eFile = Get-OwnedPath $root (Get-StateValue $stateFile 'E2E receipt') $true
        $iteration = Get-StateValue $stateFile 'Review iteration'; if ($iteration -notmatch '^[0-9]+$') { throw 'Review iteration must be numeric' }
        if ($ReceiptMode -eq 'close-docs') {
            $closure = Write-DocsClosure $root $stateFile $candidateFile $PreviousCandidatePath $specFile $qualityFile $appFile $e2eFile $iteration
            $response.Status = 0; $response.Lines = @("DOCS_CLOSURE:$closure")
            return [pscustomobject]$response
        }
        $candidateOk = Test-CurrentCandidate $root $candidateFile
        if (-not $candidateOk) {
            $promotionFile = $null
            try { $promotionFile = Get-OwnedPath $root (Get-StateValue $stateFile 'Promotion receipt') $true }
            catch { $promotionFile = $null }
            if ($promotionFile) { $candidateOk = Test-PromotedCandidate $root $candidateFile $promotionFile }
        }
        $reviewsOk = $false; $appOk = $false; $e2eOk = $false
        if ($candidateOk -and (Test-Review $root $specFile 'code-spec' $candidateFile $iteration) -and (Test-Review $root $qualityFile 'code-quality' $candidateFile $iteration)) {
            $reviewsOk = (Get-Kv $specFile 'invocation_id') -cne (Get-Kv $qualityFile 'invocation_id')
        }
        if ($candidateOk) { $appOk = Test-Verifier $root $appFile 'verify-app' $candidateFile; $e2eOk = Test-Verifier $root $e2eFile 'e2e' $candidateFile }
        if ($candidateOk -and -not ($reviewsOk -and $appOk -and $e2eOk) -and (Test-DocsClosure $root $candidateFile $specFile $qualityFile $appFile $e2eFile $iteration)) {
            $reviewsOk = $true; $appOk = $true; $e2eOk = $true
        }
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
    $receiptResponse = Invoke-VerificationReceipt -ReceiptMode $Mode -ReceiptKind $Kind -CandidatePath $Candidate -CommandText $Command -ProfileName $Profile -ReportPath $Report -ReceiptResult $Result -ReceiptExitStatus $ExitStatus -OutputPath $Output -ReceiptStartedAt $StartedAt -ReceiptEndedAt $EndedAt -StatePath $State -PreviousCandidatePath $PreviousCandidate -ReceiptDecision $Decision -ReceiptProvenance $Provenance -ReceiptSkip $Skip -ReceiptBoundary $Boundary
    foreach ($line in $receiptResponse.Lines) { Write-Output $line }
    if ($receiptResponse.Error) { [Console]::Error.WriteLine($receiptResponse.Error) }
    exit $receiptResponse.Status
}
