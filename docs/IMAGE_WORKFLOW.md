# Image Workflow

How this repository makes and uses images: terms, the chain, and the rules every image obeys. Settled in the 2026-08-01
design discussion. The physics reading is a shared shorthand, not normative. The operator definition after it is
normative.

## Terms

| Label | Name | What it is |
| --- | --- | --- |
| A | OS base | The image fetched from upstream. In code, a `BASE_IMAGE_NAME` whose `BASE_URL` is non-empty. |
| B | OS golden | An OS image carrying the settings we need, usable as it stands. |
| C | VM disk | A copy of B (B') after the purpose work; the VM's own disk. |
| ′ (prime) | copy | A' / B' mark a same-kind copy under preparation. Prime, not star or dagger — those carry other meanings (dual, adjoint). |

## Chain

```
A (OS base) ──copy──▶ A' ──prepare──▶ B (OS golden)
```

A' is the copy. The preparation runs on A' only; A is never written to.

Settled consequence: A and B are independent, so re-fetching, moving, or removing A cannot break B, and rebuilding B
cannot disturb A.

## B to VM (settled 2026-08-01)

Same shape as A to B: copy first, prepare on the copy.

```
B (OS golden) ──copy──▶ B' ──prepare (purpose work)──▶ VM disk
```

B' is the copy and is the VM's own disk. The purpose work — what iocrunner / ethercat provisioning does today — runs on
B' only. B is read, never written, never held by a running VM.

## What this resolves

B is held by no VM, which removes the root under three recorded defects:

- libvirt claimed the backing file's ownership when a consumer started; with no backing chain there is no
  file to claim
- consumers held the golden so it could not be rebaked; the in-use guard (`protect_output_consumers`) and
  its first-transition refusal become unnecessary on this stretch
- rebaking B cannot disturb any VM already made from it
- the bake's flatten step (`qemu-img convert`) disappears: the disk is independent from birth

Cost, stated once: a VM disk grows from the current overlay (~106 M observed) to the full size of B (several GB), and
the purpose work runs per VM instead of once per bake. Owner direction: disk and time costs are reviewed later, not in
this design round.

## Identity by pair (settled 2026-08-01)

Every produced golden image and run-specific build VM disk carries its identity
in two places made together:

- the file name holds a unique timestamp / hash;
- a creation-record file sits beside the image with the same values.

Verification is the pair agreeing. If either half is missing, or the values disagree, the image is ignored. Neither half
alone can lie, so forgetting to delete one is safe — a stale record points at nothing that matches it.

The pair rule applies to images we make (B and run-specific build VM disks).
Ordinary runtime VM disks are the deliberate exception: they keep the stable
`${VM_PREFIX}-${OS_TYPE}-${NODE_ID}.qcow2` name required by lifecycle selectors,
while their creation record carries the generated run ID for provenance. A
(fetched upstream) is out of scope: its identity is its source and checksum.

This covers the two problems left open above:

- "did this run make this VM" — answered by the creation record beside the VM disk, which names its maker; a domain
  merely existing never decides it (the root of the in-use misreport: an unlabeled, merely-existing domain was read
  as a live consumer of the image, blocking work on an image nothing actually held)
- where provenance lives with no purpose golden — the record file beside B carries what the manifest/sidecar carries
  today

## Naming is defined once (settled 2026-08-01)

The naming rule has two deliberate modes: ordinary runtime VMs keep their
stable `${VM_PREFIX}-${OS_TYPE}-${NODE_ID}` name, while golden images and bake
build VMs carry the run timestamp / hash. The rule is defined in ONE place from
the start, and every consumer — provisioning and bake alike — calls that one
place.

This absorbs the duplicated-naming defect: today `create_vm.bash` and the bake scripts each compute `VM_NAME` and disk paths on their own,
two copies that must agree. The approved resolver plan (`plan20260723_234700`) wanted to extract that computation; the
new naming scheme starts extracted, so that defect is resolved by the redesign rather than as separate work.

## Build VMs are always fresh by construction (settled 2026-08-01)

The working VM that prepares an image gets its name from the same one-place naming rule, so it too carries the run's
timestamp / hash. Names never collide across runs, so a leftover VM from an earlier run can never be reused by accident
— every run creates its own fresh VM.

Fresh-input enforcement (`-F` / `require_fresh_input`) becomes unnecessary: there is nothing to force when reuse is
structurally impossible. Both bake entry points use the shared build-VM creation path delivered by `4fc1341`; the naming rule
removes reuse as a correctness risk once the workflow lands. What remains after that is housekeeping - when to remove
leftover VMs - not correctness.

## A is kept (settled 2026-08-01)

A stays after B exists. Deleting A once B was built was raised by the assistant and rejected by the owner. A is read-
only ground; nothing we make ever writes to it.

## Golden naming carries identity and a newest-wins default

A published golden species is named on two layers, not one. The identity layer is the run timestamp and hash carried
in the file name and the paired creation record, exactly as "Identity by pair" defines — this is what keeps every image
unique, verifiable as a pair, and fresh by construction, and it is unchanged. The selection layer sits on top of it: a
consumer that names no run identifier gets the newest published image of that species by default. This is not a separate
pointer artifact; the run timestamp leads the run id, so sorting the unique names of a `<kind>-<platform>` family in
descending order puts the newest first, and `image_workflow_select_latest_image` returns the newest one whose pair
validates. The default never replaces the identity; it only picks among the unique images, so it can cost a convenience,
never correctness.

## Delivered workflow

`bin/image_workflow.bash` owns image and VM naming, VM disk paths, independent
qcow2 copying, creation-record writing, pair validation, and no-backing
inspection. The ioc-runner and EtherCAT bake entry points use the same naming
and copy functions. Each golden image has the form
`<kind>-<platform>-<run-id>.qcow2` and a matching `.creation-record`; ioc-runner
images also carry the validated `.manifest` sidecar. Bake build VM disks use
the same run-specific naming and independent copy path and carry their own
creation record. Ordinary runtime VM disks retain stable names and remain
independent copies. `create_vm.bash` sets every copied VM disk's virtual
capacity to 20 GiB before first boot; a golden image published from a build VM
retains that capacity.

`create_vm.bash` selects the newest valid pair for each baked runtime selector.
The upstream base image remains a read-only input, and no produced image is
used as another image's backing file.

## Physics reading (2026-08-01, shared shorthand)

A second language for the same structure, agreed between the owner and the assistant as a private shorthand — the design
stands on the plain terms above; this section is how the two of us recall it.

- A is the vacuum: the ground everything is defined on and nothing acts upon. That A is kept and never written to is not
  a policy but what a vacuum is.
- B is a particle created from that vacuum. The preparation is the creation operator; the working VM that performs it is
  a virtual particle — it exists only while mediating A' → B and appears in no final state. A leftover build VM is an
  unclosed internal line.
- C's are many particles of the same species, and identical particles are indistinguishable — "which one is mine" has no
  answer for unlabeled VMs, which was the root of the in-use misreport loop. The pair rule breaks
  exchange symmetry with labels: timestamp / hash plus creation record make the particles distinguishable.
- Each C evolves its own history from birth (an excited state); the record captures only the birth conditions, never the
  later state. Annihilation (clean) returns the disk and its identity record to vacuum together.
- The purpose work is a set of operators applied to the particle, classified as packages (what was installed) and
  configuration (what was changed) — today's manifest already records that operator list.
- The old backing chain was entanglement: a local operation on a consumer (starting it) changed the base's state
  (the ownership and held-golden defects). Copying separates the system into a product state — local operations stay local. Full copies
  are allowed because images are classical information; no-cloning does not apply.

In equations:

```
|0⟩       = A                        vacuum, never acted on
|B⟩       = P |0⟩                    preparation as creation operator, applied to A', mediated by a virtual (build) VM
P         = Π_k O_k                  O_k ∈ {pkg, cfg}; the operator product the record keeps
|C_i⟩     = W_i |B⟩                  purpose work W on the copy B'
i         = (t_i, h_i)               the label that makes identical particles distinguishable
valid(X)  ⟺ name(X) ≡ record(X)      the pair rule; either half alone is ignored
a |C_i⟩   = |0⟩                      clean removes the disk and its identity record

old       |golden, C_1, C_2, …⟩      entangled: one file shared, not separable
new       |B⟩ ⊗ |C_1⟩ ⊗ |C_2⟩ ⊗ …    product state: local stays local
```

## Operator definition

Normative. Defines the operators applied to a vacuum, their order, and the species they produce. The operators are
ansible-provision roles; this repository creates, copies, and destroys the states they act on. The terms vacuum type,
bare, rtbase, and species are defined here, not in Terms.

### Vacua

The OS type is the vacuum type. An operator is the same operator on every vacuum; only package names differ.

| Vacuum | Family |
| --- | --- |
| debian13 | debian |
| rocky8 | rocky |
| rocky10 | rocky |
| ubuntu24 | debian |
| ubuntu26 | debian |

### Operators

The preparation operator P of the physics reading is the product of the operators below.

| Operator | Role | Order | Content |
| --- | --- | --- | --- |
| P_common | `common` | First on every vacuum | Must-have: sudo, chrony, git, wget, unzip, gcc, g++, make, autoconf, automake, libtool, ssl-dev, net-tools. Core utilities: vim, tmux, lsof, tree, sysstat, logrotate, acl, socat. Both halves are P_common and always installed. Debian family only: the `locales` package, `en_US.UTF-8` enabled in `/etc/locale.gen`, `locale-gen`, `update-locale LANG=en_US.UTF-8`. EPICS development libraries are not P_common. Configuration content: chrony configured and running, the sudoers includedir kept the final active directive, and on rocky the EPEL and PowerTools (CRB on rocky10) repositories enabled and `/usr/local` prepended to the sudo `secure_path`. The cloud-init template baseline (the `packages:` block and the debian-family locale commands) is the hand-off subset of P_common applied at first boot; under proxy injection it defers to the P_common role. |
| P_rt | `rt` | After P_common; optional | PREEMPT_RT kernel and headers, running-kernel headers, dkms, build toolchain. Stock kernel stays boot default. The resulting rtbase species is published as its own golden image. |
| P_provenance | `provenance` | Before P_epics, P_procserv, P_conserver, P_con, P_iocrunner | `/usr/local/sbin/record-iocrunner-source`, the tool application operators call to record their source into the bake manifest. |
| P_epics | `epics` | After P_provenance | Binary EPICS-env distribution and its activation script under `/etc/profile.d`; on rocky, firewalld enabled with the EPICS CA and PVA ports open. Alternative to P_epics-build; never both on one vacuum. |
| P_epics-build | `epics_build` | After P_common | Python 3 and pip, the EPICS development packages, then EPICS-env built and installed from source. Alternative to P_epics. |
| P_epics-support | `epics_support` | After P_epics-build | AreaDetector modules built from source on the installed EPICS-env. |
| P_procserv | `procserv` | After P_common | procServ built and installed from procServ-env. |
| P_conserver | `conserver` | After P_common | conserver built and installed from conserver-env with OpenSSL. |
| P_con | `con` | After P_common | con console client built and installed. |
| P_nfs-sim | `nfs_sim` | After P_common | A directory exported over NFS from the same host, mounted back under `/home/nfs`, and linked into the user home. |
| P_iocrunner | `iocrunner` | After P_con, P_procserv, and one of P_epics or P_epics-build | epics-ioc-runner cloned at the pinned ref and its runner binary installed. |
| P_testusers | `testusers` | After P_iocrunner | Operator, observer, and local-mode test accounts; operators joined to the ioc group. |
| P_ethercat | `ethercat` | After P_rt | ethercat-env cloned and its root-affecting target graph run; RT kernel selected as boot default and booted. P_ethercat can apply on a non-RT bare state, but the `ethercat` species is defined on rtbase because a real EtherCAT deployment runs the RT kernel. |

Package names that differ by family:

| Name in P_common | debian family | rocky |
| --- | --- | --- |
| ssl-dev | libssl-dev | openssl-devel |
| g++ | g++ | gcc-c++ |

Commutation:

```
[P_rt, P_common] ≠ 0                     P_rt needs P_common's toolchain
[P_procserv, P_conserver] = [P_procserv, P_con] = [P_con, P_nfs-sim] = 0
```

### Species

Each bare state is a distinct species, one per vacuum: bare_debian13 is not bare_rocky8 under another name. Every
other species is one species on every vacuum it is defined for, built on that vacuum's bare state.

| Species | Product | Vacua |
| --- | --- | --- |
| bare_debian13 | P_common \|0_debian13⟩ | debian13 |
| bare_rocky8 | P_common \|0_rocky8⟩ | rocky8 |
| bare_rocky10 | P_common \|0_rocky10⟩ | rocky10 |
| bare_ubuntu24 | P_common \|0_ubuntu24⟩ | ubuntu24 |
| bare_ubuntu26 | P_common \|0_ubuntu26⟩ | ubuntu26 |
| iocrunner | P_testusers P_iocrunner (P_con P_conserver P_procserv) (P_epics or P_epics-build) P_provenance \|bare⟩ | all |
| iocrunner-nfs | P_nfs-sim \|iocrunner⟩ | all |
| epics-dev | P_epics-support P_epics-build \|bare⟩ | all |
| nfs-sim | P_nfs-sim \|bare⟩ | all |
| rtbase | P_rt \|bare⟩ | all |
| ethercat | P_ethercat \|rtbase⟩ | all |

Legal products that are not named species. Each follows from the commutation rules and stays a recorded product
rather than a named species; a real use for one is what promotes it, and none is needed today:

| Product | Meaning |
| --- | --- |
| (P_con P_conserver P_procserv) \|bare⟩ | console host without EPICS; any subset and order. The three are base software of the iocrunner species, not a standalone host. |
| P_iocrunner (P_con P_conserver P_procserv) P_epics P_provenance \|rtbase⟩ | IOC host on the RT kernel without the EtherCAT stack; reachable from rtbase and the iocrunner operators. |
| P_ethercat P_epics P_provenance \|rtbase⟩ | EtherCAT host with EPICS. A real EtherCAT host runs EPICS IOCs, so this is the anticipated end state; the `ethercat` species stays EtherCAT-only until end-to-end work reaches the EPICS layer. |
