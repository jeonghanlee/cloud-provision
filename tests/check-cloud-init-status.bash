#!/usr/bin/env bash
#
# Verifies cloud-init status handling through public create_vm.bash actions.
#
# Replaced command boundary: virsh, ssh, sleep. No production line changes.
# virsh and ssh are the external boundaries the script talks to. sleep is the
# clock boundary, replaced so the readiness retry budget runs in near-zero wall
# time; the retry loop, the shared parser, and the branch logic all execute for
# real.
#
# Readiness entry point: the readiness cases enter through the shut-off restart
# branch at bin/create_vm.bash:795, not the fresh-provision branch at :828,
# which needs a base image, a disk, a seed, and virt-install. Both call sites
# pass "retry" to the same wait_for_vm, so the covered code is the same.
#
# What the rejection cases pin: in retry mode wait_for_cloud_init never prints
# the parsed status, so "status: running" and a malformed status produce
# identical output. The two cases pin that neither input is accepted as done.
# The running-versus-unknown distinction stays with the -s status cases below.

set -e

declare -g SCRIPT_DIR
declare -g TOP
declare -g WORKSPACE
declare -g FAKEBIN
declare -g SLEEP_LOG
declare -g SSH_ARG_LOG
declare -g QEMU_IMG_LOG
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

function expect_not_contains {
    local name="$1"
    local haystack="$2"
    local needle="$3"

    if [[ "${haystack}" != *"${needle}"* ]]; then
        record_pass "${name}"
    else
        record_fail "${name}" "unexpected output: ${needle}"
    fi
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

function write_fake_commands {
    cat > "${FAKEBIN}/virsh" <<'EOF'
#!/usr/bin/env bash
set -e
cmd=""
for arg in "$@"; do
    case "$arg" in
        domstate|dominfo|domifaddr|net-update|net-dumpxml|start|shutdown|destroy|undefine|uri)
            cmd="$arg"
            break
            ;;
    esac
done
# FAKE_LIBVIRT_DOWN makes every command fail the way an unreachable libvirt
# does: domstate and uri both exit non-zero, which is the pair get_domain_state
# uses to tell an outage from an absent domain.
if [[ "${FAKE_LIBVIRT_DOWN:-}" == "1" ]]; then
    printf "error: failed to connect to the hypervisor\n" >&2
    exit 1
fi
case "$cmd" in
    uri)
        printf "%s\n" "qemu:///system"
        ;;
    domstate)
        if [[ "${FAKE_DOMAIN_STATE:-running}" == "absent" ]]; then
            printf "error: failed to get domain\n" >&2
            exit 1
        fi
        # A domain that was asked to shut down reports "shut off" from then on,
        # unless the case asked for one that never obeys.
        if [[ -n "${FAKE_SHUTDOWN_MARKER:-}" && -e "${FAKE_SHUTDOWN_MARKER}" ]]; then
            count=0
            if [[ -n "${FAKE_SHUTDOWN_COUNT_FILE:-}" && -f "${FAKE_SHUTDOWN_COUNT_FILE}" ]]; then
                read -r count < "${FAKE_SHUTDOWN_COUNT_FILE}"
            fi
            count=$((count + 1))
            if [[ -n "${FAKE_SHUTDOWN_COUNT_FILE:-}" ]]; then
                printf "%s\n" "${count}" > "${FAKE_SHUTDOWN_COUNT_FILE}"
            fi
            if [[ "${count}" -ge "${FAKE_SHUTDOWN_READY_AFTER:-1}" ]]; then
                printf "shut off\n"
            else
                printf "running\n"
            fi
            exit 0
        fi
        printf "%s\n" "${FAKE_DOMAIN_STATE:-running}"
        ;;
    dominfo)
        exit "${FAKE_DOMINFO_RC:-1}"
        ;;
    domifaddr)
        count=0
        if [[ -n "${FAKE_DOMIFADDR_COUNT_FILE:-}" && -f "${FAKE_DOMIFADDR_COUNT_FILE}" ]]; then
            read -r count < "${FAKE_DOMIFADDR_COUNT_FILE}"
        fi
        count=$((count + 1))
        if [[ -n "${FAKE_DOMIFADDR_COUNT_FILE:-}" ]]; then
            printf "%s\n" "${count}" > "${FAKE_DOMIFADDR_COUNT_FILE}"
        fi
        if [[ "${count}" -ge "${FAKE_DOMIFADDR_READY_AFTER:-1}" ]]; then
            printf " vnet0 52:54:00:00:64:00 ipv4 192.168.122.100/24\n"
        fi
        ;;
    shutdown)
        if [[ -n "${FAKE_SHUTDOWN_MARKER:-}" ]]; then
            : > "${FAKE_SHUTDOWN_MARKER}"
        fi
        ;;
    net-dumpxml)
        # A reservation whose address is a strict prefix of the one under test.
        # A substring or regex match would report the tested address as held.
        printf "%s\n" "<network><ip><dhcp>"
        printf "%s\n" "  <host mac='52:54:00:00:64:01' name='other-vm' ip='${FAKE_RESERVED_IP:-192.168.122.1501}'/>"
        printf "%s\n" "</dhcp></ip></network>"
        ;;
    net-update|start|destroy|undefine)
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
# Every invocation is recorded whole so the suite can assert what each probe
# carried. An exit-code assertion would say nothing about the options.
if [[ -n "${FAKE_SSH_ARG_LOG:-}" ]]; then
    printf "%s\n" "$*" >> "${FAKE_SSH_ARG_LOG}"
fi
remote_cmd="${@: -1}"
case "${remote_cmd}" in
    exit)
        if [[ -n "${FAKE_SSH_STDERR:-}" ]]; then
            printf "%s\n" "${FAKE_SSH_STDERR}" >&2
        fi
        if [[ -n "${FAKE_SSH_READY_AFTER:-}" ]]; then
            count=0
            if [[ -n "${FAKE_SSH_COUNT_FILE:-}" && -f "${FAKE_SSH_COUNT_FILE}" ]]; then
                read -r count < "${FAKE_SSH_COUNT_FILE}"
            fi
            count=$((count + 1))
            printf "%s\n" "${count}" > "${FAKE_SSH_COUNT_FILE}"
            if [[ "${count}" -ge "${FAKE_SSH_READY_AFTER}" ]]; then
                exit 0
            fi
            exit 255
        fi
        exit "${FAKE_SSH_EXIT_RC:-0}"
        ;;
    "cloud-init status")
        if [[ -n "${FAKE_CLOUD_INIT_READY_AFTER:-}" ]]; then
            count=0
            if [[ -n "${FAKE_CLOUD_INIT_COUNT_FILE:-}" && -f "${FAKE_CLOUD_INIT_COUNT_FILE}" ]]; then
                read -r count < "${FAKE_CLOUD_INIT_COUNT_FILE}"
            fi
            count=$((count + 1))
            printf "%s\n" "${count}" > "${FAKE_CLOUD_INIT_COUNT_FILE}"
            if [[ "${count}" -ge "${FAKE_CLOUD_INIT_READY_AFTER}" ]]; then
                printf "%s\n" "status: done"
            else
                printf "%s\n" "status: running"
            fi
            exit 0
        fi
        printf "%s" "${FAKE_CLOUD_INIT_STATUS_OUTPUT:-}"
        exit "${FAKE_CLOUD_INIT_STATUS_RC:-0}"
        ;;
    *)
        printf "unexpected ssh command: %s\n" "${remote_cmd}" >&2
        exit 2
        ;;
esac
EOF
    cat > "${FAKEBIN}/sleep" <<'EOF'
#!/usr/bin/env bash
# Clock boundary: records the requested interval and returns immediately so the
# readiness retry budget runs without wall-clock cost.
set -e
if [[ -n "${FAKE_SLEEP_LOG:-}" ]]; then
    printf "%s\n" "$1" >> "${FAKE_SLEEP_LOG}"
fi
exit 0
EOF

cat > "${FAKEBIN}/qemu-img" <<'EOF'
#!/usr/bin/env bash
# The public path uses qemu-img for image inspection, the independent copy,
# and the VM disk resize. FAKE_QEMU_IMG_FAIL reproduces an inspection that
# cannot describe the image without corrupting a fixture.
set -e
if [[ -n "${FAKE_QEMU_IMG_LOG:-}" ]]; then
    printf "%s\n" "$*" >> "${FAKE_QEMU_IMG_LOG}"
fi
if [[ "$1" == "info" ]]; then
    if [[ "${FAKE_QEMU_IMG_FAIL:-}" == "1" ]]; then
        printf "qemu-img: Failed to get shared write lock\n" >&2
        exit 1
    fi
    printf "file format: qcow2\n"
    exit 0
fi
if [[ "$1" == "convert" ]]; then
    target="${@: -1}"
    printf "%s\n" "qcow2 fixture" > "${target}"
    exit 0
fi
exit 0
EOF

    cat > "${FAKEBIN}/genisoimage" <<'EOF'
#!/usr/bin/env bash
# Records the staging paths it was handed and copies the staged meta-data out,
# because generate_seed removes the staging directory on success. Writes the
# same statistics to stderr that the real tool writes on success, so a test can
# tell a captured-and-discarded stream from a leaked one.
set -e
for argument in "$@"; do
    case "${argument}" in
        meta-data=*)
            printf "%s\n" "${argument#meta-data=}" > "${FAKE_SEED_PATH_LOG}"
            cp -- "${argument#meta-data=}" "${FAKE_SEED_META_COPY}" 2>/dev/null || true
            ;;
    esac
done
printf "Total translation table size: 0\n" >&2
printf "183 extents written (0 MB)\n" >&2
if [[ "${FAKE_GENISOIMAGE_FAIL:-}" == "1" ]]; then
    printf "genisoimage: Unable to open disc image file\n" >&2
    exit 1
fi
exit 0
EOF

    cat > "${FAKEBIN}/virt-install" <<'EOF'
#!/usr/bin/env bash
set -e
exit 0
EOF

    chmod +x "${FAKEBIN}/virsh" "${FAKEBIN}/ssh" "${FAKEBIN}/sleep" \
        "${FAKEBIN}/qemu-img" "${FAKEBIN}/genisoimage" "${FAKEBIN}/virt-install"
}

function write_baked_image_fixture {
    local kind="$1"
    local platform="$2"
    local run_id="20260812T000000Z-abcdef123456"
    local image_name="${kind}-${platform}-${run_id}.qcow2"
    local image_path="${WORKSPACE}/images/${image_name}"
    local record_path="${image_path}.creation-record"

    mkdir -p "${WORKSPACE}/images"
    printf "%s\n" "golden fixture" > "${image_path}"
    printf "%s\n" \
        "schema=1" \
        "image_name=${image_name}" \
        "image_kind=${kind}" \
        "image_platform=${platform}" \
        "image_id=${run_id}" \
        "source_image=source.qcow2" > "${record_path}"
}

function run_create_vm {
    local status_output="$1"
    local action="$2"
    local output_file="${WORKSPACE}/output.txt"
    local rc=0
    local domain_state="running"
    local dominfo_rc=1
    local -a args=("-o" "${CASE_OS_TYPE:-rocky8}" "-n" "${CASE_NODE_ID:-server}" "-d" "${WORKSPACE}/images")

    case "${action}" in
        status)
            args+=("-s")
            ;;
        stop)
            args+=("-S")
            ;;
        cleanup)
            args+=("-c")
            ;;
        *)
            domain_state="shut off"
            dominfo_rc=0
            ;;
    esac
    if [[ -n "${FAKE_STATE_OVERRIDE:-}" ]]; then
        domain_state="${FAKE_STATE_OVERRIDE}"
    fi

    FAKE_CLOUD_INIT_STATUS_OUTPUT="${status_output}" \
    FAKE_DOMAIN_STATE="${domain_state}" \
    FAKE_DOMINFO_RC="${CASE_DOMINFO_RC:-${dominfo_rc}}" \
    FAKE_SSH_EXIT_RC="${FAKE_SSH_EXIT_RC:-0}" \
    FAKE_SSH_STDERR="${FAKE_SSH_STDERR:-}" \
    FAKE_SSH_READY_AFTER="${FAKE_SSH_READY_AFTER:-}" \
    FAKE_SSH_COUNT_FILE="${FAKE_SSH_COUNT_FILE:-}" \
    FAKE_CLOUD_INIT_READY_AFTER="${FAKE_CLOUD_INIT_READY_AFTER:-}" \
    FAKE_CLOUD_INIT_COUNT_FILE="${FAKE_CLOUD_INIT_COUNT_FILE:-}" \
    FAKE_LIBVIRT_DOWN="${FAKE_LIBVIRT_DOWN:-}" \
    FAKE_SHUTDOWN_MARKER="${FAKE_SHUTDOWN_MARKER:-}" \
    FAKE_SHUTDOWN_READY_AFTER="${FAKE_SHUTDOWN_READY_AFTER:-}" \
    FAKE_SHUTDOWN_COUNT_FILE="${FAKE_SHUTDOWN_COUNT_FILE:-}" \
    FAKE_DOMIFADDR_READY_AFTER="${FAKE_DOMIFADDR_READY_AFTER:-}" \
    FAKE_DOMIFADDR_COUNT_FILE="${FAKE_DOMIFADDR_COUNT_FILE:-}" \
    FAKE_QEMU_IMG_FAIL="${FAKE_QEMU_IMG_FAIL:-}" \
    FAKE_RESERVED_IP="${FAKE_RESERVED_IP:-}" \
    FAKE_GENISOIMAGE_FAIL="${FAKE_GENISOIMAGE_FAIL:-}" \
    FAKE_SEED_PATH_LOG="${WORKSPACE}/seed-path.txt" \
    FAKE_SEED_META_COPY="${WORKSPACE}/seed-meta.txt" \
    FAKE_SLEEP_LOG="${SLEEP_LOG}" \
    FAKE_SSH_ARG_LOG="${SSH_ARG_LOG}" \
    FAKE_QEMU_IMG_LOG="${QEMU_IMG_LOG}" \
    IMAGE_WORKFLOW_RUN_ID="${CASE_RUN_ID:-}" \
    VM_WAIT_IP_ATTEMPTS="${VM_WAIT_IP_ATTEMPTS:-}" \
    VM_WAIT_IP_INTERVAL_SECONDS="${VM_WAIT_IP_INTERVAL_SECONDS:-}" \
    VM_WAIT_SSH_ATTEMPTS="${VM_WAIT_SSH_ATTEMPTS:-}" \
    VM_WAIT_SSH_INTERVAL_SECONDS="${VM_WAIT_SSH_INTERVAL_SECONDS:-}" \
    VM_WAIT_SSH_CONNECT_TIMEOUT_SECONDS="${VM_WAIT_SSH_CONNECT_TIMEOUT_SECONDS:-}" \
    VM_WAIT_CLOUD_INIT_ATTEMPTS="${VM_WAIT_CLOUD_INIT_ATTEMPTS:-}" \
    VM_WAIT_CLOUD_INIT_INTERVAL_SECONDS="${VM_WAIT_CLOUD_INIT_INTERVAL_SECONDS:-}" \
    VM_WAIT_SHUTDOWN_ATTEMPTS="${VM_WAIT_SHUTDOWN_ATTEMPTS:-}" \
    VM_WAIT_SHUTDOWN_INTERVAL_SECONDS="${VM_WAIT_SHUTDOWN_INTERVAL_SECONDS:-}" \
    PATH="${FAKEBIN}:${PATH}" \
    HOME="${WORKSPACE}/home" \
    REQUIRED_GROUP="$(id -gn)" \
    "${TOP}/bin/create_vm.bash" "${args[@]}" > "${output_file}" 2>&1 || rc=$?

    printf "%s\n" "${rc}"
    cat "${output_file}"
}

function reset_sleep_log {
    SLEEP_LOG="${WORKSPACE}/sleep.log"
    : > "${SLEEP_LOG}"
}

# Drives the readiness path with an output the shared parser must reject and
# pins the accepted default cloud-init policy through the public script.
function run_rejection_case {
    local name="$1"
    local status_output="$2"
    local result rc output attempts sleeps interval_values

    reset_sleep_log
    result=$(run_create_vm "${status_output}" "provision")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    expect_exit "${name} exit" "1" "${rc}"
    expect_contains "${name} rejected" "${output}" "cloud-init: not complete after"
    expect_not_contains "${name} not accepted" "${output}" "complete [OK]"

    attempts=$(printf "%s\n" "${output}" \
        | sed -n 's/^cloud-init: not complete after \([0-9][0-9]*\) attempts\.$/\1/p')
    if [[ -z "${attempts}" ]]; then
        record_fail "${name} attempt count" "no attempt count in output"
        return 0
    fi

    sleeps=$(wc -l < "${SLEEP_LOG}" | tr -d '[:space:]')
    interval_values=$(sort -u "${SLEEP_LOG}")

    expect_equal "${name} default attempts" "61" "${attempts}"
    expect_equal "${name} sleeps between attempts" "60" "${sleeps}"
    expect_equal "${name} default retry interval" "30" "${interval_values}"
}

# Drives the readiness path with an SSH probe that fails. The contract says a
# probe passes only on a non-interactive key login that reaches remote command
# execution, so a failing probe must be rejected; a probe failing because the
# stored host key changed must be reported as that, not as "not available",
# because waiting cannot resolve it.
function run_ssh_rejection_case {
    local name="$1"
    local stderr_text="$2"
    local want_text="$3"
    local result rc output sleeps interval_values

    reset_sleep_log
    result=$(FAKE_SSH_EXIT_RC=255 FAKE_SSH_STDERR="${stderr_text}" \
        run_create_vm $'status: done\n' "provision")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    expect_exit "${name} exit" "1" "${rc}"
    expect_contains "${name} message" "${output}" "${want_text}"
    expect_not_contains "${name} not ready" "${output}" "SSH: ready [OK]"

    if [[ -n "${stderr_text}" ]]; then
        # A changed host key ends the wait at once; spending the budget would
        # blame the wrong thing.
        sleeps=$(wc -l < "${SLEEP_LOG}" | tr -d '[:space:]')
        expect_equal "${name} does not spend the budget" "0" "${sleeps}"
        expect_contains "${name} repair" "${output}" "ssh-keygen -f"
    else
        sleeps=$(wc -l < "${SLEEP_LOG}" | tr -d '[:space:]')
        interval_values=$(sort -u "${SLEEP_LOG}")
        expect_contains "${name} default attempts" "${output}" "after 6 attempts"
        expect_equal "${name} sleeps between attempts" "5" "${sleeps}"
        expect_equal "${name} default retry interval" "10" "${interval_values}"
    fi
}

function run_ip_policy_case {
    local name="$1"
    local ready_after="$2"
    local want_rc="$3"
    local want_text="$4"
    local count_file="${WORKSPACE}/domifaddr-count"
    local result rc output sleeps interval_values attempts

    reset_sleep_log
    rm -f -- "${count_file}"
    result=$(CASE_NODE_ID=test FAKE_DOMIFADDR_READY_AFTER="${ready_after}" \
        FAKE_DOMIFADDR_COUNT_FILE="${count_file}" \
        run_create_vm $'status: done\n' "provision")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"
    sleeps=$(wc -l < "${SLEEP_LOG}" | tr -d '[:space:]')
    interval_values=$(sort -u "${SLEEP_LOG}")
    read -r attempts < "${count_file}"

    expect_exit "${name} exit" "${want_rc}" "${rc}"
    expect_contains "${name} result" "${output}" "${want_text}"
    expect_equal "${name} default attempts" "6" "${attempts}"
    expect_equal "${name} sleeps between attempts" "5" "${sleeps}"
    expect_equal "${name} default retry interval" "10" "${interval_values}"
}

function run_ssh_eventual_case {
    local count_file="${WORKSPACE}/ssh-count"
    local result rc output sleeps interval_values attempts

    reset_sleep_log
    rm -f -- "${count_file}"
    result=$(FAKE_SSH_READY_AFTER=6 FAKE_SSH_COUNT_FILE="${count_file}" \
        run_create_vm $'status: done\n' "provision")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"
    sleeps=$(wc -l < "${SLEEP_LOG}" | tr -d '[:space:]')
    interval_values=$(sort -u "${SLEEP_LOG}")
    read -r attempts < "${count_file}"

    expect_exit "ssh eventual success exit" "0" "${rc}"
    expect_contains "ssh eventual success result" "${output}" "SSH: ready [OK]"
    expect_equal "ssh eventual success attempts" "6" "${attempts}"
    expect_equal "ssh eventual success sleeps" "5" "${sleeps}"
    expect_equal "ssh eventual success interval" "10" "${interval_values}"
}

function run_cloud_init_eventual_case {
    local count_file="${WORKSPACE}/cloud-init-count"
    local result rc output sleeps interval_values attempts

    reset_sleep_log
    rm -f -- "${count_file}"
    result=$(FAKE_CLOUD_INIT_READY_AFTER=61 \
        FAKE_CLOUD_INIT_COUNT_FILE="${count_file}" \
        run_create_vm $'status: running\n' "provision")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"
    sleeps=$(wc -l < "${SLEEP_LOG}" | tr -d '[:space:]')
    interval_values=$(sort -u "${SLEEP_LOG}")
    read -r attempts < "${count_file}"

    expect_exit "cloud-init eventual success exit" "0" "${rc}"
    expect_contains "cloud-init eventual success result" "${output}" "complete [OK]"
    expect_equal "cloud-init eventual success attempts" "61" "${attempts}"
    expect_equal "cloud-init eventual success sleeps" "60" "${sleeps}"
    expect_equal "cloud-init eventual success interval" "30" "${interval_values}"
}

function run_override_case {
    local override_log="${WORKSPACE}/ssh-override-args.log"
    local saved_log="${SSH_ARG_LOG}"
    local result rc output sleeps interval_values

    reset_sleep_log
    : > "${override_log}"
    SSH_ARG_LOG="${override_log}"
    result=$(VM_WAIT_CLOUD_INIT_ATTEMPTS=3 \
        VM_WAIT_CLOUD_INIT_INTERVAL_SECONDS=7 \
        VM_WAIT_SSH_CONNECT_TIMEOUT_SECONDS=3 \
        run_create_vm $'status: running\n' "provision")
    SSH_ARG_LOG="${saved_log}"
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"
    sleeps=$(wc -l < "${SLEEP_LOG}" | tr -d '[:space:]')
    interval_values=$(sort -u "${SLEEP_LOG}")

    expect_exit "wait override exit" "1" "${rc}"
    expect_contains "wait override attempts" "${output}" "after 3 attempts"
    expect_equal "wait override sleeps" "2" "${sleeps}"
    expect_equal "wait override interval" "7" "${interval_values}"
    if grep -q -- '-o ConnectTimeout=3' "${override_log}"; then
        record_pass "SSH connect timeout override"
    else
        record_fail "SSH connect timeout override" "ConnectTimeout=3 was not used"
    fi
}

function run_invalid_wait_setting_case {
    local name="$1"
    local value="$2"
    local label="${name}=${value}"
    local result rc output
    local "${name}=${value}"

    result=$(run_create_vm $'status: done\n' "status")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    expect_exit "invalid wait setting ${label} exit" "1" "${rc}"
    expect_contains "invalid wait setting ${label} result" "${output}" \
        "${name} must be a positive integer"
}

function run_invalid_wait_setting_cases {
    local name
    local -a names=(
        VM_WAIT_IP_ATTEMPTS
        VM_WAIT_IP_INTERVAL_SECONDS
        VM_WAIT_SSH_ATTEMPTS
        VM_WAIT_SSH_INTERVAL_SECONDS
        VM_WAIT_SSH_CONNECT_TIMEOUT_SECONDS
        VM_WAIT_CLOUD_INIT_ATTEMPTS
        VM_WAIT_CLOUD_INIT_INTERVAL_SECONDS
        VM_WAIT_SHUTDOWN_ATTEMPTS
        VM_WAIT_SHUTDOWN_INTERVAL_SECONDS
    )

    for name in "${names[@]}"; do
        run_invalid_wait_setting_case "${name}" "0"
    done
    run_invalid_wait_setting_case VM_WAIT_IP_ATTEMPTS -1
    run_invalid_wait_setting_case VM_WAIT_IP_ATTEMPTS invalid
}

# Drives one cell of the action-by-state table in ARCHITECTURE section 14.
# The state is forced through the fake virsh rather than by reaching it, so a
# cell that no action can currently produce is still exercised.
# Stop against a domain that obeys the ACPI request: the marker makes the fake
# report "shut off" once shutdown has been issued, which is the transition the
# poll exists to observe. This case pins first-poll success and the default
# interval; the last-attempt case below pins the full shutdown budget.
function run_stop_obeys_case {
    local name="$1"
    local want_rc="$2"
    local want_text="$3"
    local result rc output sleeps interval_values

    reset_sleep_log
    result=$(FAKE_STATE_OVERRIDE="running" \
        FAKE_SHUTDOWN_MARKER="${WORKSPACE}/shutdown.marker" \
        run_create_vm $'status: done\n' "stop")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"
    sleeps=$(wc -l < "${SLEEP_LOG}" | tr -d '[:space:]')
    interval_values=$(sort -u "${SLEEP_LOG}")
    rm -f -- "${WORKSPACE}/shutdown.marker"

    expect_exit "${name} exit" "${want_rc}" "${rc}"
    expect_contains "${name} message" "${output}" "${want_text}"
    expect_equal "${name} first poll" "1" "${sleeps}"
    expect_equal "${name} default interval" "5" "${interval_values}"
}

function run_stop_eventual_case {
    local marker="${WORKSPACE}/shutdown.marker"
    local count_file="${WORKSPACE}/shutdown-count"
    local result rc output sleeps interval_values attempts

    reset_sleep_log
    rm -f -- "${marker}" "${count_file}"
    result=$(FAKE_STATE_OVERRIDE=running FAKE_SHUTDOWN_MARKER="${marker}" \
        FAKE_SHUTDOWN_READY_AFTER=12 FAKE_SHUTDOWN_COUNT_FILE="${count_file}" \
        run_create_vm $'status: done\n' "stop")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"
    sleeps=$(wc -l < "${SLEEP_LOG}" | tr -d '[:space:]')
    interval_values=$(sort -u "${SLEEP_LOG}")
    read -r attempts < "${count_file}"
    rm -f -- "${marker}" "${count_file}"

    expect_exit "stop eventual success exit" "0" "${rc}"
    expect_contains "stop eventual success result" "${output}" "shut off [OK]"
    expect_equal "stop eventual success attempts" "12" "${attempts}"
    expect_equal "stop eventual success sleeps" "12" "${sleeps}"
    expect_equal "stop eventual success interval" "5" "${interval_values}"
}

function run_lifecycle_case {
    local name="$1"
    local action="$2"
    local state="$3"
    local want_rc="$4"
    local want_text="$5"
    local result rc output

    reset_sleep_log
    result=$(FAKE_STATE_OVERRIDE="${state}" \
        run_create_vm $'status: done\n' "${action}")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    expect_exit "${name} exit" "${want_rc}" "${rc}"
    expect_contains "${name} message" "${output}" "${want_text}"
}

# Drives an action while libvirt does not answer at all. The point is that this
# is reported as its own outcome: an outage read as an absent domain would tell
# the operator to provision a VM that may already exist.
function run_outage_case {
    local name="$1"
    local action="$2"
    local want_rc="$3"
    local want_text="$4"
    local result rc output

    reset_sleep_log
    result=$(FAKE_LIBVIRT_DOWN=1 run_create_vm $'status: done\n' "${action}")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    expect_exit "${name} exit" "${want_rc}" "${rc}"
    expect_contains "${name} message" "${output}" "${want_text}"
    expect_not_contains "${name} not absent" "${output}" "to provision"
}

# Asserts the base image an OS type selects, and its class, through the public
# status path. Selection is decided before anything is created, so this needs no
# image, no libvirt, and no network.
function run_selection_case {
    local os_type="$1"
    local want_line="$2"
    local result output

    if [[ "${os_type}" == "rocky8-iocrunner" ]]; then
        write_baked_image_fixture "iocrunner" "rocky8"
    fi
    reset_sleep_log
    result=$(CASE_OS_TYPE="${os_type}" run_create_vm $'status: done\n' "status")
    output="${result#*$'\n'}"
    expect_contains "select ${os_type}" "${output}" "${want_line}"
}

# A bake output and the consumer input that reads it are one valid pair. This
# derives the run-specific name and asserts a consumer selects exactly it,
# including the matching creation record.
function run_bake_pair_case {
    local bake_os="$1"
    local consumer_os="$2"
    local derived result output

    write_baked_image_fixture "iocrunner" "${bake_os}"
    derived="iocrunner-${bake_os}-20260812T000000Z-abcdef123456.qcow2"
    reset_sleep_log
    result=$(CASE_OS_TYPE="${consumer_os}" run_create_vm $'status: done\n' "status")
    output="${result#*$'\n'}"
    expect_contains "bake pair ${bake_os}" "${output}" "Base image : ${derived}"
}

function run_cleanup_pair_case {
    local disk="${WORKSPACE}/images/testbed-rocky8-server.qcow2"
    local record="${disk}.creation-record"
    local seed="${WORKSPACE}/images/testbed-rocky8-server-seed.iso"
    local result rc output

    printf "%s\n" "disk fixture" > "${disk}"
    printf "%s\n" "record fixture" > "${record}"
    printf "%s\n" "seed fixture" > "${seed}"
    result=$(run_create_vm "" "cleanup")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    expect_exit "cleanup pair exit" "0" "${rc}"
    expect_contains "cleanup pair output" "${output}" "Removing disk pair"
    if [[ ! -e "${disk}" && ! -L "${disk}" && \
          ! -e "${record}" && ! -L "${record}" && \
          ! -e "${seed}" && ! -L "${seed}" ]]; then
        record_pass "cleanup removes disk, creation record, and seed"
    else
        record_fail "cleanup removes disk, creation record, and seed" \
            "one or more VM artifacts remained"
    fi
}

function run_pair_rejection_case {
    local name="$1"
    local mutation="$2"
    local image_path="${WORKSPACE}/images/iocrunner-rocky8-20260812T000000Z-abcdef123456.qcow2"
    local result rc output

    write_baked_image_fixture "iocrunner" "rocky8"
    if [[ "${mutation}" == "missing" ]]; then
        rm -f -- "${image_path}.creation-record"
    else
        sed -i 's/^image_platform=rocky8$/image_platform=debian13/' \
            "${image_path}.creation-record"
    fi
    result=$(CASE_OS_TYPE="rocky8-iocrunner" run_create_vm $'status: done\n' "status")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"
    expect_exit "${name} exit" "1" "${rc}"
    expect_contains "${name} rejects the pair" "${output}" \
        "no valid iocrunner image found for rocky8"
}

function run_invalid_run_id_case {
    local result rc output

    result=$(CASE_RUN_ID="manual-run" run_create_vm $'status: done\n' "status")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"
    expect_exit "invalid run ID exit" "1" "${rc}"
    expect_contains "invalid run ID rejection" "${output}" \
        "IMAGE_WORKFLOW_RUN_ID must match"
}

# The provisioner must never delete a base image it cannot fetch back. The
# refusal is asserted three ways together: the file survives, the run stops, and
# the message names the image. Survival alone would also pass a silent continue.
function run_no_delete_case {
    local name="$1"
    local os_type="$2"
    local image_name="$3"
    local image_path="${WORKSPACE}/images/${image_name}"
    local result rc output

    mkdir -p "${WORKSPACE}/images"
    printf "%s\n" "golden fixture" > "${image_path}"
    printf "%s\n" \
        "schema=1" \
        "image_name=${image_name}" \
        "image_kind=iocrunner" \
        "image_platform=rocky8" \
        "image_id=20260812T000000Z-abcdef123456" \
        "source_image=source.qcow2" > "${image_path}.creation-record"
    reset_sleep_log
    # dominfo must fail so the dispatch falls through to the fresh-provision
    # path; that is the only route that reaches verify_base_image.
    result=$(CASE_OS_TYPE="${os_type}" FAKE_QEMU_IMG_FAIL=1 CASE_DOMINFO_RC=1 \
        FAKE_STATE_OVERRIDE="absent" run_create_vm $'status: done\n' "provision")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    if [[ -f "${image_path}" ]]; then
        record_pass "${name} keeps the image"
    else
        record_fail "${name} keeps the image" "base image was deleted"
    fi
    expect_exit "${name} exit" "1" "${rc}"
    expect_contains "${name} names the image" "${output}" "${image_name} did not verify"
    expect_contains "${name} explains" "${output}" "no download URL"
    rm -f -- "${image_path}"
}

# Drives the fresh-provision path far enough to run generate_seed, then asserts
# on what the fake genisoimage recorded. Seed staging is the subject: issue #22
# reported that two concurrent runs shared one staging directory and interleaved
# their writes, leaving two local-hostname lines in one meta-data. The path is
# per-VM now, but that arrived as a side effect of the provenance work in
# c4ba7fd rather than as a deliberate fix, so nothing held it. These cases hold
# it.
function run_seed_case {
    local name="$1"
    local result rc output staged_path staged_meta hostname_count resize_line

    mkdir -p "${WORKSPACE}/home/.ssh" "${WORKSPACE}/images"
    printf "%s\n" "ssh-ed25519 AAAAC3NzaFixture test" \
        > "${WORKSPACE}/home/.ssh/id_ed25519.pub"
    printf "%s\n" "base" > "${WORKSPACE}/images/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2"
    rm -f "${WORKSPACE}/seed-path.txt" "${WORKSPACE}/seed-meta.txt"

    reset_sleep_log
    result=$(CASE_DOMINFO_RC=1 FAKE_STATE_OVERRIDE="absent" \
        run_create_vm $'status: done\n' "provision")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    expect_exit "${name} exit" "0" "${rc}"

    staged_path="$(cat "${WORKSPACE}/seed-path.txt" 2>/dev/null || true)"
    # Staging must not live inside the repository. It did until c4ba7fd, and
    # that made every bake stamp its manifest cloud-provision <sha>-dirty,
    # because the bake counts untracked files when it records provenance.
    if [[ -n "${staged_path}" && "${staged_path}" != "${TOP}/"* ]]; then
        record_pass "${name} stages outside the repository"
    else
        record_fail "${name} stages outside the repository" "staged at ${staged_path:-<nothing>}"
    fi

    staged_meta="$(cat "${WORKSPACE}/seed-meta.txt" 2>/dev/null || true)"
    hostname_count="$(grep -c '^local-hostname:' <<< "${staged_meta}" || true)"
    expect_equal "${name} one local-hostname" "1" "${hostname_count}"
    expect_contains "${name} own VM name" "${staged_meta}" "local-hostname: testbed-rocky8-server"

    # genisoimage writes statistics to stderr even when it succeeds. They must
    # not reach the operator: the success line stays one line.
    expect_not_contains "${name} no genisoimage noise" "${output}" "extents written"
    expect_contains "${name} reports OK" "${output}" "cloud-init ISO... [OK]"

    resize_line="$(grep '^resize ' "${QEMU_IMG_LOG}" | tail -n 1 || true)"
    expect_equal "${name} resizes the VM disk" \
        "resize ${WORKSPACE}/images/testbed-rocky8-server.qcow2 20G" \
        "${resize_line}"
}

# A failing genisoimage must stop the run and say why. It already stopped, by
# set -e, but the reason was discarded with 2>/dev/null and the operator saw a
# truncated progress line and nothing else.
function run_seed_failure_case {
    local name="$1"
    local result rc output

    mkdir -p "${WORKSPACE}/home/.ssh" "${WORKSPACE}/images"
    printf "%s\n" "ssh-ed25519 AAAAC3NzaFixture test" \
        > "${WORKSPACE}/home/.ssh/id_ed25519.pub"
    printf "%s\n" "base" > "${WORKSPACE}/images/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2"

    reset_sleep_log
    result=$(CASE_DOMINFO_RC=1 FAKE_STATE_OVERRIDE="absent" FAKE_GENISOIMAGE_FAIL=1 \
        run_create_vm $'status: done\n' "provision")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    expect_exit "${name} exit" "1" "${rc}"
    expect_not_contains "${name} not OK" "${output}" "cloud-init ISO... [OK]"
    expect_contains "${name} names the reason" "${output}" "Unable to open disc image file"
    expect_contains "${name} keeps the staging" "${output}" "Staging left for inspection"
}

# Address assignment, issue #27. An address must identify a VM, not a node
# name: hashing NODE_ID alone gave every OS type the same address and MAC for a
# given node ID, so the second VM could not be created at all. Known node IDs
# are asserted separately because they must not move - existing VMs record
# their addresses and downstream notes cite them.
function run_address_case {
    local name="$1"
    local os_type="$2"
    local node_id="$3"
    local want_last="$4"
    local result output got

    if [[ "${os_type}" == *-iocrunner || "${os_type}" == "debian13-ethercat" ]]; then
        if [[ "${os_type}" == "rocky8-iocrunner" ]]; then
            write_baked_image_fixture "iocrunner" "rocky8"
        elif [[ "${os_type}" == "debian13-iocrunner" ]]; then
            write_baked_image_fixture "iocrunner" "debian13"
        else
            write_baked_image_fixture "ethercat" "debian13"
        fi
    fi
    reset_sleep_log
    result=$(CASE_OS_TYPE="${os_type}" CASE_NODE_ID="${node_id}" \
        run_create_vm $'status: done\n' "status")
    output="${result#*$'\n'}"
    got="$(grep -oE 'mapped to 192\.168\.122\.[0-9]+|IP Address : 192\.168\.122\.[0-9]+' <<< "${output}" \
        | grep -oE '[0-9]+$' | head -1)"
    expect_equal "${name}" "${want_last}" "${got:-none}"
}

# The whole point of #27: the same unknown node ID across OS types must not
# land on one address. Asserting individual values would pass even if two of
# them agreed, so the distinctness is asserted directly.
function run_address_distinct_case {
    local node_id="$1"
    shift
    local os_type result output got
    local -a seen=()
    local unique

    for os_type in "$@"; do
        if [[ "${os_type}" == "rocky8-iocrunner" ]]; then
            write_baked_image_fixture "iocrunner" "rocky8"
        elif [[ "${os_type}" == "debian13-iocrunner" ]]; then
            write_baked_image_fixture "iocrunner" "debian13"
        elif [[ "${os_type}" == "debian13-ethercat" ]]; then
            write_baked_image_fixture "ethercat" "debian13"
        fi
        reset_sleep_log
        result=$(CASE_OS_TYPE="${os_type}" CASE_NODE_ID="${node_id}" \
            run_create_vm $'status: done\n' "status")
        output="${result#*$'\n'}"
        got="$(grep -oE 'mapped to 192\.168\.122\.[0-9]+' <<< "${output}" \
            | grep -oE '[0-9]+$' | head -1)"
        seen+=("${got:-none}")
    done
    unique="$(printf "%s\n" "${seen[@]}" | sort -u | wc -l | tr -d '[:space:]')"
    expect_equal "unknown node ${node_id} gives one address per OS type" \
        "${#seen[@]}" "${unique}"
}

# The DHCP collision guard must compare whole address fields. Matching by
# substring or regex would read 192.168.122.150 as held by the entry for
# 192.168.122.1501 and refuse a VM whose address is free - a guard that blocks
# correct work is worse than the collision it was added to name.
function run_reservation_case {
    local name="$1"
    local reserved="$2"
    local want_blocked="$3"
    local result rc output

    # register_dhcp sits behind verify_base_image, prepare_disk, and
    # generate_seed. Without these fixtures the run dies earlier and every
    # assertion below passes for the wrong reason.
    mkdir -p "${WORKSPACE}/home/.ssh" "${WORKSPACE}/images"
    printf "%s\n" "ssh-ed25519 AAAAC3NzaFixture test" \
        > "${WORKSPACE}/home/.ssh/id_ed25519.pub"
    write_baked_image_fixture "iocrunner" "rocky8"

    reset_sleep_log
    result=$(CASE_OS_TYPE="rocky8-iocrunner" CASE_DOMINFO_RC=1 \
        FAKE_STATE_OVERRIDE="absent" FAKE_RESERVED_IP="${reserved}" \
        run_create_vm $'status: done\n' "provision")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    if [[ "${want_blocked}" == "yes" ]]; then
        expect_contains "${name}" "${output}" "is already reserved for"
    else
        expect_not_contains "${name}" "${output}" "is already reserved for"
        # Prove the run actually reached the registration step, so a failure
        # earlier in the path cannot be mistaken for the guard staying quiet.
        expect_contains "${name} reached registration" "${output}" "Network: registering"
    fi
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

    reset_sleep_log
    result=$(run_create_vm "${status_output}" "${action}")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    expect_exit "${name} exit" "${want_rc}" "${rc}"
    expect_contains "${name} output" "${output}" "${want_text}"
}

# Pins the multiplexing half of the SSH readiness contract, ARCHITECTURE
# section 13, across every probe the suite drove. The claim is about the
# arguments: with the two options removed from SSH_PROBE_OPTIONS every other
# case in this file still passes, while on a real host a master left over from a
# previous run at the same reused address accepts the connection, fails
# mid-request, and returns a non-blocking stdin the caller never clears.
function assert_ssh_multiplexing_off {
    local total multiplexing_offenders timeout_offenders

    if [[ ! -s "${SSH_ARG_LOG}" ]]; then
        record_fail "ssh probes were recorded" "no ssh invocation reached the log"
        return 0
    fi
    total="$(wc -l < "${SSH_ARG_LOG}" | tr -d '[:space:]')"
    multiplexing_offenders="$(awk \
        '!/-o ControlMaster=no/ || !/-o ControlPath=none/ {count++} END {print count + 0}' \
        "${SSH_ARG_LOG}")"
    timeout_offenders="$(awk \
        '!/-o ConnectTimeout=5/ {count++} END {print count + 0}' \
        "${SSH_ARG_LOG}")"
    printf "  ssh invocations recorded: %s (multiplexing: %s, timeout: %s)\n" \
        "${total}" "${multiplexing_offenders}" "${timeout_offenders}"
    expect_equal "every ssh probe refuses multiplexing" "0" "${multiplexing_offenders}"
    expect_equal "every default SSH probe uses the 5-second connection timeout" \
        "0" "${timeout_offenders}"
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
SSH_ARG_LOG="${WORKSPACE}/ssh-args.log"
QEMU_IMG_LOG="${WORKSPACE}/qemu-img.log"
mkdir -p "${FAKEBIN}"
: > "${SSH_ARG_LOG}"
: > "${QEMU_IMG_LOG}"
write_fake_commands

run_case "status done" $'status: done\n' "status" 0 "cloud-init : done"
run_case "status running" $'status: running\n' "status" 1 "cloud-init : running"
run_case "status malformed" $'done but no status field\n' "status" 1 "cloud-init : unknown"
run_case "provision done" $'status: done\n' "provision" 0 "cloud-init: complete [OK]"
run_rejection_case "provision not complete" $'status: running\n'
run_rejection_case "provision malformed" $'done but no status field\n'
run_ip_policy_case "IP eventual success" 6 0 "SSH: ready [OK]"
run_ip_policy_case "IP timeout" 7 1 "Status: IP not available"
run_ssh_eventual_case
run_cloud_init_eventual_case
run_override_case
run_invalid_wait_setting_cases
run_ssh_rejection_case "ssh unavailable" "" "SSH: not available after"
run_ssh_rejection_case "ssh host key changed" \
    "@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@" \
    "answers with a different host key"

# Libvirt lifecycle policy, ARCHITECTURE section 14. Each case names the row of
# the action-by-state table it pins.
run_stop_obeys_case "stop running" 0 "shut off [OK]"
run_stop_eventual_case
run_lifecycle_case "stop never obeys" "stop" "running" 1 "did not shut off within 60s"
run_lifecycle_case "stop already off" "stop" "shut off" 0 "already shut off"
run_lifecycle_case "stop absent" "stop" "absent" 0 "is not defined"
run_lifecycle_case "stop paused" "stop" "paused" 1 "unexpected state: paused"
run_lifecycle_case "stop paused hints cleanup" "stop" "paused" 1 ".clean' then re-run"
run_lifecycle_case "status paused hints cleanup" "status" "paused" 1 ".clean' then re-run"
run_lifecycle_case "cleanup running" "cleanup" "running" 0 "Undefining VM"
run_lifecycle_case "cleanup absent" "cleanup" "absent" 0 "Removing disk pair"
run_cleanup_pair_case
run_outage_case "status outage" "status" 1 "libvirt did not answer"
run_outage_case "stop outage" "stop" 1 "was not checked"
run_outage_case "provision outage" "provision" 1 "nothing was created"

# Image selection, ARCHITECTURE section 15.
run_selection_case "rocky8" "Rocky-8-GenericCloud-Base.latest.x86_64.qcow2 (upstream, moving)"
run_selection_case "debian13-rtbase" "debian-13-genericcloud-amd64-20260601-2496.qcow2 (upstream, pinned)"
run_selection_case "rocky8-iocrunner" \
    "iocrunner-rocky8-20260812T000000Z-abcdef123456.qcow2 (baked locally, not downloadable)"
run_selection_case "epics-env-rocky8" "Rocky-8-GenericCloud-Base.latest.x86_64.qcow2 (upstream, moving)"
run_bake_pair_case "rocky8" "rocky8-iocrunner"
run_bake_pair_case "debian13" "debian13-iocrunner"
run_pair_rejection_case "missing creation record" "missing"
run_pair_rejection_case "mismatched creation record" "mismatched"
run_invalid_run_id_case
run_no_delete_case "unusable golden" "rocky8-iocrunner" \
    "iocrunner-rocky8-20260812T000000Z-abcdef123456.qcow2"

# Seed staging, issue #22.
run_seed_case "seed"
run_seed_failure_case "seed failure"

# Address assignment, issue #27.
run_address_case "known node rocky8-iocrunner server" "rocky8-iocrunner" "server" "150"
run_address_case "known node rocky8-iocrunner node2" "rocky8-iocrunner" "node2" "152"
run_address_case "known node debian13-ethercat node1" "debian13-ethercat" "node1" "71"
run_address_distinct_case "probe" rocky8 debian13 rocky8-iocrunner debian13-ethercat epics-env-rocky8

# DHCP reservation guard. rocky8-iocrunner/server maps to 192.168.122.150.
run_reservation_case "reservation guard ignores a longer address" "192.168.122.1501" "no"
run_reservation_case "reservation guard fires on the same address" "192.168.122.150" "yes"

# SSH readiness contract, ARCHITECTURE section 13. Asserted last so it covers
# every probe every case above drove.
assert_ssh_multiplexing_off

print_summary
