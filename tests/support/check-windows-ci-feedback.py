#!/usr/bin/env python3
"""Portable fixture contracts. Synthetic 5.1 metadata is never native qualification."""
import copy, json, os, shutil, subprocess, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
if os.name != "posix":
    print("SKIP: POSIX CI feedback fixture; native Windows suites remain CI-owned")
    raise SystemExit(0)
PWSH = shutil.which("pwsh")
if not PWSH:
    print("SKIP: CI feedback fixture requires pwsh; native coverage unverified")
    raise SystemExit(0)
def run(args, env=None):
    return subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, timeout=45)
with tempfile.TemporaryDirectory(prefix="forge-ci-feedback-", dir=Path(tempfile.gettempdir()).resolve()) as temp:
    temp=Path(temp); repo=temp/"checkout"; suites=repo/"tests/template"; suites.mkdir(parents=True)
    shutil.copy2(ROOT/"tests/template/run-all.ps1", suites/"run-all.ps1")
    (suites/"test-a-pass.ps1").write_text('Write-Host "literal-A"; exit 0\n')
    (suites/"test-b-fail.ps1").write_text('Write-Host "literal-B"; exit 7\n')
    for args in (["init","-q"],["config","user.email","test@example.invalid"],["config","user.name","Fixture"],["add","."],["commit","-qm","fixture"]):
        assert run(["git","-C",str(repo)]+args).returncode==0
    bin=temp/"bin"; bin.mkdir(); shim=bin/"powershell.exe"; shim.write_text('#!/bin/sh\nexec "'+PWSH+'" "$@"\n'); shim.chmod(0o755)
    env=dict(os.environ, PATH=str(bin)+os.pathsep+os.environ["PATH"])
    runner=[PWSH,"-NoProfile","-File",str(suites/"run-all.ps1")]
    listed=run(runner+["-ListSuites"],env)
    assert listed.returncode==0, "runner discovery must exit zero without executing suites: "+listed.stdout
    names=json.loads(listed.stdout); assert names==["test-a-pass.ps1","test-b-fail.ps1"], names
    print("PASS: exact discovered fixture names")
    result=temp/"results"; result.mkdir(); good=result/"a.result.json"; bad=result/"b.result.json"
    selected=run(runner+["-SuiteName",names[0],"-ResultPath",str(good)],env)
    assert selected.returncode==0 and "literal-A" in selected.stdout and "literal-B" not in selected.stdout, selected.stdout
    data=json.loads(good.read_text()); assert data["suite"]==names[0] and data["exit_code"]==0 and data["clean_before"] and data["clean_after"]
    failed=run(runner+["-SuiteName",names[1],"-ResultPath",str(bad)],env)
    assert failed.returncode!=0 and json.loads(bad.read_text())["exit_code"]==7
    for name in ("../test-a-pass.ps1","TEST-A-PASS.ps1","test-missing.ps1"):
        invalid=run(runner+["-SuiteName",name,"-ResultPath",str(temp/"invalid.result.json")],env)
        assert invalid.returncode!=0 and not (temp/"invalid.result.json").exists(), name
    inside=run(runner+["-SuiteName",names[0],"-ResultPath",str(repo/"result.json")],env)
    assert inside.returncode!=0 and not (repo/"result.json").exists()
    print("PASS: real selection, failure exit, exact selector and outside-checkout results")
    # A suite which dirties tracked content must report post-run dirtiness.
    (suites/"test-a-pass.ps1").write_text('Add-Content -LiteralPath $PSCommandPath -Value "# mutated"; exit 0\n')
    for args in (["add","."],["commit","-qm","dirty-fixture"]): assert run(["git","-C",str(repo)]+args).returncode==0
    dirty=run(runner+["-SuiteName",names[0],"-ResultPath",str(temp/"dirty.result.json")],env)
    assert not json.loads((temp/"dirty.result.json").read_text())["clean_after"]
    run(["git","-C",str(repo),"restore","."])
    head=run(["git","-C",str(repo),"rev-parse","HEAD"]).stdout.strip(); tree=run(["git","-C",str(repo),"rev-parse","HEAD^{tree}"]).stdout.strip()
    expected=temp/"suites.json"; expected.write_text(json.dumps(names))
    validator=[PWSH,"-NoProfile","-File",str(ROOT/"scripts/validate-windows-suite-results.ps1"),"-ProjectRoot",str(repo),"-ResultsDirectory",str(result),"-ExpectedSuitesPath",str(expected),"-DependencyStatus","success"]
    # Literal validator fixtures claim 5.1 only to exercise rejection logic, not to attest.
    base={"format":"forge-windows-suite-v1","head_before":head,"tree_before":tree,"head_after":head,"tree_after":tree,"clean_before":True,"clean_after":True,"ps_major":5,"ps_minor":1,"os":"Windows_NT","exit_code":0,"elapsed_seconds":1.25}
    def fixtures(rows):
        for p in result.glob("*.json"): p.unlink()
        for i,row in enumerate(rows): (result/(str(i)+".result.json")).write_text(json.dumps(row))
    rows=[dict(base,suite=n) for n in names]
    fixtures(rows); valid=run(validator,env); assert valid.returncode==0, valid.stdout
    print("PASS: complete literal validator fixture")
    # Windows PS5.1 emits each JSON array as one pipeline object. Exercise that
    # real shape on PS7 by shadowing only decoding, not the validator under test.
    ps51=temp/"ps51-json-shape.ps1"
    ps51.write_text("""param([string]$ValidatorPath,[string]$ProjectRoot,[string]$ResultsDirectory,[string]$ExpectedSuitesPath,[string]$DependencyStatus)
$ErrorActionPreference='Stop'
function ConvertFrom-Json {
    [CmdletBinding()] param([Parameter(Mandatory=$true,ValueFromPipeline=$true)][string]$InputObject)
    process { Microsoft.PowerShell.Utility\\ConvertFrom-Json -InputObject $InputObject -NoEnumerate }
}
& $ValidatorPath -ProjectRoot $ProjectRoot -ResultsDirectory $ResultsDirectory -ExpectedSuitesPath $ExpectedSuitesPath -DependencyStatus $DependencyStatus
""")
    nonenumerating=[PWSH,"-NoProfile","-File",str(ps51),"-ValidatorPath",validator[3]]+validator[4:]
    shape_valid=run(nonenumerating,env)
    assert shape_valid.returncode==0, "PS5.1 nonenumerating JSON-array coverage must pass: "+shape_valid.stdout
    assert "(2 suites)" in shape_valid.stdout, "both literal suite names must be counted"
    print("PASS: real validator accepts complete coverage with PS5.1 nonenumerating JSON arrays")
    negatives=[("missing",rows[:1]),("duplicate",rows+[rows[0]]),("unknown",rows+[dict(base,suite="test-unknown.ps1")])]
    for label,key,value in [("failed","exit_code",7),("wrong-head","head_after","0"*40),("wrong-tree","tree_before","0"*40),("PS7","ps_major",7),("string-runtime","ps_major","5"),("Linux","os","Unix"),("dirty","clean_after",False),("negative-time","elapsed_seconds",-1),("missing-field","clean_before",None)]:
        changed=copy.deepcopy(rows); changed[0][key]=value; negatives.append((label,changed))
    for label,changed in negatives:
        fixtures(changed); rejected=run(validator,env); assert rejected.returncode!=0, label+": "+rejected.stdout
        rejected_shape=run(nonenumerating,env); assert rejected_shape.returncode!=0, "PS5.1 "+label+": "+rejected_shape.stdout
    fixtures(rows)
    for state in ("failure","cancelled","skipped"):
        rejected=run(validator[:-1]+[state],env); assert rejected.returncode!=0, state
    expected.write_text(json.dumps(names[:1])); assert run(validator,env).returncode!=0
    print("PASS: missing/duplicate/unknown/failed/identity/runtime/dirty/dependency/discovery mismatch fail closed")
    assert not list(temp.rglob("*.receipt")), "validator cannot generate native attestation"
    fast=(ROOT/"tests/template/run-fast.sh").read_text()
    for name in ("test-powershell-runner.sh","test-powershell-local.sh","test-windows-ci-feedback.sh"):
        assert name in fast, "fast gate must register "+name
    assert len(list((ROOT/"tests/template").glob("test-*.ps1")))==18
    print("PASS: portable fast registration; native discovery remains 18 suites; no attestation")
