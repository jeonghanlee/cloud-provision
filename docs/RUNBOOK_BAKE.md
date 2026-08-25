# Bake Runbook

Operational procedures for the golden-image bakes
(`bin/bake_iocrunner_image.bash`, `bin/bake_ethercat_image.bash`).
Architecture lives in `docs/ARCHITECTURE.md` section 12; this page
covers bake entry points, failure handling, proxy handling, and acceptance
checks.

## Runbook rules

This is a command-based runbook. Every procedure must stay executable from
this page alone, in any situation and at any point in the project's life.

Do not write into this file:

- milestone, issue, plan, or review identifiers;
- current project state, such as what is next, pending, or recently landed;
- any reference that resolves only against a tracker or a session record.

Such names are renumbered and retired on their own schedule, which leaves a
command step pointing at something the reader at the terminal cannot resolve.
State the operating condition and the command instead. Tracking documents may
point here; this page does not point back.

## Why every ssh here carries two options

Every `ssh` command on this page begins with
`-o ControlMaster=no -o ControlPath=none`. Keep them when you copy a command.

OpenSSH connection multiplexing keys its shared socket on the connection target,
and the target here is an address. These VMs are destroyed and recreated at the
same fixed addresses, so a socket left by an earlier VM outlives it and the next
connection to that address finds a master whose connection is already dead. The
fallback from that state leaves the caller's standard input and standard error
non-blocking, which nothing clears; a later `ansible-playbook` in the same shell
then refuses to run at all. The two options keep each command off that path,
without touching the multiplexing an operator wants everywhere else.

## Which bake entry point to use

Use the selector by the image you need to produce, not by the VM you will boot later:

| Need | Command | Output image | Later runtime selector |
|---|---|---|---|
| Rocky 8 ioc-runner golden | `make bake.rocky8` | `iocrunner-rocky8-<run-id>.qcow2` | `rocky8-iocrunner` |
| Debian 13 ioc-runner golden | `make bake.debian13` | `iocrunner-debian13-<run-id>.qcow2` | `debian13-iocrunner` |
| Both ioc-runner goldens | `make bake` | both ioc-runner images | both `*-iocrunner` selectors |
| ioc-runner-nfs flavor golden | `make bake.iocrunner-nfs.<os>` (or `make bake.iocrunner-nfs` for both) | `iocrunner-nfs-<os>-<run-id>.qcow2` | `<os>-iocrunner-nfs` |
| Debian 13 EtherCAT golden | `make bake.ethercat.debian13` | `ethercat-debian13-<run-id>.qcow2` | `debian13-ethercat` |

To accept a production ioc-runner golden image, run the Rocky 8 and Debian 13 ioc-runner bakes from the current GitHub `origin/master`, then boot fresh `rocky8-iocrunner.main` and `debian13-iocrunner.main` consumers and compare the manifests against the running systems.

## Where a bake writes

`make bake.<os>` creates a new independent golden pair in the image directory.
The run ID is a UTC timestamp followed by a 12-character hash.

```bash
latest_iocrunner="$(ls -1t ~/libvirt/images/iocrunner-rocky8-*.qcow2 | head -n 1)"
ls -l "${latest_iocrunner}" "${latest_iocrunner}.creation-record" "${latest_iocrunner}.manifest"
```

Provisioning selects the newest valid image and creation-record pair. A missing
or mismatched record is ignored, so an incomplete output cannot become a VM
input.

## Pinning the ioc-runner version

`-r <ref>` pins the `epics-ioc-runner` version baked into the image. This
repository passes it to Ansible as `ioc_runner_version` on the species
assembly play and does nothing else with it; the `requested=<ref>` field on the
`app_ioc_runner` manifest record is written by `ansible-provision`, and this
repository's validator only shape-checks it.

```bash
bin/bake_iocrunner_image.bash -o rocky8 -r 1.2.3
```

Without `-r` the bake takes whatever the inventory resolves to and the manifest
record is unchanged. A ref that does not exist fails during the Ansible run and
publishes nothing.

## Fresh consumer SSH host keys

Fresh consumer VMs reuse deterministic lab IP addresses. After a VM is deleted and recreated from a new golden image, the SSH server host key changes while the client-side `known_hosts` entry may still contain the previous VM key. Remove the old key for the target IP before the first post-bake SSH connection.

For the default ioc-runner consumers:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R 192.168.123.150
ssh-keygen -f ~/.ssh/known_hosts -R 192.168.123.50
```

Then connect normally:

```bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.123.150
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.123.50
```

Do not disable host-key checking for final acceptance. The expected workflow is to remove the stale deterministic-IP entry, accept the new key for the freshly provisioned VM, and then read `/etc/iocrunner-bake.manifest` or run the provenance validator.

Use this SSH command contract for post-bake final acceptance. Run the command
on the remote VM and let the result print to the terminal. Do not wrap these
SSH checks in local output redirection.

Rocky 8 consumer:

```bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.123.150 "sudo stat -c '%U:%G %a %n' /etc/iocrunner-bake.manifest"
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.123.150 "sudo sha256sum /etc/iocrunner-bake.manifest"
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.123.150 "sudo sed -n '1,80p' /etc/iocrunner-bake.manifest"
scp bin/validate_iocrunner_bake.bash vmadmin@192.168.123.150:/tmp/validate_iocrunner_bake.bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.123.150 "sudo /bin/bash -p /tmp/validate_iocrunner_bake.bash"
```

Debian 13 consumer:

```bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.123.50 "sudo stat -c '%U:%G %a %n' /etc/iocrunner-bake.manifest"
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.123.50 "sudo sha256sum /etc/iocrunner-bake.manifest"
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.123.50 "sudo sed -n '1,80p' /etc/iocrunner-bake.manifest"
scp bin/validate_iocrunner_bake.bash vmadmin@192.168.123.50:/tmp/validate_iocrunner_bake.bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.123.50 "sudo /bin/bash -p /tmp/validate_iocrunner_bake.bash"
```

Compare the remote manifest hash against the sidecar hash on the control host:

```bash
latest_iocrunner="$(ls -1t /home/jeonglee/libvirt/images/iocrunner-rocky8-*.qcow2 | head -n 1)"
latest_debian_iocrunner="$(ls -1t /home/jeonglee/libvirt/images/iocrunner-debian13-*.qcow2 | head -n 1)"
sha256sum "${latest_iocrunner}.manifest" "${latest_debian_iocrunner}.manifest"
```

## Baking behind a site proxy

Keep the site proxy value in the host's protected site configuration. The
default discovery directory is `/etc/profile.d`; override it for one run with
`PROXY_SOURCE_DIR`. Exactly one regular `*proxy.sh` file may be present, and it
must contain exactly one quoted `PROXY_URL` assignment. The provisioner parses
that scalar as data and never executes or copies the host script.

The generated seed stages only the byte-identical shipped contract and its
validated data input under `/run/cloud-provision`. It creates exactly one
top-level `write_files` and one top-level `runcmd`, with privileged contract
apply as the first command. Existing locale commands remain in their original
order after apply. The source `templates/user-data.*` files are not modified.

Package install ordering (D018): under proxy injection the `packages:` directive
is stripped, so packages install after the proxy apply through Ansible, not
through the cloud-init package module. The cloud-init package module runs in the
config stage, before the runcmd proxy apply, so it has no proxy yet and cannot
fetch. Without proxy injection the cloud-init baseline (the hand-off subset of
P_common in `docs/IMAGE_WORKFLOW.md`) installs them at first boot.

Base-image locale dependency (D018): stripping `packages:` removes the `locales`
entry with it, while the runcmd locale commands are kept and still run at first
boot. On a proxy-injected build those commands rely on the base image already
shipping locale support (the `locales` package on the Debian family, glibc
langpacks on Rocky). A base image lacking it fails locale generation; the
debian-family templates carry a first-boot self-check that makes the absence
surface instead of passing silently. Keep that self-check as the last `runcmd`
entry: cloud-init runs `runcmd` as one `set -e`-less script whose exit status is
its last line, so a command placed after it would mask the self-check failure.

Apply writes the exact family set:

- Debian and Ubuntu: profile, environment, APT, sudo, sshd drop-in,
  `vmadmin` SSH environment, pip, and system Git;
- Rocky: profile, environment, DNF, global sshd configuration, `vmadmin` SSH
  environment, pip, and system Git.

Dedicated artifacts use exact content and metadata. Shared targets keep safe
existing metadata and every byte outside the marked block. A non-empty shared
target without a final newline fails before mutation. Debian and Ubuntu require
the global sshd include before using the drop-in. Rocky places
`PermitUserEnvironment yes` before the first active `Match` and rejects a
competing active setting. Apply validates sudo, installed metadata, and the
effective sshd configuration before it reports success.

Both bake callers validate and extract their manifest sidecar, then stream the
same `bin/proxy_contract.bash` bytes through the exact privileged
`/bin/bash -p -s -- seal` stdin form. Seal is the last guest mutation. It
preflights the complete family set, removes final artifacts in reverse order,
reloads sshd, removes `/run/cloud-provision` contract state, verifies value-free
absence, runs supported `cloud-init clean`, and verifies the selected
cloud-init state and logs are absent. Publication begins only after the exact
sealed VM is shut off and its exact source disk is confirmed.

Local IOC checks cover the public Debian 13 and Rocky 8 paths. They do not
constitute production acceptance; accept each family only after one real bake
and one fresh consumer pass on supported Libvirt/KVM. The IOC-only aggregate
does not verify EtherCAT.

The control host still needs its own network policy for base-image downloads
and host-side fetches. That policy is outside the guest artifact contract.

## Auditing published IOC runner images

`bin/audit_iocrunner_images.bash` audits every regular, non-symlink `iocrunner-*.qcow2` file in one image directory. Each image must follow the `iocrunner-debian13-<run-id>.qcow2`, `iocrunner-rocky8-<run-id>.qcow2`, `iocrunner-nfs-debian13-<run-id>.qcow2`, or `iocrunner-nfs-rocky8-<run-id>.qcow2` naming contract and have a non-empty regular `<image>.manifest` sidecar.

The entry point requires root privileges. It checks qcow2 metadata and integrity, starts one read-only guestfish appliance per image, finds exactly one guest root, and tests the value-free proxy artifact paths, markers, and key names pinned to the shipped `bin/proxy_contract.bash`. It does not create a host mount, attach an NBD device, execute a command in the guest, print a proxy value or guest file content, or modify an image. EtherCAT images and remediation are outside this command.

On the verified Debian 13 control host, install the runtime packages with:

```bash
sudo apt-get install bash coreutils findutils guestfish jq mawk qemu-utils sed
```

The key package mapping is `guestfish` from `guestfish`, `qemu-img` from `qemu-utils`, and `jq` from `jq`. The remaining packages provide the Bash interpreter and the standard `awk`, `find`, `realpath`, `sed`, `sha256sum`, `sleep`, and `sort` commands. `shellcheck` is required only for repository validation, not for an audit run.

From the repository root, audit the default `/data/libvirt/images` directory:

```bash
sudo /bin/bash -p bin/audit_iocrunner_images.bash
```

Select another absolute image directory with `-d`:

```bash
sudo /bin/bash -p bin/audit_iocrunner_images.bash -d /absolute/image/directory
```

Show the command interface without root privileges:

```bash
bin/audit_iocrunner_images.bash -h
```

Success prints one aggregate line and no per-image identifier:

```
audit: completed images=<count> debian=<count> rocky=<count> passed=<count> failed=0 residue=clean
```

Failure prints `audit: failed stage=<stage>` and exits nonzero. A `proxy-contract-drift` failure means `bin/proxy_contract.bash` changed after the audit inventory and digest were reviewed; update the value-free inventory and pinned digest together before running the audit against the changed contract.

## VM wait policy

The provisioner and ioc-runner bake use the same validated wait settings. Each
setting is a positive integer environment value, and an override applies only
to the command that receives it.

| Path | Default settings | Effective wait structure |
| --- | --- | --- |
| DHCP IP discovery | `VM_WAIT_IP_ATTEMPTS=6`, `VM_WAIT_IP_INTERVAL_SECONDS=10` | Six polls with five 10-second sleeps |
| SSH readiness | `VM_WAIT_SSH_ATTEMPTS=6`, `VM_WAIT_SSH_INTERVAL_SECONDS=10`, `VM_WAIT_SSH_CONNECT_TIMEOUT_SECONDS=5` | Six probes with five 10-second sleeps and up to 5 seconds per connection attempt |
| `cloud-init` completion | `VM_WAIT_CLOUD_INIT_ATTEMPTS=61`, `VM_WAIT_CLOUD_INIT_INTERVAL_SECONDS=30` | Sixty-one polls with 30 minutes between the first and final polls |
| Domain shutdown | `VM_WAIT_SHUTDOWN_ATTEMPTS=12`, `VM_WAIT_SHUTDOWN_INTERVAL_SECONDS=5` | Twelve polls after the ACPI request, up to 60 seconds |

For a known slow package-installing boot, extend only that execution. This
example allows 40 minutes between the first and final `cloud-init` polls:

```bash
VM_WAIT_CLOUD_INIT_ATTEMPTS=81 make bake.rocky8
```

The ioc-runner bake calls `create_vm.bash -S` at publication step 8, so it uses
the same 60-second shutdown default as `make <os>.<instance>.stop`. Zero, negative,
and non-integer settings are rejected before a VM action begins.

## Slow boot and package-manager diagnosis

Long waits are not automatically bake failures. Use the following read-only
checks to decide whether the VM is still making progress or has stopped.

During Step 1, repeated `cloud-init: retrying` lines mean the VM is reachable
over SSH but cloud-init has not reported completion. Check the live cloud-init
state from the control host:

```bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@<vm-ip> cloud-init status --long
ssh -o ControlMaster=no -o ControlPath=none vmadmin@<vm-ip> systemctl --no-pager --failed
```

If cloud-init reports `status: running`, `Running in stage: modules-final`, no
errors, and no failed systemd units, continue waiting until the shared
`cloud-init` limit is reached. Treat it as a failure only when cloud-init
reports an error, SSH becomes unavailable, the VM has failed systemd units
relevant to boot or networking, or the bake script exits non-zero.

During Rocky 8 package installation, Ansible can be quiet while `dnf` downloads
or runs the RPM transaction. Check the package manager process and logs:

```bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@<vm-ip> pgrep -af dnf
ssh -o ControlMaster=no -o ControlPath=none vmadmin@<vm-ip> sudo tail -n 80 /var/log/dnf.log
ssh -o ControlMaster=no -o ControlPath=none vmadmin@<vm-ip> sudo tail -n 80 /var/log/dnf.librepo.log
ssh -o ControlMaster=no -o ControlPath=none vmadmin@<vm-ip> sudo tail -n 80 /var/log/dnf.rpm.log
```

Mirror timeouts in `dnf makecache --timer` do not by themselves prove the
Ansible task failed. If the `dnf install` process is still present, downloads
are progressing, or `dnf.log` has reached `Running transaction`, continue
watching the bake output. A final Ansible failure or a vanished package-manager
process with no task progress requires normal failure handling.

During Debian 13 base package installation, Ansible can be quiet while `apt`
downloads and `dpkg` unpacks a large package set. Check the live processes and
available disk space:

```bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@<vm-ip> pgrep -af apt
ssh -o ControlMaster=no -o ControlPath=none vmadmin@<vm-ip> pgrep -af dpkg
ssh -o ControlMaster=no -o ControlPath=none vmadmin@<vm-ip> df -h / /var
```

If `apt` or `dpkg` is active and disk space is sufficient, continue waiting.
If both package-manager processes are gone and the Ansible task does not resume,
inspect the apt logs before retrying:

```bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@<vm-ip> sudo tail -n 80 /var/log/apt/term.log
ssh -o ControlMaster=no -o ControlPath=none vmadmin@<vm-ip> sudo tail -n 80 /var/log/apt/history.log
```

## Failed bake mid-way

`set -e` aborts the script; know what state remains:

- The build VM survives, running and half-provisioned. Its name includes the
  current run ID, so a later bake creates a different build VM. Inspect the
  failed VM, then run the printed cleanup command when a clean retry is intended.
- A bake that fails after the build VM exists prints a cleanup command containing
  the same run ID. The unique image name is never reused, and a failed `.tmp`
  output is removed by the script trap.
- An earlier image pair is never overwritten. Each bake creates a new image,
  manifest sidecar, and creation record only after validation succeeds.
- `-k` keeps the build VM after a successful bake for debugging.
- To restart truly clean, run the cleanup command the failed bake printed
  (`IMAGE_WORKFLOW_RUN_ID=<run-id> bin/create_vm.bash -o <os> -n build -d
  <IMAGE_DIR> -p lab -c` — the run ID selects the exact build VM), then
  re-run the bake. Cleanup removes the build VM disk and its creation
  record together; base images remain cached.
- The nfs_sim role is order-sensitive on a partially-applied VM; when
  a failure happened inside the `nfs_sim` operator of the
  `iocrunner-nfs` assembly, prefer the clean restart over a resume.

## Site overrides honored by the bake scripts

- `BAKE_INVENTORY` — host-free Ansible group inventory passed to every
  playbook call (default `inventory/lab.ini`; relative to
  ansible-provision). Each bake also calls
  `bin/generate_ansible_inventory.bash` and passes a temporary host inventory.
  The ioc-runner build host enters its vacuum group and `iocrunner` (or
  `iocrunner_nfs` for the `-f iocrunner-nfs` flavor); the EtherCAT build
  host enters its vacuum group and `rtbase`. Each temporary file is removed
  when its bake exits.
- `VM_PREFIX` — build-VM name prefix (default `lab`), now a single
  source shared with the make targets when exported.
- `REQUIRED_GROUP` — host group required by `create_vm.bash` before
  provisioning or cleanup (default `libvirt`).
- `IMAGE_DIR`, `ANSIBLE_PROVISION_DIR` — as before.

## Image pair contract

Both bake entry points use `bin/image_workflow.bash`. The shared path creates
an independent qcow2 copy, writes a `.creation-record`, rejects a non-empty
backing file, and validates the image and record together. The bake also writes
its provenance manifest beside the image.

The image name is `<kind>-<platform>-<run-id>.qcow2`, where `<run-id>` is a UTC
timestamp followed by a 12-character hash. The provisioner selects the newest
valid pair for `rocky8-iocrunner`, `debian13-iocrunner`,
`rocky8-iocrunner-nfs`, `debian13-iocrunner-nfs`, and
`debian13-ethercat`; it does not select by a static filename.

To inspect a pair after a bake:

```bash
latest_iocrunner="$(ls -1t ~/libvirt/images/iocrunner-rocky8-*.qcow2 | head -n 1)"
cat "${latest_iocrunner}.creation-record"
qemu-img info --output=json --force-share "${latest_iocrunner}"
```

The image is ready for acceptance when `virtual-size` is `21474836480`
(20 GiB), no `backing-filename` is present, and the creation record names the
same image and run ID.

## ioc-runner bake provenance

Each ioc-runner bake stamps `/etc/iocrunner-bake.manifest` inside the build VM
and publishes the image together with its `.manifest` sidecar in `${IMAGE_DIR}`.
The `.creation-record` beside the image records the image identity. The
manifest records:

- bake date, OS selector, both repository identities, and EPICS selectors;
- actual base-image filename and SHA-256 digest from the source image pair;
- one record for each fixed application: `app_con`, `app_procserv`, `app_conserver`, `app_epics`, and `app_ioc_runner`;
- one or more `pip3` lines from a successful non-empty `pip3 freeze`.

Application records use:

```
app_name schema=1 repo=<url> commit=<40-hex> state=<state> tag=<tag> recorded_at=<UTC>
```

`app_ioc_runner` may carry one optional trailing field, and no other record
may carry any:

```
app_ioc_runner schema=1 repo=<url> commit=<40-hex> state=<state> tag=<tag> recorded_at=<UTC> requested=<ref>
```

`requested` is written only when the bake was given a version selector, so an
unpinned bake produces a record byte-identical to the six-field form. It
records what the caller asked for beside the commit that was resolved, and the
two may legitimately differ: a ref is intent, while the tag is whatever happens
to point at the resolved commit. The validator therefore checks its shape —
present, non-empty, no whitespace — and does not tie it to `tag` or `state`.

`state` is `clean-tagged`, `clean-untagged`, or `dirty`. Dirty repository
suffixes are acceptable for preliminary bakes only; final acceptance
requires exact clean 40-hex repository identities.

## Provenance comparison matrix

| Manifest record | Compared with | Result required |
|---|---|---|
| `base_image` | Source image named by the source-disk creation record | Filename and SHA-256 match the observed source image |
| `app_con` | Build-time checkout record | Exactly one valid source record |
| `app_procserv` | Build-time checkout record | Exactly one valid source record |
| `app_conserver` | Build-time checkout record | Exactly one valid source record |
| `app_epics` | Retained `/opt/epics` checkout | URL, commit, state, and tag match |
| `app_ioc_runner` | Retained checkout plus `ioc-runner -V` | URL, commit, state, tag, and installed short hash match |
| `pip3` | Successful `pip3 freeze` | One or more non-empty package lines |

## Offline bake checks

Run these checks after editing the bake scripts, validator, or bake tests:

```
make check-bake
```

The target expands to:

- `make check-bake-fresh-inputs`
- `make check-bake-provenance`
- `make check-proxy-lifecycle`

These checks replace only the host boundary commands. The public bake
scripts, producer, proxy contract, and validator still run through their normal
entry points. The aggregate covers the IOC image workflow only and does not run
a dedicated EtherCAT image workflow test, while production `bake.ethercat`
targets stay available. These local checks do not replace the supported
Libvirt/KVM producer-consumer gates or an authorized existing-artifact audit.
