param(
    [Parameter(Mandatory=$true)][ValidateSet("claude", "codex")][string]$Engine,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$Output,
    [switch]$FixtureMode,
    [switch]$TestLiveDriver,
    [string]$EnginePath = ""
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object Text.UTF8Encoding($false)
if (-not (Test-Path (Join-Path $ProjectRoot ".forge"))) { throw "BLOCKED: materialized project is required" }
$ProjectRoot = (Resolve-Path $ProjectRoot).Path

function Get-ForgeSha256Bytes {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-ForgeCandidateIdentity {
    param([string]$Root)
    $lines = New-Object Collections.Generic.List[string]
    $lines.Add((& git -C $Root rev-parse HEAD 2>$null) -join "`n")
    $lines.Add((& git -C $Root status --porcelain=v2 --untracked-files=all 2>$null) -join "`n")
    $lines.Add((& git -C $Root diff --binary HEAD 2>$null) -join "`n")
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } | Sort-Object FullName) {
        $relative = $file.FullName.Substring($Root.Length).TrimStart([char[]]@('\','/'))
        $lines.Add("$relative`t$(Get-ForgeSha256Bytes ([IO.File]::ReadAllBytes($file.FullName)))")
    }
    return (Get-ForgeSha256Bytes ($Utf8NoBom.GetBytes(($lines -join "`n"))))
}

function Invoke-ForgeFixtureEngine {
    param([string]$Path, [string]$Action, [hashtable]$Variables, [string[]]$Arguments)
    $all = @{}; $all["FORGE_DISPATCH_FIXTURE_ACTION"] = $Action
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

function Invoke-ForgeDispatchFixture {
    param([string]$Binary)
    $scratch = Join-Path ([IO.Path]::GetTempPath()) ("forge-dispatch-fixture-" + [Guid]::NewGuid().ToString("N"))
    try {
        $candidate = Join-Path $scratch "candidate"
        $investigation = Join-Path $scratch "investigation-worktree"
        New-Item -ItemType Directory -Path (Join-Path $candidate ".agents\skills\canary") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $scratch "sessions") -Force | Out-Null
        & git -C $candidate init -q 2>$null | Out-Null
        & git -C $candidate config core.autocrlf false 2>$null | Out-Null
        & git -C $candidate config user.email forge@example.invalid 2>$null | Out-Null
        & git -C $candidate config user.name Forge 2>$null | Out-Null
        [IO.File]::WriteAllText((Join-Path $candidate "keep.txt"), "keep-base`n", $Utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $candidate "delete.txt"), "delete-base`n", $Utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $candidate "rename-old.txt"), "rename-base`n", $Utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $candidate "script.sh"), "#!/bin/sh`necho base`n", $Utf8NoBom)
        & git -C $candidate add keep.txt delete.txt rename-old.txt script.sh 2>$null | Out-Null
        & git -C $candidate update-index --chmod=+x script.sh 2>$null | Out-Null
        & git -C $candidate commit -qm base 2>$null | Out-Null
        [IO.File]::WriteAllText((Join-Path $candidate "keep.txt"), "keep-candidate`n", $Utf8NoBom)
        Remove-Item -LiteralPath (Join-Path $candidate "delete.txt")
        & git -C $candidate mv rename-old.txt rename-new.txt 2>$null | Out-Null
        [IO.File]::WriteAllText((Join-Path $candidate "AGENTS.md"), "FORGE_CANARY_CANDIDATE_INSTRUCTION`n", $Utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $candidate ".agents\skills\canary\SKILL.md"), "---`nname: canary`ndescription: FORGE_CANARY_SKILL`n---`n", $Utf8NoBom)
        $before = Get-ForgeCandidateIdentity $candidate

        $sentinel = "FORGE_DISPATCH_FIXTURE_$($Engine)_$PID"
        $run = Invoke-ForgeFixtureEngine $Binary "ephemeral" @{ FORGE_DISPATCH_SENTINEL=$sentinel } @("--fixture-ephemeral")
        if ($run.Code -ne 0 -or $run.Text -notmatch [regex]::Escape("ephemeral:$sentinel`:canary=false") -or $run.Text -match 'FORGE_CANARY_') { throw "deterministic ephemeral canary isolation failed" }
        $script:ephemeral = "PASS"

        $sessionId = "11111111-1111-4111-8111-{0:d12}" -f $PID
        $seatHash = Get-ForgeSha256Bytes ($Utf8NoBom.GetBytes("$Engine`n$before`n$sentinel`n"))
        $variables = @{ FORGE_DISPATCH_SESSION_STORE=(Join-Path $scratch "sessions"); FORGE_DISPATCH_SESSION_ID=$sessionId; FORGE_DISPATCH_SEAT_HASH=$seatHash }
        $run = Invoke-ForgeFixtureEngine $Binary "council-start" $variables @("--fixture-council-start")
        if ($run.Code -ne 0 -or $run.Text -notmatch [regex]::Escape($sessionId)) { throw "deterministic council first turn failed" }
        $run = Invoke-ForgeFixtureEngine $Binary "council-resume" $variables @("--fixture-council-resume")
        if ($run.Code -ne 0 -or $run.Text -notmatch [regex]::Escape($sessionId)) { throw "deterministic exact-id council resume failed" }
        $wrong = $variables.Clone(); $wrong["FORGE_DISPATCH_SEAT_HASH"] = "wrong-$seatHash"
        $run = Invoke-ForgeFixtureEngine $Binary "council-resume" $wrong @("--fixture-council-resume")
        if ($run.Code -eq 0) { throw "deterministic council resume accepted a cross-seat hash" }
        $script:councilResume = "PASS"

        Copy-Item -LiteralPath $candidate -Destination $investigation -Recurse
        $artifact = Join-Path $investigation ".forge\local\investigation-artifacts\qualification.txt"
        $run = Invoke-ForgeFixtureEngine $Binary "investigate" @{ FORGE_DISPATCH_INVESTIGATION_ROOT=$investigation; FORGE_DISPATCH_INVESTIGATION_ARTIFACT=$artifact } @("--fixture-investigate")
        if ($run.Code -ne 0) { throw "deterministic investigation fixture failed" }
        if ((Get-ForgeCandidateIdentity $candidate) -cne $before) { throw "frozen candidate identity changed during investigation" }
        if (-not (Test-Path $artifact -PathType Leaf)) { throw "investigation did not produce its declared artifact" }
        $item = Get-Item -LiteralPath $artifact -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt 65536) { throw "investigation artifact is linked or oversized" }
        if (([IO.File]::ReadAllText($artifact)).Trim() -cne "bounded-reproduction") { throw "full-agent artifact content mismatch" }
        $script:investigationFullAgent = "PASS"
        return "deterministic isolated review, exact-id resume, and full-agent worktree investigation passed"
    } finally { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-ForgeLiveEngine {
    param([string]$Path, [string[]]$Arguments, [hashtable]$Variables, [string]$WorkingDirectory)
    $previous = @{}
    foreach ($key in $Variables.Keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key, "Process"); [Environment]::SetEnvironmentVariable($key, [string]$Variables[$key], "Process") }
    try {
        Push-Location $WorkingDirectory
        try { $captured = (& $Path @Arguments 2>&1) -join "`n"; $code = $LASTEXITCODE }
        finally { Pop-Location }
        return [pscustomobject]@{ Code=$code; Text=$captured }
    } finally { foreach ($key in $Variables.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], "Process") } }
}

function New-ForgeLiveCandidate([string]$Root) {
    New-Item -ItemType Directory -Path (Join-Path $Root ".agents\skills\canary") -Force | Out-Null
    & git -C $Root init -q 2>$null | Out-Null; & git -C $Root config core.autocrlf false 2>$null | Out-Null; & git -C $Root config user.email forge@example.invalid 2>$null | Out-Null; & git -C $Root config user.name Forge 2>$null | Out-Null
    [IO.File]::WriteAllText((Join-Path $Root "keep.txt"), "keep-base`n", $Utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $Root "delete.txt"), "delete-base`n", $Utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $Root "rename-old.txt"), "rename-base`n", $Utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $Root "script.sh"), "#!/bin/sh`necho base`n", $Utf8NoBom)
    & git -C $Root add keep.txt delete.txt rename-old.txt script.sh 2>$null | Out-Null; & git -C $Root update-index --chmod=+x script.sh 2>$null | Out-Null; & git -C $Root commit -qm base 2>$null | Out-Null
    [IO.File]::WriteAllText((Join-Path $Root "keep.txt"), "keep-candidate`n", $Utf8NoBom); Remove-Item (Join-Path $Root "delete.txt"); & git -C $Root mv rename-old.txt rename-new.txt 2>$null | Out-Null
    [IO.File]::WriteAllText((Join-Path $Root "AGENTS.md"), "FORGE_CANARY_CANDIDATE_INSTRUCTION`n", $Utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $Root ".agents\skills\canary\SKILL.md"), "---`nname: canary`ndescription: FORGE_CANARY_SKILL`n---`n", $Utf8NoBom)
}

function Test-ForgeBoundResponse([string]$Text, [string]$Session, [string]$Seat, [string]$Config) {
    return ($Text -match [regex]::Escape($Session) -and $Text -match [regex]::Escape($Seat) -and $Text -match [regex]::Escape($Config) -and $Text -match 'canary_observed["= :]+false' -and $Text -notmatch 'FORGE_CANARY_')
}

function Invoke-ForgeGuardedDispatch([string]$Binary) {
    $scratch = Join-Path ([IO.Path]::GetTempPath()) ("forge-dispatch-live-" + [Guid]::NewGuid().ToString("N"))
    try {
        $primary = Join-Path $scratch "primary"; $candidate = Join-Path $scratch "candidate"; $investigation = $ProjectRoot
        foreach ($dir in @($primary,$candidate,(Join-Path $scratch "codex-home"))) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        & git -C $primary init -q 2>$null | Out-Null; New-ForgeLiveCandidate $candidate
        [IO.File]::WriteAllText((Join-Path $primary "CLAUDE.md"), "FORGE_CANARY_USER_INSTRUCTION`n", $Utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $scratch "codex-home\AGENTS.md"), "FORGE_CANARY_USER_INSTRUCTION`n", $Utf8NoBom)
        $emptyMcp = Join-Path $scratch "empty-mcp.json"; [IO.File]::WriteAllText($emptyMcp, '{"mcpServers":{}}', $Utf8NoBom)
        $schema = Join-Path $scratch "schema.json"; [IO.File]::WriteAllText($schema, '{"type":"object","additionalProperties":true}', $Utf8NoBom)
        if ($Engine -eq "codex" -and -not $TestLiveDriver) { Copy-Item $env:FORGE_CODEX_AUTH_FILE (Join-Path $scratch "codex-home\auth.json") }
        $before = Get-ForgeCandidateIdentity $candidate; $sentinel = "FORGE_ISOLATION_OK_$Engine`_$PID"
        $config = Get-ForgeSha256Bytes ($Utf8NoBom.GetBytes("$Engine`nqualified-v1`n$before`n")); $seat = Get-ForgeSha256Bytes ($Utf8NoBom.GetBytes("$Engine`n$config`n$sentinel`n")); $session = "11111111-1111-4111-8111-{0:d12}" -f $PID
        $vars = @{ FORGE_DISPATCH_SENTINEL=$sentinel; FORGE_DISPATCH_SESSION_ID=$session; FORGE_DISPATCH_SEAT_HASH=$seat; FORGE_DISPATCH_CONFIG_HASH=$config }
        if ($Engine -eq "claude") {
            $userProfile = [Environment]::GetFolderPath('UserProfile'); if (-not $userProfile) { $userProfile = $env:USERPROFILE }
            $vars['HOME'] = $userProfile; $vars['USERPROFILE'] = $userProfile; $vars['USERNAME'] = $(if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName })
        } else { $vars["CODEX_HOME"] = Join-Path $scratch "codex-home" }
        if ($Engine -eq "claude") {
            $args = @("-p","--safe-mode","--no-session-persistence","--strict-mcp-config","--mcp-config",$emptyMcp,"--setting-sources","","--tools","","--permission-mode","dontAsk","--output-format","json","--system-prompt","Return sentinel=$sentinel and canary_observed=false.",$sentinel)
        } else {
            $args = @("-a","never","exec","--disable","hooks","--disable","plugins","--disable","plugin_sharing","--disable","apps","--disable","remote_plugin","-C",$primary,"--add-dir",$candidate,"--ignore-user-config","--ignore-rules","--ephemeral","--sandbox","read-only","--json","--output-schema",$schema,"Return sentinel=$sentinel and canary_observed=false.")
        }
        $run = Invoke-ForgeLiveEngine $Binary $args $vars $primary
        if ($run.Code -ne 0 -or $run.Text -notmatch [regex]::Escape($sentinel) -or $run.Text -notmatch 'canary_observed["= :]+false' -or $run.Text -match 'FORGE_CANARY_') { throw "ephemeral response leaked a canary or missed the sentinel" }
        $script:ephemeral = "PASS"
        if ($Engine -eq "claude") {
            $startArgs = @("-p","--safe-mode","--strict-mcp-config","--mcp-config",$emptyMcp,"--setting-sources","","--tools","","--permission-mode","dontAsk","--output-format","json","--session-id",$session,"--system-prompt","Return exactly these four key=value lines and nothing else: session_id=$session, seat_hash=$seat, config_hash=$config, canary_observed=false.","FORGE_COUNCIL_START")
            $run = Invoke-ForgeLiveEngine $Binary $startArgs $vars $primary
            if ($run.Code -ne 0 -or -not (Test-ForgeBoundResponse $run.Text $session $seat $config)) { throw "Claude council first turn identity mismatch" }
            $resumeArgs = @("-p","--safe-mode","--strict-mcp-config","--mcp-config",$emptyMcp,"--setting-sources","","--tools","","--permission-mode","dontAsk","--output-format","json","--resume",$session,"--system-prompt","Return exactly these four key=value lines and nothing else: session_id=$session, seat_hash=$seat, config_hash=$config, canary_observed=false.","FORGE_COUNCIL_RESUME")
        } else {
            $startArgs = @("-a","never","exec","--disable","hooks","--disable","plugins","--disable","plugin_sharing","--disable","apps","--disable","remote_plugin","-C",$primary,"--add-dir",$candidate,"--ignore-user-config","--ignore-rules","--sandbox","read-only","--json","--output-schema",$schema,"FORGE_COUNCIL_START seat_hash=$seat config_hash=$config canary_observed=false")
            $run = Invoke-ForgeLiveEngine $Binary $startArgs $vars $primary
            $thread = ""
            foreach ($line in ($run.Text -split "`n")) { try { $event = $line | ConvertFrom-Json; if ($event.type -eq "thread.started") { $thread = $event.thread_id; break } } catch {} }
            if (-not $thread -or ($TestLiveDriver -and $thread -cne $session)) { throw "Codex council first turn emitted no exact thread.started id" }
            if (-not $TestLiveDriver) { $session = $thread; $vars["FORGE_DISPATCH_SESSION_ID"] = $session }
            if ($run.Code -ne 0 -or -not (Test-ForgeBoundResponse $run.Text $session $seat $config)) { throw "Codex council first turn identity mismatch" }
            $resumeArgs = @("-a","never","--sandbox","read-only","exec","resume","--disable","hooks","--disable","plugins","--disable","plugin_sharing","--disable","apps","--disable","remote_plugin","--ignore-user-config","--ignore-rules","--json","--output-schema",$schema,$session,"FORGE_COUNCIL_RESUME session_id=$session seat_hash=$seat config_hash=$config canary_observed=false")
        }
        $run = Invoke-ForgeLiveEngine $Binary $resumeArgs $vars $primary
        if ($run.Code -ne 0 -or -not (Test-ForgeBoundResponse $run.Text $session $seat $config)) { throw "council resume rejected cross-seat, stale config, or canary evidence" }
        $script:councilResume = "PASS"
        $artifact = Join-Path $investigation ".forge\local\investigation-artifacts\runtime-$Engine-$PID.txt"
        New-Item -ItemType Directory -Path (Split-Path -Parent $artifact) -Force | Out-Null
        if (Test-Path -LiteralPath $artifact) { throw "investigation qualification artifact already exists" }
        $investigationVars = @{ FORGE_DISPATCH_INVESTIGATION_ROOT=$investigation; FORGE_DISPATCH_INVESTIGATION_ARTIFACT=$artifact }
        if ($Engine -eq "claude") { $investigationArgs = @("-p","--permission-mode","auto","--no-session-persistence","--model","opus","--effort","max","--output-format","json","FORGE_INVESTIGATION. Work as a normal full-capability project agent. Write exactly bounded-reproduction plus a newline to $artifact. Return exactly these two key=value lines and nothing else: worktree=$investigation and artifact_written=true.") }
        else { $investigationArgs = @("-a","on-request","--search","exec","-C",$investigation,"--sandbox","danger-full-access","--ephemeral","-m","gpt-5.6-sol","-c","model_reasoning_effort=xhigh","FORGE_INVESTIGATION. Work as a normal full-capability project agent. Write exactly bounded-reproduction plus a newline to $artifact. Return exactly: worktree=$investigation artifact_written=true.") }
        $run = Invoke-ForgeLiveEngine $Binary $investigationArgs $investigationVars $investigation
        if ($run.Code -ne 0 -or $run.Text -notmatch [regex]::Escape("worktree=$investigation") -or $run.Text -notmatch 'artifact_written["= :]+true') { throw "investigation response did not bind the real worktree" }
        if (-not (Test-Path $artifact -PathType Leaf) -or ((Get-Item $artifact -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-Item $artifact).Length -gt 65536) { throw "full-agent investigation omitted its worktree artifact" }
        if (([IO.File]::ReadAllText($artifact)).Trim() -cne "bounded-reproduction") { throw "full-agent investigation artifact content mismatch" }
        Remove-Item -LiteralPath $artifact -Force
        $script:investigationFullAgent = "PASS"
        return "authenticated isolated review, exact-id resume, and full-agent worktree investigation passed"
    } finally { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

$version = ""; $status = "BLOCKED"; $ephemeral = "BLOCKED"; $councilResume = "BLOCKED"; $investigationFullAgent = "BLOCKED"; $reason = "binary unavailable"
$commandPath = ""
if ($EnginePath) { if (Test-Path $EnginePath -PathType Leaf) { $commandPath = (Resolve-Path $EnginePath).Path } }
else { $command = Get-Command $Engine -ErrorAction SilentlyContinue; if ($command) { $commandPath = $command.Source } }

if ($FixtureMode) {
    if ($commandPath) {
        $previousName = $env:FORGE_FAKE_ENGINE_NAME
        try {
            $env:FORGE_FAKE_ENGINE_NAME = $Engine
            $version = ((& $commandPath --version 2>$null) | Select-Object -First 1)
            try { $reason = Invoke-ForgeDispatchFixture $commandPath; $status = "PASS" }
            catch { $reason = $_.Exception.Message }
        } finally { $env:FORGE_FAKE_ENGINE_NAME = $previousName }
    }
} elseif ($commandPath) {
    $version = ((& $commandPath --version 2>$null) | Select-Object -First 1)
    if ($Engine -eq "claude") {
        $help = (& $commandPath --help 2>&1) -join "`n"
        $required = @("--safe-mode", "--strict-mcp-config", "--setting-sources", "--session-id", "--resume", "--no-session-persistence")
        $missing = @($required | Where-Object { $help -notmatch [regex]::Escape($_) })
        if ($missing.Count) { $reason = "qualified CLI lacks required isolation flags: $($missing -join ' ')" }
        elseif (-not $TestLiveDriver -and $env:FORGE_LIVE_QUALIFICATION -ne "1") { $reason = "set FORGE_LIVE_QUALIFICATION=1 to authorize the authenticated sentinel" }
        else { try { $reason = Invoke-ForgeGuardedDispatch $commandPath; $status = "PASS" } catch { $reason = $_.Exception.Message } }
    } else {
        $help = ((& $commandPath --help 2>&1) + (& $commandPath exec --help 2>&1)) -join "`n"
        $required = @("--add-dir", "--ignore-user-config", "--ignore-rules", "--ephemeral", "--sandbox", "--json")
        $missing = @($required | Where-Object { $help -notmatch [regex]::Escape($_) })
        if ($missing.Count) { $reason = "qualified CLI lacks required isolation flags: $($missing -join ' ')" }
        elseif (-not $TestLiveDriver -and $env:FORGE_LIVE_QUALIFICATION -ne "1") { $reason = "set FORGE_LIVE_QUALIFICATION=1 to authorize the authenticated sentinel" }
        elseif (-not $TestLiveDriver -and (-not $env:FORGE_CODEX_AUTH_FILE -or -not (Test-Path $env:FORGE_CODEX_AUTH_FILE -PathType Leaf))) { $reason = "set FORGE_CODEX_AUTH_FILE to an operator-owned auth file for disposable CODEX_HOME" }
        else { try { $reason = Invoke-ForgeGuardedDispatch $commandPath; $status = "PASS" } catch { $reason = $_.Exception.Message } }
    }
}

$receipt = [ordered]@{ schema="forge.dispatch-isolation.v1"; engine=$Engine; version="$version"; status=$status; ephemeral=$ephemeral; council_resume=$councilResume; investigation_full_agent=$investigationFullAgent; reason=$reason }
$parent = Split-Path -Parent $Output
if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$json = $receipt | ConvertTo-Json -Compress
[IO.File]::WriteAllText($Output, "$json`n", $Utf8NoBom)
Write-Output $json
if ($status -eq "PASS") { exit 0 } else { exit 1 }
