#!/usr/bin/env bash
#
# Verify EPICS-env Make recipes and the build runner through the shipped VM CLI.

set -euo pipefail

declare -g SCRIPT_DIR
declare -g TOP
declare -g WORKSPACE
declare -g FAKEBIN
declare -g TEST_CASES=3

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE="$(mktemp -d /tmp/epics-env-inventory-test.XXXXXX)"
FAKEBIN="${WORKSPACE}/bin"

function cleanup {
    local rc=$?

    if [[ "${rc}" != "0" ]]; then
        printf "Retained workspace: %s\n" "${WORKSPACE}" >&2
        return "${rc}"
    fi
    rm -rf -- "${WORKSPACE}"
    return "${rc}"
}

trap cleanup EXIT

mkdir -p "${FAKEBIN}" "${WORKSPACE}/home" "${WORKSPACE}/images"

cat > "${FAKEBIN}/virsh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command_name=""
for argument in "$@"; do
    case "${argument}" in
        uri|domstate|dominfo|domiflist|domifaddr)
            command_name="${argument}"
            break
            ;;
    esac
done
case "${command_name}" in
    uri)
        printf "%s\n" "qemu:///system"
        ;;
    domstate)
        printf "%s\n" "running"
        ;;
    dominfo)
        if [[ -n "${VM_DOMAIN_ARG_LOG:-}" ]]; then
            printf '%s\n' "${@: -1}" >> "${VM_DOMAIN_ARG_LOG}"
        fi
        printf "%s\n" "State: running"
        ;;
    domiflist)
        printf '%s\n' 'Interface Type Source Model MAC'
        printf '%s\n' 'vnet0 network lab virtio 52:54:00:01:64:00'
        ;;
    domifaddr)
        ;;
    *)
        printf "unexpected virsh command: %s\n" "$*" >&2
        exit 2
        ;;
esac
EOF

cat > "${FAKEBIN}/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
remote_command="${@: -1}"
case "${remote_command}" in
    exit)
        ;;
    *"/var/lib/cloud/instance/boot-finished"*)
        cat "${CLOUD_INIT_DONE_FIXTURE}"
        ;;
    *)
        printf "unexpected ssh command: %s\n" "${remote_command}" >&2
        exit 2
        ;;
esac
EOF

cat > "${FAKEBIN}/ansible-playbook" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
declare -a runtime_inventories=()
expect_inventory_path=false
for argument in "$@"; do
    if [[ "${expect_inventory_path}" == true ]]; then
        expect_inventory_path=false
        if [[ -f "${argument}" ]] && \
           grep -Fxq '[epics_dev]' "${argument}" && \
           grep -Fq ' ansible_host=' "${argument}"; then
            runtime_inventories+=("${argument}")
        fi
    elif [[ "${argument}" == "-i" ]]; then
        expect_inventory_path=true
    fi
done
[[ "${#runtime_inventories[@]}" -eq 2 ]] || {
    printf "expected two generated EPICS-env inventories, got %s\n" \
        "${#runtime_inventories[@]}" >&2
    exit 3
}
expected_prefix="${EXPECTED_VM_PREFIX:-lab}"
grep -Fxq "${expected_prefix}-rocky8-epics-dev-main ansible_host=192.168.123.120 ansible_user=vmadmin" \
    "${runtime_inventories[0]}" "${runtime_inventories[1]}"
grep -Fxq "${expected_prefix}-debian13-epics-dev-main ansible_host=192.168.123.20 ansible_user=vmadmin" \
    "${runtime_inventories[0]}" "${runtime_inventories[1]}"
[[ "$*" == *"--limit epics_dev"* ]]
[[ "$*" == *"playbooks/species/epics_dev.yml"* ]]
printf "%s\n" "${runtime_inventories[@]}" > "${RUNTIME_INVENTORY_ARG_LOG}"
printf "%s\n" "$*" > "${ANSIBLE_ARG_LOG}"
EOF

cat > "${FAKEBIN}/recipe-shell" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -v VM_PREFIX ]]; then
    printf 'VM_PREFIX must not be exported to the recipe shell\n' >&2
    exit 4
fi
printf 'unset\n' >> "${RECIPE_ENV_LOG}"
exec /bin/sh "$@"
EOF

chmod +x "${FAKEBIN}"/*

function verify_inventory_cleanup {
    local inventory_log="$1"
    local inventory_count
    local runtime_inventory

    [[ -s "${inventory_log}" ]]
    inventory_count="$(wc -l < "${inventory_log}")"
    [[ "${inventory_count}" == "2" ]]
    while IFS= read -r runtime_inventory; do
        [[ ! -e "${runtime_inventory}" ]]
    done < "${inventory_log}"
}

env -u VM_PREFIX \
    "PATH=${FAKEBIN}:${PATH}" \
    "HOME=${WORKSPACE}/home" \
    "USER=$(id -un)" \
    "REQUIRED_GROUP=$(id -gn)" \
    "RUNTIME_INVENTORY_ARG_LOG=${WORKSPACE}/runtime-inventory-args.log" \
    "ANSIBLE_ARG_LOG=${WORKSPACE}/ansible-args.log" \
    "CLOUD_INIT_DONE_FIXTURE=${TOP}/tests/fixtures/cloud-init-status/done.txt" \
    "VM_WAIT_SSH_ATTEMPTS=1" \
    "VM_WAIT_CLOUD_INIT_ATTEMPTS=1" \
    "${TOP}/bin/run_epics_env_build.bash" \
    -a "${TOP}/../ansible-provision" \
    -d "${WORKSPACE}/images" \
    > "${WORKSPACE}/output.log"

verify_inventory_cleanup "${WORKSPACE}/runtime-inventory-args.log"

# Refusal path: a not-ready VM (cloud-init still running) must make the driver
# print the status report, name the refused OS type, and exit non-zero rather
# than abort silently at the status assignment. The fake ssh answers the
# readiness probe from the running fixture, so create_vm -s returns non-zero.
refusal_rc=0
refusal_out="$(env -u VM_PREFIX \
    "PATH=${FAKEBIN}:${PATH}" \
    "HOME=${WORKSPACE}/home" \
    "USER=$(id -un)" \
    "REQUIRED_GROUP=$(id -gn)" \
    "RUNTIME_INVENTORY_ARG_LOG=${WORKSPACE}/refusal-runtime-args.log" \
    "ANSIBLE_ARG_LOG=${WORKSPACE}/refusal-ansible-args.log" \
    "CLOUD_INIT_DONE_FIXTURE=${TOP}/tests/fixtures/cloud-init-status/running.txt" \
    "VM_WAIT_SSH_ATTEMPTS=1" \
    "VM_WAIT_CLOUD_INIT_ATTEMPTS=1" \
    "${TOP}/bin/run_epics_env_build.bash" \
    -a "${TOP}/../ansible-provision" \
    -d "${WORKSPACE}/images" 2>&1)" || refusal_rc=$?

[[ "${refusal_rc}" -ne 0 ]]
grep -q "rocky8-epics-dev" <<< "${refusal_out}"
grep -q "cloud-init : running" <<< "${refusal_out}"

printf "[ PASS ] EPICS-env build uses two generated core inventories\n"
printf "[ PASS ] EPICS-env build removes generated inventories\n"
printf "[ PASS ] EPICS-env build refuses a not-ready VM with a named status report\n"

# The shell boundary checks export suppression and then executes the actual
# recipe unchanged. Libvirt records domain identities; Ansible checks the
# inventories generated by the real driver and generator before cleanup.
function check_make_prefix {
    local target="$1"
    local prefix_override="$2"
    local expected_prefix="${2:-lab}"
    local case_path="${WORKSPACE}/${1}-${2:-default}"
    local -a expected_domains=()
    local -a make_args=(
        --no-print-directory -C "${TOP}" --eval='unexport VM_PREFIX'
        "${target}"
        "IMAGE_DIR=${WORKSPACE}/images"
        "REQUIRED_GROUP=$(id -gn)"
        "SHELL=${FAKEBIN}/recipe-shell"
    )

    case "${target}" in
        epics-env|epics-env.provision)
            expected_domains=(
                "${expected_prefix}-rocky8-epics-dev-main"
                "${expected_prefix}-debian13-epics-dev-main"
            )
            ;;
        epics-env.provision.matrix)
            expected_domains=(
                "${expected_prefix}-rocky10-epics-dev-main"
                "${expected_prefix}-ubuntu26-epics-dev-main"
            )
            ;;
    esac
    if [[ -n "${prefix_override}" ]]; then
        make_args+=("VM_PREFIX=${prefix_override}")
    fi
    env -u VM_PREFIX -u MAKEFLAGS -u MAKEOVERRIDES -u MFLAGS \
        "PATH=${FAKEBIN}:${PATH}" \
        "HOME=${WORKSPACE}/home" \
        "USER=$(id -un)" \
        "EXPECTED_VM_PREFIX=${expected_prefix}" \
        "VM_DOMAIN_ARG_LOG=${case_path}-domains.log" \
        "RECIPE_ENV_LOG=${case_path}-env.log" \
        "RUNTIME_INVENTORY_ARG_LOG=${case_path}-inventories.log" \
        "ANSIBLE_ARG_LOG=${case_path}-ansible.log" \
        "CLOUD_INIT_DONE_FIXTURE=${TOP}/tests/fixtures/cloud-init-status/done.txt" \
        "VM_WAIT_SSH_ATTEMPTS=1" \
        "VM_WAIT_CLOUD_INIT_ATTEMPTS=1" \
        make "${make_args[@]}" > "${case_path}-output.log" 2>&1

    [[ -s "${case_path}-env.log" ]]
    [[ -s "${case_path}-domains.log" ]]
    if ! diff -u \
        <(printf '%s\n' "${expected_domains[@]}" | LC_ALL=C sort) \
        <(LC_ALL=C sort -u "${case_path}-domains.log"); then
        printf '[ FAIL ] %s selects prefix %s\n' "${target}" "${expected_prefix}" >&2
        return 1
    fi
    if [[ "${target}" == "epics-env" ]]; then
        verify_inventory_cleanup "${case_path}-inventories.log"
    else
        [[ ! -e "${case_path}-ansible.log" ]]
    fi
    TEST_CASES=$((TEST_CASES + 1))
    printf '[ PASS ] %s selects prefix %s without exporting VM_PREFIX\n' \
        "${target}" "${expected_prefix}"
}

for test_prefix in "" review; do
    for make_target in epics-env.provision epics-env epics-env.provision.matrix; do
        check_make_prefix "${make_target}" "${test_prefix}"
    done
done

printf 'Summary: %d passed / %d total\n' "${TEST_CASES}" "${TEST_CASES}"
