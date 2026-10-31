# Disposable fixtures exercise the native helper and hook; no live-host qualification is claimed.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('forge-review-waiver-' + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
$runner = (Get-Process -Id $PID).Path
$script:passes = 0; $script:failures = 0
. (Join-Path $repo 'hooks\lib\verification-receipt.ps1')
$decision = 'Skip code review for this exact change; finish the approved branch.'
$provenance = 'Explicit developer instruction in the current conversation, turn 7.'
function Assert-Waiver([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:passes++; Write-Host "PASS $Message" }
    else { $script:failures++; Write-Host "FAIL $Message" }
}
function Write-Fixture([string]$Relative, [string]$Text) { [IO.File]::WriteAllText((Join-Path $script:project $Relative), $Text, $utf8) }
function Edit-State([string]$Before, [string]$After) {
    $path = Join-Path $script:project '.forge/local/state.md'
    $body = [IO.File]::ReadAllText($path)
    if (-not $body.Contains($Before)) { throw "fixture state missing $Before" }
    [IO.File]::WriteAllText($path, $body.Replace($Before, $After), $utf8)
}
function Edit-Field([string]$Relative, [string]$Key, [string]$Value) {
    $path = Join-Path $script:project $Relative
    $body = [IO.File]::ReadAllText($path)
    [IO.File]::WriteAllText($path, ($body -replace "(?m)^$Key=.*$", "$Key=$Value"), $utf8)
}
function Invoke-FixtureReceipt([string]$Action, [string]$HumanDecision = $decision, [string]$HumanProvenance = $provenance) {
    Push-Location $script:project
    try {
        if ($Action -ceq 'record-review-waiver') {
            return Invoke-VerificationReceipt -ReceiptMode $Action -StatePath '.forge/local/state.md' -ReceiptDecision $HumanDecision -ReceiptProvenance $HumanProvenance
        }
        return Invoke-VerificationReceipt -ReceiptMode $Action -StatePath '.forge/local/state.md'
    }
    catch { return [pscustomobject]@{ Status = 2; Error = $_.Exception.Message; Lines = @() } }
    finally { Pop-Location }
}
function Invoke-FixtureGate([string]$CommandText, [string]$HookPath = (Join-Path $repo 'hooks/check-workflow-gates.ps1'), [string[]]$HookArguments = @()) {
    $payload = @{ cwd = $script:project; host = $script:mainHost; tool_input = @{ command = $CommandText } } | ConvertTo-Json -Compress
    # Windows PowerShell 5.1 pipes native stdin as ASCII by default. JSON escapes
    # preserve the exact command through that transport without changing host encodings.
    $payload = [regex]::Replace($payload, '[^\x00-\x7f]', { param($character) '\u{0:x4}' -f [int][char]$character.Value })
    $out = Join-Path $scratch 'gate.out'; $err = Join-Path $scratch 'gate.err'
    # powershell.exe 5.1 turns native stderr into ErrorRecords, so capture each stream to a file.
    $savedPreference = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $payload | & $runner -NoProfile -File $HookPath @HookArguments > $out 2> $err; $status = $LASTEXITCODE }
    finally { $ErrorActionPreference = $savedPreference }
    return [pscustomobject]@{ Status = $status; Text = ([IO.File]::ReadAllText($out) + [IO.File]::ReadAllText($err)) }
}
function Freeze-Fixture {
    Push-Location $script:project
    try {
        & (Join-Path $repo 'hooks/lib/candidate-fingerprint.ps1') -Mode freeze -Artifact 'git:working-tree' -WorkflowBaseSha $script:base -WorkflowBaseRef main -Output (Join-Path $script:project '.forge/local/evidence/candidate.receipt') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'fixture candidate capture failed' }
    }
    finally { Pop-Location }
}
function Write-VerifierFixture([string]$Kind, [string]$Result = 'PASS', [int]$Status = 0) {
    $body = "VERDICT: $Result`nControlled focused verification fixture.`n"
    if ($Result -ceq 'N/A') { $body += "N/A_REASON: this controlled change has no user-facing browser flow.`n" }
    Write-Fixture ".forge/local/evidence/$Kind.report" $body
    Push-Location $script:project
    try {
        $response = Invoke-VerificationReceipt -ReceiptMode write -ReceiptKind $Kind -CandidatePath '.forge/local/evidence/candidate.receipt' -CommandText "controlled direct $Kind check" -ProfileName focused -ReportPath ".forge/local/evidence/$Kind.report" -ReceiptResult $Result -ReceiptExitStatus $Status -OutputPath ".forge/local/evidence/$Kind.receipt"
        if ($response.Status -ne 0) { throw $response.Error }
    }
    finally { Pop-Location }
}
function New-WaiverFixture([string]$Name, [string]$MainHost = 'codex', [bool]$Merge = $false, [string]$E2e = 'PASS') {
    $script:mainHost = $MainHost; $script:project = Join-Path $scratch $Name
    foreach ($relative in @('.forge/local/evidence','.forge/local/reviews','docs','tests')) { [IO.Directory]::CreateDirectory((Join-Path $script:project $relative)) | Out-Null }
    & git -C $script:project init -q --initial-branch=main
    $script:project = (Resolve-Path ([string](& git -C $script:project rev-parse --show-toplevel))).Path
    & git -C $script:project config user.name ForgeTest
    & git -C $script:project config user.email forge-test@example.invalid
    Write-Fixture '.gitignore' ".forge/`n"
    Write-Fixture 'app.txt' "base app`n"
    Write-Fixture 'docs/CHANGELOG.md' "# Changes`n`n- Shared entry.`n"
    & git -C $script:project add -A
    & git -C $script:project commit -qm base
    $script:base = ([string](& git -C $script:project rev-parse HEAD)).Trim()
    $common = (Resolve-Path -LiteralPath (([string](& git -C $script:project rev-parse --absolute-git-dir)).Trim())).Path
    & git -C $script:project checkout -qb fix/review-waiver
    Write-Fixture 'app.txt' "changed application behavior`n"
    if ($Merge) {
        Write-Fixture 'docs/CHANGELOG.md' "# Changes`n`n- Feature entry.`n"
        & git -C $script:project add -A
        & git -C $script:project commit -qm feature
        & git -C $script:project checkout -q main
        Write-Fixture 'docs/CHANGELOG.md' "# Changes`n`n- Main entry.`n"
        Write-Fixture 'package.txt' "dependency update`n"
        Write-Fixture 'tests/unit.txt' "repaired unit test`n"
        & git -C $script:project add -A
        & git -C $script:project commit -qm 'main package and test changes'
        & git -C $script:project checkout -q fix/review-waiver
        & git -C $script:project merge --no-edit main | Out-Null
        if ($LASTEXITCODE -ne 1 -or ([string](& git -C $script:project diff --name-only --diff-filter=U)).Trim() -cne 'docs/CHANGELOG.md') { throw 'expected changelog-only merge conflict' }
        Write-Fixture 'docs/CHANGELOG.md' "# Changes`n`n- Feature entry.`n- Main entry.`n- Shared entry.`n"
    }
    & git -C $script:project add -A
    Write-Fixture '.forge/local/state.md' @"
<!-- forge:state-schema v6 -->
## Identity
| Worktree root | $script:project |
| Git common directory | $common |
| Last active host | $MainHost |
| Workflow base ref | main |
| Workflow base SHA | $script:base |
## Workflow
| Command | /fix-bug review-waiver |
| Phase | finalize |
| Next step | commit the approved candidate |
### Checklist
- [ ] Code review loop
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified
## /goal session
| nonce | <uuid-v4-lowercase> |
## PR authorization
## Receipts
| Review iteration | 1 |
| First certified iteration | none |
| Candidate receipt | .forge/local/evidence/candidate.receipt |
| Spec review receipt | .forge/local/reviews/code-spec.receipt |
| Quality review receipt | .forge/local/reviews/code-quality.receipt |
| Verify app receipt | .forge/local/evidence/verify-app.receipt |
| E2E receipt | .forge/local/evidence/e2e.receipt |
| Promotion receipt | .forge/local/evidence/promotion.receipt |
"@
    Write-Fixture '.forge/local/reviews/code-spec.receipt' "schema_version=0`nhistorical_review=spec`n"
    Write-Fixture '.forge/local/reviews/code-quality.receipt' "schema_version=0`nhistorical_review=quality`n"
    Freeze-Fixture
    Write-VerifierFixture verify-app
    Write-VerifierFixture e2e $E2e
}
try {
    [IO.Directory]::CreateDirectory($scratch) | Out-Null
    foreach ($verdict in @('PASS','FAIL','N/A','INVALID')) {
        $handleReport = Join-Path $scratch ("report-handle-" + $verdict.Replace('/','-') + '.report')
        [IO.File]::WriteAllText($handleReport, "VERDICT: $verdict`nControlled report body.`n", $utf8)
        try { $null = Get-ReportVerdict $handleReport e2e } catch { if ($verdict -cne 'INVALID') { throw } }
        $handle = $null
        try {
            $handle = [IO.File]::Open($handleReport, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            Assert-Waiver $true "report verdict $verdict releases its reader before returning"
        } catch { Assert-Waiver $false "report verdict $verdict releases its reader before returning" }
        finally { if ($handle) { $handle.Dispose() } }
    }
    if ($env:FORGE_WAIVER_EXTENSION_ONLY -ne '1') {
    foreach ($mainHost in @('claude','codex')) {
        foreach ($merge in @($false,$true)) {
            $e2e = if ($merge) { 'N/A' } else { 'PASS' }
            New-WaiverFixture "$mainHost-$merge" $mainHost $merge $e2e
            $head = ([string](& git -C $script:project rev-parse HEAD)).Trim()
            $tree = ([string](& git -C $script:project write-tree)).Trim()
            $parents = $head
            if ($merge) { $parents += ' ' + ([string](& git -C $script:project rev-parse MERGE_HEAD)).Trim() }
            $stateHash = Get-ShaFile (Join-Path $script:project '.forge/local/state.md')
            $reviewHash = Get-ShaFile (Join-Path $script:project '.forge/local/reviews/code-spec.receipt')
            Assert-Waiver ((Invoke-FixtureGate 'git commit --no-edit').Status -eq 2) "$mainHost merge=$merge review gate blocks before approval"
            $ordinary = Invoke-FixtureReceipt check
            Assert-Waiver ($ordinary.Status -eq 2 -and $ordinary.Lines -ccontains 'REVIEWS_VALID:false') 'ordinary review validity starts false'
            $recorded = Invoke-FixtureReceipt record-review-waiver
            Assert-Waiver ($recorded.Status -eq 0) "records explicit decision ($($recorded.Error))"
            $waiver = Invoke-FixtureReceipt check-review-waiver
            Assert-Waiver ($waiver.Status -eq 0 -and $waiver.Lines -ccontains 'REVIEW_WAIVER_VALID:true' -and $waiver.Lines -ccontains 'REVIEW_STATUS:human-waived' -and $waiver.Lines -ccontains 'REVIEW_WAIVER_STATE:precommit') 'exact staged candidate has valid precommit waiver without a review PASS'
            Assert-Waiver (Test-Path (Join-Path $script:project '.forge/local/evidence/candidate.receipt.review-waiver')) 'waiver uses a separate candidate sidecar'
            Assert-Waiver ((Get-ShaFile (Join-Path $script:project '.forge/local/state.md')) -ceq $stateHash) 'recording preserves state and certification counters'
            $ordinary = Invoke-FixtureReceipt check
            Assert-Waiver ($ordinary.Status -eq 2 -and $ordinary.Lines -ccontains 'REVIEWS_VALID:false') 'waiver never becomes an independent review PASS'
            Assert-Waiver ((Invoke-FixtureGate 'git push origin fix/review-waiver').Status -eq 2) 'uncommitted candidate waiver cannot authorize pushing the previous HEAD'
            Assert-Waiver ((Invoke-FixtureGate 'git commit --no-edit').Status -eq 0) 'commit gate permits explicit waiver'
            if ($merge) { & git -C $script:project -c core.editor=true commit --no-edit | Out-Null }
            else { & git -C $script:project commit -qm 'approved code change' }
            Assert-Waiver ($LASTEXITCODE -eq 0) 'ordinary Git commit succeeds'
            Assert-Waiver (([string](& git -C $script:project rev-parse 'HEAD^{tree}')).Trim() -ceq $tree) 'ordinary commit preserves approved tree'
            $actualParents = (([string](& git -C $script:project rev-list --parents -n 1 HEAD)).Trim() -split ' ' | Select-Object -Skip 1) -join ' '
            Assert-Waiver ($actualParents -ceq $parents) 'ordinary commit preserves every approved parent in order'
            $waiver = Invoke-FixtureReceipt check-review-waiver
            Assert-Waiver ($waiver.Status -eq 0 -and $waiver.Lines -ccontains 'REVIEW_WAIVER_STATE:postcommit') 'exact ordinary commit retains postcommit waiver'
            Assert-Waiver ((Invoke-FixtureGate 'git commit --no-edit').Status -eq 2) 'postcommit waiver cannot authorize another commit'
            Assert-Waiver ((Invoke-FixtureGate 'git push origin fix/review-waiver').Status -eq 0) 'push gate permits exact committed tree'
            Assert-Waiver ((Get-ShaFile (Join-Path $script:project '.forge/local/reviews/code-spec.receipt')) -ceq $reviewHash) 'historical review bytes remain unchanged'
            Assert-Waiver ((Invoke-FixtureReceipt check).Status -eq 2) 'postcommit ordinary certification remains false'
            & git -C $script:project commit --allow-empty -qm 'extra unapproved commit'
            Assert-Waiver ((Invoke-FixtureReceipt check-review-waiver).Status -eq 2) 'same-tree extra commit invalidates parent boundary'
        }
    }
    foreach ($missing in @('decision','provenance','whitespace-decision','whitespace-provenance')) {
        New-WaiverFixture "missing-$missing"
        $humanDecision = $decision; $humanProvenance = $provenance
        switch ($missing) { decision { $humanDecision = '' } provenance { $humanProvenance = '' } whitespace-decision { $humanDecision = '   ' } whitespace-provenance { $humanProvenance = '   ' } }
        Assert-Waiver ((Invoke-FixtureReceipt record-review-waiver $humanDecision $humanProvenance).Status -eq 2) "$missing cannot authorize waiver"
        Assert-Waiver (-not (Test-Path (Join-Path $script:project '.forge/local/evidence/candidate.receipt.review-waiver'))) 'missing approval never publishes sidecar'
    }
    foreach ($mutation in @('staged','unstaged','untracked','candidate','verifier-report','verifier-receipt','failed-app','failed-e2e','stale-app','missing-e2e','workflow','base','state-root','state-common','goal-nonce','goal-none','parents','duplicate-parents','rewritten-parents','branch','missing-provenance')) {
        New-WaiverFixture "reject-$mutation" codex ($mutation -in @('parents','duplicate-parents','rewritten-parents'))
        Assert-Waiver ((Invoke-FixtureReceipt record-review-waiver).Status -eq 0) "$mutation control starts valid"
        switch ($mutation) {
            staged { Write-Fixture 'app.txt' "another change`n"; & git -C $script:project add app.txt }
            unstaged { Write-Fixture 'app.txt' "unstaged change`n" }
            untracked { Write-Fixture 'untracked.txt' "untracked`n" }
            candidate { [IO.File]::AppendAllText((Join-Path $script:project '.forge/local/evidence/candidate.receipt'), "changed_metadata=true`n", $utf8) }
            verifier-report { [IO.File]::AppendAllText((Join-Path $script:project '.forge/local/evidence/verify-app.report'), "tampered`n", $utf8) }
            verifier-receipt { [IO.File]::AppendAllText((Join-Path $script:project '.forge/local/evidence/verify-app.receipt'), "changed_metadata=true`n", $utf8) }
            failed-app { Write-VerifierFixture verify-app FAIL 1 }
            failed-e2e { Write-VerifierFixture e2e FAIL 1 }
            stale-app { Edit-Field '.forge/local/evidence/verify-app.receipt' ended_at '2000-01-01T00:00:00Z' }
            missing-e2e { Remove-Item (Join-Path $script:project '.forge/local/evidence/e2e.receipt') }
            workflow { Edit-State '/fix-bug review-waiver' '/fix-bug different-task' }
            base { Edit-State "| Workflow base SHA | $script:base |" '| Workflow base SHA | changed |' }
            state-root { Edit-State "| Worktree root | $script:project |" '| Worktree root | changed |' }
            state-common { $common = (Resolve-Path -LiteralPath (([string](& git -C $script:project rev-parse --absolute-git-dir)).Trim())).Path; Edit-State "| Git common directory | $common |" '| Git common directory | changed |' }
            goal-nonce { Edit-State '<uuid-v4-lowercase>' 'different-active-goal' }
            goal-none { Edit-State '<uuid-v4-lowercase>' 'none' }
            parents { $gitDir = ([string](& git -C $script:project rev-parse --absolute-git-dir)).Trim(); [IO.File]::WriteAllText((Join-Path $gitDir 'MERGE_HEAD'), "$script:base`n", $utf8) }
            duplicate-parents { $gitDir = ([string](& git -C $script:project rev-parse --absolute-git-dir)).Trim(); $head = ([string](& git -C $script:project rev-parse HEAD)).Trim(); [IO.File]::WriteAllText((Join-Path $gitDir 'MERGE_HEAD'), "$head`n", $utf8) }
            rewritten-parents {
                $tree = ([string](& git -C $script:project write-tree)).Trim()
                $newCommit = ([string](& git -C $script:project commit-tree $tree -p $script:base -m 'different ancestry')).Trim()
                & git -C $script:project reset --hard $newCommit | Out-Null
                Edit-Field '.forge/local/evidence/candidate.receipt.review-waiver' parents $script:base
            }
            branch { & git -C $script:project checkout -qb fix/different-task }
            missing-provenance { $path = Join-Path $script:project '.forge/local/evidence/candidate.receipt.review-waiver'; if (Test-Path $path) { [IO.File]::WriteAllText($path, ([IO.File]::ReadAllText($path) -replace '(?m)^provenance=.*\r?\n',''), $utf8) } }
        }
        Assert-Waiver ((Invoke-FixtureReceipt check-review-waiver).Status -eq 2) "$mutation invalidates waiver"
        $mutationCommand = if ($mutation -ceq 'rewritten-parents') { 'git push origin fix/review-waiver' } else { 'git commit --no-edit' }
        Assert-Waiver ((Invoke-FixtureGate $mutationCommand).Status -eq 2) "$mutation blocks shipping"
    }
    New-WaiverFixture 'commit-command-boundary'
    Assert-Waiver ((Invoke-FixtureReceipt record-review-waiver).Status -eq 0) 'command boundary has valid waiver'
    foreach ($commandText in @('git commit --no-edit','git commit -m approved','git commit --message="approved change"','git commit -F .forge/local/message.txt','git commit --quiet --signoff -m ''approved change''','git commit -m approved,-n')) {
        Assert-Waiver ((Invoke-FixtureGate $commandText).Status -eq 0) "ordinary full-index command accepts waiver: $commandText"
    }
    foreach ($commandText in @('git commit --no-verify -m approved','git commit -n -m approved','git -c core.hooksPath=/tmp commit -m approved','git -C . commit -m approved','FORGE_TEST=x git commit -m approved','git commit --amend --no-edit','git commit --only app.txt','git commit --include app.txt','git commit -a -m approved','git commit --all -m approved','git commit -p','git commit app.txt','git commit -- app.txt','git commit --message="$(git status)"','git commit -m @message','git commit -m --% -m -n',"git commit -m 'a$([char]0x2019) --no-verify $([char]0x2018)b'","git commit -m approved`necho done")) {
        Assert-Waiver ((Invoke-FixtureGate $commandText).Status -eq 2) "unapproved command semantics cannot consume waiver: $commandText"
    }
    $savedPipelineEncoding = $OutputEncoding
    try {
        $OutputEncoding = [Text.Encoding]::ASCII
        $unicodeCommand = "git commit -m 'a$([char]0x2019) --no-verify $([char]0x2018)b'"
        $captureHook = Join-Path $scratch 'capture-command.ps1'
        [IO.File]::WriteAllText($captureHook, '$inputData = [Console]::In.ReadToEnd() | ConvertFrom-Json; [IO.File]::WriteAllText((Join-Path $PSScriptRoot "transport-command.txt"), $inputData.tool_input.command)', $utf8)
        $null = Invoke-FixtureGate $unicodeCommand $captureHook
        Assert-Waiver ([IO.File]::ReadAllText((Join-Path $scratch 'transport-command.txt')) -ceq $unicodeCommand) 'ASCII native pipeline delivers the exact Unicode command'
        Assert-Waiver ((Invoke-FixtureGate $unicodeCommand).Status -eq 2) 'ASCII native pipeline preserves the Unicode command rejection'
    } finally { $OutputEncoding = $savedPipelineEncoding }
    foreach ($merge in @($false,$true)) {
        New-WaiverFixture "committed-renewal-$merge" codex $merge
        Assert-Waiver ((Invoke-FixtureReceipt record-review-waiver).Status -eq 0) 'initial decision records before expiry'
        if ($merge) { & git -C $script:project -c core.editor=true commit --no-edit | Out-Null }
        else { & git -C $script:project commit -qm 'approved code change' }
        Edit-Field '.forge/local/evidence/candidate.receipt.review-waiver' recorded_at '2000-01-01T00:00:00Z'
        foreach ($kind in @('verify-app','e2e')) { Edit-Field ".forge/local/evidence/$kind.receipt" ended_at '2000-01-01T00:00:00Z' }
        Assert-Waiver ((Invoke-FixtureReceipt check-review-waiver).Status -eq 2) 'expired committed approval requires fresh evidence'
        Freeze-Fixture
        Write-VerifierFixture verify-app
        Write-VerifierFixture e2e
        $recorded = Invoke-FixtureReceipt record-review-waiver
        Assert-Waiver ($recorded.Status -eq 0 -and $recorded.Lines -ccontains 'REVIEW_WAIVER_STATE:postcommit') "renewal at committed HEAD is postcommit; merge=$merge"
        Assert-Waiver ((Invoke-FixtureGate 'git push origin fix/review-waiver').Status -eq 0) 'renewed existing HEAD can push without another commit'
        Assert-Waiver ((Invoke-FixtureGate 'git commit --no-edit').Status -eq 2) 'renewed existing HEAD cannot authorize another commit'
        & git -C $script:project commit --allow-empty -qm 'unapproved same-tree extra commit'
        Assert-Waiver ((Invoke-FixtureReceipt check-review-waiver).Status -eq 2) 'existing-HEAD approval rejects a same-tree child'
    }
    New-WaiverFixture 'pending-same-tree-merge'
    & git -C $script:project commit -qm feature
    & git -C $script:project checkout -q main
    & git -C $script:project commit --allow-empty -qm 'main history update'
    & git -C $script:project checkout -q fix/review-waiver
    $mergeErrorPreference = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & git -C $script:project merge --no-ff --no-commit main 2>$null | Out-Null; $mergeStatus = $LASTEXITCODE }
    finally { $ErrorActionPreference = $mergeErrorPreference }
    if ($mergeStatus -ne 0) { throw 'same-tree merge fixture failed' }
    Freeze-Fixture
    Write-VerifierFixture verify-app
    Write-VerifierFixture e2e
    $recorded = Invoke-FixtureReceipt record-review-waiver
    Assert-Waiver ($recorded.Status -eq 0 -and $recorded.Lines -ccontains 'REVIEW_WAIVER_STATE:precommit') 'same-tree pending merge still needs its two-parent commit'
    Assert-Waiver ((Invoke-FixtureGate 'git commit --no-edit').Status -eq 0) 'same-tree merge commit is allowed'
    & git -C $script:project -c core.editor=true commit --no-edit | Out-Null
    Assert-Waiver ((Invoke-FixtureReceipt check-review-waiver).Status -eq 0) 'same-tree merge keeps its exact approved parents'
    Assert-Waiver ((Invoke-FixtureGate 'git push origin fix/review-waiver').Status -eq 0) 'same-tree merge can push after its commit'
    New-WaiverFixture 'helper-scope'
    & git -C $script:project commit -qm feature
    [IO.Directory]::CreateDirectory((Join-Path $script:project 'tests/e2e/reports')) | Out-Null
    Write-Fixture 'tests/e2e/reports/fixture.md' "Fresh report for legacy diagnostics.`n"
    [IO.File]::SetLastWriteTimeUtc((Join-Path $script:project 'tests/e2e/reports/fixture.md'), [DateTime]::UtcNow.AddSeconds(5))
    Edit-State '| Candidate receipt | .forge/local/evidence/candidate.receipt |' '| Candidate receipt | <candidate-receipt> |'
    Edit-State '- [ ] Code review loop' '- [x] Code review loop'
    $gate = Invoke-FixtureGate 'git push origin fix/review-waiver'
    Assert-Waiver ($gate.Status -eq 2 -and $gate.Text.Contains('final receipt set') -and -not $gate.Text.Contains('no fresh report')) 'early helper preserves FileInfo freshness diagnostics'
    New-WaiverFixture 'helper-startup-failure'
    $brokenHook = Join-Path $scratch 'broken-hook'
    [IO.Directory]::CreateDirectory((Join-Path $brokenHook 'lib')) | Out-Null
    Copy-Item (Join-Path $repo 'hooks/check-workflow-gates.ps1') (Join-Path $brokenHook 'check-workflow-gates.ps1')
    foreach ($helper in @('state-path.ps1','review-breaker.ps1')) { Copy-Item (Join-Path $repo "hooks/lib/$helper") (Join-Path $brokenHook "lib/$helper") }
    [IO.File]::WriteAllText((Join-Path $brokenHook 'lib/verification-receipt.ps1'), "throw 'controlled helper startup failure'", $utf8)
    $gate = Invoke-FixtureGate 'git commit --no-edit' (Join-Path $brokenHook 'check-workflow-gates.ps1')
    Assert-Waiver ($gate.Status -eq 2 -and $gate.Text.Contains('required quality gate(s) incomplete')) 'helper startup error declines waiver without crashing the hook'
    foreach ($failed in @('failed-app','failed-e2e','stale-app','unstaged')) {
        New-WaiverFixture "record-$failed"
        switch ($failed) {
            failed-app { Write-VerifierFixture verify-app FAIL 1 }
            failed-e2e { Write-VerifierFixture e2e FAIL 1 }
            stale-app { Edit-Field '.forge/local/evidence/verify-app.receipt' ended_at '2000-01-01T00:00:00Z' }
            unstaged { Write-Fixture 'app.txt' "unstaged change`n" }
        }
        Assert-Waiver ((Invoke-FixtureReceipt record-review-waiver).Status -eq 2) "$failed prevents recording waiver"
    }
    foreach ($boundary in @('simplified','verified','e2e','compound','pr-authorization','config','breaker')) {
        New-WaiverFixture "boundary-$boundary"
        if ($boundary -ceq 'pr-authorization') { Edit-State '<uuid-v4-lowercase>' '11111111-1111-4111-8111-111111111111' }
        Assert-Waiver ((Invoke-FixtureReceipt record-review-waiver).Status -eq 0) "$boundary control has valid waiver"
        $commandText = 'git commit --no-edit'
        switch ($boundary) {
            simplified { Edit-State '- [x] Simplified' '- [ ] Simplified' }
            verified { Edit-State '- [x] Verified (tests/lint/types)' '- [ ] Verified (tests/lint/types)' }
            e2e { Edit-State '- [x] E2E verified' '- [ ] E2E verified' }
            compound { $commandText = 'git commit -m approved && git push origin fix/review-waiver' }
            pr-authorization { $commandText = 'gh pr create --title approved --body approved' }
            config { Write-Fixture '.forge/version' "6`n" }
            breaker { Edit-State '| First certified iteration | none |' '| First certified iteration | 1 |'; Edit-State '| Review iteration | 1 |' '| Review iteration | 5 |' }
        }
        $gate = Invoke-FixtureGate $commandText
        Assert-Waiver ($gate.Status -eq 2) "$boundary remains required despite review waiver"
        if ($boundary -in @('simplified','verified','e2e')) { Assert-Waiver ($gate.Text.Contains('1 required quality gate(s) incomplete')) 'waiver clears only review while the remaining checklist item blocks' }
        switch ($boundary) {
            compound { Assert-Waiver ($gate.Text.Contains('compound ship command blocked')) 'compound guard remains blocker' }
            pr-authorization { Assert-Waiver ($gate.Text.Contains('PR authorization')) 'separate PR authorization remains blocker' }
            config { Assert-Waiver ($gate.Text.Contains('FORGE_CONFIG_TAMPERED')) 'managed configuration guard remains blocker' }
            breaker { Assert-Waiver ($gate.Text.Contains('convergence breaker')) 'convergence breaker remains blocker' }
        }
    }
    }
    function Invoke-WorkflowFixture([string]$Action, [string]$Scopes = '') {
        Push-Location $script:project
        try { return Invoke-VerificationReceipt -ReceiptMode $Action -StatePath '.forge/local/state.md' -ReceiptSkip $Scopes -ReceiptDecision $decision -ReceiptProvenance $provenance }
        catch { return [pscustomobject]@{ Status = 2; Error = $_.Exception.Message; Lines = @() } }
        finally { Pop-Location }
    }
    function Write-CleanReviewFixture([string]$Role) {
        $candidateFile = Join-Path $script:project '.forge/local/evidence/candidate.receipt'
        $report = Join-Path $script:project ".forge/local/reviews/$Role.report"
        Write-Fixture ".forge/local/reviews/$Role.report" "schema_version=1`nverdict=CLEAN`nmax_severity=NONE`nblocked_class=none`n"
        $data = [ordered]@{schema_version='1'; invocation_id=$Role; timestamp=[DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'); main_host=$script:mainHost; requested_engine='claude'; actual_engine='claude'; fallback='false'; fallback_reason='none'; role=$Role; profile='review'; review_iteration='1'; fresh_process='true'; artifact_kind='git-working-tree'; artifact_hash=(Get-Kv $candidateFile 'candidate_id'); output_path=$report; output_hash=(Get-ShaFile $report); process_exit_status='0'; semantic_verdict='CLEAN'; max_severity='NONE'; findings_digest=(Get-ShaText ''); result_schema_version='1'; blocked_class='none'}
        foreach ($key in @('worktree_identity','git_head','workflow_base_sha')) { $data[$key] = Get-Kv $candidateFile $key }
        $body = @(); foreach ($key in $data.Keys) { $body += "$key=$($data[$key])" }
        Write-Fixture ".forge/local/reviews/$Role.receipt" (($body -join "`n") + "`n")
    }
    foreach ($hostName in @('claude','codex')) {
        New-WaiverFixture "extension-e2e-$hostName" $hostName
        Write-CleanReviewFixture code-spec; Write-CleanReviewFixture code-quality
        Edit-State '- [ ] Code review loop' '- [x] Code review loop'
        Edit-State '- [x] E2E verified' '- [ ] E2E verified'
        Remove-Item -LiteralPath (Join-Path $script:project '.forge/local/evidence/e2e.receipt')
        Assert-Waiver ((Invoke-WorkflowFixture record-workflow-waiver e2e).Status -eq 0) "$hostName explicit E2E omission needs no E2E receipt"
        $checked = Invoke-WorkflowFixture check-workflow-waiver
        Assert-Waiver ($checked.Status -eq 0 -and $checked.Lines -ccontains 'WAIVED_GATES:e2e') 'selected scope is precise'
        $e2eOnlyGate = Invoke-FixtureGate 'git commit -m approved'
        Assert-Waiver ($e2eOnlyGate.Status -eq 0 -and $e2eOnlyGate.Text.Contains('human-waived steps: e2e')) 'E2E-only commit accurately names the omitted step'
        Assert-Waiver ((Invoke-FixtureReceipt check).Status -eq 2) 'waived E2E is not full certification'
        Write-VerifierFixture verify-app FAIL 1
        Assert-Waiver ((Invoke-WorkflowFixture check-workflow-waiver).Status -eq 2) 'unwaived app failure invalidates decision'

        New-WaiverFixture "extension-all-$hostName" $hostName $true
        foreach ($stem in @('Simplified','Verified (tests/lint/types)','E2E verified')) { Edit-State "- [x] $stem" "- [ ] $stem" }
        Edit-State '| First certified iteration | none |' '| First certified iteration | 1 |'
        Edit-State '| Review iteration | 1 |' '| Review iteration | 5 |'
        Edit-State '## /goal session' "- [x] Plan review loop — FAIL`n## /goal session"
        Remove-Item -LiteralPath (Join-Path $script:project '.forge/local/evidence/e2e.receipt'),(Join-Path $script:project '.forge/local/evidence/verify-app.receipt')
        $before = Get-ShaFile (Join-Path $script:project '.forge/local/state.md')
        Assert-Waiver ((Invoke-WorkflowFixture record-workflow-waiver all).Status -eq 0) 'all remaining development checks can be explicitly omitted'
        Assert-Waiver ((Invoke-WorkflowFixture check-workflow-waiver).Status -eq 0) 'all-scope current candidate validates'
        Assert-Waiver ((Get-ShaFile (Join-Path $script:project '.forge/local/state.md')) -ceq $before) 'all omissions preserve unchecked state and counters'
        Assert-Waiver ((Invoke-FixtureGate 'git commit --no-edit').Status -eq 0) 'all omissions clear checklist, plan and convergence'
        & git -C $script:project commit --no-edit | Out-Null
        Assert-Waiver ($LASTEXITCODE -eq 0) 'normal merge commit succeeds'
        Assert-Waiver ((Invoke-FixtureGate 'git push origin fix/review-waiver').Status -eq 0) 'exact committed candidate reaches push'
        Assert-Waiver ((Invoke-FixtureReceipt check).Status -eq 2) 'all omissions never manufacture full certification'
        Assert-Waiver ((Invoke-FixtureGate 'git commit -n -m another').Status -eq 2) 'all omissions retain normal repository hooks'
        Write-Fixture 'app.txt' "later development`n"
        Assert-Waiver ((Invoke-WorkflowFixture check-workflow-waiver).Status -eq 2) 'subsequent development invalidates exemption'
    }
    foreach ($scopes in @('', 'unknown', 'e2e,e2e', 'all,e2e', 'e2e,')) {
        New-WaiverFixture ('extension-invalid-' + [Guid]::NewGuid().ToString('N'))
        Assert-Waiver ((Invoke-WorkflowFixture record-workflow-waiver $scopes).Status -eq 2) 'invalid or absent explicit scopes fail'
    }
    foreach ($guard in @('convergence','plan-review')) {
        New-WaiverFixture "narrow-$guard"
        if ($guard -ceq 'convergence') {
            Edit-State '| First certified iteration | none |' '| First certified iteration | 1 |'
            Edit-State '| Review iteration | 1 |' '| Review iteration | 5 |'
        } else { Edit-State '## /goal session' "- [x] Plan review loop — FAIL`n## /goal session" }
        Assert-Waiver ((Invoke-WorkflowFixture record-workflow-waiver 'review,e2e').Status -eq 0) 'narrower actual decision records without self-adjudicating other gates'
        Assert-Waiver ((Invoke-FixtureGate 'git commit -m approved').Status -eq 2) "unwaived $guard stays enforced"
        Assert-Waiver ((Invoke-WorkflowFixture record-workflow-waiver "review,e2e,$guard").Status -eq 0) "developer may explicitly omit $guard"
        Assert-Waiver ((Invoke-FixtureGate 'git commit -m approved').Status -eq 0) "only named $guard exemption releases that gate"
    }
    New-WaiverFixture extension-selected
    Remove-Item -LiteralPath (Join-Path $script:project '.forge/local/evidence/e2e.receipt')
    Assert-Waiver ((Invoke-WorkflowFixture record-workflow-waiver 'review,e2e').Status -eq 0) 'selected omissions still need app evidence'
    Edit-State '- [x] Simplified' '- [ ] Simplified'
    Assert-Waiver ((Invoke-FixtureGate 'git commit -m approved').Status -eq 2) 'unrequested simplification stays required'
    Assert-Waiver ((Invoke-WorkflowFixture record-workflow-waiver 'review,e2e,simplification').Status -eq 0) 'developer may explicitly add simplification'
    Assert-Waiver ((Invoke-FixtureGate 'git commit -m approved').Status -eq 0) 'explicit added omission releases its gate'

    New-WaiverFixture extension-stop
    foreach ($n in 1..4) { Write-Fixture "extra$n.txt" "completed development`n" }
    & git -C $script:project add -A
    & git -C $script:project commit -qm 'completed development across five files'
    Freeze-Fixture
    $stopPath = Join-Path $repo 'hooks/check-state-updated.ps1'
    Assert-Waiver ((Invoke-FixtureGate '' $stopPath).Status -eq 0) 'missing changelog does not block conversational Stop'
    Assert-Waiver ((Invoke-WorkflowFixture record-workflow-waiver all).Status -eq 0) 'all-scope records current completed multi-file change'
    Assert-Waiver ((Invoke-FixtureGate '' $stopPath).Status -eq 0) 'explicit changelog omission permits Stop'
    $stopped = Invoke-FixtureGate '' $stopPath
    Assert-Waiver ($stopped.Status -eq 0 -and -not $stopped.Text.Contains('FORGE_FINAL_EVIDENCE_STALE')) 'explicit continuation omission stops without stale-evidence loop'

    foreach ($specification in @('verify-app:unit-tests','e2e:ui-qa')) {
        $kind, $omission = $specification.Split(':')
        New-WaiverFixture "focused-$kind"
        Write-CleanReviewFixture code-spec; Write-CleanReviewFixture code-quality
        Edit-State '- [ ] Code review loop' '- [x] Code review loop'
        Write-Fixture ".forge/local/evidence/$kind.report" "VERDICT: PASS`nRemaining checks executed successfully in this controlled fixture.`nHUMAN_WAIVED_CHECKS: $omission`n"
        Push-Location $script:project
        try {
            $partial = Invoke-VerificationReceipt -ReceiptMode write -ReceiptKind $kind -CandidatePath '.forge/local/evidence/candidate.receipt' -CommandText 'controlled remaining checks' -ProfileName focused -ReportPath ".forge/local/evidence/$kind.report" -ReceiptResult PASS -ReceiptExitStatus 0 -OutputPath ".forge/local/evidence/$kind.receipt"
        } finally { Pop-Location }
        Assert-Waiver ($partial.Status -eq 0) 'remaining subset report can be recorded truthfully'
        Assert-Waiver ((Invoke-WorkflowFixture record-workflow-waiver $specification).Status -eq 0) 'developer can omit a named subcheck'
        Assert-Waiver ((Invoke-WorkflowFixture check-workflow-waiver).Status -eq 0) 'remaining aggregate still needs its actual scoped report'
        Assert-Waiver ((Invoke-FixtureGate 'git commit -m approved').Status -eq 0) 'only requested subcheck is waived'
        Assert-Waiver ((Invoke-FixtureReceipt check).Status -eq 2) 'subset PASS is never full certification'
        Write-Fixture ".forge/local/evidence/$kind.report" "VERDICT: PASS`nchanged report`nHUMAN_WAIVED_CHECKS: wrong-check`n"
        Assert-Waiver ((Invoke-WorkflowFixture check-workflow-waiver).Status -eq 2) 'unrequested omission or changed report cannot pass'
    }
    New-WaiverFixture extension-evidence
    Assert-Waiver ((Invoke-WorkflowFixture record-workflow-waiver all).Status -eq 0) 'evidence fixture records explicit decision'
    $built = Invoke-FixtureGate '' (Join-Path $repo 'hooks/build-evidence.ps1') @('-Diagnostic')
    Assert-Waiver ($built.Status -eq 0 -and $built.Text.Contains('"workflow_waiver":{"valid":true')) 'Goal evidence separately records human decision'
    Assert-Waiver ($built.Text.Contains('"unwaived_evidence_ready":true') -and $built.Text.Contains('"all_receipts_same_candidate":false')) 'Goal waiver readiness never fabricates full certification'

}
finally { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "test-human-review-waiver.ps1: $script:passes passed, $script:failures failed"
if ($script:failures -gt 0) { exit 1 }
exit 0
