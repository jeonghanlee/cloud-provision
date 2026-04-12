#!/usr/bin/env bash
#
# Host environment setup for cloud-provision.
# Verifies and installs required virtualization packages.

set -e

declare -g OS_ID

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
    PKG_LIST="libvirt virt-install qemu-kvm genisoimage"
elif [[ "${OS_ID}" == "debian" ]]; then
    PKG_CMD="apt"
    PKG_LIST="libvirt-daemon-system virt-install qemu-system-x86 genisoimage"
else
    printf "Error: Unsupported host OS: %s\n" "${OS_ID:-unknown}"
    exit 1
fi

# Verify required binaries
declare -a BINARIES=("virt-install" "qemu-img" "genisoimage" "virsh")
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

# Group membership
if groups "$USER" | grep -q "\blibvirt\b"; then
    printf "  libvirt group   [OK]\n"
else
    printf "  libvirt group   [MISSING] Run: sudo usermod -aG libvirt %s\n" "$USER"
fi

printf "%s\n" "------------------------------------------------------------"
printf "Host setup complete.\n"
printf "%s\n" "------------------------------------------------------------"
