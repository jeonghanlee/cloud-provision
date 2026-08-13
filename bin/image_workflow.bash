#!/usr/bin/env bash
#
# Shared image naming, copy, and creation-record operations.

function image_workflow_new_run_id {
    local timestamp
    local nonce
    local digest

    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    nonce="$(date -u +%s%N)-${BASHPID}-${RANDOM}"
    digest="$(printf "%s\n" "${nonce}" | sha256sum)"
    digest="${digest%% *}"
    printf "%s-%s\n" "${timestamp}" "${digest:0:12}"
}

function image_workflow_validate_run_id {
    local run_id="$1"

    [[ "${run_id}" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}$ ]]
}

function image_workflow_resolve_run_id {
    local run_id="${1:-}"

    if [[ -z "${run_id}" ]]; then
        run_id="$(image_workflow_new_run_id)"
    fi
    image_workflow_validate_run_id "${run_id}" || return 1
    printf "%s\n" "${run_id}"
}

function image_workflow_vm_name {
    local prefix="$1"
    local os_type="$2"
    local node_id="$3"
    local run_id="${4:-}"
    local name="${prefix}-${os_type}-${node_id}"

    if [[ -n "${run_id}" ]]; then
        image_workflow_validate_run_id "${run_id}" || return 1
        name="${name}-${run_id}"
    fi
    printf "%s\n" "${name}"
}

function image_workflow_vm_disk_path {
    local image_dir="$1"
    local prefix="$2"
    local os_type="$3"
    local node_id="$4"
    local run_id="${5:-}"
    local vm_name

    vm_name="$(image_workflow_vm_name \
        "${prefix}" "${os_type}" "${node_id}" "${run_id}")" || return 1
    printf "%s/%s.qcow2\n" "${image_dir}" "${vm_name}"
}

function image_workflow_image_name {
    local kind="$1"
    local platform="$2"
    local run_id="$3"

    image_workflow_validate_run_id "${run_id}" || return 1
    printf "%s-%s-%s.qcow2\n" "${kind}" "${platform}" "${run_id}"
}

function image_workflow_record_path {
    printf "%s.creation-record\n" "$1"
}

function image_workflow_record_value {
    local record="$1"
    local key="$2"
    local line

    [[ -f "${record}" && ! -L "${record}" ]] || return 1
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        line="${line//$'\r'/}"
        if [[ "${line}" == "${key}="* ]]; then
            printf "%s\n" "${line#*=}"
            return 0
        fi
    done < "${record}"
    return 1
}

function image_workflow_write_record {
    local image="$1"
    local kind="$2"
    local platform="$3"
    local run_id="$4"
    local source_image="$5"
    local record
    local record_tmp

    [[ -f "${image}" && ! -L "${image}" ]] || return 1
    record="$(image_workflow_record_path "${image}")"
    record_tmp="${record}.tmp"
    [[ ! -e "${record_tmp}" && ! -L "${record_tmp}" ]] || return 1

    printf "%s\n" \
        "schema=1" \
        "image_name=$(basename "${image}")" \
        "image_kind=${kind}" \
        "image_platform=${platform}" \
        "image_id=${run_id}" \
        "source_image=${source_image}" > "${record_tmp}"
    mv -f -- "${record_tmp}" "${record}"
}

function image_workflow_validate_pair {
    local image="$1"
    local expected_kind="${2:-}"
    local expected_platform="${3:-}"
    local expected_id="${4:-}"
    local record
    local image_name
    local image_kind
    local image_platform
    local image_id
    local base_name
    local prefix
    local name_id

    [[ -f "${image}" && ! -L "${image}" ]] || return 1
    record="$(image_workflow_record_path "${image}")"
    base_name="$(basename "${image}")"
    image_name="$(image_workflow_record_value "${record}" image_name)" || return 1
    image_kind="$(image_workflow_record_value "${record}" image_kind)" || return 1
    image_platform="$(image_workflow_record_value "${record}" image_platform)" || return 1
    image_id="$(image_workflow_record_value "${record}" image_id)" || return 1

    [[ "${image_name}" == "${base_name}" ]] || return 1
    [[ -z "${expected_kind}" || "${image_kind}" == "${expected_kind}" ]] || return 1
    [[ -z "${expected_platform}" || "${image_platform}" == "${expected_platform}" ]] || return 1
    [[ -z "${expected_id}" || "${image_id}" == "${expected_id}" ]] || return 1

    if [[ -n "${expected_kind}" && "${expected_kind}" != "vm-disk" \
        && -n "${expected_platform}" ]]; then
        image_workflow_validate_run_id "${image_id}" || return 1
        prefix="${expected_kind}-${expected_platform}-"
        [[ "${base_name}" == "${prefix}"*.qcow2 ]] || return 1
        name_id="${base_name#"${prefix}"}"
        name_id="${name_id%.qcow2}"
        [[ "${name_id}" == "${image_id}" ]] || return 1
    fi
}

function image_workflow_assert_no_backing {
    local image="$1"
    local info
    local backing

    info="$(qemu-img info --force-share "${image}")" || return 1
    backing="$(printf "%s\n" "${info}" | sed -n 's/^backing file: //p')"
    [[ -z "${backing}" || "${backing}" == "none" ]] || return 1
}

function image_workflow_copy_qcow2 {
    local source="$1"
    local target="$2"
    local kind="$3"
    local platform="$4"
    local run_id="$5"
    local source_image="$6"
    local target_tmp="${target}.tmp"

    [[ -f "${source}" && ! -L "${source}" ]] || return 1
    [[ ! -e "${target}" && ! -L "${target}" ]] || return 1
    [[ ! -e "${target_tmp}" && ! -L "${target_tmp}" ]] || return 1

    if ! qemu-img convert -p -O qcow2 "${source}" "${target_tmp}"; then
        rm -f -- "${target_tmp}"
        return 1
    fi
    if [[ ! -s "${target_tmp}" ]]; then
        rm -f -- "${target_tmp}"
        return 1
    fi
    mv -f -- "${target_tmp}" "${target}"
    if ! image_workflow_write_record "${target}" "${kind}" "${platform}" \
        "${run_id}" "${source_image}"; then
        rm -f -- "${target}" "$(image_workflow_record_path "${target}").tmp"
        return 1
    fi
    if ! image_workflow_assert_no_backing "${target}" || \
       ! image_workflow_validate_pair "${target}" "${kind}" "${platform}" "${run_id}"; then
        rm -f -- "${target}" "$(image_workflow_record_path "${target}")"
        return 1
    fi
}

function image_workflow_select_latest_image {
    local image_dir="$1"
    local kind="$2"
    local platform="$3"
    local candidate
    local -a candidates=()

    shopt -s nullglob
    candidates=("${image_dir}/${kind}-${platform}-"*.qcow2)
    shopt -u nullglob
    if (( ${#candidates[@]} > 1 )); then
        mapfile -t candidates < <(printf "%s\n" "${candidates[@]}" | sort -r)
    fi

    for candidate in "${candidates[@]}"; do
        if image_workflow_validate_pair "${candidate}" "${kind}" "${platform}"; then
            printf "%s\n" "$(basename "${candidate}")"
            return 0
        fi
    done
    return 1
}
