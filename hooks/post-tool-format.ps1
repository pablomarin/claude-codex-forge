# PostToolUse formatter for Claude Write/Edit and Codex apply_patch payloads.
$ErrorActionPreference = "SilentlyContinue"
$raw = [Console]::In.ReadToEnd(); try { $data = $raw | ConvertFrom-Json } catch { Write-Output "{}"; exit 0 }
$tool = if ($data.tool_name) { [string]$data.tool_name } else { [string]$data.tool }
$cwd = if ($data.cwd) { [string]$data.cwd } elseif ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
$root = git -C $cwd rev-parse --show-toplevel 2>$null; if ($LASTEXITCODE -ne 0 -or -not $root) { $root = $cwd }
try { $root = (Resolve-Path -LiteralPath $root -ErrorAction Stop).Path } catch { Write-Output "{}"; exit 0 }
$paths = @()
if ($tool -eq "Write" -or $tool -eq "Edit") { if ($data.tool_input.file_path) { $paths += [string]$data.tool_input.file_path } }
elseif ($tool -eq "apply_patch") {
    $patch = if ($data.tool_input.command) { [string]$data.tool_input.command } elseif ($data.tool_input.patch) { [string]$data.tool_input.patch } else { [string]$data.input }
    foreach ($line in ($patch -split "`r?`n")) { if ($line -match '^\*\*\* (?:Add|Update) File: (.+)$') { $paths += $matches[1] } }
} else { Write-Output "{}"; exit 0 }

foreach ($filePath in @($paths | Select-Object -Unique)) {
    if (-not $filePath -or ("/$filePath/" -match '/\.\./')) { continue }
    $abs = if ([IO.Path]::IsPathRooted($filePath)) { $filePath } else { Join-Path $root $filePath }
    $rootPrefix = $root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if (-not $abs.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
    # Physical-parent containment prevents an in-repository junction/symlink
    # from redirecting formatter writes outside the worktree.
    if ((Test-Path -LiteralPath $abs) -and ((Get-Item -LiteralPath $abs).Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
    $parentPath = Split-Path -Parent $abs
    try { $physicalParent = (Resolve-Path -LiteralPath $parentPath -ErrorAction Stop).Path } catch { continue }
    $physical = Join-Path $physicalParent ([IO.Path]::GetFileName($abs))
    if (-not $physical.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
    $abs = $physical
    $name=[IO.Path]::GetFileName($abs)
    if ($name -like '.env*' -or $name -like '*.key' -or $name -like '*.pem' -or $name -like '*.secret' -or $name -like '*credential*' -or $name -like '*password*' -or $name -like '*.p12' -or $name -like '*.pfx') { continue }
    if ($abs -match '[\\/](?:\.git|node_modules|\.ssh|secrets)[\\/]') { continue }
    $ext=[IO.Path]::GetExtension($abs).ToLowerInvariant()
    if ($ext -eq '.py') {
        $search=Split-Path -Parent $abs; $ruffRoot=$null
        while ($search) { if (Test-Path -LiteralPath (Join-Path $search 'pyproject.toml')) { $ruffRoot=$search; break }; $parent=Split-Path -Parent $search; if ($parent -eq $search) { break }; $search=$parent }
        if ($ruffRoot) { Push-Location $ruffRoot; try { uv run ruff check --fix $abs 2>$null } catch {}; try { uv run ruff format $abs 2>$null } catch {}; Pop-Location }
    } elseif ($ext -in @('.ts','.tsx','.js','.jsx')) { try { npx prettier --write $abs 2>$null } catch {} }
    elseif ($ext -eq '.json' -and $name -ne 'package-lock.json') { try { npx prettier --write $abs 2>$null } catch {} }
}
Write-Output "{}"
exit 0
