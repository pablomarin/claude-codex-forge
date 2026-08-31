$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('forge-dual-e2e-' + [Guid]::NewGuid().ToString('N'))
$originalPath = $env:PATH

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
    return $line.Substring($Key.Length + 1)
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

    Write-Host 'PowerShell installed fallback seam'
    $project = Join-Path $temporary 'project'; $home = Join-Path $temporary 'home'; $bin = Join-Path $temporary 'bin'
    New-Item -ItemType Directory -Path $project,$home,$bin -Force | Out-Null
    & git -C $project init -q; & git -C $project config user.email forge@example.invalid; & git -C $project config user.name Forge
    [IO.File]::WriteAllText((Join-Path $project 'app.txt'), "base`n")
    & git -C $project add app.txt; & git -C $project commit -qm base
    $fake = @'
using System;
public static class ForgeTask11Fake {
  static string E(string n) { return Environment.GetEnvironmentVariable(n) ?? "MISSING"; }
  public static int Main(string[] args) {
    if (args.Length > 0 && args[0] == "--version") { Console.WriteLine("2.1.237 (Claude Code)"); return 0; }
    if (args.Length > 0 && args[0] == "--help") { Console.WriteLine("-p --safe-mode --strict-mcp-config --mcp-config --settings --setting-sources --tools --permission-mode --add-dir --model --effort --output-format --no-session-persistence --session-id --resume"); return 0; }
    string body="schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\nforge_canary_hash="+E("FORGE_DISPATCH_CANARY_HASH")+"\nforge_config_hash="+E("FORGE_DISPATCH_CONFIG_HASH")+"\nforge_qualification_revision="+E("FORGE_DISPATCH_QUALIFICATION_REVISION");
    Console.WriteLine("{\"result\":\""+body.Replace("\\","\\\\").Replace("\"","\\\"").Replace("\n","\\n")+"\",\"modelUsage\":{\"opus\":{}},\"provider\":\"anthropic\"}");
    return 0;
  }
}
'@
    Add-Type -TypeDefinition $fake -Language CSharp -OutputAssembly (Join-Path $bin 'claude.exe') -OutputType ConsoleApplication
    $env:PATH = "$bin;$originalPath"; $env:FORGE_ENGINE_IDENTITY_FIXTURE = '1'; $env:HOME = $home
    Push-Location $project
    try { $setupOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'setup.ps1') -Project Integration -Tech fullstack 2>&1) -join "`n"; $setupRc = $LASTEXITCODE }
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
    $prompt = Join-Path $reviews 'prompt.txt'; $result = Join-Path $reviews 'result.txt'; [IO.File]::WriteAllText($prompt, "Review the installed seam.`n")
    $dispatcher = Join-Path $project '.forge\hooks\lib\agent-dispatch.ps1'; $context = Join-Path $project '.forge\hooks\lib\host-context.ps1'
    $env:FORGE_DISPATCH_TEST_MODE='1';$env:FORGE_TEST_DISABLE_ENGINE='codex'
    Push-Location $project
    try {
        "{`"session_id`":`"seam-session`",`"cwd`":`"$($project.Replace('\','\\'))`"}" | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $context -Mode hook -Host claude | Out-Null
        $before = Get-Hash $state
        $arguments = @('-Mode','run','-Engine','auto','-FallbackPolicy','automatic','-Role','general','-Profile','review','-Artifact','git:working-tree','-WorkflowBaseSha',$base,'-WorkflowBaseRef',"refs/heads/$branch",'-PromptFile',$prompt,'-Output',$result,'-TimeoutSeconds','2')
        $argumentsJson = Join-Path $reviews 'launch-arguments.json'; [IO.File]::WriteAllText($argumentsJson, ($arguments | ConvertTo-Json -Compress))
        $contextLauncher = Join-Path $reviews 'launch-host-context.ps1'
        [IO.File]::WriteAllText($contextLauncher, @'
param([string]$ContextPath, [string]$EngineHost, [string]$ArgumentsJsonPath)
$argumentsJson = [IO.File]::ReadAllText($ArgumentsJsonPath)
& $ContextPath -Mode launch -Host $EngineHost -LaunchArgumentsJson $argumentsJson
'@)
        $dispatchOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $contextLauncher $context claude $argumentsJson 2>&1) -join "`n"; $dispatchRc = $LASTEXITCODE
    } finally { Pop-Location }
    Assert-True ($dispatchRc -eq 0) 'installed dispatcher completes same-engine fallback'
    Assert-True ($dispatchOutput -like '*visible fallback*') 'fallback is visible'
    $receipt = Get-ChildItem -LiteralPath $reviews -Filter '*.receipt' | Sort-Object Name | Select-Object -Last 1
    Assert-True ((Get-ReceiptValue $receipt.FullName 'first_attempted_engine') -ceq 'codex') 'receipt records unavailable preferred engine'
    Assert-True ((Get-ReceiptValue $receipt.FullName 'actual_engine') -ceq 'claude') 'receipt records Claude fallback'
    Assert-True ((Get-ReceiptValue $receipt.FullName 'fallback') -ceq 'true') 'receipt records degraded selection'
    Assert-True ((Get-Hash $state) -ceq $before) 'reviewer leaves canonical state unchanged'
}
finally {
    $env:PATH=$originalPath
    Remove-Item Env:FORGE_ENGINE_IDENTITY_FIXTURE,Env:FORGE_DISPATCH_TEST_MODE,Env:FORGE_TEST_DISABLE_ENGINE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'PASS: PowerShell Task 11 integrated seam'
