$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runner = Join-Path $root 'scripts\qualify-runtime-final.ps1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('forge-runtime-schema-' + [Guid]::NewGuid().ToString('N'))
function Assert-True([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};Write-Host "  PASS: $Message"}

Assert-True (Test-Path -LiteralPath $runner -PathType Leaf) 'PowerShell final qualifier exists'
New-Item -ItemType Directory -Path $temporary -Force | Out-Null
try {
    $project=Join-Path $temporary 'project';$bin=Join-Path $temporary 'bin';$output=Join-Path $temporary 'final.receipt'
    New-Item -ItemType Directory -Path (Join-Path $project '.forge'),$bin -Force|Out-Null
    & git -C $project init -q;& git -C $project config user.email forge@example.invalid;& git -C $project config user.name Forge
    [IO.File]::WriteAllText((Join-Path $project 'app.txt'),"candidate`n");& git -C $project add app.txt;& git -C $project commit -qm base
    $fake=@'
using System;
using System.IO;
public static class ForgeRuntimeFake {
 static string E(string n){return Environment.GetEnvironmentVariable(n)??"";}
 public static int Main(string[] args){
  if(args.Length>0 && args[0]=="--version"){Console.WriteLine("runtime fixture 1");return 0;}
  string dispatch=E("FORGE_DISPATCH_FIXTURE_ACTION");
  if(dispatch!=""){
   if(dispatch=="ephemeral") Console.WriteLine("ephemeral:"+E("FORGE_DISPATCH_SENTINEL")+":canary=false");
   else if(dispatch=="council-start"){Directory.CreateDirectory(E("FORGE_DISPATCH_SESSION_STORE"));File.WriteAllText(Path.Combine(E("FORGE_DISPATCH_SESSION_STORE"),E("FORGE_DISPATCH_SESSION_ID")),E("FORGE_DISPATCH_SEAT_HASH"));}
   else if(dispatch=="council-resume"){if(File.ReadAllText(Path.Combine(E("FORGE_DISPATCH_SESSION_STORE"),E("FORGE_DISPATCH_SESSION_ID"))).Trim()!=E("FORGE_DISPATCH_SEAT_HASH"))return 18;}
   else if(dispatch=="investigate"){var d=Path.Combine(E("FORGE_DISPATCH_INVESTIGATION_ROOT"),"artifacts");Directory.CreateDirectory(d);File.WriteAllText(Path.Combine(d,"qualification.txt"),"bounded-reproduction\n");}
   return 0;
  }
  string goal=E("FORGE_GOAL_FIXTURE_ACTION"),dir=E("FORGE_GOAL_FIXTURE_DIR"),sid=E("FORGE_GOAL_SESSION_ID");
  if(goal=="activate"){File.WriteAllText(Path.Combine(dir,"checkpoint"),"phase=implementation\nnext_step=resume-verification\nsession_id="+sid+"\n");Console.WriteLine("native-activation:"+sid);return 0;}
  if(goal=="resume"){File.WriteAllText(Path.Combine(dir,"checkpoint"),"phase=verification\nnext_step=budget-check\nsession_id="+sid+"\n");Console.WriteLine("checkpoint-resume:"+sid);return 0;}
  return 64;
 }
}
'@
    Add-Type -TypeDefinition $fake -Language CSharp -OutputAssembly (Join-Path $bin 'runtime-fake.exe') -OutputType ConsoleApplication
    Copy-Item (Join-Path $bin 'runtime-fake.exe') (Join-Path $bin 'claude.exe');Copy-Item (Join-Path $bin 'runtime-fake.exe') (Join-Path $bin 'codex.exe')
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -FixtureMode -ProjectRoot $project -Output $output -EngineDir $bin | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'fixture qualification stays non-certifying'
    Assert-True ((Get-Content -Raw $output) -match '(?m)^evidence_mode=fixture\r?$') 'fixture source is explicit'
    Assert-True ((Get-Content -Raw $output) -match '(?m)^overall_status=BLOCKED\r?$') 'fixture cannot certify PASS'
    $validationOutput=(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Validate -Input $output 2>&1 | Out-String);$validationCode=$LASTEXITCODE
    Assert-True ($validationCode -eq 0) "fixture receipt validates structurally: $($validationOutput.Trim())"
    $fakePass=Join-Path $temporary 'fake-pass.receipt';(Get-Content $output)|ForEach-Object{if($_ -eq 'overall_status=BLOCKED'){'overall_status=PASS'}else{$_}}|Set-Content $fakePass
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Validate -Input $fakePass *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'fixture PASS is rejected'
    $child=((Get-Content $output|Where-Object{$_ -like 'claude_dispatch_path=*'}) -replace '^claude_dispatch_path=','');Add-Content $child ''
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Validate -Input $output *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'child hash mismatch is rejected'

    $windows=Join-Path $temporary 'windows-clean.receipt'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -WriteWindowsAttestation -ProjectRoot $project -Output $windows *> $null
    Assert-True ($LASTEXITCODE -eq 0 -and (Get-Content -Raw $windows) -match '(?m)^candidate_clean=true\r?$') 'clean Windows writer records candidate cleanliness'
    Add-Content -LiteralPath (Join-Path $project 'app.txt') -Value 'dirty tracked'
    $savedPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -WriteWindowsAttestation -ProjectRoot $project -Output (Join-Path $temporary 'windows-dirty.receipt') *> $null;$dirtyCode=$LASTEXITCODE}finally{$ErrorActionPreference=$savedPreference}
    Assert-True ($dirtyCode -ne 0) 'Windows writer rejects tracked dirtiness'
    [IO.File]::WriteAllText((Join-Path $project 'app.txt'),"candidate`n");[IO.File]::WriteAllText((Join-Path $project 'untracked.txt'),"untracked`n")
    $savedPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -WriteWindowsAttestation -ProjectRoot $project -Output (Join-Path $temporary 'windows-untracked.receipt') *> $null;$untrackedCode=$LASTEXITCODE}finally{$ErrorActionPreference=$savedPreference}
    Assert-True ($untrackedCode -ne 0) 'Windows writer rejects untracked dirtiness'
    Remove-Item -LiteralPath (Join-Path $project 'untracked.txt')

    $noClean=Join-Path $temporary 'windows-no-clean.receipt';$head=(& git -C $project rev-parse HEAD);$tree=(& git -C $project rev-parse 'HEAD^{tree}')
    [IO.File]::WriteAllLines($noClean,@('format=forge-windows-deterministic-v1','status=PASS','powershell_major=5','powershell_minor=1',"git_head=$head","tree_sha=$tree"))
    $noCleanFinal=Join-Path $temporary 'no-clean-final.receipt'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -FixtureMode -ProjectRoot $project -Output $noCleanFinal -EngineDir $bin -WindowsAttestation $noClean *> $null
    Assert-True ((Get-Content -Raw $noCleanFinal) -match '(?m)^windows_status=PENDING\r?$') 'final validator rejects Windows PASS without candidate_clean'

    $hangBin=Join-Path $temporary 'hanging-bin';New-Item -ItemType Directory -Path $hangBin|Out-Null;$hangMarker=Join-Path $temporary 'hang-used'
    $hangSource=@'
using System;
using System.IO;
using System.Threading;
public static class ForgeRuntimeHang {
 public static int Main(string[] args){
  if(args.Length>0 && args[0]=="--version"){Console.WriteLine("runtime hang 1");return 0;}
  if(args.Length>0 && (args[0]=="--help" || (args[0]=="exec" && args.Length>1 && args[1]=="--help"))){Console.WriteLine("--safe-mode --strict-mcp-config --setting-sources --session-id --resume --no-session-persistence --add-dir --ignore-user-config --ignore-rules --ephemeral --sandbox --json --disable");return 0;}
  if(Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]).Equals("claude",StringComparison.OrdinalIgnoreCase) && !File.Exists(Environment.GetEnvironmentVariable("FORGE_RUNTIME_HANG_MARKER"))){File.WriteAllText(Environment.GetEnvironmentVariable("FORGE_RUNTIME_HANG_MARKER"),"used");Thread.Sleep(10000);}
  return 23;
 }
}
'@
    Add-Type -TypeDefinition $hangSource -Language CSharp -OutputAssembly (Join-Path $hangBin 'runtime-hang.exe') -OutputType ConsoleApplication
    Copy-Item (Join-Path $hangBin 'runtime-hang.exe') (Join-Path $hangBin 'claude.exe');Copy-Item (Join-Path $hangBin 'runtime-hang.exe') (Join-Path $hangBin 'codex.exe')
    $savedPath=$env:PATH;$env:PATH="$hangBin;$savedPath";$env:FORGE_RUNTIME_HANG_MARKER=$hangMarker;$timeoutOutput=Join-Path $temporary 'timeout-final.receipt';$clock=[Diagnostics.Stopwatch]::StartNew()
    try{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Live -ProjectRoot $project -Output $timeoutOutput -EngineDir $hangBin -QualificationTimeoutSeconds 1 *> $null;$timeoutRc=$LASTEXITCODE}finally{$clock.Stop();$env:PATH=$savedPath;Remove-Item Env:FORGE_RUNTIME_HANG_MARKER -ErrorAction SilentlyContinue}
    Assert-True ($timeoutRc -ne 0 -and $clock.Elapsed.TotalSeconds -lt 8) 'authenticated PowerShell child qualification timeout is bounded and BLOCKED'
    Assert-True ((Get-Content -Raw "$timeoutOutput.d\claude-dispatch.json") -match 'qualification child timeout') 'PowerShell timeout emits a truthful child receipt'
} finally {Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'PASS: PowerShell runtime qualification schema'
