param([Parameter(Position=0)][string]$Mode, [string]$HostName, [string]$Fixture, [string]$InvocationHash, [string]$ProjectRoot, [string]$RequestedModel)
$ErrorActionPreference = "Stop"
if ($Mode -eq "identity") {
    if ($HostName -eq "claude") {
        if ($RequestedModel -and @("opus", "claude-opus-4-1") -notcontains $RequestedModel) { throw "BLOCKED: unsupported Claude model profile" }
        $event = Get-Content -Raw $Fixture | ConvertFrom-Json
        $model = $event.modelUsage.PSObject.Properties.Name | Select-Object -First 1
        $provider = $event.modelUsage.$model.provider
        @{host="claude"; actual_provider=$provider; actual_model=$model; invocation_hash=$InvocationHash} | ConvertTo-Json -Compress
    } elseif ($HostName -eq "codex") {
        if ($RequestedModel -and $RequestedModel -ne "gpt-5.6-sol") { throw "BLOCKED: unsupported Codex model profile" }
        @{host="codex"; invocation_hash=$InvocationHash} | ConvertTo-Json -Compress
    } else { throw "unknown host" }
} elseif ($Mode -eq "discovery") {
    $rules = @(Get-ChildItem (Join-Path $ProjectRoot ".forge\rules") -Filter "*.md" -File)
    $duplicates = @($rules | Group-Object Name | Where-Object Count -gt 1)
    Write-Host "canonical_rule_count=$($rules.Count)"
    Write-Host "duplicate_rule_count=$($duplicates.Count)"
} elseif ($Mode -eq "live") {
    Write-Host "BLOCKED: live runtime qualification is owned by qualify-dispatch-isolation.ps1"
    exit 13
} else { throw "Usage: verify-runtime.ps1 identity|discovery|live" }
