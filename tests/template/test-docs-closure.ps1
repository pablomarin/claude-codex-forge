# Native Windows/portable PS7 receipt fixtures; these do not claim live-host qualification.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('forge-docs-closure-' + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
$script:passes = 0; $script:failures = 0
. (Join-Path $repo 'hooks\lib\verification-receipt.ps1')
function Assert-Closure([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:passes++; Write-Host "PASS $Message" }
    else { $script:failures++; Write-Host "FAIL $Message" }
}
function Write-Fixture([string]$Relative, [string]$Text) { [IO.File]::WriteAllText((Join-Path $script:project $Relative), $Text, $utf8) }
function Invoke-FixtureReceipt([string]$Action) {
    Push-Location $script:project
    try {
        if ($Action -ceq 'close-docs') {
            return Invoke-VerificationReceipt -ReceiptMode close-docs -StatePath '.forge/local/state.md' -PreviousCandidatePath '.forge/local/evidence/original.receipt'
        }
        return Invoke-VerificationReceipt -ReceiptMode check -StatePath '.forge/local/state.md'
    }
    catch { return [pscustomobject]@{ Status = 2; Error = $_.Exception.Message; Lines = @() } }
    finally { Pop-Location }
}
function Freeze-Fixture {
    Push-Location $script:project
    try {
        & (Join-Path $repo 'hooks\lib\candidate-fingerprint.ps1') -Mode freeze -Artifact 'git:working-tree' -WorkflowBaseSha $script:base -WorkflowBaseRef main -Output (Join-Path $script:project '.forge/local/evidence/candidate.receipt') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'fixture candidate capture failed' }
    }
    finally { Pop-Location }
}
function Write-ReviewFixture([string]$Role, [string]$MainHost, [string]$Other, [bool]$Fallback) {
    $candidateFile = Join-Path $script:project '.forge/local/evidence/candidate.receipt'
    $reportFile = Join-Path $script:project ".forge/local/reviews/$Role.report"
    Write-Fixture ".forge/local/reviews/$Role.report" "schema_version=1`nverdict=CLEAN`nmax_severity=NONE`nblocked_class=none`n"
    $actual = if ($Fallback) { $MainHost } else { $Other }
    $reason = if ($Fallback) { 'preferred-engine-unavailable' } else { 'none' }
    $body = @(
        'schema_version=1', "invocation_id=$Role-$MainHost-$Fallback", "timestamp=$([DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))",
        "main_host=$MainHost", "requested_engine=$Other", "actual_engine=$actual", "fallback=$($Fallback.ToString().ToLowerInvariant())", "fallback_reason=$reason",
        "role=$Role", 'profile=review', 'review_iteration=1', 'fresh_process=true', 'artifact_kind=git-working-tree',
        "artifact_hash=$(Get-Kv $candidateFile 'candidate_id')", "worktree_identity=$(Get-Kv $candidateFile 'worktree_identity')",
        "git_head=$(Get-Kv $candidateFile 'git_head')", "workflow_base_sha=$script:base", "output_path=$reportFile", "output_hash=$(Get-ShaFile $reportFile)",
        'process_exit_status=0', 'semantic_verdict=CLEAN', 'max_severity=NONE', "findings_digest=$(Get-ShaText '')", 'result_schema_version=1', 'blocked_class=none'
    )
    Write-Fixture ".forge/local/reviews/$Role.receipt" (($body -join "`n") + "`n")
}
function New-ClosureFixture([string]$Name, [string]$MainHost = 'claude', [bool]$Fallback = $false, [string]$Scope = 'docs/guide.md', [string]$PolicyMode = 'installed') {
    $script:project = Join-Path $scratch $Name
    foreach ($relative in @('.forge/local/evidence','.forge/local/reviews','docs/plans')) { [IO.Directory]::CreateDirectory((Join-Path $script:project $relative)) | Out-Null }
    & git -C $script:project init -q --initial-branch=main
    $script:project = (Resolve-Path ([string](& git -C $script:project rev-parse --show-toplevel))).Path
    & git -C $script:project config user.name ForgeTest
    & git -C $script:project config user.email forge-test@example.invalid
    Write-Fixture '.gitignore' ".forge/local/`n"
    $scopeText = "# forge:non-runtime-prose v1`nprose`tdocs/guide.md`nprose`tdocs/CHANGELOG.md`n"
    if ($Scope -cne 'docs/guide.md') { $scopeText += "prose`t$Scope`n" }
    Write-Fixture '.forge/verification-scope.tsv' $scopeText
    if ($PolicyMode -ceq 'source') {
        [IO.Directory]::CreateDirectory((Join-Path $script:project 'manifests')) | Out-Null
        Move-Item (Join-Path $script:project '.forge/verification-scope.tsv') (Join-Path $script:project 'manifests/verification-scope.tsv')
        foreach ($marker in @('FORGE.template.md','state.template.md','manifests/managed-v6.tsv')) { Write-Fixture $marker "source marker`n" }
    }
    elseif ($PolicyMode -ceq 'missing') { Remove-Item (Join-Path $script:project '.forge/verification-scope.tsv') }
    Write-Fixture 'app.txt' "base app`n"
    Write-Fixture 'docs/guide.md' "# Guide`nOriginal prose.`n"
    Write-Fixture 'docs/CHANGELOG.md' "# Changes`n`n## [1.2.3] - 2026-10-22`n`n- Original prose.`n"
    Write-Fixture 'docs/config.md' "# Configuration`n"
    Write-Fixture 'CONTRIBUTING.md' "Agent instructions`n"
    Write-Fixture 'docs/plans/task.md' "Plan requirements`n"
    Write-Fixture 'docs/guide.mdx' "<Component />`n"
    & git -C $script:project add -A; & git -C $script:project commit -qm base
    $script:base = ([string](& git -C $script:project rev-parse HEAD)).Trim()
    $commonRaw = ([string](& git -C $script:project rev-parse --git-common-dir)).Trim()
    $common = if ([IO.Path]::IsPathRooted($commonRaw)) { (Resolve-Path $commonRaw).Path } else { (Resolve-Path (Join-Path $script:project $commonRaw)).Path }
    & git -C $script:project checkout -qb fix/docs-closure
    Write-Fixture '.forge/local/state.md' @"
<!-- forge:state-schema v6 -->
## Identity
| Worktree root | $script:project |
| Git common directory | $common |
| Last active host | $MainHost |
| Workflow base ref | main |
| Workflow base SHA | $script:base |
## Workflow
| Command | /fix-bug docs-closure |
| Phase | review |
| Next step | promote |
### Checklist
- [x] Code review loop (1 iterations) — PASS
- [x] Simplified
- [x] Verified (tests/lint/types)
- [x] E2E verified
## Receipts
| Review iteration | 1 |
| First certified iteration | 1 |
| Candidate receipt | .forge/local/evidence/candidate.receipt |
| Spec review receipt | .forge/local/reviews/code-spec.receipt |
| Quality review receipt | .forge/local/reviews/code-quality.receipt |
| Verify app receipt | .forge/local/evidence/verify-app.receipt |
| E2E receipt | .forge/local/evidence/e2e.receipt |
| Promotion receipt | .forge/local/evidence/promotion.receipt |
"@
    Write-Fixture 'app.txt' "fixed app`n"; & git -C $script:project add app.txt
    Freeze-Fixture
    $other = if ($MainHost -ceq 'claude') { 'codex' } else { 'claude' }
    Write-ReviewFixture code-spec $MainHost $other $Fallback; Write-ReviewFixture code-quality $MainHost $other $Fallback
    Push-Location $script:project
    try {
        foreach ($kind in @('verify-app','e2e')) {
            Write-Fixture ".forge/local/evidence/$kind.report" "VERDICT: PASS`nControlled verifier fixture.`n"
            $result = Invoke-VerificationReceipt -ReceiptMode write -ReceiptKind $kind -CandidatePath '.forge/local/evidence/candidate.receipt' -CommandText "controlled $kind" -ProfileName focused -ReportPath ".forge/local/evidence/$kind.report" -ReceiptResult PASS -ReceiptExitStatus 0 -OutputPath ".forge/local/evidence/$kind.receipt"
            if ($result.Status -ne 0) { throw $result.Error }
        }
    }
    finally { Pop-Location }
    Copy-Item (Join-Path $script:project '.forge/local/evidence/candidate.receipt') (Join-Path $script:project '.forge/local/evidence/original.receipt')
    if ((Invoke-FixtureReceipt check).Status -ne 0) { throw 'original fixture certification failed' }
}
function Edit-ClosureProse {
    [IO.File]::AppendAllText((Join-Path $script:project 'docs/guide.md'), "Corrected narrative.`n", $utf8)
    & git -C $script:project add docs/guide.md
    Freeze-Fixture
}
try {
    foreach ($mainHost in @('claude','codex')) {
        foreach ($fallback in @($false,$true)) {
            New-ClosureFixture "$mainHost-$fallback" $mainHost $fallback
            $appFile = Join-Path $script:project '.forge/local/evidence/verify-app.receipt'
            $specFile = Join-Path $script:project '.forge/local/reviews/code-spec.receipt'
            $appHash = Get-ShaFile $appFile; $specHash = Get-ShaFile $specFile
            Edit-ClosureProse
            Assert-Closure ((Invoke-FixtureReceipt check).Status -eq 2) "$mainHost fallback=$fallback changed candidate requires closure"
            $closed = Invoke-FixtureReceipt close-docs
            Assert-Closure ($closed.Status -eq 0) "$mainHost fallback=$fallback declared prose closes ($($closed.Error))"
            Assert-Closure ((Invoke-FixtureReceipt check).Status -eq 0) "$mainHost fallback=$fallback shared validator accepts exact final candidate"
            $sourceCandidate = Join-Path $script:project '.forge/local/evidence/original.receipt'
            Move-Item $sourceCandidate (Join-Path $scratch 'original.saved')
            Assert-Closure ((Invoke-FixtureReceipt check).Status -eq 0) 'closure archives its original candidate independently of caller scratch'
            Move-Item (Join-Path $scratch 'original.saved') $sourceCandidate
            Assert-Closure ((Get-ShaFile $appFile) -ceq $appHash -and (Get-ShaFile $specFile) -ceq $specHash) 'original receipt bytes and timestamps are preserved'
            Edit-ClosureProse
            Assert-Closure ((Invoke-FixtureReceipt check).Status -eq 2) 'another correction invalidates previous closure'
            Assert-Closure ((Invoke-FixtureReceipt close-docs).Status -eq 0) 'cumulative docs delta closes against original candidate'
            Write-Fixture '.forge/local/evidence/message.txt' "docs closure`n"
            Push-Location $script:project
            try {
                & (Join-Path $repo 'hooks\lib\candidate-fingerprint.ps1') -Mode promote -Candidate '.forge/local/evidence/candidate.receipt' -State '.forge/local/state.md' -MessageFile '.forge/local/evidence/message.txt' -PromotionReceipt '.forge/local/evidence/promotion.receipt' | Out-Null
                Assert-Closure ($LASTEXITCODE -eq 0) 'exact-tree promotion consumes shared closure validator'
            }
            finally { Pop-Location }
            Assert-Closure ((Invoke-FixtureReceipt check).Status -eq 0) 'post-promotion shipping preserves final-tree proof'
        }
    }
    New-ClosureFixture 'source-policy' 'claude' $false 'docs/guide.md' 'source'
    Edit-ClosureProse
    Assert-Closure ((Invoke-FixtureReceipt close-docs).Status -eq 0) 'canonical source markers select source-owned scope policy'
    Assert-Closure ((Invoke-FixtureReceipt check).Status -eq 0) 'source-only scope uses the same shipping validator'
    New-ClosureFixture 'missing-policy' 'claude' $false 'docs/guide.md' 'missing'
    Edit-ClosureProse
    Assert-Closure ((Invoke-FixtureReceipt close-docs).Status -eq 2) 'missing policy never guesses that Markdown is non-runtime'
    New-ClosureFixture 'original-promotion' 
    Write-Fixture '.forge/local/evidence/message.txt' "original promotion`n"
    Push-Location $script:project
    try {
        & (Join-Path $repo 'hooks\lib\candidate-fingerprint.ps1') -Mode promote -Candidate '.forge/local/evidence/candidate.receipt' -State '.forge/local/state.md' -MessageFile '.forge/local/evidence/message.txt' -PromotionReceipt '.forge/local/evidence/promotion.receipt' | Out-Null
        Assert-Closure ($LASTEXITCODE -eq 0) 'original fully certified candidate promotes normally'
    }
    finally { Pop-Location }
    Edit-ClosureProse
    Assert-Closure ((Get-Kv (Join-Path $script:project '.forge/local/evidence/candidate.receipt') 'git_head') -ceq (Get-Kv (Join-Path $script:project '.forge/local/evidence/promotion.receipt') 'new_branch_commit')) 'documentation candidate parent is the proven original promotion commit'
    Assert-Closure ((Invoke-FixtureReceipt close-docs).Status -eq 0) 'proved original promotion permits single parent transition'
    Push-Location $script:project
    try {
        & (Join-Path $repo 'hooks\lib\candidate-fingerprint.ps1') -Mode promote -Candidate '.forge/local/evidence/candidate.receipt' -State '.forge/local/state.md' -MessageFile '.forge/local/evidence/message.txt' -PromotionReceipt '.forge/local/evidence/promotion.receipt' | Out-Null
        Assert-Closure ($LASTEXITCODE -eq 0) 'documentation final candidate promotes after original promotion'
    }
    finally { Pop-Location }
    Assert-Closure ((Invoke-FixtureReceipt check).Status -eq 0) 'archived original promotion survives replacement of active promotion'
    :mutations foreach ($mutation in @('code','unknown-doc','scope-policy','release-heading','plan','instructions','config','mdx','delete','rename','symlink','binary','whitespace','mode','stale-review','report-tamper','receipt-tamper','sidecar-tamper','head','unstaged','untracked')) {
        $scope = switch ($mutation) { plan { 'docs/plans/task.md' } instructions { 'CONTRIBUTING.md' } config { 'docs/config.md' } rename { 'docs/renamed.md' } mdx { 'docs/guide.mdx' } default { 'docs/guide.md' } }
        New-ClosureFixture "reject-$mutation" 'claude' $false $scope
        Edit-ClosureProse
        switch ($mutation) {
            code { Write-Fixture 'app.txt' "changed code`n" }
            unknown-doc { Write-Fixture 'docs/unknown.md' "unknown prose`n" }
            scope-policy { [IO.File]::AppendAllText((Join-Path $script:project '.forge/verification-scope.tsv'), "prose`tdocs/unknown.md`n", $utf8) }
            release-heading { Write-Fixture 'docs/CHANGELOG.md' "# Changes`n`n## [1.2.4] - 2026-10-22`n" }
            plan { Write-Fixture 'docs/plans/task.md' "changed requirements`n" }
            instructions { Write-Fixture 'CONTRIBUTING.md' "changed instructions`n" }
            config { Write-Fixture 'docs/config.md' "changed configuration`n" }
            mdx { Write-Fixture 'docs/guide.mdx' "<Changed />`n" }
            delete { Remove-Item (Join-Path $script:project 'docs/guide.md') }
            rename { & git -C $script:project mv docs/guide.md docs/renamed.md }
            symlink {
                & git -C $script:project config core.symlinks false
                Write-Fixture 'docs/guide.md' '../app.txt'
                $blob = ([string](& git -C $script:project hash-object -w docs/guide.md)).Trim()
                & git -C $script:project update-index --cacheinfo "120000,$blob,docs/guide.md"
            }
            binary { Write-Fixture 'docs/guide.md' (('a' * 9000) + [char]0) }
            whitespace { Write-Fixture 'docs/guide.md' "trailing spaces  `n" }
            mode { & git -C $script:project config core.filemode false; & git -C $script:project update-index --chmod=+x docs/guide.md }
            stale-review { $file = Join-Path $script:project '.forge/local/reviews/code-spec.receipt'; [IO.File]::WriteAllText($file, ([IO.File]::ReadAllText($file) -replace '(?m)^timestamp=.*$', 'timestamp=2000-01-01T00:00:00Z'), $utf8) }
            report-tamper { Write-Fixture '.forge/local/evidence/e2e.report' "VERDICT: PASS`nTampered report`n" }
            receipt-tamper { [IO.File]::AppendAllText((Join-Path $script:project '.forge/local/evidence/verify-app.receipt'), "result=PASS`n", $utf8) }
            sidecar-tamper {
                $null = Invoke-FixtureReceipt close-docs
                [IO.File]::AppendAllText((Join-Path $script:project '.forge/local/evidence/candidate.receipt.docs-closure'), "new_candidate_hash=wrong`n", $utf8)
                Assert-Closure ((Invoke-FixtureReceipt check).Status -eq 2) 'tampered sidecar fails closed'
                continue mutations
            }
            head { & git -C $script:project commit -qm 'unproven direct commit' }
            unstaged { [IO.File]::AppendAllText((Join-Path $script:project 'docs/guide.md'), "unstaged prose`n", $utf8); Assert-Closure ((Invoke-FixtureReceipt close-docs).Status -eq 2) 'unstaged mutation rejects closure'; continue mutations }
            untracked { Write-Fixture 'untracked.txt' "untracked`n"; Assert-Closure ((Invoke-FixtureReceipt close-docs).Status -eq 2) 'untracked mutation rejects closure'; continue mutations }
        }
        if ($mutation -notin @('mode','symlink')) { & git -C $script:project add -A }
        Freeze-Fixture
        Assert-Closure ((Invoke-FixtureReceipt close-docs).Status -eq 2) "$mutation cannot reuse certification"
        Assert-Closure ((Invoke-FixtureReceipt check).Status -eq 2) "$mutation remains blocked at shipping"
    }
    :provenance foreach ($mutation in @('manual-same-tree','missing-promotion','tampered-promotion','archived-promotion','archived-candidate')) {
        New-ClosureFixture "provenance-$mutation"
        if ($mutation -ceq 'manual-same-tree') {
            & git -C $script:project commit -qm 'manual same-tree commit'
            Assert-Closure (([string](& git -C $script:project rev-parse 'HEAD^{tree}')).Trim() -ceq (Get-Kv (Join-Path $script:project '.forge/local/evidence/original.receipt') 'index_tree')) 'manual control has the exact original certified tree'
        }
        else {
            Write-Fixture '.forge/local/evidence/message.txt' "original promotion`n"
            Push-Location $script:project
            try {
                & (Join-Path $repo 'hooks\lib\candidate-fingerprint.ps1') -Mode promote -Candidate '.forge/local/evidence/candidate.receipt' -State '.forge/local/state.md' -MessageFile '.forge/local/evidence/message.txt' -PromotionReceipt '.forge/local/evidence/promotion.receipt' | Out-Null
                Assert-Closure ($LASTEXITCODE -eq 0) 'control starts with an actual exact Forge promotion'
            }
            finally { Pop-Location }
        }
        Edit-ClosureProse
        switch ($mutation) {
            missing-promotion { Remove-Item (Join-Path $script:project '.forge/local/evidence/promotion.receipt') }
            tampered-promotion { [IO.File]::AppendAllText((Join-Path $script:project '.forge/local/evidence/promotion.receipt'), "old_candidate_id=wrong`n", $utf8) }
            { $_ -in @('archived-promotion','archived-candidate') } {
                Assert-Closure ((Invoke-FixtureReceipt close-docs).Status -eq 0) 'valid closure exists before archived evidence mutation'
                $key = if ($mutation -ceq 'archived-promotion') { 'source_promotion_path' } else { 'original_candidate_path' }
                $archive = Get-Kv (Join-Path $script:project '.forge/local/evidence/candidate.receipt.docs-closure') $key
                [IO.File]::AppendAllText($archive, "tampered`n", $utf8)
                Assert-Closure ((Invoke-FixtureReceipt check).Status -eq 2) 'archived provenance is hash checked on every shipping check'
                continue provenance
            }
        }
        Assert-Closure ((Invoke-FixtureReceipt close-docs).Status -eq 2) "$mutation cannot prove the original promotion boundary"
    }
}
finally { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "test-docs-closure.ps1: $script:passes passed, $script:failures failed"
if ($script:failures -gt 0) { exit 1 }
exit 0
