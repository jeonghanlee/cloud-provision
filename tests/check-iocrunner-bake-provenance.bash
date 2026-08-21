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

function expect_equal {
    local name="$1"
    local want="$2"
    local got="$3"

    if [[ "${got}" == "${want}" ]]; then
        record_pass "${name}"
    else
        record_fail "${name}" "expected ${want}, got ${got}"
    fi
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

# Pins that every ssh this repository makes to a testbed VM refuses connection
# multiplexing. A bake reaches the VM through its own call sites and through
# create_vm.bash's readiness probe, so one recorded log covers both scripts.
#
# The assertion is on the arguments, deliberately. With the options removed the
# bake still succeeds and every other case in this file stays green, while on a
# real host a master left over from a previous run at the same address accepts
# the connection, fails mid-request, and hands the caller back a non-blocking
# stdin that the next ansible-playbook refuses to start on.
function assert_ssh_multiplexing_off {
    local label="$1"
    local arg_log="$2"
    local total=0
    local offenders=0

    if [[ ! -s "${arg_log}" ]]; then
        record_fail "${label} records ssh invocations" \
            "no ssh invocation reached ${arg_log}"
        return 0
    fi
    total="$(wc -l < "${arg_log}")"
    offenders="$(awk \
        '!/-o ControlMaster=no/ || !/-o ControlPath=none/ {count++} END {print count + 0}' \
        "${arg_log}")"
    printf "  ssh invocations recorded: %s (missing options: %s)\n" \
        "${total}" "${offenders}"
    expect_equal "${label} every ssh refuses multiplexing" "0" "${offenders}"
}

function assert_runtime_inventory {
    local label="$1"
    local path_log="$2"
    local snapshot="$3"
    local os_type="$4"
    local invocation_count=0
    local path_count=0
    local runtime_path=""
    local runtime_host=""

    if [[ -s "${path_log}" ]]; then
        invocation_count="$(wc -l < "${path_log}")"
        path_count="$(sort -u "${path_log}" | wc -l)"
        runtime_path="$(head -n 1 "${path_log}")"
    fi
    if [[ "${invocation_count}" == "3" && "${path_count}" == "1" ]]; then
        record_pass "${label} passes one runtime inventory to every play"
    else
        record_fail "${label} passes one runtime inventory to every play" \
            "invocations=${invocation_count}, paths=${path_count}"
    fi

    runtime_host="$(awk -v prefix="testbed-${os_type}-build-" \
        'index($1, prefix) == 1 && $2 ~ /^ansible_host=192[.]168[.]122[.][0-9]+$/ && \
         $3 == "ansible_user=vmadmin" {print $1; exit}' \
        "${snapshot}" 2>/dev/null || true)"
    if [[ -n "${runtime_host}" ]] && \
       grep -Fxq "[${os_type}]" "${snapshot}" && \
       grep -Fxq '[nfs_sim_nodes]' "${snapshot}" && \
       grep -Fxq "${runtime_host}" "${snapshot}"; then
        record_pass "${label} assigns the run-specific host to required groups"
    else
        record_fail "${label} assigns the run-specific host to required groups" \
            "runtime inventory did not contain the expected host and groups"
    fi

    if [[ -n "${runtime_path}" && ! -e "${runtime_path}" ]]; then
        record_pass "${label} removes the runtime inventory"
    else
        record_fail "${label} removes the runtime inventory" \
            "runtime inventory remains or its path was not recorded"
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

function prepare_proxy_guest_root {
    local root="$1"
    local os_type="$2"
    local mode="$3"
    local os_family apply_contract script_hash baseline_root config_path mutation_path

    case "${os_type}" in
        debian13) os_family=debian ;;
        rocky8) os_family=rocky ;;
        *) printf 'unsupported proxy guest OS: %s\n' "${os_type}" >&2; return 1 ;;
    esac
    apply_contract="${PROXY_APPLY_CONTRACT:-${TOP}/bin/proxy_contract.bash}"
    mkdir -p \
        "${root}/etc/profile.d" \
        "${root}/etc/apt/apt.conf.d" \
        "${root}/etc/dnf" \
        "${root}/etc/sudoers.d" \
        "${root}/etc/ssh/sshd_config.d" \
        "${root}/home/vmadmin/.ssh" \
        "${root}/run/cloud-provision" \
        "${root}/usr/bin" \
        "${root}/usr/sbin" \
        "${root}/var/lib/cloud/instances/fixture" \
        "${root}/var/lib/cloud/seed/nocloud" \
        "${root}/var/log"
    chmod 0755 \
        "${root}/etc" \
        "${root}/etc/profile.d" \
        "${root}/etc/apt/apt.conf.d" \
        "${root}/etc/dnf" \
        "${root}/etc/sudoers.d" \
        "${root}/etc/ssh" \
        "${root}/etc/ssh/sshd_config.d" \
        "${root}/run" \
        "${root}/run/cloud-provision"
    chmod 0700 "${root}/home/vmadmin/.ssh"
    printf 'root:x:0:0:root:/root:/bin/bash\n' > "${root}/etc/passwd"
    printf 'vmadmin:x:%s:%s::/home/vmadmin:/bin/bash\n' \
        "$(id -u)" "$(id -g)" >> "${root}/etc/passwd"
    printf 'ID=%s\n' "${os_family}" > "${root}/etc/os-release"
    printf 'LANG=C\n' > "${root}/etc/environment"
    chmod 0640 "${root}/etc/environment"
    printf '[user]\n    name = Fixture\n' > "${root}/etc/gitconfig"
    chmod 0600 "${root}/etc/gitconfig"
    if [[ "${os_family}" == rocky ]]; then
        printf '[main]\nkeep_dnf=true\n' > "${root}/etc/dnf/dnf.conf"
        chmod 0640 "${root}/etc/dnf/dnf.conf"
        printf 'Port 22\nMatch User nobody\n    X11Forwarding no\n' \
            > "${root}/etc/ssh/sshd_config"
    else
        printf 'Include /etc/ssh/sshd_config.d/*.conf\nPort 22\n' \
            > "${root}/etc/ssh/sshd_config"
    fi
    chmod 0644 "${root}/etc/ssh/sshd_config"

    baseline_root="${root}.before"
    mkdir -p "${baseline_root}/etc/dnf" "${baseline_root}/etc/ssh"
    cp -p -- "${root}/etc/environment" "${baseline_root}/etc/environment"
    cp -p -- "${root}/etc/gitconfig" "${baseline_root}/etc/gitconfig"
    if [[ "${os_family}" == rocky ]]; then
        cp -p -- "${root}/etc/dnf/dnf.conf" "${baseline_root}/etc/dnf/dnf.conf"
        cp -p -- "${root}/etc/ssh/sshd_config" \
            "${baseline_root}/etc/ssh/sshd_config"
    fi

    cp -- "${apply_contract}" "${root}/run/cloud-provision/proxy_contract.bash"
    chmod 0700 "${root}/run/cloud-provision/proxy_contract.bash"
    script_hash="$(sha256sum "${apply_contract}")"
    script_hash="${script_hash%% *}"
    printf 'schema=1\nproxy_url=http://fixture.invalid/\nscript_sha256=%s\n' \
        "${script_hash}" > "${root}/run/cloud-provision/proxy-contract.input"
    chmod 0600 "${root}/run/cloud-provision/proxy-contract.input"

    cat > "${root}/usr/sbin/visudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == -cf && -f "$2" ]]
grep -Fq 'Defaults env_keep +=' "$2"
EOF

    cat > "${root}/usr/sbin/sshd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
guest_root="${0%/usr/sbin/sshd}"
config=""
previous=""
for argument in "$@"; do
    if [[ "${previous}" == -f ]]; then
        config="${argument}"
    fi
    previous="${argument}"
done
[[ -n "${config}" && -f "${config}" ]]
if grep -Fq 'PermitUserEnvironment yes' "${config}" ||
   grep -Fq 'PermitUserEnvironment yes' "${guest_root}/etc/ssh/sshd_config.d/95cloud-provision-proxy.conf"; then
    printf '%s\n' 'permituserenvironment yes'
else
    printf '%s\n' 'permituserenvironment no'
fi
EOF

    cat > "${root}/usr/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == reload ]]
case "$2" in
    ssh|sshd) ;;
    *) exit 2 ;;
esac
EOF

    cat > "${root}/usr/bin/cloud-init" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root="${0%/usr/bin/cloud-init}"
if [[ "$*" == "clean --help" ]]; then
    printf '%s\n' 'usage: cloud-init clean [--logs] [--seed]'
    exit 0
fi
[[ "${1:-}" == clean ]]
rm -f -- "${root}/var/lib/cloud/instance"
rm -rf -- "${root}/var/lib/cloud/instances"/*
for argument in "$@"; do
    case "${argument}" in
        --logs)
            rm -f -- "${root}/var/log/cloud-init.log" \
                "${root}/var/log/cloud-init-output.log"
            ;;
        --seed)
            rm -rf -- "${root}/var/lib/cloud/seed"/*
            ;;
    esac
done
EOF
    chmod 0755 \
        "${root}/usr/sbin/visudo" \
        "${root}/usr/sbin/sshd" \
        "${root}/usr/bin/systemctl" \
        "${root}/usr/bin/cloud-init"
    "${root}/run/cloud-provision/proxy_contract.bash" \
        --test-root "${root}" apply > "${root}/proxy-apply.log"

    if [[ "${mode}" == placement-tamper ]]; then
        config_path="${root}/etc/ssh/sshd_config"
        mutation_path="${root}/etc/ssh/.sshd_config.placement-tamper"
        awk \
            -v begin='# BEGIN CLOUD-PROVISION PROXY CONTRACT' \
            -v end='# END CLOUD-PROVISION PROXY CONTRACT' '
            $0 == begin { inside = 1 }
            inside {
                block = block $0 ORS
                if ($0 == end) inside = 0
                next
            }
            { body = body $0 ORS }
            END { printf "%s%s", body, block }
        ' "${config_path}" > "${mutation_path}"
        chmod --reference="${config_path}" "${mutation_path}"
        mv -- "${mutation_path}" "${config_path}"
    fi

    printf '%s\n' 'instance state' > "${root}/var/lib/cloud/instances/fixture/state"
    ln -s "instances/fixture" "${root}/var/lib/cloud/instance"
    printf '%s\n' '#cloud-config' > "${root}/var/lib/cloud/seed/nocloud/user-data"
    printf '%s\n' 'cloud-init log' > "${root}/var/log/cloud-init.log"
    printf '%s\n' 'cloud-init output' > "${root}/var/log/cloud-init-output.log"
    chmod 0644 \
        "${root}/etc/passwd" \
        "${root}/etc/os-release" \
        "${root}/var/log/cloud-init.log" \
        "${root}/var/log/cloud-init-output.log"
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

    # The optional requested= field, issue #26. ansible-provision writes it on
    # app_ioc_runner when a selector is set, recording what the caller asked
    # for beside the commit that was resolved. The unset manifest above is the
    # guard for the no-op path and must stay green.
    write_runner "${runner_bin}" "${runner_commit:0:7}"

    sed '/^app_ioc_runner /s/$/ requested=1.2.3/' "${manifest}" > "${mutation}"
    chmod 0644 "${mutation}"
    expect_success "validator accepts a requested ref on the runner record" \
        run_validator "${mutation}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"

    # A requested ref is caller intent; the tag that happens to point at the
    # resolved commit is not. They may differ, so the field is not tied to tag
    # or state.
    sed '/^app_ioc_runner /s/$/ requested=some-branch/' "${manifest}" > "${mutation}"
    chmod 0644 "${mutation}"
    expect_success "validator does not tie the requested ref to the tag" \
        run_validator "${mutation}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"

    sed '/^app_ioc_runner /s/$/ requested=/' "${manifest}" > "${mutation}"
    chmod 0644 "${mutation}"
    expect_failure "validator rejects an empty requested ref" \
        run_validator "${mutation}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"

    sed '/^app_ioc_runner /s/$/ requested=one two/' "${manifest}" > "${mutation}"
    chmod 0644 "${mutation}"
    expect_failure "validator rejects a whitespace requested ref" \
        run_validator "${mutation}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"

    sed '/^app_epics /s/$/ requested=1.2.3/' "${manifest}" > "${mutation}"
    chmod 0644 "${mutation}"
    expect_failure "validator rejects requested on a non-runner record" \
        run_validator "${mutation}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"

    sed '/^app_ioc_runner /s/$/ unexpected=1/' "${manifest}" > "${mutation}"
    chmod 0644 "${mutation}"
    expect_failure "validator rejects an unknown trailing field" \
        run_validator "${mutation}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"

    sed '/^app_ioc_runner /s/$/ requested=1.2.3 extra=x/' "${manifest}" > "${mutation}"
    chmod 0644 "${mutation}"
    expect_failure "validator rejects a second trailing field" \
        run_validator "${mutation}" "${epics_checkout}" "${runner_checkout}" "${runner_bin}"
}

function write_fake_host_commands {
    local fakebin="$1"

    cat > "${fakebin}/virsh" <<'EOF'
#!/usr/bin/env bash
set -e
command_name=""
for argument in "$@"; do
    case "${argument}" in
        list|dominfo|domblklist|domstate|net-update|shutdown|uri)
            command_name="${argument}"
            break
            ;;
    esac
done
case "${command_name}" in
    uri)
        # create_vm.bash asks the connection separately so it can tell an
        # absent domain from an unreachable libvirt. A fake that does not
        # answer this reads as an outage and the provisioner refuses.
        printf "%s\n" "qemu:///system"
        ;;
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
        [[ -e "${FAKE_GUEST_ROOT}/.proxy-sealed" ]] || {
            printf "%s\n" "stop attempted before terminal proxy seal" >&2
            exit 5
        }
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
        printf "%s\n" "file format: qcow2"
        ;;
    create)
        output="${@: -2:1}"
        printf "%s\n" "independent disk" > "${output}"
        ;;
    convert)
        output="${@: -1}"
        printf "convert %s\n" "${output}" >> "${CALL_LOG}"
        if [[ "${PROMOTION_MODE}" == "conversion-fail" && "${output}" == *"iocrunner-${CASE_OS_TYPE}-"* ]]; then
            exit 1
        fi
        printf "%s\n" "converted image" > "${output}"
        ;;
    resize)
        output="$2"
        [[ -f "${output}" && "$3" == "20G" ]] || exit 1
        printf "resize %s %s\n" "${output}" "$3" >> "${CALL_LOG}"
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
set -e
if [[ -n "${SLEEP_LOG:-}" ]]; then
    printf "%s\n" "$1" >> "${SLEEP_LOG}"
fi
exit 0
EOF

    cat > "${fakebin}/ansible-playbook" <<'EOF'
#!/usr/bin/env bash
set -e
runtime_inventory=""
expect_inventory_path=false
for argument in "$@"; do
    if [[ "${expect_inventory_path}" == true ]]; then
        expect_inventory_path=false
        if [[ -f "${argument}" ]] && \
           grep -Eq "^testbed-${CASE_OS_TYPE}-build-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12} ansible_host=192\\.168\\.122\\.[0-9]+ ansible_user=vmadmin$" \
               "${argument}" && \
           grep -Fxq "[${CASE_OS_TYPE}]" "${argument}" && \
           grep -Fxq '[nfs_sim_nodes]' "${argument}"; then
            runtime_inventory="${argument}"
        fi
    elif [[ "${argument}" == "-i" ]]; then
        expect_inventory_path=true
    fi
done
[[ -n "${runtime_inventory}" ]] || {
    printf "%s\n" "runtime inventory was not passed to ansible-playbook" >&2
    exit 3
}
printf "%s\n" "${runtime_inventory}" >> "${RUNTIME_INVENTORY_ARG_LOG}"
if [[ ! -s "${RUNTIME_INVENTORY_SNAPSHOT}" ]]; then
    cat "${runtime_inventory}" > "${RUNTIME_INVENTORY_SNAPSHOT}"
fi
# Every invocation is recorded so a case can assert which play received the
# version selector. The selector belongs to site.yml alone; the other two plays
# have nothing to do with the runner version.
if [[ -n "${ANSIBLE_ARG_LOG:-}" ]]; then
    printf "%s
" "$*" >> "${ANSIBLE_ARG_LOG}"
fi
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
# Every invocation is recorded whole so a case can assert what each connection
# carried, not merely that the run succeeded. The multiplexing-off options are
# the claim; an exit-code assertion would stay green with them removed.
if [[ -n "${SSH_ARG_LOG:-}" ]]; then
    printf "%s\n" "$*" >> "${SSH_ARG_LOG}"
fi
if [[ -e "${FAKE_GUEST_ROOT:-/nonexistent}/.proxy-sealed" ]]; then
    printf "%s\n" "guest command attempted after terminal proxy seal" >&2
    exit 6
fi
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
    if grep -q 'function proxy_contract_seal' "${input_file}"; then
        [[ "${remote_command}" == "sudo /bin/bash -p -s -- seal" ]] || exit 4
        /bin/bash -p -s -- --test-root "${FAKE_GUEST_ROOT}" seal < "${input_file}"
        while IFS=$'\t' read -r os identity contract_path owner group mode form marker cleanup remnant; do
            [[ "${os}" == "${CASE_OS_FAMILY}" ]] || continue
            guest_path="${FAKE_GUEST_ROOT}${contract_path}"
            case "${form}" in
                dedicated)
                    if [[ -e "${guest_path}" || -L "${guest_path}" ]]; then
                        printf 'omitted proxy identity %s\n' "${identity}" >&2
                        exit 4
                    fi
                    ;;
                shared)
                    if grep -Eqi 'CLOUD-PROVISION PROXY CONTRACT|^[[:space:]]*(proxy|http_proxy|https_proxy|ftp_proxy|no_proxy|HTTP_PROXY|HTTPS_PROXY|FTP_PROXY|NO_PROXY)[[:space:]]*=' \
                        "${guest_path}"; then
                        printf 'omitted proxy identity %s\n' "${identity}" >&2
                        exit 4
                    fi
                    ;;
            esac
        done < "${CONTRACT_FIXTURE}"
        shared_paths=(/etc/environment /etc/gitconfig)
        if [[ "${CASE_OS_FAMILY}" == rocky ]]; then
            shared_paths+=(/etc/dnf/dnf.conf /etc/ssh/sshd_config)
        fi
        for contract_path in "${shared_paths[@]}"; do
            baseline_path="${FAKE_GUEST_ROOT}.before${contract_path}"
            guest_path="${FAKE_GUEST_ROOT}${contract_path}"
            if ! cmp -s -- "${baseline_path}" "${guest_path}" ||
               [[ "$(stat -Lc '%u:%g:%a' "${baseline_path}")" != \
                  "$(stat -Lc '%u:%g:%a' "${guest_path}")" ]]; then
                printf 'shared proxy identity was not restored: %s\n' \
                    "${contract_path}" >&2
                exit 4
            fi
        done
        printf '%s\n' seal >> "${PROXY_SEAL_LOG}"
        : > "${FAKE_GUEST_ROOT}/.proxy-sealed"
        exit 0
    fi
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

# The promotion cases exercise the public bake through image publication. The
# final VM teardown is intentionally not treated as a failure boundary because
# create_vm.bash makes cleanup idempotent and reports teardown failures without
# changing the bake result. The success cases still verify that the bake's
# failure guidance is silent after a successful publication.
function run_promotion_case {
    local mode="$1"
    local os_type="$2"
    local os_family base_image_name
    local label="${mode}-${os_type}"
    local case_dir="${WORKSPACE}/promotion-${label}"
    local fakebin="${case_dir}/bin"
    local image_dir="${case_dir}/images"
    local home_dir="${case_dir}/home"
    local epics_checkout="${case_dir}/epics"
    local runner_checkout="${case_dir}/runner"
    local runner_bin="${case_dir}/ioc-runner"
    local remote_manifest="${case_dir}/remote.manifest"
    local guest_root="${case_dir}/guest-root"
    local output_image=""
    local sidecar=""
    local record=""
    local image_name=""
    local image_id=""
    local image_stem=""
    local image_regex=""
    local epics_commit runner_commit fixture_commit
    local rc=0
    local -a images=()

    case "${os_type}" in
        debian13)
            os_family=debian
            base_image_name=debian-13-genericcloud-amd64-daily.qcow2
            ;;
        rocky8)
            os_family=rocky
            base_image_name=Rocky-8-GenericCloud-Base.latest.x86_64.qcow2
            ;;
        *)
            record_fail "${label} resolves the requested OS" \
                "unsupported OS ${os_type}"
            return 0
            ;;
    esac
    image_regex="^iocrunner-${os_type}-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}[.]qcow2$"

    mkdir -p "${fakebin}" "${image_dir}" "${home_dir}/.ssh"
    printf "%s\n" "ssh-ed25519 AAAAC3NzaFixture test" > "${home_dir}/.ssh/id_ed25519.pub"
    : > "${home_dir}/.ssh/known_hosts"
    printf "%s\n" "base image" > "${image_dir}/${base_image_name}"
    init_checkout "${epics_checkout}" "https://github.com/jeonghanlee/EPICS-env-distribution"
    init_checkout "${runner_checkout}" "https://github.com/jeonghanlee/epics-ioc-runner"
    epics_commit="$(git -C "${epics_checkout}" rev-parse HEAD)"
    runner_commit="$(git -C "${runner_checkout}" rev-parse HEAD)"
    fixture_commit="${runner_commit}"
    write_runner "${runner_bin}" "${runner_commit:0:7}"
    write_fake_host_commands "${fakebin}"
    prepare_proxy_guest_root "${guest_root}" "${os_type}" "${mode}"

    local -a bake_env=(
        "ANSIBLE_ARG_LOG=${case_dir}/ansible-args.log"
        "RUNTIME_INVENTORY_ARG_LOG=${case_dir}/runtime-inventory-args.log"
        "RUNTIME_INVENTORY_SNAPSHOT=${case_dir}/runtime-inventory.ini"
        "SSH_ARG_LOG=${case_dir}/ssh-args.log"
        "SLEEP_LOG=${case_dir}/sleep.log"
        "CASE_DIR=${case_dir}"
        "DOMAIN_STATE_FILE=${case_dir}/domain.state"
        "BASE_IMAGE_PATH=${image_dir}/${base_image_name}"
        "CALL_LOG=${case_dir}/calls.log"
        "PROMOTION_MODE=${mode}"
        "CASE_OS_TYPE=${os_type}"
        "CASE_OS_FAMILY=${os_family}"
        "REMOTE_MANIFEST=${remote_manifest}"
        "FAKE_GUEST_ROOT=${guest_root}"
        "CONTRACT_FIXTURE=${TOP}/tests/fixtures/proxy-artifacts.tsv"
        "PROXY_SEAL_LOG=${case_dir}/proxy-seal.log"
        "FIXTURE_COMMIT=${fixture_commit}"
        "EPICS_COMMIT=${epics_commit}"
        "RUNNER_COMMIT=${runner_commit}"
        "EPICS_CHECKOUT=${epics_checkout}"
        "RUNNER_CHECKOUT=${runner_checkout}"
        "RUNNER_BIN=${runner_bin}"
        "REAL_VALIDATOR=${VALIDATOR}"
        "PATH=${fakebin}:${PATH}"
        "HOME=${home_dir}"
        "USER=$(id -un)"
        "REQUIRED_GROUP=$(id -gn)"
        "VM_WAIT_SHUTDOWN_INTERVAL_SECONDS=7"
    )
    local -a bake_command=(
        "${BAKE}" -o "${os_type}" -d "${image_dir}" \
        -a "${TOP}/../ansible-provision" -k
    )
    if [[ -n "${CASE_RUNNER_REF:-}" ]]; then
        bake_command+=(-r "${CASE_RUNNER_REF}")
    fi
    env "${bake_env[@]}" "${bake_command[@]}" \
        > "${case_dir}/output.txt" 2>&1 || rc=$?

    assert_runtime_inventory "${label}" \
        "${case_dir}/runtime-inventory-args.log" \
        "${case_dir}/runtime-inventory.ini" "${os_type}"
    assert_ssh_multiplexing_off "${label}" "${case_dir}/ssh-args.log"

    if [[ "${mode}" == seal-case ]]; then
        shopt -s nullglob
        images=("${image_dir}"/iocrunner-"${os_type}"-*.qcow2)
        shopt -u nullglob
        if [[ "${rc}" == 0 ]]; then
            record_pass "${label} public bake completes"
            if [[ "$(wc -l < "${case_dir}/proxy-seal.log" 2>/dev/null || true)" == 1 ]]; then
                record_pass "${label} executes one terminal proxy seal"
            else
                record_fail "${label} executes one terminal proxy seal" \
                    "the seal completion count was not one"
            fi
            if (( ${#images[@]} == 1 )) &&
               [[ -f "${images[0]}.manifest" && -f "${images[0]}.creation-record" ]]; then
                record_pass "${label} publishes one complete image pair"
            else
                record_fail "${label} publishes one complete image pair" \
                    "the final image, manifest, or creation record is missing"
            fi
        else
            local omission_error
            omission_error="$(grep -m1 'omitted proxy identity ' \
                "${case_dir}/output.txt" || true)"
            record_fail "${label} public bake completes" \
                "${omission_error:-bake exited ${rc} before seal completion}"
            if [[ ! -s "${case_dir}/proxy-seal.log" ]]; then
                record_pass "${label} omits seal completion"
            else
                record_fail "${label} omits seal completion" \
                    "a seal completion record was written"
            fi
            if (( ${#images[@]} == 0 )) &&
               { [[ ! -e "${case_dir}/calls.log" ]] ||
                 ! grep -q "convert .*iocrunner-${os_type}-" \
                    "${case_dir}/calls.log"; }; then
                record_pass "${label} blocks publication before conversion"
            else
                record_fail "${label} blocks publication before conversion" \
                    "a final conversion or published image was observed"
            fi
        fi
        return 0
    fi

    if [[ "${mode}" == placement-tamper ]]; then
        if [[ "${rc}" != 0 ]] &&
           grep -Fq 'identity sshd contract block is not in global scope' \
            "${case_dir}/output.txt"; then
            record_pass "${mode} rejects a shared block outside global sshd scope"
        else
            record_fail "${mode} rejects a shared block outside global sshd scope" \
                "the public bake did not report the placement defect"
        fi
        if [[ ! -s "${case_dir}/proxy-seal.log" ]]; then
            record_pass "${mode} omits seal completion"
        else
            record_fail "${mode} omits seal completion" \
                "a seal completion record was written"
        fi
        shopt -s nullglob
        images=("${image_dir}"/iocrunner-"${os_type}"-*.qcow2)
        shopt -u nullglob
        if (( ${#images[@]} == 0 )) &&
           { [[ ! -e "${case_dir}/calls.log" ]] ||
             ! grep -q "convert .*iocrunner-${os_type}-" \
                "${case_dir}/calls.log"; }; then
            record_pass "${mode} blocks publication before conversion"
        else
            record_fail "${mode} blocks publication before conversion" \
                "a final conversion or published image was observed"
        fi
        return 0
    fi

    if [[ "${mode}" == "seed-argument-omission" ]]; then
        if [[ "${rc}" != "0" ]]; then
            record_pass "${mode} fails the public bake during terminal seal"
        else
            record_fail "${mode} fails the public bake during terminal seal" \
                "bake unexpectedly succeeded"
        fi
        if [[ -f "${guest_root}/var/lib/cloud/seed/nocloud/user-data" ]]; then
            record_pass "${mode} retains seed data when the argument is missing"
        else
            record_fail "${mode} retains seed data when the argument is missing" \
                "the argument-sensitive fake removed seed data"
        fi
        shopt -s nullglob
        images=("${image_dir}"/iocrunner-"${os_type}"-*.qcow2)
        shopt -u nullglob
        if (( ${#images[@]} == 0 )) &&
           { [[ ! -e "${case_dir}/calls.log" ]] ||
             ! grep -q "convert .*iocrunner-${os_type}-" "${case_dir}/calls.log"; }; then
            record_pass "${mode} blocks publication before conversion"
        else
            record_fail "${mode} blocks publication before conversion" \
                "a final image or conversion call was observed"
        fi
        return 0
    fi

    if [[ "${mode}" == "publish-clean" || "${mode}" == "publish-repeat" || \
        "${mode}" == "publish-pinned" ]]; then
        if [[ "${rc}" == "0" ]]; then
            record_pass "${mode} public bake completes"
        else
            record_fail "${mode} public bake completes" "bake exited ${rc}"
        fi

        if [[ "$(wc -l < "${case_dir}/proxy-seal.log" 2>/dev/null || true)" == "1" ]]; then
            record_pass "${mode} executes the exact terminal proxy seal"
        else
            record_fail "${mode} executes the exact terminal proxy seal" \
                "the streamed contract did not complete exactly once"
        fi

        shopt -s nullglob
        images=("${image_dir}"/iocrunner-"${os_type}"-*.qcow2)
        shopt -u nullglob
        if (( ${#images[@]} == 1 )); then
            output_image="${images[0]}"
            sidecar="${output_image}.manifest"
            record="${output_image}.creation-record"
            image_name="$(grep '^image_name=' "${record}" | cut -d= -f2- || true)"
            image_id="$(grep '^image_id=' "${record}" | cut -d= -f2- || true)"
            image_stem="${output_image##*/}"
            image_stem="${image_stem#iocrunner-${os_type}-}"
            image_stem="${image_stem%.qcow2}"
            if [[ "${output_image##*/}" =~ ${image_regex} \
                && "${image_name}" == "${output_image##*/}" \
                && "${image_id}" == "${image_stem}" ]]; then
                record_pass "${mode} names and records the published image"
            else
                record_fail "${mode} names and records the published image" \
                    "unexpected name or creation record"
            fi
        else
            record_fail "${mode} names and records the published image" \
                "found ${#images[@]} generated images"
        fi

        if (( ${#images[@]} == 1 )) && [[ -f "${sidecar}" && -f "${record}" ]]; then
            record_pass "${mode} publishes the complete image pair"
        else
            record_fail "${mode} publishes the complete image pair" "sidecar or record missing"
        fi

        if ! find "${image_dir}" -maxdepth 1 -type f \
            \( -name '*.tmp' -o -name '*.manifest.tmp' \) -print -quit | grep -q .; then
            record_pass "${mode} removes only current temporary outputs"
        else
            record_fail "${mode} removes only current temporary outputs" "temporary output remained"
        fi

        if grep -Eq \
            "VM 'testbed-${os_type}-build-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}' is running\. Shutting down \(ACPI\)\.\.\." \
            "${case_dir}/output.txt" && \
           grep -Eq \
            "VM 'testbed-${os_type}-build-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}' shut off \[OK\]" \
            "${case_dir}/output.txt"; then
            record_pass "${mode} uses the shared public stop path"
        else
            record_fail "${mode} uses the shared public stop path" \
                "public ACPI start or completion output is missing"
        fi

        if [[ "$(cat "${case_dir}/sleep.log")" == "7" ]]; then
            record_pass "${mode} passes the wait override to the shared stop path"
        else
            record_fail "${mode} passes the wait override to the shared stop path" \
                "the shared stop did not use the 7-second override"
        fi

        # These cases run with -k, which keeps the build VM on purpose. The
        # failure guidance must not fire here, or every successful debugging
        # bake would read as a failed one.
        if ! grep -q 'was left for inspection' "${case_dir}/output.txt"; then
            record_pass "${mode} prints no failure guidance on success"
        else
            record_fail "${mode} prints no failure guidance on success" \
                "cleanup guidance printed after a successful bake"
        fi

        # Where the version selector went, issue #26. Asserting only that the
        # bake succeeded would pass whether the selector reached site.yml, all
        # three plays, or none of them.
        local arg_log="${case_dir}/ansible-args.log"
        local site_lines other_with_ref
        site_lines="$(grep -c 'site\.yml' "${arg_log}" 2>/dev/null || true)"
        other_with_ref="$(grep 'ioc_runner_version' "${arg_log}" 2>/dev/null \
            | grep -c -v 'site\.yml' || true)"
        if [[ -z "${CASE_RUNNER_REF:-}" ]]; then
            if ! grep -q 'ioc_runner_version' "${arg_log}" 2>/dev/null; then
                record_pass "${mode} unset selector adds no extra vars"
            else
                record_fail "${mode} unset selector adds no extra vars" \
                    "$(grep 'ioc_runner_version' "${arg_log}" | head -1)"
            fi
        else
            if grep 'site\.yml' "${arg_log}" 2>/dev/null \
                | grep -q -- "-e ioc_runner_version=${CASE_RUNNER_REF}"; then
                record_pass "${mode} selector reaches site.yml"
            else
                record_fail "${mode} selector reaches site.yml" "not in the recorded arguments"
            fi
            expect_equal "${mode} selector reaches no other play" "0" "${other_with_ref}"
        fi
        expect_equal "${mode} site.yml ran once" "1" "${site_lines}"

        # The published image must be a real file. A symlink would satisfy the
        # existence check and make the image pair point outside the output.
        if [[ -f "${output_image}" && ! -L "${output_image}" ]]; then
            record_pass "${mode} published image is a real file"
        else
            record_fail "${mode} published image is a real file" "not a regular file"
        fi
        return 0
    fi

    if [[ "${rc}" != "0" ]]; then
        record_pass "${mode} public bake fails safely"
    else
        record_fail "${mode} public bake fails safely" "bake unexpectedly succeeded"
    fi

    if [[ "${mode}" == "validator-reject" ]]; then
        if [[ ! -e "${case_dir}/calls.log" ]] || \
           ! grep -q "iocrunner-${os_type}-" "${case_dir}/calls.log"; then
            record_pass "validator rejection prevents conversion"
        else
            record_fail "validator rejection prevents conversion" "final image conversion was called"
        fi
    else
        if grep -q "iocrunner-${os_type}-" "${case_dir}/calls.log"; then
            record_pass "conversion failure reaches the real conversion boundary"
        else
            record_fail "conversion failure reaches the real conversion boundary" "conversion was not called"
        fi
    fi

    if ! find "${image_dir}" -maxdepth 1 -type f \( -name '*.tmp' -o -name '*.manifest.tmp' \) \
        -print -quit | grep -q .; then
        record_pass "${mode} removes only current temporary outputs"
    else
        record_fail "${mode} removes only current temporary outputs" "temporary output remained"
    fi

    # The runbook tells a reader who hits this to run the printed cleanup
    # command, so the failing bake has to print one and has to name the VM it
    # actually left. Asserting only that some text appeared would pass on a
    # message naming the wrong domain.
    if grep -q 'was left for inspection' "${case_dir}/output.txt"; then
        record_pass "${mode} names the build VM left behind"
    else
        record_fail "${mode} names the build VM left behind" "no cleanup guidance printed"
    fi
    if grep -q "IMAGE_WORKFLOW_RUN_ID=.*create_vm.bash -o ${os_type} -n build .* -p testbed -c" \
        "${case_dir}/output.txt"; then
        record_pass "${mode} prints a runnable clean-restart command"
    else
        record_fail "${mode} prints a runnable clean-restart command" \
            "cleanup command absent or malformed"
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

function run_ref_guard_case {
    local name="$1"
    local want_text="$2"
    shift 2
    local output rc=0

    output="$(env REQUIRED_GROUP="$(id -gn)" "${BAKE}" "$@" 2>&1)" || rc=$?
    if [[ "${rc}" != "0" && "${output}" == *"${want_text}"* ]]; then
        record_pass "${name}"
    else
        record_fail "${name}" "rc=${rc}, output: ${output%%$'\n'*}"
    fi

    # These refusals happen before Step 1, so no build VM exists. Naming one
    # here would send the reader to clean up a domain that was never created,
    # which is the failure mode the domain query in the trap exists to avoid.
    if [[ "${output}" != *"was left for inspection"* ]]; then
        record_pass "${name} leaves no build VM to clean up"
    else
        record_fail "${name} leaves no build VM to clean up" \
            "named a build VM that was never created"
    fi
}

function run_ref_guard_tests {
    run_ref_guard_case "bake rejects an empty ref" "requires a non-empty ref" \
        -o rocky8 -r "" -d /nonexistent
    run_ref_guard_case "bake rejects a dash-led ref" "starts with -" \
        -o rocky8 -r -k -d /nonexistent
    run_ref_guard_case "bake rejects a ref with a space" "invalid ioc-runner ref" \
        -o rocky8 -r "one two" -d /nonexistent
}

WORKSPACE="$(mktemp -d /tmp/iocrunner-bake-provenance-test.XXXXXX)"

case "${1:-all}" in
    validator)
        run_validator_tests
        ;;
    promotion)
        run_ref_guard_tests
        run_promotion_case placement-tamper rocky8
        run_promotion_case validator-reject rocky8
        run_promotion_case conversion-fail rocky8
        run_promotion_case publish-clean rocky8
        run_promotion_case publish-repeat rocky8
        CASE_RUNNER_REF=1.2.3 run_promotion_case publish-pinned rocky8
        ;;
    seed-omission)
        run_promotion_case seed-argument-omission rocky8
        ;;
    seal-case)
        case "${2:-}" in
            debian13|rocky8) run_promotion_case seal-case "$2" ;;
            *)
                printf 'Usage: %s seal-case {debian13|rocky8}\n' \
                    "$(basename "$0")" >&2
                exit 2
                ;;
        esac
        ;;
    all)
        run_validator_tests
        run_ref_guard_tests
        run_promotion_case seal-case debian13
        run_promotion_case seal-case rocky8
        run_promotion_case placement-tamper rocky8
        run_promotion_case validator-reject rocky8
        run_promotion_case conversion-fail rocky8
        run_promotion_case publish-clean rocky8
        run_promotion_case publish-repeat rocky8
        CASE_RUNNER_REF=1.2.3 run_promotion_case publish-pinned rocky8
        ;;
    *)
        printf "Usage: %s [validator|promotion|seed-omission|seal-case|all]\n" \
            "$(basename "$0")" >&2
        exit 2
        ;;
esac

print_summary
