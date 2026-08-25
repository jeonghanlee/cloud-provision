#!/usr/bin/env bash
#
# Verifies that the proxy ADR and RUNBOOK_BAKE carry the durable statements M6
# and M7 record, which check-doc-refs cannot judge (it validates source
# coordinates, not prose). Each statement below is a phrase authored together
# with the prose it asserts, so the assertion and the text cannot drift apart:
# removing the statement from a document fails this check.

set -euo pipefail

declare -g SCRIPT_DIR
declare -g TOP
declare -g ADR
declare -g RUNBOOK
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -ag FAILED_DETAILS=()

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"
ADR="${TOP}/docs/decisions/ADR-20260820-proxy-artifact-lifecycle.md"
RUNBOOK="${TOP}/docs/RUNBOOK_BAKE.md"

function record_pass {
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_PASSED=$((TEST_PASSED + 1))
    printf "[ PASS ] %s\n" "$1"
}

function record_fail {
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_FAILED=$((TEST_FAILED + 1))
    FAILED_DETAILS+=("$1: $2")
    printf "[ FAIL ] %s\n" "$1" >&2
    printf "  %s\n" "$2" >&2
}

# Assert that a file contains a fixed phrase.
function expect_phrase {
    local name="$1"
    local file="$2"
    local phrase="$3"

    if grep -Fq "${phrase}" "${file}"; then
        record_pass "${name}"
    else
        record_fail "${name}" "missing phrase: ${phrase}"
    fi
}

[[ -f "${ADR}" ]] || { printf "Error: ADR not found: %s\n" "${ADR}" >&2; exit 1; }
[[ -f "${RUNBOOK}" ]] || { printf "Error: RUNBOOK not found: %s\n" "${RUNBOOK}" >&2; exit 1; }

# M7 - package install ordering, and its reason, in both documents.
expect_phrase "ADR states packages install after the proxy apply through Ansible" \
    "${ADR}" "packages install after the proxy apply through Ansible"
expect_phrase "ADR states the cloud-init package module runs before the apply" \
    "${ADR}" "before the runcmd proxy apply"
expect_phrase "RUNBOOK states packages install after the proxy apply through Ansible" \
    "${RUNBOOK}" "packages install after the proxy apply through Ansible"
expect_phrase "RUNBOOK states the cloud-init package module runs before the apply" \
    "${RUNBOOK}" "before the runcmd proxy apply"

# M6 - base-image locale dependency, in both documents.
expect_phrase "ADR states the base-image locale dependency" \
    "${ADR}" "depend on the base image already"
expect_phrase "RUNBOOK states the base-image locale dependency" \
    "${RUNBOOK}" "rely on the base image already"

# Both statements reference D018.
expect_phrase "ADR references D018" "${ADR}" "D018"
expect_phrase "RUNBOOK references D018" "${RUNBOOK}" "D018"

printf "Summary: %s passed / %s total\n" "${TEST_PASSED}" "${TEST_TOTAL}"
if [[ "${TEST_FAILED}" -gt 0 ]]; then
    printf "Failures:\n" >&2
    printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
    exit 1
fi
