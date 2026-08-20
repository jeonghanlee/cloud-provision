# cloud-provision

Cloud-init based VM provisioner for libvirt/KVM.
Provisions reproducible multi-node test environments from official cloud images.

* Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
* Image workflow: [docs/IMAGE_WORKFLOW.md](docs/IMAGE_WORKFLOW.md) — how images are made and used, from upstream base to VM disk
* Bake runbook: [docs/RUNBOOK_BAKE.md](docs/RUNBOOK_BAKE.md) — running a golden image bake and accepting the result
* Ansible inventory runbook: [docs/RUNBOOK_ANSIBLE_INVENTORY.md](docs/RUNBOOK_ANSIBLE_INVENTORY.md) — generating host inventory from a VM
* Work register: [docs/milestone-c53e17e.md](docs/milestone-c53e17e.md) — current work, external gates, and the next session entry point
* CLI Reference: [docs/VIRSH_CLI.md](docs/VIRSH_CLI.md)
* Host setup: `bin/setup_host.bash`
* Software deployment: [ansible-provision](https://github.com/jeonghanlee/ansible-provision) (next stage on top of these VMs)

## Prerequisites

```bash
make setup          # install the host virtualization stack
make check-tools    # verify required host commands are present
```

## Makefile Workflow

Override image storage path via:

```bash
echo "IMAGE_DIR=/data/libvirt/images" > configure/CONFIG_SITE.local
```

The required host group defaults to `libvirt` through `REQUIRED_GROUP`.

### Target families

The repository has several selectors that look similar but operate at different layers:

| Selector set | Values | Used by | Meaning |
|---|---|---|---|
| `DEFAULT_OS_TYPES` | `rocky8`, `debian13` | `make all`, `make status`, `make stop` | Plain base test VMs. |
| `OS_TYPES` | all values accepted by `create_vm.bash -o` | per-OS targets, `make clean` | Every provisionable VM type, including baked variants and EPICS-env build hosts. |
| `BAKE_OS_TYPES` | `rocky8`, `debian13` | `make bake`, `make bake.<os>` | Base OS inputs used to produce IOC runner golden image pairs. |
| `ETHERCAT_BAKE_OS_TYPES` | `debian13` | `make bake.ethercat`, `make bake.ethercat.<os>` | Base OS input used to produce the EtherCAT golden image. |

Operational rule: bake commands create golden images; provision commands boot VMs from either a public cloud image or a local golden image.

Each golden image has a unique UTC timestamp and hash in its filename, a
`.manifest` sidecar when the bake supplies provenance, and a `.creation-record`
sidecar. Bake build VM disks use the same run-specific naming and creation
record path. Provisioning selects the newest golden image whose creation record
matches the filename, kind, and platform. Ordinary runtime VM disks keep stable
names but remain independent copies; no produced image is used as another
image's backing file.

### Provision

```bash
make rocky8               # server + node1 + node2
make debian13             # server + node1 + node2
make all                  # base OS types only
```

```bash
make rocky8.server
make rocky8.node1
make rocky8.node2
```

### EPICS-env from-source build

Provision the two core epics-env VMs (.120 / .20, `EPICS_ENV_RAM` MB each)
and build EPICS-env from source on each via ansible-provision, in one command.
Both the VMs and the ansible role are idempotent.

The core group carries the internal distribution targets. The rocky10 (.130)
and ubuntu26 (.30) matrix VMs extend the OS coverage for the public
distribution and are driven with their own ansible invocations, so they are
provisioned without building.

```bash
make epics-env                    # provision both core VMs and build EPICS-env from source
make epics-env.provision          # provision the two core VMs only
make epics-env.provision.matrix   # provision the rocky10 / ubuntu26 matrix VMs only
make help.epics-env               # show this workflow
```

### Ansible inventory

`ansible-provision/inventory/testbed.ini` contains group relationships and no
fixed VM host rows. Generate each host entry from the actual VM status with
`bin/generate_ansible_inventory.bash`, then pass the generated file as the
second inventory source. The ioc-runner bake, EtherCAT bake, and `make
epics-env` perform this automatically.

See [docs/RUNBOOK_ANSIBLE_INVENTORY.md](docs/RUNBOOK_ANSIBLE_INVENTORY.md) for
ordinary VMs, consumer VMs, and direct Ansible use.

### Status

```bash
make status               # base OS types only
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
make stop                 # graceful shutdown, base OS types only
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
make clean all                              # every VM type, then the 6 base VMs
```

`clean` removes the VM domain, independent qcow2 disk, matching creation
record, and seed ISO. The follow-up provision rebuilds from the cached base
image and re-runs cloud-init from scratch. Per-VM time is roughly one minute.

### Bake IOC runner variants

The `rocky8-iocrunner` / `debian13-iocrunner` OS variants boot from
pre-baked golden images that already contain the full software stack
(`site.yml`, `04_nfs_sim.yml`, and `07_test_users.yml` from
ansible-provision). Bake once, then provision repeatedly without
re-running ansible at first boot.

```bash
make bake.rocky8
make bake.debian13
make bake                              # both base OS types
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

| Flag | Description                                                                            | Default                   |
|------|----------------------------------------------------------------------------------------|---------------------------|
| `-o` | OS type: `rocky8`, `debian13` (required)                                               |                           |
| `-d` | Image storage directory                                                                | `~/libvirt/images`        |
| `-a` | ansible-provision directory                                                            | `../ansible-provision`    |
| `-k` | Keep build VM after bake                                                               | destroy                   |
| `-r` | Pin the epics-ioc-runner ref baked into the image                                      | resolved by the inventory |
### Bake EtherCAT variant

The EtherCAT path is separate from IOC runner. It bakes from the Debian 13 RT base selector and produces the local image consumed by `debian13-ethercat`.

```bash
make bake.ethercat.debian13
make bake.ethercat
make debian13-ethercat.server
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
bin/create_vm.bash -o rocky8 -n server -S   # graceful shutdown
bin/create_vm.bash -o rocky8 -n server -c   # cleanup
```

Options:

| Flag | Description                              | Default            |
|------|------------------------------------------|--------------------|
| `-o` | OS type: `rocky8`, `debian13`, `rocky8-iocrunner`, `debian13-iocrunner`, `debian13-ethercat`, `debian13-rtbase`, `epics-env-rocky8`, `epics-env-debian13`, `epics-env-rocky10`, `epics-env-ubuntu26`, `epics-env-ubuntu24` | `rocky8` |
| `-n` | Node ID: `server`, `node1`, `node2`, ... | `test` (DHCP)      |
| `-d` | Image storage directory                  | `~/libvirt/images` |
| `-p` | VM name prefix                           | `testbed`          |
| `-m` | VM memory in MB                          | `4096`             |
| `-F` | Refuse if domain or disk exists (provisioning only) |         |
| `-s` | Check domain, IP, SSH, and cloud-init readiness |             |
| `-S` | Graceful shutdown (ACPI, polls until shut off) |              |
| `-c` | Remove VM domain, disk, and seed ISO     |                    |
