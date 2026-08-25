# ADR: Proxy Artifact Lifecycle

Date: 2026-08-20
Status: Accepted
Decision IDs: D009-D018

## Context

The cloud-init producer and golden-image bakes must agree on every proxy
artifact that may reach a build disk. Non-interactive package installation,
sudo, SSH, Ansible, pip, and system Git use different environment and
configuration sources. Separate apply and cleanup lists can therefore leave a
usable credential-bearing artifact on a published disk even when each path
passes an isolated check.

## Decision

`bin/proxy_contract.bash` is the single production authority for proxy apply,
use, seal, and value-free clean verification. It accepts a regular
`/etc/os-release` or a safe relative link to a regular target inside the
selected root. Absolute, dangling, escaping, parent-link, duplicate-ID,
invalid-ID, and unsupported-family inputs fail closed. A test root must be an
existing absolute directory, may not be the selected link itself, and may not
resolve to `/`. In test mode, `cloud-init`, `visudo`, `sshd`, and `systemctl`
must be executable regular files at their exact guest paths below that root;
there is no host fallback.

The production inventory is exact:

| Identity | Families | Path | Owner | Mode | Form |
| --- | --- | --- | --- | --- | --- |
| `profile` | Debian, Ubuntu, Rocky | `/etc/profile.d/95cloud-provision-proxy.sh` | `root:root` | `0644` | dedicated |
| `environment` | Debian, Ubuntu, Rocky | `/etc/environment` | `root:root` | preserve safe metadata; `0644` if absent | shared block |
| `apt` | Debian, Ubuntu | `/etc/apt/apt.conf.d/95cloud-provision-proxy` | `root:root` | `0644` | dedicated |
| `dnf` | Rocky | `/etc/dnf/dnf.conf` | `root:root` | preserve safe metadata | shared block in `[main]` |
| `sudo` | Debian, Ubuntu | `/etc/sudoers.d/95cloud-provision-proxy` | `root:root` | `0440` | dedicated |
| `sshd` | Debian, Ubuntu | `/etc/ssh/sshd_config.d/95cloud-provision-proxy.conf` | `root:root` | `0644` | dedicated drop-in |
| `sshd` | Rocky | `/etc/ssh/sshd_config` | `root:root` | preserve safe metadata | shared global block before `Match` |
| `ssh-environment` | Debian, Ubuntu, Rocky | `/home/vmadmin/.ssh/environment` | `vmadmin:vmadmin` | `0600` | dedicated |
| `pip` | Debian, Ubuntu, Rocky | `/etc/pip.conf` | `root:root` | `0644` | dedicated |
| `git` | Debian, Ubuntu, Rocky | `/etc/gitconfig` | `root:root` | preserve safe metadata; `0644` if absent | shared block |

This yields eight Debian rows, eight Ubuntu rows, and seven Rocky rows. The
environment artifacts contain lower- and uppercase HTTP, HTTPS, FTP, and
no-proxy names. Dedicated files have exact content and metadata. Shared files
preserve safe existing metadata and every byte outside one marked block. A
non-empty shared file without a final newline fails before mutation because a
separate marked block cannot be represented without changing existing bytes.

`create_vm.bash` validates the proxy URL as data, substitutes the SSH key, and
then performs a controlled merge into generated user-data. Supported templates
must contain no top-level `write_files` and at most one top-level `runcmd`.
The result contains exactly one of each, preserves existing locale commands,
and places privileged apply first in `runcmd`. The five source templates remain
unchanged.

Cloud-init stages only these transient files:

- `/run/cloud-provision/proxy_contract.bash`, `root:root`, `0700`;
- `/run/cloud-provision/proxy-contract.input`, `root:root`, `0600`;
- `/run/cloud-provision/proxy-contract.lock`, created by apply as `root:root`,
  `0600`.

The input is parsed as data and binds the staged script with SHA-256. Apply
performs a complete conflict preflight, renders all candidates, validates the
sudo candidate, installs the fixed set, validates installed metadata and the
effective sshd configuration, and reloads sshd. Debian and Ubuntu require the
global sshd include for the dedicated drop-in. Rocky rejects a competing active
`PermitUserEnvironment` and places its owned setting before the first active
`Match`.

IOC runner and EtherCAT bakes stream the same shipped contract through
`/bin/bash -p -s -- seal` after manifest validation and sidecar extraction.
Seal preflights the complete applicable set, removes final artifacts in reverse
order, reloads sshd, removes transient state, verifies value-free absence, runs
supported `cloud-init clean` as the terminal guest mutation, and verifies the
selected cloud-init state and logs are absent. Publication begins only after
the exact sealed VM is stopped and its exact source disk is confirmed.

The independent fixture under `tests/fixtures/` is not a production input. Its
ten-field tuples must equal the production inventory. Public local tests run
the shipped producer and IOC bake caller with only outer command, SSH transport,
network, image, and filesystem boundaries replaced. The IOC harness covers
normal Debian 13 and Rocky 8 paths and exactly fifteen one-at-a-time inventory
omissions. Dedicated EtherCAT tests are deferred; production EtherCAT behavior
and generic image workflow tests remain unchanged.

## Scope Boundary

This decision does not change Ansible, restore `-F`, expose proxy values,
inspect existing images, or authorize audit or remediation.

D014 keeps the existing-artifact audit deferred. Reading, quarantining,
replacing, or deleting an existing guest, disk, image, archive, or sidecar
requires a separate accepted plan and explicit authorization.

D013 limits documentation to observed evidence. Local shipped-path checks do
not establish the pending Debian and Rocky Libvirt/KVM producer-consumer gates
or the state of any existing artifact.

## Consequences

- Producer apply and bake cleanup identities cannot change independently.
- A partial, ambiguous, or malformed owned set blocks publication.
- A no-proxy build still performs cloud-init cleanup and clean-state verification.
- Local verification proves only shipped host paths under explicit outer boundaries.
- Real Debian and Rocky IOC producer-consumer gates remain required before M3
  and issue #33 can close.
- EtherCAT test restoration and runtime acceptance remain Backlog work.
- The existing-artifact audit remains separate evidence under separate
  authorization.

### Package install ordering under proxy injection (D018)

Under proxy injection `create_vm` strips the cloud-init `packages:` directive,
so packages install after the proxy apply through Ansible, not through the
cloud-init package module. The reason: the cloud-init package module runs in the
config stage, before the runcmd proxy apply in the final stage, so it has no
proxy yet and cannot fetch. Without proxy injection the cloud-init baseline (the
hand-off subset of P_common defined in `docs/IMAGE_WORKFLOW.md`) installs them at
first boot.

### Base-image locale dependency under proxy injection (D018)

Stripping `packages:` removes the `locales` entry with it, while the runcmd
locale commands (`locale-gen en_US.UTF-8` and its siblings) are kept and still
run at first boot. Those commands therefore depend on the base image already
shipping locale support — the `locales` package on the Debian family, glibc
langpacks on Rocky. A base image lacking it fails locale generation silently at
first boot; a first-boot self-check in the debian-family templates surfaces the
absence instead. That self-check must stay the last `runcmd` entry: cloud-init
flattens `runcmd` into one `set -e`-less script whose exit status is its last
line, so any command appended after the self-check would mask its failure and
let the bake pass.
