#!/usr/bin/env bash
#
# Owns the complete proxy artifact lifecycle from cloud-init apply through
# image publication cleanup.

declare -gr PROXY_CONTRACT_BEGIN="# BEGIN CLOUD-PROVISION PROXY CONTRACT"
declare -gr PROXY_CONTRACT_END="# END CLOUD-PROVISION PROXY CONTRACT"
declare -gr PROXY_CONTRACT_MARKER="cloud-provision-proxy-v1"
declare -gr PROXY_CONTRACT_NO_PROXY="localhost,127.0.0.1,192.168.0.0/16"
# Maven nonProxyHosts is a "|"-separated wildcard list and cannot express CIDR.
declare -gr PROXY_CONTRACT_NO_PROXY_MAVEN="localhost|127.0.0.1|192.168.*"
declare -gr PROXY_CONTRACT_EXEC_PATH="/usr/sbin:/usr/bin:/sbin:/bin"
declare -gr PROXY_CONTRACT_GENERAL_SERVER_ID="rocky"
declare -gr PROXY_CONTRACT_GENERAL_SERVER_VERSION="8.10"

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
# Selected explicitly with mvn -gs; it is not a Maven default location, so it
# stays directly under /etc and never collides with a packaged /etc/maven.
declare -gr PROXY_CONTRACT_MAVEN="/etc/maven-proxy-settings.xml"

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
declare -g PROXY_CONTRACT_INPUT_SCHEMA=1
declare -g PROXY_CONTRACT_SCOPE="cloud"
declare -g PROXY_CONTRACT_INPUT_LOADED=false
declare -g PROXY_CONTRACT_OPERATION=""
declare -g PROXY_CONTRACT_INTERRUPTED=false
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
    local parent directory vmadmin_home uid gid mode expected_uid expected_gid
    local directory_uid directory_gid

    parent="${path%/*}"
    proxy_contract_validate_rooted_path "${identity}" "${parent}" false || return 1
    if [[ ! -d "${parent}" || -L "${parent}" ]]; then
        proxy_contract_die "identity ${identity} has an unsafe parent directory"
        return 1
    fi
    proxy_contract_owner_ids "${owner}" "${group}" expected_uid expected_gid || return 1
    vmadmin_home="$(proxy_contract_root_path "${PROXY_CONTRACT_SSH_ENVIRONMENT%/.ssh/environment}")"
    directory="${parent}"
    while :; do
        directory_uid="${PROXY_CONTRACT_ROOT_UID}"
        directory_gid="${PROXY_CONTRACT_ROOT_GID}"
        if [[ "${directory}" == "${parent}" ]] ||
           [[ "${owner}" == vmadmin && "${directory}" == "${vmadmin_home}" ]]; then
            directory_uid="${expected_uid}"
            directory_gid="${expected_gid}"
        fi
        uid="$(stat -Lc '%u' "${directory}")" || return 1
        gid="$(stat -Lc '%g' "${directory}")" || return 1
        mode="$(stat -Lc '%a' "${directory}")" || return 1
        if [[ "${uid}" != "${directory_uid}" || "${gid}" != "${directory_gid}" ]]; then
            proxy_contract_die "identity ${identity} parent has an ownership conflict"
            return 1
        fi
        if (( (8#${mode} & 8#022) != 0 )); then
            proxy_contract_die "identity ${identity} parent is group or world writable"
            return 1
        fi
        [[ "${directory}" != "${PROXY_CONTRACT_ROOT}" ]] || break
        directory="${directory%/*}"
        [[ -n "${directory}" ]] || directory="/"
    done
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
    local path line value="" version=""
    local id_count=0 version_count=0

    if ! path="$(proxy_contract_resolve_os_release)"; then
        return 1
    fi
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^ID=(.*)$ ]]; then
            value="${BASH_REMATCH[1]}"
            id_count=$((id_count + 1))
        elif [[ "${line}" =~ ^VERSION_ID=(.*)$ ]]; then
            version="${BASH_REMATCH[1]}"
            version_count=$((version_count + 1))
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
    if [[ "${PROXY_CONTRACT_SCOPE}" == general-server ]]; then
        case "${version}" in
            \"*\") version="${version#\"}"; version="${version%\"}" ;;
            \'*\') version="${version#\'}"; version="${version%\'}" ;;
        esac
        if [[ "${value}" != "${PROXY_CONTRACT_GENERAL_SERVER_ID}" ||
              "${version_count}" != 1 || "${version}" != "${PROXY_CONTRACT_GENERAL_SERVER_VERSION}" ]]; then
            proxy_contract_die "general-server requires ID=rocky and exactly one VERSION_ID=8.10"
            return 1
        fi
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
    local -n formats_ref="${10}"
    shift 10

    if [[ "${PROXY_CONTRACT_SCOPE}" == general-server &&
          ( "$1" == sshd || "$1" == ssh-environment ) ]]; then
        return 0
    fi
    identities_ref+=("$1")
    paths_ref+=("$2")
    owners_ref+=("$3")
    groups_ref+=("$4")
    modes_ref+=("$5")
    forms_ref+=("$6")
    markers_ref+=("$7")
    cleanups_ref+=("$8")
    remnants_ref+=("$9")
    formats_ref+=("${10}")
}

# The output arrays are selected by caller-provided names.
# shellcheck disable=SC2178
function proxy_contract_inventory {
    local os_family="$1"
    local identities_name="$2" paths_name="$3" owners_name="$4"
    local groups_name="$5" modes_name="$6" forms_name="$7"
    local markers_name="$8" cleanups_name="$9" remnants_name="${10}"
    local formats_name="${11}"
    local -n identities_ref="${identities_name}"
    local -n paths_ref="${paths_name}"
    local -n owners_ref="${owners_name}"
    local -n groups_ref="${groups_name}"
    local -n modes_ref="${modes_name}"
    local -n forms_ref="${forms_name}"
    local -n markers_ref="${markers_name}"
    local -n cleanups_ref="${cleanups_name}"
    local -n remnants_ref="${remnants_name}"
    local -n formats_ref="${formats_name}"

    identities_ref=()
    paths_ref=()
    owners_ref=()
    groups_ref=()
    modes_ref=()
    forms_ref=()
    markers_ref=()
    cleanups_ref=()
    remnants_ref=()
    formats_ref=()

    case "${PROXY_CONTRACT_SCOPE}:${os_family}" in
        cloud:debian|cloud:ubuntu|cloud:rocky|general-server:rocky) ;;
        *) proxy_contract_die "contains an unsupported inventory scope"; return 1 ;;
    esac

    proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" "${formats_name}" profile "${PROXY_CONTRACT_PROFILE}" root root 0644 dedicated "${PROXY_CONTRACT_MARKER}" required required hash-comment # inventory:profile
    proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" "${formats_name}" environment "${PROXY_CONTRACT_ENVIRONMENT}" root root 0644 shared "${PROXY_CONTRACT_MARKER}" required required hash-comment # inventory:environment
    case "${os_family}" in
        debian|ubuntu)
            proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" "${formats_name}" apt "${PROXY_CONTRACT_APT}" root root 0644 dedicated "${PROXY_CONTRACT_MARKER}" required required hash-comment # inventory:apt
            proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" "${formats_name}" sudo "${PROXY_CONTRACT_SUDO}" root root 0440 dedicated "${PROXY_CONTRACT_MARKER}" required required hash-comment # inventory:sudo
            proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" "${formats_name}" sshd "${PROXY_CONTRACT_SSHD_DROPIN}" root root 0644 dedicated "${PROXY_CONTRACT_MARKER}" required required hash-comment # inventory:sshd
            ;;
        rocky)
            proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" "${formats_name}" dnf "${PROXY_CONTRACT_DNF}" root root 0644 shared "${PROXY_CONTRACT_MARKER}" required required hash-comment # inventory:dnf
            proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" "${formats_name}" sshd "${PROXY_CONTRACT_SSHD_MAIN}" root root 0644 shared "${PROXY_CONTRACT_MARKER}" required required hash-comment # inventory:sshd
            ;;
        *)
            proxy_contract_die "contains an unsupported inventory OS family"
            return 1
            ;;
    esac
    proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" "${formats_name}" ssh-environment "${PROXY_CONTRACT_SSH_ENVIRONMENT}" vmadmin vmadmin 0600 dedicated "${PROXY_CONTRACT_MARKER}" required required hash-comment # inventory:ssh-environment
    proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" "${formats_name}" pip "${PROXY_CONTRACT_PIP}" root root 0644 dedicated "${PROXY_CONTRACT_MARKER}" required required hash-comment # inventory:pip
    proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" "${formats_name}" git "${PROXY_CONTRACT_GIT}" root root 0644 shared "${PROXY_CONTRACT_MARKER}" required required hash-comment # inventory:git
    proxy_contract_inventory_add "${identities_name}" "${paths_name}" "${owners_name}" "${groups_name}" "${modes_name}" "${forms_name}" "${markers_name}" "${cleanups_name}" "${remnants_name}" "${formats_name}" maven "${PROXY_CONTRACT_MAVEN}" root root 0644 dedicated "${PROXY_CONTRACT_MARKER}" required required xml # inventory:maven
}

function proxy_contract_validate_inventory_entry {
    local os_family="$1" identity="$2" path="$3" owner="$4" group="$5"
    local mode="$6" form="$7" marker="$8" cleanup="$9" remnant="${10}"
    local format="${11}"
    local expected=""

    if [[ "${PROXY_CONTRACT_SCOPE}" == general-server &&
          ( "${os_family}" != rocky || "${identity}" == sshd || "${identity}" == ssh-environment ) ]]; then
        proxy_contract_die "contains an identity outside the general-server scope"
        return 1
    fi
    case "${os_family}:${identity}" in
        debian:profile|ubuntu:profile|rocky:profile) expected="${PROXY_CONTRACT_PROFILE}|root|root|0644|dedicated|hash-comment" ;;
        debian:environment|ubuntu:environment|rocky:environment) expected="${PROXY_CONTRACT_ENVIRONMENT}|root|root|0644|shared|hash-comment" ;;
        debian:apt|ubuntu:apt) expected="${PROXY_CONTRACT_APT}|root|root|0644|dedicated|hash-comment" ;;
        rocky:dnf) expected="${PROXY_CONTRACT_DNF}|root|root|0644|shared|hash-comment" ;;
        debian:sudo|ubuntu:sudo) expected="${PROXY_CONTRACT_SUDO}|root|root|0440|dedicated|hash-comment" ;;
        debian:sshd|ubuntu:sshd) expected="${PROXY_CONTRACT_SSHD_DROPIN}|root|root|0644|dedicated|hash-comment" ;;
        rocky:sshd) expected="${PROXY_CONTRACT_SSHD_MAIN}|root|root|0644|shared|hash-comment" ;;
        debian:ssh-environment|ubuntu:ssh-environment|rocky:ssh-environment) expected="${PROXY_CONTRACT_SSH_ENVIRONMENT}|vmadmin|vmadmin|0600|dedicated|hash-comment" ;;
        debian:pip|ubuntu:pip|rocky:pip) expected="${PROXY_CONTRACT_PIP}|root|root|0644|dedicated|hash-comment" ;;
        debian:git|ubuntu:git|rocky:git) expected="${PROXY_CONTRACT_GIT}|root|root|0644|shared|hash-comment" ;;
        debian:maven|ubuntu:maven|rocky:maven) expected="${PROXY_CONTRACT_MAVEN}|root|root|0644|dedicated|xml" ;;
        *)
            proxy_contract_die "contains an unknown inventory identity ${identity}"
            return 1
            ;;
    esac
    if [[ "${path}|${owner}|${group}|${mode}|${form}|${format}" != "${expected}" ||
          "${marker}" != "${PROXY_CONTRACT_MARKER}" ||
          "${cleanup}" != required || "${remnant}" != required ]]; then
        proxy_contract_die "contains invalid inventory metadata for ${identity}"
        return 1
    fi
}

function proxy_contract_print_inventory {
    local os_family="$1" index
    local PROXY_CONTRACT_SCOPE="${2:-${PROXY_CONTRACT_SCOPE}}"
    local -a identities=() paths=() owners=() groups=() modes=() forms=()
    local -a markers=() cleanups=() remnants=() formats=()

    proxy_contract_inventory "${os_family}" identities paths owners groups modes forms markers cleanups remnants formats || return 1
    for index in "${!identities[@]}"; do
        proxy_contract_validate_inventory_entry "${os_family}" "${identities[index]}" "${paths[index]}" "${owners[index]}" "${groups[index]}" "${modes[index]}" "${forms[index]}" "${markers[index]}" "${cleanups[index]}" "${remnants[index]}" "${formats[index]}" || return 1
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${os_family}" "${identities[index]}" "${paths[index]}" \
            "${owners[index]}" "${groups[index]}" "${modes[index]}" \
            "${forms[index]}" "${markers[index]}" "${cleanups[index]}" \
            "${remnants[index]}" "${formats[index]}"
    done
}

function proxy_contract_write_maven_settings {
    local proxy_url="$1"
    local authority host port

    authority="${proxy_url#*://}"
    authority="${authority%%/*}"
    if [[ "${authority}" == *@* ]]; then
        proxy_contract_die "identity maven cannot express proxy credentials"
        return 1
    fi
    host="${authority%%:*}"
    if [[ "${authority}" == *:* ]]; then
        port="${authority##*:}"
    elif [[ "${proxy_url}" == https://* ]]; then
        port=443
    else
        port=80
    fi
    if [[ ! "${host}" =~ ^[A-Za-z0-9.-]+$ || ! "${port}" =~ ^[0-9]+$ ]]; then
        proxy_contract_die "identity maven requires a plain proxy host and port"
        return 1
    fi
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">'
    printf '%s\n' '  <proxies>'
    local protocol
    for protocol in http https; do
        printf '%s\n' '    <proxy>'
        printf '      <id>cloud-provision-proxy-%s</id>\n' "${protocol}"
        printf '%s\n' '      <active>true</active>'
        printf '      <protocol>%s</protocol>\n' "${protocol}"
        printf '      <host>%s</host>\n' "${host}"
        printf '      <port>%s</port>\n' "${port}"
        printf '      <nonProxyHosts>%s</nonProxyHosts>\n' "${PROXY_CONTRACT_NO_PROXY_MAVEN}"
        printf '%s\n' '    </proxy>'
    done
    printf '%s\n' '  </proxies>'
    printf '%s\n' '</settings>'
}

function proxy_contract_write_block {
    local identity="$1"
    local proxy_url="$2"

    # The xml artifact is rendered whole, without the hash-comment markers the
    # other identities carry.
    if [[ "${identity}" == maven ]]; then
        proxy_contract_write_maven_settings "${proxy_url}"
        return
    fi
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
    local format="$4"
    local begin_count end_count first_line last_line

    # An xml artifact carries no hash-comment markers. Its whole file is the
    # contract's, and validate_exact_content compares it byte for byte.
    if [[ "${format}" == xml ]]; then
        return 0
    fi

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
    local format="$9"
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
    proxy_contract_validate_marker_shape "${identity}" "${path}" "${form}" "${format}" || return 1
    if [[ "${form}" == shared ]]; then
        proxy_contract_validate_shared_placement \
            "${os_family}" "${identity}" "${path}" || return 1
    fi
    if [[ "${format}" != xml ]]; then
        proxy_contract_validate_unowned_keys "${identity}" "${path}" || return 1
    fi
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
    local schema="" proxy_url="" script_hash="" scope=""
    local schema_count=0 proxy_count=0 hash_count=0 scope_count=0

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
            scope=*)
                scope="${line#scope=}"
                scope_count=$((scope_count + 1))
                ;;
            *)
                proxy_contract_die "contract input contains an unknown field"
                return 1
                ;;
        esac
    done < "${path}"
    if [[ "${schema_count}" != 1 || "${proxy_count}" != 1 ||
          "${hash_count}" != 1 ||
          ! "${script_hash}" =~ ^[0-9a-f]{64}$ ]]; then
        proxy_contract_die "contract input has invalid required fields"
        return 1
    fi
    case "${schema}:${scope_count}:${scope}" in
        1:0:) scope=cloud ;;
        2:1:general-server)
            if [[ "${PROXY_CONTRACT_OPERATION}" != reconcile ]]; then
                proxy_contract_die "schema 2 general-server supports reconcile only"
                return 1
            fi
            ;;
        *) proxy_contract_die "contract input has an unsupported schema or scope"; return 1 ;;
    esac
    if [[ "${PROXY_CONTRACT_INPUT_LOADED}" == true &&
          ( "${schema}" != "${PROXY_CONTRACT_INPUT_SCHEMA}" || "${scope}" != "${PROXY_CONTRACT_SCOPE}" ) ]]; then
        proxy_contract_die "contract input scope changed during execution"
        return 1
    fi
    proxy_contract_validate_url "${proxy_url}" || return 1
    PROXY_CONTRACT_INPUT_SCHEMA="${schema}"
    PROXY_CONTRACT_SCOPE="${scope}"
    PROXY_CONTRACT_INPUT_LOADED=true
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

function proxy_contract_print_lock {
    local created_csv="$1"

    printf 'schema=%s\n' "${PROXY_CONTRACT_INPUT_SCHEMA}"
    if [[ "${PROXY_CONTRACT_INPUT_SCHEMA}" == 2 ]]; then
        printf 'scope=%s\n' "${PROXY_CONTRACT_SCOPE}"
    fi
    printf 'state=applied\ncreated=%s\n' "${created_csv}"
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
    proxy_contract_print_lock "${created_csv}" > "${path}"
}

function proxy_contract_parse_lock {
    local path line schema="" state="" created="" identity scope=""
    local schema_count=0 state_count=0 created_count=0 scope_count=0
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
            scope=*)
                scope="${line#scope=}"
                scope_count=$((scope_count + 1))
                ;;
            *)
                proxy_contract_die "contract-lock contains an unknown field"
                return 1
                ;;
        esac
    done < "${path}"
    if [[ "${schema_count}" != 1 || "${state_count}" != 1 ||
          "${created_count}" != 1 || "${schema}" != "${PROXY_CONTRACT_INPUT_SCHEMA}" || "${state}" != applied ]]; then
        proxy_contract_die "contract-lock does not match the selected schema"
        return 1
    fi
    case "${schema}:${scope_count}:${scope}:${PROXY_CONTRACT_SCOPE}" in
        1:0::cloud|2:1:general-server:general-server) ;;
        *) proxy_contract_die "contract-lock does not match the selected scope"; return 1 ;;
    esac
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

    [[ "${PROXY_CONTRACT_SCOPE}" != general-server ]] || return 0
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

    [[ "${PROXY_CONTRACT_SCOPE}" != general-server ]] || return 0
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

    [[ "${PROXY_CONTRACT_SCOPE}" != general-server ]] || return 0
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
    local -a markers=() cleanups=() remnants=() formats=()
    # These arrays are consumed through rollback namerefs.
    # shellcheck disable=SC2034
    local -a rooted_paths=() candidates=() backups=() existed=()
    local -a install_uids=() install_gids=() install_modes=() installed=()

    proxy_contract_parse_input || return 1
    proxy_contract_validate_staged_script || return 1
    proxy_url="${PROXY_CONTRACT_INPUT_URL}"
    proxy_contract_inventory \
        "${os_family}" identities paths owners groups modes forms \
        markers cleanups remnants formats || return 1
    for index in "${!identities[@]}"; do
        proxy_contract_validate_inventory_entry \
            "${os_family}" "${identities[index]}" "${paths[index]}" \
            "${owners[index]}" "${groups[index]}" "${modes[index]}" \
            "${forms[index]}" "${markers[index]}" "${cleanups[index]}" \
            "${remnants[index]}" "${formats[index]}" || return 1
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
            "${identity}" "${candidate}" "${forms[index]}" "${formats[index]}" || return 1
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

function proxy_contract_preflight_reconcile_identity {
    local os_family="$1" identity="$2" path="$3"
    local owner="$4" group="$5" form="$6" format="$7"

    proxy_contract_validate_parent "${identity}" "${path}" "${owner}" "${group}" || return 1
    proxy_contract_validate_rooted_path "${identity}" "${path}" true || return 1
    if [[ -e "${path}" ]]; then
        if [[ ! -f "${path}" || "$(stat -Lc '%h' "${path}")" != 1 ]]; then
            proxy_contract_die "identity ${identity} is not a single-link regular file"
            return 1
        fi
        if [[ "${format}" == hash-comment ]]; then
            if [[ "${form}" == dedicated ]] ||
               grep -Fq 'CLOUD-PROVISION PROXY CONTRACT' "${path}"; then
                proxy_contract_validate_marker_shape "${identity}" "${path}" "${form}" "${format}" || return 1
            fi
            proxy_contract_validate_unowned_keys "${identity}" "${path}" || return 1
        fi
        if [[ "${form}" == shared ]]; then
            proxy_contract_validate_shared_newline "${identity}" "${path}" || return 1
        fi
    elif [[ "${identity}" == dnf || ( "${identity}" == sshd && "${form}" == shared ) ]]; then
        proxy_contract_die "identity ${identity} requires an existing shared file"
        return 1
    fi
    if [[ "${identity}" == dnf ]] &&
       [[ "$(grep -Ec '^[[:space:]]*\[main\][[:space:]]*$' "${path}" || true)" != 1 ]]; then
        proxy_contract_die "identity dnf requires exactly one main section"
        return 1
    fi
    if [[ "${identity}" == sshd && "${os_family}" != rocky ]]; then
        proxy_contract_require_sshd_include || return 1
    fi
}

function proxy_contract_replace_file {
    local identity="$1" source_path="$2" path="$3"
    local uid="$4" gid="$5" mode="$6" temporary security_context=""

    proxy_contract_validate_rooted_path "${identity}" "${path}" true || return 1
    temporary="$(mktemp "${path%/*}/.proxy-contract.XXXXXX")" || return 1
    PROXY_CONTRACT_TEMP_PATHS+=("${temporary}")
    install -o "${uid}" -g "${gid}" -m "${mode}" "${source_path}" "${temporary}" || return 1
    touch -r "${source_path}" "${temporary}" || return 1
    if [[ -e "${path}" ]]; then
        security_context="$(stat -Lc '%C' "${path}" 2>/dev/null)" || security_context=""
        if [[ -n "${security_context}" && "${security_context}" != '?' ]]; then
            cp --attributes-only --preserve=context -- "${path}" "${temporary}" || return 1
        fi
    fi
    proxy_contract_validate_rooted_path "${identity}" "${path}" true || return 1
    mv -fT -- "${temporary}" "${path}"
}

function proxy_contract_file_state {
    local path="$1"

    if [[ ! -e "${path}" && ! -L "${path}" ]]; then
        printf '%s\n' absent
        return 0
    fi
    proxy_contract_validate_rooted_path snapshot "${path}" false || return 1
    [[ -f "${path}" && "$(stat -Lc '%h' "${path}")" == 1 ]] || return 1
    stat -Lc '%d:%i:%h:%u:%g:%a:%s:%y:%z' "${path}"
}

function proxy_contract_matches_snapshot {
    local path="$1" expected_state="$2" expected_content="$3" current_state

    current_state="$(proxy_contract_file_state "${path}")" || return 1
    [[ "${current_state}" == "${expected_state}" ]] || return 1
    [[ "${expected_state}" == absent ]] || cmp -s -- "${expected_content}" "${path}"
}

# Each backup retains the original bytes and metadata, including metadata
# drift. Concurrent changes are preserved and reported as rollback failures.
function proxy_contract_restore_reconciled {
    local -n restore_indices="$1" restore_paths="$2"
    local -n restore_backups="$3" restore_existed="$4"
    local -n restore_states="$5" restore_candidates="$6"
    local index position uid gid mode rc=0

    for ((position=${#restore_indices[@]} - 1; position >= 0; position--)); do
        index="${restore_indices[position]}"
        if ! proxy_contract_matches_snapshot "${restore_paths[index]}" \
            "${restore_states[index]:-}" "${restore_candidates[index]}"; then
            proxy_contract_die "rollback preserved a concurrent change"
            rc=1
            continue
        fi
        if [[ "${restore_existed[index]}" == true ]]; then
            uid="$(stat -Lc '%u' "${restore_backups[index]}")" || return 1
            gid="$(stat -Lc '%g' "${restore_backups[index]}")" || return 1
            mode="$(stat -Lc '%a' "${restore_backups[index]}")" || return 1
            proxy_contract_replace_file rollback "${restore_backups[index]}" \
                "${restore_paths[index]}" "${uid}" "${gid}" "${mode}" || rc=1
        else
            rm -f -- "${restore_paths[index]}" || rc=1
        fi
    done
    return "${rc}"
}

function proxy_contract_reconcile {
    local os_family="$1" identity path candidate base index uid gid mode
    local lock_path lock_candidate created_csv="" current_identity changed=false
    local lock_present=false rc=0 runtime_path reconcile_fd lock_index flock_path
    local -a identities=() paths=() owners=() groups=() modes=() forms=()
    local -a markers=() cleanups=() remnants=() formats=()
    local -a rooted_paths=() candidates=() backups=() existed=()
    local -a install_uids=() install_gids=() install_modes=() changes=() installed=()
    local -a source_states=() installed_states=()

    runtime_path="$(proxy_contract_root_path "${PROXY_CONTRACT_RUNTIME_DIR}")" || return 1
    proxy_contract_validate_parent contract-lock "${runtime_path}/proxy-contract.lock" root root || return 1
    if ! flock_path="$(command -v flock)" || [[ ! -x "${flock_path}" ]]; then
        proxy_contract_die "reconcile requires flock"
        return 1
    fi
    exec {reconcile_fd}<"${runtime_path}" || return 1
    if ! "${flock_path}" -n "${reconcile_fd}"; then
        proxy_contract_die "another reconciliation is running"
        return 1
    fi
    proxy_contract_parse_input || return 1
    proxy_contract_validate_staged_script || return 1
    proxy_contract_inventory "${os_family}" identities paths owners groups modes forms \
        markers cleanups remnants formats || return 1
    for index in "${!identities[@]}"; do
        proxy_contract_validate_inventory_entry "${os_family}" "${identities[index]}" \
            "${paths[index]}" "${owners[index]}" "${groups[index]}" "${modes[index]}" \
            "${forms[index]}" "${markers[index]}" "${cleanups[index]}" \
            "${remnants[index]}" "${formats[index]}" || return 1
        path="$(proxy_contract_root_path "${paths[index]}")" || return 1
        source_states[index]="$(proxy_contract_file_state "${path}")" || return 1
        proxy_contract_preflight_reconcile_identity "${os_family}" "${identities[index]}" \
            "${path}" "${owners[index]}" "${groups[index]}" "${forms[index]}" "${formats[index]}" || return 1
        if [[ "$(proxy_contract_file_state "${path}")" != "${source_states[index]}" ]]; then
            proxy_contract_die "reconcile detected a concurrent change during preflight"
            return 1
        fi
        rooted_paths[index]="${path}"
    done
    lock_path="$(proxy_contract_root_path "${PROXY_CONTRACT_LOCK}")" || return 1
    proxy_contract_validate_parent contract-lock "${lock_path}" root root || return 1
    proxy_contract_validate_rooted_path contract-lock "${lock_path}" true || return 1
    lock_index="${#rooted_paths[@]}"
    source_states[lock_index]="$(proxy_contract_file_state "${lock_path}")" || return 1
    if [[ -e "${lock_path}" ]]; then
        proxy_contract_parse_lock || return 1
        lock_present=true
    else
        PROXY_CONTRACT_CREATED_IDENTITIES=()
    fi
    proxy_contract_preflight_apply_commands "${os_family}" || return 1
    proxy_contract_create_work_dir || return 1
    rooted_paths[lock_index]="${lock_path}"
    backups[lock_index]="${PROXY_CONTRACT_WORK_DIR}/backup-lock"
    existed[lock_index]="${lock_present}"
    if [[ "${lock_present}" == true ]]; then
        cp -p -- "${lock_path}" "${backups[lock_index]}" || return 1
        if ! proxy_contract_matches_snapshot "${lock_path}" "${source_states[lock_index]}" \
            "${backups[lock_index]}"; then
            proxy_contract_die "reconcile detected a concurrent change during rendering"
            return 1
        fi
    fi
    for index in "${!identities[@]}"; do
        if [[ "${PROXY_CONTRACT_INTERRUPTED}" == true ]]; then
            proxy_contract_die "reconcile interrupted before installation"
            return 1
        fi
        identity="${identities[index]}"
        path="${rooted_paths[index]}"
        candidate="${PROXY_CONTRACT_WORK_DIR}/candidate-${identity}"
        candidates[index]="${candidate}"
        backups[index]="${PROXY_CONTRACT_WORK_DIR}/backup-${identity}"
        base="${path}"
        mode="${modes[index]#0}"
        proxy_contract_owner_ids "${owners[index]}" "${groups[index]}" uid gid || return 1
        install_uids[index]="${uid}"
        install_gids[index]="${gid}"
        if [[ -e "${path}" ]]; then
            existed[index]=true
            cp -p -- "${path}" "${backups[index]}" || return 1
            if ! proxy_contract_matches_snapshot "${path}" "${source_states[index]}" \
                "${backups[index]}"; then
                proxy_contract_die "reconcile detected a concurrent change during rendering"
                return 1
            fi
            base="${backups[index]}"
            if [[ "${forms[index]}" == shared ]]; then
                mode="$(stat -Lc '%a' "${backups[index]}")" || return 1
                # Safe shared-file permissions belong to the existing site
                # configuration. Unsafe permissions return to the baseline.
                if (( (8#${mode} & 8#7022) != 0 )); then
                    mode="${modes[index]#0}"
                fi
                if grep -Fq -- "${PROXY_CONTRACT_BEGIN}" "${backups[index]}"; then
                    base="${PROXY_CONTRACT_WORK_DIR}/base-${identity}"
                    proxy_contract_remove_block "${identity}" "${backups[index]}" "${base}" || return 1
                fi
            fi
        else
            existed[index]=false
            base=""
            if [[ "${forms[index]}" == shared ]] &&
               ! proxy_contract_identity_was_created "${identity}"; then
                PROXY_CONTRACT_CREATED_IDENTITIES+=("${identity}")
            fi
        fi
        install_modes[index]="${mode}"
        proxy_contract_render_candidate "${os_family}" "${identity}" "${forms[index]}" \
            "${PROXY_CONTRACT_INPUT_URL}" "${base}" "${candidate}" || return 1
        proxy_contract_validate_marker_shape "${identity}" "${candidate}" \
            "${forms[index]}" "${formats[index]}" || return 1
        if [[ "${forms[index]}" == shared ]]; then
            proxy_contract_validate_shared_placement "${os_family}" "${identity}" "${candidate}" || return 1
        fi
        proxy_contract_validate_exact_content "${identity}" "${candidate}" \
            "${forms[index]}" "${PROXY_CONTRACT_INPUT_URL}" || return 1
        if [[ "${identity}" == sudo ]] && ! "${PROXY_CONTRACT_VISUDO}" -cf "${candidate}" 1>&2; then
            proxy_contract_die "sudo candidate validation failed"
            return 1
        fi
        if [[ "${existed[index]}" == false ]] || ! cmp -s -- "${path}" "${candidate}" ||
           [[ "$(stat -Lc '%u:%g:%a' "${path}")" != "${uid}:${gid}:${mode}" ]]; then
            changes+=("${index}")
            changed=true
        fi
    done
    for current_identity in "${PROXY_CONTRACT_CREATED_IDENTITIES[@]}"; do
        [[ -z "${created_csv}" ]] || created_csv+=","
        created_csv+="${current_identity}"
    done
    lock_candidate="${PROXY_CONTRACT_WORK_DIR}/lock-candidate"
    candidates[lock_index]="${lock_candidate}"
    proxy_contract_print_lock "${created_csv}" > "${lock_candidate}" || return 1
    for index in "${!rooted_paths[@]}"; do
        if ! proxy_contract_matches_snapshot "${rooted_paths[index]}" \
            "${source_states[index]}" "${backups[index]}"; then
            proxy_contract_die "reconcile detected a concurrent change before installation"
            return 1
        fi
    done
    for index in "${changes[@]}"; do
        if [[ "${PROXY_CONTRACT_INTERRUPTED}" == true ]] ||
           ! proxy_contract_matches_snapshot "${rooted_paths[index]}" \
               "${source_states[index]}" "${backups[index]}"; then
            rc=1
            break
        fi
        if ! proxy_contract_replace_file "${identities[index]}" "${candidates[index]}" \
            "${rooted_paths[index]}" "${install_uids[index]}" \
            "${install_gids[index]}" "${install_modes[index]}"; then
            rc=1
            break
        fi
        installed+=("${index}")
        installed_states[index]="$(proxy_contract_file_state "${rooted_paths[index]}")" || { rc=1; break; }
    done
    if [[ "${rc}" == 0 ]]; then
        for index in "${!identities[@]}"; do
            if ! proxy_contract_validate_regular_file "${identities[index]}" "${rooted_paths[index]}" \
                "${owners[index]}" "${groups[index]}" "${install_modes[index]}" ||
               ! proxy_contract_validate_exact_content "${identities[index]}" "${rooted_paths[index]}" \
                "${forms[index]}" "${PROXY_CONTRACT_INPUT_URL}"; then
                rc=1
                break
            fi
        done
    fi
    if [[ "${rc}" == 0 ]] && ! proxy_contract_sshd_effective; then
        rc=1
    fi
    if [[ "${PROXY_CONTRACT_INTERRUPTED}" == true ]]; then
        rc=1
    fi
    if [[ "${rc}" == 0 && "${changed}" == true ]] && ! proxy_contract_reload_sshd "${os_family}" 1>&2; then
        rc=1
    fi
    if [[ "${PROXY_CONTRACT_INTERRUPTED}" == true ]]; then
        rc=1
    fi
    if [[ "${rc}" == 0 ]]; then
        for index in "${!identities[@]}"; do
            if [[ -n "${installed_states[index]:-}" ]]; then
                proxy_contract_matches_snapshot "${rooted_paths[index]}" \
                    "${installed_states[index]}" "${candidates[index]}" || { rc=1; break; }
            else
                proxy_contract_matches_snapshot "${rooted_paths[index]}" \
                    "${source_states[index]}" "${backups[index]}" || { rc=1; break; }
            fi
        done
        proxy_contract_matches_snapshot "${lock_path}" "${source_states[lock_index]}" \
            "${backups[lock_index]}" || rc=1
    fi
    if [[ "${rc}" == 0 ]] &&
       { [[ "${lock_present}" == false ]] || ! cmp -s -- "${lock_path}" "${lock_candidate}"; }; then
        if proxy_contract_replace_file contract-lock "${lock_candidate}" "${lock_path}" \
            "${PROXY_CONTRACT_ROOT_UID}" "${PROXY_CONTRACT_ROOT_GID}" 600; then
            installed+=("${lock_index}")
            installed_states[lock_index]="$(proxy_contract_file_state "${lock_path}")" || rc=1
        else
            rc=1
        fi
    fi
    if [[ "${PROXY_CONTRACT_INTERRUPTED}" == true ]]; then
        rc=1
    fi
    trap '' HUP INT TERM
    if [[ "${PROXY_CONTRACT_INTERRUPTED}" == true ]]; then
        rc=1
    fi
    if [[ "${rc}" != 0 ]]; then
        proxy_contract_restore_reconciled installed rooted_paths backups existed installed_states candidates ||
            proxy_contract_die "reconcile rollback failed"
        if [[ "${#installed[@]}" != 0 ]]; then
            proxy_contract_reload_sshd "${os_family}" >/dev/null 2>&1 || true
        fi
        proxy_contract_die "reconcile failed; no successful change result"
        return 1
    fi
    if [[ "${PROXY_CONTRACT_SCOPE}" == general-server ]]; then
        printf 'proxy_contract schema=2 mode=reconcile scope=general-server os=%s identities=%s changed=%s\n' \
            "${os_family}" "${#identities[@]}" "${changed}"
    else
        printf 'proxy_contract schema=1 mode=reconcile os=%s identities=%s changed=%s\n' \
            "${os_family}" "${#identities[@]}" "${changed}"
    fi
}

function proxy_contract_any_artifact_present {
    local os_family="$1"
    local path index
    local -a identities=() paths=() owners=() groups=() modes=() forms=()
    local -a markers=() cleanups=() remnants=() formats=()

    proxy_contract_inventory \
        "${os_family}" identities paths owners groups modes forms \
        markers cleanups remnants formats || return 1
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
    local -a markers=() cleanups=() remnants=() formats=()

    proxy_contract_inventory \
        "${os_family}" identities paths owners groups modes forms \
        markers cleanups remnants formats || return 1
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
    local -a markers=() cleanups=() remnants=() formats=()
    local -a rooted_paths=() candidates=() candidate_modes=()

    proxy_contract_inventory \
        "${os_family}" identities paths owners groups modes forms \
        markers cleanups remnants formats || return 1
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
                "${cleanups[index]}" "${remnants[index]}" "${formats[index]}" || return 1
            proxy_contract_preflight_seal_identity \
                "${os_family}" "${identities[index]}" "${paths[index]}" \
                "${owners[index]}" "${groups[index]}" "${modes[index]}" \
                "${forms[index]}" "${proxy_url}" "${formats[index]}" || return 1
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
            proxy_contract_die "apply, reconcile, seal, and verify clean require root"
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
    return 0
}

function proxy_contract_check {
    local test_root="$1" input_fd="$2" source_path="$3"
    local python="" candidate index
    local -a identities=() paths=() owners=() groups=() modes=() forms=()
    local -a markers=() cleanups=() remnants=() formats=() inventory=()

    if [[ ! "${input_fd}" =~ ^[1-9][0-9]?$ ]] ||
       (( 10#${input_fd} < 3 || 10#${input_fd} > 63 )); then
        printf '%s\n' 'proxy_contract identity=input key=fd reason=invalid-fd' >&2
        return 1
    fi
    if [[ -z "${test_root}" ]]; then
        if (( EUID != 0 )) || [[ ! -o privileged ]]; then
            printf '%s\n' 'proxy_contract identity=runtime key=execution reason=privileged-root-required' >&2
            return 1
        fi
    elif [[ "${test_root}" == / ]]; then
        printf '%s\n' 'proxy_contract identity=runtime key=root reason=unsafe-test-root' >&2
        return 1
    fi
    for candidate in /usr/bin/python3 /usr/libexec/platform-python; do
        if [[ -x "${candidate}" ]]; then
            python="${candidate}"
            break
        fi
    done
    if [[ -z "${python}" ]]; then
        printf '%s\n' 'proxy_contract identity=runtime key=python reason=missing-interpreter' >&2
        return 1
    fi
    PROXY_CONTRACT_SCOPE=general-server
    proxy_contract_inventory rocky identities paths owners groups modes forms \
        markers cleanups remnants formats || return 1
    for index in "${!identities[@]}"; do
        inventory+=("${identities[index]}" "${paths[index]}")
    done
    # The parser is part of this source artifact; -I -B avoids inherited Python
    # configuration and bytecode writes. Configuration is always data, never code.
    "${python}" -I -B -c '
import errno
import fcntl
import hashlib
import os
import re
import stat
import sys
import urllib.parse
import xml.etree.ElementTree as ET

MAX_INPUT = 65536
MAX_FILE = 1048576
MAX_SOURCE = 4194304
OWNER_UID = os.geteuid() if sys.argv[1] else 0
OWNER_GID = os.getegid() if sys.argv[1] else 0
FIELDS = {"schema", "scope", "existing_keys", "proxy_url", "no_proxy",
          "maven_non_proxy_hosts", "script_sha256"}
IDENTITIES = {"profile", "environment", "dnf", "pip", "git", "maven"}
PROXY_KEYS = ("http_proxy", "https_proxy", "ftp_proxy", "no_proxy",
              "HTTP_PROXY", "HTTPS_PROXY", "FTP_PROXY", "NO_PROXY")
MAVEN_NAMESPACE = "http://maven.apache.org/SETTINGS/1.0.0"
SEALS = getattr(fcntl, "F_GET_SEALS", 1034)
ALL_SEALS = 15
READ_FLAGS = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_NOATIME
DIR_FLAGS = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_DIRECTORY | os.O_NOATIME


class Refusal(Exception):
    def __init__(self, identity, key, reason):
        self.identity, self.key, self.reason = identity, key, reason


def refuse(identity, key, reason):
    raise Refusal(identity, key, reason)


def diagnostic(identity, key, reason):
    print("proxy_contract identity={} key={} reason={}".format(identity, key, reason),
          file=sys.stderr)


def signature(value):
    return (value.st_dev, value.st_ino, value.st_uid, value.st_gid, value.st_mode,
            value.st_nlink, value.st_size, value.st_mtime_ns, value.st_ctime_ns)


def metadata(identity, value, directory=False):
    if value.st_uid != OWNER_UID or value.st_gid != OWNER_GID:
        refuse(identity, "metadata", "ownership-conflict")
    if value.st_mode & 0o7022:
        refuse(identity, "metadata", "unsafe-mode")
    required = 0o500 if directory else 0o400
    if value.st_mode & required != required:
        refuse(identity, "metadata", "unreadable-mode")
    if directory:
        if not stat.S_ISDIR(value.st_mode):
            refuse(identity, "path", "not-directory")
    elif not stat.S_ISREG(value.st_mode) or value.st_nlink != 1:
        refuse(identity, "path", "not-single-regular-file")


def read_fd(fd, limit, identity):
    chunks = []
    size = 0
    while size <= limit:
        part = os.read(fd, min(65536, limit + 1 - size))
        if not part:
            return b"".join(chunks)
        chunks.append(part)
        size += len(part)
    refuse(identity, "content", "too-large")


def source_state(path):
    match = re.fullmatch("/(?:proc/self/fd|dev/fd)/([0-9]+)", path)
    fd = os.open("/proc/self/fd/" + match.group(1), os.O_RDONLY | os.O_CLOEXEC | os.O_NOATIME) \
        if match else os.open(path, READ_FLAGS)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode):
            refuse("source", "script_sha256", "not-regular")
        if before.st_nlink == 0 and match:
            if fcntl.fcntl(fd, SEALS) & ALL_SEALS != ALL_SEALS:
                refuse("source", "script_sha256", "unsealed-source")
        else:
            metadata("source", before)
        data = read_fd(fd, MAX_SOURCE, "source")
        if signature(before) != signature(os.fstat(fd)):
            refuse("source", "script_sha256", "concurrent-change")
        return signature(before), hashlib.sha256(data).hexdigest()
    finally:
        os.close(fd)


def input_data(fd):
    value = os.fstat(fd)
    if fcntl.fcntl(fd, fcntl.F_GETFL) & os.O_ACCMODE != os.O_RDONLY:
        refuse("input", "fd", "not-read-only")
    if value.st_uid != OWNER_UID or value.st_gid != OWNER_GID \
            or stat.S_IMODE(value.st_mode) != 0o600:
        refuse("input", "fd", "not-private")
    if not stat.S_ISREG(value.st_mode):
        refuse("input", "fd", "unsupported-fd")
    if value.st_nlink not in (0, 1):
        refuse("input", "fd", "unsafe-links")
    reader = os.open("/proc/self/fd/" + str(fd), os.O_RDONLY | os.O_CLOEXEC | os.O_NOATIME)
    try:
        if signature(value) != signature(os.fstat(reader)):
            refuse("input", "fd", "concurrent-change")
        data = read_fd(reader, MAX_INPUT, "input").decode("ascii")
        if signature(value) != signature(os.fstat(reader)):
            refuse("input", "fd", "concurrent-change")
    finally:
        os.close(reader)
    if any(ord(char) < 32 and char != "\n" or ord(char) == 127 for char in data):
        refuse("input", "fields", "invalid-field")
    lines = data.split("\n")
    if lines[-1] == "":
        lines.pop()
    result = {}
    for line in lines:
        if "=" not in line:
            refuse("input", "fields", "invalid-field")
        key, text = line.split("=", 1)
        if key not in FIELDS or key in result:
            refuse("input", "fields", "unknown-or-duplicate-field")
        result[key] = text
    if set(result) != FIELDS:
        refuse("input", "fields", "missing-field")
    if result["schema"] != "3" or result["scope"] != "general-server" \
            or result["existing_keys"] != "reconcile":
        refuse("input", "schema", "unsupported-policy")
    if not re.fullmatch("[0-9a-f]{64}", result["script_sha256"]):
        refuse("input", "script_sha256", "invalid-hash")
    if not re.fullmatch("[A-Za-z0-9.,:/_*+-]*", result["no_proxy"]):
        refuse("input", "no_proxy", "unsupported-value")
    if not re.fullmatch("[A-Za-z0-9.*|:_-]*", result["maven_non_proxy_hosts"]):
        refuse("input", "maven_non_proxy_hosts", "unsupported-value")
    url = result["proxy_url"]
    if not re.fullmatch("https?://[A-Za-z0-9.-]+(?::(?:0|[1-9][0-9]*))?/?", url):
        refuse("input", "proxy_url", "unsupported-url")
    parsed = urllib.parse.urlsplit(url)
    try:
        port = parsed.port
    except ValueError:
        refuse("input", "proxy_url", "invalid-port")
    if port is not None and not 1 <= port <= 65535:
        refuse("input", "proxy_url", "invalid-port")
    return result, parsed, signature(value)


class Files:
    def __init__(self, root):
        if root != "/" and (not os.path.isabs(root) or os.path.realpath(root) != root):
            refuse("runtime", "root", "unsafe-test-root")
        self.path = root
        self.fd = os.open(root, DIR_FLAGS)
        metadata("runtime", os.fstat(self.fd), True)
        self.root_state = signature(os.fstat(self.fd))
        self.directories = {}
        self.observed = {}
        self.os_entry_state = None

    def os_release(self):
        directory = os.open("etc", DIR_FLAGS, dir_fd=self.fd)
        try:
            current = os.fstat(directory)
            metadata("runtime", current, True)
            self.directories["etc"] = signature(current)
            entry = os.stat("os-release", dir_fd=directory, follow_symlinks=False)
            self.os_entry_state = signature(entry)
            if not stat.S_ISLNK(entry.st_mode):
                return "/etc/os-release"
            if entry.st_uid != OWNER_UID or entry.st_gid != OWNER_GID:
                refuse("runtime", "os", "ownership-conflict")
            target = os.readlink("os-release", dir_fd=directory)
        finally:
            os.close(directory)
        if target.startswith("/"):
            refuse("runtime", "os", "unsafe-path")
        parts = ["etc"]
        for part in target.split("/"):
            if part == "..":
                if not parts:
                    refuse("runtime", "os", "unsafe-path")
                parts.pop()
            elif part not in ("", "."):
                parts.append(part)
        if not parts:
            refuse("runtime", "os", "unsafe-path")
        return "/" + "/".join(parts)

    def read(self, identity, path, observe=True):
        parts = path.split("/")[1:]
        if not path.startswith("/") or any(part in ("", ".", "..") for part in parts):
            refuse(identity, "path", "unsafe-path")
        directory = os.dup(self.fd)
        try:
            for index, part in enumerate(parts[:-1]):
                child = os.open(part, DIR_FLAGS, dir_fd=directory)
                os.close(directory)
                directory = child
                current = os.fstat(directory)
                metadata(identity, current, True)
                name = "/".join(parts[:index + 1])
                state = signature(current)
                if name in self.directories and self.directories[name] != state:
                    refuse(identity, "path", "concurrent-change")
                self.directories[name] = state
            fd = os.open(parts[-1], READ_FLAGS, dir_fd=directory)
            try:
                before = os.fstat(fd)
                metadata(identity, before)
                data = read_fd(fd, MAX_FILE, identity)
                if signature(before) != signature(os.fstat(fd)):
                    refuse(identity, "content", "concurrent-change")
                value = (signature(before), hashlib.sha256(data).digest())
            finally:
                os.close(fd)
        except FileNotFoundError:
            data, value = None, None
        except OSError as exc:
            if exc.errno in (errno.ELOOP, errno.ENOTDIR):
                refuse(identity, "path", "unsafe-path")
            refuse(identity, "path", "unreadable")
        finally:
            os.close(directory)
        if observe:
            self.observed[(identity, path)] = value
        elif self.observed[(identity, path)] != value:
            refuse(identity, "content", "concurrent-change")
        if data is not None and b"\x00" in data:
            refuse(identity, "content", "invalid-text")
        return data

    def verify(self):
        for identity, path in self.observed:
            self.read(identity, path, False)
        directory = os.open("etc", DIR_FLAGS, dir_fd=self.fd)
        try:
            entry = os.stat("os-release", dir_fd=directory, follow_symlinks=False)
            if self.os_entry_state != signature(entry):
                refuse("runtime", "os", "concurrent-change")
        finally:
            os.close(directory)
        if self.root_state != signature(os.stat(self.path, follow_symlinks=False)):
            refuse("runtime", "root", "concurrent-change")


def literal(identity, key, value):
    match = re.fullmatch(
        "(?:\"([^\"$`\\\\]*)\"|\x27([^\x27]*)\x27|([^\\s\"\x27$`\\\\;&|<>(){}#]*))(?:[ \\t]+#.*)?", value.strip())
    if not match:
        refuse(identity, key, "unsupported-syntax")
    return next(part for part in match.groups() if part is not None)


def assignments(identity, text):
    values = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        pattern = "(export[ \\t]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)" if identity == "profile" \
            else "(export[ \\t]+)?([A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(.*)"
        match = re.fullmatch(pattern, line)
        if not match or (identity == "environment" and match.group(1)):
            refuse(identity, "content", "unsupported-syntax")
        exported, key, value = match.groups()
        if identity == "profile" and value[:1].isspace():
            if value.lstrip().startswith("#"):
                value = ""
            else:
                refuse(identity, "content", "unsupported-syntax")
        relevant = key in PROXY_KEYS
        diagnostic_key = key if relevant else "content"
        if identity == "profile" and relevant and not exported:
            refuse(identity, key, "not-exported")
        alias = re.fullmatch(
            "\"\\$(?:([A-Za-z_][A-Za-z0-9_]*)|\\{([A-Za-z_][A-Za-z0-9_]*)\\})\"(?:[ \\t]+#.*)?", value)
        if identity == "profile" and relevant and alias:
            reference = alias.group(1) or alias.group(2)
            if reference not in values:
                refuse(identity, key, "unsupported-reference")
            value = values[reference]
        else:
            value = literal(identity, diagnostic_key, value)
        if relevant:
            if key in values:
                refuse(identity, key, "duplicate-key")
            values[key] = value
    return values


def git_literal(value):
    # Accept complete literal values and comments without evaluating expressions.
    if "\\" in value:
        refuse("git", "content", "unsupported-syntax")
    if value.startswith("\""):
        match = re.fullmatch("\"([^\"\\\\]*)\"[ \\t]*(?:[#;].*)?", value)
        if not match:
            refuse("git", "content", "unsupported-syntax")
        return match.group(1)
    value = re.split("[#;]", value, maxsplit=1)[0].rstrip()
    if "\"" in value:
        refuse("git", "content", "unsupported-syntax")
    return value


def ini_values(identity, text):
    values = {}
    section = ""
    sections = set()
    seen = set()
    for line in text.splitlines():
        indented = line.startswith((" ", "\t"))
        line = line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if identity != "git" and indented:
            refuse(identity, "content", "unsupported-continuation")
        if line.startswith("["):
            match = re.fullmatch("\\[([A-Za-z0-9_.-]+)(?:\\s+\"([^\"\\\\]+)\")?\\]\\s*(?:[#;].*)?", line)
            if not match:
                refuse(identity, "content", "unsupported-section")
            section = match.group(1)
            if identity == "git":
                section = section.lower()
            elif match.group(2):
                refuse(identity, "content", "unsupported-section")
            if match.group(2):
                section += ":" + match.group(2)
            if section in sections:
                refuse(identity, "content", "duplicate-section")
            sections.add(section)
            if identity == "git" and section.split(":")[0] in ("include", "includeif"):
                refuse(identity, "content", "unsupported-include")
            continue
        match = re.fullmatch("([A-Za-z0-9_.-]+)\\s*=\\s*(.*)", line)
        if not match or not section:
            refuse(identity, "content", "unsupported-syntax")
        key, value = match.groups()
        if identity == "git":
            if not re.fullmatch("[A-Za-z][A-Za-z0-9-]*", key):
                refuse(identity, "content", "unsupported-syntax")
            value = git_literal(value)
        elif key.lower() == "proxy" and key != "proxy":
            refuse(identity, "proxy", "unsupported-key-case")
        key = key.lower()
        if identity != "git" and (section, key) in seen:
            refuse(identity, "content", "duplicate-key")
        seen.add((section, key))
        if key != "proxy":
            continue
        if (section, key) in values:
            refuse(identity, "proxy", "duplicate-key")
        required = {"dnf": ("main",), "pip": ("global",), "git": ("http", "https")}[identity]
        if section not in required:
            refuse(identity, "proxy", "unsupported-override")
        if identity != "git" and ("$" in value or "%" in value or "\\" in value
                                  or value.startswith(("\"", "\x27"))):
            refuse(identity, "proxy", "unsupported-expression")
        values[(section, key)] = value
    return values


def maven_values(text):
    if re.search("<!\\s*(DOCTYPE|ENTITY)", text, re.I):
        refuse("maven", "content", "unsupported-declaration")
    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        refuse("maven", "content", "invalid-xml")
    namespace = "{" + MAVEN_NAMESPACE + "}" if root.tag.startswith("{") else ""
    if root.tag != namespace + "settings":
        refuse("maven", "content", "unsupported-namespace")
    containers = root.findall(namespace + "proxies")
    if len(containers) > 1:
        refuse("maven", "proxy", "duplicate-container")
    values = {}
    ids = set()
    for container in containers:
        for proxy in container:
            if proxy.tag != namespace + "proxy" or proxy.attrib:
                refuse("maven", "proxy", "unsupported-syntax")
            fields = {}
            for child in proxy:
                key = child.tag[len(namespace):] if child.tag.startswith(namespace) else ""
                if not key or key in fields or child.attrib or len(child):
                    refuse("maven", "proxy", "unsupported-syntax")
                fields[key] = (child.text or "").strip()
            if fields.get("active") == "false":
                continue
            if fields.get("active") != "true":
                refuse("maven", "active", "explicit-active-required")
            if fields.get("username") or fields.get("password"):
                refuse("maven", "proxy", "unsupported-credentials")
            protocol = fields.get("protocol")
            if protocol not in ("http", "https"):
                refuse("maven", "protocol", "unsupported-protocol")
            if protocol in values or (fields.get("id") and fields["id"] in ids):
                refuse("maven", "proxy", "duplicate-proxy")
            ids.add(fields.get("id"))
            values[protocol] = fields
    return values


def run():
    root, fd, source = sys.argv[1:4]
    arguments = sys.argv[4:]
    inventory = list(zip(arguments[::2], arguments[1::2]))
    if len(arguments) != 12 or {identity for identity, _ in inventory} != IDENTITIES:
        refuse("runtime", "inventory", "invalid-inventory")
    desired, proxy, input_state = input_data(int(fd))
    initial_source = source_state(source)
    if initial_source[1] != desired["script_sha256"]:
        refuse("source", "script_sha256", "hash-mismatch")
    files = Files(root or "/")
    try:
        # Resolve Rocky relative os-release link without crossing the root.
        os_path = files.os_release()
        os_data = files.read("runtime", os_path)
        if os_data is None:
            refuse("runtime", "os", "missing-os-release")
        os_values = {}
        for line in os_data.decode("utf-8").splitlines():
            match = re.fullmatch("(ID|VERSION_ID)=(.*)", line)
            if match:
                if match.group(1) in os_values:
                    refuse("runtime", "os", "duplicate-key")
                os_values[match.group(1)] = literal("runtime", "os", match.group(2))
        if os_values != {"ID": "rocky", "VERSION_ID": "8.10"}:
            refuse("runtime", "os", "unsupported-platform")
        changed = False

        def compare(identity, key, actual, expected):
            nonlocal changed
            if actual != expected:
                changed = True
                diagnostic(identity, key, "missing-key" if actual is None else "value-mismatch")

        for identity, path in inventory:
            data = files.read(identity, path)
            if data is None:
                changed = True
                diagnostic(identity, "content", "missing-file")
                continue
            text = data.decode("utf-8")
            if any((ord(char) < 32 or 127 <= ord(char) <= 159 or char.isspace())
                   and char not in " \t\n" for char in text):
                refuse(identity, "content", "unsupported-whitespace")
            if identity in ("profile", "environment"):
                values = assignments(identity, text)
                for key in PROXY_KEYS:
                    compare(identity, key, values.get(key), desired["no_proxy"]
                            if key.lower() == "no_proxy" else desired["proxy_url"])
            elif identity in ("dnf", "pip", "git"):
                values = ini_values(identity, text)
                for section in {"dnf": ("main",), "pip": ("global",),
                                "git": ("http", "https")}[identity]:
                    compare(identity, "proxy", values.get((section, "proxy")), desired["proxy_url"])
            else:
                values = maven_values(text)
                for protocol in ("http", "https"):
                    fields = values.get(protocol, {})
                    # The host is compared as written, like every other artifact.
                    compare(identity, "host", fields.get("host"), proxy.netloc.partition(":")[0])
                    compare(identity, "port", fields.get("port"), str(proxy.port or
                            (443 if proxy.scheme == "https" else 80)))
                    compare(identity, "nonProxyHosts", fields.get("nonProxyHosts"),
                            desired["maven_non_proxy_hosts"])
        files.verify()
        if initial_source != source_state(source):
            refuse("source", "script_sha256", "concurrent-change")
        if input_state != signature(os.fstat(int(fd))):
            refuse("input", "fd", "concurrent-change")
        print("proxy_contract schema=3 mode=check scope=general-server os=rocky "
              "identities=6 status=" + ("needs-change" if changed else "ready"))
        return 2 if changed else 0
    finally:
        os.close(files.fd)


try:
    sys.exit(run())
except Refusal as exc:
    diagnostic(exc.identity, exc.key, exc.reason)
except (OSError, ValueError, UnicodeError, OverflowError):
    diagnostic("runtime", "content", "unreadable-or-invalid")
except Exception:
    diagnostic("runtime", "content", "internal-error")
sys.exit(1)
' "${test_root}" "${input_fd}" "${source_path}" "${inventory[@]}"
}

function proxy_contract_main {
    local test_root="" os_family input_path input_fd=""
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
            --input-fd)
                if (( $# < 2 )) || [[ -n "${input_fd}" ]]; then
                    printf '%s\n' 'proxy_contract identity=input key=fd reason=invalid-fd' >&2
                    return 1
                fi
                input_fd="$2"
                shift 2
                ;;
            *)
                operands+=("$1")
                shift
                ;;
        esac
    done
    unset BASH_ENV ENV CDPATH TMPDIR TMP TEMP
    export LC_ALL=C
    if [[ "${#operands[@]}" == 1 && "${operands[0]}" == check ]]; then
        proxy_contract_check "${test_root}" "${input_fd}" "${BASH_SOURCE[0]:-}"
        return "$?"
    fi
    if [[ -n "${input_fd}" ]]; then
        printf '%s\n' 'proxy_contract identity=input key=fd reason=check-only-option' >&2
        return 1
    fi
    if ! { [[ "${#operands[@]}" == 1 &&
              ( "${operands[0]}" == apply || "${operands[0]}" == reconcile || "${operands[0]}" == seal ) ]] ||
           [[ "${#operands[@]}" == 2 && "${operands[0]}" == verify &&
              "${operands[1]}" == clean ]]; }; then
        proxy_contract_die \
            "usage: proxy_contract.bash [--test-root <absolute-path>] {apply|reconcile|seal|verify clean|check --input-fd N}"
        return 1
    fi

    PROXY_CONTRACT_OPERATION="${operands[0]}"
    PROXY_CONTRACT_SCOPE=cloud
    PROXY_CONTRACT_INPUT_SCHEMA=1
    PROXY_CONTRACT_INPUT_LOADED=false
    proxy_contract_configure_root "${test_root}" || return 1
    input_path="$(proxy_contract_root_path "${PROXY_CONTRACT_INPUT}")"
    # Select the input scope before account lookup or guest command preflight.
    # Cloud cleanup also permits an absent input after transient state removal.
    if [[ "${PROXY_CONTRACT_OPERATION}" == apply || "${PROXY_CONTRACT_OPERATION}" == reconcile ||
          -e "${input_path}" || -L "${input_path}" ]]; then
        proxy_contract_parse_input || return 1
    fi
    if [[ "${PROXY_CONTRACT_SCOPE}" == cloud ]]; then
        proxy_contract_parse_passwd || return 1
    fi
    trap proxy_contract_cleanup_temps EXIT
    trap 'exit 1' HUP INT TERM
    if [[ "${operands[0]}" == reconcile ]]; then
        trap 'PROXY_CONTRACT_INTERRUPTED=true' HUP INT TERM
    fi
    if ! os_family="$(proxy_contract_parse_os_release)"; then
        return 1
    fi
    case "${operands[0]}" in
        apply) proxy_contract_apply "${os_family}" ;;
        reconcile) proxy_contract_reconcile "${os_family}" ;;
        seal) proxy_contract_seal "${os_family}" ;;
        verify) proxy_contract_verify_clean "${os_family}" ;;
    esac
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]] ||
   [[ -z "${BASH_SOURCE[0]:-}" && "$0" == /bin/bash && -o privileged ]]; then
    set -euo pipefail
    proxy_contract_main "$@"
fi
