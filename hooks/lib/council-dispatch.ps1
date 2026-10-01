# PowerShell 5.1 mirror of council-dispatch.sh. The topology decision stays
# above agent-dispatch: individual seats always use fallback_policy=none.
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
$ErrorActionPreference = 'Stop'
function Stop-Council([string]$Message) { [Console]::Error.WriteLine("BLOCKED[council]: $Message"); exit 2 }
function Sha([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
function New-CouncilDirectory([string]$Worktree, [string]$QuestionHash) {
  $cursor=$Worktree
  foreach($part in @('.forge','local','reviews',"council-$QuestionHash")){
    $cursor=Join-Path $cursor $part
    if(Test-Path -LiteralPath $cursor){
      $item=Get-Item -LiteralPath $cursor -Force
      if(-not $item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)){Stop-Council 'council receipt storage ancestors must be no-follow directories'}
    }else{New-Item -ItemType Directory -Path $cursor | Out-Null}
  }
  return [IO.Path]::GetFullPath($cursor)
}
function Remove-CouncilAttempt([string]$Path,[string]$ReviewRoot) {
  if(-not (Test-Path -LiteralPath $Path)){return}
  $logs=@('failed_attempt=true')
  foreach($log in Get-ChildItem -LiteralPath $Path -Filter '*.dispatch.log' -File){$logs+=$log.Name;$logs+=Get-Content -LiteralPath $log.FullName}
  [IO.File]::WriteAllText(($Path+'.failed.log'),($logs -join "`n"))
  $quarantine=Join-Path (Split-Path -Parent $ReviewRoot) ('.discarded-council-'+[Guid]::NewGuid().ToString('N'))
  [IO.Directory]::Move($Path,$quarantine)
  try{[IO.Directory]::Delete($quarantine,$true)}catch{}
  if(Test-Path -LiteralPath $Path){Stop-Council 'failed mixed attempt artifacts could not be discarded'}
}
function Usage { @'
usage: council-dispatch.ps1 --question-file FILE --artifact ARTIFACT --workflow-base-sha SHA --workflow-base-ref REF [--seat-engine SEAT=claude|codex|main|other]
Parallel advice and peer waves, then chairman: six fresh sessions and eleven turns. Runtime other failure reruns the complete topology on main (same-engine-fallback).
'@ }
$self = Split-Path -Parent $MyInvocation.MyCommand.Path; $root = (Resolve-Path (Join-Path $self '..\..')).Path
$agent = Join-Path $self 'agent-dispatch.ps1'; $capabilities = Join-Path $root 'host-capabilities.tsv'
if (-not (Test-Path -LiteralPath $capabilities)) { $capabilities = Join-Path $root 'manifests\host-capabilities.tsv' }
$question = ''; $artifact = ''; $baseSha = ''; $baseRef = ''; $timeout = '1200'; $overrides = @()
for ($i=0; $i -lt $Arguments.Count; ) { switch ($Arguments[$i]) {
  '--help' { Usage; exit 0 }; '-h' { Usage; exit 0 }
  '--question-file' { $question=$Arguments[$i+1]; $i+=2; break }
  '--artifact' { $artifact=$Arguments[$i+1]; $i+=2; break }
  '--workflow-base-sha' { $baseSha=$Arguments[$i+1]; $i+=2; break }
  '--workflow-base-ref' { $baseRef=$Arguments[$i+1]; $i+=2; break }
  '--timeout-seconds' { $timeout=$Arguments[$i+1]; $i+=2; break }
  '--seat-engine' { $overrides += $Arguments[$i+1]; $i+=2; break }
  default { Stop-Council "unknown argument $($Arguments[$i])" }
}}
if (-not (Test-Path -LiteralPath $question -PathType Leaf) -or !$artifact -or !$baseSha -or !$baseRef) { Stop-Council 'question, artifact, and workflow base are required' }
$main = $env:FORGE_NATIVE_HOST; if ($main -cnotin @('claude','codex')) { Stop-Council 'declared main host must be claude or codex' }
$other = if ($main -eq 'claude') { 'codex' } else { 'claude' }
$seats=@('simplifier','scalability_hawk','pragmatist','contrarian','maintainer'); $labels=@{simplifier='A';scalability_hawk='B';pragmatist='C';contrarian='D';maintainer='E'}; $personas=@{simplifier='The Simplifier';scalability_hawk='The Scalability Hawk';pragmatist='The Pragmatist';contrarian='The Contrarian';maintainer='The Maintainer'}; $engine=@{simplifier=$main;scalability_hawk=$main;pragmatist=$main;contrarian=$other;maintainer=$other;chair=$other}; $custom=$false
foreach ($entry in $overrides) { $parts=$entry -split '=',2; if ($parts.Count -ne 2 -or $parts[0] -notin @($seats + 'chair')) { Stop-Council 'invalid seat override' }; $value=$parts[1]; if ($value -eq 'main') {$value=$main}; if ($value -eq 'other') {$value=$other}; if ($value -notin @('claude','codex')) { Stop-Council 'invalid seat engine' }; $engine[$parts[0]]=$value; $custom=$true }
$qhash=Sha $question; $workroot=(& git rev-parse --show-toplevel); if ($LASTEXITCODE -ne 0) { Stop-Council 'Git worktree required' }; $workroot=(Resolve-Path $workroot).Path; $reviewRoot=New-CouncilDirectory $workroot $qhash
# Establish shared session parents before concurrent no-follow transport setup.
foreach($name in @('sessions','session-stores')) {
  $path=Join-Path (Split-Path -Parent $reviewRoot) $name
  if(Test-Path -LiteralPath $path) {
    $item=Get-Item -LiteralPath $path -Force
    if(-not $item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)){Stop-Council 'council session storage ancestors must be no-follow directories'}
  } else {New-Item -ItemType Directory -Path $path | Out-Null}
}
$script:FailedEngine=''; $script:AttemptDir=''
function Test-EnginePreflight([string]$Selected) {
  if (-not (Get-Command $Selected -ErrorAction SilentlyContinue)) { return $false }
  foreach ($role in @('model-council-advisor','model-council-chair')) {
    if (-not (Select-String -LiteralPath $capabilities -SimpleMatch "$role`t$Selected")) { return $false }
  }
  return [bool](Select-String -LiteralPath $agent -SimpleMatch "'resume'") -and [bool](Select-String -LiteralPath $agent -SimpleMatch 'SessionId')
}
function Start-CouncilSeat([string]$Dir,[string]$Seat,[string]$Phase,[string]$Bundle='',[string]$Session='') {
  $prompt=Join-Path $Dir "$Seat-$Phase.prompt"; $out=Join-Path $Dir "$Seat-$Phase.out"; $lines=@("question_hash=$qhash",'requires_read_only_channel=false',"Council $Phase seat $Seat",(Get-Content -Raw -LiteralPath $question)); if ($Bundle) {$lines += 'Anonymous other-advisor bundle:'; $lines += (Get-Content -Raw -LiteralPath $Bundle)}; [IO.File]::WriteAllText($prompt,($lines -join "`n"))
  $dispatchParameters=@{Mode='run';Engine=$engine[$Seat];FallbackPolicy='none';Role='council-advisor';Profile='review';Artifact=$artifact;WorkflowBaseSha=$baseSha;WorkflowBaseRef=$baseRef;PromptFile=$prompt;Output=$out;Conversation=$(if($Phase -eq 'peer'){'resume'}else{'new'});SeatId=$Seat;TimeoutSeconds=$timeout}
  if ($Phase -eq 'peer') {$dispatchParameters.SessionId=$Session} else {$dispatchParameters.SessionIdOutput=Join-Path $Dir "$Seat.session"}
  # Separate PowerShell processes work on 5.1 as well as Core. Encode literals
  # to preserve spaces, quotes and metacharacters without command-line parsing.
  $literalArgs=@($dispatchParameters.GetEnumerator() | ForEach-Object {$_.Key+"='"+([string]$_.Value).Replace("'","''")+"'"}) -join ';'
  $agentLiteral="'"+$agent.Replace("'","''")+"'"
  $command="try { `$seatArgs=@{$literalArgs}; & $agentLiteral @seatArgs; exit `$LASTEXITCODE } catch { [Console]::Error.WriteLine(`$_.ToString()); exit 2 }"
  $start=New-Object Diagnostics.ProcessStartInfo
  $start.FileName=(Get-Process -Id $PID).Path
  $start.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
  $start.WorkingDirectory=$workroot; $start.UseShellExecute=$false; $start.CreateNoWindow=$true
  $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
  $process=New-Object Diagnostics.Process; $process.StartInfo=$start
  if(-not $process.Start()){throw "Could not start council seat $Seat"}
  return @{Process=$process;Stdout=$process.StandardOutput.ReadToEndAsync();Stderr=$process.StandardError.ReadToEndAsync();Seat=$Seat;Engine=$engine[$Seat];Log=(Join-Path $Dir "$Seat-$Phase.dispatch.log")}
}
function Invoke-CouncilWave([string]$Dir,[string]$Phase) {
  $script:FailedEngine=''; $workers=@(); $inputs=@(); $failed=$false
  # Validate all resumes before launching any seat.
  foreach($seat in $seats) {
    $others='';$sid=''
    if($Phase -eq 'peer') {
      $others=Join-Path $Dir "$seat-others.txt"; $keep=$false
      Get-Content (Join-Path $Dir 'anonymous-advice.txt') | ForEach-Object {if($_ -match '^### Advisor ') {$keep=($_.Split(' ')[2] -ne $labels[$seat])};if($keep){$_}} | Set-Content -LiteralPath $others
      $sid=(Get-Content -Raw -LiteralPath (Join-Path $Dir "$seat.session")).Trim()
      if(!$sid){return $false}
    }
    $inputs+=@{Seat=$seat;Bundle=$others;Session=$sid}
  }
  [Console]::Error.WriteLine("Council ${Phase}: launching five seats in parallel.")
  try {
    foreach($input in $inputs) {$workers+=Start-CouncilSeat $Dir $input.Seat $Phase $input.Bundle $input.Session}
    foreach($worker in $workers) {
      $worker.Process.WaitForExit()
      [IO.File]::WriteAllText($worker.Log,$worker.Stdout.Result+$worker.Stderr.Result)
      if($worker.Process.ExitCode -ne 0) {
        $failed=$true
        if($script:FailedEngine -ne $main){$script:FailedEngine=$worker.Engine}
        [Console]::Error.WriteLine("Council $Phase seat $($worker.Seat) failed (exit $($worker.Process.ExitCode)); dispatcher log: $($worker.Log)")
        Get-Content -LiteralPath $worker.Log -Tail 20 | ForEach-Object {[Console]::Error.WriteLine($_)}
      }
    }
  } catch {
    $failed=$true; $script:FailedEngine=$main
    [Console]::Error.WriteLine($_.ToString())
  } finally {
    # Drain every bounded worker even on launch or collection errors. No process
    # may still write into an attempt when whole-topology fallback discards it.
    foreach($worker in $workers) {$worker.Process.WaitForExit();$worker.Process.Dispose()}
  }
  return !$failed
}
function Invoke-Attempt([string]$Mode,[string]$Reason) {
  $reviewsRoot=Split-Path -Parent $reviewRoot
  $dir=Join-Path $reviewsRoot ('.council-attempt-'+[Guid]::NewGuid().ToString('N'))
  $finalDir=Join-Path $reviewRoot "$Mode-$([DateTime]::UtcNow.Ticks)"
  New-Item -ItemType Directory -Path $dir | Out-Null
  $script:AttemptDir=$dir
  $succeeded=$false
  try {
  if(-not (Invoke-CouncilWave $dir 'advice')) {return $null}
  $bundle=Join-Path $dir 'anonymous-advice.txt'; foreach($seat in $seats) { Add-Content -LiteralPath $bundle -Value "### Advisor $($labels[$seat])"; Get-Content -LiteralPath (Join-Path $dir "$seat-advice.out") | Where-Object {$_ -notmatch '^(engine|author)='} | Add-Content -LiteralPath $bundle }
  if(-not (Invoke-CouncilWave $dir 'peer')) {return $null}
  $peers=Join-Path $dir 'anonymous-peer-reviews.txt'; foreach($seat in $seats) { Add-Content -LiteralPath $peers -Value "### Peer review $($labels[$seat])"; Get-Content -LiteralPath (Join-Path $dir "$seat-peer.out") | Where-Object {$_ -notmatch '^(engine|author)='} | Add-Content -LiteralPath $peers }; $chairPrompt=Join-Path $dir 'chair.prompt'; [IO.File]::WriteAllText($chairPrompt,"question_hash=$qhash`nrequires_read_only_channel=false`n"+(Get-Content -Raw $question)+"`nAnonymous advice:`n"+(Get-Content -Raw $bundle)+"`nAnonymous peer reviews:`n"+(Get-Content -Raw $peers)+"`nMinority reports are mandatory.`n"); $chairOut=Join-Path $dir 'chair.out'; $script:FailedEngine=$engine['chair']; $null = & $agent -Mode run -Engine $engine['chair'] -FallbackPolicy none -Role council-chair -Profile review -Artifact $artifact -WorkflowBaseSha $baseSha -WorkflowBaseRef $baseRef -PromptFile $chairPrompt -Output $chairOut -Conversation ephemeral -SeatId chair -TimeoutSeconds $timeout; if($LASTEXITCODE -ne 0){return $null}
  $receipt=@("schema_version=1","topology_mode=$Mode","trigger_reason=$Reason","main_host=$main","question_hash=$qhash","anonymized_bundle_hash=$(Sha $bundle)","anonymized_peer_bundle_hash=$(Sha $peers)","configuration_revision=$(Sha $capabilities)")
  foreach($seat in $seats) { $sid=(Get-Content -Raw (Join-Path $dir "$seat.session")).Trim(); $receipt += @("seat_label.$($labels[$seat])=$($labels[$seat])","persona_binding.$seat=$($personas[$seat])","intended_engine.$seat.advice=$($engine[$seat])","actual_engine.$seat.advice=$($engine[$seat])","intended_engine.$seat.peer=$($engine[$seat])","actual_engine.$seat.peer=$($engine[$seat])","session_id.$seat=$sid","turn_id.$seat.advice=$seat-advice","turn_id.$seat.peer=$seat-peer","advisor_output_hash.$seat=$(Sha (Join-Path $dir "$seat-advice.out"))","peer_output_hash.$seat=$(Sha (Join-Path $dir "$seat-peer.out"))") }
  $receipt += @("intended_engine.chair=$($engine['chair'])","actual_engine.chair=$($engine['chair'])",'chair_session_id=ephemeral','turn_id.chair=chair-synthesis','advisor_turns=5','peer_turns=5','chairman_turns=1','turn_results=11','minority_reports=mandatory',"chairman_output_hash=$(Sha $chairOut)","final_verdict_path=$(Join-Path $finalDir 'chair.out')")
  $receipt | Set-Content (Join-Path $dir 'topology.receipt')
  [IO.Directory]::Move($dir,$finalDir)
  $script:AttemptDir=$finalDir
  $succeeded=$true
  return $finalDir
  } finally {
    if(-not $succeeded){Clear-AttemptSessions $dir}
  }
}
function Assert-CleanupItem([string]$Path,[bool]$Directory) {
  $item=Get-Item -LiteralPath $Path -Force
  if($item.PSIsContainer -ne $Directory -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)){throw 'BLOCKED[council]: unsafe session cleanup path; evidence retained'}
}
function Clear-AttemptSessions([string]$Dir) {
  $reviews=Split-Path -Parent $reviewRoot
  foreach($path in @((Join-Path $workroot '.forge'),(Join-Path $workroot '.forge/local'),$reviews,$Dir,(Join-Path $reviews 'sessions'),(Join-Path $reviews 'session-stores'))){Assert-CleanupItem $path $true}
  foreach($seat in $seats){
    $marker=Join-Path $Dir "$seat.session.store-id"
    if(-not (Test-Path -LiteralPath $marker)){continue}
    Assert-CleanupItem $marker $false
    $storeId=(Get-Content -Raw -LiteralPath $marker).Trim()
    if($storeId -notmatch '^[A-Za-z0-9._-]+$' -or $storeId -in @('.','..')){throw 'BLOCKED[council]: unsafe owned store id'}
    $store=Join-Path $reviews "session-stores/$storeId"
    if(-not (Test-Path -LiteralPath $store)){continue}
    Assert-CleanupItem $store $true
    $owner=Join-Path $store 'session-owner';Assert-CleanupItem $owner $false
    if((Get-Content -Raw -LiteralPath $owner).Trim() -cne $marker){throw 'BLOCKED[council]: session cleanup ownership mismatch'}
    $idPath=Join-Path $store 'session-id'
    if(Test-Path -LiteralPath $idPath){
      Assert-CleanupItem $idPath $false
      $sid=(Get-Content -Raw -LiteralPath $idPath).Trim()
      if($sid -notmatch '^[A-Za-z0-9._-]+$' -or $sid -in @('.','..')){throw 'BLOCKED[council]: unsafe owned session id'}
      $meta=Join-Path $reviews "sessions/$sid.meta";Assert-CleanupItem $meta $false
      $lines=@(Get-Content -LiteralPath $meta)
      foreach($binding in @("store_id=$storeId","session_id=$sid","seat_id=$seat","question_hash=$qhash")){
        if(@($lines | Where-Object {$_ -ceq $binding}).Count -ne 1){throw 'BLOCKED[council]: abandoned session binding mismatch'}
      }
      $updated=@($lines | ForEach-Object {if($_ -match '^completed='){'completed=true'}else{$_}})+@('abandoned=true')
      [IO.File]::WriteAllText($meta,($updated -join "`n")+"`n",(New-Object Text.UTF8Encoding($false)))
    }
    Remove-Item -LiteralPath $store -Recurse -Force
  }
}
$mode=if($custom){'custom'}else{'mixed'}; $reason='healthy'
if (-not (Test-EnginePreflight $main)) { Stop-Council "main engine $main failed council preflight" }
$usesOther = @(@($seats + 'chair') | Where-Object { $engine[$_] -eq $other }).Count -gt 0
if ($usesOther -and -not (Test-EnginePreflight $other)) { foreach($seat in @($seats+'chair')){$engine[$seat]=$main};$mode='same-engine-fallback';$reason='known-other-unavailable';$custom=$false }
$existingAttemptPaths=@(Get-ChildItem -LiteralPath $reviewRoot -Directory -ErrorAction SilentlyContinue|ForEach-Object{$_.FullName})
$result=Invoke-Attempt $mode $reason; if($result){Write-Output "Council receipt: $result\topology.receipt";exit 0}
if($script:FailedEngine -eq $other){
  $reviewsRoot=Split-Path -Parent $reviewRoot
  $attemptPrefix=$reviewsRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar+'.council-attempt-'
  if(!$script:AttemptDir.StartsWith($attemptPrefix,[StringComparison]::OrdinalIgnoreCase)){Stop-Council 'failed attempt path escaped council staging'}
  $failedAttempt=$script:AttemptDir
  Remove-CouncilAttempt $failedAttempt $reviewRoot
  foreach($seat in @($seats+'chair')){$engine[$seat]=$main}
  $result=Invoke-Attempt 'same-engine-fallback' 'runtime-other-failure';if($result){
    Get-ChildItem -LiteralPath $reviewRoot -Directory -ErrorAction SilentlyContinue|Where-Object{$_.FullName -ne $result -and $_.FullName -notin $existingAttemptPaths}|ForEach-Object{Remove-Item -LiteralPath (Join-Path $_.FullName 'topology.receipt') -Force -ErrorAction SilentlyContinue}
    Write-Output "Council receipt: $result\topology.receipt";exit 0
  }
}
Stop-Council 'main-engine council failure blocks verdict'
