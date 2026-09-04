param(
    [Parameter(Mandatory = $true)][ValidateSet('capture', 'identity', 'freeze', 'promote')][string]$Mode,
    [string]$Artifact,
    [string]$WorkflowBaseSha,
    [string]$WorkflowBaseRef,
    [string]$Output,
    [string]$Candidate,
    [string]$State,
    [string]$MessageFile,
    [string]$PromotionReceipt,
    [string]$HookDependencies,
    [ValidateSet(0, 1)][int]$ReplayAttempt = 0
)

$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$TemporaryFiles = New-Object System.Collections.Generic.List[string]
$TemporaryDirectories = New-Object System.Collections.Generic.List[string]
$CaptureObjectDirectory = $null
$SourceObjectDirectory = $null

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
function Invoke-GitTextWithIndex([string]$Index, [string[]]$Arguments) {
    $savedIndex = $env:GIT_INDEX_FILE
    $savedObjects = $env:GIT_OBJECT_DIRECTORY
    $savedAlternates = $env:GIT_ALTERNATE_OBJECT_DIRECTORIES
    try {
        $env:GIT_INDEX_FILE = $Index
        if ($CaptureObjectDirectory) {
            $env:GIT_OBJECT_DIRECTORY = $CaptureObjectDirectory
            $env:GIT_ALTERNATE_OBJECT_DIRECTORIES = $SourceObjectDirectory
        }
        return Invoke-GitText $Arguments
    }
    finally {
        if ($null -eq $savedIndex) { Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue }
        else { $env:GIT_INDEX_FILE = $savedIndex }
        if ($null -eq $savedObjects) { Remove-Item Env:GIT_OBJECT_DIRECTORY -ErrorAction SilentlyContinue }
        else { $env:GIT_OBJECT_DIRECTORY = $savedObjects }
        if ($null -eq $savedAlternates) { Remove-Item Env:GIT_ALTERNATE_OBJECT_DIRECTORIES -ErrorAction SilentlyContinue }
        else { $env:GIT_ALTERNATE_OBJECT_DIRECTORIES = $savedAlternates }
    }
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
function New-TaskTemporaryDirectory([string]$Stem) {
    $path = Join-Path ([IO.Path]::GetTempPath()) ("$Stem-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path | Out-Null
    $TemporaryDirectories.Add($path) | Out-Null
    return $path
}
function Write-GitDiff([string]$Root, [string[]]$Arguments, [string]$Destination) {
    & git -C $Root @Arguments "--output=$Destination"
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: Git diff capture failed' }
}
function Write-GitDiffWithIndex([string]$Root, [string]$Index, [string[]]$Arguments, [string]$Destination) {
    $savedIndex = $env:GIT_INDEX_FILE
    $savedObjects = $env:GIT_OBJECT_DIRECTORY
    $savedAlternates = $env:GIT_ALTERNATE_OBJECT_DIRECTORIES
    try {
        $env:GIT_INDEX_FILE = $Index
        if ($CaptureObjectDirectory) {
            $env:GIT_OBJECT_DIRECTORY = $CaptureObjectDirectory
            $env:GIT_ALTERNATE_OBJECT_DIRECTORIES = $SourceObjectDirectory
        }
        Write-GitDiff $Root $Arguments $Destination
    }
    finally {
        if ($null -eq $savedIndex) { Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue }
        else { $env:GIT_INDEX_FILE = $savedIndex }
        if ($null -eq $savedObjects) { Remove-Item Env:GIT_OBJECT_DIRECTORY -ErrorAction SilentlyContinue }
        else { $env:GIT_OBJECT_DIRECTORY = $savedObjects }
        if ($null -eq $savedAlternates) { Remove-Item Env:GIT_ALTERNATE_OBJECT_DIRECTORIES -ErrorAction SilentlyContinue }
        else { $env:GIT_ALTERNATE_OBJECT_DIRECTORIES = $savedAlternates }
    }
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
function Get-UntrackedPaths([string]$Root, [string]$Index) {
    $savedIndex = $env:GIT_INDEX_FILE
    $savedObjects = $env:GIT_OBJECT_DIRECTORY
    $savedAlternates = $env:GIT_ALTERNATE_OBJECT_DIRECTORIES
    try {
        $env:GIT_INDEX_FILE = $Index
        if ($CaptureObjectDirectory) {
            $env:GIT_OBJECT_DIRECTORY = $CaptureObjectDirectory
            $env:GIT_ALTERNATE_OBJECT_DIRECTORIES = $SourceObjectDirectory
        }
        $paths = @(& git -c core.quotepath=false -C $Root ls-files --others --exclude-standard -- . ':(exclude).forge/local/**')
        if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: cannot enumerate untracked paths' }
        return @($paths | Sort-Object)
    }
    finally {
        if ($null -eq $savedIndex) { Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue }
        else { $env:GIT_INDEX_FILE = $savedIndex }
        if ($null -eq $savedObjects) { Remove-Item Env:GIT_OBJECT_DIRECTORY -ErrorAction SilentlyContinue }
        else { $env:GIT_OBJECT_DIRECTORY = $savedObjects }
        if ($null -eq $savedAlternates) { Remove-Item Env:GIT_ALTERNATE_OBJECT_DIRECTORIES -ErrorAction SilentlyContinue }
        else { $env:GIT_ALTERNATE_OBJECT_DIRECTORIES = $savedAlternates }
    }
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
function Assert-NoUntrackedReparse([string]$Root, [string]$Index) {
    $savedIndex = $env:GIT_INDEX_FILE
    $savedObjects = $env:GIT_OBJECT_DIRECTORY
    $savedAlternates = $env:GIT_ALTERNATE_OBJECT_DIRECTORIES
    try {
        $env:GIT_INDEX_FILE = $Index
        if ($CaptureObjectDirectory) {
            $env:GIT_OBJECT_DIRECTORY = $CaptureObjectDirectory
            $env:GIT_ALTERNATE_OBJECT_DIRECTORIES = $SourceObjectDirectory
        }
        foreach ($item in Get-NoFollowTreeItems $Root) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { continue }
            $relative = $item.FullName.Substring($Root.Length).TrimStart('\', '/')
            & git -C $Root check-ignore -q -- $relative 2>$null
            if ($LASTEXITCODE -eq 0) { continue }
            & git -C $Root ls-files --error-unmatch -- $relative 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "BLOCKED[artifact]: untracked junction or reparse point rejected: $relative" }
        }
    }
    finally {
        if ($null -eq $savedIndex) { Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue }
        else { $env:GIT_INDEX_FILE = $savedIndex }
        if ($null -eq $savedObjects) { Remove-Item Env:GIT_OBJECT_DIRECTORY -ErrorAction SilentlyContinue }
        else { $env:GIT_OBJECT_DIRECTORY = $savedObjects }
        if ($null -eq $savedAlternates) { Remove-Item Env:GIT_ALTERNATE_OBJECT_DIRECTORIES -ErrorAction SilentlyContinue }
        else { $env:GIT_ALTERNATE_OBJECT_DIRECTORIES = $savedAlternates }
    }
}

function Get-ReceiptKv([string]$Path, [string]$Key) {
    $values = @()
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $position = $line.IndexOf('=')
        if ($position -gt 0 -and $line.Substring(0, $position) -ceq $Key) { $values += $line.Substring($position + 1) }
    }
    if ($values.Count -ne 1) { throw "BLOCKED[artifact]: $Key must occur exactly once in $Path" }
    return [string]$values[0]
}
function Get-LocalPromotionPath([string]$Root, [string]$Raw, [bool]$MustExist) {
    if (-not $Raw -or $Raw.Contains("`r") -or $Raw.Contains("`n")) { throw 'BLOCKED[artifact]: invalid promotion path' }
    $path = if ([IO.Path]::IsPathRooted($Raw)) { [IO.Path]::GetFullPath($Raw) } else { [IO.Path]::GetFullPath((Join-Path $Root $Raw)) }
    $prefix = [IO.Path]::GetFullPath((Join-Path $Root '.forge\local')).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'BLOCKED[artifact]: promotion inputs and receipt must be under .forge/local' }
    if ($MustExist) {
        $item = Get-Item -LiteralPath $path -Force
        if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw "BLOCKED[artifact]: no-follow regular file required: $Raw" }
    } else {
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw "BLOCKED[artifact]: linked output rejected: $Raw" }
    }
    return $path
}
function Get-PromotionHook([string]$Root, [string]$Name) {
    $raw = Invoke-GitText @('-C', $Root, 'rev-parse', '--git-path', "hooks/$Name")
    $path = if ([IO.Path]::IsPathRooted($raw)) { [IO.Path]::GetFullPath($raw) } else { [IO.Path]::GetFullPath((Join-Path $Root $raw)) }
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw "BLOCKED[artifact]: $Name hook must be a no-follow regular file" }
    return [pscustomobject]@{ Path = $path; Hash = (Get-ShaFile $path) }
}
function Invoke-PromotionHook([string]$Name, $Hook, [string]$Runner, [string]$Message, [string]$Index) {
    if (-not $Hook) { return }
    if ((Get-ShaFile $Hook.Path) -cne $Hook.Hash) { throw "BLOCKED[artifact]: $Name hook changed after capture" }
    $savedIndex = $env:GIT_INDEX_FILE
    $savedLocation = (Get-Location).Path
    try {
        Set-Location -LiteralPath $Runner
        $env:GIT_INDEX_FILE = $Index
        if ($Name -eq 'pre-commit' -or $Name -eq 'post-commit') { & $Hook.Path }
        elseif ($Name -eq 'prepare-commit-msg') { & $Hook.Path $Message '' }
        else { & $Hook.Path $Message }
        if ($LASTEXITCODE -ne 0) { throw "BLOCKED[artifact]: $Name hook failed" }
    }
    finally {
        Set-Location -LiteralPath $savedLocation
        if ($null -eq $savedIndex) { Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue } else { $env:GIT_INDEX_FILE = $savedIndex }
    }
}
function Invoke-CandidatePromotion {
    $root = (Resolve-Path (Invoke-GitText @('rev-parse', '--show-toplevel'))).Path
    $candidateFile = Get-LocalPromotionPath $root $Candidate $true
    $stateFile = Get-LocalPromotionPath $root $State $true
    $message = Get-LocalPromotionPath $root $MessageFile $true
    $receipt = Get-LocalPromotionPath $root $PromotionReceipt $false
    $verification = Join-Path $PSScriptRoot 'verification-receipt.ps1'
    if (-not (Test-Path -LiteralPath $verification)) { $verification = Join-Path $root 'hooks\lib\verification-receipt.ps1' }
    if (-not (Test-Path -LiteralPath $verification)) { throw 'BLOCKED[artifact]: verification-receipt helper unavailable' }
    . $verification
    $verificationResult = Invoke-VerificationReceipt -ReceiptMode check -StatePath $stateFile
    if ($verificationResult.Status -ne 0) { throw 'BLOCKED[artifact]: final receipt set does not certify the current candidate' }
    if ((Get-ReceiptKv $candidateFile 'schema_version') -cne '2' -or (Get-ReceiptKv $candidateFile 'candidate_state') -cne 'staged-clean') { throw 'BLOCKED[artifact]: staged-clean schema-v2 candidate required' }
    $oldId = Get-ReceiptKv $candidateFile 'candidate_id'
    $head = Get-ReceiptKv $candidateFile 'git_head'
    $tree = Get-ReceiptKv $candidateFile 'index_tree'
    if ((Invoke-GitText @('-C', $root, 'rev-parse', 'HEAD')) -cne $head) { throw 'BLOCKED[artifact]: candidate parent is stale' }
    $null = Invoke-GitText @('-C', $root, 'cat-file', '-e', "$tree^{tree}")
    $branch = Invoke-GitText @('-C', $root, 'symbolic-ref', '-q', 'HEAD')

    $hooks = @{}
    foreach ($name in @('pre-commit','prepare-commit-msg','commit-msg','post-commit')) { $hooks[$name] = Get-PromotionHook $root $name }
    $runner = Join-Path ([IO.Path]::GetTempPath()) ('forge-promote-' + [Guid]::NewGuid().ToString('N'))
    $patch = Join-Path ([IO.Path]::GetTempPath()) ('forge-hook-replay-' + [Guid]::NewGuid().ToString('N'))
    $runnerAdded = $false
    try {
        & git -C $root worktree add -q --detach --no-checkout $runner $head
        if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: cannot create disposable promotion worktree' }
        $runnerAdded = $true
        & git -C $runner read-tree --reset -u $tree
        if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: cannot materialize frozen index tree' }
        $runnerIndex = Invoke-GitText @('-C', $runner, 'rev-parse', '--git-path', 'index')
        if (-not [IO.Path]::IsPathRooted($runnerIndex)) { $runnerIndex = Join-Path $runner $runnerIndex }
        $runnerMessage = Invoke-GitText @('-C', $runner, 'rev-parse', '--git-path', 'COMMIT_EDITMSG')
        if (-not [IO.Path]::IsPathRooted($runnerMessage)) { $runnerMessage = Join-Path $runner $runnerMessage }
        Copy-Item -LiteralPath $message -Destination $runnerMessage -Force

        $dependencyHash = 'none'
        if ($HookDependencies) {
            $dependencies = Get-LocalPromotionPath $root $HookDependencies $true
            $dependencyHash = Get-ShaFile $dependencies
            foreach ($line in [IO.File]::ReadAllLines($dependencies)) {
                if (-not $line) { continue }
                $parts = $line.Split("`t"); if ($parts.Count -ne 2) { throw 'BLOCKED[artifact]: malformed hook dependency manifest' }
                $relative = $parts[0]; Assert-SafeRelative $relative
                if ($relative -eq '.git' -or $relative.StartsWith('.git\') -or $relative -eq '.forge\local' -or $relative.StartsWith('.forge\local\')) { throw "BLOCKED[artifact]: hook dependency escapes policy: $relative" }
                $source = Join-Path $root $relative; $item = Get-Item -LiteralPath $source -Force
                if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw "BLOCKED[artifact]: hook dependency missing: $relative" }
                & git -C $root check-ignore -q -- $relative
                if ($LASTEXITCODE -ne 0) { throw "BLOCKED[artifact]: hook dependency must be ignored: $relative" }
                if ((Get-ShaFile $source) -cne $parts[1]) { throw "BLOCKED[artifact]: hook dependency hash changed: $relative" }
                $destination = Join-Path $runner $relative
                New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                Copy-Item -LiteralPath $source -Destination $destination -Force
                (Get-Item -LiteralPath $destination).IsReadOnly = $true
            }
        }

        Invoke-PromotionHook 'pre-commit' $hooks['pre-commit'] $runner $runnerMessage $runnerIndex
        Invoke-PromotionHook 'prepare-commit-msg' $hooks['prepare-commit-msg'] $runner $runnerMessage $runnerIndex
        Invoke-PromotionHook 'commit-msg' $hooks['commit-msg'] $runner $runnerMessage $runnerIndex
        $afterTree = Invoke-GitText @('-C', $runner, 'write-tree')
        & git -C $runner diff --quiet
        $unstagedClean = $LASTEXITCODE -eq 0
        $untracked = @(& git -C $runner ls-files --others --exclude-standard -- .)
        if ($afterTree -cne $tree -or -not $unstagedClean -or $untracked.Count -gt 0) {
            if ($ReplayAttempt -ne 0) { throw 'BLOCKED[artifact]: hook mutated again after one bounded replay' }
            foreach ($item in Get-NoFollowTreeItems $runner) {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "BLOCKED[artifact]: hook produced linked or special path: $($item.FullName)" }
            }
            & git -C $runner add -A
            if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: cannot capture hook changes' }
            $changed = @(& git -C $runner diff --cached --name-only $tree).Count
            $maxFiles = 32; if ($env:FORGE_HOOK_REPLAY_MAX_FILES -match '^[0-9]+$') { $maxFiles = [int]$env:FORGE_HOOK_REPLAY_MAX_FILES }
            if ($changed -gt $maxFiles) { throw 'BLOCKED[artifact]: hook replay exceeds file limit' }
            foreach ($line in @(& git -C $runner diff --cached --numstat $tree)) { if ($line -match '^-') { throw 'BLOCKED[artifact]: binary hook replay is outside policy' } }
            & git -C $runner diff --cached --binary $tree "--output=$patch"
            if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: cannot capture hook replay artifact' }
            $maxBytes = 1048576; if ($env:FORGE_HOOK_REPLAY_MAX_BYTES -match '^[0-9]+$') { $maxBytes = [int64]$env:FORGE_HOOK_REPLAY_MAX_BYTES }
            if ((Get-Item -LiteralPath $patch).Length -gt $maxBytes) { throw 'BLOCKED[artifact]: hook replay exceeds byte limit' }
            $verificationResult = Invoke-VerificationReceipt -ReceiptMode check -StatePath $stateFile
            if ($verificationResult.Status -ne 0) { throw 'BLOCKED[artifact]: candidate changed before hook replay' }
            & git -C $root apply --index --binary $patch
            if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: validated hook replay could not be applied' }
            $script:PromotionExitStatus = 3
            throw 'HOOK_REPLAY_REQUIRED: changes were staged; freeze and rerun all final gates once'
        }

        $commitArgs = @('-C', $root, 'commit-tree', $tree, '-p', $head)
        $signing = (& git -C $root config --bool commit.gpgsign 2>$null | Select-Object -First 1)
        if ($signing -eq 'true') { $commitArgs = @('-C', $root, 'commit-tree', '-S', $tree, '-p', $head) }
        $newCommit = ((Get-Content -LiteralPath $runnerMessage -Raw) | & git @commitArgs) -join ''
        if ($LASTEXITCODE -ne 0 -or -not $newCommit) { throw 'BLOCKED[artifact]: commit-tree failed' }
        if ((Invoke-GitText @('-C', $root, 'rev-parse', "$newCommit^{tree}")) -cne $tree -or (Invoke-GitText @('-C', $root, 'rev-parse', "$newCommit^")) -cne $head) { throw 'BLOCKED[artifact]: temporary commit identity mismatch' }
        $verificationResult = Invoke-VerificationReceipt -ReceiptMode check -StatePath $stateFile
        if ($verificationResult.Status -ne 0) { throw 'BLOCKED[artifact]: candidate changed before compare-and-swap' }
        & git -C $root update-ref $branch $newCommit $head
        if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: compare-and-swap rejected concurrent branch movement' }

        $postStatus = 'not-run'
        if ($hooks['post-commit']) {
            try { Invoke-PromotionHook 'post-commit' $hooks['post-commit'] $root $message (Invoke-GitText @('-C', $root, 'rev-parse', '--git-path', 'index')); $postStatus = 'pass' }
            catch { $postStatus = 'failed' }
        }
        $dirty = @(& git -C $root status --porcelain --untracked-files=all).Count -gt 0
        function Get-HookHash($Hook) { if ($Hook) { return $Hook.Hash } return 'none' }
        $body = "schema_version=2`nold_candidate_id=$oldId`nold_head=$head`nhook_pre_commit_hash=$(Get-HookHash ($hooks['pre-commit']))`nhook_prepare_commit_msg_hash=$(Get-HookHash ($hooks['prepare-commit-msg']))`nhook_commit_msg_hash=$(Get-HookHash ($hooks['commit-msg']))`nhook_post_commit_hash=$(Get-HookHash ($hooks['post-commit']))`nhook_dependency_manifest_hash=$dependencyHash`ntemporary_commit=$newCommit`nnew_branch_commit=$newCommit`nnew_branch_tree=$tree`nworktree_identity=$(Get-ReceiptKv $candidateFile 'worktree_identity')`npost_commit_status=$postStatus`npost_commit_dirty=$($dirty.ToString().ToLowerInvariant())`n"
        [IO.File]::WriteAllText("$receipt.tmp.$PID", $body, $Utf8); Move-Item -LiteralPath "$receipt.tmp.$PID" -Destination $receipt -Force
        if ($postStatus -eq 'failed') { throw 'POST_COMMIT_HOOK_FAILED' }
        if ($dirty) { throw 'POST_COMMIT_DIRTY' }
        Write-Output "PROMOTED:$newCommit"
    }
    finally {
        if ($runnerAdded) { & git -C $root worktree remove --force $runner 2>$null | Out-Null }
        Remove-Item -LiteralPath $patch -Force -ErrorAction SilentlyContinue
    }
}

if ($Mode -eq 'promote') {
    $script:PromotionExitStatus = 2
    try { Invoke-CandidatePromotion; exit 0 }
    catch { [Console]::Error.WriteLine([string]$_.Exception.Message); exit $script:PromotionExitStatus }
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
    $rootIndexRaw = Invoke-GitText @('-C', $root, 'rev-parse', '--git-path', 'index')
    $rootIndex = if ([IO.Path]::IsPathRooted($rootIndexRaw)) { [IO.Path]::GetFullPath($rootIndexRaw) } else { [IO.Path]::GetFullPath((Join-Path $root $rootIndexRaw)) }
    $rootIndexItem = Get-Item -LiteralPath $rootIndex -Force
    if ($rootIndexItem.PSIsContainer -or (($rootIndexItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'BLOCKED[artifact]: worktree index must be a no-follow regular file' }
    $sourceObjectsRaw = Invoke-GitText @('-C', $root, 'rev-parse', '--git-path', 'objects')
    $SourceObjectDirectory = if ([IO.Path]::IsPathRooted($sourceObjectsRaw)) { [IO.Path]::GetFullPath($sourceObjectsRaw) } else { [IO.Path]::GetFullPath((Join-Path $root $sourceObjectsRaw)) }
    $sourceObjectsItem = Get-Item -LiteralPath $SourceObjectDirectory -Force
    if (-not $sourceObjectsItem.PSIsContainer) { throw 'BLOCKED[artifact]: source Git object database is unavailable' }
    $captureIndex = New-TaskTemporaryFile 'forge-index'
    $recheckIndex = New-TaskTemporaryFile 'forge-index-recheck'
    if ($Mode -ne 'freeze') { $CaptureObjectDirectory = New-TaskTemporaryDirectory 'forge-objects' }
    Copy-Item -LiteralPath $rootIndex -Destination $captureIndex -Force
    # Isolate even read-only capture commands because write-tree may update the
    # cache extension. Capture and identity also write generated tree objects to
    # disposable storage rather than requiring source Git-metadata write access.
    $indexTree = Invoke-GitTextWithIndex $captureIndex @('-C', $root, 'write-tree')
    $stagedPatch = New-TaskTemporaryFile 'forge-staged'
    $unstagedPatch = New-TaskTemporaryFile 'forge-unstaged'
    Write-GitDiffWithIndex $root $captureIndex @('diff', '--cached', '--binary', 'HEAD') $stagedPatch
    Write-GitDiffWithIndex $root $captureIndex @('diff', '--binary') $unstagedPatch
    $stagedHash = Get-ShaFile $stagedPatch
    $unstagedHash = Get-ShaFile $unstagedPatch
    Assert-NoUntrackedReparse $root $captureIndex
    $untrackedPaths = Get-UntrackedPaths $root $captureIndex
    $manifest = Get-UntrackedManifest $root $untrackedPaths
    $manifestText = (@($manifest) -join "`n") + "`n"
    $untrackedHash = Get-ShaText $manifestText

    $candidateId = Get-ShaText "$base`n$head`n$indexTree`n$worktreeIdentity`n"
    $candidateState = 'dirty'
    if ((Get-Item -LiteralPath $unstagedPatch).Length -eq 0 -and @($untrackedPaths).Count -eq 0) { $candidateState = 'staged-clean' }
    $kind = ''
    $identity = ''
    $snapshot = ''
    $fileArtifact = ''
    switch ($Artifact) {
        'git:working-tree' {
            $kind = 'git-working-tree'
            if ($candidateState -eq 'staged-clean') { $identity = $candidateId }
            else { $identity = Get-ShaText "$base`n$head`n$indexTree`n$stagedHash`n$unstagedHash`n$untrackedHash`n$worktreeIdentity`n" }
        }
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

    if ($Mode -eq 'freeze') {
        if ($kind -ne 'git-working-tree' -or $candidateState -ne 'staged-clean') { throw 'BLOCKED[artifact]: freeze requires a staged-clean git:working-tree candidate' }
        if (-not $Output) { throw 'BLOCKED[artifact]: freeze output is required' }
    }
    elseif ($Mode -eq 'capture') {
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
            if ($kind -eq 'git-working-tree') {
                & git -C $snapshot add -A
                if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: candidate index materialization failed' }
                $candidateTree = Invoke-GitText @('-C', $snapshot, 'write-tree')
                $savedAuthorName = $env:GIT_AUTHOR_NAME; $savedAuthorEmail = $env:GIT_AUTHOR_EMAIL
                $savedCommitterName = $env:GIT_COMMITTER_NAME; $savedCommitterEmail = $env:GIT_COMMITTER_EMAIL
                try {
                    $env:GIT_AUTHOR_NAME = 'Forge'; $env:GIT_AUTHOR_EMAIL = 'forge@invalid'
                    $env:GIT_COMMITTER_NAME = 'Forge'; $env:GIT_COMMITTER_EMAIL = 'forge@invalid'
                    $candidateCommit = ("Forge immutable review candidate`n" | & git -C $snapshot commit-tree $candidateTree -p $head) -join ''
                    if ($LASTEXITCODE -ne 0 -or -not $candidateCommit) { throw 'BLOCKED[artifact]: candidate commit materialization failed' }
                }
                finally {
                    $env:GIT_AUTHOR_NAME = $savedAuthorName; $env:GIT_AUTHOR_EMAIL = $savedAuthorEmail
                    $env:GIT_COMMITTER_NAME = $savedCommitterName; $env:GIT_COMMITTER_EMAIL = $savedCommitterEmail
                }
                & git -C $snapshot update-ref refs/heads/candidate $candidateCommit
                if ($LASTEXITCODE -eq 0) { & git -C $snapshot checkout -q --detach $candidateCommit }
            }
            else { & git -C $snapshot update-ref refs/heads/candidate $head }
            if ($LASTEXITCODE -ne 0) { throw 'BLOCKED[artifact]: candidate ref materialization failed' }
        }
    }

    if ((Invoke-GitText @('-C', $root, 'rev-parse', 'HEAD')) -cne $head) { throw 'BLOCKED[artifact]: HEAD changed during capture' }
    Copy-Item -LiteralPath $rootIndex -Destination $recheckIndex -Force
    if ((Invoke-GitTextWithIndex $recheckIndex @('-C', $root, 'write-tree')) -cne $indexTree) { throw 'BLOCKED[artifact]: index changed during capture' }
    $stagedRecheck = New-TaskTemporaryFile 'forge-staged-recheck'
    $unstagedRecheck = New-TaskTemporaryFile 'forge-unstaged-recheck'
    Write-GitDiffWithIndex $root $recheckIndex @('diff', '--cached', '--binary', 'HEAD') $stagedRecheck
    Write-GitDiffWithIndex $root $recheckIndex @('diff', '--binary') $unstagedRecheck
    if ((Get-ShaFile $stagedRecheck) -cne $stagedHash -or (Get-ShaFile $unstagedRecheck) -cne $unstagedHash) { throw 'BLOCKED[artifact]: tracked content changed during capture' }
    Assert-NoUntrackedReparse $root $recheckIndex
    $pathsAfter = Get-UntrackedPaths $root $recheckIndex
    if ((@($pathsAfter) -join "`n") -cne (@($untrackedPaths) -join "`n")) { throw 'BLOCKED[artifact]: untracked path set changed during capture' }
    $manifestAfter = Get-UntrackedManifest $root $pathsAfter
    if ((@($manifestAfter) -join "`n") -cne (@($manifest) -join "`n")) { throw 'BLOCKED[artifact]: untracked content changed during capture' }

    $schema = 1
    if ($Mode -eq 'freeze') { $schema = 2 }
    $body = "schema_version=$schema`nartifact_kind=$kind`nartifact_identity=$identity`nartifact_hash=$identity`ncandidate_id=$candidateId`ncandidate_state=$candidateState`nworktree_identity=$worktreeIdentity`ngit_head=$head`nworkflow_base_ref=$WorkflowBaseRef`nworkflow_base_sha=$base`nindex_tree=$indexTree`nstaged_hash=$stagedHash`nunstaged_hash=$unstagedHash`nuntracked_hash=$untrackedHash`nuntracked_count=$($manifest.Count)`n"
    if ($snapshot) { $body += "snapshot_path=$snapshot`n" }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Output) -Force | Out-Null
    [IO.File]::WriteAllText($Output, $body, $Utf8)
}
finally {
    foreach ($temporary in $TemporaryFiles) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    foreach ($temporary in $TemporaryDirectories) { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue }
}
