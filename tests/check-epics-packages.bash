#!/usr/bin/env bash
#
# Verifies the integrity of configure/epics-packages, the single source for the
# EPICS OS build dependencies both EPICS acquisition paths (P_epics,
# P_epics-build) install.
#
# These packages install post-boot through the ansible-provision epics and
# epics_build roles, never through cloud-init, so no user-data template holds
# them and no template-subset check applies (contrast
# tests/check-package-parity.bash). What can rot is the source itself: a vacuum
# with no build-dependency list, a duplicated or unknown OS key, an empty or
# unparseable line. The vacuum set is taken from the configure/pcommon-packages
# family map, so a vacuum added there without a list here fails loudly. The
# ansible-provision roles keep their own installer lists, which this guard does
# not compare against (D020).
#
# Usage: check-epics-packages.bash [data-file] [pcommon-file]
#   data-file     the EPICS build-dependency source (default: configure/epics-packages)
#   pcommon-file  the P_common source carrying the family map (default: configure/pcommon-packages)

set -euo pipefail

declare -g SCRIPT_DIR TOP DATA_FILE PCOMMON_FILE
declare -g TEST_TOTAL=0 TEST_PASSED=0 TEST_FAILED=0
declare -ag FAILED_DETAILS=()
declare -gA EP_COUNT=() PC_FAMILY=()

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"

DATA_FILE="${1:-${TOP}/configure/epics-packages}"
PCOMMON_FILE="${2:-${TOP}/configure/pcommon-packages}"

function record_pass {
    local name="$1"
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_PASSED=$((TEST_PASSED + 1))
    printf "[ PASS ] %s\n" "${name}"
}

function record_fail {
    local name="$1"
    local detail="$2"
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_FAILED=$((TEST_FAILED + 1))
    FAILED_DETAILS+=("${name}: ${detail}")
    printf "[ FAIL ] %s\n" "${name}" >&2
}

# Load the OS-to-family map from the P_common source; only the OS names matter
# here - they define the vacuum set every epics-packages line is checked
# against. Parsing mirrors load_pcommon in check-package-parity.bash.
function load_family {
    local line rest tok
    local -a toks
    PC_FAMILY=()
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        [[ "${line}" != family:* ]] && continue
        rest="${line#family:}"
        read -r -a toks <<< "${rest}"
        for tok in "${toks[@]}"; do
            PC_FAMILY["${tok%%=*}"]="${tok#*=}"
        done
    done < "${PCOMMON_FILE}"
    if [[ "${#PC_FAMILY[@]}" -eq 0 ]]; then
        printf "epics-packages: no family map found in %s\n" "${PCOMMON_FILE}" >&2
        exit 1
    fi
}

# Parse the build-dependency source: one "os: packages" line per vacuum. Every
# defect is recorded individually so one run surfaces them all.
function check_data_file {
    local line lineno=0 key rest
    local -a toks
    while IFS= read -r line || [[ -n "${line}" ]]; do
        lineno=$((lineno + 1))
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "${line}" ]] && continue
        if [[ "${line}" != *:* ]]; then
            record_fail "line ${lineno}" "unparseable line (expected 'os: packages'): ${line}"
            continue
        fi
        key="${line%%:*}"
        rest="${line#*:}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        if [[ -z "${PC_FAMILY[${key}]:-}" ]]; then
            record_fail "${key}" "unknown OS; not in the ${PCOMMON_FILE##*/} family map"
            continue
        fi
        if [[ -n "${EP_COUNT[${key}]:-}" ]]; then
            record_fail "${key}" "duplicate line; one line per OS"
            continue
        fi
        if [[ -z "${rest}" ]]; then
            record_fail "${key}" "empty package list"
            continue
        fi
        read -r -a toks <<< "${rest}"
        EP_COUNT["${key}"]="${#toks[@]}"
        record_pass "${key} (${#toks[@]} packages)"
    done < "${DATA_FILE}"
}

# Every vacuum in the family map must carry a build-dependency list.
function check_coverage {
    local os
    for os in "${!PC_FAMILY[@]}"; do
        if [[ -z "${EP_COUNT[${os}]:-}" ]]; then
            record_fail "${os}" "no build-dependency list in ${DATA_FILE}"
        fi
    done
}

function main {
    if [[ ! -f "${DATA_FILE}" ]]; then
        printf "no EPICS build-dependency source at %s\n" "${DATA_FILE}" >&2
        exit 1
    fi
    if [[ ! -f "${PCOMMON_FILE}" ]]; then
        printf "no P_common source at %s\n" "${PCOMMON_FILE}" >&2
        exit 1
    fi

    load_family
    check_data_file
    check_coverage

    printf "\n%d checked, %d passed, %d failed\n" \
        "${TEST_TOTAL}" "${TEST_PASSED}" "${TEST_FAILED}"

    if [[ "${TEST_FAILED}" -gt 0 ]]; then
        printf "EPICS build-dependency failures:\n" >&2
        printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
        exit 1
    fi
}

main
