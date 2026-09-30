#!/bin/bash
# ============================================================================
# Claude Code Project Setup Script
# Company-wide template for consistent AI-assisted development workflow
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory (where templates live - same directory as this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Set up Forge configuration in the current project."
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -p, --project NAME  Project name (default: directory name)"
    echo "  -t, --tech STACK    Tech stack: python, typescript, fullstack (default: fullstack)"
    echo "  -u, --upgrade       Update an existing v6 install; preserve project configuration"
    echo "  -f, --force         Authoritative transactional full installation/reconciliation"
    echo "      --dry-run       Preview --force without writing target files"
    echo "  -g, --global        Retired; prints the project-only migration path"
    echo "      --retire-global Preview removal of a legacy global Forge harness"
    echo "      --apply         Apply --retire-global after a matching preview"
    echo "      --confirm SHA   Confirm the exact retirement preview digest"
    echo "  -w, --with-playwright  Install Playwright framework templates (requires -t fullstack or typescript)"
    echo "  --playwright-dir DIR   Scaffold Playwright into DIR instead of repo root (monorepo layouts)"
    echo "                         If omitted: auto-detect frontend/apps/web/web/client if exactly one matches"
    echo ""
    echo "Examples:"
    echo "  $0                          # Setup with defaults"
    echo "  $0 -p \"My Project\"          # Custom project name"
    echo "  $0 -t python                # Python-only project"
    echo "  $0 --upgrade                # Update an existing v6 install"
    echo "  $0 --force --dry-run        # Preview full reconciliation"
    echo "  $0 --force                  # Execute full reconciliation"
    echo "  $0 --retire-global          # Preview legacy machine-wide cleanup"
    echo "  $0 --retire-global --apply --confirm SHA256"
    echo "  $0 -t fullstack --with-playwright  # Install Playwright framework templates"
}

# Parse arguments
PROJECT_NAME=""
TECH_STACK="fullstack"
FORCE=false
FULL_REFRESH=false
DRY_RUN=false
UPGRADE=false
RETIRE_GLOBAL=false
RETIRE_APPLY=false
RETIRE_CONFIRM=""
WITH_PLAYWRIGHT=false
DEPRECATED_FULL_REFRESH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -p|--project)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -t|--tech)
            TECH_STACK="$2"
            shift 2
            ;;
        -f|--force)
            FULL_REFRESH=true
            shift
            ;;
        -F)
            FULL_REFRESH=true
            DEPRECATED_FULL_REFRESH="DEPRECATED: -F is an alias for -f; use -f or --force."
            shift
            ;;
        --full-refresh)
            FULL_REFRESH=true
            DEPRECATED_FULL_REFRESH="DEPRECATED: --full-refresh is an alias for --force; use --force."
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -u|--upgrade)
            UPGRADE=true
            FORCE=true  # upgrade implies force for hooks/commands/rules
            shift
            ;;
        --migrate)
            echo "ERROR: --migrate was retired in Forge 6; no files changed. Run $0 -f --dry-run." >&2
            exit 1
            ;;
        -g|--global)
            echo "ERROR: global installation is retired; Forge is installed per project. Use --retire-global to preview cleanup of a legacy machine-wide harness." >&2
            exit 1
            ;;
        --retire-global)
            RETIRE_GLOBAL=true
            shift
            ;;
        --apply)
            RETIRE_APPLY=true
            shift
            ;;
        --confirm)
            RETIRE_CONFIRM="$2"
            shift 2
            ;;
        -w|--with-playwright)
            WITH_PLAYWRIGHT=true
            shift
            ;;
        --playwright-dir)
            PLAYWRIGHT_DIR="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

if [ "$RETIRE_APPLY" = true ] && [ "$RETIRE_GLOBAL" != true ]; then
    echo -e "${RED}ERROR: --apply is valid only with --retire-global.${NC}" >&2
    exit 1
fi
if [ -n "$RETIRE_CONFIRM" ] && [ "$RETIRE_GLOBAL" != true ]; then
    echo -e "${RED}ERROR: --confirm is valid only with --retire-global.${NC}" >&2
    exit 1
fi
if [ "$RETIRE_GLOBAL" = true ]; then
    if [ "$RETIRE_APPLY" = true ]; then
        [[ "$RETIRE_CONFIRM" =~ ^[0-9a-f]{64}$ ]] || {
            echo -e "${RED}ERROR: --retire-global --apply requires --confirm with the preview's lowercase SHA-256.${NC}" >&2
            exit 1
        }
    elif [ -n "$RETIRE_CONFIRM" ]; then
        echo -e "${RED}ERROR: --confirm requires --apply.${NC}" >&2
        exit 1
    fi
    command -v python3 >/dev/null 2>&1 || {
        echo "BLOCKED: Python 3 is required only for legacy global retirement" >&2
        exit 2
    }
    retire_args=(--repo-root "$SCRIPT_DIR" --home "${HOME:?HOME is required}" --platform unix)
    if [ "$RETIRE_APPLY" = true ]; then
        retire_args+=(--apply --digest "$RETIRE_CONFIRM")
    fi
    exec python3 "$SCRIPT_DIR/scripts/retire-global.py" "${retire_args[@]}"
fi

if [ "$DRY_RUN" = true ] && [ "$FULL_REFRESH" != true ]; then
    echo -e "${RED}ERROR: --dry-run requires --force.${NC}" >&2
    exit 1
fi

if [ "$FULL_REFRESH" = true ] && { [ "$UPGRADE" = true ] || [ "$WITH_PLAYWRIGHT" = true ]; }; then
    echo -e "${RED}ERROR: --force cannot be combined with --upgrade or --with-playwright.${NC}" >&2
    exit 1
fi

if [ -n "$DEPRECATED_FULL_REFRESH" ]; then
    echo "$DEPRECATED_FULL_REFRESH" >&2
fi

report_native_goal_collisions() {
    local root="$1"
    if [ -e "$root/.claude/commands/goal.md" ]; then
        echo "RUNTIME_READY=BLOCKED host=claude custom native goal collision; rename .claude/commands/goal.md and rerun setup"
    fi
    if [ -e "$root/.agents/skills/goal" ]; then
        echo "RUNTIME_READY=BLOCKED host=codex custom native goal collision; rename .agents/skills/goal/ and rerun setup"
    fi
}

# The first release heading is the single source of truth for the exact
# repository-local Forge release. Every installation path receives this value
# explicitly; no host-specific or machine-wide version stamp exists.
forge_version() {
    local top v
    top=$(grep -m1 '^## ' "$SCRIPT_DIR/docs/CHANGELOG.md" 2>/dev/null)
    v=$(printf '%s' "$top" | sed -nE 's/^##[[:space:]]+([0-9]+\.[0-9]+).*/\1/p')
    if [[ "$v" =~ ^[0-9]+\.[0-9]+$ ]]; then printf '%s' "$v"; else printf 'unknown'; fi
}
FORGE_VERSION="$(forge_version)"
[[ "$FORGE_VERSION" =~ ^[0-9]+\.[0-9]+$ ]] || {
    echo "BLOCKED: published Forge release is unavailable" >&2
    exit 2
}

# Full refresh is a separate transaction. It exits before ordinary setup can
# stamp, merge, or create any host surface.
if [ "$FULL_REFRESH" = true ]; then
    refresh_helper="$SCRIPT_DIR/scripts/full-refresh.sh"
    [ -f "$refresh_helper" ] || { echo "BLOCKED: full-refresh helper not found: $refresh_helper" >&2; exit 1; }
    refresh_args=(--target "$(pwd -P)" --scope project)
    refresh_args+=(--release-version "$FORGE_VERSION")
    [ "$DRY_RUN" = true ] && refresh_args+=(--dry-run)
    bash "$refresh_helper" "${refresh_args[@]}"
    report_native_goal_collisions "$(pwd -P)"
    exit $?
fi

# Task 2 checkpoint safety: do not create a v6 discovery surface beside a
# recognizable or ambiguous v5 harness. Task 3 replaces this interim block
# with the transactional full-refresh implementation and executable command.
v6_preflight_no_legacy() {
    local root="$1" scope="$2" manifest="$SCRIPT_DIR/manifests/legacy-v5.tsv" installed_version installed_major
    local kind source destination row_scope platform host ownership selector proof extra family mixed_path
    if [ -f "$root/.forge/version" ]; then
        installed_version=$(tr -d '\r\n' < "$root/.forge/version" 2>/dev/null)
        case "$installed_version" in 6|6.*) installed_major=6 ;; [0-9]*.*) installed_major=${installed_version%%.*} ;; *) installed_major="$installed_version" ;; esac
        [ "$installed_major" = 6 ] || {
            echo "BLOCKED: unsupported Forge layout major ${installed_major:-unknown}" >&2
            return 1
        }
        case "$installed_version" in 6|6.[0-9]*) ;; *)
            echo "BLOCKED: malformed Forge release at $root/.forge/version" >&2
            return 1
        esac
        return 0
    fi
    if [ "$scope" = project ] && { [ -e "$root/CONTINUITY.md" ] || [ -L "$root/CONTINUITY.md" ]; }; then
        echo "BLOCKED: legacy CONTINUITY.md requires authoritative preview; run $SCRIPT_DIR/setup.sh -f --dry-run" >&2
        return 1
    fi
    [ -f "$manifest" ] || { echo "BLOCKED: legacy v5 inventory is unavailable" >&2; return 1; }
    # Inventory-derived discovery families deliberately fail closed for a lone
    # exact or ambiguous v5 surface. Shared docs and .mcp.json are not startup
    # policy and are handled by their content-preserving v6 merge paths.
    while IFS=$'\t' read -r kind source destination row_scope platform host ownership selector proof extra; do
        case "$kind" in ""|'#'*) continue ;; esac
        [ -z "$extra" ] || { echo "BLOCKED: malformed legacy v5 inventory" >&2; return 1; }
        [ "$row_scope" = "$scope" ] || continue
        case "$platform" in all|unix) ;; *) continue ;; esac
        case "$destination" in
            CLAUDE.md|.claude/CLAUDE.md)
                [ "$ownership" = mixed-regions ] || continue
                mixed_path="$root/$destination"
                [ -f "$mixed_path" ] || continue
                grep -Eq '^# CLAUDE\.md - |^## Project Overview$|^### Research Enforcement$|^## Detailed Rules$|\.claude/(commands|rules|hooks|skills|agents)/' "$mixed_path" || continue
                ;;
            .claude/*)
                family=${destination#'.claude/'}
                family=${family%%/*}
                family=".claude/$family"
                [ -e "$root/$family" ] || continue
                # A lone custom native goal is not a legacy Forge harness. Let
                # setup preserve it and report the explicit goal collision.
                if [ "$scope" = project ] && [ "$family" = ".claude/commands" ] \
                    && [ -f "$root/.claude/commands/goal.md" ] \
                    && [ "$(find "$root/.claude/commands" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = "1" ]; then
                    continue
                fi
                ;;
            *) continue ;;
        esac
        if [ "$UPGRADE" = true ]; then
            echo "BLOCKED: legacy Forge harness requires authoritative refresh. Preview first: '$SCRIPT_DIR/setup.sh' -f --dry-run" >&2
        else
            echo "BLOCKED: legacy Forge harness detected. Preview first: '$SCRIPT_DIR/setup.sh' -f --dry-run" >&2
        fi
        return 1
    done < "$manifest"
}

v6_preflight_no_legacy "$(pwd)" project || exit 1

# Copy function with force check
copy_file() {
    local src="$1"
    local dest="$2"
    local desc="$3"

    if [[ ! -f "$src" ]]; then
        echo -e "  ${RED}✗${NC} Template not found: $src"
        return 1
    fi

    # Self-copy guard: when setup.sh is run IN-PLACE (e.g. a forge maintainer
    # dogfooding via `./setup.sh --upgrade` in the repo itself), SCRIPT_DIR ==
    # repo root, so some copies resolve to the same file (e.g. docs/adr/*).
    # `cp X X` errors "are identical" with a non-zero exit, and `set -e` would
    # abort the whole installer mid-run. Same file → copying is a no-op, so skip.
    # `-ef` detects same inode (handles symlinks/hardlinks) without a subprocess.
    if [[ -e "$dest" ]] && [[ "$src" -ef "$dest" ]]; then
        echo -e "  ${BLUE}○${NC} $desc already current (source and destination are the same file)"
        return 0
    fi

    if [[ -f "$dest" ]] && [[ "$FORCE" != true ]]; then
        echo -e "  ${BLUE}○${NC} $desc already exists (use --upgrade to refresh)"
        return 0
    fi

    cp "$src" "$dest"
    echo -e "  ${GREEN}✓${NC} Created $desc"
}

# ============================================================================
# PROJECT SETUP
# ============================================================================

# Validate --with-playwright flag
if [[ "$WITH_PLAYWRIGHT" == true ]]; then
    if [[ "$TECH_STACK" != "fullstack" && "$TECH_STACK" != "typescript" ]]; then
        echo -e "${RED}ERROR: --with-playwright requires -t fullstack or -t typescript.${NC}"
        echo -e "${YELLOW}Playwright framework only applies to web/TS projects.${NC}"
        exit 1
    fi
fi

# Default project name to directory name
if [[ -z "$PROJECT_NAME" ]]; then
    PROJECT_NAME=$(basename "$(pwd)")
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Claude Code Setup for: ${GREEN}$PROJECT_NAME${NC}"
echo -e "${BLUE}  Tech Stack: ${GREEN}$TECH_STACK${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v jq &> /dev/null; then
    echo -e "  ${YELLOW}⚠${NC} jq not found. The pre-compact-memory hook will output less session context."
    echo "    Install for best experience: brew install jq (macOS) or apt install jq (Linux)"
fi

if ! command -v git &> /dev/null; then
    echo -e "${RED}ERROR: git is required but not installed.${NC}"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}BLOCKED: Python 3 is required before Forge setup can change project files.${NC}" >&2
    exit 1
fi

if ! git rev-parse --is-inside-work-tree &> /dev/null 2>&1; then
    echo -e "${YELLOW}WARNING: Not in a git repository. Initializing...${NC}"
    git init
fi

SETUP_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo -e "${RED}BLOCKED: cannot resolve the Git repository root.${NC}" >&2
    exit 1
}
SETUP_REPO_ROOT=$(cd "$SETUP_REPO_ROOT" && pwd -P)
SETUP_WORKING_ROOT=$(pwd -P)
if [[ "$SETUP_WORKING_ROOT" != "$SETUP_REPO_ROOT" ]]; then
    echo -e "${RED}BLOCKED: run setup from the Git repository root: $SETUP_REPO_ROOT${NC}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Runtime version preflight (warn-only, never blocks).
#
# Scope (intentionally narrow for v1, per Engineering Council verdict):
#   - Reads repo-root .python-version, .nvmrc, and root package.json:engines.node
#   - Prints a warning with install guidance if the declared runtime is missing
#   - NEVER sets a non-zero exit code — --upgrade must always complete
#   - Silent if no pins exist
#
# Full rationale + troubleshooting: docs/guides/multi-project-isolation.md
# ---------------------------------------------------------------------------
preflight_python_version() {
    local required="$1"
    # Try version managers + system interpreter in order of reliability.
    # If ANY of them can supply the required version, we're good.
    #
    # NOTE: `uv python find` checks only *installed* interpreters (exits 0 if
    # one satisfies the request, non-zero otherwise). `uv python list` shows
    # downloadable versions too, which would cause false positives — don't
    # use list here.
    if command -v uv &>/dev/null; then
        uv python find "$required" >/dev/null 2>&1 && return 0
    fi
    if command -v pyenv &>/dev/null; then
        pyenv versions --bare 2>/dev/null | grep -qF "$required" && return 0
    fi
    # System python3.X where X matches (e.g., python3.12 for .python-version=3.12.5)
    local major_minor
    major_minor=$(echo "$required" | awk -F. '{print $1"."$2}')
    if [[ -n "$major_minor" ]] && command -v "python$major_minor" &>/dev/null; then
        return 0
    fi
    # Fallback: exact match from plain python3 --version
    if command -v python3 &>/dev/null; then
        python3 --version 2>&1 | grep -qF "$required" && return 0
    fi
    return 1
}

preflight_node_version() {
    local required="$1"
    # Strip leading 'v' if present (.nvmrc sometimes has it)
    required="${required#v}"

    # Distinguish bare-major pins ('20') from full versions ('20.11.0').
    # Bare major ⇒ any patch under that major satisfies.
    # Full version ⇒ require exact match.
    local is_full_version=0
    [[ "$required" == *.* ]] && is_full_version=1

    if command -v node &>/dev/null; then
        local current
        current=$(node --version 2>/dev/null | sed 's/^v//')
        if [[ "$is_full_version" == 1 ]]; then
            [[ "$required" == "$current" ]] && return 0
        else
            local req_major cur_major
            req_major=$(echo "$required" | awk -F. '{print $1}')
            cur_major=$(echo "$current" | awk -F. '{print $1}')
            [[ "$req_major" == "$cur_major" ]] && return 0
        fi
    fi
    # Version manager listings — match the version as a bounded token so
    # '20.11.0' does NOT accidentally satisfy '20.11.01' and '18' does NOT
    # accidentally match '20.18.x'.
    for vm in fnm nvm volta; do
        command -v "$vm" &>/dev/null || continue
        if [[ "$is_full_version" == 1 ]]; then
            # Match "v?20.11.0" followed by end-of-line, whitespace, or non-digit
            "$vm" list 2>/dev/null | grep -qE "v?${required//./\\.}([^0-9]|$)" && return 0
        else
            # Match "v?20.<digit>" — any patch under this major
            "$vm" list 2>/dev/null | grep -qE "v?${required}\\.[0-9]" && return 0
        fi
    done
    return 1
}

preflight_node_engines() {
    # $1 = engines.node constraint (e.g., ">=20", "^18.0.0", "20")
    local constraint="$1"
    # Extract minimum major version from constraint for a rough check.
    # Not a full semver solver — good enough for "is node the right major-ish?"
    local min_major
    min_major=$(echo "$constraint" | grep -oE '[0-9]+' | head -1)
    [[ -z "$min_major" ]] && return 0  # Unparseable — skip rather than false-warn
    if ! command -v node &>/dev/null; then
        return 1
    fi
    local current_major
    current_major=$(node --version 2>/dev/null | sed 's/^v//' | awk -F. '{print $1}')
    [[ -z "$current_major" ]] && return 1
    # Simple >= check; doesn't handle complex ranges but covers 95% of real engines fields
    [[ "$current_major" -ge "$min_major" ]]
}

echo -e "${YELLOW}Runtime version preflight...${NC}"
PREFLIGHT_WARNED=0

# .python-version (strip whitespace/comments)
if [[ -f ".python-version" ]]; then
    PY_REQ=$(head -1 .python-version | tr -d '[:space:]')
    if [[ -n "$PY_REQ" ]]; then
        if preflight_python_version "$PY_REQ"; then
            echo -e "  ${GREEN}✓${NC} Python $PY_REQ available (from .python-version)"
        else
            PREFLIGHT_WARNED=1
            echo -e "  ${YELLOW}⚠${NC} .python-version requires ${YELLOW}$PY_REQ${NC}, not detected on this machine."
            echo -e "    Install one of:"
            echo -e "      ${BLUE}uv python install $PY_REQ${NC}       (fastest — uv-native)"
            echo -e "      ${BLUE}pyenv install $PY_REQ${NC}          (classic)"
            echo -e "    Setup continues; uv sync will retry at project build time."
        fi
    fi
fi

# .nvmrc
if [[ -f ".nvmrc" ]]; then
    NODE_REQ=$(head -1 .nvmrc | tr -d '[:space:]')
    if [[ -n "$NODE_REQ" ]]; then
        if preflight_node_version "$NODE_REQ"; then
            echo -e "  ${GREEN}✓${NC} Node $NODE_REQ available (from .nvmrc)"
        else
            PREFLIGHT_WARNED=1
            echo -e "  ${YELLOW}⚠${NC} .nvmrc requires Node ${YELLOW}$NODE_REQ${NC}, not detected on this machine."
            echo -e "    Install one of:"
            echo -e "      ${BLUE}fnm install $NODE_REQ${NC}           (fastest — auto-switches)"
            echo -e "      ${BLUE}nvm install $NODE_REQ${NC}           (classic)"
            echo -e "      ${BLUE}volta install node@$NODE_REQ${NC}"
        fi
    fi
fi

# Root package.json engines.node (only check root to keep v1 scope narrow).
# `|| true` guards against `set -e` aborting setup if jq fails on malformed
# JSON or if jq isn't installed at all. Missing jq / unparseable JSON just
# silently skips the engines check — mirrors the PowerShell try/catch path.
NODE_ENGINES=""
if [[ -f "package.json" ]] && command -v jq &>/dev/null; then
    NODE_ENGINES=$(jq -r '.engines.node // empty' package.json 2>/dev/null || true)
fi
if [[ -n "$NODE_ENGINES" ]]; then
    if preflight_node_engines "$NODE_ENGINES"; then
        echo -e "  ${GREEN}✓${NC} Node satisfies engines.node ${BLUE}$NODE_ENGINES${NC}"
    else
        PREFLIGHT_WARNED=1
        echo -e "  ${YELLOW}⚠${NC} package.json engines.node requires ${YELLOW}$NODE_ENGINES${NC}, current Node does not match."
        echo -e "    Install a matching Node version via fnm / nvm / volta."
    fi
fi

if [[ "$PREFLIGHT_WARNED" -eq 1 ]]; then
    echo -e "  ${BLUE}ℹ${NC} See docs/guides/multi-project-isolation.md for the full policy."
fi

echo -e "${GREEN}✓ Prerequisites OK${NC}"
echo ""

# Create directory structure
echo -e "${YELLOW}Creating directory structure...${NC}"

directories=(
    ".claude/hooks"
    ".claude/rules"
    ".claude/commands/prd"
    ".claude/agents"
    ".claude/skills/ui-design/references"
    ".claude/skills/generate-image"
    ".claude/skills/release"
    ".claude/skills/council/references"
    "docs/prds"
    "docs/plans"
    "docs/solutions/build-errors"
    "docs/solutions/test-failures"
    "docs/solutions/runtime-errors"
    "docs/solutions/performance-issues"
    "docs/solutions/database-issues"
    "docs/solutions/security-issues"
    "docs/solutions/ui-bugs"
    "docs/solutions/integration-issues"
    "docs/solutions/logic-errors"
    "docs/solutions/patterns"
    "docs/research"
    "tests/e2e/use-cases"
    "tests/e2e/reports"
)

for dir in "${directories[@]}"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        echo -e "  ${GREEN}✓${NC} Created $dir"
    else
        echo -e "  ${BLUE}○${NC} $dir already exists"
    fi
done

# E2E reports are ephemeral — ignore everything except this gitignore itself.
if [[ ! -f "tests/e2e/reports/.gitignore" ]]; then
    cat > tests/e2e/reports/.gitignore << 'EOF'
*
!.gitignore
EOF
    echo -e "  ${GREEN}✓${NC} Created tests/e2e/reports/.gitignore (reports are ephemeral)"
fi
echo ""

# Copy templates
echo -e "${YELLOW}Copying configuration files...${NC}"

# Main files — CLAUDE.md and CONTINUITY.md are NEVER overwritten (user content).
# Capture pre-state so the end-of-run summary can honestly report which files
# were preserved (vs. freshly created from template in this run).
if [[ -f "CLAUDE.md" ]]; then had_claude_md=true; else had_claude_md=false; fi
if [[ -f "CONTINUITY.md" ]]; then had_continuity_md=true; else had_continuity_md=false; fi

prev_forge_version=""
if [[ -f ".forge/version" ]]; then
    prev_forge_version=$(tr -d '\r\n' < .forge/version)
fi

if [[ "$had_claude_md" == true ]]; then
    echo -e "  ${BLUE}○${NC} CLAUDE.md user text will be preserved outside the Forge block"
fi
bash "$SCRIPT_DIR/scripts/materialize-adapters.sh" \
    --repo-root "$SCRIPT_DIR" --target "$(pwd)" --scope project --platform unix \
    --release-version "$FORGE_VERSION"
if [[ -n "$prev_forge_version" && "$prev_forge_version" != "$FORGE_VERSION" ]]; then
    echo "FORGE_VERSION_CHANGE: $prev_forge_version -> $FORGE_VERSION"
fi
report_native_goal_collisions "$(pwd -P)"

# ADRs belong to the downstream project. Retire only byte-exact copies of
# Forge's internal decisions; preserve every customized or project-authored
# file, including same-numbered ADRs. Then seed neutral scaffolding if absent.
mkdir -p docs/adr
for forge_adr_source in "$SCRIPT_DIR/docs/adr/README.md" "$SCRIPT_DIR"/docs/adr/[0-9][0-9][0-9][0-9]-*.md; do
    [[ -f "$forge_adr_source" ]] || continue
    forge_adr_name=$(basename "$forge_adr_source")
    forge_adr_target="docs/adr/$forge_adr_name"
    if [[ -f "$forge_adr_target" ]] && ! [[ "$forge_adr_source" -ef "$forge_adr_target" ]] && cmp -s "$forge_adr_source" "$forge_adr_target"; then
        rm -f "$forge_adr_target"
        echo -e "  ${BLUE}○${NC} Retired exact Forge-internal ADR seed: $forge_adr_target"
    fi
done
if [[ ! -f docs/adr/template.md ]]; then
    copy_file "$SCRIPT_DIR/docs/adr/template.md" "docs/adr/template.md" "docs/adr/template.md"
fi
if [[ ! -f docs/adr/README.md ]]; then
    copy_file "$SCRIPT_DIR/templates/project-adr/README.md" "docs/adr/README.md" "docs/adr/README.md (project ADR index)"
fi

# Keep both the v6 canonical local state and the transitional v5-compatible
# state path private and idempotently ignored.
if [ -f ".gitignore" ]; then
    if ! grep -qxF ".claude/local/" .gitignore; then
        echo "" >> .gitignore
        echo "# Volatile per-developer workflow state (PR #2 / continuity-split)" >> .gitignore
        echo ".claude/local/" >> .gitignore
        echo -e "  ${GREEN}+${NC} Added .claude/local/ to .gitignore"
    fi
    if ! grep -qxF ".forge/local/" .gitignore; then echo ".forge/local/" >> .gitignore; fi
else
    cat > .gitignore <<'EOF'
# Volatile per-developer workflow state (PR #2 / continuity-split)
.claude/local/
.forge/local/
EOF
    echo -e "  ${GREEN}+${NC} Created .gitignore with .claude/local/"
fi

# The manifest materializer above owns all v6 adapters. The unreachable legacy
# block remains temporarily for the v5 contract strings Task 3 consumes.
if false; then
# Agents
copy_file "$SCRIPT_DIR/agents/verify-app.md" ".claude/agents/verify-app.md" ".claude/agents/verify-app.md"
copy_file "$SCRIPT_DIR/agents/verify-e2e.md" ".claude/agents/verify-e2e.md" ".claude/agents/verify-e2e.md"
copy_file "$SCRIPT_DIR/agents/council-advisor.md" ".claude/agents/council-advisor.md" ".claude/agents/council-advisor.md"
copy_file "$SCRIPT_DIR/agents/research-first.md" ".claude/agents/research-first.md" ".claude/agents/research-first.md"

# Skills (tech-agnostic)
copy_file "$SCRIPT_DIR/skills/release/SKILL.template.md" ".claude/skills/release/SKILL.md" ".claude/skills/release/SKILL.md"

# Engineering Council skill (tech-agnostic) — multi-perspective decision analysis
copy_file "$SCRIPT_DIR/skills/council/SKILL.template.md" ".claude/skills/council/SKILL.md" ".claude/skills/council/SKILL.md"
copy_file "$SCRIPT_DIR/skills/council/references/advisors.md" ".claude/skills/council/references/advisors.md" ".claude/skills/council/references/advisors.md"
copy_file "$SCRIPT_DIR/skills/council/references/output-schema.md" ".claude/skills/council/references/output-schema.md" ".claude/skills/council/references/output-schema.md"
copy_file "$SCRIPT_DIR/skills/council/references/peer-review-protocol.md" ".claude/skills/council/references/peer-review-protocol.md" ".claude/skills/council/references/peer-review-protocol.md"

# Commands - Workflow (ENFORCED)
copy_file "$SCRIPT_DIR/commands/new-feature.md" ".claude/commands/new-feature.md" ".claude/commands/new-feature.md"
copy_file "$SCRIPT_DIR/commands/fix-bug.md" ".claude/commands/fix-bug.md" ".claude/commands/fix-bug.md"
copy_file "$SCRIPT_DIR/commands/quick-fix.md" ".claude/commands/quick-fix.md" ".claude/commands/quick-fix.md"
copy_file "$SCRIPT_DIR/commands/finish-branch.md" ".claude/commands/finish-branch.md" ".claude/commands/finish-branch.md"
copy_file "$SCRIPT_DIR/commands/review-pr-comments.md" ".claude/commands/review-pr-comments.md" ".claude/commands/review-pr-comments.md"

# Commands - PRD
copy_file "$SCRIPT_DIR/commands/prd/discuss.md" ".claude/commands/prd/discuss.md" ".claude/commands/prd/discuss.md"
copy_file "$SCRIPT_DIR/commands/prd/create.md" ".claude/commands/prd/create.md" ".claude/commands/prd/create.md"

# Rules based on tech stack
echo ""
echo -e "${YELLOW}Copying rules for ${TECH_STACK}...${NC}"

# Common rules (apply to all tech stacks)
common_rules=("security.md" "skill-audit.md" "api-design.md" "testing.md" "principles.md" "workflow.md" "worktree-policy.md" "critical-rules.md" "memory.md")
for rule in "${common_rules[@]}"; do
    copy_file "$SCRIPT_DIR/rules/$rule" ".claude/rules/$rule" ".claude/rules/$rule"
done

# Tech-specific rules
case $TECH_STACK in
    python)
        copy_file "$SCRIPT_DIR/rules/python-style.md" ".claude/rules/python-style.md" ".claude/rules/python-style.md"
        copy_file "$SCRIPT_DIR/rules/database.md" ".claude/rules/database.md" ".claude/rules/database.md"
        ;;
    typescript)
        copy_file "$SCRIPT_DIR/rules/typescript-style.md" ".claude/rules/typescript-style.md" ".claude/rules/typescript-style.md"
        copy_file "$SCRIPT_DIR/rules/frontend-design.md" ".claude/rules/frontend-design.md" ".claude/rules/frontend-design.md"
        # UI Design skill (auto-triggers for frontend work) — all 10 references
        copy_file "$SCRIPT_DIR/skills/ui-design/SKILL.template.md" ".claude/skills/ui-design/SKILL.md" ".claude/skills/ui-design/SKILL.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/animation-techniques.md" ".claude/skills/ui-design/references/animation-techniques.md" ".claude/skills/ui-design/references/animation-techniques.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/typography-and-color.md" ".claude/skills/ui-design/references/typography-and-color.md" ".claude/skills/ui-design/references/typography-and-color.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/polish-checklist.md" ".claude/skills/ui-design/references/polish-checklist.md" ".claude/skills/ui-design/references/polish-checklist.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/media-assets.md" ".claude/skills/ui-design/references/media-assets.md" ".claude/skills/ui-design/references/media-assets.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/industry-design-guide.md" ".claude/skills/ui-design/references/industry-design-guide.md" ".claude/skills/ui-design/references/industry-design-guide.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/ux-antipatterns.md" ".claude/skills/ui-design/references/ux-antipatterns.md" ".claude/skills/ui-design/references/ux-antipatterns.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/landing-patterns.md" ".claude/skills/ui-design/references/landing-patterns.md" ".claude/skills/ui-design/references/landing-patterns.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/21st-dev-components.md" ".claude/skills/ui-design/references/21st-dev-components.md" ".claude/skills/ui-design/references/21st-dev-components.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/product-ui-patterns.md" ".claude/skills/ui-design/references/product-ui-patterns.md" ".claude/skills/ui-design/references/product-ui-patterns.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/trust-first-patterns.md" ".claude/skills/ui-design/references/trust-first-patterns.md" ".claude/skills/ui-design/references/trust-first-patterns.md"
        # Image generation skill (Gemini API — checks docs for current model)
        copy_file "$SCRIPT_DIR/skills/generate-image/SKILL.template.md" ".claude/skills/generate-image/SKILL.md" ".claude/skills/generate-image/SKILL.md"
        ;;
    fullstack|*)
        copy_file "$SCRIPT_DIR/rules/python-style.md" ".claude/rules/python-style.md" ".claude/rules/python-style.md"
        copy_file "$SCRIPT_DIR/rules/typescript-style.md" ".claude/rules/typescript-style.md" ".claude/rules/typescript-style.md"
        copy_file "$SCRIPT_DIR/rules/database.md" ".claude/rules/database.md" ".claude/rules/database.md"
        copy_file "$SCRIPT_DIR/rules/frontend-design.md" ".claude/rules/frontend-design.md" ".claude/rules/frontend-design.md"
        # UI Design skill (auto-triggers for frontend work) — all 10 references
        copy_file "$SCRIPT_DIR/skills/ui-design/SKILL.template.md" ".claude/skills/ui-design/SKILL.md" ".claude/skills/ui-design/SKILL.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/animation-techniques.md" ".claude/skills/ui-design/references/animation-techniques.md" ".claude/skills/ui-design/references/animation-techniques.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/typography-and-color.md" ".claude/skills/ui-design/references/typography-and-color.md" ".claude/skills/ui-design/references/typography-and-color.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/polish-checklist.md" ".claude/skills/ui-design/references/polish-checklist.md" ".claude/skills/ui-design/references/polish-checklist.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/media-assets.md" ".claude/skills/ui-design/references/media-assets.md" ".claude/skills/ui-design/references/media-assets.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/industry-design-guide.md" ".claude/skills/ui-design/references/industry-design-guide.md" ".claude/skills/ui-design/references/industry-design-guide.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/ux-antipatterns.md" ".claude/skills/ui-design/references/ux-antipatterns.md" ".claude/skills/ui-design/references/ux-antipatterns.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/landing-patterns.md" ".claude/skills/ui-design/references/landing-patterns.md" ".claude/skills/ui-design/references/landing-patterns.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/21st-dev-components.md" ".claude/skills/ui-design/references/21st-dev-components.md" ".claude/skills/ui-design/references/21st-dev-components.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/product-ui-patterns.md" ".claude/skills/ui-design/references/product-ui-patterns.md" ".claude/skills/ui-design/references/product-ui-patterns.md"
        copy_file "$SCRIPT_DIR/skills/ui-design/references/trust-first-patterns.md" ".claude/skills/ui-design/references/trust-first-patterns.md" ".claude/skills/ui-design/references/trust-first-patterns.md"
        # Image generation skill (Gemini API — checks docs for current model)
        copy_file "$SCRIPT_DIR/skills/generate-image/SKILL.template.md" ".claude/skills/generate-image/SKILL.md" ".claude/skills/generate-image/SKILL.md"
        ;;
esac
fi

# Playwright framework templates (opt-in via --with-playwright)
if [[ "$WITH_PLAYWRIGHT" == true ]]; then
    echo ""
    echo -e "${YELLOW}Installing Playwright framework templates...${NC}"

    # ------------------------------------------------------------------
    # Determine where Playwright lives.
    # Monorepos typically have package.json inside a frontend subdirectory
    # (frontend/, apps/web/, web/, client/). Flat repos have it at root.
    # We keep them as two separate concepts:
    #   - PW_DIR:     where playwright.config.ts + tests/e2e/ get scaffolded
    #   - PW_PKG_DIR: where `pnpm install` / `pnpm exec playwright` run
    # In most layouts PW_DIR == PW_PKG_DIR. If a user has an unusual
    # pnpm-workspace setup, they can override with --playwright-dir.
    # ------------------------------------------------------------------
    if [[ -n "$PLAYWRIGHT_DIR" ]]; then
        PW_DIR="$PLAYWRIGHT_DIR"
        echo -e "  ${BLUE}→${NC} Using explicit --playwright-dir: ${BLUE}$PW_DIR${NC}"
    else
        # Auto-detect: ONLY commit to a subdir if exactly one candidate matches.
        # Ambiguous detections (multiple apps) fall back to repo root with a warning.
        PW_CANDIDATES=()
        for candidate in frontend apps/web web client; do
            if [[ -f "$candidate/package.json" ]]; then
                PW_CANDIDATES+=("$candidate")
            fi
        done

        if [[ ${#PW_CANDIDATES[@]} -eq 1 ]]; then
            PW_DIR="${PW_CANDIDATES[0]}"
            echo -e "  ${GREEN}✓${NC} Detected frontend at ${BLUE}$PW_DIR${NC} — scaffolding Playwright there."
            echo -e "    (override with ${BLUE}--playwright-dir <path>${NC} if that's wrong)"
        elif [[ ${#PW_CANDIDATES[@]} -gt 1 ]]; then
            echo -e "  ${YELLOW}⚠${NC}  Multiple frontend candidates found: ${PW_CANDIDATES[*]}"
            echo -e "     Scaffolding at repo root to avoid picking wrong. Override with ${BLUE}--playwright-dir <path>${NC}."
            PW_DIR="."
        else
            PW_DIR="."
            echo -e "  ${BLUE}→${NC} No frontend subdirectory detected — scaffolding at repo root."
        fi
    fi

    # Create the target dir if it doesn't exist (explicit --playwright-dir may point to a new path)
    if [[ "$PW_DIR" != "." ]] && [[ ! -d "$PW_DIR" ]]; then
        mkdir -p "$PW_DIR"
        echo -e "  ${GREEN}✓${NC} Created $PW_DIR/"
    fi

    # All Playwright paths are relative to PW_DIR
    PW_SPECS_DIR="$PW_DIR/tests/e2e/specs"
    PW_FIXTURES_DIR="$PW_DIR/tests/e2e/fixtures"
    PW_AUTH_DIR="$PW_DIR/tests/e2e/.auth"

    if [[ ! -d "$PW_SPECS_DIR" ]]; then
        mkdir -p "$PW_SPECS_DIR"
        echo -e "  ${GREEN}✓${NC} Created $PW_SPECS_DIR (for graduated .spec.ts files)"
    fi

    # Playwright config
    copy_file "$SCRIPT_DIR/templates/playwright/playwright.config.template.ts" "$PW_DIR/playwright.config.ts" "$PW_DIR/playwright.config.ts"

    # Auth fixture
    mkdir -p "$PW_FIXTURES_DIR"
    copy_file "$SCRIPT_DIR/templates/playwright/auth.fixture.template.ts" "$PW_FIXTURES_DIR/auth.ts" "$PW_FIXTURES_DIR/auth.ts"

    # Auth storage directory — gitignored because it contains credentials
    mkdir -p "$PW_AUTH_DIR"
    if [[ ! -f "$PW_AUTH_DIR/.gitignore" ]]; then
        cat > "$PW_AUTH_DIR/.gitignore" << 'EOF'
# Auth storage state contains credentials - never commit
*
!.gitignore
EOF
        echo -e "  ${GREEN}✓${NC} Created $PW_AUTH_DIR/.gitignore (credentials protected)"
    fi

    # Persist the chosen PW_DIR so workflow commands (new-feature, fix-bug) can
    # pick it up in Phase 5.4b framework detection and dep-install loops.
    # Falls back to repo root via candidate list if this marker file is missing.
    mkdir -p .claude
    echo "$PW_DIR" > .claude/playwright-dir
    echo -e "  ${GREEN}✓${NC} Recorded Playwright dir in .claude/playwright-dir ($PW_DIR)"

    # CI workflow reference (NOT auto-activated).
    # Stamp PW_DIR into the workflow so defaults.run.working-directory matches
    # the actual scaffold location. Two important subtleties:
    # (1) Use bash parameter expansion (${var//pat/repl}) for the substitution.
    #     Unlike sed AND awk — both of which interpret '&' in the replacement
    #     string as "the matched text" — bash parameter expansion does literal
    #     substitution with NO metachar interpretation. Paths containing &, |,
    #     \, or $ (e.g. --playwright-dir 'apps/r&d') substitute correctly.
    # (2) Preserve user-edited files on non-force reruns (matches copy_file
    #     semantics). setup.sh --with-playwright should be idempotent; a
    #     second run without -f must not clobber CI customizations.
    stamp_ci_template() {
        local src="$1" dest="$2" desc="$3"
        [[ ! -f "$src" ]] && return 0
        if [[ -f "$dest" ]] && [[ "$FORCE" != true ]]; then
            echo -e "  ${BLUE}○${NC} $desc already exists (use --upgrade to refresh)"
            return 0
        fi
        # Read → literal-substitute → write. $(<file) strips trailing newlines;
        # the source templates always end with a newline, so we restore one
        # unconditionally via printf '%s\n'.
        local content
        content=$(<"$src")
        printf '%s\n' "${content//__PLAYWRIGHT_DIR__/$PW_DIR}" > "$dest"
        echo -e "  ${GREEN}✓${NC} Created $desc (working-directory stamped: $PW_DIR)"
    }

    mkdir -p docs/ci-templates
    stamp_ci_template "$SCRIPT_DIR/templates/ci-workflows/e2e.yml" "docs/ci-templates/e2e.yml" "docs/ci-templates/e2e.yml"
    stamp_ci_template "$SCRIPT_DIR/templates/ci-workflows/README.md" "docs/ci-templates/README.md" "docs/ci-templates/README.md"

    # Show the right commands in the next-steps summary based on PW_DIR
    if [[ "$PW_DIR" == "." ]]; then
        CD_HINT=""
        PW_RUN="pnpm exec playwright test"
    else
        CD_HINT="cd $PW_DIR && "
        PW_RUN="cd $PW_DIR && pnpm exec playwright test"
    fi

    echo ""
    echo -e "${GREEN}✓ Playwright templates installed into ${BLUE}$PW_DIR${GREEN}.${NC}"
    echo -e "${YELLOW}Next steps to complete Playwright setup:${NC}"
    echo -e "  1. Install the framework: ${BLUE}${CD_HINT}pnpm add -D @playwright/test${NC}"
    echo -e "     (or npm: ${BLUE}${CD_HINT}npm install --save-dev @playwright/test${NC})"
    echo -e "  2. Install browsers:      ${BLUE}${CD_HINT}pnpm exec playwright install${NC}"
    echo -e "  3. Review ${BLUE}$PW_DIR/playwright.config.ts${NC} — set baseURL and uncomment webServer if needed"
    echo -e "  4. (Optional) Activate CI:"
    echo -e "     ${BLUE}mkdir -p .github/workflows && cp docs/ci-templates/e2e.yml .github/workflows/e2e.yml${NC}"
    echo -e "     Note: CI template uses pnpm with working-directory=$PW_DIR — adjust in .github/workflows/e2e.yml if needed"
    echo -e "  5. Configure auth via env vars: TEST_USER_EMAIL + TEST_USER_PASSWORD (preferred)"
    echo -e "     TEST_API_KEY is supported but insecure — see tests/e2e/fixtures/auth.ts"
    echo -e "  6. Run tests: ${BLUE}$PW_RUN${NC}"
fi

echo ""

# Create CHANGELOG only if it doesn't exist — NEVER overwrite on --upgrade.
# docs/CHANGELOG.md is user content (each project's own release history). Same
# policy as CLAUDE.md and CONTINUITY.md: templates initialize the file on first
# install and never touch it afterward.
if [[ ! -f "docs/CHANGELOG.md" ]]; then
    echo -e "${YELLOW}Creating docs/CHANGELOG.md...${NC}"
    cat > docs/CHANGELOG.md << EOF
# Changelog

All notable changes to $PROJECT_NAME will be documented in this file.

## [Unreleased]

### Added
- Initial project setup with Claude Code configuration

### Changed

### Fixed

### Removed

---

## Format

Each entry should include:
- Date (YYYY-MM-DD)
- Brief description
- Related issue/PR if applicable
EOF
    echo -e "  ${GREEN}✓${NC} Created docs/CHANGELOG.md"
else
    echo -e "  ${BLUE}○${NC} docs/CHANGELOG.md already exists"
fi

# The v6 marker materializer owns only the bounded Forge block. Text outside
# that block is user-owned bytes and is never subject to project-name rewriting.

echo ""
if [[ "$UPGRADE" == true ]]; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Upgrade Complete!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "${YELLOW}What was updated:${NC}"
    echo ""
    echo "  .forge/                  Canonical workflows, rules, hooks, agents, skills, and state template"
    echo "  CLAUDE.md / AGENTS.md    Bounded host adapters; personal text outside Forge markers preserved"
    echo "  .claude/                 Claude Code commands, agents, skills, hooks, and merged settings"
    echo "  .codex/                  Codex agents, hooks, and merged configuration"
    echo "  .agents/                 Codex workflow and skill adapters"
    echo "  .mcp.json                Shared MCP servers (merged — your customizations kept)"
    echo ""
    # Drive "Not touched" from pre-copy booleans so we don't falsely claim a
    # file was preserved when this run actually recreated it from template.
    if [[ "$had_claude_md" == true ]] || [[ "$had_continuity_md" == true ]]; then
        echo -e "${YELLOW}Not touched:${NC}"
        echo ""
        if [[ "$had_claude_md" == true ]]; then
            echo "  CLAUDE.md                Your project description (preserved)"
        fi
        if [[ "$had_continuity_md" == true ]]; then
            echo "  CONTINUITY.md            Your task state (preserved)"
        fi
        echo ""
    fi
    echo -e "${YELLOW}Next steps:${NC}"
    echo ""
    echo -e "1. ${BLUE}Verify everything works${NC}:"
    echo ""
    echo "   /hooks       → Should show: SessionStart, Stop, PreToolUse, PostToolUse, PreCompact, SubagentStop, ConfigChange"
    echo "   /help        → Should show Forge workflows for both installed hosts"
    echo ""
    echo -e "2. ${BLUE}Commit and push${NC}:"
    echo ""
    echo "   git add .forge/ .claude/ .codex/ .agents/ .mcp.json CLAUDE.md AGENTS.md docs/"
    echo "   git commit -m \"chore: upgrade Forge harness\""
    echo "   git push"
    echo ""
    if [[ "$had_continuity_md" == true ]]; then
        echo -e "${YELLOW}⚠ Legacy CONTINUITY.md detected.${NC}"
        echo "  Forge 6 does not rewrite this mixed-content legacy file automatically."
        echo "  Preview the authoritative upgrade inventory before changing anything:"
        echo ""
        echo "    ./setup.sh -f --dry-run"
        echo ""
        echo "  Move durable facts to project instructions, decisions to docs/adr/, and"
        echo "  active state to .forge/local/state.md; then archive or remove CONTINUITY.md."
        echo ""
    fi
    if [[ "$had_claude_md" == true ]] && [[ "$had_continuity_md" == true ]]; then
        echo -e "${GREEN}Upgrade done! Your CLAUDE.md and CONTINUITY.md were preserved; run -f --dry-run to reconcile legacy continuity.${NC}"
    elif [[ "$had_claude_md" == true ]]; then
        echo -e "${GREEN}Upgrade done! Your CLAUDE.md was preserved (user content).${NC}"
    elif [[ "$had_continuity_md" == true ]]; then
        echo -e "${GREEN}Upgrade done! Your CONTINUITY.md was preserved; run -f --dry-run to reconcile legacy continuity.${NC}"
    else
        echo -e "${GREEN}Upgrade done!${NC}"
    fi

    # 5.17: soft tip recommending Claude-driven CLAUDE.md reconciliation when
    # the user's CLAUDE.md was preserved. Replaces the per-file inline drift
    # hint (cry-wolf — fired every upgrade regardless of actual drift). Uses
    # the full Variant B prompt from the migration script for consistency,
    # including the @CONTINUITY.md dangling-import cleanup clause. The "Full
    # guide" reference uses an absolute path to the Forge clone so it resolves
    # correctly when users run setup.sh --upgrade from inside their project.
    # 5.18: prompt expanded to enumerate ALL CONTINUITY reference types
    # (tree diagrams, prose pointers, labels) -- field bug where a downstream project
    # leftover refs at line 102 (tree) and line 212 (prose) survived because
    # the prior single-clause prompt only addressed the @-import line.
    if [[ "$had_claude_md" == true ]]; then
        echo ""
        echo -e "${BLUE}Tip:${NC} ask Claude to reconcile your CLAUDE.md against the latest template:"
        echo ""
        echo "  \"Reconcile my CLAUDE.md against $SCRIPT_DIR/CLAUDE.template.md."
        echo "   Port any new template sections, preserving my project-specific content."
        echo ""
        echo "   Then scan the ENTIRE file and remove every dangling reference to"
        echo "   CONTINUITY.md left over from before the 5.15 migration. Look for:"
        echo "     - @CONTINUITY.md import lines (usually at the top)"
        echo "     - File-tree diagrams that list CONTINUITY.md as a project file"
        echo "     - Prose pointers like 'see CONTINUITY', 'in CONTINUITY.md', '(CONTINUITY)'"
        echo "     - Comments or labels that reference CONTINUITY.md as a location"
        echo ""
        echo "   CONTINUITY.md no longer exists -- its content moved to CLAUDE.md"
        echo "   (durable), docs/adr/ (decisions), and .forge/local/state.md"
        echo "   (volatile). Remove these references; the 'preserve project-specific"
        echo "   content' rule does NOT apply to CONTINUITY pointers -- they are"
        echo "   stale infrastructure references.\""
        echo ""
        echo "  (Full guide: $SCRIPT_DIR/docs/guides/upgrading.md)"
        echo ""
    fi
else
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Setup Complete!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "${YELLOW}What was created:${NC}"
    echo ""
    echo "  .forge/                  Canonical workflows, rules, hooks, agents, skills, and local state"
    echo "  .forge/local/state.md    Per-worktree workflow checkpoint (gitignored)"
    echo "  CLAUDE.md / AGENTS.md    Thin Claude Code and Codex root adapters"
    echo "  .claude/                 Claude Code commands, agents, skills, hooks, and settings"
    echo "  .codex/                  Codex agents, hooks, and configuration"
    echo "  .agents/                 Codex workflow and skill adapters"
    echo "  .mcp.json                Shared MCP servers (Playwright + Context7)"
    echo "  docs/adr/                Architecture decisions and index"
    echo "  docs/                    Changelog, plans, PRDs, research, and solutions"
    echo ""
    echo -e "${YELLOW}Optional host integration enabled in .claude/settings.json:${NC}"
    echo ""
    echo "  - frontend-design          (optional Claude Code UI integration)"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo ""
    echo -e "1. ${BLUE}Verify both installed host surfaces${NC}:"
    echo ""
    echo "   /hooks       → Should show: SessionStart, Stop, PreToolUse, PostToolUse, PreCompact, SubagentStop, ConfigChange"
    echo "   /help        → Claude should show Forge commands; Codex should show matching skills such as \$fix-bug"
    echo "   scripts/verify-runtime.sh discovery --project-root \"$(pwd -P)\""
    echo ""
    echo -e "2. ${BLUE}Commit the shared harness${NC} (.forge/local/ remains gitignored):"
    echo ""
    echo "   git add .forge/ .claude/ .codex/ .agents/ .mcp.json CLAUDE.md AGENTS.md docs/"
    echo "   git commit -m \"chore: add Forge engineering harness\""
    echo "   git push"
    echo ""
    echo -e "${GREEN}Harness materialized for Claude Code and Codex.${NC}"
    echo -e "${YELLOW}Runtime readiness remains BLOCKED until the printed verify/qualify commands pass.${NC}"
fi
