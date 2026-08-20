#!/usr/bin/env bash
#
# Defines the proxy artifacts written by cloud-init and removes that exact set
# before a build disk may be published.

declare -gr PROXY_CONTRACT_BEGIN="# BEGIN CLOUD-PROVISION PROXY CONTRACT"
declare -gr PROXY_CONTRACT_END="# END CLOUD-PROVISION PROXY CONTRACT"
declare -gr PROXY_CONTRACT_PROFILE="/etc/profile.d/95cloud-provision-proxy.sh"
declare -gr PROXY_CONTRACT_APT="/etc/apt/apt.conf.d/95cloud-provision-proxy"
declare -gr PROXY_CONTRACT_DNF="/etc/dnf/dnf.conf"
declare -gr PROXY_CONTRACT_GIT="/etc/gitconfig"
declare -gr PROXY_CONTRACT_NO_PROXY="localhost,127.0.0.1,192.168.0.0/16"
declare -gr PROXY_CONTRACT_MARKER="cloud-provision-proxy-v1"

declare -g PROXY_CONTRACT_ROOT="/"
declare -g PROXY_CONTRACT_EXPECTED_UID=0
declare -g PROXY_CONTRACT_EXPECTED_GID=0
declare -ag PROXY_CONTRACT_TEMPS=()
declare -g PROXY_CONTRACT_CLOUD_INIT=""
declare -ag PROXY_CONTRACT_CLEAN_ARGS=()

function proxy_contract_die {
    printf "Error: proxy contract %s\n" "$*" >&2
    return 1
}

function proxy_contract_os_family {
    local os_name="$1"

    case "${os_name}" in
        debian*) printf "debian\n" ;;
        ubuntu*) printf "ubuntu\n" ;;
        rocky*) printf "rocky\n" ;;
        *) proxy_contract_die "does not support OS identity: ${os_name}" ;;
    esac
}

function proxy_contract_validate_url {
    local proxy_url="$1"
    local command_substitution_marker=$'\140'

    [[ "${proxy_url}" =~ ^https?://[^[:space:]]+$ ]] &&
        [[ "${proxy_url}" != *'"'* ]] &&
        [[ "${proxy_url}" != *"'"* ]] &&
        [[ "${proxy_url}" != *\\* ]] &&
        [[ "${proxy_url}" != *'$'* ]] &&
        [[ "${proxy_url}" != *"${command_substitution_marker}"* ]] &&
        [[ "${proxy_url}" != *'!'* ]] \
        || proxy_contract_die "received an invalid proxy URL"
}

function proxy_contract_render_yaml_file {
    local path="$1"
    local append="$2"
    shift 2
    local line

    printf "  - path: %s\n" "${path}"
    if [[ "${append}" == true ]]; then
        printf "    append: true\n"
    fi
    printf "    owner: root:root\n"
    printf "    permissions: '0644'\n"
    printf "    content: |\n"
    for line in "$@"; do
        printf "      %s\n" "${line}"
    done
}

# Source-only host interface used by create_vm.bash after it validates the
# scalar proxy URL. Production code never reads the independent test fixture.
function proxy_contract_render_write_files {
    local os_name="$1"
    local proxy_url="$2"
    local os_family identity contract_path ownership marker cleanup remnant
    local -a identities=()
    local -a paths=()
    local -a ownerships=()
    local -a markers=()
    local -a cleanups=()
    local -a remnants=()
    local index

    proxy_contract_validate_url "${proxy_url}" || return 1
    os_family="$(proxy_contract_os_family "${os_name}")" || return 1
    proxy_contract_inventory "${os_family}" identities paths ownerships markers cleanups remnants

    printf "\nwrite_files:\n"
    for index in "${!identities[@]}"; do
        identity="${identities[index]}"
        contract_path="${paths[index]}"
        ownership="${ownerships[index]}"
        marker="${markers[index]}"
        cleanup="${cleanups[index]}"
        remnant="${remnants[index]}"
        proxy_contract_validate_inventory_entry \
            "${identity}" "${contract_path}" "${ownership}" "${marker}" \
            "${cleanup}" "${remnant}" || return 1
        case "${identity}" in
            profile)
                proxy_contract_render_yaml_file "${contract_path}" false \
                    "${PROXY_CONTRACT_BEGIN}" \
                    "export http_proxy=\"${proxy_url}\"" \
                    "export https_proxy=\"${proxy_url}\"" \
                    "export ftp_proxy=\"${proxy_url}\"" \
                    "export no_proxy=\"${PROXY_CONTRACT_NO_PROXY}\"" \
                    'export HTTP_PROXY="$http_proxy"' \
                    'export HTTPS_PROXY="$https_proxy"' \
                    'export FTP_PROXY="$ftp_proxy"' \
                    'export NO_PROXY="$no_proxy"' \
                    "${PROXY_CONTRACT_END}"
                ;;
            apt)
                proxy_contract_render_yaml_file "${contract_path}" false \
                    "${PROXY_CONTRACT_BEGIN}" \
                    "Acquire::http::Proxy \"${proxy_url}\";" \
                    "Acquire::https::Proxy \"${proxy_url}\";" \
                    "${PROXY_CONTRACT_END}"
                ;;
            dnf)
                proxy_contract_render_yaml_file "${contract_path}" true \
                    "${PROXY_CONTRACT_BEGIN}" \
                    "proxy=${proxy_url}" \
                    "${PROXY_CONTRACT_END}"
                ;;
            git)
                proxy_contract_render_yaml_file "${contract_path}" true \
                    "${PROXY_CONTRACT_BEGIN}" \
                    "[http]" \
                    "    proxy = ${proxy_url}" \
                    "[https]" \
                    "    proxy = ${proxy_url}" \
                    "${PROXY_CONTRACT_END}"
                ;;
        esac
    done
}

function proxy_contract_root_path {
    local path="$1"

    if [[ "${PROXY_CONTRACT_ROOT}" == "/" ]]; then
        printf "%s\n" "${path}"
    else
        printf "%s%s\n" "${PROXY_CONTRACT_ROOT}" "${path}"
    fi
}

function proxy_contract_validate_regular_file {
    local identity="$1"
    local path="$2"
    local uid gid mode

    [[ -e "${path}" && ! -L "${path}" && -f "${path}" ]] \
        || proxy_contract_die "identity ${identity} is not a regular file"
    uid="$(stat -Lc '%u' "${path}")"
    gid="$(stat -Lc '%g' "${path}")"
    mode="$(stat -Lc '%a' "${path}")"
    [[ "${uid}" == "${PROXY_CONTRACT_EXPECTED_UID}" &&
       "${gid}" == "${PROXY_CONTRACT_EXPECTED_GID}" &&
       "${mode}" == "644" ]] \
        || proxy_contract_die "identity ${identity} has an ownership or mode conflict"
}

function proxy_contract_validate_parent {
    local identity="$1"
    local path="$2"
    local parent uid gid mode

    parent="${path%/*}"
    [[ -d "${parent}" && ! -L "${parent}" ]] \
        || proxy_contract_die "identity ${identity} has an unsafe parent directory"
    uid="$(stat -Lc '%u' "${parent}")"
    gid="$(stat -Lc '%g' "${parent}")"
    mode="$(stat -Lc '%a' "${parent}")"
    [[ "${uid}" == "${PROXY_CONTRACT_EXPECTED_UID}" &&
       "${gid}" == "${PROXY_CONTRACT_EXPECTED_GID}" ]] \
        || proxy_contract_die "identity ${identity} parent has an ownership conflict"
    (( (8#${mode} & 8#022) == 0 )) \
        || proxy_contract_die "identity ${identity} parent is group or world writable"
}

function proxy_contract_validate_marker_shape {
    local identity="$1"
    local path="$2"
    local form="$3"
    local begin_count end_count
    local first_line last_line

    begin_count="$(grep -Fxc -- "${PROXY_CONTRACT_BEGIN}" "${path}" || true)"
    end_count="$(grep -Fxc -- "${PROXY_CONTRACT_END}" "${path}" || true)"
    [[ "${begin_count}" == "1" && "${end_count}" == "1" ]] \
        || proxy_contract_die "identity ${identity} has missing or duplicate markers"

    if grep -F 'CLOUD-PROVISION PROXY CONTRACT' "${path}" \
        | grep -Fvx -e "${PROXY_CONTRACT_BEGIN}" -e "${PROXY_CONTRACT_END}" \
        | grep -q .; then
        proxy_contract_die "identity ${identity} has an orphan marker"
        return 1
    fi

    awk -v begin="${PROXY_CONTRACT_BEGIN}" -v end="${PROXY_CONTRACT_END}" '
        $0 == begin {
            if (inside || saw_begin) exit 1
            inside = 1
            saw_begin = 1
            next
        }
        $0 == end {
            if (!inside || saw_end) exit 1
            inside = 0
            saw_end = 1
            next
        }
        END {
            if (inside || !saw_begin || !saw_end) exit 1
        }
    ' "${path}" || proxy_contract_die "identity ${identity} has nested or orphan markers"

    if [[ "${form}" == dedicated ]]; then
        IFS= read -r first_line < "${path}" || true
        last_line="$(tail -n 1 "${path}")"
        [[ "${first_line}" == "${PROXY_CONTRACT_BEGIN}" &&
           "${last_line}" == "${PROXY_CONTRACT_END}" ]] \
            || proxy_contract_die "dedicated identity ${identity} has content outside its markers"
    fi
}

function proxy_contract_validate_unowned_keys {
    local identity="$1"
    local path="$2"
    local key_pattern="$3"

    awk -v begin="${PROXY_CONTRACT_BEGIN}" -v end="${PROXY_CONTRACT_END}" \
        -v key_pattern="${key_pattern}" '
        $0 == begin { inside = 1; next }
        $0 == end { inside = 0; next }
        !inside && $0 ~ key_pattern { found = 1 }
        END { exit found }
    ' "${path}" || proxy_contract_die "identity ${identity} has a relevant unowned proxy key"
}

function proxy_contract_parse_os_release {
    local path
    local line value=""
    local id_count=0

    path="$(proxy_contract_root_path /etc/os-release)"
    [[ -e "${path}" && ! -L "${path}" && -f "${path}" ]] \
        || proxy_contract_die "cannot read a regular /etc/os-release"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^ID=(.*)$ ]]; then
            value="${BASH_REMATCH[1]}"
            id_count=$((id_count + 1))
        fi
    done < "${path}"
    [[ "${id_count}" == "1" ]] \
        || proxy_contract_die "/etc/os-release must contain exactly one ID field"

    case "${value}" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    [[ "${value}" =~ ^[a-z0-9._-]+$ ]] \
        || proxy_contract_die "/etc/os-release contains an invalid ID field"
    proxy_contract_os_family "${value}"
}

function proxy_contract_inventory {
    local os_family="$1"
    local -n identities_ref="$2"
    local -n paths_ref="$3"
    local -n ownerships_ref="$4"
    local -n markers_ref="$5"
    local -n cleanups_ref="$6"
    local -n remnants_ref="$7"

    identities_ref=(profile) # inventory:profile
    paths_ref=("${PROXY_CONTRACT_PROFILE}")
    ownerships_ref=(dedicated)
    markers_ref=("${PROXY_CONTRACT_MARKER}")
    cleanups_ref=(required)
    remnants_ref=(required)
    case "${os_family}" in
        debian|ubuntu)
            identities_ref+=(apt) # inventory:apt
            paths_ref+=("${PROXY_CONTRACT_APT}")
            ownerships_ref+=(dedicated)
            markers_ref+=("${PROXY_CONTRACT_MARKER}")
            cleanups_ref+=(required)
            remnants_ref+=(required)
            ;;
        rocky)
            identities_ref+=(dnf) # inventory:dnf
            paths_ref+=("${PROXY_CONTRACT_DNF}")
            ownerships_ref+=(shared)
            markers_ref+=("${PROXY_CONTRACT_MARKER}")
            cleanups_ref+=(required)
            remnants_ref+=(required)
            ;;
    esac
    identities_ref+=(git) # inventory:git
    paths_ref+=("${PROXY_CONTRACT_GIT}")
    ownerships_ref+=(shared)
    markers_ref+=("${PROXY_CONTRACT_MARKER}")
    cleanups_ref+=(required)
    remnants_ref+=(required)
}

function proxy_contract_validate_inventory_entry {
    local identity="$1"
    local path="$2"
    local ownership="$3"
    local marker="$4"
    local cleanup="$5"
    local remnant="$6"
    local expected=""

    case "${identity}" in
        profile) expected="${PROXY_CONTRACT_PROFILE}|dedicated" ;;
        apt) expected="${PROXY_CONTRACT_APT}|dedicated" ;;
        dnf) expected="${PROXY_CONTRACT_DNF}|shared" ;;
        git) expected="${PROXY_CONTRACT_GIT}|shared" ;;
        *) proxy_contract_die "contains an unknown inventory identity"; return 1 ;;
    esac
    [[ "${path}|${ownership}" == "${expected}" &&
       "${marker}" == "${PROXY_CONTRACT_MARKER}" &&
       "${cleanup}" == required && "${remnant}" == required ]] \
        || proxy_contract_die "contains invalid inventory metadata for ${identity}"
}

# Source-only inspection interface for the independent test oracle.
function proxy_contract_print_inventory {
    local os_family="$1"
    local -a identities=() paths=() ownerships=() markers=() cleanups=() remnants=()
    local index

    proxy_contract_inventory \
        "${os_family}" identities paths ownerships markers cleanups remnants
    for index in "${!identities[@]}"; do
        proxy_contract_validate_inventory_entry \
            "${identities[index]}" "${paths[index]}" "${ownerships[index]}" \
            "${markers[index]}" "${cleanups[index]}" "${remnants[index]}" || return 1
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${os_family}" "${identities[index]}" "${paths[index]}" \
            "${ownerships[index]}" "${markers[index]}" \
            "${cleanups[index]}" "${remnants[index]}"
    done
}

function proxy_contract_any_artifact_present {
    local os_family="$1"
    local path
    local -a identities=()
    local -a paths=()
    local -a ownerships=() markers=() cleanups=() remnants=()
    local index

    proxy_contract_inventory \
        "${os_family}" identities paths ownerships markers cleanups remnants
    for index in "${!identities[@]}"; do
        proxy_contract_validate_inventory_entry \
            "${identities[index]}" "${paths[index]}" "${ownerships[index]}" \
            "${markers[index]}" "${cleanups[index]}" "${remnants[index]}" || return 1
        path="$(proxy_contract_root_path "${paths[index]}")"
        if [[ "${ownerships[index]}" == dedicated ]]; then
            if [[ -e "${path}" || -L "${path}" ]]; then
                return 0
            fi
        elif [[ -L "${path}" ]]; then
            return 0
        elif [[ -f "${path}" ]] &&
             grep -Eqi 'CLOUD-PROVISION PROXY CONTRACT|^[[:space:]]*proxy[[:space:]]*=' \
                 "${path}"; then
            return 0
        fi
    done
    return 1
}

function proxy_contract_preflight_identity {
    local identity="$1"
    local contract_path="$2"
    local form="$3"
    local path

    path="$(proxy_contract_root_path "${contract_path}")"
    proxy_contract_validate_parent "${identity}" "${path}"
    proxy_contract_validate_regular_file "${identity}" "${path}"
    proxy_contract_validate_marker_shape "${identity}" "${path}" "${form}"
    case "${identity}" in
        dnf)
            proxy_contract_validate_unowned_keys "${identity}" "${path}" \
                '^[[:space:]]*[Pp][Rr][Oo][Xx][Yy][[:space:]]*='
            ;;
        git)
            proxy_contract_validate_unowned_keys "${identity}" "${path}" \
                '^[[:space:]]*[Pp][Rr][Oo][Xx][Yy][[:space:]]*='
            ;;
    esac
}

function proxy_contract_prepare_shared_clean {
    local identity="$1"
    local contract_path="$2"
    local result_name="$3"
    local path parent base created_temp
    local begin_offset end_offset block_end next_byte tail_start

    path="$(proxy_contract_root_path "${contract_path}")"
    parent="${path%/*}"
    base="${path##*/}"
    created_temp="$(mktemp "${parent}/.${base}.proxy-contract.XXXXXX")" \
        || proxy_contract_die "could not create a same-parent temporary file for ${identity}"
    PROXY_CONTRACT_TEMPS+=("${created_temp}")
    begin_offset="$(grep -aboF -m1 -- "${PROXY_CONTRACT_BEGIN}" "${path}")"
    begin_offset="${begin_offset%%:*}"
    end_offset="$(grep -aboF -m1 -- "${PROXY_CONTRACT_END}" "${path}")"
    end_offset="${end_offset%%:*}"
    [[ "${begin_offset}" =~ ^[0-9]+$ && "${end_offset}" =~ ^[0-9]+$ ]] \
        || proxy_contract_die "could not resolve marker offsets for ${identity}"

    block_end=$((end_offset + ${#PROXY_CONTRACT_END}))
    next_byte="$(dd if="${path}" bs=1 skip="${block_end}" count=1 status=none \
        | od -An -tu1 | tr -d '[:space:]')"
    if [[ "${next_byte}" == "10" ]]; then
        block_end=$((block_end + 1))
    fi
    : > "${created_temp}"
    if (( begin_offset > 0 )); then
        head -c "${begin_offset}" "${path}" >> "${created_temp}"
    fi
    tail_start=$((block_end + 1))
    tail -c "+${tail_start}" "${path}" >> "${created_temp}"
    chown "${PROXY_CONTRACT_EXPECTED_UID}:${PROXY_CONTRACT_EXPECTED_GID}" \
        "${created_temp}"
    chmod 0644 "${created_temp}"
    printf -v "${result_name}" '%s' "${created_temp}"
}

function proxy_contract_cleanup_temps {
    local path

    for path in "${PROXY_CONTRACT_TEMPS[@]}"; do
        if [[ -n "${path}" ]]; then
            rm -f -- "${path}"
        fi
    done
}

function proxy_contract_preflight_cloud_init {
    local cloud_init
    local help_output

    cloud_init="$(command -v cloud-init 2>/dev/null || true)"
    [[ -n "${cloud_init}" && -x "${cloud_init}" ]] \
        || proxy_contract_die "requires the cloud-init command"
    help_output="$("${cloud_init}" clean --help 2>&1)" \
        || proxy_contract_die "could not inspect cloud-init clean support"
    PROXY_CONTRACT_CLOUD_INIT="${cloud_init}"
    PROXY_CONTRACT_CLEAN_ARGS=(clean --logs)
    if grep -Eq -- '(^|[^[:alnum:]_-])--seed([^[:alnum:]_-]|$)' \
        <<< "${help_output}"; then
        PROXY_CONTRACT_CLEAN_ARGS+=(--seed)
    fi
}

function proxy_contract_cloud_init_clean {
    [[ -n "${PROXY_CONTRACT_CLOUD_INIT}" ]] \
        || proxy_contract_die "cloud-init cleanup was not preflighted"
    "${PROXY_CONTRACT_CLOUD_INIT}" "${PROXY_CONTRACT_CLEAN_ARGS[@]}" \
        || proxy_contract_die "cloud-init clean failed"
}

function proxy_contract_cloud_state_clean {
    local path
    local -a absent_paths=(
        /var/lib/cloud/instance
        /var/lib/cloud/seed/nocloud/user-data
        /var/lib/cloud/seed/nocloud-net/user-data
        /var/log/cloud-init.log
        /var/log/cloud-init-output.log
    )
    local directory

    for path in "${absent_paths[@]}"; do
        path="$(proxy_contract_root_path "${path}")"
        if [[ -e "${path}" || -L "${path}" ]]; then
            return 1
        fi
    done
    for directory in /var/lib/cloud/instances /var/lib/cloud/seed; do
        path="$(proxy_contract_root_path "${directory}")"
        if [[ -d "${path}" ]] && find "${path}" -mindepth 1 -print -quit | grep -q .; then
            return 1
        fi
    done
}

function proxy_contract_verify_clean {
    local os_family="$1"
    local identity contract_path path
    local -a identities=()
    local -a paths=()
    local -a ownerships=() markers=() cleanups=() remnants=()
    local index

    proxy_contract_inventory \
        "${os_family}" identities paths ownerships markers cleanups remnants
    for index in "${!identities[@]}"; do
        identity="${identities[index]}"
        contract_path="${paths[index]}"
        proxy_contract_validate_inventory_entry \
            "${identity}" "${contract_path}" "${ownerships[index]}" \
            "${markers[index]}" "${cleanups[index]}" "${remnants[index]}" || return 1
        path="$(proxy_contract_root_path "${contract_path}")"
        case "${ownerships[index]}" in
            dedicated)
                if [[ -e "${path}" || -L "${path}" ]]; then
                    proxy_contract_die "identity ${identity} remains"
                    return 1
                fi
                ;;
            shared)
                if [[ -L "${path}" || ( -e "${path}" && ! -f "${path}" ) ]]; then
                    proxy_contract_die "identity ${identity} is not verifiable"
                    return 1
                fi
                if [[ -f "${path}" ]]; then
                    if grep -Fq -e "${PROXY_CONTRACT_BEGIN}" -e "${PROXY_CONTRACT_END}" "${path}"; then
                        proxy_contract_die "identity ${identity} retains a contract marker"
                        return 1
                    fi
                    case "${identity}" in
                        dnf|git)
                            if grep -Eqi '^[[:space:]]*proxy[[:space:]]*=' "${path}"; then
                                proxy_contract_die "identity ${identity} retains a proxy key"
                                return 1
                            fi
                            ;;
                    esac
                fi
                ;;
        esac
    done
    printf "proxy_contract schema=1 mode=verify-clean os=%s identities=%s clean=true\n" \
        "${os_family}" "${#identities[@]}"
}

function proxy_contract_seal {
    local os_family="$1"
    local identity contract_path path temp
    local -a identities=()
    local -a paths=()
    local -a ownerships=() markers=() cleanups=() remnants=()
    local -a shared_temps=()
    local index

    proxy_contract_inventory \
        "${os_family}" identities paths ownerships markers cleanups remnants
    for index in "${!identities[@]}"; do
        proxy_contract_validate_inventory_entry \
            "${identities[index]}" "${paths[index]}" "${ownerships[index]}" \
            "${markers[index]}" "${cleanups[index]}" "${remnants[index]}"
    done
    proxy_contract_preflight_cloud_init
    if proxy_contract_any_artifact_present "${os_family}"; then
        for index in "${!identities[@]}"; do
            proxy_contract_validate_inventory_entry \
                "${identities[index]}" "${paths[index]}" "${ownerships[index]}" \
                "${markers[index]}" "${cleanups[index]}" "${remnants[index]}"
            proxy_contract_preflight_identity \
                "${identities[index]}" "${paths[index]}" "${ownerships[index]}"
        done

        for index in "${!identities[@]}"; do
            if [[ "${ownerships[index]}" == shared ]]; then
                proxy_contract_prepare_shared_clean \
                    "${identities[index]}" "${paths[index]}" temp
                shared_temps[index]="${temp}"
            fi
        done

        for index in "${!identities[@]}"; do
            identity="${identities[index]}"
            contract_path="${paths[index]}"
            path="$(proxy_contract_root_path "${contract_path}")"
            if [[ "${ownerships[index]}" == dedicated ]]; then
                rm -f -- "${path}"
            else
                mv -f -- "${shared_temps[index]}" "${path}"
                shared_temps[index]=""
            fi
        done
    fi
    proxy_contract_cloud_init_clean
    proxy_contract_verify_clean "${os_family}" >/dev/null
    proxy_contract_cloud_state_clean \
        || proxy_contract_die "cloud-init state or selected logs remain"
    printf "proxy_contract schema=1 mode=seal os=%s identities=%s clean=true\n" \
        "${os_family}" "${#identities[@]}"
}

function proxy_contract_configure_root {
    local test_root="$1"
    local resolved_root

    if [[ -z "${test_root}" ]]; then
        [[ "${EUID}" == "0" ]] \
            || proxy_contract_die "seal and verify clean require root"
        [[ -o privileged ]] \
            || proxy_contract_die "production execution requires privileged Bash mode"
        PROXY_CONTRACT_ROOT="/"
        PROXY_CONTRACT_EXPECTED_UID=0
        PROXY_CONTRACT_EXPECTED_GID=0
        PATH="/usr/sbin:/usr/bin:/sbin:/bin"
        return 0
    fi

    [[ "${test_root}" == /* && -d "${test_root}" && ! -L "${test_root}" ]] \
        || proxy_contract_die "--test-root requires an absolute regular directory"
    resolved_root="$(realpath "${test_root}")"
    [[ "${resolved_root}" == "${test_root%/}" ]] \
        || proxy_contract_die "--test-root must be canonical"
    PROXY_CONTRACT_ROOT="${resolved_root}"
    PROXY_CONTRACT_EXPECTED_UID="${EUID}"
    PROXY_CONTRACT_EXPECTED_GID="$(id -g)"
    PATH="${PROXY_CONTRACT_ROOT}/usr/sbin:${PROXY_CONTRACT_ROOT}/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin"
}

function proxy_contract_main {
    local test_root=""
    local os_family
    local -a operands=()

    while (( $# > 0 )); do
        case "$1" in
            --test-root)
                (( $# >= 2 )) || proxy_contract_die "--test-root requires a path"
                test_root="$2"
                shift 2
                ;;
            *)
                operands+=("$1")
                shift
                ;;
        esac
    done
    [[ "${#operands[@]}" == "1" && "${operands[0]}" == seal ]] ||
        [[ "${#operands[@]}" == "2" && "${operands[0]}" == verify &&
           "${operands[1]}" == clean ]] \
        || proxy_contract_die "usage: proxy_contract.bash [--test-root <absolute-path>] {seal|verify clean}"

    unset BASH_ENV ENV CDPATH TMPDIR TMP TEMP
    export LC_ALL=C
    proxy_contract_configure_root "${test_root}"
    trap proxy_contract_cleanup_temps EXIT
    trap 'exit 1' HUP INT TERM
    os_family="$(proxy_contract_parse_os_release)"
    if [[ "${operands[0]}" == seal ]]; then
        proxy_contract_seal "${os_family}"
    else
        proxy_contract_verify_clean "${os_family}"
    fi
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]] ||
   [[ -z "${BASH_SOURCE[0]:-}" && "$0" == /bin/bash && -o privileged ]]; then
    set -euo pipefail
    proxy_contract_main "$@"
fi
