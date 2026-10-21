#!/usr/bin/env bash
#
# Decides whether a planned set of guests fits the host. The planned set is the
# running guests plus the retained guests to start or the new guests to create.
# Memory demand is each planned guest's allowance plus host overhead, less what
# a running guest already uses. Disk demand is the growth of every planned disk
# up to its virtual size, plus the new files of a created guest. Both demands
# are compared with the measured capacity and the owner margins that must stay
# free. Exit status: 0 fits, 1 does not fit, 2 cannot decide. Every measurement
# or input problem exits 2, so a caller never starts a guest on a guess.

set -euo pipefail

# Policy defaults. An owner-recorded margin overrides them through the
# environment.
declare -g MEM_OVERHEAD_MB="${CAPACITY_MEM_OVERHEAD_MB:-1024}"
declare -g NEW_FILES_MB="${CAPACITY_NEW_FILES_MB:-1}"
declare -g MEM_MARGIN_PCT="${CAPACITY_MEM_MARGIN_PCT:-10}"
declare -g DISK_MARGIN_PCT="${CAPACITY_DISK_MARGIN_PCT:-5}"

# External boundaries. Only tests replace them.
declare -g VIRSH_BIN="${CAPACITY_VIRSH:-virsh}"
declare -g DF_BIN="${CAPACITY_DF:-df}"
declare -g MEMINFO_FILE="${CAPACITY_MEMINFO:-/proc/meminfo}"
declare -g LIBVIRT_URI="${CAPACITY_LIBVIRT_URI:-qemu:///system}"

declare -gr DEFAULT_IMAGE_DIR="${HOME}/libvirt/images"
declare -gr BYTES_PER_MIB=1048576
declare -gr BYTES_PER_GIB=1073741824

declare -g ACTION=""
declare -g IMAGE_DIR=""
declare -g NEW_COUNT=1
declare -g NEW_MEM_MB=4096
declare -g NEW_DISK_SIZE="20G"
declare -g INCLUDE_DEFINED=false
declare -g QUIET=false
declare -ag TARGETS=()
declare -ag NOTES=()
declare -Ag SEEN=()

declare -g MEM_TOTAL_KB=""
declare -g MEM_AVAILABLE_KB=""
declare -g STORE_TOTAL_BYTES=""
declare -g STORE_AVAIL_BYTES=""
declare -g FIRST_DISK_DIR=""
declare -g RUNNING_COUNT=0
declare -g DEMAND_MEM_KB=0
declare -g DEMAND_DISK_BYTES=0

function print_usage {
    printf "Usage: %s [options] status\n" "$(basename "$0")"
    printf "       %s [options] start <domain>...\n" "$(basename "$0")"
    printf "       %s [options] create\n" "$(basename "$0")"
    printf "\n"
    printf "Checks that the running guests plus the planned guests fit the host.\n"
    printf "\n"
    printf "Actions:\n"
    printf "  status         Report headroom for the running guests only\n"
    printf "  start          Retained shut-off guests to start from their disks\n"
    printf "  create         New guests to create (see -N, -m, -z)\n"
    printf "\n"
    printf "Options:\n"
    printf "  -d <image_dir> Image store directory (default: directory of the first\n"
    printf "                 target disk, else %s)\n" "${DEFAULT_IMAGE_DIR}"
    printf "  -N <count>     Number of new guests for create (default: 1)\n"
    printf "  -m <mb>        Memory of each new guest in MB (default: 4096)\n"
    printf "  -z <size>      Disk size of each new guest, M/G/T suffix (default: 20G)\n"
    printf "  -D             Also count the planned growth of every other defined guest\n"
    printf "  -q             Print only the final capacity line\n"
    printf "  -h             Show this help message\n"
    printf "\n"
    printf "Policy (environment): CAPACITY_MEM_OVERHEAD_MB (1024),\n"
    printf "  CAPACITY_NEW_FILES_MB (1), CAPACITY_MEM_MARGIN_PCT (10),\n"
    printf "  CAPACITY_DISK_MARGIN_PCT (5), CAPACITY_LIBVIRT_URI.\n"
    printf "\n"
    printf "Exit status: 0 fits, 1 does not fit, 2 cannot decide.\n"
}

function die {
    printf "Error: %s\n" "$*" >&2
    exit 2
}

function note {
    NOTES+=("$*")
}

# Accepts a plain decimal in [min, max]; a leading zero is read as base 10.
function validate_uint {
    local label="$1"
    local value="$2"
    local min="$3"
    local max="$4"

    if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
        die "${label} must be a non-negative integer, got: ${value}"
    fi
    value=$((10#${value}))
    if (( value < min || value > max )); then
        die "${label} must be between ${min} and ${max}, got: ${value}"
    fi
}

function size_to_bytes {
    local size="$1"
    local number
    local unit

    if [[ ! "${size}" =~ ^([1-9][0-9]*)([MGT])$ ]]; then
        die "disk size must be a positive integer with an M, G, or T suffix, got: ${size}"
    fi
    number="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    case "${unit}" in
        M) printf "%d\n" $((number * BYTES_PER_MIB)) ;;
        G) printf "%d\n" $((number * BYTES_PER_GIB)) ;;
        T) printf "%d\n" $((number * BYTES_PER_GIB * 1024)) ;;
    esac
}

# Prints a signed byte count as GiB with one decimal.
function fmt_gib {
    local bytes="$1"
    local sign=""
    local tenths

    if (( bytes < 0 )); then
        sign="-"
        bytes=$((-bytes))
    fi
    tenths=$((bytes * 10 / BYTES_PER_GIB))
    printf "%s%d.%d" "${sign}" $((tenths / 10)) $((tenths % 10))
}

function virsh_run {
    "${VIRSH_BIN}" --connect "${LIBVIRT_URI}" "$@"
}

function parse_args {
    local opt

    while getopts ":d:N:m:z:Dqh" opt; do
        case "${opt}" in
            d) IMAGE_DIR="${OPTARG}" ;;
            N) NEW_COUNT="${OPTARG}" ;;
            m) NEW_MEM_MB="${OPTARG}" ;;
            z) NEW_DISK_SIZE="${OPTARG}" ;;
            D) INCLUDE_DEFINED=true ;;
            q) QUIET=true ;;
            h) print_usage; exit 0 ;;
            :) die "option -${OPTARG} requires an argument" ;;
            *) die "unknown option -${OPTARG}" ;;
        esac
    done
    shift $((OPTIND - 1))

    if (( $# == 0 )); then
        print_usage >&2
        exit 2
    fi
    ACTION="$1"
    shift
    case "${ACTION}" in
        status|create)
            (( $# == 0 )) || die "${ACTION} takes no domain names"
            ;;
        start)
            (( $# > 0 )) || die "start needs at least one domain name"
            TARGETS=("$@")
            ;;
        *)
            die "unknown action: ${ACTION}"
            ;;
    esac
}

function validate_inputs {
    local name

    validate_uint "CAPACITY_MEM_OVERHEAD_MB" "${MEM_OVERHEAD_MB}" 0 1048576
    validate_uint "CAPACITY_NEW_FILES_MB" "${NEW_FILES_MB}" 0 1048576
    validate_uint "CAPACITY_MEM_MARGIN_PCT" "${MEM_MARGIN_PCT}" 0 100
    validate_uint "CAPACITY_DISK_MARGIN_PCT" "${DISK_MARGIN_PCT}" 0 100
    validate_uint "-N count" "${NEW_COUNT}" 1 1000
    validate_uint "-m memory" "${NEW_MEM_MB}" 1 1048576
    size_to_bytes "${NEW_DISK_SIZE}" >/dev/null
    for name in "${TARGETS[@]}"; do
        if [[ ! "${name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
            die "invalid domain name: ${name}"
        fi
    done
}

# Reads MemTotal and MemAvailable in kB; a missing value cannot be decided.
function read_meminfo {
    local key
    local value
    local unit

    [[ -r "${MEMINFO_FILE}" ]] || die "cannot read ${MEMINFO_FILE}"
    while read -r key value unit || [[ -n "${key:-}" ]]; do
        case "${key:-}" in
            MemTotal:) MEM_TOTAL_KB="${value:-}" ;;
            MemAvailable:) MEM_AVAILABLE_KB="${value:-}" ;;
        esac
    done < "${MEMINFO_FILE}"
    if [[ ! "${MEM_TOTAL_KB}" =~ ^[0-9]+$ || ! "${MEM_AVAILABLE_KB}" =~ ^[0-9]+$ ]]; then
        die "MemTotal or MemAvailable is missing from ${MEMINFO_FILE}"
    fi
    MEM_TOTAL_KB=$((10#${MEM_TOTAL_KB}))
    MEM_AVAILABLE_KB=$((10#${MEM_AVAILABLE_KB}))
}

# Reads the total and the available bytes of the file system holding the image
# store.
function read_store {
    local dir="$1"
    local output
    local size
    local avail
    local extra
    local -a lines=()

    [[ -d "${dir}" ]] || die "image directory does not exist: ${dir}"
    output="$("${DF_BIN}" -B1 --output=size,avail -- "${dir}")" \
        || die "df failed for ${dir}"
    mapfile -t lines <<< "${output}"
    (( ${#lines[@]} >= 2 )) || die "unexpected df output for ${dir}"
    read -r size avail extra <<< "${lines[1]}"
    if [[ ! "${size}" =~ ^[0-9]+$ || ! "${avail}" =~ ^[0-9]+$ || -n "${extra:-}" ]]; then
        die "unexpected df output for ${dir}"
    fi
    STORE_TOTAL_BYTES=$((10#${size}))
    STORE_AVAIL_BYTES=$((10#${avail}))
}

# Prints the virtual size and the allocated size of one image in bytes. The
# last matches of the JSON belong to the top-level image; earlier ones belong
# to the file layer.
function image_sizes {
    local path="$1"
    local json
    local virtual
    local actual

    [[ -e "${path}" ]] || die "disk image not found: ${path}"
    json="$(qemu-img info -U --output=json -- "${path}")" \
        || die "qemu-img could not read ${path}"
    if [[ ! "${json}" =~ .*\"virtual-size\":[[:space:]]*([0-9]+) ]]; then
        die "no virtual size reported for ${path}"
    fi
    virtual="${BASH_REMATCH[1]}"
    if [[ ! "${json}" =~ .*\"actual-size\":[[:space:]]*([0-9]+) ]]; then
        die "no allocated size reported for ${path}"
    fi
    actual="${BASH_REMATCH[1]}"
    printf "%d %d\n" $((10#${virtual})) $((10#${actual}))
}

# Adds the remaining growth of every disk of one domain to the disk demand and
# remembers the directory of the first disk.
function add_domain_disks {
    local name="$1"
    local listing
    local type
    local device
    local _target
    local source
    local sizes
    local virtual
    local actual
    local found=0

    listing="$(virsh_run domblklist "${name}" --details)" \
        || die "cannot list the disks of ${name}"
    while read -r type device _target source || [[ -n "${type:-}" ]]; do
        [[ "${device:-}" == "disk" && -n "${source:-}" && "${source}" != "-" ]] || continue
        sizes="$(image_sizes "${source}")"
        read -r virtual actual <<< "${sizes}"
        if (( virtual > actual )); then
            DEMAND_DISK_BYTES=$((DEMAND_DISK_BYTES + virtual - actual))
        fi
        if [[ -z "${FIRST_DISK_DIR}" ]]; then
            FIRST_DISK_DIR="$(dirname -- "${source}")"
        fi
        found=1
    done <<< "${listing}"
    (( found == 1 )) || die "no disk found for ${name}"
}

# Prints "<state>|<max memory kB>" of one domain.
function domain_facts {
    local name="$1"
    local info
    local state
    local maxmem

    info="$(virsh_run dominfo "${name}")" || die "unknown domain: ${name}"
    if [[ ! "${info}" =~ (^|$'\n')State:[[:space:]]+([^$'\n']+) ]]; then
        die "no state reported for ${name}"
    fi
    state="${BASH_REMATCH[2]}"
    if [[ ! "${info}" =~ (^|$'\n')Max\ memory:[[:space:]]+([0-9]+)[[:space:]]KiB ]]; then
        die "no memory allowance reported for ${name}"
    fi
    maxmem="${BASH_REMATCH[2]}"
    printf "%s|%d\n" "${state}" $((10#${maxmem}))
}

# A running guest is planned to stay up: its memory may still grow to the full
# allowance plus overhead, so the difference to its resident size is demand.
function add_running {
    local name="$1"
    local facts
    local maxmem
    local stat
    local rss=0
    local extra

    SEEN["${name}"]=running
    RUNNING_COUNT=$((RUNNING_COUNT + 1))
    facts="$(domain_facts "${name}")"
    maxmem="${facts#*|}"
    if stat="$(virsh_run dommemstat "${name}" 2>/dev/null)" \
        && [[ "${stat}" =~ (^|$'\n')rss[[:space:]]+([0-9]+) ]]; then
        rss=$((10#${BASH_REMATCH[2]}))
    else
        note "resident memory of ${name} unavailable: counted as zero"
    fi
    extra=$((maxmem + MEM_OVERHEAD_MB * 1024 - rss))
    if (( extra > 0 )); then
        DEMAND_MEM_KB=$((DEMAND_MEM_KB + extra))
    fi
    add_domain_disks "${name}"
}

function add_target {
    local name="$1"
    local facts
    local state
    local maxmem

    if [[ -n "${SEEN[${name}]:-}" ]]; then
        note "${name} is already running: counted once as a running guest"
        return 0
    fi
    SEEN["${name}"]=target
    facts="$(domain_facts "${name}")"
    state="${facts%|*}"
    maxmem="${facts#*|}"
    if [[ "${state}" != "shut off" ]]; then
        die "${name} is in state '${state}', not shut off"
    fi
    DEMAND_MEM_KB=$((DEMAND_MEM_KB + maxmem + MEM_OVERHEAD_MB * 1024))
    add_domain_disks "${name}"
}

function add_new_guests {
    local disk_bytes

    disk_bytes="$(size_to_bytes "${NEW_DISK_SIZE}")"
    DEMAND_MEM_KB=$((DEMAND_MEM_KB + NEW_COUNT * (NEW_MEM_MB + MEM_OVERHEAD_MB) * 1024))
    DEMAND_DISK_BYTES=$((DEMAND_DISK_BYTES
        + NEW_COUNT * (disk_bytes + NEW_FILES_MB * BYTES_PER_MIB)))
}

# Counts the planned growth of defined guests that are neither running nor
# targets, for a stricter reading of the disk demand.
function add_defined_others {
    local listing
    local name

    listing="$(virsh_run list --all --name)" || die "cannot list defined guests"
    while read -r name || [[ -n "${name:-}" ]]; do
        [[ -n "${name:-}" ]] || continue
        [[ -z "${SEEN[${name}]:-}" ]] || continue
        SEEN["${name}"]=defined
        add_domain_disks "${name}"
    done <<< "${listing}"
}

function collect_running {
    local listing
    local name

    listing="$(virsh_run list --name)" || die "cannot list running guests"
    while read -r name || [[ -n "${name:-}" ]]; do
        [[ -n "${name:-}" ]] || continue
        add_running "${name}"
    done <<< "${listing}"
}

function report_line {
    local label="$1"
    local available="$2"
    local demand="$3"
    local left="$4"
    local margin="$5"
    local fits="$6"
    local verdict="short"

    if [[ "${fits}" == true ]]; then
        verdict="ok"
    fi
    printf "  %-7s available %s GiB, demand %s GiB, left %s GiB, margin %s GiB: %s\n" \
        "${label}" "$(fmt_gib "${available}")" "$(fmt_gib "${demand}")" \
        "$(fmt_gib "${left}")" "$(fmt_gib "${margin}")" "${verdict}"
}

function decide {
    local mem_avail_bytes
    local mem_demand_bytes
    local mem_left
    local mem_margin
    local disk_left
    local disk_margin
    local mem_ok=true
    local disk_ok=true
    local reasons=""
    local planned=0
    local item

    case "${ACTION}" in
        start) planned="${#TARGETS[@]}" ;;
        create) planned="${NEW_COUNT}" ;;
    esac
    mem_avail_bytes=$((MEM_AVAILABLE_KB * 1024))
    mem_demand_bytes=$((DEMAND_MEM_KB * 1024))
    mem_left=$((mem_avail_bytes - mem_demand_bytes))
    mem_margin=$((MEM_TOTAL_KB * 1024 * MEM_MARGIN_PCT / 100))
    disk_left=$((STORE_AVAIL_BYTES - DEMAND_DISK_BYTES))
    disk_margin=$((STORE_TOTAL_BYTES * DISK_MARGIN_PCT / 100))

    (( mem_left >= mem_margin )) || mem_ok=false
    (( disk_left >= disk_margin )) || disk_ok=false

    if [[ "${QUIET}" == false ]]; then
        printf "capacity: action=%s running=%d planned=%d\n" \
            "${ACTION}" "${RUNNING_COUNT}" "${planned}"
        report_line memory "${mem_avail_bytes}" "${mem_demand_bytes}" \
            "${mem_left}" "${mem_margin}" "${mem_ok}"
        report_line disk "${STORE_AVAIL_BYTES}" "${DEMAND_DISK_BYTES}" \
            "${disk_left}" "${disk_margin}" "${disk_ok}"
        for item in "${NOTES[@]}"; do
            printf "  note: %s\n" "${item}"
        done
    fi

    if [[ "${mem_ok}" == true && "${disk_ok}" == true ]]; then
        printf "capacity=FIT\n"
        return 0
    fi
    [[ "${mem_ok}" == true ]] || reasons="memory"
    if [[ "${disk_ok}" == false ]]; then
        reasons="${reasons:+${reasons},}disk"
    fi
    printf "capacity=NOFIT reason=%s\n" "${reasons}"
    return 1
}

function main {
    local name
    local store_dir

    parse_args "$@"
    validate_inputs
    read_meminfo
    collect_running
    case "${ACTION}" in
        start)
            for name in "${TARGETS[@]}"; do
                add_target "${name}"
            done
            ;;
        create)
            add_new_guests
            ;;
    esac
    if [[ "${INCLUDE_DEFINED}" == true ]]; then
        add_defined_others
    fi
    store_dir="${IMAGE_DIR:-${FIRST_DISK_DIR:-${DEFAULT_IMAGE_DIR}}}"
    read_store "${store_dir}"
    decide
}

main "$@"
