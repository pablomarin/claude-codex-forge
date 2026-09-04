#!/usr/bin/env bash
# Render per-invocation private host config. No ambient hooks/plugins/skills/MCP survive.
set -u
die() { printf 'BLOCKED[capability]: %s\n' "$*" >&2; exit 2; }
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
TEMPLATE_DIR=$(cd "$SELF_DIR/.." && pwd -P)/templates/runtime
engine=""; profile=""; output=""; readonly_server=""
while [ "$#" -gt 0 ]; do case "$1" in --engine) engine="$2"; shift 2 ;; --profile) profile="$2"; shift 2 ;; --output-dir) output="$2"; shift 2 ;; --read-only-server) readonly_server="$2"; shift 2 ;; *) die "unknown argument $1" ;; esac; done
case "$engine" in claude|codex) ;; *) die 'engine must be claude or codex' ;; esac
case "$profile" in review|investigate) ;; *) die 'profile must be review or investigate' ;; esac
[ -n "$output" ] || die 'output directory is required'
[ -f "$TEMPLATE_DIR/claude-review-settings.template.json" ] && [ -f "$TEMPLATE_DIR/codex-review-overrides.template.tsv" ] || die 'dispatch runtime templates are unavailable'
mkdir -p "$output/home" "$output/primary" "$output/codex-home"
git -C "$output/primary" init -q 2>/dev/null || die 'cannot create clean primary repository'
case "$readonly_server" in "") mcp='{}' ;; context7) mcp='{"context7":{"type":"http","url":"https://mcp.context7.com/mcp","readOnly":true}}' ;; *) die 'only the qualified read-only context7 server is available' ;; esac
if [ -z "$readonly_server" ]; then cp "$TEMPLATE_DIR/claude-review-settings.template.json" "$output/claude-settings.json"; else printf '{"fastMode":true,"enabledPlugins":{},"hooks":{},"permissions":{"allow":[],"deny":[]},"mcpServers":%s}\n' "$mcp" > "$output/claude-settings.json"; fi
printf '{"mcpServers":%s}\n' "$mcp" > "$output/mcp.json"
cp "$TEMPLATE_DIR/codex-review-overrides.template.tsv" "$output/codex-overrides.tsv"
printf 'config_hash='
if command -v shasum >/dev/null 2>&1; then
  { shasum -a 256 "$output/claude-settings.json"; shasum -a 256 "$output/mcp.json"; shasum -a 256 "$output/codex-overrides.tsv"; } | awk '{print $1}' | tr '\n' ':' | sed 's/:$//'
else
  { sha256sum "$output/claude-settings.json"; sha256sum "$output/mcp.json"; sha256sum "$output/codex-overrides.tsv"; } | awk '{print $1}' | tr '\n' ':' | sed 's/:$//'
fi
printf '\n'
