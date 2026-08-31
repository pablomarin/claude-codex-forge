param(
    [switch]$FixtureMode,
    [switch]$Inventory,
    [switch]$Live,
    [switch]$Validate,
    [switch]$WriteWindowsAttestation,
    [string]$ProjectRoot,
    [string]$Output,
    [string]$Input,
    [string]$EngineDir,
    [string]$ClaudeGoalAuthorization,
    [string]$CodexGoalCapture,
    [string]$WindowsAttestation,
    [ValidateRange(1,86400)][int]$QualificationTimeoutSeconds = 1200
)
$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object Text.UTF8Encoding($false)
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dispatch = Join-Path $root 'scripts\qualify-dispatch-isolation.ps1'
$goal = Join-Path $root 'scripts\qualify-goal-feasibility.ps1'

function Get-Hash([string]$Path) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}
function Get-TextHash([string]$Text) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Utf8NoBom.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}
function Get-Fields([string]$Path) {
    $result=@{}
    foreach($line in [IO.File]::ReadAllLines($Path)){$i=$line.IndexOf('=');if($i -gt 0){$result[$line.Substring(0,$i)]=$line.Substring($i+1)}}
    return $result
}
function Get-CandidateHash([string]$Path) {
    $physical=(Resolve-Path $Path).Path;$common=(& git -C $physical rev-parse --git-common-dir|Select-Object -First 1)
    if(-not [IO.Path]::IsPathRooted($common)){$common=Join-Path $physical $common};$common=(Resolve-Path $common).Path
    $lines=New-Object Collections.Generic.List[string];$lines.Add('forge-runtime-candidate-ps-v1');$lines.Add("root=$physical");$lines.Add("common=$common")
    $lines.Add(((& git -C $physical rev-parse HEAD) -join "`n"));$lines.Add(((& git -C $physical status --porcelain=v2 --untracked-files=all) -join "`n"));$lines.Add(((& git -C $physical diff --binary HEAD) -join "`n"))
    foreach($file in Get-ChildItem -LiteralPath $physical -Recurse -File -Force|Where-Object{$_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/]\.forge[\\/]local[\\/]'}|Sort-Object FullName){$relative=$file.FullName.Substring($physical.Length).TrimStart([char[]]@('\','/')).Replace('\','/');$lines.Add("$relative`t$(Get-Hash $file.FullName)")}
    return Get-TextHash (($lines -join "`n")+"`n")
}
function Test-CandidateClean([string]$Path) {
    $status=@(& git -C $Path status --porcelain --untracked-files=all)
    return $LASTEXITCODE -eq 0 -and $status.Count -eq 0
}
function ConvertTo-QualificationArgument([string]$Value) {
    if($Value.Length -eq 0){return '""'}
    if($Value -notmatch '[\s"]'){return $Value}
    return '"'+(($Value -replace '(\\*)"','$1$1\"') -replace '(\\+)$','$1$1')+'"'
}
function Write-BlockedChild([string]$Path,[string]$Schema,[string]$Reason) {
    $body=@{schema=$Schema;status='BLOCKED';reason=$Reason;evidence_mode='authenticated';source_class='forge-runtime-qualifier'}|ConvertTo-Json -Compress
    [IO.File]::WriteAllText($Path,$body+"`n",$Utf8NoBom)
}
function Invoke-QualificationChild([string[]]$Arguments,[string]$Receipt,[string]$Schema,[int]$TimeoutSeconds) {
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName='powershell.exe';$start.Arguments=(@($Arguments|ForEach-Object{ConvertTo-QualificationArgument $_}) -join ' ')
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $process=New-Object Diagnostics.Process;$process.StartInfo=$start
    try {
        if(-not $process.Start()){Write-BlockedChild $Receipt $Schema 'qualification child failed to start';return 127}
        if(-not $process.WaitForExit($TimeoutSeconds*1000)){
            & taskkill.exe /PID $process.Id /T /F 2>$null|Out-Null
            try{$process.Kill()}catch{};$process.WaitForExit()
            Write-BlockedChild $Receipt $Schema 'qualification child timeout';return 124
        }
        $rc=$process.ExitCode
        if(-not (Test-Path -LiteralPath $Receipt -PathType Leaf)){Write-BlockedChild $Receipt $Schema 'qualification child exited without receipt'}
        return $rc
    } finally {$process.Dispose()}
}
function Test-Regular([string]$Path){return ((Test-Path -LiteralPath $Path -PathType Leaf)-and -not ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint))}
function Test-Child([string]$Path,[string]$Hash,[string]$Schema){
    if(-not (Test-Regular $Path) -or (Get-Hash $Path) -cne $Hash){return $false}
    try{$receipt=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}catch{return $false}
    return ($receipt.schema -ceq $Schema -and $receipt.status -in @('PASS','BLOCKED'))
}
function Test-Final([string]$Path){
    if(-not (Test-Regular $Path)){return $false};$f=Get-Fields $Path
    if($f.format -cne 'forge-runtime-final-v1' -or $f.source_class -cne 'forge-runtime-qualifier' -or $f.evidence_mode -notin @('fixture','inventory','authenticated') -or $f.overall_status -notin @('PASS','BLOCKED')){return $false}
    if(-not (Test-Path (Join-Path $f.project_root '.forge') -PathType Container) -or (Get-CandidateHash $f.project_root) -cne $f.candidate_sha256){return $false}
    $head=(& git -C $f.project_root rev-parse HEAD|Select-Object -First 1);$tree=(& git -C $f.project_root rev-parse 'HEAD^{tree}'|Select-Object -First 1);if($f.git_head -cne $head -or $f.tree_sha -cne $tree){return $false}
    foreach($engine in @('claude','codex')){
        $binary=$f["${engine}_binary_path"];$binaryHash=$f["${engine}_binary_sha256"]
        if($binary -eq 'none'){if($binaryHash -ne 'none'){return $false}}elseif(-not (Test-Regular $binary) -or (Get-Hash $binary) -cne $binaryHash){return $false}
        if(-not (Test-Child $f["${engine}_dispatch_path"] $f["${engine}_dispatch_sha256"] 'forge.dispatch-isolation.v1')){return $false}
        if(-not (Test-Child $f["${engine}_goal_path"] $f["${engine}_goal_sha256"] 'forge.goal-feasibility.v1')){return $false}
    }
    if($f.windows_status -notin @('PASS','PENDING')){return $false}
    if($f.windows_status -eq 'PASS'){
        if(-not (Test-Regular $f.windows_attestation_path) -or (Get-Hash $f.windows_attestation_path) -cne $f.windows_attestation_sha256){return $false};$wf=Get-Fields $f.windows_attestation_path
        if($wf.format -ne 'forge-windows-deterministic-v1' -or $wf.status -ne 'PASS' -or $wf.powershell_major -ne '5' -or $wf.powershell_minor -ne '1' -or $wf.candidate_clean -ne 'true' -or $wf.git_head -ne $head -or $wf.tree_sha -ne $tree -or -not (Test-CandidateClean $f.project_root)){return $false}
    }
    if($f.overall_status -eq 'PASS'){
        if($f.evidence_mode -ne 'authenticated' -or $f.windows_status -ne 'PASS'){return $false}
        $expected=@{
          'claude_dispatch'='authenticated isolated review, exact-id resume, and full-agent worktree investigation passed';'codex_dispatch'='authenticated isolated review, exact-id resume, and full-agent worktree investigation passed';
          'claude_goal'='authenticated Claude native /goal activation, exact resume, budget pause, and stuck oracle passed';'codex_goal'='validated sealed physical operator Codex TUI capture'
        }
        foreach($name in $expected.Keys){$child=Get-Content -LiteralPath $f["${name}_path"] -Raw|ConvertFrom-Json;if($child.status -ne 'PASS' -or $child.reason -cne $expected[$name]){return $false}}
        if(-not (Test-Regular $f.codex_goal_capture_path) -or (Get-Hash $f.codex_goal_capture_path) -cne $f.codex_goal_capture_sha256){return $false}
    }
    return $true
}

if($WriteWindowsAttestation){
    if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1){throw 'Windows deterministic attestation requires Windows PowerShell 5.1'}
    $ProjectRoot=(Resolve-Path $ProjectRoot).Path;if(-not (Test-CandidateClean $ProjectRoot)){throw 'Windows deterministic attestation requires a clean candidate'};$head=(& git -C $ProjectRoot rev-parse HEAD|Select-Object -First 1);$tree=(& git -C $ProjectRoot rev-parse 'HEAD^{tree}'|Select-Object -First 1)
    [IO.File]::WriteAllLines($Output,@('format=forge-windows-deterministic-v1','status=PASS','powershell_major=5','powershell_minor=1','candidate_clean=true',"git_head=$head","tree_sha=$tree"),$Utf8NoBom);exit 0
}
if($Validate){if(Test-Final $Input){exit 0}else{exit 1}}
$selected=0;foreach($flag in @($FixtureMode,$Inventory,$Live)){if($flag){$selected++}};if($selected -ne 1 -or -not $ProjectRoot -or -not $Output){throw 'select exactly one of FixtureMode, Inventory, or Live and provide ProjectRoot/Output'}
$mode=$(if($FixtureMode){'fixture'}elseif($Inventory){'inventory'}else{'authenticated'});$ProjectRoot=(Resolve-Path $ProjectRoot).Path
$parent=Split-Path -Parent $Output;if($parent){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$Output=[IO.Path]::GetFullPath($Output);$bundle="$Output.d";if(Test-Path $bundle){throw 'output bundle already exists'};New-Item -ItemType Directory -Path $bundle|Out-Null
$candidate=Get-CandidateHash $ProjectRoot;$gitHead=(& git -C $ProjectRoot rev-parse HEAD|Select-Object -First 1);$treeSha=(& git -C $ProjectRoot rev-parse 'HEAD^{tree}'|Select-Object -First 1);$children=@{};$binaries=@{}
foreach($engine in @('claude','codex')){
    $binary='';if($EngineDir){$binary=Join-Path $EngineDir "$engine.exe"}else{$command=Get-Command $engine -ErrorAction SilentlyContinue;if($command){$binary=$command.Source}};$binaries[$engine]=$binary
    $dispatchOut=Join-Path $bundle "$engine-dispatch.json";$goalOut=Join-Path $bundle "$engine-goal.json";$children["${engine}_dispatch"]=$dispatchOut;$children["${engine}_goal"]=$goalOut
    if($FixtureMode){
        $dispatchArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$dispatch,'-Engine',$engine,'-ProjectRoot',$ProjectRoot,'-Output',$dispatchOut,'-FixtureMode','-EnginePath',$binary)
        $goalArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$goal,'-Engine',$engine,'-ProjectRoot',$ProjectRoot,'-Output',$goalOut,'-FixtureMode','-EnginePath',$binary)
        $null=Invoke-QualificationChild -Arguments $dispatchArguments -Receipt $dispatchOut -Schema 'forge.dispatch-isolation.v1' -TimeoutSeconds $QualificationTimeoutSeconds
        $null=Invoke-QualificationChild -Arguments $goalArguments -Receipt $goalOut -Schema 'forge.goal-feasibility.v1' -TimeoutSeconds $QualificationTimeoutSeconds
    }else{
        $previous=$env:FORGE_LIVE_QUALIFICATION;if($Live){$env:FORGE_LIVE_QUALIFICATION='1'}else{Remove-Item Env:FORGE_LIVE_QUALIFICATION -ErrorAction SilentlyContinue}
        try{
            $extra=@();if($engine -eq 'claude' -and $ClaudeGoalAuthorization){$extra=@('-Authorization',$ClaudeGoalAuthorization)}elseif($engine -eq 'codex' -and $CodexGoalCapture){$extra=@('-TrustedCapture',$CodexGoalCapture)}
            if($Live){
                $dispatchArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$dispatch,'-Engine',$engine,'-ProjectRoot',$ProjectRoot,'-Output',$dispatchOut)
                $goalArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$goal,'-Engine',$engine,'-ProjectRoot',$ProjectRoot,'-Output',$goalOut)+$extra
                $null=Invoke-QualificationChild -Arguments $dispatchArguments -Receipt $dispatchOut -Schema 'forge.dispatch-isolation.v1' -TimeoutSeconds $QualificationTimeoutSeconds
                $null=Invoke-QualificationChild -Arguments $goalArguments -Receipt $goalOut -Schema 'forge.goal-feasibility.v1' -TimeoutSeconds $QualificationTimeoutSeconds
            }else{
                $dispatchArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$dispatch,'-Engine',$engine,'-ProjectRoot',$ProjectRoot,'-Output',$dispatchOut)
                $goalArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$goal,'-Engine',$engine,'-ProjectRoot',$ProjectRoot,'-Output',$goalOut)+$extra
                $null=Invoke-QualificationChild -Arguments $dispatchArguments -Receipt $dispatchOut -Schema 'forge.dispatch-isolation.v1' -TimeoutSeconds $QualificationTimeoutSeconds
                $null=Invoke-QualificationChild -Arguments $goalArguments -Receipt $goalOut -Schema 'forge.goal-feasibility.v1' -TimeoutSeconds $QualificationTimeoutSeconds
            }
        }finally{if($null -eq $previous){Remove-Item Env:FORGE_LIVE_QUALIFICATION -ErrorAction SilentlyContinue}else{$env:FORGE_LIVE_QUALIFICATION=$previous}}
    }
}
$windowsStatus='PENDING';$windowsPath='none';$windowsHash='none'
if($WindowsAttestation -and (Test-Regular $WindowsAttestation)){$wf=Get-Fields $WindowsAttestation;$head=(& git -C $ProjectRoot rev-parse HEAD|Select-Object -First 1);$tree=(& git -C $ProjectRoot rev-parse 'HEAD^{tree}'|Select-Object -First 1);if($wf.format -eq 'forge-windows-deterministic-v1' -and $wf.status -eq 'PASS' -and $wf.powershell_major -eq '5' -and $wf.powershell_minor -eq '1' -and $wf.candidate_clean -eq 'true' -and $wf.git_head -eq $head -and $wf.tree_sha -eq $tree -and (Test-CandidateClean $ProjectRoot)){$windowsStatus='PASS';$windowsPath=(Resolve-Path $WindowsAttestation).Path;$windowsHash=Get-Hash $windowsPath}}
$overall='BLOCKED';if($mode -eq 'authenticated' -and $windowsStatus -eq 'PASS'){$allPass=$true;foreach($child in $children.Values){try{if((Get-Content -Raw $child|ConvertFrom-Json).status -ne 'PASS'){$allPass=$false}}catch{$allPass=$false}};if($allPass){$overall='PASS'}}
$lines=New-Object Collections.Generic.List[string];foreach($line in @('format=forge-runtime-final-v1','source_class=forge-runtime-qualifier',"evidence_mode=$mode","project_root=$ProjectRoot","candidate_sha256=$candidate","git_head=$gitHead","tree_sha=$treeSha")){$lines.Add($line)}
foreach($engine in @('claude','codex')){$binary=$binaries[$engine];if($binary -and (Test-Regular $binary)){$binary=(Resolve-Path $binary).Path;$binaryHash=Get-Hash $binary}else{$binary='none';$binaryHash='none'};$lines.Add("${engine}_binary_path=$binary");$lines.Add("${engine}_binary_sha256=$binaryHash");foreach($kind in @('dispatch','goal')){$child=$children["${engine}_${kind}"];$lines.Add("${engine}_${kind}_path=$child");$lines.Add("${engine}_${kind}_sha256=$(Get-Hash $child)")}}
if($CodexGoalCapture -and (Test-Regular $CodexGoalCapture)){$capture=(Resolve-Path $CodexGoalCapture).Path;$lines.Add("codex_goal_capture_path=$capture");$lines.Add("codex_goal_capture_sha256=$(Get-Hash $capture)")}else{$lines.Add('codex_goal_capture_path=none');$lines.Add('codex_goal_capture_sha256=none')}
$lines.Add("windows_status=$windowsStatus");$lines.Add("windows_attestation_path=$windowsPath");$lines.Add("windows_attestation_sha256=$windowsHash");$lines.Add("overall_status=$overall");[IO.File]::WriteAllLines($Output,$lines,$Utf8NoBom)
if(-not (Test-Final $Output)){throw 'generated final attestation failed schema validation'};Get-Content $Output;if($overall -eq 'PASS'){exit 0}else{exit 1}
