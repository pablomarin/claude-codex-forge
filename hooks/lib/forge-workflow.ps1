# hooks/lib/forge-workflow.ps1 — Forge runtime workflow controller (PowerShell mirror).
# v1 enforces the Phase 3 -> Phase 4 implementation handoff seam.

$StateFile = ".claude/local/workflow-run.json"
$EventsFile = ".claude/local/workflow-events.jsonl"
$GatePhase34 = "phase-3-4"
$AllowedModes = @("same-context", "compact", "fresh-session")

function Get-NowUtc {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Set-RepoRootFromCwd([string]$Cwd) {
    if ($Cwd -and (Test-Path $Cwd)) {
        try { Set-Location $Cwd } catch {}
    }
    try {
        $top = (& git rev-parse --show-toplevel 2>$null)
        if ($top -and (Test-Path $top)) { Set-Location $top }
    } catch {}
}

function Read-StdInAll {
    try {
        if (-not [Console]::IsInputRedirected) { return "" }
    } catch {}
    return [Console]::In.ReadToEnd()
}

function ConvertFrom-JsonSafe([string]$Json) {
    if (-not $Json) { return $null }
    try { return ($Json | ConvertFrom-Json) } catch { return $null }
}

function Get-WorkflowCommand {
    $stateMd = ".claude/local/state.md"
    if (-not (Test-Path $stateMd)) { return "unknown" }
    $lines = (Get-Content $stateMd -Raw -ErrorAction SilentlyContinue) -replace "`r", "" -split "`n"
    $inWorkflow = $false
    foreach ($line in $lines) {
        if ($line -eq "## Workflow") { $inWorkflow = $true; continue }
        if ($inWorkflow -and $line -match '^## ') { $inWorkflow = $false }
        if ($inWorkflow -and $line -match '\|\s*Command\s*\|') {
            $parts = $line -split '\|'
            if ($parts.Length -ge 4) { return $parts[2].Trim() }
        }
    }
    return "unknown"
}

function Get-RunState {
    if (-not (Test-Path $StateFile)) { return $null }
    return ConvertFrom-JsonSafe (Get-Content $StateFile -Raw -ErrorAction SilentlyContinue)
}

function Get-GateStatus([string]$Gate) {
    $state = Get-RunState
    if (-not $state -or -not $state.gates) { return "" }
    $gateObj = $state.gates.$Gate
    if ($gateObj -and $gateObj.status) { return [string]$gateObj.status }
    return ""
}

function Get-StatePlanFile {
    $state = Get-RunState
    if ($state -and $state.plan_file) { return [string]$state.plan_file }
    return ""
}

function Add-WorkflowEvent([string]$Event, [string]$Gate, [string]$Plan, [string]$Mode = "") {
    if (-not (Test-Path ".claude/local")) { New-Item -ItemType Directory -Path ".claude/local" -Force | Out-Null }
    $obj = [ordered]@{
        ts = Get-NowUtc
        event = $Event
        gate = $Gate
        plan_file = $Plan
    }
    if ($Mode) { $obj.mode = $Mode }
    ($obj | ConvertTo-Json -Compress) + "`n" | Add-Content -Path $EventsFile -NoNewline
}

function Write-RunState([string]$Workflow, [string]$Phase, [string]$NextStep, [string]$Plan, [string]$Gate, [string]$Status, [string]$OpenedAt, [string]$SelectedMode, [string]$SelectedAt, [string]$ApprovedAt) {
    if (-not (Test-Path ".claude/local")) { New-Item -ItemType Directory -Path ".claude/local" -Force | Out-Null }
    $gateObj = [ordered]@{
        status = $Status
        opened_at = $OpenedAt
        reason = "Implementation Handoff complete; choose same-context, compact, or fresh-session before implementation."
        allowed_modes = $AllowedModes
        selected_mode = $(if ($SelectedMode) { $SelectedMode } else { $null })
        selected_at = $(if ($SelectedAt) { $SelectedAt } else { $null })
        approved_at = $(if ($ApprovedAt) { $ApprovedAt } else { $null })
    }
    $gates = [ordered]@{}
    $gates[$Gate] = $gateObj
    $obj = [ordered]@{
        version = 1
        workflow = $Workflow
        phase = $Phase
        next_step = $NextStep
        plan_file = $Plan
        gates = $gates
    }
    $obj | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $StateFile -NoNewline
}

function Open-Gate([string[]]$ArgsList) {
    $Gate = if ($ArgsList.Count -gt 0) { $ArgsList[0] } else { "" }
    $Plan = ""
    for ($i = 1; $i -lt $ArgsList.Count; $i++) {
        if ($ArgsList[$i] -eq "--plan" -and ($i + 1) -lt $ArgsList.Count) { $Plan = $ArgsList[$i + 1]; $i++; continue }
        Write-Error "forge-workflow: unknown open-gate argument: $($ArgsList[$i])"
        exit 2
    }
    if ($Gate -ne $GatePhase34) { Write-Error "forge-workflow: unsupported gate: $Gate"; exit 2 }
    if (-not $Plan) { Write-Error "forge-workflow: open-gate requires --plan <path>"; exit 2 }

    $status = Get-GateStatus $Gate
    $existingPlan = Get-StatePlanFile
    if ($status -eq "pending" -and $existingPlan -eq $Plan) {
        Write-Output "Gate already pending: $Gate ($Plan)"
        return
    }
    if (($status -eq "awaiting-compact" -or $status -eq "awaiting-fresh-session") -and $existingPlan -eq $Plan) {
        Write-Output "Gate already awaiting approval: $Gate ($status, $Plan)"
        return
    }
    if ($status -eq "approved" -and $existingPlan -eq $Plan) {
        Write-Output "Gate already approved: $Gate ($Plan)"
        return
    }

    $opened = Get-NowUtc
    Write-RunState (Get-WorkflowCommand) "3 — Design" "Implementation Handoff" $Plan $Gate "pending" $opened "" "" ""
    Add-WorkflowEvent "gate_opened" $Gate $Plan
    Write-Output "Gate opened: $Gate ($Plan)"
}

function Select-Gate([string[]]$ArgsList) {
    $Gate = if ($ArgsList.Count -gt 0) { $ArgsList[0] } else { "" }
    $Mode = ""
    for ($i = 1; $i -lt $ArgsList.Count; $i++) {
        if ($ArgsList[$i] -eq "--mode" -and ($i + 1) -lt $ArgsList.Count) { $Mode = $ArgsList[$i + 1]; $i++; continue }
        Write-Error "forge-workflow: unknown select-gate argument: $($ArgsList[$i])"
        exit 2
    }
    if ($Gate -ne $GatePhase34) { Write-Error "forge-workflow: unsupported gate: $Gate"; exit 2 }
    if ($AllowedModes -notcontains $Mode) { Write-Error "forge-workflow: invalid mode '$Mode' (expected: same-context|compact|fresh-session)"; exit 2 }

    $state = Get-RunState
    if (-not $state) { Write-Error "forge-workflow: no workflow run state to select"; exit 2 }
    $gateObj = $state.gates.$Gate
    $status = if ($gateObj) { [string]$gateObj.status } else { "" }
    $selected = if ($gateObj -and $gateObj.selected_mode) { [string]$gateObj.selected_mode } else { "" }
    if ($status -eq "approved") {
        Write-Output "Gate already approved: $Gate ($(if ($selected) { $selected } else { 'unknown' }))"
        return
    }
    if ($status -eq "awaiting-compact" -or $status -eq "awaiting-fresh-session") {
        if ($selected -ne $Mode) {
            Write-Error "forge-workflow: gate '$Gate' already selected mode '$(if ($selected) { $selected } else { 'missing' })' and cannot be re-selected as '$Mode'"
            exit 2
        }
    } elseif ($status -ne "pending") {
        Write-Error "forge-workflow: gate '$Gate' is not selectable (status: $(if ($status) { $status } else { 'missing' }))"
        exit 2
    }

    if ($Mode -eq "same-context") {
        $newStatus = "approved"
        $phase = "4 — Execute"
        $nextStep = "Implementation may start"
    } elseif ($Mode -eq "compact") {
        $newStatus = "awaiting-compact"
        $phase = "3 — Design"
        $nextStep = "Awaiting compact approval"
    } else {
        $newStatus = "awaiting-fresh-session"
        $phase = "3 — Design"
        $nextStep = "Awaiting fresh-session approval"
    }

    if ($status -eq $newStatus -and $selected -eq $Mode) {
        Write-Output "Gate already selected: $Gate ($Mode)"
        return
    }

    $opened = if ($gateObj.opened_at) { [string]$gateObj.opened_at } else { Get-NowUtc }
    $workflow = if ($state.workflow) { [string]$state.workflow } else { Get-WorkflowCommand }
    $plan = if ($state.plan_file) { [string]$state.plan_file } else { "" }
    $now = Get-NowUtc
    if ($Mode -eq "same-context") {
        Write-RunState $workflow $phase $nextStep $plan $Gate $newStatus $opened $Mode $now $now
        Add-WorkflowEvent "gate_selected" $Gate $plan $Mode
        Add-WorkflowEvent "gate_approved" $Gate $plan $Mode
        Write-Output "Gate selected and approved: $Gate ($Mode)"
    } else {
        Write-RunState $workflow $phase $nextStep $plan $Gate $newStatus $opened $Mode $now ""
        Add-WorkflowEvent "gate_selected" $Gate $plan $Mode
        Write-Output "Gate selected: $Gate ($Mode); status=$newStatus"
    }
}

function Approve-Gate([string[]]$ArgsList) {
    $Gate = if ($ArgsList.Count -gt 0) { $ArgsList[0] } else { "" }
    $Mode = ""
    for ($i = 1; $i -lt $ArgsList.Count; $i++) {
        if ($ArgsList[$i] -eq "--mode" -and ($i + 1) -lt $ArgsList.Count) { $Mode = $ArgsList[$i + 1]; $i++; continue }
        Write-Error "forge-workflow: unknown approve-gate argument: $($ArgsList[$i])"
        exit 2
    }
    if ($Gate -ne $GatePhase34) { Write-Error "forge-workflow: unsupported gate: $Gate"; exit 2 }
    if ($AllowedModes -notcontains $Mode) { Write-Error "forge-workflow: invalid mode '$Mode' (expected: same-context|compact|fresh-session)"; exit 2 }

    $state = Get-RunState
    if (-not $state) { Write-Error "forge-workflow: no workflow run state to approve"; exit 2 }
    $gateObj = $state.gates.$Gate
    $status = if ($gateObj) { [string]$gateObj.status } else { "" }
    if ($status -eq "approved" -and $gateObj.selected_mode -eq $Mode) {
        Write-Output "Gate already approved: $Gate ($Mode)"
        return
    }
    if ($status -eq "awaiting-compact" -or $status -eq "awaiting-fresh-session") {
        if ($gateObj.selected_mode -ne $Mode) {
            Write-Error "forge-workflow: selected mode mismatch for gate '$Gate' (selected: $(if ($gateObj.selected_mode) { $gateObj.selected_mode } else { 'missing' }), requested: $Mode)"
            exit 2
        }
    } elseif ($status -ne "pending") {
        Write-Error "forge-workflow: gate '$Gate' is not awaiting approval (status: $(if ($status) { $status } else { 'missing' }))"
        exit 2
    }

    $opened = if ($gateObj.opened_at) { [string]$gateObj.opened_at } else { Get-NowUtc }
    $workflow = if ($state.workflow) { [string]$state.workflow } else { Get-WorkflowCommand }
    $plan = if ($state.plan_file) { [string]$state.plan_file } else { "" }
    $selectedAt = if ($gateObj.selected_at) { [string]$gateObj.selected_at } else { "" }
    $approvedAt = Get-NowUtc
    if (-not $selectedAt) { $selectedAt = $approvedAt }
    Write-RunState $workflow "4 — Execute" "Implementation may start" $plan $Gate "approved" $opened $Mode $selectedAt $approvedAt
    Add-WorkflowEvent "gate_approved" $Gate $plan $Mode
    Write-Output "Gate approved: $Gate ($Mode)"
}

function Show-Status {
    if (Test-Path $StateFile) { Get-Content $StateFile -Raw } else { Write-Output "NO_WORKFLOW_RUN" }
}

function Test-LocalStatePath([string]$PathValue) {
    if (-not $PathValue) { return $false }
    $root = (Get-Location).Path
    $norm = $PathValue -replace '/', '\'
    $rootNorm = $root -replace '/', '\'
    return ($norm -like ".claude\local\*" -or $norm -like ".\.claude\local\*" -or $norm -like "$rootNorm\.claude\local\*")
}

function Test-AllowedBashWhilePending([string]$Command) {
    if (-not $Command) { return $false }
    if ($Command -match '^\s*(\./)?\.claude/hooks/lib/forge-workflow\.(sh|ps1)\s+(status|approve-gate|select-gate|open-gate)\b') { return $true }
    # Single-command only: do not let `git status && pytest` or redirects ride
    # through the gate because the first token is read-only.
    if ($Command -match '[;&|<>]') { return $false }
    if ($Command -match '^find\s+.*-(delete|exec|ok)\b') { return $false }
    if ($Command -match '^(pwd|ls|find\s|rg\s|grep\s|wc\s|head\s|tail\s|cat\s|date\b|uuidgen\b|shasum\s|sha256sum\s)') { return $true }
    if ($Command -match '^git\s+(status\b|diff\b|show\s|log\b|rev-parse\s|branch\b)') { return $true }
    if ($Command -match '^(command\s+-v\s|test\s|sed\s+-n\s)') { return $true }
    return $false
}

function Write-BlockMessage([string]$Gate) {
    $state = Get-RunState
    $gateObj = if ($state -and $state.gates) { $state.gates.$Gate } else { $null }
    $status = if ($gateObj -and $gateObj.status) { [string]$gateObj.status } else { "unknown" }
    $selected = if ($gateObj -and $gateObj.selected_mode) { [string]$gateObj.selected_mode } else { "none" }
    [Console]::Error.WriteLine("PHASE_GATE_PENDING: $Gate")
    [Console]::Error.WriteLine("Implementation Handoff is complete. Current gate status: $status; selected mode: $selected.")
    [Console]::Error.WriteLine("Choose how to cross the Phase 3→4 seam:")
    [Console]::Error.WriteLine("- same-context: select and continue in this session")
    [Console]::Error.WriteLine("- compact: select compact, run /compact, then approve after resume")
    [Console]::Error.WriteLine("- fresh-session: select fresh-session, start a new session in the worktree, then approve there")
    [Console]::Error.WriteLine("Allowed commands:")
    [Console]::Error.WriteLine("  .claude/hooks/lib/forge-workflow.sh select-gate $Gate --mode same-context|compact|fresh-session")
    [Console]::Error.WriteLine("  .claude/hooks/lib/forge-workflow.sh approve-gate $Gate --mode <selected-mode>")
}

function Check-Tool {
    $inputJson = Read-StdInAll
    $data = ConvertFrom-JsonSafe $inputJson
    if ($data -and $data.cwd) { Set-RepoRootFromCwd ([string]$data.cwd) } else { Set-RepoRootFromCwd "" }

    $status = Get-GateStatus $GatePhase34
    if (-not $status -or $status -eq "approved") { exit 0 }

    $tool = if ($data -and $data.tool_name) { [string]$data.tool_name } else { "" }
    $command = if ($data -and $data.tool_input -and $data.tool_input.command) { [string]$data.tool_input.command } else { "" }
    $filePath = if ($data -and $data.tool_input -and $data.tool_input.file_path) { [string]$data.tool_input.file_path } else { "" }
    if (-not $tool -and $command) { $tool = "Bash" }

    if ($tool -eq "Bash") {
        if (Test-AllowedBashWhilePending $command) { exit 0 }
        Write-BlockMessage $GatePhase34
        exit 2
    }
    if ($tool -eq "Edit" -or $tool -eq "Write" -or $tool -eq "MultiEdit" -or $tool -eq "NotebookEdit") {
        if (Test-LocalStatePath $filePath) { exit 0 }
        Write-BlockMessage $GatePhase34
        exit 2
    }
    exit 0
}

function Show-Usage {
    Write-Output "Usage: forge-workflow <status|open-gate|select-gate|approve-gate|check-tool>"
}

$cmd = if ($args.Count -gt 0) { $args[0] } else { "" }
$rest = @()
if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }

switch ($cmd) {
    "status" { Show-Status }
    "open-gate" { Open-Gate $rest }
    "select-gate" { Select-Gate $rest }
    "approve-gate" { Approve-Gate $rest }
    "check-tool" { Check-Tool }
    "help" { Show-Usage }
    "--help" { Show-Usage }
    "" { Show-Usage }
    default { Write-Error "forge-workflow: unknown command: $cmd"; Show-Usage; exit 2 }
}
