# cloud-provision Architecture

## 1. Overview

A cloud-init based VM provisioner for libvirt/KVM. Provisions reproducible
multi-node test environments from official cloud images without manual
OS installation.

---

## 2. Provisioning Flow

```
[ bin/create_vm.bash ]
     |
     | 1. Acquire base image (download + integrity check)
     |
     | 2. Create layered disk (qcow2 backing file, no base image mutation)
     |
     | 3. Generate seed ISO
     |    - meta-data: instance-id, hostname (from VM_NAME)
     |    - user-data: OS-specific template (templates/user-data.${OS_TYPE})
     |    - SSH public key injection via perl substitution
     |
     | 4. Provision VM (virt-install, virtio, noautoconsole)
     |
     | 5. Readiness check
     |    - Poll for IP address via libvirt DHCP lease
     |    - Wait for SSH availability
     |    - Wait for cloud-init completion
     |
     V
[ VM running, SSH accessible ]
```

---

## 3. VM Lifecycle

The provisioner exposes four idempotent operations on every VM. State
transitions are deterministic and any operation can be replayed without
side effects beyond the intended target state.

```
not defined ───provision───> shut off ───start───> running
                              ^                       │
                              └─────── stop ──────────┘

any state   ───clean───>     not defined
```

| Operation | Effect | Idempotency rule |
|---|---|---|
| `provision` | Build disk, seed, virt-install, readiness check | Re-run on existing domain auto-routes to start (shut off) or no-op (running) |
| `start` | libvirt domain start, readiness check | Routed automatically by `provision` re-run; not exposed as a separate target |
| `stop` | ACPI shutdown plus 60-second poll | No-op for not-defined and shut off domains |
| `clean` | destroy + undefine + remove disk + remove seed + remove DHCP reservation | Safe on missing domain |

**Status reporting** is a separate read-only operation. It reports four
indicators in a single pass (domain state, IP, SSH reachability,
cloud-init completion) so partial-progress diagnostics survive any
failed stage.

**Reset to baseline.** A successive `clean` then provision returns a
node to fresh OS state in roughly one minute per VM. The base cloud
image is preserved as a read-only backing file; only the layered qcow2
delta and seed ISO are discarded, then rebuilt from scratch with a
fresh cloud-init run. Downstream provisioners can rely on this
guarantee — software-side residue is not the responsibility of this
layer.

---

## 4. Storage Architecture

```
${IMAGE_DIR}/
├── Rocky-8-GenericCloud-Base.latest.x86_64.qcow2   (base, read-only, shared)
├── debian-13-genericcloud-amd64-daily.qcow2        (base, read-only, shared)
├── ${VM_NAME}.qcow2                                (layered, per-VM)
└── ${VM_NAME}-seed.iso                             (cloud-init, per-VM)
```

Base images are downloaded once and shared across VMs as backing files.
Each VM disk is a thin-provisioned qcow2 layer that stores only the delta
from the base image.

---

## 5. VM Naming Convention

```
${VM_PREFIX}-${OS_TYPE}-${NODE_ID}
```

| Component   | Default    | Example Values           |
|-------------|------------|--------------------------|
| `VM_PREFIX` | `testbed`  | configurable via `-p`    |
| `OS_TYPE`   | `rocky8`   | `rocky8`, `debian13`     |
| `NODE_ID`   | `test`     | `server`, `node1`, `node2` |

Example: `testbed-rocky8-server`, `testbed-debian13-node1`

---

## 6. Cloud-Init Data Flow

```
templates/user-data.${OS_TYPE}
     |
     | perl: SSH_AUTHORIZED_KEY_PLACEHOLDER → ~/.ssh/id_ed25519.pub
     |
     V
.seed_staging/user-data  +  .seed_staging/meta-data
     |
     | genisoimage (cidata volume)
     |
     V
${VM_NAME}-seed.iso  →  attached as CDROM (bus=sata)
     |
     | VM first boot: cloud-init reads cidata
     |
     V
- hostname set
- vmadmin account created (sudo, SSH key)
- OS-specific packages installed
- timezone configured
```

---

## 7. OS Support

| OS Type   | Variant  | Base Image Source                              | Package Manager |
|-----------|----------|------------------------------------------------|-----------------|
| rocky8    | rocky8   | download.rockylinux.org                        | dnf             |
| debian13  | debian13 | cloud.debian.org/images/cloud/trixie/daily     | apt             |

OS-specific differences are isolated to `templates/user-data.*` and `bin/create_vm.bash`:

| Concern           | Rocky 8.10            | Debian 13                          |
|-------------------|-----------------------|------------------------------------|
| Admin group       | `wheel`               | `sudo`                             |
| OpenSSL headers   | `openssl-devel`       | `libssl-dev`                       |
| Boot firmware     | BIOS                  | UEFI (`--boot uefi`, requires OVMF)|
| Image filename    | `...Base.latest...`   | `...-daily.qcow2`                  |

---

## 8. Network

All VMs use the libvirt `default` network with static IP assignment via
DHCP reservation. MAC addresses and IPs are derived deterministically
from the OS type and node identifier.

**IP Address Ranges:**

| OS Type   | Range                       |
|-----------|-----------------------------|
| Debian 13 | 192.168.122.10 — .99        |
| Rocky 8.10| 192.168.122.100 — .149      |
| Other     | 192.168.122.200 — .254      |

Custom NODE_IDs (not `server`, `nodeN`, or `test`) are mapped to the
200-254 range via a deterministic hash. `NODE_ID=test` bypasses static
assignment and uses DHCP.

**Offset Mapping:**

| NODE_ID | Offset |
|---------|--------|
| server  | 0      |
| node1   | 1      |
| node2   | 2      |
| nodeN   | N      |

```
Host
  └── libvirt default network (virbr0, 192.168.122.0/24, NAT)
        ├── testbed-debian13-server   192.168.122.10
        ├── testbed-debian13-node1    192.168.122.11
        ├── testbed-debian13-node2    192.168.122.12
        ├── testbed-rocky8-server     192.168.122.100
        ├── testbed-rocky8-node1      192.168.122.101
        └── testbed-rocky8-node2      192.168.122.102
```

MAC addresses are generated deterministically from a fixed prefix
(`52:54:00:00`) combined with the OS base and node offset.

---

## 9. Test Environment Matrix

| Role   | Debian 13                              | Rocky 8.10                              |
|--------|----------------------------------------|-----------------------------------------|
| Server | `testbed-debian13-server`  .10         | `testbed-rocky8-server`   .100          |
| Node 1 | `testbed-debian13-node1`   .11         | `testbed-rocky8-node1`    .101          |
| Node 2 | `testbed-debian13-node2`   .12         | `testbed-rocky8-node2`    .102          |

---

## 10. VM Resources

| Resource | Value           |
|----------|-----------------|
| RAM      | 2048 MB         |
| vCPUs    | 2               |
| Disk     | 20 GB (qcow2)   |
| Graphics | none (headless)  |
| Network  | virtio           |

---

## 11. Hand-off

A node is ready for downstream use once it reports `Domain running` /
`SSH ready` / `cloud-init done`. The static IP allocation defined in
section 8 is the contract between this layer and downstream tools.

| Layer | Tool | Source |
|---|---|---|
| OS baseline (this repo) | `cloud-provision` | this repository |
| Software deployment | `ansible-provision` | https://github.com/jeonghanlee/ansible-provision |

`ansible-provision` reads the same IPs from `inventory/testbed.ini`
without dynamic discovery, so any change to the IP scheme requires
coordinated updates in both repositories.
