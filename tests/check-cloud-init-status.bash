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
# branch of the main section in bin/create_vm.bash (virsh start, then
# wait_for_vm), not the fresh-provision branch, which needs a base image, a
# disk, a seed, and virt-install. Both branches pass "retry" to the same
# wait_for_vm, so the covered code is the same.
#
# Readiness input: the fake ssh answers the CLOUD_INIT_READINESS_PROBE with a
# fixture from tests/fixtures/cloud-init-status, each a boot-finished line
# followed by a status.json body modeled on what cloud-init writes, so the
# shared parser reads the shape it is written for. The three fixtures are
# done, running, and error.
#
# What the rejection cases pin: in retry mode wait_for_cloud_init never prints
# the parsed status, so the running and error fixtures produce identical
# output. The two cases pin that neither input is accepted as done. The
# running-versus-error distinction stays with the -s status cases below.

set -e

declare -g SCRIPT_DIR
declare -g TOP
declare -g FIXTURE_DIR
declare -g WORKSPACE
declare -g FAKEBIN
declare -g SLEEP_LOG
declare -g SSH_ARG_LOG
declare -g QEMU_IMG_LOG
declare -g REAL_SSH_KEYGEN
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -ag FAILED_DETAILS=()

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURE_DIR="${TOP}/tests/fixtures/cloud-init-status"
REAL_SSH_KEYGEN="$(command -v ssh-keygen)"
readonly REAL_SSH_KEYGEN
export REAL_SSH_KEYGEN

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
        domstate|dominfo|domiflist|domifaddr|net-update|net-dumpxml|net-dhcp-leases|start|shutdown|destroy|undefine|list|uri)
            cmd="$arg"
            break
            ;;
    esac
done
if [[ -n "${FAKE_VIRSH_LOG:-}" ]]; then
    printf '%s\n' "${cmd}" >> "${FAKE_VIRSH_LOG}"
fi
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
        if [[ -n "${FAKE_UNDEFINED_MARKER:-}" && -e "${FAKE_UNDEFINED_MARKER}" ]]; then
            exit 1
        fi
        exit "${FAKE_DOMINFO_RC:-1}"
        ;;
    domiflist)
        printf 'Interface Type Source Model MAC\n'
        printf 'vnet0 network lab virtio %s\n' "${FAKE_DOMAIN_MAC:-52:54:00:01:64:00}"
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
            printf " vnet0 52:54:00:01:64:00 ipv4 192.168.123.100/24\n"
        fi
        ;;
    shutdown)
        if [[ -n "${FAKE_SHUTDOWN_MARKER:-}" ]]; then
            : > "${FAKE_SHUTDOWN_MARKER}"
        fi
        ;;
    net-dumpxml)
        if [[ "${FAKE_NET_DUMP_FAIL:-}" == "1" ]]; then
            printf 'error: cannot read network\n' >&2
            exit 1
        fi
        if [[ -n "${FAKE_RESERVATION_FILE:-}" ]]; then
            if [[ "$*" == *--inactive* && -n "${FAKE_CONFIG_RESERVATION_FILE:-}" ]]; then
                cat "${FAKE_CONFIG_RESERVATION_FILE}"
            else
                cat "${FAKE_RESERVATION_FILE}"
            fi
            exit 0
        fi
        # A reservation whose address is a strict prefix of the one under test.
        # A substring or regex match would report the tested address as held.
        printf "%s\n" "<network><ip><dhcp>"
        printf "%s\n" "  <host mac='52:54:00:01:64:01' name='other-vm' ip='${FAKE_RESERVED_IP:-192.168.123.1501}'/>"
        printf "%s\n" "</dhcp></ip></network>"
        ;;
    net-dhcp-leases)
        if [[ "${FAKE_LEASE_FAIL:-}" == "1" ]]; then
            printf 'error: failed to get leases\n' >&2
            exit 1
        fi
        cat "${FAKE_LEASE_FILE:-${FAKE_LEASE_FIXTURE_DIR}/leases-empty.txt}"
        ;;
    net-update)
        if [[ -n "${FAKE_NET_UPDATE_LOG:-}" ]]; then
            printf '%s\n' "$*" >> "${FAKE_NET_UPDATE_LOG}"
        fi
        exit "${FAKE_NET_UPDATE_RC:-0}"
        ;;
    undefine)
        [[ "${FAKE_UNDEFINE_RC:-0}" == 0 ]] || exit "${FAKE_UNDEFINE_RC}"
        if [[ -n "${FAKE_UNDEFINED_MARKER:-}" ]]; then
            : > "${FAKE_UNDEFINED_MARKER}"
        fi
        ;;
    destroy)
        exit "${FAKE_DESTROY_RC:-0}"
        ;;
    list)
        [[ "${FAKE_LIST_RC:-0}" == 0 ]] || exit "${FAKE_LIST_RC}"
        if [[ "${FAKE_DOMAIN_STATE:-running}" != absent ]]; then
            printf '%s\n' "${FAKE_LIST_DOMAIN:-lab-rocky8-main}"
        fi
        ;;
    start)
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
if [[ "${FAKE_CHECK_KNOWN_HOSTS:-0}" == 1 ]]; then
    host="${@: -2:1}"
    if "${REAL_SSH_KEYGEN}" -F "${host#*@}" -f "${HOME}/.ssh/known_hosts" \
        >/dev/null 2>&1; then
        printf '%s\n' 'REMOTE HOST IDENTIFICATION HAS CHANGED' >&2
        exit 255
    fi
fi
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
    *"/var/lib/cloud/instance/boot-finished"*)
        if [[ -n "${FAKE_CLOUD_INIT_READY_AFTER:-}" ]]; then
            count=0
            if [[ -n "${FAKE_CLOUD_INIT_COUNT_FILE:-}" && -f "${FAKE_CLOUD_INIT_COUNT_FILE}" ]]; then
                read -r count < "${FAKE_CLOUD_INIT_COUNT_FILE}"
            fi
            count=$((count + 1))
            printf "%s\n" "${count}" > "${FAKE_CLOUD_INIT_COUNT_FILE}"
            if [[ "${count}" -ge "${FAKE_CLOUD_INIT_READY_AFTER}" ]]; then
                cat "${FAKE_CLOUD_INIT_FIXTURE_DIR}/done.txt"
            else
                cat "${FAKE_CLOUD_INIT_FIXTURE_DIR}/running.txt"
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

    cat > "${FAKEBIN}/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "${FAKE_REFRESH_LOG}"
[[ "${FAKE_REFRESH_FAIL:-0}" == 0 ]] || exit 1
if [[ "$*" == *' -F '* && "${FAKE_REFRESH_LOOKUP_RC:-0}" != 0 ]]; then
    exit "${FAKE_REFRESH_LOOKUP_RC}"
fi
exec "${REAL_SSH_KEYGEN}" "$@"
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
    chmod +x "${FAKEBIN}/ssh-keygen"
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

# Prints the probe output fixture for one cloud-init state (done, running,
# or error) so a case passes the same bytes the fake ssh would produce.
function cloud_init_fixture {
    local state="$1"

    cat "${FIXTURE_DIR}/${state}.txt"
}

function run_create_vm {
    local status_output="$1"
    local action="$2"
    local output_file="${WORKSPACE}/output.txt"
    local rc=0
    local domain_state="running"
    local dominfo_rc=1
    local -a args=("-o" "${CASE_OS_TYPE:-rocky8}" "-n" "${CASE_NODE_ID:-main}" "-d" "${CASE_IMAGE_DIR:-${WORKSPACE}/images}" "-p" "${CASE_PREFIX:-lab}")

    [[ "${CASE_REFRESH_HOST_KEY:-0}" != 1 ]] || args+=(-R)

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
    FAKE_CLOUD_INIT_FIXTURE_DIR="${FIXTURE_DIR}" \
    FAKE_DOMAIN_STATE="${domain_state}" \
    FAKE_DOMINFO_RC="${CASE_DOMINFO_RC:-${dominfo_rc}}" \
    FAKE_SSH_EXIT_RC="${FAKE_SSH_EXIT_RC:-0}" \
    FAKE_SSH_STDERR="${FAKE_SSH_STDERR:-}" \
    FAKE_CHECK_KNOWN_HOSTS="${FAKE_CHECK_KNOWN_HOSTS:-0}" \
    FAKE_REFRESH_LOG="${WORKSPACE}/refresh.log" \
    FAKE_REFRESH_FAIL="${FAKE_REFRESH_FAIL:-0}" \
    FAKE_REFRESH_LOOKUP_RC="${FAKE_REFRESH_LOOKUP_RC:-0}" \
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
    FAKE_DOMAIN_MAC="${FAKE_DOMAIN_MAC:-}" \
    FAKE_VIRSH_LOG="${FAKE_VIRSH_LOG:-}" \
    FAKE_UNDEFINED_MARKER="${FAKE_UNDEFINED_MARKER:-}" \
    FAKE_RESERVATION_FILE="${FAKE_RESERVATION_FILE:-}" \
    FAKE_CONFIG_RESERVATION_FILE="${FAKE_CONFIG_RESERVATION_FILE:-}" \
    FAKE_NET_DUMP_FAIL="${FAKE_NET_DUMP_FAIL:-}" \
    FAKE_NET_UPDATE_LOG="${FAKE_NET_UPDATE_LOG:-}" \
    FAKE_LEASE_FILE="${FAKE_LEASE_FILE:-}" \
    FAKE_LEASE_FAIL="${FAKE_LEASE_FAIL:-}" \
    FAKE_LEASE_FIXTURE_DIR="${TOP}/tests/fixtures/dhcp" \
    FAKE_NET_UPDATE_RC="${FAKE_NET_UPDATE_RC:-0}" \
    FAKE_DESTROY_RC="${FAKE_DESTROY_RC:-0}" \
    FAKE_UNDEFINE_RC="${FAKE_UNDEFINE_RC:-0}" \
    FAKE_LIST_RC="${FAKE_LIST_RC:-0}" \
    FAKE_LIST_DOMAIN="${FAKE_LIST_DOMAIN:-lab-rocky8-main}" \
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
        run_create_vm "$(cloud_init_fixture "done")" "provision")
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

# Real ssh-keygen mutates a temporary known_hosts file. The SSH transport
# rejects a stored old identity, so success requires the actual removal path.
function run_host_key_refresh_case {
    local mode="$1"
    local action="provision"
    local node=main
    local state="shut off"
    local refresh=1
    local fail=0
    local lookup_rc=0
    local dominfo_rc=""
    local expected_rc=0
    local expected_text='READY'
    local known_hosts="${WORKSPACE}/home/.ssh/known_hosts"
    local refresh_log="${WORKSPACE}/refresh.log"
    local ssh_log="${WORKSPACE}/refresh-ssh.log"
    local original="${WORKSPACE}/refresh-original"
    local key_type key_body
    local result output target_rc=0 unrelated_rc=0

    mkdir -p "${WORKSPACE}/home/.ssh"
    read -r key_type key_body _ < "${WORKSPACE}/host-key.pub"
    printf '%s %s %s\n' 192.168.123.100 "${key_type}" "${key_body}" > "${known_hosts}"
    printf '%s %s %s\n' 192.0.2.1 "${key_type}" "${key_body}" >> "${known_hosts}"
    : > "${refresh_log}"
    : > "${ssh_log}"
    case "${mode}" in
        default) refresh=0; expected_rc=1; expected_text='different host key' ;;
        # A new domain refreshes its address without -R; the stopped restart
        # above keeps the rejection.
        new-static|new-dhcp)
            refresh=0; state=absent; dominfo_rc=1
            [[ "${mode}" != new-dhcp ]] || node=dhcp
            mkdir -p "${WORKSPACE}/images"
            printf '%s\n' 'ssh-ed25519 AAAAC3NzaFixture test' > "${WORKSPACE}/home/.ssh/id_ed25519.pub"
            printf '%s\n' base > "${WORKSPACE}/images/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2"
            ;;
        dhcp) node=dhcp ;;
        hashed) "${REAL_SSH_KEYGEN}" -H -f "${known_hosts}" >/dev/null 2>&1 ;;
        aliases)
            printf '%s %s %s\n' 192.168.123.100,192.0.2.1 "${key_type}" "${key_body}" \
                > "${known_hosts}"
            ;;
        pattern)
            printf '%s %s %s\n' '192.168.*,192.0.2.1' "${key_type}" "${key_body}" \
                > "${known_hosts}"
            expected_rc=1; expected_text='cannot refresh a shared host pattern'
            ;;
        lookup-failure)
            printf '%s %s %s\n' '192.168.*,192.0.2.1' "${key_type}" "${key_body}" \
                > "${known_hosts}"
            lookup_rc=255; expected_rc=1; expected_text='failed to refresh'
            ;;
        unmatched)
            printf '%s %s %s\n' 192.0.2.1 "${key_type}" "${key_body}" > "${known_hosts}"
            ;;
        running) state=running; expected_text='already running' ;;
        failure) fail=1; expected_rc=1; expected_text='failed to refresh' ;;
        status|stop|cleanup)
            action="${mode}"; expected_rc=1; expected_text='-R is valid only for provisioning'
            ;;
        missing) rm -f -- "${known_hosts}" ;;
    esac
    [[ ! -f "${known_hosts}" ]] || cp -p -- "${known_hosts}" "${original}"
    reset_sleep_log
    result=$(CASE_REFRESH_HOST_KEY="${refresh}" CASE_NODE_ID="${node}" \
        CASE_DOMINFO_RC="${dominfo_rc}" \
        FAKE_STATE_OVERRIDE="${state}" FAKE_CHECK_KNOWN_HOSTS=1 \
        FAKE_REFRESH_FAIL="${fail}" SSH_ARG_LOG="${ssh_log}" \
        FAKE_REFRESH_LOOKUP_RC="${lookup_rc}" \
        run_create_vm "$(cloud_init_fixture "done")" "${action}")
    output="${result#*$'\n'}"
    expect_exit "host key ${mode} exit" "${expected_rc}" "${result%%$'\n'*}"
    expect_contains "host key ${mode} output" "${output}" "${expected_text}"
    "${REAL_SSH_KEYGEN}" -F 192.168.123.100 -f "${known_hosts}" \
        >/dev/null 2>&1 || target_rc=$?
    "${REAL_SSH_KEYGEN}" -F 192.0.2.1 -f "${known_hosts}" \
        >/dev/null 2>&1 || unrelated_rc=$?
    case "${mode}" in
        default|status|stop|cleanup|failure|pattern|lookup-failure)
            expect_equal "host key ${mode} retains target" 0 "${target_rc}"
            ;;
        missing) ;;
        *) expect_equal "host key ${mode} removes target" 1 "${target_rc}" ;;
    esac
    if [[ "${mode}" != missing ]]; then
        expect_equal "host key ${mode} retains unrelated key" 0 "${unrelated_rc}"
    fi
    case "${mode}" in
        default|status|stop|cleanup|missing)
            expect_equal "host key ${mode} does not invoke removal" '' "$(cat "${refresh_log}")"
            ;;
        lookup-failure)
            expect_equal 'lookup failure does not invoke removal' 0 \
                "$(grep -c -- '-R ' "${refresh_log}" || true)"
            if cmp -s -- "${original}" "${known_hosts}"; then
                record_pass 'lookup failure preserves original known_hosts bytes'
            else
                record_fail 'lookup failure preserves original known_hosts bytes' 'file changed'
            fi
            ;;
        pattern) ;;
        *)
            expect_equal "host key ${mode} removes exactly once" 1 \
                "$(grep -c -- '-R ' "${refresh_log}")"
            expect_contains "host key ${mode} removes resolved address" \
                "$(cat "${refresh_log}")" '-R 192.168.123.100'
            ;;
    esac
    if [[ "${mode}" == failure || "${mode}" == pattern || "${mode}" == lookup-failure ]]; then
        expect_equal "host key removal failure precedes SSH" '' "$(cat "${ssh_log}")"
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
    result=$(CASE_NODE_ID=dhcp FAKE_DOMIFADDR_READY_AFTER="${ready_after}" \
        FAKE_DOMIFADDR_COUNT_FILE="${count_file}" \
        run_create_vm "$(cloud_init_fixture "done")" "provision")
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
        run_create_vm "$(cloud_init_fixture "done")" "provision")
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
        run_create_vm "$(cloud_init_fixture running)" "provision")
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
        run_create_vm "$(cloud_init_fixture running)" "provision")
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

    result=$(run_create_vm "$(cloud_init_fixture "done")" "status")
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
        run_create_vm "$(cloud_init_fixture "done")" "stop")
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
        run_create_vm "$(cloud_init_fixture "done")" "stop")
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
        run_create_vm "$(cloud_init_fixture "done")" "${action}")
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
    result=$(FAKE_LIBVIRT_DOWN=1 run_create_vm "$(cloud_init_fixture "done")" "${action}")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    expect_exit "${name} exit" "${want_rc}" "${rc}"
    expect_contains "${name} message" "${output}" "${want_text}"
    expect_not_contains "${name} not absent" "${output}" "to provision"
}

# Existing independent disks remain manageable without a source image pair.
# Each case uses its own image directory so a previous case cannot supply one.
function run_without_golden_case {
    local os_type="$1"
    local action="$2"
    local state="$3"
    local expected_rc="$4"
    local expected_text="$5"
    local name="${os_type} without golden ${action} ${state}"
    local image_dir="${WORKSPACE}/without-golden-${os_type}-${action}-${state}"
    local disk="${image_dir}/lab-${os_type}-main.qcow2"
    local record="${disk}.creation-record"
    local seed="${image_dir}/lab-${os_type}-main-seed.iso"
    local marker="${image_dir}/shutdown-marker"
    local result output
    local dominfo_rc=0

    mkdir -p "${image_dir}"
    printf '%s\n' 'independent disk fixture' > "${disk}"
    printf '%s\n' 'consumer record fixture' > "${record}"
    printf '%s\n' 'seed fixture' > "${seed}"
    [[ "${state}" != absent ]] || dominfo_rc=1
    reset_sleep_log
    : > "${QEMU_IMG_LOG}"
    result=$(CASE_OS_TYPE="${os_type}" CASE_IMAGE_DIR="${image_dir}" \
        CASE_DOMINFO_RC="${dominfo_rc}" FAKE_STATE_OVERRIDE="${state}" \
        FAKE_SHUTDOWN_MARKER="${marker}" \
        FAKE_RESERVATION_FILE="${TOP}/tests/fixtures/dhcp/empty.xml" \
        run_create_vm "$(cloud_init_fixture "done")" "${action}")
    output="${result#*$'\n'}"
    expect_exit "${name} exit" "${expected_rc}" "${result%%$'\n'*}"
    expect_contains "${name} result" "${output}" "${expected_text}"
    expect_equal "${name} does not inspect or copy an image" '' "$(cat "${QEMU_IMG_LOG}")"
    if [[ "${action}" == cleanup ]]; then
        if [[ ! -e "${disk}" && ! -e "${record}" && ! -e "${seed}" ]]; then
            record_pass "${name} removes VM artifacts"
        else
            record_fail "${name} removes VM artifacts" 'VM artifacts remain'
        fi
    else
        if [[ -s "${disk}" && -s "${record}" && -s "${seed}" ]]; then
            record_pass "${name} preserves VM artifacts"
        else
            record_fail "${name} preserves VM artifacts" 'VM artifacts changed'
        fi
    fi
    if [[ "${action}" == status ]]; then
        expect_not_contains "${name} omits base image" "${output}" 'Base image :'
    fi
}

# Exercises image selection through new provisioning with real source files and
# records; only the image-tool, libvirt and SSH command boundaries are replaced.
function run_selection_case {
    local os_type="$1"
    local want_line="$2"
    local result output
    local image_name

    mkdir -p "${WORKSPACE}/home/.ssh" "${WORKSPACE}/images"
    printf '%s\n' 'ssh-ed25519 AAAAC3NzaFixture test' \
        > "${WORKSPACE}/home/.ssh/id_ed25519.pub"
    case "${os_type}" in
        rocky8|rocky8-epics-dev)
            image_name="Rocky-8-GenericCloud-Base.latest.x86_64.qcow2"
            ;;
        debian13-rtbase)
            image_name="debian-13-genericcloud-amd64-20260601-2496.qcow2"
            ;;
        rocky8-iocrunner)
            write_baked_image_fixture "iocrunner" "rocky8"
            image_name="iocrunner-rocky8-20260812T000000Z-abcdef123456.qcow2"
            ;;
    esac
    printf '%s\n' 'base fixture' > "${WORKSPACE}/images/${image_name}"
    reset_sleep_log
    result=$(CASE_OS_TYPE="${os_type}" CASE_NODE_ID=selection CASE_DOMINFO_RC=1 \
        FAKE_STATE_OVERRIDE=absent run_create_vm "$(cloud_init_fixture "done")" "provision")
    output="${result#*$'\n'}"
    expect_exit "select ${os_type} creation exit" 0 "${result%%$'\n'*}"
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
    result=$(CASE_OS_TYPE="${consumer_os}" CASE_NODE_ID=pair CASE_DOMINFO_RC=1 \
        FAKE_STATE_OVERRIDE=absent run_create_vm "$(cloud_init_fixture "done")" "provision")
    output="${result#*$'\n'}"
    expect_exit "bake pair ${bake_os} creation exit" 0 "${result%%$'\n'*}"
    expect_contains "bake pair ${bake_os}" "${output}" "Base image : ${derived}"
}

function run_cleanup_pair_case {
    local disk="${WORKSPACE}/images/lab-rocky8-main.qcow2"
    local record="${disk}.creation-record"
    local seed="${WORKSPACE}/images/lab-rocky8-main-seed.iso"
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

function run_cleanup_teardown_case {
    local name="$1"
    local state="$2"
    local destroy_rc="$3"
    local undefine_rc="$4"
    local list_rc="$5"
    local expected_rc="$6"
    local disk="${WORKSPACE}/images/lab-rocky8-main.qcow2"
    local record="${disk}.creation-record"
    local seed="${WORKSPACE}/images/lab-rocky8-main-seed.iso"
    local log="${WORKSPACE}/teardown-${name}.log"
    local result commands

    printf '%s\n' disk > "${disk}"
    printf '%s\n' record > "${record}"
    printf '%s\n' seed > "${seed}"
    : > "${log}"
    result=$(FAKE_STATE_OVERRIDE="${state}" FAKE_DESTROY_RC="${destroy_rc}" \
        FAKE_UNDEFINE_RC="${undefine_rc}" FAKE_LIST_RC="${list_rc}" \
        FAKE_VIRSH_LOG="${log}" \
        FAKE_RESERVATION_FILE="${TOP}/tests/fixtures/dhcp/empty.xml" \
        run_create_vm "" cleanup)
    expect_exit "cleanup ${name} exit" "${expected_rc}" "${result%%$'\n'*}"
    commands="$(< "${log}")"
    if [[ "${expected_rc}" == 0 ]]; then
        if [[ ! -e "${disk}" && ! -e "${record}" && ! -e "${seed}" ]]; then
            record_pass "cleanup ${name} removes files"
        else
            record_fail "cleanup ${name} removes files" 'resources remain'
        fi
        if [[ "${name}" == already-absent ]]; then
            result=$(FAKE_STATE_OVERRIDE=absent FAKE_DESTROY_RC=1 FAKE_UNDEFINE_RC=1 \
                FAKE_RESERVATION_FILE="${TOP}/tests/fixtures/dhcp/empty.xml" \
                run_create_vm "" cleanup)
            expect_exit 'cleanup absent repeat exit' 0 "${result%%$'\n'*}"
            if [[ ! -e "${disk}" && ! -e "${record}" && ! -e "${seed}" ]]; then
                record_pass 'cleanup absent repeat leaves files absent'
            else
                record_fail 'cleanup absent repeat leaves files absent' 'resources remain'
            fi
        fi
    else
        expect_contains "cleanup ${name} reports preservation" "${result}" 'were preserved'
        if [[ -f "${disk}" && -f "${record}" && -f "${seed}" ]]; then
            record_pass "cleanup ${name} preserves all files"
        else
            record_fail "cleanup ${name} preserves all files" 'resources were removed'
        fi
        if [[ "${destroy_rc}" != 0 && "${state}" != 'shut off' ]]; then
            expect_not_contains "cleanup ${name} stops before undefine" "${commands}" undefine
        fi
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
    result=$(CASE_OS_TYPE="rocky8-iocrunner" CASE_DOMINFO_RC=1 \
        FAKE_STATE_OVERRIDE=absent run_create_vm "$(cloud_init_fixture "done")" "provision")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"
    expect_exit "${name} exit" "1" "${rc}"
    expect_contains "${name} rejects the pair" "${output}" \
        "no valid iocrunner image found for rocky8"
}

function run_invalid_run_id_case {
    local result rc output

    result=$(CASE_RUN_ID="manual-run" run_create_vm "$(cloud_init_fixture "done")" "status")
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
        FAKE_STATE_OVERRIDE="absent" run_create_vm "$(cloud_init_fixture "done")" "provision")
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
# on what the fake genisoimage recorded. Seed staging is the subject: a bug
# report showed two concurrent runs sharing one staging directory, interleaving
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
        run_create_vm "$(cloud_init_fixture "done")" "provision")
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
    expect_contains "${name} own VM name" "${staged_meta}" "local-hostname: lab-rocky8-main"

    # genisoimage writes statistics to stderr even when it succeeds. They must
    # not reach the operator: the success line stays one line.
    expect_not_contains "${name} no genisoimage noise" "${output}" "extents written"
    expect_contains "${name} reports OK" "${output}" "cloud-init ISO... [OK]"

    resize_line="$(grep '^resize ' "${QEMU_IMG_LOG}" | tail -n 1 || true)"
    expect_equal "${name} resizes the VM disk" \
        "resize ${WORKSPACE}/images/lab-rocky8-main.qcow2 20G" \
        "${resize_line}"
}

# Exercises bounded guest hostnames through the public provisioning action.
function run_hostname_case {
    local name="$1"
    local prefix="$2"
    local expected="$3"
    local result hostname meta

    result=$(CASE_PREFIX="${prefix}" CASE_DOMINFO_RC=1 FAKE_STATE_OVERRIDE=absent \
        run_create_vm "$(cloud_init_fixture "done")" provision)
    expect_exit "${name} exit" 0 "${result%%$'\n'*}"
    meta="$(< "${WORKSPACE}/seed-meta.txt")"
    hostname="$(sed -n 's/^local-hostname: //p' <<< "${meta}")"
    expect_equal "${name} hostname" "${expected}" "${hostname}"
    expect_equal "${name} length" 63 "${#hostname}"
    expect_contains "${name} full domain identity" "${result#*$'\n'}" \
        "VM Name    : ${prefix}-rocky8-main"
    expect_contains "${name} full seed identity" "$(< "${WORKSPACE}/seed-path.txt")" \
        "${prefix}-rocky8-main.seed_staging/meta-data"
}

# A failing genisoimage stops provisioning and exposes the diagnostic output.
function run_seed_failure_case {
    local name="$1"
    local result rc output

    mkdir -p "${WORKSPACE}/home/.ssh" "${WORKSPACE}/images"
    printf "%s\n" "ssh-ed25519 AAAAC3NzaFixture test" \
        > "${WORKSPACE}/home/.ssh/id_ed25519.pub"
    printf "%s\n" "base" > "${WORKSPACE}/images/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2"

    reset_sleep_log
    result=$(CASE_DOMINFO_RC=1 FAKE_STATE_OVERRIDE="absent" FAKE_GENISOIMAGE_FAIL=1 \
        run_create_vm "$(cloud_init_fixture "done")" "provision")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"

    expect_exit "${name} exit" "1" "${rc}"
    expect_not_contains "${name} not OK" "${output}" "cloud-init ISO... [OK]"
    expect_contains "${name} names the reason" "${output}" "Unable to open disc image file"
    expect_contains "${name} keeps the staging" "${output}" "Staging left for inspection"
}

# Address assignment: an address must identify a VM, not a node name.
# Hashing NODE_ID alone gave every OS type the same address and MAC for a
# given node ID, so the second VM could not be created at all. Known node IDs
# are asserted separately because they must not move - existing VMs record
# their addresses and downstream notes cite them.
function run_address_case {
    local name="$1"
    local os_type="$2"
    local node_id="$3"
    local want_last="$4"
    local result output got

    case "${os_type}" in
        rocky8-iocrunner)       write_baked_image_fixture "iocrunner" "rocky8" ;;
        debian13-iocrunner)     write_baked_image_fixture "iocrunner" "debian13" ;;
        rocky8-iocrunner-nfs)   write_baked_image_fixture "iocrunner-nfs" "rocky8" ;;
        debian13-iocrunner-nfs) write_baked_image_fixture "iocrunner-nfs" "debian13" ;;
        debian13-ethercat)      write_baked_image_fixture "ethercat" "debian13" ;;
    esac
    reset_sleep_log
    result=$(CASE_OS_TYPE="${os_type}" CASE_NODE_ID="${node_id}" \
        run_create_vm "$(cloud_init_fixture "done")" "status")
    output="${result#*$'\n'}"
    got="$(grep -oE 'mapped to 192\.168\.123\.[0-9]+|IP Address : 192\.168\.123\.[0-9]+' <<< "${output}" \
        | grep -oE '[0-9]+$' | head -1)"
    expect_equal "${name}" "${want_last}" "${got:-none}"
}

# The core address rule: the same unknown node ID across OS types must not
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
            run_create_vm "$(cloud_init_fixture "done")" "status")
        output="${result#*$'\n'}"
        got="$(grep -oE 'mapped to 192\.168\.123\.[0-9]+' <<< "${output}" \
            | grep -oE '[0-9]+$' | head -1)"
        seen+=("${got:-none}")
    done
    unique="$(printf "%s\n" "${seen[@]}" | sort -u | wc -l | tr -d '[:space:]')"
    expect_equal "unknown node ${node_id} gives one address per OS type" \
        "${#seen[@]}" "${unique}"
}

# The DHCP collision guard must compare whole address fields. Matching by
# substring or regex would read 192.168.123.150 as held by the entry for
# 192.168.123.1501 and refuse a VM whose address is free - a guard that blocks
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
        run_create_vm "$(cloud_init_fixture "done")" "provision")
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

# A lease outlives its reservation. A new domain whose address is still leased
# to another MAC must stop before any disk, seed or reservation exists, and must
# tell a live holder (still reserved, so waiting cannot help) from an orphan
# lease; its own lease, a lease for another address, or no lease must not stop
# it. Only the
# virsh transport is replaced, with shipped lease fixtures.
function run_lease_case {
    local name="$1"
    local fixture="$2"
    local want_rc="$3"
    local want_text="$4"
    local reservation="${5:-}"
    local log="${WORKSPACE}/lease-net-update.log"
    local lease_fail=0
    local result rc output before after

    mkdir -p "${WORKSPACE}/home/.ssh" "${WORKSPACE}/images"
    printf '%s\n' 'ssh-ed25519 AAAAC3NzaFixture test' > "${WORKSPACE}/home/.ssh/id_ed25519.pub"
    printf '%s\n' base > "${WORKSPACE}/images/Rocky-8-GenericCloud-Base.latest.x86_64.qcow2"
    rm -f -- "${WORKSPACE}/seed-path.txt"
    : > "${log}"
    [[ "${fixture}" != failure ]] || lease_fail=1
    before=$(wc -l < "${QEMU_IMG_LOG}")
    reset_sleep_log
    result=$(CASE_DOMINFO_RC=1 FAKE_STATE_OVERRIDE=absent \
        FAKE_LEASE_FAIL="${lease_fail}" \
        FAKE_LEASE_FILE="${TOP}/tests/fixtures/dhcp/leases-${fixture}.txt" \
        FAKE_RESERVATION_FILE="${reservation:+${TOP}/tests/fixtures/dhcp/${reservation}.xml}" \
        FAKE_NET_UPDATE_LOG="${log}" \
        run_create_vm "$(cloud_init_fixture "done")" provision)
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"
    after=$(wc -l < "${QEMU_IMG_LOG}")

    expect_exit "${name} exit" "${want_rc}" "${rc}"
    expect_contains "${name} result" "${output}" "${want_text}"
    if [[ "${want_rc}" == 0 ]]; then
        expect_contains "${name} reached registration" "${output}" 'Network: registering'
    else
        expect_equal "${name} touches no disk" "${before}" "${after}"
        expect_equal "${name} adds no reservation" '' "$(< "${log}")"
        if [[ -e "${WORKSPACE}/seed-path.txt" ]]; then
            record_fail "${name} stages no seed" 'seed staging recorded'
        else
            record_pass "${name} stages no seed"
        fi
    fi
}

# Drives the public provisioning and cleanup actions with shipped network XML
# fixtures. Only the virsh transport is replaced; ownership logic is real.
function run_dhcp_case {
    local name="$1"
    local fixture="$2"
    local action="$3"
    local want_rc="$4"
    local want_deletes="$5"
    local want_adds="$6"
    local config_fixture="${7:-${fixture}}"
    local log="${WORKSPACE}/net-update.log"
    local result rc output updates deletes adds

    mkdir -p "${WORKSPACE}/home/.ssh" "${WORKSPACE}/images"
    printf '%s\n' 'ssh-ed25519 AAAAC3NzaFixture test' > "${WORKSPACE}/home/.ssh/id_ed25519.pub"
    write_baked_image_fixture iocrunner rocky8
    : > "${log}"
    result=$(CASE_OS_TYPE=rocky8-iocrunner CASE_DOMINFO_RC=1 \
        FAKE_STATE_OVERRIDE=absent \
        FAKE_RESERVATION_FILE="${TOP}/tests/fixtures/dhcp/${fixture}.xml" \
        FAKE_CONFIG_RESERVATION_FILE="${TOP}/tests/fixtures/dhcp/${config_fixture}.xml" \
        FAKE_NET_UPDATE_LOG="${log}" \
        run_create_vm "$(cloud_init_fixture "done")" "${action}")
    rc="${result%%$'\n'*}"
    output="${result#*$'\n'}"
    updates="$(< "${log}")"
    deletes=$(grep -c ' delete ip-dhcp-host ' "${log}" || true)
    adds=$(grep -c ' add ip-dhcp-host ' "${log}" || true)
    expect_exit "${name} exit" "${want_rc}" "${rc}"
    expect_equal "${name} deletion count" "${want_deletes}" "${deletes}"
    expect_equal "${name} addition count" "${want_adds}" "${adds}"
    expect_not_contains "${name} uses MAC/IP selectors" "${updates}" 'name='
    if [[ "${want_rc}" == 0 && "${action}" == provision ]]; then
        expect_contains "${name} reaches readiness" "${output}" 'READY'
        expect_contains "${name} uses a local unicast MAC" "${output}" 'MAC Address: 02:'
    fi
}

# A failed DHCP cleanup preserves identity and files for a successful retry.
function run_cleanup_retry_case {
    local failure="$1"
    local disk="${WORKSPACE}/images/lab-rocky8-iocrunner-main.qcow2"
    local record="${disk}.creation-record"
    local seed="${WORKSPACE}/images/lab-rocky8-iocrunner-main-seed.iso"
    local marker="${WORKSPACE}/undefined-${failure}"
    local log="${WORKSPACE}/cleanup-${failure}.log"
    local updates="${WORKSPACE}/cleanup-${failure}-updates.log"
    local read_failure=0 update_failure=0 result commands

    [[ "${failure}" != read ]] || read_failure=1
    [[ "${failure}" != delete ]] || update_failure=1
    printf '%s\n' disk > "${disk}"
    printf '%s\n' record > "${record}"
    printf '%s\n' seed > "${seed}"
    : > "${log}"
    : > "${updates}"
    result=$(CASE_OS_TYPE=rocky8-iocrunner CASE_DOMINFO_RC=0 \
        FAKE_DOMAIN_MAC=02:00:00:00:00:01 FAKE_UNDEFINED_MARKER="${marker}" \
        FAKE_VIRSH_LOG="${log}" FAKE_NET_UPDATE_LOG="${updates}" \
        FAKE_RESERVATION_FILE="${TOP}/tests/fixtures/dhcp/unnamed-conflict.xml" \
        FAKE_NET_DUMP_FAIL="${read_failure}" FAKE_NET_UPDATE_RC="${update_failure}" \
        run_create_vm "" cleanup)
    expect_exit "cleanup ${failure} failure exit" 1 "${result%%$'\n'*}"
    commands="$(< "${log}")"
    expect_not_contains "cleanup ${failure} preserves running domain" "${commands}" destroy
    expect_not_contains "cleanup ${failure} preserves defined domain" "${commands}" undefine
    if [[ -f "${disk}" && -f "${record}" && -f "${seed}" && ! -e "${marker}" ]]; then
        record_pass "cleanup ${failure} preserves files and domain identity"
    else
        record_fail "cleanup ${failure} preserves files and domain identity" 'resources were removed'
    fi

    : > "${updates}"
    result=$(CASE_OS_TYPE=rocky8-iocrunner CASE_DOMINFO_RC=0 \
        FAKE_DOMAIN_MAC=02:00:00:00:00:01 FAKE_UNDEFINED_MARKER="${marker}" \
        FAKE_NET_UPDATE_LOG="${updates}" \
        FAKE_RESERVATION_FILE="${TOP}/tests/fixtures/dhcp/unnamed-conflict.xml" \
        run_create_vm "" cleanup)
    expect_exit "cleanup ${failure} retry exit" 0 "${result%%$'\n'*}"
    expect_equal "cleanup ${failure} retry removes both reservations" 2 \
        "$(grep -c ' delete ip-dhcp-host ' "${updates}" || true)"
    if [[ ! -e "${disk}" && ! -e "${record}" && ! -e "${seed}" && -f "${marker}" ]]; then
        record_pass "cleanup ${failure} retry removes files and domain"
    else
        record_fail "cleanup ${failure} retry removes files and domain" 'resources remain'
    fi
}

function run_mac_identity_case {
    local result output first repeat second run_mac

    mkdir -p "${WORKSPACE}/home/.ssh" "${WORKSPACE}/images"
    printf '%s\n' 'ssh-ed25519 AAAAC3NzaFixture test' > "${WORKSPACE}/home/.ssh/id_ed25519.pub"
    write_baked_image_fixture iocrunner rocky8
    result=$(CASE_OS_TYPE=rocky8-iocrunner CASE_DOMINFO_RC=1 \
        FAKE_STATE_OVERRIDE=absent CASE_PREFIX=identity-a \
        run_create_vm "$(cloud_init_fixture "done")" provision)
    output="${result#*$'\n'}"
    first="$(sed -n 's/^MAC Address: //p' <<< "${output}")"
    expect_exit 'first MAC identity creation exit' 0 "${result%%$'\n'*}"
    result=$(CASE_OS_TYPE=rocky8-iocrunner CASE_DOMINFO_RC=1 \
        FAKE_STATE_OVERRIDE=absent CASE_PREFIX=identity-a \
        run_create_vm "$(cloud_init_fixture "done")" provision)
    repeat="$(sed -n 's/^MAC Address: //p' <<< "${result#*$'\n'}")"
    expect_equal 'same full VM identity retains its MAC' "${first}" "${repeat}"
    result=$(CASE_OS_TYPE=rocky8-iocrunner CASE_DOMINFO_RC=1 \
        FAKE_STATE_OVERRIDE=absent CASE_PREFIX=identity-b \
        run_create_vm "$(cloud_init_fixture "done")" provision)
    second="$(sed -n 's/^MAC Address: //p' <<< "${result#*$'\n'}")"
    expect_exit 'second MAC identity creation exit' 0 "${result%%$'\n'*}"
    if [[ -n "${first}" && -n "${second}" && "${first}" != "${second}" ]]; then
        record_pass 'different prefixes sharing one address have different MACs'
    else
        record_fail 'different prefixes sharing one address have different MACs' "${first} / ${second}"
    fi
    result=$(CASE_OS_TYPE=rocky8-iocrunner CASE_DOMINFO_RC=1 \
        FAKE_STATE_OVERRIDE=absent CASE_PREFIX=identity-a \
        CASE_RUN_ID=20261001T000000Z-abcdef123456 \
        run_create_vm "$(cloud_init_fixture "done")" provision)
    run_mac="$(sed -n 's/^MAC Address: //p' <<< "${result#*$'\n'}")"
    if [[ -n "${run_mac}" && "${run_mac}" != "${first}" ]]; then
        record_pass 'run-specific VM identity has a different MAC'
    else
        record_fail 'run-specific VM identity has a different MAC' "${run_mac} / ${first}"
    fi
    result=$(CASE_DOMINFO_RC=0 FAKE_DOMAIN_MAC=52:54:00:01:64:00 \
        run_create_vm "$(cloud_init_fixture "done")" provision)
    expect_contains 'existing VM preserves its actual interface MAC' \
        "${result#*$'\n'}" 'MAC Address: 52:54:00:01:64:00'
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
    local total multiplexing_offenders timeout_offenders host_key_offenders

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
    host_key_offenders="$(awk \
        '!/-o StrictHostKeyChecking=accept-new/ {count++} END {print count + 0}' \
        "${SSH_ARG_LOG}")"
    printf "  ssh invocations recorded: %s (multiplexing: %s, timeout: %s)\n" \
        "${total}" "${multiplexing_offenders}" "${timeout_offenders}"
    expect_equal "every ssh probe refuses multiplexing" "0" "${multiplexing_offenders}"
    expect_equal "every default SSH probe uses the 5-second connection timeout" \
        "0" "${timeout_offenders}"
    expect_equal 'every SSH probe accepts new keys and rejects changed keys' \
        0 "${host_key_offenders}"
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
"${REAL_SSH_KEYGEN}" -q -t ed25519 -N '' -f "${WORKSPACE}/host-key"

for refresh_mode in default new-static new-dhcp static dhcp hashed aliases pattern lookup-failure unmatched running failure status stop cleanup missing; do
    run_host_key_refresh_case "${refresh_mode}"
done

run_case "status done" "$(cloud_init_fixture "done")" "status" 0 "cloud-init : done"
run_case "status running" "$(cloud_init_fixture running)" "status" 1 "cloud-init : running"
run_case "status error" "$(cloud_init_fixture error)" "status" 1 "cloud-init : error"
run_case "provision done" "$(cloud_init_fixture "done")" "provision" 0 "cloud-init: complete [OK]"
run_rejection_case "provision not complete" "$(cloud_init_fixture running)"
run_rejection_case "provision error" "$(cloud_init_fixture error)"
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
run_cleanup_teardown_case destroy-failure running 1 0 0 1
run_cleanup_teardown_case paused-failure paused 1 0 0 1
run_cleanup_teardown_case undefine-failure 'shut off' 0 1 0 1
run_cleanup_teardown_case list-failure absent 1 1 1 1
run_cleanup_teardown_case undefine-list-failure 'shut off' 0 1 1 1
run_cleanup_teardown_case already-stopped 'shut off' 1 0 0 0
run_cleanup_teardown_case already-absent absent 1 1 0 0
run_outage_case "status outage" "status" 1 "libvirt did not answer"
run_outage_case "stop outage" "stop" 1 "was not checked"
run_outage_case "provision outage" "provision" 1 "nothing was created"

# Independent consumer management and absent-domain creation refusal.
for consumer_os in rocky8-iocrunner debian13-iocrunner rocky8-iocrunner-nfs \
    debian13-iocrunner-nfs debian13-ethercat; do
    run_without_golden_case "${consumer_os}" status running 0 'cloud-init : done'
    run_without_golden_case "${consumer_os}" stop running 0 'shut off [OK]'
    run_without_golden_case "${consumer_os}" cleanup running 0 'Removing disk pair'
    run_without_golden_case "${consumer_os}" provision running 0 'already running'
    run_without_golden_case "${consumer_os}" provision 'shut off' 0 'READY'
    run_without_golden_case "${consumer_os}" provision absent 1 'no valid'
done

# Image selection, ARCHITECTURE section 15.
run_selection_case "rocky8" "Rocky-8-GenericCloud-Base.latest.x86_64.qcow2 (upstream, moving)"
run_selection_case "debian13-rtbase" "debian-13-genericcloud-amd64-20260601-2496.qcow2 (upstream, pinned)"
run_selection_case "rocky8-iocrunner" \
    "iocrunner-rocky8-20260812T000000Z-abcdef123456.qcow2 (baked locally, not downloadable)"
run_selection_case "rocky8-epics-dev" "Rocky-8-GenericCloud-Base.latest.x86_64.qcow2 (upstream, moving)"
run_bake_pair_case "rocky8" "rocky8-iocrunner"
run_bake_pair_case "debian13" "debian13-iocrunner"
run_pair_rejection_case "missing creation record" "missing"
run_pair_rejection_case "mismatched creation record" "mismatched"
run_invalid_run_id_case
run_no_delete_case "unusable golden" "rocky8-iocrunner" \
    "iocrunner-rocky8-20260812T000000Z-abcdef123456.qcow2"

# Seed staging.
run_seed_case "seed"
run_seed_failure_case "seed failure"
run_hostname_case '63-byte name is retained' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-rocky8-main'
run_hostname_case '64-byte name is bounded' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-5a5aa761b3e6'
run_hostname_case '90-byte name is bounded' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-e81c4f881033'
run_hostname_case 'shared prefix keeps a distinct hash' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaac' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-0549eccd1202'
run_hostname_case 'same identity retains its hostname' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab' \
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-e81c4f881033'

# Address assignment.
run_address_case "main instance rocky8-iocrunner" "rocky8-iocrunner" "main" "150"
run_address_case "main instance rocky8-iocrunner-nfs" "rocky8-iocrunner-nfs" "main" "155"
run_address_case "main instance debian13-ethercat" "debian13-ethercat" "main" "70"
run_address_case "hashed instance debian13-ethercat aux" "debian13-ethercat" "aux" "215"
run_address_distinct_case "probe" rocky8 debian13 rocky10 rocky8-iocrunner debian13-ethercat rocky8-epics-dev

# DHCP reservation guard. rocky8-iocrunner main maps to 192.168.123.150.
run_reservation_case "reservation guard ignores a longer address" "192.168.123.1501" "no"
run_reservation_case "reservation guard fires on the same address" "192.168.123.150" "yes"
run_lease_case 'foreign lease stops a new domain' foreign 1 \
    'is leased to MAC 02:aa:bb:cc:dd:ee until 2026-10-03 23:14:08'
run_lease_case 'unreadable leases stop a new domain' failure 1 'cannot read the DHCP leases'
run_lease_case 'orphan lease names its expiry as the retry point' foreign 1 \
    'retry after the lease expires'
run_lease_case 'a reserved holder is reported as a VM in use' foreign 1 \
    'is in use by the VM with MAC 02:aa:bb:cc:dd:ee' lease-holder
FAKE_NET_DUMP_FAIL=1 run_lease_case 'a foreign lease with unreadable reservations stops' \
    foreign 1 'its reservations cannot be read'
run_lease_case 'own lease proceeds' owned 0 'READY'
run_lease_case 'no lease proceeds' empty 0 'READY'
run_dhcp_case 'unnamed IP conflict' unnamed-conflict provision 1 0 0
run_dhcp_case 'persistent-only IP conflict' empty provision 1 0 0 unnamed-conflict
run_dhcp_case 'legacy named migration' legacy-owned provision 0 2 1
run_dhcp_case 'unnamed reservation replacement' unnamed-owned provision 0 2 1
run_dhcp_case 'unnamed reservation cleanup' unnamed-owned cleanup 0 2 0
run_dhcp_case 'same MAC at another IP is refused' mac-conflict provision 1 0 0
FAKE_NET_UPDATE_RC=1 run_dhcp_case 'failed deletion prevents addition' legacy-owned provision 1 1 0
run_dhcp_case 'legacy orphan cleanup' legacy-owned cleanup 0 2 0
run_dhcp_case 'foreign legacy name is preserved' legacy-foreign cleanup 0 0 0
run_dhcp_case 'unnamed foreign reservation is preserved' unnamed-conflict cleanup 0 0 0
FAKE_NET_DUMP_FAIL=1 run_dhcp_case 'network read failure prevents registration' empty provision 1 0 0
run_mac_identity_case
run_cleanup_retry_case read
run_cleanup_retry_case delete

# SSH readiness contract, ARCHITECTURE section 13. Asserted last so it covers
# every probe every case above drove.
assert_ssh_multiplexing_off

print_summary
