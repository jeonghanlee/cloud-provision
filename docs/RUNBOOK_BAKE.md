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
| Rocky 8 ioc-runner golden | `make bake.rocky8` | `iocrunner-rocky8.qcow2` | `rocky8-iocrunner` |
| Debian 13 ioc-runner golden | `make bake.debian13` | `iocrunner-debian13.qcow2` | `debian13-iocrunner` |
| Both ioc-runner goldens | `make bake` | both ioc-runner images | both `*-iocrunner` selectors |
| Debian 13 EtherCAT golden | `make bake.ethercat.debian13` | `ethercat-debian13.qcow2` | `debian13-ethercat` |

To accept a production ioc-runner golden image, run the Rocky 8 and Debian 13 ioc-runner bakes from the current GitHub `origin/master`, then boot fresh `rocky8-iocrunner.server` and `debian13-iocrunner.server` consumers and compare the manifests against the running systems.

## Where a bake writes

`make bake.<os>` publishes the golden pair into the archive and then refreshes
the working copy consumers back onto, so it ends where it always did.

```bash
ls -l ~/libvirt/archive/iocrunner-rocky8-*.qcow2
ls -l ~/libvirt/images/iocrunner-rocky8.qcow2
```

The bake prints which archive entries it keeps and which are surplus. It removes
nothing; check what a downstream pin still claims before deleting an entry.

To put a platform back on an earlier golden without baking:

```bash
make refresh.rocky8
bin/bake_iocrunner_image.bash -o rocky8 -R iocrunner-rocky8-20260729T060708Z.qcow2
```

The first form takes the newest entry, the second a named one. Provisioning
never refreshes on its own, so a consumer always gets the environment the last
refresh selected.

## Pinning the ioc-runner version

`-r <ref>` pins the `epics-ioc-runner` version baked into the image. This
repository passes it to Ansible as `ioc_runner_version` on the `site.yml` play
and does nothing else with it; the `requested=<ref>` field on the
`app_ioc_runner` manifest record is written by `ansible-provision`, and this
repository's validator only shape-checks it.

```bash
bin/bake_iocrunner_image.bash -o rocky8 -r 1.2.3
```

Without `-r` the bake takes whatever the inventory resolves to and the manifest
record is unchanged. A ref that does not exist fails during the Ansible run and
publishes nothing.

## Fresh consumer SSH host keys

Fresh consumer VMs reuse deterministic testbed IP addresses. After a VM is deleted and recreated from a new golden image, the SSH server host key changes while the client-side `known_hosts` entry may still contain the previous VM key. Remove the old key for the target IP before the first post-bake SSH connection.

For the default ioc-runner consumers:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R 192.168.122.150
ssh-keygen -f ~/.ssh/known_hosts -R 192.168.122.50
```

Then connect normally:

```bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.122.150
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.122.50
```

Do not disable host-key checking for final acceptance. The expected workflow is to remove the stale deterministic-IP entry, accept the new key for the freshly provisioned VM, and then read `/etc/iocrunner-bake.manifest` or run the provenance validator.

Use this SSH command contract for post-bake final acceptance. Run the command
on the remote VM and let the result print to the terminal. Do not wrap these
SSH checks in local output redirection.

Rocky 8 consumer:

```bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.122.150 "sudo stat -c '%U:%G %a %n' /etc/iocrunner-bake.manifest"
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.122.150 "sudo sha256sum /etc/iocrunner-bake.manifest"
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.122.150 "sudo sed -n '1,80p' /etc/iocrunner-bake.manifest"
scp bin/validate_iocrunner_bake.bash vmadmin@192.168.122.150:/tmp/validate_iocrunner_bake.bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.122.150 "sudo /bin/bash -p /tmp/validate_iocrunner_bake.bash"
```

Debian 13 consumer:

```bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.122.50 "sudo stat -c '%U:%G %a %n' /etc/iocrunner-bake.manifest"
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.122.50 "sudo sha256sum /etc/iocrunner-bake.manifest"
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.122.50 "sudo sed -n '1,80p' /etc/iocrunner-bake.manifest"
scp bin/validate_iocrunner_bake.bash vmadmin@192.168.122.50:/tmp/validate_iocrunner_bake.bash
ssh -o ControlMaster=no -o ControlPath=none vmadmin@192.168.122.50 "sudo /bin/bash -p /tmp/validate_iocrunner_bake.bash"
```

Compare the remote manifest hash against the sidecar hash on the control host:

```bash
sha256sum /home/jeonglee/libvirt/images/iocrunner-rocky8.qcow2.manifest
sha256sum /home/jeonglee/libvirt/images/iocrunner-debian13.qcow2.manifest
```

## Baking behind a site proxy

The build VM has no route to public mirrors on a proxied site. The
proxy VALUES are site-confidential: use them from your site notes,
never commit them anywhere in these repositories (`*.local` overlays
and this VM-side procedure are their only homes). `<site-proxy>`
below stands for `http://<your-proxy-host>:<port>/`.

Symptoms without this procedure, in the order you will meet them:
`dnf`/`apt` metadata stalls at 0 B/s (Step 4), then `pip` retries with
`NewConnectionError`, then in-VM `wget`/`git` of build sources times
out. Note the fix is per BUILD VM and per bake: the de-proxy step
(Step 7/10 ioc-runner, 5/7 ethercat) strips every layer again before
flatten, so goldens never carry the values.

Inject all layers into the booted build VM (as vmadmin):

1. Package manager:
   - Rocky: append `proxy=<site-proxy>` to `/etc/dnf/dnf.conf`.
   - Debian: write `/etc/apt/apt.conf.d/95proxy` with
     `Acquire::http::Proxy "<site-proxy>";` and the `https` twin.
2. Shell environment: append `http_proxy`, `https_proxy`, upper-case
   twins, and `no_proxy=localhost,127.0.0.1,192.168.0.0/16` to
   `/etc/environment`.
3. Root context (ansible runs become-root; Debian sudo env_resets):
   write `/etc/sudoers.d/95proxy` with
   `Defaults env_keep += "http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY"`
   (mode 0440, `visudo -cf` it). Rocky's default sudoers already
   keeps proxy variables.
4. Non-interactive ssh sessions (ansible raw): set
   `PermitUserEnvironment yes` in `/etc/ssh/sshd_config.d/99proxy.conf`,
   write the same variables to `~vmadmin/.ssh/environment`, restart
   sshd.
5. Tool-specific (Debian needed both in practice): `/etc/pip.conf`
   `[global] proxy = <site-proxy>`; `git config --system http.proxy
   <site-proxy>` (and https).

Verify each layer before re-running the bake: `dnf makecache` /
`apt-get update`; `sudo wget -q -O /dev/null <any-https-url>` (tests
layers 2+3); a plain `ssh vmadmin@<vm> 'env | grep -i proxy'` (tests
layer 4).

The control host itself also needs its own proxy environment for the
base-image download and any galaxy-free ansible fetches — that is host
policy, out of scope here.

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
errors, and no failed systemd units, continue waiting until the bake script's
own retry limit is reached. Treat it as a failure only when cloud-init reports
an error, SSH becomes unavailable, the VM has failed systemd units relevant to
boot or networking, or the bake script exits non-zero.

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

- The build VM SURVIVES, running and half-provisioned. Re-running the
  same `make bake.<os>` now fails early because ioc-runner bakes require
  fresh build inputs. Inspect the VM, then run the clean-restart command
  when a clean retry is intended.
- A bake that fails before its last step prints that command itself, naming
  the VM it left. Do not expect it after a failure in the final cleanup
  step: the handler that prints it is uninstalled once the working copy has
  been refreshed. The command is written out below in either case.
- A previously published golden is NEVER at risk: validation runs before
  sidecar extraction and flattening, and the image plus manifest are
  published from non-empty `.tmp` siblings only after validation and
  conversion succeed.
- `-k` keeps the build VM after a successful bake for debugging.
- To restart truly clean:
  `bin/create_vm.bash -o <os> -n server -d <IMAGE_DIR> -p testbed -c`
  then re-run the bake (re-downloads nothing; base images are cached).
- The nfs_sim role is order-sensitive on a partially-applied VM; when
  a failure happened inside `04_nfs_sim`, prefer the clean restart
  over a resume.

## Site overrides honored by the bake scripts

- `BAKE_INVENTORY` — ansible inventory path passed to every playbook
  call (default `inventory/testbed.ini`; relative to ansible-provision).
- `VM_PREFIX` — build-VM name prefix (default `testbed`), now a single
  source shared with the make targets when exported.
- `REQUIRED_GROUP` — host group required by `create_vm.bash` before
  provisioning or cleanup (default `libvirt`).
- `IMAGE_DIR`, `ANSIBLE_PROVISION_DIR` — as before.

## ioc-runner bake contract

ioc-runner bakes are fresh-input only. The build domain
`testbed-<os>-server` and its source disk must not exist before the bake.
If either exists, `bin/bake_iocrunner_image.bash` stops through
`create_vm.bash -F` and prints the cleanup command instead of removing
anything automatically.

Before mutating output paths, the bake scans defined libvirt domains and
qcow2 files in the selected `IMAGE_DIR`. If any disk resolves through the
target golden image as a backing file, the bake stops before publication.
This protects existing consumers from a golden-image replacement while
they still depend on the old image.

The ioc-runner bake publishes only this pair:

- `${IMAGE_DIR}/iocrunner-rocky8.qcow2` with `${IMAGE_DIR}/iocrunner-rocky8.qcow2.manifest`
- `${IMAGE_DIR}/iocrunner-debian13.qcow2` with `${IMAGE_DIR}/iocrunner-debian13.qcow2.manifest`

The image and sidecar are first created as `.tmp` siblings. Empty or failed
outputs are removed by the script trap; prior published files remain in
place.

## Temporary preliminary bake path

Preliminary review bakes use a dedicated temporary image directory under
the production image parent:

```
PRELIM_IMAGE_DIR=/home/jeonglee/libvirt/images/m7-preliminary.XXXXXX
```

Create it with mode 0755 and add only these two symlinks:

- `Rocky-8-GenericCloud-Base.latest.x86_64.qcow2`
- `debian-13-genericcloud-amd64-daily.qcow2`

Both symlinks point to the existing production base images in
`/home/jeonglee/libvirt/images`. Preliminary outputs, source disks, seed
files, image `.tmp` files, and manifest `.tmp` files remain inside
`PRELIM_IMAGE_DIR`. Production goldens and ioc-runner consumers are out of
scope for preliminary cleanup.

Operator-directed cleanup is limited to:

- `testbed-rocky8-server` and `testbed-debian13-server`;
- their source disks and seed files inside `PRELIM_IMAGE_DIR`;
- `iocrunner-rocky8.qcow2`, `iocrunner-debian13.qcow2`, their manifests, and their `.tmp` siblings inside `PRELIM_IMAGE_DIR`;
- the two base-image symlinks inside `PRELIM_IMAGE_DIR`;
- `rmdir "${PRELIM_IMAGE_DIR}"` after the directory is empty.

If any unexpected file remains in `PRELIM_IMAGE_DIR`, stop and inspect it
instead of widening the cleanup command.

## ioc-runner bake provenance

Each ioc-runner bake stamps `/etc/iocrunner-bake.manifest` inside the
image and publishes the image together with its `.manifest` sidecar into
the archive. The sidecar next to the working copy consumers back onto is
the copy the refresh step makes. The manifest records:

- bake date, OS selector, both repository identities, and EPICS selectors;
- actual base-image filename and SHA-256 digest from the source disk backing file;
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
| `base_image` | Source disk backing file | Filename and SHA-256 match the observed backing image |
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

These checks replace only the host boundary commands. The public bake
script and the shipped validator still run through their normal entry
points.
