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
  $quarantine=Join-Path (Split-Path -Parent $ReviewRoot) ('.discarded-council-'+[Guid]::NewGuid().ToString('N'))
  [IO.Directory]::Move($Path,$quarantine)
  try{[IO.Directory]::Delete($quarantine,$true)}catch{}
  if(Test-Path -LiteralPath $Path){Stop-Council 'failed mixed attempt artifacts could not be discarded'}
}
function Usage { @'
usage: council-dispatch.ps1 --question-file FILE --artifact ARTIFACT --workflow-base-sha SHA --workflow-base-ref REF [--seat-engine SEAT=claude|codex|main|other]
Six fresh sessions and eleven turns; runtime other failure reruns the complete topology on main (same-engine-fallback).
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
$script:FailedEngine=''; $script:AttemptDir=''
function Test-EnginePreflight([string]$Selected) {
  if (-not (Get-Command $Selected -ErrorAction SilentlyContinue)) { return $false }
  foreach ($role in @('model-council-advisor','model-council-chair')) {
    if (-not (Select-String -LiteralPath $capabilities -SimpleMatch "$role`t$Selected")) { return $false }
  }
  return [bool](Select-String -LiteralPath $agent -SimpleMatch "'resume'") -and [bool](Select-String -LiteralPath $agent -SimpleMatch 'SessionId')
}
function Invoke-Seat([string]$Dir,[string]$Seat,[string]$Phase,[string]$Bundle='',[string]$Session='') {
  $prompt=Join-Path $Dir "$Seat-$Phase.prompt"; $out=Join-Path $Dir "$Seat-$Phase.out"; $lines=@("question_hash=$qhash",'requires_read_only_channel=false',"Council $Phase seat $Seat",(Get-Content -Raw -LiteralPath $question)); if ($Bundle) {$lines += 'Anonymous other-advisor bundle:'; $lines += (Get-Content -Raw -LiteralPath $Bundle)}; [IO.File]::WriteAllText($prompt,($lines -join "`n"))
  $script:FailedEngine=$engine[$Seat]; $args=@('run','--engine',$engine[$Seat],'--fallback-policy','none','--role','council-advisor','--profile','review','--artifact',$artifact,'--workflow-base-sha',$baseSha,'--workflow-base-ref',$baseRef,'--prompt-file',$prompt,'--output',$out,'--conversation',$(if($Phase -eq 'peer'){'resume'}else{'new'}),'--seat-id',$Seat,'--timeout-seconds',$timeout)
  if ($Phase -eq 'peer') {$args += @('--session-id',$Session)} else {$args += @('--session-id-output',(Join-Path $Dir "$Seat.session"))}; $null = & $agent @args; return $LASTEXITCODE
}
function Invoke-Attempt([string]$Mode,[string]$Reason) {
  $reviewsRoot=Split-Path -Parent $reviewRoot
  $dir=Join-Path $reviewsRoot ('.council-attempt-'+[Guid]::NewGuid().ToString('N'))
  $finalDir=Join-Path $reviewRoot "$Mode-$([DateTime]::UtcNow.Ticks)"
  New-Item -ItemType Directory -Path $dir | Out-Null
  $script:AttemptDir=$dir
  foreach($seat in $seats) { if ((Invoke-Seat $dir $seat 'advice') -ne 0) { return $null } }
  $bundle=Join-Path $dir 'anonymous-advice.txt'; foreach($seat in $seats) { Add-Content -LiteralPath $bundle -Value "### Advisor $($labels[$seat])"; Get-Content -LiteralPath (Join-Path $dir "$seat-advice.out") | Where-Object {$_ -notmatch '^(engine|author)='} | Add-Content -LiteralPath $bundle }
  foreach($seat in $seats) { $others=Join-Path $dir "$seat-others.txt"; $keep=$false; Get-Content $bundle | ForEach-Object {if($_ -match '^### Advisor ') {$keep=($_.Split(' ')[2] -ne $labels[$seat])};if($keep){$_}} | Set-Content $others; $sid=(Get-Content -Raw (Join-Path $dir "$seat.session")).Trim(); if(!$sid -or (Invoke-Seat $dir $seat 'peer' $others $sid) -ne 0){return $null} }
  $peers=Join-Path $dir 'anonymous-peer-reviews.txt'; foreach($seat in $seats) { Add-Content -LiteralPath $peers -Value "### Peer review $($labels[$seat])"; Get-Content -LiteralPath (Join-Path $dir "$seat-peer.out") | Where-Object {$_ -notmatch '^(engine|author)='} | Add-Content -LiteralPath $peers }; $chairPrompt=Join-Path $dir 'chair.prompt'; [IO.File]::WriteAllText($chairPrompt,"question_hash=$qhash`nrequires_read_only_channel=false`n"+(Get-Content -Raw $question)+"`nAnonymous advice:`n"+(Get-Content -Raw $bundle)+"`nAnonymous peer reviews:`n"+(Get-Content -Raw $peers)+"`nMinority reports are mandatory.`n"); $chairOut=Join-Path $dir 'chair.out'; $script:FailedEngine=$engine['chair']; $null = & $agent run --engine $engine['chair'] --fallback-policy none --role council-chair --profile review --artifact $artifact --workflow-base-sha $baseSha --workflow-base-ref $baseRef --prompt-file $chairPrompt --output $chairOut --conversation ephemeral --seat-id chair --timeout-seconds $timeout; if($LASTEXITCODE -ne 0){return $null}
  $receipt=@("schema_version=1","topology_mode=$Mode","trigger_reason=$Reason","main_host=$main","question_hash=$qhash","anonymized_bundle_hash=$(Sha $bundle)","anonymized_peer_bundle_hash=$(Sha $peers)","configuration_revision=$(Sha $capabilities)")
  foreach($seat in $seats) { $sid=(Get-Content -Raw (Join-Path $dir "$seat.session")).Trim(); $receipt += @("seat_label.$($labels[$seat])=$($labels[$seat])","persona_binding.$seat=$($personas[$seat])","intended_engine.$seat.advice=$($engine[$seat])","actual_engine.$seat.advice=$($engine[$seat])","intended_engine.$seat.peer=$($engine[$seat])","actual_engine.$seat.peer=$($engine[$seat])","session_id.$seat=$sid","turn_id.$seat.advice=$seat-advice","turn_id.$seat.peer=$seat-peer","advisor_output_hash.$seat=$(Sha (Join-Path $dir "$seat-advice.out"))","peer_output_hash.$seat=$(Sha (Join-Path $dir "$seat-peer.out"))") }
  $receipt += @("intended_engine.chair=$($engine['chair'])","actual_engine.chair=$($engine['chair'])",'chair_session_id=ephemeral','turn_id.chair=chair-synthesis','advisor_turns=5','peer_turns=5','chairman_turns=1','turn_results=11','minority_reports=mandatory',"chairman_output_hash=$(Sha $chairOut)","final_verdict_path=$(Join-Path $finalDir 'chair.out')")
  $receipt | Set-Content (Join-Path $dir 'topology.receipt')
  [IO.Directory]::Move($dir,$finalDir)
  $script:AttemptDir=$finalDir
  return $finalDir
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
