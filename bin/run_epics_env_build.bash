#!/usr/bin/env bash
#
# Run the EPICS-env build playbook against generated VM host inventories.

set -euo pipefail

declare -g SC_RPATH
declare -g SC_TOP

SC_RPATH="$(realpath "$0")"
SC_TOP="${SC_RPATH%/*}/.."
SC_TOP="$(realpath "${SC_TOP}")"

declare -g ANSIBLE_DIR="${ANSIBLE_PROVISION_DIR:-${SC_TOP}/../ansible-provision}"
declare -g IMAGE_DIR="${IMAGE_DIR:-${HOME}/libvirt/images}"
declare -g VM_PREFIX="${VM_PREFIX:-testbed}"
declare -g NODE_ID="server"
declare -g INVENTORY="${EPICS_ENV_INVENTORY:-inventory/lab.ini}"
declare -g PLAYBOOK="${EPICS_ENV_PLAYBOOK:-playbooks/species/epics_dev.yml}"
declare -g CREATE_VM="${SC_TOP}/bin/create_vm.bash"
declare -g INVENTORY_GENERATOR="${SC_TOP}/bin/generate_ansible_inventory.bash"
declare -g ANSIBLE_PLAYBOOK_BIN=""
declare -g INVENTORY_PATH=""
declare -g ANSIBLE_LIMIT=""
declare -ag OS_TYPES=()
declare -ag RUNTIME_INVENTORIES=()

function die {
    printf "Error: %s\n" "$*" >&2
    exit 1
}

function print_usage {
    printf "Usage: %s [options]\n" "$(basename "$0")"
    printf "\n"
    printf "Run the EPICS-env build playbook against existing cloud-provision VMs.\n"
    printf "\n"
    printf "Options:\n"
    printf "  -o <os_type>    Add an EPICS-env OS selector; may be repeated\n"
    printf "                  (default: epics-env-rocky8 and epics-env-debian13)\n"
    printf "  -a <dir>        ansible-provision directory\n"
    printf "  -d <dir>        VM image directory\n"
    printf "  -p <prefix>     VM name prefix (default: testbed)\n"
    printf "  -n <node_id>    VM node identifier (default: server)\n"
    printf "  -i <inventory>  Maintained group inventory relative to ansible-provision\n"
    printf "  -P <playbook>   Playbook relative to ansible-provision\n"
    printf "  -h              Show this help\n"
}

while getopts ":o:a:d:p:n:i:P:h" opt; do
    case "${opt}" in
        o) OS_TYPES+=("${OPTARG}") ;;
        a) ANSIBLE_DIR="${OPTARG}" ;;
        d) IMAGE_DIR="${OPTARG}" ;;
        p) VM_PREFIX="${OPTARG}" ;;
        n) NODE_ID="${OPTARG}" ;;
        i) INVENTORY="${OPTARG}" ;;
        P) PLAYBOOK="${OPTARG}" ;;
        h) print_usage; exit 0 ;;
        :) die "-${OPTARG} requires an argument" ;;
        ?) die "unknown option: -${OPTARG}" ;;
    esac
done

if [[ "${#OS_TYPES[@]}" -eq 0 ]]; then
    OS_TYPES=(epics-env-rocky8 epics-env-debian13)
fi

function cleanup_runtime_inventories {
    local rc=$?
    local inventory_path

    for inventory_path in "${RUNTIME_INVENTORIES[@]}"; do
        rm -f -- "${inventory_path}"
    done
    return "${rc}"
}

trap cleanup_runtime_inventories EXIT
trap 'exit 1' HUP INT TERM

[[ -x "${CREATE_VM}" ]] || die "create_vm.bash is not executable: ${CREATE_VM}"
[[ -x "${INVENTORY_GENERATOR}" ]] \
    || die "inventory generator is not executable: ${INVENTORY_GENERATOR}"
[[ -d "${ANSIBLE_DIR}" ]] || die "ansible-provision directory not found: ${ANSIBLE_DIR}"

ANSIBLE_DIR="$(realpath "${ANSIBLE_DIR}")"
if [[ "${INVENTORY}" == /* ]]; then
    INVENTORY_PATH="${INVENTORY}"
else
    INVENTORY_PATH="${ANSIBLE_DIR}/${INVENTORY}"
fi
[[ -f "${INVENTORY_PATH}" ]] || die "inventory not found: ${INVENTORY_PATH}"
[[ -f "${ANSIBLE_DIR}/${PLAYBOOK}" ]] || die "playbook not found: ${ANSIBLE_DIR}/${PLAYBOOK}"

ANSIBLE_PLAYBOOK_BIN="$(command -v ansible-playbook 2>/dev/null || true)"
[[ -n "${ANSIBLE_PLAYBOOK_BIN}" ]] || die "ansible-playbook not found in PATH"

declare -g HAS_CORE=false
declare -g HAS_MATRIX=false
for os_type in "${OS_TYPES[@]}"; do
    case "${os_type}" in
        epics-env-rocky8|epics-env-debian13)
            HAS_CORE=true
            ;;
        epics-env-rocky10|epics-env-ubuntu24|epics-env-ubuntu26)
            HAS_MATRIX=true
            ;;
        *)
            die "unsupported EPICS-env OS selector: ${os_type}"
            ;;
    esac
done

if [[ "${HAS_CORE}" == true && "${HAS_MATRIX}" == true ]]; then
    ANSIBLE_LIMIT="epics_env_build"
elif [[ "${HAS_CORE}" == true ]]; then
    ANSIBLE_LIMIT="epics_env_core"
else
    ANSIBLE_LIMIT="epics_env_matrix"
fi

for os_type in "${OS_TYPES[@]}"; do
    runtime_inventory="$(mktemp /tmp/cloud-provision-ansible-inventory.XXXXXX)"
    RUNTIME_INVENTORIES+=("${runtime_inventory}")
    status_report="$(
        "${CREATE_VM}" -o "${os_type}" -n "${NODE_ID}" \
            -d "${IMAGE_DIR}" -p "${VM_PREFIX}" -s
    )"
    if ! "${INVENTORY_GENERATOR}" \
        --status-input \
        --os-type "${os_type}" \
        --role epics-env-build <<< "${status_report}" > "${runtime_inventory}"; then
        die "failed to generate runtime inventory for ${os_type}"
    fi
    printf "Generated inventory for %s [OK]\n" "${os_type}"
done

declare -ag INVENTORY_ARGS=(-i "${INVENTORY_PATH}")
for runtime_inventory in "${RUNTIME_INVENTORIES[@]}"; do
    INVENTORY_ARGS+=(-i "${runtime_inventory}")
done

printf "Running %s on %s\n" "${PLAYBOOK}" "${ANSIBLE_LIMIT}"
(
    cd "${ANSIBLE_DIR}"
    "${ANSIBLE_PLAYBOOK_BIN}" "${INVENTORY_ARGS[@]}" \
        --limit "${ANSIBLE_LIMIT}" "${PLAYBOOK}"
)
