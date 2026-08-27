# Test-only compatibility adapter for historical v5-path gate fixtures.
$raw=[Console]::In.ReadToEnd();try{$data=$raw|ConvertFrom-Json}catch{$data=$null}
$target=if($data -and $data.cwd){[string]$data.cwd}else{(Get-Location).Path}
$root=git -C $target rev-parse --show-toplevel 2>$null;if(-not $root){$root=$target};$root=([string]$root).Trim()
$legacy=Join-Path $root ".claude\local\state.md";$canonical=Join-Path $root ".forge\local\state.md"
if((Test-Path $legacy -PathType Leaf)-and -not(Test-Path $canonical)){
    New-Item -ItemType Directory -Path (Split-Path -Parent $canonical) -Force|Out-Null
    [IO.File]::WriteAllText($canonical,"<!-- forge:state-schema v6 -->`n"+[IO.File]::ReadAllText($legacy),(New-Object Text.UTF8Encoding($false)))
}
$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$raw|& (Join-Path $repoRoot "hooks\check-workflow-gates.ps1")
exit $LASTEXITCODE
