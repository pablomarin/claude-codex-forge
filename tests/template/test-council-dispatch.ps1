$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source = Join-Path $root 'hooks\lib\council-dispatch.ps1'
$passes = 0
function Assert-True([bool]$Condition,[string]$Message) { if(!$Condition){throw $Message};$script:passes++;Write-Host "  PASS: $Message" }
function New-Fixture([string]$Name) {
  $dir=Join-Path ([IO.Path]::GetTempPath()) ("forge-council-$Name-"+[Guid]::NewGuid().ToString('N'));$repo=Join-Path $dir 'repo';$lib=Join-Path $repo '.forge\hooks\lib';$bin=Join-Path $dir 'bin'
  New-Item -ItemType Directory -Force -Path $lib,(Join-Path $repo '.forge\manifests'),$bin|Out-Null
  Copy-Item -LiteralPath $source -Destination (Join-Path $lib 'council-dispatch.ps1')
  @'
param([string]$Mode)
Write-Output $(if($env:FAKE_MAIN){$env:FAKE_MAIN}else{'claude'})
'@ | Set-Content (Join-Path $lib 'host-context.ps1')
  @("model-council-advisor`tclaude`tqualified","model-council-chair`tclaude`tqualified","model-council-advisor`tcodex`tqualified","model-council-chair`tcodex`tqualified")|Set-Content (Join-Path $repo '.forge\manifests\host-capabilities.tsv')
  @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
# Task-5 preflight markers: 'resume' SessionId
$engine='';$role='';$seat='';$conversation='';$prompt='';$output='';$sessionOut='';$sessionId=''
for($i=1; $i -lt $Arguments.Count;){$key=$Arguments[$i];$value=$Arguments[$i+1];switch($key){'--engine'{$engine=$value};'--role'{$role=$value};'--seat-id'{$seat=$value};'--conversation'{$conversation=$value};'--prompt-file'{$prompt=$value};'--output'{$output=$value};'--session-id-output'{$sessionOut=$value};'--session-id'{$sessionId=$value}};$i+=2}
Add-Content -LiteralPath $env:FAKE_LOG -Value "$engine|$role|$seat|$conversation|$sessionId"
$match="$engine`:$seat`:$conversation";if($env:FAKE_FAIL_MATCH -eq $match -and !(Test-Path $env:FAKE_FAIL_MARKER)){New-Item -ItemType File -Path $env:FAKE_FAIL_MARKER|Out-Null;exit 17}
if($conversation -eq 'new'){Set-Content -LiteralPath $sessionOut -Value "sid-$seat"};if($conversation -eq 'resume' -and $sessionId -ne "sid-$seat"){exit 18}
if($role -eq 'council-chair'){if((Get-Content -Raw $prompt) -notmatch 'Anonymous peer reviews:'){exit 19}}
@('schema_version=1','verdict=CLEAN','max_severity=NONE','blocked_class=none',"engine=$engine","author=$seat")|Set-Content -LiteralPath $output
exit 0
'@ | Set-Content (Join-Path $lib 'agent-dispatch.ps1')
  '@exit /b 0'|Set-Content (Join-Path $bin 'claude.cmd');'@exit /b 0'|Set-Content (Join-Path $bin 'codex.cmd')
  Push-Location $repo;try{& git init -q;Set-Content question.txt 'Should Forge choose this design?';Set-Content artifact.txt 'candidate'}finally{Pop-Location}
  return @{Dir=$dir;Repo=$repo;Bin=$bin;Log=(Join-Path $dir 'calls.log');Council=(Join-Path $lib 'council-dispatch.ps1')}
}
function Invoke-Fixture([hashtable]$Fixture,[string]$Failure='',[string[]]$Extra=@()) {
  $gitDir=Split-Path -Parent (Get-Command git.exe).Source;$env:PATH="$($Fixture.Bin);$gitDir;$env:SystemRoot\System32";$env:FAKE_MAIN='claude';$env:FAKE_LOG=$Fixture.Log;$env:FAKE_FAIL_MATCH=$Failure;$env:FAKE_FAIL_MARKER=Join-Path $Fixture.Dir 'failure-used'
  $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$Fixture.Council,'--question-file',(Join-Path $Fixture.Repo 'question.txt'),'--artifact',(Join-Path $Fixture.Repo 'artifact.txt'),'--workflow-base-sha','deadbeef','--workflow-base-ref','refs/heads/main')+$Extra
  $output=& powershell.exe @args 2>&1;$rc=$LASTEXITCODE;return @{Rc=$rc;Output=@($output);Receipt=(@($output|Where-Object{$_ -like 'Council receipt:*'})[-1] -replace '^Council receipt: ','')}
}
$originalPath=$env:PATH;$fixtures=@()
try {
  $healthy=New-Fixture healthy;$fixtures+=$healthy.Dir;$result=Invoke-Fixture $healthy
  Assert-True ($result.Rc -eq 0) 'healthy PowerShell topology succeeds'
  Assert-True (@(Get-Content $healthy.Log).Count -eq 11) 'PowerShell dispatches eleven turns'
  Assert-True ((Get-Content -Raw $result.Receipt) -match 'turn_results=11') 'PowerShell receipt binds eleven turns'
  Assert-True ((Get-Content -Raw (Join-Path (Split-Path $result.Receipt) 'anonymous-peer-reviews.txt')) -notmatch 'simplifier') 'PowerShell peer bundle is anonymous'
  $fallback=New-Fixture fallback;$fixtures+=$fallback.Dir;$result=Invoke-Fixture $fallback 'codex:chair:ephemeral'
  Assert-True ($result.Rc -eq 0) 'PowerShell other-chair failure reruns all-main'
  Assert-True ((Get-Content -Raw $result.Receipt) -match 'trigger_reason=runtime-other-failure') 'PowerShell fallback reason is visible'
  Assert-True (@((Get-ChildItem (Split-Path (Split-Path $result.Receipt)) -Directory)).Count -eq 1) 'PowerShell discards failed mixed artifacts'
  Assert-True (@(Get-Content $fallback.Log|Select-Object -Last 11|Where-Object{$_ -notlike 'claude|*'}).Count -eq 0) 'PowerShell fallback reruns all seats on main'
}
finally{$env:PATH=$originalPath;foreach($dir in $fixtures){Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}}
Write-Host "PASS: $passes council dispatcher PowerShell assertions"
