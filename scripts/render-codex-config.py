#!/usr/bin/env python3
"""Render one bounded Forge block into an otherwise opaque Codex TOML file.

This deliberately does not parse TOML. The complete staged file is handed to
the qualified Codex loader (or an explicit test validator) before promotion.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List, Optional, Tuple

BEGIN = b"# forge:begin v6"
END = b"# forge:end v6"
SAFE_NAME = re.compile(r"^[A-Za-z0-9_-]+$")
ENV_REFERENCE = re.compile(r"^\$\{[A-Za-z_][A-Za-z0-9_]*\}$")


def owned_block(template: bytes) -> bytes:
    if template.count(BEGIN) != 1 or template.count(END) != 1:
        raise ValueError("template must contain exactly one Forge v6 marker pair")
    start = template.index(BEGIN)
    finish = template.index(END, start) + len(END)
    return template[start:finish].rstrip(b"\r\n") + b"\n"


def merge_block(existing: bytes, block: bytes) -> bytes:
    begins = existing.count(BEGIN)
    ends = existing.count(END)
    if begins == 0 and ends == 0:
        separator = b"" if not existing or existing.endswith((b"\n", b"\r")) else b"\n"
        return existing + separator + block
    if begins != 1 or ends != 1:
        raise ValueError("malformed or duplicate Forge v6 marker")
    start = existing.index(BEGIN)
    finish = existing.index(END)
    if finish < start:
        raise ValueError("Forge v6 end marker precedes begin marker")
    finish += len(END)
    if finish < len(existing) and existing[finish : finish + 2] == b"\r\n":
        finish += 2
    elif finish < len(existing) and existing[finish : finish + 1] == b"\n":
        finish += 1
    return existing[:start] + block + existing[finish:]


def toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=True)


def translated_mcp(path: Path) -> Tuple[bytes, List[str]]:
    if not path.exists():
        return b"", []
    payload = json.loads(path.read_text(encoding="utf-8"))
    servers = payload.get("mcpServers", {})
    if not isinstance(servers, dict):
        return b"", ["mcpServers is not an object"]
    lines: List[str] = []
    blocked: List[str] = []
    for name, server in sorted(servers.items()):
        if not SAFE_NAME.fullmatch(name) or not isinstance(server, dict):
            blocked.append(f"unsupported MCP server {name!r}")
            continue
        # The clean-install defaults are already present under Forge-prefixed
        # fallback names in the static template so setup works without Python.
        # Do not launch the same server twice when translating that unchanged
        # user-owned source.
        if name == "playwright" and server == {
            "type": "stdio",
            "command": "npx",
            "args": ["-y", "@playwright/mcp@latest"],
            "env": {},
        }:
            continue
        if name == "context7" and server == {
            "type": "http",
            "url": "https://mcp.context7.com/mcp",
        }:
            continue
        unknown = set(server) - {"type", "command", "args", "env", "cwd", "transport", "url"}
        if unknown:
            blocked.append(f"{name}: unsupported fields {','.join(sorted(unknown))}")
            continue
        command = server.get("command")
        args = server.get("args", [])
        env = server.get("env", {})
        transport_type = server.get("type", "stdio")
        if transport_type not in ("stdio", None):
            blocked.append(f"{name}: transport type {transport_type!r} is not safely translatable")
            continue
        if not isinstance(command, str) or not isinstance(args, list) or not all(isinstance(v, str) for v in args):
            blocked.append(f"{name}: command/args transport is not safely translatable")
            continue
        if not isinstance(env, dict) or any(
            not isinstance(key, str)
            or not isinstance(value, str)
            or not ENV_REFERENCE.fullmatch(value)
            for key, value in env.items()
        ):
            blocked.append(f"{name}: literal or malformed env value preserved only in .mcp.json")
            continue
        lines.extend(
            [
                "",
                f"[mcp_servers.{name}]",
                f"command = {toml_string(command)}",
                "args = [" + ", ".join(toml_string(v) for v in args) + "]",
            ]
        )
        if env:
            rendered_env = ", ".join(f"{toml_string(k)} = {toml_string(v)}" for k, v in sorted(env.items()))
            lines.append(f"env = {{ {rendered_env} }}")
    return ("\n".join(lines) + ("\n" if lines else "")).encode(), blocked


def validate(candidate: Path, validator: Optional[str], codex: Optional[str]) -> Tuple[bool, str]:
    if validator:
        result = subprocess.run([validator, str(candidate)], capture_output=True, text=True, check=False)
        return result.returncode == 0, (result.stderr or result.stdout).strip()
    if codex:
        probe = subprocess.run([codex, "doctor", "--help"], capture_output=True, text=True, check=False)
        if probe.returncode != 0 or "--json" not in (probe.stdout + probe.stderr):
            return True, "PENDING: installed Codex exposes no qualified doctor --json validator"
        fixture = Path(tempfile.mkdtemp(prefix="forge-codex-validator-"))
        try:
            project = fixture / "project"
            codex_home = fixture / "codex-home"
            (project / ".codex").mkdir(parents=True)
            codex_home.mkdir()
            # Current Codex doctor reports the user config it loaded, not the
            # project candidate. Put the same complete staged bytes at both
            # paths inside a disposable validator fixture. The installed
            # destination remains project-local.
            (project / ".codex" / "config.toml").write_bytes(candidate.read_bytes())
            (codex_home / "config.toml").write_bytes(candidate.read_bytes())
            environment = os.environ.copy()
            environment["CODEX_HOME"] = str(codex_home)
            result = subprocess.run(
                [codex, "--strict-config", "-C", str(project), "doctor", "--json"],
                capture_output=True,
                text=True,
                check=False,
                env=environment,
            )
            try:
                receipt = json.loads(result.stdout)
                config_load = receipt["checks"]["config.load"]
            except (json.JSONDecodeError, KeyError, TypeError):
                return False, (result.stderr or result.stdout or "Codex doctor emitted no config.load receipt").strip()
            if config_load.get("status") != "ok":
                return False, str(config_load.get("summary") or config_load)
            # Doctor legitimately returns nonzero for unrelated auth/network or
            # terminal checks. Only its structured config.load check owns this
            # validation decision.
            return True, "VALIDATED: " + str(config_load.get("summary", "config loaded"))
        finally:
            import shutil

            shutil.rmtree(fixture, ignore_errors=True)
    return True, "PENDING: Codex config validator unavailable"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", required=True, type=Path)
    parser.add_argument("--existing", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--validator")
    parser.add_argument("--codex-validator")
    parser.add_argument("--mcp-json", type=Path)
    args = parser.parse_args()

    try:
        existing = args.existing.read_bytes() if args.existing.exists() else b""
        block = owned_block(args.template.read_bytes())
        translated, blocked = translated_mcp(args.mcp_json) if args.mcp_json else (b"", [])
        if translated:
            block = block.replace(END + b"\n", translated + END + b"\n")
        candidate_bytes = merge_block(existing, block)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"BLOCKED: cannot stage Codex config: {exc}", file=sys.stderr)
        return 2

    args.output.parent.mkdir(parents=True, exist_ok=True)
    handle, tmp_name = tempfile.mkstemp(prefix=".forge-config-", dir=str(args.output.parent))
    os.close(handle)
    candidate = Path(tmp_name)
    try:
        candidate.write_bytes(candidate_bytes)
        ok, diagnostic = validate(candidate, args.validator, args.codex_validator)
        if not ok:
            print(f"BLOCKED: Codex rejected staged config: {diagnostic}", file=sys.stderr)
            return 3
        os.replace(candidate, args.output)
        if blocked:
            print("CODEX_MCP_PARITY: BLOCKED: " + "; ".join(blocked))
        if diagnostic:
            print("CODEX_CONFIG_READINESS: " + diagnostic)
        else:
            print("CODEX_CONFIG_READINESS: VALIDATED")
        return 0
    finally:
        candidate.unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(main())
