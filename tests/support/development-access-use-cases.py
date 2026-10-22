#!/usr/bin/env python3
"""Executable connected-default and Git-clean worktree controls."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


parser = argparse.ArgumentParser()
parser.add_argument("--source-root", type=Path, required=True)
parser.add_argument("--engine", choices=("bash", "powershell"), required=True)
parser.add_argument("--shell")
args = parser.parse_args()
source = args.source_root.resolve()
shell = args.shell or ("bash" if args.engine == "bash" else ("powershell.exe" if os.name == "nt" else "pwsh"))
environment = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_COUNT="0")


def run(command, *, cwd=None, env=None, success=True):
    result = subprocess.run(command, cwd=cwd, env=env or environment, capture_output=True, text=True)
    assert (result.returncode == 0) == success, (command, result.returncode, result.stdout, result.stderr)
    return result


def access(action, root, **kwargs):
    if args.engine == "bash":
        command = [shell, str(source / "hooks/lib/development-access.sh"), action, "--project-root", str(root)]
    else:
        command = [shell, "-NoProfile", "-File", str(source / "hooks/lib/development-access.ps1"),
                   "-Action", action, "-ProjectRoot", str(root)]
    return run(command, **kwargs)


def lifecycle(action, root, target=None, name=None, **kwargs):
    if args.engine == "bash":
        command = [shell, str(source / "hooks/lib/worktree-lifecycle.sh"), action]
        if target is not None:
            command += ["--worktree", str(target)]
        if name:
            command += ["--kind", "feat", "--name", name, "--base", "HEAD"]
    else:
        command = [shell, "-NoProfile", "-File", str(source / "hooks/lib/worktree-lifecycle.ps1"), "-Action", action]
        if target is not None:
            command += ["-Worktree", str(target)]
        if name:
            command += ["-Kind", "feat", "-Name", name, "-Base", "HEAD"]
    return run(command, cwd=root, **kwargs)


with tempfile.TemporaryDirectory(prefix="forge-development-access-") as temporary:
    base = Path(temporary).resolve()
    for variant in ("missing-ignores", "global-ignores", "probe-only-ignore"):
        root = base / variant
        (root / "manifests").mkdir(parents=True)
        (root / ".claude").mkdir()
        (root / "state.template.md").write_bytes((source / "state.template.md").read_bytes())
        (root / "manifests/managed-v6.tsv").write_text("source-mode fixture\n")
        (root / "app.txt").write_text("application\n")
        (root / ".claude/settings.json").write_text('{"sandbox":{"enabled":true}}')
        env = dict(environment)
        if variant == "global-ignores":
            global_ignore = base / "fixture-global-excludes"
            global_ignore.write_text("/.claude/settings.local.json\n/.forge/local/\n")
            env.update(GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.excludesFile", GIT_CONFIG_VALUE_0=str(global_ignore))
            (root / ".gitignore").write_bytes(b"# project-owned bytes\r\n*.cache\r\n")
        elif variant == "probe-only-ignore":
            (root / ".gitignore").write_text("/.claude/settings.local.json\n/.forge/local/connected-settings-probe\n")
        run(["git", "-C", str(root), "init", "-q", "--initial-branch=main"], env=env)
        run(["git", "-C", str(root), "config", "user.name", "Fixture"], env=env)
        run(["git", "-C", str(root), "config", "user.email", "fixture@example.invalid"], env=env)
        run(["git", "-C", str(root), "add", "."], env=env)
        run(["git", "-C", str(root), "commit", "-qm", "source fixture"], env=env)
        ignore_before = (root / ".gitignore").read_bytes() if (root / ".gitignore").exists() else None
        private_ignore = root / ".git/info/exclude"
        private_before = private_ignore.read_bytes()
        (root / ".forge/local").mkdir(parents=True)
        (root / ".forge/local/state.md").write_bytes((source / "state.template.md").read_bytes())
        local = root / ".claude/settings.local.json"
        local.write_text('{"env":{"PRIMARY_ONLY":"must-not-copy"}}')
        access("configure", root, env=env)
        assert not (root / '.forge/local/connected-development.json').exists(), 'default configuration must not create a selection marker'
        # An old marker has no authority and must not affect new worktree defaults.
        (root / '.forge/local/connected-development.json').write_text('legacy inert user bytes')
        for relative in (".forge/local/connected-development.json", ".forge/local/connected-settings-real-staging"):
            run(["git", "-C", str(root), "check-ignore", "-q", "--", relative], env=env)
        ignore_after = (root / ".gitignore").read_bytes() if (root / ".gitignore").exists() else None
        assert ignore_after == ignore_before, "configure changed tracked/project ignore bytes"
        if variant == "global-ignores":
            assert private_ignore.read_bytes() == private_before, "effective global ignores were needlessly duplicated"
        assert run(["git", "-C", str(root), "status", "--porcelain"], env=env).stdout == ""
        lifecycle("create", root, name="new-connected", env=env)
        created = root / ".worktrees/new-connected"
        assert json.loads((created / ".claude/settings.local.json").read_text()) == {"sandbox": {"enabled": False}}
        assert run(["git", "-C", str(created), "status", "--porcelain"], env=env).stdout == "", "inherit dirtied new worktree"
        adopted = base / (variant + "-native-adopt")
        run(["git", "-C", str(root), "worktree", "add", "-qb", "native-adopt", str(adopted), "HEAD"], env=env)
        (adopted / ".claude/settings.local.json").write_text('{"sandbox":{"enabled":true},"env":{"TARGET_ONLY":"keep"},"permissions":{"deny":["Bash(target-only *)"]}}')
        lifecycle("adopt", root, target=adopted, name="adopted-connected", env=env)
        value = json.loads((adopted / ".claude/settings.local.json").read_text())
        assert value == {"env": {"TARGET_ONLY": "keep"}, "permissions": {"deny": ["Bash(target-only *)"]}, "sandbox": {"enabled": False}}
        assert run(["git", "-C", str(adopted), "status", "--porcelain"], env=env).stdout == "", "inherit dirtied adopted worktree"
        target_local = created / ".claude/settings.local.json"
        target_local.write_text('{"sandbox":{"enabled":true},"env":{"TARGET_ONLY":"keep"}}')
        run(["git", "-C", str(created), "add", "-f", ".claude/settings.local.json"], env=env)
        before = target_local.read_bytes(), private_ignore.read_bytes()
        result = access("configure", created, env=env, success=False)
        assert "tracked" in result.stderr.lower(), result.stderr
        assert (target_local.read_bytes(), private_ignore.read_bytes()) == before
        print(f"PASS {args.engine}: {variant}, marker-free clean create/adopt, tracked target refused", flush=True)

    # A private exclude is repository-local metadata, but it still must not be
    # followed through a link when the helper needs to add ignore entries.
    root = base / "aliased-exclude"
    root.mkdir()
    run(["git", "-C", str(root), "init", "-q"])
    outside = base / "outside-exclude"
    outside.write_text("# preserve outside bytes\n")
    exclude = root / ".git/info/exclude"
    exclude.unlink()
    try:
        exclude.symlink_to(outside)
    except OSError:
        print(f"SKIP {args.engine}: host cannot create test file symlink", flush=True)
    else:
        result = access("configure", root, success=False)
        assert "symlink" in result.stderr.lower() or "reparse" in result.stderr.lower(), result.stderr
        assert outside.read_text() == "# preserve outside bytes\n"
        assert not (root / ".claude/settings.local.json").exists()
        assert not (root / ".gitignore").exists()
        print(f"PASS {args.engine}: aliased private exclude refused before local writes", flush=True)

    # Root aliases must not turn a tracked-input refusal into a non-repo write.
    root = base / 'real-root'
    (root / '.claude').mkdir(parents=True)
    tracked = root / '.claude/settings.local.json'
    tracked.write_text('{"sandbox":{"enabled":true}}')
    run(['git', '-C', str(root), 'init', '-q'])
    run(['git', '-C', str(root), 'add', '-f', '.claude/settings.local.json'])
    alias = base / 'root-alias'
    try:
        alias.symlink_to(root, target_is_directory=True)
    except OSError:
        print(f'SKIP {args.engine}: host cannot create root alias', flush=True)
    else:
        before = tracked.read_bytes()
        result = access('configure', alias, success=False)
        assert 'tracked' in result.stderr.lower(), result.stderr
        assert tracked.read_bytes() == before
        assert not (root / '.gitignore').exists()
        print(f'PASS {args.engine}: aliased root still refuses tracked local settings', flush=True)
