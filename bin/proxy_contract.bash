#!/usr/bin/env bash
#
# Owns the complete proxy artifact lifecycle from cloud-init apply through
# image publication cleanup.

declare -gr PROXY_CONTRACT_BEGIN="# BEGIN CLOUD-PROVISION PROXY CONTRACT"
declare -gr PROXY_CONTRACT_END="# END CLOUD-PROVISION PROXY CONTRACT"
declare -gr PROXY_CONTRACT_MARKER="cloud-provision-proxy-v1"
declare -gr PROXY_CONTRACT_NO_PROXY="localhost,127.0.0.1,192.168.0.0/16"
declare -gr PROXY_CONTRACT_EXEC_PATH="/usr/sbin:/usr/bin:/sbin:/bin"

declare -gr PROXY_CONTRACT_PROFILE="/etc/profile.d/95cloud-provision-proxy.sh"
declare -gr PROXY_CONTRACT_ENVIRONMENT="/etc/environment"
declare -gr PROXY_CONTRACT_APT="/etc/apt/apt.conf.d/95cloud-provision-proxy"
declare -gr PROXY_CONTRACT_DNF="/etc/dnf/dnf.conf"
declare -gr PROXY_CONTRACT_SUDO="/etc/sudoers.d/95cloud-provision-proxy"
declare -gr PROXY_CONTRACT_SSHD_DROPIN="/etc/ssh/sshd_config.d/95cloud-provision-proxy.conf"
declare -gr PROXY_CONTRACT_SSHD_MAIN="/etc/ssh/sshd_config"
declare -gr PROXY_CONTRACT_SSH_ENVIRONMENT="/home/vmadmin/.ssh/environment"
declare -gr PROXY_CONTRACT_PIP="/etc/pip.conf"
declare -gr PROXY_CONTRACT_GIT="/etc/gitconfig"

declare -gr PROXY_CONTRACT_RUNTIME_DIR="/run/cloud-provision"
declare -gr PROXY_CONTRACT_SCRIPT="${PROXY_CONTRACT_RUNTIME_DIR}/proxy_contract.bash"
declare -gr PROXY_CONTRACT_INPUT="${PROXY_CONTRACT_RUNTIME_DIR}/proxy-contract.input"
declare -gr PROXY_CONTRACT_LOCK="${PROXY_CONTRACT_RUNTIME_DIR}/proxy-contract.lock"

declare -g PROXY_CONTRACT_ROOT="/"
declare -g PROXY_CONTRACT_ROOT_UID=0
declare -g PROXY_CONTRACT_ROOT_GID=0
declare -g PROXY_CONTRACT_VMADMIN_UID=0
declare -g PROXY_CONTRACT_VMADMIN_GID=0
declare -g PROXY_CONTRACT_CLOUD_INIT=""
declare -g PROXY_CONTRACT_VISUDO=""
declare -g PROXY_CONTRACT_SSHD=""
declare -g PROXY_CONTRACT_SYSTEMCTL=""
declare -g PROXY_CONTRACT_WORK_DIR=""
declare -g PROXY_CONTRACT_INPUT_URL=""
declare -g PROXY_CONTRACT_INPUT_HASH=""
declare -ag PROXY_CONTRACT_CLEAN_ARGS=()
declare -ag PROXY_CONTRACT_CREATED_IDENTITIES=()
declare -ag PROXY_CONTRACT_TEMP_PATHS=()

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
        *)
            proxy_contract_die "does not support OS identity: ${os_name}"
            return 1
            ;;
    esac
}

function proxy_contract_validate_url {
    local proxy_url="$1"
    local command_substitution_marker=$'\140'

    if [[ ! "${proxy_url}" =~ ^https?://[^[:space:]]+$ ]] ||
       [[ "${proxy_url}" == *'"'* ]] ||
       [[ "${proxy_url}" == *"'"* ]] ||
       [[ "${proxy_url}" == *\\* ]] ||
       [[ "${proxy_url}" == *'$'* ]] ||
       [[ "${proxy_url}" == *"${command_substitution_marker}"* ]] ||
       [[ "${proxy_url}" == *'!'* ]]; then
        proxy_contract_die "received an invalid proxy URL"
        return 1
    fi
}

function proxy_contract_root_path {
    local path="$1"

    if [[ "${PROXY_CONTRACT_ROOT}" == "/" ]]; then
        printf "%s\n" "${path}"
    else
        printf "%s%s\n" "${PROXY_CONTRACT_ROOT}" "${path}"
    fi
}

function proxy_contract_validate_rooted_path {
    local identity="$1"
    local path="$2"
    local allow_missing_final="$3"
    local relative cursor component
    local -a components=()
    local index last_index

    if [[ "${PROXY_CONTRACT_ROOT}" == "/" ]]; then
        relative="${path#/}"
        cursor=""
    else
        if [[ "${path}" != "${PROXY_CONTRACT_ROOT}"/* ]]; then
            proxy_contract_die "identity ${identity} escapes the selected root"
            return 1
        fi
        relative="${path#"${PROXY_CONTRACT_ROOT}"/}"
        cursor="${PROXY_CONTRACT_ROOT}"
    fi
    IFS='/' read -r -a components <<< "${relative}"
    last_index=$((${#components[@]} - 1))
    for index in "${!components[@]}"; do
        component="${components[index]}"
        if [[ -z "${component}" || "${component}" == "." || "${component}" == ".." ]]; then
            proxy_contract_die "identity ${identity} has an unsafe path component"
            return 1
        fi
        cursor="${cursor}/${component}"
        if (( index == last_index )) && [[ "${allow_missing_final}" == true ]] &&
           [[ ! -e "${cursor}" && ! -L "${cursor}" ]]; then
            continue
        fi
        if [[ -L "${cursor}" ]]; then
            proxy_contract_die "identity ${identity} crosses a symbolic link"
            return 1
        fi
        if (( index < last_index )) && [[ ! -d "${cursor}" ]]; then
            proxy_contract_die "identity ${identity} has a missing parent directory"
            return 1
        fi
    done
}

function proxy_contract_owner_ids {
    local owner="$1"
    local group="$2"
    local uid_name="$3"
    local gid_name="$4"
    local resolved_uid resolved_gid

    case "${owner}:${group}" in
        root:root)
            resolved_uid="${PROXY_CONTRACT_ROOT_UID}"
            resolved_gid="${PROXY_CONTRACT_ROOT_GID}"
            ;;
        vmadmin:vmadmin)
            resolved_uid="${PROXY_CONTRACT_VMADMIN_UID}"
            resolved_gid="${PROXY_CONTRACT_VMADMIN_GID}"
            ;;
        *)
            proxy_contract_die "contains an unsupported owner and group"
            return 1
            ;;
    esac
    printf -v "${uid_name}" '%s' "${resolved_uid}"
    printf -v "${gid_name}" '%s' "${resolved_gid}"
}

function proxy_contract_validate_parent {
    local identity="$1"
    local path="$2"
    local owner="$3"
    local group="$4"
    local parent uid gid mode expected_uid expected_gid

    parent="${path%/*}"
    proxy_contract_validate_rooted_path "${identity}" "${parent}" false || return 1
    if [[ ! -d "${parent}" || -L "${parent}" ]]; then
        proxy_contract_die "identity ${identity} has an unsafe parent directory"
        return 1
    fi
    proxy_contract_owner_ids "${owner}" "${group}" expected_uid expected_gid || return 1
    uid="$(stat -Lc '%u' "${parent}")" || return 1
    gid="$(stat -Lc '%g' "${parent}")" || return 1
    mode="$(stat -Lc '%a' "${parent}")" || return 1
    if [[ "${uid}" != "${expected_uid}" || "${gid}" != "${expected_gid}" ]]; then
        proxy_contract_die "identity ${identity} parent has an ownership conflict"
        return 1
    fi
    if (( (8#${mode} & 8#022) != 0 )); then
        proxy_contract_die "identity ${identity} parent is group or world writable"
        return 1
    fi
}

function proxy_contract_validate_regular_file {
    local identity="$1"
    local path="$2"
    local owner="$3"
    local group="$4"
    local expected_mode="$5"
    local uid gid mode expected_uid expected_gid

    proxy_contract_validate_rooted_path "${identity}" "${path}" false || return 1
    if [[ ! -e "${path}" || -L "${path}" || ! -f "${path}" ]]; then
        proxy_contract_die "identity ${identity} is not a regular file"
        return 1
    fi
    proxy_contract_owner_ids "${owner}" "${group}" expected_uid expected_gid || return 1
    uid="$(stat -Lc '%u' "${path}")" || return 1
    gid="$(stat -Lc '%g' "${path}")" || return 1
    mode="$(stat -Lc '%a' "${path}")" || return 1
    if [[ "${uid}" != "${expected_uid}" || "${gid}" != "${expected_gid}" ||
          "${mode}" != "${expected_mode#0}" ]]; then
        proxy_contract_die "identity ${identity} has an ownership or mode conflict"
        return 1
    fi
}

function proxy_contract_validate_shared_file {
    local identity="$1"
    local path="$2"
    local uid gid mode

    proxy_contract_validate_rooted_path "${identity}" "${path}" false || return 1
    if [[ ! -e "${path}" || -L "${path}" || ! -f "${path}" ]]; then
        proxy_contract_die "identity ${identity} is not a regular shared file"
        return 1
    fi
    uid="$(stat -Lc '%u' "${path}")" || return 1
    gid="$(stat -Lc '%g' "${path}")" || return 1
    mode="$(stat -Lc '%a' "${path}")" || return 1
    if [[ "${uid}" != "${PROXY_CONTRACT_ROOT_UID}" ||
          "${gid}" != "${PROXY_CONTRACT_ROOT_GID}" ]]; then
        proxy_contract_die "identity ${identity} has an ownership conflict"
        return 1
    fi
    if (( (8#${mode} & 8#022) != 0 )); then
        proxy_contract_die "identity ${identity} is group or world writable"
        return 1
    fi
}

function proxy_contract_validate_shared_newline {
    local identity="$1"
    local path="$2"
    local size final_byte

    size="$(stat -Lc '%s' "${path}")" || return 1
    if (( size == 0 )); then
        return 0
    fi
    final_byte="$(od -An -tu1 -j "$((size - 1))" -N 1 -- "${path}")" || return 1
    final_byte="${final_byte//[[:space:]]/}"
    if [[ "${final_byte}" != 10 ]]; then
        proxy_contract_die \
            "identity ${identity} shared file must end with a newline"
        return 1
    fi
}

function proxy_contract_parse_passwd {
    local path name _password uid gid _gecos home _shell
    local matches=0

    path="$(proxy_contract_root_path /etc/passwd)"
    proxy_contract_validate_rooted_path passwd "${path}" false || return 1
    if [[ ! -e "${path}" || -L "${path}" || ! -f "${path}" || ! -r "${path}" ]]; then
        proxy_contract_die "cannot read a regular /etc/passwd"
        return 1
    fi
    while IFS=: read -r name _password uid gid _gecos home _shell || [[ -n "${name}" ]]; do
        if [[ "${name}" == vmadmin ]]; then
            matches=$((matches + 1))
            if [[ ! "${uid}" =~ ^[0-9]+$ || ! "${gid}" =~ ^[0-9]+$ ||
                  "${home}" != "/home/vmadmin" ]]; then
                proxy_contract_die "vmadmin has invalid passwd metadata"
                return 1
            fi
            PROXY_CONTRACT_VMADMIN_UID="${uid}"
            PROXY_CONTRACT_VMADMIN_GID="${gid}"
        fi
    done < "${path}"
    if [[ "${matches}" != 1 ]]; then
        proxy_contract_die "/etc/passwd must contain exactly one vmadmin entry"
        return 1
    fi
}

function proxy_contract_normalize_relative_target {
    local base_relative="$1"
    local target="$2"
    local result_name="$3"
    local component normalized_relative
    local -a components=() stack=()

    IFS='/' read -r -a components <<< "${base_relative}/${target}"
    for component in "${components[@]}"; do
        case "${component}" in
            ""|.) ;;
            ..)
                if [[ "${#stack[@]}" == 0 ]]; then
                    proxy_contract_die "/etc/os-release escapes the selected root"
                    return 1
                fi
                unset 'stack[${#stack[@]}-1]'
                ;;
            *) stack+=("${component}") ;;
        esac
    done
    if [[ "${#stack[@]}" == 0 ]]; then
        proxy_contract_die "/etc/os-release escapes the selected root"
        return 1
    fi
    normalized_relative="$(IFS=/; printf '%s' "${stack[*]}")"
    if [[ "${PROXY_CONTRACT_ROOT}" == "/" ]]; then
        printf -v "${result_name}" '/%s' "${normalized_relative}"
    else
        printf -v "${result_name}" '%s/%s' \
            "${PROXY_CONTRACT_ROOT}" "${normalized_relative}"
    fi
}

function proxy_contract_resolve_os_release {
    local path parent target normalized relative_parent relative cursor component
    local -a components=()

    path="$(proxy_contract_root_path /etc/os-release)"
    parent="${path%/*}"
    proxy_contract_validate_rooted_path os-release "${parent}" false || return 1
    if [[ -L "${path}" ]]; then
        target="$(readlink -- "${path}")" || return 1
        if [[ -z "${target}" || "${target}" == /* ]]; then
            proxy_contract_die "/etc/os-release has an unsafe symbolic link"
            return 1
        fi
        if [[ "${PROXY_CONTRACT_ROOT}" == "/" ]]; then
            relative_parent="${parent#/}"
            proxy_contract_normalize_relative_target \
                "${relative_parent}" "${target}" normalized || return 1
            relative="${normalized#/}"
            cursor=""
        else
            relative_parent="${parent#"${PROXY_CONTRACT_ROOT}"/}"
            proxy_contract_normalize_relative_target \
                "${relative_parent}" "${target}" normalized || return 1
            relative="${normalized#"${PROXY_CONTRACT_ROOT}"/}"
            cursor="${PROXY_CONTRACT_ROOT}"
        fi
        IFS='/' read -r -a components <<< "${relative}"
        for component in "${components[@]}"; do
            cursor="${cursor}/${component}"
            if [[ -L "${cursor}" ]]; then
                proxy_contract_die "/etc/os-release crosses a parent symbolic link"
                return 1
            fi
        done
        path="${normalized}"
    else
        proxy_contract_validate_rooted_path os-release "${path}" false || return 1
    fi
    if [[ ! -e "${path}" || -L "${path}" || ! -f "${path}" || ! -r "${path}" ]]; then
        proxy_contract_die "cannot read a regular /etc/os-release"
        return 1
    fi
    printf '%s\n' "${path}"
}

function proxy_contract_parse_os_release {
    local path line value=""
    local id_count=0

    if ! path="$(proxy_contract_resolve_os_release)"; then
        return 1
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^ID=(.*)$ ]]; then
            value="${BASH_REMATCH[1]}"
            id_count=$((id_count + 1))
        fi
    done < "${path}"
    if [[ "${id_count}" != 1 ]]; then
        proxy_contract_die "/etc/os-release must contain exactly one ID field"
        return 1
    fi
    case "${value}" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    if [[ ! "${value}" =~ ^[a-z0-9._-]+$ ]]; then
        proxy_contract_die "/etc/os-release contains an invalid ID field"
        return 1
    fi
    proxy_contract_os_family "${value}"
}

function proxy_contract_inventory_add {
    local -n identities_ref="$1"
    local -n paths_ref="$2"
    local -n owners_ref="$3"
    local -n groups_ref="$4"
    local -n modes_ref="$5"
    local -n forms_ref="$6"
    local -n markers_ref="$7"
    local -n cleanups_ref="$8"
    local -n remnants_ref="$9"
    shift 9

    identities_ref+=("$1")
    paths_ref+=("$2")
    owners_ref+=("$3")
    groups_ref+=("$4")
    modes_ref+=("$5")
    forms_ref+=("$6")
    markers_ref+=("$7")
    cleanups_ref+=("$8")
    remnants_ref+=("$9")
}

# The output arrays are selected by caller-provided names.
# shellcheck disable=SC2178
function proxy_contract_inventory {
    local os_family="$1"
    local identities_name="$2" paths_name="$3" owners_name="$4"
    local groups_name="$5" modes_name="$6" forms_name="$7"
    local markers_name="$8" cleanups_name="$9" remnants_name="${10}"
    local -n identities_ref="${identities_name}"
    local -n paths_ref="${paths_name}"
    local -n owners_ref="${owners_name}"
    local -n groups_ref="${groups_name}"
    local -n modes_ref="${modes_name}"
    local -n forms_ref="${forms_name}"
    local -n markers_ref="${markers_name}"
    local -n cleanups_ref="${cleanups_name}"
    local -n remnants_ref="${remnants_name}"

    identities_ref=()
    paths_ref=()
    owners_ref=()
    groups_ref=()
    modes_ref=()
    forms_ref=()
    markers_ref=()
    cleanups_ref=()
    remnants_ref=()

    proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" profile "${PROXY_CONTRACT_PROFILE}" root root 0644 dedicated "${PROXY_CONTRACT_MARKER}" required required # inventory:profile
    proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" environment "${PROXY_CONTRACT_ENVIRONMENT}" root root 0644 shared "${PROXY_CONTRACT_MARKER}" required required # inventory:environment
    case "${os_family}" in
        debian|ubuntu)
            proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" apt "${PROXY_CONTRACT_APT}" root root 0644 dedicated "${PROXY_CONTRACT_MARKER}" required required # inventory:apt
            proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" sudo "${PROXY_CONTRACT_SUDO}" root root 0440 dedicated "${PROXY_CONTRACT_MARKER}" required required # inventory:sudo
            proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" sshd "${PROXY_CONTRACT_SSHD_DROPIN}" root root 0644 dedicated "${PROXY_CONTRACT_MARKER}" required required # inventory:sshd
            ;;
        rocky)
            proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" dnf "${PROXY_CONTRACT_DNF}" root root 0644 shared "${PROXY_CONTRACT_MARKER}" required required # inventory:dnf
            proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" sshd "${PROXY_CONTRACT_SSHD_MAIN}" root root 0644 shared "${PROXY_CONTRACT_MARKER}" required required # inventory:sshd
            ;;
        *)
            proxy_contract_die "contains an unsupported inventory OS family"
            return 1
            ;;
    esac
    proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" ssh-environment "${PROXY_CONTRACT_SSH_ENVIRONMENT}" vmadmin vmadmin 0600 dedicated "${PROXY_CONTRACT_MARKER}" required required # inventory:ssh-environment
    proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" pip "${PROXY_CONTRACT_PIP}" root root 0644 dedicated "${PROXY_CONTRACT_MARKER}" required required # inventory:pip
    proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" git "${PROXY_CONTRACT_GIT}" root root 0644 shared "${PROXY_CONTRACT_MARKER}" required required # inventory:git
}

function proxy_contract_validate_inventory_entry {
    local os_family="$1" identity="$2" path="$3" owner="$4" group="$5"
    local mode="$6" form="$7" marker="$8" cleanup="$9" remnant="${10}"
    local expected=""

    case "${os_family}:${identity}" in
        debian:profile|ubuntu:profile|rocky:profile) expected="${PROXY_CONTRACT_PROFILE}|root|root|0644|dedicated" ;;
        debian:environment|ubuntu:environment|rocky:environment) expected="${PROXY_CONTRACT_ENVIRONMENT}|root|root|0644|shared" ;;
        debian:apt|ubuntu:apt) expected="${PROXY_CONTRACT_APT}|root|root|0644|dedicated" ;;
        rocky:dnf) expected="${PROXY_CONTRACT_DNF}|root|root|0644|shared" ;;
        debian:sudo|ubuntu:sudo) expected="${PROXY_CONTRACT_SUDO}|root|root|0440|dedicated" ;;
        debian:sshd|ubuntu:sshd) expected="${PROXY_CONTRACT_SSHD_DROPIN}|root|root|0644|dedicated" ;;
        rocky:sshd) expected="${PROXY_CONTRACT_SSHD_MAIN}|root|root|0644|shared" ;;
        debian:ssh-environment|ubuntu:ssh-environment|rocky:ssh-environment) expected="${PROXY_CONTRACT_SSH_ENVIRONMENT}|vmadmin|vmadmin|0600|dedicated" ;;
        debian:pip|ubuntu:pip|rocky:pip) expected="${PROXY_CONTRACT_PIP}|root|root|0644|dedicated" ;;
        debian:git|ubuntu:git|rocky:git) expected="${PROXY_CONTRACT_GIT}|root|root|0644|shared" ;;
        *)
            proxy_contract_die "contains an unknown inventory identity ${identity}"
            return 1
            ;;
    esac
    if [[ "${path}|${owner}|${group}|${mode}|${form}" != "${expected}" ||
          "${marker}" != "${PROXY_CONTRACT_MARKER}" ||
          "${cleanup}" != required || "${remnant}" != required ]]; then
        proxy_contract_die "contains invalid inventory metadata for ${identity}"
        return 1
    fi
}

function proxy_contract_print_inventory {
    local os_family="$1" index
    local -a identities=() paths=() owners=() groups=() modes=() forms=()
    local -a markers=() cleanups=() remnants=()

    proxy_contract_inventory "${os_family}" identities paths owners groups modes forms markers cleanups remnants || return 1
    for index in "${!identities[@]}"; do
        proxy_contract_validate_inventory_entry "${os_family}" "${identities[index]}" "${paths[index]}" "${owners[index]}" "${groups[index]}" "${modes[index]}" "${forms[index]}" "${markers[index]}" "${cleanups[index]}" "${remnants[index]}" || return 1
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${os_family}" "${identities[index]}" "${paths[index]}" \
            "${owners[index]}" "${groups[index]}" "${modes[index]}" \
            "${forms[index]}" "${markers[index]}" "${cleanups[index]}" \
            "${remnants[index]}"
    done
}

function proxy_contract_write_block {
    local identity="$1"
    local proxy_url="$2"

    printf '%s\n' "${PROXY_CONTRACT_BEGIN}"
    case "${identity}" in
        profile)
            printf 'export http_proxy="%s"\n' "${proxy_url}"
            printf 'export https_proxy="%s"\n' "${proxy_url}"
            printf 'export ftp_proxy="%s"\n' "${proxy_url}"
            printf 'export no_proxy="%s"\n' "${PROXY_CONTRACT_NO_PROXY}"
            printf '%s\n' 'export HTTP_PROXY="$http_proxy"'
            printf '%s\n' 'export HTTPS_PROXY="$https_proxy"'
            printf '%s\n' 'export FTP_PROXY="$ftp_proxy"'
            printf '%s\n' 'export NO_PROXY="$no_proxy"'
            ;;
        environment|ssh-environment)
            printf 'http_proxy="%s"\n' "${proxy_url}"
            printf 'https_proxy="%s"\n' "${proxy_url}"
            printf 'ftp_proxy="%s"\n' "${proxy_url}"
            printf 'no_proxy="%s"\n' "${PROXY_CONTRACT_NO_PROXY}"
            printf 'HTTP_PROXY="%s"\n' "${proxy_url}"
            printf 'HTTPS_PROXY="%s"\n' "${proxy_url}"
            printf 'FTP_PROXY="%s"\n' "${proxy_url}"
            printf 'NO_PROXY="%s"\n' "${PROXY_CONTRACT_NO_PROXY}"
            ;;
        apt)
            printf 'Acquire::http::Proxy "%s";\n' "${proxy_url}"
            printf 'Acquire::https::Proxy "%s";\n' "${proxy_url}"
            ;;
        dnf)
            printf 'proxy=%s\n' "${proxy_url}"
            ;;
        sudo)
            printf '%s\n' 'Defaults env_keep += "http_proxy https_proxy ftp_proxy no_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY NO_PROXY"'
            ;;
        sshd)
            printf '%s\n' 'PermitUserEnvironment yes'
            ;;
        pip)
            printf '%s\n' '[global]'
            printf 'proxy = %s\n' "${proxy_url}"
            ;;
        git)
            printf '%s\n' '[http]'
            printf '    proxy = %s\n' "${proxy_url}"
            printf '%s\n' '[https]'
            printf '    proxy = %s\n' "${proxy_url}"
            ;;
        *)
            proxy_contract_die "cannot render unknown identity ${identity}"
            return 1
            ;;
    esac
    printf '%s\n' "${PROXY_CONTRACT_END}"
}

function proxy_contract_render_yaml_source {
    local path="$1"
    local owner="$2"
    local mode="$3"
    local source_path="$4"
    local line

    printf '  - path: %s\n' "${path}"
    printf '    owner: %s\n' "${owner}"
    printf "    permissions: '%s'\n" "${mode}"
    printf '    content: |\n'
    while IFS= read -r line || [[ -n "${line}" ]]; do
        printf '      %s\n' "${line}"
    done < "${source_path}"
}

function proxy_contract_render_write_files {
    local os_name="$1"
    local proxy_url="$2"
    local source_path script_hash

    proxy_contract_os_family "${os_name}" >/dev/null || return 1
    proxy_contract_validate_url "${proxy_url}" || return 1
    source_path="${BASH_SOURCE[0]:-}"
    if [[ -z "${source_path}" || ! -e "${source_path}" || -L "${source_path}" ||
          ! -f "${source_path}" ]]; then
        proxy_contract_die "cannot stage the shipped contract source"
        return 1
    fi
    source_path="$(realpath -e -- "${source_path}")" || return 1
    script_hash="$(sha256sum "${source_path}")"
    script_hash="${script_hash%% *}"

    printf 'write_files:\n'
    proxy_contract_render_yaml_source \
        "${PROXY_CONTRACT_SCRIPT}" root:root 0700 "${source_path}" || return 1
    printf '  - path: %s\n' "${PROXY_CONTRACT_INPUT}"
    printf '    owner: root:root\n'
    printf "    permissions: '0600'\n"
    printf '    content: |\n'
    printf '      schema=1\n'
    printf '      proxy_url=%s\n' "${proxy_url}"
    printf '      script_sha256=%s\n' "${script_hash}"
}

function proxy_contract_validate_marker_shape {
    local identity="$1"
    local path="$2"
    local form="$3"
    local begin_count end_count first_line last_line

    begin_count="$(grep -Fxc -- "${PROXY_CONTRACT_BEGIN}" "${path}" || true)"
    end_count="$(grep -Fxc -- "${PROXY_CONTRACT_END}" "${path}" || true)"
    if [[ "${begin_count}" != 1 || "${end_count}" != 1 ]]; then
        proxy_contract_die "identity ${identity} has missing or duplicate markers"
        return 1
    fi
    if grep -F 'CLOUD-PROVISION PROXY CONTRACT' "${path}" \
        | grep -Fvx -e "${PROXY_CONTRACT_BEGIN}" -e "${PROXY_CONTRACT_END}" \
        | grep -q .; then
        proxy_contract_die "identity ${identity} has an orphan marker"
        return 1
    fi
    if ! awk -v begin="${PROXY_CONTRACT_BEGIN}" -v end="${PROXY_CONTRACT_END}" '
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
    ' "${path}"; then
        proxy_contract_die "identity ${identity} has nested or orphan markers"
        return 1
    fi
    if [[ "${form}" == dedicated ]]; then
        IFS= read -r first_line < "${path}" || true
        last_line="$(tail -n 1 "${path}")"
        if [[ "${first_line}" != "${PROXY_CONTRACT_BEGIN}" ||
              "${last_line}" != "${PROXY_CONTRACT_END}" ]]; then
            proxy_contract_die "dedicated identity ${identity} has content outside its markers"
            return 1
        fi
    fi
}

function proxy_contract_key_pattern {
    local identity="$1"

    case "${identity}" in
        environment|ssh-environment)
            printf '%s\n' '^[[:space:]]*(http_proxy|https_proxy|ftp_proxy|no_proxy|HTTP_PROXY|HTTPS_PROXY|FTP_PROXY|NO_PROXY)[[:space:]]*='
            ;;
        dnf|git|pip)
            printf '%s\n' '^[[:space:]]*[Pp][Rr][Oo][Xx][Yy][[:space:]]*='
            ;;
        sudo)
            printf '%s\n' '^[[:space:]]*Defaults[[:space:]].*(http_proxy|HTTP_PROXY)'
            ;;
        sshd)
            printf '%s\n' '^[[:space:]]*[Pp][Ee][Rr][Mm][Ii][Tt][Uu][Ss][Ee][Rr][Ee][Nn][Vv][Ii][Rr][Oo][Nn][Mm][Ee][Nn][Tt][[:space:]]+'
            ;;
        *) printf '%s\n' '^$' ;;
    esac
}

function proxy_contract_validate_unowned_keys {
    local identity="$1"
    local path="$2"
    local key_pattern

    key_pattern="$(proxy_contract_key_pattern "${identity}")" || return 1
    if ! awk -v begin="${PROXY_CONTRACT_BEGIN}" -v end="${PROXY_CONTRACT_END}" \
        -v key_pattern="${key_pattern}" '
        $0 == begin { inside = 1; next }
        $0 == end { inside = 0; next }
        !inside && $0 !~ /^[[:space:]]*#/ && $0 ~ key_pattern { found = 1 }
        END { exit found }
    ' "${path}"; then
        proxy_contract_die "identity ${identity} has a relevant unowned proxy key"
        return 1
    fi
}

function proxy_contract_validate_shared_placement {
    local os_family="$1"
    local identity="$2"
    local path="$3"

    case "${identity}" in
        dnf)
            if ! awk -v begin="${PROXY_CONTRACT_BEGIN}" '
                $0 == begin {
                    found = 1
                    if (section != "main") invalid = 1
                    next
                }
                /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
                    section = $0
                    sub(/^[[:space:]]*\[/, "", section)
                    sub(/\][[:space:]]*$/, "", section)
                    section = tolower(section)
                    if (section == "main") main_count++
                }
                END { exit (!found || invalid || main_count != 1) }
            ' "${path}"; then
                proxy_contract_die \
                    "identity dnf contract block is not in one main section"
                return 1
            fi
            ;;
        sshd)
            if [[ "${os_family}" != rocky ]]; then
                proxy_contract_die "shared sshd is supported only on Rocky"
                return 1
            fi
            if ! awk -v begin="${PROXY_CONTRACT_BEGIN}" '
                $0 == begin {
                    found = 1
                    if (in_match) invalid = 1
                    next
                }
                /^[[:space:]]*#/ { next }
                /^[[:space:]]*[Mm][Aa][Tt][Cc][Hh][[:space:]]+/ {
                    in_match = 1
                }
                END { exit (!found || invalid) }
            ' "${path}"; then
                proxy_contract_die \
                    "identity sshd contract block is not in global scope"
                return 1
            fi
            ;;
        environment|git) ;;
        *)
            proxy_contract_die \
                "cannot validate placement for shared identity ${identity}"
            return 1
            ;;
    esac
}

function proxy_contract_append_block {
    local identity="$1"
    local proxy_url="$2"
    local source_path="$3"
    local destination="$4"
    local size

    : > "${destination}"
    if [[ -n "${source_path}" ]]; then
        size="$(stat -Lc '%s' "${source_path}")" || return 1
        if (( size > 0 )); then
            head -c "${size}" "${source_path}" >> "${destination}"
        fi
    fi
    proxy_contract_write_block "${identity}" "${proxy_url}" >> "${destination}"
}

function proxy_contract_splice_block {
    local identity="$1"
    local proxy_url="$2"
    local source_path="$3"
    local destination="$4"
    local offset="$5"
    local tail_start

    [[ "${offset}" =~ ^[0-9]+$ ]] || {
        proxy_contract_die "identity ${identity} has an invalid insertion offset"
        return 1
    }
    : > "${destination}"
    if (( offset > 0 )); then
        head -c "${offset}" "${source_path}" >> "${destination}"
    fi
    proxy_contract_write_block "${identity}" "${proxy_url}" >> "${destination}"
    tail_start=$((offset + 1))
    tail -c "+${tail_start}" "${source_path}" >> "${destination}"
}

function proxy_contract_insert_after_main {
    local identity="$1"
    local proxy_url="$2"
    local source_path="$3"
    local destination="$4"
    local offset

    offset="$(awk '
        { next_offset = offset + length($0) + 1 }
        /^[[:space:]]*\[main\][[:space:]]*$/ { print next_offset; exit }
        { offset = next_offset }
    ' "${source_path}")"
    if [[ ! "${offset}" =~ ^[0-9]+$ ]]; then
        proxy_contract_die "identity ${identity} requires exactly one main section"
        return 1
    fi
    proxy_contract_splice_block \
        "${identity}" "${proxy_url}" "${source_path}" "${destination}" "${offset}"
}

function proxy_contract_insert_before_match {
    local identity="$1"
    local proxy_url="$2"
    local source_path="$3"
    local destination="$4"
    local offset

    offset="$(awk '
        /^[[:space:]]*#/ { offset += length($0) + 1; next }
        /^[[:space:]]*[Mm][Aa][Tt][Cc][Hh][[:space:]]+/ { print offset; found = 1; exit }
        { offset += length($0) + 1 }
        END { if (!found) print offset }
    ' "${source_path}")"
    proxy_contract_splice_block \
        "${identity}" "${proxy_url}" "${source_path}" "${destination}" "${offset}"
}

function proxy_contract_render_candidate {
    local os_family="$1"
    local identity="$2"
    local form="$3"
    local proxy_url="$4"
    local current_path="$5"
    local destination="$6"

    if [[ "${form}" == dedicated ]]; then
        proxy_contract_write_block "${identity}" "${proxy_url}" > "${destination}"
        return
    fi
    case "${identity}" in
        environment|git)
            proxy_contract_append_block \
                "${identity}" "${proxy_url}" "${current_path}" "${destination}"
            ;;
        dnf)
            proxy_contract_insert_after_main \
                "${identity}" "${proxy_url}" "${current_path}" "${destination}"
            ;;
        sshd)
            if [[ "${os_family}" != rocky ]]; then
                proxy_contract_die "shared sshd is supported only on Rocky"
                return 1
            fi
            proxy_contract_insert_before_match \
                "${identity}" "${proxy_url}" "${current_path}" "${destination}"
            ;;
        *)
            proxy_contract_die "cannot render shared identity ${identity}"
            return 1
            ;;
    esac
}

function proxy_contract_remove_block {
    local identity="$1"
    local source_path="$2"
    local destination="$3"

    local begin_offset end_offset block_end next_byte tail_start

    begin_offset="$(grep -aboF -m1 -- "${PROXY_CONTRACT_BEGIN}" "${source_path}")"
    begin_offset="${begin_offset%%:*}"
    end_offset="$(grep -aboF -m1 -- "${PROXY_CONTRACT_END}" "${source_path}")"
    end_offset="${end_offset%%:*}"
    if [[ ! "${begin_offset}" =~ ^[0-9]+$ || ! "${end_offset}" =~ ^[0-9]+$ ]]; then
        proxy_contract_die "could not resolve marker offsets for ${identity}"
        return 1
    fi
    block_end=$((end_offset + ${#PROXY_CONTRACT_END}))
    next_byte="$(dd if="${source_path}" bs=1 skip="${block_end}" count=1 status=none \
        | od -An -tu1 | tr -d '[:space:]')"
    [[ "${next_byte}" == 10 ]] || {
        proxy_contract_die "identity ${identity} block does not end with a newline"
        return 1
    }
    block_end=$((block_end + 1))
    : > "${destination}"
    if (( begin_offset > 0 )); then
        head -c "${begin_offset}" "${source_path}" >> "${destination}"
    fi
    tail_start=$((block_end + 1))
    tail -c "+${tail_start}" "${source_path}" >> "${destination}"
}

function proxy_contract_extract_block {
    local source_path="$1"
    local destination="$2"

    awk -v begin="${PROXY_CONTRACT_BEGIN}" -v end="${PROXY_CONTRACT_END}" '
        $0 == begin { inside = 1 }
        inside { print }
        $0 == end { inside = 0 }
    ' "${source_path}" > "${destination}"
}

function proxy_contract_validate_exact_content {
    local identity="$1"
    local path="$2"
    local form="$3"
    local proxy_url="$4"
    local expected actual

    expected="${PROXY_CONTRACT_WORK_DIR}/expected-${identity}"
    proxy_contract_write_block "${identity}" "${proxy_url}" > "${expected}" || return 1
    PROXY_CONTRACT_TEMP_PATHS+=("${expected}")
    if [[ "${form}" == dedicated ]]; then
        if ! cmp -s -- "${expected}" "${path}"; then
            proxy_contract_die "identity ${identity} does not match exact contract content"
            return 1
        fi
    else
        actual="${PROXY_CONTRACT_WORK_DIR}/actual-${identity}"
        proxy_contract_extract_block "${path}" "${actual}" || return 1
        PROXY_CONTRACT_TEMP_PATHS+=("${actual}")
        if ! cmp -s -- "${expected}" "${actual}"; then
            proxy_contract_die "identity ${identity} has an unexpected contract block"
            return 1
        fi
    fi
}

function proxy_contract_require_sshd_include {
    local path

    path="$(proxy_contract_root_path /etc/ssh/sshd_config)"
    proxy_contract_validate_parent sshd-include "${path}" root root || return 1
    proxy_contract_validate_shared_file sshd-include "${path}" || return 1
    if ! awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*[Mm][Aa][Tt][Cc][Hh][[:space:]]+/ { in_match = 1 }
        !in_match && /^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]]+/ &&
            $0 ~ /\/etc\/ssh\/sshd_config[.]d\/[*][.]conf/ { found = 1 }
        END { exit !found }
    ' "${path}"; then
        proxy_contract_die "sshd does not include /etc/ssh/sshd_config.d/*.conf globally"
        return 1
    fi
}

function proxy_contract_preflight_apply_identity {
    local os_family="$1"
    local identity="$2"
    local contract_path="$3"
    local owner="$4"
    local group="$5"
    local form="$6"
    local path main_count

    path="$(proxy_contract_root_path "${contract_path}")"
    proxy_contract_validate_parent \
        "${identity}" "${path}" "${owner}" "${group}" || return 1
    proxy_contract_validate_rooted_path "${identity}" "${path}" true || return 1
    if [[ "${form}" == dedicated ]]; then
        if [[ -e "${path}" || -L "${path}" ]]; then
            proxy_contract_die "identity ${identity} conflicts with an existing path"
            return 1
        fi
    elif [[ -e "${path}" || -L "${path}" ]]; then
        proxy_contract_validate_shared_file "${identity}" "${path}" || return 1
        proxy_contract_validate_shared_newline "${identity}" "${path}" || return 1
        if grep -Fq -e "${PROXY_CONTRACT_BEGIN}" -e "${PROXY_CONTRACT_END}" "${path}"; then
            proxy_contract_die "identity ${identity} already contains a contract marker"
            return 1
        fi
        proxy_contract_validate_unowned_keys "${identity}" "${path}" || return 1
    elif [[ "${identity}" == dnf || "${identity}" == sshd ]]; then
        proxy_contract_die "identity ${identity} requires an existing shared file"
        return 1
    fi

    case "${identity}" in
        dnf)
            main_count="$(grep -Ec '^[[:space:]]*\[main\][[:space:]]*$' "${path}" || true)"
            if [[ "${main_count}" != 1 ]]; then
                proxy_contract_die "identity dnf requires exactly one main section"
                return 1
            fi
            ;;
        sshd)
            if [[ "${os_family}" == rocky ]]; then
                proxy_contract_validate_unowned_keys sshd "${path}" || return 1
            else
                proxy_contract_require_sshd_include || return 1
            fi
            ;;
    esac
}

function proxy_contract_preflight_seal_identity {
    local os_family="$1"
    local identity="$2"
    local contract_path="$3"
    local owner="$4"
    local group="$5"
    local mode="$6"
    local form="$7"
    local proxy_url="$8"
    local path

    path="$(proxy_contract_root_path "${contract_path}")"
    proxy_contract_validate_parent \
        "${identity}" "${path}" "${owner}" "${group}" || return 1
    if [[ "${form}" == dedicated ]]; then
        proxy_contract_validate_regular_file \
            "${identity}" "${path}" "${owner}" "${group}" "${mode}" || return 1
    else
        proxy_contract_validate_shared_file "${identity}" "${path}" || return 1
    fi
    proxy_contract_validate_marker_shape "${identity}" "${path}" "${form}" || return 1
    if [[ "${form}" == shared ]]; then
        proxy_contract_validate_shared_placement \
            "${os_family}" "${identity}" "${path}" || return 1
    fi
    proxy_contract_validate_unowned_keys "${identity}" "${path}" || return 1
    proxy_contract_validate_exact_content \
        "${identity}" "${path}" "${form}" "${proxy_url}" || return 1
    if [[ "${identity}" == sshd && "${os_family}" != rocky ]]; then
        proxy_contract_require_sshd_include || return 1
    fi
}

function proxy_contract_validate_transient_file {
    local identity="$1"
    local contract_path="$2"
    local mode="$3"
    local path

    path="$(proxy_contract_root_path "${contract_path}")"
    proxy_contract_validate_parent "${identity}" "${path}" root root || return 1
    proxy_contract_validate_regular_file \
        "${identity}" "${path}" root root "${mode}"
}

function proxy_contract_parse_input {
    local path line
    local schema="" proxy_url="" script_hash=""
    local schema_count=0 proxy_count=0 hash_count=0

    proxy_contract_validate_transient_file \
        contract-input "${PROXY_CONTRACT_INPUT}" 0600 || return 1
    path="$(proxy_contract_root_path "${PROXY_CONTRACT_INPUT}")"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            schema=*)
                schema="${line#schema=}"
                schema_count=$((schema_count + 1))
                ;;
            proxy_url=*)
                proxy_url="${line#proxy_url=}"
                proxy_count=$((proxy_count + 1))
                ;;
            script_sha256=*)
                script_hash="${line#script_sha256=}"
                hash_count=$((hash_count + 1))
                ;;
            *)
                proxy_contract_die "contract input contains an unknown field"
                return 1
                ;;
        esac
    done < "${path}"
    if [[ "${schema_count}" != 1 || "${proxy_count}" != 1 ||
          "${hash_count}" != 1 || "${schema}" != 1 ||
          ! "${script_hash}" =~ ^[0-9a-f]{64}$ ]]; then
        proxy_contract_die "contract input does not match schema 1"
        return 1
    fi
    proxy_contract_validate_url "${proxy_url}" || return 1
    PROXY_CONTRACT_INPUT_URL="${proxy_url}"
    PROXY_CONTRACT_INPUT_HASH="${script_hash}"
}

function proxy_contract_validate_staged_script {
    local path actual_hash

    proxy_contract_validate_transient_file \
        contract-script "${PROXY_CONTRACT_SCRIPT}" 0700 || return 1
    path="$(proxy_contract_root_path "${PROXY_CONTRACT_SCRIPT}")"
    actual_hash="$(sha256sum "${path}")"
    actual_hash="${actual_hash%% *}"
    if [[ "${actual_hash}" != "${PROXY_CONTRACT_INPUT_HASH}" ]]; then
        proxy_contract_die "contract-script does not match the staged checksum"
        return 1
    fi
}

function proxy_contract_write_lock {
    local path="$1"
    local created_csv="$2"

    if ! (set -o noclobber; : > "${path}") 2>/dev/null; then
        proxy_contract_die "contract-lock already exists"
        return 1
    fi
    chown "${PROXY_CONTRACT_ROOT_UID}:${PROXY_CONTRACT_ROOT_GID}" "${path}" || return 1
    chmod 0600 "${path}" || return 1
    printf 'schema=1\nstate=applied\ncreated=%s\n' "${created_csv}" > "${path}"
}

function proxy_contract_parse_lock {
    local path line schema="" state="" created="" identity
    local schema_count=0 state_count=0 created_count=0
    local -a values=()

    proxy_contract_validate_transient_file \
        contract-lock "${PROXY_CONTRACT_LOCK}" 0600 || return 1
    path="$(proxy_contract_root_path "${PROXY_CONTRACT_LOCK}")"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            schema=*)
                schema="${line#schema=}"
                schema_count=$((schema_count + 1))
                ;;
            state=*)
                state="${line#state=}"
                state_count=$((state_count + 1))
                ;;
            created=*)
                created="${line#created=}"
                created_count=$((created_count + 1))
                ;;
            *)
                proxy_contract_die "contract-lock contains an unknown field"
                return 1
                ;;
        esac
    done < "${path}"
    if [[ "${schema_count}" != 1 || "${state_count}" != 1 ||
          "${created_count}" != 1 || "${schema}" != 1 || "${state}" != applied ]]; then
        proxy_contract_die "contract-lock does not match schema 1"
        return 1
    fi
    PROXY_CONTRACT_CREATED_IDENTITIES=()
    if [[ -n "${created}" ]]; then
        IFS=',' read -r -a values <<< "${created}"
        for identity in "${values[@]}"; do
            case "${identity}" in
                environment|git)
                    PROXY_CONTRACT_CREATED_IDENTITIES+=("${identity}")
                    ;;
                *)
                    proxy_contract_die \
                        "contract-lock contains an invalid created identity"
                    return 1
                    ;;
            esac
        done
    fi
}

function proxy_contract_identity_was_created {
    local wanted="$1"
    local identity

    for identity in "${PROXY_CONTRACT_CREATED_IDENTITIES[@]}"; do
        [[ "${identity}" == "${wanted}" ]] && return 0
    done
    return 1
}

function proxy_contract_create_work_dir {
    local runtime_path

    runtime_path="$(proxy_contract_root_path "${PROXY_CONTRACT_RUNTIME_DIR}")"
    proxy_contract_validate_rooted_path \
        runtime-directory "${runtime_path}" false || return 1
    if [[ ! -d "${runtime_path}" || -L "${runtime_path}" ]]; then
        proxy_contract_die "runtime directory is not a regular directory"
        return 1
    fi
    PROXY_CONTRACT_WORK_DIR="$(mktemp -d "${runtime_path}/.proxy-contract.XXXXXX")" || {
        proxy_contract_die "could not create the contract work directory"
        return 1
    }
}

function proxy_contract_cleanup_temps {
    local path

    for path in "${PROXY_CONTRACT_TEMP_PATHS[@]}"; do
        [[ -n "${path}" ]] && rm -f -- "${path}"
    done
    PROXY_CONTRACT_TEMP_PATHS=()
    if [[ -n "${PROXY_CONTRACT_WORK_DIR}" && -d "${PROXY_CONTRACT_WORK_DIR}" ]]; then
        find "${PROXY_CONTRACT_WORK_DIR}" \
            -mindepth 1 -maxdepth 1 -type f -delete
        rmdir -- "${PROXY_CONTRACT_WORK_DIR}" 2>/dev/null || true
    fi
    PROXY_CONTRACT_WORK_DIR=""
}

function proxy_contract_resolve_guest_command {
    local command_name="$1"
    local result_name="$2"
    local contract_path path resolved

    case "${command_name}" in
        cloud-init) contract_path="/usr/bin/cloud-init" ;;
        visudo) contract_path="/usr/sbin/visudo" ;;
        sshd) contract_path="/usr/sbin/sshd" ;;
        systemctl) contract_path="/usr/bin/systemctl" ;;
        *)
            proxy_contract_die "requested an unsupported guest command"
            return 1
            ;;
    esac
    path="$(proxy_contract_root_path "${contract_path}")"
    # An alternatives-managed command (for example resolute's sudo-rs visudo)
    # is a symbolic link to a regular executable. Resolve it to its canonical
    # target and validate that target. The rooted-path walk below still rejects
    # a target that leaves the selected root, so resolution stays in-root and
    # there is no host fallback.
    if [[ -L "${path}" ]]; then
        resolved="$(readlink -f -- "${path}" 2>/dev/null)"
        if [[ -z "${resolved}" ]]; then
            proxy_contract_die "identity command-${command_name} does not resolve"
            return 1
        fi
    else
        resolved="${path}"
    fi
    proxy_contract_validate_rooted_path \
        "command-${command_name}" "${resolved}" false || return 1
    if [[ ! -e "${resolved}" || -L "${resolved}" || ! -f "${resolved}" || ! -x "${resolved}" ]]; then
        proxy_contract_die "requires exact guest command ${contract_path}"
        return 1
    fi
    printf -v "${result_name}" '%s' "${resolved}"
}

function proxy_contract_preflight_cloud_init {
    local help_output

    proxy_contract_resolve_guest_command \
        cloud-init PROXY_CONTRACT_CLOUD_INIT || return 1
    if ! help_output="$("${PROXY_CONTRACT_CLOUD_INIT}" clean --help 2>&1)"; then
        proxy_contract_die "could not inspect cloud-init clean support"
        return 1
    fi
    PROXY_CONTRACT_CLEAN_ARGS=(clean --logs)
    if grep -Eq -- '(^|[^[:alnum:]_-])--seed([^[:alnum:]_-]|$)' \
        <<< "${help_output}"; then
        PROXY_CONTRACT_CLEAN_ARGS+=(--seed)
    fi
}

function proxy_contract_preflight_apply_commands {
    local os_family="$1"

    proxy_contract_resolve_guest_command sshd PROXY_CONTRACT_SSHD || return 1
    proxy_contract_resolve_guest_command \
        systemctl PROXY_CONTRACT_SYSTEMCTL || return 1
    if [[ "${os_family}" == debian || "${os_family}" == ubuntu ]]; then
        proxy_contract_resolve_guest_command \
            visudo PROXY_CONTRACT_VISUDO || return 1
    fi
}

function proxy_contract_sshd_effective {
    local output config_path

    config_path="$(proxy_contract_root_path "${PROXY_CONTRACT_SSHD_MAIN}")"
    if ! output="$("${PROXY_CONTRACT_SSHD}" -T -f "${config_path}" \
        -C user=vmadmin,host=localhost,addr=127.0.0.1 2>&1)"; then
        proxy_contract_die "sshd effective configuration validation failed"
        return 1
    fi
    if ! grep -Eqi \
        '^permituserenvironment[[:space:]]+yes([[:space:]]|$)' \
        <<< "${output}"; then
        proxy_contract_die \
            "sshd effective configuration does not permit user environment"
        return 1
    fi
}

function proxy_contract_reload_sshd {
    local os_family="$1"
    local service

    if [[ "${os_family}" == rocky ]]; then
        service=sshd
    else
        service=ssh
    fi
    if ! "${PROXY_CONTRACT_SYSTEMCTL}" reload "${service}"; then
        proxy_contract_die "could not reload ${service}"
        return 1
    fi
}

# The rollback arrays are selected by caller-provided names.
# shellcheck disable=SC2178
function proxy_contract_restore_installed {
    local -n installed_ref="$1"
    local -n paths_ref="$2"
    local -n backups_ref="$3"
    local -n existed_ref="$4"
    local -n modes_ref="$5"
    local index

    for ((index=${#installed_ref[@]} - 1; index >= 0; index--)); do
        if [[ "${existed_ref[index]}" == true ]]; then
            install -o "${PROXY_CONTRACT_ROOT_UID}" \
                -g "${PROXY_CONTRACT_ROOT_GID}" -m "${modes_ref[index]}" \
                "${backups_ref[index]}" "${paths_ref[index]}" || true
        else
            rm -f -- "${paths_ref[index]}"
        fi
    done
}

function proxy_contract_apply {
    local os_family="$1"
    local proxy_url identity path candidate backup lock_path created_csv=""
    local index uid gid mode
    local -a identities=() paths=() owners=() groups=() modes=() forms=()
    local -a markers=() cleanups=() remnants=()
    # These arrays are consumed through rollback namerefs.
    # shellcheck disable=SC2034
    local -a rooted_paths=() candidates=() backups=() existed=()
    local -a install_uids=() install_gids=() install_modes=() installed=()

    proxy_contract_parse_input || return 1
    proxy_contract_validate_staged_script || return 1
    proxy_url="${PROXY_CONTRACT_INPUT_URL}"
    proxy_contract_inventory \
        "${os_family}" identities paths owners groups modes forms \
        markers cleanups remnants || return 1
    for index in "${!identities[@]}"; do
        proxy_contract_validate_inventory_entry \
            "${os_family}" "${identities[index]}" "${paths[index]}" \
            "${owners[index]}" "${groups[index]}" "${modes[index]}" \
            "${forms[index]}" "${markers[index]}" "${cleanups[index]}" \
            "${remnants[index]}" || return 1
        proxy_contract_preflight_apply_identity \
            "${os_family}" "${identities[index]}" "${paths[index]}" \
            "${owners[index]}" "${groups[index]}" "${forms[index]}" || return 1
    done
    lock_path="$(proxy_contract_root_path "${PROXY_CONTRACT_LOCK}")"
    proxy_contract_validate_parent contract-lock "${lock_path}" root root || return 1
    if [[ -e "${lock_path}" || -L "${lock_path}" ]]; then
        proxy_contract_die "contract-lock conflicts with an existing path"
        return 1
    fi
    proxy_contract_preflight_apply_commands "${os_family}" || return 1
    proxy_contract_create_work_dir || return 1

    for index in "${!identities[@]}"; do
        identity="${identities[index]}"
        path="$(proxy_contract_root_path "${paths[index]}")"
        candidate="${PROXY_CONTRACT_WORK_DIR}/candidate-${identity}"
        backup="${PROXY_CONTRACT_WORK_DIR}/backup-${identity}"
        rooted_paths[index]="${path}"
        candidates[index]="${candidate}"
        # shellcheck disable=SC2034
        backups[index]="${backup}"
        PROXY_CONTRACT_TEMP_PATHS+=("${candidate}" "${backup}")
        if [[ -e "${path}" ]]; then
            existed[index]=true
            cp -p -- "${path}" "${backup}" || return 1
            uid="$(stat -Lc '%u' "${path}")" || return 1
            gid="$(stat -Lc '%g' "${path}")" || return 1
            mode="$(stat -Lc '%a' "${path}")" || return 1
            proxy_contract_render_candidate \
                "${os_family}" "${identity}" "${forms[index]}" \
                "${proxy_url}" "${path}" "${candidate}" || return 1
        else
            # shellcheck disable=SC2034
            existed[index]=false
            : > "${backup}"
            proxy_contract_owner_ids \
                "${owners[index]}" "${groups[index]}" uid gid || return 1
            mode="${modes[index]#0}"
            proxy_contract_render_candidate \
                "${os_family}" "${identity}" "${forms[index]}" \
                "${proxy_url}" "" "${candidate}" || return 1
            if [[ "${forms[index]}" == shared ]]; then
                [[ -z "${created_csv}" ]] || created_csv+=","
                created_csv+="${identity}"
            fi
        fi
        install_uids[index]="${uid}"
        install_gids[index]="${gid}"
        install_modes[index]="${mode}"
        proxy_contract_validate_marker_shape \
            "${identity}" "${candidate}" "${forms[index]}" || return 1
        if [[ "${forms[index]}" == shared ]]; then
            proxy_contract_validate_shared_placement \
                "${os_family}" "${identity}" "${candidate}" || return 1
        fi
        proxy_contract_validate_exact_content \
            "${identity}" "${candidate}" "${forms[index]}" \
            "${proxy_url}" || return 1
        if [[ "${identity}" == sudo ]]; then
            if ! "${PROXY_CONTRACT_VISUDO}" -cf "${candidate}"; then
                proxy_contract_die "sudo candidate validation failed"
                return 1
            fi
        fi
    done

    proxy_contract_write_lock "${lock_path}" "${created_csv}" || return 1
    for index in "${!identities[@]}"; do
        if ! install -o "${install_uids[index]}" -g "${install_gids[index]}" \
            -m "${install_modes[index]}" "${candidates[index]}" \
            "${rooted_paths[index]}"; then
            proxy_contract_restore_installed \
                installed rooted_paths backups existed install_modes
            rm -f -- "${lock_path}"
            proxy_contract_die "could not install identity ${identities[index]}"
            return 1
        fi
        installed+=("${identities[index]}")
    done
    for index in "${!identities[@]}"; do
        if ! proxy_contract_validate_regular_file \
            "${identities[index]}" "${rooted_paths[index]}" \
            "${owners[index]}" "${groups[index]}" \
            "${install_modes[index]}"; then
            proxy_contract_restore_installed \
                installed rooted_paths backups existed install_modes
            rm -f -- "${lock_path}"
            proxy_contract_reload_sshd "${os_family}" >/dev/null 2>&1 || true
            return 1
        fi
    done
    if ! proxy_contract_sshd_effective ||
       ! proxy_contract_reload_sshd "${os_family}"; then
        proxy_contract_restore_installed \
            installed rooted_paths backups existed install_modes
        rm -f -- "${lock_path}"
        proxy_contract_reload_sshd "${os_family}" >/dev/null 2>&1 || true
        return 1
    fi
    printf 'proxy_contract schema=1 mode=apply os=%s identities=%s applied=true\n' \
        "${os_family}" "${#identities[@]}"
}

function proxy_contract_any_artifact_present {
    local os_family="$1"
    local path index
    local -a identities=() paths=() owners=() groups=() modes=() forms=()
    local -a markers=() cleanups=() remnants=()

    proxy_contract_inventory \
        "${os_family}" identities paths owners groups modes forms \
        markers cleanups remnants || return 1
    for path in \
        "${PROXY_CONTRACT_SCRIPT}" \
        "${PROXY_CONTRACT_INPUT}" \
        "${PROXY_CONTRACT_LOCK}"; do
        path="$(proxy_contract_root_path "${path}")"
        [[ -e "${path}" || -L "${path}" ]] && return 0
    done
    for index in "${!identities[@]}"; do
        path="$(proxy_contract_root_path "${paths[index]}")"
        if [[ "${forms[index]}" == dedicated ]]; then
            [[ -e "${path}" || -L "${path}" ]] && return 0
        elif [[ -L "${path}" ]]; then
            return 0
        elif [[ -f "${path}" ]] &&
             grep -Fq -e "${PROXY_CONTRACT_BEGIN}" \
                -e "${PROXY_CONTRACT_END}" "${path}"; then
            return 0
        fi
    done
    return 1
}

function proxy_contract_verify_clean {
    local os_family="$1"
    local identity path key_pattern index
    local -a identities=() paths=() owners=() groups=() modes=() forms=()
    local -a markers=() cleanups=() remnants=()

    proxy_contract_inventory \
        "${os_family}" identities paths owners groups modes forms \
        markers cleanups remnants || return 1
    for index in "${!identities[@]}"; do
        identity="${identities[index]}"
        path="$(proxy_contract_root_path "${paths[index]}")"
        if [[ "${forms[index]}" == dedicated ]]; then
            if [[ -e "${path}" || -L "${path}" ]]; then
                proxy_contract_die "identity ${identity} remains"
                return 1
            fi
        elif [[ -L "${path}" || ( -e "${path}" && ! -f "${path}" ) ]]; then
            proxy_contract_die "identity ${identity} is not verifiable"
            return 1
        elif [[ -f "${path}" ]]; then
            if grep -Fq -e "${PROXY_CONTRACT_BEGIN}" \
                -e "${PROXY_CONTRACT_END}" "${path}"; then
                proxy_contract_die "identity ${identity} retains a contract marker"
                return 1
            fi
            key_pattern="$(proxy_contract_key_pattern "${identity}")" || return 1
            if grep -Eqi "${key_pattern}" "${path}"; then
                proxy_contract_die "identity ${identity} retains a proxy key"
                return 1
            fi
        fi
    done
    for path in \
        "${PROXY_CONTRACT_SCRIPT}" \
        "${PROXY_CONTRACT_INPUT}" \
        "${PROXY_CONTRACT_LOCK}"; do
        path="$(proxy_contract_root_path "${path}")"
        if [[ -e "${path}" || -L "${path}" ]]; then
            proxy_contract_die "transient proxy contract state remains"
            return 1
        fi
    done
    printf 'proxy_contract schema=1 mode=verify-clean os=%s identities=%s clean=true\n' \
        "${os_family}" "${#identities[@]}"
}

function proxy_contract_cloud_state_clean {
    local path directory
    local -a absent_paths=(
        /var/lib/cloud/instance
        /var/lib/cloud/seed/nocloud/user-data
        /var/lib/cloud/seed/nocloud-net/user-data
        /var/log/cloud-init.log
        /var/log/cloud-init-output.log
    )

    for path in "${absent_paths[@]}"; do
        path="$(proxy_contract_root_path "${path}")"
        if [[ -e "${path}" || -L "${path}" ]]; then
            return 1
        fi
    done
    for directory in /var/lib/cloud/instances /var/lib/cloud/seed; do
        path="$(proxy_contract_root_path "${directory}")"
        if [[ -d "${path}" ]] &&
           find "${path}" -mindepth 1 -print -quit | grep -q .; then
            return 1
        fi
    done
}

function proxy_contract_seal {
    local os_family="$1"
    local proxy_url identity path candidate index
    local script_path input_path lock_path
    local -a identities=() paths=() owners=() groups=() modes=() forms=()
    local -a markers=() cleanups=() remnants=()
    local -a rooted_paths=() candidates=() candidate_modes=()

    proxy_contract_inventory \
        "${os_family}" identities paths owners groups modes forms \
        markers cleanups remnants || return 1
    proxy_contract_preflight_cloud_init || return 1
    if proxy_contract_any_artifact_present "${os_family}"; then
        proxy_contract_parse_input || return 1
        proxy_contract_validate_staged_script || return 1
        proxy_contract_parse_lock || return 1
        proxy_url="${PROXY_CONTRACT_INPUT_URL}"
        proxy_contract_preflight_apply_commands "${os_family}" || return 1
        proxy_contract_create_work_dir || return 1
        for index in "${!identities[@]}"; do
            proxy_contract_validate_inventory_entry \
                "${os_family}" "${identities[index]}" "${paths[index]}" \
                "${owners[index]}" "${groups[index]}" "${modes[index]}" \
                "${forms[index]}" "${markers[index]}" \
                "${cleanups[index]}" "${remnants[index]}" || return 1
            proxy_contract_preflight_seal_identity \
                "${os_family}" "${identities[index]}" "${paths[index]}" \
                "${owners[index]}" "${groups[index]}" "${modes[index]}" \
                "${forms[index]}" "${proxy_url}" || return 1
            path="$(proxy_contract_root_path "${paths[index]}")"
            rooted_paths[index]="${path}"
            if [[ "${forms[index]}" == shared ]] &&
               ! proxy_contract_identity_was_created "${identities[index]}"; then
                candidate="${PROXY_CONTRACT_WORK_DIR}/clean-${identities[index]}"
                candidates[index]="${candidate}"
                candidate_modes[index]="$(stat -Lc '%a' "${path}")" || return 1
                PROXY_CONTRACT_TEMP_PATHS+=("${candidate}")
                proxy_contract_remove_block \
                    "${identities[index]}" "${path}" "${candidate}" || return 1
            fi
        done

        for ((index=${#identities[@]} - 1; index >= 0; index--)); do
            identity="${identities[index]}"
            path="${rooted_paths[index]}"
            if [[ "${forms[index]}" == dedicated ]] ||
               proxy_contract_identity_was_created "${identity}"; then
                rm -f -- "${path}"
            else
                if ! install -o "${PROXY_CONTRACT_ROOT_UID}" \
                    -g "${PROXY_CONTRACT_ROOT_GID}" \
                    -m "${candidate_modes[index]}" \
                    "${candidates[index]}" "${path}"; then
                    proxy_contract_die "could not clean identity ${identity}"
                    return 1
                fi
            fi
        done
        proxy_contract_reload_sshd "${os_family}" || return 1
        script_path="$(proxy_contract_root_path "${PROXY_CONTRACT_SCRIPT}")"
        input_path="$(proxy_contract_root_path "${PROXY_CONTRACT_INPUT}")"
        lock_path="$(proxy_contract_root_path "${PROXY_CONTRACT_LOCK}")"
        rm -f -- "${lock_path}"
        rm -f -- "${input_path}"
        rm -f -- "${script_path}"
    fi
    proxy_contract_verify_clean "${os_family}" >/dev/null || return 1
    if ! "${PROXY_CONTRACT_CLOUD_INIT}" "${PROXY_CONTRACT_CLEAN_ARGS[@]}"; then
        proxy_contract_die "cloud-init clean failed"
        return 1
    fi
    if ! proxy_contract_cloud_state_clean; then
        proxy_contract_die "cloud-init state or selected logs remain"
        return 1
    fi
    printf 'proxy_contract schema=1 mode=seal os=%s identities=%s clean=true\n' \
        "${os_family}" "${#identities[@]}"
}

function proxy_contract_configure_root {
    local test_root="$1"
    local resolved_root

    if [[ -z "${test_root}" ]]; then
        if [[ "${EUID}" != 0 ]]; then
            proxy_contract_die "apply, seal, and verify clean require root"
            return 1
        fi
        if [[ ! -o privileged ]]; then
            proxy_contract_die "production execution requires privileged Bash mode"
            return 1
        fi
        PROXY_CONTRACT_ROOT="/"
        PROXY_CONTRACT_ROOT_UID=0
        PROXY_CONTRACT_ROOT_GID=0
    else
        if [[ "${test_root}" != /* || ! -d "${test_root}" || -L "${test_root}" ]]; then
            proxy_contract_die \
                "--test-root requires an existing absolute directory"
            return 1
        fi
        resolved_root="$(realpath -e -- "${test_root}")" || return 1
        if [[ "${resolved_root}" == "/" ]]; then
            proxy_contract_die \
                "--test-root must not resolve to the production root"
            return 1
        fi
        PROXY_CONTRACT_ROOT="${resolved_root}"
        PROXY_CONTRACT_ROOT_UID="${EUID}"
        PROXY_CONTRACT_ROOT_GID="$(id -g)"
    fi
    proxy_contract_parse_passwd
}

function proxy_contract_main {
    local test_root="" os_family
    local -a operands=()

    umask 077
    export PATH="${PROXY_CONTRACT_EXEC_PATH}"
    while (( $# > 0 )); do
        case "$1" in
            --test-root)
                if (( $# < 2 )); then
                    proxy_contract_die "--test-root requires a path"
                    return 1
                fi
                test_root="$2"
                shift 2
                ;;
            *)
                operands+=("$1")
                shift
                ;;
        esac
    done
    if ! { [[ "${#operands[@]}" == 1 &&
              ( "${operands[0]}" == apply || "${operands[0]}" == seal ) ]] ||
           [[ "${#operands[@]}" == 2 && "${operands[0]}" == verify &&
              "${operands[1]}" == clean ]]; }; then
        proxy_contract_die \
            "usage: proxy_contract.bash [--test-root <absolute-path>] {apply|seal|verify clean}"
        return 1
    fi

    unset BASH_ENV ENV CDPATH TMPDIR TMP TEMP
    export LC_ALL=C
    proxy_contract_configure_root "${test_root}" || return 1
    trap proxy_contract_cleanup_temps EXIT
    trap 'exit 1' HUP INT TERM
    if ! os_family="$(proxy_contract_parse_os_release)"; then
        return 1
    fi
    case "${operands[0]}" in
        apply) proxy_contract_apply "${os_family}" ;;
        seal) proxy_contract_seal "${os_family}" ;;
        verify) proxy_contract_verify_clean "${os_family}" ;;
    esac
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]] ||
   [[ -z "${BASH_SOURCE[0]:-}" && "$0" == /bin/bash && -o privileged ]]; then
    set -euo pipefail
    proxy_contract_main "$@"
fi
