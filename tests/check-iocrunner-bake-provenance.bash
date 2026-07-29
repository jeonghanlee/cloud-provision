#!/usr/bin/env bash
#
# Verifies the shipped validator and the public bake promotion boundary.

set -euo pipefail

declare -g SCRIPT_DIR
declare -g TOP
declare -g VALIDATOR
declare -g BAKE
declare -g WORKSPACE
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -ag FAILED_DETAILS=()

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"
VALIDATOR="${TOP}/bin/validate_iocrunner_bake.bash"
BAKE="${TOP}/bin/bake_iocrunner_image.bash"

function cleanup {
    local rc=$?
    if [[ -n "${WORKSPACE:-}" && -d "${WORKSPACE}" ]]; then
        if [[ "${rc}" != "0" ]]; then
            printf "Retained workspace: %s\n" "${WORKSPACE}" >&2
            return "${rc}"
        fi
        rm -rf "${WORKSPACE}"
    fi
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

function expect_success {
    local name="$1"
    local output
    shift
    if output="$("$@" 2>&1)"; then
        record_pass "${name}"
    else
        record_fail "${name}" "command returned nonzero: ${output}"
    fi
}

function expect_failure {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        record_fail "${name}" "command unexpectedly succeeded"
    else
        record_pass "${name}"
    fi
}

function init_checkout {
    local checkout="$1"
    local repo_url="$2"

    git init -q "${checkout}"
    git -C "${checkout}" config user.name "Bake Test"
    git -C "${checkout}" config user.email "bake@example.invalid"
    git -C "${checkout}" remote add origin "${repo_url}"
    printf "%s\n" "source" > "${checkout}/source.txt"
    git -C "${checkout}" add source.txt
    git -C "${checkout}" -c core.hooksPath=/dev/null commit -q -m "Create source fixture"
}

function write_runner {
    local runner_bin="$1"
    local identity="$2"

    cat > "${runner_bin}" <<EOF
#!/usr/bin/env bash
printf "%s\\n" "epics-ioc-runner version 1.0.0 (${identity})"
printf "%s\\n" "commit date:  2026-07-29T00:00:00Z"
EOF
    chmod +x "${runner_bin}"
}

function write_valid_manifest {
    local manifest="$1"
    local epics_commit="$2"
    local runner_commit="$3"
    local fixture_commit="$4"

    cat > "${manifest}" <<EOF
# iocrunner golden bake manifest
manifest_schema 1
bake_date 2026-07-29T00:00:00Z
os_type rocky8
cloud-provision 1111111111111111111111111111111111111111-dirty
ansible-provision 2222222222222222222222222222222222222222-dirty
epics_env_version 1.2.2
epics_base_version 7.0.10
base_image schema=1 name=base.qcow2 sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
app_con schema=1 repo=https://github.com/jeonghanlee/con commit=${fixture_commit} state=clean-untagged tag=- recorded_at=2026-07-29T00:00:00Z
app_procserv schema=1 repo=https://github.com/jeonghanlee/procServ-env commit=${fixture_commit} state=clean-untagged tag=- recorded_at=2026-07-29T00:00:00Z
app_conserver schema=1 repo=https://github.com/jeonghanlee/conserver-env commit=${fixture_commit} state=clean-untagged tag=- recorded_at=2026-07-29T00:00:00Z
app_epics schema=1 repo=https://github.com/jeonghanlee/EPICS-env-distribution commit=${epics_commit} state=clean-untagged tag=- recorded_at=2026-07-29T00:00:00Z
app_ioc_runner schema=1 repo=https://github.com/jeonghanlee/epics-ioc-runner commit=${runner_commit} state=clean-untagged tag=- recorded_at=2026-07-29T00:00:00Z
pip3 fixture-package==1.0
EOF
    chmod 0644 "${manifest}"
}

function run_validator {
    local manifest="$1"
    local epics_checkout="$2"
    local runner_checkout="$3"
    local runner_bin="$4"

    unshare -Ur env GIT_DIR=/nonexistent BASH_ENV=/nonexistent \
        "${VALIDATOR}" "${manifest}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"
}

function run_validator_tests {
    local test_dir="${WORKSPACE}/validator"
    local epics_checkout="${test_dir}/epics"
    local runner_checkout="${test_dir}/runner"
    local runner_bin="${test_dir}/ioc-runner"
    local manifest="${test_dir}/manifest"
    local mutation="${test_dir}/mutation"
    local epics_commit runner_commit fixture_commit

    mkdir -p "${test_dir}"
    init_checkout "${epics_checkout}" "https://github.com/jeonghanlee/EPICS-env-distribution"
    init_checkout "${runner_checkout}" "https://github.com/jeonghanlee/epics-ioc-runner"
    epics_commit="$(git -C "${epics_checkout}" rev-parse HEAD)"
    runner_commit="$(git -C "${runner_checkout}" rev-parse HEAD)"
    fixture_commit="${runner_commit}"
    write_runner "${runner_bin}" "${runner_commit:0:7}"
    write_valid_manifest "${manifest}" "${epics_commit}" "${runner_commit}" "${fixture_commit}"

    expect_success "validator accepts complete real Git identities" \
        run_validator "${manifest}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"
    expect_failure "validator rejects unsafe plain Bash" \
        unshare -Ur /bin/bash "${VALIDATOR}" "${manifest}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"

    grep -v '^app_con ' "${manifest}" > "${mutation}"
    expect_failure "validator rejects a missing application" \
        run_validator "${mutation}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"

    cp "${manifest}" "${mutation}"
    grep '^app_con ' "${manifest}" >> "${mutation}"
    expect_failure "validator rejects a duplicate application" \
        run_validator "${mutation}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"

    cp "${manifest}" "${mutation}"
    printf "%s\n" "app_unknown schema=1 repo=x commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa state=dirty tag=- recorded_at=2026-07-29T00:00:00Z" \
        >> "${mutation}"
    expect_failure "validator rejects an unknown record" \
        run_validator "${mutation}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"

    sed 's/app_con schema=1/app_con schema=2/' "${manifest}" > "${mutation}"
    expect_failure "validator rejects malformed schema" \
        run_validator "${mutation}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"

    sed "s/${epics_commit}/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/" "${manifest}" > "${mutation}"
    expect_failure "validator rejects retained commit mismatch" \
        run_validator "${mutation}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"

    sed '/^app_ioc_runner /s/state=clean-untagged/state=dirty/' "${manifest}" > "${mutation}"
    expect_failure "validator rejects dirty state mismatch" \
        run_validator "${mutation}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"

    write_runner "${runner_bin}" "deadbee"
    expect_failure "validator rejects installed hash-prefix mismatch" \
        run_validator "${manifest}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"
}

function write_fake_host_commands {
    local fakebin="$1"

    cat > "${fakebin}/virsh" <<'EOF'
#!/usr/bin/env bash
set -e
command_name=""
for argument in "$@"; do
    case "${argument}" in
        list|dominfo|domblklist|domstate|net-update|shutdown)
            command_name="${argument}"
            break
            ;;
    esac
done
case "${command_name}" in
    list)
        ;;
    dominfo)
        [[ -f "${DOMAIN_STATE_FILE}" ]]
        ;;
    domblklist)
        printf "%s\n" " Type   Device   Target   Source"
        ;;
    domstate)
        if [[ -f "${DOMAIN_STATE_FILE}" ]]; then
            cat "${DOMAIN_STATE_FILE}"
        else
            exit 1
        fi
        ;;
    net-update)
        ;;
    shutdown)
        printf "%s\n" "shut off" > "${DOMAIN_STATE_FILE}"
        ;;
    *)
        printf "unexpected virsh command: %s\n" "$*" >&2
        exit 2
        ;;
esac
EOF

    cat > "${fakebin}/qemu-img" <<'EOF'
#!/usr/bin/env bash
set -e
case "$1" in
    info)
        disk="${@: -1}"
        if [[ "$*" != *"--output=json"* ]]; then
            printf "%s\n" "file format: qcow2"
            exit 0
        fi
        if [[ "${disk}" == *"/testbed-rocky8-server.qcow2" ]]; then
            printf '{"format":"qcow2","full-backing-filename":"%s"}\n' "${BASE_IMAGE_PATH}"
        else
            printf "%s\n" '{"format":"qcow2"}'
        fi
        ;;
    create)
        output="${@: -2:1}"
        printf "%s\n" "layered disk" > "${output}"
        ;;
    convert)
        printf "%s\n" "convert" >> "${CALL_LOG}"
        if [[ "${PROMOTION_MODE}" == "conversion-fail" ]]; then
            exit 1
        fi
        output="${@: -1}"
        printf "%s\n" "converted image" > "${output}"
        ;;
    *)
        printf "unexpected qemu-img command: %s\n" "$*" >&2
        exit 2
        ;;
esac
EOF

    cat > "${fakebin}/virt-install" <<'EOF'
#!/usr/bin/env bash
set -e
printf "%s\n" "running" > "${DOMAIN_STATE_FILE}"
EOF

    cat > "${fakebin}/genisoimage" <<'EOF'
#!/usr/bin/env bash
set -e
output=""
while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-output" ]]; then
        output="$2"
        break
    fi
    shift
done
printf "%s\n" "seed" > "${output}"
EOF

    cat > "${fakebin}/uuidgen" <<'EOF'
#!/usr/bin/env bash
printf "%s\n" "11111111-2222-3333-4444-555555555555"
EOF

    cat > "${fakebin}/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    cat > "${fakebin}/ssh-keyscan" <<'EOF'
#!/usr/bin/env bash
printf "%s\n" "host ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixture"
EOF

    cat > "${fakebin}/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

    cat > "${fakebin}/ansible-playbook" <<'EOF'
#!/usr/bin/env bash
set -e
if [[ "$*" != *"site.yml"* ]] || grep -q '^app_con ' "${REMOTE_MANIFEST}" 2>/dev/null; then
    exit 0
fi
timestamp="2026-07-29T00:00:00Z"
printf "app_con schema=1 repo=https://github.com/jeonghanlee/con commit=%s state=clean-untagged tag=- recorded_at=%s\n" \
    "${FIXTURE_COMMIT}" "${timestamp}" >> "${REMOTE_MANIFEST}"
printf "app_procserv schema=1 repo=https://github.com/jeonghanlee/procServ-env commit=%s state=clean-untagged tag=- recorded_at=%s\n" \
    "${FIXTURE_COMMIT}" "${timestamp}" >> "${REMOTE_MANIFEST}"
if [[ "${PROMOTION_MODE}" != "validator-reject" ]]; then
    printf "app_conserver schema=1 repo=https://github.com/jeonghanlee/conserver-env commit=%s state=clean-untagged tag=- recorded_at=%s\n" \
        "${FIXTURE_COMMIT}" "${timestamp}" >> "${REMOTE_MANIFEST}"
fi
printf "app_epics schema=1 repo=https://github.com/jeonghanlee/EPICS-env-distribution commit=%s state=clean-untagged tag=- recorded_at=%s\n" \
    "${EPICS_COMMIT}" "${timestamp}" >> "${REMOTE_MANIFEST}"
printf "app_ioc_runner schema=1 repo=https://github.com/jeonghanlee/epics-ioc-runner commit=%s state=clean-untagged tag=- recorded_at=%s\n" \
    "${RUNNER_COMMIT}" "${timestamp}" >> "${REMOTE_MANIFEST}"
EOF

    cat > "${fakebin}/ssh" <<'EOF'
#!/usr/bin/env bash
set -e
remote_command="${@: -1}"
case "${remote_command}" in
    exit)
        exit 0
        ;;
    "cloud-init status")
        printf "%s\n" "status: done"
        exit 0
        ;;
    "sudo cat /etc/iocrunner-bake.manifest")
        cat "${REMOTE_MANIFEST}"
        exit 0
        ;;
esac

if [[ "${remote_command}" == sudo\ /bin/bash\ -p\ -s* ]]; then
    input_file="${CASE_DIR}/ssh-input"
    cat > "${input_file}"
    if grep -q 'Validates a complete IOC runner bake manifest' "${input_file}"; then
        unshare -Ur env GIT_DIR=/nonexistent "${REAL_VALIDATOR}" \
            "${REMOTE_MANIFEST}" "${EPICS_CHECKOUT}" "${RUNNER_CHECKOUT}" "${RUNNER_BIN}"
        exit
    fi
    if grep -q '# iocrunner golden bake manifest' "${input_file}"; then
        read -r -a fields <<< "${remote_command}"
        cat > "${REMOTE_MANIFEST}" <<MANIFEST
# iocrunner golden bake manifest
manifest_schema 1
bake_date ${fields[5]}
os_type ${fields[6]}
cloud-provision ${fields[7]}
ansible-provision ${fields[8]}
epics_env_version ${fields[9]}
epics_base_version ${fields[10]}
base_image schema=1 name=${fields[11]} sha256=${fields[12]}
MANIFEST
        chmod 0644 "${REMOTE_MANIFEST}"
        exit 0
    fi
    if grep -q 'pip3 freeze' "${input_file}"; then
        printf "%s\n" "pip3 fixture-package==1.0" >> "${REMOTE_MANIFEST}"
        exit 0
    fi
    exit 0
fi

printf "unexpected ssh command: %s\n" "${remote_command}" >&2
exit 2
EOF

    chmod +x "${fakebin}"/*
}

function run_promotion_case {
    local mode="$1"
    local case_dir="${WORKSPACE}/promotion-${mode}"
    local fakebin="${case_dir}/bin"
    local image_dir="${case_dir}/images"
    local home_dir="${case_dir}/home"
    local epics_checkout="${case_dir}/epics"
    local runner_checkout="${case_dir}/runner"
    local runner_bin="${case_dir}/ioc-runner"
    local remote_manifest="${case_dir}/remote.manifest"
    local output_image="${image_dir}/iocrunner-rocky8.qcow2"
    local sidecar="${output_image}.manifest"
    local before_image before_sidecar after_image after_sidecar
    local epics_commit runner_commit fixture_commit
    local rc=0

    mkdir -p "${fakebin}" "${image_dir}" "${home_dir}/.ssh"
    printf "%s\n" "ssh-ed25519 AAAAC3NzaFixture test" > "${home_dir}/.ssh/id_ed25519.pub"
    : > "${home_dir}/.ssh/known_hosts"
    printf "%s\n" "base image" > "${image_dir}/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2"
    printf "%s\n" "prior image" > "${output_image}"
    printf "%s\n" "prior sidecar" > "${sidecar}"
    before_image="$(sha256sum "${output_image}")"
    before_image="${before_image%% *}"
    before_sidecar="$(sha256sum "${sidecar}")"
    before_sidecar="${before_sidecar%% *}"

    init_checkout "${epics_checkout}" "https://github.com/jeonghanlee/EPICS-env-distribution"
    init_checkout "${runner_checkout}" "https://github.com/jeonghanlee/epics-ioc-runner"
    epics_commit="$(git -C "${epics_checkout}" rev-parse HEAD)"
    runner_commit="$(git -C "${runner_checkout}" rev-parse HEAD)"
    fixture_commit="${runner_commit}"
    write_runner "${runner_bin}" "${runner_commit:0:7}"
    write_fake_host_commands "${fakebin}"

    CASE_DIR="${case_dir}" \
    DOMAIN_STATE_FILE="${case_dir}/domain.state" \
    BASE_IMAGE_PATH="${image_dir}/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2" \
    CALL_LOG="${case_dir}/calls.log" \
    PROMOTION_MODE="${mode}" \
    REMOTE_MANIFEST="${remote_manifest}" \
    FIXTURE_COMMIT="${fixture_commit}" \
    EPICS_COMMIT="${epics_commit}" \
    RUNNER_COMMIT="${runner_commit}" \
    EPICS_CHECKOUT="${epics_checkout}" \
    RUNNER_CHECKOUT="${runner_checkout}" \
    RUNNER_BIN="${runner_bin}" \
    REAL_VALIDATOR="${VALIDATOR}" \
    PATH="${fakebin}:${PATH}" \
    HOME="${home_dir}" \
    USER="$(id -un)" \
    REQUIRED_GROUP="$(id -gn)" \
    "${BAKE}" -o rocky8 -d "${image_dir}" -a "${TOP}/../ansible-provision" -k \
        > "${case_dir}/output.txt" 2>&1 || rc=$?

    if [[ "${rc}" != "0" ]]; then
        record_pass "${mode} public bake fails safely"
    else
        record_fail "${mode} public bake fails safely" "bake unexpectedly succeeded"
    fi

    after_image="$(sha256sum "${output_image}")"
    after_image="${after_image%% *}"
    after_sidecar="$(sha256sum "${sidecar}")"
    after_sidecar="${after_sidecar%% *}"
    if [[ "${before_image}" == "${after_image}" && "${before_sidecar}" == "${after_sidecar}" ]]; then
        record_pass "${mode} preserves the published pair"
    else
        record_fail "${mode} preserves the published pair" "published image or sidecar changed"
    fi

    if [[ "${mode}" == "validator-reject" ]]; then
        if [[ ! -e "${case_dir}/calls.log" ]] || ! grep -q '^convert$' "${case_dir}/calls.log"; then
            record_pass "validator rejection prevents conversion"
        else
            record_fail "validator rejection prevents conversion" "conversion was called"
        fi
    else
        if grep -q '^convert$' "${case_dir}/calls.log"; then
            record_pass "conversion failure reaches the real conversion boundary"
        else
            record_fail "conversion failure reaches the real conversion boundary" "conversion was not called"
        fi
    fi

    if [[ ! -e "${output_image}.tmp" && ! -e "${sidecar}.tmp" ]]; then
        record_pass "${mode} removes only current temporary outputs"
    else
        record_fail "${mode} removes only current temporary outputs" "temporary output remained"
    fi
}

function print_summary {
    printf "Summary: %s passed / %s total\n" "${TEST_PASSED}" "${TEST_TOTAL}"
    if [[ "${TEST_FAILED}" -gt "0" ]]; then
        printf "Failures:\n" >&2
        printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
        return 1
    fi
}

WORKSPACE="$(mktemp -d /tmp/iocrunner-bake-provenance-test.XXXXXX)"

case "${1:-all}" in
    validator)
        run_validator_tests
        ;;
    promotion)
        run_promotion_case validator-reject
        run_promotion_case conversion-fail
        ;;
    all)
        run_validator_tests
        run_promotion_case validator-reject
        run_promotion_case conversion-fail
        ;;
    *)
        printf "Usage: %s [validator|promotion|all]\n" "$(basename "$0")" >&2
        exit 2
        ;;
esac

print_summary
