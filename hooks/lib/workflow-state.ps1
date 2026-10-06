# Bounded cross-engine workflow state transitions. Windows PowerShell 5.1 compatible.

$WorkflowStateDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $WorkflowStateDir "state-path.ps1")

function Throw-WorkflowStateBlocked {
    param([Parameter(Mandatory = $true)][string]$Message)
    throw "BLOCKED: $Message"
}

function Get-WorkflowStateHash {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-WorkflowStateRoot {
    $raw = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { Throw-WorkflowStateBlocked "not inside a Git worktree" }
    return (Resolve-Path -LiteralPath $raw.Trim() -ErrorAction Stop).Path
}

function Get-WorkflowStateValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key
    )
    $current = ""
    $values = New-Object Collections.Generic.List[string]
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^## (.+)$') { $current = $Matches[1]; continue }
        if ($current -eq $Section -and $line -match '^\|') {
            $cells = $line -split '\|'
            if ($cells.Count -ge 4 -and $cells[1].Trim() -eq $Key) { $values.Add($cells[2].Trim()) }
        }
    }
    if ($values.Count -ne 1) { Throw-WorkflowStateBlocked "state must contain exactly one $Section/$Key row" }
    return $values[0]
}

function Test-WorkflowStateShape {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-ForgeStateV6 $Path)) { return $false }
    $required = @(
        @("Identity", "Worktree root"),
        @("Identity", "Git common directory"),
        @("Identity", "Last active host"),
        @("Identity", "Workflow base ref"),
        @("Identity", "Workflow base SHA"),
        @("Workflow", "Command"),
        @("Workflow", "Phase"),
        @("Workflow", "Next step"),
        @("Receipts", "Review iteration"),
        @("Receipts", "Candidate receipt"),
        @("Receipts", "Spec review receipt"),
        @("Receipts", "Quality review receipt"),
        @("Receipts", "Verify app receipt"),
        @("Receipts", "E2E receipt"),
        @("Receipts", "Promotion receipt"),
        @("Receipts", "Council receipt")
    )
    try {
        foreach ($pair in $required) { [void](Get-WorkflowStateValue -Path $Path -Section $pair[0] -Key $pair[1]) }
        $firstCount = 0
        $section = ""
        foreach ($line in [IO.File]::ReadAllLines($Path)) {
            if ($line -match '^## (.+)$') { $section = $Matches[1]; continue }
            if ($section -eq 'Receipts' -and $line -match '^\|') {
                $cells = $line -split '\|'
                if ($cells.Count -ge 4 -and $cells[1].Trim() -eq 'First certified iteration') { $firstCount++ }
            }
        }
        if ($firstCount -gt 1) { return $false }
    }
    catch { return $false }
    return $true
}

function Get-CanonicalWorkflowState {
    param([Parameter(Mandatory = $true)][string]$Root)
    $state = Get-ForgeStatePath -Root $Root -Mode Read
    $canonical = Join-Path $Root ".forge\local\state.md"
    if (-not $state -or [IO.Path]::GetFullPath($state) -ne [IO.Path]::GetFullPath($canonical)) {
        Throw-WorkflowStateBlocked "workflow-state supports canonical Forge V6 state only"
    }
    if (-not (Test-WorkflowStateShape -Path $state)) { Throw-WorkflowStateBlocked "invalid canonical Forge V6 state" }
    return $state
}

function Assert-WorkflowStateCell {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Value
    )
    if ([string]::IsNullOrEmpty($Value)) { Throw-WorkflowStateBlocked "$Label must not be empty" }
    if ($Value.Contains("|") -or $Value.Contains("`r") -or $Value.Contains("`n")) {
        Throw-WorkflowStateBlocked "$Label must be one Markdown-safe line"
    }
    if ($Value.Trim() -ne $Value) { Throw-WorkflowStateBlocked "$Label must not have outer whitespace" }
}

function Assert-WorkflowStateTask {
    param([Parameter(Mandatory = $true)][string]$Task)
    Assert-WorkflowStateCell -Label "task slug" -Value $Task
    if ($Task.Length -gt 64 -or $Task -cnotmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
        Throw-WorkflowStateBlocked "invalid task slug: $Task"
    }
}

function Get-OptionalFirstCertifiedIteration {
    param([Parameter(Mandatory = $true)][string]$State)
    $values = New-Object Collections.Generic.List[string]
    $section = ""
    foreach ($line in [IO.File]::ReadAllLines($State)) {
        if ($line -match '^## (.+)$') { $section = $Matches[1]; continue }
        if ($section -eq 'Receipts' -and $line -match '^\|') {
            $cells = $line -split '\|'
            if ($cells.Count -ge 4 -and $cells[1].Trim() -eq 'First certified iteration') {
                $values.Add($cells[2].Trim())
            }
        }
    }
    if ($values.Count -eq 0) { return 'none' }
    if ($values.Count -ne 1) { Throw-WorkflowStateBlocked 'state must contain at most one Receipts/First certified iteration row' }
    return $values[0]
}

function Get-OptionalWorkflowStateValue {
    param(
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key
    )
    $values = New-Object Collections.Generic.List[string]
    $current = ""
    foreach ($line in [IO.File]::ReadAllLines($State)) {
        if ($line -match '^## (.+)$') { $current = $Matches[1]; continue }
        if ($current -eq $Section -and $line -match '^\|') {
            $cells = $line -split '\|'
            if ($cells.Count -ge 4 -and $cells[1].Trim() -eq $Key) { $values.Add($cells[2].Trim()) }
        }
    }
    if ($values.Count -gt 1) { Throw-WorkflowStateBlocked "state must contain at most one $Section/$Key row" }
    if ($values.Count -eq 0) { return '' }
    return $values[0]
}

function Write-WorkflowStateLines {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines
    )
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, ([string]::Join("`n", $Lines) + "`n"), $utf8)
}

function Test-WorkflowStateReviewsValid {
    param([Parameter(Mandatory = $true)][string]$State)
    $verifier = Join-Path $WorkflowStateDir 'verification-receipt.ps1'
    if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) { return $false }
    try {
        . $verifier
        $response = Invoke-VerificationReceipt -ReceiptMode check -StatePath $State
        return ($response.Lines -contains 'REVIEWS_VALID:true')
    }
    catch { return $false }
}

function Assert-WorkflowStateRef {
    param([Parameter(Mandatory = $true)][string]$Ref)
    Assert-WorkflowStateCell -Label "base ref" -Value $Ref
    if ($Ref.StartsWith("-")) { Throw-WorkflowStateBlocked "invalid base ref: $Ref" }
    foreach ($forbidden in @("..", "@{", "~", "^", ":", "?", "*", "[", "\")) {
        if ($Ref.Contains($forbidden)) { Throw-WorkflowStateBlocked "invalid base ref: $Ref" }
    }
}

function Get-WorkflowStateCommonDirectory {
    param([Parameter(Mandatory = $true)][string]$Root)
    $raw = & git -C $Root rev-parse --git-common-dir 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { Throw-WorkflowStateBlocked "cannot resolve Git common directory" }
    $path = $raw.Trim()
    if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $Root $path }
    return (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path
}

function Publish-ForgeWorkflowState {
    param(
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][string]$Next,
        [Parameter(Mandatory = $true)][string]$ExpectedHash
    )
    if (-not (Test-Path -LiteralPath $Next -PathType Leaf)) {
        Throw-WorkflowStateBlocked "invalid workflow-state temporary file"
    }
    $nextItem = Get-Item -LiteralPath $Next -Force
    if ($nextItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Throw-WorkflowStateBlocked "invalid workflow-state temporary file"
    }
    if ((Get-WorkflowStateHash -Path $State) -ne $ExpectedHash) {
        Throw-WorkflowStateBlocked "workflow state changed concurrently; retry from show"
    }
    [IO.File]::Replace($Next, $State, [System.Management.Automation.Language.NullString]::Value)
}

function Set-WorkflowStateActivationFile {
    param(
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][string]$Next,
        [Parameter(Mandatory = $true)][ValidateSet("new", "resume", "adopt")][string]$Mode,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Common,
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][string]$BaseRef,
        [Parameter(Mandatory = $true)][string]$BaseSha,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][string]$NextStep,
        [Parameter(Mandatory = $true)][string]$Task
    )
    $section = ""
    $firstSeen = $false
    $receiptsTable = $false
    $output = New-Object Collections.Generic.List[string]
    foreach ($line in [IO.File]::ReadAllLines($State)) {
        $current = $line
        if ($section -eq 'Receipts' -and $receiptsTable -and -not $firstSeen -and -not $line.StartsWith('|')) {
            $output.Add('| First certified iteration | none |')
            $firstSeen = $true
        }
        if ($line -match '^## (.+)$') {
            if ($section -eq 'Receipts' -and -not $firstSeen) {
                $output.Add('| First certified iteration | none |')
                $firstSeen = $true
            }
            $section = $Matches[1]
        }
        if ($line -match '^\|') {
            $cells = $line -split '\|'
            $key = if ($cells.Count -ge 4) { $cells[1].Trim() } else { "" }
            if ($section -eq "Identity") {
                if ($key -eq "Last active host") { $current = "| Last active host     | $HostName |" }
                elseif ($Mode -eq "new" -and $key -eq "Worktree root") { $current = "| Worktree root        | $Root |" }
                elseif ($Mode -eq "new" -and $key -eq "Git common directory") { $current = "| Git common directory | $Common |" }
                elseif ($Mode -eq "new" -and $key -eq "Workflow base ref") { $current = "| Workflow base ref    | $BaseRef |" }
                elseif ($Mode -eq "new" -and $key -eq "Workflow base SHA") { $current = "| Workflow base SHA    | $BaseSha |" }
            }
            elseif ($Mode -ne "resume" -and $section -eq "Workflow") {
                if ($key -eq "Command") { $current = "| Command   | $Command |" }
                elseif ($key -eq "Phase") { $current = "| Phase     | $Phase |" }
                elseif ($key -eq "Next step") { $current = "| Next step | $NextStep |" }
            }
            elseif ($section -eq "Receipts") {
                if ($key -eq 'Review iteration') { $receiptsTable = $true }
                if ($key -eq 'First certified iteration') {
                    $firstSeen = $true
                    if ($Mode -ne 'resume') { $current = '| First certified iteration | none |' }
                }
                elseif ($Mode -ne 'resume') {
                    if ($key -eq "Review iteration") { $current = "| Review iteration       | 0 |" }
                    elseif ($key -eq "Candidate receipt") { $current = "| Candidate receipt      | .forge/local/evidence/$Task/candidate.receipt |" }
                    elseif ($key -eq "Spec review receipt") { $current = "| Spec review receipt    | .forge/local/reviews/$Task/spec.receipt |" }
                    elseif ($key -eq "Quality review receipt") { $current = "| Quality review receipt | .forge/local/reviews/$Task/quality.receipt |" }
                    elseif ($key -eq "Verify app receipt") { $current = "| Verify app receipt     | .forge/local/evidence/$Task/verify-app.receipt |" }
                    elseif ($key -eq "E2E receipt") { $current = "| E2E receipt            | .forge/local/evidence/$Task/e2e.receipt |" }
                    elseif ($key -eq "Promotion receipt") { $current = "| Promotion receipt      | .forge/local/evidence/$Task/promotion.receipt |" }
                }
            }
        }
        $output.Add($current)
    }
    if ($section -eq 'Receipts' -and -not $firstSeen) { $output.Add('| First certified iteration | none |') }
    Write-WorkflowStateLines -Path $Next -Lines $output.ToArray()
}

function Set-WorkflowStateRebindFile {
    param(
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][string]$Next,
        [Parameter(Mandatory = $true)][string]$BaseSha
    )
    $section = ""
    $output = New-Object Collections.Generic.List[string]
    foreach ($line in [IO.File]::ReadAllLines($State)) {
        $current = $line
        if ($line -match '^## (.+)$') { $section = $Matches[1] }
        if ($section -eq 'Identity' -and $line -match '^\|') {
            $cells = $line -split '\|'
            if ($cells.Count -ge 4 -and $cells[1].Trim() -eq 'Workflow base SHA') {
                $current = "| Workflow base SHA    | $BaseSha |"
            }
        }
        $output.Add($current)
    }
    Write-WorkflowStateLines -Path $Next -Lines $output.ToArray()
}

function Get-NextWorkflowReviewIteration {
    param([Parameter(Mandatory = $true)][string]$Value)
    $digits = $Value.ToCharArray()
    $carry = 1
    for ($i = $digits.Length - 1; $i -ge 0; $i--) {
        $digit = [int]::Parse($digits[$i].ToString())
        if ($carry -eq 1) {
            $digit++
            if ($digit -eq 10) { $digit = 0 } else { $carry = 0 }
        }
        $digits[$i] = [char]([int][char]'0' + $digit)
    }
    $result = -join $digits
    if ($carry -eq 1) { $result = "1$result" }
    return $result
}

function Set-WorkflowStateCheckpointFile {
    param(
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][string]$Next,
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][string]$NextStep,
        [Parameter(Mandatory = $true)][string]$Iteration,
        [Parameter(Mandatory = $true)][string]$FirstCertified
    )
    $section = ""
    $firstSeen = $false
    $receiptsTable = $false
    $output = New-Object Collections.Generic.List[string]
    foreach ($line in [IO.File]::ReadAllLines($State)) {
        $current = $line
        if ($section -eq 'Receipts' -and $receiptsTable -and -not $firstSeen -and -not $line.StartsWith('|')) {
            $output.Add("| First certified iteration | $FirstCertified |")
            $firstSeen = $true
        }
        if ($line -match '^## (.+)$') {
            if ($section -eq 'Receipts' -and -not $firstSeen) {
                $output.Add("| First certified iteration | $FirstCertified |")
                $firstSeen = $true
            }
            $section = $Matches[1]
        }
        if ($line -match '^\|') {
            $cells = $line -split '\|'
            $key = if ($cells.Count -ge 4) { $cells[1].Trim() } else { "" }
            if ($section -eq "Identity" -and $key -eq "Last active host") {
                $current = "| Last active host     | $HostName |"
            }
            elseif ($section -eq "Workflow" -and $key -eq "Phase") {
                $current = "| Phase     | $Phase |"
            }
            elseif ($section -eq "Workflow" -and $key -eq "Next step") {
                $current = "| Next step | $NextStep |"
            }
            elseif ($section -eq "Receipts" -and $key -eq "Review iteration") {
                $receiptsTable = $true
                $current = "| Review iteration       | $Iteration |"
            }
            elseif ($section -eq "Receipts" -and $key -eq "First certified iteration") {
                $current = "| First certified iteration | $FirstCertified |"
                $firstSeen = $true
            }
        }
        $output.Add($current)
    }
    if ($section -eq 'Receipts' -and -not $firstSeen) {
        $output.Add("| First certified iteration | $FirstCertified |")
    }
    Write-WorkflowStateLines -Path $Next -Lines $output.ToArray()
}

function Convert-WorkflowStateArguments {
    param([Parameter(Mandatory = $true)][string[]]$Tokens)
    $values = @{}
    for ($i = 0; $i -lt $Tokens.Count; $i += 2) {
        if ($i + 1 -ge $Tokens.Count) { Throw-WorkflowStateBlocked "option requires a value: $($Tokens[$i])" }
        $name = $Tokens[$i]
        if ($name -notin @("--host", "--workflow", "--task", "--base-ref", "--phase", "--next-step")) {
            Throw-WorkflowStateBlocked "unsupported activate option: $name"
        }
        if ($values.ContainsKey($name)) { Throw-WorkflowStateBlocked "duplicate activate option: $name" }
        $values[$name] = $Tokens[$i + 1]
    }
    foreach ($name in @("--host", "--workflow", "--task", "--base-ref", "--phase", "--next-step")) {
        if (-not $values.ContainsKey($name)) {
            Throw-WorkflowStateBlocked "activate requires host, workflow, task, base-ref, phase, and next-step"
        }
    }
    return $values
}

function Invoke-WorkflowStateShow {
    $root = Get-WorkflowStateRoot
    $state = Get-CanonicalWorkflowState -Root $root
    $bytes = [IO.File]::ReadAllBytes($state)
    $stream = [Console]::OpenStandardOutput()
    $stream.Write($bytes, 0, $bytes.Length)
}

function Convert-WorkflowStateRebindArguments {
    param([Parameter(Mandatory = $true)][string[]]$Tokens)
    $values = @{}
    for ($i = 0; $i -lt $Tokens.Count; $i += 2) {
        if ($i + 1 -ge $Tokens.Count) { Throw-WorkflowStateBlocked "option requires a value: $($Tokens[$i])" }
        $name = $Tokens[$i]
        if ($name -notin @('--base-ref', '--expected-base-sha')) {
            Throw-WorkflowStateBlocked "unsupported rebind option: $name"
        }
        if ($values.ContainsKey($name)) { Throw-WorkflowStateBlocked "duplicate rebind option: $name" }
        $values[$name] = $Tokens[$i + 1]
    }
    foreach ($name in @('--base-ref', '--expected-base-sha')) {
        if (-not $values.ContainsKey($name)) { Throw-WorkflowStateBlocked 'rebind requires base-ref and expected-base-sha' }
    }
    return $values
}

function Invoke-WorkflowStateRebind {
    param([Parameter(Mandatory = $true)][string[]]$Tokens)
    $values = Convert-WorkflowStateRebindArguments -Tokens $Tokens
    $baseRef = $values['--base-ref']
    $expectedBaseSha = $values['--expected-base-sha']
    Assert-WorkflowStateRef -Ref $baseRef
    if ($expectedBaseSha -cnotmatch '^[0-9a-f]{40}([0-9a-f]{24})?$') {
        Throw-WorkflowStateBlocked 'expected base SHA must be a full lowercase Git object id'
    }

    $root = Get-WorkflowStateRoot
    $common = Get-WorkflowStateCommonDirectory -Root $root
    $state = Get-CanonicalWorkflowState -Root $root
    $stateHash = Get-WorkflowStateHash -Path $state
    $currentRoot = Get-WorkflowStateValue -Path $state -Section Identity -Key 'Worktree root'
    $currentCommon = Get-WorkflowStateValue -Path $state -Section Identity -Key 'Git common directory'
    $currentBaseRef = Get-WorkflowStateValue -Path $state -Section Identity -Key 'Workflow base ref'
    $currentBaseSha = Get-WorkflowStateValue -Path $state -Section Identity -Key 'Workflow base SHA'
    $currentCommand = Get-WorkflowStateValue -Path $state -Section Workflow -Key Command
    $currentPhase = Get-WorkflowStateValue -Path $state -Section Workflow -Key Phase
    $currentNext = Get-WorkflowStateValue -Path $state -Section Workflow -Key 'Next step'
    $currentIteration = Get-WorkflowStateValue -Path $state -Section Receipts -Key 'Review iteration'
    $firstCertified = Get-OptionalFirstCertifiedIteration -State $state
    $goalNonce = Get-OptionalWorkflowStateValue -State $state -Section '/goal session' -Key nonce

    if ($currentRoot -ne $root -or $currentCommon -ne $common -or $currentBaseRef -ne $baseRef) {
        Throw-WorkflowStateBlocked 'rebind identity differs from the inactive worktree binding'
    }
    if ($currentBaseSha -ne $expectedBaseSha) {
        Throw-WorkflowStateBlocked 'inactive workflow base changed; rerun show before rebind'
    }
    if (($currentCommand -and $currentCommand -notin @('none', '-', ([string][char]0x2014))) -or $currentPhase -or $currentNext) {
        Throw-WorkflowStateBlocked 'rebind requires an inactive workflow with no phase or next step'
    }
    $placeholders = @{
        'Candidate receipt' = '.forge/local/evidence/<task-id>/candidate.receipt'
        'Spec review receipt' = '.forge/local/reviews/<task-id>/spec.receipt'
        'Quality review receipt' = '.forge/local/reviews/<task-id>/quality.receipt'
        'Verify app receipt' = '.forge/local/evidence/<task-id>/verify-app.receipt'
        'E2E receipt' = '.forge/local/evidence/<task-id>/e2e.receipt'
        'Promotion receipt' = '.forge/local/evidence/<task-id>/promotion.receipt'
        'Council receipt' = '.forge/local/council/<council-id>/receipt.json'
    }
    $placeholderMatch = ($currentIteration -in @('0', '<integer>') -and $firstCertified -eq 'none')
    foreach ($key in $placeholders.Keys) {
        if ((Get-WorkflowStateValue -Path $state -Section Receipts -Key $key) -ne $placeholders[$key]) {
            $placeholderMatch = $false
        }
    }
    if (-not $placeholderMatch) { Throw-WorkflowStateBlocked 'rebind refuses workflow or review evidence' }
    if ($goalNonce -and $goalNonce -ne '<uuid-v4-lowercase>') {
        Throw-WorkflowStateBlocked 'rebind refuses an active or malformed Goal session'
    }
    foreach ($line in [IO.File]::ReadAllLines($state)) {
        if ($line -match '^- \[x\] PR creation authorized \u2014 `[0-9]{4}-[0-9]{2}-[0-9]{2}T') {
            Throw-WorkflowStateBlocked 'rebind refuses existing PR authorization'
        }
    }
    $null = & git -C $root cat-file -e "$currentBaseSha`^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { Throw-WorkflowStateBlocked 'inactive workflow base does not resolve to a commit' }
    $resolvedBase = (& git -C $root rev-parse --verify "$baseRef`^{commit}" 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or -not $resolvedBase) { Throw-WorkflowStateBlocked "base ref does not resolve to a commit: $baseRef" }
    $resolvedBase = $resolvedBase.Trim()
    $currentHead = (& git -C $root rev-parse --verify HEAD 2>$null | Select-Object -First 1)
    if (-not $currentHead) { Throw-WorkflowStateBlocked 'cannot resolve worktree HEAD' }
    $currentHead = $currentHead.Trim()
    if ($resolvedBase -ne $currentHead) { Throw-WorkflowStateBlocked 'rebind target must resolve to current worktree HEAD' }
    if ($currentBaseSha -eq $currentHead) { Throw-WorkflowStateBlocked 'inactive workflow base already matches current HEAD' }
    $null = & git -C $root merge-base --is-ancestor $currentBaseSha $currentHead 2>$null
    if ($LASTEXITCODE -ne 0) { Throw-WorkflowStateBlocked 'rebind refuses a non-descendant worktree HEAD' }

    $temporary = Join-Path (Split-Path $state -Parent) ('state.md.tmp.' + [Guid]::NewGuid().ToString('N'))
    try {
        Set-WorkflowStateRebindFile -State $state -Next $temporary -BaseSha $currentHead
        if (-not (Test-WorkflowStateShape -Path $temporary)) { Throw-WorkflowStateBlocked 'rebind produced invalid state' }
        Publish-ForgeWorkflowState -State $state -Next $temporary -ExpectedHash $stateHash
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
    Write-Output "REBOUND: base_ref=$baseRef old=$currentBaseSha new=$currentHead"
}

function Invoke-WorkflowStateActivate {
    param([Parameter(Mandatory = $true)][string[]]$Tokens)
    $values = Convert-WorkflowStateArguments -Tokens $Tokens
    $hostName = $values["--host"]
    $workflow = $values["--workflow"]
    $task = $values["--task"]
    $baseRef = $values["--base-ref"]
    $phase = $values["--phase"]
    $nextStep = $values["--next-step"]
    if ($hostName -cnotin @("claude", "codex")) { Throw-WorkflowStateBlocked "invalid host: $hostName" }
    if ($workflow -cnotin @("new-feature", "fix-bug", "quick-fix")) { Throw-WorkflowStateBlocked "invalid workflow: $workflow" }
    Assert-WorkflowStateTask -Task $task
    Assert-WorkflowStateRef -Ref $baseRef
    Assert-WorkflowStateCell -Label "phase" -Value $phase
    Assert-WorkflowStateCell -Label "next step" -Value $nextStep

    $root = Get-WorkflowStateRoot
    $common = Get-WorkflowStateCommonDirectory -Root $root
    $state = Get-CanonicalWorkflowState -Root $root
    $stateHash = Get-WorkflowStateHash -Path $state
    $command = "/$workflow $task"
    $currentCommand = Get-WorkflowStateValue -Path $state -Section Workflow -Key Command
    $currentPhase = Get-WorkflowStateValue -Path $state -Section Workflow -Key Phase
    $currentNext = Get-WorkflowStateValue -Path $state -Section Workflow -Key "Next step"
    $currentRoot = Get-WorkflowStateValue -Path $state -Section Identity -Key "Worktree root"
    $currentCommon = Get-WorkflowStateValue -Path $state -Section Identity -Key "Git common directory"
    $currentBaseRef = Get-WorkflowStateValue -Path $state -Section Identity -Key "Workflow base ref"
    $currentBaseSha = Get-WorkflowStateValue -Path $state -Section Identity -Key "Workflow base SHA"
    $activeWorkflow = $currentCommand -and $currentCommand -notin @("none", "-", ([string][char]0x2014)) -and -not ($currentPhase -eq "complete" -and $currentNext -eq "none")
    $inactiveWorkflow = -not $currentCommand -or $currentCommand -in @("none", "-", ([string][char]0x2014))
    $boundMode = if ($currentBaseSha -match '^[0-9a-f]{40}([0-9a-f]{24})?$' -and $activeWorkflow) { "active" } elseif ($currentBaseSha -match '^[0-9a-f]{40}([0-9a-f]{24})?$' -and $inactiveWorkflow) { "prebound" } else { "none" }
    if ($boundMode -ne "none") {
        if ($currentRoot -ne $root -or $currentCommon -ne $common -or $currentBaseRef -ne $baseRef) {
            Throw-WorkflowStateBlocked "bound worktree identity differs from requested activation"
        }
        $null = & git -C $root cat-file -e "$currentBaseSha`^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) { Throw-WorkflowStateBlocked "bound worktree identity differs from requested activation" }
        $currentHead = (& git -C $root rev-parse --verify HEAD 2>$null | Select-Object -First 1)
        if (-not $currentHead) { Throw-WorkflowStateBlocked "cannot resolve bound worktree HEAD" }
        $currentHead = $currentHead.Trim()
        if ($boundMode -eq "prebound" -and $currentHead -ne $currentBaseSha) {
            Throw-WorkflowStateBlocked "prebound worktree HEAD differs from its adopted base; inspect with show, then use workflow-state rebind only for the approved descendant base"
        }
        if ($boundMode -eq "active") {
            $null = & git -C $root merge-base --is-ancestor $currentBaseSha $currentHead 2>$null
            if ($LASTEXITCODE -ne 0) { Throw-WorkflowStateBlocked "active workflow base is not an ancestor of HEAD" }
        }
        $baseSha = $currentBaseSha
    } else {
        $baseSha = & git -C $root rev-parse --verify "$baseRef`^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $baseSha) { Throw-WorkflowStateBlocked "base ref does not resolve to a commit: $baseRef" }
        $baseSha = $baseSha.Trim()
    }
    $mode = "new"
    if ($activeWorkflow) {
        $expected = @{
            "Worktree root" = $root
            "Git common directory" = $common
            "Workflow base ref" = $baseRef
            "Workflow base SHA" = $baseSha
        }
        foreach ($key in $expected.Keys) {
            if ((Get-WorkflowStateValue -Path $state -Section Identity -Key $key) -ne $expected[$key]) {
                Throw-WorkflowStateBlocked "a different or inconsistent workflow is already active"
            }
        }
        if ($currentCommand -ne $command -or $currentPhase -ne $phase -or $currentNext -ne $nextStep) {
            Throw-WorkflowStateBlocked "a different or inconsistent workflow is already active"
        }
        $receiptValues = @{
            "Candidate receipt" = ".forge/local/evidence/$task/candidate.receipt"
            "Spec review receipt" = ".forge/local/reviews/$task/spec.receipt"
            "Quality review receipt" = ".forge/local/reviews/$task/quality.receipt"
            "Verify app receipt" = ".forge/local/evidence/$task/verify-app.receipt"
            "E2E receipt" = ".forge/local/evidence/$task/e2e.receipt"
            "Promotion receipt" = ".forge/local/evidence/$task/promotion.receipt"
        }
        $placeholderValues = @{
            "Candidate receipt" = ".forge/local/evidence/<task-id>/candidate.receipt"
            "Spec review receipt" = ".forge/local/reviews/<task-id>/spec.receipt"
            "Quality review receipt" = ".forge/local/reviews/<task-id>/quality.receipt"
            "Verify app receipt" = ".forge/local/evidence/<task-id>/verify-app.receipt"
            "E2E receipt" = ".forge/local/evidence/<task-id>/e2e.receipt"
            "Promotion receipt" = ".forge/local/evidence/<task-id>/promotion.receipt"
        }
        $iteration = Get-WorkflowStateValue -Path $state -Section Receipts -Key "Review iteration"
        $receiptsMatch = $true
        $placeholdersMatch = $true
        foreach ($key in $receiptValues.Keys) {
            $actual = Get-WorkflowStateValue -Path $state -Section Receipts -Key $key
            if ($actual -ne $receiptValues[$key]) { $receiptsMatch = $false }
            if ($actual -ne $placeholderValues[$key]) { $placeholdersMatch = $false }
        }
        if ($iteration -match '^[0-9]+$' -and $receiptsMatch) {
            $mode = "resume"
        }
        elseif ($iteration -eq '<integer>' -and $placeholdersMatch) {
            $mode = "adopt"
        }
        else {
            Throw-WorkflowStateBlocked "a different or inconsistent workflow is already active"
        }
    }

    if ($workflow -ceq "quick-fix" -and $mode -ceq "new") {
        # Finish native Git before First can stop it and leave a stale exit code.
        $quickFixHead = (@(& git -C $root rev-parse --verify HEAD 2>$null) | Select-Object -First 1)
        $quickFixBranch = (@(& git -C $root symbolic-ref -q --short HEAD 2>$null) | Select-Object -First 1)
        if ($LASTEXITCODE -ne 0 -or -not $quickFixBranch -or $quickFixBranch.Trim() -cne "quick-fix/$task") {
            Throw-WorkflowStateBlocked "new quick-fix activation requires branch quick-fix/$task"
        }
        $quickFixBaseRef = (@(& git -C $root rev-parse --symbolic-full-name $baseRef 2>$null) | Select-Object -First 1)
        if ($LASTEXITCODE -ne 0 -or -not $quickFixBaseRef -or
            $quickFixBaseRef.Trim() -cnotmatch '^refs/(heads|remotes)/' -or
            $quickFixBaseRef.Trim() -ceq "refs/heads/$($quickFixBranch.Trim())") {
            Throw-WorkflowStateBlocked "new quick-fix activation requires a distinct named base branch"
        }
        if (-not $quickFixHead -or $quickFixHead.Trim() -cne $baseSha) {
            Throw-WorkflowStateBlocked "new quick-fix activation requires HEAD to equal the resolved base"
        }
        $quickFixStatus = @(& git -C $root status --porcelain --untracked-files=all 2>$null)
        if ($LASTEXITCODE -ne 0 -or $quickFixStatus.Count -gt 0) {
            Throw-WorkflowStateBlocked "new quick-fix activation requires a clean worktree"
        }
    }

    $evidenceDir = Join-Path $root ".forge\local\evidence\$task"
    $reviewDir = Join-Path $root ".forge\local\reviews\$task"
    foreach ($candidate in @((Split-Path $evidenceDir -Parent), $evidenceDir, (Split-Path $reviewDir -Parent), $reviewDir)) {
        if (Test-Path -LiteralPath $candidate) {
            if ((Get-Item -LiteralPath $candidate -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                Throw-WorkflowStateBlocked "reparse-point workflow-state directory: $candidate"
            }
        }
    }
    $temporary = Join-Path (Split-Path $state -Parent) ("state.md.tmp." + [Guid]::NewGuid().ToString("N"))
    try {
        $activation = @{
            State = $state
            Next = $temporary
            Mode = $mode
            Root = $root
            Common = $common
            HostName = $hostName
            BaseRef = $baseRef
            BaseSha = $baseSha
            Command = $command
            Phase = $phase
            NextStep = $nextStep
            Task = $task
        }
        Set-WorkflowStateActivationFile @activation
        if (-not (Test-WorkflowStateShape -Path $temporary)) { Throw-WorkflowStateBlocked "activation produced invalid state" }
        [void](New-Item -ItemType Directory -Path $evidenceDir -Force)
        [void](New-Item -ItemType Directory -Path $reviewDir -Force)
        Publish-ForgeWorkflowState -State $state -Next $temporary -ExpectedHash $stateHash
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Convert-WorkflowStateCheckpointArguments {
    param([Parameter(Mandatory = $true)][string[]]$Tokens)
    $values = @{}
    $beginReview = $false
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $name = $Tokens[$i]
        if ($name -eq "--begin-review") {
            if ($beginReview) { Throw-WorkflowStateBlocked "duplicate checkpoint option: $name" }
            $beginReview = $true
            continue
        }
        if ($name -notin @("--host", "--phase", "--next-step")) {
            Throw-WorkflowStateBlocked "unsupported checkpoint option: $name"
        }
        if ($values.ContainsKey($name)) { Throw-WorkflowStateBlocked "duplicate checkpoint option: $name" }
        if ($i + 1 -ge $Tokens.Count) { Throw-WorkflowStateBlocked "option requires a value: $name" }
        $i++
        $values[$name] = $Tokens[$i]
    }
    foreach ($name in @("--host", "--phase", "--next-step")) {
        if (-not $values.ContainsKey($name)) {
            Throw-WorkflowStateBlocked "checkpoint requires host, phase, and next-step"
        }
    }
    $values["--begin-review"] = $beginReview
    return $values
}

function Invoke-WorkflowStateCheckpoint {
    param([Parameter(Mandatory = $true)][string[]]$Tokens)
    $values = Convert-WorkflowStateCheckpointArguments -Tokens $Tokens
    $hostName = $values["--host"]
    $phase = $values["--phase"]
    $nextStep = $values["--next-step"]
    if ($hostName -notin @("claude", "codex")) { Throw-WorkflowStateBlocked "invalid host: $hostName" }
    Assert-WorkflowStateCell -Label "phase" -Value $phase
    Assert-WorkflowStateCell -Label "next step" -Value $nextStep

    $root = Get-WorkflowStateRoot
    $common = Get-WorkflowStateCommonDirectory -Root $root
    $state = Get-CanonicalWorkflowState -Root $root
    $stateHash = Get-WorkflowStateHash -Path $state
    $command = Get-WorkflowStateValue -Path $state -Section Workflow -Key Command
    $recordedRoot = Get-WorkflowStateValue -Path $state -Section Identity -Key "Worktree root"
    $recordedCommon = Get-WorkflowStateValue -Path $state -Section Identity -Key "Git common directory"
    $iteration = Get-WorkflowStateValue -Path $state -Section Receipts -Key "Review iteration"
    $firstCertified = Get-OptionalFirstCertifiedIteration -State $state
    if ($command -cnotmatch '^/(new-feature|fix-bug|quick-fix) [a-z0-9]+(-[a-z0-9]+)*$' -or
        $recordedRoot -ne $root -or $recordedCommon -ne $common) {
        Throw-WorkflowStateBlocked "checkpoint requires an active workflow in this worktree"
    }
    if ($iteration -notmatch '^(0|[1-9][0-9]*)$') {
        Throw-WorkflowStateBlocked "review iteration must be a non-negative integer"
    }
    if ($firstCertified -ne 'none' -and $firstCertified -notmatch '^[1-9][0-9]*$') {
        Throw-WorkflowStateBlocked "first certified iteration must be none or a positive integer"
    }
    if ($firstCertified -eq 'none' -and $iteration -ne '0' -and (Test-WorkflowStateReviewsValid -State $state)) {
        $firstCertified = $iteration
    }
    $nextIteration = $iteration
    if ([bool]$values["--begin-review"]) {
        $nextIteration = Get-NextWorkflowReviewIteration -Value $iteration
    }

    $temporary = Join-Path (Split-Path $state -Parent) ("state.md.tmp." + [Guid]::NewGuid().ToString("N"))
    try {
        $checkpoint = @{
            State = $state
            Next = $temporary
            HostName = $hostName
            Phase = $phase
            NextStep = $nextStep
            Iteration = $nextIteration
            FirstCertified = $firstCertified
        }
        Set-WorkflowStateCheckpointFile @checkpoint
        if (-not (Test-WorkflowStateShape -Path $temporary)) { Throw-WorkflowStateBlocked "checkpoint produced invalid state" }
        Publish-ForgeWorkflowState -State $state -Next $temporary -ExpectedHash $stateHash
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Invoke-ForgeWorkflowState {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    if ($Arguments.Count -eq 0) { Throw-WorkflowStateBlocked "usage: workflow-state show|rebind|activate|checkpoint" }
    $action = $Arguments[0]
    $remaining = if ($Arguments.Count -gt 1) { @($Arguments[1..($Arguments.Count - 1)]) } else { @() }
    switch ($action) {
        "show" {
            if ($remaining.Count -ne 0) { Throw-WorkflowStateBlocked "show accepts no arguments" }
            Invoke-WorkflowStateShow
        }
        "rebind" { Invoke-WorkflowStateRebind -Tokens $remaining }
        "activate" { Invoke-WorkflowStateActivate -Tokens $remaining }
        "checkpoint" { Invoke-WorkflowStateCheckpoint -Tokens $remaining }
        default { Throw-WorkflowStateBlocked "usage: workflow-state show|rebind|activate|checkpoint" }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-ForgeWorkflowState -Arguments @($args)
        exit 0
    }
    catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 2
    }
}
