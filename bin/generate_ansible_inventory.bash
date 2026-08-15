#!/usr/bin/env bash
#
# Generate one Ansible host inventory from a resolved cloud-provision VM.

set -euo pipefail

declare -g VM_NAME=""
declare -g VM_ADDRESS=""
declare -g OS_TYPE=""
declare -g WORKLOAD_ROLE=""
declare -g ANSIBLE_USER="vmadmin"
declare -g READ_STATUS_INPUT=false

function die {
    printf "Error: %s\n" "$*" >&2
    exit 1
}

function print_usage {
    printf "Usage: %s --os-type <selector> --role <role> [host source]\n" \
        "$(basename "$0")"
    printf "\n"
    printf "Host source (choose one):\n"
    printf "  --vm-name <name> --address <ipv4>\n"
    printf "  --status-input                     Read create_vm.bash -s output from stdin\n"
    printf "\n"
    printf "Required:\n"
    printf "  --os-type <selector>               cloud-provision OS selector\n"
    printf "  --role <role>                      ioc-node, nfs-sim-node,\n"
    printf "                                       ioc-runner-build, ethercat-node,\n"
    printf "                                       ethercat-build, or epics-env-build\n"
    printf "\n"
    printf "Optional:\n"
    printf "  --ansible-user <name>              SSH user (default: vmadmin)\n"
    printf "  -h, --help                          Show this help\n"
}

function require_option_value {
    local option_name="$1"
    local remaining="$2"

    [[ "${remaining}" -ge 2 ]] || die "${option_name} requires an argument"
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --vm-name)
            require_option_value "$1" "$#"
            VM_NAME="$2"
            shift 2
            ;;
        --address)
            require_option_value "$1" "$#"
            VM_ADDRESS="$2"
            shift 2
            ;;
        --os-type)
            require_option_value "$1" "$#"
            OS_TYPE="$2"
            shift 2
            ;;
        --role)
            require_option_value "$1" "$#"
            WORKLOAD_ROLE="$2"
            shift 2
            ;;
        --ansible-user)
            require_option_value "$1" "$#"
            ANSIBLE_USER="$2"
            shift 2
            ;;
        --status-input)
            READ_STATUS_INPUT=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

[[ -n "${OS_TYPE}" ]] || die "--os-type is required"
[[ -n "${WORKLOAD_ROLE}" ]] || die "--role is required"

if [[ "${READ_STATUS_INPUT}" == true ]]; then
    [[ -z "${VM_NAME}" && -z "${VM_ADDRESS}" ]] \
        || die "--status-input cannot be combined with --vm-name or --address"
    status_report="$(</dev/stdin)"
    VM_NAME="$(awk -F': *' '/^VM Name[[:space:]]*:/ {print $2; exit}' <<< "${status_report}")"
    VM_ADDRESS="$(awk -F': *' '/^IP Address[[:space:]]*:/ {print $2; exit}' <<< "${status_report}")"
else
    [[ -n "${VM_NAME}" && -n "${VM_ADDRESS}" ]] \
        || die "--vm-name and --address are required without --status-input"
fi

[[ "${VM_NAME}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || die "VM name is not inventory-safe: ${VM_NAME:-<empty>}"
[[ "${ANSIBLE_USER}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || die "Ansible user is not inventory-safe: ${ANSIBLE_USER:-<empty>}"

function validate_ipv4_address {
    local address="$1"
    local octet
    local -a octets=()

    IFS='.' read -r -a octets <<< "${address}"
    [[ "${#octets[@]}" -eq 4 ]] || return 1
    for octet in "${octets[@]}"; do
        [[ "${octet}" =~ ^[0-9]{1,3}$ ]] || return 1
        (( 10#${octet} <= 255 )) || return 1
    done
}

validate_ipv4_address "${VM_ADDRESS}" \
    || die "VM address is not a valid IPv4 address: ${VM_ADDRESS:-<empty>}"

declare -ag INVENTORY_GROUPS=()
declare -g BASE_OS_GROUP=""

function select_ioc_os_group {
    case "${OS_TYPE}" in
        rocky8|rocky8-iocrunner)
            BASE_OS_GROUP="rocky8"
            ;;
        debian13|debian13-iocrunner)
            BASE_OS_GROUP="debian13"
            ;;
        *)
            return 1
            ;;
    esac
}

case "${WORKLOAD_ROLE}" in
    ioc-node)
        select_ioc_os_group \
            || die "role ioc-node does not support OS selector: ${OS_TYPE}"
        INVENTORY_GROUPS=("${BASE_OS_GROUP}")
        ;;
    nfs-sim-node)
        select_ioc_os_group \
            || die "role nfs-sim-node does not support OS selector: ${OS_TYPE}"
        INVENTORY_GROUPS=("${BASE_OS_GROUP}" nfs_sim_nodes)
        ;;
    ioc-runner-build)
        case "${OS_TYPE}" in
            rocky8|debian13)
                INVENTORY_GROUPS=("${OS_TYPE}" nfs_sim_nodes)
                ;;
            *)
                die "role ioc-runner-build does not support OS selector: ${OS_TYPE}"
                ;;
        esac
        ;;
    ethercat-node)
        [[ "${OS_TYPE}" == "debian13-ethercat" ]] \
            || die "role ethercat-node requires OS selector debian13-ethercat"
        INVENTORY_GROUPS=(ethercat_nodes)
        ;;
    ethercat-build)
        [[ "${OS_TYPE}" == "debian13-rtbase" ]] \
            || die "role ethercat-build requires OS selector debian13-rtbase"
        INVENTORY_GROUPS=(ethercat_build)
        ;;
    epics-env-build)
        case "${OS_TYPE}" in
            epics-env-rocky8|epics-env-debian13)
                INVENTORY_GROUPS=(epics_env_core)
                ;;
            epics-env-rocky10|epics-env-ubuntu24|epics-env-ubuntu26)
                INVENTORY_GROUPS=(epics_env_matrix)
                ;;
            *)
                die "role epics-env-build does not support OS selector: ${OS_TYPE}"
                ;;
        esac
        ;;
    *)
        die "unsupported workload role: ${WORKLOAD_ROLE}"
        ;;
esac

declare -g HOST_LINE
HOST_LINE="${VM_NAME} ansible_host=${VM_ADDRESS} ansible_user=${ANSIBLE_USER}"

for index in "${!INVENTORY_GROUPS[@]}"; do
    printf "[%s]\n" "${INVENTORY_GROUPS[${index}]}"
    if [[ "${index}" == "0" ]]; then
        printf "%s\n" "${HOST_LINE}"
    else
        printf "%s\n" "${VM_NAME}"
    fi
    printf "\n"
done
