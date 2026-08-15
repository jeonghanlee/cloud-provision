#!/usr/bin/env bash
#
# Verifies the shipped EtherCAT bake through its public entry point.

set -euo pipefail

declare -g SCRIPT_DIR
declare -g TOP
declare -g WORKSPACE
declare -g FAKEBIN
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -ag FAILED_DETAILS=()

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE="$(mktemp -d /tmp/ethercat-bake-workflow-test.XXXXXX)"
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

function record_pass {
    local name="$1"
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_PASSED=$((TEST_PASSED + 1))
    printf "[ PASS ] %s\n" "${name}"
}

function record_fail {
    local name="$1"
    local detail="$2"
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_FAILED=$((TEST_FAILED + 1))
    FAILED_DETAILS+=("${name}: ${detail}")
    printf "[ FAIL ] %s\n" "${name}" >&2
    printf "  %s\n" "${detail}" >&2
}

function write_fake_commands {
    cat > "${FAKEBIN}/virsh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command_name=""
for argument in "$@"; do
    case "${argument}" in
        domstate|dominfo|domifaddr|net-update|net-dumpxml|shutdown|destroy|undefine|uri)
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
        if [[ -f "${FAKE_STATE_FILE}" ]]; then
            cat "${FAKE_STATE_FILE}"
        else
            exit 1
        fi
        ;;
    dominfo)
        [[ -f "${FAKE_STATE_FILE}" ]]
        ;;
    domifaddr)
        printf "%s\n" " vnet0 52:54:00:00:a0:26 ipv4 192.168.122.198/24"
        ;;
    net-dumpxml)
        printf "%s\n" "<network><ip><dhcp></dhcp></ip></network>"
        ;;
    net-update)
        ;;
    shutdown|destroy)
        printf "%s\n" "shut off" > "${FAKE_STATE_FILE}"
        ;;
    undefine)
        rm -f -- "${FAKE_STATE_FILE}"
        ;;
    *)
        printf "unexpected virsh command: %s\n" "$*" >&2
        exit 2
        ;;
esac
EOF

    cat > "${FAKEBIN}/qemu-img" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
    info)
        printf "%s\n" "file format: qcow2"
        ;;
    convert)
        output="${@: -1}"
        printf "convert %s\n" "${output}" >> "${FAKE_CALL_LOG}"
        printf "%s\n" "qcow2 fixture" > "${output}"
        ;;
    resize)
        output="$2"
        [[ -f "${output}" && "$3" == "20G" ]] || exit 1
        printf "resize %s %s\n" "${output}" "$3" >> "${FAKE_CALL_LOG}"
        ;;
    *)
        printf "unexpected qemu-img command: %s\n" "$*" >&2
        exit 2
        ;;
esac
EOF

    cat > "${FAKEBIN}/virt-install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf "%s\n" "running" > "${FAKE_STATE_FILE}"
EOF

    cat > "${FAKEBIN}/ansible-playbook" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
runtime_inventory=""
expect_inventory_path=false
for argument in "$@"; do
    if [[ "${expect_inventory_path}" == true ]]; then
        expect_inventory_path=false
        if [[ -f "${argument}" ]] && \
           grep -Fxq '[ethercat_build]' "${argument}" && \
           grep -Fq ' ansible_host=' "${argument}"; then
            runtime_inventory="${argument}"
        fi
    elif [[ "${argument}" == "-i" ]]; then
        expect_inventory_path=true
    fi
done
[[ -n "${runtime_inventory}" ]] || {
    printf "%s\n" "generated EtherCAT inventory was not passed" >&2
    exit 3
}
printf "%s\n" "${runtime_inventory}" >> "${RUNTIME_INVENTORY_ARG_LOG}"
if [[ ! -s "${RUNTIME_INVENTORY_SNAPSHOT}" ]]; then
    cp "${runtime_inventory}" "${RUNTIME_INVENTORY_SNAPSHOT}"
fi
printf "%s\n" "$*" >> "${FAKE_ANSIBLE_LOG}"
EOF

    cat > "${FAKEBIN}/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

    cat > "${FAKEBIN}/ssh-keyscan" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf "%s\n" "host ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixture"
EOF

    cat > "${FAKEBIN}/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

    cat > "${FAKEBIN}/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf "%s\n" "$*" >> "${FAKE_SSH_LOG}"
remote_command="${@: -1}"
case "${remote_command}" in
    exit)
        ;;
    "cloud-init status")
        printf "%s\n" "status: done"
        ;;
    "sudo tee /etc/ethercat-bake.manifest >/dev/null")
        cat > "${FAKE_REMOTE_MANIFEST}"
        ;;
    "sudo cat /etc/ethercat-bake.manifest")
        cat "${FAKE_REMOTE_MANIFEST}"
        ;;
    "sudo sh -s")
        cat >/dev/null
        ;;
    *)
        printf "unexpected ssh command: %s\n" "${remote_command}" >&2
        exit 2
        ;;
esac
EOF

    chmod +x "${FAKEBIN}"/*
}

function write_manifest {
    local manifest="$1"

    printf "%s\n" \
        "# ethercat golden bake manifest" \
        "bake_date 2026-08-12T00:00:00Z" \
        "cloud-provision fixture" \
        "ansible-provision fixture" > "${manifest}"
}

function run_bake {
    local output_file="$1"
    local image_dir="$2"
    local state_file="$3"
    local call_log="$4"
    local ansible_log="$5"
    local ssh_log="$6"
    local remote_manifest="$7"
    local home_dir="$8"

    env \
        "PATH=${FAKEBIN}:${PATH}" \
        "HOME=${home_dir}" \
        "USER=$(id -un)" \
        "REQUIRED_GROUP=$(id -gn)" \
        "FAKE_STATE_FILE=${state_file}" \
        "FAKE_CALL_LOG=${call_log}" \
        "FAKE_ANSIBLE_LOG=${ansible_log}" \
        "RUNTIME_INVENTORY_ARG_LOG=${WORKSPACE}/runtime-inventory-args.log" \
        "RUNTIME_INVENTORY_SNAPSHOT=${WORKSPACE}/runtime-inventory.ini" \
        "FAKE_SSH_LOG=${ssh_log}" \
        "FAKE_REMOTE_MANIFEST=${remote_manifest}" \
        "${TOP}/bin/bake_ethercat_image.bash" \
        -o debian13 -d "${image_dir}" -a "${TOP}/../ansible-provision" \
        > "${output_file}" 2>&1
}

function check_pair {
    local image="$1"
    local record="${image}.creation-record"
    local image_name
    local image_id
    local image_stem

    [[ -f "${image}" && ! -L "${image}" ]] || return 1
    [[ -f "${record}" && ! -L "${record}" ]] || return 1
    image_name="$(sed -n 's/^image_name=//p' "${record}")"
    image_id="$(sed -n 's/^image_id=//p' "${record}")"
    image_stem="${image##*/}"
    image_stem="${image_stem#ethercat-debian13-}"
    image_stem="${image_stem%.qcow2}"
    [[ "${image##*/}" =~ ^ethercat-debian13-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}\.qcow2$ ]] || return 1
    [[ "${image_name}" == "${image##*/}" ]] || return 1
    [[ "${image_id}" == "${image_stem}" ]] || return 1
}

mkdir -p "${FAKEBIN}"
write_fake_commands

image_dir="${WORKSPACE}/images"
home_dir="${WORKSPACE}/home"
state_file="${WORKSPACE}/domain.state"
call_log="${WORKSPACE}/qemu.log"
ansible_log="${WORKSPACE}/ansible.log"
ssh_log="${WORKSPACE}/ssh.log"
remote_manifest="${WORKSPACE}/ethercat.manifest"
mkdir -p "${image_dir}" "${home_dir}/.ssh"
printf "%s\n" "ssh-ed25519 AAAAC3NzaFixture test" > "${home_dir}/.ssh/id_ed25519.pub"
printf "%s\n" "pinned base" > "${image_dir}/debian-13-genericcloud-amd64-20260601-2496.qcow2"
write_manifest "${remote_manifest}"

for run_number in 1 2; do
    output_file="${WORKSPACE}/run-${run_number}.log"
    run_bake "${output_file}" "${image_dir}" "${state_file}" "${call_log}" \
        "${ansible_log}" "${ssh_log}" "${remote_manifest}" "${home_dir}"
    printf "[ PASS ] EtherCAT bake run %s reaches completion\n" "${run_number}"
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_PASSED=$((TEST_PASSED + 1))
done

shopt -s nullglob
images=("${image_dir}"/ethercat-debian13-*.qcow2)
shopt -u nullglob
if [[ "${#images[@]}" == "2" ]]; then
    record_pass "EtherCAT bake creates a unique image per run"
else
    record_fail "EtherCAT bake creates a unique image per run" \
        "found ${#images[@]} images"
fi

for image in "${images[@]}"; do
    if check_pair "${image}"; then
        record_pass "EtherCAT image has a matching creation record"
    else
        record_fail "EtherCAT image has a matching creation record" "invalid pair: ${image}"
    fi
done

if grep -q 'convert .*ethercat-debian13-' "${call_log}"; then
    record_pass "EtherCAT bake publishes through qemu-img convert"
else
    record_fail "EtherCAT bake publishes through qemu-img convert" "final copy was not recorded"
fi

if grep -q '05_ethercat_base.yml' "${ansible_log}"; then
    record_pass "EtherCAT bake runs the base playbook"
else
    record_fail "EtherCAT bake runs the base playbook" "playbook invocation was not recorded"
fi

runtime_inventory_count="$(wc -l < "${WORKSPACE}/runtime-inventory-args.log")"
if [[ "${runtime_inventory_count}" == "2" ]] && \
   grep -Eq '^testbed-debian13-rtbase-build-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12} ansible_host=[0-9.]+ ansible_user=vmadmin$' \
       "${WORKSPACE}/runtime-inventory.ini"; then
    record_pass "EtherCAT bake generates one build-host inventory per run"
else
    record_fail "EtherCAT bake generates one build-host inventory per run" \
        "generated inventory count or host entry was incorrect"
fi

runtime_inventory_remains=false
while IFS= read -r runtime_inventory; do
    if [[ -e "${runtime_inventory}" ]]; then
        runtime_inventory_remains=true
    fi
done < "${WORKSPACE}/runtime-inventory-args.log"
if [[ "${runtime_inventory_remains}" == false ]]; then
    record_pass "EtherCAT bake removes generated inventories"
else
    record_fail "EtherCAT bake removes generated inventories" \
        "a generated inventory remains after the bake"
fi

if awk '!/-o ControlMaster=no/ || !/-o ControlPath=none/ {bad++} END {exit bad + 0}' \
    "${ssh_log}"; then
    record_pass "EtherCAT bake refuses SSH multiplexing"
else
    record_fail "EtherCAT bake refuses SSH multiplexing" "an SSH call omitted the options"
fi

printf "Summary: %s passed / %s total\n" "${TEST_PASSED}" "${TEST_TOTAL}"
if [[ "${TEST_FAILED}" -gt 0 ]]; then
    printf "Failures:\n" >&2
    printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
    exit 1
fi
