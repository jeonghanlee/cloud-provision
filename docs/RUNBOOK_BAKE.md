# Bake Runbook

Operational procedures for the golden-image bakes
(`bin/bake_iocrunner_image.bash`, `bin/bake_ethercat_image.bash`).
Architecture lives in `docs/ARCHITECTURE.md` section 12; this page
covers the two situations the scripts cannot handle alone.

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
(Step 7/10 iocrunner, 5/7 ethercat) strips every layer again before
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

## Failed bake mid-way

`set -e` aborts the script; know what state remains:

- The build VM SURVIVES, running and half-provisioned. Re-running the
  same `make bake.<os>` now fails early because IOC runner bakes require
  fresh build inputs. Inspect the VM, then run the printed cleanup command
  when a clean retry is intended.
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

## IOC runner bake contract

IOC runner bakes are fresh-input only. The build domain
`testbed-<os>-server` and its source disk must not exist before the bake.
If either exists, `bin/bake_iocrunner_image.bash` stops through
`create_vm.bash -F` and prints the cleanup command instead of removing
anything automatically.

Before mutating output paths, the bake scans defined libvirt domains and
qcow2 files in the selected `IMAGE_DIR`. If any disk resolves through the
target golden image as a backing file, the bake stops before publication.
This protects existing consumers from a golden-image replacement while
they still depend on the old image.

The IOC runner bake publishes only this pair:

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
`PRELIM_IMAGE_DIR`. Production goldens and IOC runner consumers are out of
scope for preliminary cleanup.

Operator-directed cleanup is limited to:

- `testbed-rocky8-server` and `testbed-debian13-server`;
- their source disks and seed files inside `PRELIM_IMAGE_DIR`;
- `iocrunner-rocky8.qcow2`, `iocrunner-debian13.qcow2`, their manifests, and their `.tmp` siblings inside `PRELIM_IMAGE_DIR`;
- the two base-image symlinks inside `PRELIM_IMAGE_DIR`;
- `rmdir "${PRELIM_IMAGE_DIR}"` after the directory is empty.

If any unexpected file remains in `PRELIM_IMAGE_DIR`, stop and inspect it
instead of widening the cleanup command.

## IOC runner bake provenance

Each IOC runner bake stamps `/etc/iocrunner-bake.manifest` inside the
image and copies it to a sidecar `<image>.qcow2.manifest` next to the
output. The manifest records:

- bake date, OS selector, both repository identities, and EPICS selectors;
- actual base-image filename and SHA-256 digest from the source disk backing file;
- one record for each fixed application: `app_con`, `app_procserv`, `app_conserver`, `app_epics`, and `app_ioc_runner`;
- one or more `pip3` lines from a successful non-empty `pip3 freeze`.

Application records use:

```
app_name schema=1 repo=<url> commit=<40-hex> state=<state> tag=<tag> recorded_at=<UTC>
```

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
