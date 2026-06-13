#!/usr/bin/env python3
"""Summarize Claude Code transcript token usage for context-efficiency work.

Reads Claude Code JSONL transcripts under ~/.claude/projects/<project-key>/ and
reports main-thread vs sidechain context-token peaks. No third-party deps.

Context tokens are counted as:
  input_tokens + cache_read_input_tokens + cache_creation_input_tokens

Cached tokens still matter for context-rot risk: they are still prompt context.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import statistics
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


@dataclass
class UsageTurn:
    file: Path
    line_no: int
    session_id: str
    uuid: str
    timestamp: str
    is_sidechain: bool
    context_tokens: int
    input_tokens: int
    cache_read_tokens: int
    cache_creation_tokens: int
    output_tokens: int
    phase: str
    next_step: str


@dataclass
class LargePayload:
    file: Path
    line_no: int
    kind: str
    approx_tokens: int
    bytes_count: int
    preview: str


@dataclass
class SourceSize:
    path: Path
    label: str
    approx_tokens: int
    bytes_count: int


def run_git_root() -> Path:
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        if out:
            return Path(out)
    except Exception:
        pass
    return Path.cwd()


def project_key(root: Path) -> str:
    # Mirrors Forge/Claude convention well enough for Unix and Windows paths.
    raw = str(root.resolve())
    return re.sub(r"[/\\:]", "-", raw)


def default_project_dir(root: Path) -> Path:
    return Path.home() / ".claude" / "projects" / project_key(root)


def root_from_args(args: argparse.Namespace) -> Path:
    return Path(args.project_root).expanduser().resolve() if args.project_root else run_git_root()


def approx_tokens_for_text(text: str) -> int:
    return max(1, len(text.encode("utf-8", errors="replace")) // 4)


def usage_value(usage: dict[str, Any], key: str) -> int:
    val = usage.get(key, 0)
    return val if isinstance(val, int) else 0


def usage_signature(record: dict[str, Any], usage: dict[str, Any]) -> str:
    # Claude Code can emit multiple assistant JSONL rows for one API request
    # (thinking/text/tool_use blocks), each carrying identical usage. Count that
    # request once by collapsing adjacent equal signatures.
    payload = {
        "sessionId": record.get("sessionId", ""),
        "isSidechain": bool(record.get("isSidechain", False)),
        "usage": usage,
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def percentile(values: list[int], pct: float) -> int:
    if not values:
        return 0
    if len(values) == 1:
        return values[0]
    sorted_values = sorted(values)
    idx = round((pct / 100) * (len(sorted_values) - 1))
    return sorted_values[idx]


def text_from_content(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if not isinstance(item, dict):
                continue
            for key in ("text", "content", "result"):
                val = item.get(key)
                if isinstance(val, str):
                    parts.append(val)
            if item.get("type") == "tool_result":
                val = item.get("content")
                if isinstance(val, list):
                    parts.append(text_from_content(val))
        return "\n".join(parts)
    return ""


def hook_text(record: dict[str, Any]) -> str:
    """Return hook/attachment text only.

    Phase inference must ignore normal message content because Read/tool output may
    contain documentation examples like `WORKFLOW: ...` that are not live state.
    """
    chunks: list[str] = []
    attachment = record.get("attachment")
    if isinstance(attachment, dict):
        for key in ("content", "stdout", "stderr"):
            val = attachment.get(key)
            if isinstance(val, str):
                chunks.append(val)
    return "\n".join(c for c in chunks if c)


def update_phase_from_text(text: str, current_phase: str, current_next: str) -> tuple[str, str]:
    # check-state-updated emits: WORKFLOW: /cmd | Phase: X | Next: Y
    workflow_match = re.search(r"WORKFLOW:\s*[^|]+\|\s*Phase:\s*([^|]+)\|\s*Next:\s*(.+)", text)
    if workflow_match:
        current_phase = workflow_match.group(1).strip()
        current_next = workflow_match.group(2).strip().splitlines()[0]

    if "FORGE_GOAL_EVIDENCE_BEGIN" in text:
        match = re.search(r"FORGE_GOAL_EVIDENCE_BEGIN\s*(\{.*?\})\s*FORGE_GOAL_EVIDENCE_END", text, re.S)
        if match:
            try:
                evidence = json.loads(match.group(1))
                state = evidence.get("state", {})
                if isinstance(state, dict):
                    phase = state.get("phase")
                    next_step = state.get("next_step")
                    if isinstance(phase, str) and phase:
                        current_phase = phase
                    if isinstance(next_step, str) and next_step:
                        current_next = next_step
            except json.JSONDecodeError:
                pass
    return current_phase, current_next


def payload_candidates(record: dict[str, Any]) -> Iterable[tuple[str, str]]:
    attachment = record.get("attachment")
    if isinstance(attachment, dict):
        hook = attachment.get("hookName") or attachment.get("hookEvent") or "hook"
        for key in ("content", "stdout", "stderr"):
            val = attachment.get(key)
            if isinstance(val, str) and val:
                yield f"attachment:{hook}:{key}", val

    msg = record.get("message")
    if isinstance(msg, dict):
        content = text_from_content(msg.get("content"))
        if content:
            role = msg.get("role", "message")
            yield f"message:{role}", content


def parse_transcripts(files: list[Path], top_payloads: int) -> tuple[list[UsageTurn], list[LargePayload], int]:
    turns: list[UsageTurn] = []
    payloads: list[LargePayload] = []
    skipped_duplicate_usage = 0

    # Dedupe adjacent duplicated usage rows inside each file.
    for path in files:
        current_phase = ""
        current_next = ""
        seen_usage_sigs: set[str] = set()

        try:
            fh = path.open("r", encoding="utf-8")
        except OSError as exc:
            print(f"warning: cannot read {path}: {exc}", file=sys.stderr)
            continue

        with fh:
            for line_no, line in enumerate(fh, start=1):
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue

                current_phase, current_next = update_phase_from_text(
                    hook_text(record), current_phase, current_next
                )

                for kind, payload in payload_candidates(record):
                    byte_count = len(payload.encode("utf-8", errors="replace"))
                    approx = max(1, byte_count // 4)
                    if approx > 200:
                        preview = " ".join(payload.strip().split())[:180]
                        payloads.append(LargePayload(path, line_no, kind, approx, byte_count, preview))

                msg = record.get("message")
                if not isinstance(msg, dict) or msg.get("role") != "assistant":
                    continue

                usage = msg.get("usage")
                if not isinstance(usage, dict):
                    continue

                sig = usage_signature(record, usage)
                if sig in seen_usage_sigs:
                    skipped_duplicate_usage += 1
                    continue
                seen_usage_sigs.add(sig)

                input_tokens = usage_value(usage, "input_tokens")
                cache_read = usage_value(usage, "cache_read_input_tokens")
                cache_creation = usage_value(usage, "cache_creation_input_tokens")
                output_tokens = usage_value(usage, "output_tokens")
                context_tokens = input_tokens + cache_read + cache_creation

                turns.append(
                    UsageTurn(
                        file=path,
                        line_no=line_no,
                        session_id=str(record.get("sessionId", "")),
                        uuid=str(record.get("uuid", "")),
                        timestamp=str(record.get("timestamp", "")),
                        is_sidechain=bool(record.get("isSidechain", False)),
                        context_tokens=context_tokens,
                        input_tokens=input_tokens,
                        cache_read_tokens=cache_read,
                        cache_creation_tokens=cache_creation,
                        output_tokens=output_tokens,
                        phase=current_phase,
                        next_step=current_next,
                    )
                )

    payloads.sort(key=lambda p: p.approx_tokens, reverse=True)
    return turns, payloads[:top_payloads], skipped_duplicate_usage


def fmt_int(value: int) -> str:
    return f"{value:,}"


def collect_source_sizes(root: Path) -> list[SourceSize]:
    candidates: list[tuple[Path, str]] = [
        (Path.home() / ".claude" / "CLAUDE.md", "global CLAUDE.md"),
        (root / "CLAUDE.md", "project CLAUDE.md"),
        (root / "MEMORY.md", "project MEMORY.md"),
        (root / ".claude" / "local" / "state.md", "local state.md (not necessarily autoloaded)"),
    ]
    rules_dir = root / ".claude" / "rules"
    if rules_dir.is_dir():
        for path in sorted(rules_dir.glob("*.md")):
            candidates.append((path, f"rule {path.name}"))

    sizes: list[SourceSize] = []
    for path, label in candidates:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        byte_count = len(text.encode("utf-8", errors="replace"))
        sizes.append(SourceSize(path, label, approx_tokens_for_text(text), byte_count))
    sizes.sort(key=lambda s: s.approx_tokens, reverse=True)
    return sizes


def first_turns_by_file(turns: list[UsageTurn]) -> dict[Path, UsageTurn]:
    result: dict[Path, UsageTurn] = {}
    for turn in sorted(turns, key=lambda t: (str(t.file), t.line_no)):
        result.setdefault(turn.file, turn)
    return result


def summarize(label: str, turns: list[UsageTurn]) -> list[str]:
    contexts = [t.context_tokens for t in turns]
    outputs = [t.output_tokens for t in turns]
    peak = max(contexts) if contexts else 0
    peak_turn = max(turns, key=lambda t: t.context_tokens) if turns else None
    lines = [f"### {label}", ""]
    lines.append(f"- Turns counted: {fmt_int(len(turns))}")
    lines.append(f"- Peak context tokens: {fmt_int(peak)}")
    lines.append(f"- p95 context tokens: {fmt_int(percentile(contexts, 95))}")
    lines.append(f"- Median context tokens: {fmt_int(int(statistics.median(contexts))) if contexts else '0'}")
    lines.append(f"- Total output tokens: {fmt_int(sum(outputs))}")
    if peak_turn:
        phase = peak_turn.phase or "unknown"
        next_step = peak_turn.next_step or "unknown"
        lines.append(
            f"- Peak location: `{peak_turn.file.name}:{peak_turn.line_no}` "
            f"at `{peak_turn.timestamp or 'unknown time'}`; phase `{phase}`; next `{next_step}`"
        )
    lines.append("")
    return lines


def render_markdown(
    files: list[Path],
    turns: list[UsageTurn],
    payloads: list[LargePayload],
    skipped_duplicate_usage: int,
) -> str:
    main = [t for t in turns if not t.is_sidechain]
    side = [t for t in turns if t.is_sidechain]

    lines: list[str] = ["# Claude Context Metrics", ""]
    lines.append("## Scope")
    lines.append("")
    for path in files:
        lines.append(f"- `{path}`")
    lines.append("")
    lines.append(f"Skipped duplicate usage rows: {fmt_int(skipped_duplicate_usage)}")
    lines.append("")
    lines.extend(summarize("Main thread", main))
    lines.extend(summarize("Sidechains / subagents", side))
    lines.extend(summarize("All assistant turns", turns))

    if main:
        top_main = sorted(main, key=lambda t: t.context_tokens, reverse=True)[:10]
        lines.append("## Top main-thread context peaks")
        lines.append("")
        lines.append("| Rank | Context tokens | Output tokens | Timestamp | Phase | Location |")
        lines.append("| ---: | ---: | ---: | --- | --- | --- |")
        for i, turn in enumerate(top_main, start=1):
            phase = (turn.phase or "unknown").replace("|", "\\|")
            lines.append(
                f"| {i} | {fmt_int(turn.context_tokens)} | {fmt_int(turn.output_tokens)} | "
                f"`{turn.timestamp or 'unknown'}` | {phase} | `{turn.file.name}:{turn.line_no}` |"
            )
        lines.append("")

    if payloads:
        lines.append("## Largest transcript payloads (approximate)")
        lines.append("")
        lines.append("| Rank | Approx tokens | Bytes | Kind | Location | Preview |")
        lines.append("| ---: | ---: | ---: | --- | --- | --- |")
        for i, payload in enumerate(payloads, start=1):
            preview = payload.preview.replace("|", "\\|")
            lines.append(
                f"| {i} | {fmt_int(payload.approx_tokens)} | {fmt_int(payload.bytes_count)} | "
                f"`{payload.kind}` | `{payload.file.name}:{payload.line_no}` | {preview} |"
            )
        lines.append("")

    lines.append("## Counting notes")
    lines.append("")
    lines.append("- `context_tokens = input_tokens + cache_read_input_tokens + cache_creation_input_tokens`.")
    lines.append("- Cached tokens are included because they are still prompt context for context-rot risk.")
    lines.append("- Assistant rows with identical usage within a transcript file are counted once; Claude Code may split one API response across thinking/text/tool-use rows.")
    lines.append("- Payload token counts are rough byte/4 estimates, intended only to identify noisy transcript entries.")
    lines.append("")
    return "\n".join(lines)


def render_startup_markdown(
    files: list[Path],
    turns: list[UsageTurn],
    payloads: list[LargePayload],
    skipped_duplicate_usage: int,
    root: Path,
    top_payloads: int,
) -> str:
    first_by_file = first_turns_by_file(turns)
    lines: list[str] = ["# Claude Startup Context Metrics", ""]
    lines.append(f"Project root: `{root}`")
    lines.append("")
    lines.append("Startup context is measured at the first assistant usage row in each transcript:")
    lines.append("")
    lines.append("```text")
    lines.append("context_tokens = input_tokens + cache_read_input_tokens + cache_creation_input_tokens")
    lines.append("```")
    lines.append("")
    lines.append(f"Skipped duplicate usage rows: {fmt_int(skipped_duplicate_usage)}")
    lines.append("")

    lines.append("## First assistant turn per transcript")
    lines.append("")
    lines.append("| Transcript | Line | Context tokens | input | cache read | cache create | output | Timestamp |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |")
    for path in files:
        turn = first_by_file.get(path)
        if not turn:
            lines.append(f"| `{path.name}` | — | — | — | — | — | — | — |")
            continue
        lines.append(
            f"| `{path.name}` | {turn.line_no} | {fmt_int(turn.context_tokens)} | "
            f"{fmt_int(turn.input_tokens)} | {fmt_int(turn.cache_read_tokens)} | "
            f"{fmt_int(turn.cache_creation_tokens)} | {fmt_int(turn.output_tokens)} | "
            f"`{turn.timestamp or 'unknown'}` |"
        )
    lines.append("")

    first_lines = {path: turn.line_no for path, turn in first_by_file.items()}
    pre_first_payloads = [
        p for p in payloads
        if p.file in first_lines and p.line_no < first_lines[p.file]
    ]
    if pre_first_payloads:
        lines.append("## Largest pre-first-turn transcript payloads")
        lines.append("")
        lines.append("| Rank | Approx tokens | Bytes | Kind | Location | Preview |")
        lines.append("| ---: | ---: | ---: | --- | --- | --- |")
        for i, payload in enumerate(pre_first_payloads[:top_payloads], start=1):
            preview = payload.preview.replace("|", "\\|")
            lines.append(
                f"| {i} | {fmt_int(payload.approx_tokens)} | {fmt_int(payload.bytes_count)} | "
                f"`{payload.kind}` | `{payload.file.name}:{payload.line_no}` | {preview} |"
            )
        lines.append("")

    source_sizes = collect_source_sizes(root)
    if source_sizes:
        lines.append("## Autoload/source file rough sizes")
        lines.append("")
        lines.append("These are byte/4 estimates for Forge-controlled or Forge-shaped files; they are attribution hints, not exact tokenizer counts.")
        lines.append("")
        lines.append("| Rank | Approx tokens | Bytes | Source | Path |")
        lines.append("| ---: | ---: | ---: | --- | --- |")
        for i, source in enumerate(source_sizes, start=1):
            try:
                display_path = source.path.relative_to(root)
            except ValueError:
                display_path = source.path
            lines.append(
                f"| {i} | {fmt_int(source.approx_tokens)} | {fmt_int(source.bytes_count)} | "
                f"{source.label} | `{display_path}` |"
            )
        lines.append("")

    lines.append("## Counting notes")
    lines.append("")
    lines.append("- Use `--all-sessions` to compare multiple startup experiments for the same project root.")
    lines.append("- Payload sizes are rough byte/4 estimates from transcript text before the first assistant response.")
    lines.append("- Source sizes include local files that may not all be injected automatically; use them as attribution leads.")
    lines.append("")
    return "\n".join(lines)


def render_json(files: list[Path], turns: list[UsageTurn], payloads: list[LargePayload], skipped: int) -> str:
    def summary(turn_subset: list[UsageTurn]) -> dict[str, Any]:
        contexts = [t.context_tokens for t in turn_subset]
        return {
            "turns": len(turn_subset),
            "peak_context_tokens": max(contexts) if contexts else 0,
            "p95_context_tokens": percentile(contexts, 95),
            "median_context_tokens": int(statistics.median(contexts)) if contexts else 0,
            "total_output_tokens": sum(t.output_tokens for t in turn_subset),
        }

    main = [t for t in turns if not t.is_sidechain]
    side = [t for t in turns if t.is_sidechain]
    data = {
        "files": [str(p) for p in files],
        "skipped_duplicate_usage_rows": skipped,
        "main_thread": summary(main),
        "sidechains": summary(side),
        "all": summary(turns),
        "top_main_peaks": [t.__dict__ | {"file": str(t.file)} for t in sorted(main, key=lambda x: x.context_tokens, reverse=True)[:10]],
        "largest_payloads": [p.__dict__ | {"file": str(p.file)} for p in payloads],
    }
    return json.dumps(data, indent=2)


def choose_files(args: argparse.Namespace) -> list[Path]:
    if args.transcript:
        return [Path(p).expanduser() for p in args.transcript]

    root = root_from_args(args)
    project_dir = Path(args.project_dir).expanduser() if args.project_dir else default_project_dir(root)
    files = sorted(project_dir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    if not files:
        raise SystemExit(f"No transcript files found in {project_dir}")
    return files if args.all_sessions else [files[0]]


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize Claude Code transcript context-token usage.")
    parser.add_argument("--project-root", help="Project root used to derive ~/.claude/projects/<key>. Defaults to git root/cwd.")
    parser.add_argument("--project-dir", help="Explicit ~/.claude/projects/<key> directory.")
    parser.add_argument("--transcript", action="append", help="Explicit transcript JSONL file. May be passed multiple times.")
    parser.add_argument("--all-sessions", action="store_true", help="Analyze all JSONL files in the project transcript directory instead of newest only.")
    parser.add_argument("--top-payloads", type=int, default=10, help="Number of large payload rows to show. Default: 10.")
    parser.add_argument("--startup", action="store_true", help="Report first-turn startup context and pre-first-turn payloads.")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of Markdown.")
    args = parser.parse_args()

    files = choose_files(args)
    turns, payloads, skipped = parse_transcripts(files, args.top_payloads)
    if args.json:
        print(render_json(files, turns, payloads, skipped))
    elif args.startup:
        print(render_startup_markdown(files, turns, payloads, skipped, root_from_args(args), args.top_payloads))
    else:
        print(render_markdown(files, turns, payloads, skipped))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
