#!/usr/bin/env python3
"""Preview and retire only proven bytes from Forge's legacy global harness."""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import hmac
import json
import os
import pathlib
import re
import stat
import tempfile
from collections.abc import Mapping
from typing import Any


MARKDOWN_BEGIN = b"<!-- forge:begin v6 -->"
MARKDOWN_END = b"<!-- forge:end v6 -->"
TOML_BEGIN = b"# forge:begin v6"
TOML_END = b"# forge:end v6"
VERSION = re.compile(rb"6(?:\.[0-9]+)?(?:\r?\n)?\Z")


@dataclasses.dataclass(frozen=True, order=True)
class Finding:
    action: str          # REMOVE, PRESERVE, BLOCKED, ABSENT
    path: str
    kind: str
    proof: str
    expected_sha256: str = ""


@dataclasses.dataclass(frozen=True)
class RetirementPlan:
    home: pathlib.Path
    platform: str
    findings: tuple[Finding, ...]


@dataclasses.dataclass
class PlannedChanges:
    replacements: dict[pathlib.Path, bytes]
    removals: set[pathlib.Path]
    removable_directories: set[pathlib.Path]
    covered_files: set[pathlib.Path]


def plan_digest(plan: RetirementPlan) -> str:
    rows = [dataclasses.asdict(item) for item in sorted(plan.findings)]
    payload = json.dumps(rows, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()


def file_sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def is_link_or_reparse(path: pathlib.Path) -> bool:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return False
    if stat.S_ISLNK(info.st_mode):
        return True
    attributes = getattr(info, "st_file_attributes", 0)
    return bool(attributes & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0))


def display(path: pathlib.Path, home: pathlib.Path) -> str:
    return path.relative_to(home).as_posix()


def regular_file(path: pathlib.Path) -> bool:
    return path.is_file() and not is_link_or_reparse(path)


def link_ancestor(home: pathlib.Path, relative: pathlib.PurePosixPath) -> pathlib.Path | None:
    current = home
    for part in relative.parts:
        current = current / part
        if is_link_or_reparse(current):
            return current
        if not current.exists():
            return None
    return None


def read_inventory(repo_root: pathlib.Path, platform: str) -> list[tuple[str, str, str]]:
    path = repo_root / "manifests/legacy-v6-global.tsv"
    rows: list[tuple[str, str, str]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 4:
            raise ValueError(f"malformed cleanup inventory row {line_number}")
        kind, destination, row_platform, proof = fields
        relative = pathlib.PurePosixPath(destination)
        if relative.is_absolute() or ".." in relative.parts or destination.startswith("~"):
            raise ValueError(f"unsafe cleanup inventory destination on row {line_number}")
        if row_platform in {"all", platform}:
            rows.append((kind, destination, proof))
    return rows


def read_installed_hashes(home: pathlib.Path) -> tuple[dict[str, str], Finding | None]:
    relative = pathlib.PurePosixPath(".forge/installed-files.tsv")
    receipt = home / relative
    unsafe = link_ancestor(home, relative)
    if unsafe is not None:
        return {}, Finding("BLOCKED", display(unsafe, home), "canonical", "linked-path")
    if not receipt.exists():
        return {}, None
    if not regular_file(receipt):
        return {}, Finding("BLOCKED", relative.as_posix(), "canonical", "not-regular")
    result: dict[str, str] = {}
    try:
        lines = receipt.read_text(encoding="utf-8").splitlines()
        for line_number, line in enumerate(lines, 1):
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) != 3 or not re.fullmatch(r"[0-9a-fA-F]{64}", fields[1]):
                raise ValueError(f"malformed installed-files.tsv row {line_number}")
            if fields[0] in result:
                raise ValueError(f"duplicate installed-files.tsv path {fields[0]}")
            result[fields[0]] = fields[1].lower()
    except (OSError, UnicodeError, ValueError) as exc:
        return {}, Finding("BLOCKED", relative.as_posix(), "canonical", str(exc))
    return result, None


def trim_marker_block(content: bytes, begin: bytes, end: bytes) -> tuple[bytes, bool]:
    begins = content.count(begin)
    ends = content.count(end)
    if begins == 0 and ends == 0:
        return content, True
    if begins != 1 or ends != 1:
        raise ValueError("malformed-or-duplicate-marker")
    start = content.index(begin)
    finish = content.index(end)
    if finish < start:
        raise ValueError("marker-end-precedes-begin")
    finish += len(end)
    if content[finish : finish + 2] == b"\r\n":
        finish += 2
    elif content[finish : finish + 1] == b"\n":
        finish += 1
    return content[:start] + content[finish:], bool(content[:start] or content[finish:])


_MISSING = object()


def subtract_managed(current: Any, managed: Any) -> tuple[Any, bool]:
    if isinstance(managed, Mapping) and isinstance(current, Mapping):
        result = dict(current)
        changed = False
        for key, managed_value in managed.items():
            if key not in result:
                continue
            candidate, child_changed = subtract_managed(result[key], managed_value)
            if child_changed:
                changed = True
                if candidate is _MISSING:
                    del result[key]
                else:
                    result[key] = candidate
        return (result if result else _MISSING), changed
    if isinstance(managed, list) and isinstance(current, list):
        if not managed and not current:
            return _MISSING, True
        result = list(current)
        changed = False
        for managed_item in managed:
            for index, current_item in enumerate(result):
                if current_item == managed_item:
                    del result[index]
                    changed = True
                    break
        return (result if result else _MISSING), changed
    if current == managed:
        return _MISSING, True
    return current, False


def parse_key_values(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            raise ValueError("malformed-key-value-record")
        key, value = line.split("=", 1)
        if not key or key in values:
            raise ValueError("malformed-key-value-record")
        values[key] = value
    return values


def validate_identity(path: pathlib.Path) -> bool:
    try:
        values = parse_key_values(path)
    except (OSError, UnicodeError, ValueError):
        return False
    return (
        values.get("format") == "forge-codex-identity-v1"
        and values.get("engine") == "codex"
        and values.get("identity_class") in {"operator-setup", "fixture-only"}
        and values.get("status") in {"QUALIFIED", "BLOCKED"}
        and {"capture_revision", "writer_revision"}.issubset(values)
    )


def validate_generated_tree(root: pathlib.Path, tree_kind: str) -> tuple[bool, list[pathlib.Path]]:
    files: list[pathlib.Path] = []
    if not root.exists():
        return True, files
    if is_link_or_reparse(root) or not root.is_dir():
        return False, files
    for directory, names, filenames in os.walk(root, followlinks=False):
        directory_path = pathlib.Path(directory)
        for name in names:
            if is_link_or_reparse(directory_path / name):
                return False, files
        for name in filenames:
            path = directory_path / name
            if not regular_file(path):
                return False, files
            files.append(path)
    if tree_kind == "authorization":
        for path in files:
            try:
                first = path.read_text(encoding="utf-8").splitlines()[0]
            except (OSError, UnicodeError, IndexError):
                return False, files
            relative = path.relative_to(root).as_posix()
            valid = (
                (relative.endswith(".auth") and first == "format=forge-goal-authorization-v1")
                or (relative.endswith("/authorization.binding") and first == "format=forge-goal-ledger-v1")
                or ("/turns/" in relative and first == "format=forge-goal-turn-v1")
            )
            if not valid:
                return False, files
    else:
        groups: dict[pathlib.Path, set[str]] = {}
        for path in files:
            groups.setdefault(path.parent, set()).add(path.name)
        for parent, names in groups.items():
            if names != {"capture.receipt", "transcript.txt", "result.txt"}:
                return False, files
            try:
                receipt = parse_key_values(parent / "capture.receipt")
            except (OSError, UnicodeError, ValueError):
                return False, files
            if receipt.get("format") != "forge-codex-goal-tui-capture-v3":
                return False, files
            if receipt.get("transcript_sha256") != file_sha256(parent / "transcript.txt"):
                return False, files
            if receipt.get("result_sha256") != file_sha256(parent / "result.txt"):
                return False, files
    return True, files


def build_plan(
    repo_root: pathlib.Path, requested_home: pathlib.Path, platform: str
) -> tuple[RetirementPlan, PlannedChanges]:
    normalized_home = pathlib.Path(os.path.abspath(requested_home))
    if not normalized_home.exists() or not normalized_home.is_dir() or is_link_or_reparse(normalized_home):
        home = normalized_home
        finding = Finding("BLOCKED", ".", "root", "home-not-physical")
        return RetirementPlan(home, platform, (finding,)), PlannedChanges({}, set(), set(), set())
    home = normalized_home.resolve(strict=True)
    findings: list[Finding] = []
    changes = PlannedChanges({}, set(), set(), set())
    installed_hashes, receipt_problem = read_installed_hashes(home)
    if receipt_problem:
        findings.append(receipt_problem)

    inventory = read_inventory(repo_root, platform)
    inventory_paths = {destination for _kind, destination, _proof in inventory}
    cleanup_settings = json.loads(
        (repo_root / "manifests/legacy-v6-global-settings.json").read_text(encoding="utf-8")
    )

    for kind, destination, proof in inventory:
        relative = pathlib.PurePosixPath(destination)
        path = home.joinpath(*relative.parts)
        unsafe = link_ancestor(home, relative)
        if unsafe is not None:
            findings.append(Finding("BLOCKED", display(unsafe, home), kind, "linked-path"))
            continue
        if not path.exists():
            findings.append(Finding("ABSENT", destination, kind, proof))
            continue
        if proof == "installed-hash":
            if not regular_file(path):
                findings.append(Finding("BLOCKED", destination, kind, "not-regular"))
                continue
            actual = file_sha256(path)
            if installed_hashes.get(destination) != actual:
                findings.append(Finding("BLOCKED", destination, kind, "installed-hash-mismatch", actual))
                continue
            findings.append(Finding("REMOVE", destination, kind, proof, actual))
            changes.removals.add(path)
            changes.covered_files.add(path)
            if destination.startswith(".forge/bin/forge-goal-"):
                seal = pathlib.Path(str(path) + ".sha256")
                if seal.exists():
                    seal_relative = display(seal, home)
                    inventory_paths.add(seal_relative)
                    if not regular_file(seal) or seal.read_text(encoding="utf-8").strip().lower() != actual:
                        findings.append(Finding("BLOCKED", seal_relative, "generated", "helper-seal-mismatch"))
                    else:
                        seal_hash = file_sha256(seal)
                        findings.append(Finding("REMOVE", seal_relative, "generated", "recognized-seal", seal_hash))
                        changes.removals.add(seal)
                        changes.covered_files.add(seal)
            continue
        if proof in {"exact-version", "exact-release"}:
            if not regular_file(path):
                findings.append(Finding("BLOCKED", destination, kind, "not-regular"))
                continue
            content = path.read_bytes()
            actual = hashlib.sha256(content).hexdigest()
            if not VERSION.fullmatch(content):
                findings.append(Finding("BLOCKED", destination, kind, proof, actual))
            else:
                findings.append(Finding("REMOVE", destination, kind, proof, actual))
                changes.removals.add(path)
                changes.covered_files.add(path)
            continue
        if proof == "self":
            if not regular_file(path):
                findings.append(Finding("BLOCKED", destination, kind, "not-regular"))
                continue
            actual = file_sha256(path)
            findings.append(Finding("REMOVE", destination, kind, proof, actual))
            changes.removals.add(path)
            changes.covered_files.add(path)
            continue
        if proof in {"forge-marker-v6", "forge-toml-marker-v6"}:
            if not regular_file(path):
                findings.append(Finding("BLOCKED", destination, kind, "not-regular"))
                continue
            content = path.read_bytes()
            actual = hashlib.sha256(content).hexdigest()
            begin, end = (
                (MARKDOWN_BEGIN, MARKDOWN_END)
                if proof == "forge-marker-v6"
                else (TOML_BEGIN, TOML_END)
            )
            try:
                replacement, has_personal = trim_marker_block(content, begin, end)
            except ValueError as exc:
                findings.append(Finding("BLOCKED", destination, kind, str(exc), actual))
                continue
            if replacement == content:
                findings.append(Finding("PRESERVE", destination, kind, "no-forge-marker", actual))
                changes.covered_files.add(path)
                continue
            findings.append(Finding("REMOVE", destination, kind, "marker-block", actual))
            if has_personal:
                findings.append(Finding("PRESERVE", destination, kind, "personal-bytes", actual))
                changes.replacements[path] = replacement
            else:
                changes.removals.add(path)
            changes.covered_files.add(path)
            continue
        if proof == "legacy-v6-global-settings":
            if not regular_file(path):
                findings.append(Finding("BLOCKED", destination, kind, "not-regular"))
                continue
            actual = file_sha256(path)
            try:
                current = json.loads(path.read_text(encoding="utf-8"))
                replacement, changed = subtract_managed(current, cleanup_settings)
            except (OSError, UnicodeError, json.JSONDecodeError) as exc:
                findings.append(Finding("BLOCKED", destination, kind, f"invalid-json:{exc}", actual))
                continue
            if changed:
                findings.append(Finding("REMOVE", destination, kind, "managed-json-values", actual))
                if replacement is _MISSING:
                    changes.removals.add(path)
                else:
                    findings.append(Finding("PRESERVE", destination, kind, "personal-json-values", actual))
                    changes.replacements[path] = (json.dumps(replacement, indent=2) + "\n").encode()
            else:
                findings.append(Finding("PRESERVE", destination, kind, "no-exact-managed-values", actual))
            changes.covered_files.add(path)
            continue
        if proof == "recognized-schema":
            actual = file_sha256(path) if regular_file(path) else ""
            if not regular_file(path) or not validate_identity(path):
                findings.append(Finding("BLOCKED", destination, kind, proof, actual))
            else:
                findings.append(Finding("REMOVE", destination, kind, proof, actual))
                changes.removals.add(path)
                changes.covered_files.add(path)
            continue
        if proof == "recognized-seal":
            identity = home / ".forge/bin/codex.identity"
            actual = file_sha256(path) if regular_file(path) else ""
            valid = (
                regular_file(path)
                and regular_file(identity)
                and path.read_text(encoding="utf-8").strip().lower() == file_sha256(identity)
            )
            if not valid:
                findings.append(Finding("BLOCKED", destination, kind, proof, actual))
            else:
                findings.append(Finding("REMOVE", destination, kind, proof, actual))
                changes.removals.add(path)
                changes.covered_files.add(path)
            continue
        if proof == "recognized-tree":
            tree_kind = "authorization" if destination.endswith("authorizations") else "capture"
            valid, files = validate_generated_tree(path, tree_kind)
            tree_hash = hashlib.sha256(
                "\n".join(f"{display(item, home)}\t{file_sha256(item)}" for item in sorted(files)).encode()
            ).hexdigest()
            if not valid:
                findings.append(Finding("BLOCKED", destination, kind, proof, tree_hash))
            else:
                findings.append(Finding("REMOVE", destination, kind, proof, tree_hash))
                changes.removals.update(files)
                changes.covered_files.update(files)
                changes.removable_directories.add(path)
            continue
        findings.append(Finding("BLOCKED", destination, kind, "unsupported-proof"))

    forge_root = home / ".forge"
    if forge_root.exists() and not is_link_or_reparse(forge_root) and forge_root.is_dir():
        for directory, names, filenames in os.walk(forge_root, followlinks=False):
            directory_path = pathlib.Path(directory)
            for name in names:
                child = directory_path / name
                if is_link_or_reparse(child):
                    findings.append(Finding("BLOCKED", display(child, home), "unknown", "linked-path"))
            for name in filenames:
                path = directory_path / name
                relative = display(path, home)
                if path not in changes.covered_files and relative not in inventory_paths:
                    actual = file_sha256(path) if regular_file(path) else ""
                    findings.append(Finding("PRESERVE", relative, "unknown", "unknown", actual))

    return RetirementPlan(home, platform, tuple(sorted(set(findings)))), changes


def print_plan(plan: RetirementPlan) -> None:
    for finding in sorted(plan.findings):
        print(f"{finding.action} {finding.path} {finding.proof}")
    print(f"RETIRE_GLOBAL_DIGEST={plan_digest(plan)}")


def apply_changes(plan: RetirementPlan, changes: PlannedChanges) -> None:
    staged: dict[pathlib.Path, pathlib.Path] = {}
    try:
        for destination, content in sorted(changes.replacements.items(), key=lambda item: str(item[0])):
            handle, temporary_name = tempfile.mkstemp(prefix=f".{destination.name}.forge-retire-", dir=destination.parent)
            temporary = pathlib.Path(temporary_name)
            with os.fdopen(handle, "wb") as output:
                output.write(content)
                output.flush()
                os.fsync(output.fileno())
            if temporary.read_bytes() != content:
                raise OSError(f"staged replacement validation failed: {display(destination, plan.home)}")
            staged[destination] = temporary
        for destination, temporary in staged.items():
            os.replace(temporary, destination)
        for path in sorted(changes.removals, key=lambda item: (len(item.parts), str(item)), reverse=True):
            if path.exists():
                path.unlink()
        for root in sorted(changes.removable_directories, key=str):
            if not root.exists():
                continue
            for directory, _names, _files in os.walk(root, topdown=False, followlinks=False):
                try:
                    pathlib.Path(directory).rmdir()
                except OSError:
                    pass
        cleanup_roots = changes.removable_directories | {
            plan.home / ".forge/bin",
            plan.home / ".forge",
            plan.home / ".claude",
            plan.home / ".codex",
        }
        candidates: set[pathlib.Path] = set()
        for root in cleanup_roots:
            current = root
            while current != plan.home and plan.home in current.parents:
                candidates.add(current)
                current = current.parent
        for directory in sorted(candidates, key=lambda item: (len(item.parts), str(item)), reverse=True):
            try:
                directory.rmdir()
            except (FileNotFoundError, OSError):
                pass
    finally:
        for temporary in staged.values():
            temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True, type=pathlib.Path)
    parser.add_argument("--home", required=True, type=pathlib.Path)
    parser.add_argument("--platform", required=True, choices=("unix", "windows"))
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--digest")
    args = parser.parse_args()

    try:
        plan, changes = build_plan(args.repo_root.resolve(strict=True), args.home, args.platform)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"BLOCKED . retirement-plan:{exc}")
        return 2
    print_plan(plan)
    if any(finding.action == "BLOCKED" for finding in plan.findings):
        return 2
    if not args.apply:
        return 0
    if not args.digest or not hmac.compare_digest(args.digest.lower(), plan_digest(plan)):
        print("RETIRE_GLOBAL: BLOCKED digest-mismatch")
        return 2
    try:
        apply_changes(plan, changes)
    except OSError as exc:
        print(f"RETIRE_GLOBAL: BLOCKED apply-failed:{exc}")
        return 2
    print("RETIRE_GLOBAL: COMPLETE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
