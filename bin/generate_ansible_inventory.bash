#!/usr/bin/env bash
#
# Generate one Ansible host inventory from a resolved cloud-provision VM.
# The vacuum group comes from the OS selector and the species group from
# --species, per the operator definition in docs/IMAGE_WORKFLOW.md.

set -euo pipefail

declare -g VM_NAME=""
declare -g VM_ADDRESS=""
declare -g OS_TYPE=""
declare -g SPECIES=""
declare -g VACUUM=""
declare -g ANSIBLE_USER="vmadmin"
declare -g READ_STATUS_INPUT=false

function die {
    printf "Error: %s\n" "$*" >&2
    exit 1
}

function print_usage {
    printf "Usage: %s --os-type <selector> --species <species> [host source]\n" \
        "$(basename "$0")"
    printf "\n"
    printf "Host source (choose one):\n"
    printf "  --vm-name <name> --address <ipv4>\n"
    printf "  --status-input                     Read create_vm.bash -s output from stdin\n"
    printf "\n"
    printf "Required:\n"
    printf "  --os-type <selector>               cloud-provision OS selector; the\n"
    printf "                                       vacuum group is derived from it\n"
    printf "  --species <species>                bare, iocrunner, iocrunner-nfs,\n"
    printf "                                       epics-dev, nfs-sim, rtbase,\n"
    printf "                                       or ethercat\n"
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
        --species)
            require_option_value "$1" "$#"
            SPECIES="$2"
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
[[ -n "${SPECIES}" ]] || die "--species is required"

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

# The vacuum is the OS selector with any species suffix removed. The
# operator definition assigns every species to every vacuum, so the
# selector constrains only the vacuum, never the species argument.
case "${OS_TYPE}" in
    debian13|rocky8|rocky10|ubuntu24|ubuntu26)
        VACUUM="${OS_TYPE}"
        ;;
    *-iocrunner-nfs) VACUUM="${OS_TYPE%-iocrunner-nfs}" ;;
    *-iocrunner)     VACUUM="${OS_TYPE%-iocrunner}" ;;
    *-epics-dev)     VACUUM="${OS_TYPE%-epics-dev}" ;;
    *-ethercat)      VACUUM="${OS_TYPE%-ethercat}" ;;
    *-rtbase)        VACUUM="${OS_TYPE%-rtbase}" ;;
    *) die "unsupported OS selector: ${OS_TYPE}" ;;
esac
case "${VACUUM}" in
    debian13|rocky8|rocky10|ubuntu24|ubuntu26) ;;
    *) die "unsupported vacuum in OS selector: ${OS_TYPE}" ;;
esac

# A bare host joins only its vacuum group; every other species adds its
# underscore-form species group.
case "${SPECIES}" in
    bare)          INVENTORY_GROUPS=("${VACUUM}") ;;
    iocrunner)     INVENTORY_GROUPS=("${VACUUM}" iocrunner) ;;
    iocrunner-nfs) INVENTORY_GROUPS=("${VACUUM}" iocrunner_nfs) ;;
    epics-dev)     INVENTORY_GROUPS=("${VACUUM}" epics_dev) ;;
    nfs-sim)       INVENTORY_GROUPS=("${VACUUM}" nfs_sim) ;;
    rtbase)        INVENTORY_GROUPS=("${VACUUM}" rtbase) ;;
    ethercat)      INVENTORY_GROUPS=("${VACUUM}" ethercat) ;;
    *) die "unsupported species: ${SPECIES}" ;;
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
