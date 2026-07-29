#!/usr/bin/env bash
#
# Builds and validates a flat IOC runner image from a fresh base VM.

set -euo pipefail

declare -g SC_RPATH
declare -g SC_TOP

SC_RPATH="$(realpath "$0")"
SC_TOP="${SC_RPATH%/*}/.."
SC_TOP="$(realpath "${SC_TOP}")"

declare -g OS_TYPE=""
declare -g IMAGE_DIR="${IMAGE_DIR:-${HOME}/libvirt/images}"
declare -g ANSIBLE_DIR="${ANSIBLE_PROVISION_DIR:-${SC_TOP}/../ansible-provision}"
declare -g KEEP_VM=false
declare -g VM_PREFIX="${VM_PREFIX:-testbed}"
declare -g NODE_ID="server"
declare -g INVENTORY="${BAKE_INVENTORY:-inventory/testbed.ini}"
declare -g LIBVIRT_URI="qemu:///system"
declare -g VM_IP=""
declare -g OUTPUT_TEMP_CREATED=false
declare -g SIDECAR_TEMP_CREATED=false

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
    printf "  -h              Show this help\n"
}

function require_command {
    local command_name="$1"
    local command_path

    command_path="$(command -v "${command_name}" 2>/dev/null || true)"
    [[ -n "${command_path}" && -x "${command_path}" ]] \
        || die "required command not found: ${command_name}"
}

function cleanup_output_temps {
    local rc=$?

    if [[ "${OUTPUT_TEMP_CREATED}" == true ]]; then
        rm -f -- "${OUTPUT_TEMP}"
    fi
    if [[ "${SIDECAR_TEMP_CREATED}" == true ]]; then
        rm -f -- "${SIDECAR_TEMP}"
    fi
    return "${rc}"
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

function backing_path_for_disk {
    local disk="$1"
    local info_json
    local backing_path

    info_json="$(qemu-img info --force-share --output=json "${disk}")" \
        || die "cannot inspect disk: ${disk}"
    backing_path="$(jq -r '."full-backing-filename" // empty' <<< "${info_json}")"
    if [[ -n "${backing_path}" ]]; then
        realpath -e "${backing_path}"
    fi
}

# Rejects publication while any defined domain or selected-directory qcow2
# resolves through the output image as its backing file.
function protect_output_consumers {
    local output_path
    local domain disk backing_path
    local -a domains=()
    local -a domain_disks=()
    local -a image_files=()

    output_path="$(realpath -m "${OUTPUT_IMAGE}")"
    mapfile -t domains < <(virsh --connect "${LIBVIRT_URI}" list --all --name)

    for domain in "${domains[@]}"; do
        [[ -n "${domain}" ]] || continue
        mapfile -t domain_disks < <(
            virsh --connect "${LIBVIRT_URI}" domblklist "${domain}" --details \
                | awk '$2 == "disk" && $4 != "-" {print $4}'
        )
        for disk in "${domain_disks[@]}"; do
            [[ -f "${disk}" ]] || die "defined domain disk is missing: ${domain}: ${disk}"
            backing_path="$(backing_path_for_disk "${disk}")"
            if [[ -n "${backing_path}" && "${backing_path}" == "${output_path}" ]]; then
                die "output image is in use by domain ${domain}: ${OUTPUT_IMAGE}"
            fi
        done
    done

    shopt -s nullglob
    image_files=("${IMAGE_DIR}"/*.qcow2)
    shopt -u nullglob
    for disk in "${image_files[@]}"; do
        [[ -f "${disk}" ]] || continue
        backing_path="$(backing_path_for_disk "${disk}")"
        if [[ -n "${backing_path}" && "${backing_path}" == "${output_path}" ]]; then
            die "output image is in use by qcow2 disk ${disk}"
        fi
    done
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
    ssh "vmadmin@${VM_IP}" "${remote_command}" <<'REMOTE_MANIFEST'
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
    ssh "vmadmin@${VM_IP}" 'sudo /bin/bash -p -s' <<'REMOTE_PIP'
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

function remove_proxy_configuration {
    ssh "vmadmin@${VM_IP}" 'sudo /bin/bash -p -s' <<'REMOTE_DEPROXY'
if [[ ! -o privileged ]]; then
    printf "%s\n" "error: privileged Bash mode is required" >&2
    exit 1
fi
set -euo pipefail
unset BASH_ENV ENV CDPATH
unset TMPDIR TMP TEMP
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
[[ "${EUID}" == "0" ]]
[[ -f /etc/dnf/dnf.conf ]] && sed -i '/^proxy=/d' /etc/dnf/dnf.conf
rm -f /etc/apt/apt.conf.d/95proxy /etc/sudoers.d/95proxy
rm -f /etc/ssh/sshd_config.d/99proxy.conf /etc/pip.conf
sed -i '/[Pp][Rr][Oo][Xx][Yy]/d' /etc/environment
git config --system --unset-all http.proxy 2>/dev/null || true
git config --system --unset-all https.proxy 2>/dev/null || true
rm -f /root/.ssh/environment /home/*/.ssh/environment
REMOTE_DEPROXY

    ssh "vmadmin@${VM_IP}" 'sudo /bin/bash -p -s' <<'REMOTE_VERIFY'
if [[ ! -o privileged ]]; then
    printf "%s\n" "error: privileged Bash mode is required" >&2
    exit 1
fi
set -euo pipefail
unset BASH_ENV ENV CDPATH
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
hits=0
[[ -f /etc/dnf/dnf.conf ]] && grep -qsi proxy /etc/dnf/dnf.conf && hits=1
if ls /etc/apt/apt.conf.d/95proxy /etc/sudoers.d/95proxy \
      /etc/ssh/sshd_config.d/99proxy.conf /etc/pip.conf \
      /root/.ssh/environment /home/*/.ssh/environment 2>/dev/null | grep -q .; then
    hits=1
fi
grep -qsi proxy /etc/environment && hits=1
git config --system --get-regexp proxy >/dev/null 2>&1 && hits=1
exit "${hits}"
REMOTE_VERIFY
}

while getopts ":o:d:a:kh" opt; do
    case "${opt}" in
        o) OS_TYPE="${OPTARG}" ;;
        d) IMAGE_DIR="${OPTARG}" ;;
        a) ANSIBLE_DIR="${OPTARG}" ;;
        k) KEEP_VM=true ;;
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

for command_name in ansible-playbook awk du git jq mv qemu-img realpath sed \
                    sha256sum ssh ssh-keygen ssh-keyscan virsh; do
    require_command "${command_name}"
done

[[ -d "${IMAGE_DIR}" ]] || die "image directory not found: ${IMAGE_DIR}"
[[ -d "${ANSIBLE_DIR}" ]] || die "ansible-provision directory not found: ${ANSIBLE_DIR}"
IMAGE_DIR="$(realpath "${IMAGE_DIR}")"
ANSIBLE_DIR="$(realpath "${ANSIBLE_DIR}")"

declare -g VM_NAME="${VM_PREFIX}-${OS_TYPE}-${NODE_ID}"
declare -g SOURCE_DISK="${IMAGE_DIR}/${VM_NAME}.qcow2"
declare -g OUTPUT_IMAGE="${IMAGE_DIR}/iocrunner-${OS_TYPE}.qcow2"
declare -g OUTPUT_TEMP="${OUTPUT_IMAGE}.tmp"
declare -g SIDECAR="${OUTPUT_IMAGE}.manifest"
declare -g SIDECAR_TEMP="${SIDECAR}.tmp"
declare -g CREATE_VM="${SC_TOP}/bin/create_vm.bash"
declare -g VALIDATOR="${SC_TOP}/bin/validate_iocrunner_bake.bash"
declare -g INVENTORY_PATH

if [[ "${INVENTORY}" == /* ]]; then
    INVENTORY_PATH="${INVENTORY}"
else
    INVENTORY_PATH="${ANSIBLE_DIR}/${INVENTORY}"
fi

[[ -x "${CREATE_VM}" ]] || die "create_vm.bash is not executable: ${CREATE_VM}"
[[ -f "${VALIDATOR}" ]] || die "validator not found: ${VALIDATOR}"
[[ -f "${INVENTORY_PATH}" ]] || die "inventory not found: ${INVENTORY_PATH}"

trap cleanup_output_temps EXIT
trap 'exit 1' HUP INT TERM

protect_output_consumers
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
"${CREATE_VM}" -o "${OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}" -F

printf "\nStep 2/10: Refresh known_hosts and resolve the VM address\n"
VM_IP="$(
    "${CREATE_VM}" -o "${OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}" -s 2>/dev/null \
        | awk -F': *' '/^IP Address/ {print $2; exit}'
)"
[[ -n "${VM_IP}" ]] || die "failed to resolve VM IP"
ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "${VM_IP}" 2>/dev/null || true
ssh-keyscan -H "${VM_IP}" >> "${HOME}/.ssh/known_hosts" 2>/dev/null
printf "  VM_IP=%s [OK]\n" "${VM_IP}"

printf "\nStep 3/10: Resolve base identity and stamp the manifest\n"
declare -g BACKING_PATH
declare -g BASE_NAME
declare -g BASE_DIGEST
declare -g CLOUD_HEAD
declare -g ANSIBLE_HEAD
declare -g EPICS_ENV_VERSION
declare -g EPICS_BASE_VERSION

[[ -f "${SOURCE_DISK}" ]] || die "source disk missing: ${SOURCE_DISK}"
BACKING_PATH="$(backing_path_for_disk "${SOURCE_DISK}")"
[[ -n "${BACKING_PATH}" && -f "${BACKING_PATH}" ]] \
    || die "source disk has no readable backing image: ${SOURCE_DISK}"
BASE_NAME="${BACKING_PATH##*/}"
BASE_DIGEST="$(sha256sum "${BACKING_PATH}")"
BASE_DIGEST="${BASE_DIGEST%% *}"
CLOUD_HEAD="$(repository_identity "${SC_TOP}")"
ANSIBLE_HEAD="$(repository_identity "${ANSIBLE_DIR}")"
EPICS_ENV_VERSION="$(awk '$1 == "epics_env_version:" {gsub(/"/, "", $2); print $2; exit}' \
    "${ANSIBLE_DIR}/inventory/group_vars/all.yml")"
EPICS_BASE_VERSION="$(awk '$1 == "epics_base_version:" {gsub(/"/, "", $2); print $2; exit}' \
    "${ANSIBLE_DIR}/inventory/group_vars/all.yml")"
[[ -n "${EPICS_ENV_VERSION}" && -n "${EPICS_BASE_VERSION}" ]] \
    || die "EPICS selectors are missing"
stamp_manifest_header "$(date -u +%FT%TZ)" "${CLOUD_HEAD}" "${ANSIBLE_HEAD}" \
    "${EPICS_ENV_VERSION}" "${EPICS_BASE_VERSION}" "${BASE_NAME}" "${BASE_DIGEST}"
printf "  base image: %s sha256=%s [OK]\n" "${BASE_NAME}" "${BASE_DIGEST}"

printf "\nStep 4/10: Apply ansible site.yml on %s\n" "${VM_NAME}"
(
    cd "${ANSIBLE_DIR}"
    ansible-playbook -i "${INVENTORY_PATH}" --limit "${VM_NAME}" site.yml
)

printf "\nStep 5/10: Apply 04_nfs_sim.yml on %s\n" "${VM_NAME}"
(
    cd "${ANSIBLE_DIR}"
    ansible-playbook -i "${INVENTORY_PATH}" --limit "${VM_NAME}" playbooks/04_nfs_sim.yml
)

printf "\nStep 6/10: Apply 07_test_users.yml on %s\n" "${VM_NAME}"
(
    cd "${ANSIBLE_DIR}"
    ansible-playbook -i "${INVENTORY_PATH}" --limit "${VM_NAME}" playbooks/07_test_users.yml
)

printf "\nStep 7/10: Finalize provenance and remove proxy configuration\n"
append_pip_provenance
remove_proxy_configuration
printf "  manifest and de-proxy checks complete [OK]\n"

printf "\nStep 8/10: Validate the real in-image provenance\n"
ssh "vmadmin@${VM_IP}" 'sudo /bin/bash -p -s' < "${VALIDATOR}"
printf "  validator accepted the manifest [OK]\n"

SIDECAR_TEMP_CREATED=true
ssh "vmadmin@${VM_IP}" 'sudo cat /etc/iocrunner-bake.manifest' > "${SIDECAR_TEMP}"
[[ -s "${SIDECAR_TEMP}" ]] || die "sidecar extraction produced an empty file"

printf "\nStep 9/10: Shutdown, flatten, and publish the validated pair\n"
virsh --connect "${LIBVIRT_URI}" shutdown "${VM_NAME}" >/dev/null

declare -g ATTEMPT=0
declare -g STATE="unknown"
while [[ "${ATTEMPT}" -lt "24" ]]; do
    sleep 5
    STATE="$(virsh --connect "${LIBVIRT_URI}" domstate "${VM_NAME}" 2>/dev/null || printf "unknown\n")"
    if [[ "${STATE}" == "shut off" ]]; then
        printf "  VM shut off [OK]\n"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
done

[[ "${STATE}" == "shut off" ]] || die "VM did not shut down within 120s"
[[ -f "${SOURCE_DISK}" ]] || die "source disk missing: ${SOURCE_DISK}"

OUTPUT_TEMP_CREATED=true
qemu-img convert -p -O qcow2 "${SOURCE_DISK}" "${OUTPUT_TEMP}"
[[ -s "${OUTPUT_TEMP}" ]] || die "image conversion produced an empty file"
mv -- "${OUTPUT_TEMP}" "${OUTPUT_IMAGE}"
OUTPUT_TEMP_CREATED=false
mv -- "${SIDECAR_TEMP}" "${SIDECAR}"
SIDECAR_TEMP_CREATED=false
printf "  Output: %s (%s)\n" "${OUTPUT_IMAGE}" "$(du -h "${OUTPUT_IMAGE}" | awk '{print $1}')"
printf "  Manifest sidecar: %s\n" "${SIDECAR}"

printf "\nStep 10/10: Cleanup build VM\n"
if [[ "${KEEP_VM}" == true ]]; then
    printf "  Keeping build VM for explicit follow-up verification.\n"
else
    "${CREATE_VM}" -o "${OS_TYPE}" -n "${NODE_ID}" -d "${IMAGE_DIR}" -p "${VM_PREFIX}" -c
fi

printf "%s\n" "------------------------------------------------------------"
printf "Bake complete: %s\n" "${OUTPUT_IMAGE}"
printf "Boot the variant: make %s-iocrunner.server\n" "${OS_TYPE}"
printf "%s\n" "------------------------------------------------------------"
