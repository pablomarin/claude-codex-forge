$ErrorActionPreference='SilentlyContinue'
if($env:FORGE_DISPATCH_MODE){exit 0}
$raw=[Console]::In.ReadToEnd();$command=$raw;try{$j=$raw|ConvertFrom-Json;if($j.tool_input.command){$command=[string]$j.tool_input.command}elseif($j.command){$command=[string]$j.command}}catch{}
if($command-match'gh\s+(issue\s+close|pr\s+merge)|kubectl\s+(apply|delete|patch)|curl\s+-X\s+(POST|PUT|PATCH|DELETE)|mcp__.*(create|update|delete)'){[Console]::Error.WriteLine('BLOCKED: external mutation remains human-executed in Forge v1. Prepare a pending action and ask the developer to run it.');exit 2}
exit 0
