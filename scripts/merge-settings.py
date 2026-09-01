#!/usr/bin/env python3
"""Merge template settings/MCP JSON into existing user files.

Strategy: add-only, never remove.
- Objects (hooks, enabledPlugins, mcpServers): add new keys, skip existing
- Arrays (permissions.allow/deny/ask): append items not already present
- Creates timestamped backup before modifying

Usage:
    python3 merge-settings.py <template_file> <user_file>

Exit codes:
    0 = merged successfully (or no changes needed)
    1 = error
"""

import argparse
import contextlib
import dataclasses
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Optional


STATE_SCHEMA = b"<!-- forge:state-schema v6 -->\n"
RECONCILIATION_SENTINEL = re.compile(
    rb"\A<!-- forge:(?:migrated|reconciled) \d{4}-\d{2}-\d{2} -->\r?\n(?:\r?\n)?"
)
CONTINUITY_RECEIPT_SCHEMA = "forge-continuity-state-translation-v1"
CONTINUITY_RECEIPT_RELATIVE = Path(
    ".forge/local/migration-evidence/continuity-state-v5-v6.json"
)
TERMINAL_JOURNAL_PHASES = {"committed", "rolled_back", "recovered"}


class RefreshBlocked(RuntimeError):
    """A fail-closed migration disposition that must be shown to the operator."""


class ReportedRefreshBlocked(RefreshBlocked):
    """A blocked disposition already explained by a complete operator report."""


@dataclasses.dataclass(frozen=True, order=True)
class UpgradeFinding:
    code: str
    scope: str
    path: str
    detail: str
    resolution: str


@dataclasses.dataclass(frozen=True)
class LegacyInventory:
    selector: str
    region_selector: str
    recognized: bool
    proven_legacy: frozenset[str]
    proven_seeded_legacy: frozenset[str]
    preserved_legacy: frozenset[str]
    findings: tuple[UpgradeFinding, ...]


def print_agent_assisted_blocker_guidance() -> None:
    print(
        "AGENT_ASSISTED_NEXT_STEP: ask Claude Code or Codex to explain this report "
        "and follow docs/guides/agent-assisted-setup.md from the Forge checkout"
    )
    print(
        "AGENT_APPROVAL: do not modify files or run full refresh until the user "
        "approves the proposed reconciliation"
    )


def print_root_policy_actions(findings: tuple[UpgradeFinding, ...]) -> None:
    root_findings = tuple(
        finding
        for finding in findings
        if finding.code == "ROOT_POLICY_AMBIGUOUS" and finding.scope == "project"
    )
    if not root_findings:
        return
    print("ACTION_REQUIRED: reconcile project instruction files")
    for finding in root_findings:
        if finding.detail.startswith("retired active Forge references:"):
            print(
                f"ACTION: path={finding.path} remove or replace the retired Forge v5 "
                "references listed above; do not copy shared policy into both root files"
            )
        elif finding.detail.startswith("ambiguous legacy project instructions:"):
            print(
                f"ACTION: path={finding.path} Forge cannot safely separate customized project "
                "text from obsolete managed Forge v5 policy; move the shared project knowledge "
                "to docs/agent-context.md and replace the user-owned root text with the pointer below"
            )
    print(
        "SHARED_CONTEXT: docs/agent-context.md is the project-owned source shared by Claude and Codex"
    )
    print("ROOT_POINTER: Read `docs/agent-context.md` completely before acting.")
    print("RETRY: rerun the same full-refresh preview command after saving these edits")


def print_refresh_report(
    report: dict[str, list[str]],
    findings: tuple[UpgradeFinding, ...],
    *,
    upgrade: str,
    active_forge: str,
    next_step: str,
) -> None:
    for category, values in report.items():
        entries = sorted(set(values))
        if entries:
            for entry in entries:
                print(f"{category}: {entry}")
        else:
            print(f"{category}: (none)")
    for finding in findings:
        print(
            f"BLOCKED: code={finding.code} scope={finding.scope} path={finding.path} "
            f"detail={finding.detail} resolution={finding.resolution}"
        )
    print_root_policy_actions(findings)
    if findings:
        print_agent_assisted_blocker_guidance()
    print(f"UPGRADE: {upgrade}")
    print(f"ACTIVE_FORGE: {active_forge}")
    print(
        "CHANGES: "
        f"created={len(set(report['CREATED']))} rewritten={len(set(report['REWRITTEN']))} "
        f"deleted={len(set(report['DELETED']))} preserved={len(set(report['PRESERVED']))}"
    )
    print(f"BLOCKERS: {len(findings)}")
    print(f"NEXT_STEP: {next_step}")


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fsync_directory(path: Path) -> None:
    """Best-effort directory flush (unsupported by some Windows filesystems)."""
    try:
        descriptor = os.open(str(path), os.O_RDONLY)
    except (OSError, AttributeError):
        return
    try:
        os.fsync(descriptor)
    except OSError:
        pass
    finally:
        os.close(descriptor)


def durable_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    with temporary.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)
    fsync_directory(path.parent)


def relative_path(value: str) -> Path:
    candidate = Path(value)
    if (
        not value
        or candidate.is_absolute()
        or "\\" in value
        or any(part in {"", ".", ".."} for part in candidate.parts)
    ):
        raise RefreshBlocked(f"unsafe manifest path: {value!r}")
    return candidate


def ensure_under(root: Path, candidate: Path) -> None:
    try:
        candidate.relative_to(root)
    except ValueError as error:
        raise RefreshBlocked(f"path escapes transaction root: {candidate}") from error


def reject_link_ancestors(root: Path, relative: Path) -> None:
    current = root
    for part in relative.parts:
        current = current / part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(mode):
            raise RefreshBlocked(f"symlink/reparse-point managed path: {current}")
        if current != root / relative and not stat.S_ISDIR(mode):
            raise RefreshBlocked(f"non-directory managed ancestor: {current}")


def read_tsv(path: Path, expected_fields: int) -> list[list[str]]:
    rows: list[list[str]] = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw or raw.startswith("#"):
            continue
        fields = raw.split("\t")
        if len(fields) != expected_fields:
            raise RefreshBlocked(f"malformed manifest row {path.name}:{number}")
        rows.append(fields)
    return rows


def released_ownership(
    repo_root: Path,
) -> tuple[dict[str, tuple[str, str]], list[list[str]], list[list[str]]]:
    releases = {
        version: (fingerprint_set, region_set)
        for version, _commit, _mode, fingerprint_set, region_set in read_tsv(
            repo_root / "manifests/legacy-v5-releases.tsv", 5
        )
    }
    fingerprints = read_tsv(repo_root / "manifests/legacy-v5-fingerprints.tsv", 5)
    aliases = read_tsv(repo_root / "manifests/legacy-v5-aliases.tsv", 5)
    return releases, fingerprints, aliases


def transaction_destination_allowed(
    repo_root: Path, scope: str, txid: str, relative: Path, operation: dict
) -> bool:
    value = relative.as_posix()
    if scope == "global" and relative.parts[0] not in {".forge", ".claude", ".codex"}:
        return False
    backup_prefix = f".forge/local/migration-backups/{txid}/"
    if value.startswith(backup_prefix):
        return True
    if value == f".forge/local/migration-reports/{txid}.tsv":
        return True

    allowed = {
        ".forge/version",
        ".forge/installed-files.tsv",
        ".forge/managed-files.tsv",
        ".forge/local/.state-seed-snapshot.md",
        CONTINUITY_RECEIPT_RELATIVE.as_posix(),
        ".claude/local/state.md",
        ".claude/local/.state-seed-snapshot.md",
        ".forge/bin/forge-goal-authorize.sha256",
        ".forge/bin/forge-goal-capture.sha256",
    }
    for row in read_tsv(repo_root / "manifests/managed-v6.tsv", 9):
        destination, row_scope = row[2], row[5]
        if row_scope == scope and destination != "-" and "__" not in destination:
            allowed.add(destination)
    for row in read_tsv(repo_root / "manifests/legacy-v5.tsv", 9):
        destination, row_scope = row[2], row[3]
        if row_scope == scope and "__" not in destination:
            allowed.add(destination)
    if value in allowed:
        return True

    protected_prefixes = (
        (".forge/local/memory/", ".forge/memory/")
        if scope == "project"
        else (".forge/goal-authorizations/", ".forge/goal-captures/")
    )
    if value.startswith(protected_prefixes):
        # Full refresh only carries existing developer-owned protected-tree
        # files. It never creates or tombstones arbitrary paths in those trees.
        return bool(operation.get("original_hash")) and not operation.get("delete", False)
    return False


def fingerprint_hashes(
    fingerprints: list[list[str]], selector: str, scope: str
) -> dict[str, set[str]]:
    result: dict[str, set[str]] = {}
    for selectors, _source, destination, row_scope, digest in fingerprints:
        if row_scope != scope or selector not in selectors.split(","):
            continue
        result.setdefault(destination, set()).add(digest)
    return result


def inventory_legacy(
    repo_root: Path, target: Path, scope: str, platform: str
) -> LegacyInventory:
    releases, fingerprints, aliases = released_ownership(repo_root)
    findings: list[UpgradeFinding] = []
    proven_legacy: set[str] = set()
    proven_seeded_legacy: set[str] = set()
    preserved_legacy: set[str] = set()
    current_v6 = False
    v6_stamp = target / ".forge/version"
    if v6_stamp.is_file() and not v6_stamp.is_symlink():
        current_v6 = v6_stamp.read_text(encoding="utf-8", errors="replace").strip() == "6"

    stamp_relative = ".claude/.forge-version"
    stamp = target / stamp_relative
    if stamp.exists() or stamp.is_symlink():
        reject_link_ancestors(target, relative_path(stamp_relative))
        if not stamp.is_file():
            raise RefreshBlocked("legacy Forge release stamp is not a regular file")
    version = stamp.read_text(encoding="utf-8", errors="replace").strip() if stamp.is_file() else ""
    # Current v6 releases before upgrade hardening still wrote the historical
    # advisory stamp. It is inert once the canonical v6 stamp exists and must
    # not make an otherwise healthy v6 install look like an unsupported v5.
    if version and not current_v6 and version not in releases:
        findings.append(
            UpgradeFinding(
                "UNSUPPORTED_LEGACY_RELEASE",
                scope,
                stamp_relative,
                f"unsupported legacy Forge release stamp: {version}",
                "install a supported released v5 snapshot or reconcile the legacy harness manually",
            )
        )
    selector, region_selector = releases.get(version, ("", "")) if not current_v6 else ("", "")
    recognized = bool(version and version in releases and not current_v6)
    if recognized:
        proven_legacy.add(stamp_relative)

    allowed = fingerprint_hashes(fingerprints, selector, scope) if selector else {}
    legacy_rows = [] if current_v6 else read_tsv(repo_root / "manifests/legacy-v5.tsv", 9)
    seen_destinations: set[str] = set()
    for kind, _source, destination, row_scope, row_platform, _host, ownership, _selector, _proof in legacy_rows:
        if (
            row_scope != scope
            or row_platform not in {"all", platform}
            or destination in seen_destinations
            or "__PLAYWRIGHT_DIR__" in destination
            or destination in {"CLAUDE.md", ".claude/CLAUDE.md"}
        ):
            continue
        seen_destinations.add(destination)
        path = target / relative_path(destination)
        if not path.exists() and not path.is_symlink():
            continue
        reject_link_ancestors(target, relative_path(destination))
        if kind == "merge" or ownership in {"managed-entry", "managed-line", "generated-value"}:
            continue
        if not path.is_file():
            raise RefreshBlocked(f"legacy managed destination is not a regular file: {destination}")
        digest = sha256_path(path)
        if selector:
            verified = digest in allowed.get(destination, set())
        else:
            verified = any(
                dest == destination and fingerprint_scope == scope and fp == digest
                for _selectors, _src, dest, fingerprint_scope, fp in fingerprints
            )
            recognized = recognized or verified
        if verified:
            proven_legacy.add(destination)
            if ownership == "seeded-content":
                proven_seeded_legacy.add(destination)
        elif ownership == "seeded-content":
            preserved_legacy.add(destination)
        else:
            findings.append(
                UpgradeFinding(
                    "LEGACY_FILE_MODIFIED",
                    scope,
                    destination,
                    "modified or unverifiable legacy managed file",
                    "preserve the project-specific behavior in docs/agent-context.md or another "
                    "project-owned source, then restore the released bytes or archive and remove "
                    "the active legacy registration",
                )
            )

    if not current_v6:
        for selectors, _source, destination, row_scope, expected in aliases:
            if row_scope != scope:
                continue
            path = target / relative_path(destination)
            if not path.exists() and not path.is_symlink():
                continue
            reject_link_ancestors(target, relative_path(destination))
            if not path.is_file():
                raise RefreshBlocked(f"legacy alias destination is not a regular file: {destination}")
            digest = sha256_path(path)
            # An exact released whole-file hash at a known cross-host alias
            # path is stronger evidence than an advisory/stale project stamp.
            # Replacement is lossless and backed up; modified bytes still block.
            if digest == expected:
                proven_legacy.add(destination)
            else:
                findings.append(
                    UpgradeFinding(
                        "LEGACY_ALIAS_AMBIGUOUS",
                        scope,
                        destination,
                        "cross-host alias is modified or is not an exact released alias",
                        "archive the project-owned file or restore the exact released alias bytes",
                    )
                )

    json_paths = (
        [".claude/settings.json", ".mcp.json", ".codex/hooks.json"]
        if scope == "project"
        else [".claude/settings.json"]
    )
    for relative in json_paths:
        source = target / relative
        if not source.exists() and not source.is_symlink():
            continue
        reject_link_ancestors(target, relative_path(relative))
        if not source.is_file():
            raise RefreshBlocked(f"protected JSON is not a regular file: {relative}")
        try:
            json.loads(source.read_text(encoding="utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            findings.append(
                UpgradeFinding(
                    "PROTECTED_JSON_MALFORMED",
                    scope,
                    relative,
                    "malformed JSON is opaque and cannot be authoritatively merged",
                    "repair the JSON syntax without changing ownership, then rerun preview",
                )
            )

    findings.extend(root_instruction_findings(repo_root, target, scope, region_selector))
    if scope == "project":
        findings.extend(active_harness_findings(target))
        findings.extend(state_source_findings(target, current_v6))
        findings.extend(continuity_file_findings(target, current_v6))

    return LegacyInventory(
        selector=selector,
        region_selector=region_selector,
        recognized=recognized,
        proven_legacy=frozenset(proven_legacy),
        proven_seeded_legacy=frozenset(proven_seeded_legacy),
        preserved_legacy=frozenset(preserved_legacy),
        findings=tuple(sorted(set(findings))),
    )


def line_anchor_positions(raw: bytes, anchor: str) -> list[int]:
    encoded = re.escape(anchor.encode("utf-8"))
    return [match.start() for match in re.finditer(rb"(?m)^" + encoded + rb"\r?$", raw)]


def recognize_mixed_regions(
    repo_root: Path,
    raw: bytes,
    scope: str,
    destination: str,
    selected_region_set: str,
) -> bytes:
    """Select one manifest-described segmentation and return only its user slices."""
    all_rows = read_tsv(repo_root / "manifests/legacy-v5-regions.tsv", 9)
    candidate_sets = (
        [selected_region_set]
        if selected_region_set
        else sorted(
            {
                region_set
                for region_set, row_scope, row_destination, *_rest in all_rows
                if row_scope == scope and row_destination == destination
            }
        )
    )
    successful: list[tuple[str, tuple[tuple[int, int], ...], bytes]] = []
    for region_set in candidate_sets:
        rows = sorted(
            (
                row
                for row in all_rows
                if row[0] == region_set and row[1] == scope and row[2] == destination
            ),
            key=lambda row: row[3],
        )
        if not rows:
            continue
        by_id = {row[5]: row for row in rows}
        first_line_end = raw.find(b"\n") + 1

        def positions(token: str, boundary: str) -> list[int]:
            if token == "BOF":
                return [0]
            if token == "EOF":
                return [len(raw)]
            if token == "line:1":
                return [0] if boundary == "start" else [first_line_end]
            if token == "after:generated-field":
                return [first_line_end]
            referenced = token.split(":", 1)[1] if token.startswith("before:") else token
            if referenced in by_id:
                referenced = by_id[referenced][6]
            return line_anchor_positions(raw, referenced)

        row_candidates: list[list[tuple[int, int]]] = []
        invalid_set = False
        for row in rows:
            ownership, start_anchor, end_anchor, proof = row[4], row[6], row[7], row[8]
            candidates: list[tuple[int, int]] = []
            for start in positions(start_anchor, "start"):
                for end in positions(end_anchor, "end"):
                    if start < 0 or end <= start:
                        continue
                    body = raw[start:end]
                    if ownership == "generated-field":
                        title = body.rstrip(b"\r\n")
                        if (
                            not body.startswith(b"# CLAUDE.md - ")
                            or len(title) == len(b"# CLAUDE.md - ")
                            or b"\r" in title
                            or b"\n" in title
                        ):
                            continue
                    elif ownership == "managed":
                        if not re.fullmatch(r"[0-9a-f]{64}", proof):
                            invalid_set = True
                            break
                        if hashlib.sha256(body).hexdigest() != proof:
                            continue
                    elif ownership != "user" or proof != "PRESERVE":
                        invalid_set = True
                        break
                    candidates.append((start, end))
                if invalid_set:
                    break
            if invalid_set or not candidates:
                invalid_set = True
                break
            row_candidates.append(sorted(set(candidates)))
        if invalid_set:
            continue

        solutions: list[tuple[tuple[int, int], ...]] = []

        def walk(index: int, cursor: int, chosen: list[tuple[int, int]]) -> None:
            if len(solutions) > 1:
                return
            if index == len(rows):
                if cursor == len(raw):
                    solutions.append(tuple(chosen))
                return
            for start, end in row_candidates[index]:
                if start == cursor:
                    walk(index + 1, end, chosen + [(start, end)])

        walk(0, 0, [])
        if len(solutions) > 1:
            raise RefreshBlocked(
                f"ambiguous legacy {scope} instructions: nonunique manifest segmentation"
            )
        if not solutions:
            continue
        solution = solutions[0]
        preserved = b"".join(
            raw[start:end]
            for row, (start, end) in zip(rows, solution)
            if row[4] == "user"
        )
        if scope == "project":
            preserved = b"# Developer Project Instructions (preserved from Forge v5)\n\n" + preserved
        successful.append((region_set, solution, preserved))
    if len(successful) != 1:
        reason = "nonunique" if len(successful) > 1 else "managed region changed"
        raise RefreshBlocked(
            f"ambiguous legacy {scope} instructions: {reason} manifest segmentation"
        )
    return successful[0][2]


def strip_reconciliation_sentinel(raw: bytes) -> tuple[bytes, bytes]:
    match = RECONCILIATION_SENTINEL.match(raw)
    if match is None:
        return b"", raw
    return raw[: match.end()], raw[match.end() :]


def retired_reference_detail(raw: bytes) -> str:
    tokens = (
        "@CONTINUITY.md",
        "/codex",
        ".claude/commands/",
        ".claude/rules/",
        ".claude/hooks/",
    )
    matches: list[str] = []
    for number, line in enumerate(raw.decode("utf-8", errors="replace").splitlines(), 1):
        present = sorted(token for token in tokens if token in line)
        if present:
            matches.append(f"line {number} ({', '.join(present)})")
    return "; ".join(matches)


def without_v6_marker_block(raw: bytes) -> bytes:
    return re.sub(
        rb"(?s)<!-- forge:begin v6 -->.*?<!-- forge:end v6 -->",
        b"",
        raw,
    )


def root_instruction_findings(
    repo_root: Path, target: Path, scope: str, region_selector: str
) -> tuple[UpgradeFinding, ...]:
    relatives = (
        ("CLAUDE.md", "AGENTS.md")
        if scope == "project"
        else (".claude/CLAUDE.md", ".codex/AGENTS.md")
    )
    findings: list[UpgradeFinding] = []
    for relative in relatives:
        path = target / relative
        if not path.exists() and not path.is_symlink():
            continue
        reject_link_ancestors(target, relative_path(relative))
        if not path.is_file():
            raise RefreshBlocked(f"root instructions are not a regular file: {relative}")
        raw = path.read_bytes()
        active = raw
        legacy_destination = "CLAUDE.md" if scope == "project" else ".claude/CLAUDE.md"
        if relative == legacy_destination:
            _sentinel, legacy_body = strip_reconciliation_sentinel(raw)
            looks_legacy = (
                legacy_body.startswith(b"# CLAUDE.md - ")
                if scope == "project"
                else legacy_body.startswith(b"# Global Claude Code Instructions")
            )
            if looks_legacy:
                try:
                    active = recognize_mixed_regions(
                        repo_root, legacy_body, scope, relative, region_selector
                    )
                except RefreshBlocked as error:
                    findings.append(
                        UpgradeFinding(
                            "ROOT_POLICY_AMBIGUOUS",
                            scope,
                            relative,
                            str(error),
                            "reconcile the project-owned root text, then rerun full refresh preview",
                        )
                    )
                    continue
        detail = retired_reference_detail(without_v6_marker_block(active))
        if detail:
            findings.append(
                UpgradeFinding(
                    "ROOT_POLICY_AMBIGUOUS",
                    scope,
                    relative,
                    f"retired active Forge references: {detail}",
                    "replace only the obsolete project-owned references with neutral project context",
                )
            )
    return tuple(findings)


def active_harness_findings(target: Path) -> tuple[UpgradeFinding, ...]:
    harness_relative = Path(".agent-workflows")
    harness = target / harness_relative
    if not harness.exists() and not harness.is_symlink():
        return ()
    reject_link_ancestors(target, harness_relative)
    if not harness.is_dir():
        raise RefreshBlocked("independent harness root is not a regular directory: .agent-workflows")
    authority_files: list[str] = []
    for candidate in sorted(harness.rglob("*")):
        if candidate.is_symlink():
            raise RefreshBlocked(f"independent harness contains a symlink/reparse point: {candidate}")
        if candidate.is_file() and (
            "runtime" in candidate.relative_to(harness).parts
            or "policy" in candidate.name.lower()
        ):
            authority_files.append(candidate.relative_to(target).as_posix())
    references: list[str] = []
    for relative in (
        "CLAUDE.md",
        "AGENTS.md",
        ".claude/settings.json",
        ".codex/hooks.json",
        ".codex/config.toml",
    ):
        source = target / relative
        if not source.is_file() or source.is_symlink():
            continue
        if ".agent-workflows" in source.read_text(encoding="utf-8", errors="replace"):
            references.append(relative)
    if not authority_files or not references:
        return ()
    signals = ", ".join(sorted(authority_files + references))
    return (
        UpgradeFinding(
            "CUSTOM_HARNESS_COLLISION",
            "project",
            ".agent-workflows",
            f"independent active harness authority: {signals}",
            "archive or retire the custom harness, remove its active registrations, then rerun -F --dry-run",
        ),
    )


def state_source_findings(target: Path, current_v6: bool = False) -> tuple[UpgradeFinding, ...]:
    plausible: list[tuple[str, Path]] = []
    receipt_problem = ""
    for relative in (
        ".claude/local/state.md",
        ".forge/local/state.md",
        ".agent-workflows/local/state.md",
    ):
        path = target / relative
        if not path.exists() and not path.is_symlink():
            continue
        reject_link_ancestors(target, relative_path(relative))
        if not path.is_file():
            raise RefreshBlocked(f"state source is not a regular file: {relative}")
        raw = path.read_bytes()
        if raw.startswith(STATE_SCHEMA) or raw.startswith(b"# Project State"):
            plausible.append((relative, path))
    if current_v6:
        legacy = target / ".claude/local/state.md"
        canonical_template = target / ".forge/state.template.md"
        if (
            legacy.is_file()
            and not legacy.is_symlink()
            and canonical_template.is_file()
            and not canonical_template.is_symlink()
            and legacy.read_bytes() == canonical_template.read_bytes()
        ):
            plausible = [item for item in plausible if item[0] != ".claude/local/state.md"]
    if len(plausible) < 2:
        return ()
    by_relative = {relative: path for relative, path in plausible}
    if set(by_relative) == {".claude/local/state.md", ".forge/local/state.md"}:
        try:
            validate_continuity_receipt(
                target,
                by_relative[".claude/local/state.md"],
                by_relative[".forge/local/state.md"],
            )
            return ()
        except RefreshBlocked as error:
            receipt_problem = f"; continuity translation receipt invalid: {error}"
    sources = ", ".join(
        f"{relative} sha256={sha256_path(path)} mtime_ns={path.stat().st_mtime_ns}"
        for relative, path in plausible
    )
    return (
        UpgradeFinding(
            "MULTIPLE_STATE_SOURCES",
            "project",
            ".forge/local/state.md",
            f"state conflict: multiple plausible state sources: {sources}{receipt_problem}",
            "choose one authoritative state, archive the others, then rerun -F --dry-run",
        ),
    )


def continuity_file_findings(
    target: Path, current_v6: bool = False
) -> tuple[UpgradeFinding, ...]:
    """Require explicit, byte-bound evidence before accepting legacy continuity."""
    relative = Path("CONTINUITY.md")
    continuity = target / relative
    if not continuity.exists() and not continuity.is_symlink():
        return ()
    reject_link_ancestors(target, relative)
    if continuity.is_symlink() or not continuity.is_file():
        raise RefreshBlocked("legacy CONTINUITY.md is not a regular file")

    claude = target / "CLAUDE.md"
    old = target / ".claude/local/state.md"
    new = target / ".forge/local/state.md"
    receipt = target / CONTINUITY_RECEIPT_RELATIVE
    evidence_problem = "recognized migration evidence is missing"
    if (
        claude.is_file()
        and not claude.is_symlink()
        and b"<!-- forge:migrated" in claude.read_bytes()
        and new.is_file()
        and not new.is_symlink()
    ):
        try:
            if old.is_file() and not old.is_symlink():
                validate_continuity_receipt(target, old, new)
                return ()
            if current_v6:
                reject_link_ancestors(target, CONTINUITY_RECEIPT_RELATIVE)
                if receipt.is_symlink() or not receipt.is_file():
                    raise RefreshBlocked(
                        "continuity translation receipt is missing or not a regular file"
                    )
                actual = json.loads(receipt.read_text(encoding="utf-8"))
                if (
                    actual.get("schema") != CONTINUITY_RECEIPT_SCHEMA
                    or actual.get("source_relative") != ".claude/local/state.md"
                    or actual.get("source_schema") != "forge-state-v5-unversioned"
                    or not re.fullmatch(r"[0-9a-f]{64}", actual.get("source_hash", ""))
                    or actual.get("target_relative") != ".forge/local/state.md"
                    or actual.get("target_schema") != "forge-state-v6"
                    or actual.get("target_hash") != sha256_path(new)
                ):
                    raise RefreshBlocked(
                        "continuity translation receipt does not match the surviving canonical target"
                    )
                return ()
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, RefreshBlocked) as error:
            evidence_problem = str(error)

    return (
        UpgradeFinding(
            "LEGACY_CONTINUITY_UNRESOLVED",
            "project",
            relative.as_posix(),
            f"unresolved legacy continuity content sha256={sha256_path(continuity)}; {evidence_problem}",
            "move relevant facts to project instructions, decisions to docs/adr, and active state to .forge/local/state.md; archive or remove CONTINUITY.md; then rerun -F --dry-run",
        ),
    )


def strip_legacy_evidence(raw: bytes) -> bytes:
    """Translate versioned v5 state without treating narrative prose as evidence."""
    text = raw.decode("utf-8", errors="surrogateescape")
    if text.startswith("<!-- forge:state-schema v6 -->\n") or text.startswith(
        "<!-- forge:state-schema v6 -->\r\n"
    ):
        return raw
    lines = text.splitlines(keepends=True)
    output: list[str] = [STATE_SCHEMA.decode("ascii")]
    section = ""
    in_workflow_checklist = False
    inserted_goal_note = False
    inserted_auth_note = False
    goal_receipt_active = False

    review_receipt = re.compile(
        r"^\s*- \[[ xX]\] (?:"
        r"Code review iteration [1-9][0-9]* — (?:codex|pr-toolkit) clean — head=`[0-9a-f]{7,64}`|"
        r"Plan review iteration [1-9][0-9]* — codex clean — plan=`[^`]+` — plan_sha=`[0-9a-f]{64}`(?: — ts=`[^`]+`)?|"
        r"(?:Code|Plan) review loop(?: \([1-9][0-9]* iterations?\))? — (?:PASS|N/A: .+)|"
        r"Post-certification tail adjudicated by human — .+ — head=`[0-9a-f]{7,64}` — ts=`[^`]+`"
        r")\s*$"
    )
    authorization_receipt = re.compile(
        r"^\s*- \[[xX]\] PR creation authorized(?:\s*$| — `[^`]+` — nonce=`"
        r"[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}`"
        r" — head=`[0-9a-f]{7,64}`\s*$)"
    )
    goal_uuid_row = re.compile(
        r"^\s*\|\s*nonce\s*\|\s*[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-"
        r"[89ab][0-9a-f]{3}-[0-9a-f]{12}\s*\|\s*$"
    )

    for index, line in enumerate(lines):
        heading = line.rstrip("\r\n")
        if heading.startswith("## "):
            section = heading
            in_workflow_checklist = False
            if section == "## /goal session":
                inserted_goal_note = False
                next_heading = next(
                    (
                        candidate
                        for candidate in range(index + 1, len(lines))
                        if lines[candidate].rstrip("\r\n").startswith("## ")
                    ),
                    len(lines),
                )
                goal_receipt_active = any(
                    goal_uuid_row.fullmatch(candidate.rstrip("\r\n"))
                    or re.fullmatch(r"\s*- Goal session: active\s*", candidate.rstrip("\r\n"))
                    for candidate in lines[index + 1 : next_heading]
                )
            if section == "## PR authorization":
                inserted_auth_note = False
            output.append(line)
            continue
        if section == "## Workflow" and heading == "### Checklist":
            in_workflow_checklist = True
            output.append(line)
            continue
        if section == "## Workflow" and heading.startswith("### "):
            in_workflow_checklist = False
        bare = line.rstrip("\r\n")
        if section == "## /goal session":
            table_receipt_row = goal_receipt_active and re.fullmatch(
                r"\s*\|\s*(?:nonce|workflow_command|issued_at)\s*\|.*\|\s*", bare
            )
            old_receipt_row = re.fullmatch(
                r"\s*- (?:Goal session: active|Goal ID: \S+)\s*", bare
            )
            if table_receipt_row or old_receipt_row:
                if not inserted_goal_note:
                    ending = "\r\n" if line.endswith("\r\n") else "\n"
                    output.append(f"Legacy goal evidence invalidated during Forge v6 migration.{ending}")
                    inserted_goal_note = True
                continue
        if section == "## PR authorization" and authorization_receipt.fullmatch(bare):
            if not inserted_auth_note:
                ending = "\r\n" if line.endswith("\r\n") else "\n"
                output.append(f"Legacy PR authorization invalidated during Forge v6 migration.{ending}")
                inserted_auth_note = True
            continue
        if in_workflow_checklist and review_receipt.fullmatch(bare):
            continue
        output.append(line)
    return "".join(output).encode("utf-8", errors="surrogateescape")


def copy_preserved(source: Path, destination: Path) -> None:
    if source.is_symlink():
        raise RefreshBlocked(f"preserved source is a symlink/reparse point: {source}")
    if source.is_dir():
        for candidate in source.rglob("*"):
            if candidate.is_symlink():
                raise RefreshBlocked(f"preserved tree contains a symlink/reparse point: {candidate}")
        shutil.copytree(source, destination, dirs_exist_ok=True, symlinks=False)
    elif source.is_file():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def continuity_receipt_value(source: Path, destination: Path) -> dict:
    if source.is_symlink() or not source.is_file():
        raise RefreshBlocked("continuity translation receipt source is not a regular file")
    if destination.is_symlink() or not destination.is_file():
        raise RefreshBlocked("continuity translation receipt target is not a regular file")
    source_prefix = source.read_bytes()[:128]
    if source_prefix.startswith(b"<!-- forge:state-schema"):
        raise RefreshBlocked(
            "continuity translation receipt source is not an unversioned Forge v5 state"
        )
    if not destination.read_bytes().startswith(STATE_SCHEMA):
        raise RefreshBlocked("continuity translation receipt target lacks the v6 state schema")
    return {
        "schema": CONTINUITY_RECEIPT_SCHEMA,
        "source_relative": ".claude/local/state.md",
        "source_schema": "forge-state-v5-unversioned",
        "source_hash": sha256_path(source),
        "target_relative": ".forge/local/state.md",
        "target_schema": "forge-state-v6",
        "target_hash": sha256_path(destination),
    }


def validate_continuity_receipt(target: Path, old: Path, new: Path) -> Path:
    receipt = target / CONTINUITY_RECEIPT_RELATIVE
    reject_link_ancestors(target, CONTINUITY_RECEIPT_RELATIVE)
    if receipt.is_symlink() or not receipt.is_file():
        raise RefreshBlocked(
            "old/new state conflict: continuity translation receipt is missing or not a regular file"
        )
    try:
        actual = json.loads(receipt.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RefreshBlocked("old/new state conflict: continuity translation receipt is malformed") from error
    expected = continuity_receipt_value(old, new)
    if actual != expected:
        raise RefreshBlocked(
            "old/new state conflict: continuity translation receipt does not match the exact surviving source and canonical target"
        )
    return receipt


def acquire_guard(root: Path, txid: str) -> Path:
    guard = root / ".forge/local/setup-transaction.guard"
    guard.parent.mkdir(parents=True, exist_ok=True)
    try:
        guard.mkdir()
    except FileExistsError as error:
        owner = guard / "owner.json"
        detail = owner.read_text(encoding="utf-8", errors="replace") if owner.is_file() else "unknown owner"
        raise RefreshBlocked(f"active or stale setup transaction guard; recover first: {detail.strip()}") from error
    durable_json(
        guard / "owner.json",
        {"pid": os.getpid(), "transaction_id": txid, "created_unix": int(time.time())},
    )
    return guard


def validate_no_incomplete_journal(root: Path) -> None:
    journals = root / ".forge/local/migration-journals"
    if not journals.is_dir():
        return
    for path in sorted(journals.glob("*.json")):
        try:
            phase = json.loads(path.read_text(encoding="utf-8")).get("phase", "")
        except (OSError, json.JSONDecodeError) as error:
            raise RefreshBlocked(f"unverifiable migration journal requires recovery: {path}") from error
        if phase not in TERMINAL_JOURNAL_PHASES:
            raise RefreshBlocked(f"incomplete migration journal requires recovery: {path}")


def no_replace_move(source: Path, destination: Path) -> None:
    """Same-filesystem, no-clobber file move using link+unlink."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    os.link(source, destination, follow_symlinks=False)
    source.unlink()
    fsync_directory(destination.parent)


def pid_is_active(pid: int) -> bool:
    if pid <= 0:
        raise RefreshBlocked("invalid setup transaction guard owner PID")
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def validate_recovery_journal(
    journal_path: Path, root: Path, repo_root: Path
) -> tuple[dict, Optional[Path]]:
    expected_journal_dir = root / ".forge/local/migration-journals"
    if journal_path.parent.resolve(strict=True) != expected_journal_dir.resolve(strict=True):
        raise RefreshBlocked("journal is outside the transaction migration-journals directory")
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    if journal.get("schema") != "forge-full-refresh-journal-v1":
        raise RefreshBlocked("unsupported or missing full-refresh journal schema")
    txid = journal.get("transaction_id", "")
    if not isinstance(txid, str) or not re.fullmatch(r"[0-9]+-[0-9a-f]{32}", txid):
        raise RefreshBlocked("invalid full-refresh journal transaction id")
    if journal_path.name != f"{txid}.json":
        raise RefreshBlocked("journal filename does not match its transaction id")
    if Path(journal.get("transaction_root", "")).resolve(strict=True) != root:
        raise RefreshBlocked("journal transaction root does not match requested recovery root")
    if journal.get("phase") in {"committed", "recovered"}:
        raise RefreshBlocked(f"journal is already terminal: {journal.get('phase')}")
    operations = journal.get("operations")
    if not isinstance(operations, list):
        raise RefreshBlocked("journal operations must be a list")
    quarantine_root = root / ".forge/local/migration-staging" / txid / "quarantine"
    displaced_root = root / ".forge/local/migration-staging" / txid / "rollback-installed"
    scope = journal.get("scope", "")
    if scope not in {"project", "global"}:
        raise RefreshBlocked("journal has an invalid transaction scope")
    seen_destinations: set[str] = set()
    for operation in operations:
        if not isinstance(operation, dict):
            raise RefreshBlocked("journal operation must be an object")
        relative = relative_path(operation.get("relative", ""))
        if relative.as_posix() in seen_destinations:
            raise RefreshBlocked(f"journal contains duplicate destination: {relative}")
        seen_destinations.add(relative.as_posix())
        if not transaction_destination_allowed(repo_root, scope, txid, relative, operation):
            raise RefreshBlocked(f"journal destination is outside the transaction allowlist: {relative}")
        expected_destination = root / relative
        expected_quarantine = quarantine_root / relative
        destination = Path(operation.get("destination", ""))
        quarantine = Path(operation.get("quarantine", ""))
        if destination != expected_destination or quarantine != expected_quarantine:
            raise RefreshBlocked(f"journal operation path does not match relative destination: {relative}")
        reject_link_ancestors(root, relative)
        reject_link_ancestors(root, expected_quarantine.relative_to(root))
        reject_link_ancestors(root, (displaced_root / relative).relative_to(root))
        for key in ("original_hash", "installed_hash"):
            digest = operation.get(key, "")
            if not isinstance(digest, str) or (digest and not re.fullmatch(r"[0-9a-f]{64}", digest)):
                raise RefreshBlocked(f"journal operation has invalid {key}: {relative}")

    guard = root / ".forge/local/setup-transaction.guard"
    if not guard.exists():
        return journal, None
    if guard.is_symlink() or not guard.is_dir():
        raise RefreshBlocked("setup transaction guard is not a regular directory")
    owner_path = guard / "owner.json"
    try:
        owner = json.loads(owner_path.read_text(encoding="utf-8"))
        owner_pid = int(owner["pid"])
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise RefreshBlocked("setup transaction guard owner is unverifiable") from error
    if owner.get("transaction_id") != txid:
        raise RefreshBlocked("setup transaction guard belongs to a different transaction")
    if pid_is_active(owner_pid):
        raise RefreshBlocked(f"setup transaction guard owner is still active: pid {owner_pid}")
    return journal, guard


def rollback_journal(journal: dict, journal_path: Path) -> None:
    uncertain = False
    rollback_errors: list[str] = []
    root = Path(journal["transaction_root"])
    txid = journal["transaction_id"]
    displaced_root = root / ".forge/local/migration-staging" / txid / "rollback-installed"
    race_selector = os.environ.get("FORGE_FULL_REFRESH_INJECT_ROLLBACK_RACE_RELATIVE", "")
    for operation in reversed(journal.get("operations", [])):
        relative = relative_path(operation["relative"])
        destination = Path(operation["destination"])
        quarantine = Path(operation["quarantine"])
        displaced = displaced_root / relative
        original_hash = operation.get("original_hash", "")
        installed_hash = operation.get("installed_hash", "")
        try:
            for candidate in (destination, quarantine, displaced):
                if candidate.exists() and (candidate.is_symlink() or not candidate.is_file()):
                    raise RefreshBlocked(f"rollback path is not a regular file: {candidate}")

            destination_hash = sha256_path(destination) if destination.is_file() else ""
            quarantine_hash = sha256_path(quarantine) if quarantine.is_file() else ""
            displaced_hash = sha256_path(displaced) if displaced.is_file() else ""
            if quarantine_hash and (not original_hash or quarantine_hash != original_hash):
                raise RefreshBlocked(f"rollback quarantine hash mismatch: {relative}")
            if displaced_hash and (not installed_hash or displaced_hash != installed_hash):
                raise RefreshBlocked(f"rollback displaced-install hash mismatch: {relative}")

            # A previous rollback attempt may have completed the recoverable
            # installed-byte displacement but failed before restoring the
            # original. Never overwrite a concurrently-created destination.
            if displaced_hash:
                if destination_hash:
                    if destination_hash == installed_hash:
                        # no_replace_move can leave two hard links if its unlink
                        # is interrupted. The displaced verified copy makes
                        # removal of the live installed link recoverable.
                        destination.unlink()
                        fsync_directory(destination.parent)
                        destination_hash = ""
                    elif original_hash and destination_hash == original_hash and not quarantine_hash:
                        displaced.unlink()
                        fsync_directory(displaced.parent)
                        continue
                    else:
                        raise RefreshBlocked(f"rollback destination contains concurrent bytes: {relative}")
                if original_hash:
                    if not quarantine_hash:
                        raise RefreshBlocked(f"rollback original is missing from quarantine: {relative}")
                    no_replace_move(quarantine, destination)
                    if sha256_path(destination) != original_hash:
                        raise RefreshBlocked(f"rollback restored original failed verification: {relative}")
                elif destination.exists():
                    raise RefreshBlocked(f"rollback destination unexpectedly exists: {relative}")
                displaced.unlink()
                fsync_directory(displaced.parent)
                continue

            if destination_hash:
                if original_hash and destination_hash == original_hash and not quarantine_hash:
                    continue
                if not installed_hash or destination_hash != installed_hash:
                    # A concurrently-created/edited destination is never
                    # removed. Quarantine and all staged bytes remain intact.
                    raise RefreshBlocked(f"rollback destination contains concurrent bytes: {relative}")

                # Exchange the installed bytes into a collision-free recovery
                # slot before the live path is vacated. Restoration can now
                # fail without losing either the installed or original bytes.
                no_replace_move(destination, displaced)
                if sha256_path(displaced) != installed_hash:
                    raise RefreshBlocked(f"rollback displaced install failed verification: {relative}")
                if race_selector == operation["relative"]:
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    with destination.open("xb") as handle:
                        handle.write(b"FORGE_ROLLBACK_DESTINATION_RACE\n")
                        handle.flush()
                        os.fsync(handle.fileno())
                    fsync_directory(destination.parent)
                    print(f"FORGE_ROLLBACK_DESTINATION_RACE: {relative}", file=sys.stderr)
                if original_hash:
                    if not quarantine_hash:
                        raise RefreshBlocked(f"rollback original is missing from quarantine: {relative}")
                    no_replace_move(quarantine, destination)
                    if sha256_path(destination) != original_hash:
                        raise RefreshBlocked(f"rollback restored original failed verification: {relative}")
                elif destination.exists():
                    raise RefreshBlocked(f"rollback destination unexpectedly exists: {relative}")
                displaced.unlink()
                fsync_directory(displaced.parent)
                continue

            if quarantine_hash:
                no_replace_move(quarantine, destination)
                if sha256_path(destination) != original_hash:
                    raise RefreshBlocked(f"rollback restored original failed verification: {relative}")
            elif original_hash and operation.get("status") in {"quarantined", "installed", "deleted"}:
                raise RefreshBlocked(f"rollback original bytes are missing: {relative}")
        except (OSError, RefreshBlocked) as error:
            uncertain = True
            rollback_errors.append(f"{relative}: {error}")
    journal["phase"] = "recovery_required" if uncertain else "rolled_back"
    if rollback_errors:
        journal["rollback_errors"] = rollback_errors
    else:
        journal.pop("rollback_errors", None)
    durable_json(journal_path, journal)
    if uncertain:
        raise RefreshBlocked(f"rollback preserved conflicting versions; explicit recovery required: {journal_path}")


def recover_refresh(journal_path: Path, requested_root: Path, repo_root: Path) -> None:
    lexical_root = requested_root.absolute()
    if lexical_root.is_symlink():
        raise RefreshBlocked(f"symlink recovery root: {lexical_root}")
    root = lexical_root.resolve(strict=True)
    journal, stale_guard = validate_recovery_journal(journal_path, root, repo_root.resolve(strict=True))
    rollback_journal(journal, journal_path)
    journal["phase"] = "recovered"
    durable_json(journal_path, journal)
    if stale_guard is not None:
        owner_path = stale_guard / "owner.json"
        owner_path.unlink()
        stale_guard.rmdir()
        fsync_directory(stale_guard.parent)


def prepare_legacy(
    repo_root: Path,
    target: Path,
    scope: str,
    stage: Path,
    report: dict[str, list[str]],
    inventory: LegacyInventory,
) -> tuple[str, bool, set[str]]:
    selector = inventory.selector
    region_selector = inventory.region_selector
    recognized = inventory.recognized
    proven_legacy = set(inventory.proven_legacy)

    root_instruction = target / ("CLAUDE.md" if scope == "project" else ".claude/CLAUDE.md")
    if root_instruction.exists() or root_instruction.is_symlink():
        reject_link_ancestors(target, root_instruction.relative_to(target))
        if not root_instruction.is_file():
            raise RefreshBlocked("legacy root instructions are not a regular file")
    if root_instruction.is_file():
        raw = root_instruction.read_bytes()
        sentinel_prefix, legacy_body = strip_reconciliation_sentinel(raw)
        looks_legacy = (
            legacy_body.startswith(b"# CLAUDE.md - ")
            if scope == "project"
            else legacy_body.startswith(b"# Global Claude Code Instructions")
        )
        if looks_legacy:
            preserved = recognize_mixed_regions(
                repo_root,
                legacy_body,
                scope,
                root_instruction.relative_to(target).as_posix(),
                region_selector,
            )
            staged_root = stage / root_instruction.relative_to(target)
            staged_root.parent.mkdir(parents=True, exist_ok=True)
            staged_root.write_bytes(sentinel_prefix + preserved)
            report["PRESERVED"].append(f"{root_instruction.relative_to(target)} user regions (byte-exact)")
            recognized = True
        else:
            copy_preserved(root_instruction, stage / root_instruction.relative_to(target))
            report["PRESERVED"].append(str(root_instruction.relative_to(target)))

    for relative in (
        [".claude/settings.json", ".mcp.json", ".codex/hooks.json"]
        if scope == "project"
        else [".claude/settings.json"]
    ):
        source = target / relative
        if not source.exists():
            continue
        reject_link_ancestors(target, relative_path(relative))
        try:
            parsed = json.loads(source.read_text(encoding="utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise RefreshBlocked(f"protected JSON changed after inventory: {relative}") from error
        if relative.endswith("settings.json"):
            plugins = parsed.get("enabledPlugins", {}) if isinstance(parsed, dict) else {}
            overlap = sorted(
                name
                for name, enabled in plugins.items()
                if enabled is True and name in {
                    "superpowers@claude-plugins-official",
                    "pr-review-toolkit@claude-plugins-official",
                    "frontend-design@claude-plugins-official",
                }
            )
            inert = sorted(name for name, enabled in plugins.items() if enabled is True and name not in overlap)
            report["PRESERVED_COMPAT_BLOCKED"].extend(f"enabled plugin {name}" for name in overlap)
            report["PRESERVED_COMPAT"].extend(f"enabled plugin {name}" for name in inert)
        copy_preserved(source, stage / relative)
        report["PRESERVED"].append(relative)
    return selector, recognized, proven_legacy


def thin_hook_delegate_content(relative: Path) -> Optional[str]:
    if relative.suffix == ".sh":
        return (
            "#!/usr/bin/env bash\n"
            "set -u\n"
            'FORGE_PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"\n'
            f'exec "$FORGE_PROJECT_ROOT/.forge/hooks/{relative.name}" "$@"\n'
        )
    if relative.suffix == ".ps1":
        return (
            '$ErrorActionPreference = "Stop"\n'
            '$forgeProjectRoot = $env:CLAUDE_PROJECT_DIR\n'
            'if (-not $forgeProjectRoot) { $forgeProjectRoot = (& git rev-parse --show-toplevel 2>$null) }\n'
            f'& (Join-Path $forgeProjectRoot ".forge\\hooks\\{relative.name}") @args\n'
            'exit $LASTEXITCODE\n'
        )
    return None


def stage_legacy_hook_delegates(
    stage: Path, proven_legacy: set[str], scope: str, report: dict[str, list[str]]
) -> set[str]:
    """Keep preserved exact v5 hook registrations executable via v6 hooks."""
    remaining = set(proven_legacy)
    if scope != "project":
        tombstones = {value for value in remaining if value == ".claude/.forge-version"}
        report["PRESERVED_COMPAT"].extend(sorted(remaining - tombstones))
        return tombstones
    for value in sorted(proven_legacy):
        relative = relative_path(value)
        # Commands, skills, and agents already materialized at their historical
        # host path are replacements, not tombstones. Scheduling both would
        # create two journal operations for one destination.
        if (stage / relative).is_file():
            remaining.discard(value)
            continue
        if len(relative.parts) != 3 or relative.parts[:2] != (".claude", "hooks"):
            continue
        canonical = stage / ".forge/hooks" / relative.name
        if not canonical.is_file():
            continue
        destination = stage / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        delegate_content = thin_hook_delegate_content(relative)
        if delegate_content is None:
            continue
        destination.write_text(delegate_content, encoding="utf-8")
        if relative.suffix == ".sh":
            destination.chmod(0o755)
        remaining.discard(value)
        report["REWRITTEN"].append(f"{value} -> thin v6 hook delegate")
    return remaining


def prepare_state(
    target: Path, stage: Path, repo_root: Path, report: dict[str, list[str]]
) -> set[str]:
    old = target / ".claude/local/state.md"
    new = target / ".forge/local/state.md"
    staged = stage / ".forge/local/state.md"
    staged.parent.mkdir(parents=True, exist_ok=True)
    if old.exists() and (old.is_symlink() or not old.is_file()):
        raise RefreshBlocked("legacy state is not a regular file")
    if new.exists() and (new.is_symlink() or not new.is_file()):
        raise RefreshBlocked("canonical state is not a regular file")
    if old.is_file() and new.is_file():
        new_raw = new.read_bytes()
        current_v6 = (target / ".forge/version").is_file() and new_raw.startswith(STATE_SCHEMA)
        if current_v6:
            staged.write_bytes(new_raw)
            report["PRESERVED"].append(".forge/local/state.md")
            return set()
        receipt = validate_continuity_receipt(target, old, new)
        staged.write_bytes(new_raw)
        staged_receipt = stage / CONTINUITY_RECEIPT_RELATIVE
        copy_preserved(receipt, staged_receipt)
        translated_sources = {".claude/local/state.md"}
        report["REWRITTEN"].append(
            ".claude/local/state.md -> receipt-proven .forge/local/state.md"
        )
        seed = target / ".claude/local/.state-seed-snapshot.md"
        if seed.exists() or seed.is_symlink():
            reject_link_ancestors(target, relative_path(".claude/local/.state-seed-snapshot.md"))
            if not seed.is_file():
                raise RefreshBlocked("legacy state seed snapshot is not a regular file")
            staged_seed = stage / ".forge/local/.state-seed-snapshot.md"
            copy_preserved(seed, staged_seed)
            translated_sources.add(".claude/local/.state-seed-snapshot.md")
        return translated_sources
    if old.is_file():
        staged.write_bytes(strip_legacy_evidence(old.read_bytes()))
        translated_sources = {".claude/local/state.md"}
        report["REWRITTEN"].append(".claude/local/state.md -> .forge/local/state.md (legacy evidence invalidated)")
        seed = target / ".claude/local/.state-seed-snapshot.md"
        if seed.exists() or seed.is_symlink():
            reject_link_ancestors(target, relative_path(".claude/local/.state-seed-snapshot.md"))
            if not seed.is_file():
                raise RefreshBlocked("legacy state seed snapshot is not a regular file")
        if seed.is_file() and not seed.is_symlink():
            staged_seed = stage / ".forge/local/.state-seed-snapshot.md"
            staged_seed.parent.mkdir(parents=True, exist_ok=True)
            staged_seed.write_bytes(seed.read_bytes())
            translated_sources.add(".claude/local/.state-seed-snapshot.md")
            report["REWRITTEN"].append(".state-seed-snapshot.md -> canonical local path")
        return translated_sources
    elif new.is_file():
        if not new.read_bytes().startswith(STATE_SCHEMA):
            raise RefreshBlocked("invalid Forge v6 state without schema marker")
        copy_preserved(new, staged)
        report["PRESERVED"].append(".forge/local/state.md")
        return set()
    else:
        copy_preserved(repo_root / "state.template.md", staged)
        report["CREATED"].append(".forge/local/state.md")
        return set()


def prepare_project_gitignore(
    target: Path, stage: Path, report: dict[str, list[str]]
) -> None:
    relative = Path(".gitignore")
    source = target / relative
    if source.exists() or source.is_symlink():
        reject_link_ancestors(target, relative)
        if source.is_symlink() or not source.is_file():
            raise RefreshBlocked("project .gitignore is not a regular file")
        original = source.read_bytes()
        if b".forge/local/" in original.splitlines():
            return
        newline = b"\r\n" if b"\r\n" in original else b"\n"
        updated = original
        if updated and not updated.endswith((b"\n", b"\r")):
            updated += newline
        updated += b".forge/local/" + newline
        report["REWRITTEN"].append(".gitignore (added .forge/local/)")
    else:
        updated = b".forge/local/\n"
        report["CREATED"].append(".gitignore")
    staged = stage / relative
    staged.write_bytes(updated)


def selected_materializer(repo_root: Path, platform: str) -> list[str]:
    if platform == "windows":
        return [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(repo_root / "scripts/materialize-adapters.ps1"),
        ]
    return ["bash", str(repo_root / "scripts/materialize-adapters.sh")]


def materialize_stage(
    repo_root: Path, target: Path, stage: Path, scope: str, platform: str
) -> str:
    command = selected_materializer(repo_root, platform)
    if platform == "windows":
        command.extend(["-RepoRoot", str(repo_root), "-Target", str(stage), "-Scope", scope, "-Platform", platform])
    else:
        command.extend(["--repo-root", str(repo_root), "--target", str(stage), "--scope", scope, "--platform", platform])
    environment = os.environ.copy()
    environment["FORGE_TRANSACTION_STAGE"] = "1"
    environment["FORGE_DIAGNOSTIC_TARGET"] = str(target)
    environment["FORGE_DIAGNOSTIC_HOME"] = environment.get(
        "HOME", environment.get("USERPROFILE", "")
    )
    runtime_home = stage.parent / "runtime-home"
    environment["HOME"] = str(runtime_home)
    environment["USERPROFILE"] = str(runtime_home)
    environment["CODEX_HOME"] = str(runtime_home / ".codex")
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    completed = subprocess.run(command, text=True, capture_output=True, env=environment, check=False)
    if completed.returncode:
        raise RefreshBlocked(
            "staged canonical materialization failed before live mutation: "
            + (completed.stderr or completed.stdout).strip()
        )
    return (completed.stdout + completed.stderr).strip()


def canonical_hook_command(command: str) -> str:
    return (
        command.replace("/.claude/hooks/", "/.forge/hooks/")
        .replace("\\.claude\\hooks\\", "\\.forge\\hooks\\")
        .replace(".claude/local/state.md", ".forge/local/state.md")
        .replace(".claude\\local\\state.md", ".forge\\local\\state.md")
    )


def reconcile_legacy_hook_settings(
    repo_root: Path,
    target: Path,
    stage: Path,
    proven_legacy: set[str],
    scope: str,
    report: dict[str, list[str]],
) -> None:
    settings_path = stage / ".claude/settings.json"
    if not settings_path.is_file():
        return
    version_path = target / ".forge/version"
    current_v6 = (
        version_path.is_file()
        and not version_path.is_symlink()
        and version_path.read_text(encoding="utf-8", errors="replace").strip() == "6"
    )
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RefreshBlocked("staged Claude settings are malformed") from error
    hooks = settings.get("hooks", {}) if isinstance(settings, dict) else {}
    if not isinstance(hooks, dict):
        raise RefreshBlocked("staged Claude hook registrations are not an object")
    known_hook_paths = {
        destination
        for kind, _source, destination, row_scope, _platform, _host, ownership, _selector, _proof in read_tsv(
            repo_root / "manifests/legacy-v5.tsv", 9
        )
        if kind == "legacy"
        and row_scope == scope
        and ownership == "whole-file"
        and destination.startswith(".claude/hooks/")
    }
    legacy_inline_commands = {
        "echo 'COMPACTION IMMINENT. Save learnings to auto memory: bug root causes, patterns, architecture insights, user preferences. NOT session state (that goes in .claude/local/state.md).' >&2; exit 0",
        "powershell -Command \"Write-Error 'COMPACTION IMMINENT. Save learnings to auto memory: bug root causes, patterns, architecture insights, user preferences. NOT session state (that goes in .claude/local/state.md).'; exit 0\"",
    }
    changed = False
    for event, blocks in hooks.items():
        if not isinstance(blocks, list):
            raise RefreshBlocked(f"staged Claude hook event is not a list: {event}")
        for block in blocks:
            if not isinstance(block, dict) or not isinstance(block.get("hooks", []), list):
                raise RefreshBlocked(f"staged Claude matcher block is malformed: {event}")
            registered = block.get("hooks", [])
            remove_ids: set[int] = set()
            for legacy_hook in registered:
                if not isinstance(legacy_hook, dict):
                    raise RefreshBlocked(f"staged Claude hook registration is malformed: {event}")
                command = legacy_hook.get("command", "")
                if not isinstance(command, str):
                    continue
                match = re.search(
                    r"\$CLAUDE_PROJECT_DIR/\.claude/hooks/([^\"'\s]+)", command
                )
                is_released_inline = command in legacy_inline_commands
                if not match and not is_released_inline:
                    continue
                if match:
                    relative_value = f".claude/hooks/{match.group(1)}"
                    if relative_value in known_hook_paths:
                        exact_v6_delegate = False
                        if current_v6:
                            live_delegate = target / relative_path(relative_value)
                            expected_delegate = thin_hook_delegate_content(
                                relative_path(relative_value)
                            )
                            exact_v6_delegate = (
                                live_delegate.is_file()
                                and not live_delegate.is_symlink()
                                and expected_delegate is not None
                                and live_delegate.read_text(encoding="utf-8") == expected_delegate
                            )
                        if relative_value not in proven_legacy and not exact_v6_delegate:
                            raise RefreshBlocked(
                                f"referenced legacy hook is missing, modified, or ambiguous: {relative_value}"
                            )
                        relative_hook = relative_path(relative_value)
                        canonical_hook = stage / ".forge/hooks" / relative_hook.name
                        if (
                            len(relative_hook.parts) != 3
                            or relative_hook.parts[:2] != (".claude", "hooks")
                            or not canonical_hook.is_file()
                        ):
                            raise RefreshBlocked(
                                f"referenced legacy hook has no exact thin-delegate target: {relative_value}"
                            )
                    else:
                        custom = target / relative_path(relative_value)
                        reject_link_ancestors(target, relative_path(relative_value))
                        if custom.is_symlink() or not custom.is_file():
                            raise RefreshBlocked(
                                f"referenced legacy hook is missing or unsafe: {relative_value}"
                            )
                        report["PRESERVED_COMPAT"].append(
                            f"custom hook registration {relative_value}"
                        )
                        continue
                semantic = canonical_hook_command(command)
                equivalents = [
                    candidate
                    for candidate in registered
                    if candidate is not legacy_hook
                    and isinstance(candidate, dict)
                    and candidate.get("type") == legacy_hook.get("type")
                    and isinstance(candidate.get("command"), str)
                    and canonical_hook_command(candidate["command"]) == semantic
                ]
                if len(equivalents) > 1:
                    raise RefreshBlocked(
                        f"ambiguous semantic v5/v6 hook registrations in {event} matcher {block.get('matcher', '')!r}"
                    )
                if equivalents:
                    remove_ids.add(id(equivalents[0]))
                    changed = True
                report["PRESERVED_COMPAT"].append(
                    f"single legacy hook registration in {event} matcher {block.get('matcher', '')!r}"
                )
            if remove_ids:
                block["hooks"] = [item for item in registered if id(item) not in remove_ids]
    if changed:
        settings_path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")


def operation_files(stage: Path, target: Path, quarantine_root: Path) -> list[dict]:
    operations: list[dict] = []
    for source in sorted(path for path in stage.rglob("*") if path.is_file() and not path.is_symlink()):
        relative = source.relative_to(stage)
        destination = target / relative
        reject_link_ancestors(target, relative)
        original_hash = sha256_path(destination) if destination.is_file() and not destination.is_symlink() else ""
        if destination.exists() and not destination.is_file():
            raise RefreshBlocked(f"managed destination is not a regular file: {relative}")
        operations.append(
            {
                "relative": relative.as_posix(),
                "source": str(source),
                "destination": str(destination),
                "quarantine": str(quarantine_root / relative),
                "original_hash": original_hash,
                "staged_hash": sha256_path(source),
                "installed_hash": "",
                "status": "pending",
                "delete": False,
            }
        )
    # Stamp and inventory are the final live operations.
    operations.sort(key=lambda op: (op["relative"] in {".forge/version", ".forge/managed-files.tsv", ".forge/installed-files.tsv"}, op["relative"]))
    return operations


def deletion_operations(
    target: Path,
    quarantine_root: Path,
    values: set[str],
    exact_released_seeds: set[str],
    report: dict[str, list[str]],
) -> list[dict]:
    operations: list[dict] = []
    for value in sorted(values):
        relative = relative_path(value)
        destination = target / relative
        if not destination.exists():
            continue
        reject_link_ancestors(target, relative)
        if not destination.is_file():
            raise RefreshBlocked(f"proven legacy deletion is not a regular file: {relative}")
        operations.append(
            {
                "relative": relative.as_posix(),
                "source": "",
                "destination": str(destination),
                "quarantine": str(quarantine_root / relative),
                "original_hash": sha256_path(destination),
                "staged_hash": "",
                "installed_hash": "",
                "status": "pending",
                "delete": True,
            }
        )
        label = relative.as_posix()
        if label in exact_released_seeds:
            label += " (exact released Forge seed)"
        report["DELETED"].append(label)
    return operations


def apply_operations(
    operations: list[dict], journal: dict, journal_path: Path, fail_after: str
) -> None:
    applied = 0
    edit_selector = os.environ.get("FORGE_FULL_REFRESH_INJECT_EDIT_RELATIVE", "")
    race_selector = os.environ.get("FORGE_FULL_REFRESH_INJECT_DESTINATION_RACE_RELATIVE", "")
    for index, operation in enumerate(operations):
        destination = Path(operation["destination"])
        source = Path(operation["source"])
        quarantine = Path(operation["quarantine"])
        inject_edit = (
            edit_selector == operation["relative"]
            or (edit_selector == "@first" and index == 0)
            or (edit_selector == "@penultimate" and index == max(0, len(operations) - 2))
        )
        if inject_edit:
            destination.parent.mkdir(parents=True, exist_ok=True)
            with destination.open("ab") as handle:
                handle.write(b"FORGE_CONCURRENT_EDIT\n")
                handle.flush()
                os.fsync(handle.fileno())
            fsync_directory(destination.parent)
            print(f"FORGE_CONCURRENT_EDIT: {operation['relative']}", file=sys.stderr)
        if destination.exists():
            if destination.is_symlink() or not destination.is_file():
                raise RefreshBlocked(f"destination changed type after inventory: {destination}")
            if sha256_path(destination) != operation["original_hash"]:
                raise RefreshBlocked(f"concurrent edit before quarantine: {destination}")
            no_replace_move(destination, quarantine)
            if sha256_path(quarantine) != operation["original_hash"]:
                raise RefreshBlocked(f"concurrent edit detected after quarantine: {destination}")
        operation["status"] = "quarantined"
        journal["phase"] = "committing"
        durable_json(journal_path, journal)
        if operation.get("delete"):
            operation["status"] = "deleted"
            durable_json(journal_path, journal)
            applied += 1
            if failure_injected(fail_after, applied, len(operations)):
                raise OSError(f"injected full-refresh failure after operation {applied}")
            continue
        if race_selector == operation["relative"]:
            destination.parent.mkdir(parents=True, exist_ok=True)
            with destination.open("xb") as handle:
                handle.write(b"FORGE_DESTINATION_RACE\n")
                handle.flush()
                os.fsync(handle.fileno())
            fsync_directory(destination.parent)
            print(f"FORGE_DESTINATION_RACE: {operation['relative']}", file=sys.stderr)
        if destination.exists():
            raise RefreshBlocked(f"destination appeared between quarantine and install: {destination}")
        no_replace_move(source, destination)
        operation["installed_hash"] = sha256_path(destination)
        operation["status"] = "installed"
        durable_json(journal_path, journal)
        applied += 1
        if failure_injected(fail_after, applied, len(operations)):
            raise OSError(f"injected full-refresh failure after operation {applied}")


def failure_injected(selector: str, applied: int, total: int) -> bool:
    if not selector or selector == "0":
        return False
    if selector == "@penultimate":
        return applied == max(1, total - 1)
    try:
        return applied == int(selector)
    except ValueError as error:
        raise RefreshBlocked(f"invalid full-refresh failure injection selector: {selector}") from error


def prune_empty_transaction_directories(root: Path) -> None:
    for relative in (
        ".forge/local/migration-staging",
        ".forge/local/migration-journals",
        ".forge/local",
        ".forge",
    ):
        with contextlib.suppress(OSError):
            (root / relative).rmdir()


def full_refresh(
    repo_root: Path,
    target: Path,
    scope: str,
    platform: str,
    dry_run: bool = False,
) -> None:
    repo_root = repo_root.resolve(strict=True)
    if scope not in {"project", "global"} or platform not in {"unix", "windows"}:
        raise RefreshBlocked("invalid full-refresh scope or platform")
    lexical_target = target.absolute()
    if lexical_target.is_symlink():
        raise RefreshBlocked(f"symlink transaction root: {lexical_target}")
    target = target.resolve(strict=True)
    if scope == "global":
        if lexical_target != target:
            raise RefreshBlocked(f"selected global Forge home is not canonical: {lexical_target}")
        if target == Path(target.anchor):
            raise RefreshBlocked(f"filesystem root cannot be selected as the global Forge home: {target}")
    managed_roots = [Path(".forge"), Path(".forge/local"), Path(".claude"), Path(".claude/local"), Path(".codex")]
    if scope == "project":
        managed_roots.append(Path(".agents"))
    for relative in managed_roots:
        reject_link_ancestors(target, relative)
    if scope == "project":
        top = subprocess.run(
            ["git", "-C", str(target), "rev-parse", "--show-toplevel"],
            text=True,
            capture_output=True,
            check=False,
        )
        if top.returncode or Path(top.stdout.strip()).resolve() != target:
            raise RefreshBlocked("project full refresh must run at the canonical repository root")

    validate_no_incomplete_journal(target)
    txid = f"{int(time.time())}-{uuid.uuid4().hex}"
    temporary: Optional[tempfile.TemporaryDirectory] = None
    guard: Optional[Path] = None
    work_root: Optional[Path] = None
    stage: Optional[Path] = None
    quarantine: Optional[Path] = None
    journal_path = target / ".forge/local/migration-journals" / f"{txid}.json"
    report: dict[str, list[str]] = {
        category: []
        for category in (
            "CREATED",
            "REWRITTEN",
            "DELETED",
            "PRESERVED",
            "PRESERVED_COMPAT",
            "PRESERVED_COMPAT_BLOCKED",
            "BLOCKED",
        )
    }
    journal: dict = {}
    try:
        inventory = inventory_legacy(repo_root, target, scope, platform)
        report["PRESERVED"].extend(
            f"{relative} (modified seeded project content)"
            for relative in sorted(inventory.preserved_legacy)
        )
        if inventory.findings:
            print_refresh_report(
                report,
                inventory.findings,
                upgrade="BLOCKED",
                active_forge="unchanged",
                next_step="resolve every listed blocker, then rerun full refresh preview",
            )
            raise ReportedRefreshBlocked("upgrade inventory contains blocking findings")
        if not dry_run:
            guard = acquire_guard(target, txid)
            # Re-read after serialization so the transaction never relies on a
            # preview that raced with another local process.
            inventory = inventory_legacy(repo_root, target, scope, platform)
            report["PRESERVED"].extend(
                f"{relative} (modified seeded project content)"
                for relative in sorted(inventory.preserved_legacy)
            )
            if inventory.findings:
                print_refresh_report(
                    report,
                    inventory.findings,
                    upgrade="BLOCKED",
                    active_forge="unchanged",
                    next_step="resolve every listed blocker, then rerun full refresh preview",
                )
                raise ReportedRefreshBlocked("upgrade inventory contains blocking findings")
        if dry_run:
            temporary = tempfile.TemporaryDirectory(prefix="forge-full-refresh-preview-")
            work_root = Path(temporary.name)
        else:
            work_root = target / ".forge/local/migration-staging" / txid
        stage = work_root / "stage"
        quarantine = work_root / "quarantine"
        stage.mkdir(parents=True)
        _selector, legacy, proven_legacy = prepare_legacy(
            repo_root, target, scope, stage, report, inventory
        )
        translated_state_sources: set[str] = set()
        if scope == "project":
            translated_state_sources = prepare_state(target, stage, repo_root, report)
            prepare_project_gitignore(target, stage, report)
            for relative in ("AGENTS.md", ".codex/config.toml"):
                source = target / relative
                if source.exists():
                    reject_link_ancestors(target, relative_path(relative))
                    copy_preserved(source, stage / relative)
                    report["PRESERVED"].append(relative)
            for relative in (".forge/local/memory", ".forge/memory"):
                source = target / relative
                if source.exists():
                    copy_preserved(source, stage / relative)
                    report["PRESERVED"].append(relative)
        else:
            for relative in (".codex/AGENTS.md", ".codex/config.toml", ".forge/goal-authorizations", ".forge/goal-captures"):
                source = target / relative
                if source.exists():
                    reject_link_ancestors(target, relative_path(relative))
                    copy_preserved(source, stage / relative)
                    report["PRESERVED"].append(relative)

        materializer_output = materialize_stage(
            repo_root, target, stage, scope, platform
        )
        reconcile_legacy_hook_settings(
            repo_root, target, stage, proven_legacy, scope, report
        )
        legacy_deletions = stage_legacy_hook_delegates(stage, proven_legacy, scope, report)
        legacy_deletions.update(translated_state_sources)
        state = stage / ".forge/local/state.md"
        if scope == "project" and (not state.is_file() or not state.read_bytes().startswith(STATE_SCHEMA)):
            raise RefreshBlocked("staged translated state failed v6 schema validation")
        version = stage / ".forge/version"
        if not version.is_file() or version.read_text(encoding="utf-8").strip() != "6":
            raise RefreshBlocked("staged materializer did not produce the v6 stamp")

        # Remove materializer-local backups: the transaction already keeps raw,
        # collision-free backups under .forge/local/migration-backups/<txid>.
        for backup in stage.rglob("*.bak.*"):
            backup.unlink()
        initial_operations = operation_files(stage, target, quarantine)
        deletes = deletion_operations(
            target,
            quarantine,
            legacy_deletions,
            set(inventory.proven_seeded_legacy),
            report,
        )
        for operation in initial_operations:
            if operation["original_hash"]:
                report["REWRITTEN"].append(operation["relative"])
            else:
                report["CREATED"].append(operation["relative"])
        if dry_run:
            print(materializer_output)
            if report["PRESERVED_COMPAT_BLOCKED"]:
                print("claude RUNTIME_READY: BLOCKED preserved compatibility plugin requires qualification")
            print_refresh_report(
                report,
                (),
                upgrade="READY",
                active_forge="unchanged",
                next_step="run full refresh without --dry-run",
            )
            return

        backup_root = stage / ".forge/local/migration-backups" / txid
        for operation in initial_operations + deletes:
            if not operation["original_hash"]:
                continue
            source = Path(operation["destination"])
            destination = backup_root / relative_path(operation["relative"])
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

        report_path = stage / ".forge/local/migration-reports" / f"{txid}.tsv"
        report_path.parent.mkdir(parents=True, exist_ok=True)
        with report_path.open("w", encoding="utf-8", newline="\n") as handle:
            for category, entries in report.items():
                for entry in entries:
                    handle.write(f"{category}\t{entry}\n")
        staged_operations = operation_files(stage, target, quarantine)
        final_names = {".forge/version", ".forge/managed-files.tsv", ".forge/installed-files.tsv"}
        operations = (
            [operation for operation in staged_operations if operation["relative"] not in final_names]
            + deletes
            + [operation for operation in staged_operations if operation["relative"] in final_names]
        )
        operation_destinations = [operation["relative"] for operation in operations]
        if len(operation_destinations) != len(set(operation_destinations)):
            raise RefreshBlocked("staged transaction contains duplicate live destinations")
        for operation in operations:
            relative = relative_path(operation["relative"])
            if not transaction_destination_allowed(repo_root, scope, txid, relative, operation):
                raise RefreshBlocked(f"staged destination is outside the transaction allowlist: {relative}")
        journal = {
            "schema": "forge-full-refresh-journal-v1",
            "transaction_id": txid,
            "transaction_root": str(target),
            "scope": scope,
            "phase": "prepared",
            "legacy_detected": legacy,
            "operations": operations,
        }
        durable_json(journal_path, journal)
        fail_after = os.environ.get("FORGE_FULL_REFRESH_FAIL_AFTER", "0") or "0"
        try:
            apply_operations(operations, journal, journal_path, fail_after)
        except Exception as commit_error:
            print(f"BLOCKED: {commit_error}", file=sys.stderr)
            rollback_journal(journal, journal_path)
            print("ROLLED_BACK: full refresh restored the pre-transaction files", file=sys.stderr)
            raise
        journal["phase"] = "committed"
        durable_json(journal_path, journal)
        print(materializer_output)
        if report["PRESERVED_COMPAT_BLOCKED"]:
            print("claude RUNTIME_READY: BLOCKED preserved compatibility plugin requires qualification")
        print("INSTALLATION: MATERIALIZED")
        print_refresh_report(
            report,
            (),
            upgrade="READY",
            active_forge="v6",
            next_step="review per-host RUNTIME_READY diagnostics",
        )
    except RefreshBlocked as error:
        report["BLOCKED"].append(str(error))
        if not isinstance(error, ReportedRefreshBlocked):
            print(f"BLOCKED: {error}", file=sys.stderr)
        raise
    finally:
        if temporary is not None:
            temporary.cleanup()
        else:
            if work_root is not None and journal.get("phase") != "recovery_required":
                shutil.rmtree(work_root, ignore_errors=True)
            if guard is not None:
                shutil.rmtree(guard, ignore_errors=True)
            prune_empty_transaction_directories(target)


def full_refresh_cli(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="merge-settings.py full-refresh")
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--scope", required=True, choices=("project", "global"))
    parser.add_argument("--platform", required=True, choices=("unix", "windows"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    try:
        full_refresh(args.repo_root, args.target, args.scope, args.platform, args.dry_run)
    except (RefreshBlocked, OSError, ValueError, json.JSONDecodeError) as error:
        if not isinstance(error, ReportedRefreshBlocked):
            print(f"BLOCKED: {error}", file=sys.stderr)
            print_agent_assisted_blocker_guidance()
        return 1
    return 0


def recover_cli(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="merge-settings.py recover-full-refresh")
    parser.add_argument("--journal", required=True, type=Path)
    parser.add_argument("--target", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        recover_refresh(args.journal.resolve(strict=True), args.target, Path(__file__).resolve().parent.parent)
    except (RefreshBlocked, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        return 1
    print(f"RECOVERED: {args.journal}")
    return 0


def migrate_state_cli(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="merge-settings.py migrate-state-v5-v6")
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        lexical_source = args.source.absolute()
        if lexical_source.is_symlink():
            raise RefreshBlocked("legacy state source is not a regular file")
        source = lexical_source.resolve(strict=True)
        if not source.is_file():
            raise RefreshBlocked("legacy state source is not a regular file")
        destination = args.destination.absolute()
        if destination.is_symlink():
            raise RefreshBlocked("canonical state destination is a symlink")
        if destination.exists():
            existing = destination.read_bytes()
            translated = strip_legacy_evidence(source.read_bytes())
            if existing != translated:
                raise RefreshBlocked("old/new state conflict")
            print(f"PRESERVED: {destination} already contains the exact translation")
            return 0
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(f".{destination.name}.tmp-{os.getpid()}")
        with temporary.open("wb") as handle:
            handle.write(strip_legacy_evidence(source.read_bytes()))
            handle.flush()
            os.fsync(handle.fileno())
        os.link(temporary, destination, follow_symlinks=False)
        temporary.unlink()
        fsync_directory(destination.parent)
        print(f"REWRITTEN: {source} -> {destination}")
    except (RefreshBlocked, OSError, ValueError) as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        return 1
    return 0


def write_continuity_receipt_cli(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="merge-settings.py write-continuity-receipt")
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--receipt", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        root = Path.cwd().resolve(strict=True)
        source = args.source.absolute()
        destination = args.destination.absolute()
        receipt = args.receipt.absolute()
        for candidate in (source, destination, receipt):
            ensure_under(root, candidate)
            reject_link_ancestors(root, candidate.relative_to(root))
        if receipt != root / CONTINUITY_RECEIPT_RELATIVE:
            raise RefreshBlocked("continuity translation receipt path is not canonical")
        durable_json(receipt, continuity_receipt_value(source, destination))
    except (RefreshBlocked, OSError, ValueError) as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        return 1
    return 0


def merge_arrays(template_arr, user_arr):
    """Append items from template that aren't already in user's array."""
    added = []
    for item in template_arr:
        if item not in user_arr:
            user_arr.append(item)
            added.append(item)
    return added


def merge_objects(template_obj, user_obj):
    """Add keys from template that don't exist in user's object."""
    added = []
    for key, value in template_obj.items():
        if key not in user_obj:
            user_obj[key] = value
            added.append(key)
    return added


def _hook_key(h):
    """Identity tuple for a hook (type, command, prompt). Two hooks with the
    same key are considered the same command; the user-side instance is kept
    over the template-side instance during merge."""
    managed_id = h.get("forgeManagedId")
    if managed_id:
        return ("forge-managed", managed_id)
    return (h.get("type"), h.get("command"), h.get("prompt"))


def merge_hook_event(template_event, user_event):
    """Deep-merge a single hook event (Stop, PreToolUse, etc.).

    Each event is a list of matcher-blocks: [{"matcher": "...", "hooks": [...]}, ...].
    For each template matcher-block:
      1. Find the user block with the same matcher (or append the whole template
         block if none exists).
      2. Rebuild the user block's `hooks` list IN TEMPLATE ORDER, picking up the
         user's version of each hook when present. Append any user-only hooks
         (not in the template) at the end.

    Why this matters: settings.json hook events ship with multiple parallel hooks
    inside one matcher-block (e.g., Stop runs build-evidence + check-state-updated
    in that order — build-evidence writes a fingerprint side-channel file that
    check-state-updated reads, so REVERSING the order silently breaks
    stuck-detection). The old shallow merge skipped existing events entirely; a
    naive deep-merge that only appended new commands would put build-evidence at
    the WRONG position when the user had only check-state-updated. We rebuild in
    template order so the ordering invariant is preserved on --upgrade.

    Returns list of human-readable change descriptions.
    """
    changes = []
    for template_block in template_event:
        matcher = template_block.get("matcher", "")
        # Find user block with matching matcher
        user_block = next(
            (b for b in user_event if b.get("matcher", "") == matcher),
            None,
        )
        if user_block is None:
            # Whole new matcher-block — append
            user_event.append(template_block)
            changes.append(f"new matcher-block (matcher={matcher!r})")
            continue
        # Same matcher exists — rebuild `hooks` list in template order.
        user_block.setdefault("hooks", [])
        original_keys = [_hook_key(h) for h in user_block["hooks"]]
        user_by_key = {_hook_key(h): h for h in user_block["hooks"]}
        template_keys = {_hook_key(h) for h in template_block.get("hooks", [])}

        new_hooks = []
        for template_hook in template_block.get("hooks", []):
            tk = _hook_key(template_hook)
            if tk in user_by_key:
                user_hook = user_by_key[tk]
                if template_hook.get("forgeManagedId"):
                    # The stable managed id proves ownership of the fields Forge
                    # emits. Refresh those fields while retaining unknown user
                    # annotations on the same object.
                    refreshed = dict(user_hook)
                    refreshed.update(template_hook)
                    new_hooks.append(refreshed)
                    if refreshed != user_hook:
                        changes.append(
                            f"refreshed managed hook {template_hook['forgeManagedId']} "
                            f"in matcher={matcher!r}"
                        )
                else:
                    # Unowned entries remain user-controlled.
                    new_hooks.append(user_hook)
            else:
                new_hooks.append(template_hook)
                cmd_label = template_hook.get("command") or template_hook.get("type", "?")
                changes.append(f"new hook in matcher={matcher!r}: {cmd_label}")

        # Append any user-only hooks (commands the user added themselves that
        # are NOT in the template). Preserves user customizations.
        for user_hook in user_block["hooks"]:
            if _hook_key(user_hook) not in template_keys:
                new_hooks.append(user_hook)

        # P2-2 (Codex v5.32 review): detect ORDER-ONLY changes. If the user
        # already has both commands but in wrong order, the loop above rebuilds
        # new_hooks correctly but no "new hook" change is recorded — main()
        # then treats `changes == []` as "already up to date" and skips the
        # write, leaving the bad order in place. Record an order change so the
        # rebuilt list is actually persisted.
        new_keys = [_hook_key(h) for h in new_hooks]
        if new_keys != original_keys:
            # Only record order changes that AREN'T already captured by a
            # "new hook" addition above (avoid double-reporting).
            additions = [k for k in new_keys if k not in original_keys]
            if not additions:
                changes.append(
                    f"reordered hooks in matcher={matcher!r} to match template "
                    f"(ordering invariant — e.g., build-evidence must run before "
                    f"check-state-updated)"
                )

        user_block["hooks"] = new_hooks
    return changes


def merge_settings(template, user):
    """Merge settings.json: hooks, permissions, enabledPlugins."""
    changes = []

    # Merge enabledPlugins (add new plugins)
    if "enabledPlugins" in template:
        if "enabledPlugins" not in user:
            user["enabledPlugins"] = {}
        added = merge_objects(template["enabledPlugins"], user["enabledPlugins"])
        if added:
            changes.append(f"  Added plugins: {', '.join(added)}")

    # Merge permissions arrays
    if "permissions" in template:
        if "permissions" not in user:
            user["permissions"] = {}
        for key in ("allow", "deny", "ask"):
            if key in template["permissions"]:
                if key not in user["permissions"]:
                    user["permissions"][key] = []
                added = merge_arrays(template["permissions"][key], user["permissions"][key])
                if added:
                    changes.append(f"  Added permissions.{key}: {', '.join(added)}")

    # Merge hooks (deep-merge: new hook events OR new commands inside existing events).
    if "hooks" in template:
        if "hooks" not in user:
            user["hooks"] = {}
        for event_name, template_event in template["hooks"].items():
            if event_name not in user["hooks"]:
                user["hooks"][event_name] = template_event
                changes.append(f"  Added hook event: {event_name}")
                continue
            # Event exists in user — deep-merge matcher-blocks + commands.
            event_changes = merge_hook_event(template_event, user["hooks"][event_name])
            for ch in event_changes:
                changes.append(f"  hooks.{event_name}: {ch}")

    return changes


def merge_mcp(template, user):
    """Merge .mcp.json: add new MCP servers."""
    changes = []

    if "mcpServers" in template:
        if "mcpServers" not in user:
            user["mcpServers"] = {}
        added = merge_objects(template["mcpServers"], user["mcpServers"])
        if added:
            changes.append(f"  Added MCP servers: {', '.join(added)}")

    return changes


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "full-refresh":
        sys.exit(full_refresh_cli(sys.argv[2:]))
    if len(sys.argv) >= 2 and sys.argv[1] == "recover-full-refresh":
        sys.exit(recover_cli(sys.argv[2:]))
    if len(sys.argv) >= 2 and sys.argv[1] == "migrate-state-v5-v6":
        sys.exit(migrate_state_cli(sys.argv[2:]))
    if len(sys.argv) >= 2 and sys.argv[1] == "write-continuity-receipt":
        sys.exit(write_continuity_receipt_cli(sys.argv[2:]))
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <template_file> <user_file>", file=sys.stderr)
        sys.exit(1)

    template_path = Path(sys.argv[1])
    user_path = Path(sys.argv[2])

    if not template_path.exists():
        print(f"Template not found: {template_path}", file=sys.stderr)
        sys.exit(1)

    if not user_path.exists():
        # No existing file — just copy template
        shutil.copy2(template_path, user_path)
        print(f"  Created {user_path} (new)")
        sys.exit(0)

    # Load both files
    try:
        template = json.loads(template_path.read_text())
    except json.JSONDecodeError as e:
        print(f"Invalid JSON in template {template_path}: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        user = json.loads(user_path.read_text())
    except json.JSONDecodeError as e:
        print(f"Invalid JSON in {user_path}: {e}", file=sys.stderr)
        print(f"  Backing up and replacing with template", file=sys.stderr)
        backup = user_path.with_suffix(f".bak.{datetime.now().strftime('%Y%m%d%H%M%S')}")
        if os.environ.get("FORGE_TRANSACTION_STAGE") != "1":
            shutil.copy2(user_path, backup)
        shutil.copy2(template_path, user_path)
        if os.environ.get("FORGE_TRANSACTION_STAGE") != "1":
            print(f"  Backup: {backup}")
        sys.exit(0)

    # Detect file type by content
    if "mcpServers" in template:
        changes = merge_mcp(template, user)
    else:
        changes = merge_settings(template, user)

    if not changes:
        print(f"  {user_path.name}: already up to date")
        sys.exit(0)

    # Backup before modifying
    backup = user_path.with_suffix(f".bak.{datetime.now().strftime('%Y%m%d%H%M%S')}")
    if os.environ.get("FORGE_TRANSACTION_STAGE") != "1":
        shutil.copy2(user_path, backup)

    # Write merged result
    user_path.write_text(json.dumps(user, indent=2) + "\n")

    if os.environ.get("FORGE_TRANSACTION_STAGE") == "1":
        print(f"  Upgraded {user_path.name} in transaction stage:")
    else:
        print(f"  Upgraded {user_path.name} (backup: {backup.name}):")
    for change in changes:
        print(change)


if __name__ == "__main__":
    main()
