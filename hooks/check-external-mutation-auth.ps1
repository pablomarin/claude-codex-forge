# Defense in depth for unattended investigators; never authenticates approval or emits allow.
# Main sessions defer to the human conversation and native host controls.
$ErrorActionPreference = 'SilentlyContinue'
if ($env:FORGE_INVESTIGATION_CHILD -ne '1') { exit 0 }
$raw = [Console]::In.ReadToEnd(); $command = $raw
try { $j = $raw | ConvertFrom-Json; if ($j.tool_input.command) { $command = [string]$j.tool_input.command } elseif ($j.command) { $command = [string]$j.command } } catch {}
if ($command -match 'gh\s+(issue\s+close|pr\s+(merge|create))|git\s+push|npm\s+publish|rm\s+-r(f|\s)|Remove-Item\s+-Recurse|kubectl\s+(apply|delete|patch)|curl\s+-X\s+(POST|PUT|PATCH|DELETE)|mcp__.*(create|update|delete)') {
    [Console]::Error.WriteLine('BLOCKED: return the proposed consequential action to the main session for human approval and agent execution through normal host controls.')
    exit 2
}
exit 0
