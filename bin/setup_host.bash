#!/usr/bin/env bash
#
# Host environment setup for cloud-provision.
# Verifies and installs required virtualization packages.

set -e

declare -g OS_ID
declare -g REQUIRED_GROUP="${REQUIRED_GROUP:-libvirt}"

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID}"
fi

printf "%s\n" "------------------------------------------------------------"
printf "Host Environment Setup (%s)\n" "${OS_ID:-unknown}"
printf "%s\n" "------------------------------------------------------------"

# OS-specific package configuration
if [[ "${OS_ID}" == "rocky" ]]; then
    PKG_CMD="dnf"
    PKG_LIST="libvirt virt-install qemu-kvm genisoimage util-linux"
elif [[ "${OS_ID}" == "debian" ]]; then
    PKG_CMD="apt"
    PKG_LIST="libvirt-daemon-system virt-install qemu-system-x86 qemu-utils genisoimage uuid-runtime"
else
    printf "Error: Unsupported host OS: %s\n" "${OS_ID:-unknown}"
    exit 1
fi

# Verify required binaries
declare -a BINARIES=("virt-install" "qemu-img" "genisoimage" "virsh" "uuidgen")
declare -g NEED_INSTALL=false

for bin in "${BINARIES[@]}"; do
    if command -v "${bin}" >/dev/null 2>&1; then
        printf "  %-15s [OK]\n" "${bin}"
    else
        printf "  %-15s [MISSING]\n" "${bin}"
        NEED_INSTALL=true
    fi
done

if [[ "${NEED_INSTALL}" == true ]]; then
    printf "Installing virtualization packages...\n"
    if [[ "${OS_ID}" == "debian" ]]; then
        sudo "${PKG_CMD}" update
    fi
    sudo ${PKG_CMD} install -y ${PKG_LIST}
fi

# SSH key check
if [[ -f "${HOME}/.ssh/id_ed25519.pub" ]] || [[ -f "${HOME}/.ssh/id_rsa.pub" ]]; then
    printf "  SSH public key  [OK]\n"
else
    printf "  SSH public key  [MISSING] Run ssh-keygen\n"
fi

# libvirt service
if ! systemctl is-active --quiet libvirtd; then
    printf "Starting libvirtd...\n"
    sudo systemctl enable --now libvirtd
fi
printf "  libvirtd        [ACTIVE]\n"

# libvirt networks
LIBVIRT_URI="qemu:///system"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(dirname "${SCRIPT_DIR}")"

# Ensure a defined libvirt network is autostarted and active. Idempotent: a
# network already autostarting or already active is left as is.
ensure_network() {
    local net_name="$1"
    local autostart active
    autostart="$(sudo virsh --connect "${LIBVIRT_URI}" net-info "${net_name}" 2>/dev/null \
        | awk '/^Autostart:/ {print $2}')"
    active="$(sudo virsh --connect "${LIBVIRT_URI}" net-info "${net_name}" 2>/dev/null \
        | awk '/^Active:/ {print $2}')"
    if [[ "${autostart}" != "yes" ]]; then
        printf "Setting %s network autostart...\n" "${net_name}"
        sudo virsh --connect "${LIBVIRT_URI}" net-autostart "${net_name}"
    fi
    if [[ "${active}" != "yes" ]]; then
        printf "Starting %s network...\n" "${net_name}"
        sudo virsh --connect "${LIBVIRT_URI}" net-start "${net_name}"
    fi
    printf "  %s network [ACTIVE]\n" "${net_name}"
}

# The libvirt-provided default network already exists; just ensure it runs.
ensure_network "default"

# The lab network is repository-defined and isolated onto its own subnet and
# MAC space; define it from the shipped file when the host does not have it
# yet, then ensure it runs. The probe stays set-e-safe: a bare net-info of an
# undefined network exits nonzero and would abort the script.
if ! sudo virsh --connect "${LIBVIRT_URI}" net-info "lab" >/dev/null 2>&1; then
    printf "Defining lab network from %s...\n" "${TOP}/configure/lab-network.xml"
    sudo virsh --connect "${LIBVIRT_URI}" net-define "${TOP}/configure/lab-network.xml"
fi
ensure_network "lab"

# Group membership
if groups "$USER" | grep -q "\b${REQUIRED_GROUP}\b"; then
    printf "  %-15s [OK]\n" "${REQUIRED_GROUP} group"
else
    printf "  %-15s [MISSING] Run: sudo usermod -aG %s %s\n" \
        "${REQUIRED_GROUP} group" "${REQUIRED_GROUP}" "$USER"
fi

printf "%s\n" "------------------------------------------------------------"
printf "Host setup complete.\n"
printf "%s\n" "------------------------------------------------------------"
