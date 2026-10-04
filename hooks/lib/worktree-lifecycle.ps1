# Deterministic Forge v6 linked-worktree creation, state seeding, and fold-back.
# Windows PowerShell 5.1 compatible.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet("Create", "Adopt", "Seed", "Fold")][string]$Action,
    [ValidateSet("feat", "fix")][string]$Kind,
    [string]$Name,
    [string]$Base,
    [string]$Worktree
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail-ForgeLifecycle([string]$Message) {
    [Console]::Error.WriteLine($Message)
    throw $Message
}

function Get-PhysicalPath([string]$Path) {
    return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
}

function Get-PrimaryWorktree([string]$Root) {
    foreach ($line in @(& git -C $Root worktree list --porcelain 2>$null)) {
        if ($line -like "worktree *") {
            $worktreePath = $line.Substring(9)
            return (Get-PhysicalPath $worktreePath)
        }
    }
    Fail-ForgeLifecycle "FOLD_SAFE_STOP: primary checkout is unavailable"
}

function Get-GitCommon([string]$Root) {
    $common = (& git -C $Root rev-parse --git-common-dir 2>$null | Select-Object -First 1)
    if (-not $common) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: Git common directory is unavailable" }
    if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $Root $common }
    return (Get-PhysicalPath $common)
}

function Resolve-LinkedWorktree([string]$Requested) {
    $target = Get-PhysicalPath $Requested
    $inside = (& git -C $target rev-parse --is-inside-work-tree 2>$null | Select-Object -First 1)
    if ($inside -ne "true") { Fail-ForgeLifecycle "FOLD_SAFE_STOP: not a Git worktree: $target" }
    $primary = Get-PrimaryWorktree $target
    if ((Get-GitCommon $target) -ne (Get-GitCommon $primary)) {
        Fail-ForgeLifecycle "FOLD_SAFE_STOP: worktree belongs to another repository"
    }
    return @($target, $primary)
}

function Test-Reparse([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))
}

function Copy-MissingPrivateSurface([string]$Primary, [string]$Target, [string]$Relative) {
    if (-not $Relative -or [IO.Path]::IsPathRooted($Relative) -or
        (($Relative -split '[\\/]') -contains '..')) {
        Fail-ForgeLifecycle "SEED_BLOCKED: invalid installed path: $Relative"
    }
    $portable = $Relative -replace '/', [IO.Path]::DirectorySeparatorChar
    if ($Relative -eq '.forge/local' -or $Relative.StartsWith('.forge/local/')) { return }
    $source = Join-Path $Primary $portable
    $destination = Join-Path $Target $portable
    if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or (Test-Reparse $source)) { return }
    if (Test-Path -LiteralPath $destination -ErrorAction SilentlyContinue) { return }
    $parent = Split-Path -Parent $destination
    $cursor = $Target
    foreach ($segment in ((Split-Path -Parent $portable) -split '[\\/]')) {
        if (-not $segment -or $segment -eq '.') { continue }
        $cursor = Join-Path $cursor $segment
        if (Test-Reparse $cursor) { Fail-ForgeLifecycle "SEED_BLOCKED: aliased destination ancestor: $cursor" }
    }
    $null = New-Item -ItemType Directory -Path $parent -Force
    Copy-Item -LiteralPath $source -Destination $destination
}

function Test-ForgeSourceMode([string]$Root) {
    foreach ($relative in @('state.template.md', 'manifests/managed-v6.tsv')) {
        $path = Join-Path $Root ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Test-Reparse $path)) { return $false }
    }
    return $true
}

function Copy-PrivateHarness([string]$Primary, [string]$Target) {
    $ledger = Join-Path $Primary '.forge\installed-files.tsv'
    if (-not (Test-Path -LiteralPath $ledger -PathType Leaf) -or (Test-Reparse $ledger)) {
        if ((Test-ForgeSourceMode $Primary) -and (Test-ForgeSourceMode $Target)) { return }
        Fail-ForgeLifecycle "SEED_BLOCKED: primary checkout is neither an installed Forge tree nor a tracked Forge source tree"
    }
    foreach ($line in [IO.File]::ReadAllLines($ledger)) {
        if (-not $line) { continue }
        Copy-MissingPrivateSurface $Primary $Target (($line -split "`t")[0])
    }
    foreach ($relative in @(
        '.forge/version', '.forge/installed-files.tsv', 'CLAUDE.md', 'AGENTS.md',
        'docs/agent-context.md', '.claude/settings.json', '.codex/config.toml',
        '.codex/hooks.json', '.mcp.json'
    )) {
        Copy-MissingPrivateSurface $Primary $Target $relative
    }
}

function Get-FoldableNarrative([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Test-Reparse $Path)) {
        Fail-ForgeLifecycle "FOLD_SAFE_STOP: missing or aliased state input: $Path"
    }
    $lines = @([IO.File]::ReadAllLines($Path)); $section = 0; $stage = 0
    $seenState = $false; $seenOpen = $false; $seenBlockers = $false; $inNow = $false
    $result = New-Object Collections.Generic.List[string]
    foreach ($line in $lines) {
        if ($line -eq '## State') {
            if ($seenState) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: duplicate state narrative heading" }
            $seenState = $true; $section = 1; $result.Add($line); continue
        }
        if ($section -eq 1 -and $line -eq '## Open Questions') {
            if ($stage -ne 4 -or $seenOpen) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: state narrative headings are out of order" }
            $seenOpen = $true; $section = 2; $inNow = $false; $result.Add($line); continue
        }
        if ($section -eq 2 -and $line -eq '## Blockers') {
            if ($seenBlockers) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: duplicate state narrative heading" }
            $seenBlockers = $true; $section = 3; $result.Add($line); continue
        }
        if ($section -gt 0 -and $line.StartsWith('## ')) { break }
        if ($section -eq 1) {
            if ($line.StartsWith('### Done')) {
                if ($stage -ne 0) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: state narrative headings are out of order" }
                $stage = 1; $inNow = $false; $result.Add($line); continue
            }
            if ($line -eq '### Now') {
                if ($stage -ne 1) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: state narrative headings are out of order" }
                $stage = 2; $inNow = $true; $result.Add($line); $result.Add(''); continue
            }
            if ($line -eq '### Next') {
                if ($stage -ne 2) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: state narrative headings are out of order" }
                $stage = 3; $inNow = $false; $result.Add($line); continue
            }
            if ($line -eq '### Deferred') {
                if ($stage -ne 3) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: state narrative headings are out of order" }
                $stage = 4; $inNow = $false; $result.Add($line); continue
            }
            if (-not $inNow) { $result.Add($line) }
            continue
        }
        if ($section -eq 2 -or $section -eq 3) { $result.Add($line) }
    }
    if (-not $seenState -or $stage -ne 4 -or -not $seenOpen -or -not $seenBlockers) {
        Fail-ForgeLifecycle "FOLD_SAFE_STOP: state narrative is structurally incomplete"
    }
    return (($result -join "`n") + "`n")
}

function Merge-FoldableNarrative([string]$BasePath, [string]$Narrative) {
    $lines = @([IO.File]::ReadAllLines($BasePath))
    $state = [Array]::IndexOf($lines, '## State')
    $rules = [Array]::IndexOf($lines, '## Update Rules')
    if ($state -lt 0 -or $rules -le $state) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: state template is structurally incomplete" }
    # Keep surrounding bytes exactly as the Bash twin does.
    $prefix = if ($state -gt 0) { ($lines[0..($state - 1)] -join "`n") + "`n" } else { '' }
    $suffix = $lines[$rules..($lines.Count - 1)] -join "`n"
    return ($prefix + $Narrative + $suffix + "`n")
}

function Test-BlankLine([string]$Line) { return ($Line -notmatch '[^ \t]') }
function Test-RuleLine([string]$Line) { return ($Line -match '^[ \t]*---[ \t]*$') }
function Test-LayoutLine([string]$Line) { return ((Test-BlankLine $Line) -or (Test-RuleLine $Line)) }

function Get-NarrativeSections([string]$Narrative) {
    $sections = New-Object object[] 7
    for ($i = 0; $i -lt 7; $i++) {
        $sections[$i] = @{ Heading = $null; Lines = (New-Object Collections.Generic.List[string]); Footer = '' }
    }
    $sec = -1
    foreach ($line in ($Narrative -split "`n")) {
        $to = -1
        if ($sec -eq -1 -and $line -ceq '## State') { $to = 0 }
        elseif ($sec -eq 0 -and $line.StartsWith('### Done', [StringComparison]::Ordinal)) { $to = 1 }
        elseif ($sec -eq 1 -and $line -ceq '### Now') { $to = 2 }
        elseif ($sec -eq 2 -and $line -ceq '### Next') { $to = 3 }
        elseif ($sec -eq 3 -and $line -ceq '### Deferred') { $to = 4 }
        elseif ($sec -eq 4 -and $line -ceq '## Open Questions') { $to = 5 }
        elseif ($sec -eq 5 -and $line -ceq '## Blockers') { $to = 6 }
        if ($to -ge 0) { $sec = $to; $sections[$sec].Heading = $line; continue }
        if ($sec -ge 0) { $sections[$sec].Lines.Add($line) }
    }
    foreach ($section in $sections) {
        if ($null -eq $section.Heading) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: narrative merge failed" }
        $lines = $section.Lines
        while ($lines.Count -gt 0 -and (Test-BlankLine $lines[$lines.Count - 1])) { $lines.RemoveAt($lines.Count - 1) }
        if ($lines.Count -gt 0 -and (Test-RuleLine $lines[$lines.Count - 1])) {
            $section.Footer = $lines[$lines.Count - 1]; $lines.RemoveAt($lines.Count - 1)
            while ($lines.Count -gt 0 -and (Test-BlankLine $lines[$lines.Count - 1])) { $lines.RemoveAt($lines.Count - 1) }
        }
        while ($lines.Count -gt 0 -and (Test-BlankLine $lines[0])) { $lines.RemoveAt(0) }
    }
    return ,$sections
}

# Deterministic three-way narrative merge: base (seed snapshot), primary, worktree.
# Per section, lines the worktree removed since seed leave primary; lines it added
# are inserted after their nearest preceding worktree line that primary still has
# (else at the section top). Everything else in primary, including edits made after
# the seed, is kept. Blank and `---` divider lines are layout, never merged content.
# Keep the Bash twin byte-identical.
function Merge-ThreeWayNarrative([string]$BaseNarrative, [string]$PrimaryNarrative, [string]$WorktreeNarrative) {
    $base = Get-NarrativeSections $BaseNarrative
    $prim = Get-NarrativeSections $PrimaryNarrative
    $work = Get-NarrativeSections $WorktreeNarrative
    $out = New-Object Text.StringBuilder
    for ($s = 0; $s -lt 7; $s++) {
        $inBase = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $inWork = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($line in $base[$s].Lines) { if (-not (Test-LayoutLine $line)) { $null = $inBase.Add($line) } }
        foreach ($line in $work[$s].Lines) { if (-not (Test-LayoutLine $line)) { $null = $inWork.Add($line) } }
        $result = New-Object Collections.Generic.List[string]
        foreach ($line in $prim[$s].Lines) {
            if (-not (Test-LayoutLine $line) -and $inBase.Contains($line) -and -not $inWork.Contains($line)) { continue }
            $result.Add($line)
        }
        $workLines = $work[$s].Lines
        for ($i = 0; $i -lt $workLines.Count; $i++) {
            $line = $workLines[$i]
            if ((Test-LayoutLine $line) -or $inBase.Contains($line) -or $result.Contains($line)) { continue }
            $at = -1
            for ($j = $i - 1; $j -ge 0; $j--) {
                if (Test-LayoutLine $workLines[$j]) { continue }
                $anchor = $result.IndexOf($workLines[$j])
                if ($anchor -ge 0) { $at = $anchor + 1; break }
            }
            if ($at -lt 0) {
                $at = 0
                while ($at -lt $result.Count -and (Test-BlankLine $result[$at])) { $at++ }
            } elseif ($line -notmatch '^[ \t]') {
                while ($at -lt $result.Count -and $result[$at] -match '^[ \t]' -and -not (Test-LayoutLine $result[$at])) { $at++ }
            }
            $result.Insert($at, $line)
        }
        $null = $out.Append($prim[$s].Heading).Append("`n`n")
        $printed = $false; $gap = $false
        foreach ($line in $result) {
            if (Test-BlankLine $line) { if ($printed) { $gap = $true }; continue }
            if ((Test-RuleLine $line) -and $printed) { $gap = $true }
            if ($gap) { $null = $out.Append("`n") }
            $null = $out.Append($line).Append("`n"); $printed = $true; $gap = (Test-RuleLine $line)
        }
        if ($printed) { $null = $out.Append("`n") }
        if ($prim[$s].Footer) { $null = $out.Append($prim[$s].Footer).Append("`n`n") }
    }
    return $out.ToString()
}

function Test-WorktreeNowEmpty([string]$Path) {
    $inState = $false; $inNow = $false
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if (-not $inState) { if ($line -ceq '## State') { $inState = $true }; continue }
        if ($line.StartsWith('## ', [StringComparison]::Ordinal)) { break }
        if (-not $inNow) { if ($line -ceq '### Now') { $inNow = $true }; continue }
        if ($line -ceq '### Next') { break }
        if (-not (Test-BlankLine $line)) { return $false }
    }
    return $true
}

function Publish-State([string]$Content, [string]$Destination) {
    $parent = Split-Path -Parent $Destination
    if ((Test-Reparse $parent) -or (Test-Reparse $Destination)) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: aliased state destination" }
    $null = New-Item -ItemType Directory -Path $parent -Force
    $temp = Join-Path $parent ('.forge-state.' + [Guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($temp, $Content, $Utf8NoBom)
    Move-Item -LiteralPath $temp -Destination $Destination -Force
}

function Seed-ForgeWorktree([string]$Requested) {
    $pair = Resolve-LinkedWorktree $Requested; $target = $pair[0]; $primary = $pair[1]
    if ($target -eq $primary) { Fail-ForgeLifecycle "SEED_BLOCKED: target must be a linked worktree" }
    Copy-PrivateHarness $primary $target
    $state = Join-Path $target '.forge\local\state.md'
    $snapshot = Join-Path $target '.forge\local\.state-seed-snapshot.md'
    if ((Test-Path -LiteralPath $state) -or (Test-Path -LiteralPath $snapshot)) { Fail-ForgeLifecycle "SEED_BLOCKED: target state or snapshot already exists" }
    $narrative = Get-FoldableNarrative (Join-Path $primary '.forge\local\state.md')
    $template = Join-Path $target '.forge\state.template.md'
    if (-not (Test-Path -LiteralPath $template -PathType Leaf) -or (Test-Reparse $template)) {
        if (Test-ForgeSourceMode $target) { $template = Join-Path $target 'state.template.md' }
    }
    if (-not (Test-Path -LiteralPath $template -PathType Leaf) -or (Test-Reparse $template)) {
        Fail-ForgeLifecycle "SEED_BLOCKED: target state template is unavailable"
    }
    Publish-State $narrative $snapshot
    Publish-State (Merge-FoldableNarrative $template $narrative) $state
    Write-Output "SEED_OK: worktree=$target snapshot=.forge/local/.state-seed-snapshot.md"
}

function Fold-ForgeWorktree([string]$Requested) {
    $pair = Resolve-LinkedWorktree $Requested; $target = $pair[0]; $primary = $pair[1]
    if ($target -eq $primary) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: fold must run for a linked worktree" }
    $snapshotPath = Join-Path $target '.forge\local\.state-seed-snapshot.md'
    $primaryPath = Join-Path $primary '.forge\local\state.md'
    $worktreePath = Join-Path $target '.forge\local\state.md'
    if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf) -or (Test-Reparse $snapshotPath)) {
        Fail-ForgeLifecycle "FOLD_SAFE_STOP: missing or aliased seed snapshot: $snapshotPath"
    }
    $primaryNarrative = Get-FoldableNarrative $primaryPath
    $worktreeNarrative = Get-FoldableNarrative $worktreePath
    $baseNarrative = Get-FoldableNarrative $snapshotPath
    if (-not (Test-WorktreeNowEmpty $worktreePath)) {
        Fail-ForgeLifecycle "FOLD_SAFE_STOP: worktree ### Now still lists work; record finished work under ### Done and move unfinished items to ### Next or ### Deferred, then rerun fold"
    }
    # replace: primary is unchanged since seed; unchanged: already folded (retry);
    # merge: primary changed after seed (sibling fold, quick fix, or hand edit).
    $folded = $worktreeNarrative
    if ($baseNarrative -ceq $primaryNarrative) { $mode = 'replace' }
    elseif ($primaryNarrative -ceq $worktreeNarrative) { $mode = 'unchanged' }
    else { $mode = 'merge'; $folded = Merge-ThreeWayNarrative $baseNarrative $primaryNarrative $worktreeNarrative }
    Publish-State (Merge-FoldableNarrative $primaryPath $folded) $primaryPath
    Write-Output "FOLD_OK: worktree=$target primary=$primary mode=$mode"
}

function Set-ForgeWorktreeIdentity([string]$Target, [string]$BaseRef, [string]$BaseSha) {
    $statePath = Join-Path $Target '.forge\local\state.md'
    $common = Get-GitCommon $Target
    $lines = @([IO.File]::ReadAllLines($statePath))
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\|\s*Worktree root\s*\|') { $lines[$i] = "| Worktree root | $Target |"; continue }
        if ($lines[$i] -match '^\|\s*Git common directory\s*\|') { $lines[$i] = "| Git common directory | $common |"; continue }
        if ($lines[$i] -match '^\|\s*Workflow base ref\s*\|') { $lines[$i] = "| Workflow base ref | $BaseRef |"; continue }
        if ($lines[$i] -match '^\|\s*Workflow base SHA\s*\|') { $lines[$i] = "| Workflow base SHA | $BaseSha |" }
    }
    Publish-State (($lines -join "`n") + "`n") $statePath
}

function Set-NativeCanonicalBranch([string]$Target, [string]$Primary, [string]$Branch, [string]$Current, [string]$Resolved) {
    & git -C $Primary update-ref "refs/heads/$Branch" $Resolved
    if ($LASTEXITCODE -ne 0) { return $false }
    & git -C $Target symbolic-ref HEAD "refs/heads/$Branch"
    if ($LASTEXITCODE -ne 0) {
        & git -C $Primary update-ref -d "refs/heads/$Branch" $Resolved 2>$null | Out-Null
        return $false
    }
    if ($Current) {
        & git -C $Primary update-ref -d "refs/heads/$Current" $Resolved
        if ($LASTEXITCODE -ne 0) {
            & git -C $Target symbolic-ref HEAD "refs/heads/$Current" 2>$null | Out-Null
            & git -C $Primary update-ref -d "refs/heads/$Branch" $Resolved 2>$null | Out-Null
            return $false
        }
    }
    return $true
}

function Restore-NativeBranch([string]$Target, [string]$Primary, [string]$Branch, [string]$Current, [string]$Resolved) {
    if ($Current) {
        & git -C $Primary update-ref "refs/heads/$Current" $Resolved 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { return }
        & git -C $Target symbolic-ref HEAD "refs/heads/$Current" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { return }
    } else {
        & git -C $Target update-ref --no-deref HEAD $Resolved 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { return }
    }
    & git -C $Primary update-ref -d "refs/heads/$Branch" $Resolved 2>$null | Out-Null
}

function Adopt-ForgeWorktree([string]$Requested, [string]$WorkKind, [string]$WorkName, [string]$BaseRef) {
    if (-not $Requested -or -not $WorkKind -or
        $WorkName -notmatch '^[a-z0-9][a-z0-9._-]*$' -or $WorkName.EndsWith('..') -or
        -not $BaseRef) {
        Fail-ForgeLifecycle "ADOPT_BLOCKED: Worktree, Kind, lowercase Name, and Base are required"
    }
    $pair = Resolve-LinkedWorktree $Requested; $target = $pair[0]; $primary = $pair[1]
    if ($target -eq $primary) { Fail-ForgeLifecycle "ADOPT_BLOCKED: target must be a linked worktree" }
    $resolved = ((& git -C $primary rev-parse --verify "$BaseRef^{commit}" 2>$null) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or -not $resolved) { Fail-ForgeLifecycle "ADOPT_BLOCKED: base does not resolve to a commit: $BaseRef" }
    $head = ((& git -C $target rev-parse --verify HEAD 2>$null) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or -not $head) { Fail-ForgeLifecycle "ADOPT_BLOCKED: native worktree has no HEAD" }
    if ($head -ne $resolved) { Fail-ForgeLifecycle "ADOPT_BLOCKED: native worktree HEAD does not match base $BaseRef" }
    $status = ((& git -C $target status --porcelain --untracked-files=all 2>$null) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or $status) { Fail-ForgeLifecycle "ADOPT_BLOCKED: native worktree must be clean before branch normalization" }

    $branch = "$WorkKind/$WorkName"
    $current = ((& git -C $target branch --show-current 2>$null) -join '').Trim()
    if ($current -in @('main', 'master', 'develop', 'development', 'production', 'release')) {
        Fail-ForgeLifecycle "ADOPT_BLOCKED: protected branch cannot be renamed: $current"
    }
    if ($current -and $current -ne $branch) {
        $upstream = ((& git -C $target for-each-ref '--format=%(upstream)' "refs/heads/$current" 2>$null) -join '').Trim()
        $hasUpstream = [bool]$upstream
        $published = ((& git -C $target branch -r --list "*/$current" 2>$null) -join '').Trim()
        if ($hasUpstream -or $published) {
            Fail-ForgeLifecycle "ADOPT_BLOCKED: shared or published branch cannot be renamed automatically: $current"
        }
    }
    if ($current -ne $branch) {
        $null = & git -C $primary show-ref --verify --quiet "refs/heads/$branch" 2>$null
        if ($LASTEXITCODE -eq 0) { Fail-ForgeLifecycle "ADOPT_BLOCKED: branch already exists: $branch" }
    }

    $state = Join-Path $target '.forge\local\state.md'
    $snapshot = Join-Path $target '.forge\local\.state-seed-snapshot.md'
    $hasState = (Test-Path -LiteralPath $state) -or (Test-Reparse $state)
    $hasSnapshot = (Test-Path -LiteralPath $snapshot) -or (Test-Reparse $snapshot)
    if ($hasState -or $hasSnapshot) {
        if (-not (Test-Path -LiteralPath $state -PathType Leaf) -or (Test-Reparse $state) -or
            -not (Test-Path -LiteralPath $snapshot -PathType Leaf) -or (Test-Reparse $snapshot)) {
            Fail-ForgeLifecycle "ADOPT_BLOCKED: state and seed snapshot must both be present or absent"
        }
        $stateText = [IO.File]::ReadAllText($state)
        if ($stateText -notmatch '(?m)^\|\s*Command\s*\|\s*none\s*\|\s*$') {
            Fail-ForgeLifecycle "ADOPT_BLOCKED: worktree workflow is already active"
        }
    }

    $renamed = $false; $initiallyUnseeded = (-not $hasState -and -not $hasSnapshot)
    try {
        if ($current -ne $branch) {
            if (-not (Set-NativeCanonicalBranch $target $primary $branch $current $resolved)) {
                Fail-ForgeLifecycle "ADOPT_BLOCKED: cannot attach canonical branch $branch"
            }
            $renamed = $true
        }
        if ($initiallyUnseeded) { Seed-ForgeWorktree $target }
        Set-ForgeWorktreeIdentity $target $BaseRef $resolved
    } catch {
        if ($initiallyUnseeded) {
            Remove-Item -LiteralPath $state -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $snapshot -Force -ErrorAction SilentlyContinue
        }
        if ($renamed) {
            Restore-NativeBranch $target $primary $branch $current $resolved
        }
        throw
    }
    Write-Output "ADOPT_OK: branch=$branch worktree=$target base=$resolved"
}

try {
    switch ($Action) {
        'Create' {
            if (-not $Kind -or $Name -notmatch '^[a-z0-9][a-z0-9._-]*$' -or $Name.EndsWith('..') -or -not $Base) {
                Fail-ForgeLifecycle "CREATE_BLOCKED: Kind, lowercase Name, and Base are required"
            }
            $root = Get-PhysicalPath (& git rev-parse --show-toplevel 2>$null | Select-Object -First 1)
            if ((Get-PrimaryWorktree $root) -ne $root) { Fail-ForgeLifecycle "CREATE_BLOCKED: create must run from the primary checkout" }
            $resolved = (& git -C $root rev-parse --verify "$Base^{commit}" 2>$null | Select-Object -First 1)
            if (-not $resolved) { Fail-ForgeLifecycle "CREATE_BLOCKED: base does not resolve to a commit: $Base" }
            $branch = "$Kind/$Name"; $target = Join-Path $root ".worktrees\$Name"
            if (Test-Path -LiteralPath $target) { Fail-ForgeLifecycle "CREATE_BLOCKED: target already exists: $target" }
            $null = & git -C $root show-ref --verify --quiet "refs/heads/$branch" 2>$null
            if ($LASTEXITCODE -eq 0) { Fail-ForgeLifecycle "CREATE_BLOCKED: branch already exists: $branch" }
            $null = New-Item -ItemType Directory -Path (Join-Path $root '.worktrees') -Force
            & git -C $root worktree add -q --no-checkout -b $branch $target $resolved
            if ($LASTEXITCODE -ne 0) { Fail-ForgeLifecycle "CREATE_BLOCKED: git worktree add failed" }
            try {
                & git -C $target read-tree --reset -u $resolved
                if ($LASTEXITCODE -ne 0) { Fail-ForgeLifecycle "CREATE_BLOCKED: cannot materialize the resolved base" }
                Seed-ForgeWorktree $target
                Set-ForgeWorktreeIdentity $target $Base $resolved
            } catch {
                & git -C $root worktree remove --force $target 2>$null | Out-Null
                & git -C $root branch -D $branch 2>$null | Out-Null
                throw
            }
            Write-Output "CREATE_OK: branch=$branch worktree=$target base=$resolved"
        }
        'Adopt' { Adopt-ForgeWorktree $Worktree $Kind $Name $Base }
        'Seed' { if (-not $Worktree) { Fail-ForgeLifecycle "SEED_BLOCKED: Worktree is required" }; Seed-ForgeWorktree $Worktree }
        'Fold' { if (-not $Worktree) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: Worktree is required" }; Fold-ForgeWorktree $Worktree }
    }
    exit 0
} catch {
    if (-not $_.Exception.Message.StartsWith('CREATE_BLOCKED') -and
        -not $_.Exception.Message.StartsWith('ADOPT_BLOCKED') -and
        -not $_.Exception.Message.StartsWith('SEED_BLOCKED') -and
        -not $_.Exception.Message.StartsWith('FOLD_')) {
        [Console]::Error.WriteLine($_.Exception.Message)
    }
    exit 1
}
