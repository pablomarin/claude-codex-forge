# Portable PS7 fixture: real dispatcher; POSIX engine/process shims are not native evidence.
param([Parameter(Mandatory=$true)][string]$SourceRoot, [Parameter(Mandatory=$true)][string]$WorkDirectory, [Parameter(Mandatory=$true)][string]$BinDirectory, [Parameter(Mandatory=$true)][string]$CaseName, [Parameter(Mandatory=$true)][string]$Behavior, [int]$TimeoutSeconds=30)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$dispatcher = Join-Path $root 'hooks/lib/agent-dispatch.ps1'; $hostContext = Join-Path $root 'hooks/lib/host-context.ps1'
$bin = $BinDirectory
$temporary = Join-Path $WorkDirectory ("$CaseName-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $temporary -Force | Out-Null
function Sha([byte[]]$b) { $s = [Security.Cryptography.SHA256]::Create(); try { ([BitConverter]::ToString($s.ComputeHash($b))).Replace('-', '').ToLowerInvariant() } finally { $s.Dispose() } }
function ShaText([string]$t) { Sha ([Text.Encoding]::UTF8.GetBytes($t)) }
function ShaFile([string]$p) { Sha ([IO.File]::ReadAllBytes($p)) }
function Report([bool]$ok, [string]$msg) { if (-not $ok) { throw "portable boundary failed: $msg" }; Write-Host "PASS boundary: $msg" }

# New-Repository / Set-State equivalents (test-agent-dispatch.ps1:33-47)
$repo = Join-Path $temporary 'reproduction boundary'
New-Item -ItemType Directory -Path (Join-Path $repo '.forge/local/reviews') -Force | Out-Null
& git -C $repo init -q; & git -C $repo config user.email test@example.invalid; & git -C $repo config user.name ForgeTest
[IO.File]::WriteAllText((Join-Path $repo 'app.txt'), "base`n")
Copy-Item -LiteralPath (Join-Path $root 'manifests/managed-v6.tsv') -Destination (Join-Path $repo '.forge/managed-files.tsv')
& git -C $repo add app.txt .forge/managed-files.tsv; & git -C $repo commit -qm base
$base = (& git -C $repo rev-parse HEAD); $rootPath = (Resolve-Path $repo).Path; $common = (Resolve-Path (Join-Path $repo (& git -C $repo rev-parse --git-common-dir))).Path
[IO.File]::WriteAllText((Join-Path $repo '.forge/local/state.md'), "<!-- forge:state-schema v6 -->`n# Project State`n`n## Identity`n`n| Field | Value |`n| --- | --- |`n| Worktree root | $rootPath |`n| Git common directory | $common |`n| Last active host | claude |`n| Workflow base ref | refs/heads/test-base |`n| Workflow base SHA | $base |`n`n## Workflow`n`n## Receipts`n| Field | Value |`n| Review iteration | 1 |`n")

# Fixture (test-agent-dispatch.ps1:472-479)
$auth = Join-Path $temporary 'protected-auth.json'; [IO.File]::WriteAllText($auth, "protected-auth`n"); $outside = Join-Path $temporary 'reproduction-external'
$state = Join-Path $repo '.forge/local/state.md'; $stateHash = ShaFile $state; $authHash = ShaFile $auth
$program = Join-Path $repo 'boundary-repro.exe'
[IO.File]::WriteAllText($program, "#!/bin/sh`nif [ -n `"`${HTTPS_PROXY+x}`" ]; then exit 62; fi`nif [ `"`$FORGE_REPRO_NO_NETWORK`" != `"1`" ]; then printf 'escaped\n' >> '$state'; printf 'escaped\n' >> '$auth'; printf 'escaped\n' > '$outside'; fi`nif [ `"`$1`" = primary ]; then echo MATCH; else echo CONTROL; fi`nexit 0`n")
& chmod +x $program
$match = ShaText ("MATCH" + [Environment]::NewLine); $control = ShaText ("CONTROL" + [Environment]::NewLine)
$prompt = Join-Path $repo '.forge/local/reviews/prompt.txt'
[IO.File]::WriteAllText($prompt, "schema_version=1`nhypothesis=qualified boundary`nprimary_program=boundary-repro.exe`nprimary_arg=primary`nprimary_expected_exit=0`nprimary_expected_output_hash=$match`ncontrol_program=boundary-repro.exe`ncontrol_arg=control`ncontrol_expected_exit=0`ncontrol_expected_output_hash=$control`n")
$reproLog = Join-Path $repo '.forge/local/reviews/repro.log'

# Invoke-Dispatch equivalent (test-agent-dispatch.ps1:48-65, 79-84)
$launcher = Join-Path $temporary 'launch-host-context.ps1'
[IO.File]::WriteAllText($launcher, "param([string]`$ContextPath, [string]`$EngineHost, [string]`$ArgumentsJsonPath)`n`$argumentsJson = [IO.File]::ReadAllText(`$ArgumentsJsonPath)`n& `$ContextPath -Mode launch -Host `$EngineHost -LaunchArgumentsJson `$argumentsJson`nexit `$LASTEXITCODE`n")
$output = Join-Path $repo '.forge/local/reviews/result-1.txt'
$arguments = @('-Mode','run','-Engine','codex','-FallbackPolicy','none','-Role','investigation-repro','-Profile','investigate','-Artifact','git:working-tree','-WorkflowBaseSha',$base,'-WorkflowBaseRef','refs/heads/test-base','-PromptFile',$prompt,'-Output',$output,'-Conversation','ephemeral','-TimeoutSeconds',[string]$TimeoutSeconds)
$argumentsJson = Join-Path $repo '.forge/local/reviews/launch-1.json'; [IO.File]::WriteAllText($argumentsJson, ($arguments | ConvertTo-Json -Compress))
$start = New-Object Diagnostics.ProcessStartInfo ((Get-Process -Id $PID).Path)
foreach ($a in @('-NoProfile','-File',$launcher,$hostContext,'claude',$argumentsJson)) { $start.ArgumentList.Add($a) }
$start.WorkingDirectory = $repo; $start.UseShellExecute = $false; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
$e = $start.Environment
$e['PATH'] = "${bin}:" + $env:PATH; $e['FORGE_HOST_CONTEXT_TEST_MODE'] = '1'; $e['FORGE_HOST_CONTEXT_TEST_LAUNCHER'] = $dispatcher; $e['FORGE_DISPATCH_TEST_MODE'] = '1'
$e['FORGE_CODEX_AUTH_FILE'] = $auth; $e['FAKE_CODEX_BEHAVIOR'] = $Behavior; $e['FAKE_CODEX_LOG'] = $reproLog; $e['HTTPS_PROXY'] = 'http://127.0.0.1:9'
$clock = [Diagnostics.Stopwatch]::StartNew()
$p = [Diagnostics.Process]::Start($start); $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync(); $handle = $p.Handle; if (-not $p.WaitForExit(45000)) { $p.Kill($true); $ignored = $p.WaitForExit(5000); throw 'portable dispatcher outer deadline expired' }; $clock.Stop()
$rc = $p.ExitCode; $stdout = $so.Result; $stderr = $se.Result

Write-Host "CASE $CaseName behavior=$Behavior timeout=$TimeoutSeconds elapsed_s=$([Math]::Round($clock.Elapsed.TotalSeconds,1)) rc=$rc stderr_bytes=$($stderr.Length)"
if ($stderr) { Write-Host "  child stderr: $($stderr.Trim() -replace '[\r\n]+',' | ')" }
Write-Host "  child stdout: $($stdout.Trim() -replace '[\r\n]+',' | ')"
$receipt = Get-ChildItem -LiteralPath (Join-Path $repo '.forge/local/reviews') -Filter '*.receipt' | Sort-Object LastWriteTimeUtc, Name | Select-Object -Last 1
if ($receipt) {
    $lines = Get-Content -LiteralPath $receipt.FullName
    foreach ($k in @('actual_engine','attempted_engines','fallback','process_exit_status','semantic_verdict','blocked_class','failure_reason','reproduction_status','primary_check_hash','control_hash')) { Write-Host ("  receipt {0}" -f (@($lines | Where-Object { $_ -like "$k=*" })[0])) }
} else { Write-Host '  receipt: NONE' }
$launches = if (Test-Path -LiteralPath $reproLog) { @(Get-Content -LiteralPath $reproLog | Where-Object { $_ -like 'cwd=*' }).Count } else { 0 }
Write-Host "  fake codex launches=$launches"
if (-not $receipt) { throw 'actual dispatcher receipt missing' }
$fields = @{}; foreach ($line in $lines) { if ($line -match '^([^=]+)=(.*)$') { $fields[$Matches[1]]=$Matches[2] } }
if ($Behavior -eq 'repro-boundary') {
    Report ($rc -eq 0) 'positive dispatcher exit zero'
    Report ($fields.reproduction_status -ceq 'REPRODUCED') 'positive actual reproduced status'
    Report ($fields.primary_check_hash -ceq '573645001e97c1fac372ffaeeef2b6eb9c4bc1caa7c28069c4203ea159f29bc4' -and $fields.control_hash -ceq 'dc8fc650d354d9bed81e65cb094ece651f71ed854abc3738e41b0384245e6abf') 'literal MATCH and CONTROL hashes'
    Report ($launches -eq 2) 'primary and control each execute the actual runner'
} else {
    Report ($rc -eq 2) 'timed out dispatcher returns two'
    Report ($fields.reproduction_status -ceq 'UNVERIFIED') 'timed out reproduction remains unverified'
    Report ($fields.failure_reason -ceq 'timeout' -and $fields.process_exit_status -ceq '124') 'actual timeout reason and process exit124'
    Report ($fields.primary_check_hash -ceq 'MISSING' -and $fields.control_hash -ceq 'MISSING') 'timed out attempt cannot certify either output'
    Report ($launches -eq 1) 'failed primary does not run the control'
}
Report ((ShaFile $state) -ceq $stateHash) 'Forge state byte-identical'
Report ((ShaFile $auth) -ceq $authHash) 'protected auth byte-identical'
Report (-not (Test-Path -LiteralPath $outside)) 'cannot write outside disposable candidate'
Report ((Get-Content -LiteralPath $reproLog -Raw) -like '*--sandbox workspace-write*') 'qualified no-network workspace argv'
# The parent validates actual descendant PIDs and literal receipt values independently.
Copy-Item -LiteralPath $receipt.FullName -Destination (Join-Path $WorkDirectory "$CaseName.receipt")
Copy-Item -LiteralPath $reproLog -Destination (Join-Path $WorkDirectory "$CaseName.engine.log")
Write-Host "PASS: portable actual boundary $CaseName; runtime $($PSVersionTable.PSVersion), native Windows unverified"
