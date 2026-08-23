#!/bin/bash -p
#
# Audits published IOC runner images without exposing guest proxy values.

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="/root"
export LC_ALL=C
umask 077
unset BASH_ENV ENV CDPATH TMPDIR TMP TEMP XDG_RUNTIME_DIR
unset LIBGUESTFS_BACKEND LIBGUESTFS_MEMSIZE LIBGUESTFS_CACHEDIR LIBGUESTFS_TMPDIR
unset LIBGUESTFS_PATH LIBGUESTFS_DEBUG LIBGUESTFS_TRACE

readonly DEFAULT_IMAGE_DIR="/data/libvirt/images"
declare -g IMAGE_DIR="${DEFAULT_IMAGE_DIR}"
declare -g SC_RPATH
declare -g SC_TOP

SC_RPATH="$(realpath "$0")"
SC_TOP="${SC_RPATH%/*}/.."
SC_TOP="$(realpath "${SC_TOP}")"

readonly PROXY_CONTRACT="${SC_TOP}/bin/proxy_contract.bash"
readonly PROXY_CONTRACT_SHA256="4fac765bcaa5246a011ac8c464a70aa368919583e5d9843377ca717eefb8392f"

# The verifier mirrors only value-free paths, markers, and key names from the
# shipped proxy contract. The pinned digest makes inventory drift fail closed
# instead of silently weakening the audit.
readonly PROXY_CONTRACT_BEGIN="# BEGIN CLOUD-PROVISION PROXY CONTRACT"
readonly PROXY_CONTRACT_END="# END CLOUD-PROVISION PROXY CONTRACT"
readonly PROXY_CONTRACT_PROFILE="/etc/profile.d/95cloud-provision-proxy.sh"
readonly PROXY_CONTRACT_ENVIRONMENT="/etc/environment"
readonly PROXY_CONTRACT_APT="/etc/apt/apt.conf.d/95cloud-provision-proxy"
readonly PROXY_CONTRACT_DNF="/etc/dnf/dnf.conf"
readonly PROXY_CONTRACT_SUDO="/etc/sudoers.d/95cloud-provision-proxy"
readonly PROXY_CONTRACT_SSHD_DROPIN="/etc/ssh/sshd_config.d/95cloud-provision-proxy.conf"
readonly PROXY_CONTRACT_SSHD_MAIN="/etc/ssh/sshd_config"
readonly PROXY_CONTRACT_SSH_ENVIRONMENT="/home/vmadmin/.ssh/environment"
readonly PROXY_CONTRACT_PIP="/etc/pip.conf"
readonly PROXY_CONTRACT_GIT="/etc/gitconfig"
readonly PROXY_CONTRACT_RUNTIME_DIR="/run/cloud-provision"
readonly PROXY_CONTRACT_SCRIPT="${PROXY_CONTRACT_RUNTIME_DIR}/proxy_contract.bash"
readonly PROXY_CONTRACT_INPUT="${PROXY_CONTRACT_RUNTIME_DIR}/proxy-contract.input"
readonly PROXY_CONTRACT_LOCK="${PROXY_CONTRACT_RUNTIME_DIR}/proxy-contract.lock"
readonly PROXY_ENVIRONMENT_PATTERN='^[[:space:]]*(http_proxy|https_proxy|ftp_proxy|no_proxy|HTTP_PROXY|HTTPS_PROXY|FTP_PROXY|NO_PROXY)[[:space:]]*='
readonly PROXY_GENERIC_PATTERN='^[[:space:]]*[Pp][Rr][Oo][Xx][Yy][[:space:]]*='
readonly PROXY_SSHD_PATTERN='^[[:space:]]*[Pp][Ee][Rr][Mm][Ii][Tt][Uu][Ss][Ee][Rr][Ee][Nn][Vv][Ii][Rr][Oo][Nn][Mm][Ee][Nn][Tt][[:space:]]+'

GUESTFISH_PID=""
GUEST_ROOT=""
IMAGE_OS=""

die() {
    printf 'audit: failed stage=%s\n' "$1" >&2
    exit 1
}

print_usage() {
    printf "Usage: %s [-d <image_dir>]\n" "${0##*/}"
    printf "\n"
    printf "Audit published IOC runner qcow2 images through read-only guestfish inspection.\n"
    printf "\n"
    printf "Options:\n"
    printf "  -d <image_dir>  Image directory (default: %s)\n" "${DEFAULT_IMAGE_DIR}"
    printf "  -h              Show this help\n"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing-command"
}

require_root() {
    (( EUID == 0 )) || die "root-required"
}

guestfish_stop() {
    local pid="${GUESTFISH_PID}"
    local attempt=0
    local cleanup_status=0

    [[ -n "${pid}" ]] || return 0
    GUESTFISH_PID="${pid}" guestfish --remote exit >/dev/null 2>&1 || cleanup_status=1
    while (( attempt < 200 )); do
        if ! kill -0 "${pid}" >/dev/null 2>&1; then
            GUESTFISH_PID=""
            return "${cleanup_status}"
        fi
        sleep 0.1
        attempt=$((attempt + 1))
    done
    GUESTFISH_PID=""
    return 1
}

cleanup() {
    guestfish_stop || {
        printf 'audit: failed stage=cleanup\n' >&2
        return 1
    }
    return 0
}

guestfish_start() {
    local image="${1}"
    local session_output=""

    session_output="$(guestfish --ro --no-progress-bars --format=qcow2 -a "${image}" -i --listen 2>/dev/null)" || return 1
    GUESTFISH_PID="$(printf '%s\n' "${session_output}" | sed -n 's/^GUESTFISH_PID=\([0-9][0-9]*\); export GUESTFISH_PID$/\1/p')"
    [[ "${GUESTFISH_PID}" =~ ^[0-9]+$ ]] || return 1
    kill -0 "${GUESTFISH_PID}" >/dev/null 2>&1 || return 1
    GUEST_ROOT=""
}

guestfish_remote() {
    GUESTFISH_PID="${GUESTFISH_PID}" guestfish --remote "$@" 2>/dev/null
}

guestfish_bool() {
    local output=""

    if ! output="$(guestfish_remote "$@")"; then
        return 2
    fi
    case "${output}" in
        true) return 0 ;;
        false) return 1 ;;
        *) return 2 ;;
    esac
}

path_absent() {
    local state=0

    if guestfish_bool exists "$1"; then
        return 1
    else
        state=$?
    fi
    (( state == 1 )) || return 2

    if guestfish_bool is-symlink "$1"; then
        return 1
    else
        state=$?
    fi
    (( state == 1 )) || return 2
}

path_is_regular() {
    local state=0

    if guestfish_bool is-file "$1" followsymlinks:false; then
        return 0
    else
        state=$?
    fi
    (( state == 1 )) && return 1
    return 2
}

pattern_present() {
    local pattern="${1}"
    local path="${2}"
    local insensitive="${3:-false}"
    local fixed="${4:-false}"
    local -a pipeline_status=()

    set +e
    guestfish_remote cat "${path}" |
        awk -v pattern="${pattern}" -v insensitive="${insensitive}" -v fixed="${fixed}" '
            BEGIN {
                regex = pattern
                if (insensitive == "true") {
                    regex = tolower(regex)
                }
            }
            {
                line = $0
                if (insensitive == "true") {
                    line = tolower(line)
                }
                if ((fixed == "true" && index(line, regex) > 0) ||
                    (fixed != "true" && line ~ regex)) {
                    found = 1
                }
            }
            END { exit found ? 0 : 1 }
        ' >/dev/null 2>&1
    pipeline_status=("${PIPESTATUS[@]}")
    set -e

    [[ "${pipeline_status[0]}" == 0 ]] || return 2
    case "${pipeline_status[1]}" in
        0) return 0 ;;
        1) return 1 ;;
        *) return 2 ;;
    esac
}

verify_absent() {
    local label="${1}"
    local path="${2}"

    path_absent "${path}" || die "proxy-state:${label}"
}

verify_shared() {
    local label="${1}"
    local path="${2}"
    local key_pattern="${3}"
    local pattern_status=0

    if guestfish_bool is-symlink "${path}"; then
        die "proxy-state:${label}"
    else
        pattern_status=$?
    fi
    (( pattern_status == 1 )) || die "proxy-state:${label}"

    if guestfish_bool exists "${path}"; then
        path_is_regular "${path}" || die "proxy-state:${label}"
    else
        pattern_status=$?
        (( pattern_status == 1 )) || die "proxy-state:${label}"
        return 0
    fi

    if pattern_present "${PROXY_CONTRACT_BEGIN}" "${path}" false true; then
        die "proxy-state:${label}"
    else
        pattern_status=$?
    fi
    (( pattern_status == 1 )) || die "proxy-state:${label}"

    if pattern_present "${PROXY_CONTRACT_END}" "${path}" false true; then
        die "proxy-state:${label}"
    else
        pattern_status=$?
    fi
    (( pattern_status == 1 )) || die "proxy-state:${label}"

    if pattern_present "${key_pattern}" "${path}" true false; then
        die "proxy-state:${label}"
    else
        pattern_status=$?
    fi
    (( pattern_status == 1 )) || die "proxy-state:${label}"
}

inspect_guest_root() {
    local mount_output=""

    mount_output="$(guestfish_remote mountpoints)" || return 1
    GUEST_ROOT="$(printf '%s\n' "${mount_output}" | awk -F': ' '$2 == "/" { count++; root = $1 } END { if (count == 1) print root; else exit 1 }')" || return 1
    [[ "${GUEST_ROOT}" =~ ^/dev/[A-Za-z0-9._/-]+$ ]]
}

verify_guest_distro() {
    local distro=""

    distro="$(guestfish_remote inspect-get-distro "${GUEST_ROOT}")" || die "guest-inspection"
    case "${IMAGE_OS}:${distro}" in
        debian:debian*|debian:ubuntu*|rocky:rocky*) ;;
        *) die "guest-inspection" ;;
    esac
}

verify_guest_proxy_clean() {
    inspect_guest_root || die "guest-inspection"

    verify_absent profile "${PROXY_CONTRACT_PROFILE}"
    verify_shared environment "${PROXY_CONTRACT_ENVIRONMENT}" "${PROXY_ENVIRONMENT_PATTERN}"
    verify_absent ssh-environment "${PROXY_CONTRACT_SSH_ENVIRONMENT}"
    verify_absent pip "${PROXY_CONTRACT_PIP}"
    verify_shared git "${PROXY_CONTRACT_GIT}" "${PROXY_GENERIC_PATTERN}"

    case "${IMAGE_OS}" in
        debian)
            verify_absent apt "${PROXY_CONTRACT_APT}"
            verify_absent sudo "${PROXY_CONTRACT_SUDO}"
            verify_absent sshd-dropin "${PROXY_CONTRACT_SSHD_DROPIN}"
            ;;
        rocky)
            verify_shared dnf "${PROXY_CONTRACT_DNF}" "${PROXY_GENERIC_PATTERN}"
            verify_shared sshd-main "${PROXY_CONTRACT_SSHD_MAIN}" "${PROXY_SSHD_PATTERN}"
            ;;
        *)
            die "unsupported-os"
            ;;
    esac

    verify_absent runtime-script "${PROXY_CONTRACT_SCRIPT}"
    verify_absent runtime-input "${PROXY_CONTRACT_INPUT}"
    verify_absent runtime-lock "${PROXY_CONTRACT_LOCK}"
    verify_guest_distro
}

verify_image_metadata() {
    local image="${1}"

    qemu-img info --output=json -- "${image}" 2>/dev/null |
        jq -e '(.format == "qcow2") and ((.["backing-filename"] // null) == null) and ((.["virtual-size"] // 0) > 0)' \
            >/dev/null 2>&1 || return 1

    qemu-img check --output=json -- "${image}" 2>/dev/null |
        jq -e '((.["check-errors"] // 1) == 0) and ((.corruptions // 0) == 0) and ((.leaks // 0) == 0)' \
            >/dev/null 2>&1 || return 1
}

audit_image() {
    local image="${1}"
    local manifest="${image}.manifest"

    [[ -f "${image}" && ! -L "${image}" ]] || die "inventory-image"
    [[ -f "${manifest}" && ! -L "${manifest}" && -s "${manifest}" ]] || die "inventory-sidecar"
    verify_image_metadata "${image}" || die "image-metadata"
    guestfish_start "${image}" || die "guestfish-start"
    verify_guest_proxy_clean
    guestfish_stop || die "guestfish-stop"
}

while getopts ":d:h" opt; do
    case "${opt}" in
        d) IMAGE_DIR="${OPTARG}" ;;
        h) print_usage; exit 0 ;;
        :) die "usage" ;;
        ?) die "usage" ;;
    esac
done
shift $((OPTIND - 1))
(( $# == 0 )) || die "usage"

require_root
for command_name in awk find guestfish jq kill qemu-img realpath sed sha256sum sleep sort; do
    require_command "${command_name}"
done

[[ "${IMAGE_DIR}" == /* ]] || die "image-directory"
[[ -d "${IMAGE_DIR}" && ! -L "${IMAGE_DIR}" ]] || die "image-directory"
IMAGE_DIR="$(realpath -e -- "${IMAGE_DIR}" 2>/dev/null)" || die "image-directory"
[[ -f "${PROXY_CONTRACT}" && ! -L "${PROXY_CONTRACT}" ]] || die "proxy-contract"
[[ "$(sha256sum "${PROXY_CONTRACT}" | awk '{ print $1 }')" == "${PROXY_CONTRACT_SHA256}" ]] || die "proxy-contract-drift"

trap 'cleanup || exit 1' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mapfile -d '' -t image_names < <(
    find "${IMAGE_DIR}" -maxdepth 1 -type f ! -type l -name 'iocrunner-*.qcow2' -printf '%f\0' 2>/dev/null |
        LC_ALL=C sort -z 2>/dev/null &&
        printf '\0'
)
(( ${#image_names[@]} > 0 )) || die "inventory-enumeration"
sentinel_index=$((${#image_names[@]} - 1))
[[ -z "${image_names[${sentinel_index}]}" ]] || die "inventory-enumeration"
unset "image_names[${sentinel_index}]"
(( ${#image_names[@]} > 0 )) || die "inventory-empty"

total=0
passed=0
debian=0
rocky=0

for image_name in "${image_names[@]}"; do
    image_path="${IMAGE_DIR}/${image_name}"
    case "${image_name}" in
        iocrunner-debian13-*.qcow2)
            IMAGE_OS="debian"
            ;;
        iocrunner-rocky8-*.qcow2)
            IMAGE_OS="rocky"
            ;;
        *)
            die "inventory-name"
            ;;
    esac
    audit_image "${image_path}"
    case "${IMAGE_OS}" in
        debian)
            debian=$((debian + 1))
            ;;
        rocky)
            rocky=$((rocky + 1))
            ;;
        *)
            die "unsupported-os"
            ;;
    esac
    total=$((total + 1))
    passed=$((passed + 1))
done

printf 'audit: completed images=%d debian=%d rocky=%d passed=%d failed=0 residue=clean\n' \
    "${total}" "${debian}" "${rocky}" "${passed}"
