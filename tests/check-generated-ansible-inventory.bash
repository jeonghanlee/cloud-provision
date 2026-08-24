#!/usr/bin/env bash
#
# Verify generated host inventories against the maintained Ansible group graph.

set -euo pipefail

declare -g SCRIPT_DIR
declare -g TOP
declare -g GENERATOR
declare -g ANSIBLE_DIR
declare -g STATIC_INVENTORY
declare -g WORKSPACE
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -ag FAILED_DETAILS=()

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"
GENERATOR="${TOP}/bin/generate_ansible_inventory.bash"
ANSIBLE_DIR="${ANSIBLE_PROVISION_DIR:-${TOP}/../ansible-provision}"
STATIC_INVENTORY="${ANSIBLE_DIR}/inventory/lab.ini"
WORKSPACE="$(mktemp -d /tmp/generated-ansible-inventory-test.XXXXXX)"

function cleanup {
    local rc=$?

    if [[ "${rc}" != "0" ]]; then
        printf "Retained workspace: %s\n" "${WORKSPACE}" >&2
        return "${rc}"
    fi
    rm -rf -- "${WORKSPACE}"
    return "${rc}"
}

trap cleanup EXIT

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

function require_command {
    local command_name="$1"

    command -v "${command_name}" >/dev/null 2>&1 \
        || { printf "Error: required command not found: %s\n" "${command_name}" >&2; exit 1; }
}

function inventory_command {
    env \
        "HOME=${WORKSPACE}/home" \
        "ANSIBLE_LOCAL_TEMP=${WORKSPACE}/ansible-tmp" \
        ansible-inventory "$@"
}

function direct_groups_for_host {
    local inventory_json="$1"
    local host_name="$2"
    local group_name
    local -a groups=()
    local -a known_groups=(
        debian13
        rocky8
        rocky10
        ubuntu24
        ubuntu26
        iocrunner
        iocrunner_nfs
        epics_dev
        nfs_sim
        rtbase
        ethercat
    )

    for group_name in "${known_groups[@]}"; do
        if jq -e --arg group "${group_name}" --arg host "${host_name}" \
            '(.[$group].hosts // []) | index($host) != null' \
            "${inventory_json}" >/dev/null; then
            groups+=("${group_name}")
        fi
    done
    printf "%s\n" "${groups[*]}"
}

function run_case {
    local label="$1"
    local os_type="$2"
    local species="$3"
    local expected_groups="$4"
    local expected_parents="$5"
    local address="$6"
    local host_name="m51-${label}-node-20260815T000000Z-abcdef123456"
    local runtime_inventory="${WORKSPACE}/${label}.ini"
    local inventory_json="${WORKSPACE}/${label}.json"
    local actual_groups
    local expected_parent
    local parent_graph
    local -a parent_groups=()

    "${GENERATOR}" \
        --vm-name "${host_name}" \
        --address "${address}" \
        --os-type "${os_type}" \
        --species "${species}" > "${runtime_inventory}"

    if inventory_command -i "${STATIC_INVENTORY}" -i "${runtime_inventory}" \
        --list > "${inventory_json}"; then
        record_pass "${label} parses with the maintained group inventory"
    else
        record_fail "${label} parses with the maintained group inventory" \
            "ansible-inventory rejected the merged sources"
        return 0
    fi

    actual_groups="$(direct_groups_for_host "${inventory_json}" "${host_name}")"
    if [[ "${actual_groups}" == "${expected_groups}" ]]; then
        record_pass "${label} has only its required direct groups"
    else
        record_fail "${label} has only its required direct groups" \
            "expected '${expected_groups}', got '${actual_groups}'"
    fi

    if jq -e --arg host "${host_name}" --arg address "${address}" \
        '._meta.hostvars[$host].ansible_host == $address and
         ._meta.hostvars[$host].ansible_user == "vmadmin"' \
        "${inventory_json}" >/dev/null; then
        record_pass "${label} preserves the resolved address and SSH user"
    else
        record_fail "${label} preserves the resolved address and SSH user" \
            "host variables did not match the generated values"
    fi

    read -r -a parent_groups <<< "${expected_parents}"
    for expected_parent in "${parent_groups[@]}"; do
        parent_graph="${WORKSPACE}/${label}-${expected_parent}.graph"
        inventory_command -i "${STATIC_INVENTORY}" -i "${runtime_inventory}" \
            --graph "${expected_parent}" > "${parent_graph}"
        if grep -Fq -- "${host_name}" "${parent_graph}"; then
            record_pass "${label} is reachable through ${expected_parent}"
        else
            record_fail "${label} is reachable through ${expected_parent}" \
                "the merged graph omitted the generated host"
        fi
    done
}

require_command ansible-inventory
require_command jq
[[ -x "${GENERATOR}" ]] || { printf "Error: generator is not executable\n" >&2; exit 1; }
[[ -f "${STATIC_INVENTORY}" ]] \
    || { printf "Error: maintained inventory not found: %s\n" "${STATIC_INVENTORY}" >&2; exit 1; }
mkdir -p "${WORKSPACE}/home" "${WORKSPACE}/ansible-tmp"

if grep -Eq '^[A-Za-z0-9][^[]*ansible_host=|^testbed-|^lab-' "${STATIC_INVENTORY}"; then
    record_fail "maintained inventory contains no fixed host rows" \
        "an ansible_host assignment remains in ${STATIC_INVENTORY}"
else
    record_pass "maintained inventory contains no fixed host rows"
fi

# Every vacuum-species pair the operator definition assigns.
# The bare selector constrains only the vacuum, so the full matrix is
# driven with plain vacuum selectors; suffixed selectors follow below.
declare -a VACUA=(debian13 rocky8 rocky10 ubuntu24 ubuntu26)
declare -a ALL_SPECIES=(bare iocrunner iocrunner-nfs epics-dev nfs-sim rtbase ethercat)
matrix_octet=60
for vacuum in "${VACUA[@]}"; do
    for species in "${ALL_SPECIES[@]}"; do
        if [[ "${species}" == "bare" ]]; then
            expected_groups="${vacuum}"
        else
            expected_groups="${vacuum} ${species//-/_}"
        fi
        run_case "${vacuum}-${species}" "${vacuum}" "${species}" \
            "${expected_groups}" "vacua" "192.168.122.${matrix_octet}"
        matrix_octet=$((matrix_octet + 1))
    done
done

# Suffixed selectors must strip to the vacuum; -iocrunner-nfs must strip
# before -iocrunner.
run_case sel-rocky8-iocrunner rocky8-iocrunner iocrunner "rocky8 iocrunner" "vacua" 192.168.122.150
run_case sel-debian13-iocrunner-nfs debian13-iocrunner-nfs iocrunner-nfs "debian13 iocrunner_nfs" "vacua" 192.168.122.55
run_case sel-rocky10-epics-dev rocky10-epics-dev epics-dev "rocky10 epics_dev" "vacua" 192.168.122.130
run_case sel-debian13-rtbase debian13-rtbase rtbase "debian13 rtbase" "vacua" 192.168.122.80
run_case sel-debian13-ethercat debian13-ethercat ethercat "debian13 ethercat" "vacua" 192.168.122.70

status_inventory="${WORKSPACE}/status-input.ini"
printf "%s\n" \
    "VM Name    : custom-prefix-rocky8-arbitrary-node" \
    "IP Address : 192.168.122.201" \
    | "${GENERATOR}" --status-input --os-type rocky8 --species bare \
        > "${status_inventory}"
if grep -Fq 'custom-prefix-rocky8-arbitrary-node ansible_host=192.168.122.201' \
    "${status_inventory}"; then
    record_pass "status input preserves arbitrary VM identity"
else
    record_fail "status input preserves arbitrary VM identity" \
        "the generated host did not match the status report"
fi

if "${GENERATOR}" --vm-name bad --address 192.168.122.300 \
    --os-type rocky8 --species bare >/dev/null 2>&1; then
    record_fail "invalid IPv4 address is rejected" "the generator accepted .300"
else
    record_pass "invalid IPv4 address is rejected"
fi

if "${GENERATOR}" --vm-name bad --address 192.168.122.80 \
    --os-type rocky7 --species bare >/dev/null 2>&1; then
    record_fail "unsupported OS selector is rejected" \
        "rocky7 was accepted as a vacuum selector"
else
    record_pass "unsupported OS selector is rejected"
fi

if "${GENERATOR}" --vm-name bad --address 192.168.122.80 \
    --os-type rocky8 --species ioc-node >/dev/null 2>&1; then
    record_fail "unsupported species is rejected" \
        "the retired role name was accepted as a species"
else
    record_pass "unsupported species is rejected"
fi

printf "Summary: %s passed / %s total\n" "${TEST_PASSED}" "${TEST_TOTAL}"
if [[ "${TEST_FAILED}" -gt 0 ]]; then
    printf "Failures:\n" >&2
    printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
    exit 1
fi
