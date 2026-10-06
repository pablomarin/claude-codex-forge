# .claude/hooks/check-state-updated.ps1
# This hook runs when Claude is about to stop responding.
#
# THREE CONCERNS -- only ONE blocks:
#
#   1. state.md missing breadcrumb (advisory, stderr only, exit 0).
#      Fires only when legacy CONTINUITY.md is present (signals upgraded
#      install that still needs full-refresh reconciliation). Suppressed otherwise to
#      avoid spamming every Stop event.
#
#   2. Workflow checkpoint (v6 only).
#      An unchanged canonical state hash continues the model once with the
#      current command/phase/next step; changed state stops normally.
#
#   3. CHANGELOG threshold gate (BLOCKS via exit 2).
#      If 4+ files changed on branch (committed + uncommitted) but
#      docs/CHANGELOG.md was never modified, hook blocks the stop with
#      a stderr message. This is the ONLY blocking concern.
#
# Uses exit code 2 + stderr to block (avoids JSON stdout parsing issues).
#
# Requirements: PowerShell 5.1+, git

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
    # Completed receipts are historical; PreToolUse still enforces shipping.
    if ($workflowPhase -cne 'complete' -and $workflowCommand -and $workflowCommand -notin @('none', '-', '—') -and -not $quickFixDirect) {
        $verificationReceipt = Join-Path $hookDir 'lib\verification-receipt.ps1'
        if (-not (Test-Path -LiteralPath $verificationReceipt)) { $verificationReceipt = Join-Path (Get-Location) 'hooks\lib\verification-receipt.ps1' }
        $receiptStatus = 2
        if (Test-Path -LiteralPath $verificationReceipt) {
            . $verificationReceipt
            $receiptResponse = Invoke-VerificationReceipt -ReceiptMode check -StatePath $stateMd
            $receiptStatus = $receiptResponse.Status
        }
        if ($receiptStatus -ne 0) {
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

# All git commands run in current directory (Claude cd's into worktrees)
# Only count tracked modifications (staged + unstaged), NOT untracked files (??)
$uncommittedOutput = git status --porcelain 2>$null | Where-Object { $_ -notmatch '^\?\?' }
$uncommitted = if ($uncommittedOutput) { @($uncommittedOutput).Count } else { 0 }

# Check if CHANGELOG was modified
$changelogOutput = git status --porcelain docs/CHANGELOG.md 2>$null
$changelogModified = if ($changelogOutput) { ($changelogOutput | Measure-Object -Line).Lines } else { 0 }

# Get branch base for comparison
# Resolve repo default branch via the shared helper.
# CRITICAL: dot-source (not subprocess) — Windows ships powershell.exe (5.1),
# spawning pwsh (7+) would fail on stock Windows. Dot-source works in both.
$hookDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libPath = Join-Path $hookDir "lib\default-branch.ps1"
$defaultBranch = "main"  # fallback if helper or git fails
$helperBailed = $false
if (Test-Path $libPath) {
    . $libPath
    $detected = Get-DefaultBranch
    if ($detected) {
        $defaultBranch = $detected
    } else {
        $helperBailed = $true
    }
} else {
    $helperBailed = $true
}
# Helper-bail breadcrumb (stderr): mirrors the bash hook so silent fallback to "main"
# is at least diagnosable on master-default Windows installs.
if ($helperBailed) {
    [Console]::Error.WriteLine("⚠ check-state-updated: default-branch helper bailed; assuming 'main'")
}
# Merge-base fallback chain: prefer local <default>; else origin/<default>
# (single-branch clones may have only the remote-tracking ref); else HEAD~10.
$branchBase = $null
$null = git rev-parse --verify $defaultBranch 2>$null
if ($LASTEXITCODE -eq 0) {
    $branchBase = git merge-base $defaultBranch HEAD 2>$null
} else {
    $null = git rev-parse --verify "origin/$defaultBranch" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $branchBase = git merge-base "origin/$defaultBranch" HEAD 2>$null
    }
}
if (-not $branchBase) { $branchBase = "HEAD~10" }

# Count files changed on branch
$branchChangedOutput = git diff --name-only $branchBase HEAD 2>$null
$branchChanged = if ($branchChangedOutput) { ($branchChangedOutput | Measure-Object -Line).Lines } else { 0 }

$uncommittedFilesOutput = git diff --name-only 2>$null
$uncommittedFiles = if ($uncommittedFilesOutput) { ($uncommittedFilesOutput | Measure-Object -Line).Lines } else { 0 }

$totalChanged = $branchChanged + $uncommittedFiles

# Check if CHANGELOG was updated anywhere on branch
$changelogInBranch = 0
if ($branchChangedOutput) {
    $changelogInBranch = ($branchChangedOutput | Select-String "CHANGELOG.md" | Measure-Object).Count
}

# --- Workflow state tracking ---
# State file is gitignored. Emit breadcrumb only when legacy CONTINUITY.md is also present
# (signals user upgraded but hasn't migrated) — avoid spamming every Stop event.
if ((-not $stateMd -or -not (Test-Path $stateMd)) -and (Test-Path "CONTINUITY.md")) {
    [Console]::Error.WriteLine("ℹ check-state-updated: Forge state.md not found, but CONTINUITY.md exists.")
    [Console]::Error.WriteLine("  Run setup -Force -DryRun, resolve every reported blocker, then run setup -Force.")
    # Continue to CHANGELOG check — gates are independent.
}

# Workflow reminder — read .claude/local/state.md (gitignored), single-line format.
#
# IMPORTANT: scope the extraction to ONLY the `## Workflow` section. Migrated
# content carried forward from an older Forge state source (for example old "### Done"
# entries that mention prior workflow scaffolds) can leave stray `| Command |`
# lines elsewhere in the file. A whole-file Select-String would match every one
# of them; even with `Select-Object -First 1` the FIRST hit can be the stray if
# it appears before the canonical scaffold. Scope first, then match.
$workflowReminder = ""
if ($stateMd -and (Test-Path $stateMd)) {
    $stateContent = (Get-Content $stateMd -Raw -ErrorAction SilentlyContinue) -replace "`r", ""
    if (-not [string]::IsNullOrEmpty($stateContent)) {
        # Extract just the `## Workflow` block (between `## Workflow` and the next `## ` heading).
        $workflowBlockLines = @()
        $inWorkflow = $false
        foreach ($line in ($stateContent -split "`n")) {
            if ($line -match '^## Workflow$') { $inWorkflow = $true; continue }
            if ($inWorkflow -and $line -match '^## ') { break }
            if ($inWorkflow) { $workflowBlockLines += $line }
        }
        $cmdLine = ($workflowBlockLines | Select-String '\|\s*Command\s*\|' | Select-Object -First 1)
        if ($cmdLine) {
            $cmd = ($cmdLine -split '\|')[2].Trim()
            if ($cmd -and $cmd -ne "none" -and $cmd -ne ([char]0x2014).ToString() -and $cmd -ne "-") {
                $phaseLine = ($workflowBlockLines | Select-String '\|\s*Phase\s*\|' | Select-Object -First 1)
                $nextLine = ($workflowBlockLines | Select-String '\|\s*Next step\s*\|' | Select-Object -First 1)
                $phase = if ($phaseLine) { ($phaseLine -split '\|')[2].Trim() } else { "" }
                $next = if ($nextLine) { ($nextLine -split '\|')[2].Trim() } else { "" }
                if ($phase -cne "complete") { $workflowReminder = "WORKFLOW: $cmd | Phase: $phase | Next: $next" }
            }
        }
    }
}

# Build response
$issues = ""

# Block: 3+ files changed on branch but CHANGELOG.md never updated.
# "files changed on branch vs $defaultBranch" — count is committed + uncommitted
# diff vs the merge-base, NOT files-this-turn.
if ($totalChanged -gt 3 -and $changelogInBranch -eq 0 -and $changelogModified -eq 0) {
    if ($issues) {
        $issues = "$issues Update docs/CHANGELOG.md ($totalChanged files changed on branch vs $defaultBranch)."
    } else {
        $issues = "Update docs/CHANGELOG.md ($totalChanged files changed on branch vs $defaultBranch)."
    }
}

# Block using exit code 2 + stderr (robust — immune to stdout pollution)
if ($issues) {
    # Prepend workflow reminder if active (so model always sees current phase)
    if ($workflowReminder) { $issues = "[$workflowReminder] $issues" }
    [Console]::Error.WriteLine($issues)

    # Detect open PR for current branch. Once a PR is open, the CHANGELOG gate
    # downgrades from blocking (exit 2) to advisory (exit 0): the human reviewer
    # carries the signal, and per-turn blocking during CI wait is just noise.
    # gh availability and network are best-effort; on failure, default to "no
    # open PR" so the original blocking behavior is preserved.
    # Probe only runs when $issues is non-empty — clean stops pay no gh-API cost.
    $prOpen = $false
    $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghCmd) {
        $prState = (& gh pr view --json state -q .state 2>$null) | Out-String
        if ($prState.Trim() -eq "OPEN") { $prOpen = $true }
    }

    if ($prOpen) {
        # Advisory only — PR already open. Exit 0 so the message is informational
        # and the build-evidence STDERR dump is not labeled "Stop hook error".
        Exit-ForgeAllow
    }
    exit 2
}

# A changed v6 state checkpoint stops normally. If the exact state hash remains
# unchanged across normal Stops, give the model one visible continuation turn.
if ($workflowReminder) {
    if ($stateLocalDir -ne ".forge/local") {
        [Console]::Error.WriteLine($workflowReminder)
        Exit-ForgeAllow
    }
    try {
        $stateStopHash = (Get-FileHash -LiteralPath $stateMd -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    } catch {
        [Console]::Error.WriteLine("FORGE_STATE_INVALID: could not hash canonical state checkpoint")
        exit 2
    }
    # .NET relative writes retain the process cwd after Set-Location; bind
    # checkpoint paths to the resolved event-worktree state directory.
    $stateStopDirectory = Split-Path -Parent $stateMd
    $stateStopFile = Join-Path $stateStopDirectory "state-last-stop.sha256"
    $stateStopItem = Get-Item -LiteralPath $stateStopFile -Force -ErrorAction SilentlyContinue
    if ($stateStopItem -and (($stateStopItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $stateStopItem.PSIsContainer)) {
        [Console]::Error.WriteLine("FORGE_STATE_INVALID: invalid state checkpoint sidecar")
        exit 2
    }
    $stateStopPrevious = ""
    if ($stateStopItem) { $stateStopPrevious = ([IO.File]::ReadAllText($stateStopFile)).Trim() }
    if ($stateStopPrevious -ne $stateStopHash) {
        $stateStopTemp = Join-Path $stateStopDirectory (".state-last-stop." + [Guid]::NewGuid().ToString("N"))
        try {
            [IO.File]::WriteAllText($stateStopTemp, "$stateStopHash`n", (New-Object Text.UTF8Encoding($false)))
            Move-Item -LiteralPath $stateStopTemp -Destination $stateStopFile -Force
        } catch {
            Remove-Item -LiteralPath $stateStopTemp -Force -ErrorAction SilentlyContinue
            [Console]::Error.WriteLine("FORGE_STATE_INVALID: could not publish state checkpoint sidecar")
            exit 2
        }
        Exit-ForgeAllow
    }
    [Console]::Error.WriteLine("$workflowReminder. Run .forge/hooks/lib/workflow-state.ps1 show before continuing; use workflow-state.ps1 checkpoint for its exact next step and record any durable learning in the appropriate Forge memory layer before stopping.")
    exit 2
}

# All good, allow stop
Exit-ForgeAllow
