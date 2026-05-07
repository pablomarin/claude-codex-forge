# hooks/lib/codex-pty.ps1 — work around openai/codex#19945 (Windows side).
#
# Mirrors hooks/lib/codex-pty.sh. See that file's header for the bug and the
# unified contract; the docs below cover only Windows-specific concerns.
#
# Status of #19945 on Windows: zero confirmed reproductions as of 2026-05-01.
# This shim exists primarily for parity (ADR 0005) — its default action is
# detect-then-bypass: on PS 7+ with non-redirected stdio (native ConPTY host),
# we just exec codex directly. Only when stdio is redirected (e.g., the user
# pipes / redirects / spawns from a no-tty parent) do we escalate to winpty,
# WSL, or fall through with a warning.
#
# Contract:
#   - First arg MUST be "exec"
#   - All args after "exec" forwarded to codex verbatim
#   - Stdout = codex's stdout
#   - Stderr = codex's stderr + shim diagnostics prefixed `codex-pty: ` written
#     via [Console]::Error.WriteLine (NOT Write-Warning, which uses PS warning
#     stream #3 — would violate the cross-shim stderr contract)
#   - Exit codes: 2 = bad usage, 127 = codex not found, otherwise codex's exit
#
# Opt-out env vars (mirror codex-pty.sh):
#   $env:CLAUDE_FORGE_CODEX_PTY_BYPASS = '1'       skip the shim entirely
#   $env:CLAUDE_FORGE_CODEX_PTY_VIA_WSL = '1'      escalate via WSL when other strategies fail
#
# Dual-mode (mirrors default-branch.ps1):
#   Script-call:   & "$libPath" exec --foo bar
#   Dot-source:    . "$libPath" ; Invoke-CodexPty exec --foo bar
#   The dual-mode is critical because the shipped Claude Code launcher on
#   Windows is `powershell.exe` (5.1), not `pwsh` (7+), so consumers should
#   prefer dot-sourcing to avoid spawning a 7+ subprocess that may not exist.

function Invoke-CodexPty {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    # Usage check — first arg must be 'exec'
    if ($Args.Count -lt 1 -or $Args[0] -ne 'exec') {
        $first = if ($Args.Count -ge 1) { $Args[0] } else { '<empty>' }
        [Console]::Error.WriteLine("codex-pty: usage: Invoke-CodexPty exec [codex-exec-args...]")
        [Console]::Error.WriteLine("codex-pty: first argument must be 'exec' (the codex subcommand); got: $first")
        return 2
    }

    # codex availability check
    $codex = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $codex) {
        [Console]::Error.WriteLine("codex-pty: codex not found on PATH")
        [Console]::Error.WriteLine("codex-pty: install with 'npm i -g @openai/codex' or 'scoop install codex'")
        return 127
    }

    # Bypass: skip shim logic entirely.
    if ($env:CLAUDE_FORGE_CODEX_PTY_BYPASS -eq '1') {
        & codex @Args
        return $LASTEXITCODE
    }

    # If stdio is not redirected AND we're on PS 7+, the shell's console host
    # is ConPTY-backed. Spawning codex with no redirection gives the child a
    # console-attached stdio, isatty() returns true, bug condition not met.
    $outRedirected = [Console]::IsOutputRedirected
    $inRedirected  = [Console]::IsInputRedirected
    if (-not $outRedirected -and -not $inRedirected -and
        $PSVersionTable.PSVersion.Major -ge 7) {
        & codex @Args
        return $LASTEXITCODE
    }

    # Stdio is redirected (or we're on PS 5.1). Probe for winpty.exe — bundled
    # with Git for Windows and installable via scoop.
    $winpty = Get-Command winpty.exe -ErrorAction SilentlyContinue
    if (-not $winpty) {
        $candidates = @(
            (Join-Path $env:ProgramFiles 'Git\usr\bin\winpty.exe'),
            (Join-Path $env:ProgramFiles 'Git\mingw64\bin\winpty.exe')
        )
        foreach ($cand in $candidates) {
            if (Test-Path -LiteralPath $cand) {
                $winpty = Get-Item -LiteralPath $cand
                break
            }
        }
    }

    if ($winpty) {
        & $winpty.Source codex @Args
        return $LASTEXITCODE
    }

    # WSL opt-in: shell out to WSL Linux + python3 + Linux codex. Only viable
    # when the user has a working WSL distro with codex installed.
    if ($env:CLAUDE_FORGE_CODEX_PTY_VIA_WSL -eq '1') {
        $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
        if ($wsl) {
            # Invoke the canonical helper (avoids drift between this file and
            # codex-pty-helper.py — iter-2 fix). Translate the Windows path to
            # a WSL-mount path via `wsl.exe wslpath -u`; pass it to the WSL-
            # side python3.
            $helperWin = Join-Path (Split-Path -Parent $PSCommandPath) 'codex-pty-helper.py'
            $helperWsl = & wsl.exe wslpath -u "$helperWin" 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $helperWsl) {
                [Console]::Error.WriteLine("codex-pty: wsl.exe wslpath failed; cannot translate helper path. Falling through.")
            }
            else {
                # Capture stderr to distinguish wsl.exe infrastructure errors
                # from codex's own exit codes (silent-failure agent P1, iter-2).
                $errFile = [System.IO.Path]::GetTempFileName()
                try {
                    & wsl.exe -- python3 $helperWsl codex @Args 2>$errFile
                    $rc = $LASTEXITCODE
                    $errText = (Get-Content -Raw -ErrorAction SilentlyContinue $errFile)
                    if ($rc -eq -1 -or ($errText -and $errText -match '^wsl(\.exe)?:')) {
                        # WSL itself failed (distro stopped, kernel update needed,
                        # python3/codex missing inside WSL). Don't masquerade
                        # wsl.exe's exit as codex's — fall through to next strategy.
                        [Console]::Error.WriteLine("codex-pty: WSL escalation failed (exit=$rc): $($errText.Trim())")
                        [Console]::Error.WriteLine("codex-pty: falling through to direct invoke")
                    }
                    else {
                        # Forward helper's stderr (codex errors, exec failures)
                        if ($errText) { [Console]::Error.Write($errText) }
                        return $rc
                    }
                }
                finally {
                    Remove-Item -ErrorAction SilentlyContinue $errFile
                }
            }
        }
        else {
            [Console]::Error.WriteLine("codex-pty: CLAUDE_FORGE_CODEX_PTY_VIA_WSL=1 but wsl.exe not on PATH; falling through")
        }
    }

    # Last-resort fallback: direct invoke with a stderr warning.
    [Console]::Error.WriteLine("codex-pty: winpty.exe not found and stdio is redirected; falling back to direct invoke (may hit openai/codex#19945)")
    [Console]::Error.WriteLine("codex-pty: install via 'scoop install winpty' or Git for Windows; or set `$env:CLAUDE_FORGE_CODEX_PTY_BYPASS='1' to silence")
    & codex @Args
    return $LASTEXITCODE
}

# Dual-mode entry point — same pattern as default-branch.ps1.
# When dot-sourced: $MyInvocation.InvocationName == '.' → just define the function.
# When invoked as script: call the function with $args, exit with its return.
if ($MyInvocation.InvocationName -ne '.') {
    $rc = Invoke-CodexPty @args
    exit $rc
}
