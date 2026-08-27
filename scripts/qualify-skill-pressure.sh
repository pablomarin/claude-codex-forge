#!/usr/bin/env bash
# Qualify a surviving Forge-owned portable skill outside deterministic CI.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  qualify-skill-pressure.sh --validate-fixture <candidate-decisions.tsv>
  FORGE_SKILL_PRESSURE_COMMAND=/absolute/qualified-runner \
    qualify-skill-pressure.sh --skill <name> --phase <red|green> \
      --scenario <path> --attestation <path> [--red-attestation <path>]

The command is intentionally supplied by the authenticated operator environment.
This script stores only the command's redacted attestation and never runs in CI.
EOF
}

validate_fixture() {
    local fixture="$1" expected candidate
    [ -f "$fixture" ] || { printf 'missing fixture: %s\n' "$fixture" >&2; return 1; }
    [ "$(head -n 1 "$fixture")" = $'candidate\tdecision\tlive_callsite\tcanonical_owner\trationale' ] || { printf 'invalid fixture schema\n' >&2; return 1; }
    expected='brainstorming writing-plans systematic-debugging subagent-driven-development executing-plans requesting-review receiving-review simplifying-work verifying-work'
    for candidate in $expected; do
        [ "$(awk -F '\t' -v candidate="$candidate" '$1 == candidate { count++ } END { print count + 0 }' "$fixture")" = 1 ] || { printf 'candidate decision missing or duplicated: %s\n' "$candidate" >&2; return 1; }
        awk -F '\t' -v candidate="$candidate" '$1 == candidate && $2 == "REJECTED_DUPLICATE" && $3 != "" && $4 != "" && $5 != "" { found=1 } END { exit found ? 0 : 1 }' "$fixture" || { printf 'candidate rationale incomplete: %s\n' "$candidate" >&2; return 1; }
    done
}

receipt_value() {
    local receipt="$1" key="$2" value
    value=$(awk -v key="$key" 'index($0, key "=") == 1 { count++; value=substr($0, length(key) + 2) } END { if (count == 1 && value != "") print value; else exit 1 }' "$receipt") || return 1
    printf '%s\n' "$value"
}

sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }

validate_receipt() {
    local receipt="$1" expected_phase="$2" expected_outcome="$3" expected_skill="$4" expected_scenario="$5"
    [ "$(receipt_value "$receipt" skill)" = "$expected_skill" ] && [ "$(receipt_value "$receipt" phase)" = "$expected_phase" ] && [ "$(receipt_value "$receipt" scenario_sha256)" = "$expected_scenario" ] && [ "$(receipt_value "$receipt" outcome)" = "$expected_outcome" ] || return 1
    [ "$expected_phase" != red ] || [ -n "$(receipt_value "$receipt" rationalization)" ]
}

fixture="" skill="" phase="" scenario="" attestation="" red_attestation=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --validate-fixture) fixture="${2:-}"; shift 2 ;;
        --skill) skill="${2:-}"; shift 2 ;;
        --phase) phase="${2:-}"; shift 2 ;;
        --scenario) scenario="${2:-}"; shift 2 ;;
        --attestation) attestation="${2:-}"; shift 2 ;;
        --red-attestation) red_attestation="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -n "$fixture" ]; then
    [ -z "$skill$phase$scenario$attestation$red_attestation" ] || { printf '--validate-fixture cannot be combined with qualification options\n' >&2; exit 2; }
    validate_fixture "$fixture"
    exit 0
fi

[ -n "$skill" ] && [ -n "$phase" ] && [ -n "$scenario" ] && [ -n "$attestation" ] || { usage >&2; exit 2; }
[ "$phase" = red ] || [ "$phase" = green ] || { printf 'phase must be red or green\n' >&2; exit 2; }
[ -f "$scenario" ] || { printf 'scenario does not exist: %s\n' "$scenario" >&2; exit 2; }
[ -n "${FORGE_SKILL_PRESSURE_COMMAND:-}" ] || { printf 'FORGE_SKILL_PRESSURE_COMMAND is required for authenticated qualification\n' >&2; exit 2; }
[ -x "$FORGE_SKILL_PRESSURE_COMMAND" ] || { printf 'qualified runner is not executable: %s\n' "$FORGE_SKILL_PRESSURE_COMMAND" >&2; exit 2; }
scenario_sha256=$(sha256_file "$scenario")
if [ "$phase" = green ]; then
    [ -n "$red_attestation" ] && [ -f "$red_attestation" ] || { printf 'green qualification requires a prior red attestation\n' >&2; exit 2; }
    validate_receipt "$red_attestation" red NONCOMPLIANT "$skill" "$scenario_sha256" || { printf 'prior RED attestation must be a bound NONCOMPLIANT receipt with a rationalization\n' >&2; exit 2; }
    red_sha256=$(sha256_file "$red_attestation")
fi

mkdir -p "$(dirname "$attestation")"
"$FORGE_SKILL_PRESSURE_COMMAND" --skill "$skill" --phase "$phase" --scenario "$scenario" --red-attestation "$red_attestation" > "$attestation"
if [ "$phase" = red ]; then
    validate_receipt "$attestation" red NONCOMPLIANT "$skill" "$scenario_sha256" || { printf 'invalid RED qualification attestation\n' >&2; exit 1; }
else
    validate_receipt "$attestation" green COMPLIANT "$skill" "$scenario_sha256" && [ "$(receipt_value "$attestation" prior_red_sha256)" = "$red_sha256" ] || { printf 'invalid GREEN qualification attestation\n' >&2; exit 1; }
fi
