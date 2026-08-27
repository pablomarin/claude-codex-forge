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
    Assert-True ((Get-Content -Raw $output) -match '(?m)^evidence_mode=fixture$') 'fixture source is explicit'
    Assert-True ((Get-Content -Raw $output) -match '(?m)^overall_status=BLOCKED$') 'fixture cannot certify PASS'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Validate -Input $output | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'fixture receipt validates structurally'
    $fakePass=Join-Path $temporary 'fake-pass.receipt';(Get-Content $output)|ForEach-Object{if($_ -eq 'overall_status=BLOCKED'){'overall_status=PASS'}else{$_}}|Set-Content $fakePass
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Validate -Input $fakePass *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'fixture PASS is rejected'
    $child=((Get-Content $output|Where-Object{$_ -like 'claude_dispatch_path=*'}) -replace '^claude_dispatch_path=','');Add-Content $child ''
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Validate -Input $output *> $null
    Assert-True ($LASTEXITCODE -ne 0) 'child hash mismatch is rejected'
} finally {Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'PASS: PowerShell runtime qualification schema'
