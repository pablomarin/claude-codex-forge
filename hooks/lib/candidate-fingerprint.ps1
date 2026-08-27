param(
    [Parameter(Mandatory = $true)][ValidateSet('capture', 'identity')][string]$Mode,
    [Parameter(Mandatory = $true)][string]$Artifact,
    [Parameter(Mandatory = $true)][string]$WorkflowBaseSha,
    [Parameter(Mandatory = $true)][string]$WorkflowBaseRef,
    [Parameter(Mandatory = $true)][string]$Output
)

$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$TemporaryFiles = New-Object System.Collections.Generic.List[string]

function Get-ShaBytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-ShaText([string]$Text) { return Get-ShaBytes ($Utf8.GetBytes($Text)) }
function Get-ShaFile([string]$Path) { return Get-ShaBytes ([IO.File]::ReadAllBytes($Path)) }
function Invoke-GitText([string[]]$Arguments) {
    $result = (& git @Arguments 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "BLOCKED[artifact]: git $($Arguments -join ' ') failed" }
    return $result
}
function Get-StateValue([string]$Path, [string]$Field) {
    $matches = New-Object System.Collections.Generic.List[string]
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $parts = $line.Split('|')
        if ($parts.Count -ge 4 -and $parts[1].Trim() -ceq $Field) { $matches.Add($parts[2].Trim()) }
    }
    if ($matches.Count -ne 1) { throw "BLOCKED[artifact]: canonical state field $Field must occur exactly once" }
    return $matches[0]
}
function New-TaskTemporaryFile([string]$Stem) {
    $path = Join-Path ([IO.Path]::GetTempPath()) ("$Stem-" + [Guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllBytes($path, [byte[]]@())
    $TemporaryFiles.Add($path) | Out-Null
    return $path
}
function Write-GitDiff([string]$Root, [string[]]$Arguments, [string]$Destination) {
    & git -C $Root @Arguments "--output=$Destination"
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: Git diff capture failed' }
}
function Test-InExcludedTree([string]$Relative) {
    return $Relative -eq '.git' -or $Relative.StartsWith('.git\') -or
        $Relative -eq '.forge\local' -or $Relative.StartsWith('.forge\local\')
}
function Get-NoFollowTreeItems([string]$Root) {
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($Root)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($item in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop) {
            $relative = $item.FullName.Substring($Root.Length).TrimStart('\', '/')
            if (Test-InExcludedTree $relative) { continue }
            Write-Output $item
            if ($item.PSIsContainer -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)) { $pending.Push($item.FullName) }
        }
    }
}
function Get-UntrackedPaths([string]$Root) {
    $paths = @(& git -c core.quotepath=false -C $Root ls-files --others --exclude-standard -- . ':(exclude).forge/local/**')
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: cannot enumerate untracked paths' }
    return @($paths | Sort-Object)
}
function Assert-SafeRelative([string]$Relative) {
    if (-not $Relative -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)' -or $Relative.Contains("`n") -or $Relative.Contains("`r")) {
        throw "BLOCKED[artifact]: unsafe candidate path: $Relative"
    }
}
function Get-UntrackedManifest([string]$Root, [string[]]$Paths) {
    $manifest = New-Object System.Collections.Generic.List[string]
    [long]$total = 0
    foreach ($relative in $Paths) {
        Assert-SafeRelative $relative
        $path = Join-Path $Root $relative
        $item = Get-Item -LiteralPath $path -Force
        if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw "BLOCKED[artifact]: untracked reparse or non-file rejected: $relative" }
        $total += $item.Length
        if ($item.Length -gt 10485760 -or $total -gt 52428800) { throw 'BLOCKED[artifact]: untracked size limit exceeded' }
        $manifest.Add("$relative`t$($item.Length)`t$(Get-ShaFile $path)")
    }
    return $manifest
}
function Assert-NoUntrackedReparse([string]$Root) {
    foreach ($item in Get-NoFollowTreeItems $Root) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { continue }
        $relative = $item.FullName.Substring($Root.Length).TrimStart('\', '/')
        & git -C $Root ls-files --error-unmatch -- $relative 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "BLOCKED[artifact]: untracked junction or reparse point rejected: $relative" }
    }
}

try {
    $root = (Resolve-Path (Invoke-GitText @('rev-parse', '--show-toplevel'))).Path
    $head = Invoke-GitText @('-C', $root, 'rev-parse', 'HEAD')
    $commonRelative = Invoke-GitText @('-C', $root, 'rev-parse', '--git-common-dir')
    $common = (Resolve-Path (Join-Path $root $commonRelative)).Path
    $state = Join-Path $root '.forge/local/state.md'
    if (-not (Test-Path -LiteralPath $state -PathType Leaf)) { throw 'BLOCKED[artifact]: canonical state is required' }
    $stateItem = Get-Item -LiteralPath $state -Force
    if (($stateItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or (Get-Content -LiteralPath $state -TotalCount 1) -cne '<!-- forge:state-schema v6 -->') { throw 'BLOCKED[artifact]: canonical state schema is unsupported' }
    if ((Get-StateValue $state 'Worktree root') -cne $root -or (Get-StateValue $state 'Git common directory') -cne $common) { throw 'BLOCKED[artifact]: canonical state belongs to another worktree' }
    if ($WorkflowBaseRef -cne (Get-StateValue $state 'Workflow base ref') -or $WorkflowBaseSha -cne (Get-StateValue $state 'Workflow base SHA')) { throw 'BLOCKED[artifact]: caller workflow base differs from canonical state' }
    $base = Invoke-GitText @('-C', $root, 'rev-parse', "$WorkflowBaseSha^{commit}")
    & git -C $root merge-base --is-ancestor $base $head 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: workflow base is not an ancestor of HEAD' }
    $worktreeIdentity = Get-ShaText "$root|$common`n"
    $indexTree = Invoke-GitText @('-C', $root, 'write-tree')
    $stagedPatch = New-TaskTemporaryFile 'forge-staged'
    $unstagedPatch = New-TaskTemporaryFile 'forge-unstaged'
    Write-GitDiff $root @('diff', '--cached', '--binary', 'HEAD') $stagedPatch
    Write-GitDiff $root @('diff', '--binary') $unstagedPatch
    $stagedHash = Get-ShaFile $stagedPatch
    $unstagedHash = Get-ShaFile $unstagedPatch
    Assert-NoUntrackedReparse $root
    $untrackedPaths = Get-UntrackedPaths $root
    $manifest = Get-UntrackedManifest $root $untrackedPaths
    $manifestText = (@($manifest) -join "`n") + "`n"
    $untrackedHash = Get-ShaText $manifestText

    $kind = ''
    $identity = ''
    $snapshot = ''
    $fileArtifact = ''
    switch ($Artifact) {
        'git:working-tree' { $kind = 'git-working-tree'; $identity = Get-ShaText "$base`n$head`n$indexTree`n$stagedHash`n$unstagedHash`n$untrackedHash`n$worktreeIdentity`n" }
        'git:head' { $kind = 'git-head'; $identity = Get-ShaText "$head|$worktreeIdentity`n" }
        default {
            if (-not $Artifact.StartsWith('file:')) { throw 'BLOCKED[artifact]: invalid artifact' }
            $kind = 'file'
            $rawPath = $Artifact.Substring(5)
            if (-not $rawPath) { throw 'BLOCKED[artifact]: empty file artifact' }
            $candidatePath = if ([IO.Path]::IsPathRooted($rawPath)) { $rawPath } else { Join-Path $root $rawPath }
            $fileArtifact = [IO.Path]::GetFullPath($candidatePath)
            $rootPrefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            if (-not $fileArtifact.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'BLOCKED[artifact]: file artifact escapes worktree' }
            $item = Get-Item -LiteralPath $fileArtifact -Force
            if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'BLOCKED[artifact]: linked or non-file artifact rejected' }
            $identity = Get-ShaText "$fileArtifact|$(Get-ShaFile $fileArtifact)`n"
        }
    }

    if ($Mode -eq 'capture') {
        $parent = Join-Path ([IO.Path]::GetTempPath()) ('forge-candidate-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $parent | Out-Null
        if ($kind -eq 'file') {
            $snapshot = Join-Path $parent 'data'
            New-Item -ItemType Directory -Path $snapshot | Out-Null
            Copy-Item -LiteralPath $fileArtifact -Destination (Join-Path $snapshot ([IO.Path]::GetFileName($fileArtifact)))
        }
        else {
            $snapshot = Join-Path $parent 'repository'
            & git clone -q --no-hardlinks --no-checkout $root $snapshot
            if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: clone failed' }
            & git -C $snapshot remote remove origin
            if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: candidate source binding removal failed' }
            & git -C $snapshot reflog expire --expire=now --all
            if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: candidate clone provenance removal failed' }
            $disabledHooks = Join-Path $snapshot '.git/forge-disabled-hooks'
            New-Item -ItemType Directory -Path $disabledHooks | Out-Null
            & git -C $snapshot config core.hooksPath $disabledHooks
            if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: candidate hook isolation failed' }
            & git -C $snapshot config core.symlinks false
            & git -C $snapshot checkout -q --detach $head
            if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: candidate checkout failed' }
            if ($kind -eq 'git-working-tree') {
                if ((Get-Item -LiteralPath $stagedPatch).Length -gt 0) {
                    & git -C $snapshot apply --index --binary $stagedPatch
                    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: staged materialization failed' }
                }
                if ((Get-Item -LiteralPath $unstagedPatch).Length -gt 0) {
                    & git -C $snapshot apply --binary $unstagedPatch
                    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: unstaged materialization failed' }
                }
                foreach ($line in $manifest) {
                    $parts = $line.Split("`t")
                    $relative = $parts[0]
                    $source = Join-Path $root $relative
                    if ((Get-ShaFile $source) -ne $parts[2]) { throw "BLOCKED[artifact]: untracked content raced: $relative" }
                    $destination = Join-Path $snapshot $relative
                    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                    Copy-Item -LiteralPath $source -Destination $destination
                }
            }
        }
    }

    if ((Invoke-GitText @('-C', $root, 'rev-parse', 'HEAD')) -cne $head) { throw 'BLOCKED[artifact]: HEAD changed during capture' }
    if ((Invoke-GitText @('-C', $root, 'write-tree')) -cne $indexTree) { throw 'BLOCKED[artifact]: index changed during capture' }
    $stagedRecheck = New-TaskTemporaryFile 'forge-staged-recheck'
    $unstagedRecheck = New-TaskTemporaryFile 'forge-unstaged-recheck'
    Write-GitDiff $root @('diff', '--cached', '--binary', 'HEAD') $stagedRecheck
    Write-GitDiff $root @('diff', '--binary') $unstagedRecheck
    if ((Get-ShaFile $stagedRecheck) -cne $stagedHash -or (Get-ShaFile $unstagedRecheck) -cne $unstagedHash) { throw 'BLOCKED[artifact]: tracked content changed during capture' }
    Assert-NoUntrackedReparse $root
    $pathsAfter = Get-UntrackedPaths $root
    if ((@($pathsAfter) -join "`n") -cne (@($untrackedPaths) -join "`n")) { throw 'BLOCKED[artifact]: untracked path set changed during capture' }
    $manifestAfter = Get-UntrackedManifest $root $pathsAfter
    if ((@($manifestAfter) -join "`n") -cne (@($manifest) -join "`n")) { throw 'BLOCKED[artifact]: untracked content changed during capture' }

    $body = "schema_version=1`nartifact_kind=$kind`nartifact_identity=$identity`nartifact_hash=$identity`nworktree_identity=$worktreeIdentity`ngit_head=$head`nworkflow_base_ref=$WorkflowBaseRef`nworkflow_base_sha=$base`nindex_tree=$indexTree`nstaged_hash=$stagedHash`nunstaged_hash=$unstagedHash`nuntracked_hash=$untrackedHash`nuntracked_count=$($manifest.Count)`n"
    if ($snapshot) { $body += "snapshot_path=$snapshot`n" }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Output) -Force | Out-Null
    [IO.File]::WriteAllText($Output, $body, $Utf8)
}
finally {
    foreach ($temporary in $TemporaryFiles) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}
