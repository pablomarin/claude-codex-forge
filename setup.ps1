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

    [Alias("u")]
    [switch]$Upgrade,

    [switch]$Migrate,

    [Alias("g")]
    [switch]$Global,

    [Alias("w")]
    [switch]$WithPlaywright,

    [string]$PlaywrightDir
)

# Upgrade implies force for hooks/commands/rules
if ($Upgrade) { $Force = $true }

# Script directory (where templates live)
$ScriptDir = $PSScriptRoot

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
    Write-Host "Set up Claude Code configuration for a project or globally."
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -h, -Help           Show this help message"
    Write-Host "  -p, -Project NAME   Project name (default: directory name)"
    Write-Host "  -t, -Tech STACK     Tech stack: python, typescript, fullstack (default: fullstack)"
    Write-Host "  -f, -Force          Overwrite existing files"
    Write-Host "  -Migrate            Migrate legacy CONTINUITY.md content to the new structure"
    Write-Host "  -g, -Global         Set up global memory system (~/.claude/)"
    Write-Host "  -w, -WithPlaywright Install Playwright framework templates (requires -Tech fullstack or typescript)"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\setup.ps1                          # Setup with defaults"
    Write-Host "  .\setup.ps1 -p `"My Project`"          # Custom project name"
    Write-Host "  .\setup.ps1 -t python                # Python-only project"
    Write-Host "  .\setup.ps1 -f                       # Force overwrite existing files"
    Write-Host "  .\setup.ps1 -Migrate                 # Migrate CONTINUITY.md to .claude/local/state.md + ADRs"
    Write-Host "  .\setup.ps1 -Global                  # Set up global memory (run once per machine)"
    Write-Host "  .\setup.ps1 -Global -f               # Force overwrite global settings"
    Write-Host "  .\setup.ps1 -Tech fullstack -WithPlaywright  # Install Playwright framework templates"
}

# Show help if requested
if ($Help) {
    Show-Usage
    exit 0
}

# --- Migration dispatch (PR #2 / continuity-split) -------------------------
# Migration runs as a SEPARATE script for review hygiene. The logic lives at
# $ScriptDir\scripts\migrate-continuity.ps1 -- not embedded here.
if ($Migrate) {
    $migrateHelper = Join-Path (Join-Path $ScriptDir "scripts") "migrate-continuity.ps1"
    if (-not (Test-Path $migrateHelper)) {
        [Console]::Error.WriteLine("x Migration helper not found at $migrateHelper")
        [Console]::Error.WriteLine("  Your Forge clone may be incomplete. Re-clone from https://github.com/pablomarin/claude-codex-forge")
        exit 1
    }
    & $migrateHelper
    exit $LASTEXITCODE
}

# Copy function with force check
function Copy-TemplateFile {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Description
    )

    if (-not (Test-Path $Source)) {
        Write-Host "  " -NoNewline
        Write-Color "x" "Red"
        Write-Host " Template not found: $Source"
        return
    }

    if ((Test-Path $Destination) -and (-not $Force)) {
        Write-Host "  " -NoNewline
        Write-Color "o" "Blue"
        Write-Host " $Description already exists (use -f to overwrite)"
        return
    }

    # Ensure parent directory exists
    $parentDir = Split-Path -Parent $Destination
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    Copy-Item -Path $Source -Destination $Destination -Force
    Write-Host "  " -NoNewline
    Write-Color "+" "Green"
    Write-Host " Created $Description"
}

# ============================================================================
# GLOBAL SETUP (-Global flag)
# ============================================================================
if ($Global) {
    Write-Color "============================================" "Blue"
    Write-Color "  Claude Code Global Setup" "Blue"
    Write-Color "============================================" "Blue"
    Write-Host ""
    Write-Host "This sets up Claude Code's memory system for " -NoNewline
    Write-Color "ALL" "Green"
    Write-Host " your projects."
    Write-Host "After this, Claude will remember learnings across sessions and projects."
    Write-Host ""

    # Create global directories
    Write-Color "Step 1: Creating global directories..." "Yellow"

    $globalDirs = @(
        (Join-Path $HOME ".claude"),
        (Join-Path (Join-Path $HOME ".claude") "hooks"),
        (Join-Path (Join-Path $HOME ".claude") "rules")
    )

    foreach ($dir in $globalDirs) {
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
    Write-Host ""

    # Copy global CLAUDE.md
    Write-Color "Step 2: Installing global configuration..." "Yellow"
    Write-Host "  These files tell Claude how to manage its memory."
    Copy-TemplateFile (Join-Path $ScriptDir "GLOBAL-CLAUDE.template.md") (Join-Path (Join-Path $HOME ".claude") "CLAUDE.md") "~\.claude\CLAUDE.md (global instructions)"

    # Copy global hooks
    Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "hooks") "pre-compact-memory.ps1") (Join-Path (Join-Path (Join-Path $HOME ".claude") "hooks") "pre-compact-memory.ps1") "~\.claude\hooks\pre-compact-memory.ps1"

    # Merge global hooks into existing settings (preserves user's plugins, statusLine, etc.)
    $globalSettings = Join-Path (Join-Path $HOME ".claude") "settings.json"
    $templateSettings = Join-Path (Join-Path $ScriptDir "settings") "global-settings.template.json"
    if (Test-Path $globalSettings) {
        try {
            $existing = Get-Content $globalSettings -Raw | ConvertFrom-Json
            $template = Get-Content $templateSettings -Raw | ConvertFrom-Json
            # Merge just the hooks key, preserving everything else
            $existing | Add-Member -MemberType NoteProperty -Name "hooks" -Value $template.hooks -Force
            $existing | ConvertTo-Json -Depth 10 | Set-Content $globalSettings -Encoding UTF8
            Write-Host "  " -NoNewline
            Write-Color "+" "Green"
            Write-Host " Merged hooks into existing ~\.claude\settings.json (your settings preserved)"
        }
        catch {
            Write-Host "  " -NoNewline
            Write-Color "!" "Yellow"
            Write-Host " Could not merge hooks. Manually add hooks from:"
            Write-Host "    $templateSettings"
        }
    }
    else {
        Copy-TemplateFile $templateSettings $globalSettings "~\.claude\settings.json (global hooks)"
    }

    Write-Host ""
    Write-Color "============================================" "Green"
    Write-Color "  Global Setup Complete!" "Green"
    Write-Color "============================================" "Green"
    Write-Host ""
    Write-Color "What was created:" "Yellow"
    Write-Host ""
    Write-Host "  ~\.claude\CLAUDE.md         Instructions that tell Claude how to use its memory"
    Write-Host "  ~\.claude\settings.json     Hooks that auto-save learnings before context loss"
    Write-Host "  ~\.claude\hooks\            Scripts that provide context to memory hooks"
    Write-Host "  ~\.claude\rules\            Personal rules that apply to all your projects"
    Write-Host ""
    Write-Color "What this means:" "Yellow"
    Write-Host ""
    Write-Host "  Claude will now:"
    Write-Host "  - Save bug fixes, patterns, and preferences to persistent memory"
    Write-Host "  - Automatically preserve learnings before context compression"
    Write-Host "  - Load its memory at the start of every session"
    Write-Host "  - Get smarter over time as it accumulates project knowledge"
    Write-Host ""
    Write-Color "Now set up your first project:" "Yellow"
    Write-Host ""
    Write-Host "  cd C:\your\project"
    Write-Host "  & $ScriptDir\setup.ps1 -p `"Project Name`""
    Write-Host ""
    exit 0
}

# ============================================================================
# PROJECT SETUP (default, no -Global flag)
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

# Check if global setup has been done
$globalClaude = Join-Path (Join-Path $HOME ".claude") "CLAUDE.md"
if (-not (Test-Path $globalClaude)) {
    Write-Color "Warning: Global memory not set up. Run: & $ScriptDir\setup.ps1 -Global" "Yellow"
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

# Settings — merge on upgrade, copy otherwise
if ($Upgrade -and (Test-Path ".claude\settings.json")) {
    Write-Color "  ^ Merging .claude\settings.json (upgrade mode)" "Yellow"
    if ($PythonCmd) {
        & $PythonCmd (Join-Path (Join-Path $ScriptDir "scripts") "merge-settings.py") (Join-Path (Join-Path $ScriptDir "settings") "settings-windows.template.json") ".claude\settings.json"
    } else {
        Write-Color "  ! Python not found -- cannot merge settings. Install Python or merge manually." "Yellow"
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
# codex-pty shim — work around openai/codex#19945 (silent empty exit when codex
# exec runs without a controlling TTY). Both .ps1 + .sh + helper.py ship for
# cross-platform parity (ADR 0005).
Copy-TemplateFile (Join-Path (Join-Path (Join-Path $ScriptDir "hooks") "lib") "codex-pty.ps1") "$libDir\codex-pty.ps1" "$libDir\codex-pty.ps1 (codex PTY shim, openai/codex#19945)"
Copy-TemplateFile (Join-Path (Join-Path (Join-Path $ScriptDir "hooks") "lib") "codex-pty.sh") "$libDir\codex-pty.sh" "$libDir\codex-pty.sh (codex PTY shim, bash — used by commands/codex.md callsites)"
Copy-TemplateFile (Join-Path (Join-Path (Join-Path $ScriptDir "hooks") "lib") "codex-pty-helper.py") "$libDir\codex-pty-helper.py" "$libDir\codex-pty-helper.py (Python pty.fork helper for the shim)"

# ADRs -- ship template + README + seed ADRs (existing-file-skip semantics).
if (-not (Test-Path "docs\adr")) { New-Item -ItemType Directory -Path "docs\adr" -Force | Out-Null }
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "docs") "adr\template.md") "docs\adr\template.md" "docs\adr\template.md"
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "docs") "adr\README.md") "docs\adr\README.md" "docs\adr\README.md (ADR index)"
foreach ($adr in @("0001-volatile-state-not-auto-loaded", "0002-bash-and-powershell-dual-platform", "0003-template-distributed-no-build-step", "0004-diataxis-docs-structure", "0005-hard-platform-parity-rule")) {
    Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "docs") "adr\$adr.md") "docs\adr\$adr.md" "docs\adr\$adr.md"
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
} else {
    @"
# Volatile per-developer workflow state (PR #2 / continuity-split)
.claude/local/
"@ | Set-Content ".gitignore"
    Write-Host "  " -NoNewline; Write-Color "+" "Green"; Write-Host " Created .gitignore with .claude/local/"
}

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
Copy-TemplateFile (Join-Path (Join-Path $ScriptDir "commands") "codex.md") ".claude\commands\codex.md" ".claude\commands\codex.md"
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
            Write-Host " $desc already exists (use -Force to overwrite)"
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

# Create CHANGELOG only if it doesn't exist — NEVER overwrite on -Force / -Upgrade.
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

# Update CLAUDE.md with project name
if (Test-Path "CLAUDE.md") {
    # Read with UTF8 encoding to preserve Unicode characters (arrows, box chars)
    $content = [System.IO.File]::ReadAllText((Resolve-Path "CLAUDE.md"), [System.Text.Encoding]::UTF8)
    $content = $content -replace '\[Project Name\]', $Project
    # Write back with UTF8 without BOM to preserve Unicode
    [System.IO.File]::WriteAllText((Resolve-Path "CLAUDE.md"), $content, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "  " -NoNewline
    Write-Color "+" "Green"
    Write-Host " Updated CLAUDE.md with project name"
}

Write-Host ""
if ($Upgrade) {
    Write-Color "============================================" "Green"
    Write-Color "  Upgrade Complete!" "Green"
    Write-Color "============================================" "Green"
    Write-Host ""
    Write-Color "What was updated:" "Yellow"
    Write-Host ""
    Write-Host "  .claude\commands\        Workflow commands (refreshed)"
    Write-Host "  .claude\hooks\           Hook scripts (refreshed)"
    Write-Host "  .claude\rules\           Coding standards (refreshed)"
    Write-Host "  .claude\agents\          Subagent definitions (refreshed)"
    Write-Host "  .claude\skills\          Skills (release, council, ui-design if typescript/fullstack)"
    Write-Host "  .claude\settings.json    Hooks and permissions (merged - your customizations kept)"
    Write-Host "  .mcp.json                MCP servers (merged - your customizations kept)"
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
    Write-Host "   /help        -> Should show: /superpowers:*, /new-feature, /fix-bug, /prd:*"
    Write-Host ""
    Write-Host "2. " -NoNewline
    Write-Color "Commit and push" "Blue"
    Write-Host ":"
    Write-Host ""
    Write-Host "   git add .claude/ .mcp.json"
    Write-Host "   git commit -m `"chore: upgrade Claude Code automation templates`""
    Write-Host "   git push"
    Write-Host ""
    # 5.16: dropped the consolidated cry-wolf drift preamble that fired on
    # every --upgrade regardless of actual drift. The migration script's
    # Variant B "ask Claude to reconcile" message handles drift reconciliation
    # when it actually matters (during --migrate). 5.17: also dropped the
    # per-file inline drift hint at the same layer; replaced by the soft tip
    # at end of upgrade summary below.
    # PR #2 (continuity-split): legacy CONTINUITY.md migration prompt.
    if ($hadContinuity) {
        Write-Color "! Legacy CONTINUITY.md detected." "Yellow"
        Write-Host "  PR #2 (continuity-split) replaces CONTINUITY.md with three artifacts:"
        Write-Host "    - durable team-shared facts -> CLAUDE.md"
        Write-Host "    - architecture decisions -> docs/adr/NNNN-*.md"
        Write-Host "    - volatile per-developer state -> .claude/local/state.md (gitignored)"
        Write-Host "  Run the migration assistant to move your content into the new structure:"
        Write-Host ""
        Write-Host "    .\setup.ps1 -Migrate"
        Write-Host ""
        Write-Host "  The migration is idempotent (sentinel-marker-based) and preserves your CONTINUITY.md byte-for-byte."
        Write-Host ""
    }
    # Replaces a pre-existing hardcoded claim that lied whenever the user had
    # deleted one of the files before running --upgrade.
    if ($hadClaude -and $hadContinuity) {
        Write-Color "Upgrade done! Your CLAUDE.md and CONTINUITY.md were preserved (run -Migrate to move content to the new structure)." "Green"
    } elseif ($hadClaude) {
        Write-Color "Upgrade done! Your CLAUDE.md was preserved (user content)." "Green"
    } elseif ($hadContinuity) {
        Write-Color "Upgrade done! Your CONTINUITY.md was preserved (run -Migrate to move content to the new structure)." "Green"
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
    # (tree diagrams, prose pointers, labels) -- field bug where msai-v2
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
        Write-Host "   (durable), docs/adr/ (decisions), and .claude/local/state.md"
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
    Write-Host "  CLAUDE.md                Your project description (edit this!)"
    Write-Host "  .claude\local\state.md   Volatile per-developer workflow state (gitignored)"
    Write-Host "  .claude\state.template.md Canonical state template (always-refresh)"
    Write-Host "  .claude\settings.json    Hooks and permissions"
    Write-Host "  .mcp.json                MCP servers (Playwright + Context7)"
    Write-Host "  .claude\commands\        Workflow commands: /new-feature, /fix-bug, /quick-fix"
    Write-Host "  .claude\hooks\           Auto-run scripts (format, verify, memory)"
    Write-Host "  .claude\agents\          Subagent definitions (verify-app, verify-e2e)"
    Write-Host "  .claude\rules\           Coding standards + workflow rules (safe to update)"
    Write-Host "  .claude\skills\           Skills (release, council, ui-design if typescript/fullstack)"
    Write-Host "  docs\                    Changelog, ADRs (docs\adr\), PRDs, solutions knowledge base"
    Write-Host ""
    Write-Color "Plugins pre-enabled in .claude\settings.json:" "Yellow"
    Write-Host ""
    Write-Host "  - superpowers              (requires install - see step 3 below)"
    Write-Host "  - pr-review-toolkit        (built-in, no install needed)"
    Write-Host "  - frontend-design          (built-in, no install needed)"
    Write-Host ""
    # Check if global setup needed
    $globalClaude = Join-Path (Join-Path $HOME ".claude") "CLAUDE.md"
    if (-not (Test-Path $globalClaude)) {
        Write-Color "+--------------------------------------------------------------+" "Red"
        Write-Color "|  WARNING: Global memory not set up yet!                       |" "Red"
        Write-Color "|                                                               |" "Red"
        Write-Color "|  Without global setup:                                        |" "Red"
        Write-Color "|  - Claude won't save learnings before context compression     |" "Red"
        Write-Color "|  - /memory won't show your auto memory directory              |" "Red"
        Write-Color "|  - Session knowledge will be lost on compaction               |" "Red"
        Write-Color "|                                                               |" "Red"
        Write-Host  "|  Run: " -NoNewline -ForegroundColor Red
        Write-Host  "& $ScriptDir\setup.ps1 -Global" -NoNewline -ForegroundColor Green
        Write-Color "                          |" "Red"
        Write-Color "+--------------------------------------------------------------+" "Red"
        Write-Host ""
    }
    Write-Color "Next steps:" "Yellow"
    Write-Host ""
    Write-Host "1. " -NoNewline
    Write-Color "Edit CLAUDE.md" "Blue"
    Write-Host " - Fill in your project description, tech stack, and commands"
    Write-Host "   (It's intentionally short - all rules live in .claude\rules\)"
    Write-Host ""
    Write-Host "2. " -NoNewline
    Write-Color "Set your project goal" "Blue"
    Write-Host " - In CLAUDE.md, add one sentence under '### Goal'"
    Write-Host "   (Volatile state lives in .claude\local\state.md - gitignored, populated by /new-feature)"
    Write-Host ""
    Write-Host "3. " -NoNewline
    Write-Color "Install the Superpowers plugin" "Blue"
    Write-Host " (one time):"
    Write-Host ""
    Write-Host "   claude"
    Write-Host "   /plugin marketplace add obra/superpowers-marketplace"
    Write-Host "   /plugin install superpowers@superpowers-marketplace"
    Write-Host ""
    Write-Host "   Then restart Claude Code."
    Write-Host ""
    Write-Host "   Note: pr-review-toolkit and frontend-design are built-in Claude Code plugins -"
    Write-Host "   no install needed. /simplify is a built-in command. They're already"
    Write-Host "   enabled in .claude\settings.json."
    Write-Host ""
    Write-Host "4. " -NoNewline
    Write-Color "Verify everything works" "Blue"
    Write-Host ":"
    Write-Host ""
    Write-Host "   /hooks       -> Should show: SessionStart, Stop, PreToolUse, PostToolUse, PreCompact, SubagentStop, ConfigChange"
    Write-Host "   /help        -> Should show: /superpowers:*, /new-feature, /fix-bug, /prd:*"
    Write-Host "   /memory      -> Should show your auto memory directory"
    Write-Host ""
    Write-Host "5. " -NoNewline
    Write-Color "Commit and push" "Blue"
    Write-Host ":"
    Write-Host ""
    Write-Host "   git add .claude/ .mcp.json CLAUDE.md docs/"
    Write-Host "   git commit -m `"chore: add Claude Code automation setup`""
    Write-Host "   git push"
    Write-Host ""
    Write-Color "You're ready! Run /new-feature <name> to start your first guided workflow." "Green"
}
