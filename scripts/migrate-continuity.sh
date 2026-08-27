#!/bin/bash
# scripts/migrate-continuity.sh
# Migrate legacy CONTINUITY.md into the new three-artifact structure.
# Idempotent (sentinel-marker-based); original-file-preserving; no dry-run.
#
# Invoked by setup.sh / setup.ps1 on --migrate. Runs in the user's CWD.
# Forge-internal -- not shipped to downstream installs.

set -u  # fail on unset vars; do NOT set -e (we handle errors explicitly)

# AC-4 parity: this script emits ASCII-only, color-free output so its stdout
# matches scripts/migrate-continuity.ps1 byte-for-byte under the test contract.
# If interactive callers want color, setup.sh / setup.ps1 can wrap the dispatch.

# Resolve this script's Forge-clone root so the dangling-import reconcile
# message can name the canonical CLAUDE.template.md path. Forward slash kept
# in the emitted text for cross-platform display + bash/PS parity.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Sentinel marker for idempotency -- embedded in migrated content.
SENTINEL_PREFIX="<!-- forge:migrated"
SENTINEL_TODAY="<!-- forge:migrated $(date +%Y-%m-%d) -->"

LEGACY_FILE="CONTINUITY.md"
STATE_FILE=".forge/local/state.md"
LEGACY_STATE_FILE=".claude/local/state.md"
RECEIPT_FILE=".forge/local/migration-evidence/continuity-state-v5-v6.json"

write_translation_receipt() {
    [ -f "$LEGACY_STATE_FILE" ] && [ -f "$STATE_FILE" ] || return 0
    command -v python3 >/dev/null 2>&1 || {
        echo "x Python 3 is required to bind continuity migration evidence." >&2
        return 1
    }
    python3 "$SCRIPT_DIR/scripts/merge-settings.py" write-continuity-receipt \
        --source "$LEGACY_STATE_FILE" --destination "$STATE_FILE" --receipt "$RECEIPT_FILE"
}

# A continuity migration may precede full refresh. In that case translate the
# active v5 state first so all subsequent writes already use the canonical v6
# path. The original remains untouched for the full-refresh ownership backup.
if [ ! -f "$STATE_FILE" ] && [ -f ".claude/local/state.md" ]; then
    bash "$SCRIPT_DIR/scripts/migrate-state-v5-v6.sh" ".claude/local/state.md" "$STATE_FILE" || exit 1
fi

if [ ! -f "$LEGACY_FILE" ]; then
    write_translation_receipt || exit 1
    # ASCII-safe output for AC-4 byte-equivalence with PS mirror.
    echo "!  No CONTINUITY.md found in this directory. Nothing to migrate."
    exit 0
fi

# Idempotency check -- if either target already has the sentinel, this is a rerun.
# Sentinel locations: top-of-file in canonical .forge/local/state.md AND in CLAUDE.md.
# Sentinel is written UNCONDITIONALLY at the start of migration (see below) --
# so even repos with no Goal / no decisions / no Done content still get marked.
already_migrated() {
    [ -f "CLAUDE.md" ] && grep -qF "$SENTINEL_PREFIX" CLAUDE.md 2>/dev/null && return 0
    [ -f "$STATE_FILE" ] && grep -qF "$SENTINEL_PREFIX" "$STATE_FILE" 2>/dev/null && return 0
    return 1
}

if already_migrated; then
    write_translation_receipt || exit 1
    # Use -E (regex), NOT -F (fixed-string + regex metachars don't mix).
    existing=$(grep -hoE '<!-- forge:migrated [^>]*-->' CLAUDE.md "$STATE_FILE" 2>/dev/null | head -1)
    # Strip "<!-- forge:migrated " prefix and " -->" suffix to get the date alone.
    existing_date=$(echo "$existing" | sed -E 's/^<!-- forge:migrated[[:space:]]+//; s/[[:space:]]+-->$//')
    if [ -n "$existing_date" ]; then
        echo "Already migrated on ${existing_date}."
    else
        echo "Already migrated."
    fi
    echo "  Sentinel marker detected in CLAUDE.md or .forge/local/state.md."
    echo "  No content was modified. To force a fresh migration, remove the marker line(s) and rerun."
    exit 0
fi

# --- Write sentinel UNCONDITIONALLY at the start (before any extraction) ---
# This guarantees idempotency even when the legacy CONTINUITY.md has no Goal,
# no Decisions table, or empty Done -- repos that migrate "nothing" still get
# marked as migrated, so rerun is a no-op (Codex iter-2 P0 fix).
if [ ! -f "$STATE_FILE" ]; then
    # state.md will be present on -f / --upgrade installs; if standalone --migrate
    # was invoked without first running -f, bail with a clear message.
    # (P3 fix: don't pre-create .claude/local/ before this check -- on the failure
    # path it leaves an empty .claude/local/ directory behind in the user's repo.)
    echo "x .forge/local/state.md not found." >&2
    echo "  Run setup -F first to install/translate the canonical state, then rerun --migrate." >&2
    exit 1
fi
# Keep the v6 schema marker on line 1; insert the continuity sentinel on line 2.
if head -1 "$STATE_FILE" | grep -qxF '<!-- forge:state-schema v6 -->'; then
    { head -1 "$STATE_FILE"; echo "$SENTINEL_TODAY"; tail -n +2 "$STATE_FILE"; } > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
else
    echo "x canonical state schema marker missing." >&2
    exit 1
fi

# If CLAUDE.md exists, prepend sentinel as a comment line on line 1 (matches
# state.md treatment + AC-10 amendment). Forge dogfood result confirmed line-1
# placement is the desired behavior; the original "after H1" wording was wrong.
if [ -f "CLAUDE.md" ] && ! grep -qF "$SENTINEL_PREFIX" CLAUDE.md; then
    { echo "$SENTINEL_TODAY"; cat CLAUDE.md; } > CLAUDE.md.tmp && mv CLAUDE.md.tmp CLAUDE.md
fi

echo "Migrating $LEGACY_FILE..."
echo ""

moved_sections=()
skipped_sections=()
created_adrs=()
warnings=()

# --- (a) Extract Goal section to CLAUDE.md ---
# Goal extraction preserves interior blank lines (multi-paragraph goals are valid markdown).
# Only strips leading/trailing blank lines.
goal_content=$(awk '
    /^## Goal$/ { flag=1; next }
    flag && /^## / { flag=0 }
    flag { print }
' "$LEGACY_FILE" | awk '
    NF { found=1; lines[++n]=$0; last=n }
    !NF && found { lines[++n]=$0 }
    END {
        for (i=1; i<=last; i++) print lines[i]
    }
')
goal_placeholder='[PROJECT GOAL - One sentence describing what we'"'"'re building]'

# Trim before comparison to tolerate user-added whitespace variations.
goal_trimmed=$(echo "$goal_content" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

if [ -n "$goal_trimmed" ] && [ "$goal_trimmed" != "$goal_placeholder" ]; then
    if [ -f "CLAUDE.md" ]; then
        if grep -q "^## Project Overview" CLAUDE.md; then
            # Sentinel was already prepended unconditionally above -- no need to duplicate here.
            # Use tmpfile + getline to preserve embedded newlines in multi-paragraph goals
            # (P1-C fix: `awk -v goal="..."` chokes on newlines in the variable value with
            # "awk: newline in string" and silently drops the Goal -- since the sentinel is
            # already written, a rerun is a no-op and the Goal never lands in CLAUDE.md).
            content_file=$(mktemp)
            printf '%s\n' "$goal_content" > "$content_file"
            tmp=$(mktemp)
            awk -v cfile="$content_file" '
                /^## Project Overview$/ {
                    print
                    print ""
                    print "### Goal"
                    print ""
                    while ((getline line < cfile) > 0) print line
                    close(cfile)
                    print ""
                    next
                }
                { print }
            ' CLAUDE.md > "$tmp" && mv "$tmp" CLAUDE.md
            rm -f "$content_file"
            moved_sections+=("Goal -> CLAUDE.md (under ## Project Overview)")
        else
            skipped_sections+=("Goal (CLAUDE.md has no ## Project Overview section)")
        fi
    else
        skipped_sections+=("Goal (CLAUDE.md not present)")
    fi
else
    skipped_sections+=("Goal (placeholder content; not migrated)")
fi

# --- (b) Extract Architecture/Key Decisions table rows to per-file ADRs ---
decisions_section=$(awk '
    /^## (Architecture Decisions|Key Decisions)$/ { flag=1; next }
    flag && /^## / { flag=0 }
    flag { print }
' "$LEGACY_FILE")

if [ -n "$decisions_section" ]; then
    # Find next available ADR number using glob-safe shell (NOT [ -f "...*..." ]).
    next_num=6
    while compgen -G "docs/adr/$(printf '%04d' "$next_num")-*.md" >/dev/null 2>&1; do
        next_num=$((next_num + 1))
    done

    while IFS= read -r line; do
        # Only data rows of a markdown pipe table.
        [[ "$line" =~ ^\|.*\|$ ]] || continue
        # Skip header (first cell == "Decision").
        [[ "$line" =~ ^\|[[:space:]]*Decision[[:space:]]*\| ]] && continue
        # Skip separator (cells are dashes / colons).
        [[ "$line" =~ ^\|[[:space:]]*[:-] ]] && continue
        # Skip empty/whitespace-only rows.
        stripped=$(echo "$line" | sed 's/[[:space:]|]//g')
        [ -z "$stripped" ] && continue

        decision=$(echo "$line" | awk -F'|' '{print $2}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        choice=$(echo "$line"   | awk -F'|' '{print $3}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        why=$(echo "$line"      | awk -F'|' '{print $4}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

        # Skip rows where decision OR choice is empty after trimming.
        [ -z "$decision" ] && continue
        [ -z "$choice" ] && continue

        slug=$(echo "$decision" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//')
        adr_num=$(printf '%04d' "$next_num")
        adr_file="docs/adr/${adr_num}-${slug}.md"

        # Idempotency at the slug level -- if any ADR already has this slug, skip.
        if compgen -G "docs/adr/*-${slug}.md" >/dev/null 2>&1; then
            skipped_sections+=("Decision '$decision' (ADR with slug '${slug}' already exists)")
            continue
        fi

        mkdir -p docs/adr
        cat > "$adr_file" <<EOF
# ${adr_num} -- ${decision}

## Status

Accepted (migrated $(date +%Y-%m-%d))

## Context

Migrated from legacy CONTINUITY.md Architecture Decisions table.

## Considered Options

- **${choice} (chosen)**

## Decision

${choice}

## Consequences

${why:-(empty in legacy CONTINUITY.md - please fill in)}
EOF
        created_adrs+=("$adr_file")
        moved_sections+=("Decision '$decision' -> $adr_file")
        next_num=$((next_num + 1))
    done <<< "$decisions_section"
fi

# --- (c) Extract volatile sections to canonical .forge/local/state.md ---
# state.md presence already verified at the top (sentinel-write block).
# Done: keep the LAST 3 entries (most recent), not the first.
# POSIX awk: use [[:space:]] not \s (BSD awk + portability).
done_section=$(awk '
    /^### Done([[:space:]]|$|[^[:alnum:]])/ { flag=1; next }
    flag && /^### / { flag=0 }
    flag && /^- / { print }
' "$LEGACY_FILE" | tail -3)

if [ -n "$done_section" ]; then
    # Sentinel is already on line 1 of state.md (unconditional write at top).
    # Use tmpfile + getline to preserve embedded newlines / em-dashes / parens
    # (P1-1 fix: `awk -v done_content="..."` chokes on newlines in the variable
    # value with "awk: newline in string" and drops the section).
    content_file=$(mktemp)
    printf '%s\n' "$done_section" > "$content_file"
    tmp=$(mktemp)
    awk -v cfile="$content_file" '
        /^### Done/ {
            print
            print ""
            while ((getline line < cfile) > 0) print line
            close(cfile)
            print ""
            in_done=1
            next
        }
        in_done && /^### / { in_done=0 }
        in_done { next }
        { print }
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    rm -f "$content_file"
    moved_sections+=("Done (last 3 entries) -> .forge/local/state.md")
fi

# Now/Next: same idea, replace placeholder content with migrated content.
# Already using [[:space:]] (POSIX-portable across BSD and GNU awk).
for section in Now Next; do
    section_content=$(awk -v s="$section" '
        $0 ~ "^### "s"([[:space:]]|$|[^[:alnum:]])" { flag=1; next }
        flag && /^### / { flag=0 }
        flag
    ' "$LEGACY_FILE")
    if [ -n "$section_content" ]; then
        # Same tmpfile + getline pattern as Done above (P1-1 fix).
        content_file=$(mktemp)
        printf '%s\n' "$section_content" > "$content_file"
        tmp=$(mktemp)
        awk -v sec="$section" -v cfile="$content_file" '
            $0 ~ "^### "sec"([[:space:]]|$|[^[:alnum:]])" {
                print
                print ""
                while ((getline line < cfile) > 0) print line
                close(cfile)
                in_sec=1
                next
            }
            in_sec && /^### / { in_sec=0; print; next }
            in_sec { next }
            { print }
        ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
        rm -f "$content_file"
        moved_sections+=("$section -> .forge/local/state.md")
    fi
done

# --- (d) Flag dangling @CONTINUITY.md import in CLAUDE.md ---
# Variant B reconcile-prompt: one consolidated "ask Claude" instruction that
# (a) reconciles CLAUDE.md against the latest template AND (b) removes the
# dangling @-import in a single operation. The literal "@CONTINUITY.md" and
# "dangling" tokens are preserved for the existing fixture asserts in
# tests/template/test-migrate.sh and for keyword-grep discoverability.
if [ -f "CLAUDE.md" ] && grep -qE '^@CONTINUITY\.md\b' CLAUDE.md; then
    warnings+=("CLAUDE.md still contains an '@CONTINUITY.md' dangling import.
    Open Claude Code in this project and paste this prompt:

      Reconcile my CLAUDE.md against $SCRIPT_DIR/CLAUDE.template.md.
      Port any new template sections I'm missing, preserving my
      project-specific content.

      Then scan the ENTIRE file and remove every dangling reference to
      CONTINUITY.md left over from before the 5.15 migration. Look for:
        - @CONTINUITY.md import lines (usually at the top)
        - File-tree diagrams that list CONTINUITY.md as a project file
        - Prose pointers like 'see CONTINUITY', 'in CONTINUITY.md', '(CONTINUITY)'
        - Comments or labels that reference CONTINUITY.md as a location

      CONTINUITY.md no longer exists -- its content moved to CLAUDE.md
      (durable), docs/adr/ (decisions), and .forge/local/state.md
      (volatile). Remove these references; the 'preserve project-specific
      content' rule does NOT apply to CONTINUITY pointers -- they are
      stale infrastructure references.

    (Not in Claude Code? See docs/guides/upgrading.md \"Manual fallback\".)")
fi

# Bind the exact surviving v5 source to the final canonical state after all
# sentinel and continuity edits. Full refresh never trusts path coincidence.
write_translation_receipt || exit 1

# --- (e) Print summary (ASCII-safe characters for AC-4 byte-equivalence with PS) ---
echo "Migration complete."
echo ""
echo "Moved:"
if [ ${#moved_sections[@]} -eq 0 ]; then
    echo "  (nothing - content was either placeholder or already migrated)"
else
    for s in "${moved_sections[@]}"; do echo "  + $s"; done
fi
echo ""
if [ ${#skipped_sections[@]} -gt 0 ]; then
    echo "Skipped:"
    for s in "${skipped_sections[@]}"; do echo "  . $s"; done
    echo ""
fi
if [ ${#created_adrs[@]} -gt 0 ]; then
    echo "ADRs created:"
    for a in "${created_adrs[@]}"; do echo "  + $a"; done
    echo ""
fi
if [ ${#warnings[@]} -gt 0 ]; then
    echo "Warnings:"
    for w in "${warnings[@]}"; do echo "  ! $w"; done
    echo ""
fi
echo "Original CONTINUITY.md was preserved in place (byte-for-byte)."
echo "Review the migrated content, then delete CONTINUITY.md when satisfied."
exit 0
