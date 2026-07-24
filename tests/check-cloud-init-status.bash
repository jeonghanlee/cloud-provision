#!/usr/bin/env bash
#
# Verifies cloud-init status handling through public create_vm.bash actions.

set -e

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

function cleanup {
    local rc=$?
    if [[ -n "${WORKSPACE:-}" && -d "${WORKSPACE}" ]]; then
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

function expect_exit {
    local name="$1"
    local want="$2"
    local got="$3"

    if [[ "${got}" == "${want}" ]]; then
        record_pass "${name}"
    else
        record_fail "${name}" "expected exit ${want}, got ${got}"
    fi
}

function expect_contains {
    local name="$1"
    local haystack="$2"
    local needle="$3"

    if [[ "${haystack}" == *"${needle}"* ]]; then
        record_pass "${name}"
    else
        record_fail "${name}" "missing output: ${needle}"
    fi
}

function write_fake_commands {
    cat > "${FAKEBIN}/virsh" <<'EOF'
#!/usr/bin/env bash
set -e
cmd=""
for arg in "$@"; do
    case "$arg" in
        domstate|dominfo|domifaddr|net-update|start|shutdown|destroy|undefine)
            cmd="$arg"
            break
            ;;
    esac
done
case "$cmd" in
    domstate)
        printf "%s\n" "${FAKE_DOMAIN_STATE:-running}"
        ;;
    dominfo)
        exit "${FAKE_DOMINFO_RC:-1}"
        ;;
    domifaddr)
        printf " vnet0 52:54:00:00:64:00 ipv4 192.168.122.100/24\n"
        ;;
    net-update|start|shutdown|destroy|undefine)
        ;;
    *)
        printf "unexpected virsh command: %s\n" "$*" >&2
        exit 2
        ;;
esac
EOF

    cat > "${FAKEBIN}/ssh" <<'EOF'
#!/usr/bin/env bash
set -e
remote_cmd="${@: -1}"
case "${remote_cmd}" in
    exit)
        exit 0
        ;;
    "cloud-init status")
        printf "%s" "${FAKE_CLOUD_INIT_STATUS_OUTPUT:-}"
        exit "${FAKE_CLOUD_INIT_STATUS_RC:-0}"
        ;;
    *)
        printf "unexpected ssh command: %s\n" "${remote_cmd}" >&2
        exit 2
        ;;
esac
EOF
    chmod +x "${FAKEBIN}/virsh" "${FAKEBIN}/ssh"
}

function run_create_vm {
    local status_output="$1"
    local action="$2"
    local output_file="${WORKSPACE}/output.txt"
    local rc=0
    local domain_state="running"
    local dominfo_rc=1
    local -a args=("-o" "rocky8" "-n" "server" "-d" "${WORKSPACE}/images")

    if [[ "${action}" == "status" ]]; then
        args+=("-s")
    else
        domain_state="shut off"
        dominfo_rc=0
    fi

    FAKE_CLOUD_INIT_STATUS_OUTPUT="${status_output}" \
    FAKE_DOMAIN_STATE="${domain_state}" \
    FAKE_DOMINFO_RC="${dominfo_rc}" \
    PATH="${FAKEBIN}:${PATH}" \
    HOME="${WORKSPACE}/home" \
    REQUIRED_GROUP="$(id -gn)" \
    "${TOP}/bin/create_vm.bash" "${args[@]}" > "${output_file}" 2>&1 || rc=$?

    printf "%s\n" "${rc}"
    cat "${output_file}"
}

function run_case {
    local name="$1"
    local status_output="$2"
    local action="$3"
    local want_rc="$4"
    local want_text="$5"
    local result
    local rc
    local output

    result=$(run_create_vm "${status_output}" "${action}")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    expect_exit "${name} exit" "${want_rc}" "${rc}"
    expect_contains "${name} output" "${output}" "${want_text}"
}

function print_summary {
    printf "Summary: %s passed / %s total\n" "${TEST_PASSED}" "${TEST_TOTAL}"
    if [[ ${TEST_FAILED} -gt 0 ]]; then
        printf "Failures:\n" >&2
        printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
        return 1
    fi
    return 0
}

WORKSPACE="$(mktemp -d /tmp/cloud-init-status-test.XXXXXX)"
FAKEBIN="${WORKSPACE}/bin"
mkdir -p "${FAKEBIN}"
write_fake_commands

run_case "status done" $'status: done\n' "status" 0 "cloud-init : done"
run_case "status running" $'status: running\n' "status" 1 "cloud-init : running"
run_case "status malformed" $'done but no status field\n' "status" 1 "cloud-init : unknown"
run_case "provision done" $'status: done\n' "provision" 0 "cloud-init: complete [OK]"

print_summary
