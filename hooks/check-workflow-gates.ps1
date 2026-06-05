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
# No-code carve-out: a `git commit` staging ONLY documentation skips the
# code-quality gates for that commit WITHOUT mutating state.md (gates stay
# `- [ ]` for the real-code ship). Scope = commit only; push/PR always enforce.
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
# Ship-verb detection tolerant of two common, fully-legitimate invocation forms
# that a plain `^git commit` anchor misses:
#   - env-assignment prefix:  GIT_AUTHOR_NAME=x git commit ...   /  FOO=bar git push
#   - git global options:     git -C <dir> commit ...           /  git -c k=v push
# matched at BOTH the command start AND after a separator (&&, ||, ;, |).
#
# KNOWN RESIDUAL (accepted, fail-safe — conscious scope decision 2026-05-26):
# exotic wrappers — subshell `(git push)`, control-flow `if true; then git push; fi`,
# and command-substitution `$(git push)` — are NOT matched here. They are rare,
# non-idiomatic ways to ship; missing them yields a non-block (exit 0), never a
# crash. Robust shell-command parsing is out of scope for this gate. Pushes/PRs
# also re-enter this hook at push/PR time against the stable HEAD.
# env-assignment prefix: NAME=VALUE followed by whitespace, zero or more times.
# VALUE may be bare, 'single-quoted', "double-quoted" (may contain spaces), or
# empty — covering `GIT_AUTHOR_NAME='Pablo Marin' git commit` and `FOO= git push`.
# Single-quoted PS string: literal single quotes are doubled ('').
$envp = '([A-Za-z_][A-Za-z0-9_]*=(''[^'']*''|"[^"]*"|\S*)\s+)*'
$gitopt = '(\s+-[cC]\s+\S+)*'
$shipVerb = "$envp(git$gitopt\s+(commit|push)\b|gh\s+pr\s+create\b)"

# Normalize command separators ONCE, BEFORE ship detection (mirrors .sh): real
# newlines, CRs, AND literal \n / \r escapes become `;`. PowerShell's `-match`
# `^` is NOT multiline, so a multi-line tool input whose FIRST line is non-ship
# (`echo ok<newline>git push`) would otherwise slip the non-ship fast path and
# never reach the compound guard (Codex P1). Normalizing first surfaces later
# ship verbs to both checks.
$commandNorm = ($command -replace '\\[nr]', ';') -replace "[`r`n]", ';'

$isShip = $false
if ($commandNorm -match "^\s*$shipVerb") { $isShip = $true }
if ($commandNorm -match "[&|;]+\s*$shipVerb") { $isShip = $true }

if (-not $isShip) { exit 0 }

# --- Block compound ship commands ---
# A compound like `git commit -m x && git push` validates evidence against the
# pre-commit HEAD, passes, then the chained push ships the new (unreviewed)
# HEAD with no second gate check. Detect a ship verb AFTER a separator
# (&&, ||, ;, |) and block — force the user to run each ship action
# individually so every one gets its own gate evaluation.
# Operates on $commandNorm (built above) so newline-separated and escaped-newline
# ship chains are treated as compound too (Codex P1).
$compoundTail = $commandNorm -replace '^[^&|;]*[&|;]+', ''
if ($compoundTail -ne $commandNorm) {
    if ($compoundTail -match $shipVerb) {
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

# --- Resolve repo context (bug d, mirrors check-workflow-gates.sh) ---
# cd to the harness-provided stdin `cwd` (the dir the command actually runs in —
# trustworthy, NOT parsed from the command text), then normalize to the git
# worktree ROOT so state.md, git, and all repo-relative reads resolve in the
# right repo. We deliberately do NOT parse `-C <dir>` from the command for repo
# context: a `-C` can hide in a quoted -m message / `-c key='… -C …'` value / gh
# --title, so regex parsing opened fail-open paths. A `git -C <other> commit` is
# evaluated against the session cwd (the agent's repo), which never bypasses that
# repo's gates. (`git -C` is still recognized as a ship verb above.) Fail-safe:
# cwd absent / not a dir / not in a repo → stay in CWD. Existing tests pass no
# `cwd`, so the process CWD governs as before.
if ($data.cwd) {
    $hookCwd = [string]$data.cwd
    if ($hookCwd -and (Test-Path -LiteralPath $hookCwd -PathType Container)) {
        try { Set-Location -LiteralPath $hookCwd -ErrorAction Stop } catch {}
    }
}
# --show-toplevel is a no-op at the root and fails silently outside a repo.
$topLevel = (git rev-parse --show-toplevel 2>$null)
if ($topLevel) {
    $topLevel = ([string]$topLevel).Trim()
    if ($topLevel -and (Test-Path -LiteralPath $topLevel -PathType Container)) {
        try { Set-Location -LiteralPath $topLevel -ErrorAction Stop } catch {}
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
# Env-prefix-aware (matches `FOO=bar gh pr create`) so the broadened ship
# detection above can't route an env-prefixed PR-create past this auth guard.
# $envp ends in `*` so this also matches the bare `gh pr create` form.
$prCreatePattern = "^\s*${envp}gh\s+pr\s+create\b"
if ($command -match $prCreatePattern) {
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

# --- Convergence breaker (hook-enforced backstop; ADR 0009) ---
# Placement: BEFORE the docs-only commit carve-out and OUTSIDE the PASS-evidence
# branch — neither a docs-only staged diff, a `Code review loop — N/A:` escape,
# nor an unchecked loop line may bypass it. Runs on every gated ship action.
# ADJUDICATED is the helper's own head-bound detection of the human adjudication
# line (single-sourced parser). For non-workflow repos / uncertified branches the
# helper emits BREAKER:ok, so this block is inert.
#
# Helper invocation (PS 5.1 contract — mirrors review-scope.ps1's dual-mode note):
# DOT-SOURCE the helper and CALL the function — `. $ReviewScopePs1` then
# `Invoke-ReviewScope $StateFile $beforeN`. Do NOT call-operator the script (its
# standalone entrypoint could `exit` the hook mid-validation) and do NOT spawn a
# separate pwsh interpreter (the repo ships against powershell.exe 5.1). The
# function RETURNS the sentinel lines (string array) and never calls `exit` when
# dot-sourced.
$ReviewScopePs1 = Join-Path $topLevel ".claude\hooks\lib\review-scope.ps1"
if (-not (Test-Path -LiteralPath $ReviewScopePs1)) {
    $ReviewScopePs1 = Join-Path $topLevel "hooks\lib\review-scope.ps1"
}
$brkHead = ""
try { $brkHead = ((git rev-parse HEAD 2>$null) -join "").Trim() } catch {}
if ($brkHead -and (Test-Path -LiteralPath $ReviewScopePs1) -and (Test-Path $stateFile)) {
    . $ReviewScopePs1
    $rsOut2 = Invoke-ReviewScope $stateFile 999999
    $brkTripped = ($rsOut2 | Where-Object { $_ -eq 'BREAKER:tripped' } | Select-Object -First 1)
    $adjNo = ($rsOut2 | Where-Object { $_ -eq 'ADJUDICATED:no' } | Select-Object -First 1)
    if ($brkTripped -and $adjNo) {
        [Console]::Error.WriteLine("WORKFLOW GATE: convergence breaker — POST_CERT_REVIEW_ROUND_LIMIT exceeded.")
        foreach ($l in ($rsOut2 | Where-Object { $_ -match '^(POST_CERT_ROUNDS|LAST_CLEAN_HEAD)' })) {
            [Console]::Error.WriteLine($l)
        }
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("The review loop is not converging. STOP and surface the open tail")
        [Console]::Error.WriteLine("(severities + in-delta vs certified-unchanged) to the human. Ship is")
        [Console]::Error.WriteLine("blocked until the human records:")
        [Console]::Error.WriteLine("  - [x] Post-certification tail adjudicated by human — <decision> — head=``$brkHead`` — ts=``<ISO8601>``")
        exit 2
    }
}

# ---------------------------------------------------------------------------
# No-code carve-out (git commit only) — closes the integrity hole (mirrors .sh)
# See check-workflow-gates.sh for the full rationale + scope decision. When a
# `git commit` stages ONLY documentation, skip the code-quality gates for THIS
# commit WITHOUT touching state.md (boxes stay [ ] for the real-code ship). Scope
# = commit only; push/PR always enforce. Because state is never mutated, any
# under-gating at commit is still caught at push/PR (boxes remain unchecked).
# docs predicate (path ∩ extension, fail-safe): curated doc basenames anywhere,
# OR a prose extension under a docs/ dir. Everything else is code.
# ---------------------------------------------------------------------------
function Test-IsDocPath {
    param([string]$p)
    $base = Split-Path -Leaf $p
    # Curated doc files: extensionless, or curated prefix + prose/.txt extension.
    # A curated prefix with a code extension (README.py) is NOT docs (Codex P2).
    if ($base -match '^(README|CHANGELOG|LICENSE|NOTICE|AUTHORS|CONTRIBUTORS|CONTRIBUTING|CODE_OF_CONDUCT)$') {
        return $true
    }
    if ($base -match '^(README|CHANGELOG|LICENSE|CONTRIBUTORS|CONTRIBUTING|CODE_OF_CONDUCT)' -and
        $base -match '\.(md|mdx|markdown|rst|txt)$') {
        return $true
    }
    # Under a docs/ dir AND a prose extension (.txt excluded here, mirrors .sh).
    if ($p -match '(^|/)docs/' -and $base -match '\.(md|mdx|markdown|rst)$') {
        return $true
    }
    return $false
}

# Plain `git commit` only. Decline (→ enforce) on -a/--all/--include/--only/
# --amend/-p/--patch/-i/--interactive: those commit content NOT visible in
# `git diff --cached` at PreToolUse time. (Bare-pathspec residual is neutralized
# by the push/PR backstop — see the .sh comment.)
if ($command -match "^\s*${envp}git${gitopt}\s+commit\b" -and
    $command -notmatch '(^|\s)(-[a-zA-Z]*[apio][a-zA-Z]*|--all|--include|--only|--amend|--patch|--interactive)(\s|=|$)') {
    # --no-renames so a code→docs rename surfaces the old (code) path too.
    $stagedRaw = (git diff --cached --name-status --no-renames 2>$null)
    $stagedPaths = @()
    foreach ($l in @($stagedRaw)) {
        if (-not $l) { continue }
        $parts = $l -split "`t"
        if ($parts.Count -ge 2) { $stagedPaths += $parts[1] }
    }
    if ($stagedPaths.Count -gt 0) {
        $allDocs = $true
        foreach ($f in $stagedPaths) {
            if (-not (Test-IsDocPath $f)) { $allDocs = $false; break }
        }
        if ($allDocs) { exit 0 }  # docs-only commit — skip gates, NO state mutation
    }
    # Empty staged diff → can't prove docs-only → fall through and enforce (fail-safe).
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
    # ANCHORED (mirrors check-workflow-gates.sh): the unchecked marker must be
    # at line start AND immediately followed by a gate stem. A loose `- [ ]`
    # match false-positives on a literal `- [ ]` inside an already-[x] line's
    # prose (e.g. an N/A justification) and on unrelated unchecked items whose
    # prose merely mentions a gate name. Keep this single anchored regex.
    if ($inChecklist -and $line -match '^\s*- \[ \]\s+(Code review loop|Simplified|Verified \(tests|E2E verified)') {
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
# Build $checklistLines (scoped to the ### Checklist subsection) ONCE here and
# reuse for the E2E, plan-review, and code-review evidence gates below. The E2E
# scan previously used $workflowBlockLines (the whole Workflow block) with an
# unanchored match — fixed to scoped + anchored for parity with the .sh (bug c).
$checklistLines = @()
$inCl = $false
foreach ($l in $workflowBlockLines) {
    if ($l -match '^### Checklist') { $inCl = $true; continue }
    if ($l -match '^### ' -and $inCl) { break }
    if ($inCl) { $checklistLines += $l }
}

$e2eCheckedLine = $null
foreach ($line in $checklistLines) {
    if ($line -match '^\s*- \[x\]\s+E2E verified') {
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

# ($checklistLines was built once above the E2E gate and is reused here.)

# N/A escape: any `[x] Plan review loop ... N/A:` line skips the evidence check
# (mirrors the E2E verified — N/A: gate). Codex is mandatory; there is no
# "codex unavailable" escape.
$planNaLine = ($checklistLines `
    | Where-Object { $_ -match '^\s*-\s*\[x\]\s+Plan review loop' -and $_ -match 'N/A:' } `
    | Select-Object -First 1)

$planPassLine = ($checklistLines `
    | Where-Object { $_ -match '^\s*-\s*\[x\]\s+Plan review loop \(\d+ iterations\) — PASS' } `
    | Select-Object -Last 1)

# Any checked `Plan review loop` line — for malformed detection (bug b).
$planCheckedAny = ($checklistLines `
    | Where-Object { $_ -match '^\s*-\s*\[x\]\s+Plan review loop' } `
    | Select-Object -Last 1)

# PASS-before-N/A (bug a) + malformed (bug b), mirrors .sh: a well-formed PASS
# line always requires its evidence (stale N/A can't mask it); N/A applies only
# when there is no PASS line; a checked line that is neither → block as malformed.
if ($planPassLine) {
    # enforce evidence below (PASS wins over any N/A line)
} elseif ($planNaLine) {
    # N/A and no PASS line — skip plan-review evidence check
} elseif ($planCheckedAny) {
    [Console]::Error.WriteLine("WORKFLOW GATE: malformed '[x] Plan review loop' line.")
    [Console]::Error.WriteLine("A checked Plan review loop line must be either:")
    [Console]::Error.WriteLine("  - [x] Plan review loop (N iterations) — PASS   (with per-iter evidence), OR")
    [Console]::Error.WriteLine("  - [x] Plan review loop — N/A: <reason>")
    [Console]::Error.WriteLine("Got: $planCheckedAny")
    exit 2
}

if ($planPassLine) {
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
    if ($planClean -match '— codex clean —') {
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

# Any checked `Code review loop` line — for malformed detection (bug b).
$codeCheckedAny = ($checklistLines `
    | Where-Object { $_ -match '^\s*-\s*\[x\]\s+Code review loop' } `
    | Select-Object -Last 1)

$headShaCode = (git rev-parse HEAD 2>$null)
if ($headShaCode) { $headShaCode = ([string]$headShaCode).Trim() } else { $headShaCode = "" }

# Degraded env (no git repo) → skip code-review evidence check entirely.
# PASS-before-N/A (bug a) + malformed (bug b), mirrors .sh.
if ($codePassLine) {
    # enforce below when git is available; PASS wins over any N/A
} elseif ($codeNaLine) {
    $codePassLine = ""  # no PASS line — N/A escape applies; skip evidence
} elseif ($codeCheckedAny) {
    [Console]::Error.WriteLine("WORKFLOW GATE: malformed '[x] Code review loop' line.")
    [Console]::Error.WriteLine("A checked Code review loop line must be either:")
    [Console]::Error.WriteLine("  - [x] Code review loop (N iterations) — PASS   (with per-iter evidence), OR")
    [Console]::Error.WriteLine("  - [x] Code review loop — N/A: <reason>")
    [Console]::Error.WriteLine("Got: $codeCheckedAny")
    exit 2
}

if ($codePassLine -and $headShaCode) {
    if ($codePassLine -match 'Code review loop \((\d+) iterations\)') {
        $codeN = $matches[1]
    } else {
        $codeN = $null
    }

    # --- v5.54 scoped-review-certification (ADR 0009) ---------------------------
    # $ReviewScopePs1 was resolved by the convergence-breaker block above (installed
    # path, then forge-internal source path), and the helper dot-sourced there so
    # Invoke-ReviewScope is in scope. A mechanical re-stamp row CAN satisfy iteration
    # N WITHOUT an engine pair — it is the evidence by design — so compute $mechLine
    # FIRST and gate the legacy pair checks on its absence.
    $mechLine = ($checklistLines `
        | Where-Object { $_ -cmatch "^\s*-\s*\[x\]\s+Code review iteration $codeN — mechanical re-stamp — scope=mechanical — " } `
        | Select-Object -Last 1)

    # Prior-chain context: helper computed EXCLUDING the current iteration's rows,
    # so LAST_CLEAN_HEAD/CERTIFIED describe the state this iteration must chain from.
    # (Helper already dot-sourced in the breaker block; call the function directly.)
    $rsPrior = @()
    if (Test-Path -LiteralPath $ReviewScopePs1) {
        $rsPrior = Invoke-ReviewScope $stateFile ([int]$codeN)
    }
    $priorCertified = ($rsPrior | Where-Object { $_ -eq 'CERTIFIED:yes' } | Measure-Object).Count
    $priorCleanHead = ""
    foreach ($l in $rsPrior) {
        if ($l -match '^LAST_CLEAN_HEAD:(.*)$') { $priorCleanHead = $matches[1] }
    }

    # Validate codex side (last-line semantics — defensive against stale duplicates).
    # Exclude the deliberate deep-pass row (`— codex deep-pass clean —`): it is a
    # SEPARATE tool recorded at the same iteration and must not be tailed into the
    # `— codex clean —` variant check (false-block on the certified happy path).
    $codexLine = ($checklistLines `
        | Where-Object { $_ -match "^\s*-\s*\[x\]\s+Code review iteration $codeN — codex " -and $_ -notmatch '— codex deep-pass' } `
        | Select-Object -Last 1)
    $toolkitLine = ($checklistLines `
        | Where-Object { $_ -match "^\s*-\s*\[x\]\s+Code review iteration $codeN — pr-toolkit " } `
        | Select-Object -Last 1)

    # The engine pair is required ONLY when there is no mechanical re-stamp for this
    # iteration. When $mechLine exists, the mechanical line IS the evidence
    # (validated in the scoped branch below) and the pair is absent by design.
    if (-not $mechLine) {
        if (-not $codexLine -or -not $toolkitLine) {
            [Console]::Error.WriteLine("WORKFLOW GATE: [x] Code review loop ($codeN iterations) — PASS lacks per-iter clean evidence.")
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("Required: matching lines in state.md (### Checklist):")
            [Console]::Error.WriteLine("  - [x] Code review iteration $codeN — codex clean — scope=full — base=``<merge-base>`` — head=``$headShaCode``")
            [Console]::Error.WriteLine("  - [x] Code review iteration $codeN — pr-toolkit clean — scope=full — base=``<merge-base>`` — head=``$headShaCode``")
            [Console]::Error.WriteLine("  (legacy form codex clean — head=``<sha>`` is back-compat — certification only)")
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("Run iter-$codeN reviewers + append both clean lines, OR uncheck the loop.")
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

            if ($line -match "— $tool clean —") {
                # clean variant — head already verified above
            } else {
                [Console]::Error.WriteLine("WORKFLOW GATE: Code review iteration $codeN $tool line variant not recognized.")
                [Console]::Error.WriteLine("Got: $line")
                [Console]::Error.WriteLine("")
                [Console]::Error.WriteLine("Codex is mandatory in this repo. Required: $tool clean — scope=full — base=``<merge-base>`` — head=``<sha>``,")
                [Console]::Error.WriteLine("or the legacy form $tool clean — head=``<sha>`` (legacy back-compat — certification only),")
                [Console]::Error.WriteLine("or mark the loop N/A:  - [x] Code review loop — N/A: <reason>")
                exit 2
            }
        }
    }

    if ($mechLine) {
        # A mechanical re-stamp claims no review was needed. NEVER trust it —
        # it requires an existing certification, a correct chain base, AND the
        # helper's own recomputation agreeing for the current head.
        $mHead = ""
        if ($mechLine -match 'head=`([0-9a-f]+)`') { $mHead = $matches[1] }
        $mBase = ""
        if ($mechLine -match 'base=`([0-9a-f]+)`') { $mBase = $matches[1] }
        if ((-not (Test-Path -LiteralPath $ReviewScopePs1)) -or ($mHead -ne $headShaCode) -or ($priorCertified -eq 0) `
            -or (-not $mBase) -or ($mBase -ne $priorCleanHead)) {
            $pchDisp = if ($priorCleanHead) { $priorCleanHead } else { "<none>" }
            [Console]::Error.WriteLine("WORKFLOW GATE: mechanical re-stamp invalid (requires certification, base=prior clean head ``$pchDisp``, head=current HEAD).")
            [Console]::Error.WriteLine("Got: $mechLine")
            exit 2
        }
        # Recompute with the CURRENT iteration's rows EXCLUDED (--before $codeN,
        # i.e. $rsPrior) — a full-state run would let the mechanical row advance
        # LAST_CLEAN_HEAD to its own head and validate itself (Codex iter-2 P1).
        $priorMechanical = ($rsPrior | Where-Object { $_ -eq 'SCOPE_REQUIRED:mechanical' } | Select-Object -First 1)
        if (-not $priorMechanical) {
            [Console]::Error.WriteLine("WORKFLOW GATE: mechanical claim rejected — recomputation says a review is required:")
            foreach ($l in ($rsPrior | Where-Object { $_ -match '^(PR_OWNED_DELTA|UPSTREAM_FILES|SCOPE_REQUIRED|ANCESTOR_OK)' })) {
                [Console]::Error.WriteLine($l)
            }
            [Console]::Error.WriteLine("Run the required review scope and record real evidence.")
            exit 2
        }
    } else {
        # Engine-pair path (existing loop already validated head + clean variant).
        # Collect per-line scope/base, then validate the PAIR — both engines must
        # have reviewed the SAME thing (iter-3 P1: a mixed full/delta pair, or two
        # delta lines with different bases, is not a coherent review round).
        $cScope = ""; $cBase = ""; $tScope = ""; $tBase = ""
        foreach ($pair in @(@{ tool = 'codex'; line = $codexLine }, @{ tool = 'pr-toolkit'; line = $toolkitLine })) {
            $tool = $pair.tool
            $line = $pair.line
            if ($line -cmatch 'scope=') {
                # Any scoped line must carry a well-formed base (full grammar).
                # Delimiter-bound value: scope=fullish must NOT pass as full.
                if ($line -cnotmatch 'scope=(full|delta)(\s|$)') {
                    [Console]::Error.WriteLine("WORKFLOW GATE: unknown scope value on iteration $codeN line.")
                    [Console]::Error.WriteLine("Got: $line")
                    exit 2
                }
                if ($line -notmatch 'base=`[0-9a-f]+`') {
                    [Console]::Error.WriteLine("WORKFLOW GATE: scoped iteration $codeN line missing base=``<sha>``.")
                    [Console]::Error.WriteLine("Got: $line")
                    exit 2
                }
                $lScope = ([regex]::Match($line, 'scope=(full|delta)(\s|$)')).Groups[1].Value
                $lBase = ([regex]::Match($line, 'base=`([0-9a-f]+)`')).Groups[1].Value
            } else {
                # Scope-less LEGACY pair: valid ONLY as certification evidence —
                # i.e., when no certification existed before this iteration. After
                # certification, every re-review must be scoped (spec: legacy lines
                # "never satisfy a rebind").
                if ($priorCertified -gt 0) {
                    [Console]::Error.WriteLine("WORKFLOW GATE: post-certification evidence must be scoped (scope=full|delta or a mechanical re-stamp).")
                    [Console]::Error.WriteLine("Got legacy scope-less line: $line")
                    exit 2
                }
                $lScope = "legacy"; $lBase = ""
            }
            if ($tool -eq 'codex') { $cScope = $lScope; $cBase = $lBase }
            else { $tScope = $lScope; $tBase = $lBase }
        }
        if (($cScope -ne $tScope) -or ($cBase -ne $tBase)) {
            $cbDisp = if ($cBase) { $cBase } else { "<none>" }
            $tbDisp = if ($tBase) { $tBase } else { "<none>" }
            [Console]::Error.WriteLine("WORKFLOW GATE: incoherent reviewer pair on iteration $codeN — both engines must review the same scope from the same base.")
            [Console]::Error.WriteLine("  codex:      scope=$cScope base=$cbDisp")
            [Console]::Error.WriteLine("  pr-toolkit: scope=$tScope base=$tbDisp")
            exit 2
        }
        if ($cScope -eq 'delta') {
            if (($priorCertified -eq 0) -or (-not $priorCleanHead) -or ($cBase -ne $priorCleanHead)) {
                $pchDisp = if ($priorCleanHead) { $priorCleanHead } else { "<none>" }
                [Console]::Error.WriteLine("WORKFLOW GATE: scope=delta base chain broken on iteration $codeN.")
                [Console]::Error.WriteLine("  Claimed base: $cBase   Prior clean head: $pchDisp")
                [Console]::Error.WriteLine("A delta review must chain from the previous clean evidence head.")
                exit 2
            }
            # A delta claim is only as good as the identity computation behind it:
            # after a rebase/amend the helper says ANCESTOR_OK:no + SCOPE_REQUIRED:full —
            # a forged delta from the old clean head must not pass (iter-4 P1).
            $priorAncestorOk = ($rsPrior | Where-Object { $_ -eq 'ANCESTOR_OK:yes' } | Select-Object -First 1)
            $priorScopeFull = ($rsPrior | Where-Object { $_ -eq 'SCOPE_REQUIRED:full' } | Select-Object -First 1)
            if ((-not $priorAncestorOk) -or $priorScopeFull) {
                [Console]::Error.WriteLine("WORKFLOW GATE: scope=delta rejected — recomputation requires a FULL review here:")
                foreach ($l in ($rsPrior | Where-Object { $_ -match '^(ANCESTOR_OK|SCOPE_REQUIRED|LAST_CLEAN_HEAD)' })) {
                    [Console]::Error.WriteLine($l)
                }
                [Console]::Error.WriteLine("(history was rewritten or identity is unestablishable — fail-closed to full)")
                exit 2
            }
        } elseif ($cScope -eq 'full') {
            # A scope=full base must be the TRUE merge-base for the current head
            # (same DEFAULT_REF resolution as review-scope.ps1 — fabrication guard).
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
            $gateMb = (& git merge-base $gateRef $headShaCode 2>$null | Select-Object -First 1)
            if (-not $gateMb -or ($cBase -ne $gateMb)) {
                $mbDisp = if ($gateMb) { $gateMb } else { "<unresolvable>" }
                [Console]::Error.WriteLine("WORKFLOW GATE: scope=full base on iteration $codeN is not the merge-base for this head.")
                [Console]::Error.WriteLine("  Claimed base: $cBase   Merge-base($gateRef, HEAD): $mbDisp")
                exit 2
            }
        }
    }
}

exit 0
