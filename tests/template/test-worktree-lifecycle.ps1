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
    [IO.File]::WriteAllText($Path, "<!-- forge:state-schema v6 -->`n## Workflow`n| Field | Value |`n| Command | $Command |`n| Phase | fixture |`n| Next step | fixture |`n## /goal session`nnone`n## PR authorization`nnone`n## State`n### Done (recent 2-3 only)`n- $Done`n### Now`n- $Now`n### Next`n- $Next`n### Deferred`n- deferred`n## Open Questions`n- question`n## Blockers`n- blocker`n## Update Rules`nfixture`n")
}
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
    Copy-Item (Join-Path $RepoRoot 'state.template.md') (Join-Path $Primary '.forge\state.template.md')
    [IO.File]::WriteAllText((Join-Path $Primary '.forge\version'), "6`n")
    [IO.File]::WriteAllText((Join-Path $Primary '.forge\instructions.md'), "policy`n")
    [IO.File]::WriteAllText((Join-Path $Primary '.forge\installed-files.tsv'), ".forge/state.template.md`tfixture`tv6`n.forge/instructions.md`tfixture`tv6`nowned.txt`tfixture`tv6`n")
    Write-State (Join-Path $Primary '.forge\local\state.md') '/fix-bug prior' 'done-primary' 'now-primary' 'next-primary'
    Push-Location $Primary
    & powershell.exe -NoProfile -File $Helper -Action Create -Kind fix -Name bug-one -Base HEAD | Out-Null
    Pop-Location
    Check ((& git -C $Target branch --show-current) -eq 'fix/bug-one') 'exact fix branch'
    Check (Test-Path (Join-Path $Target '.forge\instructions.md')) 'private harness copied'
    Check (Test-Path (Join-Path $Target '.forge\version')) 'generated v6 stamp copied'
    Check (Test-Path (Join-Path $Target '.forge\installed-files.tsv')) 'generated ledger copied'
    Check ((Get-Content (Join-Path $Target 'owned.txt') -Raw).Trim() -eq 'tracked-owned') 'existing worktree file not overwritten'
    Check ((Get-Content (Join-Path $Target '.forge\local\state.md') -Raw) -notmatch 'now-primary') 'Now cleared'
    Check ((Get-Content (Join-Path $Target '.forge\local\state.md') -Raw) -match [regex]::Escape("| Worktree root | $Target |")) 'worktree identity bound'
    Check ((Get-Content (Join-Path $Target '.forge\local\state.md') -Raw) -match [regex]::Escape("| Workflow base SHA | $baseSha |")) 'base SHA frozen'

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

    Write-State (Join-Path $Target '.forge\local\state.md') '/fix-bug bug-one' 'done-worktree' 'active' 'next-worktree'
    & powershell.exe -NoProfile -File $Helper -Action Fold -Worktree $Target | Out-Null
    $folded = Get-Content (Join-Path $Primary '.forge\local\state.md') -Raw
    Check ($folded -match 'done-worktree') 'folded narrative reaches primary'
    Check ($folded -match '\| Command \| /fix-bug prior \|') 'primary workflow authority preserved'

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
    Remove-Item -LiteralPath $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "test-worktree-lifecycle.ps1: $Pass passed, $Fail failed"
if ($Fail -gt 0) { exit 1 }
