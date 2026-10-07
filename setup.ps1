# ============================================================================
# Claude Code Project Setup Script (PowerShell)
# Company-wide template for consistent AI-assisted development workflow
# ============================================================================

param(
    [Alias("h")]
    [switch]$Help,

    [Alias("p")]
    [string]$Project = "",

    [Alias("t")]
    [ValidateSet("python", "typescript", "fullstack")]
    [string]$Tech = "fullstack",

    [Alias("f")]
    [switch]$Force,

    [Alias("R")][switch]$FullRefresh,

    [switch]$DryRun,

    [switch]$ThisCheckoutOnly,

    [Alias("u")]
    [switch]$Upgrade,

    [switch]$Migrate,

    [Alias("g")]
    [switch]$Global,

    [switch]$RetireGlobal,

    [switch]$Apply,

    [string]$Confirm = "",

    [Alias("w")]
    [switch]$WithPlaywright,

    [string]$PlaywrightDir
)

if ($args.Count -gt 0) {
    [Console]::Error.WriteLine("ERROR: unknown option or unexpected argument: $($args[0])")
    exit 1
}

# Preserve bound public options before normal setup derives its internal flags.
$OriginalSetupParameters = @{}
foreach ($key in $PSBoundParameters.Keys) { $OriginalSetupParameters[$key] = $PSBoundParameters[$key] }

# Script directory (where templates live)
$ScriptDir = $PSScriptRoot

function Get-ForgeVersion {
    try {
        $top = Select-String -Path (Join-Path $ScriptDir "docs/CHANGELOG.md") -Pattern '^##\s' -List 2>$null
        if ($top -and $top.Line -match '^##\s+([0-9]+\.[0-9]+\.[0-9]+)(?:\s|$)') {
            $v = $Matches[1]
            if ($v -match '^\d+\.\d+\.\d+$') { return $v }
        }
    } catch {}
    return "unknown"
}
$ForgeVersion = Get-ForgeVersion
if ($ForgeVersion -notmatch '^\d+\.\d+\.\d+$') {
    [Console]::Error.WriteLine('BLOCKED: published Forge release is unavailable')
    exit 2
}

if ($Migrate) {
    [Console]::Error.WriteLine("ERROR: -Migrate was retired in Forge 6; no files changed. Run .\setup.ps1 -Force -DryRun.")
    exit 1
}

$DeprecatedFullRefresh = $FullRefresh
$AuthoritativeRefresh = $Force -or $FullRefresh

if ($DryRun -and -not $AuthoritativeRefresh) {
    [Console]::Error.WriteLine("ERROR: DryRun requires Force.")
    exit 1
}

if ($AuthoritativeRefresh -and ($Upgrade -or $WithPlaywright)) {
    [Console]::Error.WriteLine("ERROR: Force cannot be combined with Upgrade or WithPlaywright.")
    exit 1
}

if ($DeprecatedFullRefresh) {
    [Console]::Error.WriteLine("DEPRECATED: -FullRefresh/-R is an alias for -Force; use -Force.")
}

$FullRefresh = $AuthoritativeRefresh
$Force = $false

function Write-NativeGoalCollisions {
    param([string]$Root)
    if (Test-Path -LiteralPath (Join-Path $Root ".claude\commands\goal.md")) {
        Write-Host "RUNTIME_READY=BLOCKED host=claude custom native goal collision; rename .claude/commands/goal.md and rerun setup"
    }
    if (Test-Path -LiteralPath (Join-Path $Root ".agents\skills\goal")) {
        Write-Host "RUNTIME_READY=BLOCKED host=codex custom native goal collision; rename .agents/skills/goal/ and rerun setup"
    }
}

# Upgrade refreshes Forge-owned hooks/commands/rules in an existing v6 install.
if ($Upgrade) { $Force = $true }

# Colors function
function Write-Color {
    param(
        [string]$Text,
        [string]$Color = "White"
    )
    Write-Host $Text -ForegroundColor $Color
}

# Usage
function Show-Usage {
    Write-Host "Usage: .\setup.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Set up Forge configuration in the current project."
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -h, -Help           Show this help message"
    Write-Host "  -p, -Project NAME   Project name (default: directory name)"
    Write-Host "  -t, -Tech STACK     Tech stack: python, typescript, fullstack (default: fullstack)"
    Write-Host "  -u, -Upgrade        Update an existing v6 install; preserve project configuration"
    Write-Host "  -f, -Force          Authoritative transactional full installation/reconciliation"
    Write-Host "      -DryRun         Preview -Force without writing target files"
    Write-Host "      -ThisCheckoutOnly  Limit setup to this checkout (default: all Git worktrees)"
    Write-Host "  -g, -Global         Retired; prints the project-only migration path"
    Write-Host "      -RetireGlobal   Preview removal of a legacy global Forge harness"
    Write-Host "      -Apply          Apply -RetireGlobal after a matching preview"
    Write-Host "      -Confirm SHA    Confirm the exact retirement preview digest"
    Write-Host "  -w, -WithPlaywright Install Playwright framework templates (requires -Tech fullstack or typescript)"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\setup.ps1                          # Setup with defaults"
    Write-Host "  .\setup.ps1 -p `"My Project`"          # Custom project name"
    Write-Host "  .\setup.ps1 -t python                # Python-only project"
    Write-Host "  .\setup.ps1 -Upgrade                 # Update an existing v6 install"
    Write-Host "  .\setup.ps1 -Force -DryRun           # Preview full reconciliation"
    Write-Host "  .\setup.ps1 -Force                   # Execute full reconciliation"
    Write-Host "  .\setup.ps1 -RetireGlobal            # Preview legacy machine-wide cleanup"
    Write-Host "  .\setup.ps1 -RetireGlobal -Apply -Confirm SHA256"
    Write-Host "  .\setup.ps1 -Tech fullstack -WithPlaywright  # Install Playwright framework templates"
}

# Show help if requested
if ($Help) {
    Show-Usage
    exit 0
}

if ($Global) {
    [Console]::Error.WriteLine("ERROR: global installation is retired; Forge is installed per project. Use -RetireGlobal to preview cleanup of a legacy machine-wide harness.")
    exit 1
}
if ($Apply -and -not $RetireGlobal) {
    [Console]::Error.WriteLine("ERROR: -Apply is valid only with -RetireGlobal.")
    exit 1
}
if ($Confirm -and -not $RetireGlobal) {
    [Console]::Error.WriteLine("ERROR: -Confirm is valid only with -RetireGlobal.")
    exit 1
}
if ($RetireGlobal) {
    if ($Apply -and $Confirm -cnotmatch '^[0-9a-f]{64}$') {
        [Console]::Error.WriteLine("ERROR: -RetireGlobal -Apply requires -Confirm with the preview's lowercase SHA-256.")
        exit 1
    }
    if (-not $Apply -and $Confirm) {
        [Console]::Error.WriteLine("ERROR: -Confirm requires -Apply.")
        exit 1
    }
    $python = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $python) {
        [Console]::Error.WriteLine("BLOCKED: Python 3 is required only for legacy global retirement")
        exit 2
    }
    $retireArgs = @((Join-Path $ScriptDir "scripts\retire-global.py"), "--repo-root", $ScriptDir, "--home", $HOME, "--platform", "windows")
    if ($Apply) { $retireArgs += @("--apply", "--digest", $Confirm) }
    & $python.Source @retireArgs
    exit $LASTEXITCODE
}

# Reject invalid public combinations before any sibling action.
if ($WithPlaywright -and $Tech -ne 'fullstack' -and $Tech -ne 'typescript') {
    [Console]::Error.WriteLine('ERROR: -WithPlaywright requires -Tech fullstack or -Tech typescript.')
    exit 1
}

# Native line pipelines on Windows 5.1 can decode Unicode using the console
# code page. Capture Git's UTF-8 metadata directly, including NUL list records.
function Read-SetupGit {
    param([string]$Arguments, [string]$Directory)
    $gitProcess = $null
    try {
        $gitProcess = New-Object System.Diagnostics.Process
        $gitProcess.StartInfo.FileName = (Get-Command git -ErrorAction Stop).Source
        $gitProcess.StartInfo.Arguments = $Arguments
        $gitProcess.StartInfo.WorkingDirectory = $Directory
        $gitProcess.StartInfo.UseShellExecute = $false
        $gitProcess.StartInfo.RedirectStandardOutput = $true
        $gitProcess.StartInfo.RedirectStandardError = $true
        $gitProcess.StartInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
        $null = $gitProcess.Start()
        $output = $gitProcess.StandardOutput.ReadToEnd()
        $diagnostic = $gitProcess.StandardError.ReadToEnd()
        $gitProcess.WaitForExit()
        if ($gitProcess.ExitCode -ne 0) { throw $diagnostic }
        return $output
    } finally { if ($gitProcess) { $gitProcess.Dispose() } }
}

if (-not $ThisCheckoutOnly) {
    $insideWorktree = (& git rev-parse --is-inside-work-tree 2>$null)
    if ($LASTEXITCODE -eq 0 -and $insideWorktree -eq 'true') {
        try {
            $worktreeRootText = (Read-SetupGit 'rev-parse --show-toplevel' (Get-Location).Path).TrimEnd([char[]]"`r`n")
            $worktreeRoot = (Resolve-Path -LiteralPath $worktreeRootText -ErrorAction Stop).Path
            if ((Resolve-Path -LiteralPath (Get-Location).Path).Path -ne $worktreeRoot) {
                [Console]::Error.WriteLine("BLOCKED: run setup from the Git repository root: $worktreeRoot")
                exit 1
            }
            $worktreeList = Read-SetupGit 'worktree list --porcelain -z' (Get-Location).Path
        } catch {
            [Console]::Error.WriteLine("BLOCKED: cannot discover Git worktrees; default discovery requires Git 2.36+. Upgrade Git or use -ThisCheckoutOnly; no checkouts changed. $_")
            exit 1
        }
        $worktreeTargets = @()
        $worktreePath = ''; $worktreeBare = $false
        foreach ($field in $worktreeList.Split([char]0)) {
            if ($field.StartsWith('worktree ')) { $worktreePath = $field.Substring(9) }
            elseif ($field -eq 'bare') { $worktreeBare = $true }
            elseif ($field -eq '') {
                if ($worktreePath -and -not $worktreeBare) { $worktreeTargets += $worktreePath }
                $worktreePath = ''; $worktreeBare = $false
            }
        }
        if ($worktreeTargets.Count -eq 0) {
            [Console]::Error.WriteLine('BLOCKED: Git returned no checkout worktrees; no checkouts changed.')
            exit 1
        }
        if ($worktreeTargets.Count -gt 1) {
            try {
                $commonText = (Read-SetupGit 'rev-parse --git-common-dir' $worktreeRoot).TrimEnd([char[]]"`r`n")
                if (-not [IO.Path]::IsPathRooted($commonText)) { $commonText = Join-Path $worktreeRoot $commonText }
                $worktreeCommon = (Resolve-Path -LiteralPath $commonText -ErrorAction Stop).Path
            } catch {
                [Console]::Error.WriteLine("BLOCKED: cannot resolve the Git common directory; no checkouts changed. $_")
                exit 1
            }
            # Use this caller's actual runtime, including native Windows 5.1.
            # Encoded commands preserve string values and explicit false switches
            # through Windows native quoting without changing the public mode.
            $setupRuntime = (Get-Process -Id $PID).Path
            function Invoke-WorktreeSetup {
                param([hashtable]$Options)
                $childCommand = "& '" + [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent((Join-Path $ScriptDir 'setup.ps1')) + "'"
                foreach ($name in $Options.Keys) {
                    if ($name -eq 'ThisCheckoutOnly') { continue }
                    $value = $Options[$name]
                    if ($value -is [switch] -or $value -is [bool]) {
                        $childCommand += ' -' + $name + ':$' + ([bool]$value).ToString().ToLowerInvariant()
                    } else {
                        $childCommand += ' -' + $name + " '" + [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent([string]$value) + "'"
                    }
                }
                $childCommand += ' -ThisCheckoutOnly; if (-not $?) { exit 1 }; exit $LASTEXITCODE'
                $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCommand))
                & $setupRuntime -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand $encoded | Out-Host
                return $LASTEXITCODE
            }
            $worktreeStatus = 0
            foreach ($target in $worktreeTargets) {
                if (-not (Test-Path -LiteralPath $target -PathType Container)) {
                    Write-Host "WORKTREE_RESULT path=$target release=$ForgeVersion outcome=missing"
                    $worktreeStatus = 1
                    continue
                }
                $locationPushed = $false
                try {
                    # Refuse unavailable/prunable paths and unrelated replacement
                    # repositories before normal setup could initialize them.
                    $targetRootText = (Read-SetupGit 'rev-parse --show-toplevel' $target).TrimEnd([char[]]"`r`n")
                    $targetRoot = (Resolve-Path -LiteralPath $targetRootText -ErrorAction Stop).Path
                    $targetCommonText = (Read-SetupGit 'rev-parse --git-common-dir' $target).TrimEnd([char[]]"`r`n")
                    if (-not [IO.Path]::IsPathRooted($targetCommonText)) { $targetCommonText = Join-Path $target $targetCommonText }
                    $targetCommon = (Resolve-Path -LiteralPath $targetCommonText -ErrorAction Stop).Path
                    if ($targetRoot -ne (Resolve-Path -LiteralPath $target).Path -or $targetCommon -ne $worktreeCommon) {
                        throw "registered checkout has unrelated Git identity: $target"
                    }
                    Push-Location -LiteralPath $target -ErrorAction Stop
                    $locationPushed = $true
                    if (-not $DryRun) {
                        # Output stays visible, including a BLOCKED planner.
                        $plannerStatus = Invoke-WorktreeSetup @{Force=$true;DryRun=$true}
                        if ($plannerStatus -ne 0) {
                            Write-Host "WORKTREE_RESULT path=$target release=$ForgeVersion outcome=blocked"
                            $worktreeStatus = 1
                            continue
                        }
                    }
                    $childStatus = Invoke-WorktreeSetup $OriginalSetupParameters
                    if ($childStatus -eq 0) {
                        $outcome = 'materialized'
                        if ($DryRun) { $outcome = 'preview' }
                        Write-Host "WORKTREE_RESULT path=$target release=$ForgeVersion outcome=$outcome"
                    } else {
                        Write-Host "WORKTREE_RESULT path=$target release=$ForgeVersion outcome=failed"
                        $worktreeStatus = 1
                    }
                } catch {
                    [Console]::Error.WriteLine("BLOCKED: registered checkout failed: $target; $_")
                    Write-Host "WORKTREE_RESULT path=$target release=$ForgeVersion outcome=blocked"
                    $worktreeStatus = 1
                } finally { if ($locationPushed) { Pop-Location } }
            }
            exit $worktreeStatus
        }
    }
}

if ($FullRefresh) {
    $refreshHelper = Join-Path (Join-Path $ScriptDir "scripts") "full-refresh.ps1"
    if (-not (Test-Path -LiteralPath $refreshHelper -PathType Leaf)) {
        [Console]::Error.WriteLine("BLOCKED: full-refresh helper not found: $refreshHelper")
        exit 1
    }
    $refreshArguments = @{ Target = (Get-Location).Path; Scope = "project"; ReleaseVersion = $ForgeVersion }
    if ($DryRun) { $refreshArguments["DryRun"] = $true }
    & $refreshHelper @refreshArguments
    if ($LASTEXITCODE -eq 0) { Write-NativeGoalCollisions (Get-Location).Path }
    exit $LASTEXITCODE
}

function Test-V6PreflightNoLegacy {
    param([string]$Root, [ValidateSet("project")][string]$Scope)
    $version = Join-Path $Root ".forge\version"
    if (Test-Path $version) {
        $installedVersion = ((Get-Content -Raw $version).Trim())
        if ($installedVersion -match '^(\d+)(\.\d+){0,2}$') {
            if ($Matches[1] -ne "6") { throw "BLOCKED: unsupported Forge layout major $($Matches[1])" }
            return
        }
        throw "BLOCKED: malformed Forge release at $version"
        return
    }
    if ($Scope -eq "project" -and (Test-Path -LiteralPath (Join-Path $Root "CONTINUITY.md"))) {
        throw "BLOCKED: legacy CONTINUITY.md requires authoritative preview; run .\setup.ps1 -Force -DryRun"
    }
    $manifest = Join-Path $ScriptDir "manifests\legacy-v5.tsv"
    if (-not (Test-Path $manifest)) { throw "BLOCKED: legacy v5 inventory is unavailable" }
    foreach ($raw in [IO.File]::ReadAllLines($manifest)) {
        if (-not $raw.Trim() -or $raw.StartsWith("#")) { continue }
        $fields = $raw.Split("`t")
        if ($fields.Count -ne 9) { throw "BLOCKED: malformed legacy v5 inventory" }
        $destination = $fields[2]; $rowScope = $fields[3]; $platform = $fields[4]; $ownership = $fields[6]
        if ($rowScope -ne $Scope -or @("all", "windows") -notcontains $platform) { continue }
        if ($destination -eq "CLAUDE.md" -or $destination -eq ".claude/CLAUDE.md") {
            if ($ownership -ne "mixed-regions") { continue }
            $mixed = Join-Path $Root ($destination -replace '/', '\')
            if (-not (Test-Path $mixed -PathType Leaf)) { continue }
            $text = [IO.File]::ReadAllText($mixed)
            $recognizable = $text -match '(?m)^# CLAUDE\.md - |^## Project Overview$|^### Research Enforcement$|^## Detailed Rules$|\.claude/(commands|rules|hooks|skills|agents)/'
            if (-not $recognizable) { continue }
        } elseif ($destination.StartsWith(".claude/")) {
            $tail = $destination.Substring(8)
            $family = $tail.Split('/')[0]
            $familyPath = Join-Path $Root ".claude\$family"
            if (-not (Test-Path $familyPath)) { continue }
            # A lone custom native goal is not a legacy Forge harness. Let
            # setup preserve it and report the explicit goal collision.
            if ($Scope -eq "project" -and $family -eq "commands") {
                $members = @(Get-ChildItem -Force $familyPath)
                $goalPath = Join-Path $familyPath "goal.md"
                if ((Test-Path $goalPath -PathType Leaf) -and $members.Count -eq 1 -and $members[0].Name -eq "goal.md") { continue }
            }
        } else { continue }
        if ($Upgrade) { throw "BLOCKED: legacy Forge harness requires authoritative refresh. Preview first: & '$ScriptDir\setup.ps1' -Force -DryRun" }
        throw "BLOCKED: legacy Forge harness detected. Preview first: & '$ScriptDir\setup.ps1' -Force -DryRun"
    }
}

try {
    Test-V6PreflightNoLegacy (Get-Location).Path "project"
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}

# Tracks template-copy failures so the project version pin is only written after a
# FULLY successful copy pass (Codex code-review iter-2 P2). PowerShell Copy-Item errors
# are non-terminating by default, so — unlike setup.sh under `set -e` which aborts — we
# must count failures explicitly and refuse to stamp if any occurred.
$script:ForgeCopyErrors = 0

# Copy function with force check
function Copy-TemplateFile {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Description
    )

    if (-not (Test-Path $Source)) {
        $script:ForgeCopyErrors++   # missing template = incomplete install → must not stamp (Codex iter-3 P2)
        Write-Host "  " -NoNewline
        Write-Color "x" "Red"
        Write-Host " Template not found: $Source"
        return
    }

    # Self-copy guard (parity with setup.sh copy_file): when run IN-PLACE
    # (maintainer dogfooding via `.\setup.ps1 -Upgrade` in the repo), $ScriptDir
    # == repo root, so some copies (e.g. docs\adr\*) resolve to the same file and
    # Copy-Item onto itself throws. Same file → no-op, so skip. `-ceq` is
    # case-sensitive because PowerShell `-eq` is not (avoids over-skipping
    # case-only-distinct paths). This is path-identity, not inode-identity (a true
    # check needs PS 7.1+ ResolveLinkTarget, absent on the 5.1 floor — ADR 0002);
    # sufficient here because the repo's copies are plain files.
    if ((Test-Path $Destination) -and
        ((Resolve-Path $Source).Path -ceq (Resolve-Path $Destination).Path)) {
        Write-Host "  " -NoNewline
        Write-Color "o" "Blue"
        Write-Host " $Description already current (source and destination are the same file)"
        return
    }

    if ((Test-Path $Destination) -and (-not $Force)) {
        Write-Host "  " -NoNewline
        Write-Color "o" "Blue"
        Write-Host " $Description already exists (use -Upgrade to refresh)"
        return
    }

    # Ensure parent directory exists
    $parentDir = Split-Path -Parent $Destination
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    try {
        Copy-Item -Path $Source -Destination $Destination -Force -ErrorAction Stop
        Write-Host "  " -NoNewline
        Write-Color "+" "Green"
        Write-Host " Created $Description"
    } catch {
        $script:ForgeCopyErrors++
        Write-Host "  " -NoNewline
        Write-Color "x" "Red"
        Write-Host " Failed to copy $Description ($_)"
    }
}

# ============================================================================
# PROJECT SETUP
# ============================================================================

# Validate -WithPlaywright flag
if ($WithPlaywright) {
    if ($Tech -ne "fullstack" -and $Tech -ne "typescript") {
        Write-Color "ERROR: -WithPlaywright requires -Tech fullstack or -Tech typescript." "Red"
        Write-Color "Playwright framework only applies to web/TS projects." "Yellow"
        exit 1
    }
}

# Default project name to directory name
if ([string]::IsNullOrEmpty($Project)) {
    $Project = Split-Path -Leaf (Get-Location)
}

Write-Color "============================================" "Blue"
Write-Color "  Claude Code Setup for: $Project" "Green"
Write-Color "  Tech Stack: $Tech" "Green"
Write-Color "============================================" "Blue"
Write-Host ""

# Check prerequisites
Write-Color "Checking prerequisites..." "Yellow"

# Check for git
$gitPath = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitPath) {
    Write-Color "ERROR: git is required but not installed." "Red"
    exit 1
}

# Check if in git repository
$isGitRepo = git rev-parse --is-inside-work-tree 2>$null
if (-not $isGitRepo) {
    Write-Color "WARNING: Not in a git repository. Initializing..." "Yellow"
    git init
}

try {
    $setupRepoRootText = (Read-SetupGit 'rev-parse --show-toplevel' (Get-Location).Path).TrimEnd([char[]]"`r`n")
} catch {
    [Console]::Error.WriteLine("BLOCKED: cannot resolve the Git repository root. $_")
    exit 1
}
if (-not $setupRepoRootText) {
    [Console]::Error.WriteLine("BLOCKED: cannot resolve the Git repository root.")
    exit 1
}
$setupRepoRoot = (Resolve-Path -LiteralPath $setupRepoRootText.Trim()).Path
$setupWorkingRoot = (Resolve-Path -LiteralPath (Get-Location).Path).Path
if ($setupWorkingRoot -ne $setupRepoRoot) {
    [Console]::Error.WriteLine("BLOCKED: run setup from the Git repository root: $setupRepoRoot")
    exit 1
}

# ---------------------------------------------------------------------------
# Runtime version preflight (warn-only, never blocks).
# Mirrors the POSIX logic in setup.sh. See docs/guides/multi-project-isolation.md
# for the full policy. Scope for v1: repo-root .python-version, .nvmrc, and
# root package.json engines.node. Never changes exit code.
# ---------------------------------------------------------------------------
function Test-PythonVersion([string]$required) {
    # NOTE: use `uv python find` (checks only installed interpreters), not
    # `uv python list` (which includes downloadable ones and would false-positive).
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        uv python find $required *>$null 2>&1
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    if (Get-Command pyenv -ErrorAction SilentlyContinue) {
        $pyenvList = pyenv versions --bare 2>$null
        if ($pyenvList -and ($pyenvList -match [regex]::Escape($required))) { return $true }
    }
    $parts = $required.Split('.')
    if ($parts.Length -ge 2) {
        $mm = "python$($parts[0]).$($parts[1])"
        if (Get-Command $mm -ErrorAction SilentlyContinue) { return $true }
    }
    if (Get-Command python3 -ErrorAction SilentlyContinue) {
        $v = (python3 --version 2>&1) -join ""
        if ($v -match [regex]::Escape($required)) { return $true }
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        $v = (python --version 2>&1) -join ""
        if ($v -match [regex]::Escape($required)) { return $true }
    }
    return $false
}

function Test-NodeVersion([string]$required) {
    $required = $required.TrimStart('v')
    # Bare-major pin ('20') vs full version ('20.11.0'). Full versions require
    # exact match; bare majors allow any patch under that major.
    $isFullVersion = $required.Contains('.')

    if (Get-Command node -ErrorAction SilentlyContinue) {
        $current = ((node --version 2>$null) -replace '^v', '').Trim()
        if ($isFullVersion) {
            if ($required -eq $current) { return $true }
        } else {
            $reqMajor = ($required.Split('.'))[0]
            $curMajor = ($current.Split('.'))[0]
            if ($reqMajor -eq $curMajor) { return $true }
        }
    }
    foreach ($vm in @('fnm', 'nvm', 'volta')) {
        if (Get-Command $vm -ErrorAction SilentlyContinue) {
            $list = (& $vm list 2>$null) -join "`n"
            if (-not $list) { continue }
            if ($isFullVersion) {
                # Match bounded: v?20.11.0 followed by non-digit or EOL
                $escaped = [regex]::Escape($required)
                if ($list -match "v?$escaped(?:[^0-9]|$)") { return $true }
            } else {
                # Match v?20.<digit> — any patch under the major
                if ($list -match "v?$required\.[0-9]") { return $true }
            }
        }
    }
    return $false
}

function Test-NodeEngines([string]$constraint) {
    $minMajorMatch = [regex]::Match($constraint, '\d+')
    if (-not $minMajorMatch.Success) { return $true }  # unparseable — skip
    $minMajor = [int]$minMajorMatch.Value
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return $false }
    $current = ((node --version 2>$null) -replace '^v', '').Trim()
    $curMajor = [int]($current.Split('.'))[0]
    return $curMajor -ge $minMajor
}

Write-Color "Runtime version preflight..." "Yellow"
$script:PreflightWarned = $false

if (Test-Path ".python-version") {
    $pyReq = (Get-Content ".python-version" -TotalCount 1).Trim()
    if ($pyReq) {
        if (Test-PythonVersion $pyReq) {
            Write-Host "  " -NoNewline
            Write-Color "+" "Green"
            Write-Host " Python $pyReq available (from .python-version)"
        } else {
            $script:PreflightWarned = $true
            Write-Host "  " -NoNewline
            Write-Color "!" "Yellow"
            Write-Host " .python-version requires $pyReq, not detected on this machine."
            Write-Host "    Install one of:"
            Write-Host "      uv python install $pyReq       (fastest - uv-native)"
            Write-Host "      pyenv install $pyReq           (classic)"
            Write-Host "    Setup continues; uv sync will retry at project build time."
        }
    }
}

if (Test-Path ".nvmrc") {
    $nodeReq = (Get-Content ".nvmrc" -TotalCount 1).Trim()
    if ($nodeReq) {
        if (Test-NodeVersion $nodeReq) {
            Write-Host "  " -NoNewline
            Write-Color "+" "Green"
            Write-Host " Node $nodeReq available (from .nvmrc)"
        } else {
            $script:PreflightWarned = $true
            Write-Host "  " -NoNewline
            Write-Color "!" "Yellow"
            Write-Host " .nvmrc requires Node $nodeReq, not detected on this machine."
            Write-Host "    Install one of:"
            Write-Host "      fnm install $nodeReq           (fastest - auto-switches)"
            Write-Host "      nvm install $nodeReq           (classic)"
            Write-Host "      volta install node@$nodeReq"
        }
    }
}

if (Test-Path "package.json") {
    try {
        $pkg = Get-Content "package.json" -Raw | ConvertFrom-Json
        $enginesNode = $pkg.engines.node
        if ($enginesNode) {
            if (Test-NodeEngines $enginesNode) {
                Write-Host "  " -NoNewline
                Write-Color "+" "Green"
                Write-Host " Node satisfies engines.node $enginesNode"
            } else {
                $script:PreflightWarned = $true
                Write-Host "  " -NoNewline
                Write-Color "!" "Yellow"
                Write-Host " package.json engines.node requires $enginesNode, current Node does not match."
                Write-Host "    Install a matching Node version via fnm / nvm / volta."
            }
        }
    } catch {
        # Unparseable package.json — skip rather than false-warn
    }
}

if ($script:PreflightWarned) {
    Write-Host "  " -NoNewline
    Write-Color "i" "Blue"
    Write-Host " See docs\guides\multi-project-isolation.md for the full policy."
}

Write-Host "  " -NoNewline
Write-Color "+" "Green"
Write-Host " Prerequisites OK"
Write-Host ""

# Configure git for Windows long paths
# This is required for worktrees in projects with deeply nested file structures
Write-Color "Configuring git for Windows long paths..." "Yellow"

$longPathsEnabled = git config --get core.longpaths 2>$null
if ($longPathsEnabled -ne "true") {
    git config core.longpaths true
    Write-Host "  " -NoNewline
    Write-Color "+" "Green"
    Write-Host " Enabled core.longpaths for this repository"
    Write-Host ""
    Write-Color "NOTE: If you have very long file paths (>260 chars), you may also need to:" "Yellow"
    Write-Host "  1. Run as Admin: " -NoNewline
    Write-Color "New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -PropertyType DWORD -Force" "Cyan"
    Write-Host "  2. Or enable via Group Policy: Computer Configuration > Administrative Templates > System > Filesystem > Enable Win32 long paths"
    Write-Host ""
}
else {
    Write-Host "  " -NoNewline
    Write-Color "o" "Blue"
    Write-Host " core.longpaths already enabled"
}
Write-Host ""

# Create directory structure
Write-Color "Creating directory structure..." "Yellow"

$directories = @(
    ".claude\hooks",
    ".claude\rules",
    ".claude\commands\prd",
    ".claude\agents",
    "docs\prds",
    "docs\plans",
    "docs\solutions\build-errors",
    "docs\solutions\test-failures",
    "docs\solutions\runtime-errors",
    "docs\solutions\performance-issues",
    "docs\solutions\database-issues",
    "docs\solutions\security-issues",
    "docs\solutions\ui-bugs",
    "docs\solutions\integration-issues",
    "docs\solutions\logic-errors",
    "docs\solutions\patterns",
    ".claude\skills\ui-design\references",
    ".claude\skills\generate-image",
    ".claude\skills\release",
    ".claude\skills\council\references",
    "docs\research",
    "tests\e2e\use-cases",
    "tests\e2e\reports"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "  " -NoNewline
        Write-Color "+" "Green"
        Write-Host " Created $dir"
    }
    else {
        Write-Host "  " -NoNewline
        Write-Color "o" "Blue"
        Write-Host " $dir already exists"
    }
}

# E2E reports are ephemeral — ignore everything except this gitignore itself.
$reportsGitignore = "tests\e2e\reports\.gitignore"
if (-not (Test-Path $reportsGitignore)) {
    Set-Content -Path $reportsGitignore -Value "*`n!.gitignore`n" -NoNewline
    Write-Host "  " -NoNewline
    Write-Color "+" "Green"
    Write-Host " Created tests\e2e\reports\.gitignore (reports are ephemeral)"
}
Write-Host ""

# Copy templates
Write-Color "Copying configuration files..." "Yellow"

# Main files — CLAUDE.md and CONTINUITY.md are NEVER overwritten (user content).
# Capture pre-state so the end-of-run summary can honestly report which files
# were preserved (vs. freshly created from template in this run).
$hadClaude = Test-Path "CLAUDE.md"
$hadContinuity = Test-Path "CONTINUITY.md"

$prevForgeVersion = ""
try {
    if (Test-Path ".forge/version") {
        $prevForgeVersion = ((Get-Content ".forge/version" -Raw -ErrorAction SilentlyContinue)).Trim()
    }
} catch {}

& (Join-Path (Join-Path $ScriptDir "scripts") "materialize-adapters.ps1") -RepoRoot $ScriptDir -Target (Get-Location).Path -Scope project -Platform windows -ReleaseVersion $ForgeVersion
Write-NativeGoalCollisions (Get-Location).Path
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($prevForgeVersion -and $prevForgeVersion -ne $ForgeVersion) {
    Write-Host "FORGE_VERSION_CHANGE: $prevForgeVersion -> $ForgeVersion"
}

# Retain the v5 implementation text for Task 3 ownership recognition, but do
# not execute it beside the v6 materialized layout.
if ($false) {
if ($hadClaude) {
    Write-Host "  " -NoNewline; Write-Color "o" "Blue"; Write-Host " CLAUDE.md already exists (never overwritten - user content)"
} else {
    Copy-TemplateFile (Join-Path $ScriptDir "CLAUDE.template.md") "CLAUDE.md" "CLAUDE.md"
}
# Install state template (stable path under .claude/ -- used by /new-feature
# Pre-Flight reuse and migration helper). Always refresh this -- it's the
# canonical template, not user content.
if (-not (Test-Path ".claude")) { New-Item -ItemType Directory -Path ".claude" -Force | Out-Null }
Copy-TemplateFile (Join-Path $ScriptDir "state.template.md") ".claude\state.template.md" ".claude\state.template.md (template, stable path)"

# Volatile per-developer state (gitignored, never overwritten).
if (-not (Test-Path ".claude\local\state.md")) {
    if (-not (Test-Path ".claude\local")) { New-Item -ItemType Directory -Path ".claude\local" -Force | Out-Null }
    Copy-TemplateFile (Join-Path $ScriptDir "state.template.md") ".claude\local\state.md" ".claude\local\state.md (volatile per-developer state)"
}

# Resolve Python command (Windows uses 'python', Unix uses 'python3')
$PythonCmd = $null
if (Get-Command python -ErrorAction SilentlyContinue) { $PythonCmd = "python" }
elseif (Get-Command python3 -ErrorAction SilentlyContinue) { $PythonCmd = "python3" }

# Settings — merge on upgrade, copy otherwise.
#
# P2-3 (Codex v5.32 review): hard-fail rather than silently leaving the old
# settings.json in place. Without the merge, NEW Stop hook entries (e.g.,
# build-evidence) are never registered, and the upgraded check-state-updated.ps1
# no longer invokes build-evidence inline — silent loss of FORGE_GOAL_EVIDENCE.
#
# Codex P2 follow-up (v5.32 iter 2): also detect cases where $PythonCmd is
# truthy but the invocation FAILS — common on Windows when the resolved
# `python.exe` is the Microsoft Store alias (no-op), Python 2 (which can't
# run the script), or when merge-settings.py itself errors out. PowerShell's
# default $ErrorActionPreference does NOT abort on native command non-zero
# exits, so we must check $LASTEXITCODE explicitly.
if ($Upgrade -and (Test-Path ".claude\settings.json")) {
    Write-Color "  ^ Merging .claude\settings.json (upgrade mode)" "Yellow"
    if (-not $PythonCmd) {
        Write-Color "  X Python not found -- cannot merge settings.json safely." "Red"
        Write-Color "    Install Python 3 (https://www.python.org/downloads/) and re-run --upgrade." "Red"
        Write-Color "    Without the merge, new Stop hook entries (e.g., build-evidence) will" "Red"
        Write-Color "    NOT be registered, silently breaking /forge-goal evidence emission." "Red"
        exit 1
    }
    & $PythonCmd (Join-Path (Join-Path $ScriptDir "scripts") "merge-settings.py") (Join-Path (Join-Path $ScriptDir "settings") "settings-windows.template.json") ".claude\settings.json"
    if ($LASTEXITCODE -ne 0) {
        Write-Color "  X merge-settings.py exited $LASTEXITCODE -- settings.json was NOT updated." "Red"
        Write-Color "    Common causes on Windows:" "Red"
        Write-Color "      - 'python' resolves to the Microsoft Store alias (no real Python installed)" "Red"
        Write-Color "      - Python 2 instead of Python 3" "Red"
        Write-Color "      - merge-settings.py rejected your existing .claude/settings.json as malformed" "Red"
        Write-Color "    Install Python 3 from https://www.python.org/downloads/ and re-run --upgrade." "Red"
        Write-Color "    Without a successful merge, new Stop hook entries are NOT registered." "Red"
        exit 1
    }
} else {
    Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "settings") "settings-windows.template.json") ".claude\settings.json" ".claude\settings.json"
}

# MCP servers — merge on upgrade, copy otherwise
if ($Upgrade -and (Test-Path ".mcp.json")) {
    Write-Color "  ^ Merging .mcp.json (upgrade mode)" "Yellow"
    if ($PythonCmd) {
        & $PythonCmd (Join-Path (Join-Path $ScriptDir "scripts") "merge-settings.py") (Join-Path $ScriptDir "mcp.template.json") ".mcp.json"
    } else {
        Write-Color "  ! Python not found -- cannot merge .mcp.json. Install Python or merge manually." "Yellow"
    }
} else {
    Copy-TemplateFile (Join-Path $ScriptDir "mcp.template.json") ".mcp.json" ".mcp.json (MCP servers: Playwright + Context7)"
}

# Hooks (PowerShell versions for Windows)
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "hooks") "session-start.ps1") ".claude\hooks\session-start.ps1" ".claude\hooks\session-start.ps1"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "hooks") "check-state-updated.ps1") ".claude\hooks\check-state-updated.ps1" ".claude\hooks\check-state-updated.ps1"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "hooks") "post-tool-format.ps1") ".claude\hooks\post-tool-format.ps1" ".claude\hooks\post-tool-format.ps1"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "hooks") "pre-compact-memory.ps1") ".claude\hooks\pre-compact-memory.ps1" ".claude\hooks\pre-compact-memory.ps1"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "hooks") "check-config-change.ps1") ".claude\hooks\check-config-change.ps1" ".claude\hooks\check-config-change.ps1"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "hooks") "check-bash-safety.ps1") ".claude\hooks\check-bash-safety.ps1" ".claude\hooks\check-bash-safety.ps1"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "hooks") "check-workflow-gates.ps1") ".claude\hooks\check-workflow-gates.ps1" ".claude\hooks\check-workflow-gates.ps1"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "hooks") "auto-approve-local-writes.ps1") ".claude\hooks\auto-approve-local-writes.ps1" ".claude\hooks\auto-approve-local-writes.ps1"
# build-evidence.ps1 — read-only evidence emitter for the /forge-goal autonomous loop
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "hooks") "build-evidence.ps1") ".claude\hooks\build-evidence.ps1" ".claude\hooks\build-evidence.ps1"

# Hook lib helpers
# Install BOTH the .ps1 and .sh helpers on Windows because:
#   - .ps1 is dot-sourced by the PowerShell hooks (session-start.ps1, check-state-updated.ps1)
#   - .sh is invoked via `bash "$LIB"` from the bash code blocks in commands/new-feature.md
#     and commands/fix-bug.md. Those blocks run under Git Bash on Windows and would silently
#     fall back to DEFAULT_BRANCH=main if the .sh file weren't installed — breaking
#     master-default repos and any non-main default downstream.
$libDir = ".claude\hooks\lib"
if (-not (Test-Path $libDir)) { New-Item -ItemType Directory -Path $libDir -Force | Out-Null }
Copy-TemplateFile (Join-Path (Join-Path (Join-Path $ScriptDir "hooks") "lib") "default-branch.ps1") "$libDir\default-branch.ps1" "$libDir\default-branch.ps1 (default-branch detection helper, PowerShell)"
Copy-TemplateFile (Join-Path (Join-Path (Join-Path $ScriptDir "hooks") "lib") "default-branch.sh") "$libDir\default-branch.sh" "$libDir\default-branch.sh (default-branch detection helper, bash — used by commands/*.md preflight)"
Copy-TemplateFile (Join-Path (Join-Path (Join-Path $ScriptDir "hooks") "lib") "review-breaker.sh") "$libDir\review-breaker.sh" "$libDir\review-breaker.sh (review-loop convergence breaker, v5.54)"
Copy-TemplateFile (Join-Path (Join-Path (Join-Path $ScriptDir "hooks") "lib") "review-breaker.ps1") "$libDir\review-breaker.ps1" "$libDir\review-breaker.ps1 (review-loop convergence breaker, v5.54)"
# codex-pty shim — work around openai/codex#19945 (silent empty exit when codex
# exec runs without a controlling TTY). Both .ps1 + .sh + helper.py ship for
# cross-platform parity (ADR 0005).
Copy-TemplateFile (Join-Path (Join-Path (Join-Path $ScriptDir "hooks") "lib") "codex-pty.ps1") "$libDir\codex-pty.ps1" "$libDir\codex-pty.ps1 (codex PTY shim, openai/codex#19945)"
Copy-TemplateFile (Join-Path (Join-Path (Join-Path $ScriptDir "hooks") "lib") "codex-pty.sh") "$libDir\codex-pty.sh" "$libDir\codex-pty.sh (Codex PTY shim, bash)"
Copy-TemplateFile (Join-Path (Join-Path (Join-Path $ScriptDir "hooks") "lib") "codex-pty-helper.py") "$libDir\codex-pty-helper.py" "$libDir\codex-pty-helper.py (Python pty.fork helper for the shim)"
}

# ADRs belong to the downstream project. Retire only byte-exact copies of
# Forge's internal decisions; preserve customized and same-numbered project
# ADRs. Then seed neutral project scaffolding if absent.
if (-not (Test-Path "docs\adr")) { New-Item -ItemType Directory -Path "docs\adr" -Force | Out-Null }
$forgeAdrSourceDir = Join-Path (Join-Path $ScriptDir "docs") "adr"
$forgeAdrSeeds = @((Join-Path $forgeAdrSourceDir "README.md")) + @(
    Get-ChildItem -LiteralPath $forgeAdrSourceDir -File | Where-Object { $_.Name -match '^\d{4}-.+\.md$' } | ForEach-Object { $_.FullName }
)
foreach ($forgeAdrSource in $forgeAdrSeeds) {
    $forgeAdrTarget = Join-Path "docs\adr" (Split-Path -Leaf $forgeAdrSource)
    if ((Test-Path -LiteralPath $forgeAdrTarget -PathType Leaf) -and
        -not [string]::Equals((Resolve-Path -LiteralPath $forgeAdrSource).Path, (Resolve-Path -LiteralPath $forgeAdrTarget).Path, [StringComparison]::OrdinalIgnoreCase) -and
        (Get-FileHash -Algorithm SHA256 -LiteralPath $forgeAdrSource).Hash -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $forgeAdrTarget).Hash) {
        Remove-Item -LiteralPath $forgeAdrTarget -Force
        Write-Host "  Retired exact Forge-internal ADR seed: $forgeAdrTarget"
    }
}
if (-not (Test-Path -LiteralPath "docs\adr\template.md" -PathType Leaf)) {
    Copy-TemplateFile (Join-Path $forgeAdrSourceDir "template.md") "docs\adr\template.md" "docs\adr\template.md"
}
if (-not (Test-Path -LiteralPath "docs\adr\README.md" -PathType Leaf)) {
    Copy-TemplateFile (Join-Path (Join-Path (Join-Path $ScriptDir "templates") "project-adr") "README.md") "docs\adr\README.md" "docs\adr\README.md (project ADR index)"
}

# Append .claude/local/ to root .gitignore if not already present (idempotent).
if (Test-Path ".gitignore") {
    $gitignoreContent = Get-Content ".gitignore" -ErrorAction SilentlyContinue
    if (-not ($gitignoreContent -contains ".claude/local/")) {
        Add-Content -Path ".gitignore" -Value ""
        Add-Content -Path ".gitignore" -Value "# Volatile per-developer workflow state (PR #2 / continuity-split)"
        Add-Content -Path ".gitignore" -Value ".claude/local/"
        Write-Host "  " -NoNewline; Write-Color "+" "Green"; Write-Host " Added .claude/local/ to .gitignore"
    }
    if (-not ($gitignoreContent -contains ".forge/local/")) { Add-Content -Path ".gitignore" -Value ".forge/local/" }
} else {
    @"
# Volatile per-developer workflow state (PR #2 / continuity-split)
.claude/local/
.forge/local/
"@ | Set-Content ".gitignore"
    Write-Host "  " -NoNewline; Write-Color "+" "Green"; Write-Host " Created .gitignore with .claude/local/"
}

if ($false) {
# Agents
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "agents") "verify-app.md") ".claude\agents\verify-app.md" ".claude\agents\verify-app.md"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "agents") "verify-e2e.md") ".claude\agents\verify-e2e.md" ".claude\agents\verify-e2e.md"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "agents") "council-advisor.md") ".claude\agents\council-advisor.md" ".claude\agents\council-advisor.md"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "agents") "research-first.md") ".claude\agents\research-first.md" ".claude\agents\research-first.md"

# Skills (tech-agnostic)
$releaseDir = Join-Path (Join-Path (Join-Path $ScriptDir "skills") "release")
Copy-TemplateFile (Join-Path $releaseDir "SKILL.template.md") ".claude\skills\release\SKILL.md" ".claude\skills\release\SKILL.md"

# Engineering Council skill (tech-agnostic) — multi-perspective decision analysis
$councilDir = Join-Path (Join-Path (Join-Path $ScriptDir "skills") "council")
$councilRefDir = Join-Path $councilDir "references"
Copy-TemplateFile (Join-Path $councilDir "SKILL.template.md") ".claude\skills\council\SKILL.md" ".claude\skills\council\SKILL.md"
Copy-TemplateFile (Join-Path $councilRefDir "advisors.md") ".claude\skills\council\references\advisors.md" ".claude\skills\council\references\advisors.md"
Copy-TemplateFile (Join-Path $councilRefDir "output-schema.md") ".claude\skills\council\references\output-schema.md" ".claude\skills\council\references\output-schema.md"
Copy-TemplateFile (Join-Path $councilRefDir "peer-review-protocol.md") ".claude\skills\council\references\peer-review-protocol.md" ".claude\skills\council\references\peer-review-protocol.md"

# Commands - Workflow (ENFORCED)
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "commands") "new-feature.md") ".claude\commands\new-feature.md" ".claude\commands\new-feature.md"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "commands") "fix-bug.md") ".claude\commands\fix-bug.md" ".claude\commands\fix-bug.md"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "commands") "quick-fix.md") ".claude\commands\quick-fix.md" ".claude\commands\quick-fix.md"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "commands") "finish-branch.md") ".claude\commands\finish-branch.md" ".claude\commands\finish-branch.md"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "commands") "review-pr-comments.md") ".claude\commands\review-pr-comments.md" ".claude\commands\review-pr-comments.md"

# Commands - PRD
Copy-TemplateFile (Join-Path (Join-Path (Join-Path $ScriptDir "commands") "prd") "discuss.md") ".claude\commands\prd\discuss.md" ".claude\commands\prd\discuss.md"
Copy-TemplateFile (Join-Path (Join-Path (Join-Path $ScriptDir "commands") "prd") "create.md") ".claude\commands\prd\create.md" ".claude\commands\prd\create.md"

# Rules based on tech stack
Write-Host ""
Write-Color "Copying rules for $Tech..." "Yellow"

# Common rules
# Common rules (apply to all tech stacks)
$commonRules = @("security.md", "skill-audit.md", "api-design.md", "testing.md", "principles.md", "workflow.md", "worktree-policy.md", "critical-rules.md", "memory.md")
foreach ($rule in $commonRules) {
    Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "rules") $rule) ".claude\rules\$rule" ".claude\rules\$rule"
}

# Tech-specific rules
switch ($Tech) {
    "python" {
        Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "rules") "python-style.md") ".claude\rules\python-style.md" ".claude\rules\python-style.md"
        Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "rules") "database.md") ".claude\rules\database.md" ".claude\rules\database.md"
    }
    "typescript" {
        Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "rules") "typescript-style.md") ".claude\rules\typescript-style.md" ".claude\rules\typescript-style.md"
        Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "rules") "frontend-design.md") ".claude\rules\frontend-design.md" ".claude\rules\frontend-design.md"
        # UI Design skill (auto-triggers for frontend work) — all 10 references
        $skillDir = Join-Path (Join-Path (Join-Path $ScriptDir "skills") "ui-design")
        $refsDir = Join-Path $skillDir "references"
        Copy-TemplateFile (Join-Path $skillDir "SKILL.template.md") ".claude\skills\ui-design\SKILL.md" ".claude\skills\ui-design\SKILL.md"
        Copy-TemplateFile (Join-Path $refsDir "animation-techniques.md") ".claude\skills\ui-design\references\animation-techniques.md" ".claude\skills\ui-design\references\animation-techniques.md"
        Copy-TemplateFile (Join-Path $refsDir "typography-and-color.md") ".claude\skills\ui-design\references\typography-and-color.md" ".claude\skills\ui-design\references\typography-and-color.md"
        Copy-TemplateFile (Join-Path $refsDir "polish-checklist.md") ".claude\skills\ui-design\references\polish-checklist.md" ".claude\skills\ui-design\references\polish-checklist.md"
        Copy-TemplateFile (Join-Path $refsDir "media-assets.md") ".claude\skills\ui-design\references\media-assets.md" ".claude\skills\ui-design\references\media-assets.md"
        Copy-TemplateFile (Join-Path $refsDir "industry-design-guide.md") ".claude\skills\ui-design\references\industry-design-guide.md" ".claude\skills\ui-design\references\industry-design-guide.md"
        Copy-TemplateFile (Join-Path $refsDir "ux-antipatterns.md") ".claude\skills\ui-design\references\ux-antipatterns.md" ".claude\skills\ui-design\references\ux-antipatterns.md"
        Copy-TemplateFile (Join-Path $refsDir "landing-patterns.md") ".claude\skills\ui-design\references\landing-patterns.md" ".claude\skills\ui-design\references\landing-patterns.md"
        Copy-TemplateFile (Join-Path $refsDir "21st-dev-components.md") ".claude\skills\ui-design\references\21st-dev-components.md" ".claude\skills\ui-design\references\21st-dev-components.md"
        Copy-TemplateFile (Join-Path $refsDir "product-ui-patterns.md") ".claude\skills\ui-design\references\product-ui-patterns.md" ".claude\skills\ui-design\references\product-ui-patterns.md"
        Copy-TemplateFile (Join-Path $refsDir "trust-first-patterns.md") ".claude\skills\ui-design\references\trust-first-patterns.md" ".claude\skills\ui-design\references\trust-first-patterns.md"
        # Image generation skill (Gemini API — checks docs for current model)
        $genImgDir = Join-Path (Join-Path (Join-Path $ScriptDir "skills") "generate-image")
        Copy-TemplateFile (Join-Path $genImgDir "SKILL.template.md") ".claude\skills\generate-image\SKILL.md" ".claude\skills\generate-image\SKILL.md"
    }
    default {
        Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "rules") "python-style.md") ".claude\rules\python-style.md" ".claude\rules\python-style.md"
        Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "rules") "typescript-style.md") ".claude\rules\typescript-style.md" ".claude\rules\typescript-style.md"
        Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "rules") "database.md") ".claude\rules\database.md" ".claude\rules\database.md"
        Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "rules") "frontend-design.md") ".claude\rules\frontend-design.md" ".claude\rules\frontend-design.md"
        # UI Design skill (auto-triggers for frontend work) — all 10 references
        $skillDir = Join-Path (Join-Path (Join-Path $ScriptDir "skills") "ui-design")
        $refsDir = Join-Path $skillDir "references"
        Copy-TemplateFile (Join-Path $skillDir "SKILL.template.md") ".claude\skills\ui-design\SKILL.md" ".claude\skills\ui-design\SKILL.md"
        Copy-TemplateFile (Join-Path $refsDir "animation-techniques.md") ".claude\skills\ui-design\references\animation-techniques.md" ".claude\skills\ui-design\references\animation-techniques.md"
        Copy-TemplateFile (Join-Path $refsDir "typography-and-color.md") ".claude\skills\ui-design\references\typography-and-color.md" ".claude\skills\ui-design\references\typography-and-color.md"
        Copy-TemplateFile (Join-Path $refsDir "polish-checklist.md") ".claude\skills\ui-design\references\polish-checklist.md" ".claude\skills\ui-design\references\polish-checklist.md"
        Copy-TemplateFile (Join-Path $refsDir "media-assets.md") ".claude\skills\ui-design\references\media-assets.md" ".claude\skills\ui-design\references\media-assets.md"
        Copy-TemplateFile (Join-Path $refsDir "industry-design-guide.md") ".claude\skills\ui-design\references\industry-design-guide.md" ".claude\skills\ui-design\references\industry-design-guide.md"
        Copy-TemplateFile (Join-Path $refsDir "ux-antipatterns.md") ".claude\skills\ui-design\references\ux-antipatterns.md" ".claude\skills\ui-design\references\ux-antipatterns.md"
        Copy-TemplateFile (Join-Path $refsDir "landing-patterns.md") ".claude\skills\ui-design\references\landing-patterns.md" ".claude\skills\ui-design\references\landing-patterns.md"
        Copy-TemplateFile (Join-Path $refsDir "21st-dev-components.md") ".claude\skills\ui-design\references\21st-dev-components.md" ".claude\skills\ui-design\references\21st-dev-components.md"
        Copy-TemplateFile (Join-Path $refsDir "product-ui-patterns.md") ".claude\skills\ui-design\references\product-ui-patterns.md" ".claude\skills\ui-design\references\product-ui-patterns.md"
        Copy-TemplateFile (Join-Path $refsDir "trust-first-patterns.md") ".claude\skills\ui-design\references\trust-first-patterns.md" ".claude\skills\ui-design\references\trust-first-patterns.md"
        # Image generation skill (Gemini API — checks docs for current model)
        $genImgDir = Join-Path (Join-Path (Join-Path $ScriptDir "skills") "generate-image")
        Copy-TemplateFile (Join-Path $genImgDir "SKILL.template.md") ".claude\skills\generate-image\SKILL.md" ".claude\skills\generate-image\SKILL.md"
    }
}
}

# Playwright framework templates (opt-in via -WithPlaywright)
if ($WithPlaywright) {
    Write-Host ""
    Write-Color "Installing Playwright framework templates..." "Yellow"

    # ------------------------------------------------------------------
    # Determine where Playwright lives.
    # Monorepos typically have package.json inside a frontend subdirectory
    # (frontend/, apps/web/, web/, client/). Flat repos have it at root.
    # Users can override with -PlaywrightDir <path>.
    # ------------------------------------------------------------------
    if ($PlaywrightDir) {
        $PwDir = $PlaywrightDir
        Write-Host "  " -NoNewline
        Write-Color "->" "Blue"
        Write-Host " Using explicit -PlaywrightDir: $PwDir"
    } else {
        # Auto-detect: ONLY commit to a subdir if exactly one candidate matches.
        $candidates = @()
        foreach ($c in @("frontend", "apps\web", "web", "client")) {
            if (Test-Path (Join-Path $c "package.json")) {
                $candidates += $c
            }
        }

        if ($candidates.Count -eq 1) {
            $PwDir = $candidates[0]
            Write-Host "  " -NoNewline
            Write-Color "+" "Green"
            Write-Host " Detected frontend at $PwDir - scaffolding Playwright there."
            Write-Host "    (override with -PlaywrightDir <path> if that's wrong)"
        } elseif ($candidates.Count -gt 1) {
            Write-Host "  " -NoNewline
            Write-Color "!" "Yellow"
            Write-Host "  Multiple frontend candidates found: $($candidates -join ', ')"
            Write-Host "     Scaffolding at repo root to avoid picking wrong. Override with -PlaywrightDir <path>."
            $PwDir = "."
        } else {
            $PwDir = "."
            Write-Host "  " -NoNewline
            Write-Color "->" "Blue"
            Write-Host " No frontend subdirectory detected - scaffolding at repo root."
        }
    }

    if ($PwDir -ne "." -and -not (Test-Path $PwDir)) {
        New-Item -ItemType Directory -Path $PwDir -Force | Out-Null
        Write-Host "  " -NoNewline
        Write-Color "+" "Green"
        Write-Host " Created $PwDir\"
    }

    $PwSpecsDir = Join-Path $PwDir "tests\e2e\specs"
    $PwFixturesDir = Join-Path $PwDir "tests\e2e\fixtures"
    $PwAuthDir = Join-Path $PwDir "tests\e2e\.auth"

    if (-not (Test-Path $PwSpecsDir)) {
        New-Item -ItemType Directory -Path $PwSpecsDir -Force | Out-Null
        Write-Host "  " -NoNewline
        Write-Color "+" "Green"
        Write-Host " Created $PwSpecsDir (for graduated .spec.ts files)"
    }

    $pwTemplateDir = Join-Path (Join-Path $ScriptDir "templates") "playwright"
    $ciTemplateDir = Join-Path (Join-Path $ScriptDir "templates") "ci-workflows"

    # Playwright config
    Copy-TemplateFile (Join-Path $pwTemplateDir "playwright.config.template.ts") (Join-Path $PwDir "playwright.config.ts") "$PwDir\playwright.config.ts"

    # Auth fixture
    if (-not (Test-Path $PwFixturesDir)) {
        New-Item -ItemType Directory -Path $PwFixturesDir -Force | Out-Null
    }
    Copy-TemplateFile (Join-Path $pwTemplateDir "auth.fixture.template.ts") (Join-Path $PwFixturesDir "auth.ts") "$PwFixturesDir\auth.ts"

    # Auth storage directory - gitignored because it contains credentials
    if (-not (Test-Path $PwAuthDir)) {
        New-Item -ItemType Directory -Path $PwAuthDir -Force | Out-Null
    }
    $PwAuthGitignore = Join-Path $PwAuthDir ".gitignore"
    if (-not (Test-Path $PwAuthGitignore)) {
        @"
# Auth storage state contains credentials - never commit
*
!.gitignore
"@ | Set-Content -Path $PwAuthGitignore -NoNewline -Encoding UTF8
        Write-Host "  " -NoNewline
        Write-Color "+" "Green"
        Write-Host " Created $PwAuthGitignore (credentials protected)"
    }

    # Persist the chosen PW_DIR so workflow commands (new-feature, fix-bug)
    # can pick it up in Phase 5.4b framework detection and dep-install loops.
    if (-not (Test-Path ".claude")) {
        New-Item -ItemType Directory -Path ".claude" -Force | Out-Null
    }
    $PwDir | Set-Content -Path ".claude\playwright-dir" -NoNewline -Encoding UTF8
    Write-Host "  " -NoNewline
    Write-Color "+" "Green"
    Write-Host " Recorded Playwright dir in .claude\playwright-dir ($PwDir)"

    # CI workflow reference (NOT auto-activated).
    # Stamp PW_DIR into the workflow so working-directory matches. Use a literal
    # placeholder replacement to avoid regex metacharacter interpretation in
    # user paths (& and | are safe in .NET -replace, but backslashes / dollar-
    # signs are not — using [regex]::Escape on the pattern and a literal on the
    # replacement). Preserve user-edited files on non-force reruns (matches
    # Copy-TemplateFile semantics).
    if (-not (Test-Path "docs\ci-templates")) {
        New-Item -ItemType Directory -Path "docs\ci-templates" -Force | Out-Null
    }
    $e2eTemplate = Join-Path $ciTemplateDir "e2e.yml"
    $readmeTemplate = Join-Path $ciTemplateDir "README.md"
    $PwDirForCI = $PwDir -replace '\\', '/'  # YAML uses forward slashes even on Windows

    function Stamp-CiTemplate($src, $dest, $desc) {
        if (-not (Test-Path $src)) { return }
        if ((Test-Path $dest) -and (-not $Force)) {
            Write-Host "  " -NoNewline
            Write-Color "o" "Blue"
            Write-Host " $desc already exists (use -Upgrade to refresh)"
            return
        }
        # Pattern: literal placeholder (no regex metachars in __PLAYWRIGHT_DIR__).
        # Replacement: wrapped in [System.Text.RegularExpressions.Regex]::Escape
        # would be wrong because -replace's replacement string interprets `$1` etc.
        # Safer: use .NET String.Replace which does no regex interpretation.
        $content = (Get-Content $src -Raw).Replace('__PLAYWRIGHT_DIR__', $PwDirForCI)
        $content | Set-Content -Path $dest -NoNewline -Encoding UTF8
        Write-Host "  " -NoNewline
        Write-Color "+" "Green"
        Write-Host " Created $desc (working-directory stamped: $PwDirForCI)"
    }

    Stamp-CiTemplate $e2eTemplate "docs\ci-templates\e2e.yml" "docs\ci-templates\e2e.yml"
    Stamp-CiTemplate $readmeTemplate "docs\ci-templates\README.md" "docs\ci-templates\README.md"

    if ($PwDir -eq ".") {
        $cdHint = ""
        $pwRun = "pnpm exec playwright test"
    } else {
        $cdHint = "cd $PwDir; "
        $pwRun = "cd $PwDir; pnpm exec playwright test"
    }

    Write-Host ""
    Write-Color "Playwright templates installed into $PwDir." "Green"
    Write-Color "Next steps to complete Playwright setup:" "Yellow"
    Write-Host "  1. Install the framework: " -NoNewline
    Write-Color "$cdHint`pnpm add -D @playwright/test" "Blue"
    Write-Host "     (or npm: " -NoNewline
    Write-Color "$cdHint`npm install --save-dev @playwright/test" "Blue"
    Write-Host ")"
    Write-Host "  2. Install browsers:      " -NoNewline
    Write-Color "$cdHint`pnpm exec playwright install" "Blue"
    Write-Host "  3. Review " -NoNewline
    Write-Color "$PwDir\playwright.config.ts" "Blue"
    Write-Host " - set baseURL and uncomment webServer if needed"
    Write-Host "  4. (Optional) Activate CI:"
    Write-Host "     " -NoNewline
    Write-Color "mkdir .github\workflows; cp docs\ci-templates\e2e.yml .github\workflows\e2e.yml" "Blue"
    Write-Host "     Note: CI template uses pnpm with working-directory=$PwDirForCI - adjust if needed"
    Write-Host "  5. Configure auth via env vars: TEST_USER_EMAIL + TEST_USER_PASSWORD (preferred)"
    Write-Host "     TEST_API_KEY is supported but insecure - see tests\e2e\fixtures\auth.ts"
    Write-Host "  6. Run tests: " -NoNewline
    Write-Color $pwRun "Blue"
}

Write-Host ""

# Create CHANGELOG only if it doesn't exist — NEVER overwrite on -Upgrade.
# docs\CHANGELOG.md is user content (each project's own release history). Same
# policy as CLAUDE.md and CONTINUITY.md: templates initialize the file on first
# install and never touch it afterward.
if (-not (Test-Path "docs\CHANGELOG.md")) {
    Write-Color "Creating docs\CHANGELOG.md..." "Yellow"

    $changelogLines = @(
        "# Changelog",
        "",
        "All notable changes to $Project will be documented in this file.",
        "",
        "## [Unreleased]",
        "",
        "### Added",
        "- Initial project setup with Claude Code configuration",
        "",
        "### Changed",
        "",
        "### Fixed",
        "",
        "### Removed",
        "",
        "---",
        "",
        "## Format",
        "",
        "Each entry should include:",
        "- Date (YYYY-MM-DD)",
        "- Brief description",
        "- Related issue/PR if applicable"
    )

    $changelogLines | Out-File -FilePath "docs\CHANGELOG.md" -Encoding UTF8
    Write-Host "  " -NoNewline
    Write-Color "+" "Green"
    Write-Host " Created docs\CHANGELOG.md"
}
else {
    Write-Host "  " -NoNewline
    Write-Color "o" "Blue"
    Write-Host " docs\CHANGELOG.md already exists"
}

# The v6 marker materializer owns only the bounded Forge block. Text outside
# that block is user-owned bytes and is never subject to project-name rewriting.

Write-Host ""
if ($Upgrade) {
    Write-Color "============================================" "Green"
    Write-Color "  Upgrade Complete!" "Green"
    Write-Color "============================================" "Green"
    Write-Host ""
    Write-Color "What was updated:" "Yellow"
    Write-Host ""
    Write-Host "  .forge/                  Canonical workflows, rules, hooks, agents, skills, and state template"
    Write-Host "  CLAUDE.md / AGENTS.md    Bounded host adapters; personal text outside Forge markers preserved"
    Write-Host "  .claude/                 Claude Code commands, agents, skills, hooks, and merged settings"
    Write-Host "  .codex/                  Codex agents, hooks, and merged configuration"
    Write-Host "  .agents/                 Codex workflow and skill adapters"
    Write-Host "  .mcp.json                Shared MCP servers (merged - your customizations kept)"
    Write-Host ""
    # Drive "Not touched" from pre-copy booleans so we don't falsely claim a
    # file was preserved when this run actually recreated it from template.
    if ($hadClaude -or $hadContinuity) {
        Write-Color "Not touched:" "Yellow"
        Write-Host ""
        if ($hadClaude) {
            Write-Host "  CLAUDE.md                Your project description (preserved)"
        }
        if ($hadContinuity) {
            Write-Host "  CONTINUITY.md            Your task state (preserved)"
        }
        Write-Host ""
    }
    Write-Color "Next steps:" "Yellow"
    Write-Host ""
    Write-Host "1. " -NoNewline
    Write-Color "Verify everything works" "Blue"
    Write-Host ":"
    Write-Host ""
    Write-Host "   /hooks       -> Should show: SessionStart, Stop, PreToolUse, PostToolUse, PreCompact, SubagentStop, ConfigChange"
    Write-Host "   /help        -> Should show Forge workflows for both installed hosts"
    Write-Host ""
    Write-Host "2. " -NoNewline
    Write-Color "Commit and push" "Blue"
    Write-Host ":"
    Write-Host ""
    Write-Host "   git add .forge/ .claude/ .codex/ .agents/ .mcp.json CLAUDE.md AGENTS.md docs/"
    Write-Host "   git commit -m `"chore: upgrade Forge harness`""
    Write-Host "   git push"
    Write-Host ""
    if ($hadContinuity) {
        Write-Color "! Legacy CONTINUITY.md detected." "Yellow"
        Write-Host "  Forge 6 does not rewrite this mixed-content legacy file automatically."
        Write-Host "  Preview the authoritative upgrade inventory before changing anything:"
        Write-Host ""
        Write-Host "    .\setup.ps1 -Force -DryRun"
        Write-Host ""
        Write-Host "  Move durable facts to project instructions, decisions to docs/adr/, and"
        Write-Host "  active state to .forge/local/state.md; then archive or remove CONTINUITY.md."
        Write-Host ""
    }
    if ($hadClaude -and $hadContinuity) {
        Write-Color "Upgrade done! Your CLAUDE.md and CONTINUITY.md were preserved; run -Force -DryRun to reconcile legacy continuity." "Green"
    } elseif ($hadClaude) {
        Write-Color "Upgrade done! Your CLAUDE.md was preserved (user content)." "Green"
    } elseif ($hadContinuity) {
        Write-Color "Upgrade done! Your CONTINUITY.md was preserved; run -Force -DryRun to reconcile legacy continuity." "Green"
    } else {
        Write-Color "Upgrade done!" "Green"
    }

    # 5.17: soft tip recommending Claude-driven CLAUDE.md reconciliation when
    # the user's CLAUDE.md was preserved. Replaces the per-file inline drift
    # hint (cry-wolf -- fired every upgrade regardless of actual drift). Uses
    # the full Variant B prompt from the migration script for consistency,
    # including the @CONTINUITY.md dangling-import cleanup clause. The "Full
    # guide" reference uses an absolute path to the Forge clone so it resolves
    # correctly when users run setup.ps1 -Upgrade from inside their project.
    # 5.18: prompt expanded to enumerate ALL CONTINUITY reference types
    # (tree diagrams, prose pointers, labels) -- field bug where a downstream project
    # leftover refs at line 102 (tree) and line 212 (prose) survived because
    # the prior single-clause prompt only addressed the @-import line.
    if ($hadClaude) {
        Write-Host ""
        Write-Host "Tip:" -ForegroundColor Blue -NoNewline
        Write-Host " ask Claude to reconcile your CLAUDE.md against the latest template:"
        Write-Host ""
        Write-Host "  `"Reconcile my CLAUDE.md against $ScriptDir/CLAUDE.template.md."
        Write-Host "   Port any new template sections, preserving my project-specific content."
        Write-Host ""
        Write-Host "   Then scan the ENTIRE file and remove every dangling reference to"
        Write-Host "   CONTINUITY.md left over from before the 5.15 migration. Look for:"
        Write-Host "     - @CONTINUITY.md import lines (usually at the top)"
        Write-Host "     - File-tree diagrams that list CONTINUITY.md as a project file"
        Write-Host "     - Prose pointers like 'see CONTINUITY', 'in CONTINUITY.md', '(CONTINUITY)'"
        Write-Host "     - Comments or labels that reference CONTINUITY.md as a location"
        Write-Host ""
        Write-Host "   CONTINUITY.md no longer exists -- its content moved to CLAUDE.md"
        Write-Host "   (durable), docs/adr/ (decisions), and .forge/local/state.md"
        Write-Host "   (volatile). Remove these references; the 'preserve project-specific"
        Write-Host "   content' rule does NOT apply to CONTINUITY pointers -- they are"
        Write-Host "   stale infrastructure references.`""
        Write-Host ""
        Write-Host "  (Full guide: $ScriptDir/docs/guides/upgrading.md)"
        Write-Host ""
    }
} else {
    Write-Color "============================================" "Green"
    Write-Color "  Setup Complete!" "Green"
    Write-Color "============================================" "Green"
    Write-Host ""
    Write-Color "What was created:" "Yellow"
    Write-Host ""
    Write-Host "  .forge/                  Canonical workflows, rules, hooks, agents, skills, and local state"
    Write-Host "  .forge/local/state.md    Per-worktree workflow checkpoint (gitignored)"
    Write-Host "  CLAUDE.md / AGENTS.md    Thin Claude Code and Codex root adapters"
    Write-Host "  .claude/                 Claude Code commands, agents, skills, hooks, and settings"
    Write-Host "  .codex/                  Codex agents, hooks, and configuration"
    Write-Host "  .agents/                 Codex workflow and skill adapters"
    Write-Host "  .mcp.json                Shared MCP servers (Playwright + Context7)"
    Write-Host "  docs/adr/                Architecture decisions and index"
    Write-Host "  docs/                    Changelog, plans, PRDs, research, and solutions"
    Write-Host ""
    Write-Color "Optional host integration enabled in .claude\settings.json:" "Yellow"
    Write-Host ""
    Write-Host "  - frontend-design          (optional Claude Code UI integration)"
    Write-Host ""
    Write-Color "Next steps:" "Yellow"
    Write-Host ""
    Write-Host "1. " -NoNewline
    Write-Color "Verify both installed host surfaces" "Blue"
    Write-Host ":"
    Write-Host ""
    Write-Host "   /hooks       -> Should show: SessionStart, Stop, PreToolUse, PostToolUse, PreCompact, SubagentStop, ConfigChange"
    Write-Host "   /help        -> Claude should show Forge commands; Codex should show matching skills such as `$fix-bug"
    Write-Host "   & '$ScriptDir\scripts\verify-runtime.ps1' discovery -ProjectRoot (Get-Location).Path"
    Write-Host ""
    Write-Host "2. " -NoNewline
    Write-Color "Commit the shared harness (.forge/local/ remains gitignored)" "Blue"
    Write-Host ":"
    Write-Host ""
    Write-Host "   git add .forge/ .claude/ .codex/ .agents/ .mcp.json CLAUDE.md AGENTS.md docs/"
    Write-Host "   git commit -m `"chore: add Forge engineering harness`""
    Write-Host "   git push"
    Write-Host ""
    Write-Color "Harness materialized for Claude Code and Codex." "Green"
    Write-Color "Runtime readiness remains BLOCKED until the printed verify/qualify commands pass." "Yellow"
}
