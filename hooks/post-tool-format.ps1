# .claude/hooks/post-tool-format.ps1
# This hook runs after Edit or Write tool is used.
# It automatically formats the modified file based on its type.
#
# Requirements: PowerShell 5.1+
# Optional: ruff (for Python), prettier (for JS/TS/JSON/MD)
#
# Security: Follows Anthropic best practices
# - Validates and sanitizes inputs
# - Blocks path traversal attacks
# - Skips sensitive files

# Read the hook input from stdin
$jsonInput = [Console]::In.ReadToEnd()

# Parse JSON input
try {
    $data = $jsonInput | ConvertFrom-Json
} catch {
    exit 0
}

# Extract file path
$filePath = $data.tool_input.file_path

if (-not $filePath) {
    exit 0
}

# Security: Block path traversal
if ($filePath -match '\.\.') {
    Write-Error "Security: Path traversal blocked"
    exit 0
}

# Security: Skip sensitive files
$fileName = [System.IO.Path]::GetFileName($filePath)
$sensitivePatterns = @('.env*', '*.key', '*.pem', '*.secret', '*credential*', '*password*', '*.p12', '*.pfx')
foreach ($pattern in $sensitivePatterns) {
    if ($fileName -like $pattern) {
        exit 0
    }
}

# Skip files in sensitive directories
$sensitiveDirs = @('.git', 'node_modules', '.ssh', 'secrets')
foreach ($dir in $sensitiveDirs) {
    if ($filePath -match [regex]::Escape($dir)) {
        exit 0
    }
}

# Get file extension
$extension = [System.IO.Path]::GetExtension($filePath).ToLower()

# Format based on file type
switch ($extension) {
    ".py" {
        # Python files — format with ruff, using the nearest pyproject.toml as config.
        # Walks up from the edited file to find the project root (works for
        # monorepo layouts like backend/src/ or apps/api/, not just flat repos).
        # Runs `ruff check --fix` and `ruff format` independently so a lint
        # failure does not skip formatting.

        # Normalize to absolute path
        if ([System.IO.Path]::IsPathRooted($filePath)) {
            $absPath = $filePath
        } elseif ($env:CLAUDE_PROJECT_DIR) {
            $absPath = Join-Path $env:CLAUDE_PROJECT_DIR $filePath
        } else {
            $absPath = Join-Path (Get-Location) $filePath
        }

        # Walk up from the file's directory looking for pyproject.toml
        $searchDir = Split-Path -Parent $absPath
        $ruffRoot = $null
        while ($searchDir -and (Test-Path $searchDir)) {
            if (Test-Path (Join-Path $searchDir "pyproject.toml")) {
                $ruffRoot = $searchDir
                break
            }
            $parent = Split-Path -Parent $searchDir
            if ($parent -eq $searchDir) { break }
            $searchDir = $parent
        }

        if ($ruffRoot) {
            Push-Location $ruffRoot
            try {
                uv run ruff check --fix $absPath 2>$null
            } catch {}
            try {
                uv run ruff format $absPath 2>$null
            } catch {}
            Pop-Location
        }
        # If no pyproject.toml found anywhere above: skip silently.
    }
    { $_ -in ".ts", ".tsx", ".js", ".jsx" } {
        # TypeScript/JavaScript files - format with prettier
        npx prettier --write $filePath 2>$null
    }
    ".json" {
        # JSON files - format with prettier (skip package-lock.json)
        if ($fileName -eq "package-lock.json") { exit 0 }
        npx prettier --write $filePath 2>$null
    }
    ".md" {
        # Markdown is intentionally NOT auto-formatted (v5.56) — mirrors the .sh hook.
        # The harness ships hand-authored markdown (rules/, commands/, skills/, agents/,
        # docs/) using an escaped-backtick convention (\`...\`) and sentinel/byte-pinned
        # blocks enforced by tests/template/test-contracts.sh. prettier 3.x corrupts it
        # (merges escaped-backtick continuation lines, strips spaces around inline code),
        # garbling prose and breaking byte-identical contracts. Skip it.
    }
}

exit 0
