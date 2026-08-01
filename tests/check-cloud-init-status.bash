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

    cat > "${FAKEBIN}/qemu-img" <<'EOF'
#!/usr/bin/env bash
# Only "info" is used by the selection path under test. FAKE_QEMU_IMG_FAIL
# reproduces an inspection that cannot describe the image - a lock held by a
# running consumer looks exactly like this - without corrupting a fixture.
set -e
if [[ "$1" == "info" ]]; then
    if [[ "${FAKE_QEMU_IMG_FAIL:-}" == "1" ]]; then
        printf "qemu-img: Failed to get shared write lock\n" >&2
        exit 1
    fi
    printf "file format: qcow2\n"
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
    FAKE_LIBVIRT_DOWN="${FAKE_LIBVIRT_DOWN:-}" \
    FAKE_SHUTDOWN_MARKER="${FAKE_SHUTDOWN_MARKER:-}" \
    FAKE_QEMU_IMG_FAIL="${FAKE_QEMU_IMG_FAIL:-}" \
    FAKE_GENISOIMAGE_FAIL="${FAKE_GENISOIMAGE_FAIL:-}" \
    FAKE_SEED_PATH_LOG="${WORKSPACE}/seed-path.txt" \
    FAKE_SEED_META_COPY="${WORKSPACE}/seed-meta.txt" \
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

# Asserts the base image an OS type selects, and its class, through the public
# status path. Selection is decided before anything is created, so this needs no
# image, no libvirt, and no network.
function run_selection_case {
    local os_type="$1"
    local want_line="$2"
    local result output

    reset_sleep_log
    result=$(CASE_OS_TYPE="${os_type}" run_create_vm $'status: done\n' "status")
    output="${result#*$'\n'}"
    expect_contains "select ${os_type}" "${output}" "${want_line}"
}

# A bake output name and the consumer input name that reads it are one pair,
# spelled in two files. This derives the bake's name and asserts a consumer
# selects exactly it, so a divergence introduced in either file fails here.
function run_bake_pair_case {
    local bake_os="$1"
    local consumer_os="$2"
    local derived result output

    derived="iocrunner-${bake_os}.qcow2"
    reset_sleep_log
    result=$(CASE_OS_TYPE="${consumer_os}" run_create_vm $'status: done\n' "status")
    output="${result#*$'\n'}"
    expect_contains "bake pair ${bake_os}" "${output}" "Base image : ${derived}"
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
    local result rc output staged_path staged_meta hostname_count

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

# Image selection, ARCHITECTURE section 15.
run_selection_case "rocky8" "Rocky-8-GenericCloud-Base.latest.x86_64.qcow2 (upstream, moving)"
run_selection_case "debian13-rtbase" "debian-13-genericcloud-amd64-20260601-2496.qcow2 (upstream, pinned)"
run_selection_case "rocky8-iocrunner" "iocrunner-rocky8.qcow2 (baked locally, not downloadable)"
run_selection_case "epics-env-rocky8" "Rocky-8-GenericCloud-Base.latest.x86_64.qcow2 (upstream, moving)"
run_bake_pair_case "rocky8" "rocky8-iocrunner"
run_bake_pair_case "debian13" "debian13-iocrunner"
run_no_delete_case "unusable golden" "rocky8-iocrunner" "iocrunner-rocky8.qcow2"

# Seed staging, issue #22.
run_seed_case "seed"
run_seed_failure_case "seed failure"

# Address assignment, issue #27.
run_address_case "known node rocky8-iocrunner server" "rocky8-iocrunner" "server" "150"
run_address_case "known node rocky8-iocrunner node2" "rocky8-iocrunner" "node2" "152"
run_address_case "known node debian13-ethercat node1" "debian13-ethercat" "node1" "71"
run_address_distinct_case "probe" rocky8 debian13 rocky8-iocrunner debian13-ethercat epics-env-rocky8

print_summary
