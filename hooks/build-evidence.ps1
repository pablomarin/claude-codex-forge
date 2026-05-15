# hooks/build-evidence.ps1 — emit FORGE_GOAL_EVIDENCE JSON.
# Mirrors hooks/build-evidence.sh. See that file for design notes.
#
# Read-only. Parses .claude/local/state.md plus git/gh/E2E state and emits a
# unified evidence JSON between FORGE_GOAL_EVIDENCE_BEGIN/END markers on STDERR.
# Stop hook (check-state-updated.ps1) invokes this each turn so the Haiku
# verifier inside an active /goal sees the evidence in the transcript.
#
# PS 5.1 compatible. No ??. No ConvertTo-Json for emission (byte-stable
# hand-built string instead). No Get-Date -UFormat %s (inconsistent across hosts).

$ErrorActionPreference = 'Continue'

$StateMd = ".claude/local/state.md"

# ---------------------------------------------------------------------------
# Helper: Unix epoch time (PS 5.1 compatible)
# ---------------------------------------------------------------------------
function Get-UnixTime {
    [int][Math]::Floor(((Get-Date) - (Get-Date '1970-01-01Z').ToUniversalTime()).TotalSeconds)
}

$NowUnix = Get-UnixTime

# ---------------------------------------------------------------------------
# Helper: JSON string field builder (null for empty; escapes \ and ")
# ---------------------------------------------------------------------------
function Build-JsonStringField {
    param([string]$Key, [string]$Value)
    if ([string]::IsNullOrEmpty($Value)) {
        return '"' + $Key + '":null'
    }
    $esc = $Value -replace '\\', '\\' -replace '"', '\"'
    return '"' + $Key + '":"' + $esc + '"'
}

# ---------------------------------------------------------------------------
# Helper: Read state.md as CRLF-normalized lines (LF only)
# ---------------------------------------------------------------------------
function Read-StateMdLines {
    if (-not (Test-Path $StateMd)) { return @() }
    $raw = Get-Content $StateMd -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($raw)) { return @() }
    # CRLF normalize: strip \r, then split on \n
    return ($raw -replace "`r", "") -split "`n"
}

# ---------------------------------------------------------------------------
# Parse-GoalSession: returns @{nonce=""; workflow_command=""}
# Scoped to ## /goal session Markdown table.
# ---------------------------------------------------------------------------
function Parse-GoalSession {
    $result = @{ nonce = ""; workflow_command = "" }
    $lines = Read-StateMdLines
    $inSection = $false
    foreach ($line in $lines) {
        if ($line -match '^## /goal session$') { $inSection = $true; continue }
        if ($inSection -and $line -match '^## ') { break }
        if (-not $inSection) { continue }
        # Markdown table row: | <field> | <value> |
        if ($line -match '^\|\s*nonce\s*\|\s*(.+?)\s*\|') {
            $result.nonce = $matches[1].Trim()
        }
        elseif ($line -match '^\|\s*workflow_command\s*\|\s*(.+?)\s*\|') {
            $result.workflow_command = $matches[1].Trim()
        }
    }
    return $result
}

# ---------------------------------------------------------------------------
# Parse-Workflow: returns @{phase=""; next_step=""; total=0; done=0}
# Scoped to ## Workflow block (checklist under ### Checklist).
# ---------------------------------------------------------------------------
function Parse-Workflow {
    $result = @{ phase = ""; next_step = ""; total = 0; done = 0 }
    $lines = Read-StateMdLines
    $inWorkflow = $false
    $inChecklist = $false
    foreach ($line in $lines) {
        if ($line -match '^## Workflow$') { $inWorkflow = $true; continue }
        if ($inWorkflow -and $line -match '^## ') { $inWorkflow = $false; $inChecklist = $false; continue }
        if (-not $inWorkflow) { continue }

        if ($line -match '^### Checklist') { $inChecklist = $true; continue }
        if ($line -match '^### ' -and $line -notmatch '^### Checklist') { $inChecklist = $false; continue }

        # Markdown table: | Phase | <value> |
        if ($line -match '^\|\s*Phase\s*\|') {
            $parts = $line -split '\|'
            if ($parts.Count -ge 3) {
                $result.phase = $parts[2].Trim()
            }
        }
        elseif ($line -match '^\|\s*Next step\s*\|') {
            $parts = $line -split '\|'
            if ($parts.Count -ge 3) {
                $result.next_step = $parts[2].Trim()
            }
        }

        if ($inChecklist) {
            if ($line -match '^\- \[x\]') { $result.done++; $result.total++ }
            elseif ($line -match '^\- \[ \]') { $result.total++ }
        }
    }
    return $result
}

# ---------------------------------------------------------------------------
# Compute-ReviewerGate: returns @{clean=$false; matched_iteration=""; matched_head=""}
# Scoped to ## Workflow / ### Checklist. Requires codex clean AND pr-toolkit
# clean for the SAME iteration at the matching HEAD sha.
# ---------------------------------------------------------------------------
function Compute-ReviewerGate {
    param([string]$HeadSha)
    $result = @{ clean = $false; matched_iteration = ""; matched_head = "" }
    if ([string]::IsNullOrEmpty($HeadSha)) { return $result }
    if (-not (Test-Path $StateMd)) { return $result }

    $lines = Read-StateMdLines
    $inWorkflow = $false
    $inChecklist = $false
    # Track per-iteration which tools have cleared (using a hashtable keyed by "iter|tool")
    $seen = @{}

    foreach ($line in $lines) {
        if ($line -match '^## Workflow$') { $inWorkflow = $true; continue }
        if ($inWorkflow -and $line -match '^## ') { $inWorkflow = $false; $inChecklist = $false; continue }
        if (-not $inWorkflow) { continue }

        if ($line -match '^### Checklist') { $inChecklist = $true; continue }
        if ($line -match '^### ' -and $line -notmatch '^### Checklist') { $inChecklist = $false; continue }

        if ($inChecklist -and $line -match '^\- \[x\]\s+Code review iteration \d+ — ') {
            # Extract iteration number
            if ($line -match 'iteration (\d+)') {
                $iter = $matches[1]
            } else { continue }

            # Extract tool
            if ($line -match 'codex clean') { $tool = "codex" }
            elseif ($line -match 'pr-toolkit clean') { $tool = "pr-toolkit" }
            else { continue }

            # Extract head sha
            if ($line -match 'head=`([0-9a-f]+)`') {
                $sha = $matches[1]
            } else { continue }

            if ($sha -ne $HeadSha) { continue }

            $key = "$iter|$tool"
            $seen[$key] = $true

            $codexKey = "$iter|codex"
            $tkKey = "$iter|pr-toolkit"
            if ($seen.ContainsKey($codexKey) -and $seen.ContainsKey($tkKey)) {
                $result.clean = $true
                $result.matched_iteration = $iter
                $result.matched_head = $HeadSha
                return $result
            }
        }
    }
    return $result
}

# ---------------------------------------------------------------------------
# Parse-PRAuthorization: returns @{authorized=$false; authorized_at="";
#   head_sha_at_auth=""; nonce_at_auth=""}
# Requires BOTH nonce AND head match for authorized=true.
# ---------------------------------------------------------------------------
function Parse-PRAuthorization {
    param([string]$HeadSha, [string]$GoalNonce)
    $result = @{ authorized = $false; authorized_at = ""; head_sha_at_auth = ""; nonce_at_auth = "" }
    if (-not (Test-Path $StateMd)) { return $result }
    if ([string]::IsNullOrEmpty($HeadSha)) { return $result }
    if ([string]::IsNullOrEmpty($GoalNonce)) { return $result }

    $lines = Read-StateMdLines
    $matchLine = ""
    foreach ($line in $lines) {
        if ($line -match '^-\s*\[x\]\s+PR creation authorized') {
            $matchLine = $line
            break
        }
    }

    if ([string]::IsNullOrEmpty($matchLine)) { return $result }

    # Pattern: - [x] PR creation authorized — `<timestamp>` — nonce=`<nonce>` — head=`<sha>`
    if ($matchLine -match '\[x\]\s+PR creation authorized\s+[—\-]+\s+`([^`]+)`\s+[—\-]+\s+nonce=`([^`]+)`\s+[—\-]+\s+head=`([^`]+)`') {
        $at = $matches[1]
        $nonce = $matches[2]
        $head = $matches[3]

        $result.authorized_at = $at
        $result.head_sha_at_auth = $head
        $result.nonce_at_auth = $nonce

        if ($nonce -eq $GoalNonce -and $head -eq $HeadSha) {
            $result.authorized = $true
        }
    }
    return $result
}

# ---------------------------------------------------------------------------
# Git state queries (read-only, best-effort — failures produce empty strings)
# ---------------------------------------------------------------------------
$HeadSha = (git rev-parse HEAD 2>$null) -join ""
if ($LASTEXITCODE -ne 0) { $HeadSha = "" }

$Branch = (git rev-parse --abbrev-ref HEAD 2>$null) -join ""
if ($LASTEXITCODE -ne 0) { $Branch = "" }

$TreeSha = (git rev-parse "HEAD^{tree}" 2>$null) -join ""
if ($LASTEXITCODE -ne 0) { $TreeSha = "" }

$DirtyOutput = git status --porcelain 2>$null
$Dirty = "false"
if ($DirtyOutput) { $Dirty = "true" }

# Branch-off: prefer main, then master
$BranchOff = ""
$branchOffRaw = git merge-base HEAD main 2>$null
if ($LASTEXITCODE -eq 0 -and $branchOffRaw) {
    $BranchOff = ($branchOffRaw -join "").Trim()
} else {
    $branchOffRaw = git merge-base HEAD master 2>$null
    if ($LASTEXITCODE -eq 0 -and $branchOffRaw) {
        $BranchOff = ($branchOffRaw -join "").Trim()
    }
}

# If HEAD IS the branch-off (user is on main/master directly), force skip path.
# Mirrors check-workflow-gates.sh lines 139-142 exactly.
if ((-not [string]::IsNullOrEmpty($BranchOff)) -and (-not [string]::IsNullOrEmpty($HeadSha)) -and ($BranchOff -eq $HeadSha)) {
    $BranchOff = ""
}

$BranchOffTs = ""
if (-not [string]::IsNullOrEmpty($BranchOff)) {
    $tsRaw = git log -1 --format="%ct" $BranchOff 2>$null
    if ($LASTEXITCODE -eq 0 -and $tsRaw) {
        $BranchOffTs = ($tsRaw -join "").Trim()
    }
}

# ---------------------------------------------------------------------------
# gh pr view — best-effort; skipped silently if gh not installed or no PR
# ---------------------------------------------------------------------------
$PrExists = "false"
$PrNumber = "null"
$PrUrl = ""
$PrStateVal = ""
$PrHeadOid = ""
$PrBaseRef = ""
$PrHeadRef = ""

$ghAvailable = $null
try {
    $null = Get-Command gh -ErrorAction Stop
    $ghAvailable = $true
} catch {
    $ghAvailable = $false
}

if ($ghAvailable) {
    $prJson = gh pr view --json number,url,state,headRefOid,baseRefName,headRefName 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrEmpty($prJson)) {
        try {
            $prObj = $prJson | ConvertFrom-Json
            $PrExists = "true"
            # number: use int directly; null-safe
            if ($null -ne $prObj.number) {
                $PrNumber = [string]$prObj.number
            } else {
                $PrNumber = "null"
            }
            if ($null -ne $prObj.url) { $PrUrl = [string]$prObj.url } else { $PrUrl = "" }
            if ($null -ne $prObj.state) { $PrStateVal = [string]$prObj.state } else { $PrStateVal = "" }
            if ($null -ne $prObj.headRefOid) { $PrHeadOid = [string]$prObj.headRefOid } else { $PrHeadOid = "" }
            if ($null -ne $prObj.baseRefName) { $PrBaseRef = [string]$prObj.baseRefName } else { $PrBaseRef = "" }
            if ($null -ne $prObj.headRefName) { $PrHeadRef = [string]$prObj.headRefName } else { $PrHeadRef = "" }
        } catch {
            # JSON parse failed — treat as no PR
            $PrExists = "false"
        }
    }
}

# ---------------------------------------------------------------------------
# E2E report freshness — mirrors mtime logic in check-workflow-gates.sh
# ---------------------------------------------------------------------------
$E2ePresent = "false"
$E2eFresh = "false"
$E2ePath = ""
$E2eMtime = ""
$E2eMtimeInt = 0

if (Test-Path "tests/e2e/reports") {
    $newestItem = $null
    $newestMtime = 0

    $reportItems = Get-ChildItem "tests/e2e/reports" -Filter "*.md" -File -ErrorAction SilentlyContinue
    foreach ($item in $reportItems) {
        # Convert LastWriteTime to Unix epoch (UTC)
        $epochBase = [datetime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
        $mtime = [int][Math]::Floor(($item.LastWriteTimeUtc - $epochBase).TotalSeconds)
        if ($mtime -gt $newestMtime) {
            $newestMtime = $mtime
            $newestItem = $item
        }
    }

    if ($null -ne $newestItem) {
        $E2ePresent = "true"
        $E2ePath = $newestItem.FullName -replace '\\', '/'
        # Make path relative if it starts with current directory
        $pwd = (Get-Location).Path -replace '\\', '/'
        if ($E2ePath.StartsWith($pwd + "/")) {
            $E2ePath = $E2ePath.Substring($pwd.Length + 1)
        }
        $E2eMtimeInt = $newestMtime
        $E2eMtime = [string]$newestMtime

        if ((-not [string]::IsNullOrEmpty($BranchOffTs)) -and ($newestMtime -gt [int]$BranchOffTs)) {
            $E2eFresh = "true"
        }
    }
}

# ---------------------------------------------------------------------------
# Parse all sections
# ---------------------------------------------------------------------------
$goalSession = Parse-GoalSession
$GoalNonce = $goalSession.nonce
$GoalCmd = $goalSession.workflow_command

$wf = Parse-Workflow
$Phase = $wf.phase
$NextStep = $wf.next_step
$TotalCount = $wf.total
$DoneCount = $wf.done

$rg = Compute-ReviewerGate -HeadSha $HeadSha
$RgClean = if ($rg.clean) { "true" } else { "false" }
$RgIter = $rg.matched_iteration
$RgHead = $rg.matched_head

$pa = Parse-PRAuthorization -HeadSha $HeadSha -GoalNonce $GoalNonce
$PaAuth = if ($pa.authorized) { "true" } else { "false" }
$PaAt = $pa.authorized_at
$PaHead = $pa.head_sha_at_auth
$PaNonce = $pa.nonce_at_auth

# ---------------------------------------------------------------------------
# Task 7: Derived fields — pr_ready, all_gates_green, progress_fingerprint
# ---------------------------------------------------------------------------

# pr_ready: PR open AND PR head matches HEAD AND reviewer gate clean
#           AND E2E fresh AND PR auth accepted.
$PrOpen = if ($PrStateVal -eq "OPEN") { "true" } else { "false" }
$PrHeadMatch = "false"
if ((-not [string]::IsNullOrEmpty($HeadSha)) -and ($PrHeadOid -eq $HeadSha)) {
    $PrHeadMatch = "true"
}

$PrReady = "false"
if ($PrOpen -eq "true" -and $PrHeadMatch -eq "true" -and $RgClean -eq "true" -and $E2eFresh -eq "true" -and $PaAuth -eq "true") {
    $PrReady = "true"
}

# all_gates_green: every checklist item checked (DONE == TOTAL > 0) AND pr_ready=true.
$AllGates = "false"
if ($DoneCount -eq $TotalCount -and $TotalCount -gt 0 -and $PrReady -eq "true") {
    $AllGates = "true"
}

# ---------------------------------------------------------------------------
# progress_fingerprint: deterministic SHA256 of a SCOPED, ORDER-PRESERVING subset.
#
# Design notes (from plan Task 7):
#   1. CRLF normalize BEFORE pattern matching — anchors must match even on
#      Windows-edited files.
#   2. Scope to ## Workflow / ### Checklist only.
#   3. Preserve document ORDER.
#   4. Use ASCII Unit Separator (0x1f) as delimiter — never appears in Markdown.
#   5. Include PR authorization line (whole-file OK — there's only ever one).
# ---------------------------------------------------------------------------
$Delim = [char]31  # ASCII Unit Separator

$fpParts = [System.Text.StringBuilder]::new()
$null = $fpParts.Append($Phase)
$null = $fpParts.Append($Delim)
$null = $fpParts.Append($NextStep)
$null = $fpParts.Append($Delim)

# Extract checklist rows in document order (scoped to ## Workflow / ### Checklist)
$lines = Read-StateMdLines
$inWorkflow = $false
$inChecklist = $false
foreach ($line in $lines) {
    if ($line -match '^## Workflow$') { $inWorkflow = $true; continue }
    if ($inWorkflow -and $line -match '^## ') { $inWorkflow = $false; $inChecklist = $false; continue }
    if (-not $inWorkflow) { continue }
    if ($line -match '^### Checklist') { $inChecklist = $true; continue }
    if ($line -match '^### ' -and $line -notmatch '^### Checklist') { $inChecklist = $false; continue }
    if ($inChecklist -and $line -match '^\- \[[ x]\]') {
        $null = $fpParts.Append($line)
        $null = $fpParts.Append($Delim)
    }
}

# PR authorization line (whole-file — singleton)
foreach ($line in $lines) {
    if ($line -match '^- \[[xX]\]\s+PR creation authorized') {
        $null = $fpParts.Append($line)
        break
    }
}

$fpInput = $fpParts.ToString()
$fpBytes = [System.Text.Encoding]::UTF8.GetBytes($fpInput)
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha256.ComputeHash($fpBytes)
$sha256.Dispose()
$ProgressFp = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""

# ---------------------------------------------------------------------------
# Build JSON field strings
# ---------------------------------------------------------------------------
$SessionNonceJson = Build-JsonStringField "session_nonce" $GoalNonce
$WorkflowCmdJson  = Build-JsonStringField "workflow_command" $GoalCmd
$PhaseJson        = Build-JsonStringField "phase" $Phase
$NextStepJson     = Build-JsonStringField "next_step" $NextStep
$RgIterJson       = Build-JsonStringField "matched_iteration" $RgIter
$RgHeadJson       = Build-JsonStringField "matched_head" $RgHead
$PaAtJson         = Build-JsonStringField "authorized_at" $PaAt
$PaHeadJson       = Build-JsonStringField "head_sha_at_authorization" $PaHead
$PaNonceJson      = Build-JsonStringField "nonce_at_authorization" $PaNonce
$BranchJson       = Build-JsonStringField "branch" $Branch
$HeadShaJson      = Build-JsonStringField "head_sha" $HeadSha
$TreeShaJson      = Build-JsonStringField "tree_sha" $TreeSha
$BranchOffJson    = Build-JsonStringField "branch_off_commit" $BranchOff
$PrUrlJson        = Build-JsonStringField "url" $PrUrl
$PrStateJson      = Build-JsonStringField "state" $PrStateVal
$PrHeadOidJson    = Build-JsonStringField "head_oid" $PrHeadOid
$PrBaseRefJson    = Build-JsonStringField "base_ref" $PrBaseRef
$PrHeadRefJson    = Build-JsonStringField "head_ref" $PrHeadRef
$E2ePathJson      = Build-JsonStringField "path" $E2ePath

# pr_state block
if ($PrExists -eq "true") {
    $prStateBlock = '"pr_state":{"exists":true,"number":' + $PrNumber + ',' + $PrUrlJson + ',' + $PrStateJson + ',' + $PrHeadOidJson + ',' + $PrBaseRefJson + ',' + $PrHeadRefJson + '}'
} else {
    $prStateBlock = '"pr_state":{"exists":false,"number":null,"url":null,"state":null,"head_oid":null,"base_ref":null,"head_ref":null}'
}

# e2e_report block
if ($E2ePresent -eq "true") {
    $e2eBlock = '"e2e_report":{"present":true,' + $E2ePathJson + ',"mtime_unix":' + $E2eMtime + ',"fresh_for_head":' + $E2eFresh + '}'
} else {
    $e2eBlock = '"e2e_report":{"present":false,"path":null,"mtime_unix":null,"fresh_for_head":false}'
}

# ---------------------------------------------------------------------------
# Emit evidence JSON to STDERR (between begin/end markers)
# Same field order as build-evidence.sh
# ---------------------------------------------------------------------------
$json = '{' +
    '"type":"forge_goal_evidence",' +
    '"schema_version":1,' +
    '"produced_at_unix":' + $NowUnix + ',' +
    $SessionNonceJson + ',' +
    $WorkflowCmdJson + ',' +
    '"state":{' + $PhaseJson + ',' + $NextStepJson + ',"checklist_total":' + $TotalCount + ',"checklist_done":' + $DoneCount + '},' +
    '"reviewer_gate":{"clean_same_iteration":' + $RgClean + ',' + $RgIterJson + ',' + $RgHeadJson + '},' +
    $BranchJson + ',' +
    $HeadShaJson + ',' +
    $TreeShaJson + ',' +
    $BranchOffJson + ',' +
    '"working_tree_dirty":' + $Dirty + ',' +
    $prStateBlock + ',' +
    $e2eBlock + ',' +
    '"pr_authorization":{"authorized":' + $PaAuth + ',' + $PaAtJson + ',' + $PaHeadJson + ',' + $PaNonceJson + '},' +
    '"pr_ready":' + $PrReady + ',' +
    '"all_gates_green":' + $AllGates + ',' +
    '"progress_fingerprint":"' + $ProgressFp + '",' +
    '"warnings":[],' +
    '"errors":[]' +
    '}'

[Console]::Error.WriteLine("FORGE_GOAL_EVIDENCE_BEGIN")
[Console]::Error.WriteLine($json)
[Console]::Error.WriteLine("FORGE_GOAL_EVIDENCE_END")

exit 0
