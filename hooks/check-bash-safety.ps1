# .claude/hooks/check-bash-safety.ps1
# PreToolUse hook for Bash: audit logging + dangerous pattern blocking.
#
# Fires BEFORE every Bash command. Logs all commands to ~/.claude/audit.log.
# Blocks commands matching high-risk patterns (exit 2 + stderr).
#
# Input (JSON via stdin): {session_id, cwd, tool_name, tool_input: {command}}
# Block: exit 2 + message on stderr
# Allow: exit 0

$ErrorActionPreference = "SilentlyContinue"

$RawInput = $input | Out-String
$Data = $RawInput | ConvertFrom-Json -ErrorAction SilentlyContinue

$Command = if ($Data.tool_input.command) { $Data.tool_input.command } else { "" }
$SessionId = if ($Data.session_id) { $Data.session_id } else { "unknown" }
$Cwd = if ($Data.cwd) { $Data.cwd } else { "unknown" }

# Skip empty commands
if (-not $Command) { exit 0 }

# --- Audit log ---
$AuditLog = Join-Path $env:USERPROFILE ".claude" "audit.log"
$AuditDir = Split-Path $AuditLog -Parent
if (-not (Test-Path $AuditDir)) { New-Item -ItemType Directory -Path $AuditDir -Force | Out-Null }
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
# Redact potential secrets from logged commands
$SafeCommand = $Command -replace '(export\s+\w*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL)\w*=)[^ ]*', '$1[REDACTED]'
$SafeCommand = $SafeCommand -replace '(sk-|ghp_|gho_|github_pat_|xoxb-|xoxp-)[A-Za-z0-9_-]+', '$1[REDACTED]'
$LogEntry = "[$Timestamp] session=$SessionId cwd=$Cwd cmd=$SafeCommand"
Add-Content -Path $AuditLog -Value $LogEntry -ErrorAction SilentlyContinue

# --- High-risk pattern detection ---
# Collapse bash line-continuations (backslash + newline) for the check #9 write
# guardrail so a write split across physical lines still matches. Used ONLY by
# check #9; check #8 keeps its v5.56 per-line scope. Mirror of the .sh CMD9.
$C9 = $Command -replace '\\\r?\n', ''

$Reason = ""

# 1. Piping remote content to shell
if ($Command -match 'curl\s.*\|\s*(sh|bash|zsh|cmd|powershell)') {
    $Reason = "Piping remote script to shell (curl | sh)"
}
elseif ($Command -match 'wget\s.*\|\s*(sh|bash|zsh|cmd|powershell)') {
    $Reason = "Piping remote script to shell (wget | sh)"
}
# Also catch PowerShell-specific download-and-execute
elseif ($Command -match 'Invoke-Expression.*Invoke-WebRequest|iex.*iwr|IEX.*\(New-Object') {
    $Reason = "Download and execute pattern (Invoke-Expression)"
}
# 2. Base64 decode piped to shell
elseif ($Command -match 'base64.*-d.*\|\s*(sh|bash|zsh|eval)') {
    $Reason = "Base64-decoded content piped to shell"
}
elseif ($Command -match '\[Convert\]::FromBase64.*Invoke-Expression') {
    $Reason = "Base64-decoded content executed via PowerShell"
}
# 3. Reverse shell patterns
elseif ($Command -match '/dev/tcp/') {
    $Reason = "Potential reverse shell (/dev/tcp)"
}
elseif ($Command -match 'bash\s+-i\s+>&') {
    $Reason = "Potential reverse shell (bash -i)"
}
elseif ($Command -match 'nc\s.*-e\s*(sh|bash|/bin|cmd|powershell)') {
    $Reason = "Potential reverse shell (netcat)"
}
# 4. Exfiltration of credentials via network
elseif ($Command -match 'cat.*(id_rsa|id_ed25519|\.ssh|\.gnupg|\.aws\\credentials|\.env).*\|\s*curl') {
    $Reason = "Exfiltrating credential files via network"
}
elseif ($Command -match 'curl.*-d\s*@.*(id_rsa|id_ed25519|\.ssh|\.env|\.aws)') {
    $Reason = "Uploading credential files via curl"
}
elseif ($Command -match 'Get-Content.*(id_rsa|\.ssh|\.aws|\.env).*Invoke-WebRequest') {
    $Reason = "Exfiltrating credential files via PowerShell"
}
# 5. Mass deletion (catch variants beyond static deny list)
elseif ($Command -match 'rm\s+-[rf]*\s+/' -and $Command -notmatch 'rm\s+-[rf]*\s+\./') {
    $Reason = "Recursive deletion targeting root filesystem"
}
elseif ($Command -match 'Remove-Item.*-Recurse.*[A-Z]:\\$') {
    $Reason = "Recursive deletion targeting drive root"
}
# 6. Modifying Claude Code config via Bash
elseif ($Command -match '(sed|awk|echo|tee|printf|Set-Content|Out-File).*\.claude[/\\](settings|config)') {
    $Reason = "Attempting to modify Claude Code configuration via Bash"
}
# 7. Global package installs (supply chain attack vector — see Clinejection)
elseif ($Command -match 'npm\s+(install|i)\s+(-g|--global)|npm\s+(-g|--global)\s+(install|i)') {
    $Reason = "Global npm package install detected (supply chain risk)"
}
elseif ($Command -match 'yarn\s+global\s+add') {
    $Reason = "Global yarn package install detected (supply chain risk)"
}
elseif ($Command -match 'pnpm\s+(add|install|i)\s+(-g|--global)|pnpm\s+(-g|--global)\s+(add|install|i)') {
    $Reason = "Global pnpm package install detected (supply chain risk)"
}
elseif ($Command -match '(^|\s)pip3?\s+install\s+[^-]' -and $Command -notmatch 'pip3?\s+install\s+(-r\s|-e\s|\.\s*$)|uv\s+pip') {
    $Reason = "Unscoped pip install detected (supply chain risk — use venv or uv)"
}
# 8. Workflow-safety (NOT security): block Bash read-utilities that read
#    .claude/local/state.md inline — mirrors check #8 in check-bash-safety.sh.
#    A Bash read of this sensitive file trips CC's sensitive-file prompt and
#    SILENTLY STALLS an autonomous /goal run; the Read tool is prompt-free.
#    (?m) + [^\r\n]* keep the match line-scoped (.NET `.` is not dot-all, and
#    -match runs on the whole string), so the utility token and the literal path
#    must be on the SAME line — sanctioned flows that read via a shell variable
#    are structurally exempt. [/\\] handles Windows separators; the trailing
#    class is a filename terminator so state.md.bak does not match.
elseif ($Command -match '(?m)(^|[ \t])(/[^ \t]*/)?(cat|sed|grep|egrep|fgrep|rg|awk|head|tail|less|more|nl|tac)[ \t][^\r\n]*\.claude[/\\]local[/\\]state\.md([^A-Za-z0-9._-]|$)') {
    $Reason = "Reading .claude/local/state.md via Bash — use the Read tool instead (Bash reads of this sensitive file stall autonomous /goal runs on a permission prompt)"
}
# 9. Workflow-safety: block Bash WRITES under .claude/local/ — mirrors check #9
#    in check-bash-safety.sh. (?m) + [^\r\n] keep the match line-scoped; [ \t]
#    and [/\\] handle whitespace + Windows separators; no POSIX bracket
#    space-class (invalid .NET regex). Wildcard stops at ; so it cannot span commands.
elseif ($C9 -match '(?m)(^|[ \t]|[;&|()])(/[^ \t]*/)?(mkdir|touch|cp|mv|tee|ln|install|dd|rmdir|rm|truncate|rsync|chmod|chown|chgrp)[ \t][^\r\n|&;]*\.claude[/\\]local($|[^A-Za-z0-9._-])') {
    $Reason = "Writing under .claude/local/ via Bash — use the Write/Edit tool instead (Bash writes under .claude/ are never auto-approved and stall autonomous /goal runs on a permission prompt; the Write tool auto-creates parent dirs — see ADR 0006)"
}
elseif ($C9 -match '(?m)(^|[ \t]|[;&|()])(/[^ \t]*/)?g?sed[ \t][^\r\n|&;]*-[A-Za-z]*i[^\r\n|&;]*\.claude[/\\]local($|[^A-Za-z0-9._-])') {
    $Reason = "Writing under .claude/local/ via Bash (sed -i) — use the Write/Edit tool instead (Bash writes under .claude/ stall autonomous /goal runs on a permission prompt; see ADR 0006)"
}
elseif ($C9 -match '(?m)(^|[^-\r\n])([0-9]*|&)?>>?[&|]?[ \t]*[^\r\n \t|&;]*\.claude[/\\]local($|[^A-Za-z0-9._-])') {
    $Reason = "Writing under .claude/local/ via Bash (redirect) — use the Write/Edit tool instead (Bash writes under .claude/ stall autonomous /goal runs on a permission prompt; see ADR 0006)"
}

# --- Block or allow ---
if ($Reason) {
    Add-Content -Path $AuditLog -Value "BLOCKED: $Reason`nCommand: $SafeCommand" -ErrorAction SilentlyContinue
    [Console]::Error.WriteLine("BLOCKED by safety hook: $Reason")
    exit 2
}

exit 0
