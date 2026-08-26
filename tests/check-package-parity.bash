#!/usr/bin/env bash
#
# Verifies that every cloud-init packages: entry in each user-data template is
# present in that OS's P_common package set. The expected set is derived from the
# single source configure/pcommon-packages, not from a hand-copied per-OS list.
# One direction only: the P_common set may hold more than a template installs,
# but a template entry outside it fails, naming the package and OS.
#
# Usage: check-package-parity.bash [template-dir] [data-file]
#   template-dir  directory of user-data.<os> templates (default: templates/)
#   data-file     the P_common source (default: configure/pcommon-packages)

set -euo pipefail

declare -g SCRIPT_DIR TOP TEMPLATE_DIR DATA_FILE
declare -g TEST_TOTAL=0 TEST_PASSED=0 TEST_FAILED=0
declare -ag FAILED_DETAILS=()
declare -gA LIST_SET=()
declare -ga PC_MUST_HAVE=() PC_CORE=() PC_DEBIAN_ONLY=()
declare -gA PC_SPELL_DEBIAN=() PC_SPELL_ROCKY=() PC_FAMILY=()

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"

TEMPLATE_DIR="${1:-${TOP}/templates}"
DATA_FILE="${2:-${TOP}/configure/pcommon-packages}"

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

# Extract the cloud-init packages: block entries from a template. The block
# boundary mirrors the proxy-merge stripper in bin/create_vm.bash: the packages:
# key starts the block, and the first line that does not start with whitespace
# (a blank line included) ends it. Reading the block the same way the stripper
# drops it keeps the guard verifying exactly the set that leaves the image, and
# excludes the users: and runcmd: list items. Keep the two boundary rules in
# sync.
function extract_template_packages {
    local template="$1"
    awk '
        /^packages:[[:space:]]*$/ { in_block = 1; next }
        in_block && !/^[[:space:]]/ { in_block = 0 }
        in_block && /^[[:space:]]+-[[:space:]]/ {
            line = $0
            sub(/^[[:space:]]+-[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (line != "") print line
        }
    ' "${template}"
}

# Parse the P_common source into the groups, per-family spellings, and OS-to-
# family map. Blank lines and # comments are ignored; each data line is a single
# "key: values" entry.
function load_pcommon {
    local data_file="$1"
    local line key rest tok name val
    local -a toks
    PC_MUST_HAVE=(); PC_CORE=(); PC_DEBIAN_ONLY=()
    PC_SPELL_DEBIAN=(); PC_SPELL_ROCKY=(); PC_FAMILY=()
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "${line}" ]] && continue
        [[ "${line}" != *:* ]] && continue
        key="${line%%:*}"
        rest="${line#*:}"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        case "${key}" in
            must_have)   read -r -a PC_MUST_HAVE   <<< "${rest}" ;;
            core)        read -r -a PC_CORE        <<< "${rest}" ;;
            debian_only) read -r -a PC_DEBIAN_ONLY <<< "${rest}" ;;
            spelling)
                read -r -a toks <<< "${rest}"
                for tok in "${toks[@]}"; do
                    name="${tok%%=*}"
                    val="${tok#*=}"
                    PC_SPELL_DEBIAN["${name}"]="${val%%:*}"
                    PC_SPELL_ROCKY["${name}"]="${val#*:}"
                done ;;
            family)
                read -r -a toks <<< "${rest}"
                for tok in "${toks[@]}"; do
                    PC_FAMILY["${tok%%=*}"]="${tok#*=}"
                done ;;
        esac
    done < "${data_file}"
}

# Derive the P_common set for one OS into LIST_SET, applying the OS's family
# spelling. Returns non-zero when the OS has no family mapping.
function derive_os_set {
    local os="$1"
    local fam name spelled
    local -a names
    LIST_SET=()
    fam="${PC_FAMILY[${os}]:-}"
    [[ -z "${fam}" ]] && return 1
    names=("${PC_MUST_HAVE[@]}" "${PC_CORE[@]}")
    [[ "${fam}" == debian ]] && names+=("${PC_DEBIAN_ONLY[@]}")
    for name in "${names[@]}"; do
        if [[ "${fam}" == debian && -n "${PC_SPELL_DEBIAN[${name}]:-}" ]]; then
            spelled="${PC_SPELL_DEBIAN[${name}]}"
        elif [[ "${fam}" == rocky && -n "${PC_SPELL_ROCKY[${name}]:-}" ]]; then
            spelled="${PC_SPELL_ROCKY[${name}]}"
        else
            spelled="${name}"
        fi
        LIST_SET["${spelled}"]=1
    done
    return 0
}

function check_template {
    local template="$1"
    local os="$2"
    local -a missing=()
    local pkg

    if ! derive_os_set "${os}"; then
        record_fail "${os}" "no package family mapped for this OS in ${DATA_FILE}"
        return
    fi

    while IFS= read -r pkg; do
        [[ -z "${pkg}" ]] && continue
        if [[ -z "${LIST_SET[${pkg}]:-}" ]]; then
            missing+=("${pkg}")
        fi
    done < <(extract_template_packages "${template}")

    if [[ "${#missing[@]}" -gt 0 ]]; then
        record_fail "${os}" "packages absent from the P_common set: ${missing[*]}"
    else
        record_pass "${os}"
    fi
}

function main {
    local template os
    local found=0

    if [[ ! -f "${DATA_FILE}" ]]; then
        printf "no P_common source at %s\n" "${DATA_FILE}" >&2
        exit 1
    fi
    load_pcommon "${DATA_FILE}"

    for template in "${TEMPLATE_DIR}"/user-data.*; do
        [[ -e "${template}" ]] || continue
        found=1
        os="${template##*/user-data.}"
        check_template "${template}" "${os}"
    done

    if [[ "${found}" -eq 0 ]]; then
        printf "no user-data.* templates found in %s\n" "${TEMPLATE_DIR}" >&2
        exit 1
    fi

    printf "\n%d checked, %d passed, %d failed\n" \
        "${TEST_TOTAL}" "${TEST_PASSED}" "${TEST_FAILED}"

    if [[ "${TEST_FAILED}" -gt 0 ]]; then
        printf "Package-parity failures:\n" >&2
        printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
        exit 1
    fi
}

main
