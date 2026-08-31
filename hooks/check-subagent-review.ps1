# One command evaluator shared by Claude and Codex v6 subagent producers.
$ErrorActionPreference = "SilentlyContinue"
$raw = [Console]::In.ReadToEnd()
try { $data = $raw | ConvertFrom-Json } catch { $data = $null }
if (-not $data -or $data.agent_type -ne "forge-v6-producer") { Write-Output "{}"; exit 0 }
$cwd = [string]$data.cwd
$agentType = [string]$data.agent_type
$taskId = [string]$data.agent_id
if (-not $taskId) { $taskId = [string]$data.task_id }
if (-not $cwd -or -not (Test-Path -LiteralPath $cwd -PathType Container)) { [Console]::Error.WriteLine("FORGE_SUBAGENT_REVIEW_BLOCKED: missing trusted cwd"); exit 2 }
$root = git -C $cwd rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or -not $root) { [Console]::Error.WriteLine("FORGE_SUBAGENT_REVIEW_BLOCKED: cwd outside Git"); exit 2 }
try { $root = (Resolve-Path -LiteralPath $root -ErrorAction Stop).Path } catch { exit 2 }
$cap = Join-Path $root ".forge\workflow-capabilities.tsv"
$marker = $false
foreach ($line in @(Get-Content -LiteralPath $cap -ErrorAction SilentlyContinue)) {
    $fields = $line -split "`t"
    if ($fields.Count -ge 7 -and $fields[0] -eq "forge" -and $fields[1] -eq "subagent-review-receipt" -and $fields[2] -eq $agentType -and $fields[5] -eq "forge-subagent-review-v1" -and $fields[6] -eq "claude,codex") { $marker = $true }
}
if (-not $marker) { [Console]::Error.WriteLine("FORGE_SUBAGENT_REVIEW_BLOCKED: v6 producer schema is not installed"); exit 2 }
if ($taskId -notmatch '^[A-Za-z0-9._-]+$') { [Console]::Error.WriteLine("FORGE_SUBAGENT_REVIEW_BLOCKED: invalid task id"); exit 2 }
$head = git -C $root rev-parse HEAD 2>$null
if ($LASTEXITCODE -ne 0 -or -not $head) { [Console]::Error.WriteLine("FORGE_SUBAGENT_REVIEW_BLOCKED: no current HEAD"); exit 2 }
$receiptDir = Join-Path $root ".forge\local\reviews\$taskId"
$ancestors=@((Join-Path $root ".forge"),(Join-Path $root ".forge\local"),(Join-Path $root ".forge\local\reviews"),$receiptDir)
foreach($ancestor in $ancestors){
    if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){[Console]::Error.WriteLine("FORGE_SUBAGENT_REVIEW_BLOCKED: aliased receipt path");exit 2}
}
if(-not (Test-Path -LiteralPath $receiptDir -PathType Container)){[Console]::Error.WriteLine("FORGE_SUBAGENT_REVIEW_BLOCKED: missing receipt directory for $taskId");exit 2}
$physicalReceiptDir=(Resolve-Path -LiteralPath $receiptDir).Path
$expectedPrefix=(Join-Path $root ".forge\local\reviews")+[IO.Path]::DirectorySeparatorChar
if(-not $physicalReceiptDir.StartsWith($expectedPrefix,[StringComparison]::OrdinalIgnoreCase)){[Console]::Error.WriteLine("FORGE_SUBAGENT_REVIEW_BLOCKED: receipt path escapes project-local storage");exit 2}
foreach ($kind in @("spec", "quality")) {
    $receipt = Join-Path $receiptDir "$kind.receipt"
    if (-not (Test-Path -LiteralPath $receipt -PathType Leaf) -or ((Get-Item -LiteralPath $receipt -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { [Console]::Error.WriteLine("FORGE_SUBAGENT_REVIEW_BLOCKED: missing $kind receipt for $taskId"); exit 2 }
    $fields = @{}
    foreach ($line in @(Get-Content -LiteralPath $receipt)) { if ($line -match '^([^=]+)=(.*)$') { $fields[$matches[1]] = $matches[2] } }
    if ($fields["format"] -ne "forge-subagent-review-v1" -or $fields["task_id"] -ne $taskId -or $fields["kind"] -ne $kind -or $fields["verdict"] -ne "clean" -or $fields["head"] -ne $head) { [Console]::Error.WriteLine("FORGE_SUBAGENT_REVIEW_BLOCKED: stale, malformed, or non-clean $kind receipt for $taskId"); exit 2 }
}
Write-Output "{}"
exit 0
