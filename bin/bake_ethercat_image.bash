#!/usr/bin/env bash
#
# Bake an EtherCAT/RT base image from a standard cloud-provision VM.
# Boots a run-specific testbed build VM, applies ansible-provision's
# 05_ethercat_base.yml (build toolchain, kernel headers, dkms, RT kernel +
# headers installed but NOT made the boot default), then converts the
# independent VM disk into ${IMAGE_DIR}/ethercat-<platform>-<run-id>.qcow2
# ready for the debian13-ethercat OS variant in cloud-provision.
#
# The RT kernel is installed but never selected as the boot default here: the
# ethercat-env repository treats kernel selection (rt.kernel.select) and
# post-reboot running-kernel confirmation as explicit operator / external-gate
# steps (decision D2 / milestone M16). The live app_ethercat run, not this
# image, drives the boot-default change.

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
declare -g VM_PREFIX="${VM_PREFIX:-testbed}"
declare -g NODE_ID="server"
declare -g IMAGE_WORKFLOW_RUN_ID="${IMAGE_WORKFLOW_RUN_ID:-}"
declare -g LIBVIRT_URI="qemu:///system"
# Ansible inventory for the playbook call; env-overridable per site.
declare -g INVENTORY="${BAKE_INVENTORY:-inventory/testbed.ini}"
declare -g MANIFEST_TEMP=""

function cleanup_output_temps {
    local rc=$?

    if [[ -n "${MANIFEST_TEMP}" ]]; then
        rm -f -- "${MANIFEST_TEMP}"
    fi
    return "${rc}"
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
declare -g ETHERCAT_BASE_PLAYBOOK="playbooks/05_ethercat_base.yml"
declare -g ANSIBLE_PLAYBOOK_BIN

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

if [[ ! -f "${ANSIBLE_DIR}/${ETHERCAT_BASE_PLAYBOOK}" ]]; then
    printf "Error: ethercat base playbook not found: %s\n" "${ANSIBLE_DIR}/${ETHERCAT_BASE_PLAYBOOK}" >&2
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
printf "\nStep 1/7: Boot %s\n" "${VM_NAME}"
"${CREATE_VM}" -o "${BUILD_OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}"

printf "\nStep 2/7: Refresh known_hosts for VM IP\n"
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

printf "\nStep 3/7: Stamp the bake manifest header\n"
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

printf "\nStep 4/7: Apply ansible %s on %s\n" "${ETHERCAT_BASE_PLAYBOOK}" "${VM_NAME}"
( cd "${ANSIBLE_DIR}" && "${ANSIBLE_PLAYBOOK_BIN}" \
    -i "${INVENTORY}" --limit "${VM_NAME}" "${ETHERCAT_BASE_PLAYBOOK}" )

printf "\nStep 5/7: De-proxy, verify, copy manifest sidecar\n"
ssh "${SSH_OPTIONS[@]}" "vmadmin@${VM_IP}" 'sudo sh -s' <<'DEPROXY'
set -e
[ -f /etc/dnf/dnf.conf ] && sed -i '/^proxy=/d' /etc/dnf/dnf.conf
rm -f /etc/apt/apt.conf.d/95proxy /etc/sudoers.d/95proxy \
      /etc/ssh/sshd_config.d/99proxy.conf /etc/pip.conf
sed -i '/[Pp][Rr][Oo][Xx][Yy]/d' /etc/environment
git config --system --unset-all http.proxy 2>/dev/null || true
git config --system --unset-all https.proxy 2>/dev/null || true
rm -f /root/.ssh/environment /home/*/.ssh/environment
DEPROXY
if ssh "${SSH_OPTIONS[@]}" "vmadmin@${VM_IP}" 'sudo sh -s' <<'REMNANT'
set -e
hits=0
[ -f /etc/dnf/dnf.conf ] && grep -qsi proxy /etc/dnf/dnf.conf && hits=1
ls /etc/apt/apt.conf.d/95proxy /etc/sudoers.d/95proxy \
   /etc/ssh/sshd_config.d/99proxy.conf /etc/pip.conf \
   /root/.ssh/environment /home/*/.ssh/environment 2>/dev/null | grep -q . && hits=1
grep -qsi proxy /etc/environment && hits=1
git config --system --get-regexp proxy >/dev/null 2>&1 && hits=1
exit ${hits}
REMNANT
then
    printf "  de-proxy verified: no remnants [OK]\n"
else
    printf "Error: proxy remnants survived the de-proxy step\n" >&2
    exit 1
fi
MANIFEST_TEMP="${OUTPUT_IMAGE}.manifest.tmp"
ssh "${SSH_OPTIONS[@]}" "vmadmin@${VM_IP}" 'sudo cat /etc/ethercat-bake.manifest' > "${MANIFEST_TEMP}"
printf "  manifest copied to sidecar [OK]\n"

printf "\nStep 6/7: Shutdown and copy qcow2\n"
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

printf "  qemu-img convert (independent copy)...\n"
image_workflow_copy_qcow2 "${SOURCE_DISK}" "${OUTPUT_IMAGE}" \
    "ethercat" "${OS_TYPE}" "${IMAGE_WORKFLOW_RUN_ID}" "${SOURCE_DISK##*/}" \
    || { printf "Error: failed to publish image copy: %s\n" "${OUTPUT_IMAGE}" >&2; exit 1; }
mv "${MANIFEST_TEMP}" "${OUTPUT_IMAGE}.manifest"
MANIFEST_TEMP=""
printf "  Output: %s (%s)\n" "${OUTPUT_IMAGE}" "$(du -h "${OUTPUT_IMAGE}" | awk '{print $1}')"
printf "  Manifest sidecar: %s\n" "${OUTPUT_IMAGE}.manifest"

printf "\nStep 7/7: Cleanup build VM\n"
if [[ "${KEEP_VM}" == true ]]; then
    printf "  Keeping build VM (use 'bin/create_vm.bash -o %s -n %s -c' to remove later)\n" \
        "${BUILD_OS_TYPE}" "${NODE_ID}"
else
    "${CREATE_VM}" -o "${BUILD_OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}" -c
fi

printf "%s\n" "------------------------------------------------------------"
printf "Bake complete: %s\n" "${OUTPUT_IMAGE}"
printf "Boot the variant: make %s-ethercat.server\n" "${OS_TYPE}"
printf "%s\n" "------------------------------------------------------------"
