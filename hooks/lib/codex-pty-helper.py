#!/usr/bin/env python3
# hooks/lib/codex-pty-helper.py — PTY wrapper for codex exec.
#
# Why a separate file (not inline in codex-pty.sh)?
#   pty.spawn() in Python 3.9 hangs on macOS after the child exits because
#   the parent's _copy loop blocks in select() waiting on master_fd that
#   never reports ready. Working around it requires an explicit waitpid
#   poll loop, which is too long to inline as `python3 -c '...'` in bash.
#
# Why pty.fork() not pty.spawn()?
#   pty.spawn() does the fork + I/O loop together but its loop is buggy on
#   3.9. We use the lower-level pty.fork() (which just allocates a pty pair
#   and forks) and write our own loop that polls waitpid(WNOHANG) so we can
#   exit promptly when the child terminates.
#
# Contract:
#   sys.argv[1:] is the command + args to run inside the pty.
#   stdin → pty master, pty master → stdout, both 4KB chunks.
#   Returns child's exit code; signal-killed children return 128 + signum.

import errno
import os
import pty
import select
import signal
import sys
import termios


def main() -> int:
    if len(sys.argv) < 2:
        print("codex-pty-helper: usage: codex-pty-helper.py <cmd> [args...]",
              file=sys.stderr)
        return 2

    argv = sys.argv[1:]

    pid, master_fd = pty.fork()
    if pid == 0:
        # Child: pty.fork() already dup'd slave to fd 0/1/2 and made us the
        # session leader.
        # Reset signal dispositions to SIG_DFL before exec. Without this, the
        # child inherits whatever the parent had — and bash sets SIGINT to
        # SIG_IGN for any process it backgrounds in a non-interactive shell
        # (POSIX). That inherited SIG_IGN would prevent the child from
        # responding to our forwarded SIGINT during cancellation. Real codex
        # (Rust) reinstalls its own handlers in main(), so this is mostly
        # defense-in-depth, but it makes the shim behave correctly with any
        # POSIX child including /bin/sleep, /usr/bin/cat, etc.
        for _sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP, signal.SIGPIPE, signal.SIGQUIT):
            try:
                signal.signal(_sig, signal.SIG_DFL)
            except (ValueError, OSError):
                pass
        # On exec failure, emit a diagnostic to stderr (which goes through the
        # pty back to the user) so the user can distinguish "codex ran and
        # exited N" from "execvp failed and we couldn't run codex" — without
        # the diagnostic, exit codes 126/127 collide with legitimate codex
        # exits (silent-failure agent P0, iter-2).
        try:
            os.execvp(argv[0], argv)
        except FileNotFoundError:
            sys.stderr.write(
                f"codex-pty-helper: command not found: {argv[0]}\n"
            )
            sys.stderr.flush()
            os._exit(127)
        except OSError as e:
            sys.stderr.write(
                f"codex-pty-helper: execvp failed for {argv[0]}: "
                f"errno={e.errno} ({e.strerror})\n"
            )
            sys.stderr.flush()
            os._exit(126)

    # Parent: disable TTY echo on the pty so when we forward parent stdin to
    # master the line discipline doesn't echo it back into our output stream.
    # Without this, writing EOT (^D) to signal stdin EOF to the child causes
    # `^D\b\b` to appear in codex's output. Echo is only meaningful for
    # interactive terminals; the shim is always non-interactive.
    try:
        attrs = termios.tcgetattr(master_fd)
        attrs[3] &= ~termios.ECHO  # lflag &= ~ECHO
        termios.tcsetattr(master_fd, termios.TCSANOW, attrs)
    except (termios.error, OSError):
        pass  # not all platforms support tcsetattr on a pty master

    # Forward SIGINT/SIGTERM/SIGHUP to the child so cancellation
    # actually cancels codex (verified gap in iter-2: without these handlers,
    # Python's default SIGINT handler raises KeyboardInterrupt which our
    # `except OSError` clause inadvertently caught via InterruptedError, and
    # the parent silently kept reading the pty until codex finished naturally).
    # The handlers forward; the main loop notices child exit via waitpid and
    # returns 128+signum per WIFSIGNALED handling at the bottom of main().
    def _forward_signal(signum: int, _frame: object) -> None:
        try:
            os.kill(pid, signum)
        except OSError:
            pass

    for _sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        try:
            signal.signal(_sig, _forward_signal)
        except (ValueError, OSError):
            # SIGHUP not available on Windows; signal.signal in non-main
            # threads also raises ValueError. Fall through silently.
            pass

    # I/O multiplex until child exits.
    # `stdin_open` tracks whether we should still poll fd 0. After EOF we drop
    # it from the select set entirely. (iter-3 council P1 fix — Contrarian
    # and Maintainer empirically reproduced a CPU busy-loop here: the previous
    # `dup2(/dev/null, 0)` trick did not stop select() from waking, because
    # /dev/null on macOS/Linux is always selectable. Result: ~2 CPU-seconds
    # per 2 wall-seconds wrapping `/bin/sleep 2 </dev/null`. Fix is the flag.)
    exit_status = None
    select_error_streak = 0
    stdin_open = True
    try:
        while True:
            # Poll for child exit — non-blocking.
            try:
                wpid, status = os.waitpid(pid, os.WNOHANG)
            except ChildProcessError:
                exit_status = 0
                break
            if wpid == pid:
                exit_status = status
                # Drain remaining buffered output before returning.
                _drain(master_fd)
                break
            # Build select set dynamically; drop fd 0 once stdin EOFs.
            select_fds: list[int] = [master_fd]
            if stdin_open:
                select_fds.append(0)
            try:
                rfds, _, _ = select.select(select_fds, [], [], 0.1)
                select_error_streak = 0
            except (OSError, ValueError) as e:
                # Either master_fd was closed under us, or stdin is closed.
                # Bail after a sustained streak — without this, EBADF would
                # spin at 100% CPU forever (silent-failure agent P1, iter-2).
                select_error_streak += 1
                if select_error_streak > 50:  # ~5s of consecutive errors
                    sys.stderr.write(
                        f"codex-pty-helper: select() persistently failing "
                        f"({e}); killing child and aborting\n"
                    )
                    try:
                        os.kill(pid, signal.SIGTERM)
                    except OSError:
                        pass
                    exit_status = 1 << 8  # encode as wait-status (exit 1)
                    break
                continue

            if master_fd in rfds:
                try:
                    data = os.read(master_fd, 4096)
                except OSError:
                    # macOS: master read returns EIO when slave is fully closed.
                    # Treat as EOF — child has exited and waitpid will catch it.
                    data = b""
                if data:
                    try:
                        os.write(1, data)
                    except BrokenPipeError:
                        # Downstream reader is gone (SIGPIPE semantics). Kill
                        # the child to free resources and surface 141 (per
                        # silent-failure agent P1, iter-2).
                        try:
                            os.kill(pid, signal.SIGTERM)
                        except OSError:
                            pass
                        exit_status = (128 + signal.SIGPIPE) << 8  # encode wait-status
                        break
                    except OSError as e:
                        sys.stderr.write(
                            f"codex-pty-helper: stdout write failed: {e}\n"
                        )
                        exit_status = 1 << 8
                        break
                # If empty, don't break — let waitpid confirm the exit.

            if stdin_open and 0 in rfds:
                try:
                    data = os.read(0, 4096)
                except OSError:
                    data = b""
                if data:
                    try:
                        os.write(master_fd, data)
                    except OSError as e:
                        if e.errno not in (errno.EIO, errno.EPIPE):
                            sys.stderr.write(
                                f"codex-pty-helper: pty write failed: {e}\n"
                            )
                        # Child hung up its end — stop forwarding stdin.
                        stdin_open = False
                else:
                    # Stdin EOF: stop polling fd 0 AND signal EOF to the child
                    # by writing EOT (^D, 0x04) to the pty master. In canonical
                    # mode (the default after pty.fork on macOS/Linux), the
                    # line discipline interprets ^D at line-start as EOF, so
                    # the child's next read() returns 0 bytes. Without this,
                    # children that read stdin (like /bin/cat with piped
                    # input) hang forever waiting for more data — found by
                    # the iter-3 smoke /codex review against ../mcpgateway.
                    stdin_open = False
                    try:
                        os.write(master_fd, b'\x04')
                    except OSError:
                        pass
    finally:
        try:
            os.close(master_fd)
        except OSError:
            pass

    if exit_status is None:
        return 1
    if os.WIFEXITED(exit_status):
        return os.WEXITSTATUS(exit_status)
    if os.WIFSIGNALED(exit_status):
        return 128 + os.WTERMSIG(exit_status)
    return 1


def _drain(master_fd: int, max_bytes: int = 16 << 20) -> None:
    """Read everything buffered on master_fd and write to stdout.

    Bounded by max_bytes (16 MiB) to avoid infinite loops if upstream is weird.
    The cap is sized for council-chairman synthesis output (multi-advisor raw
    outputs at xhigh effort can plausibly exceed 1 MiB; 16 MiB is comfortably
    above any realistic single codex turn). Truncation emits an unconditional
    stderr warning so silent half-output is impossible (iter-3 council P2 fix).
    """
    total = 0
    while total < max_bytes:
        try:
            rfds, _, _ = select.select([master_fd], [], [], 0)
        except (OSError, ValueError):
            return
        if master_fd not in rfds:
            return
        try:
            data = os.read(master_fd, 4096)
        except OSError:
            return
        if not data:
            return
        try:
            os.write(1, data)
        except OSError:
            return
        total += len(data)
    # Reached cap without seeing EOF — surface the truncation loudly so the
    # user knows the response was clipped.
    sys.stderr.write(
        f"codex-pty-helper: drain cap reached ({max_bytes} bytes); "
        f"output truncated. File a bug if reproducible.\n"
    )
    sys.stderr.flush()


if __name__ == "__main__":
    sys.exit(main())
