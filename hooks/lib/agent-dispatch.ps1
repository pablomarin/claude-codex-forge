param(
    [Parameter(Mandatory = $true)][ValidateSet('run', 'verify-pair')][string]$Mode,
    [ValidateSet('auto', 'claude', 'codex')][string]$Engine = 'auto',
    [ValidateSet('automatic', 'none')][string]$FallbackPolicy = 'automatic',
    [ValidateSet('general', 'plan', 'code-spec', 'code-quality', 'investigation', 'investigation-repro', 'prd', 'comments', 'council-advisor', 'council-chair')][string]$Role = 'general',
    [ValidateSet('review', 'investigate')][string]$Profile = 'review',
    [string]$Artifact,
    [string]$WorkflowBaseSha,
    [string]$WorkflowBaseRef,
    [string]$PromptFile,
    [string]$Output,
    [ValidateSet('ephemeral', 'new', 'resume')][string]$Conversation = 'ephemeral',
    [string]$SessionId,
    [string]$SessionIdOutput,
    [string]$SeatId,
    [int]$TimeoutSeconds = 1200,
    [ValidateSet('', 'context7')][string]$ReadOnlyServer = '',
    [string]$CodeSpecReceipt,
    [string]$CodeQualityReceipt
)

$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$LibraryRoot = (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ForgeRoot = (Resolve-Path (Join-Path $LibraryRoot '../..')).Path
$Capabilities = Join-Path $ForgeRoot 'host-capabilities.tsv'
if (-not (Test-Path -LiteralPath $Capabilities)) { $Capabilities = Join-Path $ForgeRoot 'manifests/host-capabilities.tsv' }
$Renderer = Join-Path $ForgeRoot 'bin/render-dispatch-config.ps1'
if (-not (Test-Path -LiteralPath $Renderer)) { $Renderer = Join-Path $ForgeRoot 'scripts/render-dispatch-config.ps1' }
$Fingerprint = Join-Path $LibraryRoot 'candidate-fingerprint.ps1'
$HostContext = Join-Path $LibraryRoot 'host-context.ps1'

function Get-ShaBytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-ShaText([string]$Text) { return Get-ShaBytes ($Utf8.GetBytes($Text)) }
function Get-ShaFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'MISSING' }
    return Get-ShaBytes ([IO.File]::ReadAllBytes($Path))
}
function Get-Value([string]$Path, [string]$Key, [bool]$Strict = $false) {
    $rows = @(Get-Content -LiteralPath $Path | Where-Object { $_ -like "$Key=*" })
    if ($Strict -and $rows.Count -ne 1) { throw "BLOCKED[invariant]: key $Key must occur exactly once" }
    if ($rows.Count -eq 0) { return '' }
    return $rows[0].Substring($Key.Length + 1)
}
function Get-StateTableValue([string]$Path, [string]$Field) {
    $values = @()
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $parts = $line.Split('|')
        if ($parts.Count -ge 4 -and $parts[1].Trim() -ceq $Field) { $values += $parts[2].Trim() }
    }
    if ($values.Count -ne 1) { throw "BLOCKED[invariant]: state field $Field must occur exactly once" }
    return [string]$values[0]
}
function Test-SafeSessionId([string]$Value) { return $Value -match '^[A-Za-z0-9._-]+$' }
function Assert-NoFollowSessionMetadata([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'BLOCKED[invariant]: exact council session metadata is unavailable' }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'BLOCKED[invariant]: council session metadata must be a no-follow regular file' }
}
function Ensure-ReservedReviewDirectory([string]$Reviews, [string]$Relative, [bool]$Create) {
    if (-not $Relative -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)') { throw 'BLOCKED[invariant]: unsafe dispatcher-reserved path' }
    $cursor = $Reviews
    foreach ($part in @($Relative -split '[\\/]' | Where-Object { $_ -and $_ -ne '.' })) {
        $cursor = Join-Path $cursor $part
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (-not $item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'BLOCKED[invariant]: dispatcher-reserved ancestors must be no-follow directories' }
        }
        elseif ($Create) { New-Item -ItemType Directory -Path $cursor | Out-Null }
        else { throw 'BLOCKED[invariant]: dispatcher-reserved directory is unavailable' }
    }
    return [IO.Path]::GetFullPath($cursor)
}
function Reserve-OwnedReviewPath([string]$Path, [string]$Label, [string]$Root, [string]$Reviews) {
    if (-not $Path) { throw "BLOCKED[invariant]: $Label is required" }
    if ($Path.Contains("`n") -or $Path.Contains("`r")) { throw "BLOCKED[invariant]: $Label contains a newline" }
    $ownedDirectory = $Root
    foreach ($part in @('.forge', 'local', 'reviews')) {
        $ownedDirectory = Join-Path $ownedDirectory $part
        if (Test-Path -LiteralPath $ownedDirectory) {
            $ownedItem = Get-Item -LiteralPath $ownedDirectory -Force
            if (-not $ownedItem.PSIsContainer -or (($ownedItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'BLOCKED[invariant]: review storage ancestors must be no-follow directories' }
        }
        else { New-Item -ItemType Directory -Path $ownedDirectory | Out-Null }
    }
    $full = [IO.Path]::GetFullPath($Path); $prefix = $Reviews.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "BLOCKED[invariant]: $Label must stay under .forge/local/reviews" }
    $relative = $full.Substring($prefix.Length)
    if ($relative -match '^(sessions|session-stores)[\\/]' -or $relative -match '\.(receipt|candidate|recheck|manifest)$') { throw "BLOCKED[invariant]: $Label targets a dispatcher-reserved path" }
    $relativeParent = Split-Path -Parent $relative; $cursor = $Reviews
    foreach ($part in @($relativeParent -split '[\\/]' | Where-Object { $_ })) {
        $cursor = Join-Path $cursor $part
        if (Test-Path -LiteralPath $cursor) { $item = Get-Item -LiteralPath $cursor -Force; if (-not $item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw "BLOCKED[invariant]: reparse point in $Label path" } }
        else { New-Item -ItemType Directory -Path $cursor | Out-Null }
    }
    try { $stream = [IO.File]::Open($full, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None); $stream.Dispose() }
    catch { throw "BLOCKED[invariant]: $Label already exists, is linked, or cannot be reserved" }
    return $full
}
function Publish-OwnedReviewFile([string]$Source, [string]$Destination, [string]$Label, [string]$Reviews) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "BLOCKED[artifact]: $Label source must be a regular file" }
    $sourceItem = Get-Item -LiteralPath $Source -Force
    if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "BLOCKED[artifact]: $Label source cannot be a reparse point" }
    $prefix = $Reviews.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $Destination.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "BLOCKED[invariant]: $Label escaped review storage" }
    $parent = Split-Path -Parent $Destination; $relativeParent = $parent.Substring($Reviews.Length).TrimStart('\', '/'); $cursor = $Reviews
    foreach ($part in @($relativeParent -split '[\\/]' | Where-Object { $_ })) {
        $cursor = Join-Path $cursor $part
        $item = Get-Item -LiteralPath $cursor -Force
        if (-not $item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw "BLOCKED[invariant]: $Label ancestor changed before publication" }
    }
    if ((Resolve-Path -LiteralPath $parent).Path -cne [IO.Path]::GetFullPath($parent)) { throw "BLOCKED[invariant]: $Label parent changed before publication" }
    $temporary = "$Destination.publish.$invocationId"
    try {
        $input = [IO.File]::Open($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $staged = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $input.CopyTo($staged) } finally { $staged.Dispose() }
        }
        finally { $input.Dispose() }
        $temporaryItem = Get-Item -LiteralPath $temporary -Force
        if (($temporaryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "BLOCKED[invariant]: $Label publication temporary changed" }
        if ((Resolve-Path -LiteralPath $parent).Path -cne [IO.Path]::GetFullPath($parent)) { throw "BLOCKED[invariant]: $Label parent changed during publication" }
        [IO.File]::Replace($temporary, $Destination, $null, $true)
        $published = Get-Item -LiteralPath $Destination -Force
        if ($published.PSIsContainer -or (($published.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw "BLOCKED[invariant]: $Label publication is not a regular file" }
    }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}
function Escape-ProcessArgument([string]$Value) {
    if ($Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}
function ConvertTo-PowerShellLiteral([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
function Invoke-BoundProcess([string]$Executable, [string[]]$Arguments, [string]$WorkingDirectory, [hashtable]$Environment, [int]$Timeout) {
    $stdout = Join-Path ([IO.Path]::GetTempPath()) ('forge-stdout-' + [Guid]::NewGuid().ToString('N'))
    $stderr = Join-Path ([IO.Path]::GetTempPath()) ('forge-stderr-' + [Guid]::NewGuid().ToString('N'))
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = (@($Arguments | ForEach-Object { Escape-ProcessArgument $_ }) -join ' ')
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables.Clear()
    foreach ($key in @('PATH', 'SystemRoot', 'ComSpec', 'TEMP', 'TMP')) {
        $value = [Environment]::GetEnvironmentVariable($key)
        if ($value) { $start.EnvironmentVariables[$key] = $value }
    }
    foreach ($key in $Environment.Keys) { $start.EnvironmentVariables[$key] = [string]$Environment[$key] }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    if (-not $process.Start()) { return @{ Exit = 127; Stdout = $stdout; Stderr = $stderr } }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($Timeout * 1000)) {
        & taskkill.exe /PID $process.Id /T /F 2>$null | Out-Null
        try { $process.Kill() } catch {}
        $process.WaitForExit()
        [IO.File]::WriteAllText($stdout, $stdoutTask.Result, $Utf8)
        [IO.File]::WriteAllText($stderr, $stderrTask.Result, $Utf8)
        return @{ Exit = 124; Stdout = $stdout; Stderr = $stderr }
    }
    [IO.File]::WriteAllText($stdout, $stdoutTask.Result, $Utf8)
    [IO.File]::WriteAllText($stderr, $stderrTask.Result, $Utf8)
    return @{ Exit = $process.ExitCode; Stdout = $stdout; Stderr = $stderr }
}
function Read-Envelope([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).Length -eq 0) {
        return @{ Valid = $false; Class = 'engine'; Reason = 'empty-result'; Verdict = 'BLOCKED'; Severity = 'NONE'; Schema = 'none'; Digest = 'MISSING' }
    }
    $schema = Get-Value $Path 'schema_version'
    $verdict = Get-Value $Path 'verdict'
    $severity = Get-Value $Path 'max_severity'
    $blocked = Get-Value $Path 'blocked_class'
    $findings = @(Get-Content -LiteralPath $Path | Where-Object { $_ -like 'finding=*' })
    $valid = $schema -eq '1' -and $verdict -in @('CLEAN', 'FINDINGS', 'BLOCKED') -and
        $severity -in @('NONE', 'P0', 'P1', 'P2', 'P3') -and
        $blocked -in @('none', 'engine', 'capability', 'artifact', 'authorization', 'invariant')
    foreach ($finding in $findings) { if (($finding -split '\|').Count -lt 3 -or ($finding -split '\|')[1] -notin @('P0', 'P1', 'P2', 'P3')) { $valid = $false } }
    if ($verdict -eq 'CLEAN') { $valid = $valid -and $blocked -eq 'none' -and $severity -in @('NONE', 'P3') -and -not ($findings -match '\|(P0|P1|P2)\|') }
    elseif ($verdict -eq 'FINDINGS') { $valid = $valid -and $blocked -eq 'none' -and $findings.Count -gt 0 }
    elseif ($verdict -eq 'BLOCKED') { $valid = $valid -and $blocked -ne 'none' -and $findings.Count -eq 0 }
    if (-not $valid) { return @{ Valid = $false; Class = 'engine'; Reason = 'malformed-result'; Verdict = 'BLOCKED'; Severity = 'NONE'; Schema = 'none'; Digest = 'MISSING' } }
    return @{ Valid = $true; Class = $blocked; Reason = 'semantic-result'; Verdict = $verdict; Severity = $severity; Schema = '1'; Digest = Get-ShaText ($findings -join "`n") }
}
function Get-SnapshotState([string]$Root) {
    $state = @{}
    foreach ($item in Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction Stop) {
        $relative = $item.FullName.Substring($Root.Length).TrimStart('\', '/')
        if ($relative -eq '.git' -or $relative.StartsWith('.git\')) { continue }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "BLOCKED[artifact]: reparse point in candidate snapshot: $relative" }
        if (-not $item.PSIsContainer) { $state[$relative] = Get-ShaFile $item.FullName }
    }
    return $state
}
function Get-SnapshotStateHash([hashtable]$State) {
    $lines = @($State.Keys | Sort-Object | ForEach-Object { "$_`t$($State[$_])" })
    return Get-ShaText (($lines -join "`n") + "`n")
}
function Copy-DeclaredInvestigation([string]$Envelope, [string]$Snapshot, [hashtable]$Before, [string]$RealRoot) {
    $declared = @(Get-Content -LiteralPath $Envelope | Where-Object { $_ -like 'replay_path=*' } | ForEach-Object { $_.Substring(12) })
    if ($declared.Count -eq 0) { return 'NONE' }
    $allowed = @{}
    [long]$total = 0
    foreach ($declaredPath in $declared) {
        if ($declaredPath -notmatch '^(tests[\\/]reproductions|\.forge[\\/]local[\\/]investigation-artifacts)[\\/]' -or [IO.Path]::IsPathRooted($declaredPath) -or $declaredPath -match '(^|[\\/])\.\.([\\/]|$)') { throw 'BLOCKED[authorization]: undeclared investigation replay scope' }
        $relative = $declaredPath -replace '[\\/]', [string][IO.Path]::DirectorySeparatorChar
        $source = Join-Path $Snapshot $relative
        $item = Get-Item -LiteralPath $source -Force
        if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'BLOCKED[artifact]: replay source must be a regular file' }
        $total += $item.Length
        if ($item.Length -gt 1048576 -or $total -gt 5242880) { throw 'BLOCKED[artifact]: replay size limit exceeded' }
        $allowed[$relative] = $true
    }
    $after = Get-SnapshotState $Snapshot
    foreach ($path in @((@($Before.Keys) + @($after.Keys)) | Sort-Object -Unique)) {
        $beforeValue = if ($Before.ContainsKey($path)) { $Before[$path] } else { 'MISSING' }
        $afterValue = if ($after.ContainsKey($path)) { $after[$path] } else { 'MISSING' }
        if ($beforeValue -cne $afterValue -and -not $allowed.ContainsKey($path)) { throw 'BLOCKED[artifact]: undeclared investigation write' }
    }
    foreach ($declaredPath in $declared) {
        $relative = $declaredPath -replace '[\\/]', [string][IO.Path]::DirectorySeparatorChar
        $destination = Join-Path $RealRoot $relative
        $cursor = $RealRoot
        foreach ($part in @($relative -split '[\\/]' | Select-Object -SkipLast 1)) {
            $cursor = Join-Path $cursor $part
            if (Test-Path -LiteralPath $cursor) {
                $ancestor = Get-Item -LiteralPath $cursor -Force
                if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'BLOCKED[authorization]: replay ancestor is a reparse point' }
            }
        }
        if (Test-Path -LiteralPath $destination) {
            $existing = Get-Item -LiteralPath $destination -Force
            if (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'BLOCKED[authorization]: replay destination is a reparse point' }
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $Snapshot $relative) -Destination $destination -Force
    }
    return 'REPLAYED'
}
function Test-ReproductionProtectedBytes {
    if ((Get-ShaFile (Join-Path $root '.forge/local/state.md')) -cne $script:ReproProtectedStateHash) { return 'reproduction-protected-state-mutated' }
    if ($script:ReproProtectedAuthFile) {
        if (-not (Test-Path -LiteralPath $script:ReproProtectedAuthFile -PathType Leaf)) { return 'reproduction-protected-auth-mutated' }
        $item = Get-Item -LiteralPath $script:ReproProtectedAuthFile -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or (Get-ShaFile $script:ReproProtectedAuthFile) -cne $script:ReproProtectedAuthHash) { return 'reproduction-protected-auth-mutated' }
    }
    return ''
}
function Invoke-ReproductionPair([string]$Selected) {
    $script:ReproCheckKind = 'primary'; $script:ReproProgram = $script:ReproPrimaryProgram; $script:ReproArguments = @($script:ReproPrimaryArguments)
    $primaryResult = Invoke-Engine $Selected
    $protectedReason = Test-ReproductionProtectedBytes
    if ($protectedReason) { return @{ Rc = 2; Class = 'authorization'; Reason = $protectedReason; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = $primaryResult.Exit; Session = 'none'; ReproductionStatus = 'UNVERIFIED' } }
    if ($primaryResult.Rc -ne 0) { $primaryResult.ReproductionStatus = 'UNVERIFIED'; return $primaryResult }
    $primaryOutputHash = Get-ShaFile $primaryResult.ReproStdout
    $primaryHash = Get-ShaText (($script:ReproPrimaryProgram + "`n" + ($script:ReproPrimaryArguments -join "`n") + "`n$($primaryResult.ReproExit)`n$primaryOutputHash`n$(Get-ShaFile $primaryResult.ReproStderr)`n"))
    $primaryOk = $primaryResult.ReproExit -eq [int]$script:ReproPrimaryExpectedExit -and $primaryOutputHash -ceq $script:ReproPrimaryExpectedHash

    $script:ReproCheckKind = 'control'; $script:ReproProgram = $script:ReproControlProgram; $script:ReproArguments = @($script:ReproControlArguments)
    $controlResult = Invoke-Engine $Selected
    $protectedReason = Test-ReproductionProtectedBytes
    if ($protectedReason) { return @{ Rc = 2; Class = 'authorization'; Reason = $protectedReason; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = $controlResult.Exit; Session = 'none'; ReproductionStatus = 'UNVERIFIED'; PrimaryHash = $primaryHash } }
    if ($controlResult.Rc -ne 0) { $controlResult.ReproductionStatus = 'UNVERIFIED'; $controlResult.PrimaryHash = $primaryHash; return $controlResult }
    $controlOutputHash = Get-ShaFile $controlResult.ReproStdout
    $controlHash = Get-ShaText (($script:ReproControlProgram + "`n" + ($script:ReproControlArguments -join "`n") + "`n$($controlResult.ReproExit)`n$controlOutputHash`n$(Get-ShaFile $controlResult.ReproStderr)`n"))
    $controlOk = $controlResult.ReproExit -eq [int]$script:ReproControlExpectedExit -and $controlOutputHash -ceq $script:ReproControlExpectedHash
    $controlResult.ReproductionStatus = if ($primaryOk -and $controlOk) { 'REPRODUCED' } elseif (-not $primaryOk -and $controlOk) { 'FAILED' } elseif ($primaryOk) { 'PARTIAL' } else { 'UNVERIFIED' }
    $controlResult.PrimaryHash = $primaryHash; $controlResult.ControlHash = $controlHash; $controlResult.HypothesisHash = $script:ReproHypothesisHash
    $controlResult.Class = 'none'; $controlResult.Reason = 'dispatcher-owned-reproduction'; $controlResult.Verdict = 'CLEAN'; $controlResult.Severity = 'NONE'; $controlResult.Rc = 0; $controlResult.Exit = 0
    return $controlResult
}
function Invoke-IndependentReproduction([string]$Selected) {
    $required = @('schema_version','hypothesis','primary_program','primary_expected_exit','primary_expected_output_hash')
    foreach ($key in $required) { try { Get-Value $PromptFile $key $true | Out-Null } catch { return @{ Rc = 0; Class = 'none'; Reason = 'reproduction-spec-incomplete'; Engine = 'none'; Verdict = 'CLEAN'; Severity = 'NONE'; Exit = 0; Session = 'none'; ReproductionStatus = 'UNVERIFIED'; HypothesisHash = 'MISSING'; PrimaryHash = 'MISSING'; ControlHash = 'MISSING' } } }
    if ((Get-Value $PromptFile 'schema_version' $true) -ne '1') { return @{ Rc = 0; Class = 'none'; Reason = 'reproduction-schema-invalid'; Engine = 'none'; Verdict = 'CLEAN'; Severity = 'NONE'; Exit = 0; Session = 'none'; ReproductionStatus = 'UNVERIFIED'; HypothesisHash = 'MISSING'; PrimaryHash = 'MISSING'; ControlHash = 'MISSING' } }
    $script:ReproHypothesisHash = Get-ShaText (Get-Value $PromptFile 'hypothesis' $true)
    $script:ReproPrimaryProgram = Get-Value $PromptFile 'primary_program' $true; $script:ReproPrimaryExpectedExit = Get-Value $PromptFile 'primary_expected_exit' $true; $script:ReproPrimaryExpectedHash = Get-Value $PromptFile 'primary_expected_output_hash' $true
    if ($script:ReproPrimaryProgram -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($script:ReproPrimaryProgram) -or $script:ReproPrimaryExpectedExit -notmatch '^\d+$' -or $script:ReproPrimaryExpectedHash -notmatch '^[0-9a-fA-F]{64}$') { return @{ Rc = 2; Class = 'authorization'; Reason = 'reproduction-spec-invalid'; Engine = 'none'; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127; Session = 'none' } }
    $script:ReproPrimaryArguments = @(Get-Content -LiteralPath $PromptFile | Where-Object { $_ -like 'primary_arg=*' } | ForEach-Object { $_.Substring(12) })
    foreach ($key in @('control_program','control_expected_exit','control_expected_output_hash')) { try { Get-Value $PromptFile $key $true | Out-Null } catch { return @{ Rc = 0; Class = 'none'; Reason = 'reproduction-control-missing'; Engine = 'none'; Verdict = 'CLEAN'; Severity = 'NONE'; Exit = 0; Session = 'none'; ReproductionStatus = 'UNVERIFIED'; HypothesisHash = $script:ReproHypothesisHash; PrimaryHash = 'MISSING'; ControlHash = 'MISSING' } } }
    $script:ReproControlProgram = Get-Value $PromptFile 'control_program' $true; $script:ReproControlExpectedExit = Get-Value $PromptFile 'control_expected_exit' $true; $script:ReproControlExpectedHash = Get-Value $PromptFile 'control_expected_output_hash' $true
    if ($script:ReproControlProgram -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($script:ReproControlProgram) -or $script:ReproControlExpectedExit -notmatch '^\d+$' -or $script:ReproControlExpectedHash -notmatch '^[0-9a-fA-F]{64}$') { return @{ Rc = 2; Class = 'authorization'; Reason = 'reproduction-control-invalid'; Engine = 'none'; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127; Session = 'none' } }
    $script:ReproControlArguments = @(Get-Content -LiteralPath $PromptFile | Where-Object { $_ -like 'control_arg=*' } | ForEach-Object { $_.Substring(12) })
    return Invoke-ReproductionPair $Selected
}
function Get-CapabilityRow([string]$Selected, [string]$RequestedRole) {
    $capability = if ($RequestedRole -eq 'council-advisor') { 'model-council-advisor' } elseif ($RequestedRole -eq 'council-chair') { 'model-council-chair' } else { 'model-certifying' }
    return Get-Content -LiteralPath $Capabilities | Where-Object { $_ -like "$capability`t$Selected`t*" } | Select-Object -First 1
}

function Invoke-Engine([string]$Selected) {
    if ($env:FORGE_DISPATCH_TEST_MODE -and $env:FORGE_TEST_DISABLE_ENGINE -eq $Selected) { return @{ Rc = 1; Class = 'engine'; Reason = 'binary-unavailable'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127 } }
    if ($env:FORGE_DISPATCH_TEST_MODE -and $env:FORGE_TEST_DISABLE_CAPABILITY -eq $Selected) { return @{ Rc = 1; Class = 'capability'; Reason = 'missing-required-capability'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127 } }
    $command = Get-Command $Selected -ErrorAction SilentlyContinue
    if (-not $command) { return @{ Rc = 1; Class = 'engine'; Reason = 'binary-unavailable'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127 } }
    if (-not $env:FORGE_DISPATCH_TEST_MODE) {
        $help = (& $command.Source --help 2>&1) -join "`n"
        if ($Selected -eq 'codex') { $help += "`n" + ((& $command.Source exec --help 2>&1) -join "`n") }
        $required = if ($Selected -eq 'claude') { @('-p', '--safe-mode', '--strict-mcp-config', '--mcp-config', '--settings', '--setting-sources', '--tools', '--permission-mode', '--add-dir', '--model', '--effort', '--output-format') } else { @('-a', 'exec', '--sandbox', '--add-dir', '--ignore-user-config', '--ignore-rules', '--disable', '--output-last-message', '-C', '-m', '-c') }
        if ($Conversation -eq 'ephemeral') { $required += $(if ($Selected -eq 'claude') { '--no-session-persistence' } else { '--ephemeral' }) }
        elseif ($Conversation -eq 'new') { $required += $(if ($Selected -eq 'claude') { '--session-id' } else { '--json' }) }
        else { $required += $(if ($Selected -eq 'claude') { '--resume' } else { @('resume', '--json') }) }
        $missing = @($required | Where-Object { $help -notlike "*$_*" })
        if ($missing.Count -gt 0) { return @{ Rc = 1; Class = 'capability'; Reason = 'missing-capability-' + ($missing -join ','); Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127 } }
    }
    $row = Get-CapabilityRow $Selected $Role
    if (-not $row) { return @{ Rc = 1; Class = 'capability'; Reason = 'unqualified-role'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127 } }
    $columns = $row -split "`t"
    $provider = $columns[5]; $model = $columns[6]; $effort = $columns[7]
    $scratch = Join-Path ([IO.Path]::GetTempPath()) ("forge-dispatch-$Selected-" + [Guid]::NewGuid().ToString('N'))
    $renderArguments = @{ Engine = $Selected; Profile = $Profile; OutputDir = $scratch }
    if ($ReadOnlyServer) { $renderArguments.ReadOnlyServer = $ReadOnlyServer }
    $configReceipt = Join-Path $scratch 'config.receipt'
    & $Renderer @renderArguments | Set-Content -LiteralPath $configReceipt -Encoding Ascii
    $configHash = Get-Value $configReceipt 'config_hash' $true
    $computedConfigHash = "$(Get-ShaFile (Join-Path $scratch 'claude-settings.json')):$(Get-ShaFile (Join-Path $scratch 'mcp.json')):$(Get-ShaFile (Join-Path $scratch 'codex-overrides.tsv'))"
    if ($configHash -cne $computedConfigHash) { return @{ Rc = 1; Class = 'capability'; Reason = 'config-receipt-hash-mismatch'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127 } }
    $canaryHash = Get-ShaText "$Selected|$configHash|$QualificationRevision|fresh-isolation-v1"
    $seatHash = Get-ShaText "$Selected|$Role|$SeatId|$QuestionHash"
    if ($Conversation -eq 'resume') {
        if ($configHash -cne (Get-Value $SessionMeta 'config_hash' $true)) { return @{ Rc = 2; Class = 'capability'; Reason = 'resume-config-mismatch'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127 } }
        if ($canaryHash -cne $SessionCanaryHash -or $seatHash -cne $SessionSeatHash) { return @{ Rc = 2; Class = 'invariant'; Reason = 'resume-seat-or-canary-mismatch'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127 } }
    }
    if ($Conversation -eq 'resume') { $snapshot = $SessionSnapshot }
    else {
        $attemptFingerprint = Join-Path $reviews "$invocationId.attempt-$Selected-$([Guid]::NewGuid().ToString('N')).candidate"
        & $Fingerprint -Mode capture -Artifact $Artifact -WorkflowBaseSha $WorkflowBaseSha -WorkflowBaseRef $WorkflowBaseRef -Output $attemptFingerprint
        if ($LASTEXITCODE -ne 0 -or (Get-Value $attemptFingerprint 'artifact_hash') -cne $ArtifactHash -or (Get-Value $attemptFingerprint 'worktree_identity') -cne $worktreeIdentity) { return @{ Rc = 2; Class = 'artifact'; Reason = 'candidate-capture-failed'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127 } }
        $snapshot = Get-Value $attemptFingerprint 'snapshot_path'
    }
    $snapshotBefore = Get-SnapshotState $snapshot
    if ($Conversation -eq 'resume' -and (Get-SnapshotStateHash $snapshotBefore) -cne $SessionSnapshotHash) { return @{ Rc = 2; Class = 'artifact'; Reason = 'resume-snapshot-mismatch'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127 } }
    $primary = Join-Path $scratch 'primary'
    $canaryBody = "forge_canary_hash=$canaryHash`nforge_config_hash=$configHash`nforge_qualification_revision=$QualificationRevision`n"
    [IO.File]::WriteAllText((Join-Path $primary '.forge-dispatch-canary'), $canaryBody, $Utf8)
    if ($script:ReproMode) {
        $reproExecutable = [IO.Path]::GetFullPath((Join-Path $snapshot $script:ReproProgram)); $snapshotPrefix = $snapshot.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
        if (-not $reproExecutable.StartsWith($snapshotPrefix, [StringComparison]::OrdinalIgnoreCase)) { return @{ Rc = 2; Class = 'authorization'; Reason = 'reproduction-program-escape'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127 } }
        $reproItem = Get-Item -LiteralPath $reproExecutable -Force
        if ($reproItem.PSIsContainer -or (($reproItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { return @{ Rc = 2; Class = 'artifact'; Reason = 'reproduction-program-not-regular'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127 } }
        $script:ReproRunner = Join-Path $primary '.forge-reproduction-runner.ps1'; $reproStdout = Join-Path $primary '.forge-reproduction.stdout'; $reproStderr = Join-Path $primary '.forge-reproduction.stderr'; $reproExit = Join-Path $primary '.forge-reproduction.exit'
        $argumentLiterals = @($script:ReproArguments | ForEach-Object { ConvertTo-PowerShellLiteral ([string]$_) }) -join ','
        $runnerLines = @(
            '$ErrorActionPreference=''Continue'''
            '$utf8=New-Object Text.UTF8Encoding($false)'
            '$env:FORGE_REPRO_NO_NETWORK=''1'''
            ('$arguments=@(' + $argumentLiterals + ')')
            ('Push-Location ' + (ConvertTo-PowerShellLiteral $snapshot))
            ('try { $captured=@(& ' + (ConvertTo-PowerShellLiteral $reproExecutable) + ' @arguments 2> ' + (ConvertTo-PowerShellLiteral $reproStderr) + '); $code=$LASTEXITCODE; if ($null -eq $code) { $code=0 } } finally { Pop-Location }')
            '$text=$captured -join [Environment]::NewLine; if ($captured.Count -gt 0) { $text += [Environment]::NewLine }'
            ('[IO.File]::WriteAllText(' + (ConvertTo-PowerShellLiteral $reproStdout) + ', $text, $utf8)')
            ('[IO.File]::WriteAllText(' + (ConvertTo-PowerShellLiteral $reproExit) + ', [string]$code + "`n", $utf8)')
            'exit 0'
        )
        $runnerBody = ($runnerLines -join "`n") + "`n"
        [IO.File]::WriteAllText($script:ReproRunner, $runnerBody, $Utf8)
    }
    $prompt = "You are a fresh independent $Selected reviewer. Your cwd is a clean primary. First read .forge-dispatch-canary and copy its exact observation lines into the result. Logical project root: $snapshot. Review immutable scope $WorkflowBaseSha..candidate. Ambient instructions, hooks, plugins, skills, and write-capable MCP are absent. Return only the Forge line envelope.`n" + [IO.File]::ReadAllText($PromptFile)
    if ($script:ReproMode) { $prompt = "This is the dispatcher-owned $($script:ReproCheckKind) reproduction check. Under the already-qualified no-network workspace boundary, execute powershell.exe -NoProfile -ExecutionPolicy Bypass -File $($script:ReproRunner) exactly once. Do not edit it or synthesize its stdout/exit files.`n" + $prompt }
    $bound = Join-Path $scratch 'bound.out'
    $environment = @{ FORGE_DISPATCH_MODE = $(if ($Profile -eq 'investigate') { 'investigate' } else { 'review' }); FORGE_CANDIDATE_ROOT = $snapshot; FORGE_REPRO_RUNNER = $(if ($script:ReproMode) { $script:ReproRunner } else { '' }); FORGE_DISPATCH_SESSION_ID = $(if ($Conversation -eq 'new') { $SessionProvisionalId } else { $SessionId }); FORGE_DISPATCH_SEAT_HASH = $seatHash; FORGE_DISPATCH_CONFIG_HASH = $configHash; FORGE_DISPATCH_CANARY_HASH = $canaryHash; FORGE_DISPATCH_QUALIFICATION_REVISION = $QualificationRevision }
    foreach ($name in @('FORGE_DISPATCH_TEST_MODE', 'FORGE_TEST_DISABLE_ENGINE', 'FAKE_CLAUDE_BEHAVIOR', 'FAKE_CODEX_BEHAVIOR', 'FAKE_CLAUDE_LOG', 'FAKE_CLAUDE_ARGV_LOG', 'FAKE_CODEX_LOG', 'FAKE_CHILD_PID_FILE')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $environment[$name] = $value }
    }
    if ($Selected -eq 'claude') {
        $tools = if ($script:ReproMode) { 'Read,Write,Edit,Bash' } elseif ($Profile -eq 'investigate') { 'Read,Write,Edit,Bash,WebSearch,WebFetch' } else { 'Read,Grep,Glob' }
        $userProfile = [Environment]::GetFolderPath('UserProfile')
        if (-not $userProfile) { $userProfile = $env:USERPROFILE }
        $environment.HOME = $userProfile
        $environment.USERPROFILE = $userProfile
        $environment.USERNAME = $(if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName })
        if ($env:USER) { $environment.USER = $env:USER }
        if ($env:LOGNAME) { $environment.LOGNAME = $env:LOGNAME }
        $arguments = @('-p', '--safe-mode', '--strict-mcp-config', '--mcp-config', (Join-Path $scratch 'mcp.json'), '--settings', (Join-Path $scratch 'claude-settings.json'), '--setting-sources', '', '--tools', $tools, '--permission-mode', 'dontAsk', '--add-dir', $snapshot, '--model', $model, '--effort', $effort, '--output-format', 'json')
        if ($Conversation -eq 'ephemeral') { $arguments += '--no-session-persistence' }
        elseif ($Conversation -eq 'new') { $arguments += @('--session-id', $SessionProvisionalId) }
        else { $arguments += @('--resume', $SessionId) }
        $arguments += $prompt
        $process = Invoke-BoundProcess $command.Source $arguments $primary $environment $TimeoutSeconds
        Copy-Item -LiteralPath $process.Stdout -Destination $bound -Force
        $capturedSession = if ($Conversation -eq 'new') { $SessionProvisionalId } elseif ($Conversation -eq 'resume') { $SessionId } else { 'none' }
    }
    else {
        $sandbox = if ($Profile -eq 'investigate') { 'workspace-write' } else { 'read-only' }
        $codexHome = if ($Conversation -eq 'ephemeral') { Join-Path $scratch 'codex-home' } else { Join-Path $SessionStore 'codex-home' }
        $environment.HOME = Join-Path $scratch 'home'
        $environment.CODEX_HOME = $codexHome
        $authPath = if ($env:FORGE_CODEX_AUTH_FILE) { $env:FORGE_CODEX_AUTH_FILE } elseif ($env:CODEX_HOME) { Join-Path $env:CODEX_HOME 'auth.json' } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex/auth.json' }
        if ($env:FORGE_CODEX_AUTH_FILE -or (Test-Path -LiteralPath $authPath)) {
            $auth = Get-Item -LiteralPath $authPath -Force
            if (($auth.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return @{ Rc = 2; Class = 'authorization'; Reason = 'invalid-codex-auth-file'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 127 } }
            New-Item -ItemType Directory -Path $codexHome -Force | Out-Null
            Copy-Item -LiteralPath $auth.FullName -Destination (Join-Path $codexHome 'auth.json')
        }
        $disabled = @('--disable', 'hooks', '--disable', 'plugins', '--disable', 'plugin_sharing', '--disable', 'apps', '--disable', 'remote_plugin', '--disable', 'in_app_browser', '--disable', 'browser_use', '--disable', 'computer_use')
        if ($Conversation -eq 'resume') {
            $arguments = @('-a', 'never', 'exec', 'resume') + $disabled + @('--ignore-user-config', '--ignore-rules', '--sandbox', $sandbox, '--json', '-m', $model, '-c', "model_reasoning_effort=$effort", '--output-last-message', $bound, $SessionId, $prompt)
        }
        else {
            $arguments = @('-a', 'never', 'exec') + $disabled + @('-C', $primary, '--add-dir', $snapshot, '--ignore-user-config', '--ignore-rules', '--sandbox', $sandbox, '-m', $model, '-c', "model_reasoning_effort=$effort", '--output-last-message', $bound)
            if ($ReadOnlyServer -eq 'context7') { $arguments += @('-c', 'mcp_servers.context7.url=https://mcp.context7.com/mcp', '-c', 'mcp_servers.context7.read_only=true') }
            if ($Conversation -eq 'ephemeral') { $arguments += '--ephemeral' } else { $arguments += '--json' }
            $arguments += $prompt
        }
        try { $process = Invoke-BoundProcess $command.Source $arguments $primary $environment $TimeoutSeconds }
        finally { Remove-Item -LiteralPath (Join-Path $codexHome 'auth.json') -Force -ErrorAction SilentlyContinue }
        $capturedSession = 'none'
        if ($Conversation -eq 'new') {
            foreach ($line in Get-Content -LiteralPath $process.Stdout) {
                try { $event = $line | ConvertFrom-Json; if ($event.type -eq 'thread.started') { $capturedSession = [string]$event.thread_id; break } } catch {}
            }
            if (-not (Test-SafeSessionId $capturedSession)) { return @{ Rc = 1; Class = 'capability'; Reason = 'missing-thread-id'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = $process.Exit } }
        }
        elseif ($Conversation -eq 'resume') { $capturedSession = $SessionId }
    }
    if ($process.Exit -eq 124) { return @{ Rc = 1; Class = 'engine'; Reason = 'timeout'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 124 } }
    if ($process.Exit -ne 0) { return @{ Rc = 1; Class = 'engine'; Reason = "process-exit-$($process.Exit)"; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = $process.Exit } }
    if ($script:ReproMode) {
        foreach ($path in @($reproStdout, $reproStderr, $reproExit)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return @{ Rc = 1; Class = 'capability'; Reason = 'reproduction-runner-result-missing'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 0 } }
        }
        $reproExitValue = ([IO.File]::ReadAllText($reproExit)).Trim(); if ($reproExitValue -notmatch '^\d+$') { return @{ Rc = 1; Class = 'capability'; Reason = 'reproduction-runner-exit-invalid'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 0 } }
    }
    $actualProvider = 'UNOBSERVABLE'; $actualModel = 'UNOBSERVABLE'
    if ($Selected -eq 'claude' -and (Get-Item -LiteralPath $bound).Length -gt 0 -and [IO.File]::ReadAllText($bound).TrimStart().StartsWith('{')) {
        try {
            $wrapper = [IO.File]::ReadAllText($bound) | ConvertFrom-Json
            if ($wrapper.result) { [IO.File]::WriteAllText($bound, [string]$wrapper.result + "`n", $Utf8) }
            $modelProperty = @($wrapper.modelUsage.PSObject.Properties)
            if ($modelProperty.Count -eq 1) { $actualProvider = [string]$wrapper.provider; $actualModel = $modelProperty[0].Name }
        } catch {}
        if ($actualProvider -eq 'UNOBSERVABLE' -or $actualModel -eq 'UNOBSERVABLE') { return @{ Rc = 1; Class = 'capability'; Reason = 'observable-identity-missing'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 0 } }
        if (-not ($actualProvider -eq $provider -and (($actualModel -eq $model) -or ($model -eq 'opus' -and $actualModel -eq 'claude-opus-4-1')))) {
            return @{ Rc = 1; Class = 'capability'; Reason = 'observable-identity-mismatch'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 0 }
        }
    }
    $envelope = Read-Envelope $bound
    if (-not $envelope.Valid) { return @{ Rc = 1; Class = 'engine'; Reason = $envelope.Reason; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 0 } }
    foreach ($observation in @(@('forge_canary_hash', $canaryHash), @('forge_config_hash', $configHash), @('forge_qualification_revision', $QualificationRevision))) {
        if ((Get-Value $bound $observation[0] $true) -cne $observation[1]) { return @{ Rc = 1; Class = 'capability'; Reason = 'isolation-canary-missing-or-mismatch'; Engine = $Selected; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = 0 } }
    }
    $rc = if ($envelope.Class -in @('engine', 'capability')) { 1 } elseif ($envelope.Class -in @('artifact', 'authorization', 'invariant')) { 2 } else { 0 }
    return @{ Rc = $rc; Class = $envelope.Class; Reason = $envelope.Reason; Engine = $Selected; Verdict = $envelope.Verdict; Severity = $envelope.Severity; Exit = 0; Output = $bound; Provider = $provider; Model = $model; Effort = $effort; ActualProvider = $actualProvider; ActualModel = $actualModel; Digest = $envelope.Digest; Schema = $envelope.Schema; ConfigHash = $configHash; CanaryHash = $canaryHash; SeatHash = $seatHash; Snapshot = $snapshot; SnapshotBefore = $snapshotBefore; Session = $capturedSession; ReproStdout = $reproStdout; ReproStderr = $reproStderr; ReproExit = $(if ($script:ReproMode) { [int]$reproExitValue } else { 0 }) }
}

try {
    if ($Mode -eq 'verify-pair') {
        foreach ($path in @($CodeSpecReceipt, $CodeQualityReceipt)) {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'BLOCKED[artifact]: two no-follow regular receipts are required' }
        }
        if ((Get-Value $CodeSpecReceipt 'role') -ne 'code-spec' -or (Get-Value $CodeQualityReceipt 'role') -ne 'code-quality' -or (Get-Value $CodeSpecReceipt 'invocation_id') -eq (Get-Value $CodeQualityReceipt 'invocation_id')) { throw 'BLOCKED[invariant]: distinct code lenses are required' }
        foreach ($key in @('artifact_hash', 'worktree_identity', 'workflow_base_sha', 'git_head')) { if ((Get-Value $CodeSpecReceipt $key) -cne (Get-Value $CodeQualityReceipt $key)) { throw "BLOCKED[artifact]: mixed candidate pair: $key" } }
        $specOutput = Get-Value $CodeSpecReceipt 'output_path' $true
        $marker = [IO.Path]::DirectorySeparatorChar + '.forge' + [IO.Path]::DirectorySeparatorChar + 'local' + [IO.Path]::DirectorySeparatorChar + 'reviews' + [IO.Path]::DirectorySeparatorChar
        $markerIndex = $specOutput.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase)
        if ($markerIndex -lt 1) { throw 'BLOCKED[invariant]: review receipt output path cannot resolve canonical state' }
        $pairState = Join-Path $specOutput.Substring(0, $markerIndex) '.forge\local\state.md'
        $pairRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $pairState))
        $reviews = Join-Path $pairRoot '.forge\local\reviews'
        $cursor = $pairRoot
        foreach ($part in @('.forge','local','reviews')) {
            $cursor = Join-Path $cursor $part; $item = Get-Item -LiteralPath $cursor -Force
            if (-not $item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'BLOCKED[invariant]: review storage ancestors must be no-follow directories' }
        }
        $currentIteration = Get-StateTableValue $pairState 'Review iteration'
        if ($currentIteration -notmatch '^[0-9]+$') { throw 'BLOCKED[invariant]: current review iteration is invalid' }
        foreach ($path in @($CodeSpecReceipt, $CodeQualityReceipt)) { if ((Get-Value $path 'review_iteration' $true) -cne $currentIteration) { throw 'BLOCKED[artifact]: review receipt iteration is stale or mixed' } }
        foreach ($path in @($CodeSpecReceipt, $CodeQualityReceipt)) {
            if ((Get-Value $path 'schema_version' $true) -cne '1' -or (Get-Value $path 'fresh_process' $true) -cne 'true' -or (Get-Value $path 'process_exit_status' $true) -cne '0' -or (Get-Value $path 'blocked_class' $true) -cne 'none' -or (Get-Value $path 'result_schema_version' $true) -cne '1') { throw 'BLOCKED[artifact]: review receipt execution schema is not certifying' }
            if ((Get-Value $path 'semantic_verdict' $true) -cne 'CLEAN' -or (Get-Value $path 'max_severity' $true) -notin @('NONE', 'P3')) { throw 'BLOCKED[artifact]: both lenses must be certifying clean' }
            $reviewOutput = Get-Value $path 'output_path' $true
            $prefix = $reviews.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
            if (-not $reviewOutput.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $reviewOutput -PathType Leaf) -or ((Get-Item -LiteralPath $reviewOutput -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'BLOCKED[artifact]: review output must be a bound no-follow regular file' }
            $relativeParent = (Split-Path -Parent $reviewOutput).Substring($reviews.Length).TrimStart('\','/')
            if ($relativeParent) { $null = Ensure-ReservedReviewDirectory $reviews $relativeParent $false }
            if ((Get-ShaFile $reviewOutput) -cne (Get-Value $path 'output_hash' $true)) { throw 'BLOCKED[artifact]: review output hash changed' }
        }
        $current = Join-Path $reviews ('.verify-pair-' + [Guid]::NewGuid().ToString('N') + '.candidate')
        try {
            Push-Location $pairRoot
            try { & $Fingerprint -Mode identity -Artifact 'git:working-tree' -WorkflowBaseSha (Get-Value $CodeSpecReceipt 'workflow_base_sha' $true) -WorkflowBaseRef (Get-Value $CodeSpecReceipt 'workflow_base_ref' $true) -Output $current *> $null }
            finally { Pop-Location }
            if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: current candidate capture failed' }
            foreach ($path in @($CodeSpecReceipt, $CodeQualityReceipt)) { foreach ($key in @('artifact_hash','worktree_identity','workflow_base_sha','git_head')) { if ((Get-Value $path $key $true) -cne (Get-Value $current $key $true)) { throw "BLOCKED[artifact]: review pair is stale: $key" } } }
        }
        finally { Remove-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue }
        Write-Output 'CLEAN: distinct code-spec and code-quality receipts certify one candidate'
        exit 0
    }
    if ($TimeoutSeconds -lt 1 -or -not (Test-Path -LiteralPath $PromptFile -PathType Leaf)) { throw 'BLOCKED[invariant]: valid timeout and prompt are required' }
    if ($PromptFile.Contains("`n") -or $PromptFile.Contains("`r") -or $WorkflowBaseRef.Contains("`n") -or $WorkflowBaseRef.Contains("`r")) { throw 'BLOCKED[invariant]: dispatcher scalar contains a newline' }
    $promptItem = Get-Item -LiteralPath $PromptFile -Force
    if (($promptItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'BLOCKED[artifact]: linked prompt rejected' }
    if (($Role -in @('investigation','investigation-repro')) -and $Profile -ne 'investigate') { throw 'BLOCKED[authorization]: investigation roles require investigate profile' }
    if (($Role -notin @('investigation','investigation-repro')) -and $Profile -ne 'review') { throw 'BLOCKED[authorization]: only investigation roles may use investigate profile' }
    if ($Conversation -ne 'ephemeral' -and $Role -ne 'council-advisor') { throw 'BLOCKED[capability]: only council-advisor supports multi-turn transport' }
    if ($Conversation -ne 'ephemeral' -and $FallbackPolicy -ne 'none') { throw 'BLOCKED[capability]: multi-turn council transport forbids per-seat fallback' }
    if ($Conversation -eq 'resume' -and -not (Test-SafeSessionId $SessionId)) { throw 'BLOCKED[invariant]: exact safe session id is required' }
    $root = (Resolve-Path (& git rev-parse --show-toplevel)).Path
    $reviews = Join-Path $root '.forge/local/reviews'
    $reviewIteration = 'none'
    if ($Role -in @('code-spec','code-quality')) {
        $reviewIteration = Get-StateTableValue (Join-Path $root '.forge\local\state.md') 'Review iteration'
        if ($reviewIteration -notmatch '^[0-9]+$') { throw 'BLOCKED[invariant]: code review requires a numeric current Review iteration' }
    }
    $Output = Reserve-OwnedReviewPath $Output 'review output' $root $reviews
    if ($Conversation -eq 'new') { $SessionIdOutput = Reserve-OwnedReviewPath $SessionIdOutput 'session id output' $root $reviews }
    if ($Role -in @('council-advisor','council-chair')) {
        if (-not (Test-SafeSessionId $SeatId)) { throw 'BLOCKED[invariant]: council roles require a safe SeatId' }
        $questionRows = @(Get-Content -LiteralPath $PromptFile | Where-Object { $_ -like 'question_hash=*' }); if ($questionRows.Count -ne 1) { throw 'BLOCKED[invariant]: council prompt requires exactly one question_hash' }
        $QuestionHash = $questionRows[0].Substring(14); if ($QuestionHash -notmatch '^[0-9a-fA-F]{64}$') { throw 'BLOCKED[invariant]: council question_hash must be sha256' }
    }
    else { if ($SeatId) { throw 'BLOCKED[invariant]: SeatId is reserved for council roles' }; $QuestionHash = Get-ShaFile $PromptFile; $SeatId = $Role }
    if ((Get-Content -LiteralPath $PromptFile) -contains 'requires_read_only_channel=true' -and -not $ReadOnlyServer) { throw 'BLOCKED[authorization]: required read-only investigation channel was not selected' }
    $invocationId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + "-$PID-" + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $activeHost = (& $HostContext -Mode verify)
    if ($LASTEXITCODE -ne 0 -or -not $activeHost) { throw 'BLOCKED[invariant]: host context mismatch' }
    $contextHash = Get-Value $env:FORGE_HOST_CONTEXT_FILE 'receipt_hash' $true
    $first = if ($Engine -eq 'auto') { if ($activeHost -eq 'claude') { 'codex' } else { 'claude' } } else { $Engine }
    $second = if ($first -eq 'claude') { 'codex' } else { 'claude' }
    $FingerprintReceipt = Join-Path $reviews "$invocationId.candidate"
    & $Fingerprint -Mode identity -Artifact $Artifact -WorkflowBaseSha $WorkflowBaseSha -WorkflowBaseRef $WorkflowBaseRef -Output $FingerprintReceipt
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: candidate capture failed' }
    $ArtifactHash = Get-Value $FingerprintReceipt 'artifact_hash'
    $worktreeIdentity = Get-Value $FingerprintReceipt 'worktree_identity'
    $PromptHash = Get-ShaFile $PromptFile
    $QualificationRevision = Get-ShaFile $Capabilities
    $SessionMeta = ''; $SessionStore = ''; $SessionSnapshot = ''; $SessionSnapshotHash = ''; $SessionCanaryHash = ''; $SessionSeatHash = ''; $SessionProvisionalId = ''
    if ($Conversation -eq 'new') {
        $SessionProvisionalId = [Guid]::NewGuid().ToString()
        $SessionStore = Ensure-ReservedReviewDirectory $reviews "session-stores/$invocationId" $true
        $null = Ensure-ReservedReviewDirectory $reviews "session-stores/$invocationId/home" $true
        $null = Ensure-ReservedReviewDirectory $reviews "session-stores/$invocationId/codex-home" $true
    }
    elseif ($Conversation -eq 'resume') {
        $null = Ensure-ReservedReviewDirectory $reviews 'sessions' $false
        $SessionMeta = Join-Path $reviews "sessions/$SessionId.meta"
        Assert-NoFollowSessionMetadata $SessionMeta
        if ((Get-Value $SessionMeta 'completed' $true) -ne 'false' -or (Get-Value $SessionMeta 'session_id' $true) -cne $SessionId -or (Get-Value $SessionMeta 'engine' $true) -cne $first -or (Get-Value $SessionMeta 'role' $true) -cne $Role -or (Get-Value $SessionMeta 'seat_id' $true) -cne $SeatId -or (Get-Value $SessionMeta 'question_hash' $true) -cne $QuestionHash -or (Get-Value $SessionMeta 'active_host' $true) -cne $activeHost -or (Get-Value $SessionMeta 'context_hash' $true) -cne $contextHash -or (Get-Value $SessionMeta 'artifact_hash' $true) -cne $ArtifactHash -or (Get-Value $SessionMeta 'worktree_identity' $true) -cne $worktreeIdentity -or (Get-Value $SessionMeta 'qualification_revision' $true) -cne $QualificationRevision) { throw 'BLOCKED[invariant]: stale, cross-seat, or cross-candidate council resume' }
        $storeId = Get-Value $SessionMeta 'store_id' $true
        if (-not (Test-SafeSessionId $storeId)) { throw 'BLOCKED[invariant]: unsafe council session store id' }
        $SessionStore = Ensure-ReservedReviewDirectory $reviews "session-stores/$storeId" $false
        $SessionSnapshot = Get-Value $SessionMeta 'snapshot_path' $true
        $SessionSnapshotHash = Get-Value $SessionMeta 'snapshot_manifest_hash' $true
        $SessionCanaryHash = Get-Value $SessionMeta 'canary_hash' $true
        $SessionSeatHash = Get-Value $SessionMeta 'seat_hash' $true
        if (-not (Test-Path -LiteralPath $SessionStore -PathType Container) -or -not (Test-Path -LiteralPath $SessionSnapshot -PathType Container)) { throw 'BLOCKED[invariant]: bound council session store or snapshot is unavailable' }
    }
    $attempted = New-Object System.Collections.Generic.List[string]
    $fallback = $false; $fallbackReason = 'none'; $script:ReproMode = $Role -eq 'investigation-repro'
    if ($Role -eq 'investigation-repro') {
        $script:ReproProtectedStateHash = Get-ShaFile (Join-Path $root '.forge/local/state.md'); $script:ReproProtectedAuthFile = ''; $script:ReproProtectedAuthHash = ''
        $reproAuth = if ($env:FORGE_CODEX_AUTH_FILE) { $env:FORGE_CODEX_AUTH_FILE } elseif ($env:CODEX_HOME) { Join-Path $env:CODEX_HOME 'auth.json' } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex/auth.json' }
        if (Test-Path -LiteralPath $reproAuth) { $reproAuthItem = Get-Item -LiteralPath $reproAuth -Force; if ($reproAuthItem.PSIsContainer -or (($reproAuthItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'BLOCKED[authorization]: protected reproduction auth must be a no-follow regular file' }; $script:ReproProtectedAuthFile = $reproAuthItem.FullName; $script:ReproProtectedAuthHash = Get-ShaFile $reproAuthItem.FullName }
        $attempted.Add($first) | Out-Null; $result = Invoke-IndependentReproduction $first
        if ($result.Engine -eq 'none') { $attempted.Clear(); $first = 'none' }
        elseif ($result.Rc -eq 1 -and $FallbackPolicy -eq 'automatic') {
            $fallback = $true; $fallbackReason = $result.Reason
            Write-Output "Reproduction boundary $first unavailable ($fallbackReason); visible fallback to fresh $second boundaries."
            $attempted.Add($second) | Out-Null; $result = Invoke-IndependentReproduction $second
        }
        $reproductionOutput = Join-Path $reviews "$invocationId.reproduction-result"
        $reproductionBody = "schema_version=1`nverdict=$($result.Verdict)`nmax_severity=NONE`nblocked_class=$($result.Class)`nreproduction_status=$(if($result.ReproductionStatus){$result.ReproductionStatus}else{'UNVERIFIED'})`nhypothesis_hash=$(if($result.HypothesisHash){$result.HypothesisHash}else{'MISSING'})`nprimary_check_hash=$(if($result.PrimaryHash){$result.PrimaryHash}else{'MISSING'})`ncontrol_hash=$(if($result.ControlHash){$result.ControlHash}else{'MISSING'})`n"
        [IO.File]::WriteAllText($reproductionOutput, $reproductionBody, $Utf8); $result.Output = $reproductionOutput
    }
    else {
        $attempted.Add($first) | Out-Null; $result = Invoke-Engine $first
        if ($result.Rc -eq 1 -and $FallbackPolicy -eq 'automatic') {
            $fallback = $true; $fallbackReason = $result.Reason
            Write-Output "Reviewer $first unavailable ($fallbackReason); visible fallback to fresh $second."
            $attempted.Add($second) | Out-Null
            $result = Invoke-Engine $second
        }
    }
    $recheck = Join-Path $reviews "$invocationId.recheck"
    & $Fingerprint -Mode identity -Artifact $Artifact -WorkflowBaseSha $WorkflowBaseSha -WorkflowBaseRef $WorkflowBaseRef -Output $recheck
    if ($LASTEXITCODE -ne 0 -or (Get-Value $recheck 'artifact_hash') -cne $ArtifactHash) { $result = @{ Rc = 2; Class = 'artifact'; Reason = 'artifact-mutated'; Engine = $result.Engine; Verdict = 'BLOCKED'; Severity = 'NONE'; Exit = $result.Exit; Session = 'none' } }
    $investigationReplay = 'NONE'; $reproductionStatus = 'UNVERIFIED'; $hypothesisHash = 'MISSING'; $primaryHash = 'MISSING'; $controlHash = 'MISSING'
    if ($result.Rc -eq 0 -and $Role -eq 'investigation') {
        try { $investigationReplay = Copy-DeclaredInvestigation $result.Output $result.Snapshot $result.SnapshotBefore $root }
        catch { $result.Rc = 2; $result.Class = if ($_.Exception.Message -like '*authorization*') { 'authorization' } else { 'artifact' }; $result.Reason = 'investigation-replay-rejected'; $result.Verdict = 'BLOCKED'; $result.Severity = 'NONE' }
    }
    if ($Role -eq 'investigation-repro') {
        $hypothesisHash = if ($result.HypothesisHash) { $result.HypothesisHash } else { 'MISSING' }; $primaryHash = if ($result.PrimaryHash) { $result.PrimaryHash } else { 'MISSING' }; $controlHash = if ($result.ControlHash) { $result.ControlHash } else { 'MISSING' }
        if ($result.ReproductionStatus -in @('REPRODUCED', 'FAILED', 'PARTIAL', 'UNVERIFIED')) { $reproductionStatus = $result.ReproductionStatus }
    }
    if ($result.Rc -eq 0 -and $Conversation -eq 'new') {
        if (-not (Test-SafeSessionId $result.Session)) { throw 'BLOCKED[invariant]: engine emitted unsafe session id' }
        $sessionDirectory = Ensure-ReservedReviewDirectory $reviews 'sessions' $true
        $SessionMeta = Join-Path $sessionDirectory "$($result.Session).meta"
        if (Test-Path -LiteralPath $SessionMeta) { throw 'BLOCKED[invariant]: session metadata already exists' }
        $meta = "schema_version=1`ncompleted=false`nsession_id=$($result.Session)`nengine=$($result.Engine)`nrole=$Role`nseat_id=$SeatId`nquestion_hash=$QuestionHash`nactive_host=$activeHost`ncontext_hash=$contextHash`nartifact_hash=$ArtifactHash`nworktree_identity=$worktreeIdentity`nturn_prompt_hash=$PromptHash`nconfig_hash=$($result.ConfigHash)`ncanary_hash=$($result.CanaryHash)`nseat_hash=$($result.SeatHash)`nqualification_revision=$QualificationRevision`nstore_id=$invocationId`nsnapshot_path=$($result.Snapshot)`nsnapshot_manifest_hash=$(Get-SnapshotStateHash $result.SnapshotBefore)`n"
        [IO.File]::WriteAllText($SessionMeta, $meta, $Utf8)
        $sessionSource = Join-Path $sessionDirectory "$($result.Session).session-id.$PID"
        [IO.File]::WriteAllText($sessionSource, "$($result.Session)`n", $Utf8)
        Publish-OwnedReviewFile $sessionSource $SessionIdOutput 'session id output' $reviews
        Remove-Item -LiteralPath $sessionSource -Force -ErrorAction SilentlyContinue
    }
    if ($result.Output -and (Test-Path -LiteralPath $result.Output -PathType Leaf)) { Publish-OwnedReviewFile $result.Output $Output 'review output' $reviews }
    if ($result.Rc -eq 0 -and $Conversation -eq 'resume') {
        Assert-NoFollowSessionMetadata $SessionMeta
        $updated = (Get-Content -LiteralPath $SessionMeta | ForEach-Object { if ($_ -eq 'completed=false') { 'completed=true' } else { $_ } }) -join "`n"
        Assert-NoFollowSessionMetadata $SessionMeta
        [IO.File]::WriteAllText($SessionMeta, $updated + "`n", $Utf8)
        $null = Ensure-ReservedReviewDirectory $reviews "session-stores/$(Split-Path -Leaf $SessionStore)" $false
        Remove-Item -LiteralPath $SessionStore -Recurse -Force
    }
    $receipt = Join-Path $reviews "$invocationId.receipt"
    $outputHash = Get-ShaFile $Output
    $configHash = if ($result.ConfigHash) { $result.ConfigHash } else { 'MISSING' }
    $body = "schema_version=1`ninvocation_id=$invocationId`ntimestamp=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))`nmain_host=$activeHost`nrequested_engine=$Engine`nfirst_attempted_engine=$first`nactual_engine=$($result.Engine)`nfallback=$($fallback.ToString().ToLowerInvariant())`nfallback_reason=$fallbackReason`nattempted_engines=$($attempted -join ',')`nrole=$Role`nprofile=$Profile`nreview_iteration=$reviewIteration`nfresh_process=true`nconversation=$Conversation`nsession_id=$($result.Session)`nartifact_kind=$(Get-Value $FingerprintReceipt 'artifact_kind')`nartifact_identity=$ArtifactHash`nartifact_hash=$ArtifactHash`nworktree_identity=$worktreeIdentity`ngit_head=$(Get-Value $FingerprintReceipt 'git_head')`nprompt_hash=$PromptHash`nworkflow_base_ref=$WorkflowBaseRef`nworkflow_base_sha=$(Get-Value $FingerprintReceipt 'workflow_base_sha')`noutput_path=$Output`noutput_hash=$outputHash`nprocess_exit_status=$($result.Exit)`nsemantic_verdict=$($result.Verdict)`nmax_severity=$($result.Severity)`nfindings_digest=$($result.Digest)`nresult_schema_version=$($result.Schema)`nrequested_provider=$($result.Provider)`nrequested_model=$($result.Model)`nrequested_reasoning_effort=$($result.Effort)`nbound_provider=$($result.Provider)`nbound_model=$($result.Model)`nbound_reasoning_effort=$($result.Effort)`nactual_provider=$(if($result.ActualProvider){$result.ActualProvider}else{'UNOBSERVABLE'})`nactual_model=$(if($result.ActualModel){$result.ActualModel}else{'UNOBSERVABLE'})`nactual_reasoning_effort=UNOBSERVABLE`ninvocation_config_hash=$(Get-ShaText (($attempted -join ',') + '|' + $configHash + '|' + $ArtifactHash + '|' + $PromptHash))`nmodel_qualification_revision=$QualificationRevision`nblocked_class=$($result.Class)`ninvestigation_replay=$investigationReplay`nreproduction_status=$reproductionStatus`nhypothesis_hash=$hypothesisHash`nprimary_check_hash=$primaryHash`ncontrol_hash=$controlHash`n"
    [IO.File]::WriteAllText($receipt, $body, $Utf8)
    Write-Output "Reviewer selection: main=$activeHost requested=$Engine actual=$($result.Engine) fallback=$fallback role=$Role receipt=$receipt"
    if ($result.Rc -ne 0) { exit 2 }
    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
}
