# hooks/build-evidence.ps1 — emit FORGE_GOAL_EVIDENCE JSON.
# Mirrors hooks/build-evidence.sh. See that file for design notes.
#
# Read-only. Parses .claude/local/state.md plus git/gh/E2E state and emits a
# unified evidence JSON between FORGE_GOAL_EVIDENCE_BEGIN/END markers on STDERR.
# Registered as its own Stop hook (settings.template.json) so its STDERR
# output is shown as informational rather than merged into check-state-updated's
# exit-2 output. Always exits 0 — never blocks.
#
# PS 5.1 compatible. No ??. No ConvertTo-Json for emission (byte-stable
# hand-built string instead). No Get-Date -UFormat %s (inconsistent across hosts).

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Worktree CWD fix (v5.32) — parse `cwd` from stdin JSON and chdir there so
# relative paths (.claude/local/state.md) and git ops target the worktree,
# not $CLAUDE_PROJECT_DIR (which CC uses as default Stop hook CWD).
# Fallback: git rev-parse --show-toplevel → current CWD.
# ---------------------------------------------------------------------------
$input_raw = ""
if (-not [Console]::IsInputRedirected) {
    # stdin not redirected — running outside hook context (manual invocation)
} else {
    try { $input_raw = [Console]::In.ReadToEnd() } catch { $input_raw = "" }
}
$hookCwd = ""
if ($input_raw) {
    try {
        $parsed = $input_raw | ConvertFrom-Json -ErrorAction Stop
        if ($parsed -and $parsed.PSObject.Properties['cwd']) {
            $hookCwd = [string]$parsed.cwd
        }
    } catch {
        # Fallback regex parse (PS 5.1 ConvertFrom-Json may reject some shapes)
        if ($input_raw -match '"cwd"\s*:\s*"([^"]*)"') {
            $hookCwd = $matches[1]
        }
    }
}
if ($hookCwd -and (Test-Path -LiteralPath $hookCwd -PathType Container)) {
    # Normalize to repo/worktree root in case stdin.cwd points at a subdirectory
    # (Codex P2-1, v5.32 review). Without this, relative paths would silently miss.
    $normalized = (& git -C "$hookCwd" rev-parse --show-toplevel 2>$null)
    if ($normalized -and (Test-Path -LiteralPath $normalized -PathType Container)) {
        Set-Location -LiteralPath $normalized
    } else {
        Set-Location -LiteralPath $hookCwd
    }
} else {
    $toplevel = (& git rev-parse --show-toplevel 2>$null)
    if ($toplevel -and (Test-Path -LiteralPath $toplevel -PathType Container)) {
        Set-Location -LiteralPath $toplevel
    }
}

$StateMd = ".claude/local/state.md"

# ---------------------------------------------------------------------------
# v5.54 scoped-review-certification (ADR 0009): resolve the scope helper the SAME
# way the gate does — installed path first, then forge-internal source path — and
# DOT-SOURCE it so Invoke-ReviewScope is in scope. Do NOT call-operator the script
# (its standalone entrypoint would `exit` the hook) and do NOT spawn a separate
# pwsh interpreter (the repo ships against powershell.exe 5.1 per the
# default-branch.ps1 contract). Helper absence → fail-open (0/"ok"; only
# self-contained evidence forms validate — see Compute-ReviewerGate).
$ReviewScopePs1 = Join-Path (Get-Location) ".claude\hooks\lib\review-scope.ps1"
if (-not (Test-Path -LiteralPath $ReviewScopePs1)) {
    $ReviewScopePs1 = Join-Path (Get-Location) "hooks\lib\review-scope.ps1"
}
$ReviewScopeAvailable = $false
if (Test-Path -LiteralPath $ReviewScopePs1) {
    . $ReviewScopePs1
    $ReviewScopeAvailable = $true
}

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
    $esc = $Value -replace '\\', '\\\\' -replace '"', '\"'
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
# Get-ChecklistLines: ## Workflow / ### Checklist lines (CRLF-normalized).
# ---------------------------------------------------------------------------
function Get-ChecklistLines {
    $lines = Read-StateMdLines
    $inWorkflow = $false
    $inChecklist = $false
    $out = @()
    foreach ($line in $lines) {
        if ($line -match '^## Workflow$') { $inWorkflow = $true; continue }
        if ($inWorkflow -and $line -match '^## ') { $inWorkflow = $false; $inChecklist = $false; continue }
        if (-not $inWorkflow) { continue }
        if ($line -match '^### Checklist') { $inChecklist = $true; continue }
        if ($line -match '^### ' -and $line -notmatch '^### Checklist') { $inChecklist = $false; continue }
        if ($inChecklist) { $out += $line }
    }
    return $out
}

# ---------------------------------------------------------------------------
# Compute-ReviewerGate: returns @{clean=$false; matched_iteration=""; matched_head=""}
#
# v5.54 (ADR 0009): applies the SAME helper-backed validation as the ship gate
# (check-workflow-gates.ps1) so /goal readiness is never a weaker parser. For the
# latest iteration N at the current head, accept ONLY:
#   * legacy pair  — when RS_PRIOR says CERTIFIED:no (certifies; never rebinds)
#   * scoped pair  — delimiter-bound scope=full|delta, coherent (same scope+base,
#                    base=/head= present); delta → base == RS_PRIOR LAST_CLEAN_HEAD
#                    AND RS_PRIOR ANCESTOR_OK:yes AND NOT SCOPE_REQUIRED:full;
#                    full → base == recomputed default-ref merge-base for head
#   * mechanical   — base == RS_PRIOR LAST_CLEAN_HEAD AND RS_PRIOR CERTIFIED:yes
#                    AND RS_PRIOR SCOPE_REQUIRED:mechanical
# Helper absence → reject chain-dependent claims (delta, mechanical); accept only
# self-contained forms (legacy pair, or scope=full pair at the current head).
# ---------------------------------------------------------------------------
function Compute-ReviewerGate {
    param([string]$HeadSha)
    $result = @{ clean = $false; matched_iteration = ""; matched_head = "" }
    if ([string]::IsNullOrEmpty($HeadSha)) { return $result }
    if (-not (Test-Path $StateMd)) { return $result }

    $checklist = Get-ChecklistLines

    # Latest iteration N at the current head — mechanical row, or codex+pr-toolkit
    # pair both at head=$HeadSha. Mechanical wins ties.
    $mechN = $null
    $pairN = $null
    $seen = @{}
    foreach ($line in $checklist) {
        if ($line -notmatch '^\s*-\s*\[x\]\s+Code review iteration (\d+) — ') { continue }
        $iter = [int]$matches[1]
        if ($line -cmatch "Code review iteration $iter — mechanical re-stamp — scope=mechanical — " `
            -and $line -match 'head=`([0-9a-f]+)`' -and $matches[1] -eq $HeadSha) {
            if (($null -eq $mechN) -or ($iter -gt $mechN)) { $mechN = $iter }
            continue
        }
        if ($line -match '— codex deep-pass clean —') { continue }
        if ($line -match '— codex clean —') { $tool = 'codex' }
        elseif ($line -match '— pr-toolkit clean —') { $tool = 'pr-toolkit' }
        else { continue }
        if ($line -match 'head=`([0-9a-f]+)`') { $sha = $matches[1] } else { continue }
        if ($sha -ne $HeadSha) { continue }
        $seen["$iter|$tool"] = $true
        if ($seen.ContainsKey("$iter|codex") -and $seen.ContainsKey("$iter|pr-toolkit")) {
            if (($null -eq $pairN) -or ($iter -gt $pairN)) { $pairN = $iter }
        }
    }

    $n = $null
    if (($null -ne $mechN) -and (($null -eq $pairN) -or ($mechN -ge $pairN))) { $n = $mechN }
    elseif ($null -ne $pairN) { $n = $pairN }
    else { return $result }

    # RS_PRIOR: helper state EXCLUDING iteration N's rows (--before $n).
    $rsPrior = @()
    if ($ReviewScopeAvailable) { $rsPrior = Invoke-ReviewScope $StateMd ([int]$n) }
    $priorCertified = ($rsPrior | Where-Object { $_ -eq 'CERTIFIED:yes' } | Measure-Object).Count
    $priorCleanHead = ""
    foreach ($l in $rsPrior) { if ($l -match '^LAST_CLEAN_HEAD:(.*)$') { $priorCleanHead = $matches[1] } }

    # --- Mechanical branch ---
    $mLine = ($checklist `
        | Where-Object { $_ -cmatch "^\s*-\s*\[x\]\s+Code review iteration $n — mechanical re-stamp — scope=mechanical — " -and $_ -match 'head=`([0-9a-f]+)`' } `
        | Where-Object { ([regex]::Match($_, 'head=`([0-9a-f]+)`')).Groups[1].Value -eq $HeadSha } `
        | Select-Object -Last 1)
    if ($mLine) {
        $mBase = ""
        if ($mLine -match 'base=`([0-9a-f]+)`') { $mBase = $matches[1] }
        if ((-not $ReviewScopeAvailable) -or ($priorCertified -eq 0) -or (-not $mBase) -or ($mBase -ne $priorCleanHead)) {
            return $result
        }
        $priorMechanical = ($rsPrior | Where-Object { $_ -eq 'SCOPE_REQUIRED:mechanical' } | Select-Object -First 1)
        if (-not $priorMechanical) { return $result }
        $result.clean = $true; $result.matched_iteration = [string]$n; $result.matched_head = $HeadSha
        return $result
    }

    # --- Engine-pair branch ---
    $codexLine = ($checklist `
        | Where-Object { $_ -match "^\s*-\s*\[x\]\s+Code review iteration $n — codex " -and $_ -notmatch '— codex deep-pass' } `
        | Select-Object -Last 1)
    $toolkitLine = ($checklist `
        | Where-Object { $_ -match "^\s*-\s*\[x\]\s+Code review iteration $n — pr-toolkit " } `
        | Select-Object -Last 1)
    if (-not $codexLine -or -not $toolkitLine) { return $result }

    $cScope = ""; $cBase = ""; $tScope = ""; $tBase = ""
    foreach ($pair in @(@{ tool = 'codex'; line = $codexLine }, @{ tool = 'pr-toolkit'; line = $toolkitLine })) {
        $tool = $pair.tool
        $line = $pair.line
        if ($line -cmatch 'scope=') {
            if ($line -cnotmatch 'scope=(full|delta)(\s|$)') { return $result }
            if ($line -notmatch 'base=`[0-9a-f]+`') { return $result }
            $lScope = ([regex]::Match($line, 'scope=(full|delta)(\s|$)')).Groups[1].Value
            $lBase = ([regex]::Match($line, 'base=`([0-9a-f]+)`')).Groups[1].Value
        } else {
            # Scope-less LEGACY pair: valid ONLY as certification evidence.
            if ($priorCertified -gt 0) { return $result }
            $lScope = "legacy"; $lBase = ""
        }
        if ($tool -eq 'codex') { $cScope = $lScope; $cBase = $lBase }
        else { $tScope = $lScope; $tBase = $lBase }
    }
    if (($cScope -ne $tScope) -or ($cBase -ne $tBase)) { return $result }

    if ($cScope -eq 'delta') {
        if ((-not $ReviewScopeAvailable) -or ($priorCertified -eq 0) -or (-not $priorCleanHead) -or ($cBase -ne $priorCleanHead)) {
            return $result
        }
        $priorAncestorOk = ($rsPrior | Where-Object { $_ -eq 'ANCESTOR_OK:yes' } | Select-Object -First 1)
        $priorScopeFull = ($rsPrior | Where-Object { $_ -eq 'SCOPE_REQUIRED:full' } | Select-Object -First 1)
        if ((-not $priorAncestorOk) -or $priorScopeFull) { return $result }
    } elseif ($cScope -eq 'full') {
        # Self-contained: base must be the TRUE merge-base for head (same default-ref
        # resolution as the helper / gate — no RS needed).
        # Deliberately re-derived here rather than emitted by the helper: the
        # consumers stay self-contained validators (a helper-output change can
        # never silently weaken the full-base check).
        $gateLibDir = Split-Path -Parent $ReviewScopePs1
        $gateDb = 'main'
        $dbHelper = Join-Path $gateLibDir 'default-branch.ps1'
        if (Test-Path -LiteralPath $dbHelper) {
            . $dbHelper
            $db = Get-DefaultBranch
            if ($db) { $gateDb = $db }
        }
        $gateRef = $gateDb
        & git rev-parse --verify "origin/$gateDb" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $gateRef = "origin/$gateDb" }
        $gateMb = (& git merge-base $gateRef $HeadSha 2>$null | Select-Object -First 1)
        if (-not $gateMb -or ($cBase -ne $gateMb)) { return $result }
    }
    # legacy (scope-less, uncertified) reaches here as self-contained → accept.
    $result.clean = $true; $result.matched_iteration = [string]$n; $result.matched_head = $HeadSha
    return $result
}

# ---------------------------------------------------------------------------
# Compute-BreakerFields: full-state helper run (NOT --before). Returns
# @{rounds=0; breaker='ok'; breaker_ok=$true}. Helper absence → 0/'ok'/$true.
# breaker_ok is $false ONLY when the helper says BOTH tripped AND unadjudicated.
# ---------------------------------------------------------------------------
function Compute-BreakerFields {
    $result = @{ rounds = 0; breaker = 'ok'; breaker_ok = $true }
    if (-not $ReviewScopeAvailable) { return $result }
    if (-not (Test-Path $StateMd)) { return $result }
    $rsOut = Invoke-ReviewScope $StateMd 999999
    $brk = 'ok'; $adj = 'no'
    foreach ($l in $rsOut) {
        if ($l -match '^POST_CERT_ROUNDS:(\d+)$') { $result.rounds = [int]$matches[1] }
        elseif ($l -match '^BREAKER:(.*)$') { $brk = $matches[1] }
        elseif ($l -match '^ADJUDICATED:(.*)$') { $adj = $matches[1] }
    }
    if ($brk -eq 'tripped') { $result.breaker = 'tripped' }
    if (($brk -eq 'tripped') -and ($adj -eq 'no')) { $result.breaker_ok = $false }
    return $result
}

# ---------------------------------------------------------------------------
# Compute-PlanReviewGate: returns @{clean=$false; matched_iteration="";
#   matched_plan_sha=""}
# Scoped to ## Workflow / ### Checklist. Requires a per-iter "codex clean"
# line for the same iteration N as the "Plan review loop (N iterations) — PASS"
# checkbox, with plan_sha matching the sha256 of the referenced plan file.
# Canonical clean-line stem (test-contracts.sh parity check):
#   Plan review iteration N — codex clean — plan=`<path>` — plan_sha=`<sha>`
# Canonical code stem (parity with Compute-ReviewerGate):
#   Code review iteration N — codex clean — head=`<sha>`
# ---------------------------------------------------------------------------
function Compute-PlanReviewGate {
    $result = @{ clean = $false; matched_iteration = ""; matched_plan_sha = "" }
    if (-not (Test-Path $StateMd)) { return $result }

    $lines = Read-StateMdLines
    $inWorkflow = $false
    $inChecklist = $false
    $checklist = @()
    foreach ($line in $lines) {
        if ($line -match '^## Workflow$') { $inWorkflow = $true; continue }
        if ($inWorkflow -and $line -match '^## ') { $inWorkflow = $false; $inChecklist = $false; continue }
        if (-not $inWorkflow) { continue }
        if ($line -match '^### Checklist') { $inChecklist = $true; continue }
        if ($line -match '^### ' -and $line -notmatch '^### Checklist') { $inChecklist = $false; continue }
        if ($inChecklist) { $checklist += $line }
    }

    # LAST [x] Plan review loop (N iterations) — PASS line within scope
    $passLine = ($checklist `
        | Where-Object { $_ -match '^\s*-\s*\[x\]\s+Plan review loop \(\d+ iterations\) — PASS' } `
        | Select-Object -Last 1)
    if (-not $passLine) { return $result }
    if ($passLine -match 'Plan review loop \((\d+) iterations\)') { $n = $matches[1] } else { return $result }

    # Matching per-iter clean line for iteration n (scoped lookup)
    $cleanLine = ($checklist `
        | Where-Object { $_ -match "^\s*-\s*\[x\]\s+Plan review iteration $n — " } `
        | Select-Object -Last 1)
    if (-not $cleanLine) { return $result }

    if ($cleanLine -match '— codex clean —') {
        if ($cleanLine -match 'plan=`([^`]+)`') { $planPath = $matches[1] } else { return $result }
        if ($cleanLine -match 'plan_sha=`([^`]+)`') { $claimedSha = $matches[1].ToLower() } else { return $result }
        if (-not (Test-Path $planPath)) { return $result }
        $actualSha = (Get-FileHash -Algorithm SHA256 -Path $planPath).Hash.ToLower()
        if ($actualSha -eq $claimedSha) {
            $result.clean = $true
            $result.matched_iteration = $n
            $result.matched_plan_sha = $actualSha
        } else {
            $result.matched_iteration = $n
            $result.matched_plan_sha = $claimedSha
        }
        return $result
    }
    # Codex is mandatory: only a `codex clean` line with matching plan_sha sets
    # clean=true. There is no "codex unavailable" escape. A plan-review N/A
    # escape does NOT set it true — so /goal can't self-complete without real
    # Codex evidence (mirrors e2e_report).
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
$HeadSha = ((git rev-parse HEAD 2>$null) -join "").Trim()
if ($LASTEXITCODE -ne 0) { $HeadSha = "" }

$Branch = ((git rev-parse --abbrev-ref HEAD 2>$null) -join "").Trim()
if ($LASTEXITCODE -ne 0) { $Branch = "" }

$TreeSha = ((git rev-parse "HEAD^{tree}" 2>$null) -join "").Trim()
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
        if ($E2ePath.StartsWith($pwd + "/", [System.StringComparison]::OrdinalIgnoreCase)) {
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

# Convergence breaker fields (full-state helper run).
$brkFields = Compute-BreakerFields
$PostCertRounds = $brkFields.rounds
$Breaker = $brkFields.breaker
$BreakerOk = $brkFields.breaker_ok

$prg = Compute-PlanReviewGate
$PrgClean = if ($prg.clean) { "true" } else { "false" }
$PrgIter = $prg.matched_iteration
$PrgSha = $prg.matched_plan_sha

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
if ($PrOpen -eq "true" -and $PrHeadMatch -eq "true" -and $RgClean -eq "true" -and $E2eFresh -eq "true" -and $PaAuth -eq "true" -and $BreakerOk) {
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
        $null = $fpParts.Append("`n")   # match Bash grep's trailing newline
        break
    }
}

$fpInput = $fpParts.ToString()
$fpBytes = [System.Text.Encoding]::UTF8.GetBytes($fpInput)
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha256.ComputeHash($fpBytes)
$sha256.Dispose()
$ProgressFp = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""

# Side-channel: write fingerprint to .claude/local/forge-goal-last-fingerprint so
# the stuck-detection logic in check-state-updated.ps1 can read it without
# re-running build-evidence or parsing STDERR. One line — just the SHA256 value.
# Best-effort: failure must not abort the evidence emission.
if (-not [string]::IsNullOrEmpty($ProgressFp)) {
    $sidechannel = ".claude/local/forge-goal-last-fingerprint"
    try {
        $null = New-Item -ItemType Directory -Path ".claude/local" -Force -ErrorAction SilentlyContinue
        [System.IO.File]::WriteAllText($sidechannel, $ProgressFp + "`n")
    } catch {
        # Non-blocking: ignore write failures
    }
}

# ---------------------------------------------------------------------------
# Build JSON field strings
# ---------------------------------------------------------------------------
$SessionNonceJson = Build-JsonStringField "session_nonce" $GoalNonce
$WorkflowCmdJson  = Build-JsonStringField "workflow_command" $GoalCmd
$PhaseJson        = Build-JsonStringField "phase" $Phase
$NextStepJson     = Build-JsonStringField "next_step" $NextStep
$RgIterJson       = Build-JsonStringField "matched_iteration" $RgIter
$RgHeadJson       = Build-JsonStringField "matched_head" $RgHead
$PrgIterJson      = Build-JsonStringField "matched_iteration" $PrgIter
$PrgShaJson       = Build-JsonStringField "matched_plan_sha" $PrgSha
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
    '"reviewer_gate":{"clean_same_iteration":' + $RgClean + ',' + $RgIterJson + ',' + $RgHeadJson + ',"post_cert_rounds":' + $PostCertRounds + ',"breaker":"' + $Breaker + '"},' +
    '"plan_review_gate":{"clean_same_iteration":' + $PrgClean + ',' + $PrgIterJson + ',' + $PrgShaJson + '},' +
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
