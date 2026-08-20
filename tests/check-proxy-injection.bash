#!/usr/bin/env bash
#
# Verifies proxy discovery and cloud-init injection through the public
# create_vm.bash provisioning path.
#
# The shipped provisioner and image workflow execute for real. Only external
# boundaries are replaced: curl, virsh, virt-install, genisoimage, ssh, and
# groups. The captured user-data is the actual seed input produced by the
# provisioner before the ISO boundary.

set -euo pipefail

declare -g SCRIPT_DIR
declare -g TOP
declare -g WORKSPACE
declare -g FAKEBIN
declare -g BASE_FIXTURE
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

    chmod +x "${FAKEBIN}"/*
}

function write_proxy_fixture {
    local proxy_dir="$1"
    local file_name="$2"

    mkdir -p "${proxy_dir}"
    printf '%s\n' \
        'PROXY_URL="http://proxy.example.test:3128/"' \
        "export http_proxy=\"\$PROXY_URL\"" \
        "export https_proxy=\"\$PROXY_URL\"" \
        "export ftp_proxy=\"\$PROXY_URL\"" \
        'export no_proxy="127.0.0.1,localhost"' \
        "export HTTP_PROXY=\"\$PROXY_URL\"" \
        "export HTTPS_PROXY=\"\$PROXY_URL\"" \
        "export FTP_PROXY=\"\$PROXY_URL\"" \
        "export NO_PROXY=\"\$no_proxy\"" > "${proxy_dir}/${file_name}"
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
    local rc=0

    mkdir -p "${image_dir}" "${home_dir}/.ssh" "${proxy_dir}"
    printf "%s\n" "ssh-ed25519 AAAAproxy-test-key" \
        > "${home_dir}/.ssh/id_ed25519.pub"

    if [[ "${proxy_count}" == "one" ]]; then
        write_proxy_fixture "${proxy_dir}" "alsu-proxy.sh"
    elif [[ "${proxy_count}" == "multiple" ]]; then
        write_proxy_fixture "${proxy_dir}" "first-proxy.sh"
        write_proxy_fixture "${proxy_dir}" "second-proxy.sh"
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
        -o "${os_type}" -n server -d "${image_dir}" -p "proxy-${label}" \
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
        return 0
    fi

    expect_contains "${label} copies the selected profile script" \
        "${capture_file}" "/etc/profile.d/alsu-proxy.sh"
    expect_contains "${label} preserves the profile script content" \
        "${capture_file}" "export http_proxy=\"\$PROXY_URL\""
    expect_contains "${label} writes the Git HTTP proxy setting" \
        "${capture_file}" 'proxy = http://proxy.example.test:3128/'

    if [[ "${os_type}" == "rocky8" ]]; then
        expect_contains "${label} writes the DNF proxy setting" \
            "${capture_file}" 'proxy=http://proxy.example.test:3128/'
        expect_not_contains "${label} omits the Debian APT file" \
            "${capture_file}" "/etc/apt/apt.conf.d/95cloud-provision-proxy"
    else
        expect_contains "${label} writes the HTTP proxy setting" \
            "${capture_file}" 'Acquire::http::Proxy "http://proxy.example.test:3128/";'
        expect_contains "${label} writes the HTTPS proxy setting" \
            "${capture_file}" 'Acquire::https::Proxy "http://proxy.example.test:3128/";'
        expect_not_contains "${label} omits the Rocky DNF file" \
            "${capture_file}" "/etc/dnf/dnf.conf"
    fi

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
run_case ubuntu24-locale epics-env-ubuntu24 none
run_case ubuntu26-locale epics-env-ubuntu26 none
run_case debian-proxy debian13 one
run_case rocky-proxy rocky8 one
run_case multiple-proxy debian13 multiple

printf "Summary: %s passed / %s total\n" "${TEST_PASSED}" "${TEST_TOTAL}"
if [[ "${TEST_FAILED}" -gt 0 ]]; then
    printf "Failures:\n" >&2
    printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
    exit 1
fi
