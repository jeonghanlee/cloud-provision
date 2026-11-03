# ADR: Generic Kernel On Debian 13 Guests

Date: 2026-11-02
Status: Accepted; verified on plain Debian 13, Ubuntu 24, and Ubuntu 26 guests; the IOC runner bake and two Debian 13 variants pending verification

## Context

The Debian 13 genericcloud base image boots the `-cloud-amd64` kernel. On a
Debian 13 guest that kernel has no `CONFIG_HWMON` line in `/boot/config-*` and
exposes no `/sys/class/hwmon` (verified). The Debian 13 host's generic kernel
`6.12.111+deb13-amd64` has `CONFIG_HWMON=y` (verified). Software that reads
hwmon (the EPICS linStat module) reports errors on every run. Reported by the
requesting session and not verified here: the cloud kernel holds no hwmon
modules, and the Rocky 8 kernel provides `CONFIG_HWMON=y`.

Adding the generic kernel package to a genericcloud guest does not help.
Observed on a Debian 13 guest created from the genericcloud image with
`linux-image-amd64` added to its template (2026-11-02): both `6.12.115+deb13.1`
kernels were installed, the default grub entry booted `-cloud-amd64`, and after
a reboot `uname -r` still reported the cloud kernel and `/sys/class/hwmon` was
absent. grub orders kernels with `sort -V`, and at an equal version
`-cloud-amd64` sorts above `-amd64`.

Ubuntu needs no change. Observed on guests created from the unchanged Ubuntu
images, with a template that still installed `linux-generic` (2026-11-02, before
any reboot, so the running kernel is the one the image ships): Ubuntu 24.04 runs `6.8.0-134-generic`
and Ubuntu 26.04 runs `7.0.0-27-generic`; both have `CONFIG_HWMON=y` and
`/sys/class/hwmon`. Each image already installs `linux-image-virtual`, which
brings the generic kernel.

## Decision

The Debian 13 OS types that boot a general-purpose guest use the generic base
image `debian-13-generic-amd64-daily.qcow2` instead of the genericcloud image,
as Debian 12 already does. The types are `debian13`, `debian13-epics-dev`, and
`debian13-archiver-dev`. No template installs a kernel package. Ubuntu and Rocky
types are unchanged. Provisioning does not reboot a guest.

A new Debian type uses the generic image unless a pinned image is required for
a stated reason, as `debian13-rtbase` does for published kernel headers.
`tests/check-cloud-init-status.bash` pins the image name of each Debian 13 type
listed above.

## Scope

The IOC runner bake (`bin/bake_iocrunner_image.bash`) creates its build VM as
the plain `debian13` type, so the Debian 13 IOC runner golden images are built
from the generic base image from now on. `debian13-rtbase` and the EtherCAT bake
keep their pinned genericcloud release image and boot the cloud kernel.

Observed on a Debian 13 guest created from the generic image (2026-11-02,
before any reboot): the running kernel is `6.12.113+deb13-amd64`,
`/sys/class/hwmon` exists, `CONFIG_HWMON=y`, no `-cloud-` kernel package is
installed, and the default grub entry is the generic `6.12.115+deb13.1-amd64`.

The image does not depend on proxy injection, so proxy-path guests get the same
kernel. The ansible-provision `common` role needs no change for this decision.

## Pending verification

Plain check, for any new Debian or Ubuntu guest after its first reboot: run
`uname -r` and `test -d /sys/class/hwmon`. The check passes when the kernel name
does not contain `-cloud-` and the directory exists.

Run so far, without a reboot: a `debian13` guest created from the generic image,
an Ubuntu 24 guest, and an Ubuntu 26 guest passed. It has not been run on Debian
12, `debian13-epics-dev`, or `debian13-archiver-dev` guests, nor after a reboot.

Not verified:

- A real IOC runner bake on the generic base image.
  `tests/check-iocrunner-bake-provenance.bash` uses a fake base image and does
  not exercise the image selection.
- Whether the generic image changes anything the IOC runner relies on beyond the
  kernel.
