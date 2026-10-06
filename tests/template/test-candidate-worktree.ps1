# Candidate identity and freeze bind real primary/linked worktree state.
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$exe=(Get-Process -Id $PID).Path
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('forge-candidate-worktree-'+[Guid]::NewGuid().ToString('N'))
$project=Join-Path $temporary 'project'
$originalPath=$env:PATH
$originalHome=$env:HOME
$passed=0
function Check([bool]$Condition,[string]$Message) { if(!$Condition){throw $Message};$script:passed++;Write-Host "  PASS: $Message" }
function Value([string]$Path,[string]$Key) { return ((Get-Content -LiteralPath $Path|Where-Object {$_ -like "$Key=*"}) -replace ('^'+[regex]::Escape($Key)+'='),'') }
function Invoke-Fingerprint([string]$Worktree,[string]$Mode,[string]$Output) {
    $savedPreference=$ErrorActionPreference
    Push-Location $Worktree
    try {
        $ErrorActionPreference='Continue'
        $text=(& $exe -NoProfile -File (Join-Path $root 'hooks/lib/candidate-fingerprint.ps1') -Mode $Mode -Artifact git:working-tree -WorkflowBaseRef main -WorkflowBaseSha $base -Output $Output 2>&1)-join "`n"
        return @{Rc=$LASTEXITCODE;Text=$text}
    } finally {Pop-Location;$ErrorActionPreference=$savedPreference}
}
try {
    New-Item -ItemType Directory -Path $project -Force|Out-Null
    & git -C $project init -q --initial-branch=main
    $project=(Resolve-Path (& git -C $project rev-parse --show-toplevel)).Path
    & git -C $project config user.name ForgeTest
    & git -C $project config user.email test@example.invalid
    [IO.File]::WriteAllText((Join-Path $project 'app.txt'),"base`n")
    & git -C $project add app.txt
    & git -C $project commit -qm base
    # Isolate readiness checks; this fixture never calls vendor engines.
    $gitBin=Split-Path -Parent (Get-Command git -CommandType Application|Select-Object -First 1).Source
    if($env:OS -eq 'Windows_NT') {
        $systemPath=$env:SystemRoot+'\System32'+[IO.Path]::PathSeparator+$env:SystemRoot+'\System32\WindowsPowerShell\v1.0'
    } else {
        $privateBin=Join-Path $temporary 'bin';New-Item -ItemType Directory -Path $privateBin|Out-Null
        New-Item -ItemType SymbolicLink -Path (Join-Path $privateBin 'git') -Target (Join-Path $gitBin 'git')|Out-Null
        $gitBin=$privateBin;$systemPath='/usr/bin:/bin'
    }
    $env:PATH=$gitBin+[IO.Path]::PathSeparator+$systemPath
    $env:HOME=Join-Path $temporary 'home';New-Item -ItemType Directory -Path $env:HOME|Out-Null
    Push-Location $project
    try { & $exe -NoProfile -File (Join-Path $root 'setup.ps1') -Project Candidate -Tech fullstack *> (Join-Path $temporary 'setup.log');Check ($LASTEXITCODE -eq 0) 'real setup creates canonical primary state' } finally {Pop-Location}
    & git -C $project add -A
    & git -C $project commit -qm installed
    $base=(& git -C $project rev-parse HEAD)
    Add-Content -LiteralPath (Join-Path $project '.git/info/exclude') -Value '.worktrees/'
    $lifecycle=Join-Path $root 'hooks/lib/worktree-lifecycle.ps1'
    Push-Location $project
    try { & $exe -NoProfile -File $lifecycle -Action Create -Kind fix -Name candidate-linked -Base main|Out-Null;Check ($LASTEXITCODE -eq 0) 'sanctioned lifecycle creates linked state' } finally {Pop-Location}
    $linked=(Resolve-Path (Join-Path $project '.worktrees/candidate-linked')).Path
    & git -C $project checkout -qb fix/candidate-primary
    $primaryState=Join-Path $project '.forge/local/state.md'
    $linkedState=Join-Path $linked '.forge/local/state.md'
    Check (-not [IO.Path]::IsPathRooted((& git -C $project rev-parse --git-common-dir))) 'primary Git common directory is relative'
    Check ([IO.Path]::IsPathRooted((& git -C $linked rev-parse --git-common-dir))) 'linked Git common directory is absolute'
    foreach($worktree in @($project,$linked)) {
        [IO.File]::WriteAllText((Join-Path $worktree 'app.txt'),"staged candidate`n")
        & git -C $worktree add app.txt
    }
    foreach($main in @('claude','codex')) {
        $identities=@()
        foreach($worktree in @($project,$linked)) {
            $task=if($worktree -eq $project){'candidate-primary'}else{'candidate-linked'}
            $primaryBeforeLinked=(Get-FileHash -LiteralPath $primaryState).Hash
            Push-Location $worktree
            try {
                & $exe -NoProfile -File (Join-Path $root 'hooks/lib/workflow-state.ps1') activate --host $main --workflow fix-bug --task $task --base-ref main --phase implementation --next-step verify|Out-Null
                Check ($LASTEXITCODE -eq 0) "$main activates $task through the canonical helper"
            } finally {Pop-Location}
            if($worktree -eq $linked) { Check ((Get-FileHash -LiteralPath $primaryState).Hash -ceq $primaryBeforeLinked) "$main linked activation leaves primary state unchanged" }
            $stateHash=(Get-FileHash -LiteralPath $primaryState).Hash
            $identity=Join-Path $worktree ".forge/local/$main.identity"
            $freeze=Join-Path $worktree ".forge/local/$main.candidate"
            $result=Invoke-Fingerprint $worktree identity $identity
            Check ($result.Rc -eq 0) "$main $task identity succeeds: $($result.Text)"
            $result=Invoke-Fingerprint $worktree freeze $freeze
            Check ($result.Rc -eq 0) "$main $task freeze succeeds: $($result.Text)"
            Check ((Value $identity candidate_id) -ceq (Value $freeze candidate_id)) "$main $task identity and freeze certify the same candidate"
            Check ((Value $freeze candidate_state) -ceq 'staged-clean') "$main $task freeze verifies staged-clean content"
            Check ((Get-FileHash -LiteralPath $primaryState).Hash -ceq $stateHash) "$main candidate capture leaves primary state unchanged"
            $identities+=Value $freeze worktree_identity
        }
        Check ($identities[0] -cne $identities[1]) "$main primary and linked candidate identities are distinct"
    }
    $savedState=[IO.File]::ReadAllBytes($linkedState)
    try {
        Copy-Item -LiteralPath $primaryState -Destination $linkedState -Force
        $foreign=Invoke-Fingerprint $linked identity (Join-Path $linked '.forge/local/foreign.identity')
        Check ($foreign.Rc -ne 0 -and $foreign.Text -like '*canonical state belongs to another worktree*') 'linked candidate rejects the primary checkout state'
    } finally {[IO.File]::WriteAllBytes($linkedState,$savedState)}
} finally {
    $env:PATH=$originalPath;$env:HOME=$originalHome
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "PASS: $passed candidate worktree PowerShell assertions"
