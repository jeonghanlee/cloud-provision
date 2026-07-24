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
out. Note the fix is per BUILD VM and per bake — the de-proxy step
(Step 7/9 iocrunner, 5/7 ethercat) strips every layer again before
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
  same `make bake.<os>` resumes against it: `create_vm.bash` is
  idempotent, and the role guards skip completed work.
- A previously published golden is NEVER at risk: the flatten writes
  `<image>.tmp` and renames only on success.
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

## Bake provenance

Each bake stamps `/etc/iocrunner-bake.manifest` (or
`/etc/ethercat-bake.manifest`) inside the image — bake date, both
repositories' HEADs, EPICS versions, per-clone `rev-parse` lines from
the build roles, `pip3 freeze` — and copies it to a sidecar
`<image>.qcow2.manifest` next to the output. When two goldens behave
differently, diff the sidecars first.
