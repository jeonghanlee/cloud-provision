# cloud-provision

Cloud-init based VM provisioner for libvirt/KVM.
Provisions reproducible multi-node test environments from official cloud images.

* Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
* CLI Reference: [docs/VIRSH_CLI.md](docs/VIRSH_CLI.md)
* Host setup: `bin/setup_host.bash`
* Software deployment: [ansible-provision](https://github.com/jeonghanlee/ansible-provision) (next stage on top of these VMs)

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

### Stop

```bash
make stop                 # graceful shutdown of all VMs
make rocky8.stop          # all rocky8 nodes
make rocky8.server.stop
```

### Cleanup

```bash
make clean                # all VMs
make rocky8.clean         # all rocky8 nodes
make rocky8.server.clean
```

### Reset to Baseline

Restore a node to a fresh OS state without residue. Use this when a
downstream provisioner (e.g. ansible-provision) leaves partial state
and the cleanest path is to rebuild the baseline before re-running.

```bash
make rocky8.server.clean rocky8.server      # one VM
make rocky8.clean rocky8                    # one OS group
make clean all                              # all 6 VMs
```

`clean` removes the VM domain, layered qcow2 disk, and seed ISO. The
follow-up provision rebuilds from the cached base image and re-runs
cloud-init from scratch. Per-VM time is roughly one minute.

### Bake iocrunner-test Variants

The `rocky8-iocrunner` / `debian13-iocrunner` OS variants boot from
pre-baked golden images that already contain the full software stack
(ansible-provision `site.yml` plus `04_nfs_sim.yml`). Bake once, then
provision repeatedly without re-running ansible at first boot.

```bash
bin/bake_iocrunner_image.bash -o rocky8
bin/bake_iocrunner_image.bash -o debian13
```

Once baked, the variants are usable through the standard Makefile:

```bash
make rocky8-iocrunner.server
make debian13-iocrunner
```

`make all` excludes the pre-baked variants until their golden image
exists; `make clean` covers them. See [docs/ARCHITECTURE.md section
12](docs/ARCHITECTURE.md) for the full pipeline.

Bake script options:

| Flag | Description                              | Default                |
|------|------------------------------------------|------------------------|
| `-o` | OS type: `rocky8`, `debian13` (required) |                        |
| `-d` | Image storage directory                  | `~/libvirt/images`     |
| `-a` | ansible-provision directory              | `../ansible-provision` |
| `-k` | Keep build VM after bake                 | destroy                |

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
bin/create_vm.bash -o rocky8 -n server -S   # graceful shutdown
bin/create_vm.bash -o rocky8 -n server -c   # cleanup
```

Options:

| Flag | Description                              | Default            |
|------|------------------------------------------|--------------------|
| `-o` | OS type: `rocky8`, `debian13`, `rocky8-iocrunner`, `debian13-iocrunner` | `rocky8` |
| `-n` | Node ID: `server`, `node1`, `node2`, ... | `test` (DHCP)      |
| `-d` | Image storage directory                  | `~/libvirt/images` |
| `-p` | VM name prefix                           | `testbed`          |
| `-s` | Check domain, IP, SSH, and cloud-init readiness |             |
| `-S` | Graceful shutdown (ACPI, polls until shut off) |              |
| `-c` | Remove VM domain, disk, and seed ISO     |                    |
