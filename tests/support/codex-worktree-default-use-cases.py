import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, required=True)
parser.add_argument('--engine', choices=('bash', 'powershell'), required=True)
args = parser.parse_args()
source = args.source_root.resolve()
env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_COUNT='0')
with tempfile.TemporaryDirectory(prefix='forge-old-codex-base-') as temporary:
    primary = Path(temporary).resolve() / 'project'
    (primary / 'manifests').mkdir(parents=True)
    (primary / '.codex').mkdir()
    (primary / '.forge/local').mkdir(parents=True)
    (primary / 'manifests/managed-v6.tsv').write_text('source-mode fixture\n')
    (primary / 'state.template.md').write_bytes((source / 'state.template.md').read_bytes())
    (primary / '.forge/local/state.md').write_bytes((source / 'state.template.md').read_bytes())
    (primary / '.gitignore').write_text('.forge/local/\n')
    outside = '# developer-owned prefix\n[profiles.keep]\nmodel = "gpt-6-astra"\n'
    original = ('\ufeff' + outside + (source / 'settings/codex-config.template.toml').read_text().replace('network_access = true', 'network_access = false')).replace('\n', '\r\n')
    (primary / '.codex/config.toml').write_bytes(original.encode('utf-8'))
    def run(command, cwd=primary):
        result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
        assert result.returncode == 0, (command, result.stdout, result.stderr)
        return result.stdout
    for command in (['git','init','-q','--initial-branch=main'], ['git','config','user.name','Fixture'],
                    ['git','config','user.email','fixture@example.invalid'], ['git','add','.'], ['git','commit','-qm','old base']):
        run(command)
    if args.engine == 'bash':
        command = ['bash', str(source / 'hooks/lib/worktree-lifecycle.sh'), 'create', '--kind','fix','--name','old-base','--base','HEAD']
    else:
        command = ['powershell.exe' if os.name == 'nt' else 'pwsh', '-NoProfile','-File',str(source / 'hooks/lib/worktree-lifecycle.ps1'),
                   '-Action','Create','-Kind','fix','-Name','old-base','-Base','HEAD']
    run(command)
    target = primary / '.worktrees/old-base'
    actual = (target / '.codex/config.toml').read_bytes()
    expected = original.replace('network_access = false', 'network_access = true').encode('utf-8')
    assert actual == expected, 'old-base create left Codex disconnected or altered unrelated TOML/BOM/CRLF'
    assert json.loads((target / '.claude/settings.local.json').read_text()) == {'sandbox': {'enabled': False}}
    print('PASS: old-base worktree receives both connected defaults and preserves outside TOML')
    assert run(['git', 'diff', '--name-only'], cwd=target).strip() == '.codex/config.toml'
    adopted = Path(temporary).resolve() / 'native-adopt'
    run(['git', 'worktree', 'add', '-qb', 'native-old', str(adopted), 'HEAD'])
    if args.engine == 'bash':
        command = ['bash', str(source / 'hooks/lib/worktree-lifecycle.sh'), 'adopt', '--kind','fix','--name','old-adopt','--base','HEAD','--worktree',str(adopted)]
    else:
        command = ['powershell.exe' if os.name == 'nt' else 'pwsh', '-NoProfile','-File',str(source / 'hooks/lib/worktree-lifecycle.ps1'),
                   '-Action','Adopt','-Kind','fix','-Name','old-adopt','-Base','HEAD','-Worktree',str(adopted)]
    run(command)
    assert (adopted / '.codex/config.toml').read_bytes() == expected
    assert json.loads((adopted / '.claude/settings.local.json').read_text()) == {'sandbox': {'enabled': False}}
    print('PASS: old-base native adoption updates only the managed network default')
    state = adopted / '.forge/local/state.md'
    snapshot = adopted / '.forge/local/.state-seed-snapshot.md'
    before = state.read_bytes(), snapshot.read_bytes()
    (adopted / '.codex/config.toml').write_bytes(original.encode('utf-8'))
    (adopted / '.claude/settings.local.json').write_text('{"sandbox":{"enabled":true}}')
    assert run(['git', 'status', '--porcelain'], cwd=adopted) == ''
    run(command)
    assert (adopted / '.codex/config.toml').read_bytes() == expected, 'seeded adoption left Codex disconnected'
    assert json.loads((adopted / '.claude/settings.local.json').read_text())['sandbox']['enabled'] is False
    assert (state.read_bytes(), snapshot.read_bytes()) == before, 'seeded adoption rewrote continuity'
    print('PASS: already-seeded adoption applies both defaults and preserves continuity bytes')
