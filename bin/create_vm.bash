#!/usr/bin/env bash
#
# Cloud-init based VM provisioner for libvirt/KVM.
# Provisions multi-node test environments on Rocky Linux 8.10 and Debian 13.

set -e

declare -g SC_RPATH
declare -g SC_TOP

SC_RPATH="$(realpath "$0")"
SC_TOP="${SC_RPATH%/*}/.."
SC_TOP="$(realpath "${SC_TOP}")"

# --- Global Configuration ---
declare -g VM_PREFIX="testbed"
declare -g VM_NAME
declare -g VM_RAM=2048
declare -g VM_VCPUS=2
declare -g VM_DISK_SIZE="20G"
declare -g IMAGE_DIR
declare -g OS_TYPE
declare -g OS_VARIANT
declare -g NODE_ID
declare -g BACKING_FORMAT="qcow2"
declare -g LIBVIRT_URI="qemu:///system"
declare -g LIBVIRT_NETWORK="default"
declare -g VM_BOOT_FIRMWARE=""
declare -g REQUIRED_GROUP="libvirt"

# Network configuration: static IP via libvirt DHCP reservation
declare -g NETWORK_SUBNET="192.168.122"
declare -g MAC_PREFIX="52:54:00:00"
declare -g DEBIAN13_IP_BASE=10
declare -g ROCKY8_IP_BASE=100
declare -g VM_IP=""
declare -g VM_MAC=""

# Base image details
declare -g BASE_URL
declare -g BASE_IMAGE_NAME
declare -g BASE_IMAGE_FULL_PATH
declare -g TARGET_DISK
declare -g CLOUD_INIT_ISO

# Action flags
declare -g DO_CLEANUP=false
declare -g DO_STATUS=false

function print_usage {
    printf "Usage: %s [options]\n" "$(basename "$0")"
    printf "\n"
    printf "Options:\n"
    printf "  -o <os_type>   OS type: rocky8, debian13 (default: rocky8)\n"
    printf "  -n <node_id>   Node identifier: server, node1, node2, ... (default: test)\n"
    printf "  -d <image_dir> Image storage directory (default: ~/libvirt/images)\n"
    printf "  -p <prefix>    VM name prefix (default: testbed)\n"
    printf "  -c             Remove VM domain, target disk, and seed ISO\n"
    printf "  -s             Check VM IP, SSH, and cloud-init readiness\n"
    printf "  -h             Show this help message\n"
    printf "\n"
    printf "Examples:\n"
    printf "  %s -o rocky8 -n server\n" "$(basename "$0")"
    printf "  %s -o debian13 -n node1\n" "$(basename "$0")"
    printf "  %s -o rocky8 -n server -s\n" "$(basename "$0")"
    printf "  %s -o rocky8 -n server -c\n" "$(basename "$0")"
}

# --- Group Membership Check ---
if ! groups "$USER" | grep -q "\b${REQUIRED_GROUP}\b"; then
    printf "Error: User is not in the %s group.\n" "$REQUIRED_GROUP"
    printf "Action: Run 'sudo usermod -aG %s %s' and re-login.\n" "$REQUIRED_GROUP" "$USER"
    exit 1
fi

# --- Argument Processing ---
while getopts ":o:n:d:p:csh" opt; do
    case "$opt" in
        o) OS_TYPE="$OPTARG" ;;
        n) NODE_ID="$OPTARG" ;;
        d) IMAGE_DIR="$OPTARG" ;;
        p) VM_PREFIX="$OPTARG" ;;
        c) DO_CLEANUP=true ;;
        s) DO_STATUS=true ;;
        h) print_usage; exit 0 ;;
        :) printf "Error: Option -%s requires an argument.\n" "$OPTARG"; exit 1 ;;
        ?) printf "Error: Unknown option -%s\n" "$OPTARG"; exit 1 ;;
    esac
done

: "${OS_TYPE:=rocky8}"
: "${NODE_ID:=test}"
: "${IMAGE_DIR:=${HOME}/libvirt/images}"

# --- OS-Specific Configuration ---
if [[ "${OS_TYPE}" == "rocky8" ]]; then
    OS_VARIANT="rocky8"
    BASE_IMAGE_NAME="Rocky-8-GenericCloud-Base.latest.x86_64.qcow2"
    BASE_URL="https://download.rockylinux.org/pub/rocky/8/images/x86_64/${BASE_IMAGE_NAME}"
elif [[ "${OS_TYPE}" == "debian13" ]]; then
    OS_VARIANT="debian13"
    VM_BOOT_FIRMWARE="uefi"
    BASE_IMAGE_NAME="debian-13-genericcloud-amd64-daily.qcow2"
    BASE_URL="https://cloud.debian.org/images/cloud/trixie/daily/latest/${BASE_IMAGE_NAME}"
else
    printf "Error: Unsupported OS type: %s\n" "${OS_TYPE}"
    exit 1
fi

# --- Derived Paths ---
if [[ ! -d "${IMAGE_DIR}" ]]; then
    mkdir -p "${IMAGE_DIR}"
    chmod 755 "${IMAGE_DIR}"
fi
IMAGE_DIR="$(realpath "${IMAGE_DIR}")"

VM_NAME="${VM_PREFIX}-${OS_TYPE}-${NODE_ID}"
BASE_IMAGE_FULL_PATH="${IMAGE_DIR}/${BASE_IMAGE_NAME}"
TARGET_DISK="${IMAGE_DIR}/${VM_NAME}.qcow2"
CLOUD_INIT_ISO="${IMAGE_DIR}/${VM_NAME}-seed.iso"

# --- Network Resolution ---
# Derives static IP and MAC from OS type and node identifier.
# IP:  ${NETWORK_SUBNET}.${OS_BASE + NODE_OFFSET}
# MAC: ${MAC_PREFIX}:${OS_HEX}:${NODE_HEX}
function resolve_network {
    local os_base=0
    local node_offset=0

    case "${OS_TYPE}" in
        rocky8)   os_base=${ROCKY8_IP_BASE} ;;
        debian13) os_base=${DEBIAN13_IP_BASE} ;;
    esac

    case "${NODE_ID}" in
        server) node_offset=0 ;;
        node[0-9]*) node_offset="${NODE_ID#node}" ;;
        test)
            printf "Warning: NODE_ID=test uses DHCP (no static IP).\n"
            return 1
            ;;
        *)
            # Deterministic hash of NODE_ID mapped to 200-254 range
            local hash=0
            local i ch
            for (( i=0; i<${#NODE_ID}; i++ )); do
                printf -v ch '%d' "'${NODE_ID:$i:1}"
                hash=$(( (hash * 31 + ch) % 55 ))
            done
            local ip_last=$(( 200 + hash ))
            VM_IP="${NETWORK_SUBNET}.${ip_last}"
            VM_MAC=$(printf "%s:%02x:%02x" "${MAC_PREFIX}" "200" "${hash}")
            printf "Note: NODE_ID=%s mapped to %s\n" "${NODE_ID}" "${VM_IP}"
            return 0
            ;;
    esac

    local ip_last=$(( os_base + node_offset ))
    VM_IP="${NETWORK_SUBNET}.${ip_last}"
    VM_MAC=$(printf "%s:%02x:%02x" "${MAC_PREFIX}" "${os_base}" "${node_offset}")
}

# Register DHCP reservation in libvirt network
function register_dhcp {
    if [[ -z "${VM_IP}" || -z "${VM_MAC}" ]]; then
        return 0
    fi

    # Remove existing reservation if present
    virsh --connect "${LIBVIRT_URI}" net-update "${LIBVIRT_NETWORK}" delete ip-dhcp-host \
        "<host mac='${VM_MAC}' name='${VM_NAME}' ip='${VM_IP}'/>" \
        --live --config 2>/dev/null || true

    printf "Network: registering %s → %s (%s)... " "${VM_NAME}" "${VM_IP}" "${VM_MAC}"
    virsh --connect "${LIBVIRT_URI}" net-update "${LIBVIRT_NETWORK}" add ip-dhcp-host \
        "<host mac='${VM_MAC}' name='${VM_NAME}' ip='${VM_IP}'/>" \
        --live --config
    printf "[OK]\n"
}

# Remove DHCP reservation from libvirt network
function unregister_dhcp {
    if [[ -z "${VM_IP}" || -z "${VM_MAC}" ]]; then
        return 0
    fi

    printf "  Removing DHCP reservation... "
    virsh --connect "${LIBVIRT_URI}" net-update "${LIBVIRT_NETWORK}" delete ip-dhcp-host \
        "<host mac='${VM_MAC}' name='${VM_NAME}' ip='${VM_IP}'/>" \
        --live --config 2>/dev/null \
        && printf "[OK]\n" || printf "[not found]\n"
}

# Resolve network (non-fatal if NODE_ID is unknown)
resolve_network || true

# --- Cleanup ---
function do_cleanup {
    printf "Cleanup: %s\n" "${VM_NAME}"

    printf "  Stopping VM... "
    virsh --connect "${LIBVIRT_URI}" destroy "${VM_NAME}" 2>/dev/null \
        && printf "[OK]\n" || printf "[not running]\n"

    printf "  Undefining VM... "
    virsh --connect "${LIBVIRT_URI}" undefine "${VM_NAME}" 2>/dev/null \
        && printf "[OK]\n" || printf "[not defined]\n"

    printf "  Removing disk... "
    rm -f "${TARGET_DISK}" && printf "[OK]\n" || printf "[not found]\n"

    printf "  Removing seed ISO... "
    rm -f "${CLOUD_INIT_ISO}" && printf "[OK]\n" || printf "[not found]\n"

    unregister_dhcp
}

# --- Base Image Acquisition ---
function verify_base_image {
    if [[ -f "${BASE_IMAGE_FULL_PATH}" ]]; then
        printf "Base image: verifying... "
        if ! qemu-img info "${BASE_IMAGE_FULL_PATH}" 2>/dev/null | grep -q "file format: qcow2"; then
            printf "[CORRUPT] removing\n"
            rm -f "${BASE_IMAGE_FULL_PATH}"
        else
            printf "[OK]\n"
            return 0
        fi
    fi

    printf "Base image: downloading from mirror...\n"
    curl -f -L --retry 3 -o "${BASE_IMAGE_FULL_PATH}" "${BASE_URL}"
    printf "Base image: download complete.\n"
}

# --- Disk Preparation ---
function prepare_disk {
    if [[ -f "${TARGET_DISK}" ]]; then
        rm -f "${TARGET_DISK}"
    fi

    printf "Disk: creating layered qcow2... "
    qemu-img create -f qcow2 -b "${BASE_IMAGE_FULL_PATH}" -F "${BACKING_FORMAT}" \
        "${TARGET_DISK}" "${VM_DISK_SIZE}" > /dev/null
    printf "[OK]\n"
}

# --- Cloud-Init Seed Generation ---
function generate_seed {
    local pub_key_path=""
    local pub_key_data=""
    local seed_dir="${SC_TOP}/.seed_staging"
    local user_data_template="${SC_TOP}/templates/user-data.${OS_TYPE}"

    # SSH key discovery
    for key_file in "id_ed25519.pub" "id_rsa.pub"; do
        if [[ -f "${HOME}/.ssh/${key_file}" ]]; then
            pub_key_path="${HOME}/.ssh/${key_file}"
            break
        fi
    done

    if [[ -z "${pub_key_path}" ]]; then
        printf "Error: No SSH public key found in ~/.ssh/\n"
        exit 1
    fi
    pub_key_data=$(cat "${pub_key_path}")

    if [[ ! -f "${user_data_template}" ]]; then
        printf "Error: user-data template not found: %s\n" "${user_data_template}"
        exit 1
    fi

    printf "Seed: generating cloud-init ISO... "

    rm -rf "${seed_dir}"
    mkdir -p "${seed_dir}"

    # meta-data: dynamic hostname from VM_NAME
    printf "instance-id: %s\n" "$(uuidgen)" > "${seed_dir}/meta-data"
    printf "local-hostname: %s\n" "${VM_NAME}" >> "${seed_dir}/meta-data"

    # user-data: inject SSH key into OS-specific template
    export PUB_KEY_DATA="${pub_key_data}"
    perl -pe 's/SSH_AUTHORIZED_KEY_PLACEHOLDER/$ENV{PUB_KEY_DATA}/g' \
        "${user_data_template}" > "${seed_dir}/user-data"

    if [[ -f "${CLOUD_INIT_ISO}" ]]; then
        rm -f "${CLOUD_INIT_ISO}"
    fi

    genisoimage -output "${CLOUD_INIT_ISO}" \
        -volid cidata -joliet -rock \
        -input-charset utf-8 \
        -graft-points \
        "user-data=${seed_dir}/user-data" \
        "meta-data=${seed_dir}/meta-data" 2>/dev/null

    rm -rf "${seed_dir}"
    printf "[OK]\n"
}

# --- VM Provisioning ---
function provision_vm {
    printf "Provisioning: %s\n" "${VM_NAME}"

    local boot_args=()
    if [[ -n "${VM_BOOT_FIRMWARE}" ]]; then
        boot_args=(--boot "${VM_BOOT_FIRMWARE}")
    fi


    local net_args="network=default,model=virtio"
    if [[ -n "${VM_MAC}" ]]; then
        net_args="${net_args},mac=${VM_MAC}"
    fi

    virt-install \
        --connect "${LIBVIRT_URI}" \
        --name "${VM_NAME}" \
        --vcpus "${VM_VCPUS}" \
        --memory "${VM_RAM}" \
        --disk path="${TARGET_DISK}",format=qcow2,bus=virtio \
        --disk path="${CLOUD_INIT_ISO}",device=cdrom,bus=sata \
        --import \
        --network "${net_args}" \
        --os-variant "${OS_VARIANT}" \
        --graphics none \
        "${boot_args[@]+"${boot_args[@]}"}" \
        --noautoconsole
}

# --- VM Readiness Check ---
function wait_for_vm {
    local mode="${1:-retry}"
    local ip_addr="${VM_IP}"

    # Static IP: skip polling, go straight to readiness check
    if [[ -n "${ip_addr}" ]]; then
        wait_for_ssh "${ip_addr}" "${mode}" || return 1
        wait_for_cloud_init "${ip_addr}" "${mode}"

        printf "%s\n" "------------------------------------------------------------"
        printf "VM Name    : %s\n" "${VM_NAME}"
        printf "IP Address : %s\n" "${ip_addr}"
        printf "SSH        : ssh vmadmin@%s\n" "${ip_addr}"
        printf "%s\n" "------------------------------------------------------------"
        return 0
    fi

    # DHCP fallback: poll for IP
    local max_retry=3
    local interval=10
    local attempt=0

    printf "Status: retrieving IP for %s...\n" "${VM_NAME}"

    while [[ ${attempt} -lt ${max_retry} ]]; do
        ip_addr=$(virsh --connect "${LIBVIRT_URI}" domifaddr "${VM_NAME}" 2>/dev/null \
            | awk '/ipv4/ {print $4; exit}' | cut -d'/' -f1)

        if [[ -n "${ip_addr}" ]]; then
            wait_for_ssh "${ip_addr}" "${mode}" || return 1
            wait_for_cloud_init "${ip_addr}" "${mode}"

            printf "%s\n" "------------------------------------------------------------"
            printf "VM Name    : %s\n" "${VM_NAME}"
            printf "IP Address : %s\n" "${ip_addr}"
            printf "SSH        : ssh vmadmin@%s\n" "${ip_addr}"
            printf "%s\n" "------------------------------------------------------------"
            return 0
        fi

        if [[ "${mode}" == "once" ]]; then
            printf "Status: IP not available.\n"
            return 1
        fi

        attempt=$(( attempt + 1 ))
        if [[ ${attempt} -lt ${max_retry} ]]; then
            printf "Status: IP not yet available. Retrying in %ss... (%s/%s)\n" \
                "${interval}" "${attempt}" "${max_retry}"
            sleep "${interval}"
        fi
    done

    printf "Status: IP not available. Check manually: %s -s\n" "$(basename "$0")"
}

function wait_for_ssh {
    local ip_addr="$1"
    local mode="${2:-retry}"
    local max_retry=6
    local interval=10
    local attempt=0

    while [[ ${attempt} -lt ${max_retry} ]]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
               "vmadmin@${ip_addr}" "exit" 2>/dev/null; then
            printf "SSH: ready [OK]\n"
            return 0
        fi

        if [[ "${mode}" == "once" ]]; then
            printf "SSH: not available.\n"
            return 1
        fi

        attempt=$(( attempt + 1 ))
        if [[ ${attempt} -lt ${max_retry} ]]; then
            printf "SSH: retrying in %ss... (%s/%s)\n" "${interval}" "${attempt}" "${max_retry}"
            sleep "${interval}"
        fi
    done

    printf "SSH: not available after %s attempts.\n" "${max_retry}"
    return 1
}

function wait_for_cloud_init {
    local ip_addr="$1"
    local mode="${2:-retry}"
    local max_retry=6
    local interval=30
    local attempt=0
    local status

    while [[ ${attempt} -lt ${max_retry} ]]; do
        status=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
                     "vmadmin@${ip_addr}" "cloud-init status" 2>/dev/null || true)

        if [[ "${status}" == *"done"* ]]; then
            printf "cloud-init: complete [OK]\n"
            return 0
        fi

        if [[ "${mode}" == "once" ]]; then
            printf "cloud-init: %s\n" "${status}"
            return 1
        fi

        attempt=$(( attempt + 1 ))
        if [[ ${attempt} -lt ${max_retry} ]]; then
            printf "cloud-init: retrying in %ss... (%s/%s)\n" "${interval}" "${attempt}" "${max_retry}"
            sleep "${interval}"
        fi
    done

    printf "cloud-init: not complete after %s attempts.\n" "${max_retry}"
}

# --- Main ---
if [[ "${DO_CLEANUP}" == true ]]; then
    do_cleanup
    exit 0
fi

if [[ "${DO_STATUS}" == true ]]; then
    wait_for_vm "once"
    exit 0
fi

printf "%s\n" "------------------------------------------------------------"
printf "OS Type    : %s\n" "${OS_TYPE}"
printf "Node ID    : %s\n" "${NODE_ID}"
printf "VM Name    : %s\n" "${VM_NAME}"
printf "Storage    : %s\n" "${IMAGE_DIR}"
if [[ -n "${VM_IP}" ]]; then
    printf "IP Address : %s\n" "${VM_IP}"
    printf "MAC Address: %s\n" "${VM_MAC}"
fi
printf "%s\n" "------------------------------------------------------------"

# Check if VM already exists
if virsh --connect "${LIBVIRT_URI}" dominfo "${VM_NAME}" >/dev/null 2>&1; then
    printf "VM '%s' already exists.\n" "${VM_NAME}"
    printf "  [1] Rebuild (destroy and reprovision)\n"
    printf "  [2] Connect (show SSH info)\n"
    printf "  [3] Abort\n"
    printf "Select [1-3]: "
    read -r choice
    case "${choice}" in
        1)
            do_cleanup
            ;;
        2)
            wait_for_vm "once"
            exit 0
            ;;
        *)
            printf "Aborted.\n"
            exit 0
            ;;
    esac
fi

verify_base_image
prepare_disk
generate_seed
register_dhcp
provision_vm
wait_for_vm

printf "%s\n" "------------------------------------------------------------"
printf "READY\n"
printf "%s\n" "------------------------------------------------------------"
