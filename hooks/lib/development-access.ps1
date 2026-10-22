# Connected Claude development defaults. Windows PowerShell 5.1 compatible.
param(
    [ValidateSet('Configure')][string]$Action = 'Configure',
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
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

function Assert-UntrackedDevelopmentInput([string]$Project, [string]$Relative) {
    $tracked = @(& git -C $Project ls-files -- $Relative 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "cannot verify developer-local input is untracked: $Relative" }
    if ($tracked.Count -gt 0) { throw "$Relative is tracked; reconcile it before selecting local development" }
}

function Read-DevelopmentGit([string]$Project, [string]$Arguments) {
    # Windows PowerShell 5.1's native pipeline can misdecode Unicode metadata.
    $process = New-Object System.Diagnostics.Process
    try {
        $process.StartInfo.FileName = (Get-Command git -ErrorAction Stop).Source
        $process.StartInfo.Arguments = $Arguments
        $process.StartInfo.WorkingDirectory = $Project
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
        $null = $process.Start()
        $output = $process.StandardOutput.ReadToEnd()
        $null = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [pscustomobject]@{ Status=$process.ExitCode; Output=$output }
    } finally { $process.Dispose() }
}

function Get-PrivateDevelopmentIgnore([string]$Project) {
    $commonResult = Read-DevelopmentGit $Project 'rev-parse --git-common-dir'
    $excludeResult = Read-DevelopmentGit $Project 'rev-parse --git-path info/exclude'
    if ($commonResult.Status -ne 0 -or $excludeResult.Status -ne 0) { throw 'cannot locate repository-private ignores' }
    $common = $commonResult.Output.TrimEnd([char[]]"`r`n")
    $exclude = $excludeResult.Output.TrimEnd([char[]]"`r`n")
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

function Get-ConnectedCodex([string]$Project) {
    Assert-DevelopmentPath $Project '.codex/config.toml'
    $path = Join-Path $Project '.codex/config.toml'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Codex config must be a regular file' }
    $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path))
    $begin = '# forge:begin v6'; $end = '# forge:end v6'
    if (-not $text.Contains($begin) -and -not $text.Contains($end)) { return $null }
    if ([regex]::Matches($text, [regex]::Escape($begin)).Count -ne 1 -or
        [regex]::Matches($text, [regex]::Escape($end)).Count -ne 1 -or $text.IndexOf($end) -lt $text.IndexOf($begin)) {
        throw 'malformed or duplicate Forge TOML marker'
    }
    $start = $text.IndexOf($begin); $finish = $text.IndexOf($end)
    $block = $text.Substring($start, $finish - $start)
    $tables = [regex]::Matches($block, '(?ms)^\[sandbox_workspace_write\][ \t]*\r?$.*?(?=^\[|\z)')
    if ($tables.Count -ne 1) { throw 'managed Codex workspace settings require Forge setup' }
    $table = $tables[0]
    $pattern = '(?m)(^[ \t]*network_access[ \t]*=[ \t]*)(true|false)([ \t]*(?:#[^\r\n]*)?\r?$)'
    if ([regex]::Matches($table.Value, $pattern).Count -ne 1) { throw 'managed Codex network setting requires Forge setup' }
    $updated = [regex]::Replace($table.Value, $pattern, '${1}true${3}')
    $content = $text.Substring(0, $start) + $block.Substring(0, $table.Index) + $updated + $block.Substring($table.Index + $table.Length) + $text.Substring($finish)
    if ($content -ceq $text) { return $null }
    return [pscustomobject]@{ Path=$path; Content=$content }
}

function Set-ConnectedDevelopment {
    param([string]$Project, [switch]$Check)
    foreach ($relative in @('.claude/settings.local.json', '.forge/local')) {
        Assert-DevelopmentPath $Project $relative
    }
    $local = Join-Path $Project '.claude/settings.local.json'
    $scratch = Join-Path $Project '.forge/local'
    foreach ($path in @($local)) {
        if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "connected development requires a regular file: $path"
        }
    }
    if ((Test-Path -LiteralPath $scratch) -and -not (Test-Path -LiteralPath $scratch -PathType Container)) {
        throw 'connected development requires a regular .forge/local directory'
    }
    try {
        $settings = if (Test-Path -LiteralPath $local) { [IO.File]::ReadAllText($local) | ConvertFrom-Json -ErrorAction Stop } else { [pscustomobject]@{} }
    } catch { throw 'local Claude settings are malformed JSON; preserve and repair the file before selecting connected development' }
    if ($settings -isnot [System.Management.Automation.PSCustomObject]) { throw 'local Claude settings must be a JSON object' }
    if ($settings.PSObject.Properties['sandbox'] -and $settings.sandbox -isnot [System.Management.Automation.PSCustomObject]) {
        throw 'local Claude sandbox settings must be a JSON object'
    }
    $codex = Get-ConnectedCodex $Project
    $inRepository = $false
    if (Get-Command git -ErrorAction SilentlyContinue) {
        # Git's empty prefix identifies the root through aliases and Unicode
        # paths without comparing differently normalized/decoded path strings.
        $prefix = Read-DevelopmentGit $Project 'rev-parse --show-prefix'
        if ($prefix.Status -eq 0 -and $prefix.Output.TrimEnd([char[]]"`r`n").Length -eq 0) {
            $inRepository = $true
            Assert-UntrackedDevelopmentInput $Project '.claude/settings.local.json'
        }
    }
    if ($Check) { return }
    # Stage secret-bearing JSON only inside the ignored local directory. Never
    # create an adjacent temporary file or a backup beside settings.local.json.
    Set-DevelopmentIgnores $Project $inRepository
    $updates = @()
    if (-not $settings.PSObject.Properties['sandbox']) { $settings | Add-Member -NotePropertyName sandbox -NotePropertyValue ([pscustomobject]@{}) }
    if (-not $settings.sandbox.PSObject.Properties['enabled'] -or $settings.sandbox.enabled -isnot [bool] -or $settings.sandbox.enabled) {
        if ($settings.sandbox.PSObject.Properties['enabled']) { $settings.sandbox.enabled = $false }
        else { $settings.sandbox | Add-Member -NotePropertyName enabled -NotePropertyValue $false }
        $updates += [pscustomobject]@{ Path=$local; Content=($settings | ConvertTo-Json -Depth 100) + "`n" }
    }
    if ($codex) { $updates += $codex }
    foreach ($update in $updates) {
        $local = $update.Path
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
            [IO.File]::WriteAllText($temporary, $update.Content, $Utf8NoBom)
            if (Test-Path -LiteralPath $local) { [IO.File]::Replace($temporary, $local, [System.Management.Automation.Language.NullString]::Value) }
            else { [IO.File]::Move($temporary, $local) }
        } finally {
            if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) }
        }
    }
    Write-Host 'CLAUDE_SANDBOX: CONNECTED_LOCAL sandbox.enabled=false; native permissions and managed policy still apply; restart the Claude session'
}

try {
    Set-ConnectedDevelopment $ProjectRoot -Check:$Check
    exit 0
} catch {
    [Console]::Error.WriteLine("BLOCKED: " + $_.Exception.Message)
    exit 1
}
