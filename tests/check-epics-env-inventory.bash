#!/usr/bin/env bash
#
# Verify the EPICS-env build runner through create_vm status and inventory generation.

set -euo pipefail

declare -g SCRIPT_DIR
declare -g TOP
declare -g WORKSPACE
declare -g FAKEBIN

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
        uri|domstate|dominfo|domifaddr)
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
        printf "%s\n" "State: running"
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
    "cloud-init status")
        printf "%s\n" "status: done"
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
           grep -Fxq '[epics_env_core]' "${argument}" && \
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
grep -Fq 'testbed-epics-env-rocky8-server ansible_host=192.168.122.120 ansible_user=vmadmin' \
    "${runtime_inventories[0]}" "${runtime_inventories[1]}"
grep -Fq 'testbed-epics-env-debian13-server ansible_host=192.168.122.20 ansible_user=vmadmin' \
    "${runtime_inventories[0]}" "${runtime_inventories[1]}"
[[ "$*" == *"--limit epics_env_core"* ]]
[[ "$*" == *"playbooks/species/epics_dev.yml"* ]]
printf "%s\n" "${runtime_inventories[@]}" > "${RUNTIME_INVENTORY_ARG_LOG}"
printf "%s\n" "$*" > "${ANSIBLE_ARG_LOG}"
EOF

chmod +x "${FAKEBIN}"/*

env \
    "PATH=${FAKEBIN}:${PATH}" \
    "HOME=${WORKSPACE}/home" \
    "USER=$(id -un)" \
    "REQUIRED_GROUP=$(id -gn)" \
    "RUNTIME_INVENTORY_ARG_LOG=${WORKSPACE}/runtime-inventory-args.log" \
    "ANSIBLE_ARG_LOG=${WORKSPACE}/ansible-args.log" \
    "VM_WAIT_SSH_ATTEMPTS=1" \
    "VM_WAIT_CLOUD_INIT_ATTEMPTS=1" \
    "${TOP}/bin/run_epics_env_build.bash" \
    -a "${TOP}/../ansible-provision" \
    -d "${WORKSPACE}/images" \
    > "${WORKSPACE}/output.log"

runtime_inventory_count="$(wc -l < "${WORKSPACE}/runtime-inventory-args.log")"
[[ "${runtime_inventory_count}" == "2" ]]
while IFS= read -r runtime_inventory; do
    [[ ! -e "${runtime_inventory}" ]]
done < "${WORKSPACE}/runtime-inventory-args.log"

printf "[ PASS ] EPICS-env build uses two generated core inventories\n"
printf "[ PASS ] EPICS-env build removes generated inventories\n"
printf "Summary: 2 passed / 2 total\n"
