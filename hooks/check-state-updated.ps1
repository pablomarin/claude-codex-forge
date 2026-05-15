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

# Block: 3+ files changed on branch but CHANGELOG.md never updated
if ($totalChanged -gt 3 -and $changelogInBranch -eq 0 -and $changelogModified -eq 0) {
    if ($issues) {
        $issues = "$issues Update docs/CHANGELOG.md ($totalChanged files changed this session)."
    } else {
        $issues = "Update docs/CHANGELOG.md ($totalChanged files changed this session)."
    }
}

# Block using exit code 2 + stderr (robust — immune to stdout pollution)
if ($issues) {
    # Prepend workflow reminder if active (so model always sees current phase)
    if ($workflowReminder) { $issues = "[$workflowReminder] $issues" }
    [Console]::Error.WriteLine($issues)
    exit 2
}

# Advisory: remind about active workflow even when no issues (non-blocking)
if ($workflowReminder) {
    [Console]::Error.WriteLine($workflowReminder)
}

# All good, allow stop
exit 0
