#!/usr/bin/env bash
#
# Verifies that every cloud-init packages: entry in each user-data template is
# present in that OS's P_common expected-coverage list. One direction only: a
# list may hold more than a template installs, but a template entry outside the
# list fails, naming the package and OS.
#
# Usage: check-package-parity.bash [template-dir] [list-dir]
#   template-dir  directory of user-data.<os> templates (default: templates/)
#   list-dir      directory of <os>.txt lists
#                 (default: tests/fixtures/expected-post-apply-packages/)

set -euo pipefail

declare -g SCRIPT_DIR
declare -g TOP
declare -g TEMPLATE_DIR
declare -g LIST_DIR
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -ag FAILED_DETAILS=()
declare -gA LIST_SET=()

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"

TEMPLATE_DIR="${1:-${TOP}/templates}"
LIST_DIR="${2:-${TOP}/tests/fixtures/expected-post-apply-packages}"

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

# Load an OS list into LIST_SET (name -> 1), ignoring blank lines and comments.
function load_list {
    local list_file="$1"
    local line
    LIST_SET=()
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "${line}" ]] && continue
        [[ "${line}" == \#* ]] && continue
        LIST_SET["${line}"]=1
    done < "${list_file}"
}

function check_template {
    local template="$1"
    local os="$2"
    local list_file="${LIST_DIR}/${os}.txt"
    local -a missing=()
    local pkg

    if [[ ! -f "${list_file}" ]]; then
        record_fail "${os}" "no expected-coverage list at ${list_file}"
        return
    fi

    load_list "${list_file}"

    while IFS= read -r pkg; do
        [[ -z "${pkg}" ]] && continue
        if [[ -z "${LIST_SET[${pkg}]:-}" ]]; then
            missing+=("${pkg}")
        fi
    done < <(extract_template_packages "${template}")

    if [[ "${#missing[@]}" -gt 0 ]]; then
        record_fail "${os}" "packages absent from P_common list: ${missing[*]}"
    else
        record_pass "${os}"
    fi
}

function main {
    local template os
    local found=0

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
