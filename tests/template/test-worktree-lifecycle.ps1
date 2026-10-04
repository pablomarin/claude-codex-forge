# Behavioral Windows PowerShell 5.1 parity for v6 worktree lifecycle.
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Helper = Join-Path $RepoRoot 'hooks\lib\worktree-lifecycle.ps1'
$SessionStart = Join-Path $RepoRoot 'hooks\session-start.ps1'
$Scratch = Join-Path ([IO.Path]::GetTempPath()) ('forge-lifecycle-' + [Guid]::NewGuid().ToString('N'))
$Primary = Join-Path $Scratch 'project'
$Target = Join-Path $Primary '.worktrees\bug-one'
$Pass = 0; $Fail = 0
function Check([bool]$Condition, [string]$Message) { if ($Condition) { $script:Pass++; Write-Host "  PASS $Message" } else { $script:Fail++; Write-Error "FAIL $Message" -ErrorAction Continue } }
function Write-State([string]$Path, [string]$Command, [string]$Done, [string]$Now, [string]$Next) {
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    $nowLine = if ($Now) { "- $Now`n" } else { '' }
    [IO.File]::WriteAllText($Path, "<!-- forge:state-schema v6 -->`n## Workflow`n| Field | Value |`n| Command | $Command |`n| Phase | fixture |`n| Next step | fixture |`n## /goal session`nnone`n## PR authorization`nnone`n## State`n### Done (recent 2-3 only)`n- $Done`n### Now`n$nowLine### Next`n- $Next`n### Deferred`n- deferred`n## Open Questions`n- question`n## Blockers`n- blocker`n## Update Rules`nfixture`n")
}
function Edit-Lines([string]$Path, [scriptblock]$Map) {
    $out = New-Object Collections.Generic.List[string]
    foreach ($line in [IO.File]::ReadAllLines($Path)) { foreach ($mapped in @(& $Map $line)) { $out.Add([string]$mapped) } }
    [IO.File]::WriteAllText($Path, (($out -join "`n") + "`n"))
}
function Invoke-Fold([string]$Worktree) {
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = (& powershell.exe -NoProfile -File $Helper -Action Fold -Worktree $Worktree *>&1 | Out-String)
        return @{ Rc = $LASTEXITCODE; Output = $output }
    } finally { $ErrorActionPreference = $previous }
}
function Get-StateHash([string]$Path) { return (Get-FileHash -Algorithm SHA256 $Path).Hash }
try {
    $null = New-Item -ItemType Directory -Path $Primary -Force
    & git -C $Primary init -q --initial-branch=main
    & git -C $Primary config user.email t@t; & git -C $Primary config user.name t
    [IO.File]::WriteAllText((Join-Path $Primary 'app.txt'), "tracked`n")
    [IO.File]::WriteAllText((Join-Path $Primary 'owned.txt'), "tracked-owned`n")
    & git -C $Primary add app.txt owned.txt; & git -C $Primary commit -q -m base
    $baseSha = (& git -C $Primary rev-parse HEAD).Trim()
    [IO.File]::WriteAllText((Join-Path $Primary 'owned.txt'), "primary-local-change`n")
    $null = New-Item -ItemType Directory -Path (Join-Path $Primary '.forge\local') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $Primary '.claude') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $Primary '.codex') -Force
    Copy-Item (Join-Path $RepoRoot 'state.template.md') (Join-Path $Primary '.forge\state.template.md')
    [IO.File]::WriteAllText((Join-Path $Primary '.forge\version'), "6`n")
    [IO.File]::WriteAllText((Join-Path $Primary '.forge\instructions.md'), "policy`n")
    [IO.File]::WriteAllText((Join-Path $Primary '.claude\settings.json'), "claude settings`n")
    [IO.File]::WriteAllText((Join-Path $Primary '.codex\config.toml'), "codex config`n")
    [IO.File]::WriteAllText((Join-Path $Primary '.codex\hooks.json'), "codex hooks stay primary`n")
    [IO.File]::WriteAllText((Join-Path $Primary '.forge\installed-files.tsv'), ".forge/state.template.md`tfixture`tv6`n.forge/instructions.md`tfixture`tv6`nowned.txt`tfixture`tv6`n")
    Write-State (Join-Path $Primary '.forge\local\state.md') '/fix-bug prior' 'done-primary' 'now-primary' 'next-primary'
    $hookDir = Join-Path $Primary '.git\hooks'
    $hookLog = (Join-Path $Scratch 'post-checkout.log').Replace('\', '/')
    $null = New-Item -ItemType Directory -Path $hookDir -Force
    [IO.File]::WriteAllText((Join-Path $hookDir 'post-checkout'), "#!/bin/sh`nprintf 'post-checkout-ran\n' >> '$hookLog'`nexit 1`n")
    Push-Location $Primary
    & powershell.exe -NoProfile -File $Helper -Action Create -Kind fix -Name bug-one -Base HEAD | Out-Null
    Pop-Location
    Check (-not (Test-Path (Join-Path $Scratch 'post-checkout.log'))) 'canonical worktree creation does not execute post-checkout hooks'
    Check ((& git -C $Target branch --show-current) -eq 'fix/bug-one') 'exact fix branch'
    Check (Test-Path (Join-Path $Target '.forge\instructions.md')) 'private harness copied'
    Check (Test-Path (Join-Path $Target '.forge\version')) 'generated v6 stamp copied'
    Check (Test-Path (Join-Path $Target '.forge\installed-files.tsv')) 'generated ledger copied'
    Check (Test-Path (Join-Path $Target '.claude\settings.json')) 'merge-owned Claude host adapter copied outside canonical ledger'
    Check (Test-Path (Join-Path $Target '.codex\config.toml')) 'merge-owned Codex config copied outside canonical ledger'
    Check (Test-Path (Join-Path $Target '.codex\hooks.json')) 'Codex hook validation mirror is copied outside canonical ledger'
    Check ((Get-Content (Join-Path $Target 'owned.txt') -Raw).Trim() -eq 'tracked-owned') 'existing worktree file not overwritten'
    Check ((Get-Content (Join-Path $Target '.forge\local\state.md') -Raw) -notmatch 'now-primary') 'Now cleared'
    Check ((Get-Content (Join-Path $Target '.forge\local\state.md') -Raw) -match [regex]::Escape("| Worktree root | $Target |")) 'worktree identity bound'
    Check ((Get-Content (Join-Path $Target '.forge\local\state.md') -Raw) -match [regex]::Escape("| Workflow base SHA | $baseSha |")) 'base SHA frozen'

    $nativeTarget = Join-Path $Primary '.claude\worktrees\native-feature'
    & git -C $Primary worktree add -q -b claude/native-feature $nativeTarget $baseSha
    & git -C $Primary config branch.claude/native-feature.description 'host-native metadata'
    $nativeConfigHash = (Get-FileHash -Algorithm SHA256 (Join-Path $Primary '.git\config')).Hash
    & powershell.exe -NoProfile -File $Helper -Action Adopt -Kind feat -Name native-feature -Base main -Worktree $nativeTarget | Out-Null
    Check ($LASTEXITCODE -eq 0) 'clean native worktree adoption succeeds'
    Check ((& git -C $nativeTarget branch --show-current) -eq 'feat/native-feature') 'native host prefix is normalized to feat/<slug>'
    Check (Test-Path (Join-Path $nativeTarget '.forge\local\.state-seed-snapshot.md')) 'native adoption seeds the fold baseline'
    Check ((Get-Content (Join-Path $nativeTarget '.forge\local\state.md') -Raw) -match [regex]::Escape("| Workflow base SHA | $baseSha |")) 'native adoption freezes the verified base SHA'
    Check ((Get-FileHash -Algorithm SHA256 (Join-Path $Primary '.git\config')).Hash -eq $nativeConfigHash) 'native adoption never writes shared Git config'

    $dirtyTarget = Join-Path $Primary '.claude\worktrees\dirty-feature'
    & git -C $Primary worktree add -q -b claude/dirty-feature $dirtyTarget $baseSha
    [IO.File]::AppendAllText((Join-Path $dirtyTarget 'app.txt'), "dirty`n")
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $dirtyOutput = (& powershell.exe -NoProfile -File $Helper -Action Adopt -Kind feat -Name dirty-feature -Base main -Worktree $dirtyTarget *>&1 | Out-String)
        $dirtyRc = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    Check ($dirtyRc -ne 0) 'dirty native worktree adoption exits nonzero'
    Check ($dirtyOutput -match 'ADOPT_BLOCKED: native worktree must be clean') 'dirty native worktree adoption explains the safe stop'
    Check ((& git -C $dirtyTarget branch --show-current) -eq 'claude/dirty-feature') 'dirty native branch is not renamed'

    $truncatedState = Join-Path $Scratch 'truncated-state.md'
    [IO.File]::WriteAllText($truncatedState, "<!-- forge:state-schema v6 -->`n## Workflow`n| Field | Value |`n| Command | /fix-bug truncated |`n")
    Copy-Item -LiteralPath $truncatedState -Destination (Join-Path $Target '.forge\local\state.md') -Force
    Push-Location $Target
    $truncatedOutput = ('{"source":"compact","cwd":"' + $Target.Replace('\','\\') + '"}' | & powershell.exe -NoProfile -File $SessionStart) -join "`n"
    Pop-Location
    Check ($truncatedOutput -match 'FORGE_STATE_INVALID') 'active workflow without phase and next step is invalid for resume'
    [IO.File]::WriteAllText((Join-Path $Target '.forge\local\state.md'), "<!-- forge:state-schema v6 -->`n## Workflow`n| Field | Value |`n| Command | none |`n")
    Push-Location $Target
    $inactiveOutput = ('{"source":"compact","cwd":"' + $Target.Replace('\','\\') + '"}' | & powershell.exe -NoProfile -File $SessionStart) -join "`n"
    Pop-Location
    Check ($inactiveOutput -notmatch 'FORGE_STATE_INVALID') 'explicit inactive command-only state remains valid'

    Write-State (Join-Path $Target '.forge\local\state.md') '/fix-bug bug-one' 'done-worktree' 'active' 'next-worktree'
    $malformedPath = Join-Path $Target '.forge\local\state.md'
    $malformed = [IO.File]::ReadAllText($malformedPath).Replace("### Now`n", "### Done (duplicate)`n- duplicate`n### Now`n")
    [IO.File]::WriteAllText($malformedPath, $malformed)
    $primaryHash = (Get-FileHash -Algorithm SHA256 (Join-Path $Primary '.forge\local\state.md')).Hash
    try { & powershell.exe -NoProfile -File $Helper -Action Fold -Worktree $Target | Out-Null; $duplicateRc = $LASTEXITCODE } catch { $duplicateRc = 1 }
    Check ($duplicateRc -ne 0) 'duplicate narrative heading exits nonzero'
    Check ((Get-FileHash -Algorithm SHA256 (Join-Path $Primary '.forge\local\state.md')).Hash -eq $primaryHash) 'duplicate narrative heading leaves primary bytes unchanged'

    $primaryState = Join-Path $Primary '.forge\local\state.md'
    Write-State (Join-Path $Target '.forge\local\state.md') '/fix-bug bug-one' 'done-worktree' 'active' 'next-worktree'
    $primaryHash = Get-StateHash $primaryState
    $nowFold = Invoke-Fold $Target
    Check ($nowFold.Rc -ne 0) 'non-empty worktree Now exits nonzero'
    Check ($nowFold.Output -match 'FOLD_SAFE_STOP: worktree ### Now still lists work') 'non-empty worktree Now explains how to record the status first'
    Check ((Get-StateHash $primaryState) -eq $primaryHash) 'non-empty worktree Now leaves primary bytes unchanged'

    Write-State (Join-Path $Target '.forge\local\state.md') '/fix-bug bug-one' 'done-worktree' '' 'next-worktree'
    $replaceFold = Invoke-Fold $Target
    Check ($replaceFold.Rc -eq 0) 'unchanged primary narrative folds successfully'
    Check ($replaceFold.Output -match 'mode=replace') 'unchanged primary uses the exact replace path'
    $folded = Get-Content $primaryState -Raw
    Check ($folded -match 'done-worktree') 'folded narrative reaches primary'
    Check ($folded -notmatch 'now-primary') 'fold clears primary Now'
    Check ($folded -match '\| Command \| /fix-bug prior \|') 'primary workflow authority preserved'

    Write-State (Join-Path $Target '.forge\local\state.md') '/fix-bug bug-one' 'done-second' '' 'next-worktree'
    Write-State $primaryState '/fix-bug prior' 'independent-main' 'main-active' 'next-main-only'
    $mergeFold = Invoke-Fold $Target
    Check ($mergeFold.Rc -eq 0) 'diverged primary narrative folds by merge'
    Check ($mergeFold.Output -match 'mode=merge') 'diverged primary uses the three-way merge path'
    $merged = Get-Content $primaryState -Raw
    Check ($merged -match 'done-second') 'worktree Done edit reaches primary'
    Check ($merged -match 'independent-main') 'independent primary Done edit survives'
    Check ($merged -match 'next-main-only') 'independent primary Next edit survives'
    Check ($merged -notmatch 'done-worktree') 'line removed by the worktree stays removed'
    Check ($merged -match '\| Command \| /fix-bug prior \|') 'merge leaves primary workflow authority untouched'

    $parPrimary = Join-Path $Scratch 'parallel-project'
    $null = New-Item -ItemType Directory -Path $parPrimary -Force
    & git -C $parPrimary init -q --initial-branch=main
    & git -C $parPrimary config user.email t@t; & git -C $parPrimary config user.name t
    [IO.File]::WriteAllText((Join-Path $parPrimary 'app.txt'), "tracked`n")
    & git -C $parPrimary add app.txt; & git -C $parPrimary commit -q -m base
    $null = New-Item -ItemType Directory -Path (Join-Path $parPrimary '.forge\local') -Force
    Copy-Item (Join-Path $RepoRoot 'state.template.md') (Join-Path $parPrimary '.forge\state.template.md')
    [IO.File]::WriteAllText((Join-Path $parPrimary '.forge\version'), "6`n")
    [IO.File]::WriteAllText((Join-Path $parPrimary '.forge\installed-files.tsv'), ".forge/state.template.md`tfixture`tv6`n")
    [IO.File]::AppendAllText((Join-Path $parPrimary '.git\info\exclude'), ".forge/`n.worktrees/`n")
    $parState = Join-Path $parPrimary '.forge\local\state.md'
    Copy-Item (Join-Path $RepoRoot 'state.template.md') $parState
    Edit-Lines $parState { param($l) switch -Exact ($l) {
        '- (your most recent completed work)' { '- shipped login' }
        "- (what's queued)" { '- build auth', '- build billing', '- polish docs' }
        '- (questions needing resolution)' { '- which auth provider?', '- billing currency?' }
        default { $l } } }
    Push-Location $parPrimary
    & powershell.exe -NoProfile -File $Helper -Action Create -Kind feat -Name auth -Base HEAD | Out-Null
    & powershell.exe -NoProfile -File $Helper -Action Create -Kind feat -Name billing -Base HEAD | Out-Null
    Pop-Location
    $authTarget = Join-Path $parPrimary '.worktrees\auth'
    $billingTarget = Join-Path $parPrimary '.worktrees\billing'
    $authState = Join-Path $authTarget '.forge\local\state.md'
    $billingState = Join-Path $billingTarget '.forge\local\state.md'
    Check (Test-Path $authState) 'first parallel worktree is seeded'
    Check (Test-Path $billingState) 'second parallel worktree is seeded'
    Edit-Lines $parState { param($l) if ($l -eq '- polish docs') { $l, '- main hotfix follow-up' } else { $l } }
    Edit-Lines $authState { param($l) switch -Exact ($l) {
        '- shipped login' { '- shipped auth (PR 12)', $l }
        '- build auth' { }
        '- which auth provider?' { }
        '- (parked items with reason)' { '- auth: rotate signing keys later' }
        '### Now' { $l, '', '- finishing auth' }
        default { $l } } }
    Edit-Lines $billingState { param($l) switch -Exact ($l) {
        '- shipped login' { '- shipped billing (PR 13)', $l }
        '- build billing' { }
        '- polish docs' { $l, '- billing: add invoices' }
        default { $l } } }

    $parBefore = Get-StateHash $parState
    $authNow = Invoke-Fold $authTarget
    Check ($authNow.Rc -ne 0) 'auth fold stops while Now still lists work'
    Check ((Get-StateHash $parState) -eq $parBefore) 'stopped fold leaves primary bytes unchanged'
    Edit-Lines $authState { param($l) if ($l -ne '- finishing auth') { $l } }
    $authFold = Invoke-Fold $authTarget
    Check ($authFold.Rc -eq 0) 'first parallel fold succeeds after main changed'
    Check ($authFold.Output -match 'mode=merge') 'first parallel fold merges around the main edit'
    $authFolded = Get-StateHash $parState
    $authRetry = Invoke-Fold $authTarget
    Check ($authRetry.Rc -eq 0) 'retrying a completed fold succeeds'
    Check ((Get-StateHash $parState) -eq $authFolded) 'retrying a completed fold is idempotent'
    $billingFold = Invoke-Fold $billingTarget
    Check ($billingFold.Rc -eq 0) 'second parallel fold succeeds after its sibling folded'
    Check ($billingFold.Output -match 'mode=merge') 'second parallel fold merges with its sibling'
    $expectedNarrative = "## State`n`n### Done (recent 2-3 only)`n`n- shipped billing (PR 13)`n- shipped auth (PR 12)`n- shipped login`n`n### Now`n`n### Next`n`n- polish docs`n- billing: add invoices`n- main hotfix follow-up`n`n### Deferred`n`n- auth: rotate signing keys later`n`n---`n`n## Open Questions`n`n- billing currency?`n`n## Blockers`n`n- (anything blocking forward progress)`n`n---`n`n"
    $parText = [IO.File]::ReadAllText($parState)
    $narrativeStart = [regex]::Match($parText, '(?m)^## State\n').Index
    $narrativeEnd = [regex]::Match($parText, '(?m)^## Update Rules$').Index
    $actualNarrative = $parText.Substring($narrativeStart, $narrativeEnd - $narrativeStart)
    Check ($actualNarrative -ceq $expectedNarrative) 'primary narrative holds both finished statuses and the main edit, in order'
    if ($actualNarrative -cne $expectedNarrative) { Write-Host $actualNarrative }
    Check ($parText -match '\| Command   \| none  \|') 'parallel folds leave primary workflow control untouched'

    $sourcePrimary = Join-Path $Scratch 'source-project'
    $sourceTarget = Join-Path $sourcePrimary '.worktrees\source-bug'
    $null = New-Item -ItemType Directory -Path (Join-Path $sourcePrimary 'manifests') -Force
    Copy-Item (Join-Path $RepoRoot 'state.template.md') (Join-Path $sourcePrimary 'state.template.md')
    [IO.File]::WriteAllText((Join-Path $sourcePrimary 'manifests\managed-v6.tsv'), "state.template.md`tsource`tv6`n")
    [IO.File]::WriteAllText((Join-Path $sourcePrimary 'app.txt'), "source`n")
    & git -C $sourcePrimary init -q --initial-branch=main
    & git -C $sourcePrimary config user.email t@t; & git -C $sourcePrimary config user.name t
    & git -C $sourcePrimary add app.txt state.template.md manifests/managed-v6.tsv
    & git -C $sourcePrimary commit -q -m base
    Write-State (Join-Path $sourcePrimary '.forge\local\state.md') '/fix-bug prior' 'source-done' 'source-now' 'source-next'
    Push-Location $sourcePrimary
    & powershell.exe -NoProfile -File $Helper -Action Create -Kind fix -Name source-bug -Base HEAD | Out-Null
    Pop-Location
    Check ((& git -C $sourceTarget branch --show-current) -eq 'fix/source-bug') 'source checkout creates exact fix branch without installed ledger'
    Check (Test-Path (Join-Path $sourceTarget '.forge\local\state.md')) 'source checkout uses root state template'
    Check ((Get-Content (Join-Path $sourceTarget '.forge\local\state.md') -Raw) -match 'source-done') 'source checkout carries continuity narrative'
} finally {
    if (Test-Path $Primary) { & git -C $Primary worktree remove --force $Target 2>$null | Out-Null }
    if ($parPrimary -and (Test-Path $parPrimary)) {
        foreach ($name in @('auth', 'billing')) { & git -C $parPrimary worktree remove --force (Join-Path $parPrimary ".worktrees\$name") 2>$null | Out-Null }
    }
    Remove-Item -LiteralPath $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "test-worktree-lifecycle.ps1: $Pass passed, $Fail failed"
if ($Fail -gt 0) { exit 1 }
