# Operator Model

Normative. Single source of truth for the operators applied to a vacuum, their
order, the species they produce, and the realization modes those species are
built in. The operators are ansible-provision roles; this repository creates,
copies, and destroys the states they act on. The terms vacuum type, bare,
rtbase, species, and realization mode are defined here, not in
the `IMAGE_WORKFLOW.md` Terms section.

The physics-reading shorthand (vacuum, creation operator, particle species)
stays in `IMAGE_WORKFLOW.md` and is not normative. This document is.

## Notation

- `|x⟩` denotes a state — the raw vacuum `|0⟩`, a bare OS `|bare⟩`, or a species.
- An operator product is read right to left: the rightmost operator acts first
  on the vacuum. `P_b P_a |0⟩` applies `P_a`, then `P_b`.
- `|bare⟩` is the bare state of the vacuum in context (`|0⟩` with P_common
  applied); `|0⟩` is the raw vacuum.
- The full shorthand (creation operator, particle species, annihilation) is the
  physics reading in `IMAGE_WORKFLOW.md`; only what is needed to read the tables
  below is restated here.

## Status of this pass

- Adds the realization-mode axis (Golden, Live, Instant) over the existing
  operators and species.
- Names the EPICS-env-distribution as a produced artifact, with its build
  environment (`epics-dev`), its two build mechanisms (local make, ansible), and
  its consumers (`P_epics`).
- Existing operator and species definitions are carried unchanged. Rewording
  mechanism-specific wording (for example, wording that assumes systemd) into
  mode-neutral contracts is deferred to a later pass.
- Internal site modules (`P_site`) are out of scope; they are managed in
  ansible-provision and alsu-site-modules.
- The `P_proxy` precondition and the `iocserver` species are deferred to a
  separate pass that lands together with their ansible-provision implementation.

## Vacua

The OS type is the vacuum type. An operator is the same operator on every
vacuum; only package names differ.

| Vacuum | Family |
| --- | --- |
| debian13 | debian |
| rocky8 | rocky |
| rocky10 | rocky |
| ubuntu24 | debian |
| ubuntu26 | debian |

## Operators

The preparation operator P of the physics reading is the product of the
operators below. These are the members of a species product — the persistent
software and configuration a species is made of.

| Operator | Role | Order | Content |
| --- | --- | --- | --- |
| P_common | `common` | First on every vacuum | Packages: the canonical P_common set is defined in `configure/pcommon-packages` - a must-have group and a core-utilities group, both always installed, plus the debian-family-only `locales` package; names that differ by family (`ssl-dev`, `g++`) take the per-family spellings recorded there. On the debian family the locale is also enabled at first boot: `en_US.UTF-8` in `/etc/locale.gen`, `locale-gen`, `update-locale LANG=en_US.UTF-8`. EPICS development libraries are not P_common. Configuration content: chrony configured and running, the sudoers includedir kept the final active directive, and on rocky the EPEL and PowerTools (CRB on rocky10) repositories enabled and `/usr/local` prepended to the sudo `secure_path`. The cloud-init template baseline (the `packages:` block and the debian-family locale commands) is the hand-off subset of P_common applied at first boot; under proxy injection it defers to the P_common role. |
| P_rt | `rt` | After P_common; optional | PREEMPT_RT kernel and headers, running-kernel headers, dkms, build toolchain. Stock kernel stays boot default. The resulting rtbase species is published as its own golden image. |
| P_provenance | `provenance` | Before P_epics, P_procserv, P_conserver, P_con, P_iocrunner | `/usr/local/sbin/record-iocrunner-source`, the tool application operators call to record their source into the bake manifest. |
| P_python | `python` | After P_common; before P_epics and P_epics-build | Python 3 and pip runtime. Both EPICS acquisition paths need it, so it is a shared prerequisite rather than part of either. |
| P_epics | `epics` | After P_provenance and P_python | Binary EPICS-env distribution and its activation script under `/etc/profile.d`; on rocky, firewalld enabled with the EPICS CA and PVA ports open. Requires P_python. Alternative to P_epics-build; never both on one vacuum. |
| P_epics-build | `epics_build` | After P_common and P_python | The EPICS development packages, then EPICS-env built and installed from source. Requires P_python. Alternative to P_epics. |
| P_epics-support | `epics_support` | After P_epics-build | AreaDetector modules built from source on the installed EPICS-env. |
| P_procserv | `procserv` | After P_common | procServ built and installed from procServ-env. |
| P_conserver | `conserver` | After P_common | conserver built and installed from conserver-env with OpenSSL. |
| P_con | `con` | After P_common | con console client built and installed. |
| P_nfs-sim | `nfs_sim` | After P_common | A directory exported over NFS from the same host, mounted back under `/home/nfs`, and linked into the user home. |
| P_iocrunner | `iocrunner` | After P_con, P_procserv, and one of P_epics or P_epics-build | epics-ioc-runner cloned at the pinned ref and its runner binary installed. |
| P_testusers | `testusers` | After P_iocrunner | Operator, observer, and local-mode test accounts; operators joined to the ioc group. |
| P_ethercat | `ethercat` | After P_rt | ethercat-env cloned and its root-affecting target graph run; RT kernel selected as boot default and booted. P_ethercat can apply on a non-RT bare state, but the `ethercat` species is defined on rtbase because a real EtherCAT deployment runs the RT kernel. |

Package names that differ by family (`ssl-dev`, `g++`) are recorded with their debian and rocky spellings in `configure/pcommon-packages`.

Commutation:

```
[P_rt, P_common] ≠ 0                     P_rt needs P_common's toolchain
[P_procserv, P_conserver] = [P_procserv, P_con] = [P_con, P_nfs-sim] = 0
```

## Species

Each bare state is a distinct species, one per vacuum: bare_debian13 is not
bare_rocky8 under another name. Every other species is one species on every
vacuum it is defined for, built on that vacuum's bare state.

| Species | Product | Vacua |
| --- | --- | --- |
| bare_debian13 | P_common \|0_debian13⟩ | debian13 |
| bare_rocky8 | P_common \|0_rocky8⟩ | rocky8 |
| bare_rocky10 | P_common \|0_rocky10⟩ | rocky10 |
| bare_ubuntu24 | P_common \|0_ubuntu24⟩ | ubuntu24 |
| bare_ubuntu26 | P_common \|0_ubuntu26⟩ | ubuntu26 |
| iocrunner | P_testusers P_iocrunner (P_con P_conserver P_procserv) (P_epics or P_epics-build) P_python P_provenance \|bare⟩ | all |
| iocrunner-nfs | P_nfs-sim \|iocrunner⟩ | all |
| epics-dev | P_epics-support P_epics-build P_python \|bare⟩ | all |
| nfs-sim | P_nfs-sim \|bare⟩ | all |
| rtbase | P_rt \|bare⟩ | all |
| ethercat | P_ethercat \|rtbase⟩ | all |

Legal products that are not named species. Each follows from the commutation
rules and stays a recorded product rather than a named species; a real use for
one is what promotes it, and none is needed today:

| Product | Meaning |
| --- | --- |
| (P_con P_conserver P_procserv) \|bare⟩ | console host without EPICS; any subset and order. The three are base software of the iocrunner species, not a standalone host. |
| P_iocrunner (P_con P_conserver P_procserv) P_epics P_python P_provenance \|rtbase⟩ | IOC host on the RT kernel without the EtherCAT stack; reachable from rtbase and the iocrunner operators. |
| P_ethercat P_epics P_python P_provenance \|rtbase⟩ | EtherCAT host with EPICS. A real EtherCAT host runs EPICS IOCs, so this is the anticipated end state; the `ethercat` species stays EtherCAT-only until end-to-end work reaches the EPICS layer. |

## Realization modes

A species defines what state is reached. A realization mode defines how that
state is produced and shipped. The two are orthogonal: one species definition is
realized by any mode. The operator's contract — what state it establishes — is
mode-invariant; only its mechanism differs by mode.

| Mode | What it produces | Mechanism |
| --- | --- | --- |
| Golden | A published cloud image (KVM/libvirt qcow2), consumed by many ephemeral copies | cloud-init bake on a throwaway build VM; systemd units |
| Live | A running server, configured in place; no image is published | ansible roles run against the live host; systemd units |
| Instant | A container image (Docker), published to a registry | Dockerfile layers; no systemd init; entrypoint instead of init |

The five vacua are the five flavors. Running one species across all five vacua,
in a given mode, is the consistency check the environment must pass: the same
species must reach an equivalent state on every flavor.

Current realizations:

- Golden: the golden qcow2 images for all five vacua.
- Live: production IOC servers.
- Instant: `jeonghanlee/Dockerfiles` builds debian13, rocky8, and rocky10 images
  today. They carry the distribution (P_epics clone) with procServ and con; the
  systemd-free container work continues in epics-ioc-runner.

## Produced artifacts

A realization consumes artifacts as well as reaching a state. The binary EPICS
distribution is the artifact an operator consumes directly, and it is produced
by a build environment, not by a realization mode. Naming it closes the gap
between what `P_epics` clones and where that comes from.

**EPICS-env-distribution** — the built EPICS-env tree, published to a repository
(the public gz distribution and the internal distribution). It is the payload
`P_epics` clones. `P_epics-build` is the alternative that rebuilds the same tree
from source in place instead of cloning it.

Producer: the `epics-dev` species is the build environment. `P_epics-build`
makes it build-capable — it installs the EPICS development packages and builds
EPICS-env from source; `P_epics-support` adds the AreaDetector modules. Building
`epics-dev` from source and publishing its tree is what produces the
distribution.

Two mechanisms drive that build, one contract:

- Local make — the EPICS-env Makefiles directly (`make build`, `make build.gz`).
  EPICS-env is managed through Makefiles, so this is the build implementation.
- ansible — the `epics_dev` species playbook, which invokes the same make
  targets. ansible orchestrates; make builds.

Both yield the same distribution. The container (Instant) realization is a third
consumer: its Dockerfile clones the published distribution rather than building
it.

Consistency: building `epics-dev` across all five vacua tests that the build
environment is equivalent on every flavor — the same species reaching an
equivalent state.

What a given run produces and where the result is recorded — a shipping
distribution image (Ship), a pass/fail verdict on a release candidate (Release
Verification), or a portability note for a non-shipping combination (Portability
coverage) — is classified by the `epics-env-pipeline` skill's Run kinds, not
redefined here.

## Cross-repository map

The model is one definition realized in three places. Keeping the definition
single is what stops the three realizations from drifting.

| Concern | Repository |
| --- | --- |
| Definition (this document, `IMAGE_WORKFLOW.md`, `create_vm.bash`, `generate_ansible_inventory.bash`) | cloud-provision |
| Operator implementation (species playbooks `playbooks/species/*.yml`, roles, `inventory/lab.ini`) | ansible-provision |
| Container realization (per-flavor Dockerfiles) | Dockerfiles (jeonghanlee) |

The container Dockerfiles today re-encode operator content by hand — their
comments state that the package baseline follows an ansible-provision group_vars
file and that the procServ and con recipes mirror the ansible app roles. That
hand-mirroring is the drift this single definition is meant to remove: each mode
should realize the one operator contract in its own mechanism, not re-derive the
contract.
