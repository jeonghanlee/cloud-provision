#!/usr/bin/env bash
#
# Verifies the joined proxy artifact lifecycle through the shipped producer and
# both supported IOC families, then proves tuple and source omissions remain red.

set -euo pipefail

declare -g SCRIPT_DIR
declare -g TOP
declare -g FIXTURE
declare -g WORKSPACE
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -g INVENTORY_OMISSION_TOTAL=0
declare -ag FAILED_DETAILS=()

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURE="${PROXY_CONTRACT_FIXTURE:-${TOP}/tests/fixtures/proxy-artifacts.tsv}"
WORKSPACE="$(mktemp -d /tmp/cloud-provision-proxy-lifecycle.XXXXXX)"

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

function expect_success {
    local name="$1"
    local output_file="$2"
    shift 2

    if "$@" > "${output_file}" 2>&1; then
        record_pass "${name}"
    else
        record_fail "${name}" "command returned nonzero; see ${output_file}"
    fi
}

function expect_failure {
    local name="$1"
    local output_file="$2"
    shift 2

    if "$@" > "${output_file}" 2>&1; then
        record_fail "${name}" "mutation unexpectedly passed"
    else
        record_pass "${name}"
    fi
}

function validate_fixture {
    local os
    local row_count
    local expected_count
    local expected_inventory
    local actual_inventory
    local valid=true

    if [[ "$(head -n 1 "${FIXTURE}")" == $'os\tidentity\tpath\towner\tgroup\tmode\tform\tmarker\tcleanup\tremnant' ]]; then
        record_pass "independent fixture has the fixed schema"
    else
        record_fail "independent fixture has the fixed schema" "unexpected header"
        valid=false
    fi

    for os in debian ubuntu rocky; do
        row_count="$(awk -F '\t' -v os="${os}" 'NR > 1 && $1 == os {count++} END {print count + 0}' \
            "${FIXTURE}")"
        case "${os}" in
            debian|ubuntu) expected_count=8 ;;
            rocky) expected_count=7 ;;
        esac
        if [[ "${row_count}" == "${expected_count}" ]] &&
           [[ "$(awk -F '\t' -v os="${os}" '
               NR > 1 && $1 == os && ($9 != "required" || $10 != "required") {count++}
               END {print count + 0}
           ' "${FIXTURE}")" == "0" ]]; then
            record_pass "${os} fixture defines one exact cleanup and remnant set"
        else
            record_fail "${os} fixture defines one exact cleanup and remnant set" \
                "row or coverage count differs"
            valid=false
        fi
        expected_inventory="${WORKSPACE}/${os}.fixture-inventory"
        actual_inventory="${WORKSPACE}/${os}.production-inventory"
        awk -F '\t' -v os="${os}" 'NR > 1 && $1 == os' "${FIXTURE}" \
            | sort > "${expected_inventory}"
        bash -c 'source "$1"; proxy_contract_print_inventory "$2"' \
            proxy-inventory "${TOP}/bin/proxy_contract.bash" "${os}" \
            | sort > "${actual_inventory}"
        if diff -u "${expected_inventory}" "${actual_inventory}" >/dev/null; then
            record_pass "${os} fixture matches the production inventory tuple"
        else
            record_fail "${os} fixture matches the production inventory tuple" \
                "path, owner, group, mode, form, marker, cleanup, or remnant differs"
            valid=false
        fi
    done
    [[ "${valid}" == true ]]
}

function verify_fresh_consumer {
    local root="${WORKSPACE}/fresh-consumer"

    mkdir -p "${root}/etc" "${root}/var/lib/cloud/instances/current" "${root}/var/log"
    chmod 0755 "${root}/etc" "${root}/var" "${root}/var/lib" \
        "${root}/var/lib/cloud" "${root}/var/lib/cloud/instances" \
        "${root}/var/lib/cloud/instances/current" "${root}/var/log"
    printf "ID=debian\n" > "${root}/etc/os-release"
    printf 'root:x:0:0:root:/root:/bin/bash\n' > "${root}/etc/passwd"
    printf 'vmadmin:x:%s:%s::/home/vmadmin:/bin/bash\n' \
        "$(id -u)" "$(id -g)" >> "${root}/etc/passwd"
    printf "fresh consumer state\n" > "${root}/var/lib/cloud/instances/current/user-data.txt"
    printf "fresh consumer log\n" > "${root}/var/log/cloud-init.log"

    expect_success "fresh consumer verify clean ignores new cloud-init runtime state" \
        "${WORKSPACE}/fresh-consumer.log" \
        bash "${TOP}/bin/proxy_contract.bash" --test-root "${root}" verify clean
}

function prepare_mutation_checkout {
    local label="$1"
    local parent="${WORKSPACE}/${label}"
    local checkout="${parent}/cloud-provision"

    mkdir -p "${parent}"
    cp -a "${TOP}" "${checkout}"
    ln -s "$(realpath "${TOP}/../ansible-provision")" "${parent}/ansible-provision"
    printf "%s\n" "${checkout}"
}

function expect_fixture_mutation_failure {
    local label="$1"
    local column="$2"
    local replacement="$3"
    local fixture="${WORKSPACE}/${label}.tsv"
    local output="${WORKSPACE}/${label}.log"
    local rc=0

    awk -F '\t' -v OFS='\t' -v column="${column}" -v replacement="${replacement}" '
        NR == 2 {$column = replacement}
        {print}
    ' "${TOP}/tests/fixtures/proxy-artifacts.tsv" > "${fixture}"
    PROXY_CONTRACT_FIXTURE="${fixture}" \
        bash "${TOP}/tests/check-proxy-lifecycle.bash" joined \
        > "${output}" 2>&1 || rc=$?
    if [[ "${rc}" != "0" ]] &&
       ! grep -Fq -e 'shipped Debian IOC bake executes' \
           -e 'shipped Rocky IOC bake executes' \
           "${output}"; then
        record_pass "${label} fails the public joined gate before publication"
    else
        record_fail "${label} fails the public joined gate before publication" \
            "the mutation passed or reached a bake consumer"
    fi
}

function run_inventory_omission {
    local os_type="$1"
    local identity="$2"
    local label="ioc-${os_type}-${identity}-omission"
    local checkout output rc=0

    checkout="$(prepare_mutation_checkout "${label}")"
    sed -i "/# inventory:${identity}$/d" "${checkout}/bin/proxy_contract.bash"
    output="${WORKSPACE}/${label}.log"
    env PROXY_APPLY_CONTRACT="${TOP}/bin/proxy_contract.bash" \
        bash "${checkout}/tests/check-iocrunner-bake-provenance.bash" \
        seal-case "${os_type}" > "${output}" 2>&1 || rc=$?
    INVENTORY_OMISSION_TOTAL=$((INVENTORY_OMISSION_TOTAL + 1))
    if [[ "${rc}" != 0 ]] &&
       grep -Fq "omitted proxy identity ${identity}" "${output}" &&
       grep -Fq "omits seal completion" "${output}" &&
       grep -Fq "blocks publication before conversion" "${output}" &&
       ! grep -Fq 'http://fixture.invalid/' "${output}"; then
        record_pass "${label} fails before seal completion and publication"
    else
        record_fail "${label} fails before seal completion and publication" \
            "rc=${rc}; identity, seal, conversion, or value-free evidence is missing"
    fi
}

function run_mutations {
    local checkout

    run_inventory_omission debian13 profile
    run_inventory_omission debian13 environment
    run_inventory_omission debian13 apt
    run_inventory_omission debian13 sudo
    run_inventory_omission debian13 sshd
    run_inventory_omission debian13 ssh-environment
    run_inventory_omission debian13 pip
    run_inventory_omission debian13 git
    run_inventory_omission rocky8 profile
    run_inventory_omission rocky8 environment
    run_inventory_omission rocky8 dnf
    run_inventory_omission rocky8 sshd
    run_inventory_omission rocky8 ssh-environment
    run_inventory_omission rocky8 pip
    run_inventory_omission rocky8 git
    if [[ "${INVENTORY_OMISSION_TOTAL}" == 15 ]]; then
        record_pass "IOC lifecycle executes exactly fifteen inventory omissions"
    else
        record_fail "IOC lifecycle executes exactly fifteen inventory omissions" \
            "observed ${INVENTORY_OMISSION_TOTAL}"
    fi

    checkout="$(prepare_mutation_checkout dispatch-omission)"
    sed -i '/^[[:space:]]*proxy_contract_main "\$@"$/d' \
        "${checkout}/bin/proxy_contract.bash"
    expect_failure "missing stdin dispatch blocks IOC stop and publication" \
        "${WORKSPACE}/dispatch-omission.log" \
        env PROXY_APPLY_CONTRACT="${TOP}/bin/proxy_contract.bash" \
        bash "${checkout}/tests/check-iocrunner-bake-provenance.bash" \
        seal-case rocky8

    checkout="$(prepare_mutation_checkout ioc-seal-omission)"
    sed -i '/^seal_proxy_contract$/d' "${checkout}/bin/bake_iocrunner_image.bash"
    expect_failure "missing IOC terminal seal blocks publication" \
        "${WORKSPACE}/ioc-seal-omission.log" \
        bash "${checkout}/tests/check-iocrunner-bake-provenance.bash" \
        seal-case rocky8

    checkout="$(prepare_mutation_checkout seed-argument-omission)"
    sed -i 's/PROXY_CONTRACT_CLEAN_ARGS+=(--seed)/: # mutation: omit seed argument/' \
        "${checkout}/bin/proxy_contract.bash"
    expect_success "missing supported cloud-init seed argument leaves seed and blocks publication" \
        "${WORKSPACE}/seed-argument-omission.log" \
        bash "${checkout}/tests/check-iocrunner-bake-provenance.bash" seed-omission
}

function run_joined_gate {
    if ! validate_fixture; then
        return 1
    fi
    verify_fresh_consumer
    expect_success "shipped producer matches the independent exact set" \
        "${WORKSPACE}/producer.log" bash "${TOP}/tests/check-proxy-injection.bash"
    expect_success "shipped Debian IOC bake executes the exact terminal seal" \
        "${WORKSPACE}/ioc-bake-debian13.log" \
        bash "${TOP}/tests/check-iocrunner-bake-provenance.bash" \
        seal-case debian13
    expect_success "shipped Rocky IOC bake executes the exact terminal seal" \
        "${WORKSPACE}/ioc-bake-rocky8.log" \
        bash "${TOP}/tests/check-iocrunner-bake-provenance.bash" \
        seal-case rocky8
}

case "${1:-all}" in
    joined)
        run_joined_gate || true
        ;;
    all)
        run_joined_gate || true
        expect_failure "filename execution rejects an invalid operand" \
            "${WORKSPACE}/filename-invalid.log" \
            bash "${TOP}/bin/proxy_contract.bash" invalid
        expect_failure "production stdin execution rejects an invalid operand" \
            "${WORKSPACE}/stdin-invalid.log" \
            /bin/bash -p -s -- invalid < "${TOP}/bin/proxy_contract.bash"
        expect_fixture_mutation_failure fixture-identity-mutation 2 invalid-identity
        expect_fixture_mutation_failure fixture-form-mutation 7 shared
        expect_fixture_mutation_failure fixture-marker-mutation 8 invalid-marker
        run_mutations
        ;;
    *)
        printf "Usage: %s [joined|all]\n" "$(basename "$0")" >&2
        exit 2
        ;;
esac

printf "Summary: %s passed / %s total\n" "${TEST_PASSED}" "${TEST_TOTAL}"
if [[ "${TEST_FAILED}" -gt 0 ]]; then
    printf "Failures:\n" >&2
    printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
    exit 1
fi
