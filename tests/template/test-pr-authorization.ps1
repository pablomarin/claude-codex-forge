$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
python (Join-Path $root 'tests\template\pr-authorization-fixture.py') --powershell
exit $LASTEXITCODE
