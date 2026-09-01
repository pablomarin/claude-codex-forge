# .claude/hooks/check-state-updated.ps1
# This hook runs when Claude is about to stop responding.
#
# THREE CONCERNS -- only ONE blocks:
#
#   1. state.md missing breadcrumb (advisory, stderr only, exit 0).
#      Fires only when legacy CONTINUITY.md is present (signals upgraded
#      install that still needs full-refresh reconciliation). Suppressed otherwise to
#      avoid spamming every Stop event.
#
#   2. Workflow reminder (advisory, stderr only, exit 0).
#      Reads .claude/local/state.md ## Workflow table; emits
#      "WORKFLOW: <cmd> | Phase: <n> | Next: <step>" so the model always
#      sees current phase even when no issues fire.
#
#   3. CHANGELOG threshold gate (BLOCKS via exit 2).
#      If 4+ files changed on branch (committed + uncommitted) but
#      docs/CHANGELOG.md was never modified, hook blocks the stop with
#      a stderr message. This is the ONLY blocking concern.
#
# Uses exit code 2 + stderr to block (avoids JSON stdout parsing issues).
#
# Requirements: PowerShell 5.1+, git

# Read the hook input from stdin
$jsonInput = [Console]::In.ReadToEnd()
function Exit-ForgeAllow { if ($data.host -eq "codex") { Write-Output "{}" }; exit 0 }

# Parse JSON input
try {
    $data = $jsonInput | ConvertFrom-Json
} catch {
    # If JSON parsing fails, allow stop
    Exit-ForgeAllow
}

# ---------------------------------------------------------------------------
# Worktree CWD fix (v5.32) — CC's Stop hook runs with CWD=$CLAUDE_PROJECT_DIR
# (the parent project in worktree sessions), but the user's actual session
# CWD lives in the stdin JSON. cd there so relative state.md reads and git
# ops target the worktree, not the main repo.
# Fallback: git rev-parse --show-toplevel → current CWD.
# ---------------------------------------------------------------------------
$hookCwd = ""
if ($data -and $data.PSObject.Properties['cwd']) {
    $hookCwd = [string]$data.cwd
}
if ($hookCwd -and (Test-Path -LiteralPath $hookCwd -PathType Container)) {
    # Normalize to repo/worktree root in case stdin.cwd is a subdirectory.
    $normalized = (& git -C "$hookCwd" rev-parse --show-toplevel 2>$null)
    if ($normalized -and (Test-Path -LiteralPath $normalized -PathType Container)) {
        Set-Location -LiteralPath $normalized
    } else {
        Set-Location -LiteralPath $hookCwd
    }
} else {
    $toplevel = (& git rev-parse --show-toplevel 2>$null)
    if ($toplevel -and (Test-Path -LiteralPath $toplevel -PathType Container)) {
        Set-Location -LiteralPath $toplevel
    }
}

$hookDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateHelper = Join-Path $hookDir "lib\state-path.ps1"
if (-not (Test-Path -LiteralPath $stateHelper)) {
    $stateHelper = Join-Path (Get-Location) "hooks\lib\state-path.ps1"
}
$stateMd = ""
if (Test-Path -LiteralPath $stateHelper) {
    try {
        . $stateHelper
        $stateMd = Get-ForgeStatePath -Root (Get-Location).Path -Mode Read
    } catch {
        $canonicalSurface = $false
        foreach ($surface in @(".forge\version", ".forge\local", ".forge\local\state.md")) {
            if (Get-Item -LiteralPath (Join-Path (Get-Location).Path $surface) -Force -ErrorAction SilentlyContinue) { $canonicalSurface = $true; break }
        }
        $forgeRootItem = Get-Item -LiteralPath (Join-Path (Get-Location).Path ".forge") -Force -ErrorAction SilentlyContinue
        if ($forgeRootItem -and ($forgeRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $canonicalSurface = $true }
        if ($canonicalSurface) {
            [Console]::Error.WriteLine([string]$_.Exception.Message)
            [Console]::Error.WriteLine("FORGE_STATE_INVALID: canonical v6 state could not be resolved")
            exit 2
        }
        $stateMd = ""
    }
}
$stateLocalDir = ".forge/local"
if (($stateMd -replace '\\', '/') -match '/\.claude/local/state\.md$') { $stateLocalDir = ".claude/local" }

# Stop is self-sufficient when the side channel is missing or older than state.
if ($stateLocalDir -eq ".forge/local" -and (Test-Path -LiteralPath $stateMd -PathType Leaf)) {
    $fp = Join-Path $stateLocalDir "forge-goal-last-fingerprint"
    $needsEvidence = -not (Test-Path -LiteralPath $fp -PathType Leaf)
    if (-not $needsEvidence) { $needsEvidence = (Get-Item -LiteralPath $stateMd).LastWriteTimeUtc -gt (Get-Item -LiteralPath $fp).LastWriteTimeUtc }
    $builder = Join-Path $hookDir "build-evidence.ps1"
    if ($needsEvidence -and (Test-Path -LiteralPath $builder -PathType Leaf)) { $jsonInput | & $builder 2>&1 | ForEach-Object { [Console]::Error.WriteLine($_) } }

    $candidateRows = @()
    $receiptStateRaw = (Get-Content -LiteralPath $stateMd -Raw) -replace "`r", ""
    foreach ($line in @($receiptStateRaw -split "`n")) {
        $parts = $line -split '\|'
        if ($parts.Count -ge 4 -and $parts[1].Trim() -ceq 'Candidate receipt') { $candidateRows += $parts[2].Trim() }
    }
    $candidateReceipt = if ($candidateRows.Count -eq 1) { [string]$candidateRows[0] } else { "" }
    if ($candidateReceipt -and -not $candidateReceipt.Contains('<')) {
        $verificationReceipt = Join-Path $hookDir 'lib\verification-receipt.ps1'
        if (-not (Test-Path -LiteralPath $verificationReceipt)) { $verificationReceipt = Join-Path (Get-Location) 'hooks\lib\verification-receipt.ps1' }
        $receiptStatus = 2
        if (Test-Path -LiteralPath $verificationReceipt) {
            . $verificationReceipt
            $receiptResponse = Invoke-VerificationReceipt -ReceiptMode check -StatePath $stateMd
            $receiptStatus = $receiptResponse.Status
        }
        if ($receiptStatus -ne 0) {
            [Console]::Error.WriteLine('FORGE_FINAL_EVIDENCE_STALE: candidate-bound review, verify-app, and E2E receipts no longer certify the current staged-clean candidate.')
        }
    }
}

function Write-ForgeGoalTamper([string]$Reason) { [Console]::Error.WriteLine("FORGE_GOAL_AUTHORIZATION_TAMPERED: $Reason"); exit 2 }
function Get-ForgeShaText([string]$Text) {
    $sha=[Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-","").ToLowerInvariant() } finally { $sha.Dispose() }
}
function Get-ForgeGoalValue([string]$Path,[string]$Key) {
    foreach($line in @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)){if($line -match ('^'+[regex]::Escape($Key)+'=(.*)$')){return $matches[1]}}
    return ""
}
function New-ForgeNoClobber([string]$Path,[byte[]]$Bytes) {
    try { $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None); try{$stream.Write($Bytes,0,$Bytes.Length)}finally{$stream.Dispose()}; return $true } catch { return $false }
}
function Get-ForgeFileSha([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Assert-ForgePhysicalDirectory([string]$Path,[string]$Prefix) {
    if(-not (Test-Path -LiteralPath $Path -PathType Container)){Write-ForgeGoalTamper "missing ledger ancestor: $Path"}
    $item=Get-Item -LiteralPath $Path -Force
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){Write-ForgeGoalTamper "reparse-point ledger ancestor: $Path"}
    $physical=(Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $prefixPath=$Prefix.TrimEnd('\','/');$prefixWithSep=$prefixPath+[IO.Path]::DirectorySeparatorChar
    if($physical -ne $prefixPath -and -not $physical.StartsWith($prefixWithSep,[StringComparison]::OrdinalIgnoreCase)){Write-ForgeGoalTamper "ledger ancestor escapes trusted root: $Path"}
}
function Test-ForgeBytesEqual([string]$Path,[byte[]]$Bytes) {
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){return $false}
    if((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){return $false}
    return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) -ceq [Convert]::ToBase64String($Bytes)
}
function Publish-ForgeNoClobber([string]$Path,[byte[]]$Bytes,[string]$Label) {
    if(Test-Path -LiteralPath $Path){if(-not (Test-ForgeBytesEqual $Path $Bytes)){Write-ForgeGoalTamper "$Label already exists with different or invalid content"}}
    elseif(-not (New-ForgeNoClobber $Path $Bytes)){if(-not (Test-ForgeBytesEqual $Path $Bytes)){Write-ForgeGoalTamper "$Label no-clobber publication failed"}}
    if(-not (Test-ForgeBytesEqual $Path $Bytes)){Write-ForgeGoalTamper "$Label read verification failed"}
    (Get-Item -LiteralPath $Path).IsReadOnly=$true
}
function Invoke-ForgeGoalChargeTurn {
    if ($stateLocalDir -ne ".forge/local" -or -not (Test-Path -LiteralPath $stateMd -PathType Leaf)) { return }
    $rawState=(Get-Content -LiteralPath $stateMd -Raw) -replace "`r",""; $lines=$rawState -split "`n"; $inside=$false; $goal=@{}
    foreach($line in $lines){if($line -match '^## /goal session$'){$inside=$true;continue};if($inside -and $line -match '^## '){break};if($inside -and $line -match '^\|\s*([^|]+?)\s*\|\s*([^|]*?)\s*\|'){$goal[$matches[1].Trim().ToLowerInvariant()]=$matches[2].Trim()}}
    $nonce=[string]$goal["nonce"]; if(-not $nonce -or $nonce -eq "<uuid-v4-lowercase>"){return}; $objective=[string]$goal["objective_hash"]
    if($nonce -notmatch '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-4[0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$' -or $objective -notmatch '^[A-Za-z0-9._-]+$'){Write-ForgeGoalTamper "invalid active nonce or objective hash";return}
    $turnId=""; foreach($name in @("turn_id","hook_turn_id","assistant_message_id")){if($data.PSObject.Properties[$name] -and $data.$name){$turnId=[string]$data.$name;break}}
    $session=if($data.session_id){[string]$data.session_id}else{"unknown"}; $host=if($data.host){[string]$data.host}elseif($data.engine){[string]$data.engine}else{"unknown"}
    if(-not $turnId -and $data.last_assistant_message){$turnId=Get-ForgeShaText ($session+"`n"+[string]$data.last_assistant_message+"`n")}; if(-not $turnId){return}
    $turnKey=if($turnId -match '^[A-Za-z0-9._-]+$'){$turnId}else{Get-ForgeShaText $turnId}; if($host -notin @("claude","codex")){$host="unknown"}
    $root=git rev-parse --show-toplevel 2>$null; if($LASTEXITCODE -ne 0 -or -not $root){return}; $root=(Resolve-Path -LiteralPath $root).Path
    $common=git rev-parse --git-common-dir 2>$null; if(-not [IO.Path]::IsPathRooted($common)){$common=Join-Path $root $common}; $common=(Resolve-Path -LiteralPath $common).Path
    $projectId=Get-ForgeShaText ($root+"`n"+$common+"`n")
    $homeRoot=if($env:USERPROFILE){$env:USERPROFILE}else{$HOME};if(-not $homeRoot){Write-ForgeGoalTamper "trusted home unavailable"}
    $homePhysical=(Resolve-Path -LiteralPath $homeRoot -ErrorAction Stop).Path;$homeForge=Join-Path $homeRoot ".forge";$bin=Join-Path $homeForge "bin"
    Assert-ForgePhysicalDirectory $homeForge $homePhysical;Assert-ForgePhysicalDirectory $bin (Resolve-Path -LiteralPath $homeForge).Path
    $writer=Join-Path $bin "forge-goal-authorize.ps1";$writerSeal=Join-Path $bin "forge-goal-authorize.ps1.sha256"
    if(-not (Test-Path -LiteralPath $writer -PathType Leaf) -or -not (Test-Path -LiteralPath $writerSeal -PathType Leaf) -or ((Get-Item $writer -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or ((Get-Item $writerSeal -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){Write-ForgeGoalTamper "sealed authorization writer unavailable or aliased"}
    if(([IO.File]::ReadAllText($writerSeal)).Trim() -cne (Get-ForgeFileSha $writer)){Write-ForgeGoalTamper "authorization writer revision seal mismatch"}
    $writerRevision="";foreach($writerLine in @(Get-Content -LiteralPath $writer)){if($writerLine -match '^\$WriterRevision = ''([^'']+)''$'){ $writerRevision=$matches[1];break }}
    if($writerRevision -notmatch '^[0-9a-fA-F]{64}$'){Write-ForgeGoalTamper "installed writer identity is unsealed"}
    $authRoot=Join-Path $homeForge "goal-authorizations";Assert-ForgePhysicalDirectory $authRoot (Resolve-Path -LiteralPath $homeForge).Path
    $authRootPhysical=(Resolve-Path -LiteralPath $authRoot).Path
    $rootPrefix=$root.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar;$commonPrefix=$common.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if($authRootPhysical -eq $root -or $authRootPhysical.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase) -or $authRootPhysical -eq $common -or $authRootPhysical.StartsWith($commonPrefix,[StringComparison]::OrdinalIgnoreCase)){Write-ForgeGoalTamper "authorization root overlaps project authority"}
    $authProject=Join-Path $authRoot $projectId
    Assert-ForgePhysicalDirectory $authProject $authRootPhysical
    $auth=Join-Path $authProject "$nonce.auth"
    if(-not (Test-Path -LiteralPath $auth -PathType Leaf) -or ((Get-Item -LiteralPath $auth -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){Write-ForgeGoalTamper "authorization record missing or aliased";return}
    $ceiling=0; [void][int]::TryParse((Get-ForgeGoalValue $auth "ceiling"),[ref]$ceiling)
    $valid=(Get-ForgeGoalValue $auth "format") -eq "forge-goal-authorization-v1" -and (Get-ForgeGoalValue $auth "project_root") -eq $root -and (Get-ForgeGoalValue $auth "git_common_dir") -eq $common -and (Get-ForgeGoalValue $auth "project_id") -eq $projectId -and (Get-ForgeGoalValue $auth "nonce") -eq $nonce -and (Get-ForgeGoalValue $auth "objective_hash") -eq $objective -and (Get-ForgeGoalValue $auth "approval_channel") -eq "physical-operator-action" -and -not [string]::IsNullOrEmpty((Get-ForgeGoalValue $auth "issue_id")) -and (Get-ForgeGoalValue $auth "writer_revision") -ceq $writerRevision -and $ceiling -gt 0
    if(-not $valid){Write-ForgeGoalTamper "state/authorization binding mismatch";return}
    $forge=Join-Path $root ".forge";$local=Join-Path $forge "local";Assert-ForgePhysicalDirectory $forge $root;Assert-ForgePhysicalDirectory $local $root
    $goalCounters=Join-Path $local "goal-counters";$counter=Join-Path $goalCounters $nonce;$localTurns=Join-Path $counter "turns";$ledger=Join-Path $authProject "$nonce.ledger";$externalTurns=Join-Path $ledger "turns"
    foreach($path in @($goalCounters,$counter,$localTurns)){if(Test-Path -LiteralPath $path){if((Get-Item $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){Write-ForgeGoalTamper "aliased turn ledger"}}else{New-Item -ItemType Directory -Path $path -ErrorAction Stop|Out-Null};Assert-ForgePhysicalDirectory $path $root}
    foreach($path in @($ledger,$externalTurns)){if(Test-Path -LiteralPath $path){if((Get-Item $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){Write-ForgeGoalTamper "aliased protected ledger"}}else{New-Item -ItemType Directory -Path $path -ErrorAction Stop|Out-Null};Assert-ForgePhysicalDirectory $path $authRootPhysical}
    $lock=Join-Path $counter ".goal-charge.lock";$lockBytes=[Text.Encoding]::UTF8.GetBytes("$PID`n");$locked=$false
    for($attempt=0;$attempt -lt 200 -and -not $locked;$attempt++){if(New-ForgeNoClobber $lock $lockBytes){$locked=$true}else{if((Test-Path $lock) -and ((Get-Item $lock -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){Write-ForgeGoalTamper "aliased checkpoint lock"};Start-Sleep -Milliseconds 10}}
    if(-not $locked){Write-ForgeGoalTamper "checkpoint publication lock unavailable"}
    try {
    $binding=Join-Path $ledger "authorization.binding"
    $authSha=(Get-FileHash -LiteralPath $auth -Algorithm SHA256).Hash.ToLowerInvariant()
    $bindingText="format=forge-goal-ledger-v1`nauthorization_sha256=$authSha`nnonce=$nonce`nobjective_hash=$objective`nceiling=$ceiling`nissue_id=$(Get-ForgeGoalValue $auth 'issue_id')`nwriter_revision=$(Get-ForgeGoalValue $auth 'writer_revision')`nproject_id=$projectId`n"
    $bindingBytes=[Text.Encoding]::UTF8.GetBytes($bindingText)
    if(-not (Test-Path -LiteralPath $binding -PathType Leaf)){
        if(@(Get-ChildItem -LiteralPath $externalTurns -File -ErrorAction SilentlyContinue).Count -gt 0){Write-ForgeGoalTamper "authorization binding deleted after charging";return}
        [void](New-ForgeNoClobber $binding $bindingBytes)
    }
    if(-not (Test-Path -LiteralPath $binding -PathType Leaf) -or ((Get-Item -LiteralPath $binding -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or [IO.File]::ReadAllText($binding) -cne $bindingText){Write-ForgeGoalTamper "authorization record changed after activation";return}
    (Get-Item -LiteralPath $binding).IsReadOnly=$true
    foreach($externalItem in @(Get-ChildItem -LiteralPath $externalTurns -Force -ErrorAction SilentlyContinue)){
        if($externalItem.PSIsContainer -or ($externalItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $externalItem.Name -notmatch '^[A-Za-z0-9._-]+$'){Write-ForgeGoalTamper "invalid protected turn entry"}
        $ep=$externalItem.FullName
        if((Get-ForgeGoalValue $ep "format") -ne "forge-goal-turn-v1" -or (Get-ForgeGoalValue $ep "nonce") -ne $nonce -or (Get-ForgeGoalValue $ep "objective_hash") -ne $objective -or -not (Get-ForgeGoalValue $ep "turn_id")){Write-ForgeGoalTamper "malformed protected turn record"}
        $lp=Join-Path $localTurns $externalItem.Name;$eb=[IO.File]::ReadAllBytes($ep)
        if(Test-Path -LiteralPath $lp){if(-not (Test-ForgeBytesEqual $lp $eb)){Write-ForgeGoalTamper "turn record content diverged"}}
        elseif(-not (New-ForgeNoClobber $lp $eb)){Write-ForgeGoalTamper "local turn recovery collision"}
    }
    foreach($localItem in @(Get-ChildItem -LiteralPath $localTurns -Force -ErrorAction SilentlyContinue)){
        $ep=Join-Path $externalTurns $localItem.Name
        if($localItem.PSIsContainer -or ($localItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not (Test-Path -LiteralPath $ep -PathType Leaf) -or -not (Test-ForgeBytesEqual $ep ([IO.File]::ReadAllBytes($localItem.FullName)))){Write-ForgeGoalTamper "local and protected turn ledgers diverged"}
    }
    $count=@(Get-ChildItem -LiteralPath $externalTurns -File -Force).Count;$checkpoint=Join-Path $counter "checkpoint";$marker=Join-Path $counter "budget-exhausted.marker"
    if((Test-Path -LiteralPath $checkpoint) -or (Test-Path -LiteralPath $marker)){
        if(-not (Test-Path $checkpoint -PathType Leaf) -or -not (Test-Path $marker -PathType Leaf) -or ((Get-Item $checkpoint -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or ((Get-Item $marker -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){Write-ForgeGoalTamper "partial or aliased exhaustion publication"}
        if((Get-ForgeGoalValue $checkpoint "format") -ne "forge-goal-checkpoint-v1" -or (Get-ForgeGoalValue $checkpoint "nonce") -ne $nonce -or (Get-ForgeGoalValue $checkpoint "objective_hash") -ne $objective -or (Get-ForgeGoalValue $checkpoint "turn_count") -ne [string]$count -or (Get-ForgeGoalValue $checkpoint "turn_ceiling") -ne [string]$ceiling -or $count -lt $ceiling){Write-ForgeGoalTamper "checkpoint authority mismatch"}
        $first=@(Get-Content -LiteralPath $marker -TotalCount 1)[0]
        if($first -ne "FORGE_GOAL_BUDGET_EXHAUSTED" -or (Get-ForgeGoalValue $marker "nonce") -ne $nonce -or (Get-ForgeGoalValue $marker "turn_count") -ne [string]$count -or (Get-ForgeGoalValue $marker "turn_ceiling") -ne [string]$ceiling -or (Get-ForgeGoalValue $marker "checkpoint") -ne $checkpoint -or (Get-ForgeGoalValue $marker "checkpoint_sha256") -ne (Get-ForgeFileSha $checkpoint)){Write-ForgeGoalTamper "marker/checkpoint binding mismatch"}
        [Console]::Error.WriteLine("FORGE_GOAL_BUDGET_EXHAUSTED: checkpoint=$checkpoint");return
    }
    $phase="";$next="";foreach($line in $lines){if($line -match '^\|\s*Phase\s*\|\s*([^|]*?)\s*\|'){$phase=$matches[1].Trim()};if($line -match '^\|\s*Next step\s*\|\s*([^|]*?)\s*\|'){$next=$matches[1].Trim()}}
    $stateSha=(Get-FileHash -LiteralPath $stateMd -Algorithm SHA256).Hash.ToLowerInvariant();$record="format=forge-goal-turn-v1`nnonce=$nonce`nobjective_hash=$objective`nturn_id=$turnId`nhost=$host`nsession_id=$session`nstate_sha256=$stateSha`nnext_step=$next`n";$bytes=[Text.Encoding]::UTF8.GetBytes($record)
    $externalRecord=Join-Path $externalTurns $turnKey;$localRecord=Join-Path $localTurns $turnKey
    if(-not (Test-Path -LiteralPath $externalRecord)){[void](New-ForgeNoClobber $externalRecord $bytes)}
    if(-not (Test-Path -LiteralPath $externalRecord -PathType Leaf) -or ((Get-Item $externalRecord -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){Write-ForgeGoalTamper "protected turn publication incomplete"}
    $externalBytes=[IO.File]::ReadAllBytes($externalRecord)
    if(-not (Test-Path -LiteralPath $localRecord)){[void](New-ForgeNoClobber $localRecord $externalBytes)}
    if(-not (Test-ForgeBytesEqual $localRecord $externalBytes)){Write-ForgeGoalTamper "turn mirror incomplete"}
    $count=@(Get-ChildItem -LiteralPath $externalTurns -File -Force).Count
    if($count -lt $ceiling){if((Test-Path $checkpoint) -or (Test-Path $marker)){Write-ForgeGoalTamper "premature checkpoint or marker exists"};return}
    $checkpointText="format=forge-goal-checkpoint-v1`nnonce=$nonce`nobjective_hash=$objective`nturn_count=$count`nturn_ceiling=$ceiling`nturn_id=$turnId`nhost=$host`nworkflow_command=$($goal['workflow_command'])`nphase=$phase`nnext_step=$next`nstate_sha256=$stateSha`n";$checkpointBytes=[Text.Encoding]::UTF8.GetBytes($checkpointText)
    Publish-ForgeNoClobber $checkpoint $checkpointBytes "checkpoint";$checkpointSha=Get-ForgeFileSha $checkpoint
    $markerText="FORGE_GOAL_BUDGET_EXHAUSTED`npaused=true`nnext_step=$next`nnonce=$nonce`nturn_count=$count`nturn_ceiling=$ceiling`ncheckpoint=$checkpoint`ncheckpoint_sha256=$checkpointSha`n";$markerBytes=[Text.Encoding]::UTF8.GetBytes($markerText)
    Publish-ForgeNoClobber $marker $markerBytes "marker"
    if((Get-ForgeGoalValue $marker "checkpoint_sha256") -ne (Get-ForgeFileSha $checkpoint)){Write-ForgeGoalTamper "marker/checkpoint binding mismatch"}
    [Console]::Error.WriteLine("FORGE_GOAL_BUDGET_EXHAUSTED: checkpoint=$checkpoint")
    } finally { Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue }
}
Invoke-ForgeGoalChargeTurn

# Note: build-evidence is no longer invoked inline. It runs as its own Stop
# hook entry (registered in settings.template.json) BEFORE this one — so its
# STDERR output is rendered as informational hook output rather than being
# merged with our exit-2 stderr and labeled "Stop hook error" by CC.
# build-evidence still writes the fingerprint side-channel file that the
# stuck-detection logic below reads.

# ---------------------------------------------------------------------------
# Task 8: /forge-goal stuck-detection soft warning.
#
# build-evidence.ps1 runs as a separate Stop hook entry BEFORE this one and
# writes the current progress_fingerprint to
# .claude/local/forge-goal-last-fingerprint as a side-channel. We read it
# here. After 5 consecutive identical fingerprints, emit
# FORGE_GOAL_STUCK_WARNING to STDERR. Informational only — does NOT abort.
# Fires even when stop_hook_active=true. Counter lives in
# .claude/local/forge-goal-stuck-count: format "<count>|<fingerprint_sha256>".
# PS 5.1 compatible: no ??, [Console]::Error.WriteLine for STDERR.
# ---------------------------------------------------------------------------
function Invoke-ForgeGoalStuckCheck {
    $fpFile   = Join-Path $stateLocalDir "forge-goal-last-fingerprint"
    $ctrFile  = Join-Path $stateLocalDir "forge-goal-stuck-count"

    # Only proceed if /forge-goal is active: state.md must have a non-empty
    # nonce in the ## /goal session table.
    if (-not (Test-Path $stateMd)) { return }

    $raw = Get-Content $stateMd -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($raw)) { return }

    # CRLF normalize then extract nonce from ## /goal session block.
    $lines = ($raw -replace "`r", "") -split "`n"
    $inSection = $false
    $nonce = ""
    foreach ($line in $lines) {
        if ($line -match '^## /goal session$') { $inSection = $true; continue }
        if ($inSection -and $line -match '^## ') { break }
        if (-not $inSection) { continue }
        if ($line -match '^\|\s*nonce\s*\|\s*(.+?)\s*\|') {
            $nonce = $matches[1].Trim()
            break
        }
    }
    if ([string]::IsNullOrEmpty($nonce) -or $nonce -eq "<uuid-v4-lowercase>") { return }

    # Read the current fingerprint written by build-evidence.ps1.
    if (-not (Test-Path $fpFile)) { return }
    $currentFp = (Get-Content $fpFile -Raw -ErrorAction SilentlyContinue)
    if ([string]::IsNullOrEmpty($currentFp)) { return }
    $currentFp = $currentFp.Trim()
    if ([string]::IsNullOrEmpty($currentFp)) { return }

    # Read previous counter state (format: "<count>|<fingerprint>").
    $prevCount = 0
    $prevFp    = ""
    if (Test-Path $ctrFile) {
        $ctrRaw = (Get-Content $ctrFile -Raw -ErrorAction SilentlyContinue)
        if (-not [string]::IsNullOrEmpty($ctrRaw)) {
            $ctrRaw = $ctrRaw.Trim()
            $pipeIdx = $ctrRaw.IndexOf('|')
            if ($pipeIdx -gt 0) {
                $countStr = $ctrRaw.Substring(0, $pipeIdx)
                $prevFp   = $ctrRaw.Substring($pipeIdx + 1)
                $parsedCount = 0
                if ([int]::TryParse($countStr, [ref]$parsedCount) -and $parsedCount -ge 0) {
                    $prevCount = $parsedCount
                }
            }
        }
    }

    # Update counter: increment if fingerprint unchanged, reset if changed.
    $newCount = if ($currentFp -eq $prevFp) { $prevCount + 1 } else { 1 }

    # Persist updated counter (WriteAllText to avoid BOM that Set-Content adds).
    try {
        $null = New-Item -ItemType Directory -Path $stateLocalDir -Force -ErrorAction SilentlyContinue
        [System.IO.File]::WriteAllText($ctrFile, "$newCount|$currentFp`n")
    } catch {
        # Non-blocking: ignore write failures
    }

    # Emit warning if threshold reached (>= 5 consecutive identical fingerprints).
    if ($newCount -ge 5) {
        [Console]::Error.WriteLine("FORGE_GOAL_STUCK_WARNING: no measurable progress for $newCount consecutive turns (fingerprint unchanged). Consider invoking /council, checkpointing state.md, or surfacing a blocker. Loop continues — this is informational only.")
    }
}
Invoke-ForgeGoalStuckCheck

# Check if stop_hook_active to prevent infinite loops
if ($data.stop_hook_active -eq $true) {
    Exit-ForgeAllow
}

# All git commands run in current directory (Claude cd's into worktrees)
# Only count tracked modifications (staged + unstaged), NOT untracked files (??)
$uncommittedOutput = git status --porcelain 2>$null | Where-Object { $_ -notmatch '^\?\?' }
$uncommitted = if ($uncommittedOutput) { @($uncommittedOutput).Count } else { 0 }

# Check if CHANGELOG was modified
$changelogOutput = git status --porcelain docs/CHANGELOG.md 2>$null
$changelogModified = if ($changelogOutput) { ($changelogOutput | Measure-Object -Line).Lines } else { 0 }

# Get branch base for comparison
# Resolve repo default branch via the shared helper.
# CRITICAL: dot-source (not subprocess) — Windows ships powershell.exe (5.1),
# spawning pwsh (7+) would fail on stock Windows. Dot-source works in both.
$hookDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libPath = Join-Path $hookDir "lib\default-branch.ps1"
$defaultBranch = "main"  # fallback if helper or git fails
$helperBailed = $false
if (Test-Path $libPath) {
    . $libPath
    $detected = Get-DefaultBranch
    if ($detected) {
        $defaultBranch = $detected
    } else {
        $helperBailed = $true
    }
} else {
    $helperBailed = $true
}
# Helper-bail breadcrumb (stderr): mirrors the bash hook so silent fallback to "main"
# is at least diagnosable on master-default Windows installs.
if ($helperBailed) {
    [Console]::Error.WriteLine("⚠ check-state-updated: default-branch helper bailed; assuming 'main'")
}
# Merge-base fallback chain: prefer local <default>; else origin/<default>
# (single-branch clones may have only the remote-tracking ref); else HEAD~10.
$branchBase = $null
$null = git rev-parse --verify $defaultBranch 2>$null
if ($LASTEXITCODE -eq 0) {
    $branchBase = git merge-base $defaultBranch HEAD 2>$null
} else {
    $null = git rev-parse --verify "origin/$defaultBranch" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $branchBase = git merge-base "origin/$defaultBranch" HEAD 2>$null
    }
}
if (-not $branchBase) { $branchBase = "HEAD~10" }

# Count files changed on branch
$branchChangedOutput = git diff --name-only $branchBase HEAD 2>$null
$branchChanged = if ($branchChangedOutput) { ($branchChangedOutput | Measure-Object -Line).Lines } else { 0 }

$uncommittedFilesOutput = git diff --name-only 2>$null
$uncommittedFiles = if ($uncommittedFilesOutput) { ($uncommittedFilesOutput | Measure-Object -Line).Lines } else { 0 }

$totalChanged = $branchChanged + $uncommittedFiles

# Check if CHANGELOG was updated anywhere on branch
$changelogInBranch = 0
if ($branchChangedOutput) {
    $changelogInBranch = ($branchChangedOutput | Select-String "CHANGELOG.md" | Measure-Object).Count
}

# --- Workflow state tracking ---
# State file is gitignored. Emit breadcrumb only when legacy CONTINUITY.md is also present
# (signals user upgraded but hasn't migrated) — avoid spamming every Stop event.
if ((-not $stateMd -or -not (Test-Path $stateMd)) -and (Test-Path "CONTINUITY.md")) {
    [Console]::Error.WriteLine("ℹ check-state-updated: Forge state.md not found, but CONTINUITY.md exists.")
    [Console]::Error.WriteLine("  Run setup -FullRefresh -DryRun, resolve every reported blocker, then run setup -FullRefresh.")
    # Continue to CHANGELOG check — gates are independent.
}

# Workflow reminder — read .claude/local/state.md (gitignored), single-line format.
#
# IMPORTANT: scope the extraction to ONLY the `## Workflow` section. Migrated
# content carried forward from an older Forge state source (for example old "### Done"
# entries that mention prior workflow scaffolds) can leave stray `| Command |`
# lines elsewhere in the file. A whole-file Select-String would match every one
# of them; even with `Select-Object -First 1` the FIRST hit can be the stray if
# it appears before the canonical scaffold. Scope first, then match.
$workflowReminder = ""
if ($stateMd -and (Test-Path $stateMd)) {
    $stateContent = Get-Content $stateMd -Raw -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrEmpty($stateContent)) {
        # Extract just the `## Workflow` block (between `## Workflow` and the next `## ` heading).
        $workflowBlockLines = @()
        $inWorkflow = $false
        foreach ($line in ($stateContent -split "`n")) {
            if ($line -match '^## Workflow$') { $inWorkflow = $true; continue }
            if ($inWorkflow -and $line -match '^## ') { break }
            if ($inWorkflow) { $workflowBlockLines += $line }
        }
        $cmdLine = ($workflowBlockLines | Select-String '\|\s*Command\s*\|' | Select-Object -First 1)
        if ($cmdLine) {
            $cmd = ($cmdLine -split '\|')[2].Trim()
            if ($cmd -and $cmd -ne "none" -and $cmd -ne ([char]0x2014).ToString() -and $cmd -ne "-") {
                $phaseLine = ($workflowBlockLines | Select-String '\|\s*Phase\s*\|' | Select-Object -First 1)
                $nextLine = ($workflowBlockLines | Select-String '\|\s*Next step\s*\|' | Select-Object -First 1)
                $phase = if ($phaseLine) { ($phaseLine -split '\|')[2].Trim() } else { "" }
                $next = if ($nextLine) { ($nextLine -split '\|')[2].Trim() } else { "" }
                $workflowReminder = "WORKFLOW: $cmd | Phase: $phase | Next: $next"
            }
        }
    }
}

# Build response
$issues = ""

# Block: 3+ files changed on branch but CHANGELOG.md never updated.
# "files changed on branch vs $defaultBranch" — count is committed + uncommitted
# diff vs the merge-base, NOT files-this-turn.
if ($totalChanged -gt 3 -and $changelogInBranch -eq 0 -and $changelogModified -eq 0) {
    if ($issues) {
        $issues = "$issues Update docs/CHANGELOG.md ($totalChanged files changed on branch vs $defaultBranch)."
    } else {
        $issues = "Update docs/CHANGELOG.md ($totalChanged files changed on branch vs $defaultBranch)."
    }
}

# Block using exit code 2 + stderr (robust — immune to stdout pollution)
if ($issues) {
    # Prepend workflow reminder if active (so model always sees current phase)
    if ($workflowReminder) { $issues = "[$workflowReminder] $issues" }
    [Console]::Error.WriteLine($issues)

    # Detect open PR for current branch. Once a PR is open, the CHANGELOG gate
    # downgrades from blocking (exit 2) to advisory (exit 0): the human reviewer
    # carries the signal, and per-turn blocking during CI wait is just noise.
    # gh availability and network are best-effort; on failure, default to "no
    # open PR" so the original blocking behavior is preserved.
    # Probe only runs when $issues is non-empty — clean stops pay no gh-API cost.
    $prOpen = $false
    $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghCmd) {
        $prState = (& gh pr view --json state -q .state 2>$null) | Out-String
        if ($prState.Trim() -eq "OPEN") { $prOpen = $true }
    }

    if ($prOpen) {
        # Advisory only — PR already open. Exit 0 so the message is informational
        # and the build-evidence STDERR dump is not labeled "Stop hook error".
        Exit-ForgeAllow
    }
    exit 2
}

# Advisory: remind about active workflow even when no issues (non-blocking)
if ($workflowReminder) {
    [Console]::Error.WriteLine($workflowReminder)
}

# All good, allow stop
Exit-ForgeAllow
