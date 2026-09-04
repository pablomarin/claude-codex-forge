#!/usr/bin/env bash
# tests/template/test-platform-parity.sh — centralized static host/platform parity.
#
# Run from repo root: bash tests/template/test-platform-parity.sh

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=lib.sh
source "$REPO_ROOT/tests/template/lib.sh"

init_counters

HOSTS="$REPO_ROOT/manifests/host-capabilities.tsv"
WORKFLOWS="$REPO_ROOT/manifests/workflow-capabilities.tsv"
MANAGED="$REPO_ROOT/manifests/managed-v6.tsv"

start_test "Bash and PowerShell hook sources remain paired"
PAIR_DIR=$(scratch_dir platform-parity)
find "$REPO_ROOT/hooks" -type f -name '*.sh' -print \
    | sed -E 's#^.*/hooks/##; s/\.sh$//' | LC_ALL=C sort > "$PAIR_DIR/bash"
find "$REPO_ROOT/hooks" -type f -name '*.ps1' -print \
    | sed -E 's#^.*/hooks/##; s/\.ps1$//' | LC_ALL=C sort > "$PAIR_DIR/powershell"
if diff -u "$PAIR_DIR/bash" "$PAIR_DIR/powershell" >/dev/null 2>&1; then
    pass "every Bash hook/helper has a PowerShell twin"
else
    fail "hook source parity mismatch"
    diff -u "$PAIR_DIR/bash" "$PAIR_DIR/powershell" >&2 || true
fi

start_test "managed manifest uses the same static Unix and Windows inventory"
assert_file_exists "$MANAGED" "managed-v6.tsv exists"
if [ -f "$MANAGED" ]; then
    awk -F '\t' '!/^#/ && NF && ($4 == "unix" || $4 == "all") {print $6 "\t" $3 "\t" $1 "\t" $5 "\t" $7 "\t" $8 "\t" $9}' "$MANAGED" | sort > "$PAIR_DIR/unix-managed"
    awk -F '\t' '!/^#/ && NF && ($4 == "windows" || $4 == "all") {print $6 "\t" $3 "\t" $1 "\t" $5 "\t" $7 "\t" $8 "\t" $9}' "$MANAGED" | sort > "$PAIR_DIR/windows-managed"
    if diff -u "$PAIR_DIR/unix-managed" "$PAIR_DIR/windows-managed" >/dev/null 2>&1; then
        pass "Unix and Windows materialize the same (scope, destination) contracts"
    else
        fail "Unix/Windows managed inventory differs"
    fi
    assert_contains "$MANAGED" $'merge\tsettings/settings.template.json\t.claude/settings.json\tunix\tclaude\tproject' "Unix Claude settings select settings.template.json"
    assert_contains "$MANAGED" $'merge\tsettings/settings-windows.template.json\t.claude/settings.json\twindows\tclaude\tproject' "Windows Claude settings select settings-windows.template.json"
fi

start_test "host capability matrix is complete and symmetric"
assert_file_exists "$HOSTS" "host-capabilities.tsv exists"
if [ -f "$HOSTS" ]; then
    BAD_FIELDS=$(awk -F '\t' '!/^#/ && NF != 13 {print NR ":" NF}' "$HOSTS")
    [ -z "$BAD_FIELDS" ] && pass "host capability rows have 13 explicit fields" || fail "host capability field mismatch: $BAD_FIELDS"

    awk -F '\t' '!/^#/ && NF && $2 == "claude" {print $1}' "$HOSTS" | sort > "$PAIR_DIR/claude-capabilities"
    awk -F '\t' '!/^#/ && NF && $2 == "codex" {print $1}' "$HOSTS" | sort > "$PAIR_DIR/codex-capabilities"
    if diff -u "$PAIR_DIR/claude-capabilities" "$PAIR_DIR/codex-capabilities" >/dev/null 2>&1; then
        pass "Claude and Codex expose the same named behavior matrix"
    else
        fail "Claude/Codex capability names differ"
        diff -u "$PAIR_DIR/claude-capabilities" "$PAIR_DIR/codex-capabilities" >&2 || true
    fi

    REQUIRED='instruction-discovery rule-discovery commands skills session-start stop subagent-stop pre-compact config-change pre-tool-use permission-request post-tool-use subagents permissions fresh-runs investigation trust native-goals model-certifying model-council-advisor model-council-chair'
    for capability in $REQUIRED; do
        for host in claude codex; do
            if awk -F '\t' -v capability="$capability" -v host="$host" '$1 == capability && $2 == host {found=1} END {exit found ? 0 : 1}' "$HOSTS"; then
                pass "$host declares $capability"
            else
                fail "$host missing $capability"
            fi
        done
    done

    assert_contains "$HOSTS" $'subagent-stop\tcodex\tall\tcommand-hook' "Codex subagent-stop uses a command-hook equivalent"
    assert_contains "$HOSTS" $'config-change\tcodex\tall\tlifecycle-check' "Codex config-change uses lifecycle fingerprint checking"
    assert_contains "$HOSTS" $'model-certifying\tcodex\tall\tcli\tcertifying\topenai\tgpt-5.6-sol\txhigh' "Codex certifying profile is fixed to gpt-5.6-sol/xhigh"
    assert_contains "$HOSTS" $'model-certifying\tclaude\tall\tcli\tcertifying\tanthropic\topus\tmax' "Claude certifying profile is fixed to opus/max"
    assert_contains "$HOSTS" $'model-certifying\tclaude\tall\tcli\tcertifying\tanthropic\topus\tmax\t--model=opus;--effort=max;--settings={"fastMode":true}' "Claude certifying profile declares fast mode"
    assert_contains "$HOSTS" $'model-certifying\tcodex\tall\tcli\tcertifying\topenai\tgpt-5.6-sol\txhigh\t-m=gpt-5.6-sol;-c=model_reasoning_effort=xhigh;-c=service_tier=fast' "Codex certifying profile declares the fast service tier"
    assert_contains "$HOSTS" "UNOBSERVABLE" "non-observable identity fields are declared honestly"
    assert_not_contains "$HOSTS" "override" "v1 capability map exposes no model override"
fi

start_test "external workflow behaviors have one owned v6 replacement"
assert_file_exists "$WORKFLOWS" "workflow-capabilities.tsv exists"
if [ -f "$WORKFLOWS" ]; then
    BAD_FIELDS=$(awk -F '\t' '!/^#/ && NF != 7 {print NR ":" NF}' "$WORKFLOWS")
    [ -z "$BAD_FIELDS" ] && pass "workflow capability rows have seven explicit fields" || fail "workflow capability field mismatch: $BAD_FIELDS"
    DUPLICATES=$(awk -F '\t' '!/^#/ && NF {print $1 "\t" $2}' "$WORKFLOWS" | sort | uniq -d)
    [ -z "$DUPLICATES" ] && pass "external behavior replacements are unique" || fail "duplicate external behavior replacements: $DUPLICATES"
    for behavior in brainstorming writing-plans subagent-driven-development executing-plans systematic-debugging code-simplifier code-reviewer review-pr frontend-design; do
        if awk -F '\t' -v behavior="$behavior" '$2 == behavior && $4 == "forge" && $5 ~ /^\.forge\// {found=1} END {exit found ? 0 : 1}' "$WORKFLOWS"; then
            pass "$behavior has a Forge-owned canonical replacement"
        else
            fail "$behavior lacks a Forge-owned canonical replacement"
        fi
    done
fi

report "test-platform-parity.sh"
