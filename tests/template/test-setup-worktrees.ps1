# Native Windows PowerShell 5.1 suite; PS7 executions are portable smoke only.
# Main-host identities are synthetic preservation fixtures, not authentication.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$setup = Join-Path $root 'setup.ps1'
$runtime = (Get-Process -Id $PID).Path
$utf8 = New-Object System.Text.UTF8Encoding $false
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('forge-worktrees-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
$passes = 0; $failures = 0
$release = ([regex]::Match([IO.File]::ReadAllText((Join-Path $root 'docs/CHANGELOG.md')), '(?m)^##\s+(\d+\.\d+\.\d+)')).Groups[1].Value
$python = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python -ErrorAction Stop }
$realGit = (Get-Command git).Source
function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:passes++; Write-Host "PASS: $Message" }
    else { $script:failures++; Write-Host "FAIL: $Message" }
}
function Write-Text([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, $script:utf8)
}
function Read-Text([string]$Path) { if ([IO.File]::Exists($Path)) { return [IO.File]::ReadAllText($Path) }; return '' }
function Quote-PS([string]$Value) { return "'" + [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Value) + "'" }
function Invoke-Setup([string]$Target, [string]$Log, [hashtable]$Options, [ValidateRange(1,300)][int]$TimeoutSeconds = 300) {
    $command = 'Set-Location -LiteralPath ' + (Quote-PS $Target) + '; & ' + (Quote-PS $script:setup)
    foreach ($key in $Options.Keys) {
        if ($Options[$key] -is [bool]) { $command += ' -' + $key + ':$' + $Options[$key].ToString().ToLowerInvariant() }
        else { $command += ' -' + $key + ' ' + (Quote-PS ([string]$Options[$key])) }
    }
    $command += '; exit $LASTEXITCODE'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    if (-not (Get-Variable setupTransportRoot -Scope Script -ErrorAction SilentlyContinue)) {
        $script:setupTransportRoot = if ($env:RUNNER_TEMP) {
            Join-Path $env:RUNNER_TEMP 'forge-windows-powershell51/setup-transport'
        } else { Join-Path ([IO.Path]::GetTempPath()) ('forge-setup-transport-' + [Guid]::NewGuid().ToString('N')) }
    }
    $capture = Join-Path $script:setupTransportRoot ([Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($capture) | Out-Null
    $stdout = Join-Path $capture 'stdout.txt'; $stderr = Join-Path $capture 'stderr.txt'
    $encoding = [Console]::OutputEncoding
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $process = $null; $code = $null; $timedOut = $false; $failure = $null
    Write-Host "SETUP_START path=$Target log=$Log capture=$capture utc=$([DateTime]::UtcNow.ToString('o'))"
    try {
        $process = Start-Process -FilePath $script:runtime -ArgumentList @('-NoProfile','-NonInteractive','-OutputFormat','Text','-EncodedCommand',$encoded) -WorkingDirectory $Target -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        # Cache immediately: native5.1 otherwise can expose a null ExitCode.
        $processHandle = $process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            $childId = $process.Id
            $tree = @()
            try {
                if ($env:OS -eq 'Windows_NT') {
                    $all = @(Get-CimInstance Win32_Process -OperationTimeoutSec 5 | Select-Object ProcessId, ParentProcessId, Name, CreationDate, CommandLine)
                } else {
                    $all = @(& ps -axo 'pid=,ppid=,command=' | ForEach-Object {
                        if ($_ -match '^\s*(\d+)\s+(\d+)\s+(.*)$') {
                            [pscustomobject]@{ProcessId=[int]$Matches[1];ParentProcessId=[int]$Matches[2];CommandLine=$Matches[3]}
                        }
                    })
                }
                $ids = @($childId)
                do {
                    $next = @($all | Where-Object { $_.ParentProcessId -in $ids -and $_.ProcessId -notin $ids })
                    $ids += @($next | ForEach-Object { $_.ProcessId })
                } while ($next.Count)
                $tree = @($all | Where-Object { $_.ProcessId -in $ids })
            } catch { [IO.File]::WriteAllText((Join-Path $capture 'process-tree-error.txt'), $_.Exception.Message) }
            [IO.File]::WriteAllText((Join-Path $capture 'process-tree.json'), (ConvertTo-Json -InputObject $tree -Depth 4))
            if (-not $process.HasExited) {
                if ($env:OS -eq 'Windows_NT') {
                    $previousPreference = $ErrorActionPreference
                    try { $ErrorActionPreference = 'Continue'; & taskkill.exe /PID $childId /T /F 2>&1 | Out-Host }
                    finally { $ErrorActionPreference = $previousPreference }
                } else { $process.Kill($true) }
            }
            if (-not $process.WaitForExit(5000)) { throw "disposable setup child did not stop: $childId" }
        } else {
            $code = $process.ExitCode
            if ($null -eq $code) { throw 'setup child exit code unavailable; refusing to treat null as zero' }
        }
    } catch { $failure = $_ }
    finally {
        $timer.Stop()
        $elapsed = $timer.Elapsed.TotalSeconds.ToString('F3', [Globalization.CultureInfo]::InvariantCulture)
        $observations = @("console_output_encoding=$($encoding.WebName)", "console_output_codepage=$($encoding.CodePage)")
        $decoded = @()
        foreach ($path in @($stdout, $stderr)) {
            $bytes = if ([IO.File]::Exists($path)) { [IO.File]::ReadAllBytes($path) } else { [byte[]]@() }
            # ReadAllText detects BOMs; without one, use the console encoding.
            $text = if ($bytes.Length) { [IO.File]::ReadAllText($path, $encoding) } else { '' }
            $prefix = (($bytes | Select-Object -First 16 | ForEach-Object { $_.ToString('x2') }) -join '')
            $name = [IO.Path]::GetFileName($path)
            $observations += "$name captured_file_bytes=$($bytes.Length) prefix_hex=$prefix clixml_headers=$([regex]::Matches($text, '#< CLIXML').Count) decode=bom-or-console"
            $decoded += $text
            if ($text) { Write-Host $text }
        }
        [IO.File]::WriteAllText($Log, ($decoded -join [Environment]::NewLine), (New-Object Text.UTF8Encoding $false))
        $status = if ($timedOut) { 'timeout' } elseif ($null -eq $code) { 'unknown' } else { [string]$code }
        $observations += "exit=$status elapsed_s=$elapsed timeout_s=$TimeoutSeconds"
        [IO.File]::WriteAllLines((Join-Path $capture 'observation.txt'), $observations)
        Write-Host "SETUP_END path=$Target exit=$status elapsed_s=$elapsed capture=$capture utc=$([DateTime]::UtcNow.ToString('o'))"
        if ($process) { $process.Dispose() }
    }
    if ($timedOut) { throw "SETUP_TIMEOUT after $TimeoutSeconds seconds; retained evidence: $capture" }
    if ($failure) { throw $failure }
    return $code
}
function Get-GitRoot([string]$Path) {
    # Capture Git's UTF-8 bytes instead of Windows5.1 console-code-page decoding.
    $metadata = Join-Path $script:tmp 'git-root.txt'
    & $script:python.Source -c 'import subprocess,sys;open(sys.argv[2],''wb'').write(subprocess.check_output([''git'',''-C'',sys.argv[1],''rev-parse'',''--show-toplevel'']))' $Path $metadata
    if ($LASTEXITCODE -ne 0) { throw "Git root lookup failed: $Path" }
    return ([IO.File]::ReadAllText($metadata)).TrimEnd([char[]]"`r`n")
}
function New-Fixture([string]$Name) {
    $base = Join-Path $script:tmp $Name
    $script:primary = Join-Path $base 'primary project'
    $script:link = Join-Path $base 'linked café'
    $script:sibling = Join-Path $base 'other checkout'
    [IO.Directory]::CreateDirectory($script:primary) | Out-Null
    & git -C $script:primary init -q
    & git -C $script:primary config user.name Fixture
    & git -C $script:primary config user.email fixture@example.invalid
    Write-Text (Join-Path $script:primary 'app.txt') "application`n"
    Write-Text (Join-Path $script:primary 'package.json') '{"name":"fixture"}'
    & git -C $script:primary add .
    & git -C $script:primary commit -qm seed
    & git -C $script:primary worktree add -qb fixture-link $script:link
    & git -C $script:primary worktree add -qb fixture-sibling $script:sibling
    # Use Git's physical spelling without native pipeline encoding loss.
    $script:primary = Get-GitRoot $script:primary
    $script:link = Get-GitRoot $script:link
    $script:sibling = Get-GitRoot $script:sibling
    return $base
}
$snapshotCode = @'
import hashlib,os,sys
h=hashlib.sha256()
for root,dirs,files in os.walk(sys.argv[1]):
 dirs.sort()
 for name in sorted(files):
  p=os.path.join(root,name);h.update(os.path.relpath(p,sys.argv[1]).encode());h.update(open(p,'rb').read())
print(h.hexdigest())
'@
function Get-Snapshot([string]$Path) { return (& $script:python.Source -c $script:snapshotCode $Path).Trim() }
$canonicalCode = @'
from pathlib import Path
import sys
s,t=map(Path,sys.argv[1:])
for line in (s/'manifests/managed-v6.tsv').read_text().splitlines():
 if not line or line.startswith('#'):continue
 kind,src,dest,platform,*_=line.split('\t')
 if kind=='canonical' and platform in ('all','windows'):
  assert (t/dest).read_bytes()==(s/src).read_bytes(),dest
'@
function Test-Canonical([string]$Path) {
    & $script:python.Source -c $script:canonicalCode $script:root $Path 2>$null
    return ($LASTEXITCODE -eq 0)
}
# Unauthenticated deterministic probes avoid native installation dependencies.
$initialPath = $env:PATH
$fixtureBin = Join-Path $tmp 'fixture-bin'
foreach ($hostName in @('claude','codex')) {
    if ($env:OS -eq 'Windows_NT') {
        Write-Text (Join-Path $fixtureBin "$hostName.cmd") "@echo off`r`nexit /b 127`r`n"
    } else {
        Write-Text (Join-Path $fixtureBin $hostName) "#!/bin/sh`nexit 127`n"
        & chmod +x (Join-Path $fixtureBin $hostName)
    }
}
$env:PATH = $fixtureBin + [IO.Path]::PathSeparator + $env:PATH
try {
    $literalProject = 'Shared ' + [char]0x2019 + 'project' + [char]0x2019
    foreach ($main in @('claude','codex')) {
        $base = New-Fixture $main
        $roots = @($primary, $link, $sibling)
        foreach ($target in $roots) {
            Write-Text (Join-Path $target '.forge/local/state.md') ((Read-Text (Join-Path $root 'state.template.md')) + "`nhost=$main`nactive workflow bytes`n")
            Write-Text (Join-Path $target '.forge/local/memory/notes.md') 'local memory'
            Write-Text (Join-Path $target '.forge/memory/notes.md') 'durable memory'
            Write-Text (Join-Path $target 'AGENTS.md') 'user instructions'
            Write-Text (Join-Path $target 'app.txt') "dirty application`n"
        }
        $branches = (& git -C $primary for-each-ref '--format=%(refname) %(objectname)' refs/heads) -join "`n"
        $log = Join-Path $tmp "$main-install.log"
        Assert-True ((Invoke-Setup $link $log @{Project=$literalProject;Tech='typescript';WithPlaywright=$true}) -eq 0) "$main-main linked default succeeds"
        $result = @((Read-Text $log) -split "`r?`n" | Where-Object { $_ -match 'WORKTREE_RESULT' })
        Assert-True ($result.Count -gt 0 -and $result[0].Contains($primary)) 'primary result first'
        foreach ($target in $roots) {
            Assert-True ((Read-Text (Join-Path $target '.forge/version')).Trim() -eq $release) "exact installed release: $target"
            Assert-True (Test-Canonical $target) 'canonical source bytes'
            Assert-True ((Read-Text (Join-Path $target '.forge/local/state.md')).Contains("host=$main")) 'host state preserved'
            Assert-True ((Read-Text (Join-Path $target '.forge/local/memory/notes.md')) -eq 'local memory') 'local memory preserved'
            Assert-True ((Read-Text (Join-Path $target '.forge/memory/notes.md')) -eq 'durable memory') 'durable memory preserved'
            Assert-True ((Read-Text (Join-Path $target 'AGENTS.md')).Contains('user instructions')) 'project instructions preserved'
            Assert-True ((Read-Text (Join-Path $target 'docs/CHANGELOG.md')).Contains($literalProject)) 'literal typographic project value forwarded'
            Assert-True (Test-Path -LiteralPath (Join-Path $target 'playwright.config.ts')) 'public tech/Playwright options forwarded'
            Assert-True ((Read-Text (Join-Path $target 'app.txt')).Contains('dirty application')) 'app bytes preserved'
        }
        Assert-True (((& git -C $primary for-each-ref '--format=%(refname) %(objectname)' refs/heads) -join "`n") -eq $branches) 'all branches and HEADs preserved'
        foreach ($target in $roots) {
            Write-Text (Join-Path $target '.claude/settings.json') '{"userEntry":"keep"}'
            Write-Text (Join-Path $target '.codex/config.toml') "[profiles.fixture]`nmodel = `"gpt-6-astra`"`n"
        }
        Write-Text (Join-Path $sibling 'playwright.config.ts') '// customized sibling scaffold'
        Write-Text (Join-Path $sibling '.forge/hooks/session-start.ps1') 'stale canonical hook'
        Assert-True ((Invoke-Setup $link (Join-Path $tmp "$main-default.log") @{Tech='typescript';WithPlaywright=$true}) -eq 0) 'repeated default succeeds'
        Assert-True ((Read-Text (Join-Path $sibling 'playwright.config.ts')).Contains('customized sibling scaffold')) 'default mode unchanged, scaffold preserved'
        Assert-True (Test-Canonical $sibling) 'default refreshes canonical hook'
        foreach ($target in $roots) {
            & git -C $target add .
            & git -C $target -c core.hooksPath=/dev/null commit -qm installed
            Write-Text (Join-Path $target 'app.txt') 'uncommitted app work'
            Write-Text (Join-Path $target '.forge/hooks/session-start.ps1') 'stale canonical hook'
        }
        $branches = (& git -C $primary for-each-ref '--format=%(refname) %(objectname)' refs/heads) -join "`n"
        Assert-True ((Invoke-Setup $link (Join-Path $tmp "$main-upgrade.log") @{Upgrade=$true}) -eq 0) 'upgrade propagates'
        foreach ($target in $roots) {
            Assert-True (Test-Canonical $target) 'upgrade source equivalence'
            Assert-True ((Read-Text (Join-Path $target 'app.txt')) -eq 'uncommitted app work') 'upgrade preserves dirty application'
            Assert-True ((Read-Text (Join-Path $target '.claude/settings.json')).Contains('userEntry')) 'Claude config preserved'
            Assert-True ((Read-Text (Join-Path $target '.codex/config.toml')).Contains('model = "gpt-6-astra"')) 'Codex config preserved'
        }
        Assert-True (((& git -C $primary for-each-ref '--format=%(refname) %(objectname)' refs/heads) -join "`n") -eq $branches) 'upgrade preserves branches/HEADs'
        Assert-True (Test-Path -LiteralPath (Join-Path $primary '.codex/hooks.json')) 'primary Codex hooks registered'
        Assert-True ((Read-Text $log).Contains('CODEX_HOOKS: MATERIALIZED primary worktree registration')) 'primary shared registration materialized first'
        Assert-True ((Read-Text $log).Contains('CODEX_HOOKS: BLOCKED linked worktree cannot mutate primary registration')) 'linked setup respects primary registration'
        $before = Get-Snapshot $base
        $previewLog = Join-Path $tmp "$main-preview.log"
        Assert-True ((Invoke-Setup $link $previewLog @{Force=$true;DryRun=$true}) -eq 0) 'repository preview succeeds'
        Assert-True ((Get-Snapshot $base) -eq $before) 'preview preserves every byte including Git metadata'
        Assert-True ((Read-Text $previewLog).Contains('outcome=preview')) 'preview outcome identified'
        Write-Text (Join-Path $primary '.forge/hooks/session-start.ps1') 'stale only primary'
        $before = Get-Snapshot $primary
        Assert-True ((Invoke-Setup $link (Join-Path $tmp "$main-optout.log") @{Upgrade=$true;ThisCheckoutOnly=$true}) -eq 0) 'opt-out succeeds'
        Assert-True ((Get-Snapshot $primary) -eq $before) 'opt-out sibling byte preservation'
        Assert-True ((Invoke-Setup $link (Join-Path $tmp "$main-force.log") @{Force=$true}) -eq 0) 'force forwards to every target'
        Assert-True (Test-Canonical $primary) 'force repairs primary'
        $subdir = Join-Path $link 'subdir'
        [IO.Directory]::CreateDirectory($subdir) | Out-Null
        $before = Get-Snapshot $base
        Assert-True ((Invoke-Setup $subdir (Join-Path $tmp "$main-subdir.log") @{Upgrade=$true}) -ne 0) 'subdirectory fails safely'
        Assert-True ((Get-Snapshot $base) -eq $before) 'subdirectory stops before sibling writes'
    }
    $base = New-Fixture 'partial'
    Write-Text (Join-Path $link '.claude/hooks/session-start.ps1') 'custom user hook'
    $before = Get-Snapshot $link
    $partialLog = Join-Path $tmp 'partial.log'
    Assert-True ((Invoke-Setup $primary $partialLog @{}) -ne 0) 'blocked target overall failure'
    Assert-True ((Get-Snapshot $link) -eq $before) 'blocked target byte preservation'
    Assert-True (Test-Path (Join-Path $primary '.forge/version')) 'primary completes'
    Assert-True (Test-Path (Join-Path $sibling '.forge/version')) 'independent later target completes'
    Assert-True ((Read-Text $partialLog).Contains("path=$link release=$release outcome=blocked")) 'blocked outcome truthful'
    Assert-True ((Read-Text $partialLog).Contains("path=$sibling release=$release outcome=materialized")) 'successful outcome truthful'
    Remove-Item -LiteralPath $link -Recurse -Force
    $missingLog = Join-Path $tmp 'missing.log'
    Assert-True ((Invoke-Setup $primary $missingLog @{Upgrade=$true}) -ne 0) 'missing target overall failure'
    Assert-True (-not (Test-Path -LiteralPath $link)) 'missing target never recreated'
    Assert-True ((Read-Text $missingLog).Contains("path=$link release=$release outcome=missing")) 'missing path identified'
    Assert-True ((Read-Text $missingLog).Contains("path=$sibling release=$release outcome=materialized")) 'later target still processed'
    [IO.Directory]::CreateDirectory($link) | Out-Null
    Write-Text (Join-Path $link 'sentinel') 'registered checkout sentinel'
    $before = Get-Snapshot $link
    $noGitLog = Join-Path $tmp 'no-git.log'
    Assert-True ((Invoke-Setup $primary $noGitLog @{Upgrade=$true}) -ne 0) 'unavailable registered checkout fails overall'
    Assert-True ((Get-Snapshot $link) -eq $before) 'unavailable registered directory never initialized or installed'
    Assert-True ((Read-Text $noGitLog).Contains("path=$sibling release=$release outcome=materialized")) 'independent target continues'
    & git -C $link init -q
    $before = Get-Snapshot $link
    Assert-True ((Invoke-Setup $primary (Join-Path $tmp 'unrelated.log') @{Upgrade=$true}) -ne 0) 'unrelated replacement fails overall'
    Assert-True ((Get-Snapshot $link) -eq $before) 'unrelated replacement untouched'
    $before = Get-Snapshot $base
    $helpLog = Join-Path $tmp 'help.log'
    Assert-True ((Invoke-Setup $primary $helpLog @{Help=$true}) -eq 0) 'help succeeds without discovery'
    Assert-True (-not (Read-Text $helpLog).Contains('WORKTREE_RESULT')) 'help stays single-purpose'
    Assert-True ((Invoke-Setup $primary (Join-Path $tmp 'invalid.log') @{UnknownOption=$true}) -ne 0) 'invalid option rejected'
    Assert-True ((Invoke-Setup $primary (Join-Path $tmp 'global.log') @{Global=$true}) -ne 0) 'retired global option rejected'
    Assert-True ((Get-Snapshot $base) -eq $before) 'help/invalid/global preserve bytes'
    $bin = Join-Path $tmp 'bin'
    if ($env:OS -eq 'Windows_NT') {
        Write-Text (Join-Path $bin 'git.cmd') "@echo off`r`nif `"%1`"==`"worktree`" exit /b 23`r`n`"$realGit`" %*`r`n"
    } else {
        Write-Text (Join-Path $bin 'git') "#!/bin/sh`nif [ `"`$1`" = worktree ]; then exit 23; fi`nexec `"$realGit`" `"`$@`"`n"
        & chmod +x (Join-Path $bin 'git')
    }
    $oldPath = $env:PATH
    $before = Get-Snapshot $primary
    try {
        $env:PATH = $bin + [IO.Path]::PathSeparator + $oldPath
        Assert-True ((Invoke-Setup $primary (Join-Path $tmp 'discovery.log') @{Upgrade=$true}) -ne 0) 'discovery failure blocks setup'
        Assert-True ((Get-Snapshot $primary) -eq $before) 'discovery failure no writes'
    } finally { $env:PATH = $oldPath }
    $bare = Join-Path $tmp 'bare.git'; $bareLink = Join-Path $tmp 'bare-linked'
    & git clone -q --bare $primary $bare
    & git -C $bare worktree add -qb bare-link $bareLink
    $bareLink = Get-GitRoot $bareLink
    Assert-True ((Invoke-Setup $bareLink (Join-Path $tmp 'bare.log') @{Upgrade=$true}) -eq 0) 'bare metadata entry skipped'
    Assert-True (Test-Path (Join-Path $bareLink '.forge/version')) 'actual linked checkout installed'
    Assert-True (-not (Test-Path (Join-Path $bare '.forge'))) 'bare metadata not installed'
    Write-Host "test-setup-worktrees.ps1: $passes passed, $failures failed; runtime $($PSVersionTable.PSVersion)"
} finally {
    $env:PATH = $initialPath
    if ($env:KEEP_TMP -ne '1') { Remove-Item -LiteralPath $tmp -Recurse -Force }
}
if ($failures -gt 0) { exit 1 }
