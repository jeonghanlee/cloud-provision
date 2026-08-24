#!/usr/bin/env bash
#
# Verifies fresh-only provisioning through the public create_vm.bash entry point.

set -euo pipefail

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

function expect_contains {
    local name="$1"
    local content="$2"
    local expected="$3"

    if [[ "${content}" == *"${expected}"* ]]; then
        record_pass "${name}"
    else
        record_fail "${name}" "missing output: ${expected}"
    fi
}

function write_fake_virsh {
    cat > "${FAKEBIN}/virsh" <<'EOF'
#!/usr/bin/env bash
set -e
for argument in "$@"; do
    if [[ "${argument}" == "dominfo" ]]; then
        exit "${FAKE_DOMAIN_EXISTS:-1}"
    fi
done
printf "unexpected virsh command: %s\n" "$*" >&2
exit 2
EOF
    chmod +x "${FAKEBIN}/virsh"
}

function run_case {
    local name="$1"
    local domain_exists="$2"
    local create_disk="$3"
    local expected_text="$4"
    local case_dir="${WORKSPACE}/${name}"
    local image_dir="${case_dir}/images"
    local home_dir="${case_dir}/home"
    local disk="${image_dir}/lab-rocky8-main.qcow2"
    local output_file="${case_dir}/output.txt"
    local before_hash=""
    local after_hash=""
    local rc=0

    mkdir -p "${image_dir}" "${home_dir}"
    if [[ "${create_disk}" == "yes" ]]; then
        printf "%s\n" "preserve this disk" > "${disk}"
        before_hash="$(sha256sum "${disk}")"
        before_hash="${before_hash%% *}"
    fi

    FAKE_DOMAIN_EXISTS="${domain_exists}" \
    PATH="${FAKEBIN}:${PATH}" \
    HOME="${home_dir}" \
    USER="$(id -un)" \
    REQUIRED_GROUP="$(id -gn)" \
    "${TOP}/bin/create_vm.bash" -o rocky8 -n main -d "${image_dir}" -p lab -F \
        > "${output_file}" 2>&1 || rc=$?

    if [[ "${rc}" != "0" ]]; then
        record_pass "${name} rejects stale input"
    else
        record_fail "${name} rejects stale input" "create_vm.bash unexpectedly succeeded"
    fi

    declare -g CASE_OUTPUT
    CASE_OUTPUT="$(< "${output_file}")"
    expect_contains "${name} reports the stale input" "${CASE_OUTPUT}" "${expected_text}"
    expect_contains "${name} reports the cleanup command" "${CASE_OUTPUT}" "Cleanup:"

    if [[ "${create_disk}" == "yes" ]]; then
        after_hash="$(sha256sum "${disk}")"
        after_hash="${after_hash%% *}"
        if [[ "${after_hash}" == "${before_hash}" ]]; then
            record_pass "${name} preserves the source disk"
        else
            record_fail "${name} preserves the source disk" "source disk content changed"
        fi
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

WORKSPACE="$(mktemp -d /tmp/fresh-bake-inputs-test.XXXXXX)"
FAKEBIN="${WORKSPACE}/bin"
mkdir -p "${FAKEBIN}"
write_fake_virsh

run_case "existing-domain" 0 no "fresh provisioning requires an undefined domain"
run_case "orphan-disk" 1 yes "fresh provisioning requires an absent source disk"
print_summary
