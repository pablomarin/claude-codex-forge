param(
 [Parameter(Mandatory=$true)][ValidateSet('claude','codex')][string]$Engine,
 [Parameter(Mandatory=$true)][ValidateSet('review','investigate')][string]$Profile,
 [Parameter(Mandatory=$true)][string]$OutputDir,
 [ValidateSet('','context7')][string]$ReadOnlyServer=''
)
$ErrorActionPreference='Stop'; $Utf8=New-Object Text.UTF8Encoding($false)
$templateRoot = (Resolve-Path (Join-Path $PSScriptRoot '../templates/runtime')).Path
$claudeTemplate = Join-Path $templateRoot 'claude-review-settings.template.json'; $codexTemplate = Join-Path $templateRoot 'codex-review-overrides.template.tsv'
if (-not (Test-Path -LiteralPath $claudeTemplate -PathType Leaf) -or -not (Test-Path -LiteralPath $codexTemplate -PathType Leaf)) { throw 'BLOCKED[capability]: dispatch runtime templates are unavailable' }
foreach($d in @($OutputDir,(Join-Path $OutputDir 'home'),(Join-Path $OutputDir 'primary'),(Join-Path $OutputDir 'codex-home'))) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
& git -C (Join-Path $OutputDir 'primary') init -q; if($LASTEXITCODE -ne 0){throw 'BLOCKED[capability]: cannot create clean primary repository'}
$servers = if($ReadOnlyServer -eq 'context7'){'{"context7":{"type":"http","url":"https://mcp.context7.com/mcp","readOnly":true}}'}else{'{}'}
if ($ReadOnlyServer) { [IO.File]::WriteAllText((Join-Path $OutputDir 'claude-settings.json'),"{`"fastMode`":true,`"enabledPlugins`":{},`"hooks`":{},`"permissions`":{`"allow`":[],`"deny`":[]},`"mcpServers`":$servers}`n",$Utf8) } else { Copy-Item -LiteralPath $claudeTemplate -Destination (Join-Path $OutputDir 'claude-settings.json') -Force }
[IO.File]::WriteAllText((Join-Path $OutputDir 'mcp.json'),"{`"mcpServers`":$servers}`n",$Utf8)
Copy-Item -LiteralPath $codexTemplate -Destination (Join-Path $OutputDir 'codex-overrides.tsv') -Force
$sha=[Security.Cryptography.SHA256]::Create(); try { $joined=@(); foreach($p in @('claude-settings.json','mcp.json','codex-overrides.tsv')){$joined += ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes((Join-Path $OutputDir $p))))).Replace('-','').ToLowerInvariant()}; Write-Output ('config_hash='+($joined -join ':')) } finally {$sha.Dispose()}
