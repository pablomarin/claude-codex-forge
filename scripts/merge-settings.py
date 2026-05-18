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

import json
import sys
import shutil
from datetime import datetime
from pathlib import Path


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
        user_by_key = {_hook_key(h): h for h in user_block["hooks"]}
        template_keys = {_hook_key(h) for h in template_block.get("hooks", [])}

        new_hooks = []
        for template_hook in template_block.get("hooks", []):
            tk = _hook_key(template_hook)
            if tk in user_by_key:
                # Keep user's version (preserves any user customizations on the
                # same command, e.g., extra fields we don't recognize).
                new_hooks.append(user_by_key[tk])
            else:
                new_hooks.append(template_hook)
                cmd_label = template_hook.get("command") or template_hook.get("type", "?")
                changes.append(f"new hook in matcher={matcher!r}: {cmd_label}")

        # Append any user-only hooks (commands the user added themselves that
        # are NOT in the template). Preserves user customizations.
        for user_hook in user_block["hooks"]:
            if _hook_key(user_hook) not in template_keys:
                new_hooks.append(user_hook)

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
        shutil.copy2(user_path, backup)
        shutil.copy2(template_path, user_path)
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
    shutil.copy2(user_path, backup)

    # Write merged result
    user_path.write_text(json.dumps(user, indent=2) + "\n")

    print(f"  Upgraded {user_path.name} (backup: {backup.name}):")
    for change in changes:
        print(change)


if __name__ == "__main__":
    main()
