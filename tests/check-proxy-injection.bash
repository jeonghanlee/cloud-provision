#!/usr/bin/env bash
#
# Verifies proxy discovery and cloud-init injection through the public
# create_vm.bash provisioning path.
#
# The shipped provisioner and image workflow execute for real. Only external
# boundaries are replaced: curl, virsh, virt-install, genisoimage, ssh, guest
# command executables, and groups. The captured user-data is the actual seed
# input produced by the provisioner before the ISO boundary.

set -euo pipefail

declare -g SCRIPT_DIR
declare -g TOP
declare -g WORKSPACE
declare -g FAKEBIN
declare -g BASE_FIXTURE
declare -g CONTRACT_FIXTURE
declare -g ORIGINAL_PATH
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -ag FAILED_DETAILS=()

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE="$(mktemp -d /tmp/cloud-provision-proxy-test.XXXXXX)"
FAKEBIN="${WORKSPACE}/fakebin"
BASE_FIXTURE="${WORKSPACE}/base.qcow2"
CONTRACT_FIXTURE="${TOP}/tests/fixtures/proxy-artifacts.tsv"
ORIGINAL_PATH="${PATH}"

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

function expect_exit {
    local name="$1"
    local expected="$2"
    local actual="$3"

    if [[ "${actual}" == "${expected}" ]]; then
        record_pass "${name}"
    else
        record_fail "${name}" "expected exit ${expected}, got ${actual}"
    fi
}

function expect_contains {
    local name="$1"
    local file="$2"
    local text="$3"

    if grep -Fq -- "${text}" "${file}"; then
        record_pass "${name}"
    else
        record_fail "${name}" "missing expected text in ${file}"
    fi
}

function expect_not_contains {
    local name="$1"
    local file="$2"
    local text="$3"

    if ! grep -Fq -- "${text}" "${file}"; then
        record_pass "${name}"
    else
        record_fail "${name}" "unexpected text in ${file}"
    fi
}

function extract_yaml_literal {
    local source_file="$1"
    local wanted_path="$2"
    local output_file="$3"

    awk -v wanted_path="${wanted_path}" '
        $0 == "  - path: " wanted_path {
            selected = 1
            next
        }
        selected && $0 == "    content: |" {
            content = 1
            next
        }
        content && $0 ~ /^  - path:/ { exit }
        content && $0 !~ /^      / { exit }
        content { print substr($0, 7) }
    ' "${source_file}" > "${output_file}"
    [[ -s "${output_file}" ]]
}

function expect_exact_artifact_set {
    local name="$1"
    local os_type="$2"
    local capture_file="$3"
    local os_family
    local expected_count
    local expected_file="${WORKSPACE}/${name}.expected-transient-paths"
    local actual_file="${WORKSPACE}/${name}.actual-transient-paths"
    local expected_inventory="${WORKSPACE}/${name}.expected-inventory"
    local actual_inventory="${WORKSPACE}/${name}.actual-inventory"
    local staged_script="${WORKSPACE}/${name}.staged-contract"
    local staged_input="${WORKSPACE}/${name}.staged-input"
    local write_files_count runcmd_count apply_line runcmd_line

    case "${os_type}" in
        *debian*) os_family="debian" ;;
        *ubuntu*) os_family="ubuntu" ;;
        *rocky*) os_family="rocky" ;;
        *) record_fail "${name} resolves fixture OS" "unsupported test OS ${os_type}"; return 0 ;;
    esac
    awk -F '\t' -v os="${os_family}" 'NR > 1 && $1 == os' \
        "${CONTRACT_FIXTURE}" | sort > "${expected_inventory}"
    bash -c 'source "$1"; proxy_contract_print_inventory "$2"' \
        proxy-inventory "${TOP}/bin/proxy_contract.bash" "${os_family}" \
        | sort > "${actual_inventory}"
    if diff -u "${expected_inventory}" "${actual_inventory}" >/dev/null; then
        record_pass "${name} fixture matches the production inventory tuple"
    else
        record_fail "${name} fixture matches the production inventory tuple" \
            "path, owner, group, mode, form, marker, cleanup, or remnant differs"
    fi
    expected_count="$(awk -F '\t' -v os="${os_family}" \
        'NR > 1 && $1 == os {count++} END {print count + 0}' \
        "${CONTRACT_FIXTURE}")"
    case "${os_family}" in
        debian|ubuntu)
            expect_exit "${name} fixture contains eight identities" 8 "${expected_count}"
            ;;
        rocky)
            expect_exit "${name} fixture contains seven identities" 7 "${expected_count}"
            ;;
    esac

    printf '%s\n' \
        "/run/cloud-provision/proxy-contract.input" \
        "/run/cloud-provision/proxy_contract.bash" \
        | sort > "${expected_file}"
    awk '$1 == "-" && $2 == "path:" {print $3}' "${capture_file}" \
        | sort > "${actual_file}"
    if diff -u "${expected_file}" "${actual_file}" >/dev/null; then
        record_pass "${name} stages only the exact transient artifact set"
    else
        record_fail "${name} stages only the exact transient artifact set" \
            "generated write_files paths differ from the contract staging set"
    fi

    write_files_count="$(grep -Ec '^write_files:' "${capture_file}" || true)"
    runcmd_count="$(grep -Ec '^runcmd:' "${capture_file}" || true)"
    expect_exit "${name} emits one top-level write_files" 1 "${write_files_count}"
    expect_exit "${name} emits one top-level runcmd" 1 "${runcmd_count}"
    apply_line="$(grep -nF \
        '  - [sudo, /bin/bash, -p, /run/cloud-provision/proxy_contract.bash, apply]' \
        "${capture_file}" | cut -d: -f1)"
    runcmd_line="$(grep -n '^runcmd:' "${capture_file}" | cut -d: -f1)"
    if [[ "${apply_line}" =~ ^[0-9]+$ && "${runcmd_line}" =~ ^[0-9]+$ &&
          "${apply_line}" == "$((runcmd_line + 1))" ]]; then
        record_pass "${name} places apply first in runcmd"
    else
        record_fail "${name} places apply first in runcmd" \
            "the privileged apply command is not the first runcmd item"
    fi

    if extract_yaml_literal "${capture_file}" \
        "/run/cloud-provision/proxy_contract.bash" "${staged_script}" &&
       cmp -s -- "${TOP}/bin/proxy_contract.bash" "${staged_script}"; then
        record_pass "${name} stages the byte-identical shipped contract"
    else
        record_fail "${name} stages the byte-identical shipped contract" \
            "the staged script differs from bin/proxy_contract.bash"
    fi
    if extract_yaml_literal "${capture_file}" \
        "/run/cloud-provision/proxy-contract.input" "${staged_input}" &&
       grep -Fxq 'schema=1' "${staged_input}" &&
       grep -Fxq 'proxy_url=http://proxy.example.test:3128/' "${staged_input}" &&
       grep -Eq '^script_sha256=[0-9a-f]{64}$' "${staged_input}"; then
        record_pass "${name} stages validated schema 1 input as data"
    else
        record_fail "${name} stages validated schema 1 input as data" \
            "the staged input is missing an exact schema field"
    fi
}

function write_fake_commands {
    cat > "${FAKEBIN}/groups" <<'EOF'
#!/usr/bin/env bash
printf "%s\n" "${1:-testuser} nogroup"
EOF

    cat > "${FAKEBIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            target="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
[[ -n "${target}" ]]
if [[ -n "${FAKE_CURL_LOG:-}" ]]; then
    printf "%s\n" "${target}" >> "${FAKE_CURL_LOG}"
fi
cp "${FAKE_BASE_IMAGE}" "${target}"
EOF

    cat > "${FAKEBIN}/virsh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command_name=""
for arg in "$@"; do
    case "${arg}" in
        uri|domstate|dominfo|net-dumpxml|net-update)
            command_name="${arg}"
            break
            ;;
    esac
done
case "${command_name}" in
    uri)
        printf "%s\n" "qemu:///system"
        ;;
    domstate|dominfo)
        exit 1
        ;;
    net-dumpxml)
        printf "%s\n" "<network><ip><dhcp></dhcp></ip></network>"
        ;;
    net-update)
        ;;
    *)
        printf "unexpected virsh command: %s\n" "$*" >&2
        exit 2
        ;;
esac
EOF

    cat > "${FAKEBIN}/virt-install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FAKE_VIRT_INSTALL_LOG:-}" ]]; then
    printf "%s\n" "$*" >> "${FAKE_VIRT_INSTALL_LOG}"
fi
EOF

    cat > "${FAKEBIN}/genisoimage" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
user_data=""
previous=""
for arg in "$@"; do
    if [[ "${previous}" == "-output" ]]; then
        output="${arg}"
    fi
    case "${arg}" in
        user-data=*)
            user_data="${arg#user-data=}"
            ;;
    esac
    previous="${arg}"
done
[[ -n "${output}" && -n "${user_data}" ]]
cp "${user_data}" "${FAKE_CAPTURE_USER_DATA}"
: > "${output}"
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

    cat > "${FAKEBIN}/uuidgen" <<'EOF'
#!/usr/bin/env bash
printf "%s\n" "00000000-0000-4000-8000-000000000001"
EOF

    cat > "${FAKEBIN}/cloud-init" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: > "${PROXY_HOST_COMMAND_SENTINEL}"
exit 0
EOF

    chmod +x "${FAKEBIN}"/*
}

function write_proxy_fixture {
    local proxy_dir="$1"
    local file_name="$2"
    local proxy_url="${3:-http://proxy.example.test:3128/}"

    mkdir -p "${proxy_dir}"
    {
        printf 'PROXY_URL="%s"\n' "${proxy_url}"
        printf '%s\n' \
        "export http_proxy=\"\$PROXY_URL\"" \
        "export https_proxy=\"\$PROXY_URL\"" \
        "export ftp_proxy=\"\$PROXY_URL\"" \
        'export no_proxy="127.0.0.1,localhost"' \
        "export HTTP_PROXY=\"\$PROXY_URL\"" \
        "export HTTPS_PROXY=\"\$PROXY_URL\"" \
        "export FTP_PROXY=\"\$PROXY_URL\"" \
        "export NO_PROXY=\"\$no_proxy\""
    } > "${proxy_dir}/${file_name}"
}

function write_guest_commands {
    local guest_root="$1"

    cat > "${guest_root}/usr/sbin/visudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${PROXY_GUEST_ENV_LOG:-}" ]]; then
    printf 'PATH=%s\n' "${PATH}" >> "${PROXY_GUEST_ENV_LOG}"
    printf 'umask=%s\n' "$(umask)" >> "${PROXY_GUEST_ENV_LOG}"
    printf 'sentinel=%s\n' "${HOSTILE_INHERITED_SENTINEL-unset}" \
        >> "${PROXY_GUEST_ENV_LOG}"
fi
[[ "$1" == "-cf" && -f "$2" ]]
grep -Fq 'Defaults env_keep += "http_proxy https_proxy ftp_proxy no_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY NO_PROXY"' "$2"
printf 'visudo %s\n' "$2" >> "${PROXY_GUEST_COMMAND_LOG}"
EOF

    cat > "${guest_root}/usr/sbin/sshd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
config=""
previous=""
for argument in "$@"; do
    if [[ "${previous}" == "-f" ]]; then
        config="${argument}"
    fi
    previous="${argument}"
done
[[ -n "${config}" && -f "${config}" ]]
if grep -Fq 'PermitUserEnvironment yes' "${config}" ||
   grep -Fq 'PermitUserEnvironment yes' "${PROXY_GUEST_ROOT}/etc/ssh/sshd_config.d/95cloud-provision-proxy.conf"; then
    printf '%s\n' 'permituserenvironment yes'
else
    printf '%s\n' 'permituserenvironment no'
fi
printf 'sshd %s\n' "$*" >> "${PROXY_GUEST_COMMAND_LOG}"
EOF

    cat > "${guest_root}/usr/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "reload" ]]
case "$2" in
    ssh|sshd) ;;
    *) exit 2 ;;
esac
printf 'systemctl %s\n' "$*" >> "${PROXY_GUEST_COMMAND_LOG}"
if [[ "${PROXY_GUEST_SYSTEMCTL_FAIL:-0}" == 1 ]]; then
    exit 1
fi
EOF

    chmod 0755 \
        "${guest_root}/usr/sbin/visudo" \
        "${guest_root}/usr/sbin/sshd" \
        "${guest_root}/usr/bin/systemctl"
}

function write_guest_cloud_init {
    local guest_root="$1"

    cat > "${guest_root}/usr/bin/cloud-init" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == clean ]]
printf 'cloud-init %s\n' "$*" >> "${PROXY_GUEST_COMMAND_LOG}"
EOF
    chmod 0755 "${guest_root}/usr/bin/cloud-init"
}

function run_contract_with_hostile_environment {
    local guest_root="$1"
    local operation="$2"
    local command_log="$3"
    local environment_log="$4"
    local fail_reload="$5"

    HOSTILE_INHERITED_SENTINEL=present /usr/bin/env -i \
        "PROXY_GUEST_ROOT=${guest_root}" \
        "PROXY_GUEST_COMMAND_LOG=${command_log}" \
        "PROXY_GUEST_ENV_LOG=${environment_log}" \
        "PROXY_GUEST_SYSTEMCTL_FAIL=${fail_reload}" \
        /bin/bash --noprofile --norc -c \
        'umask 000; exec "$1" --test-root "$2" "$3"' \
        hostile-proxy-contract \
        "${guest_root}/run/cloud-provision/proxy_contract.bash" \
        "${guest_root}" "${operation}"
}

function expect_shared_baseline_restored {
    local name="$1"
    local baseline_root="$2"
    local actual_root="$3"
    local relative_path baseline_metadata actual_metadata
    local failures=0

    for relative_path in etc/environment etc/gitconfig etc/ssh/sshd_config; do
        baseline_metadata="$(stat -Lc '%u:%g:%a' \
            "${baseline_root}/${relative_path}")"
        actual_metadata="$(stat -Lc '%u:%g:%a' \
            "${actual_root}/${relative_path}")"
        if ! cmp -s -- "${baseline_root}/${relative_path}" \
            "${actual_root}/${relative_path}" ||
           [[ "${baseline_metadata}" != "${actual_metadata}" ]]; then
            failures=$((failures + 1))
        fi
    done
    if [[ "${failures}" == 0 ]]; then
        record_pass "${name} restores shared bytes and metadata"
    else
        record_fail "${name} restores shared bytes and metadata" \
            "${failures} shared files differ from the baseline"
    fi
}

function expect_contract_markers_absent {
    local name="$1"
    local os_family="$2"
    local guest_root="$3"
    local fixture_os identity path owner group mode form marker cleanup remnant
    local failures=0

    while IFS=$'\t' read -r fixture_os identity path owner group mode form marker cleanup remnant; do
        [[ "${fixture_os}" == "${os_family}" ]] || continue
        path="${guest_root}${path}"
        if [[ -f "${path}" ]] &&
           grep -Fq '# BEGIN CLOUD-PROVISION PROXY CONTRACT' "${path}"; then
            failures=$((failures + 1))
        fi
    done < <(awk -F '\t' -v os="${os_family}" 'NR > 1 && $1 == os' \
        "${CONTRACT_FIXTURE}")
    if [[ "${failures}" == 0 ]]; then
        record_pass "${name} leaves no contract marker"
    else
        record_fail "${name} leaves no contract marker" \
            "${failures} contract markers remain"
    fi
}

function run_hostile_environment_lifecycle {
    local baseline_root="${WORKSPACE}/debian-proxy.guest-root.before-apply"
    local lifecycle_root="${WORKSPACE}/hostile-environment-lifecycle"
    local rollback_root="${WORKSPACE}/hostile-environment-rollback"
    local lifecycle_commands="${WORKSPACE}/hostile-lifecycle-commands.log"
    local lifecycle_environment="${WORKSPACE}/hostile-lifecycle-environment.log"
    local rollback_commands="${WORKSPACE}/hostile-rollback-commands.log"
    local rollback_environment="${WORKSPACE}/hostile-rollback-environment.log"
    local apply_output="${WORKSPACE}/hostile-lifecycle-apply.log"
    local seal_output="${WORKSPACE}/hostile-lifecycle-seal.log"
    local rollback_output="${WORKSPACE}/hostile-rollback-apply.log"
    local rc=0

    cp -a -- "${baseline_root}" "${lifecycle_root}"
    write_guest_cloud_init "${lifecycle_root}"
    run_contract_with_hostile_environment \
        "${lifecycle_root}" apply "${lifecycle_commands}" \
        "${lifecycle_environment}" 0 > "${apply_output}" 2>&1 || rc=$?
    expect_exit "hostile environment apply succeeds" 0 "${rc}"
    if [[ "${rc}" == 0 ]]; then
        expect_contains "hostile environment exports the fixed PATH" \
            "${lifecycle_environment}" \
            'PATH=/usr/sbin:/usr/bin:/sbin:/bin'
        expect_contains "hostile environment normalizes the umask" \
            "${lifecycle_environment}" 'umask=0077'
        expect_contains "hostile environment clears inherited variables" \
            "${lifecycle_environment}" 'sentinel=unset'
        verify_applied_artifacts \
            "hostile environment" debian "${lifecycle_root}"
        if [[ "$(stat -Lc '%a' \
              "${lifecycle_root}/run/cloud-provision/proxy-contract.lock")" == 600 ]]; then
            record_pass "hostile environment creates a mode 0600 lock"
        else
            record_fail "hostile environment creates a mode 0600 lock" \
                "the apply lock does not have mode 0600"
        fi
    fi

    rc=0
    run_contract_with_hostile_environment \
        "${lifecycle_root}" seal "${lifecycle_commands}" \
        "${lifecycle_environment}" 0 > "${seal_output}" 2>&1 || rc=$?
    expect_exit "hostile environment seal succeeds" 0 "${rc}"
    if [[ "${rc}" == 0 ]]; then
        expect_shared_baseline_restored \
            "hostile environment seal" "${baseline_root}" "${lifecycle_root}"
        expect_contract_markers_absent \
            "hostile environment seal" debian "${lifecycle_root}"
        if [[ ! -e "${lifecycle_root}/run/cloud-provision/proxy_contract.bash" &&
              ! -e "${lifecycle_root}/run/cloud-provision/proxy-contract.input" &&
              ! -e "${lifecycle_root}/run/cloud-provision/proxy-contract.lock" ]]; then
            record_pass "hostile environment seal removes transient files"
        else
            record_fail "hostile environment seal removes transient files" \
                "one or more transient files remain"
        fi
        expect_contains "hostile environment seal runs cloud-init clean" \
            "${lifecycle_commands}" 'cloud-init clean'
    fi

    cp -a -- "${baseline_root}" "${rollback_root}"
    rc=0
    run_contract_with_hostile_environment \
        "${rollback_root}" apply "${rollback_commands}" \
        "${rollback_environment}" 1 > "${rollback_output}" 2>&1 || rc=$?
    expect_exit "hostile environment reload failure rejects apply" 1 "${rc}"
    expect_shared_baseline_restored \
        "hostile environment rollback" "${baseline_root}" "${rollback_root}"
    expect_contract_markers_absent \
        "hostile environment rollback" debian "${rollback_root}"
    if [[ ! -e "${rollback_root}/run/cloud-provision/proxy-contract.lock" ]]; then
        record_pass "hostile environment rollback removes the apply lock"
    else
        record_fail "hostile environment rollback removes the apply lock" \
            "the apply lock remains after rollback"
    fi
}

function expected_applied_mode {
    local identity="$1"
    local fixture_mode="$2"

    case "${identity}" in
        environment|dnf) printf '%s\n' 640 ;;
        git) printf '%s\n' 600 ;;
        *) printf '%s\n' "${fixture_mode#0}" ;;
    esac
}

function verify_applied_artifacts {
    local name="$1"
    local os_family="$2"
    local guest_root="$3"
    local identity path owner group mode form marker cleanup remnant
    local actual_uid actual_gid actual_mode expected_uid expected_gid expected_mode
    local checked=0 failures=0

    while IFS=$'\t' read -r fixture_os identity path owner group mode form marker cleanup remnant; do
        [[ "${fixture_os}" == "${os_family}" ]] || continue
        checked=$((checked + 1))
        path="${guest_root}${path}"
        if [[ ! -f "${path}" || -L "${path}" ]]; then
            failures=$((failures + 1))
            continue
        fi
        actual_uid="$(stat -Lc '%u' "${path}")"
        actual_gid="$(stat -Lc '%g' "${path}")"
        actual_mode="$(stat -Lc '%a' "${path}")"
        expected_uid="$(id -u)"
        expected_gid="$(id -g)"
        expected_mode="$(expected_applied_mode "${identity}" "${mode}")"
        if [[ "${actual_uid}" != "${expected_uid}" ||
              "${actual_gid}" != "${expected_gid}" ||
              "${actual_mode}" != "${expected_mode}" ||
              ( "${owner}" != root && "${owner}" != vmadmin ) ||
              ( "${group}" != root && "${group}" != vmadmin ) ||
              ( "${form}" != dedicated && "${form}" != shared ) ||
              "${marker}" != cloud-provision-proxy-v1 ||
              "${cleanup}" != required || "${remnant}" != required ]] ||
           ! grep -Fq '# BEGIN CLOUD-PROVISION PROXY CONTRACT' "${path}" ||
           ! grep -Fq '# END CLOUD-PROVISION PROXY CONTRACT' "${path}"; then
            failures=$((failures + 1))
        fi
    done < <(awk -F '\t' -v os="${os_family}" 'NR > 1 && $1 == os' \
        "${CONTRACT_FIXTURE}")

    if [[ "${failures}" == 0 ]] &&
       { [[ "${os_family}" == rocky && "${checked}" == 7 ]] ||
         [[ "${os_family}" != rocky && "${checked}" == 8 ]]; }; then
        record_pass "${name} applies every fixture artifact with exact metadata"
    else
        record_fail "${name} applies every fixture artifact with exact metadata" \
            "${failures} of ${checked} checked artifacts failed"
    fi
}

function run_staged_apply {
    local name="$1"
    local os_family="$2"
    local capture_file="$3"
    local guest_root="${WORKSPACE}/${name}.guest-root"
    local command_log="${WORKSPACE}/${name}.guest-commands.log"
    local output_file="${WORKSPACE}/${name}.apply-output.log"
    local begin_line match_line rc=0

    mkdir -p \
        "${guest_root}/etc/profile.d" \
        "${guest_root}/etc/apt/apt.conf.d" \
        "${guest_root}/etc/dnf" \
        "${guest_root}/etc/sudoers.d" \
        "${guest_root}/etc/ssh/sshd_config.d" \
        "${guest_root}/home/vmadmin/.ssh" \
        "${guest_root}/run/cloud-provision" \
        "${guest_root}/usr/bin" \
        "${guest_root}/usr/sbin"
    chmod 0755 \
        "${guest_root}/etc" \
        "${guest_root}/etc/profile.d" \
        "${guest_root}/etc/apt/apt.conf.d" \
        "${guest_root}/etc/dnf" \
        "${guest_root}/etc/sudoers.d" \
        "${guest_root}/etc/ssh" \
        "${guest_root}/etc/ssh/sshd_config.d" \
        "${guest_root}/run" \
        "${guest_root}/run/cloud-provision"
    chmod 0700 "${guest_root}/home/vmadmin/.ssh"
    printf 'root:x:0:0:root:/root:/bin/bash\n' > "${guest_root}/etc/passwd"
    printf 'vmadmin:x:%s:%s::/home/vmadmin:/bin/bash\n' \
        "$(id -u)" "$(id -g)" >> "${guest_root}/etc/passwd"
    printf 'ID=%s\n' "${os_family}" > "${guest_root}/etc/os-release"
    printf 'LANG=C\n' > "${guest_root}/etc/environment"
    chmod 0640 "${guest_root}/etc/environment"
    printf '[user]\n    name = Proxy Test\n' > "${guest_root}/etc/gitconfig"
    chmod 0600 "${guest_root}/etc/gitconfig"
    if [[ "${os_family}" == rocky ]]; then
        printf '[main]\ngpgcheck=1\n' > "${guest_root}/etc/dnf/dnf.conf"
        chmod 0640 "${guest_root}/etc/dnf/dnf.conf"
        printf 'Port 22\nMatch User nobody\n    X11Forwarding no\n' \
            > "${guest_root}/etc/ssh/sshd_config"
    else
        printf 'Include /etc/ssh/sshd_config.d/*.conf\nPort 22\n' \
            > "${guest_root}/etc/ssh/sshd_config"
    fi
    chmod 0644 "${guest_root}/etc/ssh/sshd_config"

    extract_yaml_literal "${capture_file}" \
        "/run/cloud-provision/proxy_contract.bash" \
        "${guest_root}/run/cloud-provision/proxy_contract.bash"
    extract_yaml_literal "${capture_file}" \
        "/run/cloud-provision/proxy-contract.input" \
        "${guest_root}/run/cloud-provision/proxy-contract.input"
    chmod 0700 "${guest_root}/run/cloud-provision/proxy_contract.bash"
    chmod 0600 "${guest_root}/run/cloud-provision/proxy-contract.input"
    write_guest_commands "${guest_root}"
    if [[ "${name}" == debian-proxy ]]; then
        cp -a -- "${guest_root}" "${guest_root}.before-apply"
    fi

    env \
        "PROXY_GUEST_ROOT=${guest_root}" \
        "PROXY_GUEST_COMMAND_LOG=${command_log}" \
        "${guest_root}/run/cloud-provision/proxy_contract.bash" \
        --test-root "${guest_root}" apply > "${output_file}" 2>&1 || rc=$?
    expect_exit "${name} staged apply succeeds" 0 "${rc}"
    if [[ "${rc}" != 0 ]]; then
        return 0
    fi
    verify_applied_artifacts "${name}" "${os_family}" "${guest_root}"
    expect_contains "${name} preserves existing environment content" \
        "${guest_root}/etc/environment" 'LANG=C'
    expect_contains "${name} preserves existing Git content" \
        "${guest_root}/etc/gitconfig" 'name = Proxy Test'
    expect_contains "${name} reloads sshd through the guest command" \
        "${command_log}" 'systemctl reload'
    if grep -Fq 'proxy.example.test:3128' "${output_file}"; then
        record_fail "${name} keeps the endpoint out of apply output" \
            "the staged apply printed the proxy endpoint"
    else
        record_pass "${name} keeps the endpoint out of apply output"
    fi
    if [[ "${os_family}" == rocky ]]; then
        begin_line="$(grep -nF '# BEGIN CLOUD-PROVISION PROXY CONTRACT' \
            "${guest_root}/etc/ssh/sshd_config" | cut -d: -f1)"
        match_line="$(grep -nE '^[[:space:]]*Match[[:space:]]+' \
            "${guest_root}/etc/ssh/sshd_config" | cut -d: -f1)"
        if [[ "${begin_line}" =~ ^[0-9]+$ && "${match_line}" =~ ^[0-9]+$ &&
              "${begin_line}" -lt "${match_line}" ]]; then
            record_pass "${name} places the sshd block before Match"
        else
            record_fail "${name} places the sshd block before Match" \
                "the contract block is not in the global sshd scope"
        fi
    fi
}

function run_shared_newline_boundary_case {
    local guest_root="${WORKSPACE}/debian-proxy.guest-root.before-apply"
    local output_file="${WORKSPACE}/shared-newline-boundary.log"
    local rc=0

    printf '%s' 'LANG=C' > "${guest_root}/etc/environment"
    env \
        "PROXY_GUEST_ROOT=${guest_root}" \
        "PROXY_GUEST_COMMAND_LOG=${WORKSPACE}/shared-newline-commands.log" \
        "${guest_root}/run/cloud-provision/proxy_contract.bash" \
        --test-root "${guest_root}" apply > "${output_file}" 2>&1 || rc=$?
    expect_exit "shared file without final newline is rejected" 1 "${rc}"
    expect_contains "shared file rejection names the boundary" \
        "${output_file}" "shared file must end with a newline"
    if [[ ! -e "${guest_root}/run/cloud-provision/proxy-contract.lock" ]] &&
       [[ ! -e "${guest_root}/etc/profile.d/95cloud-provision-proxy.sh" ]] &&
       ! grep -Fq 'CLOUD-PROVISION PROXY CONTRACT' \
        "${guest_root}/etc/environment"; then
        record_pass "shared newline rejection leaves the artifact set unchanged"
    else
        record_fail "shared newline rejection leaves the artifact set unchanged" \
            "apply created contract state after preflight rejection"
    fi
}

function run_missing_guest_command_case {
    local name="$1"
    local guest_root="${WORKSPACE}/${name}.guest-root"
    local output_file="${WORKSPACE}/${name}.missing-cloud-init.log"
    local sentinel="${WORKSPACE}/${name}.host-cloud-init-called"
    local rc=0

    env \
        "PATH=${FAKEBIN}:${ORIGINAL_PATH}" \
        "PROXY_HOST_COMMAND_SENTINEL=${sentinel}" \
        "PROXY_GUEST_ROOT=${guest_root}" \
        "PROXY_GUEST_COMMAND_LOG=${WORKSPACE}/${name}.guest-commands.log" \
        "${guest_root}/run/cloud-provision/proxy_contract.bash" \
        --test-root "${guest_root}" seal > "${output_file}" 2>&1 || rc=$?
    expect_exit "${name} rejects a missing exact guest cloud-init" 1 "${rc}"
    expect_contains "${name} names the missing exact guest command" \
        "${output_file}" "requires exact guest command /usr/bin/cloud-init"
    if [[ ! -e "${sentinel}" ]] &&
       grep -Fq '# BEGIN CLOUD-PROVISION PROXY CONTRACT' \
        "${guest_root}/etc/profile.d/95cloud-provision-proxy.sh" &&
       [[ -f "${guest_root}/run/cloud-provision/proxy-contract.lock" ]]; then
        record_pass "${name} does not fall back to host commands or mutate artifacts"
    else
        record_fail "${name} does not fall back to host commands or mutate artifacts" \
            "the host sentinel ran or seal changed the applied set"
    fi
}

function run_identity_symlink_cases {
    local name="$1"
    local root="${WORKSPACE}/${name}.identity-root"
    local out rc

    # Mirror resolute's sudo-rs layout: visudo is a relative symlink chain
    # through /etc/alternatives to a regular executable, all inside the root.
    mkdir -p "${root}/usr/sbin" "${root}/etc/alternatives" \
        "${root}/usr/lib/cargo/bin"
    printf '#!/bin/sh\n' > "${root}/usr/lib/cargo/bin/visudo"
    chmod 0755 "${root}/usr/lib/cargo/bin/visudo"
    ln -s ../../usr/lib/cargo/bin/visudo "${root}/etc/alternatives/visudo"
    ln -s ../../etc/alternatives/visudo "${root}/usr/sbin/visudo"

    rc=0
    out="$(bash -c 'source "$1"; PROXY_CONTRACT_ROOT="$2"; \
        proxy_contract_resolve_guest_command visudo RESOLVED && \
        printf "%s\n" "${RESOLVED}"' \
        resolve "${TOP}/bin/proxy_contract.bash" "${root}" 2>&1)" || rc=$?
    if [[ "${rc}" == 0 && "${out}" == *"/usr/lib/cargo/bin/visudo" ]] &&
       [[ -f "${out}" && -x "${out}" ]]; then
        record_pass "${name} accepts an in-root relative symlink identity command"
    else
        record_fail "${name} accepts an in-root relative symlink identity command" \
            "rc=${rc} out=${out}"
    fi

    # Symlink through a missing intermediate directory: readlink -f cannot
    # canonicalize it, so resolution is impossible; fail closed.
    ln -sf ../../usr/lib/nodir/visudo "${root}/usr/sbin/visudo"
    rc=0
    out="$(bash -c 'source "$1"; PROXY_CONTRACT_ROOT="$2"; \
        proxy_contract_resolve_guest_command visudo RESOLVED' \
        resolve "${TOP}/bin/proxy_contract.bash" "${root}" 2>&1)" || rc=$?
    if [[ "${rc}" != 0 ]] && grep -Fq 'does not resolve' <<< "${out}"; then
        record_pass "${name} rejects a symlink through a missing directory"
    else
        record_fail "${name} rejects a symlink through a missing directory" \
            "rc=${rc} out=${out}"
    fi

    # Symlink to an absent in-root target: the resolved path is not a regular
    # executable; fail closed.
    ln -sf ../../usr/lib/cargo/bin/absent "${root}/usr/sbin/visudo"
    rc=0
    out="$(bash -c 'source "$1"; PROXY_CONTRACT_ROOT="$2"; \
        proxy_contract_resolve_guest_command visudo RESOLVED' \
        resolve "${TOP}/bin/proxy_contract.bash" "${root}" 2>&1)" || rc=$?
    if [[ "${rc}" != 0 ]] && grep -Fq 'requires exact guest command' <<< "${out}"; then
        record_pass "${name} rejects a symlink to an absent target"
    else
        record_fail "${name} rejects a symlink to an absent target" \
            "rc=${rc} out=${out}"
    fi

    # Absolute symlink whose target leaves the root: fail closed on escape.
    ln -sf /bin/sh "${root}/usr/sbin/visudo"
    rc=0
    out="$(bash -c 'source "$1"; PROXY_CONTRACT_ROOT="$2"; \
        proxy_contract_resolve_guest_command visudo RESOLVED' \
        resolve "${TOP}/bin/proxy_contract.bash" "${root}" 2>&1)" || rc=$?
    if [[ "${rc}" != 0 ]] && grep -Fq 'escapes the selected root' <<< "${out}"; then
        record_pass "${name} rejects an escaping absolute symlink identity command"
    else
        record_fail "${name} rejects an escaping absolute symlink identity command" \
            "rc=${rc} out=${out}"
    fi
}

function expect_renderer_rejects_shell_active {
    local name="$1"
    local active_character="$2"
    local proxy_url="http://proxy.example.test:3128/path${active_character}segment"
    local output_file="${WORKSPACE}/renderer-${name}.log"
    local rc=0

    bash -c 'source "$1"; proxy_contract_render_write_files debian13 "$2"' \
        proxy-render "${TOP}/bin/proxy_contract.bash" "${proxy_url}" \
        > "${output_file}" 2>&1 || rc=$?
    if [[ "${rc}" != "0" ]] &&
       grep -Fq 'received an invalid proxy URL' "${output_file}" &&
       ! grep -Fq -- "${proxy_url}" "${output_file}"; then
        record_pass "renderer rejects ${name} without recording the value"
    else
        record_fail "renderer rejects ${name} without recording the value" \
            "renderer accepted the character or exposed the rejected scalar"
    fi
}

function prepare_verify_root {
    local root_path="$1"

    mkdir -p "${root_path}/etc" "${root_path}/usr/lib"
    chmod 0755 "${root_path}/etc" "${root_path}/usr" "${root_path}/usr/lib"
    printf 'root:x:0:0:root:/root:/bin/bash\n' > "${root_path}/etc/passwd"
    printf 'vmadmin:x:%s:%s::/home/vmadmin:/bin/bash\n' \
        "$(id -u)" "$(id -g)" >> "${root_path}/etc/passwd"
}

function run_verify_root_case {
    local name="$1"
    local root_path="$2"
    local expected_exit="$3"
    local expected_text="${4:-}"
    local output_file="${WORKSPACE}/${name}.verify-root.log"
    local rc=0

    "${TOP}/bin/proxy_contract.bash" \
        --test-root "${root_path}" verify clean > "${output_file}" 2>&1 || rc=$?
    expect_exit "${name}" "${expected_exit}" "${rc}"
    if [[ -n "${expected_text}" ]]; then
        expect_contains "${name} reports the rejected boundary" \
            "${output_file}" "${expected_text}"
    fi
}

function run_os_release_boundary_cases {
    local case_root

    case_root="${WORKSPACE}/os-release-regular"
    prepare_verify_root "${case_root}"
    printf 'ID=debian\n' > "${case_root}/etc/os-release"
    run_verify_root_case "regular os-release is accepted" "${case_root}" 0

    case_root="${WORKSPACE}/os-release-relative-link"
    prepare_verify_root "${case_root}"
    printf 'ID=rocky\n' > "${case_root}/usr/lib/os-release"
    ln -s ../usr/lib/os-release "${case_root}/etc/os-release"
    run_verify_root_case "safe relative os-release link is accepted" "${case_root}" 0

    case_root="${WORKSPACE}/os-release-absolute-link"
    prepare_verify_root "${case_root}"
    printf 'ID=debian\n' > "${case_root}/usr/lib/os-release"
    ln -s /usr/lib/os-release "${case_root}/etc/os-release"
    run_verify_root_case "absolute os-release link is rejected" \
        "${case_root}" 1 "unsafe symbolic link"

    case_root="${WORKSPACE}/os-release-dangling-link"
    prepare_verify_root "${case_root}"
    ln -s ../usr/lib/missing-os-release "${case_root}/etc/os-release"
    run_verify_root_case "dangling os-release link is rejected" \
        "${case_root}" 1 "cannot read a regular /etc/os-release"

    case_root="${WORKSPACE}/os-release-escaping-link"
    prepare_verify_root "${case_root}"
    printf 'ID=debian\n' > "${WORKSPACE}/outside-os-release"
    ln -s ../../outside-os-release "${case_root}/etc/os-release"
    run_verify_root_case "escaping os-release link is rejected" \
        "${case_root}" 1 "escapes the selected root"

    case_root="${WORKSPACE}/os-release-parent-link"
    prepare_verify_root "${case_root}"
    mv "${case_root}/usr/lib" "${case_root}/usr/lib-real"
    printf 'ID=debian\n' > "${case_root}/usr/lib-real/os-release"
    ln -s lib-real "${case_root}/usr/lib"
    ln -s ../usr/lib/os-release "${case_root}/etc/os-release"
    run_verify_root_case "parent os-release link is rejected" \
        "${case_root}" 1 "parent symbolic link"

    case_root="${WORKSPACE}/os-release-duplicate-id"
    prepare_verify_root "${case_root}"
    printf 'ID=debian\nID=ubuntu\n' > "${case_root}/etc/os-release"
    run_verify_root_case "duplicate os-release ID is rejected" \
        "${case_root}" 1 "exactly one ID field"

    case_root="${WORKSPACE}/os-release-invalid-id"
    prepare_verify_root "${case_root}"
    printf 'ID=Debian\n' > "${case_root}/etc/os-release"
    run_verify_root_case "invalid os-release ID is rejected" \
        "${case_root}" 1 "invalid ID field"

    case_root="${WORKSPACE}/os-release-unsupported-id"
    prepare_verify_root "${case_root}"
    printf 'ID=fedora\n' > "${case_root}/etc/os-release"
    run_verify_root_case "unsupported os-release ID is rejected" \
        "${case_root}" 1 "does not support OS identity"
}

function run_test_root_boundary_cases {
    local real_root="${WORKSPACE}/selected-root"
    local linked_root="${WORKSPACE}/selected-root-link"

    prepare_verify_root "${real_root}"
    printf 'ID=debian\n' > "${real_root}/etc/os-release"
    ln -s "${real_root}" "${linked_root}"
    run_verify_root_case "selected root symlink is rejected" \
        "${linked_root}" 1 "existing absolute directory"
    run_verify_root_case "slash test root is rejected" \
        / 1 "must not resolve to the production root"
    run_verify_root_case "double-slash test root is rejected" \
        // 1 "must not resolve to the production root"
    run_verify_root_case "dot test root is rejected" \
        /./ 1 "must not resolve to the production root"
    run_verify_root_case "parent-component test root is rejected" \
        /tmp/.. 1 "must not resolve to the production root"
}

function run_case {
    local label="$1"
    local os_type="$2"
    local proxy_count="$3"
    local case_dir="${WORKSPACE}/${label}"
    local image_dir="${case_dir}/images"
    local proxy_dir="${case_dir}/proxy"
    local home_dir="${case_dir}/home"
    local output_file="${case_dir}/output.log"
    local capture_file="${case_dir}/user-data"
    local curl_log="${case_dir}/curl.log"
    local virt_install_log="${case_dir}/virt-install.log"
    local active_character=""
    local rc=0

    mkdir -p "${image_dir}" "${home_dir}/.ssh" "${proxy_dir}"
    printf "%s\n" "ssh-ed25519 AAAAproxy-test-key" \
        > "${home_dir}/.ssh/id_ed25519.pub"

    if [[ "${proxy_count}" == "one" ]]; then
        write_proxy_fixture "${proxy_dir}" "alsu-proxy.sh"
    elif [[ "${proxy_count}" == "multiple" ]]; then
        write_proxy_fixture "${proxy_dir}" "first-proxy.sh"
        write_proxy_fixture "${proxy_dir}" "second-proxy.sh"
    elif [[ "${proxy_count}" == "shell-active" ]]; then
        printf -v active_character '%b' '\044'
        write_proxy_fixture "${proxy_dir}" "active-proxy.sh" \
            "http://proxy.example.test:3128/path${active_character}segment"
    fi

    env \
        "PATH=${FAKEBIN}:${ORIGINAL_PATH}" \
        "HOME=${home_dir}" \
        "USER=testuser" \
        "REQUIRED_GROUP=nogroup" \
        "PROXY_SOURCE_DIR=${proxy_dir}" \
        "FAKE_BASE_IMAGE=${BASE_FIXTURE}" \
        "FAKE_CAPTURE_USER_DATA=${capture_file}" \
        "FAKE_CURL_LOG=${curl_log}" \
        "FAKE_VIRT_INSTALL_LOG=${virt_install_log}" \
        VM_WAIT_SSH_ATTEMPTS=1 \
        VM_WAIT_CLOUD_INIT_ATTEMPTS=1 \
        "${TOP}/bin/create_vm.bash" \
        -o "${os_type}" -n main -d "${image_dir}" -p "proxy-${label}" \
        > "${output_file}" 2>&1 || rc=$?

    if [[ "${proxy_count}" == "multiple" ]]; then
        expect_exit "${label} rejects multiple proxy files" 1 "${rc}"
        expect_contains "${label} reports ambiguous proxy input" \
            "${output_file}" "multiple proxy files found"
        if [[ ! -s "${curl_log}" ]]; then
            record_pass "${label} rejects before downloading the base image"
        else
            record_fail "${label} rejects before downloading the base image" \
                "the base image download boundary was called"
        fi
        return 0
    fi

    if [[ "${proxy_count}" == "shell-active" ]]; then
        expect_exit "${label} rejects shell-active proxy input as data" 1 "${rc}"
        expect_contains "${label} reports value-free proxy rejection" \
            "${output_file}" "received an invalid proxy URL"
        if [[ ! -s "${curl_log}" ]] && [[ ! -e "${capture_file}" ]]; then
            record_pass "${label} rejects before seed generation and download"
        else
            record_fail "${label} rejects before seed generation and download" \
                "an outer boundary ran after the rejected scalar"
        fi
        return 0
    fi

    expect_exit "${label} provisioning succeeds" 0 "${rc}"
    if [[ ! -f "${capture_file}" ]]; then
        record_fail "${label} captures generated user-data" "capture file is missing"
        return 0
    fi

    if [[ "${proxy_count}" == "none" ]]; then
        expect_not_contains "${label} has no proxy write_files block" \
            "${capture_file}" "write_files:"
        expect_contains "${label} installs locale support" \
            "${capture_file}" "  - locales"
        expect_contains "${label} enables en_US.UTF-8 generation" \
            "${capture_file}" "  - [sed, -i, 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/', /etc/locale.gen]"
        expect_contains "${label} generates en_US.UTF-8" \
            "${capture_file}" "  - [locale-gen, en_US.UTF-8]"
        expect_contains "${label} sets the default locale" \
            "${capture_file}" "  - [update-locale, LANG=en_US.UTF-8]"
        expect_contains "${label} carries the locale self-check" \
            "${capture_file}" "en_US.utf8 ||"
        return 0
    fi

    expect_exact_artifact_set "${label}" "${os_type}" "${capture_file}"
    expect_not_contains "${label} drops the cloud-init packages directive" \
        "${capture_file}" "packages:"
    expect_not_contains "${label} drops the packages locale entry" \
        "${capture_file}" "  - locales"
    if [[ "${os_type}" != rocky* ]]; then
        expect_contains "${label} preserves locale generation" \
            "${capture_file}" \
            "  - [sed, -i, 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/', /etc/locale.gen]"
        expect_contains "${label} preserves locale-gen" \
            "${capture_file}" "  - [locale-gen, en_US.UTF-8]"
        expect_contains "${label} preserves update-locale" \
            "${capture_file}" "  - [update-locale, LANG=en_US.UTF-8]"
        expect_contains "${label} preserves the locale self-check" \
            "${capture_file}" "en_US.utf8 ||"
    fi

    case "${label}" in
        debian-proxy) run_staged_apply "${label}" debian "${capture_file}" ;;
        rocky-proxy) run_staged_apply "${label}" rocky "${capture_file}" ;;
    esac

    if grep -Fq -- "proxy.example.test:3128" "${output_file}"; then
        record_fail "${label} keeps the endpoint out of command output" \
            "the proxy endpoint was printed"
    else
        record_pass "${label} keeps the endpoint out of command output"
    fi
}

mkdir -p "${FAKEBIN}"
write_fake_commands
qemu-img create -f qcow2 "${BASE_FIXTURE}" 32M >/dev/null

run_case no-proxy debian13 none
run_case ubuntu24-locale ubuntu24 none
run_case ubuntu26-locale ubuntu26 none
run_case debian-proxy debian13 one
# Offline locale-contract lint over the debian-family template files directly.
# A template that keeps the locale-gen runcmd must also carry the `locales`
# package entry (so a non-proxy boot installs it) and the first-boot self-check
# (so a proxy boot on a base image lacking locale support fails loudly instead
# of silently). This is a pure file lint reading the template path; it does not
# run create_vm.
function template_locale_contract_ok {
    local template="$1"
    local last_list_item

    grep -Fq '  - locales' "${template}" || return 1
    grep -Fq '  - [locale-gen, en_US.UTF-8]' "${template}" || return 1
    grep -Fq 'en_US.utf8 ||' "${template}" || return 1
    # The self-check must be the LAST list item in the template. cloud-init
    # flattens runcmd into one set-e-less sh script whose exit status is only
    # its last line, so a runcmd appended after the self-check would keep it
    # printing to stderr while the script still exits 0 - the bake would pass
    # silently. The self-check is the final runcmd entry and runcmd is the last
    # list-bearing block, so it must be the last `  - ` line in the file.
    last_list_item="$(grep '^  - ' "${template}" | tail -n 1)"
    [[ "${last_list_item}" == *'en_US.utf8 ||'* ]] || return 1
    return 0
}

function run_template_locale_contract {
    local template scratch drop

    for template in debian13 ubuntu24 ubuntu26; do
        if template_locale_contract_ok "${TOP}/templates/user-data.${template}"; then
            record_pass "template ${template} keeps the full locale contract"
        else
            record_fail "template ${template} keeps the full locale contract" \
                "a shipped debian-family template is missing part of the locale contract"
        fi
    done

    for drop in locales locale-gen self-check; do
        scratch="${WORKSPACE}/contract-drop-${drop}.user-data"
        cp "${TOP}/templates/user-data.debian13" "${scratch}"
        case "${drop}" in
            locales)    sed -i '/^  - locales$/d' "${scratch}" ;;
            locale-gen) sed -i '/locale-gen, en_US.UTF-8/d' "${scratch}" ;;
            self-check) sed -i '/en_US.utf8 ||/d' "${scratch}" ;;
        esac
        if template_locale_contract_ok "${scratch}"; then
            record_fail "locale contract catches a missing ${drop}" \
                "the lint accepted a template with ${drop} removed"
        else
            record_pass "locale contract catches a missing ${drop}"
        fi
    done

    # A runcmd item appended after the self-check defeats it: the appended line
    # becomes the script's last, so its zero exit masks the self-check failure.
    scratch="${WORKSPACE}/contract-appended-runcmd.user-data"
    cp "${TOP}/templates/user-data.debian13" "${scratch}"
    sed -i '/en_US.utf8 ||/a\  - [true]' "${scratch}"
    if template_locale_contract_ok "${scratch}"; then
        record_fail "locale contract catches a runcmd after the self-check" \
            "the lint accepted a template with a runcmd item after the self-check"
    else
        record_pass "locale contract catches a runcmd after the self-check"
    fi
}

run_case ubuntu-proxy ubuntu24 one
run_case rocky-proxy rocky8 one
run_case multiple-proxy debian13 multiple
run_case shell-active-proxy debian13 shell-active

run_missing_guest_command_case debian-proxy
run_identity_symlink_cases identity-symlink
run_hostile_environment_lifecycle
run_shared_newline_boundary_case

printf -v active_character '%b' '\044'
expect_renderer_rejects_shell_active "parameter expansion introducer" "${active_character}"
printf -v active_character '%b' '\140'
expect_renderer_rejects_shell_active "command substitution introducer" "${active_character}"
printf -v active_character '%b' '\041'
expect_renderer_rejects_shell_active "history expansion introducer" "${active_character}"

run_os_release_boundary_cases
run_test_root_boundary_cases
run_template_locale_contract

printf "Summary: %s passed / %s total\n" "${TEST_PASSED}" "${TEST_TOTAL}"
if [[ "${TEST_FAILED}" -gt 0 ]]; then
    printf "Failures:\n" >&2
    printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
    exit 1
fi
