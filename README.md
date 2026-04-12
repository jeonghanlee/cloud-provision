# cloud-provision

Cloud-init based VM provisioner for libvirt/KVM test environments.

## Prerequisites

Run the host setup script to verify and install required packages:

```bash
./bin/setup_host.bash
```

This checks for libvirt, qemu, genisoimage, SSH keys, and libvirt group membership.
Manual installation if preferred:

```bash
# Rocky Linux 8
sudo dnf install libvirt virt-install qemu-kvm genisoimage

# Debian 13
sudo apt install libvirt-daemon-system virt-install qemu-system-x86 genisoimage
```

User must be in the `libvirt` group:

```bash
sudo usermod -aG libvirt $USER
```

## Supported OS

| OS Type   | Base Image                                       |
|-----------|--------------------------------------------------|
| rocky8    | Rocky-8-GenericCloud-Base.latest.x86_64.qcow2    |
| debian13  | debian-13-genericcloud-amd64.qcow2               |

## Usage

```bash
./bin/create_vm.bash -o <os_type> -n <node_id> [-d <image_dir>] [-p <prefix>]
./bin/create_vm.bash -o <os_type> -n <node_id> -s    # check status
./bin/create_vm.bash -o <os_type> -n <node_id> -c    # cleanup
```

## Multi-Node Test Environment

```bash
# Rocky 8.10 set
./bin/create_vm.bash -o rocky8 -n server
./bin/create_vm.bash -o rocky8 -n node1
./bin/create_vm.bash -o rocky8 -n node2

# Debian 13 set
./bin/create_vm.bash -o debian13 -n server
./bin/create_vm.bash -o debian13 -n node1
./bin/create_vm.bash -o debian13 -n node2
```

## VM Specifications

| Resource | Value          |
|----------|----------------|
| RAM      | 2048 MB        |
| vCPUs    | 2              |
| Disk     | 20 GB (qcow2)  |
| Network  | libvirt default |

## Cloud-Init Templates

OS-specific templates in `templates/` provide:

- `vmadmin` account with SSH key injection
- Development packages (gcc, make, autoconf, automake, OpenSSL headers)
- Timezone set to America/Los_Angeles
