#!/usr/bin/env bash
#
# Builds and validates an independent IOC runner image from a run-specific VM.

set -euo pipefail

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
declare -g IOC_RUNNER_VERSION=""
declare -g IOC_RUNNER_VERSION_GIVEN=false
declare -g VM_PREFIX="${VM_PREFIX:-testbed}"
declare -g NODE_ID="server"
declare -g IMAGE_WORKFLOW_RUN_ID="${IMAGE_WORKFLOW_RUN_ID:-}"
declare -g INVENTORY="${BAKE_INVENTORY:-inventory/testbed.ini}"
declare -g ANSIBLE_USER="vmadmin"
declare -g LIBVIRT_URI="qemu:///system"
declare -g VM_IP=""
declare -g RUNTIME_INVENTORY=""
declare -g INVENTORY_GENERATOR="${SC_TOP}/bin/generate_ansible_inventory.bash"
declare -g PROXY_CONTRACT="${SC_TOP}/bin/proxy_contract.bash"
declare -g OUTPUT_TEMP_CREATED=false
declare -g SIDECAR_TEMP_CREATED=false
declare -g SEALED_VM_NAME=""
declare -g SEALED_SOURCE_DISK=""

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

function die {
    printf "Error: %s\n" "$*" >&2
    exit 1
}

function print_usage {
    printf "Usage: %s -o <os_type> [options]\n" "$(basename "$0")"
    printf "\n"
    printf "Bake a validated golden IOC runner image from a fresh VM.\n"
    printf "\n"
    printf "Required:\n"
    printf "  -o <os_type>    rocky8 or debian13\n"
    printf "\n"
    printf "Options:\n"
    printf "  -d <image_dir>  Image storage (default: %s)\n" "${IMAGE_DIR}"
    printf "  -a <dir>        ansible-provision directory (default: %s)\n" "${ANSIBLE_DIR}"
    printf "  -k              Keep the build VM after bake (default: destroy)\n"
    printf "  -r <ref>        Pin the epics-ioc-runner version baked into the image.\n"
    printf "                  Unset bakes whatever the inventory resolves to.\n"
    printf "  -h              Show this help\n"
}

function require_command {
    local command_name="$1"
    local command_path

    command_path="$(command -v "${command_name}" 2>/dev/null || true)"
    [[ -n "${command_path}" && -x "${command_path}" ]] \
        || die "required command not found: ${command_name}"
}

# A failed bake leaves the build VM running and half-provisioned so it can be
# inspected. docs/RUNBOOK_BAKE.md tells the reader to run the printed cleanup
# command; nothing was printed, and that runbook is read by agents working from
# a log more often than by operators at a terminal. The run-specific VM name
# makes the domain query unambiguous for this bake.
function report_build_vm_on_failure {
    local rc="$1"

    [[ "${rc}" != "0" ]] || return 0
    [[ -n "${VM_NAME:-}" ]] || return 0
    virsh --connect "${LIBVIRT_URI}" domstate "${VM_NAME}" >/dev/null 2>&1 || return 0

    printf "\nBuild VM %s was left for inspection. To restart clean:\n" \
        "${VM_NAME}" >&2
    printf "  IMAGE_WORKFLOW_RUN_ID=%q %s -o %s -n %s -d %s -p %s -c\n" \
        "${IMAGE_WORKFLOW_RUN_ID}" "${CREATE_VM}" "${OS_TYPE}" "${NODE_ID}" \
        "${IMAGE_DIR}" "${VM_PREFIX}" >&2
}

function cleanup_output_temps {
    local rc=$?

    if [[ -n "${RUNTIME_INVENTORY}" ]]; then
        rm -f -- "${RUNTIME_INVENTORY}"
    fi
    if [[ "${OUTPUT_TEMP_CREATED}" == true ]]; then
        rm -f -- "${OUTPUT_TEMP}"
    fi
    if [[ "${SIDECAR_TEMP_CREATED}" == true ]]; then
        rm -f -- "${SIDECAR_TEMP}"
    fi
    report_build_vm_on_failure "${rc}"
    return "${rc}"
}

function write_runtime_inventory {
    RUNTIME_INVENTORY="$(mktemp /tmp/cloud-provision-ansible-inventory.XXXXXX)" \
        || die "failed to create runtime inventory"
    if ! "${INVENTORY_GENERATOR}" \
        --vm-name "${VM_NAME}" \
        --address "${VM_IP}" \
        --os-type "${OS_TYPE}" \
        --role ioc-runner-build \
        --ansible-user "${ANSIBLE_USER}" > "${RUNTIME_INVENTORY}"; then
        rm -f -- "${RUNTIME_INVENTORY}"
        RUNTIME_INVENTORY=""
        die "failed to generate runtime inventory"
    fi
    [[ -s "${RUNTIME_INVENTORY}" ]] || die "runtime inventory is empty"
}

function repository_identity {
    local repository="$1"
    local identity

    identity="$(git -C "${repository}" rev-parse --verify HEAD)"
    [[ "${identity}" =~ ^[0-9a-f]{40}$ ]] \
        || die "repository HEAD is not a 40-hex commit: ${repository}"
    if [[ -n "$(git -C "${repository}" status --porcelain=v1 --untracked-files=normal)" ]]; then
        identity+="-dirty"
    fi
    printf "%s\n" "${identity}"
}

function stamp_manifest_header {
    local bake_date="$1"
    local cloud_head="$2"
    local ansible_head="$3"
    local epics_env_version="$4"
    local epics_base_version="$5"
    local base_name="$6"
    local base_digest="$7"
    local remote_command

    printf -v remote_command \
        'sudo /bin/bash -p -s -- %q %q %q %q %q %q %q %q' \
        "${bake_date}" "${OS_TYPE}" "${cloud_head}" "${ansible_head}" \
        "${epics_env_version}" "${epics_base_version}" "${base_name}" "${base_digest}"

    # shellcheck disable=SC2029
    ssh "${SSH_OPTIONS[@]}" "vmadmin@${VM_IP}" "${remote_command}" <<'REMOTE_MANIFEST'
if [[ ! -o privileged ]]; then
    printf "%s\n" "error: privileged Bash mode is required" >&2
    exit 1
fi
set -euo pipefail
unset BASH_ENV ENV CDPATH
unset TMPDIR TMP TEMP
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export LC_ALL=C
target="/etc/iocrunner-bake.manifest"
parent="${target%/*}"
[[ "${EUID}" == "0" ]]
[[ -d "${parent}" && ! -L "${parent}" ]]
[[ "$(stat -Lc '%u' "${parent}")" == "0" ]]
mode="$(stat -Lc '%a' "${parent}")"
(( (8#${mode} & 8#022) == 0 ))
if [[ -e "${target}" || -L "${target}" ]]; then
    [[ -f "${target}" && ! -L "${target}" ]]
fi
tmp="$(mktemp "${parent}/.iocrunner-bake.manifest.tmp.XXXXXX")"
trap 'rm -f -- "${tmp}"' EXIT HUP INT TERM
printf "%s\n" \
    "# iocrunner golden bake manifest" \
    "manifest_schema 1" \
    "bake_date $1" \
    "os_type $2" \
    "cloud-provision $3" \
    "ansible-provision $4" \
    "epics_env_version $5" \
    "epics_base_version $6" \
    "base_image schema=1 name=$7 sha256=$8" > "${tmp}"
chown 0:0 "${tmp}"
chmod 0644 "${tmp}"
mv -f -- "${tmp}" "${target}"
trap - EXIT HUP INT TERM
REMOTE_MANIFEST
}

function append_pip_provenance {
    ssh "${SSH_OPTIONS[@]}" "vmadmin@${VM_IP}" 'sudo /bin/bash -p -s' <<'REMOTE_PIP'
if [[ ! -o privileged ]]; then
    printf "%s\n" "error: privileged Bash mode is required" >&2
    exit 1
fi
set -euo pipefail
unset BASH_ENV ENV CDPATH
unset TMPDIR TMP TEMP
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export LC_ALL=C
manifest="/etc/iocrunner-bake.manifest"
[[ "${EUID}" == "0" ]]
[[ -f "${manifest}" && ! -L "${manifest}" ]]
package_tmp="$(mktemp /etc/.iocrunner-pip-freeze.tmp.XXXXXX)"
manifest_tmp="$(mktemp /etc/.iocrunner-bake.manifest.tmp.XXXXXX)"
trap 'rm -f -- "${package_tmp}" "${manifest_tmp}"' EXIT HUP INT TERM
pip3 freeze > "${package_tmp}"
[[ -s "${package_tmp}" ]]
awk '$1 != "pip3" {print}' "${manifest}" > "${manifest_tmp}"
sed 's/^/pip3 /' "${package_tmp}" >> "${manifest_tmp}"
[[ -s "${manifest_tmp}" ]]
chown 0:0 "${manifest_tmp}"
chmod 0644 "${manifest_tmp}"
mv -f -- "${manifest_tmp}" "${manifest}"
trap - EXIT HUP INT TERM
rm -f -- "${package_tmp}"
REMOTE_PIP
}

function seal_proxy_contract {
    ssh "${SSH_OPTIONS[@]}" "vmadmin@${VM_IP}" \
        'sudo /bin/bash -p -s -- seal' < "${PROXY_CONTRACT}"
    SEALED_VM_NAME="${VM_NAME}"
    SEALED_SOURCE_DISK="${SOURCE_DISK}"
}

while getopts ":o:d:a:kr:h" opt; do
    case "${opt}" in
        o) OS_TYPE="${OPTARG}" ;;
        d) IMAGE_DIR="${OPTARG}" ;;
        a) ANSIBLE_DIR="${OPTARG}" ;;
        k) KEEP_VM=true ;;
        r) IOC_RUNNER_VERSION="${OPTARG}"; IOC_RUNNER_VERSION_GIVEN=true ;;
        h) print_usage; exit 0 ;;
        :) die "-${OPTARG} requires an argument" ;;
        ?) die "unknown option -${OPTARG}" ;;
    esac
done

[[ -n "${OS_TYPE}" ]] || die "-o <os_type> is required"
case "${OS_TYPE}" in
    rocky8|debian13) ;;
    *) die "-o must be rocky8 or debian13 (got: ${OS_TYPE})" ;;
esac

for command_name in ansible-playbook awk du git mktemp mv qemu-img realpath sed \
                    sha256sum ssh ssh-keygen ssh-keyscan virsh; do
    require_command "${command_name}"
done

if [[ "${IOC_RUNNER_VERSION_GIVEN}" == true ]]; then
    # -r with an empty value is rejected rather than treated as unset. An
    # operator writing -r "${SOME_VAR}" against an unset variable would
    # otherwise get an unpinned bake and learn about it hours later, from a
    # manifest with no requested field.
    [[ -n "${IOC_RUNNER_VERSION}" ]] || die "-r requires a non-empty ref"
    # getopts takes whatever token follows -r as its value, so a forgotten
    # value swallows the next flag: -r -k yields ref "-k", which the character
    # class below would accept. No Git ref starts with a dash, so refusing the
    # shape catches the mistake instead of pinning the bake to "-k".
    [[ "${IOC_RUNNER_VERSION}" != -* ]] \
        || die "invalid ioc-runner ref (starts with -): ${IOC_RUNNER_VERSION}"
    # A ref reaches Ansible as an extra variable and ends up in the manifest, so
    # it is constrained to what a Git ref can contain. Rejecting here keeps a
    # malformed value out of both.
    [[ "${IOC_RUNNER_VERSION}" =~ ^[A-Za-z0-9._/-]+$ ]] \
        || die "invalid ioc-runner ref: ${IOC_RUNNER_VERSION}"
fi

[[ -d "${IMAGE_DIR}" ]] || die "image directory not found: ${IMAGE_DIR}"
[[ -d "${ANSIBLE_DIR}" ]] || die "ansible-provision directory not found: ${ANSIBLE_DIR}"
IMAGE_DIR="$(realpath "${IMAGE_DIR}")"
ANSIBLE_DIR="$(realpath "${ANSIBLE_DIR}")"

if ! IMAGE_WORKFLOW_RUN_ID="$(image_workflow_resolve_run_id \
    "${IMAGE_WORKFLOW_RUN_ID}")"; then
    die "IMAGE_WORKFLOW_RUN_ID must match YYYYMMDDTHHMMSSZ-<12 lowercase hex>"
fi
NODE_ID="build"
export IMAGE_WORKFLOW_RUN_ID
if ! OUTPUT_IMAGE="${IMAGE_DIR}/$(image_workflow_image_name \
    "iocrunner" "${OS_TYPE}" "${IMAGE_WORKFLOW_RUN_ID}")"; then
    die "failed to resolve ioc-runner image name"
fi
OUTPUT_TEMP="${OUTPUT_IMAGE}.tmp"
SIDECAR="${OUTPUT_IMAGE}.manifest"
SIDECAR_TEMP="${SIDECAR}.tmp"
if ! VM_NAME="$(image_workflow_vm_name \
    "${VM_PREFIX}" "${OS_TYPE}" "${NODE_ID}" \
    "${IMAGE_WORKFLOW_RUN_ID}")"; then
    die "failed to resolve build VM name"
fi
if ! SOURCE_DISK="$(image_workflow_vm_disk_path \
    "${IMAGE_DIR}" "${VM_PREFIX}" "${OS_TYPE}" "${NODE_ID}" \
    "${IMAGE_WORKFLOW_RUN_ID}")"; then
    die "failed to resolve build VM disk path"
fi
declare -g SOURCE_RECORD=""
declare -g BAKE_DATE=""
declare -g CREATE_VM="${SC_TOP}/bin/create_vm.bash"
declare -g VALIDATOR="${SC_TOP}/bin/validate_iocrunner_bake.bash"
declare -g INVENTORY_PATH

if [[ "${INVENTORY}" == /* ]]; then
    INVENTORY_PATH="${INVENTORY}"
else
    INVENTORY_PATH="${ANSIBLE_DIR}/${INVENTORY}"
fi

[[ -x "${CREATE_VM}" ]] || die "create_vm.bash is not executable: ${CREATE_VM}"
[[ -x "${INVENTORY_GENERATOR}" ]] \
    || die "inventory generator is not executable: ${INVENTORY_GENERATOR}"
[[ -f "${VALIDATOR}" ]] || die "validator not found: ${VALIDATOR}"
[[ -f "${PROXY_CONTRACT}" ]] || die "proxy contract not found: ${PROXY_CONTRACT}"
[[ -f "${INVENTORY_PATH}" ]] || die "inventory not found: ${INVENTORY_PATH}"

trap cleanup_output_temps EXIT
trap 'exit 1' HUP INT TERM

[[ ! -e "${OUTPUT_TEMP}" && ! -L "${OUTPUT_TEMP}" ]] \
    || die "temporary image already exists: ${OUTPUT_TEMP}"
[[ ! -e "${SIDECAR_TEMP}" && ! -L "${SIDECAR_TEMP}" ]] \
    || die "temporary sidecar already exists: ${SIDECAR_TEMP}"

printf "%s\n" "------------------------------------------------------------"
printf "Bake: IOC runner image\n"
printf "  OS Type    : %s\n" "${OS_TYPE}"
printf "  Build VM   : %s\n" "${VM_NAME}"
printf "  Source disk: %s\n" "${SOURCE_DISK}"
printf "  Output     : %s\n" "${OUTPUT_IMAGE}"
printf "  Ansible    : %s\n" "${ANSIBLE_DIR}"
printf "%s\n" "------------------------------------------------------------"

printf "\nStep 1/10: Boot a fresh %s\n" "${VM_NAME}"
"${CREATE_VM}" -o "${OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}"

printf "\nStep 2/10: Refresh known_hosts and resolve the VM address\n"
VM_IP="$(
    "${CREATE_VM}" -o "${OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}" -s 2>/dev/null \
        | awk -F': *' '/^IP Address/ && !seen {print $2; seen=1}'
)"
[[ -n "${VM_IP}" ]] || die "failed to resolve VM IP"
ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "${VM_IP}" 2>/dev/null || true
ssh-keyscan -H "${VM_IP}" >> "${HOME}/.ssh/known_hosts" 2>/dev/null
printf "  VM_IP=%s [OK]\n" "${VM_IP}"
write_runtime_inventory
printf "  runtime inventory for %s [OK]\n" "${VM_NAME}"

printf "\nStep 3/10: Resolve base identity and stamp the manifest\n"
declare -g BASE_NAME
declare -g BASE_DIGEST
declare -g CLOUD_HEAD
declare -g ANSIBLE_HEAD
declare -g EPICS_ENV_VERSION
declare -g EPICS_BASE_VERSION

[[ -f "${SOURCE_DISK}" ]] || die "source disk missing: ${SOURCE_DISK}"
SOURCE_RECORD="$(image_workflow_record_path "${SOURCE_DISK}")"
BASE_NAME="$(image_workflow_record_value "${SOURCE_RECORD}" source_image)" \
    || die "source disk creation record has no source image: ${SOURCE_DISK}"
[[ -f "${IMAGE_DIR}/${BASE_NAME}" ]] || die "source image missing: ${IMAGE_DIR}/${BASE_NAME}"
BASE_DIGEST="$(sha256sum "${IMAGE_DIR}/${BASE_NAME}")"
BASE_DIGEST="${BASE_DIGEST%% *}"
CLOUD_HEAD="$(repository_identity "${SC_TOP}")"
ANSIBLE_HEAD="$(repository_identity "${ANSIBLE_DIR}")"
EPICS_ENV_VERSION="$(awk '$1 == "epics_env_version:" {gsub(/"/, "", $2); print $2; exit}' \
    "${ANSIBLE_DIR}/inventory/group_vars/all.yml")"
EPICS_BASE_VERSION="$(awk '$1 == "epics_base_version:" {gsub(/"/, "", $2); print $2; exit}' \
    "${ANSIBLE_DIR}/inventory/group_vars/all.yml")"
[[ -n "${EPICS_ENV_VERSION}" && -n "${EPICS_BASE_VERSION}" ]] \
    || die "EPICS selectors are missing"
BAKE_DATE="$(date -u +%FT%TZ)"
stamp_manifest_header "${BAKE_DATE}" "${CLOUD_HEAD}" "${ANSIBLE_HEAD}" \
    "${EPICS_ENV_VERSION}" "${EPICS_BASE_VERSION}" "${BASE_NAME}" "${BASE_DIGEST}"
printf "  base image: %s sha256=%s [OK]\n" "${BASE_NAME}" "${BASE_DIGEST}"

printf "\nStep 4/10: Apply ansible site.yml on %s\n" "${VM_NAME}"
(
    cd "${ANSIBLE_DIR}"
    # The selector goes to site.yml alone. This is the first --extra-vars use in
    # this repository, and confining it to the one invocation that builds the
    # runner keeps the precedent narrow; 04_nfs_sim and 07_test_users have
    # nothing to do with the runner version.
    if [[ -n "${IOC_RUNNER_VERSION}" ]]; then
        ansible-playbook -i "${INVENTORY_PATH}" -i "${RUNTIME_INVENTORY}" \
            --limit "${VM_NAME}" \
            -e ioc_runner_version="${IOC_RUNNER_VERSION}" site.yml
    else
        ansible-playbook -i "${INVENTORY_PATH}" -i "${RUNTIME_INVENTORY}" \
            --limit "${VM_NAME}" site.yml
    fi
)

printf "\nStep 5/10: Apply 04_nfs_sim.yml on %s\n" "${VM_NAME}"
(
    cd "${ANSIBLE_DIR}"
    ansible-playbook -i "${INVENTORY_PATH}" -i "${RUNTIME_INVENTORY}" \
        --limit "${VM_NAME}" playbooks/04_nfs_sim.yml
)

printf "\nStep 6/10: Apply 07_test_users.yml on %s\n" "${VM_NAME}"
(
    cd "${ANSIBLE_DIR}"
    ansible-playbook -i "${INVENTORY_PATH}" -i "${RUNTIME_INVENTORY}" \
        --limit "${VM_NAME}" playbooks/07_test_users.yml
)

printf "\nStep 7/10: Finalize provenance\n"
append_pip_provenance
printf "  manifest provenance complete [OK]\n"

printf "\nStep 8/10: Validate provenance and extract the sidecar\n"
ssh "${SSH_OPTIONS[@]}" "vmadmin@${VM_IP}" 'sudo /bin/bash -p -s' < "${VALIDATOR}"
printf "  validator accepted the manifest [OK]\n"

SIDECAR_TEMP_CREATED=true
ssh "${SSH_OPTIONS[@]}" "vmadmin@${VM_IP}" 'sudo cat /etc/iocrunner-bake.manifest' > "${SIDECAR_TEMP}"
[[ -s "${SIDECAR_TEMP}" ]] || die "sidecar extraction produced an empty file"

printf "\nStep 9/10: Seal the current proxy artifact contract\n"
seal_proxy_contract
printf "  terminal proxy seal complete [OK]\n"

printf "\nStep 10/10: Shutdown and publish the validated pair\n"
[[ "${SEALED_VM_NAME}" == "${VM_NAME}" && \
   "${SEALED_SOURCE_DISK}" == "${SOURCE_DISK}" ]] \
    || die "terminal seal state does not match the exact build VM and disk"
"${CREATE_VM}" -o "${OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" \
    -p "${VM_PREFIX}" -S
[[ "$(virsh --connect "${LIBVIRT_URI}" domstate "${VM_NAME}")" == "shut off" ]] \
    || die "exact build VM is not shut off after the shared stop"
[[ -f "${SOURCE_DISK}" && ! -L "${SOURCE_DISK}" ]] \
    || die "exact stopped source disk is missing or not a regular file: ${SOURCE_DISK}"

OUTPUT_TEMP_CREATED=true
image_workflow_copy_qcow2 "${SOURCE_DISK}" "${OUTPUT_IMAGE}" \
    "iocrunner" "${OS_TYPE}" "${IMAGE_WORKFLOW_RUN_ID}" "${SOURCE_DISK##*/}" \
    || die "failed to publish image copy: ${OUTPUT_IMAGE}"
OUTPUT_TEMP_CREATED=false
mv -f -- "${SIDECAR_TEMP}" "${SIDECAR}"
SIDECAR_TEMP_CREATED=false
printf "  Copied: %s (%s)\n" "${OUTPUT_IMAGE}" "$(du -h "${OUTPUT_IMAGE}" | awk '{print $1}')"
printf "  Manifest sidecar: %s\n" "${SIDECAR}"

printf "\nCleanup build VM\n"
if [[ "${KEEP_VM}" == true ]]; then
    printf "  Keeping build VM for explicit follow-up verification.\n"
else
    "${CREATE_VM}" -o "${OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}" -c
fi

printf "%s\n" "------------------------------------------------------------"
printf "Bake complete: %s\n" "${OUTPUT_IMAGE}"
printf "Boot the variant: make %s-iocrunner.server\n" "${OS_TYPE}"
printf "%s\n" "------------------------------------------------------------"
