# ADR: Proxy Artifact Lifecycle

Date: 2026-08-20
Status: Accepted
Decision IDs: D009-D018, D022

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
resolve to `/`. In cloud test mode, required `cloud-init`, `visudo`, `sshd`, and
`systemctl` commands must each be, at their exact guest paths below that root, an executable regular
file or a symbolic link that resolves within that root to one; a link that
leaves the root fails and there is no host fallback.

The cloud production inventory is exact:

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
| `maven` | Debian, Ubuntu, Rocky | `/etc/maven-proxy-settings.xml` | `root:root` | `0644` | dedicated |

This yields nine Debian rows, nine Ubuntu rows, and eight Rocky rows. The
environment artifacts contain lower- and uppercase HTTP, HTTPS, FTP, and
no-proxy names. Dedicated files have exact content and metadata. Shared files
preserve safe existing metadata and every byte outside one marked block. A
non-empty shared file without a final newline fails before mutation because a
separate marked block cannot be represented without changing existing bytes.

Each artifact also carries a format. Every identity but `maven` is
`hash-comment`, wrapping its content in the marked block; `maven` is `xml`,
because an XML document cannot carry a `#` marker line. The whole `maven` file
is the contract's, so its lifecycle is the dedicated one already defined: apply
writes it, seal removes it, and the clean check requires its absence. Maven
reads it only when a build selects it with `-gs`; it is not a Maven default
location.

`create_vm.bash` validates the proxy URL as data, substitutes the SSH key, and
then performs a controlled merge into generated user-data. Supported templates
may contain at most one top-level `write_files` and at most one top-level
`runcmd`, and must contain exactly one top-level `final_message`. The result
contains exactly one `write_files` and one `runcmd`, preserves existing
template-owned file entries and locale commands, and places privileged apply
first in `runcmd`. Proxy merging modifies generated user-data; it does not
modify the source templates.

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

### Live proxy reconciliation

In the cloud scope, `apply` is the initial-install operation and refuses an existing owned path or
marker. `reconcile` is the Live/Instant operation for an initial install or a
re-apply. Both use the same inventory, schema-1 input, staged-script checksum,
root requirement and privileged Bash execution. After staging the script as
`root:root`, `0700`, the caller stages `proxy-contract.input` as `root:root`,
`0600`, with exactly these fields (values are parsed as data, not shell):

```text
schema=1
proxy_url=<site-proxy-url>
script_sha256=<sha256-of-the-staged-script>
```

The caller then runs:

```bash
/bin/bash -p /run/cloud-provision/proxy_contract.bash reconcile
```

Reconcile preflights the complete applicable set and renders every candidate
before installing any artifact. It restores missing dedicated artifacts and
the shared `environment` and `git` files, corrects the owned content and owner
and group, and sets dedicated-file modes to their inventory values. A safe
shared-file mode is preserved; a mode carrying special bits or group or world
write permission returns to its inventory baseline. Shared-file bytes outside
the owned block remain intact. A valid block in the wrong dnf or sshd scope is
relocated into `[main]` or the global scope. Dedicated files belong wholly to
the contract; hash-comment files must retain a valid enclosing marker pair,
and the XML Maven artifact has no markers.

Symlinks, multiple hard links, non-regular artifacts, unsafe parents,
malformed markers and competing unowned proxy keys fail before installation.
Every parent directory through the selected root must have the expected owner
and group and no group or world write permission. System ancestors are owned
by root; the vmadmin home and its SSH directory are owned by vmadmin.
Missing dnf or Rocky sshd shared files also fail: reconcile does not reconstruct
the site's package-manager or SSH baseline. Debian and Ubuntu still require
the global sshd include. Input, staged script and an existing runtime lock
must retain valid metadata and schema; artifact repair does not repair these
control files.

Only artifacts whose content or required metadata differ are replaced, using
a temporary file in the destination directory followed by rename. Installed
content, metadata and effective sshd settings are checked. Changed runs reload
sshd; unchanged runs do not reload it or replace correct artifacts. If an
installation, installed-state check, reload or lock update fails, already
replaced artifacts are restored from backups, including their original bytes,
owner, group, mode and modification time. A rollback failure is reported as an
error. Neither reconcile nor its rollback runs seal or cloud-init cleanup.

Reconcile requires `flock` and holds an exclusive, nonblocking lock on the
existing runtime directory until the process exits. A second reconcile call
fails without installing artifacts; no additional lock file is created.
Source snapshots are bound to the initial preflight, and candidates are
rendered from checked backups. A source change during candidate preparation
fails before installation.
Before installation, before each replacement, and before the runtime-lock
commit, reconcile compares source or installed snapshots using bytes, inode,
link count, owner, group, mode, size, mtime and ctime. An external change causes
failure. Rollback restores only files that still match this run's installed
snapshot; it preserves external changes and reports an incomplete rollback.
The caller must exclude unrelated configuration writers while reconciliation
runs. Directory locking serializes reconcile calls; snapshot checks are not an
atomic compare-and-rename against arbitrary writers that ignore that lock.

HUP, INT and TERM request cancellation. The current file replacement finishes,
then replaced artifacts and any replaced runtime lock are rolled back before
temporary backups are removed. Rollback ignores further cancellation signals
so it can finish. The commit boundary precedes the success result; signals
after that boundary do not undo the completed operation. SIGKILL, host failure
and power loss cannot run rollback.

Diagnostic command output goes to stderr. On success stdout has one
value-free result line:

```text
proxy_contract schema=1 mode=reconcile os=rocky identities=8 changed=false
```

`changed=true` means at least one final artifact needed installation or repair;
`changed=false` means no final artifact changed. Recreating a missing transient
runtime lock alone does not count as a change. An existing lock preserves its
shared-file creation history, and newly created shared files are added to that
history. After a reboot removes the lock, its reconstruction records only files
created during the current run; it does not infer earlier creation history.
Failure returns nonzero and prints no successful change result. Callers use the
exit status and the exact `changed` field, rather than a profile marker, to
determine the outcome.

### General-server reconciliation

General-server reconciliation supports Rocky Linux 8.10. The same safe
`/etc/os-release` resolver is used, with exactly one `ID=rocky` and exactly one
`VERSION_ID=8.10` required. Unquoted, single-quoted and double-quoted values
are accepted. Other identities, versions, missing or duplicate fields, and
malformed values fail before artifact installation. Values are parsed as data.
The version requirement applies only to the general-server scope; cloud
schema-1 inputs and their existing OS-family rules remain unchanged.

Callers explicitly select this scope through a schema-2 input file, staged at
the same root-owned control paths and modes used by cloud callers:

```text
schema=2
scope=general-server
proxy_url=<site-proxy-url>
script_sha256=<sha256-of-the-staged-script>
```

The four fields are required exactly once; unknown fields and unsupported
schema/scope combinations fail. Schema 1 accepts its original three fields
without a scope field. General-server schema 2 supports `reconcile` only.
The command remains:

```bash
/bin/bash -p /run/cloud-provision/proxy_contract.bash reconcile
```

The general-server inventory contains exactly six root-owned artifacts:
`profile`, `environment`, `dnf`, `pip`, `git`, and `maven`, at the paths and
metadata defined in the cloud inventory table. It does not require a
`vmadmin` passwd entry, create an account or home directory, or read or modify
account credentials and user SSH environment files. SSH configuration and
service settings are outside this scope; success, rejection and rollback do
not resolve or execute `sshd`, `systemctl`, or `cloud-init` commands.

The shared-file preservation, dedicated-file rendering, ownership and mode
repair, safe-parent validation, checksum binding, directory lock, snapshot
checks, cancellation and rollback rules remain the same. Missing dedicated
files and shared environment/Git files are created. The site's existing
`/etc/dnf/dnf.conf` and its single `[main]` section remain required; the
contract does not reconstruct a missing package-manager baseline. Maven's
dedicated XML is produced here and consumed through `mvn -gs`.

The runtime lock is root-owned mode `0600` and records `schema=2`,
`scope=general-server`, `state=applied` and `created`. An existing lock must
match the selected schema and scope before any artifact is replaced. There
is no automatic conversion of an existing lock or removal of files outside
the selected scope. Reconstructing a missing runtime lock retains the same
change-state and creation-history rules as cloud reconciliation.

Success has exactly one value-free stdout line:

```text
proxy_contract schema=2 mode=reconcile scope=general-server os=rocky identities=6 changed=false
```

Callers must validate the schema and scope corresponding to their input as
well as the exit status and exact change field. The cloud schema-1 result
format remains unchanged. A profile marker never substitutes for inspecting
the complete selected inventory.

`tests/fixtures/proxy-general-server-artifacts.tsv` independently specifies
the six general-server tuples. Local tests execute the shipped CLI without a
VM account or SSH tools, compare its artifacts with the real cloud-produced
files, and cover restoration, unchanged application, malformed inputs,
version/scope rejection, file safety, and rollback after a real filesystem
installation failure. These local checks do not establish real-target Ansible
acceptance, which requires a separately authorized Rocky 8.10 target without
`vmadmin` and execution of the shipped role and producer.

The independent fixture under `tests/fixtures/` is not a production input. Its
eleven-field tuples must equal the production inventory. Public local tests run
the shipped producer and IOC bake caller with only outer command, SSH transport,
network, image, and filesystem boundaries replaced. The IOC harness covers
normal Debian 13 and Rocky 8 paths and exactly seventeen one-at-a-time
inventory omissions. Dedicated EtherCAT tests are deferred; production
EtherCAT behavior and generic image workflow tests remain unchanged.

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

### Identity command symlink resolution (D022)

`proxy_contract_resolve_guest_command` accepts a fixed identity command
(`cloud-init`, `visudo`, `sshd`, `systemctl`) whose exact guest path is a
symbolic link, by resolving it to its canonical target and validating that
target as an in-root regular executable. This admits alternatives-managed
commands such as resolute's sudo-rs `visudo`, whose `/usr/sbin/visudo` links
through `/etc/alternatives` to a regular executable. The relaxation follows
links only within the selected root: the rooted-path walk rejects a resolved
target that leaves the root, so there is no host fallback and every other
fail-closed property is unchanged. It covers only the four identity commands,
not any proxy artifact or the `/etc/os-release` rules. The shared rooted-path
walk is untouched, so artifact and os-release validation stay strict.
