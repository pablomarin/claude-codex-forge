# Deterministic Forge v6 linked-worktree creation, state seeding, and fold-back.
# Windows PowerShell 5.1 compatible.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet("Create", "Seed", "Fold")][string]$Action,
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
    $prefix = if ($state -gt 0) { $lines[0..($state - 1)] -join "`n" } else { '' }
    $suffix = $lines[$rules..($lines.Count - 1)] -join "`n"
    return ($prefix.TrimEnd("`r", "`n") + "`n" + $Narrative.TrimEnd("`r", "`n") + "`n" + $suffix + "`n")
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
    $snapshot = [IO.File]::ReadAllText($snapshotPath) -replace "`r", ''
    $primaryNarrative = Get-FoldableNarrative $primaryPath
    if ($snapshot -ne $primaryNarrative) { Fail-ForgeLifecycle "FOLD_DIVERGED: primary narrative changed after worktree seed; reconcile manually" }
    $worktreeNarrative = Get-FoldableNarrative $worktreePath
    Publish-State (Merge-FoldableNarrative $primaryPath $worktreeNarrative) $primaryPath
    Write-Output "FOLD_OK: worktree=$target primary=$primary"
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
            & git -C $root worktree add -q -b $branch $target $resolved
            if ($LASTEXITCODE -ne 0) { Fail-ForgeLifecycle "CREATE_BLOCKED: git worktree add failed" }
            try {
                Seed-ForgeWorktree $target
                Set-ForgeWorktreeIdentity $target $Base $resolved
            } catch {
                & git -C $root worktree remove --force $target 2>$null | Out-Null
                & git -C $root branch -D $branch 2>$null | Out-Null
                throw
            }
            Write-Output "CREATE_OK: branch=$branch worktree=$target base=$resolved"
        }
        'Seed' { if (-not $Worktree) { Fail-ForgeLifecycle "SEED_BLOCKED: Worktree is required" }; Seed-ForgeWorktree $Worktree }
        'Fold' { if (-not $Worktree) { Fail-ForgeLifecycle "FOLD_SAFE_STOP: Worktree is required" }; Fold-ForgeWorktree $Worktree }
    }
    exit 0
} catch {
    if (-not $_.Exception.Message.StartsWith('CREATE_BLOCKED') -and
        -not $_.Exception.Message.StartsWith('SEED_BLOCKED') -and
        -not $_.Exception.Message.StartsWith('FOLD_')) {
        [Console]::Error.WriteLine($_.Exception.Message)
    }
    exit 1
}
