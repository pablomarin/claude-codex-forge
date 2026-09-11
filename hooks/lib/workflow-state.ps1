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
    if ($Task.Length -gt 64 -or $Task -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
        Throw-WorkflowStateBlocked "invalid task slug: $Task"
    }
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
    [IO.File]::Replace($Next, $State, $null)
}

function Set-WorkflowStateActivationFile {
    param(
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][string]$Next,
        [Parameter(Mandatory = $true)][ValidateSet("new", "resume")][string]$Mode,
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
    $output = New-Object Collections.Generic.List[string]
    foreach ($line in [IO.File]::ReadAllLines($State)) {
        $current = $line
        if ($line -match '^## (.+)$') { $section = $Matches[1] }
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
            elseif ($Mode -eq "new" -and $section -eq "Workflow") {
                if ($key -eq "Command") { $current = "| Command   | $Command |" }
                elseif ($key -eq "Phase") { $current = "| Phase     | $Phase |" }
                elseif ($key -eq "Next step") { $current = "| Next step | $NextStep |" }
            }
            elseif ($Mode -eq "new" -and $section -eq "Receipts") {
                if ($key -eq "Review iteration") { $current = "| Review iteration       | 0 |" }
                elseif ($key -eq "Candidate receipt") { $current = "| Candidate receipt      | .forge/local/evidence/$Task/candidate.receipt |" }
                elseif ($key -eq "Spec review receipt") { $current = "| Spec review receipt    | .forge/local/reviews/$Task/spec.receipt |" }
                elseif ($key -eq "Quality review receipt") { $current = "| Quality review receipt | .forge/local/reviews/$Task/quality.receipt |" }
                elseif ($key -eq "Verify app receipt") { $current = "| Verify app receipt     | .forge/local/evidence/$Task/verify-app.receipt |" }
                elseif ($key -eq "E2E receipt") { $current = "| E2E receipt            | .forge/local/evidence/$Task/e2e.receipt |" }
                elseif ($key -eq "Promotion receipt") { $current = "| Promotion receipt      | .forge/local/evidence/$Task/promotion.receipt |" }
            }
        }
        $output.Add($current)
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllLines($Next, $output.ToArray(), $utf8)
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
    [Console]::Out.Write([IO.File]::ReadAllText($state))
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
    if ($hostName -notin @("claude", "codex")) { Throw-WorkflowStateBlocked "invalid host: $hostName" }
    if ($workflow -notin @("new-feature", "fix-bug", "quick-fix")) { Throw-WorkflowStateBlocked "invalid workflow: $workflow" }
    Assert-WorkflowStateTask -Task $task
    Assert-WorkflowStateRef -Ref $baseRef
    Assert-WorkflowStateCell -Label "phase" -Value $phase
    Assert-WorkflowStateCell -Label "next step" -Value $nextStep

    $root = Get-WorkflowStateRoot
    $common = Get-WorkflowStateCommonDirectory -Root $root
    $state = Get-CanonicalWorkflowState -Root $root
    $baseSha = & git -C $root rev-parse --verify "$baseRef`^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $baseSha) { Throw-WorkflowStateBlocked "base ref does not resolve to a commit: $baseRef" }
    $baseSha = $baseSha.Trim()
    $stateHash = Get-WorkflowStateHash -Path $state
    $command = "/$workflow $task"
    $currentCommand = Get-WorkflowStateValue -Path $state -Section Workflow -Key Command
    $currentPhase = Get-WorkflowStateValue -Path $state -Section Workflow -Key Phase
    $currentNext = Get-WorkflowStateValue -Path $state -Section Workflow -Key "Next step"
    $mode = "new"
    if ($currentCommand -and $currentCommand -ne "none" -and -not ($currentPhase -eq "complete" -and $currentNext -eq "none")) {
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
        $iteration = Get-WorkflowStateValue -Path $state -Section Receipts -Key "Review iteration"
        if ($iteration -notmatch '^[0-9]+$') { Throw-WorkflowStateBlocked "a different or inconsistent workflow is already active" }
        $receiptValues = @{
            "Candidate receipt" = ".forge/local/evidence/$task/candidate.receipt"
            "Spec review receipt" = ".forge/local/reviews/$task/spec.receipt"
            "Quality review receipt" = ".forge/local/reviews/$task/quality.receipt"
            "Verify app receipt" = ".forge/local/evidence/$task/verify-app.receipt"
            "E2E receipt" = ".forge/local/evidence/$task/e2e.receipt"
            "Promotion receipt" = ".forge/local/evidence/$task/promotion.receipt"
        }
        foreach ($key in $receiptValues.Keys) {
            if ((Get-WorkflowStateValue -Path $state -Section Receipts -Key $key) -ne $receiptValues[$key]) {
                Throw-WorkflowStateBlocked "a different or inconsistent workflow is already active"
            }
        }
        $mode = "resume"
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

function Invoke-ForgeWorkflowState {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    if ($Arguments.Count -eq 0) { Throw-WorkflowStateBlocked "usage: workflow-state show|activate|checkpoint" }
    $action = $Arguments[0]
    $remaining = if ($Arguments.Count -gt 1) { @($Arguments[1..($Arguments.Count - 1)]) } else { @() }
    switch ($action) {
        "show" {
            if ($remaining.Count -ne 0) { Throw-WorkflowStateBlocked "show accepts no arguments" }
            Invoke-WorkflowStateShow
        }
        "activate" { Invoke-WorkflowStateActivate -Tokens $remaining }
        "checkpoint" { Throw-WorkflowStateBlocked "checkpoint is not implemented" }
        default { Throw-WorkflowStateBlocked "usage: workflow-state show|activate|checkpoint" }
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
