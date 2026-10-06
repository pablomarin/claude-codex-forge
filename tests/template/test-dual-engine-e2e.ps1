$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('forge-dual-e2e-' + [Guid]::NewGuid().ToString('N'))
$originalPath = $env:PATH
$originalHome = $env:HOME
$powershellExe = (Get-Process -Id $PID).Path
$completed = $false

$coverage = @(
    'UC01|authoritative-legacy-refresh|test-full-refresh.ps1,test-setup.sh',
    'UC02|global-dual-host-setup|test-setup.sh,test-full-refresh.ps1',
    'UC03|clean-install-one-engine|test-setup.sh,test-agent-dispatch.ps1',
    'UC04|four-review-modes|test-agent-dispatch.ps1,test-build-evidence.sh',
    'UC05|cross-host-resume|test-state-roundtrip.sh,test-agent-dispatch.ps1',
    'UC06|artifact-invalidation|test-build-evidence.sh,test-hooks.sh',
    'UC07|council-healthy|test-council-dispatch.ps1',
    'UC08|council-degraded|test-council-dispatch.ps1',
    'UC09|council-overrides|test-council-dispatch.ps1',
    'UC10|investigation-authorization|test-agent-dispatch.ps1,test-authorized-action.ps1',
    'UC11|goal-parity-resume|test-goal-feasibility.ps1,test-state-roundtrip.sh,test-hooks.sh',
    'UC12|failed-migration-honesty|test-full-refresh.ps1',
    'UC13|cross-worktree-evidence|test-state-roundtrip.sh,test-build-evidence.sh',
    'UC14|materialized-versus-ready|test-setup.sh,test-runtime-identity.ps1',
    'UC15|native-goal-collision|test-workflow-parity.sh,test-goal-feasibility.ps1',
    'UC16|mutation-free-finalization|test-build-evidence.sh,test-hooks.sh',
    'UC17|linked-worktree-codex-hooks|test-setup.sh,test-hooks.sh'
)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    Write-Host "  PASS: $Message"
}
function Get-Hash([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-ReceiptValue([string]$Path, [string]$Key) {
    $line = Get-Content -LiteralPath $Path | Where-Object { $_ -like "$Key=*" } | Select-Object -First 1
    if ($null -eq $line) { return '' }
    return $line.Substring($Key.Length + 1)
}

# Exercise the actual compiled Windows fixture's reply on every PS platform.
# A library probe avoids claiming that Unix executed a Windows native binary.
function Test-CompiledClaudeFixture([string]$Source) {
    $probeSource=$Source.Replace('ForgeTask11Fake','ForgeTask11FixtureProbe')
    Add-Type -TypeDefinition $probeSource -Language CSharp
    $previousConsole=[Console]::Out
    $captured=New-Object IO.StringWriter
    try {
        [Console]::SetOut($captured)
        $probeRc=[ForgeTask11FixtureProbe]::Main([string[]]@())
    } finally { [Console]::SetOut($previousConsole) }
    $wrapper=$captured.ToString()|ConvertFrom-Json
    $captured.Dispose()
    Assert-True ($probeRc -eq 0) 'compiled Claude fixture emits a successful reply'
    $identity=$wrapper.modelUsage.'claude-opus-5-5'
    Assert-True ($identity.canonicalModel -ceq 'claude-opus-5-5' -and $identity.provider -ceq 'firstParty') 'compiled Claude fixture binds the configured model and provider'
}

# Unix exercises the same installed PowerShell dispatcher with portable fake CLIs.
# Windows retains its compiled native executable fixtures.
function Install-PortableEngine([string]$Engine) {
    $path=Join-Path $bin $Engine
    $fixture=Join-Path $root "tests/template/fixtures/fake-engines/$Engine"
    if($Engine -eq 'claude') {
        [IO.File]::WriteAllText($path,@"
#!/usr/bin/env bash
case "`${1:-}" in
  --version) printf '2.1.237 (Claude Code)\n'; exit 0 ;;
  --help) printf '%s\n' '-p --safe-mode --strict-mcp-config --mcp-config --settings --setting-sources --tools --permission-mode --add-dir --model --effort --output-format --no-session-persistence --session-id --resume'; exit 0 ;;
esac
exec "$fixture" "`$@"
"@)
        & chmod +x $path
    } else { New-Item -ItemType SymbolicLink -Path $path -Target $fixture | Out-Null }
}

try {
    Write-Host 'PowerShell acceptance ownership map'
    Assert-True ($coverage.Count -eq 17) 'coverage map has 17 rows'
    Assert-True (@($coverage | ForEach-Object { ($_ -split '\|')[0] } | Sort-Object -Unique).Count -eq 17) 'coverage ids are unique'
    foreach ($row in $coverage) {
        $parts = $row -split '\|'
        foreach ($owner in $parts[2].Split(',')) {
            Assert-True (Test-Path -LiteralPath (Join-Path $PSScriptRoot $owner) -PathType Leaf) "$($parts[0]) owner exists: $owner"
        }
    }

    Write-Host 'PowerShell installed two-main review/opinion and fallback seam'
    $project = Join-Path $temporary 'project'; $testHome = Join-Path $temporary 'home'; $bin = Join-Path $temporary 'bin'
    New-Item -ItemType Directory -Path $project,$testHome,$bin -Force | Out-Null
    if($env:OS -ne 'Windows_NT') {
        # Installed .ps1 helpers use the Windows launcher name. Route that name
        # to this PS7 process solely within the portable test's private PATH.
        $launcher=Join-Path $bin 'powershell.exe'
        [IO.File]::WriteAllText($launcher,"#!/bin/sh`nexec `"$powershellExe`" `"`$@`"`n")
        & chmod +x $launcher
    }
    & git -C $project init -q
    $project=(Resolve-Path (& git -C $project rev-parse --show-toplevel)).Path
    & git -C $project config user.email forge@example.invalid; & git -C $project config user.name Forge
    [IO.File]::WriteAllText((Join-Path $project 'app.txt'), "base`n")
    & git -C $project add app.txt; & git -C $project commit -qm base
    $fake = @'
using System;
public static class ForgeTask11Fake {
  static string E(string n) { return Environment.GetEnvironmentVariable(n) ?? "MISSING"; }
  public static int Main(string[] args) {
    if (args.Length > 0 && args[0] == "--version") { Console.WriteLine("2.1.237 (Claude Code)"); return 0; }
    if (args.Length > 0 && args[0] == "--help") { Console.WriteLine("-p --safe-mode --strict-mcp-config --mcp-config --settings --setting-sources --tools --permission-mode --add-dir --model --effort --output-format --no-session-persistence --session-id --resume"); return 0; }
    if (E("FAKE_CLAUDE_BEHAVIOR") == "exit") { return 23; }
    string body="schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\nforge_canary_hash="+E("FORGE_DISPATCH_CANARY_HASH")+"\nforge_config_hash="+E("FORGE_DISPATCH_CONFIG_HASH")+"\nforge_qualification_revision="+E("FORGE_DISPATCH_QUALIFICATION_REVISION");
    Console.WriteLine("{\"result\":\""+body.Replace("\\","\\\\").Replace("\"","\\\"").Replace("\n","\\n")+"\",\"modelUsage\":{\"claude-haiku-4-5\":{\"canonicalModel\":\"claude-haiku-4-5\",\"provider\":\"firstParty\"},\"claude-opus-5-5\":{\"canonicalModel\":\"claude-opus-5-5\",\"provider\":\"firstParty\"}}}");
    return 0;
  }
}
'@
    Test-CompiledClaudeFixture $fake
    if($env:OS -eq 'Windows_NT') { Add-Type -TypeDefinition $fake -Language CSharp -OutputAssembly (Join-Path $bin 'claude.exe') -OutputType ConsoleApplication }
    else { Install-PortableEngine claude }
    $gitExecutable=(Get-Command git -CommandType Application | Select-Object -First 1).Source
    if($env:OS -eq 'Windows_NT') {
        # Installed helpers launch Windows PowerShell by name even from PS7.
        $systemPath=(Split-Path -Parent $gitExecutable)+';'+$env:SystemRoot+'\System32;'+$env:SystemRoot+'\System32\WindowsPowerShell\v1.0'
    } else {
        # Expose only Git, not other vendor CLIs sharing a package-manager bin.
        New-Item -ItemType SymbolicLink -Path (Join-Path $bin 'git') -Target $gitExecutable | Out-Null
        $systemPath='/usr/bin:/bin'
    }
    $env:PATH = $bin+[IO.Path]::PathSeparator+$systemPath; $env:FORGE_ENGINE_IDENTITY_FIXTURE = '1'; $env:HOME = $testHome
    Push-Location $project
    try { $setupOutput = (& $powershellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'setup.ps1') -Project Integration -Tech fullstack 2>&1) -join "`n"; $setupRc = $LASTEXITCODE }
    finally { Pop-Location }
    Assert-True ($setupRc -eq 0) 'clean setup materializes the seam fixture'
    Assert-True ($setupOutput -like '*INSTALLATION: MATERIALIZED*') 'setup reports materialization'
    Assert-True ($setupOutput -like '*codex RUNTIME_READY: BLOCKED*') 'missing Codex remains visibly blocked'
    & git -C $project add -A; & git -C $project commit -qm installed
    $base = (& git -C $project rev-parse HEAD); $branch = (& git -C $project branch --show-current)
    $commonRelative = (& git -C $project rev-parse --git-common-dir); $common = (Resolve-Path (Join-Path $project $commonRelative)).Path
    $reviews = Join-Path $project '.forge\local\reviews'; New-Item -ItemType Directory -Path $reviews -Force | Out-Null
    $state = Join-Path $project '.forge\local\state.md'
    $stateBody = "<!-- forge:state-schema v6 -->`n# Project State`n`n## Identity`n`n| Field | Value |`n| --- | --- |`n| Worktree root | $project |`n| Git common directory | $common |`n| Last active host | claude |`n| Workflow base ref | refs/heads/$branch |`n| Workflow base SHA | $base |`n`n## Workflow`n`n## Receipts`n| Field | Value |`n| Review iteration | 1 |`n"
    [IO.File]::WriteAllText($state, $stateBody)
    # Preserve the one-engine setup case, then add the second deterministic CLI.
    $codexFake = $fake.Replace('ForgeTask11Fake','ForgeTask11CodexFake').Replace('2.1.237 (Claude Code)','codex-cli 0.144.1').Replace('FAKE_CLAUDE_BEHAVIOR','FAKE_CODEX_BEHAVIOR')
    $claudeReply = @($fake -split "`n" | Where-Object { $_ -like '    Console.WriteLine(*body.Replace*' })[0]
    $codexFake = $codexFake.Replace($claudeReply, @'
    for (int i=0; i<args.Length-1; i++) {
      if (args[i] == "--output-last-message") { System.IO.File.WriteAllText(args[i+1],body+"\n"); return 0; }
    }
    Console.WriteLine(body);
'@)
    if($env:OS -eq 'Windows_NT') { Add-Type -TypeDefinition $codexFake -Language CSharp -OutputAssembly (Join-Path $bin 'codex.exe') -OutputType ConsoleApplication }
    else { Install-PortableEngine codex }
    $prompt = Join-Path $reviews 'prompt.txt'; [IO.File]::WriteAllText($prompt, "Review the installed seam.`n")
    $dispatcher = Join-Path $project '.forge\hooks\lib\agent-dispatch.ps1'; $context = Join-Path $project '.forge\hooks\lib\host-context.ps1'
    $env:FORGE_DISPATCH_TEST_MODE='1'
    $argumentsJson = Join-Path $reviews 'launch-arguments.json'
    $contextLauncher = Join-Path $reviews 'launch-host-context.ps1'
    [IO.File]::WriteAllText($contextLauncher, @'
param([string]$ContextPath, [string]$EngineHost, [string]$ArgumentsJsonPath)
$argumentsJson = [IO.File]::ReadAllText($ArgumentsJsonPath)
& $ContextPath -Mode launch -Host $EngineHost -LaunchArgumentsJson $argumentsJson
exit $LASTEXITCODE
'@)
    $before = Get-Hash $state
    foreach ($main in @('claude','codex')) {
        $other = if ($main -eq 'claude') { 'codex' } else { 'claude' }
        foreach ($role in @('general','plan','code-spec','code-quality')) {
            foreach ($topology in @('healthy','fallback')) {
                $env:FAKE_CLAUDE_BEHAVIOR='clean'; $env:FAKE_CODEX_BEHAVIOR='clean'
                if ($topology -eq 'fallback') {
                    if ($other -eq 'claude') { $env:FAKE_CLAUDE_BEHAVIOR='exit' } else { $env:FAKE_CODEX_BEHAVIOR='exit' }
                }
                $result = Join-Path $reviews "$main-$role-$topology.txt"
                $arguments = @('-Mode','run','-Engine','auto','-FallbackPolicy','automatic','-Role',$role,'-Profile','review','-Artifact','git:working-tree','-WorkflowBaseSha',$base,'-WorkflowBaseRef',"refs/heads/$branch",'-PromptFile',$prompt,'-Output',$result,'-TimeoutSeconds','2')
                [IO.File]::WriteAllText($argumentsJson, ($arguments | ConvertTo-Json -Compress))
                Push-Location $project
                try {
                    $dispatchOutput = (& $powershellExe -NoProfile -ExecutionPolicy Bypass -File $contextLauncher $context $main $argumentsJson 2>&1) -join "`n"; $dispatchRc = $LASTEXITCODE
                } finally { Pop-Location }
                [IO.File]::WriteAllText((Join-Path $reviews "$main-$role-$topology.dispatch.log"),$dispatchOutput)
                if ($dispatchRc -ne 0) {
                    Write-Host "Dispatcher failed (exit=$dispatchRc): $dispatchOutput"
                    $failedReceipt=@(Get-ChildItem -LiteralPath $reviews -Filter '*.receipt'|Where-Object {(Get-ReceiptValue $_.FullName 'output_path') -ceq $result})
                    foreach($file in $failedReceipt) { Write-Host "Failed dispatcher receipt: $($file.FullName)";Write-Host ([IO.File]::ReadAllText($file.FullName)) }
                }
                Assert-True ($dispatchRc -eq 0) "$main main $role $topology review completes (exit=$dispatchRc)"
                $receipt = @(Get-ChildItem -LiteralPath $reviews -Filter '*.receipt' | Where-Object { (Get-ReceiptValue $_.FullName 'output_path') -ceq $result })
                Assert-True ($receipt.Count -eq 1) "$main $role $topology has its own receipt"
                $receiptPath = $receipt[0].FullName
                Assert-True ((Get-ReceiptValue $receiptPath 'main_host') -ceq $main) "receipt binds $main main"
                Assert-True ((Get-ReceiptValue $receiptPath 'role') -ceq $role) "receipt binds $role review mode"
                Assert-True ((Get-ReceiptValue $receiptPath 'first_attempted_engine') -ceq $other) "$main main selects the other engine"
                Assert-True ((Get-ReceiptValue $receiptPath 'fresh_process') -ceq 'true') "$main $role uses a fresh reviewer process"
                Assert-True ((Get-ReceiptValue $receiptPath 'semantic_verdict') -ceq 'CLEAN') "$main $role result is validated"
                if ($topology -eq 'healthy') {
                    Assert-True ((Get-ReceiptValue $receiptPath 'actual_engine') -ceq $other) "$main $role healthy review uses $other"
                    Assert-True ((Get-ReceiptValue $receiptPath 'fallback') -ceq 'false') 'healthy review does not degrade'
                    Assert-True ($dispatchOutput -notlike '*visible fallback*') 'healthy review emits no fallback notice'
                } else {
                    Assert-True ((Get-ReceiptValue $receiptPath 'actual_engine') -ceq $main) "$main $role fallback uses the main engine"
                    Assert-True ((Get-ReceiptValue $receiptPath 'fallback') -ceq 'true') 'failed other-engine review records degradation'
                    Assert-True ((Get-ReceiptValue $receiptPath 'attempted_engines') -ceq "$other,$main") 'fallback records both independent attempts'
                    Assert-True ($dispatchOutput -like '*visible fallback*') "$main $role fallback is visible"
                }
                Assert-True ((Get-Hash $state) -ceq $before) "$main $role $topology leaves canonical state unchanged"
            }
        }
    }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $testHome '.forge\host-contexts'))) 'installed PowerShell reviews need no host authority directory'
    $completed=$true

}
finally {
    $env:PATH=$originalPath; $env:HOME=$originalHome
    Remove-Item Env:FORGE_ENGINE_IDENTITY_FIXTURE,Env:FORGE_DISPATCH_TEST_MODE,Env:FORGE_TEST_DISABLE_ENGINE,Env:FAKE_CLAUDE_BEHAVIOR,Env:FAKE_CODEX_BEHAVIOR -ErrorAction SilentlyContinue
    if($completed) { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "Failed deterministic fixture preserved: $temporary" }
}
Write-Host 'PASS: PowerShell two-main integrated seam (deterministic CLIs)'
