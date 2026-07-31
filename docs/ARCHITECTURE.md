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
templates/user-data.${OS_VARIANT}
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

`OS_VARIANT` collapses pre-baked variants onto their base OS template,
so `rocky8-iocrunner` reuses `templates/user-data.rocky8` and
`debian13-iocrunner` reuses `templates/user-data.debian13`.

---

## 7. OS Support

Selector sets are intentionally different:

| Selector set | Values | Entry point | Meaning |
|---|---|---|---|
| `DEFAULT_OS_TYPES` | `rocky8`, `debian13` | `make all`, `make status`, `make stop` | Plain base test VMs. |
| `OS_TYPES` | every row in the OS table below | `make <os>[.<node>]`, `make clean` | Every provisionable VM type. |
| `BAKE_OS_TYPES` | `rocky8`, `debian13` | `make bake`, `make bake.<os>` | Base OS inputs for IOC runner golden images. |
| `ETHERCAT_BAKE_OS_TYPES` | `debian13` | `make bake.ethercat`, `make bake.ethercat.<os>` | Base OS input for the EtherCAT golden image. |

| OS Type | Variant | Base Image Source | Package Manager | Role |
|---|---|---|---|---|
| rocky8 | rocky8 | download.rockylinux.org | dnf | Plain base test VM |
| debian13 | debian13 | cloud.debian.org/images/cloud/trixie/daily | apt | Plain base test VM |
| rocky8-iocrunner | rocky8 | local: `${IMAGE_DIR}/iocrunner-rocky8.qcow2` | dnf | IOC runner runtime VM |
| debian13-iocrunner | debian13 | local: `${IMAGE_DIR}/iocrunner-debian13.qcow2` | apt | IOC runner runtime VM |
| debian13-ethercat | debian13 | local: `${IMAGE_DIR}/ethercat-debian13.qcow2` | apt | EtherCAT runtime VM |
| debian13-rtbase | debian13 | pinned Debian 13 release cloud image | apt | EtherCAT bake source VM |
| epics-env-rocky8 | rocky8 | download.rockylinux.org | dnf | EPICS-env source-build host |
| epics-env-debian13 | debian13 | cloud.debian.org/images/cloud/trixie/daily | apt | EPICS-env source-build host |
| epics-env-rocky10 | rocky10 | download.rockylinux.org | dnf | EPICS-env source-build host |
| epics-env-ubuntu24 | ubuntu24 | cloud-images.ubuntu.com/noble/current | apt | EPICS-env source-build host |
| epics-env-ubuntu26 | ubuntu26 | cloud-images.ubuntu.com/resolute/current | apt | EPICS-env source-build host |

The `*-iocrunner` variants boot from images produced by section 12
and are gated out of `make all` via `DEFAULT_OS_TYPES` until their
golden image is present. They share the base OS variant's cloud-init
template and boot firmware.

The `debian13-ethercat` variant boots from the EtherCAT golden image.
The `debian13-rtbase` selector is a bake input, not the final EtherCAT
runtime host.

The `epics-env-*` variants boot plain cloud images (no golden bake) and
exist to give EPICS-env from-source builds dedicated hosts. They are
excluded from `make all`.

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

| OS Type              | Range                       |
|----------------------|-----------------------------|
| Debian 13            | 192.168.122.10  — .49       |
| EPICS-env Ubuntu 26  | 192.168.122.30  — .32       |
| EPICS-env Ubuntu 24  | 192.168.122.40  — .42       |
| Debian 13 iocrunner  | 192.168.122.50  — .69       |
| Debian 13 ethercat   | 192.168.122.70  — .79       |
| Debian 13 rtbase (ethercat bake) | 192.168.122.80 — .99 |
| Rocky 8.10           | 192.168.122.100 — .149      |
| EPICS-env Rocky 10   | 192.168.122.130 — .132      |
| Rocky 8.10 iocrunner | 192.168.122.150 — .199      |
| Other                | 192.168.122.200 — .254      |

The EPICS-env from-source build hosts reserve dedicated slots:
`epics-env-debian13` at .20-.22, `epics-env-ubuntu26` at .30-.32,
`epics-env-ubuntu24` at .40-.42, `epics-env-rocky8` at .120-.122, and
`epics-env-rocky10` at .130-.132. They never collide with the base VMs,
which only occupy the .10-.12 and .100-.102 server/node slots.

The `*_IP_BASE` constants live in `bin/create_vm.bash` and partition the
subnet so variant builds never collide with their base OS counterparts.

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
        ├── testbed-debian13-server             192.168.122.10
        ├── testbed-debian13-node1              192.168.122.11
        ├── testbed-debian13-node2              192.168.122.12
        ├── testbed-debian13-iocrunner-server   192.168.122.50
        ├── testbed-debian13-iocrunner-node1    192.168.122.51
        ├── testbed-debian13-iocrunner-node2    192.168.122.52
        ├── testbed-rocky8-server               192.168.122.100
        ├── testbed-rocky8-node1                192.168.122.101
        ├── testbed-rocky8-node2                192.168.122.102
        ├── testbed-rocky8-iocrunner-server     192.168.122.150
        ├── testbed-rocky8-iocrunner-node1      192.168.122.151
        └── testbed-rocky8-iocrunner-node2      192.168.122.152
```

MAC addresses are generated deterministically from a fixed prefix
(`52:54:00:00`) combined with the OS base and node offset.

---

## 9. Test Environment Matrix

Default OS types (built by `make all`):

| Role   | Debian 13                              | Rocky 8.10                              |
|--------|----------------------------------------|-----------------------------------------|
| Server | `testbed-debian13-server`  .10         | `testbed-rocky8-server`   .100          |
| Node 1 | `testbed-debian13-node1`   .11         | `testbed-rocky8-node1`    .101          |
| Node 2 | `testbed-debian13-node2`   .12         | `testbed-rocky8-node2`    .102          |

Pre-baked IOC runner variants (require section 12 bake first):

| Role   | Debian 13 iocrunner                              | Rocky 8.10 iocrunner                              |
|--------|--------------------------------------------------|---------------------------------------------------|
| Server | `testbed-debian13-iocrunner-server`  .50         | `testbed-rocky8-iocrunner-server`   .150          |
| Node 1 | `testbed-debian13-iocrunner-node1`   .51         | `testbed-rocky8-iocrunner-node1`    .151          |
| Node 2 | `testbed-debian13-iocrunner-node2`   .52         | `testbed-rocky8-iocrunner-node2`    .152          |

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

The canonical seam contract — responsibility boundary, cross-repo naming
contract, and consumer register — is `ansible-provision/docs/SEAM.md`.

`ansible-provision` reads the same IPs from `inventory/testbed.ini`
without dynamic discovery, so any change to the IP scheme requires
coordinated updates in both repositories.

**Pre-baked variants.** `rocky8-iocrunner` and `debian13-iocrunner`
boot from a golden image that already contains the
`ansible-provision` `site.yml` plus `04_nfs_sim.yml` outputs (see
section 12). The runtime ansible step is therefore skipped at first
boot, trading a periodic re-bake against fast, reproducible
software-ready VMs for `epics-ioc-runner` integration tests.

---

## 12. IOC Runner Bake Pipeline

The `epics-ioc-runner` project consumes this repository as its test
substrate. To shorten the feedback loop, `bin/bake_iocrunner_image.bash`
produces a flat golden qcow2 per OS that already contains the full
software stack, so iocrunner integration tests boot directly into a
ready-to-use environment.

```
[ bin/bake_iocrunner_image.bash -o <os> ]
     |
     | 1. reject any existing build domain or source disk
     |
     | 2. create_vm.bash -F -o <os> -n server
     |
     | 3. resolve the source disk backing image and write the manifest header
     |
     | 4. ansible-playbook site.yml
     |
     | 5. ansible-playbook playbooks/04_nfs_sim.yml
     |
     | 6. ansible-playbook playbooks/07_test_users.yml
     |
     | 7. append pip provenance and strip proxy configuration
     |
     | 8. validate /etc/iocrunner-bake.manifest inside the VM
     |
     | 9. shutdown, flatten, and rename image and sidecar from .tmp siblings
     |
     | 10. clean build VM  (or keep with -k)
     |
     V
${IMAGE_DIR}/iocrunner-<os>.qcow2  →  base image of <os>-iocrunner variant
```

| Step | Tool | Purpose |
|------|------|---------|
| 1-2 | `create_vm.bash -F` | Require a fresh build domain and source disk, then boot the build VM |
| 3 | `qemu-img`, `jq`, `sha256sum` | Record the observed backing-image filename and digest |
| 4-6 | `ansible-playbook` | Apply the software stack, NFS simulator, and test users |
| 7 | remote privileged Bash | Append `pip3 freeze` and remove site proxy configuration |
| 8 | `validate_iocrunner_bake.bash` | Validate the manifest before any sidecar extraction or image publication |
| 9 | `virsh`, `qemu-img`, `mv` | Quiesce, flatten, and publish only after validation and conversion succeed |
| 10 | `create_vm.bash -c` | Tear down the build VM unless `-k` keeps it for explicit follow-up checks |

**Inputs.**

| Variable                  | Default                  | Override                          |
|---------------------------|--------------------------|-----------------------------------|
| `IMAGE_DIR`               | `~/libvirt/images`       | `-d` flag                         |
| `ANSIBLE_PROVISION_DIR`   | `${SC_TOP}/../ansible-provision` | `-a` flag or env var      |
| `OS_TYPE`                 | (required)               | `-o rocky8` / `-o debian13`       |

The bake script never mutates the upstream cloud base image. It also
refuses to start when a defined domain or qcow2 file in the selected
`IMAGE_DIR` resolves through the target output image as a backing file.
The flattened output is independent and self-contained. Re-running the
bake replaces `${IMAGE_DIR}/iocrunner-<os>.qcow2` and its sidecar only
after non-empty `.tmp` siblings have passed validation and conversion.

**Provenance manifest.** Each IOC runner bake writes
`/etc/iocrunner-bake.manifest` inside the build VM and copies it to
`${IMAGE_DIR}/iocrunner-<os>.qcow2.manifest` after validation. The
manifest contains exactly one header, schema, bake date, OS selector,
repository identity for `cloud-provision` and `ansible-provision`, EPICS
selectors, observed base image identity, five application records, and
one or more `pip3` records. Application records use:

```
app_name schema=1 repo=<url> commit=<40-hex> state=<state> tag=<tag> recorded_at=<UTC>
```

Allowed application states are `clean-tagged`, `clean-untagged`, and
`dirty`. Final release acceptance requires clean 40-hex repository
identities; dirty suffixes are permitted only for preliminary bakes.

**Validation boundary.** `bin/validate_iocrunner_bake.bash` is the single
validator for IOC runner bake outputs. It rejects malformed, duplicate,
missing, unknown, `(live)`, commit-mismatch, dirty-state-mismatch, and
installed-runner-mismatch records. Direct manifest mutations are parser
coverage only; promotion evidence comes from the public bake script
calling the real validator before publication.

**Runtime comparison matrix.**

| Manifest record | Runtime comparison | Acceptance rule |
|---|---|---|
| `base_image` | Source disk `full-backing-filename` and backing-file SHA-256 | Filename and digest are observed, not inferred from OS selector |
| `app_con` | Build-time source record | Exactly one valid record is required |
| `app_procserv` | Build-time source record | Exactly one valid record is required |
| `app_conserver` | Build-time source record | Exactly one valid record is required |
| `app_epics` | Retained `/opt/epics` Git checkout | Repository URL, commit, dirty state, and tag match the record |
| `app_ioc_runner` | Retained runner checkout and installed `ioc-runner -V` | Repository identity matches the checkout and installed short hash |
| `pip3` | In-image `pip3 freeze` output | One or more non-empty package lines are required |

The build-time records cover tools whose source trees are removed after
installation. Retained-source records are checked against the live checkout
that remains in the image.

**Consumption.** The flat image is referenced by the
`<os>-iocrunner` branch of `bin/create_vm.bash`, which sets
`BASE_URL=""` and emits a clear hint when the file is absent:

```
Error: Base image .../iocrunner-rocky8.qcow2 not found and no download URL.
Hint: run bin/bake_iocrunner_image.bash to build it first.
```

`make all` and `make status` / `make stop` iterate over
`DEFAULT_OS_TYPES` (which excludes the iocrunner variants), so a
missing golden image never breaks the default workflow. `make clean`
iterates over the full `OS_TYPES` list and is safe on missing
domains.

## 13. VM Readiness Contract

`bin/create_vm.bash` gates every readiness decision on one SSH contract,
defined once as `SSH_USER`, `SSH_PROBE_OPTIONS`, and `ssh_probe`. The status
path (`-s`), the provisioning wait, and the `cloud-init` poll all go through
it, so the four paths cannot drift apart.

**Readiness means a non-interactive, key-only login as `vmadmin` that reaches
remote command execution.** It is not transport availability: a host whose
port 22 answers but whose key is not authorized is not ready. It is not a
broader operator-readiness condition either; nothing beyond running a remote
command is asserted.

Two option choices carry that meaning.

| Option | What it decides |
| --- | --- |
| `BatchMode=yes` | Removes password and keyboard-interactive authentication, so a probe can pass only with a usable key and never blocks on a prompt. |
| `StrictHostKeyChecking=no` | Accepts a host key that is not yet known, so a freshly provisioned VM needs no operator step. It does **not** accept a key that has changed. |

That second limit produces a third outcome the contract names explicitly. VMs
reuse deterministic addresses, so recreating one leaves the previous host key
stored against the same address, and every probe then fails. This is not "not
ready yet" and waiting will not resolve it, so `ssh_probe` returns a distinct
code for it, `wait_for_ssh` stops instead of spending its budget, and the
operator is given the `ssh-keygen -R` repair for that address.

Refreshing `known_hosts` automatically is deliberately not done here. The bake
scripts do it at their own step 2 because they are talking to a VM they created
seconds earlier; the provisioner also reports on long-lived VMs the operator did
not just create, where silently accepting a changed identity would hide a fact
worth seeing.

Retry counts and intervals are not part of this contract. They are recorded and
reviewed separately.

## 14. Libvirt Lifecycle Policy

Four public actions read or change domain state. They are stated as one table
because the failure this policy exists to prevent is the four drifting apart
without anyone noticing; a divergence shows up here as a row that no longer
matches.

| Domain state | `-s` status | provision (default) | `-S` stop | `-c` cleanup |
| --- | --- | --- | --- | --- |
| `running` | reports IP, SSH, `cloud-init` | prints the summary and exits 0, idempotent | ACPI shutdown, polls until off | destroys, undefines, removes disk and seed |
| `shut off` | reports the state, hints `virsh start`, exits 1 | starts and waits for readiness | reports already off, exits 0 | same as above; destroy reports not running |
| `not defined` | reports the state, hints provision, exits 1 | provisions from scratch | reports not defined, exits 0 | same as above; both virsh steps report absent |
| unexpected (`paused`, `crashed`, `pmsuspended`) | reports the state, hints cleanup, exits 1 | reports the state, hints cleanup, exits 1 | reports the state, hints cleanup, exits 1 | proceeds and returns 0 |
| `unavailable` (libvirt did not answer) | reports it and says the domain was not checked, exits 1 | refuses before creating anything, exits 1 | reports it and exits 1 | proceeds; each step reports its own failure |

Three rules explain the table.

**An unexpected state is not resolved by waiting.** Every action that reads or
starts refuses and points at cleanup, because cleanup is the way back. Cleanup
itself proceeds for the same reason.

**`unavailable` is not `not defined`.** `virsh domstate` fails identically when
the domain is absent and when libvirt cannot be reached, so `get_domain_state`
asks the connection separately. Reporting an outage as absence would tell the
operator to provision a VM that may already exist, and would let a stop exit 0
for a question nobody answered. The distinction stops at reporting: nothing
retries or reconnects, because that would be a wait budget, which is tracked
separately.

**Cleanup never checks state, deliberately.** Its contract is idempotent
removal, and the end state is the same from every starting state. A pre-check
would race — the domain can change between the check and the command — and would
buy nothing. Every step reports its own outcome as information and cleanup
always returns 0, so teardown scripts can run it unconditionally. Do not add
state checks here for symmetry with the other three actions.
