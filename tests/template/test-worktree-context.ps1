# Native event/root comparison is stateless and distinct from a process-only check.
# Synthetic payloads below exercise the contract; they are not live host evidence.
param([switch]$LegacyProcessArguments)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$runtime = (Get-Process -Id $PID).Path
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('forge-worktree-context-' + [Guid]::NewGuid().ToString('N'))
$primary = Join-Path $scratch 'primary'
$linked = Join-Path $scratch ('linked task-' + [char]0x00e9)
$sibling = Join-Path $scratch 'sibling'
$outside = Join-Path $scratch 'outside'
$alias = Join-Path $scratch 'linked-alias'
$utf8 = New-Object Text.UTF8Encoding($false)
$passes = 0; $failures = 0
$oldOptionalLocks = $env:GIT_OPTIONAL_LOCKS
$env:GIT_OPTIONAL_LOCKS = '0'

function Check([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:passes++; Write-Host "PASS $Message" }
    else {
        $script:failures++; Write-Host "FAIL $Message"
        if ($script:lastInvocation) { Write-Host ('DIAGNOSTIC ' + ($script:lastInvocation | ConvertTo-Json -Compress)) }
    }
}
function Get-ExplicitInputOffset([byte[]]$Bytes, [byte[]]$NativePreamble) {
    # Process.Start may already have emitted this UTF-8 BOM through AutoFlush.
    # Keep exactly one prefix instead of adding the fixture's explicit copy too.
    if ($NativePreamble.Length -eq 3 -and $Bytes.Length -ge 3 -and
        ([BitConverter]::ToString($NativePreamble)) -ceq 'EF-BB-BF' -and
        $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { return 3 }
    return 0
}
function Invoke-Script([string]$Root, [string]$Script, [string[]]$Arguments = @(), [string]$InputText = '') {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $runtime
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Script) + $Arguments
    if (-not $LegacyProcessArguments -and $info.PSObject.Properties['ArgumentList']) {
        foreach ($argument in $argv) { $info.ArgumentList.Add($argument) }
    } else {
        $info.Arguments = ($argv | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' '
    }
    $info.WorkingDirectory = $Root
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    # Native hosts send UTF-8 bytes independently of the child's console page.
    $inputBytes = $utf8.GetBytes($InputText)
    $process.StandardInput.Flush()
    $inputOffset = Get-ExplicitInputOffset $inputBytes ($process.StandardInput.Encoding.GetPreamble())
    $process.StandardInput.BaseStream.Write($inputBytes, $inputOffset, $inputBytes.Length - $inputOffset)
    $process.StandardInput.Close()
    $process.WaitForExit()
    $result = [PSCustomObject]@{ Rc = $process.ExitCode; Out = $stdout.Result; Err = $stderr.Result }
    $script:lastInvocation = $result
    $process.Dispose()
    return $result
}
function Get-GitText([string]$Root, [string[]]$Arguments) {
    # Capture raw Git UTF-8, including on Windows PowerShell 5.1.
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = 'git'
    $argv = @('-C', $Root) + $Arguments
    if (-not $LegacyProcessArguments -and $info.PSObject.Properties['ArgumentList']) {
        foreach ($argument in $argv) { $info.ArgumentList.Add($argument) }
    } else { $info.Arguments = ($argv | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' ' }
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $bytes = New-Object IO.MemoryStream
    try {
        $null = $process.Start()
        $copy = $process.StandardOutput.BaseStream.CopyToAsync($bytes)
        $errors = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $null = $copy.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Git metadata failed: $($errors.Result)" }
        return $utf8.GetString($bytes.ToArray()).TrimEnd([char[]]"`r`n")
    } finally { $bytes.Dispose(); $process.Dispose() }
}
function Canonical([string]$Value) {
    if ($env:OS -eq 'Windows_NT') { return $Value.Replace('\', '/').ToLowerInvariant() }
    return $Value
}
function Hex([string]$Value) { return ([BitConverter]::ToString($utf8.GetBytes($Value))).Replace('-', '').ToLowerInvariant() }
function Probe-Command([string]$Path, [string]$RootHex, [string]$Engine = 'powershell.exe') {
    return "$Engine -NoProfile -ExecutionPolicy Bypass -File $Path -Mode probe -ExpectedRootHex $RootHex"
}
function Event([string]$HostName, [object]$Cwd, [string]$Command) {
    $value = @{ host = $HostName; hook_event_name = 'PreToolUse'; tool_name = 'Bash'; tool_input = @{ command = $Command } }
    if ($null -ne $Cwd) { $value.cwd = $Cwd }
    return $value | ConvertTo-Json -Depth 6 -Compress
}
function Write-File([string]$Path, [string]$Text) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}
function Install-Fixture([string]$Root) {
    foreach ($prefix in @('.forge/hooks', 'hooks')) {
        $null = [IO.Directory]::CreateDirectory((Join-Path $Root "$prefix/lib"))
        Copy-Item (Join-Path $repo 'hooks/lib/host-context.ps1') (Join-Path $Root "$prefix/lib/host-context.ps1")
        Copy-Item (Join-Path $repo 'hooks/check-workflow-gates.ps1') (Join-Path $Root "$prefix/check-workflow-gates.ps1")
    }
    Write-File (Join-Path $Root '.forge/local/state.md') "fixture state must remain byte-identical`n"
    Write-File (Join-Path $Root '.forge/local/evidence/candidate.receipt') "fixture receipt must remain byte-identical`n"
    Write-File (Join-Path $Root '.forge/local/managed-config.fingerprint') "fixture fingerprint must remain byte-identical`n"
}
function Snapshot([string]$Root) {
    $lines = New-Object Collections.Generic.List[string]
    foreach ($item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Sort-Object FullName)) {
        if ($item.FullName.StartsWith((Join-Path $Root '.git') + [IO.Path]::DirectorySeparatorChar)) { continue }
        $lines.Add($item.FullName.Substring($Root.Length) + ':' + (Get-FileHash -LiteralPath $item.FullName).Hash)
    }
    $index = Get-GitText $Root @('rev-parse', '--git-path', 'index')
    if (-not [IO.Path]::IsPathRooted($index)) { $index = Join-Path $Root $index }
    $lines.Add('index:' + (Get-FileHash -LiteralPath $index).Hash)
    $lines.Add('head:' + (Get-GitText $Root @('rev-parse', 'HEAD')))
    $lines.Add('refs:' + (Get-GitText $Root @('for-each-ref', '--format=%(refname):%(objectname)')))
    return $lines -join "`n"
}

try {
    # .NET Framework Process.Start uses a BOM-bearing StreamWriter and enables
    # AutoFlush before the fixture writes raw bytes. Model that exact behavior.
    $wire = New-Object IO.MemoryStream
    $writer = [IO.StreamWriter]::new($wire, [Text.UTF8Encoding]::new($true), 1024, $true)
    $writer.AutoFlush = $true
    $explicitBytes = $utf8.GetBytes(([string][char]0xFEFF) + '{"probe":"wire"}')
    $wireOffset = Get-ExplicitInputOffset $explicitBytes ($writer.Encoding.GetPreamble())
    $wire.Write($explicitBytes, $wireOffset, $explicitBytes.Length - $wireOffset)
    $writer.Dispose()
    Check (([BitConverter]::ToString($wire.ToArray())) -ceq ([BitConverter]::ToString($explicitBytes))) 'fixture sends exactly one BOM when the native writer already emitted its preamble'
    $wire.Dispose()
    $null = [IO.Directory]::CreateDirectory($primary)
    & git -C $primary init -q --initial-branch=main
    & git -C $primary config user.name ForgeTest
    & git -C $primary config user.email test@example.invalid
    Write-File (Join-Path $primary 'tracked.txt') "base`n"
    & git -C $primary add tracked.txt
    & git -C $primary commit -qm base
    & git -C $primary worktree add -q -b fix/context-linked $linked
    & git -C $primary worktree add -q -b fix/context-sibling $sibling
    $null = [IO.Directory]::CreateDirectory($outside)
    & git -C $outside init -q
    $originalLinked = $linked
    $originalConsoleEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(28591)
        $primary = Get-GitText $primary @('rev-parse', '--show-toplevel')
        $linked = Get-GitText $linked @('rev-parse', '--show-toplevel')
        $sibling = Get-GitText $sibling @('rev-parse', '--show-toplevel')
        $outside = Get-GitText $outside @('rev-parse', '--show-toplevel')
    } finally { [Console]::OutputEncoding = $originalConsoleEncoding }
    $physicalLinked = Join-Path (Split-Path -Parent $primary) (Split-Path -Leaf $originalLinked)
    Check ((Canonical $linked) -ceq (Canonical $physicalLinked)) 'Git UTF-8 metadata survives a non-UTF-8 console page'
    foreach ($root in @($primary, $linked, $sibling)) { Install-Fixture $root }
    $nested = Join-Path $linked 'nested'
    $null = [IO.Directory]::CreateDirectory($nested)
    $linkType = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
    $null = New-Item -ItemType $linkType -Path $alias -Target $linked
    $expected = Hex (Canonical $linked)
    $beforePrimary = Snapshot $primary
    $beforeLinked = Snapshot $linked
    $beforeSibling = Snapshot $sibling

    # This is the meaningful RED: the old non-ship fast path returns success
    # even though the native event is primary and the intended root is linked.
    $command = Probe-Command '.forge/hooks/lib/host-context.ps1' $expected
    $result = Invoke-Script $linked (Join-Path $primary '.forge/hooks/check-workflow-gates.ps1') @() (Event 'codex' $primary $command)
    Check ($result.Rc -eq 2) "RED regression: primary event versus linked intended root blocks (actual exit $($result.Rc))"
    Check ($result.Err -like '*FORGE_NATIVE_CONTEXT: MISMATCH*') 'mismatch names the native context boundary on stderr'
    Check ($result.Err.Contains((Canonical $primary)) -and $result.Err.Contains((Canonical $linked))) 'mismatch reports actual and intended physical roots'

    $gate = Join-Path $primary '.forge/hooks/check-workflow-gates.ps1'
    $forcedInputRunner = Join-Path $scratch 'force-console-input.ps1'
    $encodingResult = Join-Path $scratch 'input-encoding.txt'
    Write-File $forcedInputRunner "param([string]`$Target, [string]`$EncodingResult, [int]`$CodePage = 28591)`n[Console]::InputEncoding = [Text.Encoding]::GetEncoding(`$CodePage)`ntry { & `$Target } finally { [IO.File]::WriteAllText(`$EncodingResult, [string][Console]::InputEncoding.CodePage) }`nexit `$LASTEXITCODE`n"
    $result = Invoke-Script $linked $forcedInputRunner @($gate, $encodingResult) (Event 'codex' $linked $command)
    Check ($result.Rc -eq 2 -and $result.Err -like '*FORGE_NATIVE_CONTEXT: MATCH*') 'gate decodes raw UTF-8 before a non-UTF-8 console page can corrupt Unicode cwd'
    Check ([IO.File]::ReadAllText($encodingResult) -eq '28591') 'UTF-8 hook input does not mutate the host console input code page'
    $result = Invoke-Script $linked $gate @() (Event 'codex' $linked 'git commit -m approved && git push origin HEAD')
    Check ($result.Rc -eq 2 -and $result.Err -like '*compound ship command blocked*') 'ordinary ASCII shipping input still reaches the workflow gate'
    $bom = [string][char]0xFEFF
    $result = Invoke-Script $linked $forcedInputRunner @($gate, $encodingResult, '65001') ($bom + (Event 'codex' $linked $command))
    Check ($result.Rc -eq 2 -and $result.Err -like '*FORGE_NATIVE_CONTEXT: MATCH*') 'BOM-prefixed native input at code page 65001 reaches the aligned probe'
    Check ([IO.File]::ReadAllText($encodingResult) -eq '65001') 'BOM handling preserves the UTF-8 console input code page'
    $result = Invoke-Script $linked $gate @() ($bom + (Event 'codex' $linked 'git commit -m approved && git push origin HEAD'))
    Check ($result.Rc -eq 2 -and $result.Err -like '*compound ship command blocked*') 'BOM-prefixed ordinary shipping input cannot bypass enforcement'
    $result = Invoke-Script $linked (Join-Path $primary '.forge/hooks/lib/host-context.ps1') @('-Mode', 'probe-event') ($bom + (Event 'codex' $linked $command))
    Check ($result.Rc -eq 2 -and $result.Err -like '*FORGE_NATIVE_CONTEXT: MATCH*') 'probe-event child accepts the native pipe UTF-8 BOM'
    $startupInput = @{ cwd = $linked; source = 'clear' } | ConvertTo-Json -Compress
    $result = Invoke-Script $primary (Join-Path $repo 'hooks/session-start.ps1') @() ($bom + $startupInput)
    Check ($result.Rc -eq 0 -and $result.Out -like '*Current branch: fix/context-linked*') 'SessionStart consumes BOM-prefixed native event input'
    $result = Invoke-Script $primary $gate @() (Event 'codex' $alias $command)
    Check ($result.Rc -eq 2 -and $result.Err -like '*FORGE_NATIVE_CONTEXT: MATCH*') 'alias event resolves to its physical linked worktree'
    $result = Invoke-Script $primary (Join-Path $linked '.forge/hooks/lib/host-context.ps1') @('-Mode', 'prepare-context', '-Worktree', $alias)
    Check ($result.Rc -eq 0 -and $result.Out.Contains($expected)) 'alias preparation encodes its physical linked worktree'
    $faultGate = Join-Path $scratch 'fault/check-workflow-gates.ps1'
    Write-File (Join-Path $scratch 'fault/lib/host-context.ps1') "exit 1`n"
    Copy-Item $gate $faultGate
    foreach ($faultCommand in @($command, ($command + ' && git push origin HEAD'))) {
        $result = Invoke-Script $linked $faultGate @() (Event 'claude' $linked $faultCommand)
        Check ($result.Rc -eq 2) 'helper exit 1 remains a blocking native denial, including compound ship input'
    }
    foreach ($unsafeRoot in @("c:/drive`n", ('c:/drive' + [char]0x1b))) {
        $unsafeHex = Hex $unsafeRoot
        $result = Invoke-Script $linked $gate @() (Event 'codex' $linked (Probe-Command '.forge/hooks/lib/host-context.ps1' $unsafeHex))
        Check ($result.Rc -eq 2 -and $result.Err.Contains('expected=<unavailable>') -and -not $result.Err.Contains($unsafeRoot)) 'native diagnostic rejects drive-root controls before displaying the decoded value'
        $result = Invoke-Script $linked (Join-Path $linked '.forge/hooks/lib/host-context.ps1') @('-Mode', 'check-process', '-ExpectedRootHex', $unsafeHex)
        Check ($result.Rc -eq 2 -and $result.Err.Contains('expected=<unavailable>') -and -not $result.Err.Contains($unsafeRoot)) 'process diagnostic rejects drive-root controls before displaying the decoded value'
    }

    foreach ($hostName in @('claude', 'codex')) {
        foreach ($prefix in @('.forge/hooks', 'hooks')) {
            $gate = Join-Path $primary "$prefix/check-workflow-gates.ps1"
            foreach ($engine in @('powershell.exe', 'pwsh')) {
                $command = Probe-Command "$prefix/lib/host-context.ps1" $expected $engine
                $result = Invoke-Script $primary $gate @() (Event $hostName $linked $command)
                Check ($result.Rc -eq 2 -and $result.Err -like '*FORGE_NATIVE_CONTEXT: MATCH*') "$hostName $prefix $engine aligned event intentionally denies with visible MATCH"
                $result = Invoke-Script $primary $gate @() (Event $hostName $nested $command)
                Check ($result.Rc -eq 2 -and $result.Err -like '*FORGE_NATIVE_CONTEXT: MATCH*') "$hostName $prefix $engine nested event resolves to linked root"
            }
            $bashCommand = "bash $prefix/lib/host-context.sh probe $expected"
            $result = Invoke-Script $primary $gate @() (Event $hostName $linked $bashCommand)
            Check ($result.Rc -eq 2 -and $result.Err -like '*FORGE_NATIVE_CONTEXT: MATCH*') "$hostName $prefix Bash probe is understood by PowerShell gate"
            $result = Invoke-Script $linked $gate @() (Event $hostName $primary $bashCommand)
            Check ($result.Rc -eq 2 -and $result.Err -like '*FORGE_NATIVE_CONTEXT: MISMATCH*') "$hostName $prefix cross-paired Bash mismatch is denied"
        }
        $gate = Join-Path $primary '.forge/hooks/check-workflow-gates.ps1'
        $command = Probe-Command '.forge/hooks/lib/host-context.ps1' $expected
        foreach ($badRoot in @($primary, $sibling, $outside, 'relative/path', (Join-Path $scratch 'missing'))) {
            $result = Invoke-Script $linked $gate @() (Event $hostName $badRoot $command)
            Check ($result.Rc -ne 0) "$hostName rejects mismatched or invalid event root: $badRoot"
        }
        $result = Invoke-Script $linked $gate @() (Event $hostName $null $command)
        Check ($result.Rc -ne 0) "$hostName missing event cwd cannot fall back to process cwd"
    }

    $gate = Join-Path $primary '.forge/hooks/check-workflow-gates.ps1'
    foreach ($badHex in @('xyz', '2', $expected.ToUpperInvariant(), '00', 'ff', ('ab' * 8193), (Hex 'relative/path'), (Hex (Canonical $nested)), (Hex (Join-Path $scratch 'missing')), (Hex '//server/share/not-this-checkout'))) {
        $result = Invoke-Script $linked $gate @() (Event 'codex' $linked (Probe-Command '.forge/hooks/lib/host-context.ps1' $badHex))
        Check ($result.Rc -eq 2 -and $result.Err -like '*FORGE_NATIVE_CONTEXT: MISMATCH*') 'malformed, excessive, or different expected literal is rejected visibly'
    }
    $canonical = Probe-Command '.forge/hooks/lib/host-context.ps1' $expected
    foreach ($badCommand in @(($canonical + ' extra'), ($canonical + '; git push'), ($canonical + "`ngit push"), ($canonical + "`rgit push"), ($canonical + [char]0), ($canonical -replace '-Mode probe', '-Mode probe-event'), ($canonical -replace '-ExpectedRootHex [0-9a-f]+$', '-ExpectedRootHex'))) {
        $result = Invoke-Script $linked $gate @() (Event 'codex' $linked $badCommand)
        Check ($result.Rc -eq 2 -and $result.Err -notlike '*FORGE_NATIVE_CONTEXT: MATCH*') 'malformed or compound probe never bypasses the native boundary'
    }
    $malformed = '{"tool_input":{"command":"' + $canonical + '"},"cwd":'
    $result = Invoke-Script $linked $gate @() $malformed
    Check ($result.Rc -ne 0) 'malformed event JSON containing the probe cannot claim a native match'
    $rawNul = (Event 'codex' $linked $canonical).Replace('"host":', ([string][char]0 + '"host":'))
    $result = Invoke-Script $linked $gate @() $rawNul
    Check ($result.Rc -eq 2 -and $result.Err -notlike '*FORGE_NATIVE_CONTEXT: MATCH*') 'raw NUL in native JSON cannot disappear into a false match'
    $duplicate = '{"cwd":' + (ConvertTo-Json $primary -Compress) + ',"cwd":' + (ConvertTo-Json $linked -Compress) + ',"tool_input":{"command":' + (ConvertTo-Json $canonical -Compress) + '}}'
    $result = Invoke-Script $linked $gate @() $duplicate
    Check ($result.Rc -eq 2 -and $result.Err -like '*MISMATCH*') 'duplicate native cwd cannot select a favorable checkout'
    foreach ($arrayEvent in @(('[' + (Event 'codex' $linked $canonical) + ']'), ('{"cwd":' + (ConvertTo-Json $linked -Compress) + ',"tool_input":[{"command":' + (ConvertTo-Json $canonical -Compress) + '}]}'))) {
        $result = Invoke-Script $linked $gate @() $arrayEvent
        Check ($result.Rc -eq 2 -and $result.Err -like '*MISMATCH*') 'native event and tool input require object shapes'
    }
    foreach ($extendedJson in @((Event 'codex' $linked $canonical).Insert(1, '/* comment */'), ((Event 'codex' $linked $canonical) -replace '}$', ',}'))) {
        $result = Invoke-Script $linked $gate @() $extendedJson
        Check ($result.Rc -eq 2 -and $result.Err -like '*MISMATCH*') 'nonstandard JSON extensions cannot claim a native match'
    }
    foreach ($incidental in @("echo '$canonical'", "printf '%s' 'bash hooks/lib/host-context.sh probe $expected'")) {
        $result = Invoke-Script $linked $gate @() (Event 'codex' $primary $incidental)
        Check ($result.Rc -eq 0 -and $result.Err -notlike '*FORGE_NATIVE_CONTEXT:*') 'incidental probe text retains normal non-shipping behavior'
    }

    foreach ($prefix in @('.forge/hooks', 'hooks')) {
        $helper = Join-Path $linked "$prefix/lib/host-context.ps1"
        $result = Invoke-Script $linked $helper @('-Mode', 'probe', '-ExpectedRootHex', $expected)
        Check ($result.Rc -eq 2 -and ($result.Out + $result.Err) -like '*UNVERIFIED*' -and ($result.Out + $result.Err) -notlike '*FORGE_NATIVE_CONTEXT: MATCH*') "$prefix actually executed probe cannot certify a native hook"
        $result = Invoke-Script $linked $helper @('-Mode', 'check-process', '-ExpectedRootHex', $expected)
        Check ($result.Rc -eq 0 -and ($result.Out + $result.Err) -like '*FORGE_PROCESS_CONTEXT: MATCH*') "$prefix separate process check matches its own physical root"
        Check (($result.Out + $result.Err) -notlike '*FORGE_NATIVE_CONTEXT: MATCH*') "$prefix process check does not certify native alignment"
        $result = Invoke-Script $primary $helper @('-Mode', 'check-process', '-ExpectedRootHex', $expected)
        Check ($result.Rc -ne 0) "$prefix process check catches event/process disagreement"
        $result = Invoke-Script $nested $helper @('-Mode', 'prepare-context', '-Worktree', $linked)
        Check ($result.Rc -eq 0 -and $result.Out -match ('-Mode probe -ExpectedRootHex ' + [regex]::Escape($expected))) "$prefix preparation emits the intended physical root as a hex literal"
        Check ($result.Out -match ('-Mode check-process -ExpectedRootHex ' + [regex]::Escape($expected)) -and @($result.Out.Trim() -split '\r?\n').Count -eq 2) "$prefix preparation emits two separate fixed commands"
        Check ($result.Out -notlike '*FORGE_NATIVE_CONTEXT: MATCH*') "$prefix preparation does not authenticate context"
        foreach ($hostName in @('claude', 'codex')) {
            $result = Invoke-Script $linked $helper @('-Mode', 'hook', '-Host', $hostName) '{"cwd":"ignored","session_id":"not-authority"}'
            Check ($result.Rc -eq 0 -and [string]::IsNullOrWhiteSpace($result.Out)) "$prefix $hostName compatibility hook remains a no-op"
        }
    }
    if ($env:OS -eq 'Windows_NT') {
        $command = Probe-Command '.forge/hooks/lib/host-context.ps1' $expected
        $result = Invoke-Script $primary $gate @() (Event 'claude' $linked.Replace('/', '\').ToUpperInvariant() $command)
        Check ($result.Rc -eq 2 -and $result.Err -like '*FORGE_NATIVE_CONTEXT: MATCH*') 'Windows case and slash aliases normalize to the Git Bash-compatible root token'
    } else { Write-Host 'SKIP native Windows drive/UNC and Git Bash qualification; portable PS7 only' }
    $result = Invoke-Script $linked $gate @() (Event 'codex' $primary 'git status --short')
    Check ($result.Rc -eq 0) 'ordinary non-shipping command keeps existing behavior'
    Check ((Snapshot $primary) -ceq $beforePrimary) 'probes preserve primary files, state, receipts, fingerprint, index and refs'
    Check ((Snapshot $linked) -ceq $beforeLinked) 'probes preserve linked files, state, receipts, fingerprint, index and refs'
    Check ((Snapshot $sibling) -ceq $beforeSibling) 'probes preserve unrelated sibling files and Git state'
} finally {
    $env:GIT_OPTIONAL_LOCKS = $oldOptionalLocks
    if (Test-Path -LiteralPath $alias) { [IO.Directory]::Delete($alias) }
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "worktree context PowerShell: $passes passed, $failures failed"
if ($failures -ne 0) { exit 1 }
