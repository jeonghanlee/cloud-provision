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
STATIC_INVENTORY="${ANSIBLE_DIR}/inventory/testbed.ini"
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
        rocky8
        debian13
        nfs_sim_nodes
        ethercat_nodes
        ethercat_build
        epics_env_core
        epics_env_matrix
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
    local workload_role="$3"
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
        --role "${workload_role}" > "${runtime_inventory}"

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

if grep -Eq '^[A-Za-z0-9][^[]*ansible_host=|^testbed-' "${STATIC_INVENTORY}"; then
    record_fail "maintained inventory contains no fixed host rows" \
        "an ansible_host assignment remains in ${STATIC_INVENTORY}"
else
    record_pass "maintained inventory contains no fixed host rows"
fi

run_case rocky8-runtime rocky8 ioc-node "rocky8" "ioc_nodes all_nodes" 192.168.122.100
run_case debian13-runtime debian13 ioc-node "debian13" "ioc_nodes all_nodes" 192.168.122.10
run_case rocky8-iocrunner rocky8-iocrunner ioc-node "rocky8" "ioc_nodes all_nodes" 192.168.122.150
run_case debian13-iocrunner debian13-iocrunner ioc-node "debian13" "ioc_nodes all_nodes" 192.168.122.50
run_case ethercat-runtime debian13-ethercat ethercat-node "ethercat_nodes" "" 192.168.122.70
run_case ethercat-build debian13-rtbase ethercat-build "ethercat_build" "" 192.168.122.198
run_case epics-rocky8 epics-env-rocky8 epics-env-build "epics_env_core" epics_env_build 192.168.122.120
run_case epics-debian13 epics-env-debian13 epics-env-build "epics_env_core" epics_env_build 192.168.122.20
run_case epics-rocky10 epics-env-rocky10 epics-env-build "epics_env_matrix" epics_env_build 192.168.122.130
run_case epics-ubuntu24 epics-env-ubuntu24 epics-env-build "epics_env_matrix" epics_env_build 192.168.122.40
run_case epics-ubuntu26 epics-env-ubuntu26 epics-env-build "epics_env_matrix" epics_env_build 192.168.122.30
run_case rocky8-nfs rocky8 nfs-sim-node "rocky8 nfs_sim_nodes" "ioc_nodes all_nodes" 192.168.122.177
run_case rocky8-bake rocky8 ioc-runner-build "rocky8 nfs_sim_nodes" "ioc_nodes all_nodes" 192.168.122.178
run_case debian13-bake debian13 ioc-runner-build "debian13 nfs_sim_nodes" "ioc_nodes all_nodes" 192.168.122.179

status_inventory="${WORKSPACE}/status-input.ini"
printf "%s\n" \
    "VM Name    : custom-prefix-rocky8-arbitrary-node" \
    "IP Address : 192.168.122.201" \
    | "${GENERATOR}" --status-input --os-type rocky8 --role ioc-node \
        > "${status_inventory}"
if grep -Fq 'custom-prefix-rocky8-arbitrary-node ansible_host=192.168.122.201' \
    "${status_inventory}"; then
    record_pass "status input preserves arbitrary VM identity"
else
    record_fail "status input preserves arbitrary VM identity" \
        "the generated host did not match the status report"
fi

if "${GENERATOR}" --vm-name bad --address 192.168.122.300 \
    --os-type rocky8 --role ioc-node >/dev/null 2>&1; then
    record_fail "invalid IPv4 address is rejected" "the generator accepted .300"
else
    record_pass "invalid IPv4 address is rejected"
fi

if "${GENERATOR}" --vm-name bad --address 192.168.122.80 \
    --os-type rocky8 --role ethercat-build >/dev/null 2>&1; then
    record_fail "invalid role and selector pair is rejected" \
        "rocky8 was accepted as an EtherCAT build selector"
else
    record_pass "invalid role and selector pair is rejected"
fi

printf "Summary: %s passed / %s total\n" "${TEST_PASSED}" "${TEST_TOTAL}"
if [[ "${TEST_FAILED}" -gt 0 ]]; then
    printf "Failures:\n" >&2
    printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
    exit 1
fi
