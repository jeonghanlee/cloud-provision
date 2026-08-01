#!/bin/bash -p
#
# Validates a complete IOC runner bake manifest against retained sources.

if [[ ! -o privileged ]]; then
    printf "%s\n" "error: execute this script directly or with /bin/bash -p" >&2
    exit 1
fi

set -euo pipefail

unset BASH_ENV ENV CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
unset GIT_CONFIG_COUNT GIT_CEILING_DIRECTORIES
unset TMPDIR TMP TEMP

readonly SAFE_PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH="${SAFE_PATH}"
export LC_ALL=C

declare -g MANIFEST="/etc/iocrunner-bake.manifest"
declare -g EPICS_CHECKOUT="/opt/epics"
declare -g RUNNER_CHECKOUT="/home/vmadmin/gitsrc/epics-ioc-runner"
declare -g RUNNER_BIN="/usr/local/bin/ioc-runner"
readonly MANIFEST_HEADER="# iocrunner golden bake manifest"

declare -Ag EXPECTED_REPOS=(
    [app_con]="https://github.com/jeonghanlee/con"
    [app_procserv]="https://github.com/jeonghanlee/procServ-env"
    [app_conserver]="https://github.com/jeonghanlee/conserver-env"
    [app_epics]="https://github.com/jeonghanlee/EPICS-env-distribution"
    [app_ioc_runner]="https://github.com/jeonghanlee/epics-ioc-runner"
)
readonly -a REQUIRED_APPS=(
    app_con
    app_procserv
    app_conserver
    app_epics
    app_ioc_runner
)

declare -Ag RECORD_COUNT=()
declare -Ag APP_REPO=()
declare -Ag APP_COMMIT=()
declare -Ag APP_STATE=()
declare -Ag APP_TAG=()
declare -g CHECKOUT_COMMIT=""
declare -g CHECKOUT_STATE=""
declare -g CHECKOUT_TAG=""

function die {
    printf "error: %s\n" "$*" >&2
    exit 1
}

function require_command {
    local command_name="$1"
    local command_path

    command_path="$(command -v "${command_name}" 2>/dev/null || true)"
    [[ -n "${command_path}" && -x "${command_path}" ]] \
        || die "required command not found: ${command_name}"
}

function increment_count {
    local key="$1"
    RECORD_COUNT["${key}"]=$(( ${RECORD_COUNT["${key}"]:-0} + 1 ))
}

function require_singleton {
    local key="$1"
    [[ "${RECORD_COUNT["${key}"]:-0}" == "1" ]] \
        || die "manifest must contain exactly one ${key} record"
}

function parse_app_record {
    local line="$1"
    local app_name="$2"
    local schema repo commit state tag recorded_at extra
    local requested=""

    read -r app_name schema repo commit state tag recorded_at extra <<< "${line}"

    # Exactly one optional trailing field is allowed, only on app_ioc_runner,
    # only spelled requested=<ref>. It records what the caller asked for beside
    # the commit that was resolved, and the two may legitimately differ: a ref
    # is intent, and the tag that happens to point at the resolved commit is
    # not. So it is checked for shape only and is not tied to tag or state.
    if [[ -n "${extra:-}" ]]; then
        [[ "${app_name}" == "app_ioc_runner" ]] \
            || die "application record has extra fields: ${app_name}"
        [[ "${extra}" == requested=* ]] \
            || die "unexpected trailing field: ${app_name}"
        requested="${extra#requested=}"
        [[ -n "${requested}" && "${requested}" != *[[:space:]]* ]] \
            || die "invalid requested ref: ${app_name}"
    fi
    [[ "${schema}" == "schema=1" ]] || die "invalid application schema: ${app_name}"
    [[ "${repo}" == repo=* ]] || die "missing repository field: ${app_name}"
    [[ "${commit}" == commit=* ]] || die "missing commit field: ${app_name}"
    [[ "${state}" == state=* ]] || die "missing state field: ${app_name}"
    [[ "${tag}" == tag=* ]] || die "missing tag field: ${app_name}"
    [[ "${recorded_at}" == recorded_at=* ]] || die "missing timestamp field: ${app_name}"

    repo="${repo#repo=}"
    commit="${commit#commit=}"
    state="${state#state=}"
    tag="${tag#tag=}"
    recorded_at="${recorded_at#recorded_at=}"

    [[ "${repo}" == "${EXPECTED_REPOS["${app_name}"]}" ]] \
        || die "unexpected repository identity: ${app_name}"
    [[ "${commit}" =~ ^[0-9a-f]{40}$ ]] \
        || die "invalid application commit: ${app_name}"
    [[ "${recorded_at}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
        || die "invalid application timestamp: ${app_name}"
    [[ -n "${tag}" && "${tag}" != *[[:space:]]* ]] \
        || die "invalid application tag: ${app_name}"

    case "${state}" in
        dirty)
            [[ "${tag}" == "-" ]] || die "dirty record must use tag=-: ${app_name}"
            ;;
        clean-tagged)
            [[ "${tag}" != "-" ]] || die "clean-tagged record requires a tag: ${app_name}"
            ;;
        clean-untagged)
            [[ "${tag}" == "-" ]] || die "clean-untagged record must use tag=-: ${app_name}"
            ;;
        *)
            die "invalid application state: ${app_name}"
            ;;
    esac

    APP_REPO["${app_name}"]="${repo}"
    APP_COMMIT["${app_name}"]="${commit}"
    APP_STATE["${app_name}"]="${state}"
    APP_TAG["${app_name}"]="${tag}"
    increment_count "${app_name}"
}

function read_checkout_identity {
    local checkout="$1"
    local dirty_output

    [[ -d "${checkout}/.git" ]] || die "retained checkout is missing: ${checkout}"
    CHECKOUT_COMMIT="$(/usr/bin/git -C "${checkout}" rev-parse --verify HEAD)"
    [[ "${CHECKOUT_COMMIT}" =~ ^[0-9a-f]{40}$ ]] \
        || die "retained checkout has an invalid HEAD: ${checkout}"

    dirty_output="$(/usr/bin/git -C "${checkout}" status --porcelain=v1 --untracked-files=normal)"
    if [[ -n "${dirty_output}" ]]; then
        CHECKOUT_STATE="dirty"
        CHECKOUT_TAG="-"
        return
    fi

    CHECKOUT_TAG="$(/usr/bin/git -C "${checkout}" tag --points-at HEAD | /usr/bin/sort | /usr/bin/awk 'NR == 1 {print; exit}')"
    if [[ -n "${CHECKOUT_TAG}" ]]; then
        CHECKOUT_STATE="clean-tagged"
    else
        CHECKOUT_STATE="clean-untagged"
        CHECKOUT_TAG="-"
    fi
}

function compare_checkout {
    local app_name="$1"
    local checkout="$2"
    local actual_repo

    read_checkout_identity "${checkout}"
    actual_repo="$(/usr/bin/git -C "${checkout}" config --local --get remote.origin.url)"

    [[ "${actual_repo}" == "${APP_REPO["${app_name}"]}" ]] \
        || die "retained repository mismatch: ${app_name}"
    [[ "${CHECKOUT_COMMIT}" == "${APP_COMMIT["${app_name}"]}" ]] \
        || die "retained commit mismatch: ${app_name}"
    [[ "${CHECKOUT_STATE}" == "${APP_STATE["${app_name}"]}" ]] \
        || die "retained dirty state mismatch: ${app_name}"
    [[ "${CHECKOUT_TAG}" == "${APP_TAG["${app_name}"]}" ]] \
        || die "retained tag mismatch: ${app_name}"
}

if [[ "$#" == "4" ]]; then
    MANIFEST="$1"
    EPICS_CHECKOUT="$2"
    RUNNER_CHECKOUT="$3"
    RUNNER_BIN="$4"
elif [[ "$#" != "0" ]]; then
    die "usage: validate_iocrunner_bake.bash [manifest epics_checkout runner_checkout runner_bin]"
fi

[[ "${EUID}" == "0" ]] || die "root privileges are required"

for command_name in awk git sort stat; do
    require_command "${command_name}"
done

[[ "${MANIFEST}" == /* ]] || die "manifest path must be absolute"
[[ ! -L "${MANIFEST}" ]] || die "manifest must not be a symbolic link"
[[ -s "${MANIFEST}" && -f "${MANIFEST}" ]] || die "manifest must be a non-empty regular file"
[[ "$(/usr/bin/stat -Lc '%u' -- "${MANIFEST}")" == "0" ]] \
    || die "manifest is not owned by root"
(( (8#$(/usr/bin/stat -Lc '%a' -- "${MANIFEST}") & 8#022) == 0 )) \
    || die "manifest is group- or world-writable"
[[ -x "${RUNNER_BIN}" && ! -L "${RUNNER_BIN}" ]] \
    || die "ioc-runner executable is missing or unsafe"

declare -g LINE
declare -g KEY
declare -g LINE_NUMBER=0
declare -g PIP_COUNT=0

while IFS= read -r LINE || [[ -n "${LINE}" ]]; do
    LINE_NUMBER=$((LINE_NUMBER + 1))
    [[ "${LINE}" != *"(live)"* ]] || die "live provenance marker is forbidden"

    if [[ "${LINE_NUMBER}" == "1" ]]; then
        [[ "${LINE}" == "${MANIFEST_HEADER}" ]] || die "manifest header is malformed"
        increment_count header
        continue
    fi

    [[ -n "${LINE}" ]] || die "manifest contains an empty line"
    KEY="${LINE%% *}"
    case "${KEY}" in
        manifest_schema)
            [[ "${LINE}" == "manifest_schema 1" ]] || die "manifest schema is malformed"
            increment_count manifest_schema
            ;;
        bake_date)
            [[ "${LINE#bake_date }" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
                || die "bake date is malformed"
            increment_count bake_date
            ;;
        os_type)
            [[ "${LINE}" == "os_type rocky8" || "${LINE}" == "os_type debian13" ]] \
                || die "OS selector is invalid"
            increment_count os_type
            ;;
        cloud-provision|ansible-provision)
            [[ "${LINE#* }" =~ ^[0-9a-f]{40}(-dirty)?$ ]] \
                || die "repository identity is invalid: ${KEY}"
            increment_count "${KEY}"
            ;;
        epics_env_version|epics_base_version)
            [[ "${LINE}" == "${KEY} "* && "${LINE#* }" != *[[:space:]]* ]] \
                || die "EPICS selector is malformed: ${KEY}"
            increment_count "${KEY}"
            ;;
        base_image)
            read -r _ schema name digest extra <<< "${LINE}"
            [[ -z "${extra:-}" && "${schema}" == "schema=1" && "${name}" == name=* ]] \
                || die "base image identity is malformed"
            [[ "${digest}" =~ ^sha256=[0-9a-f]{64}$ ]] \
                || die "base image digest is malformed"
            [[ -n "${name#name=}" && "${name#name=}" != *[[:space:]]* ]] \
                || die "base image name is malformed"
            increment_count base_image
            ;;
        app_con|app_procserv|app_conserver|app_epics|app_ioc_runner)
            parse_app_record "${LINE}" "${KEY}"
            ;;
        pip3)
            [[ "${LINE}" == "pip3 "* && -n "${LINE#pip3 }" ]] \
                || die "pip provenance is malformed"
            PIP_COUNT=$((PIP_COUNT + 1))
            ;;
        *)
            die "unknown manifest record at line ${LINE_NUMBER}: ${KEY}"
            ;;
    esac
done < "${MANIFEST}"

for singleton in header manifest_schema bake_date os_type cloud-provision ansible-provision \
                 epics_env_version epics_base_version base_image; do
    require_singleton "${singleton}"
done

for app_name in "${REQUIRED_APPS[@]}"; do
    require_singleton "${app_name}"
done

[[ "${PIP_COUNT}" -gt "0" ]] || die "manifest contains no pip provenance"

compare_checkout app_epics "${EPICS_CHECKOUT}"
compare_checkout app_ioc_runner "${RUNNER_CHECKOUT}"

declare -g RUNNER_OUTPUT
declare -g RUNNER_IDENTITY
declare -g EXPECTED_RUNNER_IDENTITY

RUNNER_OUTPUT="$("${RUNNER_BIN}" -V)"
RUNNER_IDENTITY="$(/usr/bin/awk 'NR == 1 && match($0, /\([^)]*\)/) {print substr($0, RSTART + 1, RLENGTH - 2)}' <<< "${RUNNER_OUTPUT}")"
EXPECTED_RUNNER_IDENTITY="${APP_COMMIT[app_ioc_runner]:0:7}"
if [[ "${APP_STATE[app_ioc_runner]}" == "dirty" ]]; then
    EXPECTED_RUNNER_IDENTITY+="-dirty"
fi

[[ "${RUNNER_IDENTITY}" == "${EXPECTED_RUNNER_IDENTITY}" ]] \
    || die "installed ioc-runner identity mismatch"

printf "%s\n" "IOC runner bake provenance is valid."
