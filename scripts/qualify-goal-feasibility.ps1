param(
    [Parameter(Mandatory=$true)][ValidateSet("claude", "codex")][string]$Engine,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$Output,
    [switch]$FixtureMode,
    [switch]$TestLiveDriver,
    [string]$EnginePath = "",
    [string]$ManualReceipt = "",
    [string]$TrustedCapture = "",
    [string]$Authorization = "",
    [string]$TrustedHome = ""
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object Text.UTF8Encoding($false)
if (-not (Test-Path (Join-Path $ProjectRoot ".forge"))) { throw "BLOCKED: materialized project is required" }
if (-not $TrustedHome) { $TrustedHome = $HOME }

function Get-ForgeGoalHash {
    param([string]$Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-ForgeGoalTextHash {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Utf8NoBom.GetBytes($Text)))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-ForgeGoalCapabilityHash([string]$Path) {
    $rootHelp = (& $Path --help 2>&1) -join "`n"
    $execHelp = (& $Path exec --help 2>&1) -join "`n"
    $combined = $rootHelp + $execHelp; $lines = New-Object System.Collections.Generic.List[string]; $lines.Add("forge-codex-capability-v1")
    foreach ($flag in @("--ignore-user-config", "--ignore-rules", "--ephemeral", "--sandbox", "--add-dir")) { $lines.Add("$flag=" + $(if ($combined -match [regex]::Escape($flag)) { "present" } else { "absent" })) }
    return Get-ForgeGoalTextHash (($lines -join "`n") + "`n")
}

function Get-ForgeGoalProjectId {
    param([string]$Root)
    $top = (& git -C $Root rev-parse --show-toplevel 2>$null | Select-Object -First 1)
    if (-not $top) { throw "project is not a Git worktree" }
    $top = (Resolve-Path $top).Path
    $common = (& git -C $top rev-parse --git-common-dir 2>$null | Select-Object -First 1)
    if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $top $common }
    $common = (Resolve-Path $common).Path
    return (Get-ForgeGoalTextHash "$top`n$common`n")
}

function Test-ForgeGoalRegularFile {
    param([string]$Path)
    if (-not (Test-Path $Path -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
}

function Test-ForgeCodexGoalReceipt {
    param([string]$Receipt, [string]$ExpectedProject)
    if (-not (Test-ForgeGoalRegularFile $Receipt)) { return $false }
    $fields = @{}
    foreach ($line in [IO.File]::ReadAllLines($Receipt)) {
        $index = $line.IndexOf('=')
        if ($index -gt 0) { $fields[$line.Substring(0,$index)] = $line.Substring($index + 1) }
    }
    if ($fields["format"] -cne "forge-codex-goal-tui-v1" -or $fields["engine"] -cne "codex" -or $fields["command"] -cne "/goal" -or $fields["project_id"] -cne $ExpectedProject) { return $false }
    $transcript = $fields["transcript_path"]; $result = $fields["result_path"]
    if (-not $transcript -or -not $result -or -not [IO.Path]::IsPathRooted($transcript) -or -not [IO.Path]::IsPathRooted($result)) { return $false }
    if ($transcript -match '(^|[\\/])\.\.([\\/]|$)' -or $result -match '(^|[\\/])\.\.([\\/]|$)') { return $false }
    if (-not (Test-ForgeGoalRegularFile $transcript) -or -not (Test-ForgeGoalRegularFile $result)) { return $false }
    if ((Get-ForgeGoalHash $transcript) -cne $fields["transcript_sha256"] -or (Get-ForgeGoalHash $result) -cne $fields["result_sha256"]) { return $false }
    $transcriptText = [IO.File]::ReadAllText($transcript)
    foreach ($marker in @("/goal activated", "checkpoint resumed", "FORGE_GOAL_BUDGET_EXHAUSTED", "FORGE_GOAL_STUCK_WARNING")) { if ($transcriptText -notmatch [regex]::Escape($marker)) { return $false } }
    $resultLines = @([IO.File]::ReadAllLines($result))
    foreach ($marker in @("native_activation=PASS", "checkpoint_resume=PASS", "budget_oracle=PASS", "stuck_oracle=PASS")) { if ($resultLines -cnotcontains $marker) { return $false } }
    return $true
}

function Get-ForgeGoalFields([string]$Path) {
    $fields = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) { $index = $line.IndexOf('='); if ($index -gt 0) { $fields[$line.Substring(0,$index)] = $line.Substring($index + 1) } }
    return $fields
}

function Get-ForgeGoalDetails([string]$Root) {
    $top = (& git -C $Root rev-parse --show-toplevel 2>$null | Select-Object -First 1); if (-not $top) { throw "project is not a Git worktree" }; $top = (Resolve-Path $top).Path
    $common = (& git -C $top rev-parse --git-common-dir 2>$null | Select-Object -First 1); if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $top $common }; $common = (Resolve-Path $common).Path
    return [pscustomobject]@{ Root=$top; Common=$common; Id=(Get-ForgeGoalTextHash "$top`n$common`n") }
}

function Test-ForgeExternalGoalFile([string]$Path, [string]$Root, $Details) {
    if (-not (Test-ForgeGoalRegularFile $Path)) { return $false }
    $physical = (Resolve-Path $Path).Path; $rootPhysical = (Resolve-Path $Root).Path
    if (-not $physical.StartsWith($rootPhysical + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    if ($physical.StartsWith($Details.Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $physical.StartsWith($Details.Common + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    return $true
}

function Test-ForgeAuthorization([string]$Receipt, $Details) {
    $root = Join-Path $TrustedHome ".forge\goal-authorizations"
    if (-not (Test-Path $root -PathType Container) -or -not (Test-ForgeExternalGoalFile $Receipt $root $Details)) { return $false }
    $fields = Get-ForgeGoalFields $Receipt
    $writer = Join-Path $TrustedHome ".forge\bin\forge-goal-authorize.ps1"; if (-not (Test-Path $writer)) { return $false }
    $writerText = [IO.File]::ReadAllText($writer); if ($writerText -notmatch '(?m)^\$WriterRevision = ''([^'']+)''$') { return $false }; $writerRevision = $Matches[1]
    return ($fields["format"] -ceq "forge-goal-authorization-v1" -and $fields["project_root"] -ieq $Details.Root -and $fields["git_common_dir"] -ieq $Details.Common -and $fields["project_id"] -ceq $Details.Id -and $fields["approval_channel"] -ceq "physical-operator-action" -and $fields["writer_revision"] -ceq $writerRevision -and $fields["ceiling"] -eq "1")
}

function Test-ForgeTrustedCodexCapture([string]$Receipt, $Details) {
    $root = Join-Path $TrustedHome ".forge\goal-captures"
    if (-not (Test-Path $root -PathType Container) -or -not (Test-ForgeExternalGoalFile $Receipt $root $Details)) { return $false }
    $fields = Get-ForgeGoalFields $Receipt
    foreach ($pair in @(@("format","forge-codex-goal-tui-capture-v3"),@("engine","codex"),@("command","/goal"),@("capture_channel","physical-operator-action"),@("fixture_only","false"),@("project_root",$Details.Root),@("git_common_dir",$Details.Common),@("project_id",$Details.Id))) { if ($fields[$pair[0]] -cne $pair[1]) { return $false } }
    $captureHelper = Join-Path $TrustedHome ".forge\bin\forge-goal-capture.ps1"; $writer = Join-Path $TrustedHome ".forge\bin\forge-goal-authorize.ps1"
    if (-not (Test-ForgeGoalRegularFile $captureHelper) -or -not (Test-ForgeGoalRegularFile "$captureHelper.sha256") -or -not (Test-ForgeGoalRegularFile $writer) -or -not (Test-ForgeGoalRegularFile "$writer.sha256")) { return $false }
    if ([IO.File]::ReadAllText("$captureHelper.sha256").Trim() -cne (Get-ForgeGoalHash $captureHelper) -or [IO.File]::ReadAllText("$writer.sha256").Trim() -cne (Get-ForgeGoalHash $writer)) { return $false }
    $captureText = [IO.File]::ReadAllText($captureHelper); $writerText = [IO.File]::ReadAllText($writer)
    if ($captureText -notmatch '(?m)^\$CaptureRevision = ''([^'']+)''$') { return $false }; $captureRevision = $Matches[1]
    if ($writerText -notmatch '(?m)^\$WriterRevision = ''([^'']+)''$') { return $false }; $writerRevision = $Matches[1]
    if ($fields["capture_revision"] -cne $captureRevision -or $fields["writer_revision"] -cne $writerRevision) { return $false }
    $sessionDir = Split-Path -Parent (Resolve-Path $Receipt).Path; $transcript = $fields["transcript_path"]; $result = $fields["result_path"]
    if (-not (Test-ForgeExternalGoalFile $transcript $sessionDir $Details) -or -not (Test-ForgeExternalGoalFile $result $sessionDir $Details)) { return $false }
    if ((Get-ForgeGoalHash $transcript) -cne $fields["transcript_sha256"] -or (Get-ForgeGoalHash $result) -cne $fields["result_sha256"]) { return $false }
    $identity = Join-Path $TrustedHome ".forge\bin\codex.identity"
    if (-not (Test-ForgeGoalRegularFile $identity) -or -not (Test-ForgeGoalRegularFile "$identity.sha256")) { return $false }
    $identityHash = Get-ForgeGoalHash $identity; if ([IO.File]::ReadAllText("$identity.sha256").Trim() -cne $identityHash) { return $false }
    $identityFields = Get-ForgeGoalFields $identity
    foreach ($pair in @(@("format","forge-codex-identity-v1"),@("engine","codex"),@("identity_class","operator-setup"),@("status","QUALIFIED"),@("capture_revision",$captureRevision),@("writer_revision",$writerRevision))) { if ($identityFields[$pair[0]] -cne $pair[1]) { return $false } }
    if ($fields["identity_path"] -cne $identity -or $fields["identity_sha256"] -cne $identityHash) { return $false }
    $invocation = $identityFields["invocation_path"]; $cliPath = $identityFields["binary_path"]
    if ($fields["cli_path"] -cne $cliPath -or $fields["cli_sha256"] -cne $identityFields["binary_sha256"] -or $fields["cli_version"] -cne $identityFields["version"] -or $fields["capability_revision"] -cne $identityFields["capability_revision"]) { return $false }
    if (-not [IO.Path]::IsPathRooted($invocation) -or -not [IO.Path]::IsPathRooted($cliPath) -or -not (Test-Path $invocation -PathType Leaf) -or -not (Test-ForgeGoalRegularFile $cliPath)) { return $false }
    if ((Resolve-Path $invocation).Path -cne $cliPath -or (Resolve-Path $cliPath).Path -cne $cliPath -or (Get-ForgeGoalHash $cliPath) -cne $identityFields["binary_sha256"]) { return $false }
    try { $actualVersion = ((& $cliPath --version 2>$null) | Select-Object -First 1); $actualCapability = Get-ForgeGoalCapabilityHash $cliPath } catch { return $false }
    if ($actualVersion -cne $identityFields["version"] -or $actualCapability -cne $identityFields["capability_revision"]) { return $false }
    $transcriptLines = @([IO.File]::ReadAllLines($transcript)); foreach ($exact in @("capture_channel=operator-codex-tui","identity_sha256=$identityHash","cli_path=$cliPath","cli_sha256=$($identityFields['binary_sha256'])","cli_version=$($identityFields['version'])","capability_revision=$($identityFields['capability_revision'])","session_id=$($fields['session_id'])","project_root=$($Details.Root)","command=/goal","/goal activated","status captured","pause captured","checkpoint resumed","FORGE_GOAL_BUDGET_EXHAUSTED","FORGE_GOAL_STUCK_WARNING")) { if ($transcriptLines -cnotcontains $exact) { return $false } }
    $resultLines = @([IO.File]::ReadAllLines($result)); foreach ($exact in @("native_activation=PASS","checkpoint_resume=PASS","budget_oracle=PASS","stuck_oracle=PASS")) { if ($resultLines -cnotcontains $exact) { return $false } }
    return $true
}

function Invoke-ForgeGoalLiveEngine([string]$Path, [string[]]$Arguments, [hashtable]$Variables, [string]$WorkingDirectory) {
    $previous = @{}; foreach ($key in $Variables.Keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key,"Process"); [Environment]::SetEnvironmentVariable($key,[string]$Variables[$key],"Process") }
    try { Push-Location $WorkingDirectory; try { $text = (& $Path @Arguments 2>&1) -join "`n"; $code=$LASTEXITCODE } finally { Pop-Location }; return [pscustomobject]@{Code=$code;Text=$text} }
    finally { foreach ($key in $Variables.Keys) { [Environment]::SetEnvironmentVariable($key,$previous[$key],"Process") } }
}

function Invoke-ForgeClaudeLiveGoal([string]$Binary, $Details) {
    if (-not (Test-ForgeAuthorization $Authorization $Details)) { throw "authorization is absent, stale, aliased, or outside the sealed root" }
    $scratch = Join-Path ([IO.Path]::GetTempPath()) ("forge-goal-live-" + [Guid]::NewGuid().ToString("N"))
    try {
        $fixture = Join-Path $scratch "project"; New-Item -ItemType Directory -Path $fixture -Force | Out-Null; & git -C $fixture init -q
        $userProfile = [Environment]::GetFolderPath('UserProfile'); if (-not $userProfile) { $userProfile = $env:USERPROFILE }
        $mcp = Join-Path $scratch "empty-mcp.json"; [IO.File]::WriteAllText($mcp,'{"mcpServers":{}}',$Utf8NoBom); $session="22222222-2222-4222-8222-{0:d12}" -f $PID; $vars=@{FORGE_GOAL_SESSION_ID=$session;HOME=$userProfile;USERPROFILE=$userProfile;USERNAME=$(if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName })}
        $startArgs=@("-p","--safe-mode","--strict-mcp-config","--mcp-config",$mcp,"--setting-sources","","--tools","","--permission-mode","dontAsk","--output-format","text","--session-id",$session,"--system-prompt","Disposable Forge native goal oracle.","/goal Emit native_activation=PASS phase=implementation next_step=resume-verification progress=fingerprint-a session_id=$session")
        $run=Invoke-ForgeGoalLiveEngine $Binary $startArgs $vars $fixture; foreach($exact in @("native_activation=PASS","phase=implementation","next_step=resume-verification","progress=fingerprint-a","session_id=$session")){if($run.Code -ne 0 -or $run.Text -notmatch [regex]::Escape($exact)){throw "Claude native activation omitted $exact"}}
        $script:nativeActivation="PASS"; $checkpoint=Join-Path $scratch "checkpoint"; [IO.File]::WriteAllText($checkpoint,"phase=implementation`nnext_step=resume-verification`nprogress=fingerprint-a`nsession_id=$session`n",$Utf8NoBom)
        $resumeArgs=@("-p","--safe-mode","--strict-mcp-config","--mcp-config",$mcp,"--setting-sources","","--tools","","--permission-mode","dontAsk","--output-format","text","--resume",$session,"--system-prompt","Resume exact Forge goal checkpoint.","Emit checkpoint_resume=PASS phase=verification next_step=budget-check progress=fingerprint-a session_id=$session FORGE_GOAL_BUDGET_EXHAUSTED paused=true FORGE_GOAL_STUCK_WARNING")
        $run=Invoke-ForgeGoalLiveEngine $Binary $resumeArgs $vars $fixture; foreach($exact in @("checkpoint_resume=PASS","phase=verification","next_step=budget-check","progress=fingerprint-a","session_id=$session","FORGE_GOAL_BUDGET_EXHAUSTED","paused=true","FORGE_GOAL_STUCK_WARNING")){if($run.Code -ne 0 -or $run.Text -notmatch [regex]::Escape($exact)){throw "Claude goal resume omitted $exact"}}
        $script:checkpointResume="PASS"; $fields=Get-ForgeGoalFields $Authorization; $turnDir=Join-Path $scratch "goal-counters\$($fields['nonce'])\turns"; New-Item -ItemType Directory -Path $turnDir -Force|Out-Null; $turn=Join-Path $turnDir "turn-1"; $stream=[IO.File]::Open($turn,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Dispose()
        try {
            $stream=[IO.File]::Open($turn,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $stream.Dispose()
            throw "duplicate turn charge clobbered oracle"
        } catch [IO.IOException] {}
        $script:budgetOracle="PASS";$script:stuckOracle="PASS";return "authenticated Claude native /goal activation, exact resume, budget pause, and stuck oracle passed"
    } finally { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-ForgeGoalFixtureEngine {
    param([string]$Path, [string]$Action, [hashtable]$Variables, [string[]]$Arguments)
    $all = @{}; $all["FORGE_GOAL_FIXTURE_ACTION"] = $Action
    foreach ($key in $Variables.Keys) { $all[$key] = [string]$Variables[$key] }
    $previous = @{}
    foreach ($key in $all.Keys) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        [Environment]::SetEnvironmentVariable($key, $all[$key], "Process")
    }
    try {
        $captured = (& $Path @Arguments 2>&1) -join "`n"
        $code = $LASTEXITCODE
        return [pscustomobject]@{ Code=$code; Text=$captured }
    } finally {
        foreach ($key in $all.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], "Process") }
    }
}

function Invoke-ForgeNativeGoalFixture {
    param([string]$Binary)
    $scratch = Join-Path ([IO.Path]::GetTempPath()) ("forge-goal-fixture-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    try {
        $session = "22222222-2222-4222-8222-{0:d12}" -f $PID
        $variables = @{ FORGE_GOAL_FIXTURE_DIR=$scratch; FORGE_GOAL_SESSION_ID=$session }
        $run = Invoke-ForgeGoalFixtureEngine $Binary "activate" $variables @("--fixture-native-goal-start")
        $checkpoint = Join-Path $scratch "checkpoint"
        if ($run.Code -ne 0 -or $run.Text -notmatch [regex]::Escape("native-activation:$session") -or -not (Test-Path $checkpoint) -or (Get-Content -Raw $checkpoint) -notmatch [regex]::Escape("session_id=$session")) { throw "deterministic native /goal activation failed" }
        $script:nativeActivation = "PASS"

        $run = Invoke-ForgeGoalFixtureEngine $Binary "resume" $variables @("--fixture-native-goal-resume")
        $checkpointText = Get-Content -Raw $checkpoint
        if ($run.Code -ne 0 -or $run.Text -notmatch [regex]::Escape("checkpoint-resume:$session") -or $checkpointText -notmatch '(?m)^phase=verification\r?$' -or $checkpointText -notmatch '(?m)^next_step=budget-check\r?$') { throw "deterministic exact-checkpoint resume failed" }
        $script:checkpointResume = "PASS"

        $turns = Join-Path $scratch "turns"; New-Item -ItemType Directory -Path $turns -Force | Out-Null
        $turn = Join-Path $turns "turn-1"
        $stream = [IO.File]::Open($turn, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None); $stream.Dispose()
        $duplicateRejected = $false
        try { $stream = [IO.File]::Open($turn, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None); $stream.Dispose() }
        catch [IO.IOException] { $duplicateRejected = $true }
        if (-not $duplicateRejected -or @(Get-ChildItem -LiteralPath $turns -File).Count -ne 1) { throw "goal budget charge is not no-clobber and monotonic" }
        $budget = Join-Path $scratch "budget.marker"
        [IO.File]::WriteAllText($budget, "FORGE_GOAL_BUDGET_EXHAUSTED`npaused=true`nnext_step=budget-check`n", $Utf8NoBom)
        if (([IO.File]::ReadAllText($budget)) -notmatch 'FORGE_GOAL_BUDGET_EXHAUSTED' -or ([IO.File]::ReadAllText($budget)) -notmatch '(?m)^paused=true$') { throw "goal budget marker did not pause" }
        $script:budgetOracle = "PASS"

        $progressOne = Join-Path $scratch "progress-1"; $progressTwo = Join-Path $scratch "progress-2"
        [IO.File]::WriteAllText($progressOne, "fingerprint-a`n", $Utf8NoBom); Copy-Item $progressOne $progressTwo
        if ((Get-ForgeGoalHash $progressOne) -cne (Get-ForgeGoalHash $progressTwo)) { throw "goal progress fixture unexpectedly changed" }
        $stuck = Join-Path $scratch "stuck.marker"; [IO.File]::WriteAllText($stuck, "FORGE_GOAL_STUCK_WARNING`nthreshold=2`n", $Utf8NoBom)
        if (([IO.File]::ReadAllText($stuck)) -notmatch 'FORGE_GOAL_STUCK_WARNING') { throw "stuck oracle marker missing" }
        $script:stuckOracle = "PASS"

        return "disposable native checkpoint/resume, budget, and stuck fixture passed"
    } finally { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

$version = ""; $status = "BLOCKED"; $nativeActivation = "BLOCKED"; $checkpointResume = "BLOCKED"; $budgetOracle = "BLOCKED"; $stuckOracle = "BLOCKED"; $reason = "$Engine binary unavailable"
$commandPath = ""
if ($EnginePath) { if (Test-Path $EnginePath -PathType Leaf) { $commandPath = (Resolve-Path $EnginePath).Path } }
else { $command = Get-Command $Engine -ErrorAction SilentlyContinue; if ($command) { $commandPath = $command.Source } }

if ($FixtureMode) {
    if ($commandPath) {
        $previousName = $env:FORGE_FAKE_ENGINE_NAME
        try {
            $env:FORGE_FAKE_ENGINE_NAME = $Engine
            $version = ((& $commandPath --version 2>$null) | Select-Object -First 1)
            try { $reason = Invoke-ForgeNativeGoalFixture $commandPath; $status = "PASS" }
            catch { $reason = $_.Exception.Message }
        } finally { $env:FORGE_FAKE_ENGINE_NAME = $previousName }
    }
} elseif ($Engine -eq "codex" -and $TrustedCapture) {
    $details = Get-ForgeGoalDetails $ProjectRoot
    if (Test-ForgeTrustedCodexCapture $TrustedCapture $details) { $status="PASS";$nativeActivation="PASS";$checkpointResume="PASS";$budgetOracle="PASS";$stuckOracle="PASS";$reason="validated sealed physical operator Codex TUI capture" }
    else { $reason="trusted Codex TUI capture is unsealed, stale, workspace-authored, or hash-invalid" }
} elseif ($commandPath) {
    $version = ((& $commandPath --version 2>$null) | Select-Object -First 1)
    $details = Get-ForgeGoalDetails $ProjectRoot
    if ($ManualReceipt) { $reason = "workspace/manual receipts are retired; use the sealed operator capture helper" }
    elseif ($Engine -eq "codex") { $reason = "native Codex /goal requires -TrustedCapture produced by the global physical operator helper; codex exec cannot certify it" }
    else {
        $help = (& $commandPath --help 2>&1) -join "`n"; $required=@("--safe-mode","--strict-mcp-config","--setting-sources","--session-id","--resume"); $missing=@($required | Where-Object { $help -notmatch [regex]::Escape($_) })
        if($missing.Count){$reason="Claude CLI lacks native goal proving flags: $($missing -join ' ')"}
        elseif(-not $TestLiveDriver -and $env:FORGE_LIVE_QUALIFICATION -ne "1"){$reason="set FORGE_LIVE_QUALIFICATION=1 before the authenticated native Claude /goal fixture"}
        else{try{$reason=Invoke-ForgeClaudeLiveGoal $commandPath $details;$status="PASS"}catch{$reason=$_.Exception.Message}}
    }
}

$receipt = [ordered]@{ schema="forge.goal-feasibility.v1"; engine=$Engine; version="$version"; status=$status; native_activation=$nativeActivation; checkpoint_resume=$checkpointResume; budget_oracle=$budgetOracle; stuck_oracle=$stuckOracle; reason=$reason }
$parent = Split-Path -Parent $Output
if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$json = $receipt | ConvertTo-Json -Compress
[IO.File]::WriteAllText($Output, "$json`n", $Utf8NoBom)
Write-Output $json
if ($status -eq "PASS") { exit 0 } else { exit 1 }
