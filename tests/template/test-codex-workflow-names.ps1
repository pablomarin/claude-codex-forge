$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('forge-short-names-' + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object System.Text.UTF8Encoding($false)
$names = @('finish-branch', 'fix-bug', 'new-feature', 'prd-create', 'prd-discuss', 'quick-fix', 'review-pr-comments')
function Assert-True([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message }; Write-Host "PASS $Message" }
function Install-Fixture {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts/materialize-adapters.ps1') -RepoRoot $root -Target $temporary *> (Join-Path $temporary 'install.log')
    return $LASTEXITCODE
}
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    & git -C $temporary init -q
    Assert-True ((Install-Fixture) -eq 0) 'fresh materialization succeeds'
    foreach ($name in $names) {
        $skill = Join-Path $temporary ".agents/skills/$name/SKILL.md"
        Assert-True ((Test-Path $skill) -and ([IO.File]::ReadAllText($skill).Contains("name: `"$name`""))) "$name is directly invocable"
    }
    $oldRelative = '.agents/skills/workflow-fix-bug/SKILL.md'
    $old = Join-Path $temporary $oldRelative
    New-Item -ItemType Directory -Path (Split-Path $old) -Force | Out-Null
    [IO.File]::WriteAllText($old, "---`nname: `"workflow-fix-bug`"`nforge-generated: true`ncanonical-path: `".forge/workflows/fix-bug.md`"`n---`nRead the workflow.`n", $utf8)
    $original = [IO.File]::ReadAllText($old)
    $digest = (Get-FileHash $old -Algorithm SHA256).Hash.ToLowerInvariant()
    $receipt = Join-Path $temporary '.forge/installed-files.tsv'
    [IO.File]::AppendAllText($receipt, "$oldRelative`t$digest`t-`n", $utf8)
    Assert-True ((Install-Fixture) -eq 0) 'upgrade succeeds'
    Assert-True (-not (Test-Path $old)) 'proven old wrapper retired'
    Assert-True ((Install-Fixture) -eq 0) 'repeat install succeeds'
    New-Item -ItemType Directory -Path (Split-Path $old) -Force | Out-Null
    [IO.File]::WriteAllText($old, $original + 'Custom edits', $utf8)
    [IO.File]::AppendAllText($receipt, "$oldRelative`t$digest`t-`n", $utf8)
    Assert-True ((Install-Fixture) -eq 0) 'modified old wrapper is preserved'
    Assert-True ([IO.File]::ReadAllText($old).Contains('Custom edits')) 'old custom bytes survive'
    $short = Join-Path $temporary '.agents/skills/fix-bug/SKILL.md'
    [IO.File]::WriteAllText($short, 'Custom short skill', $utf8)
    Assert-True ((Install-Fixture) -ne 0) 'short-name collision blocks'
    Assert-True ([IO.File]::ReadAllText($short) -eq 'Custom short skill') 'short custom bytes survive'
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
