# .claude/hooks/check-workflow-gates.ps1
# PreToolUse hook for Bash: blocks commit/push/PR if quality gates aren't complete.
#
# Fires BEFORE Bash commands. Only activates when:
# 1. An active workflow exists in .claude/local/state.md (Command != none)
# 2. The command is git commit, git push, or gh pr create
# 3. Always-required quality gate checklist items aren't checked off
#
# Gated markers (canonical vocabulary — see rules/testing.md):
#   "Code review loop"  — code review must pass
#   "Simplified"        — simplification must run
#   "Verified (tests"   — tests/lint/types/migrations must pass
#   "E2E verified"      — Phase 5.4 must pass OR be checked [x] with N/A reason
#
# Non-gated (conditional) items ("E2E use cases designed", "E2E regression
# passed", post-PASS housekeeping) stay advisory — the model decides.
# The E2E verified gate has an explicit N/A escape:
#   - [x] E2E verified — N/A: <reason>
#
# Requirements: PowerShell 5.1+

# Read hook input from stdin
$jsonInput = [Console]::In.ReadToEnd()

# Parse JSON input
try {
    $data = $jsonInput | ConvertFrom-Json
} catch {
    exit 0
}

$command = $data.tool_input.command
if (-not $command) { exit 0 }

# --- Only gate ship actions ---
$isShip = $false
if ($command -match '^\s*git\s+commit\b') { $isShip = $true }
if ($command -match '^\s*git\s+push\b') { $isShip = $true }
if ($command -match '^\s*gh\s+pr\s+create\b') { $isShip = $true }

if (-not $isShip) { exit 0 }

# --- Block compound ship commands ---
# A compound like `git commit -m x && git push` validates evidence against the
# pre-commit HEAD, passes, then the chained push ships the new (unreviewed)
# HEAD with no second gate check. Detect a ship verb AFTER a separator
# (&&, ||, ;, |) and block — force the user to run each ship action
# individually so every one gets its own gate evaluation.
$compoundTail = $command -replace '^[^&|;]*[&|;]+', ''
if ($compoundTail -ne $command) {
    if ($compoundTail -match '(git\s+commit\b|git\s+push\b|gh\s+pr\s+create\b)') {
        [Console]::Error.WriteLine("WORKFLOW GATE: compound ship command blocked.")
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("This command chains a ship action (git commit / git push / gh pr create)")
        [Console]::Error.WriteLine("with another command via &&, ||, ;, or |. Each ship action must be run")
        [Console]::Error.WriteLine("individually so the workflow gate can validate evidence against the exact")
        [Console]::Error.WriteLine("HEAD being shipped. A chained 'git commit && git push' would ship a new,")
        [Console]::Error.WriteLine("unreviewed HEAD past the gate.")
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("Run each ship action as its own command.")
        exit 2
    }
}

# --- Check for active workflow (post PR #2: state file is .claude/local/state.md) ---
$stateFile = ".claude/local/state.md"

if (-not (Test-Path $stateFile)) {
    # Hard-cut: do NOT fall back to CONTINUITY.md.
    # Breadcrumb wording byte-equivalent to bash variant for AC-4 parity.
    [Console]::Error.WriteLine("ℹ check-workflow-gates: $stateFile not found.")
    [Console]::Error.WriteLine("  If you have a legacy CONTINUITY.md and just upgraded, run setup --migrate")
    exit 0
}

$content = Get-Content $stateFile -Raw -ErrorAction SilentlyContinue

# Scope extraction to ONLY the `## Workflow` section. Migrated content (e.g.,
# from `setup.sh --migrate` ingesting old CONTINUITY.md "### Done" entries that
# mention prior workflow scaffolds) can leave stray `| Command |` lines or
# `### Checklist` headings elsewhere in the file. A whole-file Select-String
# with `-First 1` would pick the first match — which can be the stray, not the
# canonical scaffold — and gate (or fail to gate) on bogus content.
# CRLF normalize BEFORE splitting. A CRLF-encoded state.md (Windows checkout)
# would leave trailing \r so `^## Workflow$` never matches → empty block →
# hook bails exit 0 → ALL gates silently bypassed. Strip \r first (mirrors
# build-evidence.ps1's Read-StateMdLines).
$workflowBlockLines = @()
$inWorkflow = $false
foreach ($line in (($content -replace "`r", "") -split "`n")) {
    if ($line -match '^## Workflow$') { $inWorkflow = $true; continue }
    if ($inWorkflow -and $line -match '^## ') { break }
    if ($inWorkflow) { $workflowBlockLines += $line }
}

$cmdLine = ($workflowBlockLines | Select-String '\|\s*Command\s*\|' | Select-Object -First 1)
if (-not $cmdLine) { exit 0 }

$cmd = ($cmdLine -split '\|')[2].Trim()
if (-not $cmd -or $cmd -eq "none" -or $cmd -eq ([char]0x2014).ToString() -or $cmd -eq "-") { exit 0 }

# ---------------------------------------------------------------------------
# Layer 2 — /forge-goal PR-create authorization guard (PS parity for .sh)
#
# ACTIVE definition: $goalNonce is non-empty after parsing. An empty nonce
# cell, missing /goal session section, or missing state.md → guard is no-op.
# LAST-LINE defense: multiple PR auth lines → use last (REPLACE semantics
# should keep exactly one; multiple = state.md corruption, surface to user).
# PS 5.1 constraints: no ??, no Out-Null on STDERR, no pwsh spawn,
# [Console]::Error.WriteLine for STDERR, CRLF normalize before regex.
# ---------------------------------------------------------------------------
if ($command -match '^\s*gh\s+pr\s+create\b') {
    if (Test-Path $stateFile) {
        # CRLF normalize, then scope to ## /goal session block
        $raw = Get-Content $stateFile -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { $raw = "" }
        $allLines = ($raw -replace "`r", "") -split "`n"
        $inSession = $false
        $goalNonce = ""
        foreach ($line in $allLines) {
            if ($line -match '^## /goal session$') { $inSession = $true; continue }
            if ($inSession -and $line -match '^## ') { break }
            if (-not $inSession) { continue }
            if ($line -match '^\|\s*nonce\s*\|\s*(.+?)\s*\|$') {
                $goalNonce = $matches[1].Trim()
            }
        }

        if ($goalNonce) {
            # /forge-goal is active (non-empty nonce); enforce PR-auth requirements
            $headSha = ""
            try { $headSha = ((git rev-parse HEAD 2>$null) -join "").Trim() } catch {}

            # Collect ALL auth lines, use LAST (stale-duplicate defense)
            $prAuthLines = @()
            foreach ($line in $allLines) {
                if ($line -match '^-\s*\[x\]\s+PR creation authorized') {
                    $prAuthLines += $line
                }
            }
            $prAuthLine = if ($prAuthLines.Count -gt 0) { $prAuthLines[-1] } else { "" }

            if ($prAuthLines.Count -gt 1) {
                [Console]::Error.WriteLine("WORKFLOW GATE WARNING: Multiple PR authorization lines found ($($prAuthLines.Count)). State.md corruption — REPLACE semantics should keep exactly one. Using LAST line.")
            }

            if (-not $prAuthLine) {
                [Console]::Error.WriteLine("WORKFLOW GATE: gh pr create blocked — no ## PR authorization line in state.md.")
                [Console]::Error.WriteLine("")
                [Console]::Error.WriteLine("A /forge-goal-driven workflow is active (nonce: $goalNonce).")
                [Console]::Error.WriteLine("PR creation requires user authorization via AskUserQuestion.")
                [Console]::Error.WriteLine("On user YES, REPLACE any existing ## PR authorization content with:")
                [Console]::Error.WriteLine("  - [x] PR creation authorized — ``<ts>`` — nonce=``<n>`` — head=``<sha>``")
                exit 2
            }

            $authNonce = ""
            $authHead = ""
            if ($prAuthLine -match 'nonce=`([^`]+)`') { $authNonce = $matches[1] }
            if ($prAuthLine -match 'head=`([^`]+)`')  { $authHead = $matches[1] }

            if ($authNonce -ne $goalNonce) {
                [Console]::Error.WriteLine("WORKFLOW GATE: gh pr create blocked — PR authorization nonce mismatch.")
                [Console]::Error.WriteLine("Session nonce:   $goalNonce")
                [Console]::Error.WriteLine("Auth line nonce: $authNonce")
                [Console]::Error.WriteLine("Stale authorization from a previous /forge-goal session. Re-authorize via AskUserQuestion.")
                [Console]::Error.WriteLine("  - [x] PR creation authorized — ``<ts>`` — nonce=``<n>`` — head=``<sha>``")
                exit 2
            }

            if (-not $headSha -or $authHead -ne $headSha) {
                [Console]::Error.WriteLine("WORKFLOW GATE: gh pr create blocked — PR authorization HEAD mismatch.")
                [Console]::Error.WriteLine("Current HEAD:   $headSha")
                [Console]::Error.WriteLine("Auth line head: $authHead")
                [Console]::Error.WriteLine("Commits added since authorization; re-authorize at the new HEAD.")
                [Console]::Error.WriteLine("  - [x] PR creation authorized — ``<ts>`` — nonce=``<n>`` — head=``<sha>``")
                exit 2
            }

            # All checks passed; fall through to the existing checklist guard
        }
    }
}

# --- Active workflow: check always-required quality gates ---
# Extract checklist section (scoped to the Workflow block, so stray
# `### Checklist` headings in migrated State content can't poison this).
$inChecklist = $false
$unchecked = @()

foreach ($line in $workflowBlockLines) {
    if ($line -match '^### Checklist') { $inChecklist = $true; continue }
    # Stop at the next `### ` heading (not just `## `) — matches build-evidence
    # scoping so evidence lines under a DIFFERENT `### ` subsection of
    # `## Workflow` cannot satisfy the hook.
    if ($line -match '^### ' -and $inChecklist) { break }
    # Gate on the 4 canonical pre-ship markers:
    #   Code review loop | Simplified | Verified (tests | E2E verified
    # Exclude non-gate items that share words:
    #   "PR reviews addressed" (post-PR), "Plugins verified" (pre-flight),
    #   "Plan review loop" (design phase), "E2E use cases designed/graduated"
    #   (Phase 3.2b / 6.2b — conditional), "E2E regression passed" (Phase 5.4b).
    if ($inChecklist -and $line -match '- \[ \]' -and $line -match '(Code review loop|Simplified|Verified \(tests|E2E verified)') {
        $unchecked += $line
    }
}

if ($unchecked.Count -gt 0) {
    [Console]::Error.WriteLine("WORKFLOW GATE: $($unchecked.Count) required quality gate(s) incomplete.")
    [Console]::Error.WriteLine("Complete these before shipping:")
    foreach ($item in $unchecked) {
        [Console]::Error.WriteLine("  $($item.Trim() -replace '- \[ \] ', '- ')")
    }
    [Console]::Error.WriteLine("")
    [Console]::Error.WriteLine("How to clear each gate:")
    [Console]::Error.WriteLine("  - Code review loop:  run /codex review + /pr-review-toolkit:review-pr, fix findings")
    [Console]::Error.WriteLine("  - Simplified:        run /simplify")
    [Console]::Error.WriteLine("  - Verified (tests):  run the verify-app agent")
    [Console]::Error.WriteLine("  - E2E verified:      run the verify-e2e agent AND persist its report, OR mark N/A:")
    [Console]::Error.WriteLine('                         - [x] E2E verified — N/A: <specific reason>')
    [Console]::Error.WriteLine("  See .claude\rules\testing.md for the canonical gate vocabulary.")
    exit 2
}

# ---------------------------------------------------------------------------
# Evidence-based gate for E2E verified. Mirrors the .sh logic:
# a checked '[x] E2E verified' without 'N/A:' must have a fresh report file
# in tests/e2e/reports/ whose LastWriteTime is later than the branch-off
# commit. Skips gracefully if git state prevents determining branch-off.
# ---------------------------------------------------------------------------
$e2eCheckedLine = $null
foreach ($line in $workflowBlockLines) {
    if ($line -match '- \[x\]\s+E2E verified') {
        $e2eCheckedLine = $line
        break
    }
}

if ($e2eCheckedLine -and ($e2eCheckedLine -notmatch 'N/A:')) {
    # Find branch-off commit (try main, fall back to master, else skip)
    $branchOff = git merge-base HEAD main 2>$null
    if (-not $branchOff) { $branchOff = git merge-base HEAD master 2>$null }

    # If HEAD itself IS the branch-off point (user is on main/master, not a
    # feature branch), there's no meaningful "produced on this branch"
    # comparison. Skip the evidence check — matches the documented "on main
    # → skip" contract in rules/testing.md.
    $headSha = git rev-parse HEAD 2>$null
    if ($branchOff -and $headSha -and ($branchOff.Trim() -eq $headSha.Trim())) {
        $branchOff = $null  # Force the skip path below
    }

    if ($branchOff) {
        $branchOffTsStr = git log -1 --format=%ct $branchOff 2>$null
        $branchOffTs = 0
        if ($branchOffTsStr) { $branchOffTs = [long]$branchOffTsStr }

        $branchOffDate = [DateTimeOffset]::FromUnixTimeSeconds($branchOffTs).LocalDateTime

        $freshReportFound = $false
        if (Test-Path "tests/e2e/reports") {
            $reports = Get-ChildItem "tests/e2e/reports" -Filter "*.md" -File -ErrorAction SilentlyContinue
            foreach ($report in $reports) {
                if ($report.LastWriteTime -gt $branchOffDate) {
                    $freshReportFound = $true
                    break
                }
            }
        }

        if (-not $freshReportFound) {
            [Console]::Error.WriteLine("WORKFLOW GATE: E2E verified is checked, but no fresh report was found.")
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("The checklist says [x] E2E verified, but tests\e2e\reports\ has no")
            [Console]::Error.WriteLine("report file newer than this branch's commit off main. That usually means")
            [Console]::Error.WriteLine("the verify-e2e agent was never actually run on this branch.")
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("Either:")
            [Console]::Error.WriteLine("  (a) Run the verify-e2e agent and have the main agent persist its")
            [Console]::Error.WriteLine("      report to tests\e2e\reports\<YYYY-MM-DD-HH-MM>-<feature>.md,")
            [Console]::Error.WriteLine("  (b) Mark the gate N/A with justification:")
            [Console]::Error.WriteLine('        - [x] E2E verified — N/A: <specific reason>')
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("See .claude\rules\testing.md for the full policy.")
            exit 2
        }
    }
    # No branch-off (user on main / no main or master) → skip evidence check.
}

# ---------------------------------------------------------------------------
# Evidence-based gate for Plan review loop PASS
# Mirrors check-workflow-gates.sh Task 3 — see those comments for rationale.
# The .sh hook uses $CHECKLIST (a sed-extracted string); the .ps1 hook builds
# $checklistLines from $workflowBlockLines (different shape, same scope).
# ---------------------------------------------------------------------------

# Build $checklistLines from $workflowBlockLines (mirrors the .ps1 pattern at
# lines 165-177 of the existing quality-gate scan).
$checklistLines = @()
$inCl = $false
foreach ($l in $workflowBlockLines) {
    if ($l -match '^### Checklist') { $inCl = $true; continue }
    # Stop at the next `### ` heading (matches build-evidence scoping).
    if ($l -match '^### ' -and $inCl) { break }
    if ($inCl) { $checklistLines += $l }
}

# N/A escape: any `[x] Plan review loop ... N/A:` line skips the evidence check
# (mirrors the E2E verified — N/A: gate). Codex is mandatory; there is no
# "codex unavailable" escape.
$planNaLine = ($checklistLines `
    | Where-Object { $_ -match '^\s*-\s*\[x\]\s+Plan review loop' -and $_ -match 'N/A:' } `
    | Select-Object -First 1)

$planPassLine = ($checklistLines `
    | Where-Object { $_ -match '^\s*-\s*\[x\]\s+Plan review loop \(\d+ iterations\) — PASS' } `
    | Select-Object -Last 1)

if ($planNaLine) {
    # N/A justification present — skip plan-review evidence check
} elseif ($planPassLine) {
    if ($planPassLine -match 'Plan review loop \((\d+) iterations\)') {
        $planN = $matches[1]
    } else {
        $planN = $null
    }

    $planClean = ($checklistLines `
        | Where-Object { $_ -match "^\s*-\s*\[x\]\s+Plan review iteration $planN — " } `
        | Select-Object -Last 1)

    if (-not $planClean) {
        [Console]::Error.WriteLine("WORKFLOW GATE: [x] Plan review loop ($planN iterations) — PASS lacks per-iter clean evidence.")
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("Required: matching line in state.md (### Checklist):")
        [Console]::Error.WriteLine("  - [x] Plan review iteration $planN — codex clean — plan=``<plan-file>`` — plan_sha=``<sha256>`` — ts=``<ts>``")
        exit 2
    }

    # Codex is mandatory: only `codex clean` (plan_sha bound) is accepted.
    if ($planClean -match 'codex clean') {
        # Presence check BEFORE extraction (mirror .sh): a clean line missing
        # plan=/plan_sha= tokens must hit "malformed", not a garbled missing-file error.
        if ($planClean -notmatch 'plan=`[^`]+`.*plan_sha=`[^`]+`') {
            [Console]::Error.WriteLine("WORKFLOW GATE: Plan review iteration $planN clean line is malformed.")
            [Console]::Error.WriteLine("Expected format: codex clean — plan=``<path>`` — plan_sha=``<sha256>`` — ts=``<ts>``")
            [Console]::Error.WriteLine("Got: $planClean")
            exit 2
        }
        if ($planClean -match 'plan=`([^`]+)`') { $planPath = $matches[1] } else { $planPath = $null }
        if ($planClean -match 'plan_sha=`([^`]+)`') { $claimedSha = $matches[1].ToLower() } else { $claimedSha = $null }
        if (-not $planPath -or -not $claimedSha) {
            [Console]::Error.WriteLine("WORKFLOW GATE: Plan review iteration $planN clean line is malformed.")
            exit 2
        }
        if (-not (Test-Path $planPath)) {
            [Console]::Error.WriteLine("WORKFLOW GATE: Plan review evidence references missing file: $planPath")
            exit 2
        }
        # Lowercase BOTH sides of hash comparison (Get-FileHash returns uppercase).
        $actualSha = (Get-FileHash -Algorithm SHA256 -Path $planPath).Hash.ToLower()
        if ($actualSha -ne $claimedSha) {
            [Console]::Error.WriteLine("WORKFLOW GATE: Plan review iteration $planN plan_sha mismatch.")
            [Console]::Error.WriteLine("  Claimed (state.md): $claimedSha")
            [Console]::Error.WriteLine("  Actual ($planPath): $actualSha")
            exit 2
        }
    } else {
        [Console]::Error.WriteLine("WORKFLOW GATE: Plan review iteration $planN clean line variant not recognized.")
        [Console]::Error.WriteLine("Got: $planClean")
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("Codex is mandatory in this repo. Accepted forms (see rules/workflow.md):")
        [Console]::Error.WriteLine("  - codex clean — plan=``<path>`` — plan_sha=``<sha>`` — ts=``<ts>``")
        [Console]::Error.WriteLine("  - mark the loop N/A:  - [x] Plan review loop — N/A: <reason>")
        exit 2
    }
}

# ---------------------------------------------------------------------------
# Evidence-based gate for Code review loop PASS
# Mirrors check-workflow-gates.sh Task 5 — binds to git HEAD. Codex + pr-toolkit
# both required for the same iteration at the current HEAD.
# Canonical clean-line stem (test-contracts.sh parity check):
#   Code review iteration N — codex clean — head=`<sha>`
# ---------------------------------------------------------------------------
# N/A escape: any `[x] Code review loop ... N/A:` line skips the evidence check.
# Codex is mandatory; there is no "tool unavailable" escape.
$codeNaLine = ($checklistLines `
    | Where-Object { $_ -match '^\s*-\s*\[x\]\s+Code review loop' -and $_ -match 'N/A:' } `
    | Select-Object -First 1)

$codePassLine = ($checklistLines `
    | Where-Object { $_ -match '^\s*-\s*\[x\]\s+Code review loop \(\d+ iterations\) — PASS' } `
    | Select-Object -Last 1)

$headShaCode = (git rev-parse HEAD 2>$null)
if ($headShaCode) { $headShaCode = ([string]$headShaCode).Trim() } else { $headShaCode = "" }

# Degraded env (no git repo) → skip code-review evidence check entirely.
if ($codeNaLine) {
    # N/A justification present — skip code-review evidence check
} elseif ($codePassLine -and $headShaCode) {
    if ($codePassLine -match 'Code review loop \((\d+) iterations\)') {
        $codeN = $matches[1]
    } else {
        $codeN = $null
    }

    $codexLine = ($checklistLines `
        | Where-Object { $_ -match "^\s*-\s*\[x\]\s+Code review iteration $codeN — codex " } `
        | Select-Object -Last 1)
    $toolkitLine = ($checklistLines `
        | Where-Object { $_ -match "^\s*-\s*\[x\]\s+Code review iteration $codeN — pr-toolkit " } `
        | Select-Object -Last 1)

    if (-not $codexLine -or -not $toolkitLine) {
        [Console]::Error.WriteLine("WORKFLOW GATE: [x] Code review loop ($codeN iterations) — PASS lacks per-iter clean evidence.")
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("Required: matching lines in state.md (### Checklist):")
        [Console]::Error.WriteLine("  - [x] Code review iteration $codeN — codex clean — head=``$headShaCode``")
        [Console]::Error.WriteLine("  - [x] Code review iteration $codeN — pr-toolkit clean — head=``$headShaCode``")
        exit 2
    }

    foreach ($pair in @(@{ tool = 'codex'; line = $codexLine }, @{ tool = 'pr-toolkit'; line = $toolkitLine })) {
        $tool = $pair.tool
        $line = $pair.line

        # Every variant must carry head=`<sha>` matching current HEAD.
        if ($line -match 'head=`([0-9a-f]+)`') {
            $lineHead = $matches[1]
        } else {
            [Console]::Error.WriteLine("WORKFLOW GATE: Code review iteration $codeN $tool line missing head=``<sha>``.")
            [Console]::Error.WriteLine("Got: $line")
            exit 2
        }
        if ($lineHead -ne $headShaCode) {
            [Console]::Error.WriteLine("WORKFLOW GATE: Code review iteration $codeN $tool line is at a stale HEAD (head mismatch).")
            [Console]::Error.WriteLine("  Line head:    $lineHead")
            [Console]::Error.WriteLine("  Current head: $headShaCode")
            [Console]::Error.WriteLine("New commits landed since iter-$codeN. Re-run $tool at current head.")
            exit 2
        }

        if ($line -match "$tool clean") {
            # clean variant — head already verified above
        } else {
            [Console]::Error.WriteLine("WORKFLOW GATE: Code review iteration $codeN $tool line variant not recognized.")
            [Console]::Error.WriteLine("Got: $line")
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("Codex is mandatory in this repo. Required: $tool clean — head=``<sha>``,")
            [Console]::Error.WriteLine("or mark the loop N/A:  - [x] Code review loop — N/A: <reason>")
            exit 2
        }
    }
}

exit 0
