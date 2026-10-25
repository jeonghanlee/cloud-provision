#!/usr/bin/env bash
#
# Verifies that the IOC image audit mirrors the shipped proxy contract.
#
# The audit keeps its own value-free copy of the proxy artifact paths, shared
# key patterns and markers, and pins the contract digest so that a contract
# change stops it before any image is read. This check compares that copy with
# the contract itself: the digest, the paths checked per audited family, the
# check kind per ownership form, the shared key patterns and the markers. It
# reads the audit as text and sources the contract for its inventory; it runs
# no guestfish, root code or image.
#
# Usage: check-audit-inventory.bash [audit-file] [contract-file]
#   audit-file     the audit under check (default: bin/audit_iocrunner_images.bash)
#   contract-file  the proxy contract (default: bin/proxy_contract.bash)

set -euo pipefail

declare -g SCRIPT_DIR
declare -g TOP
declare -g AUDIT
declare -g CONTRACT
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -ag FAILED_DETAILS=()
declare -Ag AUDIT_VALUES=()

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"
AUDIT="${1:-${TOP}/bin/audit_iocrunner_images.bash}"
CONTRACT="${2:-${TOP}/bin/proxy_contract.bash}"

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
    printf "  %s\n" "${detail}" >&2
}

function expect_equal {
    local name="$1"
    local want="$2"
    local got="$3"

    if [[ "${got}" == "${want}" ]]; then
        record_pass "${name}"
    else
        record_fail "${name}" "expected '${want}', got '${got}'"
    fi
}

# Reads every readonly scalar of the audit into AUDIT_VALUES, expanding the
# references to earlier values that the runtime paths use.
function load_audit_values {
    local line name value reference

    while IFS= read -r line; do
        if [[ "${line}" =~ ^readonly\ ([A-Z][A-Z0-9_]*)=\"(.*)\"$ ]] ||
           [[ "${line}" =~ ^readonly\ ([A-Z][A-Z0-9_]*)=\'(.*)\'$ ]]; then
            name="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            for reference in "${!AUDIT_VALUES[@]}"; do
                value="${value//\$\{${reference}\}/${AUDIT_VALUES[${reference}]}}"
            done
            AUDIT_VALUES["${name}"]="${value}"
        fi
    done < "${AUDIT}"
}

# Prints "kind path pattern" for each check the audit runs on one family:
# the common checks of verify_guest_proxy_clean plus that family's case branch.
function audited_checks {
    local family="$1"
    local kind variable pattern_variable

    awk -v family="${family}" '
        /^verify_guest_proxy_clean\(\) \{/ { inside = 1; next }
        inside && /^\}/ { exit }
        !inside { next }
        /^[[:space:]]+case / { in_case = 1; next }
        in_case && /^[[:space:]]+esac/ { in_case = 0; branch = ""; next }
        in_case && /^[[:space:]]+[a-z*]+\)$/ {
            branch = $1
            sub(/\)$/, "", branch)
            next
        }
        /^[[:space:]]+verify_(absent|shared) / {
            if (in_case && branch != family) next
            variable = $3
            pattern_variable = (NF >= 4) ? $4 : "-"
            gsub(/["${}]/, "", variable)
            gsub(/["${}]/, "", pattern_variable)
            print $1, variable, pattern_variable
        }
    ' "${AUDIT}" | while read -r kind variable pattern_variable; do
        printf "%s\t%s\t%s\n" "${kind}" "${AUDIT_VALUES[${variable}]:-?${variable}}" \
            "${AUDIT_VALUES[${pattern_variable}]:--}"
    done
}

function contract_eval {
    bash -c 'source "$1"; shift; "$@"' contract "${CONTRACT}" "$@"
}

function contract_value {
    # shellcheck disable=SC2016
    bash -c 'source "$1"; printf "%s\n" "${!2}"' contract "${CONTRACT}" "$1"
}

function check_family {
    local family="$1"
    local checks inventory runtime expected_paths audited_paths
    local identity path form audit_kind audit_pattern want_kind contract_pattern

    checks="$(audited_checks "${family}")"
    inventory="$(contract_eval proxy_contract_print_inventory "${family}")"
    runtime="$(printf "%s\n" \
        "$(contract_value PROXY_CONTRACT_SCRIPT)" \
        "$(contract_value PROXY_CONTRACT_INPUT)" \
        "$(contract_value PROXY_CONTRACT_LOCK)")"

    expected_paths="$( { cut -f3 <<< "${inventory}"; printf "%s\n" "${runtime}"; } | LC_ALL=C sort)"
    audited_paths="$(cut -f2 <<< "${checks}" | LC_ALL=C sort)"
    expect_equal "${family} audit checks exactly the contract and runtime paths" \
        "$(tr '\n' ' ' <<< "${expected_paths}")" "$(tr '\n' ' ' <<< "${audited_paths}")"

    while IFS=$'\t' read -r _ identity path _ _ _ form _; do
        audit_kind="$(awk -F '\t' -v path="${path}" '$2 == path { print $1; exit }' <<< "${checks}")"
        case "${form}" in
            dedicated) want_kind=verify_absent ;;
            shared) want_kind=verify_shared ;;
            *) want_kind="unknown-form-${form}" ;;
        esac
        expect_equal "${family} ${identity} uses the ${form} check" "${want_kind}" "${audit_kind}"
        if [[ "${form}" == shared ]]; then
            audit_pattern="$(awk -F '\t' -v path="${path}" '$2 == path { print $3; exit }' <<< "${checks}")"
            contract_pattern="$(contract_eval proxy_contract_key_pattern "${identity}")"
            expect_equal "${family} ${identity} key pattern matches the contract" \
                "${contract_pattern}" "${audit_pattern}"
        fi
    done <<< "${inventory}"

    while IFS= read -r path; do
        audit_kind="$(awk -F '\t' -v path="${path}" '$2 == path { print $1; exit }' <<< "${checks}")"
        expect_equal "${family} runtime ${path##*/} uses the dedicated check" \
            verify_absent "${audit_kind}"
    done <<< "${runtime}"
}

[[ -f "${AUDIT}" ]] || { printf "Error: audit not found: %s\n" "${AUDIT}" >&2; exit 1; }
[[ -f "${CONTRACT}" ]] || { printf "Error: contract not found: %s\n" "${CONTRACT}" >&2; exit 1; }

load_audit_values

declare -g CONTRACT_DIGEST
CONTRACT_DIGEST="$(sha256sum "${CONTRACT}")"
CONTRACT_DIGEST="${CONTRACT_DIGEST%% *}"
expect_equal "audit pins the shipped contract digest" \
    "${CONTRACT_DIGEST}" "${AUDIT_VALUES[PROXY_CONTRACT_SHA256]:-}"

expect_equal "audit begin marker matches the contract" \
    "$(contract_value PROXY_CONTRACT_BEGIN)" "${AUDIT_VALUES[PROXY_CONTRACT_BEGIN]:-}"
expect_equal "audit end marker matches the contract" \
    "$(contract_value PROXY_CONTRACT_END)" "${AUDIT_VALUES[PROXY_CONTRACT_END]:-}"

for family in debian rocky; do
    check_family "${family}"
done

printf "Summary: %s passed / %s total\n" "${TEST_PASSED}" "${TEST_TOTAL}"
if [[ "${TEST_FAILED}" -gt 0 ]]; then
    printf "Failures:\n" >&2
    printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
    exit 1
fi
