# PermissionRequest hook: auto-approve Write/Edit on .forge/local/**
#
# Workaround for anthropics/claude-code#36593 — Claude Code v2.1.80+
# regression where path-scoped Write/Edit allow rules in settings.json
# don't auto-approve. The workflow file .forge/local/state.md is written
# on every /new-feature, /fix-bug, and Phase update; without this hook,
# CC v2.1.80+ prompts the user on every state-md write.
#
# PermissionRequest fires only when CC is about to show a permission
# dialog, so this hook adds no overhead to Write/Edit calls that are
# already allowed by other rules.
#
# Input (JSON via stdin): {tool_name, tool_input: {file_path}, cwd, ...}
# Allow:  emit hookSpecificOutput JSON to stdout, exit 0
# Defer:  print nothing, exit 0 (CC falls back to default permission flow)
#
# Opt-out: set CLAUDE_FORGE_AUTO_APPROVE_LOCAL_WRITES=0 to disable.
#
# Fail-open philosophy: any parse error, malformed path, traversal segment,
# or unknown tool → silent defer (no allow emitted).

$ErrorActionPreference = "SilentlyContinue"

# Honor opt-out
if ($env:CLAUDE_FORGE_AUTO_APPROVE_LOCAL_WRITES -eq "0") { exit 0 }

$RawInput = $input | Out-String
$Data = $RawInput | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $Data) { exit 0 }

$Tool = $Data.tool_name
$FilePath = $Data.tool_input.file_path
$Cwd = $Data.cwd

# Only act on Write|Edit
if ($Tool -ne "Write" -and $Tool -ne "Edit") { exit 0 }
if ([string]::IsNullOrEmpty($FilePath)) { exit 0 }

# Normalize separators
$Normalized = $FilePath -replace '\\', '/'

# Reject traversal segments (segment match, not substring)
if (("/" + $Normalized + "/") -match '/\.\./') { exit 0 }

# Resolve relative paths against hook-provided cwd
if ($Normalized -match '^([A-Za-z]:)?/') {
    $Abs = $Normalized
} else {
    if ([string]::IsNullOrEmpty($Cwd)) { exit 0 }
    $CwdNorm = $Cwd -replace '\\', '/'
    $Abs = "$CwdNorm/$Normalized"
}

# Lexically collapse '.' and empty segments
$Segments = $Abs -split '/' | Where-Object { $_ -ne "" -and $_ -ne "." }
# Preserve absolute-path leading slash (Unix) or drive-letter (Windows)
if ($Abs -match '^/') {
    $Collapsed = "/" + ($Segments -join "/")
} else {
    $Collapsed = ($Segments -join "/")
}

# Segment match: must contain /.forge/local/ as a directory boundary.
# Case-insensitive on Windows file systems.
if ($Collapsed -imatch '/\.(forge|claude)/local/') {
    $Output = @{
        hookSpecificOutput = @{
            hookEventName = "PermissionRequest"
            decision = @{
                behavior = "allow"
            }
        }
    } | ConvertTo-Json -Depth 5 -Compress
    Write-Output $Output
}

exit 0
