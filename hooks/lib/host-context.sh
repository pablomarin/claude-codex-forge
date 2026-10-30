#!/usr/bin/env bash
# Stable native-host metadata adapter and fixed Forge dispatcher launcher.
set -u

die_context() { printf 'BLOCKED[invariant]: %s\n' "$*" >&2; exit 2; }
root_context() { git rev-parse --show-toplevel 2>/dev/null || die_context 'not inside a Git worktree'; }
physical_root_context() { local root; root=$(root_context); (cd "$root" && pwd -P); }
test_mode_allowed_context() {
    local root script_parent script
    root=$(physical_root_context)
    script_parent=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || die_context 'cannot resolve host launcher script'
    script="$script_parent/$(basename "$0")"
    case "$script" in "$root"/*) die_context 'test launcher override is disabled in an installed harness' ;; esac
}
canonical_target_context() {
    local requested="$1" label="$2" parent
    [ -f "$requested" ] && [ ! -L "$requested" ] || die_context "fixed $label dispatcher is unavailable"
    parent=$(cd "$(dirname "$requested")" 2>/dev/null && pwd -P) || die_context "cannot resolve fixed $label dispatcher"
    printf '%s/%s\n' "$parent" "$(basename "$requested")"
}
launcher_context() {
    local root requested
    root=$(physical_root_context)
    requested="$root/.forge/hooks/lib/agent-dispatch.sh"
    if [ "${FORGE_HOST_CONTEXT_TEST_MODE:-0}" = 1 ] && [ -n "${FORGE_HOST_CONTEXT_TEST_LAUNCHER:-}" ]; then
        test_mode_allowed_context
        requested="$FORGE_HOST_CONTEXT_TEST_LAUNCHER"
    fi
    canonical_target_context "$requested" agent
}
council_context() {
    local root requested
    root=$(physical_root_context)
    requested="$root/.forge/hooks/lib/council-dispatch.sh"
    if [ "${FORGE_HOST_CONTEXT_TEST_MODE:-0}" = 1 ]; then
        test_mode_allowed_context
        if [ -n "${FORGE_HOST_CONTEXT_TEST_COUNCIL:-}" ]; then requested="$FORGE_HOST_CONTEXT_TEST_COUNCIL"; else requested=$(launcher_context); fi
    fi
    canonical_target_context "$requested" council
}
validate_host_context() {
    case "$1" in claude|codex) ;; *) die_context "$2 host must be claude or codex" ;; esac
}

# Diagnostic-only context checks. They create no registry, receipt or authority.
# Keep JSON and UTF-8 decoding out of shell variables: an embedded NUL must not
# disappear before validation. The legacy hook/launcher do not require Python.
probe_context() {
    command -v python3 >/dev/null 2>&1 || die_context 'Python 3 is required for the native context probe'
    python3 -I - "$0" "$@" 3<&0 <<'PY_CONTEXT'
import json
import os
import re
import subprocess
import sys

script, mode, *args = sys.argv[1:]
windows = os.name == 'nt' or sys.platform.startswith(('cygwin', 'msys'))
if not windows:
    windows = subprocess.run(['uname', '-s'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             text=True).stdout.startswith(('MINGW', 'MSYS', 'CYGWIN'))

def git(path, *arguments):
    result = subprocess.run(['git', '-C', path, *arguments], stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
    if result.returncode:
        raise ValueError('native directory is not a readable Git worktree')
    return result.stdout.rstrip('\r\n')

def physical(path):
    if windows and os.name != 'nt':
        # Git Bash/MSYS and native PowerShell must encode the same drive/UNC path.
        unix = subprocess.run(['cygpath', '-au', path], check=True, stdout=subprocess.PIPE,
                              text=True, encoding='utf-8').stdout.rstrip('\r\n')
        path = subprocess.run(['cygpath', '-am', os.path.realpath(unix)], check=True,
                              stdout=subprocess.PIPE, text=True, encoding='utf-8').stdout.rstrip('\r\n')
    else:
        path = os.path.realpath(path)
    return path.replace('\\', '/').lower() if windows else path

def identity(path):
    if not isinstance(path, str) or not path or any(ord(c) < 32 or ord(c) == 127 for c in path):
        raise ValueError('event cwd must be a nonempty absolute directory')
    absolute = os.path.isabs(path) or (windows and (re.match(r'^[A-Za-z]:[/\\]', path) or path.startswith('\\\\')))
    if not absolute:
        raise ValueError('event cwd must be an existing absolute directory')
    if windows and os.name != 'nt':
        # A native event can supply C:\... or UNC while MSYS Python expects /c/...
        path = subprocess.run(['cygpath', '-au', path], check=True, stdout=subprocess.PIPE,
                              text=True, encoding='utf-8').stdout.rstrip('\r\n')
    if not os.path.isdir(path):
        raise ValueError('event cwd must be an existing absolute directory')
    root = physical(git(path, 'rev-parse', '--show-toplevel'))
    common = git(path, 'rev-parse', '--git-common-dir')
    if not os.path.isabs(common) and not (windows and re.match(r'^[A-Za-z]:[/\\]', common)):
        common = os.path.join(path, common)
    return root, physical(common)

def decode(token):
    if not isinstance(token, str) or not re.fullmatch(r'(?:[0-9a-f]{2}){1,8192}', token):
        raise ValueError('expected root must be bounded, even lowercase hexadecimal')
    value = bytes.fromhex(token).decode('utf-8', errors='strict')
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError('expected root cannot contain NUL or control characters')
    absolute = value.startswith('/') or (windows and re.match(r'^[a-z]:/', value))
    if not absolute:
        raise ValueError('expected root must encode a canonical absolute path')
    # The literal is an assertion only. Never run Git or read state in this path.
    return value

def diagnostic(kind, status, expected, actual, common, reason):
    print(f'{kind}: {status} expected={expected} actual={actual} common={common}; {reason}', file=sys.stderr)
    if status == 'MISMATCH':
        print('Open or bind the native session to the existing intended worktree, then repeat the native probe and process check. Do not copy workflow state or bypass hooks.', file=sys.stderr)

def unique_object(pairs):
    result = {}
    seen = set()
    for key, value in pairs:
        # PowerShell property lookup is case-insensitive; neither host may select
        # a different value from an ambiguous cwd/Cwd or command/Command object.
        folded = key.casefold()
        if folded in seen:
            raise ValueError('duplicate JSON field')
        seen.add(folded)
        result[key] = value
    return result

# This only classifies the reserved diagnostic family for rejection. It never
# extracts a shipping target from arbitrary shell text or changes hook routing.
family_pattern = (r'(?:bash (?:\.forge/)?hooks/lib/host-context\.sh probe\b|'
                  r'(?:powershell\.exe|pwsh) -NoProfile -ExecutionPolicy Bypass -File '
                  r'(?:\.forge/)?hooks/lib/host-context\.ps1 -Mode probe\b)')
family = re.compile(family_pattern)
raw_family = re.compile(r'"command"\s*:\s*"' + family_pattern)
bash_probe = re.compile(r'bash (?:\.forge/)?hooks/lib/host-context\.sh probe ([0-9a-f]+)')
ps_probe = re.compile(r'(?:powershell\.exe|pwsh) -NoProfile -ExecutionPolicy Bypass -File (?:\.forge/)?hooks/lib/host-context\.ps1 -Mode probe -ExpectedRootHex ([0-9a-f]+)')
expected, actual, common = '<invalid>', '<unavailable>', '<unavailable>'
try:
    if mode == 'probe-event':
        raw = os.fdopen(3, encoding='utf-8').read()
        try:
            event = json.loads(raw, object_pairs_hook=unique_object)
        except (ValueError, UnicodeError):
            if not raw_family.search(raw):
                sys.exit(0)
            raise ValueError('recognizable probe has malformed or ambiguous JSON')
        if not isinstance(event, dict) or not isinstance(event.get('tool_input'), dict):
            if raw_family.search(raw):
                raise ValueError('native event and tool_input must be JSON objects')
            sys.exit(0)
        command = event['tool_input'].get('command')
        if not isinstance(command, str) or not family.match(command):
            sys.exit(0)
        if any(c in command for c in '\r\n\0'):
            raise ValueError('probe command must be one line without CR, LF or NUL')
        match = bash_probe.fullmatch(command) or ps_probe.fullmatch(command)
        if not match:
            raise ValueError('probe must use the exact prepared command with no extra tokens or compound actions')
        expected = decode(match.group(1))
        actual, common = identity(event.get('cwd'))
        if actual != expected:
            raise ValueError('native event does not identify the intended worktree')
        diagnostic('FORGE_NATIVE_CONTEXT', 'MATCH', expected, actual, common,
                   'intentional diagnostic denial; this is not shipping authority')
        sys.exit(2)
    if mode == 'prepare-context':
        if len(args) != 2 or args[0] != '--worktree':
            raise ValueError('prepare-context requires --worktree <absolute directory>')
        actual, common = identity(args[1])
        token = actual.encode('utf-8').hex()
        decode(token)
        relative = '.forge/hooks/lib/host-context.sh' if '/.forge/hooks/lib/' in os.path.abspath(script).replace('\\', '/') else 'hooks/lib/host-context.sh'
        print(f'bash {relative} probe {token}')
        print(f'bash {relative} check-process {token}')
        sys.exit(0)
    if mode == 'check-process':
        if len(args) != 1:
            raise ValueError('check-process requires exactly one expected-root token')
        expected = decode(args[0])
        actual, common = identity(os.getcwd())
        if actual != expected:
            raise ValueError('tool process does not identify the intended worktree')
        print(f'FORGE_PROCESS_CONTEXT: MATCH expected={expected} actual={actual} common={common}; native observation is separate')
        sys.exit(0)
    raise ValueError('unsupported context operation')
except (ValueError, UnicodeError, OSError, subprocess.SubprocessError) as error:
    diagnostic('FORGE_NATIVE_CONTEXT' if mode == 'probe-event' else 'FORGE_PROCESS_CONTEXT',
               'MISMATCH', expected, actual, common, str(error))
    sys.exit(2)
PY_CONTEXT
}

mode="${1:-}"
[ "$#" -gt 0 ] && shift
case "$mode" in
prepare-context|check-process|probe-event)
    probe_context "$mode" "$@"
    exit $?
    ;;
probe)
    printf '%s\n' 'FORGE_NATIVE_CONTEXT: UNVERIFIED native-hook-not-observed; the probe process executed instead of receiving a native diagnostic denial.' >&2
    exit 2
    ;;
hook)
    host=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --host) host="${2:-}"; shift 2 ;;
        *) die_context "unknown hook argument $1" ;;
        esac
    done
    validate_host_context "$host" hook
    cat >/dev/null 2>&1 || true
    ;;
launch)
    host=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --host) host="${2:-}"; shift 2 ;;
        --) shift; break ;;
        *) die_context "unknown launch argument $1" ;;
        esac
    done
    validate_host_context "$host" 'fixed launcher'
    launcher=$(launcher_context)
    council=$(council_context)
    [ "$#" -gt 0 ] || set -- "$launcher"
    requested="$1"
    [ -f "$requested" ] && [ ! -L "$requested" ] || die_context 'requested command is not a canonical Forge dispatcher'
    requested_parent=$(cd "$(dirname "$requested")" 2>/dev/null && pwd -P) || die_context 'cannot resolve requested launcher'
    requested="$requested_parent/$(basename "$requested")"
    [ "$requested" = "$launcher" ] || [ "$requested" = "$council" ] || die_context 'requested command is not a canonical Forge dispatcher'
    export FORGE_NATIVE_HOST="$host"
    unset FORGE_NATIVE_SESSION_ID FORGE_HOST_CONTEXT_FILE FORGE_HOST_CONTEXT_LAUNCHER_HASH
    exec "$@"
    ;;
*) die_context 'usage: host-context.sh hook|launch|prepare-context|probe|check-process|probe-event' ;;
esac
