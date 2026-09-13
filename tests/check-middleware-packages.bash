#!/usr/bin/env bash
#
# Verifies the integrity of configure/middleware-packages, the single source for
# the middleware server's OS package baseline (the P_java runtime, the P_mariadb
# server, and the source-build ssh client).
#
# These packages install post-boot through the ansible-provision middleware
# roles (planned as its M14), never through cloud-init, so no user-data template
# holds them and no
# template-subset check applies (contrast tests/check-package-parity.bash).
# What can rot is the source itself: a middleware vacuum with no list, a line
# for an OS that is not a middleware vacuum, a duplicated OS key, an empty or
# unparseable line. Package names themselves are not validated - a typo passes
# as a token, the same scope as check-epics-packages. The middleware vacua are
# debian13 and rocky8 - a subset of the full vacuum set. Every OS key is also
# checked against the configure/pcommon-packages family map so a typo'd family
# name fails loudly.
# The ansible-provision roles keep their own installer lists, which this guard
# does not compare against.
#
# Usage: check-middleware-packages.bash [data-file] [pcommon-file]
#   data-file     the middleware package source (default: configure/middleware-packages)
#   pcommon-file  the P_common source carrying the family map (default: configure/pcommon-packages)

set -euo pipefail

declare -g SCRIPT_DIR TOP DATA_FILE PCOMMON_FILE
declare -g TEST_TOTAL=0 TEST_PASSED=0 TEST_FAILED=0
declare -ag FAILED_DETAILS=()
declare -gA MW_COUNT=() PC_FAMILY=()
# The middleware vacua - a deliberate subset of the full vacuum set. Adding one
# here requires a matching line in configure/middleware-packages, and vice versa.
declare -ag MIDDLEWARE_VACUA=(debian13 rocky8)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"

DATA_FILE="${1:-${TOP}/configure/middleware-packages}"
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
# here - they let a typo'd family name fail loudly. Parsing mirrors load_family
# in check-epics-packages.bash.
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
        printf "middleware-packages: no family map found in %s\n" "${PCOMMON_FILE}" >&2
        exit 1
    fi
}

# is_middleware_vacuum <os> - succeeds when the OS is one of the middleware vacua.
function is_middleware_vacuum {
    local os="$1" v
    for v in "${MIDDLEWARE_VACUA[@]}"; do
        [[ "${v}" == "${os}" ]] && return 0
    done
    return 1
}

# Parse the middleware package source: one "os: packages" line per middleware
# vacuum. Every defect is recorded individually so one run surfaces them all.
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
        if ! is_middleware_vacuum "${key}"; then
            record_fail "${key}" "not a middleware vacuum (expected one of: ${MIDDLEWARE_VACUA[*]})"
            continue
        fi
        if [[ -n "${MW_COUNT[${key}]:-}" ]]; then
            record_fail "${key}" "duplicate line; one line per OS"
            continue
        fi
        if [[ -z "${rest}" ]]; then
            record_fail "${key}" "empty package list"
            continue
        fi
        read -r -a toks <<< "${rest}"
        MW_COUNT["${key}"]="${#toks[@]}"
        record_pass "${key} (${#toks[@]} packages)"
    done < "${DATA_FILE}"
}

# Every middleware vacuum must carry a package list.
function check_coverage {
    local os
    for os in "${MIDDLEWARE_VACUA[@]}"; do
        if [[ -z "${MW_COUNT[${os}]:-}" ]]; then
            record_fail "${os}" "no middleware package list in ${DATA_FILE}"
        fi
    done
}

function main {
    if [[ ! -f "${DATA_FILE}" ]]; then
        printf "no middleware package source at %s\n" "${DATA_FILE}" >&2
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
        printf "middleware package failures:\n" >&2
        printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
        exit 1
    fi
}

main
