#!/usr/bin/env python3
"""Installed connected-default journeys; native authenticated host qualification is separate."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, required=True)
parser.add_argument('--engine', choices=('bash', 'powershell'), default='bash')
args = parser.parse_args()
source = args.source_root.resolve()

with tempfile.TemporaryDirectory(prefix='forge-connected-default-') as temporary:
    base = Path(temporary).resolve()
    project = base / 'project'
    project.mkdir()
    home = base / 'home'
    home.mkdir()
    binary = base / 'bin'
    binary.mkdir()
    for name in ('codex', 'claude'):
        shim = binary / (name + ('.cmd' if os.name == 'nt' else ''))
        shim.write_text('@exit /b 127\n' if os.name == 'nt' else '#!/bin/sh\nexit 127\n')
        shim.chmod(0o755)
    env = dict(os.environ, HOME=str(home), USERPROFILE=str(home), CODEX_HOME=str(home / '.codex'),
               PATH=str(binary) + os.pathsep + os.environ['PATH'], GIT_CONFIG_GLOBAL=os.devnull,
               GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_COUNT='0')

    def run(command, *, success=True, extra=None):
        result = subprocess.run(command, cwd=project, env=dict(env, **(extra or {})), capture_output=True, text=True)
        assert (result.returncode == 0) == success, (command, result.returncode, result.stdout[-3000:], result.stderr[-3000:])
        return result

    def setup(*flags, success=True, extra=None):
        if args.engine == 'bash':
            command = ['bash', str(source / 'setup.sh'), '--this-checkout-only', *flags]
        else:
            mapped = {'--upgrade': '-Upgrade', '--force': '-Force', '--dry-run': '-DryRun'}
            command = ['powershell.exe' if os.name == 'nt' else shutil.which('pwsh'), '-NoProfile', '-File', str(source / 'setup.ps1'),
                       '-ThisCheckoutOnly', *(mapped[f] for f in flags)]
        return run(command, success=success, extra=extra)

    def snapshot():
        return {str(p.relative_to(project)): (hashlib.sha256(p.read_bytes()).hexdigest(), stat.S_IMODE(p.stat().st_mode))
                for p in project.rglob('*') if p.is_file() and '.git' not in p.relative_to(project).parts}

    local = project / '.claude/settings.local.json'
    config = project / '.codex/config.toml'
    original = {'sandbox': {'enabled': True, 'network': {'allowedDomains': ['keep.invalid']}},
                'env': {'PROJECT_VALUE': 'keep'}, 'permissions': {'deny': ['Bash(protected *)']}}

    def windows_acl(protect=False, path=local):
        command = "$ErrorActionPreference='Stop'; $acl=Get-Acl -LiteralPath $env:FORGE_ACL_TEST; "
        if protect:
            command += "$acl.SetAccessRuleProtection($true,$true); Set-Acl -LiteralPath $env:FORGE_ACL_TEST -AclObject $acl; $acl=Get-Acl -LiteralPath $env:FORGE_ACL_TEST; "
        command += "$acl.Sddl"
        return run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', command],
                   extra={'FORGE_ACL_TEST': str(path)}).stdout.strip()

    def strict():
        local.write_text(json.dumps(original))
        local.chmod(0o600)

    def connected():
        expected = json.loads(json.dumps(original))
        expected['sandbox']['enabled'] = False
        assert json.loads(local.read_text()) == expected, 'connected default changed unrelated local entries'
        if os.name != 'nt':
            assert stat.S_IMODE(local.stat().st_mode) == 0o600
        assert 'network_access = true' in config.read_text()
        assert '[profiles.keep]\nmodel = "gpt-6-astra"\n' in config.read_text(), 'outside TOML changed'
        assert not (project / '.forge/local/connected-development.json').exists()

    run(['git', 'init', '-q', '--initial-branch=main'])
    run(['git', 'config', 'user.name', 'Fixture'])
    run(['git', 'config', 'user.email', 'fixture@example.invalid'])
    (project / 'app.txt').write_text('application\n')
    run(['git', 'add', 'app.txt'])
    run(['git', 'commit', '-qm', 'fixture'])
    setup()
    assert json.loads(local.read_text()) == {'sandbox': {'enabled': False}}
    assert 'network_access = true' in config.read_text()
    print(f'PASS {args.engine}: fresh setup is connected without selection', flush=True)
    shared = project / '.claude/settings.json'
    shared_value = json.loads(shared.read_text())
    shared_value['sandbox'] = {'enabled': True, 'allowUnsandboxedCommands': False}
    shared.write_text(json.dumps(shared_value))
    ignore = project / '.gitignore'
    ignore.write_bytes(b'# project ignores\r\n.env\r\nnode_modules/\r\ncustom-output/\r\n.forge/local/\r\n.claude/settings.local.json\r\n')
    config.write_text(config.read_text().replace('network_access = true', 'network_access = false') + '\n[profiles.keep]\nmodel = "gpt-6-astra"\n')
    strict()
    setup('--upgrade')
    connected()
    assert json.loads(shared.read_text())['sandbox'] == shared_value['sandbox'], 'upgrade changed shared sandbox instead of the local default'
    ignore_before = ignore.read_bytes()
    print(f'PASS {args.engine}: ordinary upgrade migrates old restrictions and preserves unrelated values', flush=True)
    strict()
    acl_before = windows_acl(protect=True) if os.name == 'nt' else None
    before = snapshot()
    setup('--force', '--dry-run')
    assert snapshot() == before, 'full-refresh preview changed live bytes or modes'
    setup('--force')
    connected()
    if os.name == 'nt':
        assert windows_acl() == acl_before, 'full refresh changed local settings ACLs'
        backups = list((project / '.forge/local/migration-backups').glob('*/.claude/settings.local.json'))
        assert backups, 'full refresh did not preserve its original local settings backup'
        assert all(windows_acl(path=p) == acl_before for p in backups), 'backup broadened local settings ACLs'
    assert ignore.read_bytes() == ignore_before, 'full refresh changed fully covered project ignore bytes'
    print(f'PASS {args.engine}: full refresh stages connected local settings; preview is read-only', flush=True)
    strict()
    before_local = local.read_bytes(), stat.S_IMODE(local.stat().st_mode)
    setup('--force', success=False, extra={'FORGE_FULL_REFRESH_FAIL_AFTER': '@penultimate'})
    assert (local.read_bytes(), stat.S_IMODE(local.stat().st_mode)) == before_local, 'rollback failed to restore strict local settings'
    if os.name == 'nt':
        assert windows_acl() == acl_before, 'rollback changed local settings ACLs'
    assert ignore.read_bytes() == ignore_before, 'rollback changed project ignore bytes'
    print(f'PASS {args.engine}: injected transaction failure restores local settings bytes and modes', flush=True)
    local.write_text('{malformed')
    before = snapshot()
    setup('--force', success=False)
    assert snapshot() == before, 'malformed local settings mutated a full refresh'
    print(f'PASS {args.engine}: malformed local settings block full refresh before writes', flush=True)
