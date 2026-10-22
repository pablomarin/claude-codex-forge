#!/usr/bin/env bash
# Configure or inherit the explicit local Claude development-access choice.
# Python 3 is required, as it is for Forge installation.
set -eu
command -v python3 >/dev/null 2>&1 || { echo "BLOCKED: Python 3 is required for local development-access configuration" >&2; exit 1; }
exec python3 - "$@" <<'FORGE_DEVELOPMENT_ACCESS_PY'
import argparse, contextlib, json, os, shutil, stat, subprocess, sys, tempfile
from pathlib import Path

class DevelopmentAccessBlocked(RuntimeError):
    pass

SELECTION = {"schema_version": 1, "claude_sandbox_enabled": False}

def reject_link_ancestors(root, relative):
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise DevelopmentAccessBlocked(f"symlink/reparse-point local settings path: {current}")
        if current.exists() and current != root / relative and not current.is_dir():
            raise DevelopmentAccessBlocked(f"non-directory local settings ancestor: {current}")

def git(root, *arguments):
    return subprocess.run(["git", "-C", str(root), *arguments], capture_output=True, check=False)

def require_untracked(root, relative):
    tracked = git(root, "ls-files", "--error-unmatch", "--", relative)
    if tracked.returncode == 0:
        raise DevelopmentAccessBlocked(f"{relative} is tracked; reconcile it before selecting local development")
    if tracked.returncode != 1:
        raise DevelopmentAccessBlocked(f"cannot verify developer-local input is untracked: {relative}")

def private_ignore_path(root):
    common = git(root, "rev-parse", "--git-common-dir")
    exclude = git(root, "rev-parse", "--git-path", "info/exclude")
    if common.returncode or exclude.returncode:
        raise DevelopmentAccessBlocked("cannot locate repository-private ignores")
    common_path = Path(os.fsdecode(common.stdout).strip())
    if not common_path.is_absolute():
        common_path = root / common_path
    common_path = common_path.resolve(strict=True)
    exclude_path = Path(os.fsdecode(exclude.stdout).strip())
    if not exclude_path.is_absolute():
        exclude_path = root / exclude_path
    if (exclude_path.name != "exclude" or exclude_path.parent.name != "info" or
            exclude_path.parent.parent.resolve(strict=True) != common_path):
        raise DevelopmentAccessBlocked("unexpected repository-private ignore path")
    # Check before resolving info/exclude: resolving it would follow a link.
    reject_link_ancestors(common_path, Path("info/exclude"))
    target = common_path / "info/exclude"
    if target.exists() and not target.is_file():
        raise DevelopmentAccessBlocked("repository-private ignores require a regular file")
    return target

def ensure_local_ignores(root, in_repository):
    paths = (".claude/settings.local.json", ".forge/local/")
    entries = (b"/.claude/settings.local.json", b"/.forge/local/")
    if in_repository:
        missing = []
        for relative, entry in zip(paths, entries):
            result = git(root, "check-ignore", "--no-index", "-q", "--", relative)
            if result.returncode == 1:
                missing.append(entry)
            elif result.returncode:
                raise DevelopmentAccessBlocked(f"cannot verify local ignore: {relative}")
        if not missing:
            return
        ignore = private_ignore_path(root)
    else:
        ignore = root / ".gitignore"
        reject_link_ancestors(root, Path(".gitignore"))
        if ignore.exists() and not ignore.is_file():
            raise DevelopmentAccessBlocked("connected development requires a regular .gitignore")
        missing = [entry.lstrip(b"/") for entry in entries]
    ignored = ignore.read_bytes() if ignore.exists() else b""
    suffix = b""
    for entry in missing:
        if entry not in ignored.splitlines():
            if ignored and not ignored.endswith(b"\n"):
                ignored += b"\n"
                suffix += b"\n"
            ignored += entry + b"\n"
            suffix += entry + b"\n"
    if suffix:
        ignore.parent.mkdir(parents=True, exist_ok=True)
        with ignore.open("ab") as handle:
            handle.write(suffix)
    if in_repository:
        for relative in paths:
            if git(root, "check-ignore", "--no-index", "-q", "--", relative).returncode:
                raise DevelopmentAccessBlocked(f"connected development requires an ignored local path: {relative}")

def development_access_cli(argv: list[str]) -> int:
    """Apply an explicit local choice without taking ownership of sandbox policy."""
    parser = argparse.ArgumentParser(prog="development-access.sh")
    parser.add_argument("action", choices=("configure", "inherit"))
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--source-root")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    temporary = None
    try:
        if args.action == "inherit":
            if not args.source_root:
                raise DevelopmentAccessBlocked("inherit requires --source-root")
            source = Path(args.source_root).resolve(strict=True)
            selection = source / ".forge/local/connected-development.json"
            reject_link_ancestors(source, Path(".forge/local/connected-development.json"))
            if not selection.exists():
                return 0
            require_untracked(source, ".forge/local/connected-development.json")
            if not selection.is_file() or json.loads(selection.read_text(encoding="utf-8-sig")) != SELECTION:
                raise DevelopmentAccessBlocked("unrecognized connected-development selection; preserve and reconcile it")
            reject_link_ancestors(source, Path(".claude/settings.local.json"))
            source_local = source / ".claude/settings.local.json"
            if not source_local.is_file():
                return 0
            require_untracked(source, ".claude/settings.local.json")
            current = json.loads(source_local.read_text(encoding="utf-8-sig"))
            if not isinstance(current, dict) or not isinstance(current.get("sandbox"), dict) or current["sandbox"].get("enabled") is not False:
                return 0
        root = Path(args.project_root).resolve(strict=True)
        if not root.is_dir():
            raise DevelopmentAccessBlocked("connected development requires a project directory")
        local = root / ".claude/settings.local.json"
        scratch = root / ".forge/local"
        selection = scratch / "connected-development.json"
        for relative in (Path(".claude/settings.local.json"), Path(".forge/local/connected-development.json")):
            reject_link_ancestors(root, relative)
        for path in (local, selection):
            if path.exists() and not path.is_file():
                raise DevelopmentAccessBlocked(f"connected development requires a regular file: {path}")
        if scratch.exists() and not scratch.is_dir():
            raise DevelopmentAccessBlocked("connected development requires a regular .forge/local directory")
        if selection.exists() and json.loads(selection.read_text(encoding="utf-8-sig")) != SELECTION:
            raise DevelopmentAccessBlocked("unrecognized connected-development selection; preserve and reconcile it")
        settings = json.loads(local.read_text(encoding="utf-8-sig")) if local.exists() else {}
        if not isinstance(settings, dict):
            raise DevelopmentAccessBlocked("local Claude settings must be a JSON object")
        if "sandbox" in settings and not isinstance(settings["sandbox"], dict):
            raise DevelopmentAccessBlocked("local Claude sandbox settings must be a JSON object")
        if args.action == "inherit" and "enabled" in settings.get("sandbox", {}):
            print("CLAUDE_SANDBOX: PRESERVED existing worktree-local sandbox choice")
            return 0
        in_repository = False
        if shutil.which("git"):
            repository = subprocess.run(["git", "-C", str(root), "rev-parse", "--show-toplevel"],
                                        capture_output=True, check=False)
            if repository.returncode == 0:
                in_repository = True
                for relative in (".claude/settings.local.json", ".forge/local/connected-development.json"):
                    require_untracked(root, relative)
        if args.check:
            return 0

        # Ignore the local settings and secret-bearing staging directory before
        # writing any local JSON. Never create adjacent backups or temporary files.
        ensure_local_ignores(root, in_repository)
        if settings.get("sandbox", {}).get("enabled") is not False:
            local.parent.mkdir(parents=True, exist_ok=True)
            scratch.mkdir(mode=0o700, parents=True, exist_ok=True)
            descriptor, name = tempfile.mkstemp(prefix="connected-settings-", dir=scratch)
            temporary = Path(name)
            mode = stat.S_IMODE(local.stat().st_mode) if local.exists() else 0o600
            settings.setdefault("sandbox", {})["enabled"] = False
            with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
                os.chmod(temporary, mode)
                json.dump(settings, handle, indent=2)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, local)
            temporary = None
        if not selection.exists():
            scratch.mkdir(mode=0o700, parents=True, exist_ok=True)
            descriptor, name = tempfile.mkstemp(prefix="connected-selection-", dir=scratch)
            temporary = Path(name)
            with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
                json.dump(SELECTION, handle, indent=2)
                handle.write("\n")
            os.replace(temporary, selection)
            temporary = None
        print("CLAUDE_SANDBOX: CONNECTED_LOCAL sandbox.enabled=false; native permissions and managed policy still apply; restart the Claude session")
        return 0
    except (OSError, ValueError, DevelopmentAccessBlocked) as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        return 1
    finally:
        if temporary is not None:
            with contextlib.suppress(OSError):
                temporary.unlink(missing_ok=True)


raise SystemExit(development_access_cli(sys.argv[1:]))
FORGE_DEVELOPMENT_ACCESS_PY
