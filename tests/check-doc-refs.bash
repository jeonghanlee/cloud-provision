#!/usr/bin/env bash
#
# Verifies that every source coordinate cited by a document names the tree it
# was read from.
#
# A bare file:line rots silently. Inserting one line anywhere above shifts every
# coordinate below it, and no suite in this repository can see a document become
# false - they all pass either way. On 2026-08-01 ten of sixteen citations in
# docs/milestone.md pointed at unrelated lines for exactly that reason; each was
# correct when written and had been overtaken by later commits.
#
# Pinning the coordinate to a commit removes the failure instead of alarming on
# it: `bin/foo.bash:95@77fd36e` cannot drift, because the tree it names is
# immutable. So this check has only two jobs - refuse a citation that names no
# tree, and catch the writing-time mistakes a pin cannot prevent (a mistyped
# hash, a path absent from that tree, a line past its end).
#
# What it cannot do: judge whether the cited line says what the prose around it
# claims. A citation aimed at the wrong line of the right file at the right tree
# passes here and always will, because the claim lives in English. The pin makes
# a coordinate reproducible, not true; a reader who doubts one runs
# git show <hash>:<path> and reads it.
#
# Paths outside this repository - ansible-provision roles cited by the docs,
# for instance - are not resolvable here and are left alone.

set -euo pipefail

declare -g SCRIPT_DIR
declare -g TOP
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -ag FAILED_DETAILS=()

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source trees whose coordinates this repository can resolve. A citation of any
# other path is somebody else's file and is not inspected.
declare -ag LOCAL_PREFIXES=(bin tests configure templates)

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

function prefix_pattern {
    local IFS="|"
    printf "%s" "${LOCAL_PREFIXES[*]}"
}

function documents {
    git -C "${TOP}" ls-files -- 'docs/*.md' 'README.md'
}

# A citation carrying a tree: <path>:<line>[-<line>]@<hash>. The hash makes the
# coordinate reproducible with git show <hash>:<path>.
function check_pinned_citation {
    local citation="$1"
    local locator="${citation%@*}"
    local hash="${citation##*@}"
    local path="${locator%%:*}"
    local lines="${locator##*:}"
    local first="${lines%%-*}"
    local last="${lines##*-}"
    local blob
    local length

    if ! git -C "${TOP}" rev-parse --verify --quiet "${hash}^{commit}" >/dev/null; then
        record_fail "${citation}" "no such commit in this repository"
        return
    fi

    if ! blob="$(git -C "${TOP}" show "${hash}:${path}" 2>/dev/null)"; then
        record_fail "${citation}" "path absent from ${hash}"
        return
    fi

    length="$(printf "%s\n" "${blob}" | wc -l)"
    if [[ "${last}" -gt "${length}" ]]; then
        record_fail "${citation}" "line ${last} past end of file (${length} lines at ${hash})"
        return
    fi

    if [[ "${first}" -lt "1" ]]; then
        record_fail "${citation}" "line number below 1"
        return
    fi

    record_pass "${citation}"
}

function check_pinned_citations {
    local -a citations=()
    local citation

    mapfile -t citations < <(
        documents \
            | xargs -r git -C "${TOP}" grep -ohE \
                "\`($(prefix_pattern))/[A-Za-z0-9._/-]+:[0-9]+(-[0-9]+)?@[0-9a-f]{7,40}\`" -- \
            | tr -d '`' \
            | sort -u
    )

    if [[ "${#citations[@]}" -eq "0" ]]; then
        record_fail "documents cite at least one source coordinate" \
            "no pinned citation found; the extraction pattern may have drifted"
        return
    fi

    for citation in "${citations[@]}"; do
        check_pinned_citation "${citation}"
    done
}

# Reports document:line and the offending coordinate alone. A register row runs
# to thousands of characters, so echoing the matched line back would bury the
# one token the reader has to fix.
function report_offenders {
    local name="$1"
    local pattern="$2"
    local -a offenders=()

    mapfile -t offenders < <(
        documents | xargs -r git -C "${TOP}" grep -noE "${pattern}" -- | sort -u
    )

    if [[ "${#offenders[@]}" -eq "0" ]]; then
        record_pass "${name}"
        return
    fi

    record_fail "${name}" "$(printf "%s " "${offenders[@]}")"
}

# The regression guard. A coordinate written without a tree is the defect this
# check exists for, so it fails on sight rather than being reported as a note.
function check_no_unpinned_citation {
    report_offenders "every source coordinate names its tree" \
        "\`($(prefix_pattern))/[A-Za-z0-9._/-]+:[0-9]+(-[0-9]+)?\`"
}

# A coordinate with no file at all - :437 in backticks - reads only against the
# prose around it, which no tool can follow and a later editor can break by
# moving a sentence.
function check_no_bare_line_citation {
    report_offenders "every coordinate names its file" \
        "\`:[0-9]+(-[0-9]+)?\`"
}

function print_summary {
    printf "Summary: %s passed / %s total\n" "${TEST_PASSED}" "${TEST_TOTAL}"
    if [[ "${TEST_FAILED}" -gt "0" ]]; then
        printf "Failures:\n" >&2
        printf "  %s\n" "${FAILED_DETAILS[@]}" >&2
        return 1
    fi
}

check_pinned_citations
check_no_unpinned_citation
check_no_bare_line_citation
print_summary
