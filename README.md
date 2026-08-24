# cloud-provision

Cloud-init based VM provisioner for libvirt/KVM.
Provisions reproducible test VMs across the supported OS variants from official cloud images.

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
make rocky8               # lab-rocky8-main
make debian13             # lab-debian13-main
make all                  # base OS types only
```

```bash
make rocky8.main
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

`ansible-provision/inventory/lab.ini` contains group relationships and no
fixed VM host rows. Generate each host entry from the actual VM status with
`bin/generate_ansible_inventory.bash`, then pass the generated file as the
second inventory source. The ioc-runner bake, EtherCAT bake, and `make
epics-env` perform this automatically.

See [docs/RUNBOOK_ANSIBLE_INVENTORY.md](docs/RUNBOOK_ANSIBLE_INVENTORY.md) for
ordinary VMs, consumer VMs, and direct Ansible use.

### Status

```bash
make status               # base OS types only
make rocky8.status        # all rocky8 instances
make rocky8.main.status
```

```bash
make list                 # virsh list --all
make leases               # DHCP lease table
make net                  # libvirt network list
```

### Stop

```bash
make stop                 # graceful shutdown, base OS types only
make rocky8.stop          # all rocky8 instances
make rocky8.main.stop
```

### Cleanup

```bash
make clean                # all VMs
make rocky8.clean         # all rocky8 instances
make rocky8.main.clean
```

### Reset to Baseline

Restore a node to a fresh OS state without residue. Use this when a
downstream provisioner (e.g. ansible-provision) leaves partial state
and the cleanest path is to rebuild the baseline before re-running.

```bash
make rocky8.main.clean rocky8.main          # one VM
make rocky8.clean rocky8                    # one OS group
make clean all                              # every VM type, then the two base VMs
```

`clean` removes the VM domain, independent qcow2 disk, matching creation
record, and seed ISO. The follow-up provision rebuilds from the cached base
image and re-runs cloud-init from scratch. Per-VM time is roughly one minute.

### Bake IOC runner variants

The `rocky8-iocrunner` / `debian13-iocrunner` OS variants boot from
pre-baked golden images that already contain the full software stack
(the `iocrunner` species assembly from ansible-provision; the
`iocrunner-nfs` flavor adds the `nfs_sim` operator). Bake once, then
provision repeatedly without re-running ansible at first boot.

```bash
make bake.rocky8
make bake.debian13
make bake                              # both base OS types
make bake.iocrunner-nfs.debian13       # iocrunner-nfs flavor for one OS
make bake.iocrunner-nfs                # iocrunner-nfs flavor for both
```

Once baked, the variants are usable through the standard Makefile:

```bash
make rocky8-iocrunner.main
make debian13-iocrunner
```

`make all` excludes the pre-baked variants until their golden image
exists; `make clean` covers them. See [docs/ARCHITECTURE.md section
12](docs/ARCHITECTURE.md) for the full pipeline.

Bake script options:

| Flag | Description                                                                            | Default                   |
|------|----------------------------------------------------------------------------------------|---------------------------|
| `-o` | OS type: `rocky8`, `debian13` (required)                                               |                           |
| `-f` | Golden flavor: `iocrunner` or `iocrunner-nfs`                                          | `iocrunner`               |
| `-d` | Image storage directory                                                                | `~/libvirt/images`        |
| `-a` | ansible-provision directory                                                            | `../ansible-provision`    |
| `-k` | Keep build VM after bake                                                               | destroy                   |
| `-r` | Pin the epics-ioc-runner ref baked into the image                                      | resolved by the inventory |

### Bake EtherCAT variant

The EtherCAT path is separate from IOC runner. It bakes from the Debian 13 RT base selector and produces the local image consumed by `debian13-ethercat`.

```bash
make bake.ethercat.debian13
make bake.ethercat
make debian13-ethercat.main
```

### Configuration

```bash
make vars
make PRINT.IMAGE_DIR
```

---

## Direct CLI Workflow

```bash
bin/create_vm.bash -o rocky8   -n main
bin/create_vm.bash -o debian13 -n main
bin/create_vm.bash -o rocky8   -n aux    # named instance, hashed address
```

```bash
bin/create_vm.bash -o rocky8 -n main -s   # status check
bin/create_vm.bash -o rocky8 -n main -S   # graceful shutdown
bin/create_vm.bash -o rocky8 -n main -c   # cleanup
```

Options:

| Flag | Description                              | Default            |
|------|------------------------------------------|--------------------|
| `-o` | OS type — bare vacua: `rocky8`, `debian13`, `rocky10`, `ubuntu24`, `ubuntu26`; golden consumers: `rocky8-iocrunner`, `debian13-iocrunner`, `rocky8-iocrunner-nfs`, `debian13-iocrunner-nfs`, `debian13-ethercat`, `debian13-rtbase`; EPICS build hosts: `rocky8-epics-dev`, `debian13-epics-dev`, `rocky10-epics-dev`, `ubuntu24-epics-dev`, `ubuntu26-epics-dev` | `rocky8` |
| `-n` | Instance label: `main` (static base IP), `dhcp` (DHCP), other labels hash to 160-254 | `main` |
| `-d` | Image storage directory                  | `~/libvirt/images` |
| `-p` | VM name prefix                           | `lab`              |
| `-m` | VM memory in MB                          | `4096`             |
| `-F` | Refuse if domain or disk exists (provisioning only) |         |
| `-s` | Check domain, IP, SSH, and cloud-init readiness |             |
| `-S` | Graceful shutdown (ACPI, polls until shut off) |              |
| `-c` | Remove VM domain, disk, and seed ISO     |                    |
