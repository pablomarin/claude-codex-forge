# Shared Stop checks for Claude Code and Codex.
# Preserve canonical state validation, Goal accounting and final-evidence
# advisories. Ordinary replies never require a state edit or changelog update;
# those belong to durable workflow checkpoints and finalization respectively.
# Blocking integrity failures use exit 2 with stderr diagnostics.

# Read the hook input from stdin
$jsonInput = [Console]::In.ReadToEnd()
function Exit-ForgeAllow { if ($data.host -eq "codex") { Write-Output "{}" }; exit 0 }

# Parse JSON input
try {
    $data = $jsonInput | ConvertFrom-Json
} catch {
    # If JSON parsing fails, allow stop
    Exit-ForgeAllow
}

# ---------------------------------------------------------------------------
# Worktree CWD fix (v5.32) — CC's Stop hook runs with CWD=$CLAUDE_PROJECT_DIR
# (the parent project in worktree sessions), but the user's actual session
# CWD lives in the stdin JSON. cd there so relative state.md reads and git
# ops target the worktree, not the main repo.
# Fallback: git rev-parse --show-toplevel → current CWD.
# ---------------------------------------------------------------------------
$hookCwd = ""
if ($data -and $data.PSObject.Properties['cwd']) {
    $hookCwd = [string]$data.cwd
}
if ($hookCwd -and (Test-Path -LiteralPath $hookCwd -PathType Container)) {
    # Normalize to repo/worktree root in case stdin.cwd is a subdirectory.
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

$hookDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateHelper = Join-Path $hookDir "lib\state-path.ps1"
if (-not (Test-Path -LiteralPath $stateHelper)) {
    $stateHelper = Join-Path (Get-Location) "hooks\lib\state-path.ps1"
}
$stateMd = ""
if (Test-Path -LiteralPath $stateHelper) {
    try {
        . $stateHelper
        $stateMd = Get-ForgeStatePath -Root (Get-Location).Path -Mode Read
    } catch {
        $canonicalSurface = $false
        foreach ($surface in @(".forge\version", ".forge\local", ".forge\local\state.md")) {
            if (Get-Item -LiteralPath (Join-Path (Get-Location).Path $surface) -Force -ErrorAction SilentlyContinue) { $canonicalSurface = $true; break }
        }
        $forgeRootItem = Get-Item -LiteralPath (Join-Path (Get-Location).Path ".forge") -Force -ErrorAction SilentlyContinue
        if ($forgeRootItem -and ($forgeRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $canonicalSurface = $true }
        if ($canonicalSurface) {
            [Console]::Error.WriteLine([string]$_.Exception.Message)
            [Console]::Error.WriteLine("FORGE_STATE_INVALID: canonical v6 state could not be resolved")
            exit 2
        }
        $stateMd = ""
    }
}
$stateLocalDir = ".forge/local"
if (($stateMd -replace '\\', '/') -match '/\.claude/local/state\.md$') { $stateLocalDir = ".claude/local" }

# Stop is self-sufficient when the side channel is missing or older than state.
if ($stateLocalDir -eq ".forge/local" -and -not [string]::IsNullOrEmpty($stateMd) -and (Test-Path -LiteralPath $stateMd -PathType Leaf)) {
    $fp = Join-Path $stateLocalDir "forge-goal-last-fingerprint"
    $needsEvidence = -not (Test-Path -LiteralPath $fp -PathType Leaf)
    if (-not $needsEvidence) { $needsEvidence = (Get-Item -LiteralPath $stateMd).LastWriteTimeUtc -gt (Get-Item -LiteralPath $fp).LastWriteTimeUtc }
    $builder = Join-Path $hookDir "build-evidence.ps1"
    if ($needsEvidence -and (Test-Path -LiteralPath $builder -PathType Leaf)) { $jsonInput | & $builder 2>&1 | ForEach-Object { [Console]::Error.WriteLine($_) } }

    $receiptStateRaw = (Get-Content -LiteralPath $stateMd -Raw) -replace "`r", ""
    $workflowCommandRows = @()
    $workflowPhaseRows = @()
    $inWorkflow = $false
    foreach ($line in @($receiptStateRaw -split "`n")) {
        if ($line -ceq '## Workflow') { $inWorkflow = $true; continue }
        if ($inWorkflow -and $line.StartsWith('## ')) { $inWorkflow = $false }
        if (-not $inWorkflow) { continue }
        $parts = $line -split '\|'
        if ($parts.Count -ge 4 -and $parts[1].Trim() -ceq 'Command') { $workflowCommandRows += $parts[2].Trim() }
        if ($parts.Count -ge 4 -and $parts[1].Trim() -ceq 'Phase') { $workflowPhaseRows += $parts[2].Trim() }
    }
    $workflowCommand = if ($workflowCommandRows.Count -eq 1) { [string]$workflowCommandRows[0] } else { "" }
    $workflowPhase = if ($workflowPhaseRows.Count -eq 1) { [string]$workflowPhaseRows[0] } else { "" }
    $quickFixDirect = $workflowCommand -cmatch '^/quick-fix [a-z0-9]+(-[a-z0-9]+)*$'
    $workflowWaivedGates = @()
    $waiverHelper = Join-Path $hookDir 'lib\verification-receipt.ps1'
    if (-not (Test-Path -LiteralPath $waiverHelper)) { $waiverHelper = Join-Path (Get-Location) 'hooks\lib\verification-receipt.ps1' }
    $waiverSidecarPresent = $false
    $candidateRows = @()
    foreach ($row in @($receiptStateRaw -split "`n")) {
        $cells = $row.Split('|')
        if ($cells.Count -ge 4 -and $cells[1].Trim() -ceq 'Candidate receipt') { $candidateRows += $cells[2].Trim() }
    }
    if ($candidateRows.Count -eq 1 -and $candidateRows[0]) {
        try {
            $waiverCandidate = if ([IO.Path]::IsPathRooted($candidateRows[0])) { $candidateRows[0] } else { Join-Path (Get-Location).Path $candidateRows[0] }
            foreach ($suffix in @('workflow-waiver','review-waiver')) {
                if (Get-Item -LiteralPath "$waiverCandidate.$suffix" -Force -ErrorAction SilentlyContinue) { $waiverSidecarPresent = $true }
            }
        } catch { $waiverSidecarPresent = $false }
    }
    # Presence is only a cheap activation guard; the helper still validates everything.
    if ($waiverSidecarPresent -and (Test-Path -LiteralPath $waiverHelper)) {
        try {
            $stopWaiver = & { . $waiverHelper; Invoke-VerificationReceipt -ReceiptMode check-workflow-waiver -StatePath $stateMd -ReceiptBoundary stop }
            if ($stopWaiver.Status -eq 0) {
                $scopeLine = @($stopWaiver.Lines | Where-Object { $_.StartsWith('WAIVED_GATES:') })
                if ($scopeLine.Count -eq 1) { $workflowWaivedGates = $scopeLine[0].Substring(13).Split(',') }
                [Console]::Error.WriteLine("FORGE_WORKFLOW_WAIVED: $($workflowWaivedGates -join ','); unwaived shipping checks remain required.")
            }
        } catch { }
    }
    # Final receipts belong to finalization, not ordinary development stops.
    # PreToolUse continues enforcing shipping regardless of the recorded phase.
    $finalEvidencePhase = $workflowPhase -cin @('review', 'verify', 'verification', 'finalize', 'finalization', 'promote', 'promotion', 'ship', 'shipping')
    if ($finalEvidencePhase -and $workflowCommand -and $workflowCommand -notin @('none', '-', '—') -and -not $quickFixDirect) {
        $verificationReceipt = Join-Path $hookDir 'lib\verification-receipt.ps1'
        if (-not (Test-Path -LiteralPath $verificationReceipt)) { $verificationReceipt = Join-Path (Get-Location) 'hooks\lib\verification-receipt.ps1' }
        $receiptStatus = 2
        if (Test-Path -LiteralPath $verificationReceipt) {
            $receiptResponse = & { . $verificationReceipt; Invoke-VerificationReceipt -ReceiptMode check -StatePath $stateMd }
            $receiptStatus = $receiptResponse.Status
        }
        if ($receiptStatus -ne 0 -and @($workflowWaivedGates).Count -eq 0) {
            [Console]::Error.WriteLine('FORGE_FINAL_EVIDENCE_STALE: candidate-bound review, verify-app, and E2E receipts no longer certify the current staged-clean candidate.')
        }
    }
}

# Native Goal accounting is repository-local and shared through Git's common
# directory, so the same objective continues across linked worktrees and engines.
if ($stateLocalDir -eq ".forge/local" -and -not [string]::IsNullOrEmpty($stateMd) -and (Test-Path -LiteralPath $stateMd -PathType Leaf)) {
    $goalNonce = ""
    $insideGoal = $false
    foreach ($line in @(((Get-Content -LiteralPath $stateMd -Raw) -replace "`r", "") -split "`n")) {
        if ($line -ceq "## /goal session") { $insideGoal = $true; continue }
        if ($insideGoal -and $line.StartsWith("## ", [StringComparison]::Ordinal)) { $insideGoal = $false }
        if ($insideGoal -and $line -match '^\|\s*nonce\s*\|\s*([^|]*?)\s*\|$') { $goalNonce = $Matches[1].Trim(); break }
    }
    if ($goalNonce -and $goalNonce -ne "<uuid-v4-lowercase>") {
        $goalEventId = ""
        foreach ($name in @("turn_id", "hook_turn_id", "assistant_message_id", "last_assistant_message")) {
            if ($data.PSObject.Properties[$name] -and $data.$name) { $goalEventId = [string]$data.$name; break }
        }
        if (-not $goalEventId) { $goalNonce = "" }
    }
    if ($goalNonce -and $goalNonce -ne "<uuid-v4-lowercase>") {
        $goalLedger = Join-Path $hookDir "lib\goal-ledger.ps1"
        if (-not (Test-Path -LiteralPath $goalLedger -PathType Leaf)) {
            [Console]::Error.WriteLine("FORGE_GOAL_LEDGER_TAMPERED: repository-local goal ledger helper is missing")
            exit 2
        }
        $jsonInput | & $goalLedger charge -Project (Get-Location).Path -State $stateMd -EventJson -
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}

# Note: build-evidence is no longer invoked inline. It runs as its own Stop
# hook entry (registered in settings.template.json) BEFORE this one — so its
# STDERR output is rendered as informational hook output rather than being
# merged with our exit-2 stderr and labeled "Stop hook error" by CC.
# build-evidence still writes the fingerprint side-channel file that the
# stuck-detection logic below reads.

# ---------------------------------------------------------------------------
# Task 8: /forge-goal stuck-detection soft warning.
#
# build-evidence.ps1 runs as a separate Stop hook entry BEFORE this one and
# writes the current progress_fingerprint to
# .claude/local/forge-goal-last-fingerprint as a side-channel. We read it
# here. After 5 consecutive identical fingerprints, emit
# FORGE_GOAL_STUCK_WARNING to STDERR. Informational only — does NOT abort.
# Fires even when stop_hook_active=true. Counter lives in
# .claude/local/forge-goal-stuck-count: format "<count>|<fingerprint_sha256>".
# PS 5.1 compatible: no ??, [Console]::Error.WriteLine for STDERR.
# ---------------------------------------------------------------------------
function Invoke-ForgeGoalStuckCheck {
    # Only proceed if /forge-goal is active: state.md must have a non-empty
    # nonce in the ## /goal session table.
    if ([string]::IsNullOrEmpty($stateMd) -or -not (Test-Path -LiteralPath $stateMd)) { return }
    $stateDirectory = Split-Path -Parent $stateMd
    $fpFile = Join-Path $stateDirectory "forge-goal-last-fingerprint"
    $ctrFile = Join-Path $stateDirectory "forge-goal-stuck-count"

    $raw = Get-Content $stateMd -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($raw)) { return }

    # CRLF normalize then extract nonce from ## /goal session block.
    $lines = ($raw -replace "`r", "") -split "`n"
    $inSection = $false
    $nonce = ""
    foreach ($line in $lines) {
        if ($line -match '^## /goal session$') { $inSection = $true; continue }
        if ($inSection -and $line -match '^## ') { break }
        if (-not $inSection) { continue }
        if ($line -match '^\|\s*nonce\s*\|\s*(.+?)\s*\|') {
            $nonce = $matches[1].Trim()
            break
        }
    }
    if ([string]::IsNullOrEmpty($nonce) -or $nonce -eq "<uuid-v4-lowercase>") { return }

    # Read the current fingerprint written by build-evidence.ps1.
    if (-not (Test-Path $fpFile)) { return }
    $currentFp = (Get-Content $fpFile -Raw -ErrorAction SilentlyContinue)
    if ([string]::IsNullOrEmpty($currentFp)) { return }
    $currentFp = $currentFp.Trim()
    if ([string]::IsNullOrEmpty($currentFp)) { return }

    # Read previous counter state (format: "<count>|<fingerprint>").
    $prevCount = 0
    $prevFp    = ""
    if (Test-Path $ctrFile) {
        $ctrRaw = (Get-Content $ctrFile -Raw -ErrorAction SilentlyContinue)
        if (-not [string]::IsNullOrEmpty($ctrRaw)) {
            $ctrRaw = $ctrRaw.Trim()
            $pipeIdx = $ctrRaw.IndexOf('|')
            if ($pipeIdx -gt 0) {
                $countStr = $ctrRaw.Substring(0, $pipeIdx)
                $prevFp   = $ctrRaw.Substring($pipeIdx + 1)
                $parsedCount = 0
                if ([int]::TryParse($countStr, [ref]$parsedCount) -and $parsedCount -ge 0) {
                    $prevCount = $parsedCount
                }
            }
        }
    }

    # Update counter: increment if fingerprint unchanged, reset if changed.
    $newCount = if ($currentFp -eq $prevFp) { $prevCount + 1 } else { 1 }

    # Persist updated counter (WriteAllText to avoid BOM that Set-Content adds).
    try {
        $null = New-Item -ItemType Directory -Path $stateDirectory -Force -ErrorAction SilentlyContinue
        [System.IO.File]::WriteAllText($ctrFile, "$newCount|$currentFp`n")
    } catch {
        # Non-blocking: ignore write failures
    }

    # Emit warning if threshold reached (>= 5 consecutive identical fingerprints).
    if ($newCount -ge 5) {
        [Console]::Error.WriteLine("FORGE_GOAL_STUCK_WARNING: no measurable progress for $newCount consecutive turns (fingerprint unchanged). If progress is blocked because a genuine non-destructive decision is required to continue the active native Goal, invoke /council; otherwise checkpoint state.md or surface a blocker. Loop continues — this is informational only.")
    }
}
Invoke-ForgeGoalStuckCheck

# Check if stop_hook_active to prevent infinite loops
if ($data.stop_hook_active -eq $true) {
    Exit-ForgeAllow
}

# --- Workflow state tracking ---
# State file is gitignored. Emit breadcrumb only when legacy CONTINUITY.md is also present
# (signals user upgraded but hasn't migrated) — avoid spamming every Stop event.
if ((-not $stateMd -or -not (Test-Path $stateMd)) -and (Test-Path "CONTINUITY.md")) {
    [Console]::Error.WriteLine("ℹ check-state-updated: Forge state.md not found, but CONTINUITY.md exists.")
    [Console]::Error.WriteLine("  Run setup -Force -DryRun, resolve every reported blocker, then run setup -Force.")
}

# All good, allow stop
Exit-ForgeAllow
