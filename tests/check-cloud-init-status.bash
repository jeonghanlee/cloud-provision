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
        domstate|dominfo|domifaddr|net-update|start|shutdown|destroy|undefine|uri)
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
            printf "shut off\n"
            exit 0
        fi
        printf "%s\n" "${FAKE_DOMAIN_STATE:-running}"
        ;;
    dominfo)
        exit "${FAKE_DOMINFO_RC:-1}"
        ;;
    domifaddr)
        printf " vnet0 52:54:00:00:64:00 ipv4 192.168.122.100/24\n"
        ;;
    shutdown)
        if [[ -n "${FAKE_SHUTDOWN_MARKER:-}" ]]; then
            : > "${FAKE_SHUTDOWN_MARKER}"
        fi
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
remote_cmd="${@: -1}"
case "${remote_cmd}" in
    exit)
        if [[ -n "${FAKE_SSH_STDERR:-}" ]]; then
            printf "%s\n" "${FAKE_SSH_STDERR}" >&2
        fi
        exit "${FAKE_SSH_EXIT_RC:-0}"
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

    chmod +x "${FAKEBIN}/virsh" "${FAKEBIN}/ssh" "${FAKEBIN}/sleep"
}

function run_create_vm {
    local status_output="$1"
    local action="$2"
    local output_file="${WORKSPACE}/output.txt"
    local rc=0
    local domain_state="running"
    local dominfo_rc=1
    local -a args=("-o" "rocky8" "-n" "server" "-d" "${WORKSPACE}/images")

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
    FAKE_DOMINFO_RC="${dominfo_rc}" \
    FAKE_SSH_EXIT_RC="${FAKE_SSH_EXIT_RC:-0}" \
    FAKE_SSH_STDERR="${FAKE_SSH_STDERR:-}" \
    FAKE_LIBVIRT_DOWN="${FAKE_LIBVIRT_DOWN:-}" \
    FAKE_SHUTDOWN_MARKER="${FAKE_SHUTDOWN_MARKER:-}" \
    FAKE_SLEEP_LOG="${SLEEP_LOG}" \
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

# Drives the readiness path with an output the shared parser must reject, then
# checks the retry contract without hard-coding the budget: the loop reports the
# attempt count it actually made, sleeps once between consecutive attempts, and
# uses one interval throughout. Reading the count from the run keeps this test
# valid when the retry budget itself is revisited.
function run_rejection_case {
    local name="$1"
    local status_output="$2"
    local result rc output attempts sleeps intervals

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
    intervals=$(sort -u "${SLEEP_LOG}" | wc -l | tr -d '[:space:]')

    expect_equal "${name} sleeps between attempts" "$(( attempts - 1 ))" "${sleeps}"
    expect_equal "${name} single retry interval" "1" "${intervals}"
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
    local result rc output sleeps

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
    fi
}

# Drives one cell of the action-by-state table in ARCHITECTURE section 14.
# The state is forced through the fake virsh rather than by reaching it, so a
# cell that no action can currently produce is still exercised.
# Stop against a domain that obeys the ACPI request: the marker makes the fake
# report "shut off" once shutdown has been issued, which is the transition the
# poll exists to observe. The attempt count and interval are deliberately not
# asserted; they belong to the wait-budget policy.
function run_stop_obeys_case {
    local name="$1"
    local want_rc="$2"
    local want_text="$3"
    local result rc output

    reset_sleep_log
    result=$(FAKE_STATE_OVERRIDE="running" \
        FAKE_SHUTDOWN_MARKER="${WORKSPACE}/shutdown.marker" \
        run_create_vm $'status: done\n' "stop")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"
    rm -f -- "${WORKSPACE}/shutdown.marker"

    expect_exit "${name} exit" "${want_rc}" "${rc}"
    expect_contains "${name} message" "${output}" "${want_text}"
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
run_rejection_case "provision not complete" $'status: running\n'
run_rejection_case "provision malformed" $'done but no status field\n'
run_ssh_rejection_case "ssh unavailable" "" "SSH: not available after"
run_ssh_rejection_case "ssh host key changed" \
    "@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@" \
    "answers with a different host key"

# Libvirt lifecycle policy, ARCHITECTURE section 14. Each case names the row of
# the action-by-state table it pins.
run_stop_obeys_case "stop running" 0 "shut off [OK]"
run_lifecycle_case "stop never obeys" "stop" "running" 1 "did not shut off within"
run_lifecycle_case "stop already off" "stop" "shut off" 0 "already shut off"
run_lifecycle_case "stop absent" "stop" "absent" 0 "is not defined"
run_lifecycle_case "stop paused" "stop" "paused" 1 "unexpected state: paused"
run_lifecycle_case "stop paused hints cleanup" "stop" "paused" 1 ".clean' then re-run"
run_lifecycle_case "status paused hints cleanup" "status" "paused" 1 ".clean' then re-run"
run_lifecycle_case "cleanup running" "cleanup" "running" 0 "Undefining VM"
run_lifecycle_case "cleanup absent" "cleanup" "absent" 0 "Removing disk"
run_outage_case "status outage" "status" 1 "libvirt did not answer"
run_outage_case "stop outage" "stop" 1 "was not checked"
run_outage_case "provision outage" "provision" 1 "nothing was created"

print_summary
