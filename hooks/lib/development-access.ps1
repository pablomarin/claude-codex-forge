# Explicit local Claude development-access configuration. Windows PowerShell 5.1 compatible.
param(
    [ValidateSet('Configure','Inherit')][string]$Action = 'Configure',
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [string]$SourceRoot,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-DevelopmentPath {
    param([string]$Root, [string]$Relative)
    $current = (Resolve-Path $Root).Path
    foreach ($part in ($Relative -split '[\\/]')) {
        $current = Join-Path $current $part
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($item) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "reparse-point managed path: $current" }
        }
    }
}

function Test-ConnectedSelection([string]$Path) {
    try { $value = [IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'unrecognized connected-development selection; preserve and reconcile it' }
    return ($value -is [System.Management.Automation.PSCustomObject] -and
        @($value.PSObject.Properties).Count -eq 2 -and $value.schema_version -eq 1 -and
        $value.claude_sandbox_enabled -is [bool] -and -not $value.claude_sandbox_enabled)
}

function Assert-UntrackedDevelopmentInput([string]$Project, [string]$Relative) {
    $tracked = @(& git -C $Project ls-files -- $Relative 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "cannot verify developer-local input is untracked: $Relative" }
    if ($tracked.Count -gt 0) { throw "$Relative is tracked; reconcile it before selecting local development" }
}

function Get-PrivateDevelopmentIgnore([string]$Project) {
    $common = & git -C $Project rev-parse --git-common-dir 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'cannot locate repository-private ignores' }
    $exclude = & git -C $Project rev-parse --git-path info/exclude 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'cannot locate repository-private ignores' }
    if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $Project $common }
    $common = (Resolve-Path -LiteralPath $common).Path
    if (-not [IO.Path]::IsPathRooted($exclude)) { $exclude = Join-Path $Project $exclude }
    $exclude = [IO.Path]::GetFullPath($exclude)
    $info = Split-Path -Parent $exclude
    $excludeCommon = (Resolve-Path -LiteralPath (Split-Path -Parent $info)).Path
    if ((Split-Path -Leaf $exclude) -cne 'exclude' -or (Split-Path -Leaf $info) -cne 'info' -or $excludeCommon -ne $common) {
        throw 'unexpected repository-private ignore path'
    }
    # Inspect before following info/exclude; neither component may be a link.
    Assert-DevelopmentPath $common 'info/exclude'
    $target = Join-Path $common 'info/exclude'
    if ((Test-Path -LiteralPath $target) -and -not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw 'repository-private ignores require a regular file'
    }
    return $target
}

function Set-DevelopmentIgnores([string]$Project, [bool]$InRepository) {
    $paths = @('.claude/settings.local.json', '.forge/local/')
    $entries = @('/.claude/settings.local.json', '/.forge/local/')
    $missing = @()
    if ($InRepository) {
        for ($index = 0; $index -lt $paths.Count; $index++) {
            & git -C $Project check-ignore --no-index -q -- $paths[$index]
            if ($LASTEXITCODE -eq 1) { $missing += $entries[$index] }
            elseif ($LASTEXITCODE -ne 0) { throw "cannot verify local ignore: $($paths[$index])" }
        }
        if ($missing.Count -eq 0) { return }
        $ignore = Get-PrivateDevelopmentIgnore $Project
    } else {
        $ignore = Join-Path $Project '.gitignore'
        Assert-DevelopmentPath $Project '.gitignore'
        if ((Test-Path -LiteralPath $ignore) -and -not (Test-Path -LiteralPath $ignore -PathType Leaf)) {
            throw 'connected development requires a regular .gitignore'
        }
        $missing = @('.claude/settings.local.json', '.forge/local/')
    }
    $ignored = if (Test-Path -LiteralPath $ignore) { [IO.File]::ReadAllText($ignore) } else { '' }
    $suffix = ''
    foreach ($entry in $missing) {
        if (@($ignored -split "`r?`n") -cnotcontains $entry) {
            if ($ignored -and -not $ignored.EndsWith("`n")) { $ignored += "`n"; $suffix += "`n" }
            $ignored += "$entry`n"
            $suffix += "$entry`n"
        }
    }
    if ($suffix) {
        [IO.Directory]::CreateDirectory((Split-Path -Parent $ignore)) | Out-Null
        [IO.File]::AppendAllText($ignore, $suffix, $Utf8NoBom)
    }
    if ($InRepository) {
        foreach ($relative in $paths) {
            & git -C $Project check-ignore --no-index -q -- $relative
            if ($LASTEXITCODE -ne 0) { throw "connected development requires an ignored local path: $relative" }
        }
    }
}

function Set-ConnectedDevelopment {
    param([string]$Project, [switch]$Check)
    foreach ($relative in @('.claude/settings.local.json', '.forge/local/connected-development.json')) {
        Assert-DevelopmentPath $Project $relative
    }
    $local = Join-Path $Project '.claude/settings.local.json'
    $scratch = Join-Path $Project '.forge/local'
    $selection = Join-Path $scratch 'connected-development.json'
    foreach ($path in @($local, $selection)) {
        if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "connected development requires a regular file: $path"
        }
    }
    if ((Test-Path -LiteralPath $scratch) -and -not (Test-Path -LiteralPath $scratch -PathType Container)) {
        throw 'connected development requires a regular .forge/local directory'
    }
    if ((Test-Path -LiteralPath $selection) -and -not (Test-ConnectedSelection $selection)) {
        throw 'unrecognized connected-development selection; preserve and reconcile it'
    }
    try {
        $settings = if (Test-Path -LiteralPath $local) { [IO.File]::ReadAllText($local) | ConvertFrom-Json -ErrorAction Stop } else { [pscustomobject]@{} }
    } catch { throw 'local Claude settings are malformed JSON; preserve and repair the file before selecting connected development' }
    if ($settings -isnot [System.Management.Automation.PSCustomObject]) { throw 'local Claude settings must be a JSON object' }
    if ($settings.PSObject.Properties['sandbox'] -and $settings.sandbox -isnot [System.Management.Automation.PSCustomObject]) {
        throw 'local Claude sandbox settings must be a JSON object'
    }
    if ($Action -eq 'Inherit' -and $settings.PSObject.Properties['sandbox'] -and $settings.sandbox.PSObject.Properties['enabled']) {
        Write-Host 'CLAUDE_SANDBOX: PRESERVED existing worktree-local sandbox choice'
        return
    }
    $inRepository = $false
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $null = & git -C $Project rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0) {
            $inRepository = $true
            foreach ($relative in @('.claude/settings.local.json', '.forge/local/connected-development.json')) {
                Assert-UntrackedDevelopmentInput $Project $relative
            }
        }
    }
    if ($Check) { return }
    # Stage secret-bearing JSON only inside the ignored local directory. Never
    # create an adjacent temporary file or a backup beside settings.local.json.
    Set-DevelopmentIgnores $Project $inRepository
    if (-not $settings.PSObject.Properties['sandbox']) { $settings | Add-Member -NotePropertyName sandbox -NotePropertyValue ([pscustomobject]@{}) }
    if (-not $settings.sandbox.PSObject.Properties['enabled'] -or $settings.sandbox.enabled -isnot [bool] -or $settings.sandbox.enabled) {
        if ($settings.sandbox.PSObject.Properties['enabled']) { $settings.sandbox.enabled = $false }
        else { $settings.sandbox | Add-Member -NotePropertyName enabled -NotePropertyValue $false }
        [IO.Directory]::CreateDirectory((Split-Path -Parent $local)) | Out-Null
        [IO.Directory]::CreateDirectory($scratch) | Out-Null
        $temporary = Join-Path $scratch ('connected-settings-' + [Guid]::NewGuid().ToString('N'))
        try {
            $empty = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $empty.Dispose()
            # Set permissions before the temporary file receives local settings,
            # which may contain credentials. File.Replace alone loses Unix modes.
            if ($env:OS -eq 'Windows_NT') {
                if (Test-Path -LiteralPath $local) { Set-Acl -LiteralPath $temporary -AclObject (Get-Acl -LiteralPath $local) }
            } else {
                if (-not [IO.File].GetMethod('GetUnixFileMode', [type[]]@([string]))) {
                    throw 'portable PowerShell requires the Unix file-permission API; use development-access.sh on this host'
                }
                $mode = if (Test-Path -LiteralPath $local) { [IO.File]::GetUnixFileMode($local) } else { [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite }
                [IO.File]::SetUnixFileMode($temporary, $mode)
            }
            [IO.File]::WriteAllText($temporary, ($settings | ConvertTo-Json -Depth 100) + "`n", $Utf8NoBom)
            if (Test-Path -LiteralPath $local) { [IO.File]::Replace($temporary, $local, [System.Management.Automation.Language.NullString]::Value) }
            else { [IO.File]::Move($temporary, $local) }
        } finally {
            if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) }
        }
    }
    if (-not (Test-Path -LiteralPath $selection)) {
        [IO.Directory]::CreateDirectory($scratch) | Out-Null
        $temporary = Join-Path $scratch ('connected-selection-' + [Guid]::NewGuid().ToString('N'))
        try {
            [IO.File]::WriteAllText($temporary, "{`"schema_version`":1,`"claude_sandbox_enabled`":false}`n", $Utf8NoBom)
            [IO.File]::Move($temporary, $selection)
        } finally { if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) } }
    }
    Write-Host 'CLAUDE_SANDBOX: CONNECTED_LOCAL sandbox.enabled=false; native permissions and managed policy still apply; restart the Claude session'
}

try {
    if ($Action -eq 'Inherit') {
        if (-not $SourceRoot) { throw 'inherit requires SourceRoot' }
        Assert-DevelopmentPath $SourceRoot '.forge/local/connected-development.json'
        $sourceSelection = Join-Path $SourceRoot '.forge/local/connected-development.json'
        if (-not (Test-Path -LiteralPath $sourceSelection)) { exit 0 }
        Assert-UntrackedDevelopmentInput $SourceRoot '.forge/local/connected-development.json'
        if (-not (Test-Path -LiteralPath $sourceSelection -PathType Leaf)) { throw 'unrecognized connected-development selection; preserve and reconcile it' }
        if (-not (Test-ConnectedSelection $sourceSelection)) { throw 'unrecognized connected-development selection; preserve and reconcile it' }
        Assert-DevelopmentPath $SourceRoot '.claude/settings.local.json'
        $sourceLocal = Join-Path $SourceRoot '.claude/settings.local.json'
        if (-not (Test-Path -LiteralPath $sourceLocal -PathType Leaf)) { exit 0 }
        Assert-UntrackedDevelopmentInput $SourceRoot '.claude/settings.local.json'
        try { $current = [IO.File]::ReadAllText($sourceLocal) | ConvertFrom-Json -ErrorAction Stop }
        catch { throw 'primary local Claude settings are malformed JSON; preserve and repair the file' }
        if ($current.sandbox.enabled -isnot [bool] -or $current.sandbox.enabled) { exit 0 }
    }
    Set-ConnectedDevelopment $ProjectRoot -Check:$Check
    exit 0
} catch {
    [Console]::Error.WriteLine("BLOCKED: " + $_.Exception.Message)
    exit 1
}
