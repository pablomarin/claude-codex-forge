# hooks/lib/review-scope.ps1 — PowerShell mirror of hooks/lib/review-scope.sh:
# single source of truth for the scoped-review-certification model (v5.54, ADR 0009).
# READ-ONLY: emits sentinel lines, never writes. Fail-open direction is MORE
# review: any ambiguity -> SCOPE_REQUIRED:full.
#
# Usage (standalone): review-scope.ps1 <state_md_path> [--before <N>]
#   (run from a checkout of the branch; --before <N> ignores iteration rows with
#    number >= N — the gate uses it to compute the PRIOR clean head for chain checks)
#
# Sentinels:
#   CERTIFIED:<yes|no>  LAST_CLEAN_HEAD:<sha|none>  ANCESTOR_OK:<yes|no|n/a>
#   PR_OWNED_DELTA:<empty|docs-only|code|n/a>  UPSTREAM_FILES:<none|nonruntime|code|n/a>
#   SCOPE_REQUIRED:<full|delta|mechanical>  POST_CERT_ROUNDS:<n>  BREAKER:<ok|tripped>
#   ADJUDICATED:<yes|no>   # human adjudication line present at the CURRENT head
#
# Dual-mode (CRITICAL for cross-launcher safety — mirrors default-branch.ps1):
#   On Windows, the shipped Claude Code launcher is `powershell.exe` (5.1).
#   Consumer hooks (check-workflow-gates.ps1 / build-evidence.ps1) MUST dot-source
#   this file and CALL the function, never subprocess it:
#       . "$libPath\review-scope.ps1"
#       $sentinels = Invoke-ReviewScope $StateFile $beforeN
#   A script-style helper with `exit` statements would terminate the CALLING hook
#   mid-validation. Therefore: the function RETURNS the sentinel lines (string
#   array) and NEVER calls `exit`; early fail-closed paths `return` the block.
#   Only the standalone entrypoint at the bottom may `exit`.
#
# PowerShell 5.1-compatible (no 7-only syntax): no `&&`/`||` pipeline chains, no
# ternary, no null-coalescing. Git via `& git ... 2>$null` + $LASTEXITCODE checks.

$POST_CERT_REVIEW_ROUND_LIMIT = 3   # canonical home mirrored from review-scope.sh

function Invoke-ReviewScope {
    param(
        [string]$StateFile,
        [int]$BeforeN = 999999
    )

    $ErrorActionPreference = 'SilentlyContinue'

    # Sentinel block for the fail-closed-to-full direction. Mirrors emit_full() in
    # the bash helper: SCOPE_REQUIRED:full + the three trailing fields.
    function _emit_full {
        param([int]$Rounds = 0, [string]$Breaker = 'ok', [string]$Adj = 'no')
        return @(
            "SCOPE_REQUIRED:full",
            "POST_CERT_ROUNDS:$Rounds",
            "BREAKER:$Breaker",
            "ADJUDICATED:$Adj"
        )
    }
    # The five-line fail-closed prefix used by the early bail paths (missing state,
    # no git, detached HEAD, broken ancestry). Mirrors the bash inline echoes.
    function _failclosed_prefix {
        return @(
            "CERTIFIED:no",
            "LAST_CLEAN_HEAD:none",
            "ANCESTOR_OK:n/a",
            "PR_OWNED_DELTA:n/a",
            "UPSTREAM_FILES:n/a"
        )
    }
    # _emit_uncertified: the fail-closed prefix + _emit_full, as one block. Mirrors
    # emit_uncertified() in the bash helper — the early guards (missing state, no
    # git, detached HEAD) and the no-certification return all emit this identical
    # preamble, extracted to one site so the "uncertified -> full" output can never
    # drift between them.
    function _emit_uncertified {
        param([int]$Rounds = 0, [string]$Breaker = 'ok', [string]$Adj = 'no')
        return (_failclosed_prefix) + (_emit_full $Rounds $Breaker $Adj)
    }

    # --- guards (mirror lines 21-25 of review-scope.sh) ---
    if (-not $StateFile -or -not (Test-Path -LiteralPath $StateFile -PathType Leaf)) {
        return (_emit_uncertified 0 'ok' 'no')
    }
    & git rev-parse HEAD 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return (_emit_uncertified 0 'ok' 'no')
    }
    # Detached HEAD -> fail closed to full: scoped evidence binds to a BRANCH's
    # review history; a detached checkout has none.
    & git symbolic-ref -q HEAD 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return (_emit_uncertified 0 'ok' 'no')
    }

    # --- default branch via the sibling helper, fallback main ---
    $libDir = Split-Path -Parent $PSCommandPath
    if (-not $libDir) { $libDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
    $DEFAULT_BRANCH = 'main'
    $dbHelper = Join-Path $libDir 'default-branch.ps1'
    if (Test-Path -LiteralPath $dbHelper -PathType Leaf) {
        # Dot-source into a child scope via &-block to avoid clobbering our funcs,
        # then call. default-branch.ps1 defines Get-DefaultBranch when dot-sourced.
        . $dbHelper
        $db = Get-DefaultBranch
        if ($db) { $DEFAULT_BRANCH = $db }
    }
    $DEFAULT_REF = $DEFAULT_BRANCH
    & git rev-parse --verify "origin/$DEFAULT_BRANCH" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $DEFAULT_REF = "origin/$DEFAULT_BRANCH" }
    $HEAD_SHA = (& git rev-parse HEAD 2>$null | Select-Object -First 1)

    # --- docs predicate — SAME SEMANTICS as is_docs()/_is_doc_path() ---
    # curated doc basenames anywhere; prose extensions ONLY under a docs/ dir; bare
    # *.md outside docs/ is CODE; docs/foo.py and docs/config.json are CODE.
    function Test-IsDocs {
        param([string]$Path)
        $base = Split-Path -Leaf $Path
        switch -Wildcard -CaseSensitive ($base) {
            'README'          { return $true }
            'CHANGELOG'       { return $true }
            'LICENSE'         { return $true }
            'NOTICE'          { return $true }
            'AUTHORS'         { return $true }
            'CONTRIBUTORS'    { return $true }
            'CONTRIBUTING'    { return $true }
            'CODE_OF_CONDUCT' { return $true }
        }
        # Prefixed curated docs (README*, CHANGELOG*, ...) with a prose extension.
        $prefixed = $false
        switch -Wildcard -CaseSensitive ($base) {
            'README*'          { $prefixed = $true }
            'CHANGELOG*'       { $prefixed = $true }
            'LICENSE*'         { $prefixed = $true }
            'CONTRIBUTORS*'    { $prefixed = $true }
            'CONTRIBUTING*'    { $prefixed = $true }
            'CODE_OF_CONDUCT*' { $prefixed = $true }
        }
        if ($prefixed) {
            switch -Wildcard -CaseSensitive ($base) {
                '*.md'       { return $true }
                '*.mdx'      { return $true }
                '*.markdown' { return $true }
                '*.rst'      { return $true }
                '*.txt'      { return $true }
            }
        }
        # Prose extensions under a docs/ directory (docs/* or */docs/*).
        $underDocs = $false
        switch -Wildcard -CaseSensitive ($Path) {
            'docs/*'   { $underDocs = $true }
            '*/docs/*' { $underDocs = $true }
        }
        if ($underDocs) {
            switch -Wildcard -CaseSensitive ($base) {
                '*.md'       { return $true }
                '*.mdx'      { return $true }
                '*.markdown' { return $true }
                '*.rst'      { return $true }
            }
        }
        return $false
    }

    # patch-id with EXPLICIT status checks (mirror pid()). Returns the patch-id hash
    # string, or $null on ANY git failure (caller fails closed). The merge-base is
    # PRECOMPUTED by the caller (Invoke-Classify already has $mba/$mbb), so this no
    # longer re-spawns `git merge-base` per call. Optional -File restricts the diff.
    function Get-Pid {
        param([string]$MergeBase, [string]$Commit, [string]$File)
        if ($File) {
            $d = & git diff --no-renames $MergeBase $Commit -- $File 2>$null
        } else {
            $d = & git diff --no-renames $MergeBase $Commit 2>$null
        }
        if ($LASTEXITCODE -ne 0) { return $null }
        $text = ($d -join "`n")
        $out = $text | & git patch-id --stable 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        $first = ($out | Select-Object -First 1)
        if (-not $first) { return '' }   # empty diff -> empty patch-id (mirror)
        return ($first -split '\s+')[0]
    }

    # classify <from> <to> — sets script:C_DELTA (empty|docs-only|code) and
    # script:C_UP (none|nonruntime|code). Returns $false on ANY git failure or
    # broken ancestry (caller fails toward MORE review). Mirrors classify().
    $script:C_DELTA = 'empty'
    $script:C_UP = 'none'
    function Invoke-Classify {
        param([string]$From, [string]$To)
        & git cat-file -e $From 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        & git merge-base --is-ancestor $From $To 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        $mba = & git merge-base $DEFAULT_REF $From 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $mba = ($mba | Select-Object -First 1)
        $mbb = & git merge-base $DEFAULT_REF $To 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $mbb = ($mbb | Select-Object -First 1)
        $pa = Get-Pid $mba $From
        if ($null -eq $pa) { return $false }
        $pb = Get-Pid $mbb $To
        if ($null -eq $pb) { return $false }
        $script:C_DELTA = 'empty'
        if ($pa -ne $pb) {
            $script:C_DELTA = 'docs-only'
            $f1 = & git diff --name-only --no-renames $mba $From 2>$null
            if ($LASTEXITCODE -ne 0) { return $false }
            $f2 = & git diff --name-only --no-renames $mbb $To 2>$null
            if ($LASTEXITCODE -ne 0) { return $false }
            $files = @()
            if ($f1) { $files += $f1 }
            if ($f2) { $files += $f2 }
            $files = $files | Where-Object { $_ -ne '' } | Sort-Object -Unique
            foreach ($file in $files) {
                if (-not $file) { continue }
                # Paths git quotes (leading `"`) are unresolvable here -> fail closed.
                if ($file.StartsWith('"')) { return $false }
                $fa = Get-Pid $mba $From $file
                if ($null -eq $fa) { return $false }
                $fb = Get-Pid $mbb $To $file
                if ($null -eq $fb) { return $false }
                if ($fa -eq $fb) { continue }
                if (-not (Test-IsDocs $file)) { $script:C_DELTA = 'code'; break }
            }
        }
        $script:C_UP = 'none'
        $upf = & git diff --name-only --no-renames $mba $mbb 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        if ($upf) {
            $script:C_UP = 'nonruntime'
            foreach ($file in $upf) {
                if (-not $file) { continue }
                if ($file.StartsWith('"')) { return $false }
                if (-not (Test-IsDocs $file)) { $script:C_UP = 'code'; break }
            }
        }
        return $true
    }

    # full_base_ok <head> <base> — a scope=full row's recorded base must be the
    # true merge-base of DEFAULT_REF and that head. Mirrors full_base_ok().
    function Test-FullBaseOk {
        param([string]$Head, [string]$Base)
        $mb = & git merge-base $DEFAULT_REF $Head 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
        $mb = ($mb | Select-Object -First 1)
        return ($mb -eq $Base)
    }

    # --- read state.md, CRLF-safe; isolate the ### Checklist of ## Workflow ---
    $raw = Get-Content -LiteralPath $StateFile -Raw
    $raw = $raw -replace "`r", ""
    $lines = $raw -split "`n"
    # EXACT heading anchor (^## Workflow$) — a stale "## Workflow Archive" section
    # from a migration must not feed the chain.
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

    # --- parse evidence rows: object list with N|tool|scope|head|base ---
    # Rows with N >= BeforeN are excluded; deep-pass rows dropped; UNKNOWN scope
    # values dropped entirely (NOT legacy); rows missing head dropped.
    $rows = @()
    foreach ($ln in $checklist) {
        $m = [regex]::Match($ln, '^- \[x\] Code review iteration ([0-9]+) — ')
        if (-not $m.Success) { continue }
        $n = [int]$m.Groups[1].Value
        if ($n -ge $BeforeN) { continue }
        $tool = ''
        if ($ln -match '— codex deep-pass clean') { $tool = 'deep-pass' }
        elseif ($ln -match '— codex clean') { $tool = 'codex' }
        elseif ($ln -match '— pr-toolkit clean') { $tool = 'pr-toolkit' }
        elseif ($ln -match '— mechanical re-stamp') { $tool = 'mechanical' }
        if ($tool -eq '' -or $tool -eq 'deep-pass') { continue }
        # scope value must be delimiter-bound: scope=fullish is UNKNOWN -> drop row.
        $scope = 'legacy'
        if ($ln -cmatch 'scope=') {
            $sm = [regex]::Match($ln, 'scope=(full|delta|mechanical)(\s|$)')
            if ($sm.Success) { $scope = $sm.Groups[1].Value }
            else { continue }
        }
        $head = ''
        $hm = [regex]::Match($ln, 'head=`([0-9a-f]+)`')
        if ($hm.Success) { $head = $hm.Groups[1].Value }
        $base = ''
        $bm = [regex]::Match($ln, 'base=`([0-9a-f]+)`')
        if ($bm.Success) { $base = $bm.Groups[1].Value }
        if ($head -eq '') { continue }
        $rows += [pscustomobject]@{ N = $n; Tool = $tool; Scope = $scope; Head = $head; Base = $base }
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

    # Human adjudication line bound to the CURRENT head.
    $ADJ = 'no'
    foreach ($ln in $checklist) {
        if (($ln -match '^- \[x\] Post-certification tail adjudicated by human — ') -and ($ln -match [regex]::Escape('head=`' + $HEAD_SHA + '`'))) {
            $ADJ = 'yes'
        }
    }

    # --- certification: lowest N with a COHERENT codex+pr-toolkit pair at the
    # same head, scope full or legacy. ---
    $sortedNs = $rows | ForEach-Object { $_.N } | Sort-Object -Unique
    $CERT_N = $null
    $CERT_HEAD = ''
    foreach ($n in $sortedNs) {
        $cl = $rows | Where-Object { $_.N -eq $n -and $_.Tool -eq 'codex' -and ($_.Scope -eq 'full' -or $_.Scope -eq 'legacy') } | Select-Object -Last 1
        $tl = $rows | Where-Object { $_.N -eq $n -and $_.Tool -eq 'pr-toolkit' -and ($_.Scope -eq 'full' -or $_.Scope -eq 'legacy') } | Select-Object -Last 1
        if (-not $cl -or -not $tl) { continue }
        if ($cl.Head -ne $tl.Head) { continue }
        if ($cl.Base -ne '' -and $tl.Base -ne '' -and $cl.Base -ne $tl.Base) { continue }
        # A scope=full row MUST carry a valid base (= true merge-base for its head);
        # only legacy scope-less rows may omit base (back-compat).
        $ok = $true
        if ($cl.Scope -eq 'full') {
            if (-not ($cl.Base -ne '' -and (Test-FullBaseOk $cl.Head $cl.Base))) { $ok = $false }
        }
        if ($tl.Scope -eq 'full') {
            if (-not ($tl.Base -ne '' -and (Test-FullBaseOk $tl.Head $tl.Base))) { $ok = $false }
        }
        if (-not $ok) { continue }
        $CERT_N = $n; $CERT_HEAD = $cl.Head; break
    }

    if ($null -eq $CERT_N) {
        return (_emit_uncertified 0 'ok' $ADJ)
    }

    $result = @("CERTIFIED:yes")

    # --- last clean head: walk post-cert iterations, advancing ONLY on rows that
    # re-validate TODAY. ---
    $LAST_CLEAN_HEAD = $CERT_HEAD
    foreach ($n in $sortedNs) {
        if ($n -le $CERT_N) { continue }
        $mrow = $rows | Where-Object { $_.N -eq $n -and $_.Tool -eq 'mechanical' -and $_.Scope -eq 'mechanical' } | Select-Object -Last 1
        if ($mrow) {
            if ($mrow.Base -eq $LAST_CLEAN_HEAD) {
                if (Invoke-Classify $LAST_CLEAN_HEAD $mrow.Head) {
                    if ($script:C_DELTA -ne 'code' -and $script:C_UP -ne 'code') {
                        $LAST_CLEAN_HEAD = $mrow.Head
                    }
                }
            }
            continue
        }
        $cl = $rows | Where-Object { $_.N -eq $n -and $_.Tool -eq 'codex' -and ($_.Scope -eq 'full' -or $_.Scope -eq 'delta') } | Select-Object -Last 1
        $tl = $rows | Where-Object { $_.N -eq $n -and $_.Tool -eq 'pr-toolkit' -and ($_.Scope -eq 'full' -or $_.Scope -eq 'delta') } | Select-Object -Last 1
        if (-not $cl -or -not $tl) { continue }
        if (-not ($cl.Scope -eq $tl.Scope -and $cl.Head -eq $tl.Head -and $cl.Base -eq $tl.Base -and $cl.Base -ne '')) { continue }
        if ($cl.Scope -eq 'delta') {
            if ($cl.Base -ne $LAST_CLEAN_HEAD) { continue }   # stale-base delta never advances
            if (-not (Invoke-Classify $LAST_CLEAN_HEAD $cl.Head)) { continue }
        }
        else {
            if (-not (Test-FullBaseOk $cl.Head $cl.Base)) { continue }
        }
        $LAST_CLEAN_HEAD = $cl.Head
    }
    $result += "LAST_CLEAN_HEAD:$LAST_CLEAN_HEAD"

    # Rounds: max of (loop-counter − CERT_N) and the distinct post-cert evidence rows.
    $ROWS_POST = ($sortedNs | Where-Object { $_ -gt $CERT_N } | Measure-Object).Count
    $LOOP_POST = 0
    if ($LOOP_N -gt $CERT_N) { $LOOP_POST = $LOOP_N - $CERT_N }
    $POST_CERT_ROUNDS = $ROWS_POST
    if ($LOOP_POST -gt $ROWS_POST) { $POST_CERT_ROUNDS = $LOOP_POST }
    $BREAKER = 'ok'
    if ($POST_CERT_ROUNDS -gt $POST_CERT_REVIEW_ROUND_LIMIT) { $BREAKER = 'tripped' }
    if ($NA_COUNTLESS) { $BREAKER = 'tripped' }

    # --- ancestry + PR-owned delta classification (chain head -> current HEAD) ---
    if (-not (Invoke-Classify $LAST_CLEAN_HEAD $HEAD_SHA)) {
        $result += "ANCESTOR_OK:no"
        $result += "PR_OWNED_DELTA:n/a"
        $result += "UPSTREAM_FILES:n/a"
        return $result + (_emit_full $POST_CERT_ROUNDS $BREAKER $ADJ)
    }
    $result += "ANCESTOR_OK:yes"
    $result += "PR_OWNED_DELTA:$($script:C_DELTA)"

    # Fold UNMERGED default-branch movement into the upstream surface.
    $MBH = & git merge-base $DEFAULT_REF $HEAD_SHA 2>$null
    if ($LASTEXITCODE -ne 0) {
        $result += "UPSTREAM_FILES:n/a"
        return $result + (_emit_full $POST_CERT_ROUNDS $BREAKER $ADJ)
    }
    $MBH = ($MBH | Select-Object -First 1)
    $PEND = & git diff --name-only --no-renames $MBH $DEFAULT_REF 2>$null
    if ($LASTEXITCODE -ne 0) {
        $result += "UPSTREAM_FILES:n/a"
        return $result + (_emit_full $POST_CERT_ROUNDS $BREAKER $ADJ)
    }
    $C_UP = $script:C_UP
    if ($PEND) {
        if ($C_UP -eq 'none') { $C_UP = 'nonruntime' }
        foreach ($file in $PEND) {
            if (-not $file) { continue }
            if ($file.StartsWith('"')) { $C_UP = 'code'; break }   # quoted path -> review
            if (-not (Test-IsDocs $file)) { $C_UP = 'code'; break }
        }
    }
    $result += "UPSTREAM_FILES:$C_UP"

    $SCOPE = 'mechanical'
    if ($script:C_DELTA -eq 'code' -or $C_UP -eq 'code') { $SCOPE = 'delta' }
    $result += "SCOPE_REQUIRED:$SCOPE"
    $result += "POST_CERT_ROUNDS:$POST_CERT_ROUNDS"
    $result += "BREAKER:$BREAKER"
    $result += "ADJUDICATED:$ADJ"
    return $result
}

# Dual-mode entry point. When dot-sourced ($MyInvocation.InvocationName -eq '.'),
# only the function is defined and this block is skipped. When invoked as a script
# (e.g. `& review-scope.ps1 state.md --before 3` or `powershell.exe -File ...`),
# parse the args, call the function, print each sentinel on its own line via
# Write-Output (success stream — captured by both in-PS and bash-subprocess callers),
# and exit. Only the entrypoint may exit.
if ($MyInvocation.InvocationName -ne '.') {
    $stateArg = ''
    $beforeArg = 999999
    if ($args.Count -ge 1) { $stateArg = [string]$args[0] }
    if ($args.Count -ge 3 -and [string]$args[1] -eq '--before') {
        $tmp = 0
        if ([int]::TryParse([string]$args[2], [ref]$tmp)) { $beforeArg = $tmp }
    }
    $sentinels = Invoke-ReviewScope $stateArg $beforeArg
    foreach ($line in $sentinels) { Write-Output $line }
    exit 0
}
