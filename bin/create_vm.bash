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
source "${SC_TOP}/bin/image_workflow.bash"

# --- Global Configuration ---
declare -g VM_PREFIX="testbed"
declare -g VM_NAME
declare -g VM_RAM=4096
declare -g VM_VCPUS=2
declare -g IMAGE_DIR
declare -g OS_TYPE
declare -g OS_VARIANT
# libosinfo id for virt-install when it differs from OS_VARIANT: OS_VARIANT
# names the cloud-init template, and for an OS newer than the host's osinfo
# database the nearest known id stands in for device-default selection.
declare -g OSINFO_VARIANT=""
declare -g NODE_ID
declare -g LIBVIRT_URI="qemu:///system"
declare -g LIBVIRT_NETWORK="default"
declare -g VM_BOOT_FIRMWARE=""
declare -g REQUIRED_GROUP="${REQUIRED_GROUP:-libvirt}"

# Network configuration: static IP via libvirt DHCP reservation
declare -g NETWORK_SUBNET="192.168.122"
declare -g MAC_PREFIX="52:54:00:00"
declare -g DEBIAN13_IP_BASE=10
declare -g ROCKY8_IP_BASE=100
declare -g DEBIAN13_IOCRUNNER_IP_BASE=50
declare -g ROCKY8_IOCRUNNER_IP_BASE=150
declare -g DEBIAN13_ETHERCAT_IP_BASE=70
declare -g DEBIAN13_RTBASE_IP_BASE=80
declare -g EPICSENV_DEBIAN13_IP_BASE=20
declare -g EPICSENV_ROCKY8_IP_BASE=120
declare -g EPICSENV_ROCKY10_IP_BASE=130
declare -g EPICSENV_UBUNTU26_IP_BASE=30
declare -g EPICSENV_UBUNTU24_IP_BASE=40
declare -g VM_IP=""
declare -g VM_MAC=""

# Base image details
declare -g BASE_URL
declare -g BASE_IMAGE_NAME
declare -g BASE_IMAGE_FULL_PATH
declare -g TARGET_DISK
declare -g CLOUD_INIT_ISO
declare -g BASE_IMAGE_KIND=""
declare -g BASE_IMAGE_PLATFORM=""
declare -g IMAGE_WORKFLOW_RUN_ID="${IMAGE_WORKFLOW_RUN_ID:-}"

# Action flags
declare -g DO_CLEANUP=false
declare -g DO_STATUS=false
declare -g DO_STOP=false
declare -g DO_FRESH=false

function print_usage {
    printf "Usage: %s [options]\n" "$(basename "$0")"
    printf "\n"
    printf "Options:\n"
    printf "  -o <os_type>   OS type (default: rocky8)\n"
    printf "                 rocky8, debian13, rocky8-iocrunner, debian13-iocrunner\n"
    printf "                 debian13-ethercat, debian13-rtbase\n"
    printf "                 epics-env-rocky8, epics-env-debian13, epics-env-rocky10\n"
    printf "                 epics-env-ubuntu26, epics-env-ubuntu24\n"
    printf "  -n <node_id>   Node identifier: server, node1, node2, ... (default: test)\n"
    printf "  -d <image_dir> Image storage directory (default: ~/libvirt/images)\n"
    printf "  -p <prefix>    VM name prefix (default: testbed)\n"
    printf "  -m <mb>        VM memory in MB (default: 4096)\n"
    printf "  -c             Remove VM domain, target disk, and seed ISO\n"
    printf "  -s             Check VM domain, IP, SSH, and cloud-init readiness\n"
    printf "  -S             Graceful shutdown of running VM (ACPI, polls until shut off)\n"
    printf "  -F             Require a new domain and disk (provisioning only)\n"
    printf "  -h             Show this help message\n"
    printf "\n"
    printf "Examples:\n"
    printf "  %s -o rocky8 -n server\n" "$(basename "$0")"
    printf "  %s -o debian13 -n node1\n" "$(basename "$0")"
    printf "  %s -o rocky8 -n server -m 4096\n" "$(basename "$0")"
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
while getopts ":o:n:d:p:m:csSFh" opt; do
    case "$opt" in
        o) OS_TYPE="$OPTARG" ;;
        n) NODE_ID="$OPTARG" ;;
        d) IMAGE_DIR="$OPTARG" ;;
        p) VM_PREFIX="$OPTARG" ;;
        m) VM_RAM="$OPTARG" ;;
        c) DO_CLEANUP=true ;;
        s) DO_STATUS=true ;;
        S) DO_STOP=true ;;
        F) DO_FRESH=true ;;
        h) print_usage; exit 0 ;;
        :) printf "Error: Option -%s requires an argument.\n" "$OPTARG"; exit 1 ;;
        ?) printf "Error: Unknown option -%s\n" "$OPTARG"; exit 1 ;;
    esac
done

: "${OS_TYPE:=rocky8}"
: "${NODE_ID:=test}"
: "${IMAGE_DIR:=${HOME}/libvirt/images}"

if [[ "${DO_FRESH}" == true ]] && \
   { [[ "${DO_CLEANUP}" == true ]] || [[ "${DO_STATUS}" == true ]] || [[ "${DO_STOP}" == true ]]; }; then
    printf "Error: -F is valid only for provisioning.\n" >&2
    exit 1
fi

if [[ ! "${VM_RAM}" =~ ^[1-9][0-9]*$ ]]; then
    printf "Error: -m memory must be a positive integer in MB, got: %s\n" "${VM_RAM}"
    exit 1
fi

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
elif [[ "${OS_TYPE}" == "rocky8-iocrunner" ]]; then
    OS_VARIANT="rocky8"
    BASE_IMAGE_KIND="iocrunner"
    BASE_IMAGE_PLATFORM="rocky8"
    BASE_URL=""
elif [[ "${OS_TYPE}" == "debian13-iocrunner" ]]; then
    OS_VARIANT="debian13"
    VM_BOOT_FIRMWARE="uefi"
    BASE_IMAGE_KIND="iocrunner"
    BASE_IMAGE_PLATFORM="debian13"
    BASE_URL=""
elif [[ "${OS_TYPE}" == "debian13-ethercat" ]]; then
    OS_VARIANT="debian13"
    VM_BOOT_FIRMWARE="uefi"
    BASE_IMAGE_KIND="ethercat"
    BASE_IMAGE_PLATFORM="debian13"
    BASE_URL=""
elif [[ "${OS_TYPE}" == "debian13-rtbase" ]]; then
    # Pinned Debian 13 genericcloud RELEASE image used as the EtherCAT/RT bake
    # base. Unlike the moving "-daily" image, a dated release has published
    # kernel headers, so module builds resolve. Bump this pin at least quarterly
    # (consciously, like ethercat-env SRC_HASH) from
    # https://cloud.debian.org/images/cloud/trixie/<DATE-BUILD>/.
    OS_VARIANT="debian13"
    VM_BOOT_FIRMWARE="uefi"
    BASE_IMAGE_NAME="debian-13-genericcloud-amd64-20260601-2496.qcow2"
    BASE_URL="https://cloud.debian.org/images/cloud/trixie/20260601-2496/debian-13-genericcloud-amd64-20260601-2496.qcow2"
elif [[ "${OS_TYPE}" == "epics-env-rocky8" ]]; then
    # EPICS-env from-source build host. Boots the plain Rocky 8 base image
    # (no golden bake); ansible-provision builds EPICS-env from source on top.
    OS_VARIANT="rocky8"
    BASE_IMAGE_NAME="Rocky-8-GenericCloud-Base.latest.x86_64.qcow2"
    BASE_URL="https://download.rockylinux.org/pub/rocky/8/images/x86_64/${BASE_IMAGE_NAME}"
elif [[ "${OS_TYPE}" == "epics-env-debian13" ]]; then
    # EPICS-env from-source build host on the plain Debian 13 base image.
    OS_VARIANT="debian13"
    VM_BOOT_FIRMWARE="uefi"
    BASE_IMAGE_NAME="debian-13-genericcloud-amd64-daily.qcow2"
    BASE_URL="https://cloud.debian.org/images/cloud/trixie/daily/latest/${BASE_IMAGE_NAME}"
elif [[ "${OS_TYPE}" == "epics-env-rocky10" ]]; then
    # EPICS-env from-source build host on the plain Rocky 10 base image.
    # RHEL 10 family dropped legacy BIOS boot on x86_64, so UEFI is required;
    # the host osinfo database tops out at rocky9, which stands in for
    # device-default selection.
    OS_VARIANT="rocky10"
    OSINFO_VARIANT="rocky9"
    VM_BOOT_FIRMWARE="uefi"
    BASE_IMAGE_NAME="Rocky-10-GenericCloud-Base.latest.x86_64.qcow2"
    BASE_URL="https://download.rockylinux.org/pub/rocky/10/images/x86_64/${BASE_IMAGE_NAME}"
elif [[ "${OS_TYPE}" == "epics-env-ubuntu24" ]]; then
    # EPICS-env from-source build host on the plain Ubuntu 24.04 LTS base
    # image (codename noble); carried for full-coverage distribution builds.
    OS_VARIANT="ubuntu24"
    OSINFO_VARIANT="ubuntu24.04"
    VM_BOOT_FIRMWARE="uefi"
    BASE_IMAGE_NAME="noble-server-cloudimg-amd64.img"
    BASE_URL="https://cloud-images.ubuntu.com/noble/current/${BASE_IMAGE_NAME}"
elif [[ "${OS_TYPE}" == "epics-env-ubuntu26" ]]; then
    # EPICS-env from-source build host on the plain Ubuntu 26.04 LTS base
    # image (codename resolute). The host osinfo database tops out at
    # ubuntu25.10, which stands in for device-default selection.
    OS_VARIANT="ubuntu26"
    OSINFO_VARIANT="ubuntu25.10"
    VM_BOOT_FIRMWARE="uefi"
    BASE_IMAGE_NAME="resolute-server-cloudimg-amd64.img"
    BASE_URL="https://cloud-images.ubuntu.com/resolute/current/${BASE_IMAGE_NAME}"
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

if [[ -n "${IMAGE_WORKFLOW_RUN_ID}" ]] && \
   ! image_workflow_validate_run_id "${IMAGE_WORKFLOW_RUN_ID}"; then
    printf "Error: IMAGE_WORKFLOW_RUN_ID must match YYYYMMDDTHHMMSSZ-<12 lowercase hex>\n" >&2
    exit 1
fi
if ! VM_NAME="$(image_workflow_vm_name \
    "${VM_PREFIX}" "${OS_TYPE}" "${NODE_ID}" "${IMAGE_WORKFLOW_RUN_ID}")"; then
    printf "Error: failed to resolve VM name\n" >&2
    exit 1
fi
if [[ -n "${BASE_IMAGE_KIND}" ]]; then
    if ! BASE_IMAGE_NAME="$(image_workflow_select_latest_image \
        "${IMAGE_DIR}" "${BASE_IMAGE_KIND}" "${BASE_IMAGE_PLATFORM}")"; then
        printf "Error: no valid %s image found for %s in %s\n" \
            "${BASE_IMAGE_KIND}" "${BASE_IMAGE_PLATFORM}" "${IMAGE_DIR}" >&2
        exit 1
    fi
fi
BASE_IMAGE_FULL_PATH="${IMAGE_DIR}/${BASE_IMAGE_NAME}"
if ! TARGET_DISK="$(image_workflow_vm_disk_path \
    "${IMAGE_DIR}" "${VM_PREFIX}" "${OS_TYPE}" "${NODE_ID}" \
    "${IMAGE_WORKFLOW_RUN_ID}")"; then
    printf "Error: failed to resolve VM disk path\n" >&2
    exit 1
fi
CLOUD_INIT_ISO="${IMAGE_DIR}/${VM_NAME}-seed.iso"

# --- Network Resolution ---
# Derives static IP and MAC from OS type and node identifier.
# IP:  ${NETWORK_SUBNET}.${OS_BASE + NODE_OFFSET}
# MAC: ${MAC_PREFIX}:${OS_HEX}:${NODE_HEX}
function resolve_network {
    local os_base=0
    local node_offset=0

    case "${OS_TYPE}" in
        rocky8)             os_base=${ROCKY8_IP_BASE} ;;
        debian13)           os_base=${DEBIAN13_IP_BASE} ;;
        rocky8-iocrunner)   os_base=${ROCKY8_IOCRUNNER_IP_BASE} ;;
        debian13-iocrunner) os_base=${DEBIAN13_IOCRUNNER_IP_BASE} ;;
        debian13-ethercat)  os_base=${DEBIAN13_ETHERCAT_IP_BASE} ;;
        debian13-rtbase)    os_base=${DEBIAN13_RTBASE_IP_BASE} ;;
        epics-env-rocky8)   os_base=${EPICSENV_ROCKY8_IP_BASE} ;;
        epics-env-debian13) os_base=${EPICSENV_DEBIAN13_IP_BASE} ;;
        epics-env-rocky10)  os_base=${EPICSENV_ROCKY10_IP_BASE} ;;
        epics-env-ubuntu26) os_base=${EPICSENV_UBUNTU26_IP_BASE} ;;
        epics-env-ubuntu24) os_base=${EPICSENV_UBUNTU24_IP_BASE} ;;
    esac

    case "${NODE_ID}" in
        server) node_offset=0 ;;
        node[0-9]*) node_offset="${NODE_ID#node}" ;;
        test)
            printf "Warning: NODE_ID=test uses DHCP (no static IP).\n"
            return 1
            ;;
        *)
            # Deterministic hash of OS_TYPE and NODE_ID mapped to 160-254.
            # 160-199 sits between the highest per-OS block (150 plus node
            # offsets) and the old 200-254 window, and nothing else uses it, so
            # widening costs nothing and roughly halves the collision rate. A
            # fixed range still collides; register_dhcp names it when it does.
            # Both go into the hash: an address identifies a VM, not a node
            # name. Hashing NODE_ID alone gave every OS type the same address
            # and the same MAC for a given node ID, so the second VM could not
            # be created at all.
            local hash=0
            local i ch
            local hash_key="${OS_TYPE}/${NODE_ID}"
            for (( i=0; i<${#hash_key}; i++ )); do
                printf -v ch '%d' "'${hash_key:$i:1}"
                hash=$(( (hash * 31 + ch) % 95 ))
            done
            local ip_last=$(( 160 + hash ))
            VM_IP="${NETWORK_SUBNET}.${ip_last}"
            VM_MAC=$(printf "%s:%02x:%02x" "${MAC_PREFIX}" "160" "${hash}")
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

    # Remove existing reservation if present. This matches only this VM's own
    # exact triple, so another VM holding the same address is left alone and
    # the add below is what meets it.
    virsh --connect "${LIBVIRT_URI}" net-update "${LIBVIRT_NETWORK}" delete ip-dhcp-host \
        "<host mac='${VM_MAC}' name='${VM_NAME}' ip='${VM_IP}'/>" \
        --live --config 2>/dev/null || true

    # Name the collision before libvirt does. The address computed for this VM
    # can be held by another one — the fallback node-ID mapping has 95 slots,
    # so unrelated pairs can land together. libvirt refuses the duplicate, but
    # its message says only that an entry exists; it cannot say which VM holds
    # the address or that a node-ID choice produced it.
    # Match the address as a whole quoted field. A substring or regex match
    # would report 192.168.122.10 as held by the entry for 192.168.122.101,
    # refusing a VM whose address is free.
    local holder
    holder="$(virsh --connect "${LIBVIRT_URI}" net-dumpxml "${LIBVIRT_NETWORK}" 2>/dev/null \
        | awk -F"'" -v want="${VM_IP}" '
            {
                name = ""; addr = ""
                for (i = 2; i <= NF; i += 2) {
                    if ($(i-1) ~ /name=$/) name = $i
                    if ($(i-1) ~ /ip=$/)   addr = $i
                }
                if (addr == want && name != "") { print name; exit }
            }')"
    if [[ -n "${holder}" && "${holder}" != "${VM_NAME}" ]]; then
        printf "Error: %s is already reserved for %s.\n" "${VM_IP}" "${holder}" >&2
        printf "Cause: OS type %s with node ID %s maps to that address.\n" \
            "${OS_TYPE}" "${NODE_ID}" >&2
        printf "Hint: choose a different node ID, or remove the other VM.\n" >&2
        exit 1
    fi

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
    virsh --connect "${LIBVIRT_URI}" undefine "${VM_NAME}" --nvram 2>/dev/null \
        && printf "[OK]\n" || printf "[not defined]\n"

    printf "  Removing disk... "
    rm -f "${TARGET_DISK}" && printf "[OK]\n" || printf "[not found]\n"

    printf "  Removing seed ISO... "
    rm -f "${CLOUD_INIT_ISO}" && printf "[OK]\n" || printf "[not found]\n"

    unregister_dhcp
}

# --- Graceful Shutdown ---
# Issues an ACPI shutdown request and polls until the domain reaches "shut off"
# or the timeout expires (60s default). Idempotent across all states:
#   - not defined / shut off  -> success, no-op
#   - running                 -> shutdown + poll
#   - other (paused, etc.)    -> reported as unexpected, exit 1
function do_stop {
    local state
    local max_retry=12
    local interval=5
    local attempt=0

    state=$(get_domain_state)
    case "${state}" in
        "not defined")
            printf "VM '%s' is not defined.\n" "${VM_NAME}"
            return 0
            ;;
        unavailable)
            printf "libvirt did not answer at %s; '%s' was not checked.\n" \
                "${LIBVIRT_URI}" "${VM_NAME}"
            return 1
            ;;
        "shut off")
            printf "VM '%s' is already shut off.\n" "${VM_NAME}"
            return 0
            ;;
        running)
            printf "VM '%s' is running. Shutting down (ACPI)...\n" "${VM_NAME}"
            virsh --connect "${LIBVIRT_URI}" shutdown "${VM_NAME}" >/dev/null
            while [[ ${attempt} -lt ${max_retry} ]]; do
                sleep "${interval}"
                state=$(get_domain_state)
                if [[ "${state}" == "shut off" ]]; then
                    printf "VM '%s' shut off [OK]\n" "${VM_NAME}"
                    return 0
                fi
                attempt=$(( attempt + 1 ))
            done
            printf "VM '%s' did not shut off within %ss\n" \
                "${VM_NAME}" "$(( max_retry * interval ))"
            return 1
            ;;
        *)
            printf "VM '%s' is in unexpected state: %s\n" "${VM_NAME}" "${state}"
            printf "Hint: run 'make %s.%s.clean' then re-run\n" "${OS_TYPE}" "${NODE_ID}"
            return 1
            ;;
    esac
}

# Requires a new provisioning input while preserving any existing domain or
# source disk. The printed cleanup command is the sole recovery action.
function require_fresh_input {
    local cleanup_command

    printf -v cleanup_command '%q -o %q -n %q -d %q -p %q -c' \
        "${SC_RPATH}" "${OS_TYPE}" "${NODE_ID}" "${IMAGE_DIR}" "${VM_PREFIX}"

    if virsh --connect "${LIBVIRT_URI}" dominfo "${VM_NAME}" >/dev/null 2>&1; then
        printf "Error: fresh provisioning requires an undefined domain: %s\n" \
            "${VM_NAME}" >&2
        printf "Cleanup: %s\n" "${cleanup_command}" >&2
        return 1
    fi

    if [[ -e "${TARGET_DISK}" || -L "${TARGET_DISK}" ]]; then
        printf "Error: fresh provisioning requires an absent source disk: %s\n" \
            "${TARGET_DISK}" >&2
        printf "Cleanup: %s\n" "${cleanup_command}" >&2
        return 1
    fi
}

# --- Base Image Acquisition ---
# Names the class of the selected base image. The operationally important fact
# is not the file name but whether it can be obtained again: a moving upstream
# image reappears on the next run, a pinned one reappears at a fixed URL, and a
# locally baked one does not reappear at all.
function base_image_class {
    if [[ -z "${BASE_URL}" ]]; then
        printf "baked locally, not downloadable\n"
    elif [[ "${BASE_URL}" == *"/latest/"* || "${BASE_URL}" == *"/current/"* \
            || "${BASE_IMAGE_NAME}" == *"daily"* || "${BASE_IMAGE_NAME}" == *".latest."* ]]; then
        printf "upstream, moving\n"
    else
        printf "upstream, pinned\n"
    fi
}

# Never deletes the base image. A locally baked golden has no download URL, so
# removing it on a failed inspection destroys hours of work that cannot be
# fetched back; and for a downloadable image the curl below overwrites the
# target anyway, so a delete buys nothing there either. --force-share matches
# the bake's own inspection: without it qemu-img takes a lock and an image a
# running consumer is using is refused rather than described, which has nothing
# to do with the image being bad.
function verify_base_image {
    local info_output
    local info_rc

    if [[ -f "${BASE_IMAGE_FULL_PATH}" ]]; then
        printf "Base image: verifying... "
        info_rc=0
        info_output="$(qemu-img info --force-share "${BASE_IMAGE_FULL_PATH}" 2>&1)" \
            || info_rc=$?
        if [[ "${info_rc}" == "0" ]] && grep -q "file format: qcow2" <<< "${info_output}"; then
            printf "[OK]\n"
            return 0
        fi

        printf "[UNUSABLE]\n"
        printf "Error: base image %s did not verify.\n" "${BASE_IMAGE_FULL_PATH}" >&2
        printf "qemu-img: %s\n" "${info_output%%$'\n'*}" >&2
        if [[ -z "${BASE_URL}" ]]; then
            printf "Hint: this image is produced locally and has no download URL.\n" >&2
            printf "Hint: it was left in place; inspect it before re-baking.\n" >&2
            exit 1
        fi
        printf "Hint: re-downloading over it from %s\n" "${BASE_URL}" >&2
    fi

    if [[ -z "${BASE_URL}" ]]; then
        printf "Error: Base image %s not found and no download URL.\n" \
            "${BASE_IMAGE_FULL_PATH}" >&2
        # Provisioning never creates a missing baked pair on its own: the
        # selected environment must come from an existing valid image pair.
        printf "Hint: otherwise run the matching bin/bake_*_image.bash first.\n" >&2
        exit 1
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

    if ! IMAGE_WORKFLOW_RUN_ID="$(image_workflow_resolve_run_id \
        "${IMAGE_WORKFLOW_RUN_ID}")"; then
        printf "Error: failed to resolve image workflow run ID\n" >&2
        exit 1
    fi
    printf "Disk: copying independent qcow2... "
    image_workflow_copy_qcow2 "${BASE_IMAGE_FULL_PATH}" "${TARGET_DISK}" \
        "vm-disk" "${OS_TYPE}" "${IMAGE_WORKFLOW_RUN_ID}" "${BASE_IMAGE_NAME}" \
        || { printf "[FAILED]\n" >&2; exit 1; }
    printf "[OK]\n"
}

# --- Cloud-Init Seed Generation ---
function generate_seed {
    local pub_key_path=""
    local pub_key_data=""
    local seed_dir="${IMAGE_DIR}/${VM_NAME}.seed_staging"
    # Variants share the base OS cloud-init template (e.g. rocky8-iocrunner uses user-data.rocky8).
    local user_data_template="${SC_TOP}/templates/user-data.${OS_VARIANT}"

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

    # genisoimage writes its statistics to stderr even on success, so the
    # output is captured rather than discarded and replayed only on failure.
    # Discarding it left a failed run showing a truncated progress line and no
    # reason at all. The staging directory is deliberately left in place when
    # this fails: it holds the exact inputs that produced the failure.
    local iso_log
    iso_log="$(mktemp)"
    if ! genisoimage -output "${CLOUD_INIT_ISO}" \
        -volid cidata -joliet -rock \
        -input-charset utf-8 \
        -graft-points \
        "user-data=${seed_dir}/user-data" \
        "meta-data=${seed_dir}/meta-data" 2>"${iso_log}"; then
        printf "[FAILED]\n"
        printf "Error: cloud-init seed generation failed for %s\n" "${VM_NAME}" >&2
        sed 's/^/  genisoimage: /' "${iso_log}" >&2
        printf "Staging left for inspection: %s\n" "${seed_dir}" >&2
        rm -f -- "${iso_log}"
        exit 1
    fi
    rm -f -- "${iso_log}"

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
        --os-variant "${OSINFO_VARIANT:-${OS_VARIANT}}" \
        --graphics none \
        "${boot_args[@]+"${boot_args[@]}"}" \
        --noautoconsole
}

# --- Domain State Inspection ---
# Reports libvirt domain state without polling. Treats undefined domains as
# a first-class state so callers can branch without inspecting virsh exit codes.
# Reports the domain state as libvirt sees it, plus two states of our own.
# "not defined" means libvirt answered and has no such domain. "unavailable"
# means libvirt did not answer at all: domstate fails identically for both, so
# the connection is asked separately rather than assuming absence. Reporting an
# outage as absence would tell the operator to provision a VM that may already
# exist, and would let a stop exit 0 for a question nobody answered.
function get_domain_state {
    local state
    if state=$(virsh --connect "${LIBVIRT_URI}" domstate "${VM_NAME}" 2>/dev/null); then
        printf "%s\n" "${state}"
        return 0
    fi
    if virsh --connect "${LIBVIRT_URI}" uri >/dev/null 2>&1; then
        printf "not defined\n"
    else
        printf "unavailable\n"
    fi
}

# Resolves the runtime IP: prefers the statically reserved VM_IP, falls back
# to virsh domifaddr for DHCP-only nodes. Empty stdout means no IP yet.
function resolve_runtime_ip {
    if [[ -n "${VM_IP}" ]]; then
        printf "%s\n" "${VM_IP}"
        return 0
    fi
    virsh --connect "${LIBVIRT_URI}" domifaddr "${VM_NAME}" 2>/dev/null \
        | awk '/ipv4/ {print $4; exit}' | cut -d'/' -f1
}

# --- SSH Readiness Contract ---
# Readiness means a non-interactive, key-only login as SSH_USER that reaches
# remote command execution. BatchMode=yes removes password and keyboard-
# interactive authentication, so a probe can pass only with a usable key, and
# the probe runs a remote command rather than opening a socket. A first-time
# host key is accepted; a CHANGED host key is not, and StrictHostKeyChecking=no
# does not override that. That case means the address now answers for a
# different host, which is a different fact from "not ready yet", so ssh_probe
# reports it separately and the callers say so.
#
# Connection multiplexing is refused, not merely left unconfigured. An operator
# ssh_config that sets ControlMaster/ControlPath under Host * names its socket
# after the connection target, and this repository's VMs are destroyed and
# recreated at fixed addresses. A master left alive by a previous run then
# accepts the next run's first connection and fails mid-request behind it; ssh
# falls back to a direct connection and returns with O_NONBLOCK set on the
# caller's stdin, which it never clears. Ansible refuses to start on a
# non-blocking stdin, so the leak surfaces hours later at a bake's playbook
# step. Both options are needed: ControlPath=none stops this ssh from using a
# socket, ControlMaster=no stops it from becoming one for the next call.
declare -g SSH_USER="vmadmin"
declare -ag SSH_PROBE_OPTIONS=(
    -o StrictHostKeyChecking=no
    -o ConnectTimeout=5
    -o BatchMode=yes
    -o ControlMaster=no
    -o ControlPath=none
)

# Runs one remote command under the contract above and prints its stdout.
# Returns 0 on success, 2 when the stored host key conflicts, 1 otherwise.
function ssh_probe {
    local ip_addr="$1"
    shift
    local stderr_file
    local rc=0

    stderr_file="$(mktemp)"
    # shellcheck disable=SC2029
    # Client-side expansion is intended: callers pass a fixed remote command.
    ssh "${SSH_PROBE_OPTIONS[@]}" "${SSH_USER}@${ip_addr}" "$@" \
        2>"${stderr_file}" || rc=$?
    if [[ "${rc}" != "0" ]] && grep -qE \
        'REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed' \
        "${stderr_file}"; then
        rc=2
    fi
    rm -f -- "${stderr_file}"
    return "${rc}"
}

# Prints the operator-facing explanation and repair for a host-key conflict.
function report_host_key_conflict {
    local ip_addr="$1"

    printf "SSH: %s answers with a different host key than the stored one.\n" \
        "${ip_addr}"
    printf "SSH: repair with: ssh-keygen -f %s/.ssh/known_hosts -R %s\n" \
        "${HOME}" "${ip_addr}"
}

# Parses cloud-init status output from the command-line tool. The printed value
# is the operator-facing status field; the return code is success only for done.
function parse_cloud_init_status {
    local output="$1"
    local line
    local status="unknown"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == status:* ]]; then
            status="${line#status:}"
            status="${status#"${status%%[![:space:]]*}"}"
            status="${status%"${status##*[![:space:]]}"}"
            [[ -n "${status}" ]] || status="unknown"
            break
        fi
    done <<< "${output}"

    printf "%s\n" "${status}"
    [[ "${status}" == "done" ]]
}

# --- Status Report ---
# Single-pass diagnostic used by `-s` and the `<os>.<node>.status` make target.
# Always prints Domain / IP / SSH / cloud-init lines plus a summary block so
# operators see partial progress regardless of which stage is failing.
# Exit code is 0 only when domain is running, SSH succeeds, and cloud-init is done.
function print_status_report {
    local domain_state ip_addr ci_output ci_status
    local rc=0

    domain_state=$(get_domain_state)
    printf "Base image : %s (%s)\n" "${BASE_IMAGE_NAME}" "$(base_image_class)"
    printf "Domain     : %s\n" "${domain_state}"

    if [[ "${domain_state}" != "running" ]]; then
        printf "IP         : (n/a)\n"
        printf "SSH        : (n/a)\n"
        printf "cloud-init : (n/a)\n"
        printf "%s\n" "------------------------------------------------------------"
        printf "VM Name    : %s\n" "${VM_NAME}"
        case "${domain_state}" in
            "shut off")
                printf "Hint       : virsh -c %s start %s\n" "${LIBVIRT_URI}" "${VM_NAME}"
                ;;
            "not defined")
                printf "Hint       : run 'make %s.%s' to provision\n" "${OS_TYPE}" "${NODE_ID}"
                ;;
            unavailable)
                printf "Hint       : libvirt did not answer at %s; the domain was not checked\n" \
                    "${LIBVIRT_URI}"
                ;;
            *)
                printf "Hint       : run 'make %s.%s.clean' then re-run\n" "${OS_TYPE}" "${NODE_ID}"
                ;;
        esac
        printf "%s\n" "------------------------------------------------------------"
        return 1
    fi

    ip_addr=$(resolve_runtime_ip)
    if [[ -z "${ip_addr}" ]]; then
        printf "IP         : (not yet assigned)\n"
        printf "SSH        : (n/a)\n"
        printf "cloud-init : (n/a)\n"
        rc=1
    else
        printf "IP         : %s\n" "${ip_addr}"

        local probe_rc=0
        ssh_probe "${ip_addr}" "exit" >/dev/null || probe_rc=$?
        if [[ "${probe_rc}" == "0" ]]; then
            printf "SSH        : ready\n"
            ci_output=$(ssh_probe "${ip_addr}" "cloud-init status" || true)
            ci_status=$(parse_cloud_init_status "${ci_output}") || rc=1
            printf "cloud-init : %s\n" "${ci_status}"
        elif [[ "${probe_rc}" == "2" ]]; then
            printf "SSH        : host key mismatch\n"
            printf "cloud-init : (n/a)\n"
            report_host_key_conflict "${ip_addr}"
            rc=1
        else
            printf "SSH        : not available\n"
            printf "cloud-init : (n/a)\n"
            rc=1
        fi
    fi

    printf "%s\n" "------------------------------------------------------------"
    printf "VM Name    : %s\n" "${VM_NAME}"
    if [[ -n "${ip_addr}" ]]; then
        printf "IP Address : %s\n" "${ip_addr}"
        printf "SSH command: ssh vmadmin@%s\n" "${ip_addr}"
    fi
    printf "%s\n" "------------------------------------------------------------"

    return ${rc}
}

# --- VM Readiness Check ---
function wait_for_vm {
    local mode="${1:-retry}"
    local ip_addr="${VM_IP}"

    # Static IP: skip polling, go straight to readiness check
    if [[ -n "${ip_addr}" ]]; then
        wait_for_ssh "${ip_addr}" "${mode}" || return 1
        wait_for_cloud_init "${ip_addr}" "${mode}" || return 1

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
            wait_for_cloud_init "${ip_addr}" "${mode}" || return 1

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
    local probe_rc

    while [[ ${attempt} -lt ${max_retry} ]]; do
        probe_rc=0
        ssh_probe "${ip_addr}" "exit" >/dev/null || probe_rc=$?
        if [[ "${probe_rc}" == "0" ]]; then
            printf "SSH: ready [OK]\n"
            return 0
        fi

        # A changed host key will not resolve by waiting; retrying only spends
        # the budget and then blames the wrong thing.
        if [[ "${probe_rc}" == "2" ]]; then
            report_host_key_conflict "${ip_addr}"
            return 1
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
    # Budget covers a package-installing cloud-init: Rocky 8 spends its final
    # stage on dnf (gcc, make, openssl-devel) and has been measured at ~490s.
    local max_retry=20
    local interval=30
    local attempt=0
    local status
    local ci_status

    while [[ ${attempt} -lt ${max_retry} ]]; do
        status=$(ssh_probe "${ip_addr}" "cloud-init status" || true)

        if ci_status=$(parse_cloud_init_status "${status}"); then
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
    return 1
}

# --- Main ---
if [[ "${DO_CLEANUP}" == true ]]; then
    do_cleanup
    exit 0
fi

if [[ "${DO_STATUS}" == true ]]; then
    if print_status_report; then
        exit 0
    else
        exit 1
    fi
fi

if [[ "${DO_STOP}" == true ]]; then
    if do_stop; then
        exit 0
    else
        exit 1
    fi
fi

if [[ "${DO_FRESH}" == true ]]; then
    require_fresh_input || exit 1
fi

printf "%s\n" "------------------------------------------------------------"
printf "OS Type    : %s\n" "${OS_TYPE}"
printf "Node ID    : %s\n" "${NODE_ID}"
printf "VM Name    : %s\n" "${VM_NAME}"
printf "Storage    : %s\n" "${IMAGE_DIR}"
printf "Base image : %s (%s)\n" "${BASE_IMAGE_NAME}" "$(base_image_class)"
if [[ -n "${VM_IP}" ]]; then
    printf "IP Address : %s\n" "${VM_IP}"
    printf "MAC Address: %s\n" "${VM_MAC}"
fi
printf "%s\n" "------------------------------------------------------------"

# Existing-domain dispatch (no interactive menu — all states resolve automatically):
#   - shut off  -> auto start + readiness check (symmetric to "not defined -> auto provision")
#   - running   -> emit IP/SSH summary and exit 0 (idempotent, group targets flow through)
#   - other     -> abnormal state (paused, crashed, ...) — print state and exit 1;
#                  user reclaims via `make <os>.<node>.clean` then re-run
# Ask the connection before the dispatch: dominfo fails identically for an
# absent domain and an unreachable libvirt, and taking an outage for absence
# would start provisioning a VM that may already exist.
if [[ "$(get_domain_state)" == "unavailable" ]]; then
    printf "Error: libvirt did not answer at %s; nothing was created.\n" \
        "${LIBVIRT_URI}" >&2
    exit 1
fi

if virsh --connect "${LIBVIRT_URI}" dominfo "${VM_NAME}" >/dev/null 2>&1; then
    existing_state=$(get_domain_state)

    case "${existing_state}" in
        "shut off")
            printf "VM '%s' is shut off. Starting...\n" "${VM_NAME}"
            virsh --connect "${LIBVIRT_URI}" start "${VM_NAME}"
            wait_for_vm "retry" || exit 1
            printf "%s\n" "------------------------------------------------------------"
            printf "READY\n"
            printf "%s\n" "------------------------------------------------------------"
            exit 0
            ;;
        running)
            existing_ip=$(resolve_runtime_ip)
            printf "VM '%s' is already running.\n" "${VM_NAME}"
            printf "%s\n" "------------------------------------------------------------"
            printf "VM Name    : %s\n" "${VM_NAME}"
            if [[ -n "${existing_ip}" ]]; then
                printf "IP Address : %s\n" "${existing_ip}"
                printf "SSH command: ssh vmadmin@%s\n" "${existing_ip}"
            else
                printf "IP Address : (not yet assigned)\n"
            fi
            printf "%s\n" "------------------------------------------------------------"
            exit 0
            ;;
        *)
            printf "VM '%s' is in unexpected state: %s\n" "${VM_NAME}" "${existing_state}"
            printf "Hint       : run 'make %s.%s.clean' then re-run\n" "${OS_TYPE}" "${NODE_ID}"
            exit 1
            ;;
    esac
fi

verify_base_image
prepare_disk
generate_seed
register_dhcp
provision_vm
wait_for_vm "retry" || exit 1

printf "%s\n" "------------------------------------------------------------"
printf "READY\n"
printf "%s\n" "------------------------------------------------------------"
