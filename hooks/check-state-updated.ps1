# .claude/hooks/check-state-updated.ps1
# This hook runs when Claude is about to stop responding.
#
# THREE CONCERNS -- only ONE blocks:
#
#   1. state.md missing breadcrumb (advisory, stderr only, exit 0).
#      Fires only when legacy CONTINUITY.md is present (signals upgraded
#      install that hasn't run -Migrate yet). Suppressed otherwise to
#      avoid spamming every Stop event.
#
#   2. Workflow reminder (advisory, stderr only, exit 0).
#      Reads .claude/local/state.md ## Workflow table; emits
#      "WORKFLOW: <cmd> | Phase: <n> | Next: <step>" so the model always
#      sees current phase even when no issues fire.
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

# Parse JSON input
try {
    $data = $jsonInput | ConvertFrom-Json
} catch {
    # If JSON parsing fails, allow stop
    exit 0
}

# Emit FORGE_GOAL evidence FIRST — must run on every Stop call,
# including those with stop_hook_active=true (active /goal loop),
# so the /goal verifier sees the current evidence in transcript.
$projectDir = $env:CLAUDE_PROJECT_DIR
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$evidenceScript = Join-Path $projectDir ".claude/hooks/build-evidence.ps1"
if (Test-Path $evidenceScript) {
    try {
        & $evidenceScript
    } catch {
        # Non-blocking: write one warning to stderr; don't break the Stop hook.
        [Console]::Error.WriteLine("WARN: build-evidence.ps1 failed: $($_.Exception.Message)")
    }
}

# ---------------------------------------------------------------------------
# Task 8: /forge-goal stuck-detection soft warning.
#
# Fires after build-evidence (which writes .claude/local/forge-goal-last-fingerprint
# as a side-channel). After 5 consecutive identical progress_fingerprint values,
# emits FORGE_GOAL_STUCK_WARNING to STDERR. Informational only — does NOT abort.
# Fires even when stop_hook_active=true. Counter lives in
# .claude/local/forge-goal-stuck-count: format "<count>|<fingerprint_sha256>".
# PS 5.1 compatible: no ??, [Console]::Error.WriteLine for STDERR.
# ---------------------------------------------------------------------------
function Invoke-ForgeGoalStuckCheck {
    $stateMd = ".claude/local/state.md"
    $fpFile   = ".claude/local/forge-goal-last-fingerprint"
    $ctrFile  = ".claude/local/forge-goal-stuck-count"

    # Only proceed if /forge-goal is active: state.md must have a non-empty
    # nonce in the ## /goal session table.
    if (-not (Test-Path $stateMd)) { return }

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
    if ([string]::IsNullOrEmpty($nonce)) { return }

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
        $null = New-Item -ItemType Directory -Path ".claude/local" -Force -ErrorAction SilentlyContinue
        [System.IO.File]::WriteAllText($ctrFile, "$newCount|$currentFp`n")
    } catch {
        # Non-blocking: ignore write failures
    }

    # Emit warning if threshold reached (>= 5 consecutive identical fingerprints).
    if ($newCount -ge 5) {
        [Console]::Error.WriteLine("FORGE_GOAL_STUCK_WARNING: no measurable progress for $newCount consecutive turns (fingerprint unchanged). Consider invoking /council, checkpointing state.md, or surfacing a blocker. Loop continues — this is informational only.")
    }
}
Invoke-ForgeGoalStuckCheck

# Check if stop_hook_active to prevent infinite loops
if ($data.stop_hook_active -eq $true) {
    exit 0
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
if (-not (Test-Path ".claude/local/state.md") -and (Test-Path "CONTINUITY.md")) {
    [Console]::Error.WriteLine("ℹ check-state-updated: .claude/local/state.md not found, but CONTINUITY.md exists.")
    [Console]::Error.WriteLine("  Run setup --migrate to move your content to the new structure.")
    # Continue to CHANGELOG check — gates are independent.
}

# Workflow reminder — read .claude/local/state.md (gitignored), single-line format.
#
# IMPORTANT: scope the extraction to ONLY the `## Workflow` section. Migrated
# content (e.g., from `setup.sh --migrate` ingesting old CONTINUITY.md "### Done"
# entries that mention prior workflow scaffolds) can leave stray `| Command |`
# lines elsewhere in the file. A whole-file Select-String would match every one
# of them; even with `Select-Object -First 1` the FIRST hit can be the stray if
# it appears before the canonical scaffold. Scope first, then match.
$workflowReminder = ""
if (Test-Path ".claude/local/state.md") {
    $stateContent = Get-Content ".claude/local/state.md" -Raw -ErrorAction SilentlyContinue
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
                $workflowReminder = "WORKFLOW: $cmd | Phase: $phase | Next: $next"
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
        exit 0
    }
    exit 2
}

# Advisory: remind about active workflow even when no issues (non-blocking)
if ($workflowReminder) {
    [Console]::Error.WriteLine($workflowReminder)
}

# All good, allow stop
exit 0
