#!/usr/bin/env python3
"""Focused real-renderer controls; PS functions come from the actual materializer."""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
scratch = pathlib.Path(tempfile.mkdtemp(prefix="forge-mcp-reuse-"))
template = root / "settings/codex-config.template.toml"
defaults = json.loads((root / "mcp.template.json").read_text())
custom = {"mcpServers": {name: {"type": "stdio", "command": "fixture-server", "args": ["--custom"], "env": {"TOKEN": "${FIXTURE_TOKEN}"}} for name in ("context7", "playwright")}}
custom_prefixed = {"mcpServers": {"forge_" + name: server for name, server in custom["mcpServers"].items()}}
context = b'[mcp_servers.context7]\nurl = "https://mcp.context7.com/mcp"\nbearer_token_env_var = "FIXTURE_TOKEN"\n'
playwright = b'[mcp_servers.playwright]\ncommand = "npx"\nargs = ["@playwright/mcp@latest", "--headless"]\n'
prefixed = context.replace(b".context7]", b".forge_context7]") + playwright.replace(b".playwright]", b".forge_playwright]")
cases = [
    ("fresh", b"", defaults, {"forge_context7", "forge_playwright"}),
    ("context", context, defaults, {"context7", "forge_playwright"}),
    ("playwright", playwright, defaults, {"forge_context7", "playwright"}),
    ("both", context + playwright, defaults, {"context7", "playwright"}),
    ("crlf-comments", (context + playwright).replace(b"]\n", b"] # chosen server\n").replace(b"\n", b"\r\n"), custom, {"context7", "playwright"}),
    ("managed-duplicates", context + playwright + template.read_bytes(), defaults, {"context7", "playwright"}),
    ("outside-suffix", template.read_bytes() + context + playwright, defaults, {"context7", "playwright"}),
    ("prefixed", prefixed, custom, {"forge_context7", "forge_playwright"}),
    ("custom-translation", b"", custom, {"context7", "playwright"}),
    ("prefixed-translation", b"", custom_prefixed, {"forge_context7", "forge_playwright"}),
    ("outside-wins", context + playwright, custom, {"context7", "playwright"}),
    ("quoted", context.replace(b".context7]", b'."context7"]') + playwright.replace(b".playwright]", b".'playwright']"), custom, {"context7", "playwright"}),
]
backends = ["python"]
pwsh = sys.argv[2] if len(sys.argv) > 2 else shutil.which("pwsh")
if pwsh:
    backends.append("powershell")
    source = (root / "scripts/materialize-adapters.ps1").read_text()
    # Execute the production functions without running unrelated installation.
    functions = source[source.index("function Convert-McpJsonToCodexToml"):source.index("function Get-EngineAvailability")]
    (scratch / "render.ps1").write_text('param($Template,$Destination,$McpJson)\n$ErrorActionPreference="Stop"\n$Utf8NoBom=New-Object Text.UTF8Encoding($false)\nfunction Get-Command { return $null }\n' + functions + '\nSet-CodexTomlBlock $Template $Destination $McpJson\n')
else:
    print("SKIP: PowerShell MCP controls (PowerShell unavailable)")
failures = []
count = 0
for backend in backends:
    for name, initial, mcp, expected in cases:
        directory = scratch / (backend + "-" + name)
        directory.mkdir()
        config = directory / "config.toml"
        config.write_bytes(initial)
        mcp_path = directory / "mcp.json"
        mcp_path.write_text(json.dumps(mcp))
        ps_policy = ["-ExecutionPolicy", "Bypass"] if pwsh and pathlib.Path(pwsh).name.lower() == "powershell.exe" else []
        command = ([sys.executable, str(root / "scripts/render-codex-config.py"), "--template", str(template), "--existing", str(config), "--output", str(config), "--mcp-json", str(mcp_path)] if backend == "python" else [pwsh, "-NoProfile", *ps_policy, "-File", str(scratch / "render.ps1"), str(template), str(config), str(mcp_path)])
        try:
            result = subprocess.run(command, capture_output=True, text=True)
            assert result.returncode == 0, result.stdout + result.stderr
            rendered = config.read_bytes()
            prefix = initial.split(b"# forge:begin v6")[0]
            assert rendered.startswith(prefix), "outside bytes changed"
            if b"# forge:end v6\n" in initial:
                suffix = initial.split(b"# forge:end v6\n", 1)[1]
                assert rendered.endswith(suffix), "outside suffix bytes changed"
            # Fixtures contain only known MCP tables; normalize quoted names.
            import re
            tables = re.findall(rb"^\[mcp_servers\.([^\]]+)\]", rendered, re.M)
            names = [value.strip(b"\"'").decode() for value in tables]
            assert set(names) == expected and len(names) == len(expected), names
            again = subprocess.run(command, capture_output=True, text=True)
            assert again.returncode == 0 and config.read_bytes() == rendered, "not idempotent"
            count += 1
        except AssertionError as exc:
            failures.append(f"{backend}/{name}: {exc}")
    for broken in (b"# forge:begin v6\n", b"# forge:end v6\n# forge:begin v6\n"):
        config.write_bytes(broken)
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode == 0 or config.read_bytes() != broken:
            failures.append(f"{backend}: malformed marker accepted/mutated")
        else:
            count += 1
print(f"MCP reuse controls: {count} passed, {len(failures)} failed; raw {scratch}")
for failure in failures:
    print(failure)
sys.exit(bool(failures))
