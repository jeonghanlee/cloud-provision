#!/usr/bin/env bash
#
# MAC identity and DHCP reservation operations for the VM provisioner.

declare -gr VM_NETWORK_MAC_PREFIX="02"

function vm_network_mac {
    local name="$1"
    local digest

    digest="$(printf '%s' "${name}" | sha256sum)" || return 1
    digest="${digest%% *}"
    [[ "${digest}" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s:%s:%s:%s:%s:%s\n' "${VM_NETWORK_MAC_PREFIX}" \
        "${digest:0:2}" "${digest:2:2}" "${digest:4:2}" \
        "${digest:6:2}" "${digest:8:2}"
}

# Read canonical virsh XML as MAC|IP|name rows. Missing MACs remain visible
# so reservations identified by a client ID or a name still block an address.
function vm_network_reservations {
    local scope="$1"
    local xml
    local -a options=()

    [[ "${scope}" != "config" ]] || options+=(--inactive)
    xml="$(virsh --connect "${LIBVIRT_URI}" net-dumpxml \
        "${LIBVIRT_NETWORK}" "${options[@]}")" || return 1
    [[ -n "${xml}" ]] || return 1
    awk -F"['\"]" -v RS='>' '
        /<dhcp([[:space:]]|$)/ { dhcp = 1 }
        /<\/dhcp/ { dhcp = 0 }
        dhcp && /<host[[:space:]]/ {
            mac = "-"; addr = ""; name = ""
            for (i = 2; i <= NF; i += 2) {
                if ($(i-1) ~ /mac=$/) mac = tolower($i)
                if ($(i-1) ~ /ip=$/) addr = $i
                if ($(i-1) ~ /name=$/) name = $i
            }
            if (addr != "") printf "%s|%s|%s\n", mac, addr, name
        }
    ' <<< "${xml}"
}

# Existing domains retain their actual interface MAC, including the legacy
# address-derived scheme. A missing or ambiguous interface is not guessed.
function vm_network_existing_mac {
    local interfaces
    local mac

    if ! virsh --connect "${LIBVIRT_URI}" dominfo "${VM_NAME}" >/dev/null 2>&1; then
        return 0
    fi
    interfaces="$(virsh --connect "${LIBVIRT_URI}" domiflist \
        "${VM_NAME}" --inactive)" || return 1
    mac="$(awk -v network="${LIBVIRT_NETWORK}" '
        $2 == "network" && $3 == network { print tolower($5) }
    ' <<< "${interfaces}")"
    if [[ ! "${mac}" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
        printf 'Error: cannot identify one %s interface for %s.\n' \
            "${LIBVIRT_NETWORK}" "${VM_NAME}" >&2
        return 1
    fi
    VM_MAC="${mac}"
}

function vm_network_owned_reservation {
    local mac="$1"
    local ip="$2"
    local name="$3"

    [[ "${ip}" == "${VM_IP}" ]] || return 1
    if [[ "${mac}" == "${VM_MAC}" && \
          ( -z "${name}" || "${name}" == "${VM_NAME}" ) ]]; then
        return 0
    fi
    # A legacy orphan is attributable only by its exact historical name,
    # address and MAC; the legacy MAC by itself has only 95 hashed values.
    [[ "${mac}" == "${VM_LEGACY_MAC}" && "${name}" == "${VM_NAME}" ]]
}

# A lease outlives the reservation that produced it. While another MAC still
# holds the address, dnsmasq does not hand it to the new reservation, so the
# new guest takes another address and its readiness probe fails. Refuse before
# anything is created. A holder that still has a live reservation is a VM that
# keeps renewing its lease, so waiting cannot help; any other holder is an
# orphan whose expiry tells the operator when to retry.
function check_dhcp_lease {
    local leases reserved
    local expiry_date expiry_time mac protocol addr

    [[ -n "${VM_IP}" && -n "${VM_MAC}" ]] || return 0
    if ! leases="$(virsh --connect "${LIBVIRT_URI}" net-dhcp-leases \
        "${LIBVIRT_NETWORK}")"; then
        printf 'Error: cannot read the DHCP leases of network %s; nothing was created.\n' \
            "${LIBVIRT_NETWORK}" >&2
        return 1
    fi
    while read -r expiry_date expiry_time mac protocol addr _; do
        [[ "${protocol}" == "ipv4" && "${addr%/*}" == "${VM_IP}" ]] || continue
        mac="${mac,,}"
        [[ "${mac}" != "${VM_MAC}" ]] || continue
        if ! reserved="$(vm_network_reservations live)"; then
            printf 'Error: %s is leased to MAC %s until %s %s, and its reservations cannot be read; nothing was created.\n' \
                "${VM_IP}" "${mac}" "${expiry_date}" "${expiry_time}" >&2
            return 1
        fi
        if awk -F'|' -v holder="${mac}" '$1 == holder { found = 1 } END { exit !found }' \
            <<< "${reserved}"; then
            printf 'Error: %s is in use by the VM with MAC %s, which holds its reservation and an active lease; nothing was created.\n' \
                "${VM_IP}" "${mac}" >&2
            printf 'Hint: remove that VM with its cleanup command or choose a different node ID.\n' >&2
        else
            printf 'Error: %s is leased to MAC %s until %s %s; nothing was created.\n' \
                "${VM_IP}" "${mac}" "${expiry_date}" "${expiry_time}" >&2
            printf 'Hint: no VM holds a reservation for that MAC; retry after the lease expires or choose a different node ID.\n' >&2
        fi
        return 1
    done <<< "${leases}"
}

function register_dhcp {
    local live
    local config
    local scope rows mac ip name

    [[ -n "${VM_IP}" && -n "${VM_MAC}" ]] || return 0
    live="$(vm_network_reservations live)" || return 1
    config="$(vm_network_reservations config)" || return 1

    # Validate both configurations before deleting or replacing any entry.
    for rows in "${live}" "${config}"; do
        while IFS='|' read -r mac ip name; do
            [[ -n "${ip}" ]] || continue
            if [[ "${ip}" == "${VM_IP}" || "${mac}" == "${VM_MAC}" ]]; then
                if ! vm_network_owned_reservation "${mac}" "${ip}" "${name}"; then
                    printf 'Error: %s is already reserved for MAC %s (%s).\n' \
                        "${ip}" "${mac}" "${name:-unnamed}" >&2
                    printf 'Hint: choose a different node ID or inspect the existing reservation.\n' >&2
                    return 1
                fi
            fi
        done <<< "${rows}"
    done

    printf 'Network: registering %s -> %s (%s)... ' "${VM_NAME}" "${VM_IP}" "${VM_MAC}"
    for scope in live config; do
        rows="${live}"
        [[ "${scope}" != "config" ]] || rows="${config}"
        while IFS='|' read -r mac ip name; do
            [[ -n "${ip}" ]] || continue
            if vm_network_owned_reservation "${mac}" "${ip}" "${name}"; then
                virsh --connect "${LIBVIRT_URI}" net-update "${LIBVIRT_NETWORK}" \
                    delete ip-dhcp-host "<host mac='${mac}' ip='${ip}'/>" \
                    "--${scope}" || return 1
            fi
        done <<< "${rows}"
    done
    virsh --connect "${LIBVIRT_URI}" net-update "${LIBVIRT_NETWORK}" \
        add ip-dhcp-host "<host mac='${VM_MAC}' ip='${VM_IP}'/>" \
        --live --config || return 1
    printf '[OK]\n'
}

function unregister_dhcp {
    local live
    local config
    local scope rows mac ip name
    local removed=false

    [[ -n "${VM_IP}" && -n "${VM_MAC}" ]] || return 0
    live="$(vm_network_reservations live)" || return 1
    config="$(vm_network_reservations config)" || return 1
    printf '  Removing DHCP reservation... '
    for scope in live config; do
        rows="${live}"
        [[ "${scope}" != "config" ]] || rows="${config}"
        while IFS='|' read -r mac ip name; do
            [[ -n "${ip}" ]] || continue
            if vm_network_owned_reservation "${mac}" "${ip}" "${name}"; then
                virsh --connect "${LIBVIRT_URI}" net-update "${LIBVIRT_NETWORK}" \
                    delete ip-dhcp-host "<host mac='${mac}' ip='${ip}'/>" \
                    "--${scope}" || return 1
                removed=true
            fi
        done <<< "${rows}"
    done
    if [[ "${removed}" == true ]]; then
        printf '[OK]\n'
    else
        printf '[not found]\n'
    fi
}
