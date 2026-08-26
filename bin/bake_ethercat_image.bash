#!/usr/bin/env bash
#
# Bake an EtherCAT/RT base image from a standard cloud-provision VM.
# Boots a run-specific lab build VM, applies ansible-provision's
# rtbase species assembly (build toolchain, kernel headers, dkms, RT kernel +
# headers installed but NOT made the boot default), then converts the
# independent VM disk into ${IMAGE_DIR}/ethercat-<platform>-<run-id>.qcow2
# ready for the debian13-ethercat OS variant in cloud-provision.
#
# The RT kernel is installed but never selected as the boot default here: the
# ethercat-env repository treats kernel selection (rt.kernel.select) and
# post-reboot running-kernel confirmation as explicit operator / external-gate
# steps. The live app_ethercat run, not this image, drives the boot-default
# change.

set -e

declare -g SC_RPATH
declare -g SC_TOP

SC_RPATH="$(realpath "$0")"
SC_TOP="${SC_RPATH%/*}/.."
SC_TOP="$(realpath "${SC_TOP}")"
source "${SC_TOP}/bin/image_workflow.bash"

declare -g OS_TYPE=""
declare -g IMAGE_DIR="${IMAGE_DIR:-${HOME}/libvirt/images}"
declare -g ANSIBLE_DIR="${ANSIBLE_PROVISION_DIR:-${SC_TOP}/../ansible-provision}"
declare -g KEEP_VM=false
declare -g VM_PREFIX="${VM_PREFIX:-lab}"
declare -g NODE_ID="build"
declare -g IMAGE_WORKFLOW_RUN_ID="${IMAGE_WORKFLOW_RUN_ID:-}"
declare -g LIBVIRT_URI="qemu:///system"
# Ansible inventory for the playbook call; env-overridable per site.
declare -g INVENTORY="${BAKE_INVENTORY:-inventory/lab.ini}"
declare -g ANSIBLE_USER="vmadmin"
declare -g RUNTIME_INVENTORY=""
declare -g MANIFEST_TEMP=""

function cleanup_output_temps {
    local rc=$?

    if [[ -n "${RUNTIME_INVENTORY}" ]]; then
        rm -f -- "${RUNTIME_INVENTORY}"
    fi
    if [[ -n "${MANIFEST_TEMP}" ]]; then
        rm -f -- "${MANIFEST_TEMP}"
    fi
    return "${rc}"
}

function seal_proxy_contract {
    ssh "${SSH_OPTIONS[@]}" "vmadmin@${VM_IP}" \
        'sudo /bin/bash -p -s -- seal' < "${PROXY_CONTRACT}"
    SEALED_VM_NAME="${VM_NAME}"
    SEALED_SOURCE_DISK="${SOURCE_DISK}"
}

# Connection multiplexing is refused for every ssh this bake makes. An operator
# ssh_config that sets ControlMaster/ControlPath under Host * names its socket
# after the connection target, and the build VM is destroyed and recreated at a
# fixed address. A master left alive by a previous bake then accepts this run's
# first connection and fails mid-request behind it; ssh falls back to a direct
# connection and returns with O_NONBLOCK set on the caller's stdin, which it
# never clears. Ansible refuses to start on a non-blocking stdin, so a leak at
# step 2 or 3 fails the playbook at step 4 with no visible link back. Both
# options are needed: ControlPath=none stops this ssh from using a socket,
# ControlMaster=no stops it from becoming one for the next call. Stated here
# and in bin/create_vm.bash; ARCHITECTURE section 13 holds the contract.
declare -ag SSH_OPTIONS=(
    -o ControlMaster=no
    -o ControlPath=none
)

function print_usage {
    printf "Usage: %s -o <os_type> [options]\n" "$(basename "$0")"
    printf "\n"
    printf "Bake a golden ethercat base image from a fresh cloud-provision VM.\n"
    printf "\n"
    printf "Required:\n"
    printf "  -o <os_type>    debian13 (EtherCAT is Debian 13 only)\n"
    printf "\n"
    printf "Options:\n"
    printf "  -d <image_dir>  Image storage (default: %s)\n" "${IMAGE_DIR}"
    printf "  -a <dir>        ansible-provision directory (default: %s)\n" "${ANSIBLE_DIR}"
    printf "  -k              Keep the build VM after bake (default: destroy)\n"
    printf "  -h              Show this help\n"
}

while getopts ":o:d:a:kh" opt; do
    case "${opt}" in
        o) OS_TYPE="${OPTARG}" ;;
        d) IMAGE_DIR="${OPTARG}" ;;
        a) ANSIBLE_DIR="${OPTARG}" ;;
        k) KEEP_VM=true ;;
        h) print_usage; exit 0 ;;
        :) printf "Error: -%s requires an argument\n" "${OPTARG}" >&2; exit 1 ;;
        ?) printf "Error: Unknown option -%s\n" "${OPTARG}" >&2; exit 1 ;;
    esac
done

if [[ -z "${OS_TYPE}" ]]; then
    printf "Error: -o <os_type> is required\n" >&2
    print_usage >&2
    exit 1
fi

case "${OS_TYPE}" in
    debian13) ;;
    *) printf "Error: -o must be debian13 (EtherCAT is Debian 13 only; got: %s)\n" "${OS_TYPE}" >&2; exit 1 ;;
esac

# The build VM is created from a PINNED Debian release base (create_vm.bash
# debian13-rtbase), not the moving shared "debian13" daily image, so kernel
# headers resolve at build time. The output name is selected by the shared
# image workflow and is resolved by create_vm.bash through its creation record.
declare -g BUILD_OS_TYPE="${OS_TYPE}-rtbase"
declare -g CREATE_VM="${SC_TOP}/bin/create_vm.bash"
declare -g INVENTORY_GENERATOR="${SC_TOP}/bin/generate_ansible_inventory.bash"
declare -g PROXY_CONTRACT="${SC_TOP}/bin/proxy_contract.bash"
declare -g ETHERCAT_BASE_PLAYBOOK="playbooks/species/rtbase.yml"
declare -g ANSIBLE_PLAYBOOK_BIN
declare -g INVENTORY_PATH
declare -g SEALED_VM_NAME=""
declare -g SEALED_SOURCE_DISK=""

if [[ "${INVENTORY}" == /* ]]; then
    INVENTORY_PATH="${INVENTORY}"
else
    INVENTORY_PATH="${ANSIBLE_DIR}/${INVENTORY}"
fi

if ! IMAGE_WORKFLOW_RUN_ID="$(image_workflow_resolve_run_id \
    "${IMAGE_WORKFLOW_RUN_ID}")"; then
    printf "Error: IMAGE_WORKFLOW_RUN_ID must match YYYYMMDDTHHMMSSZ-<12 lowercase hex>\n" >&2
    exit 1
fi
NODE_ID="build"
export IMAGE_WORKFLOW_RUN_ID
if ! VM_NAME="$(image_workflow_vm_name \
    "${VM_PREFIX}" "${BUILD_OS_TYPE}" "${NODE_ID}" \
    "${IMAGE_WORKFLOW_RUN_ID}")"; then
    printf "Error: failed to resolve build VM name\n" >&2
    exit 1
fi
if ! SOURCE_DISK="$(image_workflow_vm_disk_path \
    "${IMAGE_DIR}" "${VM_PREFIX}" "${BUILD_OS_TYPE}" "${NODE_ID}" \
    "${IMAGE_WORKFLOW_RUN_ID}")"; then
    printf "Error: failed to resolve build VM disk path\n" >&2
    exit 1
fi
declare -g OUTPUT_IMAGE
if ! OUTPUT_IMAGE="${IMAGE_DIR}/$(image_workflow_image_name \
    "ethercat" "${OS_TYPE}" "${IMAGE_WORKFLOW_RUN_ID}")"; then
    printf "Error: failed to resolve EtherCAT image name\n" >&2
    exit 1
fi
trap cleanup_output_temps EXIT

ANSIBLE_PLAYBOOK_BIN="$(command -v ansible-playbook || true)"

if [[ -z "${ANSIBLE_PLAYBOOK_BIN}" ]]; then
    printf "Error: ansible-playbook not found in PATH\n" >&2
    exit 1
fi

if [[ ! -d "${ANSIBLE_DIR}" ]]; then
    printf "Error: ansible-provision directory not found: %s\n" "${ANSIBLE_DIR}" >&2
    exit 1
fi

if [[ ! -x "${INVENTORY_GENERATOR}" ]]; then
    printf "Error: inventory generator is not executable: %s\n" \
        "${INVENTORY_GENERATOR}" >&2
    exit 1
fi

if [[ ! -f "${INVENTORY_PATH}" ]]; then
    printf "Error: inventory not found: %s\n" "${INVENTORY_PATH}" >&2
    exit 1
fi

if [[ ! -f "${ANSIBLE_DIR}/${ETHERCAT_BASE_PLAYBOOK}" ]]; then
    printf "Error: ethercat base playbook not found: %s\n" "${ANSIBLE_DIR}/${ETHERCAT_BASE_PLAYBOOK}" >&2
    exit 1
fi
if [[ ! -f "${PROXY_CONTRACT}" ]]; then
    printf "Error: proxy contract not found: %s\n" "${PROXY_CONTRACT}" >&2
    exit 1
fi

printf "%s\n" "------------------------------------------------------------"
printf "Bake: ethercat base image\n"
printf "  OS Type    : %s\n" "${OS_TYPE}"
printf "  Build base : %s (pinned release)\n" "${BUILD_OS_TYPE}"
printf "  Build VM   : %s\n" "${VM_NAME}"
printf "  Source disk: %s\n" "${SOURCE_DISK}"
printf "  Output     : %s\n" "${OUTPUT_IMAGE}"
printf "  Ansible    : %s\n" "${ANSIBLE_DIR}"
printf "  Playbook   : %s\n" "${ETHERCAT_BASE_PLAYBOOK}"
printf "%s\n" "------------------------------------------------------------"

# Step 1: create_vm.bash creates a run-specific build VM and polls until SSH
# and cloud-init are ready before returning.
printf "\nStep 1/8: Boot %s\n" "${VM_NAME}"
"${CREATE_VM}" -o "${BUILD_OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}"

printf "\nStep 2/8: Refresh known_hosts for VM IP\n"
declare -g VM_IP
VM_IP="$("${CREATE_VM}" -o "${BUILD_OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}" -s 2>/dev/null \
    | awk -F': *' '/^IP Address/ {print $2; exit}')"
if [[ -z "${VM_IP}" ]]; then
    printf "Error: failed to resolve VM IP\n" >&2
    exit 1
fi
ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "${VM_IP}" 2>/dev/null || true
ssh-keyscan -H "${VM_IP}" >> "${HOME}/.ssh/known_hosts" 2>/dev/null
printf "  VM_IP=%s [OK]\n" "${VM_IP}"
RUNTIME_INVENTORY="$(mktemp /tmp/cloud-provision-ansible-inventory.XXXXXX)"
if ! "${INVENTORY_GENERATOR}" \
    --vm-name "${VM_NAME}" \
    --address "${VM_IP}" \
    --os-type "${BUILD_OS_TYPE}" \
    --species rtbase \
    --ansible-user "${ANSIBLE_USER}" > "${RUNTIME_INVENTORY}"; then
    printf "Error: failed to generate runtime inventory\n" >&2
    exit 1
fi
printf "  runtime inventory for %s [OK]\n" "${VM_NAME}"

printf "\nStep 3/8: Stamp the bake manifest header\n"
declare -g CLOUD_HEAD ANSIBLE_HEAD
CLOUD_HEAD="$(git -C "${SC_TOP}" rev-parse HEAD 2>/dev/null || printf unknown)"
[[ -n "$(git -C "${SC_TOP}" status --porcelain 2>/dev/null)" ]] && CLOUD_HEAD="${CLOUD_HEAD}-dirty"
ANSIBLE_HEAD="$(git -C "${ANSIBLE_DIR}" rev-parse HEAD 2>/dev/null || printf unknown)"
[[ -n "$(git -C "${ANSIBLE_DIR}" status --porcelain 2>/dev/null)" ]] && ANSIBLE_HEAD="${ANSIBLE_HEAD}-dirty"
# shellcheck disable=SC2087
ssh "${SSH_OPTIONS[@]}" "vmadmin@${VM_IP}" "sudo tee /etc/ethercat-bake.manifest >/dev/null" <<MANIFEST
# ethercat golden bake manifest
bake_date $(date -u +%FT%TZ)
cloud-provision ${CLOUD_HEAD}
ansible-provision ${ANSIBLE_HEAD}
MANIFEST
printf "  manifest header stamped [OK]\n"

printf "\nStep 4/8: Apply ansible %s on %s\n" "${ETHERCAT_BASE_PLAYBOOK}" "${VM_NAME}"
( cd "${ANSIBLE_DIR}" && "${ANSIBLE_PLAYBOOK_BIN}" \
    -i "${INVENTORY_PATH}" -i "${RUNTIME_INVENTORY}" \
    --limit "${VM_NAME}" "${ETHERCAT_BASE_PLAYBOOK}" )

printf "\nStep 5/8: Extract and validate the manifest sidecar\n"
MANIFEST_TEMP="${OUTPUT_IMAGE}.manifest.tmp"
ssh "${SSH_OPTIONS[@]}" "vmadmin@${VM_IP}" 'sudo cat /etc/ethercat-bake.manifest' > "${MANIFEST_TEMP}"
if [[ "$(grep -Fxc '# ethercat golden bake manifest' "${MANIFEST_TEMP}")" != "1" ||
      "$(grep -c '^bake_date ' "${MANIFEST_TEMP}")" != "1" ||
      "$(grep -c '^cloud-provision ' "${MANIFEST_TEMP}")" != "1" ||
      "$(grep -c '^ansible-provision ' "${MANIFEST_TEMP}")" != "1" ]]; then
    printf "Error: EtherCAT manifest sidecar validation failed\n" >&2
    exit 1
fi
printf "  manifest copied to sidecar [OK]\n"

printf "\nStep 6/8: Seal the current proxy artifact contract\n"
seal_proxy_contract
printf "  terminal proxy seal complete [OK]\n"

printf "\nStep 7/8: Shutdown and copy qcow2\n"
if [[ "${SEALED_VM_NAME}" != "${VM_NAME}" ||
      "${SEALED_SOURCE_DISK}" != "${SOURCE_DISK}" ]]; then
    printf "Error: terminal seal state does not match the exact build VM and disk\n" >&2
    exit 1
fi
"${CREATE_VM}" -o "${BUILD_OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" \
    -p "${VM_PREFIX}" -S
if [[ "$(virsh --connect "${LIBVIRT_URI}" domstate "${VM_NAME}")" != "shut off" ]]; then
    printf "Error: exact build VM is not shut off after the shared stop\n" >&2
    exit 1
fi
if [[ ! -f "${SOURCE_DISK}" || -L "${SOURCE_DISK}" ]]; then
    printf "Error: exact stopped source disk is missing or not a regular file: %s\n" \
        "${SOURCE_DISK}" >&2
    exit 1
fi

printf "  qemu-img convert (independent copy)...\n"
image_workflow_copy_qcow2 "${SOURCE_DISK}" "${OUTPUT_IMAGE}" \
    "ethercat" "${OS_TYPE}" "${IMAGE_WORKFLOW_RUN_ID}" "${SOURCE_DISK##*/}" \
    || { printf "Error: failed to publish image copy: %s\n" "${OUTPUT_IMAGE}" >&2; exit 1; }
mv "${MANIFEST_TEMP}" "${OUTPUT_IMAGE}.manifest"
MANIFEST_TEMP=""
printf "  Output: %s (%s)\n" "${OUTPUT_IMAGE}" "$(du -h "${OUTPUT_IMAGE}" | awk '{print $1}')"
printf "  Manifest sidecar: %s\n" "${OUTPUT_IMAGE}.manifest"

printf "\nStep 8/8: Cleanup build VM\n"
if [[ "${KEEP_VM}" == true ]]; then
    printf "  Keeping build VM (use 'bin/create_vm.bash -o %s -n %s -c' to remove later)\n" \
        "${BUILD_OS_TYPE}" "${NODE_ID}"
else
    "${CREATE_VM}" -o "${BUILD_OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}" -c
fi

printf "%s\n" "------------------------------------------------------------"
printf "Bake complete: %s\n" "${OUTPUT_IMAGE}"
printf "Boot the variant: make %s-ethercat.main\n" "${OS_TYPE}"
printf "%s\n" "------------------------------------------------------------"
