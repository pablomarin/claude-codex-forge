#!/usr/bin/env bash
# hooks/lib/codex-pty.sh — work around openai/codex#19945.
#
# THE BUG: codex 0.124.0+ (last unaffected: 0.123.0) silently exits with empty
# stdout when `codex exec` runs with stdio detached from a controlling TTY AND
# the prompt is non-trivial in length (~2KB+). Both triggers fire any time
# Claude Code's Bash tool spawns codex, because that tool pipes stdio without
# allocating a pseudo-terminal. Issue tracker:
#   https://github.com/openai/codex/issues/19945  (open as of 2026-05-01)
# Companion (macOS): https://github.com/openai/codex/issues/8690
#
# THE FIX: allocate a pseudo-tty for codex's stdio so isatty(stdin/out) returns
# true. We delegate to a Python helper (codex-pty-helper.py) that uses
# `pty.fork()` plus an explicit `waitpid(WNOHANG)` loop. We do NOT use BSD
# `script(1)` (it requires a parent tty — calls `tcgetattr` on parent stdin —
# which Claude Code's Bash tool, running with stdin connected to a Unix domain
# socket, does not have). We do NOT use Python's `pty.spawn()` either: 3.9's
# stdlib version hangs on macOS after the child exits because the parent's
# `select()` loop blocks on a master_fd that never reports EOF. The explicit
# waitpid-based helper sidesteps both problems. python3 ships with macOS 10.13+
# and essentially all Linux distros.
#
# RETEST CRITERION: drop this shim once codex 0.128+ is empirically confirmed
# clean on Linux + macOS + Windows. Verify by running the original repro from
# issue #19945:  setsid codex exec "$LARGE_PROMPT" < /dev/null   producing
# non-empty output. Until then, leave the shim in place.
#
# Contract:
#   - First arg MUST be "exec" (or "exec review", which becomes "exec" + "review")
#   - All args after "exec" are forwarded to codex verbatim, in order
#   - Stdout = codex's stdout (PTY-merged with stderr per script(1) semantics)
#   - Stderr = the shim's own diagnostics, prefixed `codex-pty: `
#   - Exit codes: 2 = bad usage, 127 = codex not found, otherwise codex's exit
#
# Opt-out env vars (mirror PR #592 pattern):
#   CLAUDE_FORGE_CODEX_PTY_BYPASS=1     skip the PTY wrapping entirely
#   CLAUDE_FORGE_CODEX_PTY_VIA_WSL=1    (Windows only) escalate via WSL
#
# Invocation: this is a script-only file. Always invoke it directly via
#   bash "$REPO/.claude/hooks/lib/codex-pty.sh" exec [codex-args...]
# Sourcing is NOT supported because the function uses `exec` to chain into
# python3/codex; sourcing it into your shell and then calling the function
# would replace your shell. (iter-2 fix — earlier docstring described a
# source-mode that would crash the caller.)

codex_pty_exec() {
    # Usage check
    if [ "${1:-}" != "exec" ]; then
        echo "codex-pty: usage: codex_pty_exec exec [codex-exec-args...]" >&2
        echo "codex-pty: first argument must be 'exec' (the codex subcommand); got: ${1:-<empty>}" >&2
        return 2
    fi

    # Bypass: skip PTY wrapping entirely. Check this BEFORE the codex
    # availability check so a user with a `codex` shell alias (invisible
    # to `command -v`) can still exec it via bypass (silent-failure agent
    # P2, iter-2).
    if [ "${CLAUDE_FORGE_CODEX_PTY_BYPASS:-}" = "1" ]; then
        exec codex "$@"
    fi

    # codex availability check (only reached when not bypassing)
    if ! command -v codex >/dev/null 2>&1; then
        echo "codex-pty: codex not found on PATH" >&2
        echo "codex-pty: install with 'npm i -g @openai/codex' or 'brew install --cask codex'" >&2
        return 127
    fi

    # OS-specific PTY wrapping
    case "$(uname -s 2>/dev/null)" in
        Darwin|Linux)
            if ! command -v python3 >/dev/null 2>&1; then
                echo "codex-pty: python3 not found; falling back to direct invoke (may hit openai/codex#19945)" >&2
                echo "codex-pty: install via 'brew install python' or 'apt install python3', or set CLAUDE_FORGE_CODEX_PTY_BYPASS=1" >&2
                exec codex "$@"
            fi
            # Resolve the helper path relative to this shim.
            local helper
            helper="$(dirname "${BASH_SOURCE[0]}")/codex-pty-helper.py"
            if [ ! -f "$helper" ]; then
                # Missing helper is an installation defect, not graceful
                # degradation. Falling through to direct invoke would silently
                # re-introduce openai/codex#19945 — exactly what the shim
                # exists to prevent. Surface it loudly with a non-zero exit
                # (silent-failure agent P1, iter-2).
                echo "codex-pty: helper not found at $helper" >&2
                echo "codex-pty: this is an installation defect — re-run setup.sh -f to repair" >&2
                echo "codex-pty: or set CLAUDE_FORGE_CODEX_PTY_BYPASS=1 to deliberately skip the workaround" >&2
                return 3
            fi
            # The helper runs codex in a pty.fork()'d child and uses an
            # explicit waitpid(WNOHANG) loop to exit promptly when codex
            # terminates — pty.spawn() in Python 3.9 hangs on macOS in this
            # role, see helper file header for details.
            exec python3 "$helper" codex "$@"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            # Git Bash / MSYS / Cygwin on Windows. mintty talks to console
            # programs through winpty. winpty is bundled with Git for Windows.
            if command -v winpty >/dev/null 2>&1; then
                exec winpty codex "$@"
            fi
            echo "codex-pty: winpty not found on Git Bash; falling back to direct invoke (may hit openai/codex#19945)" >&2
            echo "codex-pty: install Git for Windows or 'scoop install winpty', or set CLAUDE_FORGE_CODEX_PTY_BYPASS=1" >&2
            exec codex "$@"
            ;;
        *)
            echo "codex-pty: unknown OS '$(uname -s 2>/dev/null)'; falling back to direct invoke (may hit openai/codex#19945)" >&2
            echo "codex-pty: set CLAUDE_FORGE_CODEX_PTY_BYPASS=1 to silence this warning" >&2
            exec codex "$@"
            ;;
    esac
}

# Dual-mode: when invoked as a script (not sourced), call the function and
# exit with its status. When sourced, just expose codex_pty_exec.
#
# Idiom: BASH_SOURCE[0] equals $0 only when this file is the entry point
# (i.e., invoked as `bash this-file.sh`). When sourced, BASH_SOURCE[0] is
# this file's path while $0 is the parent script's name.
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    codex_pty_exec "$@"
    exit $?
else
    echo "codex-pty: this script must be invoked directly (bash codex-pty.sh ...), not sourced." >&2
    echo "codex-pty: sourcing it would replace your shell when codex_pty_exec runs 'exec'." >&2
    # shellcheck disable=SC2317  # exit 2 is reachable when `return` is invalid (script-mode)
    return 2 2>/dev/null || exit 2
fi
