# cloud-provision

Cloud-init based VM provisioner for libvirt/KVM.
Provisions reproducible multi-node test environments from official cloud images.

* Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
* CLI Reference: [docs/VIRSH_CLI.md](docs/VIRSH_CLI.md)
* Host setup: `bin/setup_host.bash`

## Prerequisites

```bash
bin/setup_host.bash
```

## Makefile Workflow

Override image storage path via:

```bash
echo "IMAGE_DIR=/data/libvirt/images" > configure/CONFIG_SITE.local
```

### Provision

```bash
make rocky8               # server + node1 + node2
make debian13             # server + node1 + node2
make all                  # all OS types
```

```bash
make rocky8.server
make rocky8.node1
make rocky8.node2
```

### Status

```bash
make status               # all VMs
make rocky8.status        # all rocky8 nodes
make rocky8.server.status
```

```bash
make list                 # virsh list --all
make leases               # DHCP lease table
make net                  # libvirt network list
```

### Cleanup

```bash
make clean                # all VMs
make rocky8.clean         # all rocky8 nodes
make rocky8.server.clean
```

### Configuration

```bash
make vars
make PRINT.IMAGE_DIR
```

---

## Direct CLI Workflow

```bash
bin/create_vm.bash -o rocky8   -n server
bin/create_vm.bash -o rocky8   -n node1
bin/create_vm.bash -o debian13 -n server
```

```bash
bin/create_vm.bash -o rocky8 -n server -s   # status check
bin/create_vm.bash -o rocky8 -n server -c   # cleanup
```

Options:

| Flag | Description                              | Default            |
|------|------------------------------------------|--------------------|
| `-o` | OS type: `rocky8`, `debian13`            | `rocky8`           |
| `-n` | Node ID: `server`, `node1`, `node2`, ... | `test` (DHCP)      |
| `-d` | Image storage directory                  | `~/libvirt/images` |
| `-p` | VM name prefix                           | `testbed`          |
| `-s` | Check IP, SSH, and cloud-init readiness  |                    |
| `-c` | Remove VM domain, disk, and seed ISO     |                    |
