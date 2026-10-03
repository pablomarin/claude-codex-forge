param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [Parameter(Mandatory=$true)][string]$Target,
    [Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$ReleaseVersion,
    [ValidateSet("project")][string]$Scope = "project",
    [ValidateSet("windows")][string]$Platform = "windows"
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Begin = "<!-- forge:begin v6 -->"
$End = "<!-- forge:end v6 -->"
$Manifest = Join-Path $RepoRoot "manifests\managed-v6.tsv"
$Installed = @()

function Test-SafeRelativePath {
    param([string]$Path)
    if (-not $Path -or [IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)' -or $Path -match '[*?]') { return $false }
    return $true
}

function Read-ManagedManifest {
    param([string]$Path)
    $rows = @()
    $line = 0
    foreach ($raw in [IO.File]::ReadAllLines($Path)) {
        $line++
        if (-not $raw.Trim() -or $raw.StartsWith("#")) { continue }
        $fields = $raw.Split("`t")
        if ($fields.Count -ne 9) { throw "manifest row $line must have nine fields" }
        if (-not (Test-SafeRelativePath $fields[2])) { throw "unsafe manifest destination on row $line" }
        if (@("canonical", "adapter", "merge", "marker", "protected", "tombstone") -notcontains $fields[0]) { throw "invalid manifest kind on row $line" }
        if (@("all", "windows", "unix") -notcontains $fields[3]) { throw "invalid manifest platform on row $line" }
        if ($fields[5] -ne "project") { throw "active managed manifest contains non-project scope on row $line" }
        $rows += [pscustomobject]@{
            Kind=$fields[0]; Source=$fields[1]; Destination=$fields[2]; Platform=$fields[3]
            Host=$fields[4]; Scope=$fields[5]; Ownership=$fields[6]
            CanonicalPath=$fields[7]; Revision=$fields[8]
        }
    }
    return $rows
}

function Get-PrimaryCheckout {
    param([string]$Project)
    if (-not (Test-Path -LiteralPath (Join-Path $Project ".git"))) { return "" }
    $lines = @(& git -C $Project worktree list --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) { return "" }
    foreach ($line in $lines) {
        if ($line.StartsWith("worktree ")) { return $line.Substring(9) }
    }
    return ""
}

function Get-MaterializerStateValue {
    param([string]$Path, [string]$Section, [string]$Key)
    $currentSection = ""
    $values = @()
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line.StartsWith("## ")) {
            $currentSection = $line.Substring(3)
            continue
        }
        if ($currentSection -cne $Section -or -not $line.StartsWith("|", [StringComparison]::Ordinal)) { continue }
        $cells = $line.Split('|')
        if ($cells.Count -ge 4 -and $cells[1].Trim() -ceq $Key) {
            $values += $cells[2].Trim()
        }
    }
    if ($values.Count -ne 1) { throw "canonical state field is missing or duplicated: $Section/$Key" }
    return $values[0]
}

function Write-NormalProjectWorkflowStatus {
    param([string]$Project)
    $state = Join-Path $Project ".forge\local\state.md"
    if (-not (Test-Path -LiteralPath $state)) {
        Write-Host "NORMAL_PROJECT_WORKFLOWS: READY"
        return
    }
    $stateItem = Get-Item -LiteralPath $state -Force
    if ($stateItem.PSIsContainer -or ($stateItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Write-Host "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=canonical-state-not-regular action=workflow-state-show"
        return
    }
    try {
        $command = Get-MaterializerStateValue $state Workflow Command
        $phase = Get-MaterializerStateValue $state Workflow Phase
        $nextStep = Get-MaterializerStateValue $state Workflow "Next step"
        $stateRoot = Get-MaterializerStateValue $state Identity "Worktree root"
        $stateCommon = Get-MaterializerStateValue $state Identity "Git common directory"
        $baseRef = Get-MaterializerStateValue $state Identity "Workflow base ref"
        $baseSha = Get-MaterializerStateValue $state Identity "Workflow base SHA"
    } catch {
        Write-Host "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=canonical-state-unreadable action=workflow-state-show"
        return
    }
    if ($command -and $command -notin @("none", "-", ([string][char]0x2014))) {
        Write-Host "NORMAL_PROJECT_WORKFLOWS: READY"
        return
    }
    if ($baseSha -notmatch '^[0-9a-f]{40}([0-9a-f]{24})?$') {
        Write-Host "NORMAL_PROJECT_WORKFLOWS: READY"
        return
    }
    if ($phase -or $nextStep) {
        Write-Host "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=inactive-prebound-state-invalid action=workflow-state-show"
        return
    }
    $common = (& git -C $Project rev-parse --git-common-dir 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or -not $common) {
        Write-Host "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=inactive-prebound-git-unavailable action=workflow-state-show"
        return
    }
    $common = $common.Trim()
    if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $Project $common }
    try { $common = (Resolve-Path -LiteralPath $common).Path } catch { $common = "" }
    if (-not [string]::Equals($stateRoot, $Project, [StringComparison]::OrdinalIgnoreCase) -or
        -not $common -or
        -not [string]::Equals($stateCommon, $common, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=inactive-prebound-identity-mismatch action=workflow-state-show"
        return
    }
    $currentHead = (& git -C $Project rev-parse --verify HEAD 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or -not $currentHead) {
        Write-Host "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=inactive-prebound-head-unavailable action=workflow-state-show"
        return
    }
    $currentHead = $currentHead.Trim()
    if ($currentHead -eq $baseSha) {
        Write-Host "NORMAL_PROJECT_WORKFLOWS: READY"
        return
    }
    $action = "workflow-state-show"
    $resolvedRef = (& git -C $Project rev-parse --verify "$baseRef`^{commit}" 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -eq 0 -and $resolvedRef -and $resolvedRef.Trim() -eq $currentHead) {
        $null = & git -C $Project merge-base --is-ancestor $baseSha $currentHead 2>$null
        if ($LASTEXITCODE -eq 0) { $action = "workflow-state-rebind" }
    }
    Write-Host "NORMAL_PROJECT_WORKFLOWS: BLOCKED reason=inactive-prebound-head-mismatch action=$action base_ref=$baseRef base_sha=$baseSha head=$currentHead"
}

function Test-HasByteOrderMark {
    param([byte[]]$Bytes)
    return ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) -or
        ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) -or
        ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) -or
        ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0x00 -and $Bytes[1] -eq 0x00 -and $Bytes[2] -eq 0xFE -and $Bytes[3] -eq 0xFF)
}

function Get-LegacyStateSkeleton {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if (Test-HasByteOrderMark $bytes) { return $null }
    $output = New-Object Collections.Generic.List[string]
    $narrative = $false
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if (@('## State', '## Open Questions', '## Blockers') -ccontains $line) {
            $output.Add($line)
            $output.Add('<forge-preserved-narrative>')
            $narrative = $true
            continue
        }
        if ($line.StartsWith('## ', [StringComparison]::Ordinal)) { $narrative = $false }
        if ($narrative) { continue }
        if ($line -cmatch '^<!-- forge:migrated \d{4}-\d{2}-\d{2} -->$') {
            $output.Add('<!-- forge:migrated <date> -->')
        } elseif ($line -cmatch '^\|\s*Command\s*\|') {
            $output.Add('| Command | <inactive> |')
        } elseif ($line -cmatch '^\|\s*Phase\s*\|') {
            $output.Add('| Phase | <inactive> |')
        } elseif ($line -cmatch '^\|\s*Next step\s*\|') {
            $output.Add('| Next step | <inactive> |')
        } else {
            $output.Add($line)
        }
    }
    return [string]::Join("`n", $output)
}

function Invoke-LegacyStateMigration {
    if ($Scope -ne 'project' -or $env:FORGE_TRANSACTION_STAGE -eq '1') { return }
    $state = Join-Path $Target '.forge\local\state.md'
    if (-not (Test-Path -LiteralPath $state)) { return }
    $item = Get-Item -LiteralPath $state -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Write-Host 'STATE_COMPATIBILITY: BLOCKED reason=canonical-state-not-regular action=copy-state-aside-seed-current-template-and-restore-reviewed-narrative'
        return
    }
    Assert-NoLinkAncestor $Target '.forge\local\state.md'
    $bytes = [IO.File]::ReadAllBytes($state)
    $snapshot = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllBytes($snapshot, $bytes)
    try {
        $hasBom = Test-HasByteOrderMark $bytes
        $lines = @([IO.File]::ReadAllLines($snapshot))
        $portableMarker = $lines.Count -gt 0 -and $lines[0] -ceq '<!-- forge:state-schema v6 -->' -and -not $hasBom
        $workflowHelper = Join-Path $RepoRoot 'hooks\lib\workflow-state.ps1'
        $current = $false
        if ($portableMarker) {
            $current = & { param($Helper, $State) . $Helper; Test-WorkflowStateShape -Path $State } $workflowHelper $snapshot
        }
        if ($current) { return }

        $fixture = Join-Path $RepoRoot 'tests\template\fixtures\state-v6-transitional-inactive.md'
        try {
            $command = Get-MaterializerStateValue $snapshot Workflow Command
            $phase = Get-MaterializerStateValue $snapshot Workflow Phase
            $nextStep = Get-MaterializerStateValue $snapshot Workflow 'Next step'
        } catch {
            Write-Host 'STATE_COMPATIBILITY: BLOCKED reason=unrecognized-canonical-state action=copy-state-aside-seed-current-template-and-restore-reviewed-narrative'
            return
        }
        $commandInactive = @('', 'none', '-', [string][char]0x2014)
        $flowInactive = @('', '-', [string][char]0x2014)
        if ($commandInactive -cnotcontains $command -or $flowInactive -cnotcontains $phase -or $flowInactive -cnotcontains $nextStep) {
            Write-Host 'STATE_COMPATIBILITY: BLOCKED reason=active-or-unrecognized-canonical-state action=copy-state-aside-seed-current-template-and-restore-reviewed-narrative'
            return
        }
        $raw = [IO.File]::ReadAllText($snapshot)
        $skeleton = Get-LegacyStateSkeleton $snapshot
        $fixtureSkeleton = Get-LegacyStateSkeleton $fixture
        if ($null -eq $skeleton -or $skeleton -cne $fixtureSkeleton) {
            Write-Host 'STATE_COMPATIBILITY: BLOCKED reason=unrecognized-canonical-state action=copy-state-aside-seed-current-template-and-restore-reviewed-narrative'
            return
        }
        if ($raw -cmatch '(?m)^- \[[xX]\]|PR creation authorized|\|\s*nonce\s*\|\s*[0-9a-fA-F]{8}-|Review iteration\s*\||Candidate receipt\s*\||Spec review receipt\s*\||Quality review receipt\s*\||Verify app receipt\s*\||E2E receipt\s*\||Promotion receipt\s*\||Council receipt\s*\|') {
            Write-Host 'STATE_COMPATIBILITY: BLOCKED reason=legacy-state-contains-evidence action=copy-state-aside-seed-current-template-and-restore-reviewed-narrative'
            return
        }

        $stateHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $snapshot).Hash.ToLowerInvariant()
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $state).Hash.ToLowerInvariant() -cne $stateHash) {
            throw 'canonical state changed during compatibility classification'
        }
    $backup = "$state.bak.$stateHash"
    if (Test-Path -LiteralPath $backup) {
        $backupItem = Get-Item -LiteralPath $backup -Force
        if ($backupItem.PSIsContainer -or ($backupItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $backup).Hash.ToLowerInvariant() -cne $stateHash) {
            throw "canonical state backup collision: $backup"
        }
    } else {
        $backupTemporary = "$backup.tmp.$([Guid]::NewGuid().ToString('N'))"
        [IO.File]::WriteAllBytes($backupTemporary, $bytes)
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $backupTemporary).Hash.ToLowerInvariant() -cne $stateHash) {
            Remove-Item -LiteralPath $backupTemporary -Force
            throw 'canonical state backup verification failed'
        }
        [IO.File]::Move($backupTemporary, $backup)
    }

        $patterns = @{
        State = '(?ms)^## State\r?\n.*?(?=^## Open Questions\r?$)'
        Questions = '(?ms)^## Open Questions\r?\n.*?(?=^## Blockers\r?$)'
        Blockers = '(?ms)^## Blockers\r?\n.*?(?=^## Update Rules\r?$)'
    }
    $ranges = @{}
    foreach ($key in $patterns.Keys) {
        $matches = [regex]::Matches($raw, $patterns[$key])
        if ($matches.Count -ne 1) { throw "legacy state has an ambiguous $key narrative range" }
        $ranges[$key] = $matches[0].Value
    }
    $candidateText = [IO.File]::ReadAllText((Join-Path $RepoRoot 'state.template.md'))
    foreach ($key in @('State', 'Questions', 'Blockers')) {
        $replacement = $ranges[$key]
        $candidateText = [regex]::Replace($candidateText, $patterns[$key], { param($match) $replacement }, 1)
    }
    $candidate = "$state.tmp.$([Guid]::NewGuid().ToString('N'))"
    try {
        [IO.File]::WriteAllText($candidate, $candidateText, $Utf8NoBom)
        $valid = & { param($Helper, $State) . $Helper; Test-WorkflowStateShape -Path $State } $workflowHelper $candidate
        if (-not $valid) { throw 'migrated canonical state failed current shape validation' }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $state).Hash.ToLowerInvariant() -cne $stateHash) {
            throw 'canonical state changed during compatibility migration'
        }
        [IO.File]::Replace($candidate, $state, [System.Management.Automation.Language.NullString]::Value)
    } finally {
        if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Force }
    }
        Write-Host "STATE_COMPATIBILITY: MIGRATED backup=$backup"
    } finally {
        if (Test-Path -LiteralPath $snapshot) { Remove-Item -LiteralPath $snapshot -Force }
    }
}

function Assert-NoLinkAncestor {
    param([string]$Root, [string]$Relative)
    $current = (Resolve-Path $Root).Path
    foreach ($part in ($Relative -split '[\\/]')) {
        $current = Join-Path $current $part
        if (Test-Path $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "reparse-point managed path: $current" }
        }
    }
}

function Install-CanonicalFile {
    param([string]$Source, [string]$Destination, [string]$Relative)
    Assert-NoLinkAncestor $Target $Relative
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Get-FileRevision {
    param([string]$Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-LegacyAliasCatalog {
    $catalog = @{}
    $manifest = Join-Path $RepoRoot "manifests\legacy-v5-aliases.tsv"
    foreach ($raw in [IO.File]::ReadAllLines($manifest)) {
        if (-not $raw.Trim() -or $raw.StartsWith("#")) { continue }
        $fields = $raw.Split("`t")
        if ($fields.Count -ne 5) { throw "legacy alias manifest row must have five fields" }
        $destination = $fields[2]
        if ($fields[3] -ne "project") { continue }
        if (-not (Test-SafeRelativePath $destination)) { throw "unsafe legacy alias destination: $destination" }
        $digest = $fields[4]
        if ($digest -notmatch '^[0-9a-f]{64}$') { throw "invalid legacy alias fingerprint: $destination" }
        if (-not $catalog.ContainsKey($destination)) {
            $catalog[$destination] = New-Object 'System.Collections.Generic.HashSet[string]'
        }
        [void]$catalog[$destination].Add($digest)
    }
    return $catalog
}

function Get-ExactLegacyAliases([hashtable]$Catalog) {
    $exact = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($destination in $Catalog.Keys) {
        Assert-NoLinkAncestor $Target $destination
        $path = Join-Path $Target ($destination -replace '/', '\')
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $item = Get-Item -LiteralPath $path -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "legacy alias destination is not a regular file: $destination"
        }
        if ($Catalog[$destination].Contains((Get-FileRevision $path))) {
            [void]$exact.Add($destination)
        }
    }
    return ,$exact
}

function Get-LegacyCodexHookRelative([string]$Command) {
    $match = [regex]::Match($Command, '(?i)(?:^|[\\/])\.codex[\\/]hooks[\\/]([A-Za-z0-9._/\\-]+)')
    if (-not $match.Success) { return "" }
    return ".codex/hooks/" + $match.Groups[1].Value.Replace('\', '/')
}

function Update-LegacyCodexHookPayload($Payload, [hashtable]$Catalog, $Exact) {
    if (-not $Payload.PSObject.Properties["hooks"]) { return $false }
    $hooks = $Payload.hooks
    if (-not $hooks) { return $false }
    $legacyInline = @(
        "echo 'COMPACTION IMMINENT. Save learnings to auto memory: bug root causes, patterns, architecture insights, user preferences. NOT session state (that goes in .claude/local/state.md).' >&2; exit 0",
        'powershell -Command "Write-Error ''COMPACTION IMMINENT. Save learnings to auto memory: bug root causes, patterns, architecture insights, user preferences. NOT session state (that goes in .claude/local/state.md).''; exit 0"'
    )
    $changed = $false
    foreach ($eventName in @($hooks.PSObject.Properties.Name)) {
        $retainedBlocks = @()
        foreach ($block in @($hooks.$eventName)) {
            if (-not $block.PSObject.Properties["hooks"]) {
                $retainedBlocks += $block
                continue
            }
            $retainedHooks = @()
            foreach ($hook in @($block.hooks)) {
                $command = if ($hook.command -is [string]) { [string]$hook.command } else { "" }
                if ($legacyInline -contains $command) { $changed = $true; continue }
                $relative = Get-LegacyCodexHookRelative $command
                if (-not $relative -or -not $Catalog.ContainsKey($relative)) {
                    $retainedHooks += $hook
                    continue
                }
                if (-not $Exact.Contains($relative)) {
                    throw "referenced legacy cross-host hook is missing, modified, or ambiguous: $relative"
                }
                $changed = $true
            }
            if ($retainedHooks.Count) {
                $block.hooks = @($retainedHooks)
                $retainedBlocks += $block
            } else {
                $changed = $true
            }
        }
        if ($retainedBlocks.Count) {
            $hooks.$eventName = @($retainedBlocks)
        } else {
            $hooks.PSObject.Properties.Remove($eventName)
            $changed = $true
        }
    }
    return $changed
}

function Invoke-LegacyAliasCleanup([ValidateSet("check", "apply")][string]$Mode) {
    if ($Scope -ne "project" -or $env:FORGE_TRANSACTION_STAGE -eq "1") { return }
    $catalog = Get-LegacyAliasCatalog
    $exact = Get-ExactLegacyAliases $catalog
    $hooksPath = Join-Path $Target ".codex\hooks.json"
    $payload = $null
    $changed = $false
    if (Test-Path -LiteralPath $hooksPath) {
        Assert-NoLinkAncestor $Target ".codex\hooks.json"
        $item = Get-Item -LiteralPath $hooksPath -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Codex hooks configuration is not a regular file"
        }
        try { $payload = Get-Content -LiteralPath $hooksPath -Raw | ConvertFrom-Json }
        catch { throw "Codex hooks configuration is malformed" }
        $changed = Update-LegacyCodexHookPayload $payload $catalog $exact
    }
    if ($Mode -eq "check") { return }
    if ($changed) {
        [IO.File]::WriteAllText($hooksPath, ($payload | ConvertTo-Json -Depth 30) + "`n", $Utf8NoBom)
        Write-Host "RETIRED_COMPAT: .codex/hooks.json legacy registrations"
    }
    $removed = 0
    foreach ($destination in @($exact | Sort-Object)) {
        $path = Join-Path $Target ($destination -replace '/', '\')
        $item = Get-Item -LiteralPath $path -Force
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            -not $catalog[$destination].Contains((Get-FileRevision $path))) {
            throw "legacy alias changed before cleanup: $destination"
        }
        Remove-Item -LiteralPath $path -Force
        $removed++
        Write-Host "RETIRED_COMPAT: $destination"
    }
    if ($removed -or $changed) {
        Write-Host "RETIRED_COMPAT_SUMMARY: files=$removed registrations=$(if ($changed) { 1 } else { 0 })"
    }
}

function Get-ForgeMaterializerTextHash([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Utf8NoBom.GetBytes($Text)))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Render-Adapter {
    param([string]$Template, [string]$Destination, [string]$CanonicalPath, [string]$Revision)
    $name = [IO.Path]::GetFileNameWithoutExtension($Destination)
    if ([IO.Path]::GetFileName($Destination) -eq "SKILL.md") { $name = Split-Path (Split-Path $Destination -Parent) -Leaf }
    $description = "Forge adapter for $name"
    if ($CanonicalPath -in @(
        '.forge/workflows/opinion.md',
        '.forge/workflows/new-feature.md',
        '.forge/workflows/fix-bug.md',
        '.forge/workflows/review-pr-comments.md',
        '.forge/skills/council/SKILL.template.md'
    )) {
        $description += '. Standing human approval covers ordinary-review transport of the bounded immutable candidate, prompt, and evidence, including sensitive tracked or in-scope non-ignored files, to the configured Claude Code/Codex reviewer services, and full-agent investigation selected from task needs. No extra Forge consent question. Ordinary review stays hermetic; investigate uses normal config, tools, network, and real-worktree write access. Host security and external/destructive mutation boundaries still apply.'
    }
    $canonical = Join-Path $Target ($CanonicalPath -replace '/', '\')
    $capabilityLines = [Collections.Generic.List[string]]::new()
    $frontmatter = $false
    $capture = $false
    $frontmatterLine = 0
    foreach ($line in [IO.File]::ReadAllLines($canonical)) {
        $frontmatterLine++
        if (-not $frontmatter) {
            if ($frontmatterLine -eq 1 -and $line -match '^---\r?$') { $frontmatter = $true }
            else { break }
            continue
        }
        if ($line -match '^---\r?$') { break }
        if ($line -match '^(tools|disallowedTools):(?:\s|$)') {
            $capture = $true
            $capabilityLines.Add($line)
            continue
        }
        if ($capture -and $line -match '^\s+') {
            $capabilityLines.Add($line)
            continue
        }
        $capture = $false
    }
    $capabilities = if ($capabilityLines.Count) { $capabilityLines -join "`n" } else { 'tools: "Read, Grep, Glob, Bash"' }
    $text = [IO.File]::ReadAllText($Template)
    $text = $text.Replace("{{CANONICAL_PATH}}", $CanonicalPath).Replace("{{CANONICAL_REVISION}}", $Revision).Replace("{{REVISION}}", $Revision)
    $text = $text.Replace("{{NAME}}", $name).Replace("{{DESCRIPTION}}", $description).Replace("{{CAPABILITIES}}", $capabilities).Replace("{{MODEL}}", "inherit")
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Destination, $text, $Utf8NoBom)
}

function Set-ForgeMarkerBlock {
    param([string]$Template, [string]$Destination, [string]$Revision)
    $block = [IO.File]::ReadAllText($Template).Replace("{{CANONICAL_REVISION}}", $Revision)
    if (($block.Split(@($Begin), [StringSplitOptions]::None).Count - 1) -ne 1 -or ($block.Split(@($End), [StringSplitOptions]::None).Count - 1) -ne 1) { throw "malformed marker template: $Template" }
    $parent = Split-Path -Parent $Destination
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $blockBytes = $Utf8NoBom.GetBytes($block)
    if (-not (Test-Path $Destination)) { [IO.File]::WriteAllBytes($Destination, $blockBytes); return }
    $existing = [IO.File]::ReadAllBytes($Destination)
    $beginBytes = [Text.Encoding]::ASCII.GetBytes($Begin)
    $endBytes = [Text.Encoding]::ASCII.GetBytes($End)
    $beginOffsets = @(Find-ForgeByteSequence $existing $beginBytes)
    $endOffsets = @(Find-ForgeByteSequence $existing $endBytes)
    if ($beginOffsets.Count -eq 0 -and $endOffsets.Count -eq 0) {
        $existingText = [Text.Encoding]::UTF8.GetString($existing)
        $meaningfulLines = @($existingText -split "`r?`n" | Where-Object { $_ -notmatch '^\s*$' })
        $isExactClaudeBridge = (Split-Path -Leaf $Destination) -eq 'CLAUDE.md' -and
            $meaningfulLines.Count -eq 1 -and $meaningfulLines[0] -ceq '@AGENTS.md'
        if ($isExactClaudeBridge) {
            $candidate = $blockBytes
        } else {
            $separator = if ($existing.Length -eq 0) { [byte[]]@() } elseif ($existing[$existing.Length - 1] -eq 10) { [byte[]](10) } else { [byte[]](10,10) }
            $candidate = Join-ForgeByteArrays -First $existing -Second $separator -Third $blockBytes
        }
    } elseif ($beginOffsets.Count -eq 1 -and $endOffsets.Count -eq 1 -and $endOffsets[0] -ge $beginOffsets[0]) {
        $replacementLength = $blockBytes.Length
        if ($replacementLength -gt 0 -and $blockBytes[$replacementLength - 1] -eq 10) { $replacementLength-- }
        if ($replacementLength -gt 0 -and $blockBytes[$replacementLength - 1] -eq 13) { $replacementLength-- }
        $replacement = New-Object byte[] $replacementLength
        if ($replacementLength -gt 0) { [Array]::Copy($blockBytes, 0, $replacement, 0, $replacementLength) }
        $prefix = New-Object byte[] $beginOffsets[0]
        if ($prefix.Length -gt 0) { [Array]::Copy($existing, 0, $prefix, 0, $prefix.Length) }
        $suffixStart = $endOffsets[0] + $endBytes.Length
        $suffix = New-Object byte[] ($existing.Length - $suffixStart)
        if ($suffix.Length -gt 0) { [Array]::Copy($existing, $suffixStart, $suffix, 0, $suffix.Length) }
        $candidate = Join-ForgeByteArrays -First $prefix -Second $replacement -Third $suffix
    } else { throw "malformed or duplicate Forge marker: $Destination" }
    if (-not (Test-ForgeByteArraysEqual $existing $candidate)) { [IO.File]::WriteAllBytes($Destination, $candidate) }
}

function Find-ForgeByteSequence {
    param([byte[]]$Haystack, [byte[]]$Needle)
    if ($Needle.Length -eq 0 -or $Haystack.Length -lt $Needle.Length) { return }
    for ($i = 0; $i -le $Haystack.Length - $Needle.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) { if ($Haystack[$i + $j] -ne $Needle[$j]) { $match = $false; break } }
        if ($match) { Write-Output $i }
    }
}

function Join-ForgeByteArrays {
    param([byte[]]$First, [byte[]]$Second, [byte[]]$Third)
    $result = New-Object byte[] ($First.Length + $Second.Length + $Third.Length)
    if ($First.Length -gt 0) { [Array]::Copy($First, 0, $result, 0, $First.Length) }
    if ($Second.Length -gt 0) { [Array]::Copy($Second, 0, $result, $First.Length, $Second.Length) }
    if ($Third.Length -gt 0) { [Array]::Copy($Third, 0, $result, $First.Length + $Second.Length, $Third.Length) }
    return ,$result
}

function Test-ForgeByteArraysEqual {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($i = 0; $i -lt $Left.Length; $i++) { if ($Left[$i] -ne $Right[$i]) { return $false } }
    return $true
}

function Get-ManagedJsonIdentity {
    param($Value)
    if ($Value -is [string] -or $Value -is [ValueType]) { return "value:$Value" }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        if ($Value.PSObject.Properties["forgeManagedId"]) { return "managed:$($Value.forgeManagedId)" }
        if ($Value.PSObject.Properties["matcher"]) { return "matcher:$($Value.matcher)" }
        if ($Value.PSObject.Properties["command"]) {
            $command = if ($Value.command -is [Array]) { $Value.command -join "`0" } else { [string]$Value.command }
            if ($command -like '*.forge/hooks/lib/*') {
                $known = [ordered]@{
                    'host-context'='host-context'; 'session-start'='session-start';
                    'check-bash-safety'='bash-safety'; 'check-workflow-gates'='workflow-gates';
                    'check-external-mutation-auth'='external-mutation-auth'; 'post-tool-format'='format';
                    'check-subagent-review'='subagent-review-receipt'; 'pre-compact-memory'='precompact-memory';
                    'build-evidence'='build-evidence'; 'check-state-updated'='state-updated'
                }
                foreach ($token in $known.Keys) {
                    if ($command -like "*/$token.sh*" -or $command.EndsWith(" $token.sh")) { return "managed:$($known[$token])" }
                }
            }
            return "command:$($Value.type):$command"
        }
    }
    return "json:$($Value | ConvertTo-Json -Depth 30 -Compress)"
}

function Merge-ManagedJsonObject {
    param($Target, $Owned)
    foreach ($property in $Owned.PSObject.Properties) {
        $targetProperty = $Target.PSObject.Properties[$property.Name]
        if (-not $targetProperty) {
            $Target | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
            continue
        }
        $ownedValue = $property.Value
        $targetValue = $targetProperty.Value
        if ($ownedValue -is [System.Management.Automation.PSCustomObject] -and $targetValue -is [System.Management.Automation.PSCustomObject]) {
            Merge-ManagedJsonObject $targetValue $ownedValue
        } elseif ($ownedValue -is [Array] -and $targetValue -is [Array]) {
            [object[]]$remaining = @($targetValue)
            [object[]]$merged = @()
            foreach ($ownedItem in $ownedValue) {
                $identity = Get-ManagedJsonIdentity $ownedItem
                $match = $null
                foreach ($candidate in @($remaining)) {
                    if ((Get-ManagedJsonIdentity $candidate) -ceq $identity) { $match = $candidate; break }
                }
                if ($match) {
                    if ($ownedItem -is [System.Management.Automation.PSCustomObject] -and $match -is [System.Management.Automation.PSCustomObject]) { Merge-ManagedJsonObject $match $ownedItem }
                    $merged += $match
                    $remaining = @($remaining | Where-Object { (Get-ManagedJsonIdentity $_) -cne $identity })
                } else { $merged += $ownedItem }
            }
            foreach ($item in $remaining) { $merged += $item }
            $targetProperty.Value = [object[]]$merged
        } else {
            # Every key present in the Forge template is managed. Unknown user
            # keys are absent from Owned and therefore remain untouched.
            $targetProperty.Value = $ownedValue
        }
    }
}

function Merge-JsonManagedEntries {
    param([string]$Template, [string]$Destination)
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if (-not (Test-Path $Destination)) { Copy-Item $Template $Destination; return }
    $user = Get-Content -Raw $Destination | ConvertFrom-Json
    $owned = Get-Content -Raw $Template | ConvertFrom-Json
    $beforeCanonical = $user | ConvertTo-Json -Depth 30 -Compress
    if ([string]$owned.description -ceq 'Forge v6 project hooks') {
        if ($user.PSObject.Properties['forgeManagedVersion'] -and [int]$user.forgeManagedVersion -eq 6) {
            $user.PSObject.Properties.Remove('forgeManagedVersion')
        }
        foreach ($legacyEvent in @('session_start','pre_tool_use','post_tool_use','subagent_stop','pre_compact','stop')) {
            $property = $user.hooks.PSObject.Properties[$legacyEvent]
            if (-not $property) { continue }
            [object[]]$retained = @($property.Value | Where-Object { -not $_.forgeManagedId })
            if ($retained.Count -eq 0) { $user.hooks.PSObject.Properties.Remove($legacyEvent) }
            else { $property.Value = $retained }
        }
    }
    Merge-ManagedJsonObject $user $owned
    $afterCanonical = $user | ConvertTo-Json -Depth 30 -Compress
    if ($beforeCanonical -ceq $afterCanonical) { return }
    $backup = "$Destination.bak.$([DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff'))"
    Copy-Item -LiteralPath $Destination -Destination $backup
    [IO.File]::WriteAllText($Destination, ($user | ConvertTo-Json -Depth 30) + "`n", $Utf8NoBom)
}

function Merge-CodexHookEntries {
    param([string]$Template, [string]$Destination)
    Merge-JsonManagedEntries $Template $Destination
}

function Convert-McpJsonToCodexToml {
    param([string]$Path)
    $lines = @()
    $blocked = @()
    if (-not $Path -or -not (Test-Path $Path)) { return [pscustomobject]@{ Text=""; Blocked=@() } }
    $payload = Get-Content -Raw $Path | ConvertFrom-Json
    if (-not $payload.PSObject.Properties["mcpServers"]) { return [pscustomobject]@{ Text=""; Blocked=@() } }
    foreach ($property in $payload.mcpServers.PSObject.Properties | Sort-Object Name) {
        $name = $property.Name
        $server = $property.Value
        if ($name -notmatch '^[A-Za-z0-9_-]+$') { $blocked += "unsupported MCP server '$name'"; continue }
        if ($name -eq "playwright" -and $server.type -eq "stdio" -and $server.command -eq "npx" -and
            (($server.args | ConvertTo-Json -Compress) -eq '["-y","@playwright/mcp@latest"]') -and @($server.env.PSObject.Properties).Count -eq 0) { continue }
        if ($name -eq "context7" -and $server.type -eq "http" -and $server.url -eq "https://mcp.context7.com/mcp") { continue }
        $unknown = @($server.PSObject.Properties.Name | Where-Object { @("type", "command", "args", "env", "cwd", "transport", "url") -notcontains $_ })
        if ($unknown.Count) { $blocked += "$name`: unsupported fields $($unknown -join ',')"; continue }
        if ($server.type -and $server.type -ne "stdio") { $blocked += "$name`: transport type is not safely translatable"; continue }
        if (-not ($server.command -is [string])) { $blocked += "$name`: command transport is not safely translatable"; continue }
        $args = @($server.args)
        if (@($args | Where-Object { -not ($_ -is [string]) }).Count) { $blocked += "$name`: args are not safely translatable"; continue }
        $environment = @($server.env.PSObject.Properties)
        if (@($environment | Where-Object { -not ($_.Value -is [string]) -or $_.Value -notmatch '^\$\{[A-Za-z_][A-Za-z0-9_]*\}$' }).Count) {
            $blocked += "$name`: literal or malformed env value preserved only in .mcp.json"; continue
        }
        $lines += ""
        $lines += "[mcp_servers.$name]"
        $lines += "command = $($server.command | ConvertTo-Json -Compress)"
        $renderedArgs = @($args | ForEach-Object { $_ | ConvertTo-Json -Compress }) -join ", "
        $lines += "args = [$renderedArgs]"
        if ($environment.Count) {
            $renderedEnv = @($environment | Sort-Object Name | ForEach-Object { "$($_.Name | ConvertTo-Json -Compress) = $($_.Value | ConvertTo-Json -Compress)" }) -join ", "
            $lines += "env = { $renderedEnv }"
        }
    }
    $text = if ($lines.Count) { ($lines -join "`n") + "`n" } else { "" }
    return [pscustomobject]@{ Text=$text; Blocked=$blocked }
}

function Set-CodexTomlBlock {
    param([string]$Template, [string]$Destination, [string]$McpJson = "")
    $block = [IO.File]::ReadAllText($Template)
    $tb = "# forge:begin v6"; $te = "# forge:end v6"
    $translation = Convert-McpJsonToCodexToml $McpJson
    if ($translation.Text) { $block = $block.Replace("$te", $translation.Text + $te) }
    if ($translation.Blocked.Count) { Write-Host "CODEX_MCP_PARITY: BLOCKED: $($translation.Blocked -join '; ')" }
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $existing = if (Test-Path $Destination) { [IO.File]::ReadAllText($Destination) } else { "" }
    $begins = $existing.Split(@($tb), [StringSplitOptions]::None).Count - 1
    $ends = $existing.Split(@($te), [StringSplitOptions]::None).Count - 1
    if ($begins -eq 0 -and $ends -eq 0) { $candidate = $existing + $(if (-not $existing -or $existing.EndsWith("`n")) { "" } else { "`n" }) + $block }
    elseif ($begins -eq 1 -and $ends -eq 1) {
        $start=$existing.IndexOf($tb); $finish=$existing.IndexOf($te,$start)+$te.Length
        $candidate=$existing.Substring(0,$start)+$block.TrimEnd()+$existing.Substring($finish)
    } else { throw "malformed or duplicate Forge TOML marker" }
    $readiness = "PENDING: version-qualified Codex doctor validation unavailable"
    $codex = Get-Command codex -ErrorAction SilentlyContinue
    if ($codex) {
        $doctorHelp = (& $codex.Source doctor --help 2>&1) -join "`n"
        if ($doctorHelp -match [regex]::Escape("--json")) {
            $scratch = Join-Path ([IO.Path]::GetTempPath()) ("forge-codex-validator-" + [Guid]::NewGuid().ToString("N"))
            $project = Join-Path $scratch "project"
            $codexHome = Join-Path $scratch "codex-home"
            $projectCodex = Join-Path $project ".codex"
            New-Item -ItemType Directory -Path $projectCodex -Force | Out-Null
            New-Item -ItemType Directory -Path $codexHome -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $projectCodex "config.toml"), $candidate, $Utf8NoBom)
            [IO.File]::WriteAllText((Join-Path $codexHome "config.toml"), $candidate, $Utf8NoBom)
            $previousCodexHome = $env:CODEX_HOME
            try {
                $env:CODEX_HOME = $codexHome
                $stderrPath = Join-Path $scratch "doctor.stderr"
                $doctorJson = (& $codex.Source --strict-config -C $project doctor --json 2>$stderrPath) -join "`n"
                $receipt = $doctorJson | ConvertFrom-Json
                $configLoad = $receipt.checks.'config.load'
                if (-not $configLoad -or $configLoad.status -ne "ok") {
                    $diagnostic = if ($configLoad) { $configLoad.summary } else { Get-Content -Raw $stderrPath }
                    throw "BLOCKED: Codex rejected staged config: $diagnostic"
                }
                $readiness = "VALIDATED: $($configLoad.summary)"
            } finally {
                if ($null -eq $previousCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue }
                else { $env:CODEX_HOME = $previousCodexHome }
                Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    # Promote only after the complete staged candidate passes the available
    # host-native loader. A rejection leaves Destination byte-identical.
    [IO.File]::WriteAllText($Destination, $candidate, $Utf8NoBom)
    Write-Host "CODEX_CONFIG_READINESS: $readiness"
}

function Get-EngineAvailability {
    foreach ($engine in @("claude", "codex")) {
        $command = Get-Command $engine -ErrorAction SilentlyContinue
        if (-not $command) { [pscustomobject]@{ Engine=$engine; Availability="ABSENT"; Path=""; Version="" }; continue }
        $version = (& $command.Source --version 2>$null | Select-Object -First 1)
        if ($engine -eq "claude") {
            $help = (& $command.Source --help 2>&1) -join "`n"
            $required = @("--safe-mode", "--strict-mcp-config", "--session-id", "--resume")
        } else {
            $help = ((& $command.Source --help 2>&1) + (& $command.Source exec --help 2>&1)) -join "`n"
            $required = @("--ignore-user-config", "--ignore-rules", "--ephemeral", "--sandbox", "--add-dir")
        }
        $missing = @($required | Where-Object { $help -notmatch [regex]::Escape($_) })
        if ($missing.Count) {
            [pscustomobject]@{ Engine=$engine; Availability="PRESENT_CAPABILITY_GAP"; Path=$command.Source; Version="$version"; Diagnostic="missing: $($missing -join ' ')" }
        } else {
            [pscustomobject]@{ Engine=$engine; Availability="PRESENT"; Path=$command.Source; Version="$version"; Diagnostic="" }
        }
    }
}

function Get-RetiredWorkflowSkills([object[]]$Rows) {
    $retired = @{}
    if ($Scope -ne 'project') { return $retired }
    $hashes = @{}
    Assert-NoLinkAncestor $Target '.forge/installed-files.tsv'
    $receipt = Join-Path $Target '.forge/installed-files.tsv'
    if (Test-Path -LiteralPath $receipt) {
        foreach ($line in [IO.File]::ReadAllLines($receipt)) {
            if (-not $line -or $line.StartsWith('#')) { continue }
            $fields = $line.Split("`t")
            if ($fields.Count -ne 3) { throw 'malformed installed-files.tsv row' }
            if ($hashes.ContainsKey($fields[0])) { $hashes[$fields[0]] = $null }
            else { $hashes[$fields[0]] = $fields[1] }
        }
    }
    foreach ($row in $Rows) {
        if ($row.Kind -ne 'tombstone' -or $row.Host -ne 'codex' -or $row.Scope -ne 'project' -or $row.Ownership -ne 'forge-generated') { continue }
        $old = $row.Destination
        $short = $old.Replace('/workflow-', '/')
        foreach ($relative in @($short, $old)) {
            Assert-NoLinkAncestor $Target $relative
            $path = Join-Path $Target $relative
            if (-not (Test-Path -LiteralPath $path)) { continue }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "workflow skill is not a regular file: $relative" }
            $digest = Get-FileRevision $path
            $lines = [IO.File]::ReadAllLines($path)
            $metadata = @{}
            if ($lines.Length -gt 0 -and $lines[0] -ceq '---') {
                for ($i = 1; $i -lt $lines.Length; $i++) {
                    if ($lines[$i] -ceq '---') { break }
                    $pair = $lines[$i] -split ':', 2
                    if ($pair.Count -eq 2) { $metadata[$pair[0]] = $pair[1].Trim().Trim('"') }
                }
                if ($i -eq $lines.Length) { $metadata = @{} }
            }
            $name = ($relative -split '/')[-2]
            $owned = $hashes[$relative] -ceq $digest -and $metadata['forge-generated'] -ceq 'true' -and $metadata['canonical-path'] -ceq $row.CanonicalPath -and $metadata['name'] -ceq $name
            if (-not $owned) {
                if ($relative -eq $short) { throw "custom or unproven workflow skill collision: $relative; move it aside, rerun setup, then reconcile custom content" }
                Write-Host "PRESERVED_COMPAT: $relative (modified or unproven; reconcile the old name manually)"
            } elseif ($relative -eq $old) { $retired[$relative] = $digest }
        }
    }
    return $retired
}

function Write-InstallManifest {
    param([object[]]$Records)
    $out = Join-Path $Target ".forge\installed-files.tsv"
    $lines = @()
    foreach ($record in ($Records | Sort-Object Path -Unique)) {
        $relative = $record.Path
        $full = Join-Path $Target $relative
        if ($relative -eq '.forge/version') {
            $revision = Get-ForgeMaterializerTextHash "$ReleaseVersion`n"
        } elseif (Test-Path $full -PathType Leaf) {
            $revision = Get-FileRevision $full
        } else {
            continue
        }
        $lines += "$relative`t$revision`t$($record.CanonicalRevision)"
    }
    $temporary = "$out.tmp.$([Guid]::NewGuid().ToString('N'))"
    [IO.File]::WriteAllLines($temporary, $lines, $Utf8NoBom)
    if (Test-Path -LiteralPath $out) { [IO.File]::Replace($temporary, $out, [System.Management.Automation.Language.NullString]::Value) }
    else { [IO.File]::Move($temporary, $out) }
}

Invoke-LegacyAliasCleanup "check"
$rows = Read-ManagedManifest $Manifest
$retiredWorkflowSkills = Get-RetiredWorkflowSkills $rows
Invoke-LegacyStateMigration
foreach ($row in $rows) {
    if ($row.Scope -ne $Scope -or @("all", $Platform) -notcontains $row.Platform) { continue }
    $source = Join-Path $RepoRoot ($row.Source -replace '/', '\')
    $destination = Join-Path $Target ($row.Destination -replace '/', '\')
    if (@("canonical", "adapter", "marker") -contains $row.Kind) { Assert-NoLinkAncestor $Target $row.Destination }
    switch ($row.Kind) {
        "canonical" {
            Install-CanonicalFile $source $destination $row.Destination
            $Installed += [pscustomobject]@{ Path=$row.Destination; CanonicalRevision=(Get-FileRevision $destination) }
        }
        "adapter" {
            $canonical = Join-Path $Target ($row.CanonicalPath -replace '/', '\')
            if (-not (Test-Path $canonical)) { throw "adapter canonical target missing: $($row.CanonicalPath)" }
            $canonicalRevision = Get-FileRevision $canonical
            Render-Adapter $source $destination $row.CanonicalPath $canonicalRevision
            $Installed += [pscustomobject]@{ Path=$row.Destination; CanonicalRevision=$canonicalRevision }
        }
        "marker" {
            $canonical = Join-Path $Target ($row.CanonicalPath -replace '/', '\')
            if (-not (Test-Path $canonical)) { throw "marker canonical target missing: $($row.CanonicalPath)" }
            $canonicalRevision = Get-FileRevision $canonical
            Set-ForgeMarkerBlock $source $destination $canonicalRevision
            $Installed += [pscustomobject]@{ Path=$row.Destination; CanonicalRevision=$canonicalRevision }
        }
    }
}

foreach ($relative in @(".forge\local\state.md", ".claude\settings.json", ".mcp.json", ".codex\hooks.json", ".codex\config.toml")) { Assert-NoLinkAncestor $Target $relative }
New-Item -ItemType Directory -Path (Join-Path $Target ".forge\local") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Target ".forge\memory") -Force | Out-Null
$state = Join-Path $Target ".forge\local\state.md"
if (-not (Test-Path $state)) { Copy-Item (Join-Path $RepoRoot "state.template.md") $state }
Merge-JsonManagedEntries (Join-Path $RepoRoot "settings\settings-windows.template.json") (Join-Path $Target ".claude\settings.json")
Merge-JsonManagedEntries (Join-Path $RepoRoot "mcp.template.json") (Join-Path $Target ".mcp.json")
Merge-CodexHookEntries (Join-Path $RepoRoot "settings\codex-hooks.template.json") (Join-Path $Target ".codex\hooks.json")
Set-CodexTomlBlock (Join-Path $RepoRoot "settings\codex-config.template.toml") (Join-Path $Target ".codex\config.toml") (Join-Path $Target ".mcp.json")
Invoke-LegacyAliasCleanup "apply"
foreach ($relative in $retiredWorkflowSkills.Keys) {
    Assert-NoLinkAncestor $Target $relative
    $path = Join-Path $Target $relative
    if ((Get-FileRevision $path) -cne $retiredWorkflowSkills[$relative]) { throw "workflow skill changed before cleanup: $relative" }
    Remove-Item -LiteralPath $path
    Write-Host "RETIRED_COMPAT: $relative"
}
$Installed += [pscustomobject]@{ Path=".forge/version"; CanonicalRevision="-" }
Write-InstallManifest -Records $Installed
$version = Join-Path $Target ".forge\version"
$versionTemporary = "$version.tmp.$([Guid]::NewGuid().ToString('N'))"
[IO.File]::WriteAllText($versionTemporary, "$ReleaseVersion`n", $Utf8NoBom)
if (Test-Path -LiteralPath $version) { [IO.File]::Replace($versionTemporary, $version, [System.Management.Automation.Language.NullString]::Value) }
else { [IO.File]::Move($versionTemporary, $version) }
Write-Host "FORGE_VERSION: $ReleaseVersion"
Write-Host "INSTALLATION: MATERIALIZED"
foreach ($engine in Get-EngineAvailability) {
    if ($engine.Availability -eq "ABSENT") { Write-Host "$($engine.Engine) RUNTIME_READY: BLOCKED binary unavailable; host surface remains materialized" }
    elseif ($engine.Availability -eq "PRESENT_CAPABILITY_GAP") { Write-Host "$($engine.Engine) RUNTIME_READY: BLOCKED $($engine.Diagnostic)" }
    else { Write-Host "$($engine.Engine) RUNTIME_READY: BLOCKED pending authenticated final runtime qualification ($($engine.Path); $($engine.Version))" }
}
$diagnosticTarget = if ($env:FORGE_DIAGNOSTIC_TARGET) {
    (Resolve-Path -LiteralPath $env:FORGE_DIAGNOSTIC_TARGET).Path
} else {
    (Resolve-Path -LiteralPath $Target).Path
}
$primary = Get-PrimaryCheckout $diagnosticTarget
if ($primary) { $primary = (Resolve-Path -LiteralPath $primary).Path }
if ($primary -and -not [string]::Equals($primary, $diagnosticTarget, [StringComparison]::OrdinalIgnoreCase)) {
    Write-Host "CODEX_HOOKS: BLOCKED linked worktree cannot mutate primary registration"
    Write-Host "Run: Set-Location '$primary'; & '$RepoRoot\setup.ps1'"
} else {
    Write-Host "CODEX_HOOKS: MATERIALIZED primary worktree registration; trust remains unverified"
}
Write-NormalProjectWorkflowStatus $diagnosticTarget
Write-Host "NATIVE_GOAL_RUNTIME: PENDING reason=live-qualification-not-run"
Write-Host "RUNTIME_QUALIFICATION: final owner '$(Join-Path $RepoRoot 'scripts\qualify-runtime-final.ps1')'; live project '$diagnosticTarget'; command and required operator evidence: '$(Join-Path $RepoRoot 'docs\qualification\agent-mode-selection.md')'"
