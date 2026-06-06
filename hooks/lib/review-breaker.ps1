# hooks/lib/review-breaker.ps1 — PowerShell mirror of hooks/lib/review-breaker.sh:
# convergence-breaker for the code-review loop (v5.54, ADR 0009). READ-ONLY: emits
# 4 sentinel lines, never writes. Small state.md reader — NO git diff machinery.
#
# Usage (standalone): review-breaker.ps1 <state_md_path>
#   (run from a checkout of the branch)
#
# Sentinels (emitted in this exact order):
#   CERTIFIED:<yes|no>  POST_CERT_ROUNDS:<n>  BREAKER:<ok|tripped>  ADJUDICATED:<yes|no>
#
# Dual-mode (CRITICAL for cross-launcher safety — mirrors default-branch.ps1):
#   On Windows, the shipped Claude Code launcher is `powershell.exe` (5.1).
#   Consumer hooks (check-workflow-gates.ps1 / build-evidence.ps1) MUST dot-source
#   this file and CALL the function, never subprocess it:
#       . "$libPath\review-breaker.ps1"
#       $sentinels = Invoke-ReviewBreaker $StateFile
#   A script-style helper with `exit` statements would terminate the CALLING hook
#   mid-validation. Therefore: the function RETURNS the sentinel lines (string
#   array) and NEVER calls `exit`; early fail-safe paths `return` the block.
#   Only the standalone entrypoint at the bottom may `exit`.
#
# PowerShell 5.1-compatible (no 7-only syntax): no `&&`/`||` pipeline chains, no
# ternary, no null-coalescing. Git via `& git ... 2>$null` + $LASTEXITCODE checks.
# Case-SENSITIVE matching for the clean stems (-cmatch) mirrors bash grep.

$POST_CERT_REVIEW_ROUND_LIMIT = 3   # canonical home mirrored from review-breaker.sh

function Invoke-ReviewBreaker {
    param(
        [string]$StateFile
    )

    $ErrorActionPreference = 'SilentlyContinue'

    # Fail-safe (inert) block: missing state / no git -> breaker inert.
    function _emit_inert {
        return @(
            "CERTIFIED:no",
            "POST_CERT_ROUNDS:0",
            "BREAKER:ok",
            "ADJUDICATED:no"
        )
    }

    # --- guards ---
    if (-not $StateFile -or -not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
        return (_emit_inert)
    }
    & git rev-parse HEAD 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return (_emit_inert)
    }
    $HEAD_SHA = (& git rev-parse HEAD 2>$null | Select-Object -First 1)

    # --- read state.md, CRLF-safe; isolate the ### Checklist of ## Workflow ---
    $raw = Get-Content -LiteralPath $StateFile -Raw
    $raw = $raw -replace "`r", ""
    $lines = $raw -split "`n"
    # EXACT heading anchor (^## Workflow$) — a stale "## Workflow Archive" section
    # from a migration must not feed the count.
    $inWorkflow = $false
    $workflowLines = @()
    foreach ($ln in $lines) {
        if ($ln -eq '## Workflow') { $inWorkflow = $true; continue }
        if ($inWorkflow -and $ln -match '^## ') { $inWorkflow = $false }
        if ($inWorkflow) { $workflowLines += $ln }
    }
    $inChecklist = $false
    $checklist = @()
    foreach ($ln in $workflowLines) {
        if ($ln -match '^### Checklist') { $inChecklist = $true; continue }
        if ($inChecklist -and $ln -match '^### ') { $inChecklist = $false }
        if ($inChecklist) { $checklist += $ln }
    }

    # --- parse evidence rows: object list with N|Tool|Head ---
    # Match the exact legacy clean stems and ignore unknown/non-clean rows
    # (mechanical, codex deep-pass); extra fields such as `scope=full — base=...`
    # from this branch's dogfooding are safe — treated as inert suffixes, not scoped
    # semantics. Note `— codex deep-pass clean` does NOT contain the substring
    # `— codex clean`, so it is naturally ignored. head=`<hex>` required.
    # Case-sensitive (-cmatch) on the stems, mirroring the bash grep.
    $rows = @()
    foreach ($ln in $checklist) {
        $m = [regex]::Match($ln, '^- \[x\] Code review iteration ([0-9]+) — ')
        if (-not $m.Success) { continue }
        $n = [int]$m.Groups[1].Value
        $tool = ''
        if ($ln -cmatch '— codex clean') { $tool = 'codex' }
        elseif ($ln -cmatch '— pr-toolkit clean') { $tool = 'pr-toolkit' }
        if ($tool -eq '') { continue }
        $head = ''
        $hm = [regex]::Match($ln, 'head=`([0-9a-f]+)`')
        if ($hm.Success) { $head = $hm.Groups[1].Value }
        if ($head -eq '') { continue }
        $rows += [pscustomobject]@{ N = $n; Tool = $tool; Head = $head }
    }

    # Loop-counter line: authoritative round count (finding-rounds write no rows).
    $LOOP_N = 0
    foreach ($ln in $checklist) {
        $lm = [regex]::Match($ln, 'Code review loop \(([0-9]+) iterations\)')
        if ($lm.Success) { $LOOP_N = [int]$lm.Groups[1].Value }  # last match wins
    }
    # Count-less N/A detection: a `Code review loop — N/A:` line WITHOUT an
    # `(N iterations)` count, post-certification, reads as breaker-counter erasure.
    $NA_COUNTLESS = $false
    foreach ($ln in $checklist) {
        if (($ln -match 'Code review loop') -and ($ln -match 'N/A:') -and ($ln -notmatch '\([0-9]+ iterations\)')) {
            $NA_COUNTLESS = $true
        }
    }

    # Human adjudication line bound to the CURRENT head (unblocks a tripped breaker).
    $ADJ = 'no'
    foreach ($ln in $checklist) {
        if (($ln -match '^- \[x\] Post-certification tail adjudicated by human — ') -and ($ln -match [regex]::Escape('head=`' + $HEAD_SHA + '`'))) {
            $ADJ = 'yes'
        }
    }

    # --- certification: lowest N with BOTH engines clean at the SAME head ---
    $sortedNs = $rows | ForEach-Object { $_.N } | Sort-Object -Unique
    $CERT_N = $null
    $CERT_HEAD = ''
    foreach ($n in $sortedNs) {
        $cl = $rows | Where-Object { $_.N -eq $n -and $_.Tool -eq 'codex' } | Select-Object -Last 1
        $tl = $rows | Where-Object { $_.N -eq $n -and $_.Tool -eq 'pr-toolkit' } | Select-Object -Last 1
        if (-not $cl -or -not $tl) { continue }
        if ($cl.Head -ne $tl.Head) { continue }
        $CERT_N = $n; $CERT_HEAD = $cl.Head; break
    }

    if ($null -eq $CERT_N) {
        # Uncertified: breaker inert (certification has not occurred yet).
        return @(
            "CERTIFIED:no",
            "POST_CERT_ROUNDS:0",
            "BREAKER:ok",
            "ADJUDICATED:$ADJ"
        )
    }

    # Rounds: max of (loop-counter − CERT_N) and the distinct post-cert evidence rows.
    $postNs = $rows | ForEach-Object { $_.N } | Sort-Object -Unique | Where-Object { $_ -gt $CERT_N }
    $ROWS_POST = @($postNs).Count
    $LOOP_POST = 0
    if ($LOOP_N -gt $CERT_N) { $LOOP_POST = $LOOP_N - $CERT_N }
    $POST_CERT_ROUNDS = $LOOP_POST
    if ($ROWS_POST -gt $POST_CERT_ROUNDS) { $POST_CERT_ROUNDS = $ROWS_POST }

    $BREAKER = 'ok'
    if ($POST_CERT_ROUNDS -gt $POST_CERT_REVIEW_ROUND_LIMIT) { $BREAKER = 'tripped' }
    # Post-certification count-less N/A = the breaker counter was erased -> fail closed.
    if ($NA_COUNTLESS) { $BREAKER = 'tripped' }

    return @(
        "CERTIFIED:yes",
        "POST_CERT_ROUNDS:$POST_CERT_ROUNDS",
        "BREAKER:$BREAKER",
        "ADJUDICATED:$ADJ"
    )
}

# Dual-mode entry point. When dot-sourced ($MyInvocation.InvocationName -eq '.'),
# only the function is defined and this block is skipped. When invoked as a script
# (e.g. `& review-breaker.ps1 state.md` or `powershell.exe -File ...`), parse the
# arg, call the function, print each sentinel on its own line via Write-Output
# (success stream — captured by both in-PS and bash-subprocess callers), and exit.
# Only the entrypoint may exit.
if ($MyInvocation.InvocationName -ne '.') {
    $stateArg = ''
    if ($args.Count -ge 1) { $stateArg = [string]$args[0] }
    $sentinels = Invoke-ReviewBreaker $stateArg
    foreach ($line in $sentinels) { Write-Output $line }
    exit 0
}
