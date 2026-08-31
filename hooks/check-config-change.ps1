# Validate only Forge-managed config entries. PowerShell 5.1 compatible.
param([string]$Mode = "event", [string]$Root = "")
$ErrorActionPreference = "SilentlyContinue"
$raw = [Console]::In.ReadToEnd(); try { $data = $raw | ConvertFrom-Json } catch { $data = $null }
if (-not $Root -and $data -and $data.cwd) { $Root = [string]$data.cwd }
if (-not $Root) { $Root = (Get-Location).Path }
$top = git -C $Root rev-parse --show-toplevel 2>$null; if ($LASTEXITCODE -eq 0 -and $top) { $Root = $top }
try { $Root = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path } catch { [Console]::Error.WriteLine("FORGE_CONFIG_TAMPERED: invalid project root"); exit 2 }

if ($Mode -ne "boundary") {
    $audit = Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) ".forge\audit.log"
    New-Item -ItemType Directory -Path (Split-Path -Parent $audit) -Force | Out-Null
    $path = if ($data -and $data.file_path) { [string]$data.file_path } else { "" }
    $source = if ($data -and $data.source) { [string]$data.source } else { "unknown" }
    Add-Content -LiteralPath $audit -Value "[$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))] CONFIG_CHANGED: $path (source: $source)"
}

try {
    $claude = Get-Content -LiteralPath (Join-Path $Root ".claude\settings.json") -Raw | ConvertFrom-Json
    $codex = Get-Content -LiteralPath (Join-Path $Root ".codex\hooks.json") -Raw | ConvertFrom-Json
} catch { [Console]::Error.WriteLine("FORGE_CONFIG_TAMPERED: invalid managed JSON"); exit 2 }

$claudeExpected = @{
    "session-start"=@("SessionStart", 'powershell -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.forge/hooks/session-start.ps1"')
    "build-evidence"=@("Stop", 'powershell -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.forge/hooks/build-evidence.ps1"')
    "state-updated"=@("Stop", 'powershell -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.forge/hooks/check-state-updated.ps1"')
    "subagent-review-receipt"=@("SubagentStop", 'powershell -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.forge/hooks/check-subagent-review.ps1"')
    "precompact-memory"=@("PreCompact", 'powershell -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.forge/hooks/pre-compact-memory.ps1"')
    "config-change"=@("ConfigChange", 'powershell -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.forge/hooks/check-config-change.ps1"')
    "bash-safety"=@("PreToolUse", 'powershell -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.forge/hooks/check-bash-safety.ps1"')
    "workflow-gates"=@("PreToolUse", 'powershell -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.forge/hooks/check-workflow-gates.ps1"')
    "auto-approve-local"=@("PermissionRequest", 'powershell -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.forge/hooks/auto-approve-local-writes.ps1"')
    "post-format"=@("PostToolUse", 'powershell -ExecutionPolicy Bypass -File "$CLAUDE_PROJECT_DIR/.forge/hooks/post-tool-format.ps1"')
}
$codexExpected = @{
    "session-start"=@("session_start", ".forge/hooks/lib/codex-worktree-dispatch.sh|session-start.sh")
    "bash-safety"=@("pre_tool_use", ".forge/hooks/lib/codex-worktree-dispatch.sh|check-bash-safety.sh")
    "workflow-gates"=@("pre_tool_use", ".forge/hooks/lib/codex-worktree-dispatch.sh|check-workflow-gates.sh")
    "format"=@("post_tool_use", ".forge/hooks/lib/codex-worktree-dispatch.sh|post-tool-format.sh")
    "subagent-review-receipt"=@("subagent_stop", ".forge/hooks/lib/codex-worktree-dispatch.sh|check-subagent-review.sh")
    "precompact-memory"=@("pre_compact", ".forge/hooks/lib/codex-worktree-dispatch.sh|pre-compact-memory.sh")
    "build-evidence"=@("stop", ".forge/hooks/lib/codex-worktree-dispatch.sh|build-evidence.sh")
    "state-updated"=@("stop", ".forge/hooks/lib/codex-worktree-dispatch.sh|check-state-updated.sh")
}
$rows = New-Object System.Collections.Generic.List[string]
foreach ($event in $claude.hooks.PSObject.Properties) {
    foreach ($group in @($event.Value)) { foreach ($hook in @($group.hooks)) {
        if ($hook.forgeManagedId) { $rows.Add("claude|$($hook.forgeManagedId)|$($event.Name)|$($hook.command)") }
    }}
}
foreach ($event in $codex.hooks.PSObject.Properties) {
    foreach ($hook in @($event.Value)) { if ($hook.forgeManagedId) { $rows.Add("codex|$($hook.forgeManagedId)|$($event.Name)|$(@($hook.command) -join '|')") } }
}
foreach ($pair in @(@("claude",$claudeExpected), @("codex",$codexExpected))) {
    $host=$pair[0]; $expected=$pair[1]
    foreach ($id in $expected.Keys) {
        $want = "$host|$id|$($expected[$id][0])|$($expected[$id][1])"
        $candidates = @($rows | Where-Object { $_ -like "$host|$id|*" })
        if ($candidates.Count -ne 1 -or $candidates[0] -cne $want) { [Console]::Error.WriteLine("FORGE_CONFIG_TAMPERED: $host managed hook changed or duplicated: $id"); exit 2 }
    }
}
$joined = (@($rows | Sort-Object) -join "`n") + "`n"
$sha=[Security.Cryptography.SHA256]::Create(); try { $fingerprint=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($joined)))).Replace("-","").ToLowerInvariant() } finally { $sha.Dispose() }
$installed=Join-Path $Root ".forge\installed-files.tsv"; $installHash="missing"
if (Test-Path -LiteralPath $installed -PathType Leaf) { $installHash=(Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash.ToLowerInvariant() }
$dest=Join-Path $Root ".forge\local\managed-config.fingerprint"; New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
if (Test-Path -LiteralPath $dest -PathType Leaf) {
    $old=@{}; foreach($line in @(Get-Content -LiteralPath $dest)){if($line -match '^([^=]+)=(.*)$'){$old[$matches[1]]=$matches[2]}}
    if ($old["config"] -ne $fingerprint -and $old["install"] -eq $installHash) { [Console]::Error.WriteLine("FORGE_CONFIG_TAMPERED: managed hook fingerprint changed without a Forge install"); exit 2 }
}
$tmp="$dest.tmp.$PID"; [IO.File]::WriteAllText($tmp, "format=forge-managed-config-v1`ninstall=$installHash`nconfig=$fingerprint`n", (New-Object Text.UTF8Encoding($false))); Move-Item -LiteralPath $tmp -Destination $dest -Force
if ($Mode -eq "boundary") { Write-Output "{}" }
exit 0
