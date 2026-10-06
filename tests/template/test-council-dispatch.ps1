$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source = Join-Path $root 'hooks\lib\council-dispatch.ps1'
$powershellExe = (Get-Process -Id $PID).Path
$passes = 0
function Assert-True([bool]$Condition,[string]$Message) { if(!$Condition){throw $Message};$script:passes++;Write-Host "  PASS: $Message" }
function New-Fixture([string]$Name,[bool]$IncludeOther=$true) {
  $dir=Join-Path ([IO.Path]::GetTempPath()) ("forge-council-$Name-"+[Guid]::NewGuid().ToString('N'));$repo=Join-Path $dir 'repo';$lib=Join-Path $repo '.forge\hooks\lib';$bin=Join-Path $dir 'bin'
  New-Item -ItemType Directory -Force -Path $lib,(Join-Path $repo '.forge'),$bin|Out-Null
  Copy-Item -LiteralPath $source -Destination (Join-Path $lib 'council-dispatch.ps1')
  @("model-council-advisor`tclaude`tqualified","model-council-chair`tclaude`tqualified","model-council-advisor`tcodex`tqualified","model-council-chair`tcodex`tqualified")|Set-Content (Join-Path $repo '.forge\host-capabilities.tsv')
  @'
param([string]$Mode,[ValidateSet('claude','codex')][string]$Engine,[ValidateSet('none')][string]$FallbackPolicy,[string]$Role,[string]$Profile,[string]$Artifact,[string]$WorkflowBaseSha,[string]$WorkflowBaseRef,[string]$PromptFile,[string]$Output,[ValidateSet('ephemeral','new','resume')][string]$Conversation,[string]$SeatId,[int]$TimeoutSeconds,[string]$SessionIdOutput,[string]$SessionId)
# Task-5 preflight markers: 'resume' SessionId
$seat=$SeatId;$prompt=$PromptFile;$sessionOut=$SessionIdOutput
if($Mode -ne 'run' -or $Profile -ne 'review' -or !$SeatId -or !$Artifact -or !$WorkflowBaseSha -or !$WorkflowBaseRef -or $TimeoutSeconds -le 0){exit 25}
function Append-Call([string]$Line) {
  for($retry=0;$retry -lt 100;$retry++) {
    try {$file=[IO.File]::Open($env:FAKE_LOG,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::None);break} catch {Start-Sleep -Milliseconds 10}
  }
  try {$bytes=[Text.Encoding]::UTF8.GetBytes($Line+"`n");$file.Write($bytes,0,$bytes.Length)} finally {$file.Dispose()}
}
Append-Call "$engine|$role|$seat|$conversation|$sessionId"
$attempt=Split-Path -Parent $output
$reviews=Split-Path -Parent $attempt
if($conversation -eq 'new'){
  $storeId=[Guid]::NewGuid().ToString('N');$store=Join-Path $reviews "session-stores/$storeId"
  New-Item -ItemType Directory -Path $store|Out-Null
  [IO.File]::WriteAllText((Join-Path $store 'session-owner'),$sessionOut+'.store-id')
  [IO.File]::WriteAllText(($sessionOut+'.store-id'),$storeId)
}
if($env:FAKE_PARALLEL_PROBE -eq 'yes' -and $role -eq 'council-advisor') {
  [IO.File]::WriteAllText((Join-Path $attempt "$seat-$conversation.started"),'')
  for($tick=0;$tick -lt 100;$tick++) {$count=@(Get-ChildItem -LiteralPath $attempt -Filter "*-$conversation.started").Count;if($count -eq 5){break};Start-Sleep -Milliseconds 50}
  if($count -ne 5){exit 21}
}
if($conversation -eq 'resume' -and $env:FAKE_PARALLEL_PROBE -eq 'yes') {
  if(@(Get-ChildItem -LiteralPath $attempt -Filter '*-new.done').Count -ne 5){exit 22}
  $label=@{simplifier='A';scalability_hawk='B';pragmatist='C';contrarian='D';maintainer='E'}[$seat]
  if(Select-String -LiteralPath $prompt -SimpleMatch "### Advisor $label"){exit 23}
}
if($env:FAKE_DELAY -eq 'yes'){Start-Sleep -Milliseconds 100}
$match="$engine`:$seat`:$conversation";if($env:FAKE_FAIL_MATCH -eq $match -and !(Test-Path $env:FAKE_FAIL_MARKER)){New-Item -ItemType File -Path $env:FAKE_FAIL_MARKER|Out-Null;[Console]::Error.WriteLine("injected failure: $match");exit 17}
if($env:FAKE_MAIN_FAIL -eq 'yes' -and $match -eq "$($env:FORGE_NATIVE_HOST):simplifier:new"){exit 17}
if($conversation -eq 'new'){
  $sessionId="sid-$(Split-Path -Leaf $attempt)-$seat"
  $questionHash=((Get-Content -LiteralPath $prompt|Where-Object {$_ -like 'question_hash=*'}) -replace '^question_hash=','')
  @('completed=false',"session_id=$sessionId","store_id=$storeId","seat_id=$seat","question_hash=$questionHash")|Set-Content (Join-Path $reviews "sessions/$sessionId.meta")
  [IO.File]::WriteAllText((Join-Path $store 'session-id'),$sessionId)
  Set-Content -LiteralPath $sessionOut -Value $sessionId
}
if($conversation -eq 'resume'){
  if($sessionId -ne "sid-$(Split-Path -Leaf $attempt)-$seat"){exit 18}
  $meta=Join-Path $reviews "sessions/$sessionId.meta"
  $lines=@(Get-Content -LiteralPath $meta);$storeId=($lines|Where-Object {$_ -like 'store_id=*'}) -replace '^store_id=',''
  $lines|ForEach-Object {if($_ -eq 'completed=false'){'completed=true'}else{$_}}|Set-Content -LiteralPath $meta
  Remove-Item -LiteralPath (Join-Path $reviews "session-stores/$storeId") -Recurse -Force
}
if($role -eq 'council-chair'){if((Get-Content -Raw $prompt) -notmatch 'Anonymous peer reviews:'){exit 19};if($env:FAKE_PARALLEL_PROBE -eq 'yes' -and @(Get-ChildItem -LiteralPath $attempt -Filter '*-resume.done').Count -ne 5){exit 24}}
@('schema_version=1','verdict=CLEAN','max_severity=NONE','blocked_class=none',"engine=$engine","author=$seat")|Set-Content -LiteralPath $output
if($env:FAKE_NO_FINAL_NEWLINE -eq 'yes'){[IO.File]::AppendAllText($output,"recommendation=reply-$seat")}
[IO.File]::WriteAllText((Join-Path $attempt "$seat-$conversation.done"),'')
Write-Output 'Review completed. Receipt: fake'
exit 0
'@ | Set-Content (Join-Path $lib 'agent-dispatch.ps1')
  $engines=if($IncludeOther){@('claude','codex')}else{@($script:CouncilMain)}
  foreach($name in $engines) {
    if($env:OS -eq 'Windows_NT') {'@exit /b 0'|Set-Content (Join-Path $bin "$name.cmd")}
    else {[IO.File]::WriteAllText((Join-Path $bin $name),"#!/bin/sh`nexit 0`n");& chmod +x (Join-Path $bin $name)}
  }
  Push-Location $repo;try{& git init -q;Set-Content question.txt 'Should Forge choose this design?';Set-Content artifact.txt 'candidate'}finally{Pop-Location}
  return @{Dir=$dir;Repo=$repo;Bin=$bin;Log=(Join-Path $dir 'calls.log');Council=(Join-Path $lib 'council-dispatch.ps1')}
}
function Invoke-Fixture([hashtable]$Fixture,[string]$Failure='',[string[]]$Extra=@()) {
  $env:PATH=$Fixture.Bin+[IO.Path]::PathSeparator+$originalPath;$env:FORGE_NATIVE_HOST=$script:CouncilMain;$env:FAKE_LOG=$Fixture.Log;$env:FAKE_FAIL_MATCH=$Failure;$env:FAKE_FAIL_MARKER=Join-Path $Fixture.Dir 'failure-used'
  $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$Fixture.Council,'--question-file',(Join-Path $Fixture.Repo 'question.txt'),'--artifact',(Join-Path $Fixture.Repo 'artifact.txt'),'--workflow-base-sha','deadbeef','--workflow-base-ref','refs/heads/main')+$Extra
  $savedPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
  Push-Location $Fixture.Repo
  try{$output=& $powershellExe @args 2>&1;$rc=$LASTEXITCODE}finally{Pop-Location;$ErrorActionPreference=$savedPreference}
  $receiptLine=@($output|Where-Object{$_ -like 'Council receipt:*'}|Select-Object -Last 1);$receipt=if($receiptLine.Count){$receiptLine[0] -replace '^Council receipt: ',''}else{''};return @{Rc=$rc;Output=@($output);Receipt=$receipt}
}
$originalPath=$env:PATH;$fixtures=@()
$gitBin=Split-Path -Parent (Get-Command git -CommandType Application | Select-Object -First 1).Source
try {
  foreach($script:CouncilMain in @('claude','codex')) {
  $other=if($script:CouncilMain -eq 'claude'){'codex'}else{'claude'}
  $healthy=New-Fixture healthy;$fixtures+=$healthy.Dir;$result=Invoke-Fixture $healthy
  Assert-True ($result.Rc -eq 0) 'healthy PowerShell topology succeeds'
  Assert-True (@(Get-Content $healthy.Log).Count -eq 11) 'PowerShell dispatches eleven turns'
  Assert-True (-not ($result.Output -match 'Review completed')) 'PowerShell worker output does not pollute council return values'
  Assert-True ((Get-Content -Raw $result.Receipt) -match 'turn_results=11') 'PowerShell receipt binds eleven turns'
  Assert-True ((Get-Content -Raw $result.Receipt) -match "main_host=$script:CouncilMain") 'PowerShell receipt records declared main host metadata'
  $receiptBody=Get-Content -Raw $result.Receipt
  foreach($seat in @('simplifier','scalability_hawk','pragmatist','contrarian','maintainer')) {
    $expected=if($seat -in @('contrarian','maintainer')){$other}else{$script:CouncilMain}
    Assert-True ($receiptBody -match "actual_engine.$seat.advice=$expected") "$script:CouncilMain main routes $seat advice correctly"
    Assert-True ($receiptBody -match "actual_engine.$seat.peer=$expected") "$seat peer stays on its advice engine"
    $session=((Get-Content -LiteralPath $result.Receipt|Where-Object {$_ -like "session_id.$seat=*"}) -replace "^session_id\.$seat=",'')
    Assert-True (@(Get-Content $healthy.Log|Where-Object {$_ -eq "$expected|council-advisor|$seat|resume|$session"}).Count -eq 1) "$seat peer resumes its exact independent session"
  }
  Assert-True (@(Get-Content $healthy.Log|Where-Object {$_ -eq "$other|council-chair|chair|ephemeral|"}).Count -eq 1) "$script:CouncilMain main routes the fresh chair to $other"

  Assert-True ((Get-Content -Raw (Join-Path (Split-Path $result.Receipt) 'anonymous-peer-reviews.txt')) -notmatch 'simplifier') 'PowerShell peer bundle is anonymous'
  $parallel=New-Fixture "parallel ' quote";$fixtures+=$parallel.Dir;$env:FAKE_PARALLEL_PROBE='yes';$result=Invoke-Fixture $parallel
  Assert-True ($result.Rc -eq 0) 'PowerShell advice and peer waves rendezvous concurrently with phase barriers'
  $advice=@(Get-Content (Join-Path (Split-Path $result.Receipt) 'anonymous-advice.txt')|Where-Object {$_ -like '### Advisor *'}) -join '|'
  $peers=@(Get-Content (Join-Path (Split-Path $result.Receipt) 'anonymous-peer-reviews.txt')|Where-Object {$_ -like '### Peer review *'}) -join '|'
  Assert-True ($advice -eq '### Advisor A|### Advisor B|### Advisor C|### Advisor D|### Advisor E') 'PowerShell advice order is deterministic'
  Assert-True ($peers -eq '### Peer review A|### Peer review B|### Peer review C|### Peer review D|### Peer review E') 'PowerShell peer order is deterministic'
  $env:FAKE_PARALLEL_PROBE=''
  $unterminated=New-Fixture unterminated;$fixtures+=$unterminated.Dir;$env:FAKE_NO_FINAL_NEWLINE='yes';$env:FAKE_PARALLEL_PROBE='yes';$result=Invoke-Fixture $unterminated
  Assert-True ($result.Rc -eq 0) 'PowerShell unterminated answers preserve self exclusion'
  $resultDir=Split-Path $result.Receipt
  $advice=@(Get-Content (Join-Path $resultDir 'anonymous-advice.txt')|Where-Object {$_ -like '### Advisor *'}) -join '|'
  $peers=@(Get-Content (Join-Path $resultDir 'anonymous-peer-reviews.txt')|Where-Object {$_ -like '### Peer review *'}) -join '|'
  Assert-True ($advice -eq '### Advisor A|### Advisor B|### Advisor C|### Advisor D|### Advisor E') 'PowerShell unterminated advice preserves all five headings'
  Assert-True ($peers -eq '### Peer review A|### Peer review B|### Peer review C|### Peer review D|### Peer review E') 'PowerShell unterminated peer responses preserve all five headings'
  foreach($seat in @('simplifier','scalability_hawk','pragmatist','contrarian','maintainer')) {
    $others=Get-Content (Join-Path $resultDir "$seat-others.txt")
    Assert-True (-not ($others -match "recommendation=reply-$seat")) "PowerShell $seat excludes its own unterminated answer"
    Assert-True (@($others|Where-Object {$_ -like 'recommendation=reply-*'}).Count -eq 4) "PowerShell $seat receives four other answers"
  }
  $env:FAKE_NO_FINAL_NEWLINE='';$env:FAKE_PARALLEL_PROBE=''
  $fallback=New-Fixture fallback;$fixtures+=$fallback.Dir;$result=Invoke-Fixture $fallback "$other`:chair:ephemeral"
  Assert-True ($result.Rc -eq 0) 'PowerShell other-chair failure reruns all-main'
  Assert-True ((Get-Content -Raw $result.Receipt) -match 'trigger_reason=runtime-other-failure') 'PowerShell fallback reason is visible'
  Assert-True (($result.Output -join "`n") -match "injected failure: $other`:chair:ephemeral") 'PowerShell failure diagnostics survive attempt removal'
  $attemptDirectories=@(Get-ChildItem (Split-Path (Split-Path $result.Receipt)) -Directory)
  $fallbackDirectories=@($attemptDirectories|Where-Object{$_.Name -like 'same-engine-fallback-*'})
  Assert-True ($fallbackDirectories.Count -eq 1 -and (Split-Path -Parent $result.Receipt) -eq $fallbackDirectories[0].FullName) 'PowerShell returns only the successful fallback receipt'
  Assert-True (@(Get-Content $fallback.Log|Select-Object -Last 11|Where-Object{$_ -notlike "$script:CouncilMain|*"}).Count -eq 0) 'PowerShell fallback reruns all seats on main'
  $simultaneous=New-Fixture simultaneous;$fixtures+=$simultaneous.Dir;$env:FAKE_MAIN_FAIL='yes';$result=Invoke-Fixture $simultaneous "$other`:contrarian:new"
  Assert-True ($result.Rc -ne 0 -and @(Get-Content $simultaneous.Log).Count -eq 5) 'PowerShell main failure takes precedence after collecting the complete wave'
  $env:FAKE_MAIN_FAIL=''
  foreach($failure in @("$other`:contrarian:new","$other`:contrarian:resume","$script:CouncilMain`:simplifier:new")){
    $cleanup=New-Fixture cleanup;$fixtures+=$cleanup.Dir
    $reviews=Join-Path $cleanup.Repo '.forge/local/reviews';$unrelated=Join-Path $reviews 'session-stores/unrelated'
    New-Item -ItemType Directory -Path $unrelated -Force|Out-Null
    Set-Content -LiteralPath (Join-Path $unrelated 'sentinel') 'keep unrelated session'
    $result=Invoke-Fixture $cleanup $failure
    Assert-True (($failure -like "$script:CouncilMain`:*" -and $result.Rc -ne 0) -or ($failure -like "$other`:*" -and $result.Rc -eq 0)) "PowerShell $failure keeps the expected topology result"
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $reviews 'session-stores') -Directory).Count -eq 1) "PowerShell $failure removes all and only attempt-owned stores"
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $reviews 'sessions') -Filter '*.meta'|Select-String -SimpleMatch 'completed=false').Count -eq 0) "PowerShell $failure leaves no abandoned resumable sessions"
    Assert-True ((Get-Content -LiteralPath (Join-Path $unrelated 'sentinel')) -eq 'keep unrelated session') "PowerShell $failure preserves unrelated private input"
  }
  $absent=New-Fixture absent $false;$fixtures+=$absent.Dir
  $savedPath=$originalPath
  try {
    if($env:OS -eq 'Windows_NT') {
      $originalPath=$gitBin+[IO.Path]::PathSeparator+$env:SystemRoot+'\System32'
    } else {
      $gitExecutable=(Get-Command git -CommandType Application | Select-Object -First 1).Source
      New-Item -ItemType SymbolicLink -Path (Join-Path $absent.Bin 'git') -Target $gitExecutable | Out-Null
      $originalPath='/usr/bin:/bin'
    }
    $result=Invoke-Fixture $absent
  } finally {$originalPath=$savedPath}
  Assert-True ($result.Rc -eq 0) 'PowerShell known other absence starts all-main'
  Assert-True ((Get-Content -Raw $result.Receipt) -match 'trigger_reason=known-other-unavailable') 'PowerShell known absence is visible'
  Assert-True (@(Get-Content $absent.Log|Where-Object {$_ -notlike "$script:CouncilMain|*"}).Count -eq 0) 'PowerShell known absence uses only main'
  }
  $script:CouncilMain='claude'
  $linked=New-Fixture linked;$fixtures+=$linked.Dir;$outside=Join-Path $linked.Dir 'outside-council';New-Item -ItemType Directory -Path $outside|Out-Null
  $capture=New-Fixture snapshot;$fixtures+=$capture.Dir
  & git -C $capture.Repo config user.name ForgeTest
  & git -C $capture.Repo config user.email test@example.invalid
  & git -C $capture.Repo add -- artifact.txt question.txt
  & git -C $capture.Repo commit -qm base
  $repoRoot=(Resolve-Path (& git -C $capture.Repo rev-parse --show-toplevel)).Path;$base=(& git -C $capture.Repo rev-parse HEAD)
  $store=[IO.Path]::GetFullPath((Join-Path $repoRoot '.forge/local/reviews/session-stores/owned'))
  New-Item -ItemType Directory -Path $store -Force|Out-Null
  $state="<!-- forge:state-schema v6 -->`n## Identity`n| Field | Value |`n| Worktree root | $repoRoot |`n| Git common directory | $(Join-Path $repoRoot '.git') |`n| Workflow base ref | $base |`n| Workflow base SHA | $base |`n"
  [IO.File]::WriteAllText((Join-Path $repoRoot '.forge/local/state.md'),$state)
  $fingerprint=Join-Path $root 'hooks/lib/candidate-fingerprint.ps1';$captured=Join-Path $repoRoot '.forge/local/owned.candidate'
  Push-Location $repoRoot
  try {
    & $powershellExe -NoProfile -File $fingerprint -Mode capture -Artifact git:working-tree -WorkflowBaseSha $base -WorkflowBaseRef $base -Output $captured -SnapshotParent $store
    Assert-True ($LASTEXITCODE -eq 0) 'PowerShell real candidate capture succeeds inside the owned session store'
    $snapshot=((Get-Content -LiteralPath $captured|Where-Object {$_ -like 'snapshot_path=*'}) -replace '^snapshot_path=','')
    Assert-True ($snapshot.StartsWith($store+[IO.Path]::DirectorySeparatorChar)) 'PowerShell private repository copy is bound to the session lifecycle'
    Assert-True ((Get-Content -LiteralPath (Join-Path $snapshot 'artifact.txt')) -eq 'candidate') 'PowerShell owned snapshot preserves the actual candidate content'
    $savedPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try {& $powershellExe -NoProfile -File $fingerprint -Mode capture -Artifact git:working-tree -WorkflowBaseSha $base -WorkflowBaseRef $base -Output $captured -SnapshotParent $capture.Dir 2>&1|Out-Null;$outsideRc=$LASTEXITCODE} finally {$ErrorActionPreference=$savedPreference}
    Assert-True ($outsideRc -ne 0) 'PowerShell snapshot capture rejects a parent outside session storage'
  } finally {Pop-Location}
  $qhash=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $linked.Repo 'question.txt')).Hash.ToLowerInvariant();$reviews=Join-Path $linked.Repo '.forge\local\reviews';New-Item -ItemType Directory -Path $reviews -Force|Out-Null
  if($env:OS -eq 'Windows_NT') {& cmd.exe /d /c mklink /J "$(Join-Path $reviews "council-$qhash")" "$outside"|Out-Null}
  else {New-Item -ItemType SymbolicLink -Path (Join-Path $reviews "council-$qhash") -Target $outside|Out-Null}
  $result=Invoke-Fixture $linked
  Assert-True ((($result.Output|Out-String) -match 'council receipt storage ancestors must be no-follow directories')) 'PowerShell linked council receipt root blocks before dispatch'
  Assert-True (@(Get-ChildItem -LiteralPath $outside -Force).Count -eq 0) 'PowerShell linked council target remains untouched'
}
finally{$env:PATH=$originalPath;Remove-Item Env:FAKE_PARALLEL_PROBE,Env:FAKE_MAIN_FAIL,Env:FAKE_NO_FINAL_NEWLINE -ErrorAction SilentlyContinue;foreach($dir in $fixtures){Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}}
Write-Host "PASS: $passes council dispatcher PowerShell assertions"
