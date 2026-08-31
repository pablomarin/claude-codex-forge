$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$action = Join-Path $root 'hooks/lib/authorized-action.ps1'
$hook = Join-Path $root 'hooks/check-external-mutation-auth.ps1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('Forge Action PS ' + [Guid]::NewGuid().ToString('N'))
$script:Passed = 0; $script:Failed = 0
function Check([bool]$Condition, [string]$Message) { if ($Condition) { $script:Passed++; Write-Host "  PASS $Message" } else { $script:Failed++; [Console]::Error.WriteLine("  FAIL $Message") } }
try {
    New-Item -ItemType Directory -Path (Join-Path $scratch '.forge/local/actions') -Force | Out-Null
    & git -C $scratch init -q; & git -C $scratch config user.email test@example.invalid; & git -C $scratch config user.name ForgeTest
    [IO.File]::WriteAllText((Join-Path $scratch 'x'), 'x'); & git -C $scratch add x; & git -C $scratch commit -qm base
    $prepareWrapper = Join-Path $scratch 'prepare-action.ps1'
    [IO.File]::WriteAllText($prepareWrapper, @'
param([string]$Action, [string]$Output)
& $Action -Mode prepare -Adapter gh-issue-close -System github -Operation close-issue -Target 'owner/repo#12' -Arg @('owner/repo','12') -ExpectedEffect 'issue closes' -Output $Output
exit $LASTEXITCODE
'@)
    $pending = Join-Path $scratch '.forge/local/actions/pending.action'; Push-Location $scratch
    try { $rendered = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $prepareWrapper -Action $action -Output $pending 2>&1 | Out-String); $prepareRc = $LASTEXITCODE }
    finally { Pop-Location }
    Check ($prepareRc -eq 0) 'allowlisted direct adapter prepares successfully'
    Check ($rendered -like '*developer must execute*') 'rendered instruction requires developer execution'
    Check ((Get-Content -LiteralPath $pending -Raw) -like '*status=PENDING_HUMAN_EXECUTION*') 'pending manifest cannot unlock an agent runner'
    $bad = Join-Path $scratch '.forge/local/actions/bad.action'; Push-Location $scratch
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $action -Mode prepare -Adapter shell -System github -Operation x -Target y -Arg '$(echo pwned)' -ExpectedEffect z -Output $bad 2>$null | Out-Null; $badRc = $LASTEXITCODE }
    finally { Pop-Location }
    Check ($badRc -ne 0 -and -not (Test-Path -LiteralPath (Join-Path $scratch 'pwned'))) 'non-allowlisted nested shell text remains inert'
    Add-Content -LiteralPath $pending -Value 'approved=true'
    $reported = Join-Path $scratch '.forge/local/actions/reported.receipt'; Push-Location $scratch
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $action -Mode report -Manifest $pending -Outcome SUCCESS -Output $reported | Out-Null; $reportRc = $LASTEXITCODE }
    finally { Pop-Location }
    Check ($reportRc -eq 0) 'developer-reported outcome is audit-recorded'
    Check ((Get-Content -LiteralPath $reported -Raw) -like '*verification=UNVERIFIED*') 'reported outcome remains unverified pending independent repro'
    $sibling = Join-Path ([IO.Path]::GetTempPath()) ('Forge Action PS sibling ' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $sibling '.forge/local/actions') -Force | Out-Null
    & git -C $sibling init -q; & git -C $sibling config user.email test@example.invalid; & git -C $sibling config user.name ForgeTest
    [IO.File]::WriteAllText((Join-Path $sibling 'x'), 'x'); & git -C $sibling add x; & git -C $sibling commit -qm base
    $copied = Join-Path $sibling '.forge/local/actions/copied.action'; Copy-Item -LiteralPath $pending -Destination $copied
    Push-Location $sibling
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $action -Mode report -Manifest $copied -Outcome SUCCESS -Output (Join-Path $sibling '.forge/local/actions/copied.receipt') 2>$null | Out-Null; $copiedRc = $LASTEXITCODE }
    finally { Pop-Location }
    Check ($copiedRc -eq 2) 'copied sibling manifest is rejected by worktree identity'
    Push-Location $scratch
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $action -Mode report -Manifest $pending -Outcome SUCCESS -Output (Join-Path $scratch 'outside.receipt') 2>$null | Out-Null; $outsideRc = $LASTEXITCODE }
    finally { Pop-Location }
    Check ($outsideRc -eq 2) 'report output outside Forge local actions is rejected'
    $existing = Join-Path $scratch '.forge/local/actions/existing.receipt'; [IO.File]::WriteAllText($existing, 'owner')
    Push-Location $scratch
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $action -Mode report -Manifest $pending -Outcome SUCCESS -Output $existing 2>$null | Out-Null; $existingRc = $LASTEXITCODE }
    finally { Pop-Location }
    Check ($existingRc -eq 2 -and [IO.File]::ReadAllText($existing) -ceq 'owner') 'existing report output is never clobbered'
    $linked = Join-Path $scratch '.forge/local/actions/report-link.receipt'; & cmd.exe /d /c mklink /H "$linked" "$reported" | Out-Null
    Push-Location $scratch
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $action -Mode report -Manifest $pending -Outcome SUCCESS -Output $linked 2>$null | Out-Null; $linkedRc = $LASTEXITCODE }
    finally { Pop-Location }
    Check ($linkedRc -eq 2) 'linked report output is rejected without clobbering'
    Remove-Item -LiteralPath $sibling -Recurse -Force -ErrorAction SilentlyContinue
    $input = '{"tool_input":{"command":"gh issue close 12"}}'
    $inputFile = Join-Path $scratch 'hook-input.json'; [IO.File]::WriteAllText($inputFile, $input)
    $hookProcess = Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$hook) -RedirectStandardInput $inputFile -RedirectStandardOutput (Join-Path $scratch 'hook.out') -RedirectStandardError (Join-Path $scratch 'hook.err') -Wait -PassThru
    Check ($hookProcess.ExitCode -eq 2) 'external mutation hook blocks recognizable main-agent mutation'
    $env:FORGE_DISPATCH_MODE = 'review'
    $dispatchProcess = Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$hook) -RedirectStandardInput $inputFile -RedirectStandardOutput (Join-Path $scratch 'dispatch.out') -RedirectStandardError (Join-Path $scratch 'dispatch.err') -Wait -PassThru
    Remove-Item Env:FORGE_DISPATCH_MODE -ErrorAction SilentlyContinue
    Check ($dispatchProcess.ExitCode -eq 0) 'reviewer mutation hook is a tested no-op'
}
finally { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "PowerShell authorized action: $($script:Passed) passed, $($script:Failed) failed"
if ($script:Failed -ne 0) { exit 1 }
exit 0
