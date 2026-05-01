#!/usr/bin/env bash
#
# Bake an EPICS ioc-runner test image from a standard cloud-provision VM.
# Boots a fresh testbed-<os>-server, applies ansible-provision's site.yml
# and 04_nfs_sim.yml, then captures the layered qcow2 disk into a flat
# ${IMAGE_DIR}/iocrunner-<os>.qcow2 ready to back the rocky8-iocrunner /
# debian13-iocrunner OS variants in cloud-provision.

set -e

declare -g SC_RPATH
declare -g SC_TOP

SC_RPATH="$(realpath "$0")"
SC_TOP="${SC_RPATH%/*}/.."
SC_TOP="$(realpath "${SC_TOP}")"

declare -g OS_TYPE=""
declare -g IMAGE_DIR="${IMAGE_DIR:-${HOME}/libvirt/images}"
declare -g ANSIBLE_DIR="${ANSIBLE_PROVISION_DIR:-${SC_TOP}/../ansible-provision}"
declare -g KEEP_VM=false
declare -g VM_PREFIX="testbed"
declare -g NODE_ID="server"
declare -g LIBVIRT_URI="qemu:///system"

function print_usage {
    printf "Usage: %s -o <os_type> [options]\n" "$(basename "$0")"
    printf "\n"
    printf "Bake a golden iocrunner-test image from a fresh cloud-provision VM.\n"
    printf "\n"
    printf "Required:\n"
    printf "  -o <os_type>    rocky8 or debian13\n"
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
    rocky8|debian13) ;;
    *) printf "Error: -o must be rocky8 or debian13 (got: %s)\n" "${OS_TYPE}" >&2; exit 1 ;;
esac

declare -g VM_NAME="${VM_PREFIX}-${OS_TYPE}-${NODE_ID}"
declare -g SOURCE_DISK="${IMAGE_DIR}/${VM_NAME}.qcow2"
declare -g OUTPUT_IMAGE="${IMAGE_DIR}/iocrunner-${OS_TYPE}.qcow2"
declare -g CREATE_VM="${SC_TOP}/bin/create_vm.bash"
declare -g ANSIBLE_PLAYBOOK_BIN

ANSIBLE_PLAYBOOK_BIN="$(command -v ansible-playbook || true)"

if [[ -z "${ANSIBLE_PLAYBOOK_BIN}" ]]; then
    printf "Error: ansible-playbook not found in PATH\n" >&2
    exit 1
fi

if [[ ! -d "${ANSIBLE_DIR}" ]]; then
    printf "Error: ansible-provision directory not found: %s\n" "${ANSIBLE_DIR}" >&2
    exit 1
fi

printf "%s\n" "------------------------------------------------------------"
printf "Bake: iocrunner-test image\n"
printf "  OS Type    : %s\n" "${OS_TYPE}"
printf "  Build VM   : %s\n" "${VM_NAME}"
printf "  Source disk: %s\n" "${SOURCE_DISK}"
printf "  Output     : %s\n" "${OUTPUT_IMAGE}"
printf "  Ansible    : %s\n" "${ANSIBLE_DIR}"
printf "%s\n" "------------------------------------------------------------"

# Step 1: create_vm.bash is idempotent — handles not-defined / shut off /
# running and polls until SSH + cloud-init are ready before returning.
printf "\nStep 1/6: Boot %s\n" "${VM_NAME}"
"${CREATE_VM}" -o "${OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}"

printf "\nStep 2/6: Refresh known_hosts for VM IP\n"
declare -g VM_IP
VM_IP="$("${CREATE_VM}" -o "${OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}" -s 2>/dev/null \
    | awk -F': *' '/^IP Address/ {print $2; exit}')"
if [[ -z "${VM_IP}" ]]; then
    printf "Error: failed to resolve VM IP\n" >&2
    exit 1
fi
ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "${VM_IP}" 2>/dev/null || true
ssh-keyscan -H "${VM_IP}" >> "${HOME}/.ssh/known_hosts" 2>/dev/null
printf "  VM_IP=%s [OK]\n" "${VM_IP}"

printf "\nStep 3/6: Apply ansible site.yml on %s\n" "${VM_NAME}"
( cd "${ANSIBLE_DIR}" && "${ANSIBLE_PLAYBOOK_BIN}" \
    -i inventory/testbed.ini --limit "${VM_NAME}" site.yml )

printf "\nStep 4/6: Apply 04_nfs_sim.yml on %s\n" "${VM_NAME}"
( cd "${ANSIBLE_DIR}" && "${ANSIBLE_PLAYBOOK_BIN}" \
    -i inventory/testbed.ini --limit "${VM_NAME}" playbooks/04_nfs_sim.yml )

printf "\nStep 5/6: Shutdown and flatten qcow2\n"
virsh --connect "${LIBVIRT_URI}" shutdown "${VM_NAME}" >/dev/null

declare -g attempt=0
declare -g state="unknown"
while [[ "${attempt}" -lt 24 ]]; do
    sleep 5
    state="$(virsh --connect "${LIBVIRT_URI}" domstate "${VM_NAME}" 2>/dev/null || printf "unknown\n")"
    if [[ "${state}" == "shut off" ]]; then
        printf "  VM shut off [OK]\n"
        break
    fi
    attempt=$(( attempt + 1 ))
done

if [[ "${state}" != "shut off" ]]; then
    printf "Error: VM did not shut down within 120s\n" >&2
    exit 1
fi

if [[ ! -f "${SOURCE_DISK}" ]]; then
    printf "Error: source disk missing: %s\n" "${SOURCE_DISK}" >&2
    exit 1
fi

printf "  qemu-img convert (flatten layered qcow2)...\n"
qemu-img convert -p -O qcow2 "${SOURCE_DISK}" "${OUTPUT_IMAGE}.tmp"
mv "${OUTPUT_IMAGE}.tmp" "${OUTPUT_IMAGE}"
printf "  Output: %s (%s)\n" "${OUTPUT_IMAGE}" "$(du -h "${OUTPUT_IMAGE}" | awk '{print $1}')"

printf "\nStep 6/6: Cleanup build VM\n"
if [[ "${KEEP_VM}" == true ]]; then
    printf "  Keeping build VM (use 'bin/create_vm.bash -o %s -n %s -c' to remove later)\n" \
        "${OS_TYPE}" "${NODE_ID}"
else
    "${CREATE_VM}" -o "${OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}" -c
fi

printf "%s\n" "------------------------------------------------------------"
printf "Bake complete: %s\n" "${OUTPUT_IMAGE}"
printf "Boot the variant: make %s-iocrunner.server\n" "${OS_TYPE}"
printf "%s\n" "------------------------------------------------------------"
