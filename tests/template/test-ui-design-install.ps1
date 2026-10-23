# Actual PowerShell materialization; native Windows 5.1 qualification remains CI-owned.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('forge-ui-design-install-' + [Guid]::NewGuid().ToString('N'))
$project = Join-Path $scratch 'project'
$source = $repo
$utf8 = New-Object Text.UTF8Encoding($false)
$script:passes = 0; $script:failures = 0
function Assert-Ui([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:passes++; Write-Host "PASS $Message" }
    else { $script:failures++; Write-Host "FAIL $Message" }
}
function Read-Ui([string]$Relative) {
    $path = Join-Path $project $Relative
    if (Test-Path -LiteralPath $path) { return [IO.File]::ReadAllText($path) }
    return ''
}
# Independent expectation over the canonical frontmatter, not the install helper.
function Get-ExpectedDescription([string]$Path) {
    $front = [IO.File]::ReadAllText($Path).Split(@('---'), [StringSplitOptions]::None)[1]
    $match = [regex]::Match($front, '(?m)^description:[ \t]*(.*)\r?$')
    $value = $match.Groups[1].Value.Trim()
    if ($value -match '^>[-+]?$') {
        $tail = $front.Substring($match.Index + $match.Length)
        $continuation = [regex]::Match($tail.TrimStart("`r", "`n"), '\A(?:[ \t]+[^\r\n]*(?:\r?\n|$))+').Value
        return (($continuation -split '\r?\n' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }) -join ' ')
    }
    return $value
}
function Assert-Description([string]$Relative, [string]$Expected) {
    $match = [regex]::Match((Read-Ui $Relative), '(?m)^description\s*[:=]\s*(".*")\r?$')
    $actual = if ($match.Success) { ConvertFrom-Json $match.Groups[1].Value } else { '' }
    Assert-Ui ($actual -ceq $Expected) "$Relative keeps the complete canonical discovery description"
}
function Invoke-UiMaterialize {
    & (Join-Path $repo 'scripts\materialize-adapters.ps1') -RepoRoot $source -Target $project -ReleaseVersion '6.0.0' -Scope project *> (Join-Path $scratch 'install.log')
}
try {
    [IO.Directory]::CreateDirectory((Join-Path $project '.claude\agents')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $project '.codex\agents')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $project '.claude\agents\ui-qa.md'), "project UI QA instructions`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $project '.codex\agents\ui-qa.toml'), "name = `"ui-qa`"`ndescription = `"project UI QA config`"`ndeveloper_instructions = `"Project-owned role`"`n", $utf8)
    Invoke-UiMaterialize
    $expected = Get-ExpectedDescription (Join-Path $repo 'skills\ui-design\SKILL.template.md')
    Assert-Description '.claude\skills\ui-design\SKILL.md' $expected
    Assert-Description '.agents\skills\ui-design\SKILL.md' $expected
    Assert-Ui (Test-Path (Join-Path $project '.forge\agents\forge-ui-qa.md')) 'canonical UI QA role installed'
    $expected = Get-ExpectedDescription (Join-Path $repo 'agents\forge-ui-qa.md')
    Assert-Description '.claude\agents\forge-ui-qa.md' $expected
    Assert-Description '.codex\agents\forge-ui-qa.toml' $expected
    $claude = Read-Ui '.claude\agents\forge-ui-qa.md'
    Assert-Ui ($claude.Contains('mcp__playwright__browser_take_screenshot')) 'Claude UI QA can capture visual evidence'
    Assert-Ui ($claude.Contains('mcp__playwright__browser_resize')) 'Claude UI QA can inspect phone and desktop layouts'
    Assert-Ui (-not $claude.Contains('  - Bash')) 'Claude UI QA has no source-reading shell capability'
    Assert-Ui (-not $claude.Contains('mcp__playwright__browser_evaluate')) 'Claude UI QA cannot execute arbitrary page code'
    $codex = Read-Ui '.codex\agents\forge-ui-qa.toml'
    Assert-Ui ($codex.Contains('name = "forge-ui-qa"')) 'Codex discovers the standalone named role'
    Assert-Ui ($codex.Contains('.forge/agents/forge-ui-qa.md')) 'Codex loads canonical role contract'
    Assert-Ui ((Read-Ui '.codex\config.toml').Contains('[mcp_servers.forge_playwright]')) 'Codex UI QA inherits parent browser MCP'
    Assert-Ui ((Read-Ui '.claude\agents\ui-qa.md').Contains('project UI QA instructions')) 'project-owned Claude UI QA preserved'
    Assert-Ui ((Read-Ui '.codex\agents\ui-qa.toml').Contains('project UI QA config')) 'project-owned Codex UI QA preserved'
    $hashes = @{}
    foreach ($relative in @('.claude\skills\ui-design\SKILL.md', '.agents\skills\ui-design\SKILL.md', '.claude\agents\forge-ui-qa.md', '.codex\agents\forge-ui-qa.toml', '.codex\config.toml')) {
        $hashes[$relative] = (Get-FileHash -Algorithm SHA256 (Join-Path $project $relative)).Hash
    }
    Invoke-UiMaterialize
    foreach ($relative in $hashes.Keys) {
        Assert-Ui ((Get-FileHash -Algorithm SHA256 (Join-Path $project $relative)).Hash -ceq $hashes[$relative]) "$relative stable after repeat upgrade"
    }
    Assert-Ui ((Read-Ui '.claude\agents\ui-qa.md').Contains('project UI QA instructions')) 'upgrade preserves project-owned Claude UI QA'
    Assert-Ui ((Read-Ui '.codex\agents\ui-qa.toml').Contains('project UI QA config')) 'upgrade preserves project-owned Codex UI QA'

    # A disposable source copy verifies YAML/TOML quote escaping through real installation.
    $source = Join-Path $scratch 'source'
    [IO.Directory]::CreateDirectory($source) | Out-Null
    Get-ChildItem -LiteralPath $repo -Force | Where-Object { $_.Name -notin @('.git', '.forge', '.worktrees') } | Copy-Item -Destination $source -Recurse -Force
    foreach ($relative in @('skills\ui-design\SKILL.template.md', 'agents\forge-ui-qa.md')) {
        $path = Join-Path $source $relative
        $text = [IO.File]::ReadAllText($path)
        $descriptionPattern = [regex]::new('(?m)^description:[^\r\n]*(?:\r?\n[ \t]+[^\r\n]*)*')
        $text = $descriptionPattern.Replace($text, "description: >-`n  Inspect `"premium`" UI & movement | contrast \ clarity.`n  Use for every user-facing interface.", 1)
        [IO.File]::WriteAllText($path, $text, $utf8)
    }
    Invoke-UiMaterialize
    $expected = 'Inspect "premium" UI & movement | contrast \ clarity. Use for every user-facing interface.'
    foreach ($relative in @('.claude\skills\ui-design\SKILL.md', '.agents\skills\ui-design\SKILL.md', '.claude\agents\forge-ui-qa.md', '.codex\agents\forge-ui-qa.toml')) { Assert-Description $relative $expected }
} catch {
    $script:failures++
    Write-Host "FAIL materialization: $($_.Exception.Message)"
    $log = Join-Path $scratch 'install.log'
    if (Test-Path $log) { Get-Content $log -Tail 16 | Write-Host }
} finally {
    if (Test-Path $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
Write-Host "ui-design-install: $script:passes passed, $script:failures failed"
if ($script:failures) { exit 1 }
exit 0
