# PreCompact owns only the volatile Forge memory layer. PowerShell 5.1 compatible.
$ErrorActionPreference = "SilentlyContinue"
$raw = [Console]::In.ReadToEnd()
function Exit-ForgeAllow { if ($data.host -eq "codex") { Write-Output "{}" }; exit 0 }
$trigger = "unknown"
$cwd = ""
try {
    $data = $raw | ConvertFrom-Json
    if ($data.trigger) { $trigger = $data.trigger }
    if ($data.cwd) { $cwd = $data.cwd }
} catch {}
$root = $env:CLAUDE_PROJECT_DIR
if (-not $root) { $root = $cwd }
if (-not $root) { $root = (Get-Location).Path }
try {
    $top = git -C $root rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $top) { $root = $top }
} catch {}
try { $root = (Resolve-Path -LiteralPath $root -ErrorAction Stop).Path } catch { Exit-ForgeAllow }
$memoryDir = Join-Path $root ".forge\local\memory"
New-Item -ItemType Directory -Path $memoryDir -Force | Out-Null
$topicFiles = @(Get-ChildItem -LiteralPath $memoryDir -Filter "*.md" -File -ErrorAction SilentlyContinue).Count
[Console]::Error.WriteLine("Pre-compact Forge memory: trigger=$trigger, local=.forge/local/memory, topic_files=$topicFiles")
[Console]::Error.WriteLine("Save volatile drafts only under .forge/local/memory; promote vetted learnings to .forge/memory through review.")
Exit-ForgeAllow
