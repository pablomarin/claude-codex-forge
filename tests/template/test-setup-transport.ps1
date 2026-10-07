# Windows5.1-compatible transport control; PS7 is portable evidence only.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$runtime = (Get-Process -Id $PID).Path
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'tests/template/test-setup-worktrees.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'owning setup suite does not parse' }
foreach ($name in @('Quote-PS', 'Invoke-Setup')) {
    $function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (-not $function) { throw "missing actual helper $name" }
    Invoke-Expression $function.Extent.Text
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('forge-transport-fixture-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
$setup = Join-Path $tmp 'tiny setup.ps1'
$utf8Bom = New-Object Text.UTF8Encoding $true
$previousEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
$passes = 0; $failures = 0
function Assert-Control([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:passes++; Write-Host "PASS transport: $Message" }
    else { $script:failures++; Write-Host "FAIL transport: $Message" }
}
function Write-Setup([string]$Text) { [IO.File]::WriteAllText($script:setup, $Text, $script:utf8Bom) }
try {
    Write-Setup @'
param([int]$Code = 0, [string]$Value)
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
[Console]::Out.WriteLine(([char]0xFEFF) + "Unicode café 東京 $Value")
[Console]::Out.WriteLine("cwd=$((Get-Location).Path)")
[Console]::Error.WriteLine('stderr-visible')
exit $Code
'@
    $log = Join-Path $tmp 'success.log'
    $result = @(Invoke-Setup $tmp $log @{Code=0;Value="literal café 'value'"})
    Assert-Control ($result.Count -eq 1 -and $result[0] -is [int] -and $result[0] -eq 0) 'successful exit is one integer zero'
    $text = [IO.File]::ReadAllText($log)
    Assert-Control ($text.Contains("Unicode café 東京 literal café 'value'")) 'Unicode and literal option survive decoded assertion log'
    Assert-Control ($text.Contains("cwd=$tmp") -and $text.Contains('stderr-visible')) 'working directory and stderr survive assertion log'
    $result = @(Invoke-Setup $tmp (Join-Path $tmp 'nonzero.log') @{Code=7;Value='negative'})
    Assert-Control ($result.Count -eq 1 -and $result[0] -is [int] -and $result[0] -eq 7) 'nonzero exit remains integer seven'
    Write-Setup @'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
[Console]::Out.WriteLine('stdout-before-volume café')
for ($i = 0; $i -lt 96; $i++) { [Console]::Error.WriteLine(('x' * 1024)) }
[Console]::Error.WriteLine('stderr-after-volume 東京')
[Console]::Out.WriteLine('stdout-after-volume café')
exit 9
'@
    $volumeLog = Join-Path $tmp 'volume.log'
    $result = @(Invoke-Setup $tmp $volumeLog @{})
    $text = [IO.File]::ReadAllText($volumeLog)
    Assert-Control ($result.Count -eq 1 -and $result[0] -eq 9) 'stderr volume does not lose nonzero exit'
    Assert-Control ($text.Length -gt 65536 -and $text.Contains('stderr-after-volume 東京') -and $text.Contains('stdout-after-volume café')) 'large stderr and both stream tails are retained'
    $captures = if (Get-Variable setupTransportRoot -Scope Script -ErrorAction SilentlyContinue) { @(Get-ChildItem -LiteralPath $script:setupTransportRoot -Directory) } else { @() }
    Assert-Control ($captures.Count -ge 3) 'captured stream diagnostics live outside fixture directory'
    if ($captures.Count) {
        $capture = $captures | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
        Assert-Control ((Test-Path (Join-Path $capture.FullName 'stdout.txt')) -and (Test-Path (Join-Path $capture.FullName 'stderr.txt')) -and (Test-Path (Join-Path $capture.FullName 'observation.txt'))) 'separate captured files and encoding observations exist'
    } else { Assert-Control $false 'separate captured files and encoding observations exist' }
    Write-Setup @'
Start-Sleep -Seconds 3
[Console]::Out.WriteLine('partial-before-timeout café')
[Console]::Error.WriteLine('partial-stderr-before-timeout')
Start-Sleep -Seconds 30
exit 7
'@
    $timeoutLog = Join-Path $tmp 'timeout.log'
    $threw = $false
    try { $ignored = Invoke-Setup $tmp $timeoutLog @{} -TimeoutSeconds 10 }
    catch { $threw = $_.Exception.Message -like '*SETUP_TIMEOUT*' }
    Assert-Control $threw 'deadline throws immediately instead of accepting expected-negative exit'
    Assert-Control ((Test-Path $timeoutLog) -and ([IO.File]::ReadAllText($timeoutLog)).Contains('partial-before-timeout')) 'timeout retains partial decoded output'
    $timeoutCapture = if ($captures.Count -or (Get-Variable setupTransportRoot -Scope Script -ErrorAction SilentlyContinue)) { Get-ChildItem -LiteralPath $script:setupTransportRoot -Directory | Sort-Object LastWriteTimeUtc | Select-Object -Last 1 } else { $null }
    Assert-Control ($null -ne $timeoutCapture -and (Test-Path (Join-Path $timeoutCapture.FullName 'process-tree.json'))) 'timeout retains only scoped process-tree metadata'
    $sentinelCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Start-Sleep -Seconds 60'))
    $sentinel = Start-Process -FilePath $runtime -ArgumentList @('-NoProfile','-NonInteractive','-EncodedCommand',$sentinelCommand) -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $tmp 'sentinel.out') -RedirectStandardError (Join-Path $tmp 'sentinel.err')
    $sentinelHandle = $sentinel.Handle
    try {
        Write-Setup @'
Start-Sleep -Seconds 3
$runtime = (Get-Process -Id $PID).Path
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Start-Sleep -Seconds 30'))
$child = Start-Process -FilePath $runtime -ArgumentList @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) -NoNewWindow -PassThru -RedirectStandardOutput 'descendant.out' -RedirectStandardError 'descendant.err'
$handle = $child.Handle
[IO.File]::WriteAllText('descendant.pid', [string]$child.Id)
[Console]::Out.WriteLine('descendant-created')
Start-Sleep -Seconds 30
exit 7
'@
        $threw = $false
        try { $ignored = Invoke-Setup $tmp (Join-Path $tmp 'tree-timeout.log') @{} -TimeoutSeconds 10 }
        catch { $threw = $_.Exception.Message -like '*SETUP_TIMEOUT*' }
        $capture = Get-ChildItem -LiteralPath $script:setupTransportRoot -Directory | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
        $tree = @(ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $capture.FullName 'process-tree.json'))))
        $ids = @($tree | ForEach-Object { $_.ProcessId })
        $pidFile = Join-Path $tmp 'descendant.pid'
        Assert-Control ($threw -and (Test-Path $pidFile)) 'timeout exercises a real descendant tree'
        if (Test-Path $pidFile) {
            $descendantId = [int]([IO.File]::ReadAllText($pidFile))
            Assert-Control ($descendantId -in $ids -and $sentinel.Id -notin $ids -and $PID -notin $ids) 'captured metadata includes descendant and excludes unrelated processes'
            $live = Get-Process -Id $descendantId -ErrorAction SilentlyContinue
            Assert-Control ($null -eq $live -or $live.HasExited) 'disposable descendant is terminated'
        } else { Assert-Control $false 'captured metadata includes descendant and excludes unrelated processes'; Assert-Control $false 'disposable descendant is terminated' }
        Assert-Control (-not $sentinel.HasExited) 'unrelated disposable sentinel survives tree cleanup'
    } finally {
        if (-not $sentinel.HasExited) { $sentinel.Kill(); $ignored = $sentinel.WaitForExit(5000) }
        $sentinel.Dispose()
    }
} finally {
    [Console]::OutputEncoding = $previousEncoding
    Remove-Item -LiteralPath $tmp -Recurse -Force
}
Write-Host "test-setup-transport.ps1: $passes passed, $failures failed; runtime $($PSVersionTable.PSVersion)"
if ($failures) { exit 1 }
