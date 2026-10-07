#!/usr/bin/env python3
"""Focused real PS7 transport/reproduction feedback, never Windows qualification."""
import os, shutil, signal, subprocess, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PWSH=shutil.which("pwsh")
if not PWSH:
    print("SKIP: portable PowerShell behavior requires pwsh; native coverage unverified")
    raise SystemExit(0)
if os.name != "posix":
    print("SKIP: POSIX boundary fixture; native Windows coverage belongs to CI")
    raise SystemExit(0)
def command(args, env, log, timeout):
    with log.open("w") as out:
        p=subprocess.Popen(args, stdout=out, stderr=subprocess.STDOUT, env=env, start_new_session=True)
        try: rc=p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL); p.wait(timeout=5)
            raise AssertionError("focused fixture outer deadline expired: "+str(log))
    text=log.read_text()
    if rc:
        print(text)
    else:
        print("\n".join(line for line in text.splitlines() if line.startswith(("PASS", "FAIL", "CASE", "test-setup-transport"))))
    assert rc==0, "focused fixture failed: "+str(log)
with tempfile.TemporaryDirectory(prefix="forge-powershell-local-", dir=Path(tempfile.gettempdir()).resolve()) as raw:
    work=Path(raw); bin=work/"bin"; bin.mkdir()
    shims={
      "powershell.exe": '#!/bin/sh\nexec "'+PWSH+'" "$@"\n',
      "taskkill.exe": '#!/bin/sh\n# Only kills descendants of the fixture dispatcher child supplied by production.\npid=""; prev=""\nfor a in "$@"; do [ "$prev" = "/PID" ] && pid="$a"; prev="$a"; done\n[ -n "$pid" ] || exit 1\nkill_tree() { for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done; kill -KILL "$1" 2>/dev/null || true; }\nkill_tree "$pid"\n',
      "codex": '#!/bin/sh\njoined="$*"; output=""; prev=""\nfor a in "$@"; do [ "$prev" = "--output-last-message" ] && output="$a"; prev="$a"; done\nprintf \'cwd=%s argv=%s\n\' "$(pwd)" "$joined" >> "$FAKE_CODEX_LOG"\ncase "$joined" in *"--sandbox workspace-write"*) ;; *) exit 69;; esac\n[ -n "$FORGE_REPRO_RUNNER" ] || exit 70\ncase "$FAKE_CODEX_BEHAVIOR" in\n  repro-boundary-slow-*) sleep 20 & delay=$!; printf \'descendant_pid=%s\n\' "$delay" >> "$FAKE_CODEX_LOG"; wait "$delay";;\n  repro-boundary) ;; *) exit 64;; esac\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "$FORGE_REPRO_RUNNER"; rc=$?\n[ "$rc" -eq 0 ] || exit "$rc"\nprintf \'schema_version=1\nverdict=CLEAN\nmax_severity=NONE\nblocked_class=none\nforge_canary_hash=%s\nforge_config_hash=%s\nforge_qualification_revision=%s\n\' "${FORGE_DISPATCH_CANARY_HASH:-MISSING}" "${FORGE_DISPATCH_CONFIG_HASH:-MISSING}" "${FORGE_DISPATCH_QUALIFICATION_REVISION:-MISSING}" > "$output"\n'
    }
    for name,text in shims.items():
        p=bin/name; p.write_text(text); p.chmod(0o755)
    env=dict(os.environ, PATH=str(bin)+os.pathsep+os.environ["PATH"], RUNNER_TEMP=str(work))
    command([PWSH,"-NoProfile","-File",str(ROOT/"tests/template/test-setup-transport.ps1")],env,work/"transport.log",75)
    for name,behavior,budget in (("positive","repro-boundary",30),("timeout","repro-boundary-slow-20",3)):
        command([PWSH,"-NoProfile","-File",str(ROOT/"tests/support/portable-dispatch-case.ps1"),"-SourceRoot",str(ROOT),"-WorkDirectory",str(work),"-BinDirectory",str(bin),"-CaseName",name,"-Behavior",behavior,"-TimeoutSeconds",str(budget)],env,work/(name+".log"),55)
        values=dict(line.split("=",1) for line in (work/(name+".receipt")).read_text().splitlines() if "=" in line)
        if name=="positive":
            assert values["primary_check_hash"]=="573645001e97c1fac372ffaeeef2b6eb9c4bc1caa7c28069c4203ea159f29bc4"
            assert values["control_hash"]=="dc8fc650d354d9bed81e65cb094ece651f71ed854abc3738e41b0384245e6abf"
            assert values["reproduction_status"]=="REPRODUCED"
        else:
            assert values["failure_reason"]=="timeout" and values["process_exit_status"]=="124"
            assert values["reproduction_status"]=="UNVERIFIED"
            ids=[int(line.split("=",1)[1]) for line in (work/(name+".engine.log")).read_text().splitlines() if line.startswith("descendant_pid=")]
            assert len(ids)==1, "actual delayed descendant must be observed"
            for pid in ids:
                probe=subprocess.run(["ps","-o","stat=","-p",str(pid)],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                assert probe.returncode!=0 or probe.stdout.strip().startswith("Z"), "owned delayed descendant still running"
            print("PASS: deliberate timeout terminates observed disposable descendant")
    print("PASS: real portable transport and dispatcher boundary; Windows5.1 remains CI-owned")
