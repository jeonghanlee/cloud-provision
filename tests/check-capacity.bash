#!/usr/bin/env bash
#
# Verifies the capacity decision of bin/check_capacity.bash.
#
# Replaced command boundary: virsh, df, and the meminfo file. They are the
# hypervisor and host-measurement boundaries the script reads. Every disk is a
# real qcow2 image read by the real qemu-img, and every expected number is
# derived here from independent inputs: the image sizes come from stat, and the
# memory and margin figures are fixed constants in this file. The option
# parsing, the validation, the arithmetic, and the exit statuses all execute
# for real.
#
# Scenario inputs: each case writes the files the fake virsh serves (running
# list, all list, dominfo, domblklist, dommemstat per guest), a meminfo file,
# and a df answer, then runs the script and checks its exit status and output.

set -e

declare -g SCRIPT_DIR
declare -g TOP
declare -g WORKSPACE
declare -g FAKEBIN
declare -g SCENARIO
declare -g IMAGES
declare -g MEMINFO
declare -g DF_ANSWER
declare -g OUTPUT=""
declare -g STATUS=0
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -ag FAILED_DETAILS=()

declare -gr GIB=1073741824
declare -gr MEM_TOTAL_KB=67108864

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"

function cleanup {
    local rc=$?
    if [[ -n "${WORKSPACE:-}" && -d "${WORKSPACE}" ]]; then
        if [[ "${rc}" -ne 0 || "${KEEP_WORKSPACE:-0}" -eq 1 ]]; then
            printf "Workspace retained: %s\n" "${WORKSPACE}" >&2
        else
            rm -rf -- "${WORKSPACE:?}"
        fi
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

    if [[ "${STATUS}" == "${want}" ]]; then
        record_pass "${name}"
    else
        record_fail "${name}" "expected exit ${want}, got ${STATUS}: ${OUTPUT}"
    fi
}

function expect_contains {
    local name="$1"
    local needle="$2"

    if [[ "${OUTPUT}" == *"${needle}"* ]]; then
        record_pass "${name}"
    else
        record_fail "${name}" "missing output '${needle}' in: ${OUTPUT}"
    fi
}

function expect_not_contains {
    local name="$1"
    local needle="$2"

    if [[ "${OUTPUT}" != *"${needle}"* ]]; then
        record_pass "${name}"
    else
        record_fail "${name}" "unexpected output '${needle}' in: ${OUTPUT}"
    fi
}

# The fake virsh serves the scenario files; it knows only the subcommands the
# script uses and fails like virsh for an unknown domain.
function write_fake_commands {
    cat > "${FAKEBIN}/virsh" <<'EOF'
#!/usr/bin/env bash
set -e
args=("$@")
if [[ "${args[0]}" == "--connect" ]]; then
    args=("${args[@]:2}")
fi
dir="${FAKE_SCENARIO}"
case "${args[0]}" in
    list)
        if [[ " ${args[*]} " == *" --all "* ]]; then
            cat "${dir}/list.all"
        else
            cat "${dir}/list.running"
        fi
        ;;
    dominfo|domblklist|dommemstat)
        file="${dir}/${args[0]}.${args[1]}"
        [[ -f "${file}" ]] || { printf 'error: failed to get domain %s\n' "${args[1]}" >&2; exit 1; }
        cat "${file}"
        ;;
    *)
        printf 'unsupported fake virsh command: %s\n' "${args[*]}" >&2
        exit 1
        ;;
esac
EOF
    cat > "${FAKEBIN}/df" <<'EOF'
#!/usr/bin/env bash
[[ -z "${FAKE_DF_FAIL:-}" ]] || exit 1
cat "${FAKE_DF_ANSWER}"
EOF
    chmod 0755 "${FAKEBIN}/virsh" "${FAKEBIN}/df"
}

function new_scenario {
    SCENARIO="$(mktemp -d "${WORKSPACE}/scenario.XXXXXX")"
    : > "${SCENARIO}/list.running"
    : > "${SCENARIO}/list.all"
    write_meminfo "${MEM_TOTAL_KB}" 41943040
    write_df $((400 * GIB)) $((100 * GIB))
}

function write_meminfo {
    printf "MemTotal:       %s kB\nMemFree:        1 kB\nMemAvailable:   %s kB\n" "$1" "$2" > "${MEMINFO}"
}

function write_df {
    printf "     1B-blocks          Avail\n%s %s\n" "$1" "$2" > "${DF_ANSWER}"
}

# add_guest <name> <state> <max_kib> <virtual_gib> [rss_kib]
# Creates a real qcow2 image and the virsh answers for the guest, and sets
# ALLOC_<name> to the independently measured allocation in bytes.
function add_guest {
    local name="$1"
    local state="$2"
    local max_kib="$3"
    local virtual_gib="$4"
    local rss_kib="${5:-}"
    local image="${IMAGES}/${name}.qcow2"
    local blocks
    local blksize

    qemu-img create -q -f qcow2 "${image}" "${virtual_gib}G"
    blocks="$(stat -c '%b' "${image}")"
    blksize="$(stat -c '%B' "${image}")"
    printf -v "ALLOC_${name//[^A-Za-z0-9]/_}" '%s' $((blocks * blksize))
    printf "Id:             -\nName:           %s\nState:          %s\nMax memory:     %s KiB\n" \
        "${name}" "${state}" "${max_kib}" > "${SCENARIO}/dominfo.${name}"
    printf " Type   Device   Target   Source\n%s\n file   disk     vda      %s\n file   cdrom    sda      /nonexistent/seed.iso\n" \
        "-----------------------------------" "${image}" > "${SCENARIO}/domblklist.${name}"
    if [[ -n "${rss_kib}" ]]; then
        printf "actual %s\nrss %s\n" "${max_kib}" "${rss_kib}" > "${SCENARIO}/dommemstat.${name}"
    fi
    printf "%s\n" "${name}" >> "${SCENARIO}/list.all"
    if [[ "${state}" == "running" ]]; then
        printf "%s\n" "${name}" >> "${SCENARIO}/list.running"
    fi
}

function run_check {
    OUTPUT=""
    STATUS=0
    OUTPUT="$(FAKE_SCENARIO="${SCENARIO}" FAKE_DF_ANSWER="${DF_ANSWER}" \
        CAPACITY_VIRSH="${FAKEBIN}/virsh" CAPACITY_DF="${FAKEBIN}/df" \
        CAPACITY_MEMINFO="${MEMINFO}" "$@" 2>&1)" || STATUS=$?
}

function run_script {
    run_check "${TOP}/bin/check_capacity.bash" "$@"
}

function alloc_of {
    local var="ALLOC_${1//[^A-Za-z0-9]/_}"

    printf "%s" "${!var}"
}

# Prints a byte count as GiB with one truncated decimal, the report's format.
function gib_tenths {
    local tenths=$(($1 * 10 / GIB))

    printf "%d.%d" $((tenths / 10)) $((tenths % 10))
}

function test_status_and_start_fit {
    local growth_running
    local growth_target
    local growth

    new_scenario
    add_guest run1 running 8388608 12 2097152
    add_guest tgt1 "shut off" 8388608 12
    growth_running=$((12 * GIB - $(alloc_of run1)))
    growth_target=$((12 * GIB - $(alloc_of tgt1)))
    growth=$((growth_running + growth_target))

    run_script -d "${WORKSPACE}" start tgt1
    expect_exit "start fits with ample capacity" 0
    expect_contains "start prints the fit line" "capacity=FIT"
    # Target 8+1 GiB, running guest 8+1-2 GiB: 16.0 GiB of memory demand.
    expect_contains "memory demand counts target and running headroom" "demand 16.0 GiB"
    expect_contains "disk demand is virtual minus allocated for both guests" \
        "demand $(gib_tenths "${growth}") GiB"
    expect_contains "report names the planned counts" "running=1 planned=1"

    run_script -d "${WORKSPACE}" status
    expect_exit "status fits" 0
    # Running guest alone: 8+1-2 GiB.
    expect_contains "status counts only the running guest" "demand 7.0 GiB"
}

function test_memory_boundary {
    new_scenario
    add_guest run1 running 8388608 12 2097152
    add_guest tgt1 "shut off" 8388608 12
    # Demand 16 GiB; the 25 percent margin of 64 GiB is 16 GiB: left == margin.
    write_meminfo "${MEM_TOTAL_KB}" 33554432
    run_check env CAPACITY_MEM_MARGIN_PCT=25 "${TOP}/bin/check_capacity.bash" -d "${WORKSPACE}" start tgt1
    expect_exit "left equal to the memory margin fits" 0

    write_meminfo "${MEM_TOTAL_KB}" 33554431
    run_check env CAPACITY_MEM_MARGIN_PCT=25 "${TOP}/bin/check_capacity.bash" -d "${WORKSPACE}" start tgt1
    expect_exit "one kB below the memory margin does not fit" 1
    expect_contains "short memory names its reason" "capacity=NOFIT reason=memory"
}

function test_disk_boundary {
    local growth
    local margin

    new_scenario
    add_guest tgt1 "shut off" 4194304 12
    growth=$((12 * GIB - $(alloc_of tgt1)))
    margin=$((400 * GIB * 5 / 100))
    write_df $((400 * GIB)) $((growth + margin))
    run_script -d "${WORKSPACE}" start tgt1
    expect_exit "left equal to the disk margin fits" 0

    write_df $((400 * GIB)) $((growth + margin - 1))
    run_script -d "${WORKSPACE}" start tgt1
    expect_exit "one byte below the disk margin does not fit" 1
    expect_contains "short disk names its reason" "capacity=NOFIT reason=disk"

    write_meminfo "${MEM_TOTAL_KB}" 1048576
    run_script -d "${WORKSPACE}" start tgt1
    expect_contains "both shortages are named together" "capacity=NOFIT reason=memory,disk"
}

function test_create {
    new_scenario
    run_script -d "${WORKSPACE}" -N 2 -m 4096 -z 20G create
    expect_exit "create fits with ample capacity" 0
    # 2 x (4096 + 1024) MiB.
    expect_contains "create memory demand" "demand 10.0 GiB"
    # 2 x (20 GiB + 1 MiB of new files) is just over 40 GiB.
    expect_contains "create disk demand" "demand 40.0 GiB"
    expect_contains "create reports the planned count" "planned=2"

    run_check env CAPACITY_NEW_FILES_MB=0 "${TOP}/bin/check_capacity.bash" -d "${WORKSPACE}" -N 1 -z 1T create
    expect_contains "terabyte sizes are counted" "demand 1024.0 GiB"
    expect_exit "an oversized create does not fit" 1

    # 2 x (20 GiB + 1024 MiB of new files).
    run_check env CAPACITY_NEW_FILES_MB=1024 "${TOP}/bin/check_capacity.bash" -d "${WORKSPACE}" -N 2 -z 20G create
    expect_contains "new files are added to the disk demand of a created guest" "demand 42.0 GiB"
}

function test_running_guest_memory {
    new_scenario
    add_guest run1 running 8388608 12
    run_script -d "${WORKSPACE}" status
    expect_contains "missing resident size counts the full allowance" "demand 9.0 GiB"
    expect_contains "missing resident size is noted" "resident memory of run1 unavailable"
}

function test_already_running_target {
    new_scenario
    add_guest run1 running 8388608 12 2097152
    run_script -d "${WORKSPACE}" start run1
    expect_exit "a running target is not an error" 0
    expect_contains "a running target is counted once" "demand 7.0 GiB"
    expect_contains "a running target is noted" "run1 is already running"
}

function test_defined_option {
    local growth_target
    local growth_other
    local both

    new_scenario
    add_guest tgt1 "shut off" 8388608 12
    add_guest other1 "shut off" 8388608 12
    growth_target=$((12 * GIB - $(alloc_of tgt1)))
    growth_other=$((12 * GIB - $(alloc_of other1)))
    both=$((growth_target + growth_other))

    run_script -d "${WORKSPACE}" start tgt1
    expect_contains "default disk demand is the target only" "demand $(gib_tenths "${growth_target}") GiB"
    expect_not_contains "another defined guest is ignored by default" "demand $(gib_tenths "${both}") GiB"
    run_script -D -d "${WORKSPACE}" start tgt1
    expect_exit "defined guests counted with -D still fit" 0
    expect_contains "the -D option adds the growth of the other guest" \
        "demand $(gib_tenths "${both}") GiB"
}

function test_fail_closed {
    new_scenario
    run_script -d "${WORKSPACE}" start missing1
    expect_exit "an unknown domain cannot be decided" 2
    expect_contains "an unknown domain is named in the error" "unknown domain: missing1"
    expect_not_contains "an unknown domain prints no fit line" "capacity=FIT"

    new_scenario
    add_guest paused1 paused 8388608 12
    run_script -d "${WORKSPACE}" start paused1
    expect_exit "a paused target cannot be decided" 2

    new_scenario
    printf "MemTotal:       %s kB\n" "${MEM_TOTAL_KB}" > "${MEMINFO}"
    run_script -d "${WORKSPACE}" status
    expect_exit "meminfo without MemAvailable cannot be decided" 2

    new_scenario
    printf "garbage\n" > "${DF_ANSWER}"
    run_script -d "${WORKSPACE}" status
    expect_exit "unreadable df output cannot be decided" 2

    new_scenario
    run_check env FAKE_DF_FAIL=1 "${TOP}/bin/check_capacity.bash" -d "${WORKSPACE}" status
    expect_exit "a failing df cannot be decided" 2
    expect_contains "a failing df is named in the error" "df failed"

    new_scenario
    add_guest tgt1 "shut off" 8388608 12
    rm -f -- "${IMAGES}/tgt1.qcow2"
    run_script -d "${WORKSPACE}" start tgt1
    expect_exit "a missing disk image cannot be decided" 2

    new_scenario
    run_script -d "${WORKSPACE}/no-such-directory" status
    expect_exit "a missing image directory cannot be decided" 2
}

function test_input_validation {
    new_scenario
    run_script -d "${WORKSPACE}" -z 20 create
    expect_exit "a disk size without a suffix is rejected" 2
    run_script -d "${WORKSPACE}" -N 0 create
    expect_exit "a zero count is rejected" 2
    run_script -d "${WORKSPACE}" -m abc create
    expect_exit "a non-numeric memory is rejected" 2
    run_script -d "${WORKSPACE}" start 'bad name;'
    expect_exit "an unsafe domain name is rejected" 2
    expect_contains "an unsafe domain name is named in the error" "invalid domain name"
    run_script -d "${WORKSPACE}" start
    expect_exit "start without a domain is rejected" 2
    run_script -d "${WORKSPACE}" status extra
    expect_exit "status with an operand is rejected" 2
    run_script -d "${WORKSPACE}" bogus
    expect_exit "an unknown action is rejected" 2
    run_script -d "${WORKSPACE}" -x status
    expect_exit "an unknown option is rejected" 2
    run_check env CAPACITY_MEM_MARGIN_PCT=101 "${TOP}/bin/check_capacity.bash" -d "${WORKSPACE}" status
    expect_exit "a margin above 100 percent is rejected" 2
    run_check env CAPACITY_DISK_MARGIN_PCT=ten "${TOP}/bin/check_capacity.bash" -d "${WORKSPACE}" status
    expect_exit "a non-numeric margin is rejected" 2
}

function test_output_forms {
    new_scenario
    run_script -q -d "${WORKSPACE}" status
    expect_exit "quiet status fits" 0
    if [[ "${OUTPUT}" == "capacity=FIT" ]]; then
        record_pass "quiet mode prints only the capacity line"
    else
        record_fail "quiet mode prints only the capacity line" "got: ${OUTPUT}"
    fi

    run_script -h
    expect_exit "help exits successfully" 0
    expect_contains "help shows the usage" "Usage:"
}

function main {
    local failed

    WORKSPACE="$(mktemp -d)"
    FAKEBIN="${WORKSPACE}/fakebin"
    IMAGES="${WORKSPACE}/images"
    MEMINFO="${WORKSPACE}/meminfo"
    DF_ANSWER="${WORKSPACE}/df.answer"
    mkdir -p "${FAKEBIN}" "${IMAGES}"
    command -v qemu-img >/dev/null || { printf "qemu-img is required\n" >&2; exit 1; }
    write_fake_commands

    test_status_and_start_fit
    test_memory_boundary
    test_disk_boundary
    test_create
    test_running_guest_memory
    test_already_running_target
    test_defined_option
    test_fail_closed
    test_input_validation
    test_output_forms

    printf "Summary: %d passed / %d total\n" "${TEST_PASSED}" "${TEST_TOTAL}"
    if (( TEST_FAILED > 0 )); then
        for failed in "${FAILED_DETAILS[@]}"; do
            printf "FAILED: %s\n" "${failed}" >&2
        done
        exit 1
    fi
}

main "$@"
