$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$dispatcher = Join-Path $root 'hooks/lib/agent-dispatch.ps1'
$hostContext = Join-Path $root 'hooks/lib/host-context.ps1'
$fingerprint = Join-Path $root 'hooks/lib/candidate-fingerprint.ps1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('Forge Dispatch PS ' + [Guid]::NewGuid().ToString('N'))
$bin = Join-Path $temporary 'fake engines'
$contextLauncher = Join-Path $temporary 'launch-host-context.ps1'
$script:Passed = 0; $script:Failed = 0
$script:DispatchSequence = 0

function Pass([string]$Message) { $script:Passed++; Write-Host "  PASS $Message" }
function Fail([string]$Message) { $script:Failed++; [Console]::Error.WriteLine("  FAIL $Message") }
function Assert-Equal($Actual, $Expected, [string]$Message) { if ([string]$Actual -ceq [string]$Expected) { Pass $Message } else { Fail "$Message expected=$Expected actual=$Actual" } }
function Assert-Contains([string]$Path, [string]$Needle, [string]$Message) { if ((Get-Content -LiteralPath $Path -Raw) -like "*$Needle*") { Pass $Message } else { Fail "$Message missing=$Needle" } }
function Assert-NotContains([string]$Path, [string]$Needle, [string]$Message) { if ((Get-Content -LiteralPath $Path -Raw) -notlike "*$Needle*") { Pass $Message } else { Fail "$Message unexpected=$Needle" } }
function Get-ReceiptValue([string]$Repository, [string]$Key) { $receipt = Get-ChildItem -LiteralPath (Join-Path $Repository '.forge/local/reviews') -Filter '*.receipt' | Sort-Object LastWriteTimeUtc, Name | Select-Object -Last 1; $line = Get-Content -LiteralPath $receipt.FullName | Where-Object { $_ -like "$Key=*" } | Select-Object -First 1; return $line.Substring($Key.Length + 1) }
function Get-LatestReceipt([string]$Repository) { return (Get-ChildItem -LiteralPath (Join-Path $Repository '.forge/local/reviews') -Filter '*.receipt' | Sort-Object LastWriteTimeUtc, Name | Select-Object -Last 1).FullName }
function New-Repository([string]$Name) {
    $path = Join-Path $temporary $Name
    New-Item -ItemType Directory -Path (Join-Path $path '.forge/local/reviews'), (Join-Path $path '.forge') -Force | Out-Null
    & git -C $path init -q; & git -C $path config user.email test@example.invalid; & git -C $path config user.name ForgeTest
    [IO.File]::WriteAllText((Join-Path $path 'app.txt'), "base`n")
    Copy-Item -LiteralPath (Join-Path $root 'manifests/managed-v6.tsv') -Destination (Join-Path $path '.forge/managed-files.tsv')
    & git -C $path add app.txt .forge/managed-files.tsv; & git -C $path commit -qm base
    Set-State $path (& git -C $path rev-parse HEAD) 'refs/heads/test-base'
    return $path
}
function Set-State([string]$Repository, [string]$Base, [string]$BaseRef) {
    $rootPath = (Resolve-Path $Repository).Path; $commonRelative = (& git -C $Repository rev-parse --git-common-dir); $common = (Resolve-Path (Join-Path $Repository $commonRelative)).Path
    $body = "<!-- forge:state-schema v6 -->`n# Project State`n`n## Identity`n`n| Field | Value |`n| --- | --- |`n| Worktree root | $rootPath |`n| Git common directory | $common |`n| Last active host | claude |`n| Workflow base ref | $BaseRef |`n| Workflow base SHA | $Base |`n`n## Workflow`n`n## Receipts`n| Field | Value |`n| Review iteration | 1 |`n"
    [IO.File]::WriteAllText((Join-Path $Repository '.forge/local/state.md'), $body)
}
function Set-Context([string]$Repository, [string]$EngineHost, [string]$Session) {
    $env:FORGE_HOST_CONTEXT_TEST_MODE = '1'; $env:FORGE_HOST_CONTEXT_TEST_ROOT = Join-Path $Repository '.forge/local/test-host-authority'; $env:FORGE_HOST_CONTEXT_TEST_LAUNCHER = $dispatcher
    Push-Location $Repository
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hostContext -Mode issue-test -Host $EngineHost -SessionId $Session | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'context capture failed' } }
    finally { Pop-Location }
}
function Invoke-Dispatch([string]$Repository, [string]$EngineHost, [string]$Session, [string]$Requested, [string]$Role = 'general', [string]$Fallback = 'automatic', [string]$Conversation = 'ephemeral', [string]$ExactSession = '', [string]$SessionOutput = '', [string]$PromptText = '', [string]$OutputPath = '') {
    Set-Context $Repository $EngineHost $Session
    $script:DispatchSequence++; $prompt = Join-Path $Repository '.forge/local/reviews/prompt.txt'
    if ($PromptText) { [IO.File]::WriteAllText($prompt, $PromptText) }
    elseif ($Role -like 'council-*') { $question = Get-ShaTextForTest 'stable council question'; [IO.File]::WriteAllText($prompt, "question_hash=$question`nreview`n") } else { [IO.File]::WriteAllText($prompt, "review`n") }
    $base = (& git -C $Repository rev-parse HEAD)
    if (-not $OutputPath) { $OutputPath = Join-Path $Repository ".forge/local/reviews/result-$($script:DispatchSequence).txt" }
    $arguments = @('-Mode', 'run', '-Engine', $Requested, '-FallbackPolicy', $Fallback, '-Role', $Role, '-Profile', $(if ($Role -like 'investigation*') { 'investigate' } else { 'review' }), '-Artifact', 'git:working-tree', '-WorkflowBaseSha', $base, '-WorkflowBaseRef', 'refs/heads/test-base', '-PromptFile', $prompt, '-Output', $OutputPath, '-Conversation', $Conversation, '-TimeoutSeconds', '2')
    if ($Role -like 'council-*') { $arguments += @('-SeatId', 'advisor-1') }
    if ($ExactSession) { $arguments += @('-SessionId', $ExactSession) }
    if ($SessionOutput) { $arguments += @('-SessionIdOutput', $SessionOutput) }
    $argumentsJson = Join-Path $Repository ".forge/local/reviews/launch-$($script:DispatchSequence).json"
    [IO.File]::WriteAllText($argumentsJson, ($arguments | ConvertTo-Json -Compress))
    Push-Location $Repository
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $contextLauncher $hostContext $EngineHost $argumentsJson | Out-Null; return $LASTEXITCODE }
    finally { Pop-Location }
}
function Get-ShaTextForTest([string]$Text) { $bytes = [Text.Encoding]::UTF8.GetBytes($Text); $sha = [Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() } }
function Get-ShaFileForTest([string]$Path) { $sha = [Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() } }

try {
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    [IO.File]::WriteAllText($contextLauncher, @'
param([string]$ContextPath, [string]$EngineHost, [string]$ArgumentsJsonPath)
$argumentsJson = [IO.File]::ReadAllText($ArgumentsJsonPath)
& $ContextPath -Mode launch -Host $EngineHost -LaunchArgumentsJson $argumentsJson
'@)
    $source = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
public static class ForgeFakeEngine {
  [DllImport("Kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateHardLink(string fileName,string existingFileName,IntPtr securityAttributes);
  static string E(string name, string fallback="") { return Environment.GetEnvironmentVariable(name) ?? fallback; }
  static void Emit(string path, string text) { if (String.IsNullOrEmpty(path)) Console.Write(text); else File.WriteAllText(path, text); }
  static string Qualified(string engine,string body) {
    body += "forge_canary_hash="+E("FORGE_DISPATCH_CANARY_HASH","MISSING")+"\nforge_config_hash="+E("FORGE_DISPATCH_CONFIG_HASH","MISSING")+"\nforge_qualification_revision="+E("FORGE_DISPATCH_QUALIFICATION_REVISION","MISSING")+"\n";
    if(engine=="claude") return "{\"result\":\""+body.Replace("\\","\\\\").Replace("\"","\\\"").Replace("\r","").Replace("\n","\\n")+"\",\"modelUsage\":{\"claude-haiku-4-5\":{\"canonicalModel\":\"claude-haiku-4-5\",\"provider\":\"firstParty\"},\"claude-opus-5\":{\"canonicalModel\":\"claude-opus-5\",\"provider\":\"firstParty\"}}}\n";
    return body;
  }
  static int RunReproduction() {
    var runner=E("FORGE_REPRO_RUNNER"); if(runner=="") return 70;
    var start=new ProcessStartInfo("powershell.exe","-NoProfile -ExecutionPolicy Bypass -File \""+runner.Replace("\"","\\\"")+"\""){UseShellExecute=false,CreateNoWindow=true};
    var process=Process.Start(start); process.WaitForExit(); return process.ExitCode;
  }
  public static int Main(string[] args) {
    string engine=Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]).ToLowerInvariant();
    string behavior=E("FAKE_"+engine.ToUpperInvariant()+"_BEHAVIOR","clean"); string joined=String.Join(" ",args); string output="";
    for(int i=0;i+1<args.Length;i++) if(args[i]=="--output-last-message") output=args[i+1];
    string log=E("FAKE_"+engine.ToUpperInvariant()+"_LOG"); if(log!="") File.AppendAllText(log,"cwd="+Directory.GetCurrentDirectory()+" home="+E("HOME")+" userprofile="+E("USERPROFILE")+" username="+E("USERNAME")+" argv="+joined+Environment.NewLine);
    string argv=E("FAKE_"+engine.ToUpperInvariant()+"_ARGV_LOG"); if(argv!="") File.WriteAllLines(argv,args.Select(x=>x==""?"<EMPTY>":x));
    if(engine=="codex" && joined.Contains("--json") && !joined.Contains("exec resume")) Console.WriteLine("{\"type\":\"thread.started\",\"thread_id\":\""+E("FORGE_DISPATCH_SESSION_ID")+"\"}");
    if(behavior=="timeout") { var p=Process.Start(new ProcessStartInfo("cmd.exe","/d /c ping -n 30 127.0.0.1 >nul"){UseShellExecute=false,CreateNoWindow=true}); var pid=E("FAKE_CHILD_PID_FILE"); if(pid!="") File.WriteAllText(pid,p.Id.ToString()); Thread.Sleep(30000); return 0; }
    if(behavior=="delayed-clean") Thread.Sleep(1000);
    if(behavior=="swap-output") { var paths=File.ReadAllLines(E("FAKE_CHILD_PID_FILE")); File.Delete(paths[0]); if(!CreateHardLink(paths[0],paths[1],IntPtr.Zero)) return 71; }
    if(behavior=="exit") return 23;
    if(behavior=="investigate") { var target=Path.Combine(E("FORGE_CANDIDATE_ROOT"),"tests","reproductions","claimed.txt"); Directory.CreateDirectory(Path.GetDirectoryName(target)); File.WriteAllText(target,"bounded reproduction\n"); Emit(output,Qualified(engine,"schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\nreplay_path=tests/reproductions/claimed.txt\n")); return 0; }
    if(behavior=="full-investigation") { var root=Path.GetFullPath(E("FAKE_REAL_ROOT")); if(!String.Equals(Path.GetFullPath(Directory.GetCurrentDirectory()),root,StringComparison.OrdinalIgnoreCase)) return 71; if(E("FORGE_FULL_AGENT_PROBE")!="visible") return 72; if(!File.ReadAllText(Path.Combine(root,".forge","memory","shared.md")).Contains("shared durable memory")) return 73; if(!File.ReadAllText(Path.Combine(root,".forge","local","memory","session.md")).Contains("shared local memory")) return 74; var target=Path.Combine(root,".forge","local","investigation-artifacts",engine+".txt"); Directory.CreateDirectory(Path.GetDirectoryName(target)); File.WriteAllText(target,engine+" full agent\n"); Emit(output,Qualified(engine,"schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\n")); return 0; }
    if(behavior=="repro" || behavior=="repro-boundary") { if(behavior=="repro-boundary" && !(joined.Contains("--sandbox workspace-write") || joined.Contains("--safe-mode"))) return 69; var repro=RunReproduction(); if(repro!=0) return repro; Emit(output,Qualified(engine,"schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\n")); return 0; }
    string text="schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\n";
    if(behavior=="findings") text="schema_version=1\nverdict=FINDINGS\nmax_severity=P1\nblocked_class=none\nfinding=F-1|P1|reachable\n";
    else if(behavior=="malformed") text="prose only\n";
    else if(behavior=="empty") text="";
    else if(behavior=="blocked-artifact") text="schema_version=1\nverdict=BLOCKED\nmax_severity=NONE\nblocked_class=artifact\n";
    else if(behavior=="duplicate-canary") text="schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\nforge_canary_hash="+E("FORGE_DISPATCH_CANARY_HASH")+"\nforge_config_hash="+E("FORGE_DISPATCH_CONFIG_HASH")+"\nforge_qualification_revision="+E("FORGE_DISPATCH_QUALIFICATION_REVISION")+"\n";
    else if(behavior=="conflicting-canary") text="schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\nforge_canary_hash=WRONG\n";
    if(behavior!="malformed" && behavior!="empty") text=Qualified(engine,text);
    Emit(output,text); return 0;
  }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly (Join-Path $bin 'forge-fake.exe') -OutputType ConsoleApplication
    Copy-Item -LiteralPath (Join-Path $bin 'forge-fake.exe') -Destination (Join-Path $bin 'claude.exe')
    Copy-Item -LiteralPath (Join-Path $bin 'forge-fake.exe') -Destination (Join-Path $bin 'codex.exe')
    $env:PATH = "$bin;$($env:PATH)"; $env:FORGE_DISPATCH_TEST_MODE = '1'

    Write-Host 'PowerShell four-mode selection and fallback matrix'
    foreach ($tuple in @(@('claude','codex','codex'), @('codex','claude','claude'), @('claude','claude','claude'), @('codex','codex','codex'))) {
        $repo = New-Repository ("mode-$($tuple[0])-$($tuple[1])")
        Assert-Equal (Invoke-Dispatch $repo $tuple[0] 'sid' $tuple[1]) 0 "$($tuple[0]) main can use $($tuple[1]) reviewer"
        Assert-Equal (Get-ReceiptValue $repo 'actual_engine') $tuple[2] 'actual engine recorded'
    }
    $repo = New-Repository 'fallback malformed'; $env:FAKE_CODEX_BEHAVIOR = 'malformed'; $env:FAKE_CLAUDE_BEHAVIOR = 'clean'
    Assert-Equal (Invoke-Dispatch $repo 'claude' 'sid' 'auto') 0 'malformed other engine visibly falls back'
    Assert-Equal (Get-ReceiptValue $repo 'fallback') 'true' 'fallback is recorded'
    Assert-Equal (Get-ReceiptValue $repo 'actual_engine') 'claude' 'fallback engine is fresh main engine'

    Write-Host 'PowerShell exact empty Claude argv preservation'
    $repo = New-Repository 'empty argv'; $argvLog = Join-Path $repo '.forge/local/reviews/claude-argv.log'; $env:FAKE_CLAUDE_ARGV_LOG = $argvLog; $env:FAKE_CLAUDE_BEHAVIOR = 'clean'
    Assert-Equal (Invoke-Dispatch $repo 'claude' 'sid' 'claude') 0 'Claude invocation with explicit empty setting sources succeeds'
    $argv = @([IO.File]::ReadAllLines($argvLog)); $settingIndex = [Array]::IndexOf($argv, '--setting-sources'); $toolsIndex = [Array]::IndexOf($argv, '--tools')
    Assert-True ($settingIndex -ge 0 -and $argv[$settingIndex + 1] -ceq '<EMPTY>') 'empty --setting-sources value occupies its exact argv position'
    Assert-True ($toolsIndex -eq $settingIndex + 2 -and $argv[$toolsIndex + 1] -ceq 'Read,Grep,Glob') '--tools and its value follow the empty setting source'
    Remove-Item Env:FAKE_CLAUDE_ARGV_LOG -ErrorAction SilentlyContinue

    Write-Host 'PowerShell review-pair current candidate and output binding'
    $repo = New-Repository 'verify pair'; $env:FAKE_CODEX_BEHAVIOR = 'clean'
    Assert-Equal (Invoke-Dispatch $repo 'claude' 'sid' 'codex' 'code-spec') 0 'code-spec receipt is created'; $spec = Get-LatestReceipt $repo
    Assert-Equal (Invoke-Dispatch $repo 'claude' 'sid' 'codex' 'code-quality') 0 'code-quality receipt is created'; $quality = Get-LatestReceipt $repo
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dispatcher -Mode verify-pair -CodeSpecReceipt $spec -CodeQualityReceipt $quality *> $null
    Assert-Equal $LASTEXITCODE 0 'current distinct pair certifies'
    Add-Content -LiteralPath (Join-Path $repo 'app.txt') -Value 'mutated candidate'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dispatcher -Mode verify-pair -CodeSpecReceipt $spec -CodeQualityReceipt $quality *> $null
    Assert-Equal $LASTEXITCODE 2 'candidate mutation invalidates the pair'
    [IO.File]::WriteAllText((Join-Path $repo 'app.txt'), "base`n")
    $qualityOutput = (Get-Content -LiteralPath $quality | Where-Object { $_ -like 'output_path=*' } | Select-Object -First 1).Substring(12)
    Add-Content -LiteralPath $qualityOutput -Value 'mutated output'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dispatcher -Mode verify-pair -CodeSpecReceipt $spec -CodeQualityReceipt $quality *> $null
    Assert-Equal $LASTEXITCODE 2 'review output mutation invalidates the pair'

    Write-Host 'PowerShell timeout tree cleanup and semantic non-fallback'
    $repo = New-Repository 'timeout cleanup'; $env:FAKE_CODEX_BEHAVIOR = 'timeout'; $env:FAKE_CLAUDE_BEHAVIOR = 'clean'; $pidFile = Join-Path $repo '.forge/local/child.pid'; $env:FAKE_CHILD_PID_FILE = $pidFile
    Assert-Equal (Invoke-Dispatch $repo 'claude' 'sid' 'auto') 0 'timeout falls back once'
    $childPid = [int](Get-Content -LiteralPath $pidFile -Raw); Start-Sleep -Milliseconds 200
    if (Get-Process -Id $childPid -ErrorAction SilentlyContinue) { Fail 'timeout descendant survived taskkill tree cleanup' } else { Pass 'timeout descendant tree is terminated' }
    Remove-Item Env:FAKE_CHILD_PID_FILE -ErrorAction SilentlyContinue
    $repo = New-Repository 'semantic artifact'; $env:FAKE_CODEX_BEHAVIOR = 'blocked-artifact'; $env:FAKE_CLAUDE_BEHAVIOR = 'clean'
    Assert-Equal (Invoke-Dispatch $repo 'claude' 'sid' 'auto') 2 'artifact block never triggers engine fallback'
    Assert-Equal (Get-ReceiptValue $repo 'fallback') 'false' 'artifact block records no fallback'

    Write-Host 'PowerShell protected host ambiguity and atomic output publication'
    $repo = New-Repository 'ambiguous hosts'; Set-Context $repo 'claude' 'claude-live'; $env:FAKE_CODEX_BEHAVIOR = 'clean'; $env:FAKE_CLAUDE_BEHAVIOR = 'clean'
    Assert-Equal (Invoke-Dispatch $repo 'codex' 'codex-live' 'auto') 2 'simultaneous Claude and Codex receipts cannot be caller-selected'
    $repo = New-Repository 'atomic output'; $protected = Join-Path $repo '.forge/local/protected-output'; [IO.File]::WriteAllText($protected, "protected`n"); $protectedHash = Get-ShaFileForTest $protected
    $racedOutput = Join-Path $repo '.forge/local/reviews/raced-output'; $swapControl = Join-Path $repo '.forge/local/swap-control'; [IO.File]::WriteAllLines($swapControl, @($racedOutput, $protected))
    $env:FAKE_CHILD_PID_FILE = $swapControl; $env:FAKE_CODEX_BEHAVIOR = 'swap-output'
    Assert-Equal (Invoke-Dispatch $repo 'claude' 'sid' 'codex' 'general' 'none' 'ephemeral' '' '' '' $racedOutput) 0 'atomic publication replaces a swapped hard-link leaf'
    Assert-Equal (Get-ShaFileForTest $protected) $protectedHash 'atomic publication leaves the linked protected file byte-identical'
    Remove-Item Env:FAKE_CHILD_PID_FILE -ErrorAction SilentlyContinue

    Write-Host 'PowerShell exact resume and investigation replay'
    $repo = New-Repository 'exact resume'; $env:FAKE_CLAUDE_BEHAVIOR = 'clean'; $sessionOutput = Join-Path $repo '.forge/local/reviews/session.id'; $log = Join-Path $repo '.forge/local/reviews/claude.log'; $env:FAKE_CLAUDE_LOG = $log
    Assert-Equal (Invoke-Dispatch $repo 'claude' 'sid' 'claude' 'council-advisor' 'none' 'new' '' $sessionOutput) 0 'Claude council new turn succeeds'
    $exact = (Get-Content -LiteralPath $sessionOutput -Raw).Trim()
    Assert-Equal (Invoke-Dispatch $repo 'claude' 'sid' 'claude' 'council-advisor' 'none' 'resume' $exact) 0 'Claude exact-id resume succeeds'
    Assert-Contains $log "--session-id $exact" 'new turn binds exact Claude session'
    Assert-Contains $log "--resume $exact" 'second turn resumes exact Claude session'
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    Assert-Contains $log "home=$userProfile userprofile=$userProfile username=$env:USERNAME" 'Claude child preserves the authenticated Windows identity'
    Remove-Item Env:FAKE_CLAUDE_LOG -ErrorAction SilentlyContinue

    Write-Host 'PowerShell session metadata leaf is no-follow'
    $repo = New-Repository 'metadata leaf'; $sessionOutput = Join-Path $repo '.forge/local/reviews/session.id'; $env:FAKE_CLAUDE_BEHAVIOR = 'clean'
    Assert-Equal (Invoke-Dispatch $repo 'claude' 'sid' 'claude' 'council-advisor' 'none' 'new' '' $sessionOutput) 0 'metadata-leaf fixture starts a session'
    $exact = (Get-Content -LiteralPath $sessionOutput -Raw).Trim(); $meta = Join-Path $repo ".forge/local/reviews/sessions/$exact.meta"; $outsideMeta = Join-Path $temporary 'outside-session.meta'
    Copy-Item -LiteralPath $meta -Destination $outsideMeta; $outsideHash = Get-ShaFileForTest $outsideMeta; Remove-Item -LiteralPath $meta -Force; $linked = $false
    try { New-Item -ItemType SymbolicLink -Path $meta -Target $outsideMeta -ErrorAction Stop | Out-Null; $linked = $true } catch { Copy-Item -LiteralPath $outsideMeta -Destination $meta }
    if ($linked) {
        Assert-Equal (Invoke-Dispatch $repo 'claude' 'sid' 'claude' 'council-advisor' 'none' 'resume' $exact) 2 'session metadata reparse leaf is rejected'
        Assert-Equal (Get-ShaFileForTest $outsideMeta) $outsideHash 'reparse target remains byte-identical'
    } else {
        $source = Get-Content -LiteralPath $dispatcher -Raw
        Assert-True (([regex]::Matches($source, 'Assert-NoFollowSessionMetadata \$SessionMeta')).Count -ge 3) 'session metadata is checked before read and update when symlink creation is unavailable'
    }

    Write-Host 'PowerShell investigation uses a full agent in the real worktree'
    foreach ($selected in @('claude','codex')) {
        $repo = New-Repository "full investigation $selected"
        New-Item -ItemType Directory -Path (Join-Path $repo '.forge/memory'), (Join-Path $repo '.forge/local/memory') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $repo '.forge/memory/shared.md'), "shared durable memory`n")
        [IO.File]::WriteAllText((Join-Path $repo '.forge/local/memory/session.md'), "shared local memory`n")
        $log = Join-Path $repo ".forge/local/reviews/$selected-full-agent.log"
        $env:FAKE_REAL_ROOT = $repo; $env:FORGE_FULL_AGENT_PROBE = 'visible'; [Environment]::SetEnvironmentVariable("FAKE_$($selected.ToUpperInvariant())_BEHAVIOR", 'full-investigation'); [Environment]::SetEnvironmentVariable("FAKE_$($selected.ToUpperInvariant())_LOG", $log)
        Assert-Equal (Invoke-Dispatch $repo $(if($selected -eq 'claude'){'codex'}else{'claude'}) 'sid' $selected 'investigation' 'none') 0 "$selected investigation runs in the real worktree"
        Assert-Contains (Join-Path $repo ".forge/local/investigation-artifacts/$selected.txt") "$selected full agent" "$selected investigation writes shared local state"
        Assert-Contains $log "cwd=$repo" "$selected investigation sees the real worktree"
        foreach ($flag in @('--safe-mode','--setting-sources','--ignore-user-config','--ignore-rules','--add-dir')) { Assert-NotContains $log $flag "$selected investigation omits Forge restriction $flag" }
        if ($selected -eq 'codex') {
            Assert-Contains $log '-a on-request --search exec' 'Codex investigation preserves native on-request approval with web search'
            Assert-Contains $log '--sandbox danger-full-access' 'Codex investigation selects the full-capability sandbox mode'
        } else {
            Assert-Contains $log '--permission-mode auto' 'Claude investigation uses safety-classified full-agent mode'
            Assert-NotContains $log '--sandbox' 'Claude investigation has no Forge sandbox override'
        }
        Assert-Equal (Get-ReceiptValue $repo 'investigation_mode') 'full-agent-worktree' "$selected receipt records full-agent mode"
        [Environment]::SetEnvironmentVariable("FAKE_$($selected.ToUpperInvariant())_BEHAVIOR", $null); [Environment]::SetEnvironmentVariable("FAKE_$($selected.ToUpperInvariant())_LOG", $null)
    }
    Remove-Item Env:FAKE_REAL_ROOT, Env:FORGE_FULL_AGENT_PROBE -ErrorAction SilentlyContinue

    Write-Host 'PowerShell qualified independent reproduction boundary'
    $repo = New-Repository 'reproduction boundary'; $auth = Join-Path $repo 'protected-auth.json'; [IO.File]::WriteAllText($auth, "protected-auth`n"); $outside = Join-Path $temporary 'reproduction-external'
    $state = Join-Path $repo '.forge/local/state.md'; $stateHash = Get-ShaFileForTest $state; $authHash = Get-ShaFileForTest $auth
    $stateLiteral = $state.Replace('\','\\').Replace('"','\"'); $authLiteral = $auth.Replace('\','\\').Replace('"','\"'); $outsideLiteral = $outside.Replace('\','\\').Replace('"','\"')
    $reproSource = "using System; using System.IO; public static class ForgeBoundaryProgram { public static int Main(string[] args) { if(Environment.GetEnvironmentVariable(`"FORGE_REPRO_NO_NETWORK`")!=`"1`") { File.AppendAllText(`"$stateLiteral`",`"escaped\n`"); File.AppendAllText(`"$authLiteral`",`"escaped\n`"); File.WriteAllText(`"$outsideLiteral`",`"escaped\n`"); } Console.WriteLine(args[0]==`"primary`"?`"MATCH`":`"CONTROL`"); return 0; } }"
    $reproProgram = Join-Path $repo 'boundary-repro.exe'; Add-Type -TypeDefinition $reproSource -Language CSharp -OutputAssembly $reproProgram -OutputType ConsoleApplication
    $match = Get-ShaTextForTest ("MATCH" + [Environment]::NewLine); $control = Get-ShaTextForTest ("CONTROL" + [Environment]::NewLine)
    $reproPrompt = "schema_version=1`nhypothesis=qualified boundary`nprimary_program=boundary-repro.exe`nprimary_arg=primary`nprimary_expected_exit=0`nprimary_expected_output_hash=$match`ncontrol_program=boundary-repro.exe`ncontrol_arg=control`ncontrol_expected_exit=0`ncontrol_expected_output_hash=$control`n"
    $reproLog = Join-Path $repo '.forge/local/reviews/repro.log'; $env:FORGE_CODEX_AUTH_FILE = $auth; $env:FAKE_CODEX_BEHAVIOR = 'repro-boundary'; $env:FAKE_CODEX_LOG = $reproLog
    Assert-Equal (Invoke-Dispatch $repo 'claude' 'sid' 'codex' 'investigation-repro' 'none' 'ephemeral' '' '' $reproPrompt) 0 'primary and control use qualified Codex reproduction boundaries'
    Assert-Equal (Get-ReceiptValue $repo 'reproduction_status') 'REPRODUCED' 'dispatcher computes a reproduced status'
    Assert-Equal (Get-ShaFileForTest $state) $stateHash 'reproduction leaves Forge state byte-identical'
    Assert-Equal (Get-ShaFileForTest $auth) $authHash 'reproduction leaves protected auth byte-identical'
    if (Test-Path -LiteralPath $outside) { Fail 'reproduction escaped the disposable candidate' } else { Pass 'reproduction cannot write outside the disposable candidate' }
    Assert-Contains $reproLog '--sandbox workspace-write' 'reproduction uses the qualified no-network workspace boundary'
    Remove-Item Env:FORGE_CODEX_AUTH_FILE, Env:FAKE_CODEX_LOG -ErrorAction SilentlyContinue

    Write-Host 'PowerShell path and reparse safety'
    $repo = New-Repository 'junction rejection'; $outside = Join-Path $temporary 'outside'; New-Item -ItemType Directory -Path $outside | Out-Null
    & cmd.exe /d /c mklink /J "$(Join-Path $repo 'junction')" "$outside" | Out-Null
    $base = (& git -C $repo rev-parse HEAD); Set-State $repo $base 'x'; Push-Location $repo
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fingerprint -Mode capture -Artifact 'git:working-tree' -WorkflowBaseSha $base -WorkflowBaseRef x -Output (Join-Path $repo '.forge/local/fp') | Out-Null; $junctionRc = $LASTEXITCODE }
    finally { Pop-Location }
    if ($junctionRc -ne 0) { Pass 'untracked junction or reparse point is rejected' } else { Fail 'untracked junction was accepted' }
    foreach ($reserved in @('sessions','session-stores')) {
        $repo = New-Repository "reserved $reserved"; $outside = Join-Path $repo "outside-$reserved"; New-Item -ItemType Directory -Path $outside | Out-Null
        & cmd.exe /d /c mklink /J "$(Join-Path $repo ".forge\local\reviews\$reserved")" "$outside" | Out-Null
        $sessionOutput = Join-Path $repo '.forge/local/reviews/session.id'
        Assert-Equal (Invoke-Dispatch $repo 'claude' 'sid' 'claude' 'council-advisor' 'none' 'new' '' $sessionOutput) 2 "$reserved junction ancestor is rejected"
        Assert-Equal (@(Get-ChildItem -LiteralPath $outside -Force).Count) 0 "$reserved junction target remains untouched"
    }

    Write-Host 'PowerShell materialized Codex host-context invocation'
    $installed = Join-Path $temporary 'materialized adapters'; New-Item -ItemType Directory -Path $installed | Out-Null
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts/materialize-adapters.ps1') -RepoRoot $root -Target $installed -Scope project -Platform windows *> $null
    Assert-Equal $LASTEXITCODE 0 'PowerShell adapters materialize'
    $hooks = Get-Content -LiteralPath (Join-Path $installed '.codex/hooks.json') -Raw | ConvertFrom-Json
    $hostEntry = @($hooks.hooks.session_start | Where-Object { $_.forgeManagedId -eq 'host-context' })[0]
    Assert-Equal (($hostEntry.command -join '|')) 'powershell.exe|-NoProfile|-ExecutionPolicy|Bypass|-File|.forge/hooks/lib/host-context.ps1|-Mode|hook|-Host|codex' 'Codex host-context invokes the Windows hook directly'
    $sessionEntry = @($hooks.hooks.session_start | Where-Object { $_.forgeManagedId -eq 'session-start' })[0]
    Assert-Equal $sessionEntry.command[5] '.forge/hooks/lib/codex-worktree-dispatch.ps1' 'other Codex hooks retain worktree routing'
}
finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "PowerShell agent dispatch: $($script:Passed) passed, $($script:Failed) failed"
if ($script:Failed -ne 0) { exit 1 }
exit 0
